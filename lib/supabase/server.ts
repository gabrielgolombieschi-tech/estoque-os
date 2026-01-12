import { createClient } from "@supabase/supabase-js";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseKey) {
  throw new Error("Variáveis do Supabase ausentes");
}

export const supabaseServer = () => createClient(supabaseUrl, supabaseKey);

export const supabaseServerWithAuth = (accessToken: string) =>
  createClient(supabaseUrl, supabaseKey, {
    auth: { persistSession: false },
    global: {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    },
  });
