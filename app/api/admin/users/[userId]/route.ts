import { NextRequest, NextResponse } from "next/server";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";

function jerr(status: number, error: string) {
  return NextResponse.json({ error }, { status });
}

export const runtime = "nodejs";

type UpdateBody = {
  nome?: string;
  status?: string;
  roles?: string[];
};

type AdminContext =
  | { error: string; status: number }
  | { supabase: ReturnType<typeof supabaseFromAuthHeader>; tenantId: string };

function isAdminError(ctx: AdminContext): ctx is { error: string; status: number } {
  return "error" in ctx;
}

async function getAdminContext(req: NextRequest): Promise<AdminContext> {
  const authorization = req.headers.get("authorization");
  if (!authorization) {
    return { error: "Nao autenticado.", status: 401 } as const;
  }

  const supabase = supabaseFromAuthHeader(req);
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData.user) {
    return { error: "Nao autenticado.", status: 401 } as const;
  }

  const { data: tenantId, error: tenantErr } = await supabase.rpc("current_tenant_id");
  if (tenantErr || !tenantId) {
    return { error: "Tenant nao carregado.", status: 400 } as const;
  }

  const { data: canManage, error: canManageErr } = await supabase.rpc("admin_can_manage_users", {
    p_tenant_id: String(tenantId),
  });
  if (canManageErr || !canManage) {
    return { error: "Sem permissao.", status: 403 } as const;
  }

  return { supabase, tenantId } as const;
}

export async function PATCH(req: NextRequest, context: { params: Promise<{ userId: string }> }) {
  try {
    const ctx = await getAdminContext(req);
    if (isAdminError(ctx)) {
      return jerr(ctx.status, ctx.error);
    }

    const { userId } = await context.params;
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!userId || !uuidRegex.test(userId)) {
      return jerr(400, "Usuario invalido.");
    }

    const body = (await req.json()) as UpdateBody;
    const nome = body.nome !== undefined ? String(body.nome).trim() : null;
    const status = body.status === undefined ? null : String(body.status).trim();
    const roles = Array.isArray(body.roles) ? body.roles.filter(Boolean) : null;

    if (status !== null && status !== "active" && status !== "inactive") {
      return jerr(400, "Status invalido.");
    }

    const { tenantId } = ctx;

    const { data: canManageTarget, error: canManageTargetErr } = await ctx.supabase.rpc(
      "admin_can_manage_auth_user",
      {
        p_tenant_id: String(tenantId),
        p_target_auth_user_id: userId,
      }
    );
    if (canManageTargetErr) return jerr(400, canManageTargetErr.message);
    if (!canManageTarget) return jerr(403, "Usuario acima da sua alcada.");

    if (roles !== null) {
      const { data: canAssignRoles, error: canAssignRolesErr } = await ctx.supabase.rpc(
        "admin_can_assign_legacy_roles",
        {
          p_tenant_id: String(tenantId),
          p_role_ids: roles,
        }
      );
      if (canAssignRolesErr) return jerr(400, canAssignRolesErr.message);
      if (!canAssignRoles) return jerr(403, "Matriz de acessos restrita a OWNER/ADMIN.");
    }

    const { error: updateErr } = await ctx.supabase.rpc("admin_update_legacy_user", {
      p_tenant_id: String(tenantId),
      p_target_auth_user_id: userId,
      p_update_nome: nome !== null,
      p_nome: nome,
      p_update_status: status !== null,
      p_status: status,
      p_update_roles: roles !== null,
      p_role_ids: roles ?? [],
    });
    if (updateErr) return jerr(400, updateErr.message);

    return NextResponse.json({ ok: true });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Erro inesperado.";
    return jerr(500, message);
  }
}
