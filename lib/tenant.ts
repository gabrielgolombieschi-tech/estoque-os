import type { SupabaseClient } from "@supabase/supabase-js";

const isDev = process.env.NODE_ENV !== "production";

type UsuarioIdRow = { id: string };
type UsuarioTenantRow = { tenant_id: string; papel: string | null; created_at?: string | null };

function isMissingRpc(error: unknown, rpcName: string) {
  const message =
    typeof error === "object" && error !== null && "message" in error
      ? String((error as any).message ?? "")
      : String(error ?? "");
  return message.toLowerCase().includes(`could not find the function public.${rpcName}`);
}

async function resolveAuthUserId(supabase: SupabaseClient, authUserId?: string | null): Promise<string | null> {
  if (authUserId) return authUserId;

  try {
    const { data, error } = await supabase.auth.getUser();
    if (!error && data.user?.id) return data.user.id;
  } catch {
    // ignore
  }

  try {
    const { data } = await supabase.auth.getSession();
    return data.session?.user?.id ?? null;
  } catch {
    return null;
  }
}

async function resolveUsuarioId(
  supabase: SupabaseClient,
  authUserId: string,
  usuarioId?: string | null
): Promise<string | null> {
  if (usuarioId) return usuarioId;

  const { data, error } = await supabase
    .schema("a")
    .from("usuario")
    .select("id")
    .eq("auth_user_id", authUserId)
    .is("deleted_at", null)
    .maybeSingle<UsuarioIdRow>();

  if (error) return null;
  return data?.id ? String(data.id) : null;
}

function pickTenantId(rows: UsuarioTenantRow[]): string | null {
  if (!rows.length) return null;
  // Keep behavior aligned with public.current_tenant_id(): prefer the oldest membership.
  // (If the app wants a different tenant, it should pass preferredTenantId or rely on cached selection.)
  return rows[0]?.tenant_id ? String(rows[0].tenant_id) : null;
}

export async function ensureCurrentTenant(
  supabase: SupabaseClient,
  preferredTenantId?: string | null,
  opts?: { authUserId?: string | null; usuarioId?: string | null }
): Promise<string | null> {
  const authUserId = await resolveAuthUserId(supabase, opts?.authUserId ?? null);
  if (!authUserId) return null;

  const usuarioId = await resolveUsuarioId(supabase, authUserId, opts?.usuarioId ?? null);
  if (!usuarioId) return null;

  const trySet = async (tenantId: string) => {
    try {
      const { error } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      if (error && !isMissingRpc(error, "set_current_tenant")) {
        if (isDev) console.debug("[TENANT] set_current_tenant error", { message: error.message });
      }
    } catch {
      // ignore
    }
  };

  const isMember = async (tenantId: string) => {
    try {
      const { data, error } = await supabase
        .schema("a")
        .from("usuario_tenant")
        .select("tenant_id")
        .eq("usuario_id", usuarioId)
        .eq("tenant_id", tenantId)
        .eq("ativo", true)
        .is("deleted_at", null)
        .maybeSingle();

      if (error) return false;
      return Boolean(data?.tenant_id);
    } catch {
      return false;
    }
  };

  if (preferredTenantId && (await isMember(preferredTenantId))) {
    await trySet(preferredTenantId);
    return preferredTenantId;
  }

  const { data, error } = await supabase
    .schema("a")
    .from("usuario_tenant")
    .select("tenant_id,papel,created_at")
    .eq("usuario_id", usuarioId)
    .eq("ativo", true)
    .is("deleted_at", null);

  if (error) return null;

  const rows = (data ?? []) as UsuarioTenantRow[];
  // Ensure deterministic ordering so we don't pick a different tenant than DB-side current_tenant_id().
  rows.sort((a, b) => {
    const at = a.created_at ? Date.parse(String(a.created_at)) : Number.POSITIVE_INFINITY;
    const bt = b.created_at ? Date.parse(String(b.created_at)) : Number.POSITIVE_INFINITY;
    return at - bt;
  });
  const tenantId = pickTenantId(rows);
  if (!tenantId) return null;

  await trySet(tenantId);
  return tenantId;
}
