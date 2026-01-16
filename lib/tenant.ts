import { SupabaseClient } from "@supabase/supabase-js";

export async function ensureCurrentTenant(
  supabase: SupabaseClient,
  preferredTenantId?: string | null
): Promise<string | null> {
  // Goal: after login, automatically resolve the user's tenant and set DB context.

  const { data: sessionData } = await supabase.auth.getSession();
  const userId = sessionData.session?.user?.id ?? null;
  if (!userId) return null;

  const isMember = async (tenantId: string): Promise<boolean> => {
    try {
      const { data, error } = await supabase
        .from("tenant_memberships")
        .select("tenant_id")
        .eq("user_id", userId)
        .eq("tenant_id", tenantId)
        .eq("status", "active")
        .maybeSingle();
      if (error) return false;
      return !!data?.tenant_id;
    } catch {
      return false;
    }
  };

  const trySet = async (tenantId: string): Promise<"ok" | "missing" | "fail"> => {
    const { error } = await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
    if (!error) return "ok";

    const message = String((error as { message?: unknown } | null)?.message ?? "").toLowerCase();
    if (message.includes("could not find the function public.set_current_tenant")) {
      // Some environments may not have this RPC yet. We can still return the resolved tenant id
      // so the app can scope queries by tenant_id/empresa_id where possible.
      console.warn(
        "RPC 'set_current_tenant' não encontrada no banco. O app vai continuar usando o tenant resolvido por memberships/contexto (sem setar contexto no DB)."
      );
      return "missing";
    }

    console.warn("Erro ao setar tenant no contexto:", (error as { message?: unknown } | null)?.message ?? error);
    return "fail";
  };

  // 1) Prefer a known/cached tenant when it matches an active membership.
  if (preferredTenantId && (await isMember(preferredTenantId))) {
    const setResult = await trySet(preferredTenantId);
    if (setResult === "ok" || setResult === "missing") return preferredTenantId;
  }

  // 2) If DB has persisted tenant choice, use it.
  try {
    const { data, error } = await supabase
      .from("user_tenant_context")
      .select("tenant_id")
      .eq("user_id", userId)
      .maybeSingle();

    if (!error) {
      const ctxTenantId = data?.tenant_id ? String(data.tenant_id) : null;
      if (ctxTenantId) {
        if (await isMember(ctxTenantId)) {
          const setResult = await trySet(ctxTenantId);
          if (setResult === "ok" || setResult === "missing") return ctxTenantId;
        }
      }
    }
  } catch {
    // Table may not exist in some environments; ignore and fall back.
  }

  // 3) Fallback: pick the first active membership.
  try {
    const { data, error } = await supabase
      .from("tenant_memberships")
      .select("tenant_id")
      .eq("user_id", userId)
      .eq("status", "active")
      .limit(1)
      .maybeSingle();

    if (!error) {
      const tenantId = data?.tenant_id ? String(data.tenant_id) : null;
      if (tenantId) {
        const setResult = await trySet(tenantId);
        if (setResult === "ok" || setResult === "missing") return tenantId;
      }
    }
  } catch {
    // ignore
  }

  // 4) Last resort: ask the DB for a default tenant id, then verify membership.
  try {
    const { data, error } = await supabase.rpc("get_default_tenant_id");
    if (!error && data) {
      const tenantId = String(data);
      if (await isMember(tenantId)) {
        const setResult = await trySet(tenantId);
        if (setResult === "ok" || setResult === "missing") return tenantId;
      }
    }
  } catch {
    // ignore
  }

  return null;
}
