/**
 * Libera um perfil de servico (NFS-e) para producao amarrado a uma homologacao
 * autorizada da mesma solicitacao (f.fn_perfil_operacao_nfse_liberar_producao).
 *
 *   node scripts/nfse-perfil-liberar.mjs SEG-NFSE-1406 <solicitacao_id> "justificativa"
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
const [codigo, solicitacaoId, justificativa] = process.argv.slice(2);
if (!codigo || !solicitacaoId) { console.error("Uso: node scripts/nfse-perfil-liberar.mjs <codigo> <solicitacao_id> [justificativa]"); process.exit(1); }
const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const { error: loginError } = await supabase.auth.signInWithPassword({ email: process.env.E2E_EMAIL ?? "", password: process.env.E2E_PASSWORD ?? "" });
if (loginError) { console.error("login:", loginError.message); process.exit(1); }
const { data: perfis } = await supabase.schema("f").from("perfil_operacao").select("id,codigo").eq("codigo", codigo).eq("modelo", "NFSE");
if (!perfis?.length) { console.error("perfil nao encontrado:", codigo); process.exit(1); }
const { data, error } = await supabase.schema("f").rpc("fn_perfil_operacao_nfse_liberar_producao", {
  p_perfil_id: perfis[0].id, p_solicitacao_id: solicitacaoId,
  p_justificativa: justificativa ?? `Liberacao para producao do perfil ${codigo} apos NFS-e autorizada em homologacao com os valores da matriz de agosto/2026; primeira NFS-e real assistida (OS 319), a ser cancelada em seguida.`,
  p_confirmacao: true,
});
if (error) { console.error("liberar:", error.message); process.exit(2); }
console.log(JSON.stringify(data, null, 2));
