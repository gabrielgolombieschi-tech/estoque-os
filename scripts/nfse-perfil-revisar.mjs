/**
 * Registra a revisao fiscal de um perfil de servico (NFS-e) com os valores do
 * estudo de 06/09/2026 (29 NFS-e e 8 NF-e de agosto/2026, documento do contador
 * de 24/11/2021, legislacao vigente em 05/09/2026). Sessao do usuario de e2e;
 * auditoria em f.perfil_operacao_revisao_evento. A revisao zera a liberacao
 * de producao do perfil (exige nova homologacao + liberacao).
 *
 *   node scripts/nfse-perfil-revisar.mjs SEG-NFSE-1406
 *   node scripts/nfse-perfil-revisar.mjs SEG-NFSE-0702   (grava os valores; o perfil continua BLOQUEADO)
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

// Fonte: estudo de 06/09/2026 (NFS-e 12-40 de agosto/2026; NF-e 3765-3772).
// PIS/COFINS proprios: CST 01, 0,65%/3,00% como nas notas reais (regime do
// prestador; ver pergunta ao contador sobre 1,65/7,60 no lucro real).
const comum = {
  tributacao_iss: 1,
  cst_pis: "01", cst_cofins: "01", aliquota_pis: 0.65, aliquota_cofins: 3.0,
  cst_ibs_cbs: "000", cclass_trib: "000001", cclass_trib_versao: "NFS-e 32 e 37 de ago/2026",
  ibs_uf_aliquota: 0.1, ibs_mun_aliquota: 0, cbs_aliquota: 0.9,
  consumidor_final: 0, permite_deducao_material: false,
  tributos_aprox_federal_pct: 13.45,
};
const FRASE_SEM_RETENCAO = "\"NAO HA INCIDENCIA DAS RETENCOES FEDERAIS CONFORME IN SRF N 459/2004\"";
const FRASE_LAUDOS = "\"PARA OS SERVICOS DE LAUDOS E PERICIAS, DEVERA SER RETIDO IRRF A ALIQUOTA DE 1,5% E CRF A ALIQUOTA DE 4,65% (PIS 0,65%; COFINS 3,0%; CSLL 1%). TRIBUTOS INCIDENTES SOBRE O PRECO LEI 12.741/2012\"";
const valores = {
  // 14.06 (14.06.01): instalacao/montagem; ISS 5% Joinville, incidencia no prestador; sem retencao federal.
  // Travados (CONFERIR_08_09): ISS retido (nenhuma nota real com retencao) e INSS (nenhuma nota real com INSS).
  "SEG-NFSE-1406": {
    ...comum,
    codigo_tributacao_nacional: "140601", codigo_nbs: "120032900", descricao_servico_padrao: "INSTALACAO E MONTAGEM DE EQUIPAMENTOS ELETRICOS",
    local_prestacao_regra: "CLIENTE", incidencia_iss_regra: "PRESTADOR", aliquota_iss: 5.0,
    iss_retido_regra: "NUNCA", retencao_pcc_regra: "NUNCA", retencao_irrf_regra: "NUNCA", retencao_inss_regra: "NUNCA",
    codigo_indicador_operacao: "050103", tributos_aprox_municipal_pct: 4.69,
    texto_complementar: FRASE_SEM_RETENCAO,
    campos_conferir: [
      { campo: "iss_retido_regra", motivo: "CONFERIR_08_09: nenhuma NFS-e real de 14.06 com ISS retido; manter Nao Retido ate a conferencia", prazo: "2026-09-08" },
      { campo: "retencao_inss_regra", motivo: "CONFERIR_08_09: nenhuma NFS-e real de 14.06 com INSS; manter sem INSS ate a conferencia", prazo: "2026-09-08" },
    ],
  },
  // 14.01 (14.01.01): manutencao/conserto; CRF 4,65% por padrao (IN SRF 459/2004), excecao "conserto isolado" na OS.
  // Travado (CONFERIR_08_09): ISS retido.
  "SEG-NFSE-1401": {
    ...comum,
    codigo_tributacao_nacional: "140101", codigo_nbs: "120015000", descricao_servico_padrao: "MANUTENCAO CORRETIVA DE EQUIPAMENTOS ELETRICOS",
    local_prestacao_regra: "CLIENTE", incidencia_iss_regra: "PRESTADOR", aliquota_iss: 5.0,
    iss_retido_regra: "NUNCA", retencao_pcc_regra: "SEMPRE", aliquota_pcc: 4.65, retencao_irrf_regra: "NUNCA", retencao_inss_regra: "NUNCA",
    excecao_conserto_isolado: true,
    codigo_indicador_operacao: "050103", tributos_aprox_municipal_pct: 4.69,
    texto_complementar: FRASE_SEM_RETENCAO,
    campos_conferir: [
      { campo: "iss_retido_regra", motivo: "CONFERIR_08_09: nenhuma NFS-e real de 14.01 com ISS retido; manter Nao Retido ate a conferencia", prazo: "2026-09-08" },
    ],
  },
  // 17.09 (17.09.01): laudos e pericias; ISS retido pelo tomador; IRRF 1,5% + CRF 4,65%.
  "SEG-NFSE-1709": {
    ...comum,
    codigo_tributacao_nacional: "170901", codigo_nbs: "114044900", descricao_servico_padrao: "LAUDO TECNICO",
    local_prestacao_regra: "SEDE", incidencia_iss_regra: "PRESTADOR", aliquota_iss: 5.0,
    iss_retido_regra: "SEMPRE", retencao_pcc_regra: "SEMPRE", aliquota_pcc: 4.65, retencao_irrf_regra: "SEMPRE", aliquota_irrf: 1.5, retencao_inss_regra: "NUNCA",
    codigo_indicador_operacao: "050103", tributos_aprox_municipal_pct: 3.64,
    texto_complementar: FRASE_LAUDOS,
  },
  // 07.02 (07.02.01): obra; ISS 3% no municipio da obra (NFS-e 37, Sao Francisco do Sul), retido pelo tomador; INSS 11%.
  // O perfil continua BLOQUEADO (aguarda o contador); os valores ficam gravados para a homologacao futura.
  "SEG-NFSE-0702": {
    ...comum,
    codigo_tributacao_nacional: "070201", codigo_nbs: "101069000", descricao_servico_padrao: "EXECUCAO DE INSTALACAO ELETRICA EM OBRA",
    local_prestacao_regra: "CLIENTE", incidencia_iss_regra: "LOCAL_PRESTACAO", aliquota_iss: 3.0,
    iss_retido_regra: "SEMPRE", retencao_pcc_regra: "NUNCA", retencao_irrf_regra: "NUNCA", retencao_inss_regra: "SEMPRE", aliquota_inss: 11,
    codigo_indicador_operacao: "040101", tributos_aprox_municipal_pct: 2.11,
    texto_complementar: null,
  },
};
const campos = valores[codigo];
if (!campos) { console.error("Sem valores definidos para", codigo, "- disponiveis:", Object.keys(valores).join(", ")); process.exit(1); }
const justificativa = process.argv[3] ?? `Revisao fiscal com base no estudo de 06/09/2026 (29 NFS-e e 8 NF-e de agosto/2026, documento do contador de 24/11/2021, legislacao vigente): retencao por servico, ISS por municipio de incidencia, PIS/COFINS CST 01, IBS/CBS 000/000001 (0,10%/0,90%), cIndOp e tabela de tributos aproximados por subitem. Perfil ${codigo}.`;

const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const { error: loginError } = await supabase.auth.signInWithPassword({ email: process.env.E2E_EMAIL ?? "", password: process.env.E2E_PASSWORD ?? "" });
if (loginError) { console.error("login:", loginError.message); process.exit(1); }
const { data: perfis, error: perfisError } = await supabase.schema("f").from("perfil_operacao").select("id,codigo,revisao_fiscal_em,habilitado_producao,faixa_automacao").eq("codigo", codigo).eq("modelo", "NFSE");
if (perfisError || !perfis?.length) { console.error("perfil nao encontrado:", perfisError?.message ?? codigo); process.exit(1); }
const perfil = perfis[0];
const { data, error } = await supabase.schema("f").rpc("fn_perfil_operacao_nfse_revisar", { p_perfil_id: perfil.id, p_campos: campos, p_justificativa: justificativa });
if (error) { console.error("revisar:", error.message); process.exit(2); }
console.log(JSON.stringify({ perfil: codigo, faixa_automacao: perfil.faixa_automacao, ...data, campos }, null, 2));
