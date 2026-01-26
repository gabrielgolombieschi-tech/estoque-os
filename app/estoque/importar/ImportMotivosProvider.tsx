"use client";

import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";

export type MotivoCompra = {
  id: string;
  codigo: string;
  nome: string;
  requires_text: boolean;
  requires_os: boolean;
  aplica_em: "PRODUTO" | "SERVICO" | "AMBOS";
};

type MotivoRow = {
  id: string;
  codigo: string;
  nome: string;
  requires_text: boolean;
  requires_os: boolean;
  aplica_em: "PRODUTO" | "SERVICO" | "AMBOS";
};

type MotivosApiResponse = { motivos?: MotivoRow[]; error?: string };

type ImportMotivosState = {
  motivos: MotivoCompra[];
  loading: boolean;
  error: string | null;
};

const ImportMotivosContext = createContext<ImportMotivosState | null>(null);

export function ImportMotivosProvider({ children }: { children: ReactNode }) {
  const { tenantId, sessionUserId } = useTenantEmpresa();
  const [state, setState] = useState<ImportMotivosState>({ motivos: [], loading: true, error: null });

  useEffect(() => {
    let cancelled = false;

    const run = async () => {
      if (!tenantId) {
        setState({ motivos: [], loading: true, error: null });
        return;
      }

      setState((prev) => ({ ...prev, loading: true, error: null }));

      try {
        // IMPORTANT: this screen is under Estoque, but the source table lives in schema f (Financeiro).
        // In some DBs, RLS for f.motivo_compra is restricted to financeiro perms, causing an empty list.
        // We load via a secured API route that validates the user and uses service-role for the read.
        const supabase = getSupabaseBrowser();
        const { data: sess } = await supabase.auth.getSession();
        const token = sess.session?.access_token ?? null;
        if (!token || typeof sessionUserId !== "string") {
          setState({ motivos: [], loading: false, error: "Sessao expirada. Faca login novamente." });
          return;
        }

        const res = await fetch(`/api/estoque/motivos-compra?origem=XML_PRODUTO`,
          {
            headers: { authorization: `Bearer ${token}` },
          }
        );

        const json = (await res.json().catch(() => null)) as MotivosApiResponse | null;
        if (!res.ok) {
          const msg = typeof json?.error === "string" ? json.error : "Erro ao carregar motivos.";
          setState({ motivos: [], loading: false, error: msg });
          return;
        }

        const data = Array.isArray(json?.motivos) ? json!.motivos! : [];
        const motivos = (data ?? [])
          .map((r) => ({
            id: String(r.id),
            codigo: String(r.codigo ?? ""),
            nome: String(r.nome ?? ""),
            requires_text: Boolean(r.requires_text),
            requires_os: Boolean(r.requires_os),
            aplica_em: (String((r as Partial<MotivoRow>).aplica_em ?? "AMBOS").toUpperCase() as MotivoCompra["aplica_em"]),
          }))
          .filter((m) => m.id && m.codigo && m.nome);

        setState({ motivos, loading: false, error: null });
      } catch (e: unknown) {
        if (cancelled) return;
        const message = e instanceof Error ? e.message : "Erro ao carregar motivos.";
        setState({ motivos: [], loading: false, error: message });
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [sessionUserId, tenantId]);

  const value = useMemo(() => state, [state]);
  return <ImportMotivosContext.Provider value={value}>{children}</ImportMotivosContext.Provider>;
}

export function useImportMotivos() {
  const ctx = useContext(ImportMotivosContext);
  if (!ctx) throw new Error("useImportMotivos must be used within ImportMotivosProvider");
  return ctx;
}
