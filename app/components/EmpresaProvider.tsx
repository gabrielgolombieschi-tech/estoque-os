"use client";

import type { ReactNode } from "react";
import { createContext, useMemo } from "react";
import { useTenantEmpresaContext } from "@/lib/auth/TenantEmpresaProvider";
import type { EmpresaInfo as EmpresaOption } from "@/lib/auth/types";

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
        void ctx.setEmpresaId(id).catch(() => undefined);
      },
      loading: ctx.loading,
      error: ctx.error,
    }),
    [ctx]
  );

  return <EmpresaContext.Provider value={value}>{children}</EmpresaContext.Provider>;
}
