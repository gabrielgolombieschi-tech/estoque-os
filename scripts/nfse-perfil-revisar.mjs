/**
 * Registra a revisao fiscal de um perfil de servico (NFS-e) com os valores do
 * estudo de 06/09/2026 e as respostas do contador do mesmo dia
 * (docs/faturamento/respostas-contador-2026-09-06.md). Sessao do usuario de
 * e2e; auditoria em f.perfil_operacao_revisao_evento. A revisao zera a
 * liberacao de producao do perfil (exige nova homologacao + liberacao).
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

// PIS/COFINS proprios: Lucro Real nao cumulativo, 1,65% / 7,60% (contador, pergunta 6).
// Os 0,65% / 3,00% das notas antigas eram a aliquota da retencao espelhada por engano.
const comum = {
  tributacao_iss: 1,
  cst_pis: "01", cst_cofins: "01", aliquota_pis: 1.65, aliquota_cofins: 7.6,
  cst_ibs_cbs: "000", cclass_trib: "000001", cclass_trib_versao: "Ato Conjunto RFB/CGIBS 4/2026",
  ibs_uf_aliquota: 0.1, ibs_mun_aliquota: 0, cbs_aliquota: 0.9,
  consumidor_final: 0, permite_deducao_material: false,
  tributos_aprox_federal_pct: 13.45,
};
const SEM_RETENCAO = "Serviço não sujeito à retenção de PIS/COFINS/CSLL, conforme IN RFB nº 2.141/2023.";
// Texto exato do contador (06/09/2026, segunda rodada) para o 14.01 com CRF e sem IRRF.
const COM_CRF = "SERVIÇO SUJEITO À RETENÇÃO DE CRF À ALÍQUOTA DE 4,65% (PIS 0,65%; COFINS 3,0%; CSLL 1,0%) CONFORME IN RFB N° 2.141/2023. TRIBUTOS INCIDENTES SOBRE O PREÇO CONFORME LEI 12.741/2012.";
const LAUDOS = "Serviço sujeito à retenção de IRRF (1,5%) conforme Art. 714 do RIR/2018, e CRF (4,65%, sendo PIS 0,65%, COFINS 3,0% e CSLL 1,0%) conforme IN RFB nº 2.141/2023. Valor aproximado dos tributos conforme Lei 12.741/2012: {VTOTTRIB}.";
const valores = {
  // 14.06 (14.06.01): instalacao/montagem = empreitada com escopo fechado. ISS 5% sempre Joinville, sem retencao
  // (excecao: tomador substituto tributario, no cadastro do cliente). Sem INSS: cessao de mao de obra a Segau nao faz;
  // obra civil vai para 07.02. Campos ISS e INSS confirmados pelo contador (perguntas 1 e 2), por isso sem campos_conferir.
  "SEG-NFSE-1406": {
    ...comum,
    codigo_tributacao_nacional: "140601", codigo_nbs: "120032900", descricao_servico_padrao: "INSTALACAO E MONTAGEM DE EQUIPAMENTOS ELETRICOS",
    local_prestacao_regra: "CLIENTE", incidencia_iss_regra: "PRESTADOR", aliquota_iss: 5.0,
    iss_retido_regra: "NUNCA", retencao_pcc_regra: "NUNCA", retencao_irrf_regra: "NUNCA", retencao_inss_regra: "NUNCA",
    codigo_indicador_operacao: "050103", tributos_aprox_municipal_pct: 4.69,
    texto_complementar: SEM_RETENCAO, texto_sem_retencao: SEM_RETENCAO,
  },
  // 14.01 (14.01.01): manutencao; CRF 4,65% por padrao (pergunta 3), excecoes conserto isolado, tomador do Simples e
  // retencao <= R$ 10,00. Frase da regra geral com CRF; a de dispensa entra so pelo motivo (conferencia).
  "SEG-NFSE-1401": {
    ...comum,
    codigo_tributacao_nacional: "140101", codigo_nbs: "120015000", descricao_servico_padrao: "MANUTENCAO CORRETIVA DE EQUIPAMENTOS ELETRICOS",
    local_prestacao_regra: "CLIENTE", incidencia_iss_regra: "PRESTADOR", aliquota_iss: 5.0,
    iss_retido_regra: "NUNCA", retencao_pcc_regra: "SEMPRE", aliquota_pcc: 4.65, retencao_irrf_regra: "NUNCA", retencao_inss_regra: "NUNCA",
    excecao_conserto_isolado: true,
    codigo_indicador_operacao: "050103", tributos_aprox_municipal_pct: 4.69,
    texto_complementar: COM_CRF, texto_sem_retencao: SEM_RETENCAO,
  },
  // 17.09 (17.09.01): laudos e pericias; ISS retido pelo tomador; IRRF 1,5% (RIR/2018 art. 714) + CRF 4,65%.
  "SEG-NFSE-1709": {
    ...comum,
    codigo_tributacao_nacional: "170901", codigo_nbs: "114044900", descricao_servico_padrao: "LAUDO TECNICO",
    local_prestacao_regra: "SEDE", incidencia_iss_regra: "PRESTADOR", aliquota_iss: 5.0,
    iss_retido_regra: "SEMPRE", retencao_pcc_regra: "SEMPRE", aliquota_pcc: 4.65, retencao_irrf_regra: "SEMPRE", aliquota_irrf: 1.5, retencao_inss_regra: "NUNCA",
    codigo_indicador_operacao: "050103", tributos_aprox_municipal_pct: 3.64,
    texto_complementar: LAUDOS, texto_sem_retencao: SEM_RETENCAO,
  },
  // 07.02 (07.02.01): obra eletrica/civil; ISS no municipio da obra, retido pelo tomador (SFS 2%, LC municipal;
  // a aliquota por municipio vem de f.nfse_aliquota_iss e obra em municipio sem linha bloqueia); INSS 11%
  // (art. 111 da IN 2.110/2022; material discriminado abate a base); sem IRRF/CRF; cIndOp 020201 (bem imovel).
  // Sai de BLOQUEADO em 06/09/2026 (terceira rodada do contador).
  // NBS: o 1.0102.41.00 do contador nao existe na tabela do ambiente nacional (E0316, DPS 2/21 da OS 139,
  // 11/09/2026). Vale o 1.0102.69.00 das NFS-e 07.02 reais autorizadas para a WEG Tintas (12 a 15 de 03/08 e
  // 47 de 04/09/2026); confirmar com o contador antes da producao.
  "SEG-NFSE-0702": {
    ...comum,
    codigo_tributacao_nacional: "070201", codigo_nbs: "101026900", descricao_servico_padrao: "EXECUCAO DE INSTALACAO ELETRICA EM OBRA",
    local_prestacao_regra: "CLIENTE", incidencia_iss_regra: "LOCAL_PRESTACAO", aliquota_iss: 2.0,
    iss_retido_regra: "SEMPRE", retencao_pcc_regra: "NUNCA", retencao_irrf_regra: "NUNCA", retencao_inss_regra: "SEMPRE", aliquota_inss: 11,
    permite_deducao_material: true,
    codigo_indicador_operacao: "020201", tributos_aprox_municipal_pct: 2.11,
    texto_complementar: null, texto_sem_retencao: null,
  },
};
const campos = valores[codigo];
if (!campos) { console.error("Sem valores definidos para", codigo, "- disponiveis:", Object.keys(valores).join(", ")); process.exit(1); }
const justificativa = process.argv[3] ?? `Revisao fiscal conforme respostas do contador de 06/09/2026 (docs/faturamento/respostas-contador-2026-09-06.md): ISS sempre Joinville sem retencao salvo substituto tributario; INSS so em cessao de mao de obra ou obra civil (07.02); CRF padrao no 14.01; PIS/COFINS proprios 1,65/7,60; frases da IN RFB 2.141/2023; cIndOp 050103 (bem movel) e 020201 (07.02, bem imovel); NBS 1.2003.29.00 e 1.0102.41.00. Perfil ${codigo}.`;

const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const { error: loginError } = await supabase.auth.signInWithPassword({ email: process.env.E2E_EMAIL ?? "", password: process.env.E2E_PASSWORD ?? "" });
if (loginError) { console.error("login:", loginError.message); process.exit(1); }
const { data: perfis, error: perfisError } = await supabase.schema("f").from("perfil_operacao").select("id,codigo,revisao_fiscal_em,habilitado_producao,faixa_automacao").eq("codigo", codigo).eq("modelo", "NFSE");
if (perfisError || !perfis?.length) { console.error("perfil nao encontrado:", perfisError?.message ?? codigo); process.exit(1); }
const perfil = perfis[0];
const { data, error } = await supabase.schema("f").rpc("fn_perfil_operacao_nfse_revisar", { p_perfil_id: perfil.id, p_campos: campos, p_justificativa: justificativa });
if (error) { console.error("revisar:", error.message); process.exit(2); }
console.log(JSON.stringify({ perfil: codigo, faixa_automacao: perfil.faixa_automacao, ...data, campos }, null, 2));
