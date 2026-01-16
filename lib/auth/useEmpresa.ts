"use client";

import { useTenantEmpresaContext } from "@/lib/auth/TenantEmpresaProvider";

export function useEmpresa() {
  const ctx = useTenantEmpresaContext();

  // Compatibility shape with the old EmpresaProvider.
  return {
    empresaId: ctx.empresaId,
    empresas: ctx.empresas,
    setEmpresaId: (id: string) => {
      void ctx.setEmpresaId(id);
    },
    loading: ctx.loading || !ctx.empresaId,
    error: ctx.error,
  };
}
