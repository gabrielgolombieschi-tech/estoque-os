"use client";

import { useEffect, useRef, useState } from "react";
import { useTenantEmpresaContext } from "@/lib/auth/provider";
import { getSupabaseBrowser } from "@/lib/auth/supabase";

export function useTenantEmpresa() {
  return useTenantEmpresaContext();
}

type AdminState = {
  isAdmin: boolean;
  loading: boolean;
  tenantRole: string | null;
  error?: string;
};

export function useIsAdminTenant(): AdminState {
  const te = useTenantEmpresaContext();
  const requestIdRef = useRef(0);
  const [state, setState] = useState<AdminState>({ isAdmin: false, loading: true, tenantRole: null });

  // Reset only on real sign-out.
  useEffect(() => {
    if (te.sessionUserId !== null) return;
    const t = setTimeout(() => {
      setState({ isAdmin: false, loading: false, tenantRole: null });
    }, 0);
    return () => clearTimeout(t);
  }, [te.sessionUserId]);

  useEffect(() => {
    let active = true;

    const run = async () => {
      const supabase = getSupabaseBrowser();
      const requestId = ++requestIdRef.current;
      const isStale = () => requestIdRef.current !== requestId;

      if (te.sessionUserId === undefined) {
        if (active) setState((prev) => ({ ...prev, loading: true }));
        return;
      }

      if (!te.sessionUserId || !te.tenantId) {
        if (active) setState({ isAdmin: false, loading: false, tenantRole: null });
        return;
      }

      setState((prev) => ({ ...prev, loading: true, error: undefined }));

      const { data: usuarioRow, error: usuarioErr } = await supabase
        .schema("a")
        .from("usuario")
        .select("id")
        .eq("auth_user_id", te.sessionUserId)
        .eq("ativo", true)
        .is("deleted_at", null)
        .maybeSingle();

      if (!active || isStale()) return;

      if (usuarioErr || !usuarioRow?.id) {
        if (active) {
          setState({
            isAdmin: false,
            loading: false,
            tenantRole: null,
            error: usuarioErr?.message ?? "Usuario nao encontrado.",
          });
        }
        return;
      }

      const { data: utRow, error: utErr } = await supabase
        .schema("a")
        .from("usuario_tenant")
        .select("papel")
        .eq("usuario_id", usuarioRow.id)
        .eq("tenant_id", te.tenantId)
        .eq("ativo", true)
        .is("deleted_at", null)
        .in("papel", ["OWNER", "ADMIN"])
        .maybeSingle();

      if (!active || isStale()) return;

      if (utErr) {
        setState({ isAdmin: false, loading: false, tenantRole: null, error: utErr.message });
        return;
      }

      const nextIsAdmin = Boolean(utRow);
      setState({
        isAdmin: nextIsAdmin,
        loading: false,
        tenantRole: typeof utRow?.papel === "string" ? utRow.papel.toUpperCase() : null,
      });
    };

    void run();

    return () => {
      active = false;
    };
  }, [te.sessionUserId, te.tenantId]);

  return state;
}
