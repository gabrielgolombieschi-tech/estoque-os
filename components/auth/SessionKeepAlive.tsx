
"use client";

import { useEffect, useMemo, useRef } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";

const KEEP_ALIVE_MS = 5 * 60 * 1000; // 5 minutos
const REFRESH_THRESHOLD_SEC = 15 * 60; // 15 minutos

function normalizeRole(role: string | null | undefined) {
  return typeof role === "string" ? role.trim().toUpperCase() : "";
}

export default function SessionKeepAlive() {
  const te = useTenantEmpresa();
  const papel = te.empresa?.papel ?? null;
  const isPainelTv = useMemo(() => normalizeRole(papel) === "PAINEL_TV", [papel]);
  const timerRef = useRef<NodeJS.Timeout | null>(null);

  async function checkAndRefresh() {
    const supabase = supabaseBrowser();
    const { data } = await supabase.auth.getSession();
    const session = data?.session;
    if (!session) return;
    const expiresAt = session.expires_at ? session.expires_at * 1000 : null;
    const now = Date.now();
    if (expiresAt && expiresAt - now <= REFRESH_THRESHOLD_SEC * 1000) {
      await supabase.auth.refreshSession();
      console.log("[SessionKeepAlive] refreshSession chamado para PAINEL_TV");
    }
  }

  useEffect(() => {
    if (!isPainelTv) return;
    let cancelled = false;
    function startInterval() {
      if (timerRef.current) clearInterval(timerRef.current);
      timerRef.current = setInterval(() => {
        if (!cancelled) checkAndRefresh();
      }, KEEP_ALIVE_MS);
    }
    checkAndRefresh(); // Checagem imediata ao mount
    startInterval();
    function onVisibilityChange() {
      if (document.visibilityState === "visible") {
        checkAndRefresh();
      }
    }
    document.addEventListener("visibilitychange", onVisibilityChange);
    return () => {
      cancelled = true;
      if (timerRef.current) clearInterval(timerRef.current);
      document.removeEventListener("visibilitychange", onVisibilityChange);
    };
  }, [isPainelTv]);

  return null;
}

