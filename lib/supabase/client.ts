"use client";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

let browserClient: SupabaseClient | null = null;

export const supabaseBrowser = () => {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

  // Server-side: não tenta ler hash de URL
  if (typeof window === "undefined") {
    return createClient(url, anon);
  }

  if (!browserClient) {
    browserClient = createClient(url, anon, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true, // <- ISSO É O PONTO PRINCIPAL DO RECOVERY
      },
    });
  }

  return browserClient;
};


