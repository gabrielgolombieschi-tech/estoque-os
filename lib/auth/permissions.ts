import type { SupabaseClient } from "@supabase/supabase-js";
import { buildCanManyPayload, mapCapabilities, type Capabilities } from "@/lib/auth/capabilities";
import { supabaseBrowser } from "@/lib/supabase/client";

let cachedCapabilities: Capabilities | null = null;

export async function loadUserCapabilities(
  supabase: SupabaseClient = supabaseBrowser()
): Promise<Capabilities | null> {
  if (cachedCapabilities) return cachedCapabilities;

  const payload = buildCanManyPayload();

  try {
    const { data, error } = await supabase.rpc("can_many", { p_pairs: payload });

    if (error) {
      const message = typeof error === "object" && error !== null ? (error.message ?? "") : String(error);

      // Common developer issue: missing migration that defines public.can_many
      if (message.toLowerCase().includes("could not find the function public.can_many")) {
        // Friendly warning with actionable next step; avoid noisy stack/error object in browser console.
        console.warn(
          "RPC 'can_many' não encontrada no banco. Verifique se as migrations foram aplicadas (supabase/migrations/20260206_can_many.sql). Menus serão carregados pelo client quando possível."
        );
        return null;
      }

      const errMsg = typeof error === "object" && error !== null
        ? (error.message ?? JSON.stringify(error, Object.getOwnPropertyNames(error)))
        : String(error);
      console.error("Erro ao carregar permissoes:", errMsg, { payload, rawError: error });
      return null;
    }

    cachedCapabilities = mapCapabilities(data as Record<string, boolean> | null);
    return cachedCapabilities;
  } catch (e) {
    console.error("Erro inesperado ao chamar RPC 'can_many'", e, { payload });
    return null;
  }
}

export function clearPermissionCache() {
  cachedCapabilities = null;
}
