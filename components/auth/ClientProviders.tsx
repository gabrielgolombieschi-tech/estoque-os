"use client";

import type { ReactNode } from "react";
import { PermissionsProvider } from "@/components/auth/PermissionsProvider";
import type { Capabilities } from "@/lib/auth/capabilities";

type Props = {
  children: ReactNode;
  initialCapabilities?: Capabilities | null;
  initialTenantId?: string | null;
};

export default function ClientProviders({
  children,
  initialCapabilities = null,
  initialTenantId = null,
}: Props) {
  return (
    <PermissionsProvider initialCapabilities={initialCapabilities} initialTenantId={initialTenantId}>
      {children}
    </PermissionsProvider>
  );
}
