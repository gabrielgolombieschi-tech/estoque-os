"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { supabaseBrowser } from "@/lib/supabase/client";

let supabaseSingleton: SupabaseClient | null = null;

export function getSupabaseBrowser(): SupabaseClient {
  if (!supabaseSingleton) {
    supabaseSingleton = supabaseBrowser();
  }
  return supabaseSingleton;
}

