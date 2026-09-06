/**
 * Registra a revisao fiscal de um perfil de NF-e (IBS/CBS da transicao 2026)
 * pela RPC f.fn_perfil_operacao_nfe_revisar, com a sessao do usuario de e2e.
 * Os demais campos do perfil vem da migration que o criou. A revisao zera a
 * liberacao de producao (exige nova homologacao + liberacao).
 *
 *   node scripts/nfe-perfil-revisar.mjs SEG-IND-SC-5101-O0-CST00-17 ["justificativa"]
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
const codigo = process.argv[2];
if (!codigo) { console.error("Uso: node scripts/nfe-perfil-revisar.mjs <codigo> [justificativa]"); process.exit(1); }
const justificativa = process.argv[3] ?? `Revisao fiscal de 06/09/2026 conforme respostas do contador: venda de producao propria dentro de SC a 17% (RICMS/SC art. 26, I) para uso e consumo ou ativo do adquirente, base cheia, sem cBenef; IPI pelo NCM do item e integrando a base do ICMS para consumidor final; PIS 1,65% e COFINS 7,60% (Lucro Real); IBS/CBS 2026 CST 000, cClassTrib 000001, IBS UF 0,10%, IBS mun 0%, CBS 0,90% (ADCT art. 125; LC 214/2025). Perfil ${codigo}.`;

const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const { error: loginError } = await supabase.auth.signInWithPassword({ email: process.env.E2E_EMAIL ?? "", password: process.env.E2E_PASSWORD ?? "" });
if (loginError) { console.error("login:", loginError.message); process.exit(1); }
const { data: perfis, error: perfisError } = await supabase.schema("f").from("perfil_operacao").select("id,codigo,revisao_fiscal_em,habilitado_producao,faixa_automacao").eq("codigo", codigo).eq("modelo", "NFE");
if (perfisError || !perfis?.length) { console.error("perfil nao encontrado:", perfisError?.message ?? codigo); process.exit(1); }
const perfil = perfis[0];
const { data, error } = await supabase.schema("f").rpc("fn_perfil_operacao_nfe_revisar", {
  p_perfil_id: perfil.id, p_cst_ibs_cbs: "000", p_cclass_trib: "000001",
  p_cclass_trib_versao: "Transicao 2026 - ADCT art. 125 e LC 214/2025 (leiaute NT 2025.002)",
  p_ibs_uf_aliquota: 0.1, p_ibs_mun_aliquota: 0, p_cbs_aliquota: 0.9, p_justificativa: justificativa,
});
if (error) { console.error("revisar:", error.message); process.exit(2); }
console.log(JSON.stringify({ perfil: codigo, faixa_automacao: perfil.faixa_automacao, ...data }, null, 2));
