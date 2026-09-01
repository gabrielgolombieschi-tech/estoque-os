import { NextRequest, NextResponse } from "next/server";
import { getAllowedEmpresas } from "@/lib/auth/empresa";
import { supabaseAdmin } from "@/lib/supabase/admin";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";

export const runtime = "nodejs";

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

function jsonError(status: number, error: string) {
  return NextResponse.json({ error }, { status });
}

export async function GET(req: NextRequest) {
  try {
    const authorization = req.headers.get("authorization");
    if (!authorization) return jsonError(401, "Não autenticado.");

    const supabase = supabaseFromAuthHeader(req);
    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) return jsonError(401, "Não autenticado.");

    const tenantId = String(req.nextUrl.searchParams.get("tenantId") ?? "").trim();
    const empresaId = String(req.nextUrl.searchParams.get("empresaId") ?? "").trim();
    if (!UUID_REGEX.test(tenantId)) return jsonError(400, "Tenant inválido.");
    if (!UUID_REGEX.test(empresaId)) return jsonError(400, "Empresa inválida.");

    const empresasPermitidas = await getAllowedEmpresas(supabase, tenantId);
    if (!empresasPermitidas.some((empresa) => empresa.id === empresaId)) {
      return jsonError(403, "Sem acesso a esta empresa.");
    }

    const admin = supabaseAdmin();
    const { data: usuarioEmpresaRows, error: usuarioEmpresaError } = await admin
      .schema("a")
      .from("usuario_empresa")
      .select("ativo,deleted_at,usuario:usuario_id(id,auth_user_id,nome,email,ativo,deleted_at)")
      .eq("empresa_id", empresaId)
      .eq("ativo", true)
      .is("deleted_at", null)
      .returns<UsuarioEmpresaRow[]>();

    if (usuarioEmpresaError) return jsonError(400, usuarioEmpresaError.message);

    const candidates = (usuarioEmpresaRows ?? [])
      .map((row) => row.usuario)
      .filter((usuario): usuario is UsuarioRow => Boolean(usuario?.id))
      .filter((usuario) => usuario.ativo !== false && !usuario.deleted_at)
      .map((usuario) => ({
        id: String(usuario.id),
        auth_user_id: usuario.auth_user_id ? String(usuario.auth_user_id) : null,
        nome: String(usuario.nome ?? "").trim(),
        email: String(usuario.email ?? "").trim(),
      }))
      .filter((usuario) => usuario.auth_user_id && usuario.nome && usuario.email);

    const usuarios = candidates
      .map((usuario) => ({
        id: usuario.id,
        auth_user_id: usuario.auth_user_id!,
        nome: usuario.nome,
        email: usuario.email,
      }))
      .sort((a, b) => {
        const porNome = a.nome.localeCompare(b.nome, "pt-BR", { sensitivity: "base" });
        return porNome !== 0 ? porNome : a.email.localeCompare(b.email, "pt-BR", { sensitivity: "base" });
      });

    return NextResponse.json(
      { usuarios },
      { headers: { "Cache-Control": "private, no-store, max-age=0" } }
    );
  } catch (error: unknown) {
    return jsonError(500, error instanceof Error ? error.message : "Erro inesperado.");
  }
}
