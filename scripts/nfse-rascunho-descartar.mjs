/**
 * Descarta (cancela) os rascunhos de solicitacao de NFS-e de uma OS que ainda
 * nao foram preparados/enviados, devolvendo a reserva do saldo. Usa a sessao
 * do usuario de e2e e a RPC f.fn_solicitacao_nfe_cancelar_rascunho.
 *
 *   node scripts/nfse-rascunho-descartar.mjs <os_id> [motivo]
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
const osId = process.argv[2];
if (!osId) { console.error("Uso: node scripts/nfse-rascunho-descartar.mjs <os_id> [motivo]"); process.exit(1); }
const motivo = process.argv[3] ?? "Rascunho de teste da conferencia descartado (perfis de servico 06/09/2026)";

const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const { error: loginError } = await supabase.auth.signInWithPassword({ email: process.env.E2E_EMAIL ?? "", password: process.env.E2E_PASSWORD ?? "" });
if (loginError) { console.error("login:", loginError.message); process.exit(1); }
const { data: itens, error: itensError } = await supabase.schema("f").from("solicitacao_item").select("solicitacao_id").eq("origem_id", String(osId)).eq("modelo", "NFSE");
if (itensError) { console.error("itens:", itensError.message); process.exit(1); }
const ids = [...new Set((itens ?? []).map((i) => i.solicitacao_id))];
if (!ids.length) { console.log("nenhuma solicitacao de NFS-e para a OS", osId); process.exit(0); }
const { data: sols, error: solsError } = await supabase.schema("f").from("solicitacao_faturamento").select("id,status,created_at").in("id", ids).in("status", ["RASCUNHO", "PREVIA", "APROVADA"]);
if (solsError) { console.error("solicitacoes:", solsError.message); process.exit(1); }
if (!sols?.length) { console.log("nenhum rascunho aberto para a OS", osId); process.exit(0); }
for (const sol of sols) {
  const { data: emissoes } = await supabase.schema("f").from("documento_fiscal_emissao").select("status").eq("solicitacao_id", sol.id);
  if ((emissoes ?? []).some((e) => !["RASCUNHO", "REJEITADA", "ERRO"].includes(e.status))) {
    console.log("pulando", sol.id, "(emissao em andamento ou autorizada; use o abandono na tela)");
    continue;
  }
  const { error } = await supabase.schema("f").rpc("fn_solicitacao_nfe_cancelar_rascunho", { p_solicitacao_id: sol.id, p_motivo: motivo });
  console.log(error ? `erro ${sol.id}: ${error.message}` : `cancelada ${sol.id} (${sol.status}, ${sol.created_at})`);
}
