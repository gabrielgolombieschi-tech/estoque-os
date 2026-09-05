import assert from "node:assert/strict";
import {
  dataHoraNfeSaoPaulo,
  montarPayloadNfe,
  validarPayloadProducaoContraHomologacao,
} from "../supabase/functions/_shared/nfe-payload.ts";
import {
  normalizarFocus,
  validarReferenciaFocusEsperada,
} from "../supabase/functions/_shared/focus-nfe.ts";
import { validarAcaoCicloPorAmbiente } from "../supabase/functions/_shared/nfe-ciclo-guard.ts";
import {
  calcularIbsCbsTransicao2026,
  resolverIbsCbsTransicao2026,
} from "../supabase/functions/_shared/fiscal/ibs-cbs-transicao-2026.ts";

function solicitacao(overrides = {}) {
  return {
    pedido_cliente: "PC-123",
    emitente_snapshot: {
      cnpj: "13671448000189",
      razao_social: "ELETRICA SEGAU LTDA",
      nome_fantasia: "ELETRICA SEGAU",
      inscricao_estadual: "123456789",
      crt: 3,
      logradouro: "RUA TESTE",
      numero: "1",
      bairro: "CENTRO",
      cidade: "JOINVILLE",
      uf: "SC",
      cep: "89200000",
      codigo_municipio_ibge: "4209102",
    },
    destinatario_snapshot: {
      id: 1,
      nome: "CLIENTE LTDA",
      documento: "11222333000181",
      inscricao_estadual: "987654321",
      indicador_ie: "1",
      logradouro: "RUA CLIENTE",
      numero_endereco: "10",
      bairro: "CENTRO",
      cidade: "JOINVILLE",
      uf: "SC",
      cep: "89201000",
      codigo_ibge_municipio: "4209102",
    },
    operacao_snapshot: {
      natureza_operacao: "VENDA_MERCADORIA_TERCEIROS",
      finalidade_emissao: 1,
      consumidor_final: 0,
      presenca_comprador: 9,
      modalidade_frete: 9,
      valor_frete: 0,
      valor_seguro: 0,
      valor_outras_despesas: 0,
      transportador: null,
      destinacao_mercadoria: "REVENDA",
      pagamento: { forma: "15", indicador: 1, descricao: null },
    },
    ...overrides,
  };
}

function linha(overrides = {}) {
  return {
    documento_item: { item_n: 1 },
    solicitacao_item: {
      ordem: 1,
      codigo_produto: "ITEM-1",
      descricao: "ITEM TESTE",
      ncm: "85365090",
      cfop: "5102",
      origem_mercadoria: 0,
      unidade: "UN",
      unidade_tributavel: "UN",
      quantidade: 2,
      valor_unitario: 100,
      valor_desconto: 0,
      cst_icms: "00",
      csosn: null,
      cst_ipi: "53",
      ipi_codigo_enquadramento_legal: "999",
      cst_pis: "01",
      cst_cofins: "01",
      icms_modalidade_base_calculo: "3",
      // 12% coerente com a destinacao REVENDA do snapshot e com o NCM
      // 8536.50.90, que tem o beneficio do Anexo 2, Art. 7o, VII.
      aliquota_icms: 12,
      aliquota_ipi: null,
      aliquota_pis: 1.65,
      aliquota_cofins: 7.6,
      reducao_base_icms_percentual: 0,
      // 8536.50.90 esta na lista do Anexo 2, Art. 7o, VII, entao o cBenef e
      // obrigatorio — a SEFAZ rejeita beneficio de ICMS sem codigo.
      cbenef: "SC820006",
      ...overrides,
    },
  };
}

function contexto(overrides = {}) {
  return {
    emissao: { ambiente: "HOMOLOGACAO", referencia_externa: "NFEH-TESTE", tenant_id: "t", empresa_id: "e" },
    documento: {},
    solicitacao: solicitacao(),
    itens: [linha()],
    ...overrides,
  };
}

const payload = montarPayloadNfe(contexto());
assert.equal(payload.items.length, 1);
assert.equal(payload.items[0].cfop, "5102");
assert.equal(payload.items[0].icms_origem, 0);
assert.equal(payload.items[0].icms_situacao_tributaria, "00");
assert.equal(payload.valor_total, 200);
assert.equal("serie" in payload, false);
assert.equal("numero" in payload, false);
assert.equal(payload.nome_destinatario, "NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL");
assert.equal(payload.natureza_operacao, "VENDA MERCADORIA ADQ. REC. DE TERCEIROS");
assert.equal(payload.modalidade_frete, 9);
assert.equal("volumes" in payload, false);
assert.equal(payload.items[0].ipi_situacao_tributaria, "53");
assert.equal(payload.items[0].ipi_codigo_enquadramento_legal, "999");
assert.equal(payload.items[0].ibs_cbs_situacao_tributaria, "000");
assert.equal(payload.items[0].ibs_cbs_classificacao_tributaria, "000001");
assert.match(payload.informacoes_adicionais_contribuinte, /Pedido de compra do cliente: PC-123/);

const regraIbsCbs2026 = resolverIbsCbsTransicao2026(
  "VENDA_MERCADORIA_TERCEIROS",
  new Date("2026-09-03T12:00:00-03:00"),
);
assert.deepEqual(calcularIbsCbsTransicao2026(4563.40, regraIbsCbs2026), {
  vIBSUF: 4.56,
  vIBSMun: 0,
  vCBS: 41.07,
});
assert.throws(
  () => resolverIbsCbsTransicao2026("VENDA_MERCADORIA_TERCEIROS", new Date("2027-01-01T00:00:00-03:00")),
  /tabela IBS\/CBS precisa ser revisada para o exercicio 2027/,
);
assert.throws(
  () => resolverIbsCbsTransicao2026("DEVOLUCAO_VENDA", new Date("2026-09-03T12:00:00-03:00")),
  /natureza da operacao DEVOLUCAO_VENDA sem cClassTrib mapeado/,
);

const ipiDaFixture5102 = montarPayloadNfe(contexto({
  itens: [linha({ cst_ipi: null, ipi_codigo_enquadramento_legal: null })],
}));
assert.equal(ipiDaFixture5102.items[0].ipi_situacao_tributaria, "53");
assert.equal(ipiDaFixture5102.items[0].ipi_codigo_enquadramento_legal, "999");

const dataSaoPaulo = dataHoraNfeSaoPaulo(new Date("2026-09-02T21:56:09.000Z"));
assert.equal(dataSaoPaulo, "2026-09-02T18:56:09-03:00");
const payloadComHoraFixa = montarPayloadNfe(contexto(), new Date("2026-09-02T21:56:09.000Z"));
assert.equal(payloadComHoraFixa.data_emissao, "2026-09-02T18:56:09-03:00");
assert.equal(payloadComHoraFixa.data_entrada_saida, "2026-09-02T18:56:09-03:00");

const producao = montarPayloadNfe(contexto({
  emissao: { ambiente: "PRODUCAO", referencia_externa: "NFEP-TESTE", tenant_id: "t", empresa_id: "e" },
}));
assert.equal(producao.nome_destinatario, "CLIENTE LTDA");

const homologacaoCongelada = JSON.parse(JSON.stringify(payload));
const producaoCongelada = JSON.parse(JSON.stringify(producao));
homologacaoCongelada.data_emissao = "2026-09-01T10:00:00.000Z";
homologacaoCongelada.data_entrada_saida = "2026-09-01T10:00:00.000Z";
homologacaoCongelada.ambiente = "HOMOLOGACAO";
producaoCongelada.data_emissao = "2026-09-03T11:30:00.000Z";
producaoCongelada.data_entrada_saida = "2026-09-03T11:30:00.000Z";
producaoCongelada.ambiente = "PRODUCAO";
assert.doesNotThrow(() => validarPayloadProducaoContraHomologacao(homologacaoCongelada, producaoCongelada));

const producaoDivergente = JSON.parse(JSON.stringify(producaoCongelada));
producaoDivergente.items[0].cfop = "6102";
assert.throws(
  () => validarPayloadProducaoContraHomologacao(homologacaoCongelada, producaoDivergente),
  /payload fiscal diverge.*items\[0\]\.cfop/,
);

const homologacaoSemNomeLegal = JSON.parse(JSON.stringify(homologacaoCongelada));
homologacaoSemNomeLegal.nome_destinatario = "CLIENTE LTDA";
assert.throws(
  () => validarPayloadProducaoContraHomologacao(homologacaoSemNomeLegal, producaoCongelada),
  /homologacao autorizada nao usou o nome/,
);

const comValores = montarPayloadNfe(contexto({
  solicitacao: solicitacao({
    operacao_snapshot: {
      ...solicitacao().operacao_snapshot,
      valor_frete: 30,
      valor_seguro: 5,
      valor_outras_despesas: 2,
    },
  }),
  itens: [linha({ valor_desconto: 20 })],
}));
assert.equal(comValores.valor_frete, 30);
assert.equal(comValores.valor_desconto, 20);
assert.equal(comValores.valor_total, 217);

// Anexo 2, Art. 7o, VII: o beneficio e do NCM (8536.49.00, 8536.50.90,
// 8544.49.00) e vale nos dois caminhos que o regulamento autoriza. Caminho 1:
// CST 20 com base reduzida em 29,412% sobre aliquota de 17%.
const reduzida = montarPayloadNfe(contexto({
  itens: [linha({ cst_icms: "20", aliquota_icms: 17, reducao_base_icms_percentual: 29.412 })],
}));
assert.equal(reduzida.items[0].icms_base_calculo, 141.18);
assert.match(
  reduzida.informacoes_adicionais_contribuinte,
  /^Base de cálculo reduzida - produtos da indústria de automação, informática e telecomunicações - RICMS\/SC-01, Anexo 2, Art\. 7º, VII/,
);

// Caminho 2, a faculdade da alinea "a": 12% direto sobre a base integral. O
// texto e OBRIGATORIO aqui — e a condicao que o regulamento impoe para a
// faculdade — e o cBenef tambem, porque ha beneficio em uso.
const aliquotaDireta = montarPayloadNfe(contexto({
  itens: [linha({ aliquota_icms: 12 })],
}));
assert.match(aliquotaDireta.informacoes_adicionais_contribuinte, /RICMS\/SC-01, Anexo 2, Art\. 7º, VII/);
assert.equal(aliquotaDireta.items[0].codigo_beneficio_fiscal, "SC820006");
assert.throws(
  () => montarPayloadNfe(contexto({ itens: [linha({ aliquota_icms: 12, cbenef: null })] })),
  /exige o cBenef SC820006/,
);

// NCM fora da lista: os 12% vem da Lei 10.297/96, art. 19, III, "n", e nao ha
// beneficio a declarar. Foi o defeito da NF-e 2/8, que saiu afirmando base
// reduzida com CST 00, base integral e sem cBenef.
const semBeneficio = montarPayloadNfe(contexto({
  itens: [linha({ ncm: "85371020", aliquota_icms: 12, cbenef: null })],
}));
assert.ok(
  !/Art\. 7º, VII/.test(semBeneficio.informacoes_adicionais_contribuinte ?? ""),
  "NCM sem redução de base não deve declarar o benefício do Anexo 2, Art. 7º, VII",
);
assert.match(
  semBeneficio.informacoes_adicionais_contribuinte,
  /Alíquota interna de ICMS de 12%.*Lei 10\.297\/96, art\. 19, III, "n"/,
);

// A destinacao e a aliquota tem que dizer a mesma coisa. Sem esta guarda a nota
// declarava "destinacao: revenda" ao lado de "17% - operacao destinada a
// consumidor final" — e e exatamente a divergencia que a PORTOBELLO recusa.
function comDestinacao(destinacao, itens) {
  const base = solicitacao();
  return contexto({
    solicitacao: solicitacao({
      operacao_snapshot: { ...base.operacao_snapshot, destinacao_mercadoria: destinacao },
    }),
    ...(itens ? { itens } : {}),
  });
}
assert.throws(
  () => montarPayloadNfe(comDestinacao("REVENDA", [linha({ ncm: "85371020", aliquota_icms: 17, cbenef: null })])),
  /destinação revenda exige alíquota interna de 12%, e a nota está com 17%/,
);
assert.throws(
  () => montarPayloadNfe(comDestinacao("USO_CONSUMO", [linha({ ncm: "85371020", aliquota_icms: 12, cbenef: null })])),
  /exige alíquota interna de 17%, e a nota está com 12%/,
);
const paraConsumoFinal = montarPayloadNfe(
  comDestinacao("ATIVO_IMOBILIZADO", [linha({ ncm: "85371020", aliquota_icms: 17, cbenef: null })]),
);
assert.match(
  paraConsumoFinal.informacoes_adicionais_contribuinte,
  /ativo imobilizado do adquirente\. Alíquota interna de ICMS de 17%.*RICMS\/SC, art\. 26, I/,
);
assert.throws(
  () => montarPayloadNfe(comDestinacao("SUCATA")),
  /destinação da mercadoria SUCATA desconhecida/,
);
assert.throws(
  () => montarPayloadNfe(comDestinacao(null)),
  /destinação da mercadoria não confirmada/,
);

// Grupo YA (pag/detPag): sem ele o provedor assumia tPag 01 (dinheiro).
const comPagamento = montarPayloadNfe(contexto());
assert.deepEqual(comPagamento.formas_pagamento, [{
  forma_pagamento: "15",
  valor_pagamento: comPagamento.valor_total,
  indicador_pagamento: 1,
}]);

function comOperacao(pagamento) {
  const base = solicitacao();
  return contexto({
    solicitacao: solicitacao({
      operacao_snapshot: { ...base.operacao_snapshot, pagamento },
    }),
  });
}
assert.throws(
  () => montarPayloadNfe(comOperacao(null)),
  /forma de pagamento \(tPag\) não confirmada/,
);
assert.throws(
  () => montarPayloadNfe(comOperacao({ forma: "07", indicador: 0 })),
  /fora da tabela tPag/,
);
assert.throws(
  () => montarPayloadNfe(comOperacao({ forma: "15", indicador: null })),
  /indicador de pagamento/,
);
assert.throws(
  () => montarPayloadNfe(comOperacao({ forma: "15", indicador: 2 })),
  /deve ser 0 \(à vista\) ou 1 \(a prazo\)/,
);
assert.throws(
  () => montarPayloadNfe(comOperacao({ forma: "99", indicador: 0 })),
  /descreva a forma de pagamento quando escolher 99/i,
);
const pagamentoOutros = montarPayloadNfe(comOperacao({
  forma: "99",
  indicador: 0,
  descricao: "Compensacao de credito da OV",
}));
assert.equal(pagamentoOutros.formas_pagamento[0].descricao_pagamento, "Compensacao de credito da OV");

const comReferencia = montarPayloadNfe(contexto({
  documento: { nfe_referenciada: "1".repeat(44) },
}));
assert.match(comReferencia.informacoes_adicionais_contribuinte, new RegExp(`Chave da NF-e referenciada: ${"1".repeat(44)}`));

// A observacao da solicitacao vai para o infCpl, por ultimo e com espacos
// normalizados; vazia nao gera separador sobrando.
const comObservacao = montarPayloadNfe(contexto({
  solicitacao: solicitacao({ observacao: "  Composição parcial\n  da OV 344  " }),
}));
assert.match(comObservacao.informacoes_adicionais_contribuinte, / \| Composição parcial da OV 344$/);
const semObservacao = montarPayloadNfe(contexto({ solicitacao: solicitacao({ observacao: "   " }) }));
assert.doesNotMatch(semObservacao.informacoes_adicionais_contribuinte, /\|\s*$/);

// indPres 0 e de nota complementar/ajuste; numa venda normal (finNFe 1) e erro.
function comPresenca(presenca, finalidade = 1) {
  const base = solicitacao();
  return contexto({
    solicitacao: solicitacao({
      operacao_snapshot: { ...base.operacao_snapshot, presenca_comprador: presenca, finalidade_emissao: finalidade },
    }),
  });
}
assert.throws(() => montarPayloadNfe(comPresenca(0)), /presença do comprador 0 \(não se aplica\)/);
assert.equal(montarPayloadNfe(comPresenca(9)).presenca_comprador, 9);
assert.equal(montarPayloadNfe(comPresenca(1)).presenca_comprador, 1);

const semTransportadora = montarPayloadNfe(contexto({
  solicitacao: solicitacao({
    operacao_snapshot: { ...solicitacao().operacao_snapshot, modalidade_frete: 1 },
  }),
}));
assert.equal(semTransportadora.modalidade_frete, 9);

const simples = montarPayloadNfe(contexto({
  solicitacao: solicitacao({ emitente_snapshot: { ...solicitacao().emitente_snapshot, crt: 1 } }),
  itens: [linha({ cst_icms: null, csosn: "102", aliquota_icms: null, icms_modalidade_base_calculo: null })],
}));
assert.equal(simples.items[0].icms_situacao_tributaria, "102");

const isento = montarPayloadNfe(contexto({
  solicitacao: solicitacao({
    destinatario_snapshot: { ...solicitacao().destinatario_snapshot, indicador_ie: "2" },
  }),
}));
assert.equal("inscricao_estadual_destinatario" in isento, false);

const naoContribuinteComIe = montarPayloadNfe(contexto({
  solicitacao: solicitacao({
    destinatario_snapshot: { ...solicitacao().destinatario_snapshot, indicador_ie: "9" },
  }),
}));
assert.equal(naoContribuinteComIe.inscricao_estadual_destinatario, "987654321");

assert.throws(
  () => montarPayloadNfe(contexto({ emissao: { ambiente: "INVALIDO" } })),
  /HOMOLOGACAO ou PRODUCAO/,
);
assert.throws(
  () => montarPayloadNfe(contexto({ solicitacao: solicitacao({ destinatario_snapshot: null }) })),
  /snapshot de destinat/,
);
assert.throws(
  () => montarPayloadNfe(contexto({ itens: [linha({ cfop: null })] })),
  /CFOP/,
);
assert.throws(
  () => montarPayloadNfe(contexto({ itens: [linha({ origem_mercadoria: null })] })),
  /item ITEM-1, origem da mercadoria/,
);
assert.throws(
  () => montarPayloadNfe(contexto({
    solicitacao: solicitacao({ operacao_snapshot: { ...solicitacao().operacao_snapshot, natureza_operacao: "SLUG_DESCONHECIDO" } }),
  })),
  /não consta na fixture provisória de agosto\/2026/,
);
assert.throws(() => montarPayloadNfe(contexto({
  solicitacao: solicitacao({
    operacao_snapshot: {
      ...solicitacao().operacao_snapshot,
      modalidade_frete: 0,
      transportador: { nome: "TRANSPORTADORA TESTE" },
    },
  }),
})), /ao menos um volume quando houver transporte/);
assert.throws(
  () => montarPayloadNfe(contexto({ itens: [linha({ valor_unitario: 0 })] })),
  /valor unitário deve ser maior que zero/,
);
assert.throws(
  () => montarPayloadNfe(contexto({ itens: [linha({ cst_icms: "00", csosn: "102" })] })),
  /CST de ICMS ou CSOSN/,
);
assert.throws(
  () => montarPayloadNfe(contexto({
    emissao: { ambiente: "PRODUCAO", referencia_externa: "NFEP-TESTE", tenant_id: "t", empresa_id: "e" },
    itens: [linha({ ipi_codigo_enquadramento_legal: null })],
  })),
  /cEnq do perfil de operação/,
);

for (const [cst, cEnq] of [["02", "301"], ["52", "399"], ["04", "001"], ["54", "099"], ["05", "101"], ["55", "199"], ["53", "601"], ["53", "608"], ["53", "999"]]) {
  assert.doesNotThrow(() => montarPayloadNfe(contexto({
    emissao: { ambiente: "PRODUCAO", referencia_externa: "NFEP-TESTE", tenant_id: "t", empresa_id: "e" },
    itens: [linha({ cst_ipi: cst, ipi_codigo_enquadramento_legal: cEnq })],
  })));
}
for (const [cst, cEnq] of [["02", "999"], ["04", "301"], ["05", "001"], ["53", "600"], ["53", "609"]]) {
  assert.throws(() => montarPayloadNfe(contexto({
    emissao: { ambiente: "PRODUCAO", referencia_externa: "NFEP-TESTE", tenant_id: "t", empresa_id: "e" },
    itens: [linha({ cst_ipi: cst, ipi_codigo_enquadramento_legal: cEnq })],
  })), new RegExp(`incompatível com o CST ${cst}`));
}
assert.throws(
  () => montarPayloadNfe(contexto({ itens: [linha({ reducao_base_icms_percentual: null })] })),
  /redução da base de ICMS/,
);
const payloadSemVersaoOuDefaultsIbs = montarPayloadNfe(contexto({
  itens: [linha({ cst_ibs_cbs: null, cclass_trib: null, cclass_trib_versao: null, ibs_cbs_json: null })],
}));
assert.equal(payloadSemVersaoOuDefaultsIbs.items[0].ibs_cbs_classificacao_tributaria, "000001");
assert.equal("cclass_trib_versao" in payloadSemVersaoOuDefaultsIbs.items[0], false);

// Dados vivos e perfil podem ate existir no objeto: o builder nao os consulta.
const imuneAoCadastroVivo = montarPayloadNfe({
  ...contexto(),
  cliente: { indicador_ie: "9", documento: "invalido" },
  empresa: { cnpj: "invalido" },
  perfil_operacao: { cfop_interno: "9999", serie: 999 },
});
assert.equal(imuneAoCadastroVivo.items[0].cfop, "5102");
assert.equal(imuneAoCadastroVivo.indicador_inscricao_estadual_destinatario, 1);

const autorizadoA = normalizarFocus({ status: "autorizado", ref: "NFEH-1", chave_nfe: "1".repeat(44), protocolo: "123" });
const autorizadoB = normalizarFocus({ status: "autorizado", ref: "NFEH-1", chave_nfe: "1".repeat(44), protocolo: "123" });
assert.deepEqual(autorizadoA, autorizadoB);
assert.equal(normalizarFocus({ status: "processando_autorizacao", ref: "NFEH-2" }).status, "PROCESSANDO");
// Respostas reais do DELETE /v2/nfe em homologacao (05/09/2026): a rejeicao da
// 2/1 contem "cancel" no status e nao pode virar CANCELADA.
assert.equal(normalizarFocus({
  status: "erro_cancelamento",
  status_sefaz: "501",
  mensagem_sefaz: "Rejeicao: Prazo de Cancelamento Superior ao Previsto na Legislacao",
}).status, "REJEITADA");
const canceladaReal = normalizarFocus({
  status: "cancelado",
  status_sefaz: "135",
  mensagem_sefaz: "Evento registrado e vinculado a NF-e",
  numero_protocolo: "342260000903334",
});
assert.equal(canceladaReal.status, "CANCELADA");
assert.equal(canceladaReal.protocolo, "342260000903334");
assert.equal(validarReferenciaFocusEsperada("NFEH-X", "NFEH-X"), "NFEH-X");
assert.throws(
  () => validarReferenciaFocusEsperada("NFEH-Y", "NFEH-X"),
  /difere da emissao esperada/,
);

for (const acao of ["CANCELAR", "TESTAR_CANCELAMENTO_FORA_PRAZO", "CARTA_CORRECAO", "INUTILIZAR"]) {
  assert.throws(
    () => validarAcaoCicloPorAmbiente(acao, "PRODUCAO"),
    /PRODUCAO esta bloqueado antes da chamada ao provedor/,
  );
}
assert.doesNotThrow(() => validarAcaoCicloPorAmbiente("INUTILIZAR", "HOMOLOGACAO"));
assert.doesNotThrow(() => validarAcaoCicloPorAmbiente("TESTAR_CANCELAMENTO_FORA_PRAZO", "HOMOLOGACAO"));
assert.throws(
  () => validarAcaoCicloPorAmbiente("EMAIL", "HOMOLOGACAO"),
  /e-mail exige NF-e AUTORIZADA em PRODUCAO/,
);
assert.doesNotThrow(() => validarAcaoCicloPorAmbiente("EMAIL", "PRODUCAO"));

console.log("77 cenarios locais do pipeline NF-e passaram.");
