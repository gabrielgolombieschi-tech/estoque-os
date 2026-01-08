"use client";

import type { ReactNode } from "react";
import { usePermissions } from "@/components/auth/PermissionsProvider";

type CanProps = {
  perm: string;
  children: ReactNode;
  fallback?: ReactNode;
};

export function Can({ perm, children, fallback = null }: CanProps) {
  const { loading, has } = usePermissions();

  if (loading) return fallback;
  return has(perm) ? <>{children}</> : <>{fallback}</>;
}
