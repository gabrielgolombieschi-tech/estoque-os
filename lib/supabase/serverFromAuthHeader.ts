import { createClient } from "@supabase/supabase-js";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

if (!supabaseUrl || !supabaseKey) {
  throw new Error("Variaveis do Supabase ausentes");
}

export function supabaseFromAuthHeader(req: Request) {
  const authorization = req.headers.get("authorization") ?? "";
  return createClient(supabaseUrl, supabaseKey, {
    auth: { persistSession: false },
    global: {
      headers: {
        Authorization: authorization,
      },
    },
  });
}

export const supabaseServerFromAuthHeader = supabaseFromAuthHeader;
