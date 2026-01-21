"use client";

import { useEffect, useMemo } from "react";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";

const KEEP_ALIVE_MS = 7 * 60 * 1000;

function normalizeRole(role: string | null | undefined) {
  return typeof role === "string" ? role.trim().toUpperCase() : "";
}

export default function SessionKeepAlive() {
  const te = useTenantEmpresa();

  const isPainelTv = useMemo(() => normalizeRole(te.empresa?.papel) === "PAINEL_TV", [te.empresa?.papel]);

  useEffect(() => {
    if (!te.sessionUserId) return;
    if (!isPainelTv) return;

    const supabase = getSupabaseBrowser();
    let cancelled = false;

    const tick = async () => {
      if (cancelled) return;
      try {
        await supabase.auth.getSession();
      } catch {
        // ignore
      }

      try {
        await supabase.rpc("current_tenant_id");
      } catch {
        // ignore
      }

      try {
        await supabase.from("empresa_memberships").select("user_id").limit(1);
      } catch {
        // ignore
      }
    };

    void tick();
    const id = setInterval(() => void tick(), KEEP_ALIVE_MS);

    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [isPainelTv, te.sessionUserId]);

  return null;
}

