"use client";

import type { ReactNode } from "react";
import { TenantEmpresaProvider, useTenantEmpresaContext } from "@/lib/auth/TenantEmpresaProvider";
import type { Capabilities, CapabilityKey } from "@/lib/auth/capabilities";

export type PermissionsContextValue = {
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

export function PermissionsProvider({
  children,
  initialCapabilities = null,
  initialTenantId = null,
}: {
  children: ReactNode;
  initialCapabilities?: Capabilities | null;
  initialTenantId?: string | null;
}) {
  // Compatibility wrapper: existing screens may still mount PermissionsProvider.
  // Source of truth remains TenantEmpresaProvider.
  return (
    <TenantEmpresaProvider initialCapabilities={initialCapabilities} initialTenantId={initialTenantId}>
      {children}
    </TenantEmpresaProvider>
  );
}

export function usePermissions(): PermissionsContextValue {
  const ctx = useTenantEmpresaContext();
  const booting = ctx.loading;
  const stillLoadingCaps = booting || ctx.capabilities === null;

  return {
    capabilities: ctx.capabilities,
    loading: stillLoadingCaps,
    loadingInitial: stillLoadingCaps,
    refreshing: ctx.refreshing,
    ready: !stillLoadingCaps && ctx.capabilities !== null,
    tenantId: ctx.tenantId,
    has: ctx.has,
    reload: ctx.reload,
    clear: ctx.clear,
  };
}
