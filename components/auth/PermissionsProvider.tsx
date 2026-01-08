"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { clearPermissionCache, loadUserPermissions } from "@/lib/auth/permissions";
import { getCurrentTenantId } from "@/lib/auth/tenant";

type PermissionsContextValue = {
  permissions: string[];
  loading: boolean;
  tenantId: string | null;
  has: (permission: string) => boolean;
  reload: () => Promise<void>;
  clear: () => void;
};

const PermissionsContext = createContext<PermissionsContextValue | null>(null);

export function PermissionsProvider({ children }: { children: ReactNode }) {
  const [permissions, setPermissions] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [tenantId, setTenantId] = useState<string | null>(null);

  const reload = useCallback(async () => {
    setLoading(true);
    clearPermissionCache();
    const [permsResult, tenantResult] = await Promise.allSettled([
      loadUserPermissions(),
      getCurrentTenantId(),
    ]);
    if (permsResult.status === "fulfilled") {
      setPermissions(permsResult.value);
    } else {
      console.error(permsResult.reason);
      setPermissions([]);
    }
    if (tenantResult.status === "fulfilled") {
      setTenantId(tenantResult.value);
    } else {
      const reason = tenantResult.reason;
      if (reason instanceof Error) {
        console.error("Erro ao carregar tenant", reason);
      } else if (typeof reason === "string" && reason.trim()) {
        console.error("Erro ao carregar tenant", reason);
      }
      setTenantId(null);
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  const has = useCallback((permission: string) => permissions.includes(permission), [permissions]);

  const value = useMemo(
    () => ({
      permissions,
      loading,
      tenantId,
      has,
      reload,
      clear: () => {
        clearPermissionCache();
        setPermissions([]);
        setTenantId(null);
      },
    }),
    [permissions, loading, tenantId, has, reload]
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
