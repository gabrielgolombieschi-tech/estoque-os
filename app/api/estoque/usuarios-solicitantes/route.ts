import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase/admin";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";
import { getAllowedEmpresas } from "@/lib/auth/empresa";

export const runtime = "nodejs";

function jerr(status: number, error: string) {
  return NextResponse.json({ error }, { status });
}

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type UsuarioRow = {
  id: string;
  auth_user_id: string | null;
  nome: string | null;
  email: string | null;
  ativo: boolean | null;
  deleted_at: string | null;
};

type UsuarioEmpresaRow = {
  usuario: UsuarioRow | null;
  ativo: boolean | null;
  deleted_at: string | null;
};

type TenantMembershipRow = {
  user_id: string | null;
  status: string | null;
};

export async function GET(req: NextRequest) {
  try {
    const authorization = req.headers.get("authorization");
    if (!authorization) return jerr(401, "Nao autenticado.");

    const supabase = supabaseFromAuthHeader(req);
    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData.user) return jerr(401, "Nao autenticado.");

    const tenantId = String(req.nextUrl.searchParams.get("tenantId") ?? "").trim();
    const empresaId = String(req.nextUrl.searchParams.get("empresaId") ?? "").trim();
    if (!tenantId) return jerr(400, "tenantId obrigatorio.");
    if (!empresaId) return jerr(400, "empresaId obrigatorio.");
    if (!UUID_REGEX.test(tenantId)) return jerr(400, "tenantId invalido.");
    if (!UUID_REGEX.test(empresaId)) return jerr(400, "empresaId invalido.");

    // Validate empresa membership for the requesting user (avoid service-role overreach).
    const allowed = await getAllowedEmpresas(supabase, tenantId);
    if (!allowed.some((e) => e.id === empresaId)) return jerr(403, "Sem acesso a esta empresa.");

    const admin = supabaseAdmin();

    const { data: ueRows, error: ueErr } = await admin
      .schema("a")
      .from("usuario_empresa")
      .select("ativo,deleted_at,usuario:usuario_id(id,auth_user_id,nome,email,ativo,deleted_at)")
      .eq("empresa_id", empresaId)
      .eq("ativo", true)
      .is("deleted_at", null)
      .returns<UsuarioEmpresaRow[]>();

    if (ueErr) return jerr(400, ueErr.message ?? "Erro ao carregar usuarios.");

    const candidates = (ueRows ?? [])
      .map((r) => r.usuario ?? null)
      .filter((u): u is UsuarioRow => Boolean(u && u.id))
      .filter((u) => u.ativo !== false && !u.deleted_at)
      .map((u) => ({
        id: String(u.id),
        auth_user_id: u.auth_user_id ? String(u.auth_user_id) : null,
        nome: String(u.nome ?? "").trim(),
        email: String(u.email ?? "").trim(),
      }))
      .filter((u) => u.id && u.nome && u.email && u.auth_user_id);

    const authUserIds = Array.from(new Set(candidates.map((u) => u.auth_user_id!).filter(Boolean)));
    if (authUserIds.length === 0) return NextResponse.json({ usuarios: [] });

    const { data: tmRows, error: tmErr } = await admin
      .from("tenant_memberships")
      .select("user_id,status")
      .eq("tenant_id", tenantId)
      .in("user_id", authUserIds)
      .returns<TenantMembershipRow[]>();

    if (tmErr) return jerr(400, tmErr.message ?? "Erro ao validar usuarios no tenant.");

    const allowedAuth = new Set(
      (tmRows ?? [])
        .map((r) => ({ user_id: r.user_id ? String(r.user_id) : "", status: String(r.status ?? "").toLowerCase().trim() }))
        .filter((r) => r.user_id && (r.status === "active" || r.status === "ativo"))
        .map((r) => r.user_id)
    );

    const usuarios = candidates
      .filter((u) => allowedAuth.has(u.auth_user_id!))
      .map((u) => ({ id: u.id, nome: u.nome, email: u.email }))
      .sort((a, b) => {
        const byNome = a.nome.localeCompare(b.nome, "pt-BR", { sensitivity: "base" });
        if (byNome !== 0) return byNome;
        return a.email.localeCompare(b.email, "pt-BR", { sensitivity: "base" });
      });

    return NextResponse.json({ usuarios });
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : "Erro inesperado.";
    return jerr(500, message);
  }
}

