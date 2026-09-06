/**
 * Confirma um campo travado (CONFERIR_08_09) de um perfil de servico, com a
 * justificativa que registra a resposta do contador. Evento em
 * f.perfil_operacao_revisao_evento. Nao libera producao: isso continua exigindo
 * homologacao + fn_perfil_operacao_nfse_liberar_producao.
 *
 *   node scripts/nfse-perfil-confirmar-campo.mjs SEG-NFSE-1406 iss_retido_regra "Contador 06/09/2026: ..."
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
const [codigo, campo, justificativa] = process.argv.slice(2);
if (!codigo || !campo || !justificativa) { console.error("Uso: node scripts/nfse-perfil-confirmar-campo.mjs <codigo> <campo> <justificativa>"); process.exit(1); }

const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const { error: loginError } = await supabase.auth.signInWithPassword({ email: process.env.E2E_EMAIL ?? "", password: process.env.E2E_PASSWORD ?? "" });
if (loginError) { console.error("login:", loginError.message); process.exit(1); }
const { data: perfis, error: perfisError } = await supabase.schema("f").from("perfil_operacao").select("id,codigo,campos_conferir").eq("codigo", codigo).eq("modelo", "NFSE");
if (perfisError || !perfis?.length) { console.error("perfil nao encontrado:", perfisError?.message ?? codigo); process.exit(1); }
const { data, error } = await supabase.schema("f").rpc("fn_perfil_operacao_nfse_confirmar_campo", { p_perfil_id: perfis[0].id, p_campo: campo, p_justificativa: justificativa });
if (error) { console.error("confirmar:", error.message); process.exit(2); }
console.log(JSON.stringify({ perfil: codigo, ...data }, null, 2));
