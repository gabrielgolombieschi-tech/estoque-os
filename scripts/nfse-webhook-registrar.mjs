/**
 * Registra na Focus (homologacao) o gatilho "nfsen" apontando para a Edge
 * Function nfse-callback e guarda o id em c.empresa_fiscal. Usa a sessao do
 * usuario de e2e (.env.e2e.local) e as chaves publicas de .env.local.
 *
 *   node scripts/nfse-webhook-registrar.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createClient } from "@supabase/supabase-js";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
for (const arquivo of [".env.local", ".env.e2e.local"]) {
  const caminho = path.join(raiz, arquivo);
  if (!fs.existsSync(caminho)) continue;
  for (const linha of fs.readFileSync(caminho, "utf8").split(/\r?\n/)) {
    const par = linha.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (par && !process.env[par[1]]) process.env[par[1]] = par[2].replace(/^["']|["']$/g, "");
  }
}
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
if (!url || !anon) { console.error("NEXT_PUBLIC_SUPABASE_URL/ANON_KEY ausentes."); process.exit(1); }
const supabase = createClient(url, anon, { auth: { persistSession: false } });
const { error: loginError } = await supabase.auth.signInWithPassword({ email: process.env.E2E_EMAIL ?? "", password: process.env.E2E_PASSWORD ?? "" });
if (loginError) { console.error("login:", loginError.message); process.exit(1); }
const { data, error } = await supabase.functions.invoke("nfse-ciclo", { body: { acao: "REGISTRAR_WEBHOOK" } });
if (error) {
  let detalhe = error.message;
  try { detalhe = JSON.stringify(await error.context.json()); } catch { /* sem corpo */ }
  console.error("nfse-ciclo:", detalhe);
  process.exit(2);
}
console.log(JSON.stringify(data, null, 2));
