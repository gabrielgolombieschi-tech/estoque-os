"use client";

import type { ReactNode } from "react";
import { createContext, useMemo } from "react";
import { useTenantEmpresaContext, type EmpresaOption } from "@/lib/auth/TenantEmpresaProvider";

export type EmpresaContextValue = {
  empresaId: string | null;
  empresas: EmpresaOption[];
  setEmpresaId: (id: string) => void;
  loading: boolean;
  error: string | null;
};

export const EmpresaContext = createContext<EmpresaContextValue | null>(null);

export function EmpresaProvider({ children }: { children: ReactNode }) {
  const ctx = useTenantEmpresaContext();
  const value = useMemo<EmpresaContextValue>(
    () => ({
      empresaId: ctx.empresaId,
      empresas: ctx.empresas,
      setEmpresaId: (id: string) => {
        void ctx.setEmpresaId(id);
      },
      loading: ctx.loading || !ctx.empresaId,
      error: ctx.error,
    }),
    [ctx]
  );

  return <EmpresaContext.Provider value={value}>{children}</EmpresaContext.Provider>;
}
