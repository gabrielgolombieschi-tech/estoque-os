"use client";

import type { ReactNode } from "react";
import { createContext, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { getCurrentTenantId } from "@/lib/auth/tenant";
import { getAllowedEmpresas, getStoredEmpresaId, setStoredEmpresaId, type EmpresaOption } from "@/lib/auth/empresa";

export type EmpresaContextValue = {
  empresaId: string | null;
  empresas: EmpresaOption[];
  setEmpresaId: (id: string) => void;
  loading: boolean;
  error: string | null;
};

export const EmpresaContext = createContext<EmpresaContextValue | null>(null);

export function EmpresaProvider({ children }: { children: ReactNode }) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const router = useRouter();
  const [empresaId, setEmpresaIdState] = useState<string | null>(null);
  const [empresas, setEmpresas] = useState<EmpresaOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  useEffect(() => {
    let active = true;

    (async () => {
      try {
        setLoading(true);
        setError(null);
        const { data: sessionData } = await supabase.auth.getSession();
        if (!sessionData.session?.user) {
          if (!active) return;
          setEmpresas([]);
          setEmpresaIdState(null);
          return;
        }
        const tenantId = await getCurrentTenantId();
        if (!active) return;
        if (!tenantId) {
          setEmpresas([]);
          setEmpresaIdState(null);
          setError("Tenant nao definido.");
          return;
        }

        const allowed = await getAllowedEmpresas(supabase, tenantId);
        if (!active) return;
        setEmpresas(allowed);

        if (allowed.length === 0) {
          setEmpresaIdState(null);
          setError("Sem acesso a empresas. Fale com o admin.");
          return;
        }

        const stored = getStoredEmpresaId();
        const match = stored ? allowed.find((empresa) => empresa.id === stored) : null;
        if (match) {
          setEmpresaIdState(match.id);
          return;
        }

        if (allowed.length === 1) {
          setStoredEmpresaId(allowed[0].id);
          setEmpresaIdState(allowed[0].id);
          return;
        }

        setEmpresaIdState(null);
      } catch (e: unknown) {
        if (!active) return;
        const message = e instanceof Error ? e.message : "Erro ao carregar empresas.";
        setError(message);
        setEmpresas([]);
        setEmpresaIdState(null);
      } finally {
        if (active) setLoading(false);
      }
    })();

    return () => {
      active = false;
    };
  }, [supabase, reloadKey]);

  useEffect(() => {
    const { data: sub } = supabase.auth.onAuthStateChange(() => {
      setReloadKey((prev) => prev + 1);
    });
    return () => {
      sub.subscription.unsubscribe();
    };
  }, [supabase]);

  useEffect(() => {
    if (!empresaId) return;
    let active = true;

    (async () => {
      const { error: rpcErr } = await supabase.rpc("set_current_empresa", {
        p_empresa_id: empresaId,
      });
      if (!active) return;
      if (rpcErr) {
        setError("Erro ao definir empresa atual.");
      } else {
        setError(null);
      }
    })();

    return () => {
      active = false;
    };
  }, [supabase, empresaId]);

  const setEmpresaId = useCallback(
    (id: string) => {
      if (!empresas.some((empresa) => empresa.id === id)) return;
      setStoredEmpresaId(id);
      setEmpresaIdState(id);
      router.refresh();
    },
    [router, empresas]
  );

  const value = useMemo(
    () => ({
      empresaId,
      empresas,
      setEmpresaId,
      loading,
      error,
    }),
    [empresaId, empresas, setEmpresaId, loading, error]
  );

  return <EmpresaContext.Provider value={value}>{children}</EmpresaContext.Provider>;
}
