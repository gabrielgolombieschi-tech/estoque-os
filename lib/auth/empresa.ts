import type { SupabaseClient } from "@supabase/supabase-js";

export type EmpresaOption = { id: string; nome: string | null };

type EmpresaMembershipRow = {
  empresa_id: string;
  criado_em?: string | null;
};

type EmpresaRow = {
  id: string | number;
  nome?: string | null;
  nome_fantasia?: string | null;
  razao_social?: string | null;
  ativo?: boolean | null;
};

function getEmpresaNome(row: EmpresaRow): string | null {
  return (row.nome ?? row.nome_fantasia ?? row.razao_social ?? null) as string | null;
}

async function fetchEmpresasByIds(
  supabase: SupabaseClient,
  tenantId: string,
  ids: string[]
): Promise<EmpresaOption[]> {
  if (ids.length === 0) return [];

  const { data, error } = await supabase
    .from("empresas")
    .select("*")
    .eq("tenant_id", tenantId)
    .in("id", ids);

  if (error) throw error;

  const rows = (data ?? []) as EmpresaRow[];
  return rows
    .filter((row) => row.ativo !== false)
    .map((row) => ({
      id: String(row.id),
      nome: getEmpresaNome(row),
    }));
}

export function getStoredEmpresaId(): string | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem("current_empresa_id");
}

export function setStoredEmpresaId(id: string): void {
  if (typeof window === "undefined") return;
  window.localStorage.setItem("current_empresa_id", id);
}

export async function getAllowedEmpresas(
  supabase: SupabaseClient,
  tenantId: string
): Promise<EmpresaOption[]> {
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr) throw userErr;
  const userId = userData.user?.id ?? null;
  if (!userId) throw new Error("Usuario nao autenticado.");

  const { data, error } = await supabase
    .from("empresa_memberships")
    .select("empresa_id, criado_em")
    .eq("tenant_id", tenantId)
    .eq("user_id", userId)
    .eq("status", "active")
    .order("criado_em", { ascending: true });

  if (error) {
    throw error;
  }

  const memberships = (data ?? []) as EmpresaMembershipRow[];
  const membershipIds = memberships.map((row) => row.empresa_id).filter(Boolean);

  if (membershipIds.length === 0) {
    return [];
  }

  const empresas = await fetchEmpresasByIds(supabase, tenantId, membershipIds);
  const byId = new Map(empresas.map((empresa) => [empresa.id, empresa]));

  return membershipIds
    .map((id) => byId.get(String(id)) ?? null)
    .filter((row): row is EmpresaOption => !!row);
}

export async function ensureEmpresaId(supabase: SupabaseClient, tenantId: string): Promise<string> {
  const empresas = await getAllowedEmpresas(supabase, tenantId);
  if (empresas.length === 0) {
    throw new Error("Sem acesso a empresas.");
  }

  const stored = getStoredEmpresaId();
  const match = stored ? empresas.find((empresa) => empresa.id === stored) : null;
  const chosen = match?.id ?? empresas[0].id;

  if (!match) setStoredEmpresaId(chosen);

  return chosen;
}
