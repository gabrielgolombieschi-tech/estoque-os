"use client";

import { useTenantEmpresaContext } from "@/lib/auth/TenantEmpresaProvider";

export function useEmpresa() {
  const ctx = useTenantEmpresaContext();

  // Compatibility shape with the old EmpresaProvider.
  return {
    empresaId: ctx.empresaId,
    empresas: ctx.empresas,
    setEmpresaId: (id: string) => {
      void ctx.setEmpresaId(id).catch(() => undefined);
    },
    loading: ctx.loading || !ctx.empresaId,
    error: ctx.error,
  };
}
