import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase/admin";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";

const ADMIN_PERMISSION = "admin.manage_users";

function jerr(status: number, error: string) {
  return NextResponse.json({ error }, { status });
}

export const runtime = "nodejs";

type ResetBody = {
  mode?: "email" | "temp";
  tempPassword?: string;
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

export async function POST(req: NextRequest, context: { params: Promise<{ userId: string }> }) {
  try {
    const admin = supabaseAdmin();
    const ctx = await getAdminContext(req);
    if (isAdminError(ctx)) {
      return jerr(ctx.status, ctx.error);
    }

    const { userId } = await context.params;
    if (!userId) {
      return jerr(400, "Usuario invalido.");
    }

    const body = (await req.json()) as ResetBody;
    const mode = body.mode === "temp" ? "temp" : "email";
    const tempPassword = body.tempPassword ? String(body.tempPassword) : "";

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

    if (!membership?.id) {
      return jerr(404, "Membership nao encontrado.");
    }

    if (mode === "email") {
      const { data: userData, error: userErr } = await admin.auth.admin.getUserById(userId);
      if (userErr || !userData.user?.email) {
        return jerr(400, "Email do usuario nao encontrado.");
      }

      const { error } = await admin.auth.resetPasswordForEmail(userData.user.email);
      if (error) {
        return jerr(400, error.message);
      }

      return NextResponse.json({ ok: true, mode: "email" });
    }

    if (!tempPassword) {
      return jerr(400, "Senha temporaria obrigatoria.");
    }

    const { error: updateErr } = await admin.auth.admin.updateUserById(userId, {
      password: tempPassword,
    });

    if (updateErr) {
      return jerr(400, updateErr.message);
    }

    return NextResponse.json({ ok: true, mode: "temp" });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Erro inesperado.";
    return jerr(500, message);
  }
}
