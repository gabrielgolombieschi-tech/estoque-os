"use client";

import { useEffect, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import type { Session } from "@supabase/supabase-js";

export function useSessionReady() {
  const [session, setSession] = useState<Session | null>(null);
  const [sessionReady, setSessionReady] = useState(false);

  useEffect(() => {
    const supabase = supabaseBrowser();
    let active = true;

    const init = async () => {
      const { data } = await supabase.auth.getSession();
      if (!active) return;
      setSession(data.session ?? null);
      setSessionReady(true);
    };

    void init();

    const { data: sub } = supabase.auth.onAuthStateChange((_evt, next) => {
      if (!active) return;
      setSession(next ?? null);
      setSessionReady(true);
    });

    return () => {
      active = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  return { session, sessionReady };
}
