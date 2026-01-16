"use client";

import { useTenantEmpresaContext } from "@/lib/auth/TenantEmpresaProvider";

export function useTenantEmpresa() {
  const ctx = useTenantEmpresaContext();
  const booting = ctx.loading;
  return {
    tenantId: ctx.tenantId,
    empresaId: ctx.empresaId,
    loading: booting,
    error: ctx.error,
  };
}
