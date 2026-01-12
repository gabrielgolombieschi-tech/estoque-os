"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { clearPermissionCache, loadUserCapabilities } from "@/lib/auth/permissions";
import { getCurrentTenantId } from "@/lib/auth/tenant";
import { ensureCurrentTenant } from "@/lib/tenant";
import { type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import { supabaseBrowser } from "@/lib/supabase/client";

type PermissionsContextValue = {
  capabilities: Capabilities | null;
  loading: boolean;
  loadingInitial: boolean;
  refreshing: boolean;
  ready: boolean;
  tenantId: string | null;
  has: (capability: CapabilityKey) => boolean | undefined;
  reload: () => Promise<void>;
  clear: () => void;
};

const PermissionsContext = createContext<PermissionsContextValue | null>(null);

type CachedPermissions = {
  userId: string;
  tenantId: string;
  capabilities: Capabilities;
};

const CACHE_LAST_KEY = "permissions_cache:last";
const cacheKeyFor = (userId: string, tenantId: string) => `permissions_cache:${userId}:${tenantId}`;

function readCache(key: string): Capabilities | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.sessionStorage.getItem(key);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? (parsed as Capabilities) : null;
  } catch {
    return null;
  }
}

function readLastCache(): CachedPermissions | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.sessionStorage.getItem(CACHE_LAST_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as CachedPermissions;
    if (!parsed?.userId || !parsed?.tenantId || !parsed?.capabilities) return null;
    return parsed;
  } catch {
    return null;
  }
}

function writeCache(userId: string, tenantId: string, capabilities: Capabilities) {
  if (typeof window === "undefined") return;
  try {
    window.sessionStorage.setItem(cacheKeyFor(userId, tenantId), JSON.stringify(capabilities));
    window.sessionStorage.setItem(
      CACHE_LAST_KEY,
      JSON.stringify({ userId, tenantId, capabilities })
    );
  } catch {
    // Ignore storage errors.
  }
}

export function PermissionsProvider({
  children,
  initialCapabilities = null,
  initialTenantId = null,
}: {
  children: ReactNode;
  initialCapabilities?: Capabilities | null;
  initialTenantId?: string | null;
}) {
  const lastCache = readLastCache();
  const [capabilities, setCapabilities] = useState<Capabilities | null>(
    initialCapabilities ?? lastCache?.capabilities ?? null
  );
  const [loading, setLoading] = useState(!lastCache && initialCapabilities == null);
  const [refreshing, setRefreshing] = useState(false);
  const [tenantId, setTenantId] = useState<string | null>(initialTenantId ?? lastCache?.tenantId ?? null);
  const userIdRef = useRef<string | null>(lastCache?.userId ?? null);
  const permissionsRef = useRef<Capabilities | null>(initialCapabilities ?? lastCache?.capabilities ?? null);
  const inflightRef = useRef<Promise<void> | null>(null);
  const inflightKeyRef = useRef<string | null>(null);

  const refreshPermissions = useCallback(
    async (opts?: { background?: boolean; userId?: string | null; tenantId?: string | null }) => {
      if (inflightRef.current) return inflightRef.current;
      const run = (async () => {
        const background = opts?.background ?? false;
        if (background) setRefreshing(true);
        else setLoading(true);

        try {
          const supabase = supabaseBrowser();
          let userId = opts?.userId ?? userIdRef.current;
          if (!userId) {
            const { data: sessionData } = await supabase.auth.getSession();
            userId = sessionData.session?.user?.id ?? null;
          }

          if (!userId) {
            clearPermissionCache();
            setCapabilities(null);
            setTenantId(null);
            return;
          }

          const tenantIdResolved = opts?.tenantId ?? (await ensureCurrentTenant(supabase));
          const inflightKey = `${userId}:${tenantIdResolved ?? "none"}`;
          if (inflightKeyRef.current && inflightKeyRef.current !== inflightKey) {
            inflightRef.current = null;
          }
          inflightKeyRef.current = inflightKey;
          setTenantId(tenantIdResolved);

          if (!tenantIdResolved) {
            return;
          }

          const prevUser = userIdRef.current;
          if (prevUser && prevUser !== userId) {
            clearPermissionCache();
          }
          userIdRef.current = userId;

          clearPermissionCache();
          const perms = await loadUserCapabilities(supabase);
          if (userIdRef.current !== userId) {
            return;
          }
          // If loadUserCapabilities failed (null), do not overwrite existing capabilities.
          if (perms) {
            setCapabilities(perms);
            writeCache(userId, tenantIdResolved, perms);
          } else {
            console.warn("loadUserCapabilities returned null; keeping existing capabilities");
          }
        } catch (e) {
          console.warn("Erro ao atualizar permissoes", e);
        } finally {
          setLoading(false);
          setRefreshing(false);
        }
      })();

      inflightRef.current = run.finally(() => {
        if (inflightRef.current === run) {
          inflightRef.current = null;
          inflightKeyRef.current = null;
        }
      });
      return inflightRef.current;
    },
    []
  );

  const reload = useCallback(async () => {
    const hasCache = capabilities !== null;
    await refreshPermissions({ background: hasCache });
  }, [capabilities, refreshPermissions]);

  useEffect(() => {
    permissionsRef.current = capabilities;
  }, [capabilities]);

  useEffect(() => {
    const supabase = supabaseBrowser();
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      const nextUserId = session?.user?.id ?? null;
      if (userIdRef.current !== nextUserId) {
        userIdRef.current = nextUserId;
        inflightRef.current = null;
        inflightKeyRef.current = null;
        if (!nextUserId) {
          clearPermissionCache();
          setCapabilities(null);
          setTenantId(null);
          setLoading(false);
          return;
        }
        setCapabilities(null);
        setTenantId(null);
        setLoading(permissionsRef.current === null);
        void refreshPermissions({ background: permissionsRef.current !== null, userId: nextUserId });
      }
    });

    return () => sub.subscription.unsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    let active = true;
    const init = async () => {
      try {
        const supabase = supabaseBrowser();
        let userId = userIdRef.current;
        if (!userId) {
          const { data: sessionData } = await supabase.auth.getSession();
          userId = sessionData.session?.user?.id ?? null;
          userIdRef.current = userId;
        }
        if (!active) return;

        userIdRef.current = userId;

        if (!userId) {
          setCapabilities(null);
          setTenantId(null);
          setLoading(false);
          return;
        }

        if (lastCache && lastCache.userId !== userId) {
          setCapabilities(null);
          setLoading(true);
        }

        const tenantIdResolved = await getCurrentTenantId();
        if (!active) return;
        setTenantId(tenantIdResolved);

        if (tenantIdResolved) {
          const key = cacheKeyFor(userId, tenantIdResolved);
          const cached = readCache(key);
          if (cached) {
            setCapabilities(cached);
            setLoading(false);
            void refreshPermissions({ background: true, userId, tenantId: tenantIdResolved });
            return;
          }
        }

        setCapabilities(null);
        setLoading(true);
        await refreshPermissions({ background: false, userId, tenantId: tenantIdResolved });
      } catch (e) {
        console.warn("Erro ao iniciar permissoes", e);
        setLoading(false);
      }
    };

    void init();
    return () => {
      active = false;
    };
  }, [refreshPermissions, lastCache]);

  const has = useCallback(
    (capability: CapabilityKey) => (capabilities === null ? undefined : capabilities[capability] ?? false),
    [capabilities]
  );
  const ready = capabilities !== null && tenantId !== null;
  const loadingInitial = loading && capabilities === null;

  const value = useMemo(
    () => ({
      capabilities,
      loading,
      loadingInitial,
      refreshing,
      ready,
      tenantId,
      has,
      reload,
      clear: () => {
        clearPermissionCache();
        setCapabilities(null);
        setTenantId(null);
        setLoading(false);
      },
    }),
    [capabilities, loading, loadingInitial, refreshing, ready, tenantId, has, reload]
  );

  return <PermissionsContext.Provider value={value}>{children}</PermissionsContext.Provider>;
}

export function usePermissions() {
  const ctx = useContext(PermissionsContext);
  if (!ctx) {
    throw new Error("usePermissions must be used within a PermissionsProvider");
  }
  return ctx;
}
