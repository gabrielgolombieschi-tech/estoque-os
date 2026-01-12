import type { SupabaseClient } from "@supabase/supabase-js";

export type EmpresaOption = { id: string; nome: string | null };

type EmpresaRow = {
  id: string | number;
  nome?: string | null;
  nome_fantasia?: string | null;
  razao_social?: string | null;
  ativo?: boolean | null;
};

type EmpresaMembershipRow = {
  empresa_id: string;
  criado_em?: string | null;
};

type SupabaseError = { code?: string; message?: string } | null | undefined;

function isMissingRelation(error: SupabaseError, tableName: string): boolean {
  const message = error?.message?.toLowerCase() ?? "";
  return (
    error?.code === "42P01" ||
    message.includes("schema cache") ||
    message.includes(`relation "${tableName}"`) ||
    message.includes(tableName)
  );
}

function getEmpresaNome(row: EmpresaRow): string | null {
  return (row.nome ?? row.nome_fantasia ?? row.razao_social ?? null) as string | null;
}

async function hasAdminAccess(supabase: SupabaseClient): Promise<boolean> {
  const { data, error } = await supabase.rpc("can", {
    p_resource: "admin",
    p_action: "manage_users",
  });
  if (error) {
    return false;
  }
  return Boolean(data);
}

async function fetchEmpresasByTenant(
  supabase: SupabaseClient,
  tenantId: string
): Promise<EmpresaOption[]> {
  const { data, error } = await supabase
    .from("empresas")
    .select("*")
    .eq("tenant_id", tenantId)
    .order("criado_em", { ascending: true });

  if (error) {
    throw error;
  }

  const rows = (data ?? []) as EmpresaRow[];
  return rows
    .filter((row) => row.ativo !== false)
    .map((row) => ({
      id: String(row.id),
      nome: getEmpresaNome(row),
    }));
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

  if (error) {
    throw error;
  }

  const rows = (data ?? []) as EmpresaRow[];
  return rows
    .filter((row) => row.ativo !== false)
    .map((row) => ({
      id: String(row.id),
      nome: getEmpresaNome(row),
    }));
}

async function seedEmpresaMemberships(
  supabase: SupabaseClient,
  tenantId: string,
  userId: string,
  empresas: EmpresaOption[]
): Promise<void> {
  if (empresas.length === 0) return;
  try {
    await supabase
      .from("empresa_memberships")
      .upsert(
        empresas.map((empresa) => ({
          tenant_id: tenantId,
          empresa_id: empresa.id,
          user_id: userId,
          status: "active",
        })),
        { onConflict: "tenant_id,empresa_id,user_id" }
      );
  } catch {
    // Ignore membership seeding errors for environments without this table.
  }
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
  const { data: sessionData } = await supabase.auth.getSession();
  const userId = sessionData.session?.user?.id ?? null;
  if (!userId) {
    throw new Error("Usuario nao autenticado.");
  }

  const { data, error } = await supabase
    .from("empresa_memberships")
    .select("empresa_id, criado_em")
    .eq("tenant_id", tenantId)
    .eq("user_id", userId)
    .eq("status", "active")
    .order("criado_em", { ascending: true });

  if (error) {
    if (isMissingRelation(error, "empresa_memberships")) {
      return fetchEmpresasByTenant(supabase, tenantId);
    }

    const isAdmin = await hasAdminAccess(supabase);
    if (isAdmin) {
      const fallback = await fetchEmpresasByTenant(supabase, tenantId);
      await seedEmpresaMemberships(supabase, tenantId, userId, fallback);
      return fallback;
    }

    throw new Error(
      "Nao foi possivel carregar empresas. Verifique permissao de SELECT em empresa_memberships."
    );
  }

  const memberships = (data ?? []) as EmpresaMembershipRow[];
  const membershipIds = memberships.map((row) => row.empresa_id).filter(Boolean);

  if (membershipIds.length === 0) {
    const isAdmin = await hasAdminAccess(supabase);
    if (!isAdmin) return [];

    const fallback = await fetchEmpresasByTenant(supabase, tenantId);
    await seedEmpresaMemberships(supabase, tenantId, userId, fallback);
    return fallback;
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
