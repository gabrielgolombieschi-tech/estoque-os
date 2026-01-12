"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { clearPermissionCache, loadUserPermissions } from "@/lib/auth/permissions";
import { getCurrentTenantId } from "@/lib/auth/tenant";
import { supabaseBrowser } from "@/lib/supabase/client";

type PermissionsContextValue = {
  permissions: string[] | null;
  loading: boolean;
  refreshing: boolean;
  ready: boolean;
  tenantId: string | null;
  has: (permission: string) => boolean;
  reload: () => Promise<void>;
  clear: () => void;
};

const PermissionsContext = createContext<PermissionsContextValue | null>(null);

type CachedPermissions = {
  userId: string;
  tenantId: string;
  permissions: string[];
};

const CACHE_LAST_KEY = "permissions_cache:last";
const cacheKeyFor = (userId: string, tenantId: string) => `permissions_cache:${userId}:${tenantId}`;

function readCache(key: string): string[] | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.sessionStorage.getItem(key);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as string[]) : null;
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
    if (!parsed?.userId || !parsed?.tenantId || !Array.isArray(parsed.permissions)) return null;
    return parsed;
  } catch {
    return null;
  }
}

function writeCache(userId: string, tenantId: string, permissions: string[]) {
  if (typeof window === "undefined") return;
  try {
    window.sessionStorage.setItem(cacheKeyFor(userId, tenantId), JSON.stringify(permissions));
    window.sessionStorage.setItem(
      CACHE_LAST_KEY,
      JSON.stringify({ userId, tenantId, permissions })
    );
  } catch {
    // Ignore storage errors.
  }
}

export function PermissionsProvider({ children }: { children: ReactNode }) {
  const lastCache = readLastCache();
  const [permissions, setPermissions] = useState<string[] | null>(lastCache?.permissions ?? null);
  const [loading, setLoading] = useState(!lastCache);
  const [refreshing, setRefreshing] = useState(false);
  const [tenantId, setTenantId] = useState<string | null>(lastCache?.tenantId ?? null);
  const userIdRef = useRef<string | null>(lastCache?.userId ?? null);
  const permissionsRef = useRef<string[] | null>(lastCache?.permissions ?? null);
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
            setPermissions(null);
            setTenantId(null);
            return;
          }

          const tenantIdResolved = opts?.tenantId ?? (await getCurrentTenantId());
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
          const perms = await loadUserPermissions();
          if (userIdRef.current !== userId) {
            return;
          }
          setPermissions(perms);
          writeCache(userId, tenantIdResolved, perms);
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
    const hasCache = permissions !== null;
    await refreshPermissions({ background: hasCache });
  }, [permissions, refreshPermissions]);

  useEffect(() => {
    permissionsRef.current = permissions;
  }, [permissions]);

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
          setPermissions(null);
          setTenantId(null);
          setLoading(false);
          return;
        }
        setPermissions(null);
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
          setPermissions(null);
          setTenantId(null);
          setLoading(false);
          return;
        }

        if (lastCache && lastCache.userId !== userId) {
          setPermissions(null);
          setLoading(true);
        }

        const tenantIdResolved = await getCurrentTenantId();
        if (!active) return;
        setTenantId(tenantIdResolved);

        if (tenantIdResolved) {
          const key = cacheKeyFor(userId, tenantIdResolved);
          const cached = readCache(key);
          if (cached) {
            setPermissions(cached);
            setLoading(false);
            void refreshPermissions({ background: true, userId, tenantId: tenantIdResolved });
            return;
          }
        }

        setPermissions(null);
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

  const has = useCallback((permission: string) => permissions?.includes(permission) ?? false, [permissions]);
  const ready = permissions !== null && tenantId !== null;

  const value = useMemo(
    () => ({
      permissions,
      loading,
      refreshing,
      ready,
      tenantId,
      has,
      reload,
      clear: () => {
        clearPermissionCache();
        setPermissions(null);
        setTenantId(null);
        setLoading(false);
      },
    }),
    [permissions, loading, refreshing, ready, tenantId, has, reload]
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
