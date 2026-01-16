import { SupabaseClient } from "@supabase/supabase-js";

export async function ensureCurrentTenant(supabase: SupabaseClient): Promise<string | null> {
  // HARDCODED: Sempre retorna o tenant fixo
  const tenantId = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7';
  
  // Seta o tenant no contexto do DB
  const { error: rpcErr } = await supabase.rpc("set_current_tenant", {
    p_tenant_id: tenantId,
  });

  if (rpcErr) {
    console.warn("Erro ao setar tenant no contexto:", rpcErr.message);
  }

  return tenantId;
}
