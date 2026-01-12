import { supabaseBrowser } from "@/lib/supabase/client";

export async function getCurrentTenantId(): Promise<string | null> {
  const supabase = supabaseBrowser();
  const { data: sessionData } = await supabase.auth.getSession();
  const userId = sessionData.session?.user?.id ?? null;
  if (!userId) return null;

  const { data, error } = await supabase
    .from("tenant_memberships")
    .select("tenant_id")
    .eq("user_id", userId)
    .eq("status", "active")
    .order("created_at", { ascending: false })
    .limit(1);

  if (error) throw error;

  return data?.[0]?.tenant_id ?? null;
}
