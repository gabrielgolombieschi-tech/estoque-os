"use client";

import type { ReactNode } from "react";
import { useTenantEmpresa, useIsAdminTenant } from "@/lib/auth/hooks";
import type { CapabilityKey } from "@/lib/auth/capabilities";

export default function RequireCap({
  cap,
  children,
  requireAdminTenant = false,
}: {
  cap: CapabilityKey | CapabilityKey[];
  children: ReactNode;
  requireAdminTenant?: boolean;
}) {
  const te = useTenantEmpresa();
  const { isAdmin: isAdminTenant, loading: adminLoading } = useIsAdminTenant();

  if (te.loading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando...
      </div>
    );
  }

  if (te.capabilities === null) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando permissões...
      </div>
    );
  }

  const has = te.has;
  const capsOk = Array.isArray(cap) ? cap.every((k) => has(k) === true) : has(cap) === true;

  if (requireAdminTenant) {
    if (adminLoading) {
      return (
        <div className="min-h-screen flex items-center justify-center text-zinc-300">
          Carregando...
        </div>
      );
    }

    if (!isAdminTenant) {
      return (
        <div className="min-h-screen flex items-center justify-center text-zinc-300">
          Acesso negado.
        </div>
      );
    }
  }

  if (!capsOk) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Acesso negado.
      </div>
    );
  }

  return <>{children}</>;
}

