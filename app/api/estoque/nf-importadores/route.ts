import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase/admin";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";
import { getAllowedEmpresas } from "@/lib/auth/empresa";

export const runtime = "nodejs";

function jerr(status: number, error: string) {
  return NextResponse.json({ error }, { status });
}

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const INVALID_IMPORTADORES = new Set([
  "",
  "system-backfill",
  "sistema",
  "system",
  "backfill",
]);

type NfIdRow = {
  id: number | null;
};

type AuditRow = {
  row_pk: string | null;
  actor_user_id: string | null;
  actor_email: string | null;
  created_at: string | null;
};

type UsuarioRow = {
  auth_user_id: string | null;
  nome: string | null;
  email: string | null;
  ativo: boolean | null;
  deleted_at: string | null;
};

type MovFallbackRow = {
  origem_nf_entrada_id: number | null;
  realizado_por: string | null;
  data_movimentacao: string | null;
};

function parseNfIds(raw: string): number[] {
  const parsed = raw
    .split(",")
    .map((part) => Number.parseInt(part.trim(), 10))
    .filter((n) => Number.isFinite(n) && n > 0);
  return Array.from(new Set(parsed)).slice(0, 600);
}

function formatUsuario(nomeRaw: string | null | undefined, emailRaw: string | null | undefined): string {
  const nome = String(nomeRaw ?? "").trim();
  const email = String(emailRaw ?? "").trim();
  if (nome && email) return `${nome} (${email})`;
  if (nome) return nome;
  if (email) return email;
  return "";
}

export async function GET(req: NextRequest) {
  try {
    const authorization = req.headers.get("authorization");
    if (!authorization) return jerr(401, "Nao autenticado.");

    const supabase = supabaseFromAuthHeader(req);
    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData.user) return jerr(401, "Nao autenticado.");

    const tenantId = String(req.nextUrl.searchParams.get("tenantId") ?? "").trim();
    const empresaId = String(req.nextUrl.searchParams.get("empresaId") ?? "").trim();
    const nfIdsRaw = String(req.nextUrl.searchParams.get("nfIds") ?? "").trim();

    if (!tenantId) return jerr(400, "tenantId obrigatorio.");
    if (!empresaId) return jerr(400, "empresaId obrigatorio.");
    if (!UUID_REGEX.test(tenantId)) return jerr(400, "tenantId invalido.");
    if (!UUID_REGEX.test(empresaId)) return jerr(400, "empresaId invalido.");

    const requestedNfIds = parseNfIds(nfIdsRaw);
    if (!requestedNfIds.length) return NextResponse.json({ importadores: [] });

    const allowed = await getAllowedEmpresas(supabase, tenantId);
    if (!allowed.some((e) => e.id === empresaId)) return jerr(403, "Sem acesso a esta empresa.");

    const admin = supabaseAdmin();

    const { data: nfRows, error: nfErr } = await admin
      .from("nf_entrada")
      .select("id")
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .in("id", requestedNfIds)
      .returns<NfIdRow[]>();
    if (nfErr) return jerr(400, nfErr.message ?? "Erro ao validar NF-e.");

    const nfIds = Array.from(
      new Set(
        (nfRows ?? [])
          .map((r) => Number(r.id ?? 0))
          .filter((n) => Number.isFinite(n) && n > 0)
      )
    );
    if (!nfIds.length) return NextResponse.json({ importadores: [] });

    const rowPks = nfIds.map((id) => String(id));
    const { data: auditRows, error: auditErr } = await admin
      .from("audit_log")
      .select("row_pk,actor_user_id,actor_email,created_at")
      .eq("tenant_id", tenantId)
      .eq("table_name", "nf_entrada")
      .eq("action", "INSERT")
      .in("row_pk", rowPks)
      .order("created_at", { ascending: true })
      .returns<AuditRow[]>();
    if (auditErr) return jerr(400, auditErr.message ?? "Erro ao buscar importadores.");

    const auditByNfId = new Map<number, AuditRow>();
    const actorAuthUserIds = new Set<string>();
    for (const row of auditRows ?? []) {
      const nfId = Number.parseInt(String(row.row_pk ?? "").trim(), 10);
      if (!Number.isFinite(nfId) || nfId <= 0 || auditByNfId.has(nfId)) continue;
      auditByNfId.set(nfId, row);
      const actorAuthUserId = String(row.actor_user_id ?? "").trim();
      if (actorAuthUserId) actorAuthUserIds.add(actorAuthUserId);
    }

    const usuarioByAuthUserId = new Map<string, { nome: string; email: string }>();
    if (actorAuthUserIds.size > 0) {
      const { data: usuariosData, error: usuariosErr } = await admin
        .schema("a")
        .from("usuario")
        .select("auth_user_id,nome,email,ativo,deleted_at")
        .in("auth_user_id", Array.from(actorAuthUserIds))
        .returns<UsuarioRow[]>();
      if (usuariosErr) return jerr(400, usuariosErr.message ?? "Erro ao resolver usuarios.");

      for (const row of usuariosData ?? []) {
        const authUserId = String(row.auth_user_id ?? "").trim();
        if (!authUserId) continue;
        if (row.ativo === false || row.deleted_at) continue;
        usuarioByAuthUserId.set(authUserId, {
          nome: String(row.nome ?? "").trim(),
          email: String(row.email ?? "").trim(),
        });
      }
    }

    const realizadoPorByNfId = new Map<number, string>();
    const { data: movRows } = await admin
      .from("movimentacoes")
      .select("origem_nf_entrada_id,realizado_por,data_movimentacao")
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .in("origem_nf_entrada_id", nfIds)
      .order("data_movimentacao", { ascending: true })
      .returns<MovFallbackRow[]>();

    for (const row of movRows ?? []) {
      const nfId = Number(row.origem_nf_entrada_id ?? 0);
      if (!Number.isFinite(nfId) || nfId <= 0 || realizadoPorByNfId.has(nfId)) continue;
      const realizadoPor = String(row.realizado_por ?? "").trim();
      if (!realizadoPor) continue;
      if (INVALID_IMPORTADORES.has(realizadoPor.toLowerCase())) continue;
      realizadoPorByNfId.set(nfId, realizadoPor);
    }

    const importadores = nfIds
      .map((nfEntradaId) => {
        const audit = auditByNfId.get(nfEntradaId);
        let usuario = "";

        if (audit) {
          const actorAuthUserId = String(audit.actor_user_id ?? "").trim();
          const usuarioRow = actorAuthUserId ? usuarioByAuthUserId.get(actorAuthUserId) : null;
          const nome = String(usuarioRow?.nome ?? "").trim();
          const email = String(usuarioRow?.email ?? audit.actor_email ?? "").trim();
          usuario = formatUsuario(nome, email);
        }

        if (!usuario) {
          usuario = String(realizadoPorByNfId.get(nfEntradaId) ?? "").trim();
        }

        if (!usuario) return null;
        return { nf_entrada_id: nfEntradaId, usuario };
      })
      .filter((row): row is { nf_entrada_id: number; usuario: string } => Boolean(row?.usuario));

    return NextResponse.json({ importadores });
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : "Erro inesperado.";
    return jerr(500, message);
  }
}
