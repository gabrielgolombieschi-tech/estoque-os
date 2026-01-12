import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase/admin";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";

function jerr(status: number, error: string) {
  return NextResponse.json({ error }, { status });
}

export const runtime = "nodejs";

type RoleRow = {
  id: string;
  name: string | null;
};

type MembershipRow = {
  id: number;
  user_id: string;
  status: string;
};

type ProfileRow = {
  user_id: string;
  nome: string | null;
};

type MembershipRoleRow = {
  membership_id: number;
  role_id: string;
};

type CreateBody = {
  email?: string;
  nome?: string;
  roles?: string[];
  tempPassword?: string;
  sendInvite?: boolean;
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

async function loadEmails(userIds: string[]) {
  const admin = supabaseAdmin();
  const emailMap = new Map<string, string | null>();

  if (userIds.length === 0) return emailMap;

  for (const userId of userIds) {
    const { data: userData } = await admin.auth.admin.getUserById(userId);
    emailMap.set(userId, userData.user?.email ?? null);
  }

  return emailMap;
}

export async function GET(req: NextRequest) {
  try {
    const ctx = await getAdminContext(req);
    if (isAdminError(ctx)) {
      return jerr(ctx.status, ctx.error);
    }

    const { tenantId } = ctx;
    const admin = supabaseAdmin();

    const { data: memberships, error: memErr } = await admin
      .from("tenant_memberships")
      .select("id,user_id,status")
      .eq("tenant_id", tenantId)
      .order("created_at", { ascending: false });

    if (memErr) {
      return jerr(400, memErr.message);
    }

    const membershipRows = (memberships ?? []) as MembershipRow[];
    const userIds = Array.from(new Set(membershipRows.map((m) => m.user_id)));
    const membershipIds = membershipRows.map((m) => m.id);

    const profileMap = new Map<string, ProfileRow>();
    if (userIds.length > 0) {
      const { data: profiles, error: profileErr } = await admin
        .from("user_profiles")
        .select("user_id,nome")
        .in("user_id", userIds);

      if (profileErr) {
        return jerr(400, profileErr.message);
      }

      const profileRows = (profiles ?? []) as ProfileRow[];
      profileRows.forEach((row) => profileMap.set(row.user_id, row));
    }

    const { data: rolesData, error: rolesErr } = await admin
      .from("roles")
      .select("id,name")
      .eq("tenant_id", tenantId)
      .order("name", { ascending: true });

    if (rolesErr) {
      return jerr(400, rolesErr.message);
    }

    const roles = (rolesData ?? []) as RoleRow[];
    const roleNameMap = new Map(roles.map((r) => [r.id, r.name ?? r.id]));

    const rolesByMembership = new Map<number, RoleRow[]>();
    if (membershipIds.length > 0) {
      const { data: membershipRoles, error: membershipRolesErr } = await admin
        .from("membership_roles")
        .select("membership_id,role_id")
        .in("membership_id", membershipIds);

      if (membershipRolesErr) {
        return jerr(400, membershipRolesErr.message);
      }

      const roleRows = (membershipRoles ?? []) as MembershipRoleRow[];
      roleRows.forEach((row) => {
        const list = rolesByMembership.get(row.membership_id) ?? [];
        list.push({ id: row.role_id, name: roleNameMap.get(row.role_id) ?? row.role_id });
        rolesByMembership.set(row.membership_id, list);
      });
    }

    const emailMap = await loadEmails(userIds);

    const users = membershipRows.map((membership) => {
      const profile = profileMap.get(membership.user_id) ?? null;
      return {
        user_id: membership.user_id,
        nome: profile?.nome ?? null,
        email: emailMap.get(membership.user_id) ?? null,
        status: membership.status,
        roles: rolesByMembership.get(membership.id) ?? [],
      };
    });

    return NextResponse.json({ users, roles });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Erro inesperado.";
    return jerr(500, message);
  }
}

export async function POST(req: NextRequest) {
  try {
    const admin = supabaseAdmin();
    const ctx = await getAdminContext(req);
    if (isAdminError(ctx)) {
      return jerr(ctx.status, ctx.error);
    }

    const body = (await req.json()) as CreateBody;
    const email = String(body.email ?? "").trim().toLowerCase();
    const nome = String(body.nome ?? "").trim();
    const roles = Array.isArray(body.roles) ? body.roles.filter(Boolean) : [];
    const tempPassword = body.tempPassword ? String(body.tempPassword) : "";
    const sendInvite = Boolean(body.sendInvite);

    if (!email) {
      return jerr(400, "Email obrigatorio.");
    }

    if (!nome) {
      return jerr(400, "Nome obrigatorio.");
    }

    if (!sendInvite && !tempPassword) {
      return jerr(400, "Informe senha temporaria ou envie convite.");
    }

    const { tenantId } = ctx;

    let userId: string | null = null;

    const { data: existingAuth, error: existingAuthErr } = await admin
      .schema("auth")
      .from("users")
      .select("id")
      .eq("email", email)
      .maybeSingle();

    if (!existingAuthErr && existingAuth?.id) {
      userId = existingAuth.id as string;
    }

    if (!userId && sendInvite) {
      const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
        data: { nome },
      });
      if (error) {
        return jerr(400, error.message);
      }
      userId = data.user?.id ?? null;
    } else if (!userId) {
      const { data, error } = await admin.auth.admin.createUser({
        email,
        password: tempPassword,
        email_confirm: true,
        user_metadata: { nome },
      });
      if (error) {
        return jerr(400, error.message);
      }
      userId = data.user?.id ?? null;
    }

    if (!userId) {
      return jerr(400, "Falha ao criar usuario.");
    }

    const { error: profileErr } = await admin
      .from("user_profiles")
      .upsert({ user_id: userId, nome }, { onConflict: "user_id" });

    if (profileErr) {
      return jerr(400, profileErr.message);
    }

    const { data: membership, error: membershipErr } = await admin
      .from("tenant_memberships")
      .upsert({ tenant_id: tenantId, user_id: userId, status: "active" }, { onConflict: "tenant_id,user_id" })
      .select("id")
      .single();

    if (membershipErr) {
      return jerr(400, membershipErr.message);
    }

    const membershipId = membership?.id as number | null;

    if (membershipId && roles.length > 0) {
      const { error: clearErr } = await admin.from("membership_roles").delete().eq("membership_id", membershipId);
      if (clearErr) {
        return jerr(400, clearErr.message);
      }
      const payload = roles.map((roleId) => ({
        membership_id: membershipId,
        role_id: roleId,
      }));

      const { error: rolesErr } = await admin.from("membership_roles").insert(payload);
      if (rolesErr) {
        return jerr(400, rolesErr.message);
      }
    }

    return NextResponse.json({ ok: true, user_id: userId });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Erro inesperado.";
    return jerr(500, message);
  }
}
