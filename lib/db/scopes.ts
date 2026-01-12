type EqQuery<T> = {
  eq: (key: string, value: unknown) => T;
};

export function applyTenant<T>(query: T, tenantId: string): T {
  const withTenant = (query as EqQuery<T>).eq("tenant_id", tenantId);
  return withTenant;
}

export function applyTenantEmpresa<T>(query: T, tenantId: string, empresaId: string): T {
  const withTenant = (query as EqQuery<T>).eq("tenant_id", tenantId);
  const withEmpresa = (withTenant as EqQuery<T>).eq("empresa_id", empresaId);
  return withEmpresa;
}
