import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase/admin";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";

export const runtime = "nodejs";

function jerr(status: number, error: string) {
  return NextResponse.json({ error }, { status });
}

type Body =
  | { mode: "reset_email" }
  | {
      mode: "set_password";
      password: string;
    };

async function requireAdminManageUsers(req: NextRequest) {
  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization) return { ok: false as const, status: 401 as const, error: "Nao autenticado." };

  const supabase = supabaseFromAuthHeader(req);
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  const authUserId = userData.user?.id ?? null;
  if (userErr || !authUserId) return { ok: false as const, status: 401 as const, error: "Nao autenticado." };

  const { data: hasPerm, error: permErr } = await supabase.rpc("can", {
    p_resource: "admin",
    p_action: "manage_users",
  });
  if (permErr || !hasPerm) {
    return { ok: false as const, status: 403 as const, error: "Sem permissao." };
  }

  const { data: tenantId, error: tenantErr } = await supabase.rpc("current_tenant_id");
  if (tenantErr || !tenantId) return { ok: false as const, status: 400 as const, error: "Tenant nao carregado." };

  const admin = supabaseAdmin();

  return { ok: true as const, tenantId: String(tenantId), admin, requesterAuthUserId: authUserId };
}

async function requireRequesterIsOwner(
  admin: ReturnType<typeof supabaseAdmin>,
  tenantId: string,
  requesterAuthUserId: string
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const { data: usuarioRow, error: usuarioErr } = await admin
    .schema("a")
    .from("usuario")
    .select("id")
    .eq("auth_user_id", requesterAuthUserId)
    .is("deleted_at", null)
    .maybeSingle();

  if (usuarioErr) return { ok: false, status: 400, error: usuarioErr.message };
  if (!usuarioRow?.id) return { ok: false, status: 403, error: "Usuario nao encontrado no ERP." };

  const { data: utRow, error: utErr } = await admin
    .schema("a")
    .from("usuario_tenant")
    .select("papel")
    .eq("usuario_id", usuarioRow.id)
    .eq("tenant_id", tenantId)
    .eq("ativo", true)
    .is("deleted_at", null)
    .maybeSingle();

  if (utErr) return { ok: false, status: 400, error: utErr.message };
  if (!utRow || String(utRow.papel ?? "").toUpperCase() !== "OWNER") {
    return { ok: false, status: 403, error: "Apenas TENANT OWNER pode alterar senha." };
  }

  return { ok: true };
}

async function ensureTargetInTenant(admin: ReturnType<typeof supabaseAdmin>, tenantId: string, authUserId: string) {
  // Prefer ERP mapping (a.usuario + a.usuario_tenant)
  const { data: targetUsuario, error: targetUsuarioErr } = await admin
    .schema("a")
    .from("usuario")
    .select("id")
    .eq("auth_user_id", authUserId)
    .is("deleted_at", null)
    .maybeSingle();

  if (targetUsuarioErr) return { ok: false as const, status: 400 as const, error: targetUsuarioErr.message };

  if (targetUsuario?.id) {
    const { data: targetUt, error: targetUtErr } = await admin
      .schema("a")
      .from("usuario_tenant")
      .select("id")
      .eq("usuario_id", targetUsuario.id)
      .eq("tenant_id", tenantId)
      .eq("ativo", true)
      .is("deleted_at", null)
      .maybeSingle();

    if (targetUtErr) return { ok: false as const, status: 400 as const, error: targetUtErr.message };
    if (!targetUt?.id) return { ok: false as const, status: 404 as const, error: "Usuario alvo nao pertence ao tenant." };
    return { ok: true as const };
  }

  // Fallback: membership table (supports users not present in ERP schema)
  const { data: membership, error: membershipErr } = await admin
    .from("tenant_memberships")
    .select("id")
    .eq("tenant_id", tenantId)
    .eq("user_id", authUserId)
    .maybeSingle();

  if (membershipErr) return { ok: false as const, status: 400 as const, error: membershipErr.message };
  if (!membership?.id) return { ok: false as const, status: 404 as const, error: "Usuario alvo nao pertence ao tenant." };

  return { ok: true as const };
}

export async function POST(req: NextRequest, context: { params: Promise<{ authUserId: string }> }) {
  try {
    const ctx = await requireAdminManageUsers(req);
    if (!ctx.ok) return jerr(ctx.status, ctx.error);

    const ownerCheck = await requireRequesterIsOwner(ctx.admin, ctx.tenantId, ctx.requesterAuthUserId);
    if (!ownerCheck.ok) return jerr(ownerCheck.status, ownerCheck.error);

    const { authUserId } = await context.params;
    const targetAuthUserId = String(authUserId ?? "").trim();
    if (!targetAuthUserId) return jerr(400, "Usuario invalido.");

    const body = (await req.json().catch(() => null)) as Body | null;
    if (!body || (body as any).mode == null) return jerr(400, "Body invalido.");

    const inTenant = await ensureTargetInTenant(ctx.admin, ctx.tenantId, targetAuthUserId);
    if (!inTenant.ok) return jerr(inTenant.status, inTenant.error);

    if (body.mode === "reset_email") {
      const { data: userData, error: userErr } = await ctx.admin.auth.admin.getUserById(targetAuthUserId);
      const email = userData.user?.email ?? null;
      if (userErr || !email) return jerr(400, "Email do usuario nao encontrado.");

      const { error } = await ctx.admin.auth.resetPasswordForEmail(email);
      if (error) return jerr(400, error.message);

      return NextResponse.json({ ok: true, mode: "reset_email" });
    }

    const password = String(body.password ?? "");
    if (password.length < 8) return jerr(400, "Senha deve ter pelo menos 8 caracteres.");

    const { error: updateErr } = await ctx.admin.auth.admin.updateUserById(targetAuthUserId, { password });
    if (updateErr) return jerr(400, updateErr.message);

    return NextResponse.json({ ok: true, mode: "set_password" });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Erro inesperado.";
    return jerr(500, message);
  }
}
