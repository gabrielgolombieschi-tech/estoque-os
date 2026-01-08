import { supabaseBrowser } from "@/lib/supabase/client";

export type UserPermission = {
  tenant_id: string;
  permission: string;
};

let cachedPermissions: string[] | null = null;

/**
 * Carrega todas as permissoes do usuario logado
 */
export async function loadUserPermissions(): Promise<string[]> {
  if (cachedPermissions) return cachedPermissions;

  const { data, error } = await supabaseBrowser().from("v_user_permissions").select("permission");

  if (error) {
    console.error("Erro ao carregar permissoes", error);
    return [];
  }

  cachedPermissions = (data ?? []).map((d) => d.permission);
  return cachedPermissions;
}

/**
 * Verifica se o usuario possui uma permissao especifica
 */
export async function hasPermission(permission: string): Promise<boolean> {
  const perms = await loadUserPermissions();
  return perms.includes(permission);
}

/**
 * Limpa cache (usar no logout)
 */
export function clearPermissionCache() {
  cachedPermissions = null;
}
