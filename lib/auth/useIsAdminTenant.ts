"use client";

import { useIsAdminTenant as useIsAdminTenantCore } from "@/lib/auth/hooks";

// Back-compat wrapper: old call sites may pass tenantId; core reads it from context.
export function useIsAdminTenant(_tenantId?: string | null) {
  return useIsAdminTenantCore();
}
