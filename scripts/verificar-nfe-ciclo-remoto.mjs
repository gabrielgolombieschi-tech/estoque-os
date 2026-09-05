import fs from "node:fs";
import { createClient } from "@supabase/supabase-js";

const env = {};
for (const file of [".env.local", ".env"]) {
  if (!fs.existsSync(file)) continue;
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    const match = line.match(/^([^#=]+)=(.*)$/);
    if (!match || env[match[1]]) continue;
    env[match[1]] = match[2].trim().replace(/^['"]|['"]$/g, "");
  }
}

const supabase = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const solicitacaoPiloto = "bd138fb9-126f-4396-a228-b957c6ad3669";
const [perfis, perfisVenda, inutilizacoes, prontidaoProducao] = await Promise.all([
  supabase.schema("f").from("perfil_operacao").select("id", { count: "exact", head: true }).eq("habilitado_producao", true),
  supabase.schema("f").from("perfil_operacao")
    .select("id,codigo,nome,natureza_operacao,crt,cfop_interno,cst_icms,cst_ipi,cst_pis,cst_cofins,cst_ibs_cbs,cclass_trib,cclass_trib_versao,faixa_automacao,habilitado_producao,vigencia_inicio,vigencia_fim")
    .eq("modelo", "NFE")
    .eq("natureza_operacao", "VENDA_MERCADORIA_TERCEIROS"),
  supabase.schema("f").from("nfe_inutilizacao").select("id", { count: "exact", head: true }),
  supabase.schema("f").rpc("fn_nfe_producao_pronta", { p_solicitacao_id: solicitacaoPiloto }),
]);
if (perfis.error) throw perfis.error;
if (perfisVenda.error) throw perfisVenda.error;
if (inutilizacoes.error) throw inutilizacoes.error;
if (prontidaoProducao.error) throw prontidaoProducao.error;
console.log(JSON.stringify({
  remoto: true,
  perfis_habilitados_producao: perfis.count,
  perfis_venda_mercadoria_terceiros: perfisVenda.data ?? [],
  prontidao_producao_piloto: prontidaoProducao.data,
  inutilizacoes_registradas: inutilizacoes.count,
}, null, 2));
