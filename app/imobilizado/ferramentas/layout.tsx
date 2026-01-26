"use client";

import type { ReactNode } from "react";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";

export default function FerramentasImobilizadoLayout({ children }: { children: ReactNode }) {
  const te = useTenantEmpresa();
  const { has, loading: permissionsLoading, ready } = usePermissions();

  if (te.error) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300 p-6">
        {te.error}
      </div>
    );
  }

  if (te.loading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando...</div>;
  }

  if (!te.tenantId || !te.empresaId) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando contexto...
      </div>
    );
  }

  if (!ready && permissionsLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando permissoes...
      </div>
    );
  }

  const canRead = has("imobilizado.read") === true || has("imobilizado.write") === true;
  if (!canRead) return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;

  return <>{children}</>;
}
