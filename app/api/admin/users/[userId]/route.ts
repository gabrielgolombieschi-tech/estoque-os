import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase/admin";
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
  | { supabase: ReturnType<typeof supabaseFromAuthHeader>; tenantId: number };

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

  const { data: hasPerm, error: permErr } = await supabase.rpc("can", {
    p_resource: "admin",
    p_action: "manage_users",
  });
  if (permErr || !hasPerm) {
    return { error: "Sem permissao.", status: 403 } as const;
  }

  const { data: tenantId, error: tenantErr } = await supabase.rpc("current_tenant_id");
  if (tenantErr || !tenantId) {
    return { error: "Tenant nao carregado.", status: 400 } as const;
  }

  return { supabase, tenantId } as const;
}

export async function PATCH(req: NextRequest, context: { params: Promise<{ userId: string }> }) {
  try {
    const admin = supabaseAdmin();
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
    const status = body.status ? String(body.status).trim() : "";
    const roles = Array.isArray(body.roles) ? body.roles.filter(Boolean) : null;

    const { tenantId } = ctx;

    const { data: membership, error: membershipErr } = await admin
      .from("tenant_memberships")
      .select("id")
      .eq("tenant_id", tenantId)
      .eq("user_id", userId)
      .maybeSingle();

    if (membershipErr) {
      return jerr(400, membershipErr.message);
    }

    const membershipId = membership?.id as number | null;
    if (!membershipId) {
      return jerr(404, "Membership nao encontrado.");
    }

    if (nome !== null) {
      const { error: profileErr } = await admin
        .from("user_profiles")
        .upsert({ user_id: userId, nome: nome || null }, { onConflict: "user_id" });
      if (profileErr) {
        return jerr(400, profileErr.message);
      }
    }

    if (status) {
      const { error: statusErr } = await admin
        .from("tenant_memberships")
        .update({ status })
        .eq("id", membershipId);
      if (statusErr) {
        return jerr(400, statusErr.message);
      }
    }

    if (roles) {
      const { error: deleteErr } = await admin
        .from("membership_roles")
        .delete()
        .eq("membership_id", membershipId);
      if (deleteErr) {
        return jerr(400, deleteErr.message);
      }

      if (roles.length > 0) {
        const payload = roles.map((roleId) => ({
          membership_id: membershipId,
          role_id: roleId,
        }));
        const { error: insertErr } = await admin.from("membership_roles").insert(payload);
        if (insertErr) {
          return jerr(400, insertErr.message);
        }
      }
    }

    return NextResponse.json({ ok: true });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Erro inesperado.";
    return jerr(500, message);
  }
}
