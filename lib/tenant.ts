import { SupabaseClient } from "@supabase/supabase-js";

export async function ensureCurrentTenant(supabase: SupabaseClient): Promise<string | null> {
  // First try to read the current tenant from user_tenant_context (if available).
  let ctxTenantId: string | null = null;
  try {
    const { data: ctx, error: ctxErr } = await supabase
      .from("user_tenant_context")
      .select("tenant_id")
      .maybeSingle();
    if (ctxErr) {
      console.warn("user_tenant_context unavailable, falling back:", ctxErr.message);
    } else {
      ctxTenantId = ctx?.tenant_id ?? null;
    }
  } catch (e) {
    console.warn("Erro ao ler user_tenant_context, fallback para memberships:", e);
  }

  if (ctxTenantId) return ctxTenantId;

  // If no context yet, fetch the first active membership and set it.
  const { data: memberships, error: memErr } = await supabase
    .from("tenant_memberships")
    .select("tenant_id")
    .eq("status", "active")
    .limit(1);

  if (memErr) throw memErr;
  const tenantId = memberships?.[0]?.tenant_id;

  if (!tenantId) return null;

  const { error: rpcErr } = await supabase.rpc("set_current_tenant", {
    p_tenant_id: tenantId,
  });

  if (rpcErr) throw rpcErr;

  return tenantId;
}
