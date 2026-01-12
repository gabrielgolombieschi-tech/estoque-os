"use client";

import type { ReactNode } from "react";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import type { CapabilityKey } from "@/lib/auth/capabilities";

type CanProps = {
  perm: CapabilityKey | string;
  children: ReactNode;
  fallback?: ReactNode;
};

export function Can({ perm, children, fallback = null }: CanProps) {
  const { loadingInitial, loading, has } = usePermissions();

  const allowed = has(perm as unknown as CapabilityKey);
  if (loadingInitial || allowed === undefined) return fallback;
  return allowed ? <>{children}</> : <>{fallback}</>;
}
