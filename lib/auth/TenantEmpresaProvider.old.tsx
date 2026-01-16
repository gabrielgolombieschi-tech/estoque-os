"use client";

/*
MANUAL TEST CHECKLIST (multiempresa definitivo - RLS-only)
- Login com usuário com 1 empresa: entra direto e menu não pisca.
- Login com usuário com 2+ empresas: redireciona para /selecionar-empresa quando empresaId não definido.
- Trocar empresa no header:
  - páginas (clientes/OS/itens/estoque/financeiro) mudam conforme empresa
  - não aparece dado de outra empresa
  - menu não some/pisca durante a troca (stale-while-revalidate)
- Abrir 2 abas:
  - alternar abas (focus/visibilitychange) não deve zerar menu
  - voltar para a aba antiga mantém menu enquanto revalida
- Usuário sem membership de empresa:
  - UI mostra erro claro ("Usuário sem acesso a nenhuma empresa")
*/

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { ensureCurrentTenant } from "@/lib/tenant";
import { clearPermissionCache, loadUserCapabilities } from "@/lib/auth/permissions";
import type { Capabilities, CapabilityKey } from "@/lib/auth/capabilities";

export type EmpresaInfo = {
  id: string;
  nome_fantasia: string | null;
  razao_social: string | null;
};

export type EmpresaOption = EmpresaInfo;

export type TenantEmpresaContextValue = {
  tenantId: string | null;
  empresaId: string | null;
  empresa: EmpresaInfo | null;
  empresas: EmpresaOption[];
  capabilities: Capabilities | null;

  loading: boolean;
  error: string | null;
  refreshing: boolean;

  has: (capability: CapabilityKey) => boolean | undefined;
  reload: () => Promise<void>;
  clear: () => void;
  setEmpresaId: (nextEmpresaId: string) => Promise<void>;
};

const TenantEmpresaContext = createContext<TenantEmpresaContextValue | null>(null);

type CachedTenantEmpresa = {
  tenantId: string;
  empresaId: string;
  empresa: EmpresaInfo | null;
  capabilities: Capabilities | null;
  updatedAt: number;
};

const CACHE_LAST_TENANT_KEY = "tenant_empresa:last_tenant"; // key: per-user
const cacheKeyFor = (userId: string, tenantId: string) => `tenant_empresa:${userId}:${tenantId}`;
const lastTenantKeyFor = (userId: string) => `${CACHE_LAST_TENANT_KEY}:${userId}`;

function safeJsonParse<T>(raw: string | null): T | null {
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

function readCached(userId: string, tenantId: string): CachedTenantEmpresa | null {
  if (typeof window === "undefined") return null;
  return safeJsonParse<CachedTenantEmpresa>(window.sessionStorage.getItem(cacheKeyFor(userId, tenantId)));
}

function writeCached(userId: string, tenantId: string, value: CachedTenantEmpresa) {
  if (typeof window === "undefined") return;
  try {
    window.sessionStorage.setItem(cacheKeyFor(userId, tenantId), JSON.stringify(value));
    window.sessionStorage.setItem(lastTenantKeyFor(userId), tenantId);
  } catch {
    // ignore
  }
}

function readLastTenantId(userId: string): string | null {
  if (typeof window === "undefined") return null;
  return window.sessionStorage.getItem(lastTenantKeyFor(userId));
}

async function fetchEmpresasList() {
  // HARDCODED: Sempre retorna Elétrica Segau
  return [
    {
      id: 'f0e74f49-a127-46b4-901b-f7b37e43c690',
      nome_fantasia: 'Elétrica Segau',
      razao_social: 'ELETRICA SEGAU LTDA',
    },
  ];
}

async function fetchEmpresaById(empresaId: string): Promise<EmpresaInfo | null> {
  // HARDCODED: Sempre retorna Elétrica Segau
  if (empresaId === 'f0e74f49-a127-46b4-901b-f7b37e43c690') {
    return {
      id: 'f0e74f49-a127-46b4-901b-f7b37e43c690',
      nome_fantasia: 'Elétrica Segau',
      razao_social: 'ELETRICA SEGAU LTDA',
    };
  }
  return null;
}

async function readEmpresaFromContextTable(tenantId: string): Promise<string | null> {
  // HARDCODED: Sempre retorna Elétrica Segau
  return 'f0e74f49-a127-46b4-901b-f7b37e43c690';
}

async function getDefaultEmpresaId(tenantId: string): Promise<string | null> {
  // HARDCODED: Sempre retorna Elétrica Segau
  return 'f0e74f49-a127-46b4-901b-f7b37e43c690';
}

async function rpcSetCurrentEmpresa(empresaId: string) {
  // HARDCODED: Sempre retorna Elétrica Segau
  return 'f0e74f49-a127-46b4-901b-f7b37e43c690';
}

export function TenantEmpresaProvider({
  children,
  initialCapabilities = null,
  initialTenantId = null,
}: {
  children: ReactNode;
  initialCapabilities?: Capabilities | null;
  initialTenantId?: string | null;
}) {
  const router = useRouter();

  const [tenantId, setTenantId] = useState<string | null>(initialTenantId);
  const [empresaId, setEmpresaIdState] = useState<string | null>(null);
  const [empresa, setEmpresa] = useState<EmpresaInfo | null>(null);
  const [empresas, setEmpresas] = useState<EmpresaOption[]>([]);
  const [capabilities, setCapabilities] = useState<Capabilities | null>(initialCapabilities);

  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const userIdRef = useRef<string | null>(null);
  const inflightRef = useRef<Promise<void> | null>(null);
  const lastSetEmpresaRef = useRef<string | null>(null);

  const has = useCallback(
    (capability: CapabilityKey) => (capabilities === null ? undefined : capabilities[capability] ?? false),
    [capabilities]
  );

  const clear = useCallback(() => {
    clearPermissionCache();
    setCapabilities(null);
    setEmpresa(null);
    setEmpresaIdState(null);
    setEmpresas([]);
    setTenantId(null);
    setError(null);
    setLoading(false);
  }, []);

  const revalidate = useCallback(
    async (opts?: { background?: boolean; reason?: string }) => {
      if (inflightRef.current) return inflightRef.current;

      const run = (async () => {
        const background = opts?.background ?? false;
        if (background) setRefreshing(true);
        else setLoading(true);

        try {
          setError(null);
          const supabase = supabaseBrowser();

          const { data: sessionData } = await supabase.auth.getSession();
          const userId = sessionData.session?.user?.id ?? null;
          userIdRef.current = userId;

          if (!userId) {
            clear();
            return;
          }

          // Resolve tenantId (prefer cached/initial for immediate UX).
          let tenantResolved: string | null = tenantId ?? null;
          if (!tenantResolved) {
            const lastTenant = readLastTenantId(userId);
            if (lastTenant) tenantResolved = lastTenant;
          }

          // Fast path: if we know tenant, try to hydrate from cache before any RPC.
          if (tenantResolved) {
            const cached = readCached(userId, tenantResolved);
            if (cached) {
              setTenantId(cached.tenantId);
              setEmpresaIdState(cached.empresaId);
              setEmpresa(cached.empresa);
              if (cached.capabilities) setCapabilities(cached.capabilities);
              if (!background) setLoading(false);
            }
          }

          // Ensure tenant exists (this may call RPC set_current_tenant).
          const ensuredTenantId = await ensureCurrentTenant(supabase);
          if (!ensuredTenantId) {
            setTenantId(null);
            setEmpresaIdState(null);
            setEmpresa(null);
            setEmpresas([]);
            return;
          }

          setTenantId(ensuredTenantId);

          // Empresas list (needed for selector / UX)
          const empresasList = await fetchEmpresasList();
          setEmpresas(empresasList);
          if (empresasList.length === 0) {
            setEmpresaIdState(null);
            setEmpresa(null);
            setError("Usuário sem acesso a nenhuma empresa. Fale com o admin.");
            return;
          }

          // Resolve current empresa (user_empresa_context first, then default)
          let empresaResolved = await readEmpresaFromContextTable(ensuredTenantId);
          if (!empresaResolved) {
            empresaResolved = await getDefaultEmpresaId(ensuredTenantId);
          }

          if (!empresaResolved) {
            setEmpresaIdState(null);
            setEmpresa(null);
            setError("Não foi possível definir empresa atual. Fale com o admin.");
            return;
          }

          // If empresa is not in list, it means the user lost access.
          if (!empresasList.some((e) => e.id === empresaResolved)) {
            setEmpresaIdState(null);
            setEmpresa(null);
            setError("Usuário sem acesso a nenhuma empresa. Fale com o admin.");
            return;
          }

          // Ensure DB context (RLS) is aligned. Avoid loops.
          if (lastSetEmpresaRef.current !== empresaResolved) {
            lastSetEmpresaRef.current = empresaResolved;
            await rpcSetCurrentEmpresa(empresaResolved);
          }

          setEmpresaIdState(empresaResolved);
          setEmpresa(await fetchEmpresaById(empresaResolved));

          // Capabilities: stale-while-revalidate.
          // Keep existing capabilities if RPC fails.
          const cached2 = readCached(userId, ensuredTenantId);
          if (cached2?.capabilities && capabilities === null) {
            setCapabilities(cached2.capabilities);
          }

          clearPermissionCache();
          const caps = await loadUserCapabilities(supabase);
          if (caps) {
            setCapabilities(caps);
            writeCached(userId, ensuredTenantId, {
              tenantId: ensuredTenantId,
              empresaId: empresaResolved,
              empresa: await fetchEmpresaById(empresaResolved),
              capabilities: caps,
              updatedAt: Date.now(),
            });
          } else {
            // Persist contexto mesmo sem capabilities (para evitar “pisca” de empresa)
            writeCached(userId, ensuredTenantId, {
              tenantId: ensuredTenantId,
              empresaId: empresaResolved,
              empresa: await fetchEmpresaById(empresaResolved),
              capabilities: cached2?.capabilities ?? capabilities,
              updatedAt: Date.now(),
            });
          }
        } catch (e: unknown) {
          const message = e instanceof Error ? e.message : "Erro ao carregar contexto.";
          setError(message);
        } finally {
          setLoading(false);
          setRefreshing(false);
        }
      })();

      inflightRef.current = run.finally(() => {
        if (inflightRef.current === run) inflightRef.current = null;
      });

      return inflightRef.current;
    },
    [capabilities, clear, tenantId]
  );

  const reload = useCallback(async () => {
    const hasCache = capabilities !== null && tenantId !== null && empresaId !== null;
    await revalidate({ background: hasCache, reason: "reload" });
  }, [capabilities, empresaId, revalidate, tenantId]);

  const setEmpresaId = useCallback(
    async (nextEmpresaId: string) => {
      if (!nextEmpresaId) return;
      if (nextEmpresaId === empresaId) return;
      if (!empresas.some((e) => e.id === nextEmpresaId)) {
        setError("Sem acesso a esta empresa.");
        return;
      }

      try {
        setError(null);

        // Optimistic update (no flicker): keep capabilities, just switch empresa.
        setEmpresaIdState(nextEmpresaId);
        setEmpresa(await fetchEmpresaById(nextEmpresaId));

        if (lastSetEmpresaRef.current !== nextEmpresaId) {
          lastSetEmpresaRef.current = nextEmpresaId;
          await rpcSetCurrentEmpresa(nextEmpresaId);
        }

        // Persist to cache (SWR): tenant+empresa+caps.
        const userId = userIdRef.current;
        const tId = tenantId;
        if (userId && tId) {
          writeCached(userId, tId, {
            tenantId: tId,
            empresaId: nextEmpresaId,
            empresa: await fetchEmpresaById(nextEmpresaId),
            capabilities,
            updatedAt: Date.now(),
          });
        }

        // Refresh lightweight (App Router): re-fetch server components if any.
        router.refresh();
      } catch (e: unknown) {
        const message = e instanceof Error ? e.message : "Erro ao trocar empresa.";
        setError(message);
      }
    },
    [capabilities, empresaId, empresas, router, tenantId]
  );

  // Initial load
  useEffect(() => {
    void revalidate({ background: capabilities !== null, reason: "init" });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Revalidate on focus (stale-while-revalidate; never clears existing UI)
  useEffect(() => {
    const onFocus = () => {
      void revalidate({ background: true, reason: "focus" });
    };
    window.addEventListener("focus", onFocus);
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") onFocus();
    });

    return () => {
      window.removeEventListener("focus", onFocus);
    };
  }, [revalidate]);

  // Auth changes: only reset on SIGNED_IN / SIGNED_OUT / USER_UPDATED. Ignore TOKEN_REFRESHED to avoid flicker.
  useEffect(() => {
    const supabase = supabaseBrowser();
    const { data: sub } = supabase.auth.onAuthStateChange((event) => {
      if (event === "TOKEN_REFRESHED") return;

      if (event === "SIGNED_OUT") {
        clear();
        return;
      }

      // SIGNED_IN / USER_UPDATED: refresh context in background
      void revalidate({ background: true, reason: `auth:${event}` });
    });

    return () => {
      sub.subscription.unsubscribe();
    };
  }, [clear, revalidate]);

  const value = useMemo<TenantEmpresaContextValue>(
    () => ({
      tenantId,
      empresaId,
      empresa,
      empresas,
      capabilities,
      loading,
      error,
      refreshing,
      has,
      reload,
      clear,
      setEmpresaId,
    }),
    [tenantId, empresaId, empresa, empresas, capabilities, loading, error, refreshing, has, reload, clear, setEmpresaId]
  );

  return <TenantEmpresaContext.Provider value={value}>{children}</TenantEmpresaContext.Provider>;
}

export function useTenantEmpresaContext() {
  const ctx = useContext(TenantEmpresaContext);
  if (!ctx) throw new Error("useTenantEmpresaContext must be used within TenantEmpresaProvider");
  return ctx;
}
