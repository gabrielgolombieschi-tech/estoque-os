import { supabaseBrowser } from "@/lib/supabase/client";

export async function getCurrentTenantId(): Promise<string | null> {
  const supabase = supabaseBrowser();

  // Sem heurísticas: o tenant atual deve estar definido via RPC set_current_tenant,
  // que persiste o contexto em user_tenant_context (RLS filtra por auth.uid()).
  const { data, error } = await supabase.from("user_tenant_context").select("tenant_id").maybeSingle();
  if (error) throw error;
  return data?.tenant_id ? String(data.tenant_id) : null;
}
