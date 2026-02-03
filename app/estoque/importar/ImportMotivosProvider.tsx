"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";

export type MotivoCompra = {
  id: string;
  codigo: string;
  nome: string;
  requires_text: boolean;
  requires_os: boolean;
  aplica_em: "PRODUTO" | "SERVICO" | "AMBOS";
  favorito: boolean;
  ordem: number;
  qtd_usos_180d: number;
};

type MotivoRow = {
  id: string;
  codigo: string;
  nome: string;
  requires_text: boolean;
  requires_os: boolean;
  aplica_em: "PRODUTO" | "SERVICO" | "AMBOS";
  favorito?: boolean;
  ordem?: number;
  qtd_usos_180d?: number;
};

type MotivosApiResponse = { motivos?: MotivoRow[]; error?: string };

type ImportMotivosState = {
  motivos: MotivoCompra[];
  loading: boolean;
  error: string | null;
  reload: (opts?: { reason?: string }) => Promise<void>;
  setFavorito: (motivoId: string, favorito: boolean) => Promise<void>;
};

const ImportMotivosContext = createContext<ImportMotivosState | null>(null);

export function ImportMotivosProvider({ children }: { children: ReactNode }) {
  const { tenantId, sessionUserId } = useTenantEmpresa();
  const [state, setState] = useState<Omit<ImportMotivosState, "reload" | "setFavorito">>({
    motivos: [],
    loading: true,
    error: null,
  });

  const fetchMotivos = useCallback(async () => {
    if (!tenantId) {
      setState({ motivos: [], loading: true, error: null });
      return;
    }

    setState((prev) => ({ ...prev, loading: true, error: null }));

    // IMPORTANT: this screen is under Estoque, but the source table lives in schema f (Financeiro).
    // We load via an API route that uses the current auth session and enforces tenant scoping server-side.
    const supabase = getSupabaseBrowser();
    const { data: sess } = await supabase.auth.getSession();
    const token = sess.session?.access_token ?? null;
    if (!token || typeof sessionUserId !== "string") {
      setState({ motivos: [], loading: false, error: "Sessao expirada. Faca login novamente." });
      return;
    }

    const res = await fetch(`/api/estoque/motivos-compra?origem=XML_PRODUTO`, {
      headers: { authorization: `Bearer ${token}` },
    });

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
        favorito: Boolean((r as Partial<MotivoRow>).favorito),
        ordem: Number((r as Partial<MotivoRow>).ordem ?? 0) || 0,
        qtd_usos_180d: Number((r as Partial<MotivoRow>).qtd_usos_180d ?? 0) || 0,
      }))
      .filter((m) => m.id && m.codigo && m.nome);

    setState({ motivos, loading: false, error: null });
  }, [sessionUserId, tenantId]);

  useEffect(() => {
    let cancelled = false;

    const run = async () => {
      try {
        await fetchMotivos();
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
  }, [fetchMotivos]);

  const reload = useCallback(async (_opts?: { reason?: string }) => {
    void _opts;
    try {
      await fetchMotivos();
    } catch {
      // handled in fetchMotivos
    }
  }, [fetchMotivos]);

  const setFavorito = useCallback(
    async (motivoId: string, favorito: boolean) => {
      const id = String(motivoId ?? "").trim();
      if (!id) return;

      const supabase = getSupabaseBrowser();
      const { data: sess } = await supabase.auth.getSession();
      const token = sess.session?.access_token ?? null;
      if (!token || typeof sessionUserId !== "string") {
        setState((prev) => ({ ...prev, error: "Sessao expirada. Faca login novamente." }));
        return;
      }

      const res = await fetch(`/api/estoque/motivos-compra`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ id, favorito }),
      });

      if (!res.ok) {
        const json = (await res.json().catch(() => null)) as { error?: string } | null;
        const msg = typeof json?.error === "string" ? json.error : "Erro ao atualizar favorito.";
        setState((prev) => ({ ...prev, error: msg }));
        return;
      }

      // Reload to keep the base ordering consistent with server ranking.
      await fetchMotivos();
    },
    [fetchMotivos, sessionUserId]
  );

  const value = useMemo(() => ({ ...state, reload, setFavorito }), [reload, setFavorito, state]);
  return <ImportMotivosContext.Provider value={value}>{children}</ImportMotivosContext.Provider>;
}

export function useImportMotivos() {
  const ctx = useContext(ImportMotivosContext);
  if (!ctx) throw new Error("useImportMotivos must be used within ImportMotivosProvider");
  return ctx;
}
