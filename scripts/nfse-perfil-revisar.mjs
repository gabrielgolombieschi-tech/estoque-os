/**
 * Registra a revisao fiscal de um perfil de servico (NFS-e) com os valores da
 * matriz de 9 NFS-e reais de agosto/2026 e o documento do contador de
 * 24/11/2021. Sessao do usuario de e2e; auditoria em f.perfil_operacao_revisao_evento.
 *
 *   node scripts/nfse-perfil-revisar.mjs SEG-NFSE-1406
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
if (!codigo) { console.error("Uso: node scripts/nfse-perfil-revisar.mjs <codigo do perfil>"); process.exit(1); }

// Fonte: matriz fiscal de 05/09/2026 (NFS-e 21, 23, 27, 30, 32, 34, 36, 37, 38 de agosto/2026).
const comum = {
  tributacao_iss: 1, aliquota_iss: 5.0,
  cst_pis: "01", cst_cofins: "01", aliquota_pis: 1.65, aliquota_cofins: 7.6,
  cst_ibs_cbs: "000", cclass_trib: "000001", cclass_trib_versao: "NFS-e 32 e 37 de ago/2026",
  ibs_uf_aliquota: 0.1, ibs_mun_aliquota: 0, cbs_aliquota: 0.9,
  consumidor_final: 0, permite_deducao_material: false,
  tributos_aprox_federal_pct: 13.45,
};
const valores = {
  "SEG-NFSE-1406": {
    ...comum,
    codigo_tributacao_nacional: "140601", codigo_nbs: "120032900", descricao_servico_padrao: "SERVICOS MAO DE OBRA ELETRICISTA",
    local_prestacao_regra: "CLIENTE", iss_retido_regra: "NUNCA", retencao_pcc_regra: "NUNCA", retencao_irrf_regra: "NUNCA", retencao_inss_regra: "NUNCA",
    codigo_indicador_operacao: "050103", tributos_aprox_municipal_pct: 4.69,
    texto_complementar: "\"NAO HA INCIDENCIA DAS RETENCOES FEDERAIS CONFORME IN SRF N 459/2004\"",
  },
  "SEG-NFSE-1401": {
    ...comum,
    codigo_tributacao_nacional: "140101", codigo_nbs: "120015000", descricao_servico_padrao: "SERVICO DE MANUTENCAO",
    local_prestacao_regra: "CLIENTE", iss_retido_regra: "NUNCA", retencao_pcc_regra: "NUNCA", retencao_irrf_regra: "NUNCA", retencao_inss_regra: "NUNCA",
    codigo_indicador_operacao: "050103", tributos_aprox_municipal_pct: 4.69,
    texto_complementar: "\"NAO HA INCIDENCIA DAS RETENCOES FEDERAIS CONFORME IN SRF N 459/2004\"",
  },
  "SEG-NFSE-1709": {
    ...comum,
    codigo_tributacao_nacional: "170901", codigo_nbs: "114044900", descricao_servico_padrao: "LAUDO TECNICO",
    local_prestacao_regra: "SEDE", iss_retido_regra: "SEMPRE", retencao_pcc_regra: "SEMPRE", aliquota_pcc: 4.65, retencao_irrf_regra: "SEMPRE", aliquota_irrf: 1.5, retencao_inss_regra: "NUNCA",
    codigo_indicador_operacao: "050103", tributos_aprox_municipal_pct: 3.64,
    texto_complementar: "\"PARA OS SERVICOS DE LAUDOS E PERICIAS, DEVERA SER RETIDO IRRF A ALIQUOTA DE 1,5% E CRF A ALIQUOTA DE 4,65% (PIS 0,65%; COFINS 3,0%; CSLL 1%). TRIBUTOS INCIDENTES SOBRE O PRECO LEI 12.741/2012\"",
  },
};
const campos = valores[codigo];
if (!campos) { console.error("Sem valores definidos para", codigo, "- disponiveis:", Object.keys(valores).join(", ")); process.exit(1); }
const justificativa = process.argv[3] ?? `Revisao fiscal com base na matriz de 9 NFS-e reais de agosto/2026 (NFS-e 21, 23, 27, 30, 32, 34, 36, 37, 38) e no documento do contador de 24/11/2021: retencao por servico, ISS 5% Joinville, PIS/COFINS CST 01, IBS/CBS 000/000001 (0,10%/0,90%), cIndOp e totais aproximados observados. Perfil ${codigo}.`;

const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const { error: loginError } = await supabase.auth.signInWithPassword({ email: process.env.E2E_EMAIL ?? "", password: process.env.E2E_PASSWORD ?? "" });
if (loginError) { console.error("login:", loginError.message); process.exit(1); }
const { data: perfis, error: perfisError } = await supabase.schema("f").from("perfil_operacao").select("id,codigo,revisao_fiscal_em,habilitado_producao").eq("codigo", codigo).eq("modelo", "NFSE");
if (perfisError || !perfis?.length) { console.error("perfil nao encontrado:", perfisError?.message ?? codigo); process.exit(1); }
const perfil = perfis[0];
const { data, error } = await supabase.schema("f").rpc("fn_perfil_operacao_nfse_revisar", { p_perfil_id: perfil.id, p_campos: campos, p_justificativa: justificativa });
if (error) { console.error("revisar:", error.message); process.exit(2); }
console.log(JSON.stringify({ perfil: codigo, ...data, campos }, null, 2));
