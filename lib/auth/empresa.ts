import type { SupabaseClient } from "@supabase/supabase-js";
import type { EmpresaInfo } from "@/lib/auth/types";

export type EmpresaOption = EmpresaInfo;

type UsuarioIdRow = { id: string };
type UsuarioEmpresaRow = { empresa_id: string; papel?: string | null; created_at?: string | null };
type EmpresaRow = {
  id: string;
  tenant_id: string;
  cnpj: string | null;
  nome_fantasia: string | null;
  razao_social: string | null;
  ativo: boolean | null;
  deleted_at?: string | null;
};

function toEmpresaInfo(row: EmpresaRow): EmpresaInfo {
  return {
    id: String(row.id),
    tenant_id: String(row.tenant_id),
    nome_fantasia: row.nome_fantasia ?? null,
    razao_social: row.razao_social ?? null,
    cnpj: row.cnpj ?? null,
    ativo: row.ativo ?? null,
    papel: null,
  };
}

async function resolveAuthUserId(supabase: SupabaseClient): Promise<string | null> {
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

async function resolveUsuarioId(supabase: SupabaseClient, authUserId: string): Promise<string | null> {
  const { data, error } = await supabase
    .schema("a")
    .from("usuario")
    .select("id")
    .eq("auth_user_id", authUserId)
    .eq("ativo", true)
    .is("deleted_at", null)
    .maybeSingle<UsuarioIdRow>();
  if (error) return null;
  return data?.id ? String(data.id) : null;
}

async function fetchEmpresasByIds(supabase: SupabaseClient, tenantId: string, ids: string[]): Promise<EmpresaOption[]> {
  if (!ids.length) return [];

  const { data, error } = await supabase
    .schema("c")
    .from("empresa")
    .select("id,tenant_id,cnpj,razao_social,nome_fantasia,ativo,deleted_at")
    .eq("tenant_id", tenantId)
    .is("deleted_at", null)
    .in("id", ids)
    .order("nome_fantasia", { ascending: true });

  if (error) throw error;

  const rows = (data ?? []) as EmpresaRow[];
  return rows.filter((row) => row.ativo !== false).map(toEmpresaInfo);
}

export function getStoredEmpresaId(): string | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem("current_empresa_id");
}

export function setStoredEmpresaId(id: string): void {
  if (typeof window === "undefined") return;
  window.localStorage.setItem("current_empresa_id", id);
}

export async function getAllowedEmpresas(supabase: SupabaseClient, tenantId: string): Promise<EmpresaOption[]> {
  const authUserId = await resolveAuthUserId(supabase);
  if (!authUserId) throw new Error("Usuario nao autenticado.");

  const usuarioId = await resolveUsuarioId(supabase, authUserId);
  if (!usuarioId) {
    // When the app has a Supabase session but a.usuario isn't provisioned yet, we can't resolve memberships.
    // Keep behaviour explicit (no accidental broad access).
    throw new Error("Usuario nao encontrado em a.usuario.");
  }

  const { data: tenantMembership, error: tenantMembershipError } = await supabase
    .schema("a")
    .from("usuario_tenant")
    .select("id")
    .eq("usuario_id", usuarioId)
    .eq("tenant_id", tenantId)
    .eq("ativo", true)
    .is("deleted_at", null)
    .maybeSingle<{ id: string }>();

  if (tenantMembershipError) throw tenantMembershipError;
  if (!tenantMembership?.id) return [];

  const { data, error } = await supabase
    .schema("a")
    .from("usuario_empresa")
    .select("empresa_id,papel,created_at")
    .eq("usuario_id", usuarioId)
    .eq("ativo", true)
    .is("deleted_at", null)
    .order("created_at", { ascending: true });

  if (error) throw error;

  const memberships = (data ?? []) as UsuarioEmpresaRow[];
  const ids = memberships.map((row) => String(row.empresa_id)).filter(Boolean);
  const uniqueIds = Array.from(new Set(ids));
  if (!uniqueIds.length) return [];

  const papelByEmpresaId = new Map<string, string | null>();
  for (const m of memberships) {
    const empresaId = String(m.empresa_id);
    if (!empresaId) continue;
    if (!papelByEmpresaId.has(empresaId)) papelByEmpresaId.set(empresaId, m.papel ? String(m.papel) : null);
  }

  const empresas = await fetchEmpresasByIds(supabase, tenantId, uniqueIds);
  const byId = new Map(empresas.map((empresa) => [empresa.id, { ...empresa, papel: papelByEmpresaId.get(empresa.id) ?? null }]));

  // Preserve membership order when possible.
  return ids.map((id) => byId.get(id) ?? null).filter((row): row is EmpresaOption => !!row);
}

export async function ensureEmpresaId(
  supabase: SupabaseClient,
  tenantId: string,
  empresas?: EmpresaOption[]
): Promise<string> {
  const allowed = empresas ?? (await getAllowedEmpresas(supabase, tenantId));
  if (!allowed.length) throw new Error("Sem acesso a empresas.");

  const stored = getStoredEmpresaId();
  const match = stored ? allowed.find((empresa) => empresa.id === stored) : null;
  const chosen = match?.id ?? allowed[0].id;
  if (!match) setStoredEmpresaId(chosen);
  return chosen;
}
