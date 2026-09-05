import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-focus-webhook-token",
};

export function json(data: unknown, status = 200) {
  return Response.json(data, { status, headers: corsHeaders });
}

export function mensagemErro(cause: unknown) {
  if (cause instanceof Error) return cause.message;
  if (cause && typeof cause === "object" && "message" in cause) return String((cause as { message: unknown }).message);
  return "Falha inesperada no pipeline de NF-e.";
}

export function adminClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Configuração interna do Supabase ausente.");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

export function userClient(request: Request): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const authorization = request.headers.get("authorization");
  if (!url || !anon || !authorization) throw new Error("Sessão do usuário ausente.");
  return createClient(url, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
}

export function responderOptions(request: Request) {
  return request.method === "OPTIONS" ? new Response("ok", { headers: corsHeaders }) : null;
}

