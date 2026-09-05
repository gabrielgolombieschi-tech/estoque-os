import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { createClient } from "@supabase/supabase-js";

function loadEnvFile(file) {
  if (!fs.existsSync(file)) return;
  for (const rawLine of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const separator = line.indexOf("=");
    if (separator < 1) continue;
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
}

loadEnvFile(path.resolve(".env.local"));
loadEnvFile(path.resolve(".env"));

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !serviceKey) {
  throw new Error("NEXT_PUBLIC_SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY sao obrigatorias.");
}

const supabase = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const { data: escopos, error: escoposError } = await supabase
  .schema("f")
  .from("perfil_operacao_evidencia")
  .select("tenant_id,empresa_id")
  .eq("fonte", "regras-nfe-63-combinacoes.csv");
if (escoposError) throw new Error(`Nao foi possivel localizar a matriz: ${escoposError.message}`);

const unicos = [...new Map((escopos ?? []).map((row) => [`${row.tenant_id}:${row.empresa_id}`, row])).values()];
if (unicos.length !== 1) {
  throw new Error(`Esperado exatamente um escopo SEG para a matriz; encontrados ${unicos.length}.`);
}

const escopo = unicos[0];
const { data: extracao, error: extracaoError } = await supabase
  .schema("f")
  .rpc("fn_extrair_perfis_operacao_xml_saida", {
    p_tenant_id: escopo.tenant_id,
    p_empresa_id: escopo.empresa_id,
  });
if (extracaoError) throw new Error(`Extracao dos XMLs falhou: ${extracaoError.message}`);

const { data: evidencias, error: evidenciasError } = await supabase
  .schema("f")
  .from("perfil_operacao_evidencia")
  .select("fonte_linha,natureza_texto,cfop,origem,cst_icms,faixa,justificativa_faixa,xml_notas,xml_itens,xml_pis_csts,xml_cofins_csts,xml_pis_aliquotas,xml_cofins_aliquotas,xml_ipi_csts,xml_cbenef_valores,xml_cbenef_ausente_itens,xml_fci_itens,xml_divergente")
  .eq("tenant_id", escopo.tenant_id)
  .eq("empresa_id", escopo.empresa_id)
  .order("fonte_linha");
if (evidenciasError) throw new Error(`Leitura da reconciliacao falhou: ${evidenciasError.message}`);

const { data: perfis, error: perfisError } = await supabase
  .schema("f")
  .from("perfil_operacao")
  .select("faixa_automacao,habilitado_producao,evidencia_id")
  .eq("tenant_id", escopo.tenant_id)
  .eq("empresa_id", escopo.empresa_id)
  .not("evidencia_id", "is", null);
if (perfisError) throw new Error(`Leitura dos perfis falhou: ${perfisError.message}`);

const faixas = (perfis ?? []).reduce((acc, row) => {
  acc[row.faixa_automacao] = (acc[row.faixa_automacao] ?? 0) + 1;
  return acc;
}, {});
const resumo = {
  escopo,
  extracao,
  perfis: {
    total: perfis?.length ?? 0,
    automatico: faixas.AUTOMATICO ?? 0,
    revisao: faixas.REVISAO ?? 0,
    bloqueado: faixas.BLOQUEADO ?? 0,
    habilitados_producao: (perfis ?? []).filter((row) => row.habilitado_producao).length,
  },
  combinacoes_sem_xml: (evidencias ?? [])
    .filter((row) => row.xml_itens === 0)
    .map((row) => ({ linha: row.fonte_linha, natureza: row.natureza_texto, cfop: row.cfop })),
  combinacoes_xml_divergente: (evidencias ?? []).filter((row) => row.xml_divergente),
  combinacoes_decisao: (evidencias ?? []).map((row) => ({
    perfil: `CSV63-${String(row.fonte_linha).padStart(3, "0")}`,
    natureza: row.natureza_texto,
    combinacao: `${row.cfop} / origem ${row.origem} / CST ${row.cst_icms}`,
    faixa: row.faixa,
    falta: [
      row.justificativa_faixa,
      row.xml_itens === 0 ? "sem XML de saida correspondente" : null,
      row.xml_divergente ? "XML de saida divergente" : null,
    ].filter(Boolean).join("; "),
  })),
};

console.log(JSON.stringify(resumo, null, 2));
