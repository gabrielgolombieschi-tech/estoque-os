import { supabaseBrowser } from "@/lib/supabase/client";

export async function getCurrentTenantId(): Promise<string> {
  const supabase = supabaseBrowser();

  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr) throw userErr;

  const user = userData.user;
  if (!user?.id) throw new Error("Usuário não autenticado.");

  const { data, error } = await supabase
    .from("tenant_memberships")
    .select("tenant_id")
    .eq("user_id", user.id)          // ✅ FILTRO CRÍTICO
    .eq("status", "active")
    .order("created_at", { ascending: false })
    .limit(1);

  if (error) throw error;

  const tenantId = data?.[0]?.tenant_id;
  if (!tenantId) throw new Error("Tenant ativo nao encontrado para este usuario.");

  return tenantId;
}
