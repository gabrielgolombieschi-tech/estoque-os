import assert from "node:assert/strict";
import { montarPayloadNfse, tipoRetencaoPisCofins, valorLiquidoNfse } from "../supabase/functions/_shared/nfse-payload.ts";
import { chaveNfseDe, normalizarFocusNfse } from "../supabase/functions/_shared/nfse-retorno.ts";

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
  assert.equal(p.codigo_indicador_operacao, "050103");
  assert.equal(p.pedido_compra, "4518");
  assert.equal(p.itens_pedido_compra, undefined);
  assert.equal(p.valor_servico, 1000);
  assert.equal(p.tributacao_iss, 1);
  assert.equal(p.percentual_aliquota_relativa_municipio, undefined, "aliquota parametrizada pelo municipio (E0617)");
  assert.equal(p.tipo_retencao_iss, 1);
  assert.equal(p.situacao_tributaria_pis_cofins, "01");
  assert.equal(p.tipo_retencao_pis_cofins, 0);
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
  assert.equal(montarPayloadNfse(contexto({ servico: { item_servico: "07.02" } }), agora).codigo_indicador_operacao, "040101");
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
