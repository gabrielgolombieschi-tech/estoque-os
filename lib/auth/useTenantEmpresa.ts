"use client";

import { useContext, useEffect, useState } from "react";
import { EmpresaContext } from "@/app/components/EmpresaProvider";
import { getCurrentTenantId } from "@/lib/auth/tenant";

export function useTenantEmpresa() {
  const empresaCtx = useContext(EmpresaContext);
  const [tenantId, setTenantId] = useState<string | null>(null);
  const [tenantLoading, setTenantLoading] = useState(true);

  useEffect(() => {
    let active = true;

    (async () => {
      try {
        const id = await getCurrentTenantId();
        if (active) setTenantId(id);
      } catch {
        if (active) setTenantId(null);
      } finally {
        if (active) setTenantLoading(false);
      }
    })();

    return () => {
      active = false;
    };
  }, []);

  return {
    tenantId,
    empresaId: empresaCtx?.empresaId ?? null,
    loading: tenantLoading || (empresaCtx?.loading ?? false),
  };
}
