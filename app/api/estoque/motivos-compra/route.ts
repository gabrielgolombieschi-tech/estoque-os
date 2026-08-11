import { NextRequest, NextResponse } from "next/server";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";

function jerr(status: number, error: string) {
  return NextResponse.json({ error }, { status });
}

export const runtime = "nodejs";
const isDev = process.env.NODE_ENV !== "production";

type Origem = "XML_PRODUTO";
type AplicaEm = "PRODUTO" | "SERVICO" | "AMBOS";

type MotivoRow = {
  id: string;
  codigo: string | null;
  nome: string | null;
  requires_text: boolean | null;
  requires_os: boolean | null;
  aplica_em: AplicaEm | null;
  favorito?: boolean | null;
  ordem?: number | null;
  qtd_usos_180d?: number | string | null;
  ativo: boolean | null;
  deleted_at: string | null;
};

type FavoritoBody = {
  id?: string;
  favorito?: boolean;
};

export async function GET(req: NextRequest) {
  try {
    const authorization = req.headers.get("authorization");
    if (!authorization) return jerr(401, "Nao autenticado.");

    const supabase = supabaseFromAuthHeader(req);
    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData.user) return jerr(401, "Nao autenticado.");

    const origem = String(req.nextUrl.searchParams.get("origem") ?? "").trim().toUpperCase() as Origem | "";

    // Always resolve tenant from DB-side context (no tenantId in URL).
    let tenantId: string | null = null;
    try {
      const { data: t, error: tErr } = await supabase.rpc("current_tenant_id");
      if (tErr) return jerr(400, tErr.message ?? "Falha ao resolver tenant.");
      tenantId = t ? String(t) : null;
    } catch {
      tenantId = null;
    }
    if (!tenantId) return jerr(400, "Tenant nao carregado.");

    // A RPC valida tenant/empresa uma vez e evita a avaliacao de RLS para cada
    // titulo usado no ranking dos ultimos 180 dias.
    const { data, error } = await supabase.rpc("list_motivos_compra_import", {
      p_origem: origem || null,
    });

    if (error) {
      const msg = String(error.message ?? "");
      if (msg.toLowerCase().includes("permission denied")) {
        return jerr(403, msg);
      }
      return jerr(400, msg || "Erro ao carregar motivos.");
    }

    if (isDev) {
      let curEmpresa: string | null = null;
      try {
        const { data: e } = await supabase.rpc("current_empresa_id");
        curEmpresa = e ? String(e) : null;
      } catch {
        curEmpresa = null;
      }
      const motivoRows = (data ?? []) as unknown as MotivoRow[];
      const count = motivoRows.length;
      const preview = motivoRows
        .slice(0, 3).map((r) => ({ id: r.id, codigo: r.codigo, nome: r.nome, aplica_em: r.aplica_em }));
      console.log("[motivos-compra] loaded", { tenantId, curEmpresa, origem: origem || null, count, preview });
    }

    const motivos = ((data ?? []) as unknown as MotivoRow[])
      .map((r) => ({
        id: String(r.id),
        codigo: String(r.codigo ?? ""),
        nome: String(r.nome ?? ""),
        requires_text: Boolean(r.requires_text),
        requires_os: Boolean(r.requires_os),
        aplica_em: (r.aplica_em ? String(r.aplica_em) : "AMBOS") as AplicaEm,
        favorito: Boolean((r as MotivoRow).favorito),
        ordem: Number((r as MotivoRow).ordem ?? 0) || 0,
        qtd_usos_180d: Number((r as MotivoRow).qtd_usos_180d ?? 0) || 0,
      }))
      .filter((m) => m.id && m.codigo && m.nome);

    return NextResponse.json({ motivos });
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : "Erro inesperado.";
    return jerr(500, message);
  }
}

export async function POST(req: NextRequest) {
  try {
    const authorization = req.headers.get("authorization");
    if (!authorization) return jerr(401, "Nao autenticado.");

    const supabase = supabaseFromAuthHeader(req);
    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData.user) return jerr(401, "Nao autenticado.");

    // Resolve tenant from DB context.
    let tenantId: string | null = null;
    try {
      const { data: t, error: tErr } = await supabase.rpc("current_tenant_id");
      if (tErr) return jerr(400, tErr.message ?? "Falha ao resolver tenant.");
      tenantId = t ? String(t) : null;
    } catch {
      tenantId = null;
    }
    if (!tenantId) return jerr(400, "Tenant nao carregado.");

    const body = (await req.json().catch(() => null)) as FavoritoBody | null;
    const id = String(body?.id ?? "").trim();
    const favorito = Boolean(body?.favorito);
    if (!id) return jerr(400, "id obrigatorio.");

    const { error } = await supabase
      .schema("f")
      .from("motivo_compra")
      .update({ favorito })
      .eq("tenant_id", tenantId)
      .eq("id", id);

    if (error) {
      const msg = String(error.message ?? "Erro ao atualizar favorito.");
      if (msg.toLowerCase().includes("permission denied")) return jerr(403, msg);
      return jerr(400, msg);
    }

    if (isDev) console.log("[motivos-compra] favorito updated", { tenantId, id, favorito });
    return NextResponse.json({ ok: true });
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : "Erro inesperado.";
    return jerr(500, message);
  }
}
