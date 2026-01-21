"use client";

import type { ReactNode } from "react";
import type { Capabilities } from "@/lib/auth/capabilities";
import { TenantEmpresaProvider } from "@/lib/auth/TenantEmpresaProvider";
import SessionKeepAlive from "@/components/auth/SessionKeepAlive";

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
    <TenantEmpresaProvider initialCapabilities={initialCapabilities} initialTenantId={initialTenantId}>
      <SessionKeepAlive />
      {children}
    </TenantEmpresaProvider>
  );
}
