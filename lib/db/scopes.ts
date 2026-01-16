type EqQuery<T> = {
  eq: (key: string, value: unknown) => T;
};

export function applyTenant<T>(query: T, tenantId: string): T {
  const withTenant = (query as EqQuery<T>).eq("tenant_id", tenantId);
  return withTenant;
}

export function applyTenantEmpresa<T>(query: T, tenantId: string, empresaId: string): T {
  // IMPORTANT: empresa scoping is RLS-only via current_empresa_id() and RPC set_current_empresa.
  // Do NOT inject `.eq('empresa_id', ...)` here.
  void empresaId;
  return applyTenant(query, tenantId);
}
