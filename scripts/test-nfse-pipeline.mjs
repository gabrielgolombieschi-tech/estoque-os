import assert from "node:assert/strict";
import { arredondarMeioPar, calcularIbsCbsNfse, montarPayloadNfse, tipoRetencaoPisCofins, validarPayloadNfseProducaoContraHomologacao, valorLiquidoNfse } from "../supabase/functions/_shared/nfse-payload.ts";
import { chaveNfseDe, normalizarFocusNfse } from "../supabase/functions/_shared/nfse-retorno.ts";
import { hojeSaoPaulo, pendenciaCompetenciaNfse } from "../supabase/functions/_shared/fiscal/nfse-competencia.ts";

// Cenarios locais do pipeline de NFS-e Nacional (sem chamar a Focus).
// Executar: node scripts/test-nfse-pipeline.mjs

function contexto(overrides = {}) {
  const servico = {
    perfil_codigo: "SEG-NFSE-1406",
    item_servico: "14.06",
    codigo_tributacao_nacional: "140601",
    codigo_tributacao_municipal: null,
    codigo_nbs: "120032900",
    municipio_prestacao_ibge: "4218004",
    data_competencia: "2026-09-05",
    tributacao_iss: 1,
    aliquota_iss: 5,
    iss_retido: false,
    retem_pcc: false,
    retem_irrf: false,
    retem_inss: false,
    valor_bruto: 1000,
    valor_iss: 50,
    valor_irrf: 0,
    valor_pcc: 0,
    valor_inss: 0,
    valor_liquido: 1000,
    retencoes: [],
    cst_pis_cofins: "01",
    aliquota_pis: 1.65,
    aliquota_cofins: 7.6,
    cst_ibs_cbs: "000",
    cclass_trib: "000001",
    descricao_servico: "SERVICOS DE INSTALACAO - OS 328. PEDIDO DE COMPRA: 4518. VENCIMENTO: 30 DDL (05/10/2026). ISS RECOLHIDO PELO PRESTADOR. NAO HA INCIDENCIA DAS RETENCOES FEDERAIS CONFORME IN SRF N 459/2004.",
    os_numeros: ["328"],
    ...(overrides.servico ?? {}),
  };
  return {
    emissao: {
      ambiente: "HOMOLOGACAO", modelo: "NFSE", referencia_externa: "NFSH-x", dps_serie: 2, dps_numero: 7,
      chave_nfse_substituida: null, ...(overrides.emissao ?? {}),
    },
    solicitacao: {
      emitente_snapshot: {
        cnpj: "13671448000189", razao_social: "ELETRICA SEGAU LTDA", inscricao_municipal: "152836", telefone: "4734735171", email: "contato@segau.com.br",
        codigo_opcao_simples_nacional: 1, regime_especial_tributacao: 0, serie_dps: 2,
        logradouro: "RUA DONA FRANCISCA", numero: "8300", complemento: "BLOCO 1", bairro: "ZONA INDUSTRIAL NORTE", cidade: "JOINVILLE", uf: "SC",
        codigo_municipio_ibge: "4209102", cep: "89219600", ...(overrides.emitente ?? {}),
      },
      destinatario_snapshot: {
        id: 1, documento: "83475913000272", nome: "PORTOBELLO SA", inscricao_municipal: null, email: "nfe@portobello.com.br", telefone: null,
        logradouro: "BR 101, KM 163", numero_endereco: "S/N", complemento: null, bairro: "CENTRO", cidade: "TIJUCAS", uf: "SC",
        codigo_ibge_municipio: "4218004", cep: "88200000", ...(overrides.tomador ?? {}),
      },
      operacao_snapshot: {
        natureza_operacao: "PRESTACAO_SERVICO", modelo: "NFSE", consumidor_final: 0,
        servico,
        pedido: { pedido_cliente: "4518", pedido_item: overrides.pedido_item ?? null },
        substituicao: overrides.substituicao ?? null,
        pagamento: { forma: "15", indicador: 1, parcelas: [{ numero: "001", dias: 30, valor: null }] },
      },
    },
    itens: [],
  };
}

let cenarios = 0;
function cenario(nome, fn) {
  cenarios += 1;
  try { fn(); } catch (erro) { console.error(`FALHOU: ${nome}`); throw erro; }
}

const agora = new Date("2026-09-05T15:00:00Z");

cenario("payload 14.06 sem retencao: campos obrigatorios e nomes da Focus", () => {
  const p = montarPayloadNfse(contexto(), agora);
  assert.equal(p.serie_dps, 2);
  assert.equal(p.numero_dps, 7);
  assert.equal(p.emitente_dps, 1);
  assert.equal(p.codigo_municipio_emissora, 4209102);
  assert.equal(p.cnpj_prestador, "13671448000189");
  assert.equal(p.inscricao_municipal_prestador, undefined, "IM do prestador nao vai (E0120)");
  assert.equal(p.razao_social_prestador, undefined, "nome do prestador nao vai (E0121)");
  assert.equal(p.logradouro_prestador, undefined);
  assert.equal(p.telefone_prestador, "4734735171");
  assert.equal(p.codigo_opcao_simples_nacional, 1);
  assert.equal(p.regime_especial_tributacao, 0);
  assert.equal(p.cnpj_tomador, "83475913000272");
  assert.equal(p.razao_social_tomador, "NFS-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL");
  assert.equal(p.codigo_municipio_tomador, 4218004);
  assert.equal(p.inscricao_municipal_tomador, undefined, "IM do tomador so em Joinville");
  assert.equal(p.codigo_municipio_prestacao, "4218004");
  assert.equal(p.codigo_tributacao_nacional_iss, "140601");
  assert.equal(p.codigo_nbs, "120032900");
  assert.equal(p.codigo_interno_contribuinte, "OS328", "cIntContrib so alfanumerico");
  // Sem destinatario distinto do tomador o indicador do grupo 0501 e 050102 (18/09/2026).
  assert.equal(p.codigo_indicador_operacao, "050102");
  assert.equal(p.pedido_compra, "4518");
  assert.equal(p.itens_pedido_compra, undefined);
  assert.equal(p.valor_servico, 1000);
  assert.equal(p.tributacao_iss, 1);
  assert.equal(p.percentual_aliquota_relativa_municipio, undefined, "aliquota parametrizada pelo municipio (E0617)");
  assert.equal(p.tipo_retencao_iss, 1);
  assert.equal(p.situacao_tributaria_pis_cofins, "01");
  assert.equal(p.tipo_retencao_pis_cofins, 0);
  // PIS/COFINS proprios (vPis/vCofins) vao junto com as aliquotas: 1,65% e 7,60% de 1.000.
  assert.equal(p.valor_pis, 16.5);
  assert.equal(p.valor_cofins, 76);
  assert.equal(p.valor_csll, undefined);
  assert.equal(p.valor_irrf, undefined);
  assert.equal(p.valor_cp, undefined);
  assert.equal(p.valor_total_tributos_federais, 92.5);
  assert.equal(p.valor_total_tributos_municipais, 50);
  assert.equal(p.finalidade_emissao, 0);
  assert.equal(p.consumidor_final, 0);
  assert.equal(p.indicador_destinatario, 0);
  assert.equal(p.ibs_cbs_situacao_tributaria, "000");
  assert.equal(p.ibs_cbs_classificacao_tributaria, "000001");
  assert.match(String(p.data_emissao), /^2026-09-05T12:00:00-03:00$/);
  assert.equal(p.data_competencia, "2026-09-05");
  assert.match(String(p.informacoes_complementares), /OS 328 \| EMITIDA EM HOMOLOGACAO/);
  assert.equal(p.chave_nfse_substituida, undefined);
});

cenario("17.09 com ISS retido, IRRF e PCC: tpRetISSQN 2, tpRetPisCofins 3, valor_csll = soma", () => {
  const p = montarPayloadNfse(contexto({
    servico: { item_servico: "17.09", codigo_tributacao_nacional: "170901", municipio_prestacao_ibge: "4209102", iss_retido: true, retem_pcc: true, retem_irrf: true,
      valor_bruto: 10340, valor_iss: 517, valor_irrf: 155.1, valor_pcc: 480.81, valor_liquido: 9187.09 },
    tomador: { documento: "84689090000240", nome: "INCASA S/A", inscricao_municipal: "123456", codigo_ibge_municipio: "4209102", cep: "89239270" },
  }), agora);
  assert.equal(p.tipo_retencao_iss, 2);
  assert.equal(p.tipo_retencao_pis_cofins, 3);
  assert.equal(p.valor_csll, 480.81);
  assert.equal(p.valor_irrf, 155.1);
  assert.equal(p.valor_cp, undefined);
  assert.equal(p.inscricao_municipal_tomador, "123456", "tomador de Joinville leva IM");
  assert.equal(valorLiquidoNfse(contexto({ servico: { iss_retido: true, valor_bruto: 10340, valor_iss: 517, valor_irrf: 155.1, valor_pcc: 480.81 } }).solicitacao.operacao_snapshot.servico), 9187.09);
});

cenario("INSS retido vira valor_cp", () => {
  const p = montarPayloadNfse(contexto({ servico: { retem_inss: true, valor_inss: 110 } }), agora);
  assert.equal(p.valor_cp, 110);
  assert.equal(tipoRetencaoPisCofins(false), 0);
  assert.equal(tipoRetencaoPisCofins(true), 3);
});

// --- Ajustes de 18/09/2026 (NFS-e da OS 298, CREMER): PIS/COFINS proprios e cIndOp ------------
// Caso real: 14.01, R$ 58.000,00, ISS 5% nao retido, CRF 4,65% retida, sem IRRF e sem INSS.
const servicoCremer = {
  perfil_codigo: "SEG-NFSE-1401", item_servico: "14.01", codigo_tributacao_nacional: "140101",
  codigo_nbs: "120015000", municipio_prestacao_ibge: "4202404", aliquota_iss: 5,
  valor_bruto: 58000, valor_iss: 2900, iss_retido: false,
  retem_pcc: true, valor_pcc: 2697, retem_irrf: false, valor_irrf: 0, retem_inss: false, valor_inss: 0,
  valor_liquido: 55303,
  descricao_servico: "ADEQUACAO DE MAQUINA A NR-12 - COZINHA DE GOMA - OS 298. PEDIDO DE COMPRA: 148753.",
  os_numeros: ["298"],
};

cenario("14.01 da OS 298: PIS/COFINS proprios, CRF retida e cIndOp 050102", () => {
  const p = montarPayloadNfse(contexto({ servico: servicoCremer }), agora);
  assert.equal(p.valor_servico, 58000);
  assert.equal(p.valor_pis, 957, "PIS proprio 1,65% de 58.000");
  assert.equal(p.valor_cofins, 4408, "COFINS proprio 7,60% de 58.000");
  assert.equal(p.aliquota_pis, 1.65);
  assert.equal(p.aliquota_cofins, 7.6);
  assert.equal(p.tipo_retencao_pis_cofins, 3, "CRF retida");
  assert.equal(p.valor_csll, 2697, "retencao vai somada, como nas notas reais");
  assert.equal(p.valor_irrf, undefined);
  assert.equal(p.valor_cp, undefined);
  assert.equal(p.tipo_retencao_iss, 1, "ISS recolhido pela Segau");
  assert.equal(p.codigo_indicador_operacao, "050102");
  assert.equal(valorLiquidoNfse(contexto({ servico: servicoCremer }).solicitacao.operacao_snapshot.servico), 55303);
});

// Base do IBS/CBS na NFS-e: valor menos ISS, PIS e COFINS proprios (LC 214/2025, art. 12, §2º).
// Numeros do DANFSe devolvido pelo ambiente nacional na NFS-e de teste 21 da OS 298 (18/09/2026):
// exclusoes 8.265,00, base 49.735,00, IBS 49,74, CBS 447,62.
cenario("IBS/CBS da OS 298: base = servico - ISS - PIS - COFINS (retorno do ambiente nacional)", () => {
  assert.deepEqual(calcularIbsCbsNfse({ valorServico: 58000, valorIss: 2900, valorPis: 957, valorCofins: 4408, ibsUf: 0.1, ibsMun: 0, cbs: 0.9 }), {
    base: 49735, ibsUf: 49.74, ibsMun: 0, cbs: 447.62, total: 497.36,
  });
  assert.equal(58000 - 2900 - 957 - 4408, 49735, "exclusoes de 8.265,00");
  // Desconto incondicional, quando houver, sai da base junto.
  assert.equal(calcularIbsCbsNfse({ valorServico: 58000, valorDesconto: 1000, valorIss: 2900, valorPis: 957, valorCofins: 4408, ibsUf: 0.1, ibsMun: 0, cbs: 0.9 }).base, 48735);
});

cenario("cIndOp: perfil 050103 sem destinatario distinto vira 050102; com destinatario distinto fica", () => {
  const comPerfil = (extra) => montarPayloadNfse(contexto({ servico: { ...servicoCremer, codigo_indicador_operacao: "050103", tributacao_fonte: "PERFIL", ...extra } }), agora);
  assert.equal(comPerfil({}).codigo_indicador_operacao, "050102");
  assert.equal(comPerfil({ destinatario_distinto: true }).codigo_indicador_operacao, "050103");
  // Fora do grupo 0501 o valor do perfil manda (obra).
  assert.equal(
    montarPayloadNfse(contexto({ servico: { ...servicoCremer, item_servico: "07.02", codigo_tributacao_nacional: "070201", codigo_indicador_operacao: "020201", tributacao_fonte: "PERFIL", obra: { codigo_obra: "123456789012" } } }), agora).codigo_indicador_operacao,
    "020201",
  );
});

cenario("PIS/COFINS proprios: valores da conferencia mandam; CST sem tributacao nao destaca valor", () => {
  const daConferencia = montarPayloadNfse(contexto({ servico: { ...servicoCremer, valor_pis: 900, valor_cofins: 4000 } }), agora);
  assert.equal(daConferencia.valor_pis, 900);
  assert.equal(daConferencia.valor_cofins, 4000);
  const semTributacao = montarPayloadNfse(contexto({ servico: { ...servicoCremer, cst_pis_cofins: "07", aliquota_pis: 0, aliquota_cofins: 0 } }), agora);
  assert.equal(semTributacao.valor_pis, undefined);
  assert.equal(semTributacao.valor_cofins, undefined);
  assert.equal(semTributacao.situacao_tributaria_pis_cofins, "07");
});

cenario("pedido com item vira itens_pedido_compra", () => {
  const p = montarPayloadNfse(contexto({ pedido_item: "10" }), agora);
  assert.deepEqual(p.itens_pedido_compra, [{ numero_item_compra: "10" }]);
});

cenario("substituicao leva chave, codigo e motivo", () => {
  const p = montarPayloadNfse(contexto({
    emissao: { chave_nfse_substituida: "42091022213671448000189000000000003926082821285911", substituicao_codigo: "99", substituicao_motivo: "Descricao do servico corrigida a pedido do tomador" },
  }), agora);
  assert.equal(p.chave_nfse_substituida, "42091022213671448000189000000000003926082821285911");
  assert.equal(p.codigo_justificativa_substituicao, "99");
  assert.equal(p.motivo_substituicao, "Descricao do servico corrigida a pedido do tomador");
});

cenario("producao usa a razao social real do tomador", () => {
  const p = montarPayloadNfse(contexto({ emissao: { ambiente: "PRODUCAO" } }), agora);
  assert.equal(p.razao_social_tomador, "PORTOBELLO SA");
});

cenario("duas OS: codigo_interno_contribuinte lista as duas", () => {
  const p = montarPayloadNfse(contexto({ servico: { os_numeros: ["328", "287"] } }), agora);
  assert.equal(p.codigo_interno_contribuinte, "OS328OS287");
  assert.equal(montarPayloadNfse(contexto({ servico: { item_servico: "07.02" } }), agora).codigo_indicador_operacao, "020201");
});

cenario("bloqueios locais nomeiam campo e cadastro", () => {
  assert.throws(() => montarPayloadNfse(contexto({ emissao: { dps_numero: null } }), agora), /numero_dps/);
  assert.throws(() => montarPayloadNfse(contexto({ emissao: { dps_serie: 70000 } }), agora), /serie_dps fora da faixa/);
  assert.throws(() => montarPayloadNfse(contexto({ tomador: { codigo_ibge_municipio: "" } }), agora), /codigo_municipio_tomador \(cadastro fiscal do cliente\)/);
  assert.throws(() => montarPayloadNfse(contexto({ tomador: { cep: "123" } }), agora), /cep_tomador/);
  assert.throws(() => montarPayloadNfse(contexto({ servico: { codigo_tributacao_nacional: "" } }), agora), /codigo_tributacao_nacional_iss/);
  assert.throws(() => montarPayloadNfse(contexto({ servico: { municipio_prestacao_ibge: null } }), agora), /codigo_municipio_prestacao/);
  assert.throws(() => montarPayloadNfse(contexto({ servico: { descricao_servico: "x".repeat(1001) } }), agora), /1000 caracteres/);
  assert.throws(() => montarPayloadNfse(contexto({ emitente: { codigo_opcao_simples_nacional: null } }), agora), /codigo_opcao_simples_nacional/);
  assert.throws(() => montarPayloadNfse({ ...contexto(), solicitacao: { ...contexto().solicitacao, operacao_snapshot: { servico: null } } }, agora), /snapshot de servico/);
});

cenario("perfil revisado: cIndOp e totais aproximados vem do snapshot", () => {
  const p = montarPayloadNfse(contexto({ servico: { codigo_indicador_operacao: "040101", tributos_aprox_federal_pct: 13.45, tributos_aprox_municipal_pct: 4.69 } }), agora);
  assert.equal(p.codigo_indicador_operacao, "040101");
  assert.equal(p.valor_total_tributos_federais, 134.5);
  assert.equal(p.valor_total_tributos_municipais, 46.9);
});

// Notas 32 e 37: emitidas antes de a DPS levar PIS e COFINS proprios, entao sem esses valores a
// base continua sendo servico menos ISS — e a conta tem de reproduzi-las igual.
cenario("IBS/CBS no centavo: notas 32 e 37 reais (sem PIS/COFINS informados, meio-par)", () => {
  assert.deepEqual(calcularIbsCbsNfse({ valorServico: 3500, valorIss: 175, ibsUf: 0.1, ibsMun: 0, cbs: 0.9 }), { base: 3325, ibsUf: 3.32, ibsMun: 0, cbs: 29.92, total: 33.24 });
  assert.deepEqual(calcularIbsCbsNfse({ valorServico: 42298.75, valorIss: 1268.96, ibsUf: 0.1, ibsMun: 0, cbs: 0.9 }), { base: 41029.79, ibsUf: 41.03, ibsMun: 0, cbs: 369.27, total: 410.3 });
  assert.equal(arredondarMeioPar(3.325), 3.32);
  assert.equal(arredondarMeioPar(3.335), 3.34);
  assert.equal(arredondarMeioPar(41.02979), 41.03);
  // Fixture da NF-e (nfe-payload) usa a mesma CBS de 0,90% e IBS UF 0,10% de 2026.
  assert.equal(calcularIbsCbsNfse({ valorServico: 1000, valorIss: 50, ibsUf: 0.1, ibsMun: 0, cbs: 0.9 }).cbs, 8.55);
});

cenario("cIndOp: perfil revisado sem cIndOp nao emite; fixture usa o provisorio so ate 30/09/2026; estaduais da tabela", () => {
  assert.throws(() => montarPayloadNfse(contexto({ servico: { tributacao_fonte: "PERFIL", codigo_indicador_operacao: null } }), agora), /codigo_indicador_operacao \(perfil de servico sem cIndOp/);
  // 050103 do perfil so permanece quando ha destinatario distinto do tomador (18/09/2026).
  assert.equal(montarPayloadNfse(contexto({ servico: { tributacao_fonte: "PERFIL", codigo_indicador_operacao: "050103", destinatario_distinto: true } }), agora).codigo_indicador_operacao, "050103");
  assert.equal(montarPayloadNfse(contexto({ servico: { tributacao_fonte: "PERFIL", codigo_indicador_operacao: "050103" } }), agora).codigo_indicador_operacao, "050102");
  assert.equal(montarPayloadNfse(contexto({ servico: { tributacao_fonte: "FIXTURE_HOMOLOGACAO", item_servico: "07.02" } }), agora).codigo_indicador_operacao, "020201", "07.02 e servico sobre bem imovel (contador 06/09/2026)");
  // Competencia de outubro para a regra de competencia no mes da emissao nao falar antes do cIndOp.
  assert.throws(() => montarPayloadNfse(contexto({ servico: { tributacao_fonte: "FIXTURE_HOMOLOGACAO", data_competencia: "2026-10-01" } }), new Date("2026-10-01T12:00:00-03:00")), /obrigatorio desde 2026-10-01/);
  const p = montarPayloadNfse(contexto({ servico: { tributos_aprox_federal_pct: 13.45, tributos_aprox_municipal_pct: 4.69, tributos_aprox_estadual_pct: 0 } }), agora);
  assert.equal(p.valor_total_tributos_estaduais, 0);
});

const LOCAL_OBRA_WEG = { cep: "89272554", logradouro: "RODOVIA BR 280", numero: "6918", complemento: "KM 50 BLOCO A", bairro: "CAIXA D AGUA - URBANO" };

cenario("obra (07.02): material deduzido vai como valor_deducao_servico; sem material o campo nao vai", () => {
  const obra = montarPayloadNfse(contexto({ servico: { item_servico: "07.02", codigo_tributacao_nacional: "070201", codigo_nbs: "101024100", valor_bruto: 3500, valor_deducoes: 1000, valor_iss: 75, iss_retido: true, retem_inss: true, valor_inss: 275, valor_liquido: 3150, codigo_indicador_operacao: "020201", tributacao_fonte: "PERFIL", obra: LOCAL_OBRA_WEG } }), agora);
  assert.equal(obra.valor_servico, 3500);
  assert.equal(obra.valor_deducao_servico, 1000);
  assert.equal(obra.valor_cp, 275);
  assert.equal(obra.tipo_retencao_iss, 2);
  assert.equal(obra.codigo_indicador_operacao, "020201");
  assert.equal("valor_deducao_servico" in montarPayloadNfse(contexto(), agora), false);
  assert.throws(() => montarPayloadNfse(contexto({ servico: { valor_bruto: 1000, valor_deducoes: 1000 } }), agora), /menor que valor_servico/);
});

cenario("obra (070201): grupo obra da DPS pelo endereco, CNO no lugar do endereco, e trava sem local (E0370)", () => {
  const servicoObra = { item_servico: "07.02", codigo_tributacao_nacional: "070201", codigo_nbs: "101024100", codigo_indicador_operacao: "020201", tributacao_fonte: "PERFIL" };
  // Endereco, como nas NFS-e reais da WEG Tintas (fabrica de Guaramirim).
  const porEndereco = montarPayloadNfse(contexto({ servico: { ...servicoObra, obra: LOCAL_OBRA_WEG } }), agora);
  assert.equal(porEndereco.cep_obra, 89272554, "cep_obra e inteiro na Focus");
  assert.equal(porEndereco.logradouro_obra, "RODOVIA BR 280");
  assert.equal(porEndereco.numero_obra, "6918");
  assert.equal(porEndereco.complemento_obra, "KM 50 BLOCO A");
  assert.equal(porEndereco.bairro_obra, "CAIXA D AGUA - URBANO");
  assert.equal(porEndereco.codigo_obra, undefined);
  // Complemento vazio nao vai.
  assert.equal("complemento_obra" in montarPayloadNfse(contexto({ servico: { ...servicoObra, obra: { ...LOCAL_OBRA_WEG, complemento: null } } }), agora), false);
  // CNO identifica a obra sozinho.
  const porCno = montarPayloadNfse(contexto({ servico: { ...servicoObra, obra: { codigo_obra: "900123456789" } } }), agora);
  assert.equal(porCno.codigo_obra, "900123456789");
  assert.equal(porCno.cep_obra, undefined);
  // Sem local, ou com endereco incompleto, nao sai (a DPS 2/20 da OS 139 voltou com E0370).
  assert.throws(() => montarPayloadNfse(contexto({ servico: servicoObra }), agora), /local da obra .*070201 \(E0370\)/);
  assert.throws(() => montarPayloadNfse(contexto({ servico: { ...servicoObra, obra: { ...LOCAL_OBRA_WEG, bairro: " " } } }), agora), /local da obra/);
  // Aliquota na DPS so no ambiente em que o municipio nao esta ativo (Guaramirim: E0619 na homologacao,
  // DPS 2/22; na producao as NFS-e 12 e 47 sairam sem pAliq). A comparacao producao x homologacao aceita.
  const guaramirim = { ...servicoObra, obra: LOCAL_OBRA_WEG, aliquota_iss: 2, aliquota_iss_na_dps: { HOMOLOGACAO: true, PRODUCAO: false } };
  const homGuaramirim = montarPayloadNfse(contexto({ servico: guaramirim }), agora);
  const prodGuaramirim = montarPayloadNfse(contexto({ servico: guaramirim, emissao: { ambiente: "PRODUCAO", dps_numero: 3 } }), agora);
  assert.equal(homGuaramirim.percentual_aliquota_relativa_municipio, 2);
  assert.equal("percentual_aliquota_relativa_municipio" in prodGuaramirim, false);
  validarPayloadNfseProducaoContraHomologacao(homGuaramirim, prodGuaramirim);
  assert.equal("percentual_aliquota_relativa_municipio" in porEndereco, false, "sem marcacao, o municipio parametriza (E0617)");
  // Codigo que nao e de obra nao leva o grupo, mesmo com local no snapshot.
  const semObra = montarPayloadNfse(contexto({ servico: { obra: LOCAL_OBRA_WEG } }), agora);
  assert.equal(semObra.cep_obra, undefined);
  assert.equal(semObra.codigo_obra, undefined);
});

cenario("producao so sai igual a homologacao (menos data, DPS, nome do tomador e informacoes)", () => {
  const hom = montarPayloadNfse(contexto(), agora);
  const prod = montarPayloadNfse(contexto({ emissao: { ambiente: "PRODUCAO", dps_numero: 1 } }), new Date("2026-09-06T12:00:00Z"));
  validarPayloadNfseProducaoContraHomologacao(hom, prod);
  const divergente = montarPayloadNfse(contexto({ emissao: { ambiente: "PRODUCAO", dps_numero: 1 }, servico: { valor_bruto: 999 } }), agora);
  // O valor do servico arrasta PIS e COFINS proprios: a mensagem lista todos os campos.
  assert.throws(() => validarPayloadNfseProducaoContraHomologacao(hom, divergente), /diverge da homologacao autorizada nos campos .*valor_servico/);
  assert.throws(() => validarPayloadNfseProducaoContraHomologacao(hom, divergente), /valor_cofins.*valor_pis/);
  assert.throws(() => validarPayloadNfseProducaoContraHomologacao(hom, hom), /tomador real nao foi informado/);
});

cenario("competencia no mes da emissao (WEG Tintas, 09/2026), no fuso de Sao Paulo", () => {
  // Dia em Sao Paulo, nao em UTC: 21h de 14/09 ainda e 14/09; 23h30 de 30/09 ainda e setembro.
  assert.equal(hojeSaoPaulo(new Date("2026-09-14T21:00:00-03:00")), "2026-09-14");
  assert.equal(hojeSaoPaulo(new Date("2026-10-01T02:30:00Z")), "2026-09-30");
  assert.equal(pendenciaCompetenciaNfse("2026-09-01", "2026-09-30"), null);
  assert.match(pendenciaCompetenciaNfse("2026-07-29", "2026-08-03"), /fora do mes da emissao \(08\/2026\): use uma data de 01\/08\/2026 a 03\/08\/2026/);
  assert.match(pendenciaCompetenciaNfse("2026-09-15", "2026-09-14"), /depois da data de emissao/);
  assert.equal(pendenciaCompetenciaNfse("", "2026-09-14"), "Data de competencia invalida.");
  // O montador barra competencia de outro mes; 23h30 de 30/09 em Sao Paulo passa com competencia de setembro.
  assert.throws(() => montarPayloadNfse(contexto({ servico: { data_competencia: "2026-08-31" } }), new Date("2026-09-01T03:30:00Z")), /NFS-e bloqueada: Competencia 31\/08\/2026 fora do mes da emissao/);
  assert.equal(montarPayloadNfse(contexto({ servico: { data_competencia: "2026-09-30" } }), new Date("2026-10-01T02:30:00Z")).data_competencia, "2026-09-30");
  // Homologacao em 30/09 e producao em 01/10 com o mesmo snapshot: a producao nao sai.
  const snapshotSetembro = { servico: { data_competencia: "2026-09-30" } };
  montarPayloadNfse(contexto(snapshotSetembro), new Date("2026-09-30T15:00:00-03:00"));
  assert.throws(() => montarPayloadNfse(contexto({ ...snapshotSetembro, emissao: { ambiente: "PRODUCAO", dps_numero: 1 } }), new Date("2026-10-01T09:00:00-03:00")), /fora do mes da emissao/);
  assert.throws(() => montarPayloadNfse(contexto({ servico: { data_competencia: "2026-09-06" } }), agora), /depois da data de emissao/);
});

cenario("normalizacao do retorno: processando, autorizado (chave da url), erro, cancelado, webhook duplicado", () => {
  assert.equal(normalizarFocusNfse({ status: "processando_autorizacao", ref: "NFSH-1", protocolo: "P1" }).status, "PROCESSANDO");
  const ok = normalizarFocusNfse({
    status: "autorizado", ref: "NFSH-1", numero: "74798", codigo_verificacao: "ABC123",
    url: "https://www.nfse.gov.br/consultapublica/?tpc=1&chave=42054072212345678000123000000007479826039913594189",
    caminho_xml_nota_fiscal: "/arquivos/x/NFS42054072212345678000123000000007479826039913594189-nfse.xml",
    url_danfse: "https://focusnfe.s3.sa-east-1.amazonaws.com/arquivos/x/DANFSEs/NFS42054072212345678000123000000007479826039913594189.pdf",
  });
  assert.equal(ok.status, "AUTORIZADA");
  assert.equal(ok.chaveNfse, "42054072212345678000123000000007479826039913594189");
  assert.equal(ok.numero, "74798");
  assert.equal(ok.codigoVerificacao, "ABC123");
  assert.equal(ok.urlDanfse?.startsWith("https://focusnfe.s3.sa-east-1.amazonaws.com/"), true);
  const semUrl = normalizarFocusNfse({ status: "autorizado", caminho_xml_nota_fiscal: "/arquivos/NFS21113002212345678000123000000000003026031025747746-nfse.xml" });
  assert.equal(semUrl.chaveNfse, "21113002212345678000123000000000003026031025747746");
  const erro = normalizarFocusNfse({ status: "erro_autorizacao", erros: [{ codigo: "E0014", mensagem: "DPS ja existe", correcao: "renumerar" }] });
  assert.equal(erro.status, "REJEITADA");
  assert.equal(erro.mensagem, "E0014: DPS ja existe (renumerar)");
  assert.equal(normalizarFocusNfse({ status: "negado" }).status, "REJEITADA");
  assert.equal(normalizarFocusNfse({ status: "cancelado" }).status, "CANCELADA");
  assert.equal(normalizarFocusNfse({ status: "erro_cancelamento", erros: [{ codigo: "V999", mensagem: "fora do prazo" }] }).status, "AUTORIZADA", "erro_cancelamento nao cancela");
  assert.equal(normalizarFocusNfse({ codigo: "erro_validacao", mensagem: "Ja existe um DPS com esta referencia." }).status, "REJEITADA");
  assert.equal(chaveNfseDe(null, "x"), null);
});

console.log(`${cenarios} cenarios locais do pipeline de NFS-e passaram.`);
