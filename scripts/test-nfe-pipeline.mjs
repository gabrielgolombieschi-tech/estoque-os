import assert from "node:assert/strict";
import {
  dataHoraNfeSaoPaulo,
  dataVencimentoSaoPaulo,
  montarPayloadNfe,
  validarPayloadProducaoContraHomologacao,
} from "../supabase/functions/_shared/nfe-payload.ts";
import {
  normalizarFocus,
  validarReferenciaFocusEsperada,
} from "../supabase/functions/_shared/focus-nfe.ts";
import { validarAcaoCicloPorAmbiente } from "../supabase/functions/_shared/nfe-ciclo-guard.ts";
import { faltaCbenefAutomacaoSc } from "../supabase/functions/_shared/fiscal/icms-sc-destinacao.ts";
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
      serie_nfe: 2,
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
      pagamento: {
        forma: "15",
        indicador: 1,
        descricao: null,
        parcelas: [{ numero: "001", dias: 15, valor: null }],
        fatura_numero: "OV-SEG-00004-026",
      },
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
assert.equal(payload.serie, 2);
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

// NF-e de industrializacao a partir da OS (05/09/2026): natOp literal da
// fixture, CFOP 5101/6101 e a mesma regra IBS/CBS de 2026. Os campos fiscais
// da linha chegam preenchidos pela conferencia da OS (fixture + cadastro).
const industrializacao = montarPayloadNfe(contexto({
  solicitacao: solicitacao({
    operacao_snapshot: {
      ...solicitacao().operacao_snapshot,
      natureza_operacao: "VENDA_INDUSTRIALIZACAO_INTERNA",
      destinacao_mercadoria: "USO_CONSUMO",
      consumidor_final: 1,
    },
  }),
  itens: [linha({ cfop: "5101", ncm: "73269090", aliquota_icms: 17, cbenef: null, cst_ipi: "50", aliquota_ipi: 9.75, ipi_codigo_enquadramento_legal: "999" })],
}));
assert.equal(industrializacao.natureza_operacao, "VENDA INDUSTRIALIZACAO DENTRO ESTADO");
assert.equal(industrializacao.items[0].cfop, "5101");
assert.equal(industrializacao.items[0].icms_aliquota, 17);
assert.equal(industrializacao.items[0].ipi_situacao_tributaria, "50");
assert.equal(industrializacao.items[0].ipi_valor, 19.5);
assert.equal(industrializacao.items[0].ibs_cbs_classificacao_tributaria, "000001");
assert.equal(industrializacao.valor_total, 219.5);
assert.equal(
  resolverIbsCbsTransicao2026("VENDA_INDUSTRIALIZACAO_INTERESTADUAL", new Date("2026-09-05T12:00:00-03:00")).cfops[0],
  "6101",
);

// NF-e 3766 real (industrializacao, consumidor final): o IPI integra a base do
// ICMS. 69.232,80 + IPI 9,75% (6.750,20) = base 75.983,00 x 17% = 12.917,11.
// Na revenda (indFinal = 0) o IPI fica fora da base.
const nota3766 = montarPayloadNfe(contexto({
  solicitacao: solicitacao({
    operacao_snapshot: { ...solicitacao().operacao_snapshot, natureza_operacao: "VENDA_INDUSTRIALIZACAO_INTERNA", destinacao_mercadoria: "USO_CONSUMO", consumidor_final: 1 },
  }),
  itens: [linha({ cfop: "5101", ncm: "85372090", quantidade: 1, valor_unitario: 69232.8, aliquota_icms: 17, cbenef: null, cst_ipi: "50", aliquota_ipi: 9.75, ipi_codigo_enquadramento_legal: "999" })],
}));
assert.equal(nota3766.items[0].ipi_valor, 6750.2);
assert.equal(nota3766.items[0].icms_base_calculo, 75983);
assert.equal(nota3766.items[0].icms_valor, 12917.11);
assert.equal(nota3766.items[0].ipi_base_calculo, 69232.8);
assert.equal(nota3766.valor_total, 75983);
// Revenda so carrega IPI quando a equiparacao a industrial esta declarada; o que este
// caso guarda e a base do ICMS, que segue sem o IPI porque a destinacao e revenda.
const revendaComIpi = montarPayloadNfe(contexto({
  itens: [linha({ quantidade: 1, valor_unitario: 1000, cst_ipi: "50", aliquota_ipi: 9.75, ipi_codigo_enquadramento_legal: "999", origem_mercadoria: 1, equiparado_industrial: true })],
}));
assert.equal(revendaComIpi.items[0].ipi_valor, 97.5);
assert.equal(revendaComIpi.items[0].icms_base_calculo, 1000, "revenda: IPI fora da base do ICMS");
assert.equal(revendaComIpi.items[0].icms_valor, 120);

// O IPI na base do ICMS segue a destinacao, nao o indFinal (CF art. 155, §2º, XI:
// entre contribuintes E destinado a industrializacao ou comercializacao — cumulativo).
// Manutencao e o caso que separa os dois: o comprador e contribuinte (indFinal 0), mas
// manter o proprio parque nao e industrializar nem revender, entao o IPI entra na base.
// Lendo por indFinal a OS 319 sairia com R$ 1.657,50 de ICMS a menos a cada R$ 100 mil
// (contabilidade, 10/09/2026).
// A aliquota acompanha a destinacao pelo mesmo fato: 12% quando a mercadoria segue em
// operacao tributada, 17% quando para no adquirente. Passar a aliquota "errada" aqui
// faria a nota abortar — e e essa a trava que a NF-e 2/14 nao tinha.
const porDestinacao = (destinacao) => montarPayloadNfe(contexto({
  solicitacao: solicitacao({
    operacao_snapshot: {
      ...solicitacao().operacao_snapshot,
      natureza_operacao: "VENDA_INDUSTRIALIZACAO_INTERNA",
      destinacao_mercadoria: destinacao,
      consumidor_final: 0,
    },
  }),
  itens: [linha({
    cfop: "5101", ncm: "90328989", quantidade: 1, valor_unitario: 1000,
    aliquota_icms: destinacao === "MANUTENCAO" ? 17 : 12,
    cbenef: null, cst_ipi: "50", aliquota_ipi: 9.75, ipi_codigo_enquadramento_legal: "999",
  })],
})).items[0];

const manutencao = porDestinacao("MANUTENCAO");
assert.equal(manutencao.ipi_valor, 97.5);
assert.equal(manutencao.icms_base_calculo, 1097.5, "manutencao: IPI dentro da base do ICMS");
assert.equal(manutencao.icms_aliquota, 17, "manutencao: para no adquirente, entao 17%");
assert.equal(manutencao.icms_valor, 186.58);

const insumo = porDestinacao("INSUMO");
assert.equal(insumo.icms_base_calculo, 1000, "insumo: IPI fora da base do ICMS");
assert.equal(insumo.icms_valor, 120);

const consignado = porDestinacao("CONSIGNADO");
assert.equal(consignado.icms_base_calculo, 1000, "consignacao segue para revenda: IPI fora da base");

// NCM 8460.90.90 (maquina industrial, Convenio ICMS 52/91; contador 06/09/2026):
// nao sai a 17% cheia nem a 12% direto. Exige CST 20 + cBenef + base reduzida
// ate a carga efetiva de 8,80%: interna 17% x (1 - 48,235%) e PR 12% x (1 - 26,667%).
const industrial = (extra) => contexto({
  solicitacao: solicitacao({
    operacao_snapshot: { ...solicitacao().operacao_snapshot, natureza_operacao: "VENDA_INDUSTRIALIZACAO_INTERNA", destinacao_mercadoria: "ATIVO_IMOBILIZADO", consumidor_final: 1 },
  }),
  itens: [linha({ cfop: "5101", ncm: "84609090", quantidade: 1, valor_unitario: 1000, cst_ipi: "53", ipi_codigo_enquadramento_legal: "999", ...extra })],
});
assert.throws(() => montarPayloadNfe(industrial({ aliquota_icms: 17, cbenef: null })), /Convênio ICMS 52\/91/);
assert.throws(() => montarPayloadNfe(industrial({ aliquota_icms: 12, cbenef: null })), /Convênio ICMS 52\/91/);
assert.throws(() => montarPayloadNfe(industrial({ cst_icms: "20", aliquota_icms: 17, reducao_base_icms_percentual: 48.235, cbenef: null })), /sem cBenef/);
const maquina = montarPayloadNfe(industrial({ cst_icms: "20", aliquota_icms: 17, reducao_base_icms_percentual: 48.235, cbenef: "SC000000" }));
assert.equal(maquina.items[0].icms_situacao_tributaria, "20");
assert.equal(maquina.items[0].icms_base_calculo, 517.65);
assert.equal(maquina.items[0].icms_valor, 88);
assert.equal(String(maquina.informacoes_adicionais_contribuinte).includes("Convênio ICMS 52/91"), true);

const ipiDaFixture5102 = montarPayloadNfe(contexto({
  itens: [linha({ cst_ipi: null, ipi_codigo_enquadramento_legal: null })],
}));
assert.equal(ipiDaFixture5102.items[0].ipi_situacao_tributaria, "53");
assert.equal(ipiDaFixture5102.items[0].ipi_codigo_enquadramento_legal, "999");

// NF-e 2/50 (11/09/2026): soft-starter WEG revendido, NCM 9032.89.11 tributado a 9,75%
// na TIPI, origem nacional, CFOP 5102. Saiu com IPI destacado (470,05) e ainda somou o
// IPI a base do ICMS. Revenda nao destaca IPI: quem deve e o industrial e quem a ele se
// equipara (RIPI art. 9o). A TIPI diz quanto o FABRICANTE paga naquele NCM, nao que o
// revendedor deva o imposto.
const softStarter = (destino, extra) => contexto({
  solicitacao: solicitacao({
    operacao_snapshot: { ...solicitacao().operacao_snapshot, destinacao_mercadoria: destino, consumidor_final: 0 },
  }),
  itens: [linha({
    cfop: "5102", ncm: "90328911", quantidade: 1, valor_unitario: 4821, origem_mercadoria: 0,
    aliquota_icms: destino === "REVENDA" ? 12 : 17, cbenef: null,
    cst_ipi: "50", aliquota_ipi: 9.75, ipi_codigo_enquadramento_legal: "999", ...extra,
  })],
});
assert.throws(
  () => montarPayloadNfe(softStarter("REVENDA")),
  /revenda em CFOP 5102 não destaca IPI/,
  "revenda com CST 50 e sem equiparacao tem de abortar",
);

// Sem IPI a nota sai limpa. Sao os numeros que a 2/50 deveria ter tido.
const semIpi = montarPayloadNfe(softStarter("REVENDA", { cst_ipi: "53", aliquota_ipi: null }));
assert.equal(semIpi.items[0].ipi_situacao_tributaria, "53");
assert.equal(semIpi.items[0].ipi_valor, undefined, "sem vIPI no item");
assert.equal(semIpi.items[0].icms_base_calculo, 4821, "vBC do ICMS = vProd, sem IPI");
assert.equal(semIpi.items[0].icms_valor, 578.52);
assert.equal(semIpi.items[0].valor_total_item, 4821);
assert.equal(semIpi.valor_total, 4821, "vNF sem IPI");

// A mesma nota com destinacao manutencao: a mercadoria para no adquirente, entao os
// 12% do art. 19, III, "n" nao valem (§ 3º, "a") e a aliquota e 17%. Sem IPI, a base
// segue sendo o vProd.
const softStarterManutencao = montarPayloadNfe(softStarter("MANUTENCAO", { cst_ipi: "53", aliquota_ipi: null })).items[0];
assert.equal(softStarterManutencao.icms_aliquota, 17);
assert.equal(softStarterManutencao.icms_base_calculo, 4821);
assert.equal(softStarterManutencao.icms_valor, 819.57);

// Os dois efeitos da destinacao andam juntos: 12% com IPI dentro da base e a
// contradicao que produziu a NF-e 2/14, e agora aborta.
assert.throws(
  () => montarPayloadNfe(contexto({
    solicitacao: solicitacao({
      operacao_snapshot: { ...solicitacao().operacao_snapshot, natureza_operacao: "VENDA_INDUSTRIALIZACAO_INTERNA", destinacao_mercadoria: "MANUTENCAO", consumidor_final: 0 },
    }),
    itens: [linha({ cfop: "5101", ncm: "90328989", quantidade: 1, valor_unitario: 16553.07, aliquota_icms: 12, cbenef: null, cst_ipi: "50", aliquota_ipi: 9.75, ipi_codigo_enquadramento_legal: "999" })],
  })),
  /os 12% valem porque a mercadoria segue em operação tributada/,
  "12% com IPI dentro da base tem de abortar",
);

// Chave de seguranca importada por nos: origem 1, equiparada, revenda em 5102 COM IPI —
// a equiparacao autoriza o destaque e nao muda o CFOP (Consulta SP 22712/2020). Como a
// destinacao e revenda, o IPI fica FORA da base do ICMS.
const chaveImportada = montarPayloadNfe(contexto({
  itens: [linha({
    cfop: "5102", ncm: "85365090", quantidade: 1, valor_unitario: 239.7, origem_mercadoria: 1,
    equiparado_industrial: true, aliquota_icms: 12, cst_ipi: "50", aliquota_ipi: 9.75,
    ipi_codigo_enquadramento_legal: "999",
  })],
})).items[0];
assert.equal(chaveImportada.cfop, "5102", "equiparacao nao muda o CFOP");
assert.equal(chaveImportada.ipi_situacao_tributaria, "50");
assert.equal(chaveImportada.ipi_valor, 23.37);
assert.equal(chaveImportada.icms_base_calculo, 239.7, "revenda: IPI fora da base");
assert.equal(chaveImportada.icms_valor, 28.76);

// Os 12% e o IPI fora da base dependem de DUAS condicoes: destinatario contribuinte
// (a alinea "n" e "mercadorias destinadas a contribuinte"; a CF fala em operacao
// "entre contribuintes") E mercadoria que segue em operacao tributada. Quem nao tem
// IE nunca alcanca os 12%, declare a destinacao que declarar — nao ha operacao
// subsequente para tributar.
const revendaParaNaoContribuinte = montarPayloadNfe(contexto({
  solicitacao: solicitacao({
    destinatario_snapshot: {
      ...solicitacao().destinatario_snapshot,
      indicador_ie: "9",
      inscricao_estadual: null,
    },
    operacao_snapshot: { ...solicitacao().operacao_snapshot, destinacao_mercadoria: "REVENDA", consumidor_final: 1 },
  }),
  itens: [linha({
    cfop: "5102", ncm: "85365090", quantidade: 1, valor_unitario: 1000, origem_mercadoria: 1,
    equiparado_industrial: true, aliquota_icms: 17, cst_ipi: "50", aliquota_ipi: 9.75,
    ipi_codigo_enquadramento_legal: "999",
  })],
})).items[0];
assert.equal(revendaParaNaoContribuinte.icms_aliquota, 17, "sem IE: 17% mesmo declarando revenda");
assert.equal(revendaParaNaoContribuinte.icms_base_calculo, 1097.5, "sem IE: IPI dentro da base");
assert.equal(revendaParaNaoContribuinte.icms_valor, 186.58);

// Origem e equiparacao tem de concordar nos dois sentidos.
assert.throws(
  () => montarPayloadNfe(contexto({ itens: [linha({ origem_mercadoria: 1, cst_ipi: "53" })] })),
  /origem 1 .* sem a marca de equiparado a industrial/,
  "origem 1 sem a flag tem de abortar",
);
assert.throws(
  () => montarPayloadNfe(contexto({ itens: [linha({ origem_mercadoria: 2, equiparado_industrial: true, cst_ipi: "53" })] })),
  /equiparado a industrial mas com origem 2/,
  "flag com origem 2 tem de abortar",
);

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
  // Nao ancorado no inicio: com indFinal 1 e tabela IBPT a nota abre o infCpl com o
  // "Valor aproximado dos tributos" (Lei 12.741/2012), e o texto do beneficio vem depois.
  reduzida.informacoes_adicionais_contribuinte,
  /Base de cálculo reduzida - produtos da indústria de automação, informática e telecomunicações - RICMS\/SC-01, Anexo 2, Art\. 7º, VII/,
);
// Todos os itens da nota usam o beneficio: o texto fica sem a lista de itens.
assert.doesNotMatch(reduzida.informacoes_adicionais_contribuinte, /Itens? \d/);

// Nota misturada (Gabriel, 16/09/2026): a observacao do beneficio lista, pelo numero do
// item na nota, so os itens que usaram a reducao. O calculo de ICMS nao muda.
const itemSemReducaoSc = (ordem) => ({
  ...linha({ ordem, codigo_produto: `SEM-BENEF-${ordem}`, ncm: "85364100", cbenef: null }),
  documento_item: { item_n: ordem },
});
const itemComReducaoSc = (ordem, extra = {}) => ({
  ...linha({ ordem, codigo_produto: `COM-BENEF-${ordem}`, ...extra }),
  documento_item: { item_n: ordem },
});
const misturada = montarPayloadNfe(contexto({
  itens: [
    itemSemReducaoSc(1),
    itemComReducaoSc(2),
    itemComReducaoSc(3, { cst_icms: "20", aliquota_icms: 17, reducao_base_icms_percentual: 29.412 }),
  ],
}));
assert.match(
  misturada.informacoes_adicionais_contribuinte,
  /(^|\| )Itens 2, 3: Base de cálculo reduzida - produtos da indústria de automação, informática e telecomunicações - RICMS\/SC-01, Anexo 2, Art\. 7º, VII/,
);
assert.equal(misturada.items[0].icms_valor, 24);
assert.equal(misturada.items[2].icms_base_calculo, 141.18);
// O N da observacao e o nItem do det (numero_item), nao a posicao num array ja filtrado
// so com os itens do beneficio. Nota de 4 itens, beneficio nos itens 1 e 3: num array
// filtrado eles seriam "1, 2"; o certo e "Itens 1, 3".
const quatroItens = montarPayloadNfe(contexto({
  itens: [
    itemComReducaoSc(1),
    itemSemReducaoSc(2),
    itemComReducaoSc(3, { cst_icms: "20", aliquota_icms: 17, reducao_base_icms_percentual: 29.412 }),
    itemSemReducaoSc(4),
  ],
}));
assert.deepEqual(quatroItens.items.map((item) => item.numero_item), [1, 2, 3, 4]);
assert.deepEqual(
  quatroItens.items.filter((item) => item.codigo_beneficio_fiscal).map((item) => item.numero_item),
  [1, 3],
);
assert.match(
  quatroItens.informacoes_adicionais_contribuinte,
  /(^|\| )Itens 1, 3: Base de cálculo reduzida - produtos da indústria de automação, informática e telecomunicações - RICMS\/SC-01, Anexo 2, Art\. 7º, VII/,
);
assert.doesNotMatch(quatroItens.informacoes_adicionais_contribuinte, /Itens 1, 2:/);
// O calculo dos itens com beneficio nao muda com a lista na observacao.
assert.equal(quatroItens.items[0].icms_valor, 24);
assert.equal(quatroItens.items[2].icms_base_calculo, 141.18);

const umComBeneficio = montarPayloadNfe(contexto({ itens: [itemSemReducaoSc(1), itemComReducaoSc(2)] }));
assert.match(
  umComBeneficio.informacoes_adicionais_contribuinte,
  /(^|\| )Item 2: Base de cálculo reduzida - produtos da indústria de automação/,
);
assert.equal(
  (umComBeneficio.informacoes_adicionais_contribuinte.match(/Base de cálculo reduzida/g) ?? []).length,
  1,
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
// Trava de 16/09/2026: CST 20 num NCM do Art. 7º, VII sem cBenef bloqueia com
// QUALQUER reducao — antes so a carga efetiva de 12% disparava, e um CST 20 com
// outra reducao seguia para a Focus sem o codigo.
assert.throws(
  () => montarPayloadNfe(contexto({
    itens: [linha({ cst_icms: "20", aliquota_icms: 17, reducao_base_icms_percentual: 29.412, cbenef: null })],
  })),
  /Emissão bloqueada: item ITEM-1, CST 20 com o benefício de redução de base do RICMS\/SC-01, Anexo 2, Art\. 7º, VII \(NCM 8536\.50\.90\) e sem cBenef/,
);
assert.throws(
  () => montarPayloadNfe(contexto({
    itens: [linha({ cst_icms: "20", aliquota_icms: 17, reducao_base_icms_percentual: 10, cbenef: null })],
  })),
  /CST 20 com o benefício .* sem cBenef/,
);
// Interestadual nao tem o beneficio (so saidas internas): nada a travar por ele.
assert.equal(
  faltaCbenefAutomacaoSc({ codigo: "X", ncm: "85365090", situacaoIcms: "20", cargaEfetivaIcms: 12, cbenef: null, interestadual: true }),
  null,
);
// NCM fora da lista nao e o beneficio do Art. 7º, VII.
assert.equal(
  faltaCbenefAutomacaoSc({ codigo: "X", ncm: "85364100", situacaoIcms: "20", cargaEfetivaIcms: 12, cbenef: null, interestadual: false }),
  null,
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

// Grupo cobr: fatura + duplicatas a partir das parcelas do snapshot, com a
// data calculada na emissao (America/Sao_Paulo). Parcela unica sem valor usa o
// total; varias parcelas precisam fechar com o total.
const comDuplicatas = montarPayloadNfe(contexto(), new Date("2026-09-05T14:45:32.000Z"));
assert.equal(comDuplicatas.numero_fatura, "OV-SEG-00004-026");
assert.equal(comDuplicatas.valor_original_fatura, 200);
assert.equal(comDuplicatas.valor_liquido_fatura, 200);
assert.deepEqual(comDuplicatas.duplicatas, [{ numero: "001", data_vencimento: "2026-09-20", valor: 200 }]);
assert.equal(dataVencimentoSaoPaulo(new Date("2026-09-05T02:30:00.000Z"), 0), "2026-09-04");
const duasParcelas = montarPayloadNfe(contexto({
  solicitacao: solicitacao({
    operacao_snapshot: {
      ...solicitacao().operacao_snapshot,
      pagamento: { forma: "15", indicador: 1, parcelas: [{ dias: 30, valor: 120 }, { dias: 60, valor: 80 }] },
    },
  }),
}), new Date("2026-09-05T14:45:32.000Z"));
assert.deepEqual(duasParcelas.duplicatas.map((d) => [d.numero, d.data_vencimento, d.valor]), [
  ["001", "2026-10-05", 120],
  ["002", "2026-11-04", 80],
]);
assert.throws(
  () => montarPayloadNfe(contexto({
    solicitacao: solicitacao({
      operacao_snapshot: {
        ...solicitacao().operacao_snapshot,
        pagamento: { forma: "15", indicador: 1, parcelas: [{ dias: 30, valor: 120 }, { dias: 60, valor: 70 }] },
      },
    }),
  })),
  /parcelas somam R\$ 190\.00 e a nota vale R\$ 200\.00/,
);
assert.throws(
  () => montarPayloadNfe(contexto({
    solicitacao: solicitacao({
      operacao_snapshot: { ...solicitacao().operacao_snapshot, pagamento: { forma: "15", indicador: 1 } },
    }),
  })),
  /venda a prazo exige ao menos uma parcela/,
);
const aVista = montarPayloadNfe(contexto({
  solicitacao: solicitacao({
    operacao_snapshot: { ...solicitacao().operacao_snapshot, pagamento: { forma: "01", indicador: 0 } },
  }),
}));
assert.equal("duplicatas" in aVista, false);
// A comparacao HOM x PROD ignora as datas das duplicatas (dependem do dia da emissao).
const homDup = JSON.parse(JSON.stringify(montarPayloadNfe(contexto(), new Date("2026-09-04T12:00:00.000Z"))));
const prodDup = JSON.parse(JSON.stringify(montarPayloadNfe(contexto({
  emissao: { ambiente: "PRODUCAO", referencia_externa: "NFEP-TESTE", tenant_id: "t", empresa_id: "e" },
}), new Date("2026-09-05T12:00:00.000Z"))));
assert.notEqual(homDup.duplicatas[0].data_vencimento, prodDup.duplicatas[0].data_vencimento);
assert.doesNotThrow(() => validarPayloadProducaoContraHomologacao(homDup, prodDup));
// A observacao automatica da composicao nao vai para o cliente.
const observacaoAutomatica = montarPayloadNfe(contexto({
  solicitacao: solicitacao({ observacao: "Composicao parcial da OV OV-SEG-00004-026." }),
}));
assert.doesNotMatch(observacaoAutomatica.informacoes_adicionais_contribuinte, /Composicao parcial/);

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
  solicitacao: solicitacao({ observacao: "  Entrega combinada\n  com o comprador  " }),
}));
assert.match(comObservacao.informacoes_adicionais_contribuinte, / \| Entrega combinada com o comprador$/);
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

for (const acao of ["TESTAR_CANCELAMENTO_FORA_PRAZO", "CARTA_CORRECAO", "INUTILIZAR"]) {
  assert.throws(
    () => validarAcaoCicloPorAmbiente(acao, "PRODUCAO"),
    /PRODUCAO esta bloqueado antes da chamada ao provedor/,
  );
}
// Cancelamento real dentro das 24h (05/09/2026): a guarda deixa passar; quem
// limita prazo, recebimento e claim e o banco (fn_nfe_cancelamento_producao_*).
assert.doesNotThrow(() => validarAcaoCicloPorAmbiente("CANCELAR", "PRODUCAO"));
assert.doesNotThrow(() => validarAcaoCicloPorAmbiente("INUTILIZAR", "HOMOLOGACAO"));
assert.doesNotThrow(() => validarAcaoCicloPorAmbiente("TESTAR_CANCELAMENTO_FORA_PRAZO", "HOMOLOGACAO"));
assert.throws(
  () => validarAcaoCicloPorAmbiente("EMAIL", "HOMOLOGACAO"),
  /e-mail exige NF-e AUTORIZADA em PRODUCAO/,
);
assert.doesNotThrow(() => validarAcaoCicloPorAmbiente("EMAIL", "PRODUCAO"));

// Excecao "ICMS 12% por exigencia do destinatario" (PORTOBELLO, 16/09/2026). Manutencao
// vai a 17%, mas o contribuinte pode exigir 12% pela OC: item sem SC820006 sai CST 00 a
// 12%, indFinal 1, IPI de manutencao continua na base, e o texto cita os itens e a OC.
const operacaoExcecao = (extra = {}) => ({
  ...solicitacao().operacao_snapshot,
  destinacao_mercadoria: "MANUTENCAO",
  consumidor_final: 1,
  excecao_aliquota_destinatario: { numero_oc: "4500123456", ativada_em: "2026-09-16T10:00:00-03:00" },
  ...extra,
});
const comExcecao = (itens, extraOperacao = {}, extraSolicitacao = {}) => montarPayloadNfe(contexto({
  solicitacao: solicitacao({ operacao_snapshot: operacaoExcecao(extraOperacao), ...extraSolicitacao }),
  itens,
}));

// FAB com IPI e ICMS a 12%: vBC = vProd + vIPI = 1.000,00 + 97,50.
const fabExcecao = comExcecao(
  [linha({ codigo_produto: "FAB-0001", cfop: "5101", ncm: "90328989", quantidade: 1, valor_unitario: 1000, aliquota_icms: 12, cbenef: null, cst_ipi: "50", aliquota_ipi: 9.75, ipi_codigo_enquadramento_legal: "999" })],
  { natureza_operacao: "VENDA_INDUSTRIALIZACAO_INTERNA" },
);
assert.equal(fabExcecao.consumidor_final, 1, "excecao mantem indFinal 1");
assert.equal(fabExcecao.items[0].icms_situacao_tributaria, "00");
assert.equal(fabExcecao.items[0].icms_aliquota, 12);
assert.equal(fabExcecao.items[0].ipi_valor, 97.5, "IPI nao muda");
assert.equal(fabExcecao.items[0].icms_base_calculo, 1097.5, "FAB: vBC do ICMS = vProd + vIPI");
assert.equal(fabExcecao.items[0].icms_valor, 131.7);
assert.match(
  fabExcecao.informacoes_adicionais_contribuinte,
  /Item 1: ICMS à alíquota de 12% \(RICMS\/SC-01, art\. 26, III, "n"\) aplicada por determinação do destinatário, conforme OC nº 4500123456, utilização informada: manutenção\. O destinatário responde solidariamente pela diferença de alíquota, nos termos do art\. 26, § 6º, do RICMS\/SC-01\./,
);
assert.doesNotMatch(fabExcecao.informacoes_adicionais_contribuinte, /Lei 10\.297\/96/, "sem citar a alinea n da lei junto");

// Revenda sem SC820006: 12%, CST 00, base integral.
const revendaExcecao = comExcecao([linha({ ncm: "90328911", quantidade: 1, valor_unitario: 4821, aliquota_icms: 12, cbenef: null })]);
assert.equal(revendaExcecao.items[0].icms_situacao_tributaria, "00");
assert.equal(revendaExcecao.items[0].icms_aliquota, 12);
assert.equal(revendaExcecao.items[0].icms_base_calculo, 4821);
assert.equal(revendaExcecao.items[0].icms_valor, 578.52);
assert.equal("codigo_beneficio_fiscal" in revendaExcecao.items[0], false, "excecao nao e beneficio: sem cBenef");

// Nota mista: item 1 com SC820006 (CST 20, regra propria) e item 2 comum. O texto da
// excecao lista so o item 2; o do beneficio, so o item 1.
const mistaExcecao = comExcecao([
  linha({ ncm: "85365090", quantidade: 1, valor_unitario: 100, cst_icms: "20", aliquota_icms: 17, reducao_base_icms_percentual: 29.412, cbenef: "SC820006" }),
  linha({ codigo_produto: "ITEM-2", ncm: "90328911", quantidade: 1, valor_unitario: 200, aliquota_icms: 12, cbenef: null }),
]);
assert.equal(mistaExcecao.items[0].icms_situacao_tributaria, "20");
assert.equal(mistaExcecao.items[0].icms_reducao_base_calculo, 29.412);
assert.equal(mistaExcecao.items[0].codigo_beneficio_fiscal, "SC820006");
assert.equal(mistaExcecao.items[1].icms_situacao_tributaria, "00");
assert.match(mistaExcecao.informacoes_adicionais_contribuinte, /Item 2: ICMS à alíquota de 12%/);
assert.doesNotMatch(mistaExcecao.informacoes_adicionais_contribuinte, /Itens? [\d, ]*1[\d, ]*: ICMS à alíquota/, "o item com SC820006 fica fora do texto da excecao");
assert.match(mistaExcecao.informacoes_adicionais_contribuinte, /Item 1: Base de cálculo reduzida/);

// Sem numero de OC: bloqueia.
assert.throws(
  () => comExcecao([linha({ ncm: "90328911", aliquota_icms: 12, cbenef: null })], { excecao_aliquota_destinatario: { numero_oc: "  " } }),
  /exige o número da OC/,
);
// Destinatario nao contribuinte: excecao indisponivel.
assert.throws(
  () => comExcecao(
    [linha({ ncm: "90328911", aliquota_icms: 12, cbenef: null })],
    {},
    { destinatario_snapshot: { ...solicitacao().destinatario_snapshot, indicador_ie: "9", inscricao_estadual: null } },
  ),
  /só vale para destinatário contribuinte/,
);
// Destinacao revenda nao usa a excecao (os 12% ja sao a regra).
assert.throws(
  () => comExcecao([linha({ ncm: "90328911", aliquota_icms: 12, cbenef: null })], { destinacao_mercadoria: "REVENDA" }),
  /não se aplica à destinação revenda/,
);
// Excecao com item comum a 17% ou indFinal 0: nao sai.
assert.throws(
  () => comExcecao([linha({ ncm: "90328911", aliquota_icms: 17, cbenef: null })]),
  /sai com CST 00 a 12% sobre a base integral/,
);
assert.throws(
  () => comExcecao([linha({ ncm: "90328911", aliquota_icms: 12, cbenef: null })], { consumidor_final: 0 }),
  /mantém indFinal = 1/,
);
// Com a excecao, a frase "Destinacao informada pelo destinatario" nao se repete.
assert.doesNotMatch(fabExcecao.informacoes_adicionais_contribuinte, /Destinação informada pelo destinatário/);
assert.doesNotMatch(revendaExcecao.informacoes_adicionais_contribuinte, /Destinação informada pelo destinatário/);
// indFinal 1 sem tabela IBPT: a Focus acrescenta "Trib. aprox." ao fim; o infCpl termina em " |".
assert.match(fabExcecao.informacoes_adicionais_contribuinte, /Pedido de compra do cliente: PC-123 \|$/);
assert.equal("valor_total_tributos" in fabExcecao, false);
// indFinal 0: a Focus nao acrescenta nada, e o texto nao termina com separador.
assert.doesNotMatch(payload.informacoes_adicionais_contribuinte, /\|$/);

// NF-e 2/55: xMun do destinatario saiu "4218004", o codigo IBGE no lugar do nome.
const comMunicipio = (extraSolicitacao, extraOperacao = {}) => () => montarPayloadNfe(contexto({
  solicitacao: solicitacao({ ...extraSolicitacao, operacao_snapshot: { ...solicitacao().operacao_snapshot, ...extraOperacao } }),
}));
assert.throws(
  comMunicipio({ destinatario_snapshot: { ...solicitacao().destinatario_snapshot, cidade: "4218004" } }),
  /município do destinatário está como "4218004", só com dígitos/,
);
assert.throws(
  comMunicipio({ emitente_snapshot: { ...solicitacao().emitente_snapshot, cidade: " 4209102 " } }),
  /município do emitente está como "4209102", só com dígitos/,
);
assert.throws(
  comMunicipio({}, {
    modalidade_frete: 1,
    transportador: { nome: "TEDE TRANSPORTES LTDA", documento: "02484555001072", municipio: "4202404", uf: "SC" },
    volumes: [{ quantidade: 1, peso_liquido: 2, peso_bruto: 2.1 }],
  }),
  /município do transportador está como "4202404", só com dígitos/,
);
assert.equal(
  comMunicipio({ destinatario_snapshot: { ...solicitacao().destinatario_snapshot, cidade: "Tijucas" } })().municipio_destinatario,
  "Tijucas",
);

// Remessa para conserto (16/09/2026, cortinas SICK em garantia): CFOP 6915, ICMS CST 50 com
// SC840007, IPI 55 cEnq 108, PIS/COFINS 08, IBS/CBS 410/410999 sem base, tPag 90 com vPag 0,
// textos legais no infCpl e nenhum imposto destacado.
const itemRemessa = (extra = {}) => linha({
  codigo_produto: "1211502", ncm: "85365090", cfop: "6915", origem_mercadoria: 2, quantidade: 1,
  valor_unitario: 2563.6, cst_icms: "50", aliquota_icms: null, reducao_base_icms_percentual: 0,
  cbenef: "SC840007", cst_ipi: "55", ipi_codigo_enquadramento_legal: "108", aliquota_ipi: null,
  cst_pis: "08", cst_cofins: "08", aliquota_pis: null, aliquota_cofins: null, ...extra,
});
const contextoRemessa = (extraOperacao = {}, itens = [itemRemessa()]) => contexto({
  solicitacao: solicitacao({
    destinatario_snapshot: { ...solicitacao().destinatario_snapshot, nome: "SICK SOLUCAO EM SENSORES LTDA", uf: "SP", cidade: "SAO BERNARDO DO CAMPO", codigo_ibge_municipio: "3548708" },
    operacao_snapshot: {
      ...solicitacao().operacao_snapshot,
      natureza_operacao: "REMESSA_CONSERTO_INTERESTADUAL",
      destinacao_mercadoria: null,
      consumidor_final: 0,
      pagamento: { forma: "90", indicador: 0, descricao: null, parcelas: null, fatura_numero: null },
      ...extraOperacao,
    },
  }),
  itens,
});
const remessa = montarPayloadNfe(contextoRemessa());
assert.equal(remessa.natureza_operacao, "REMESSA PARA CONSERTO FORA DO ESTADO");
assert.equal(remessa.local_destino, 2);
assert.equal(remessa.consumidor_final, 0);
assert.equal(remessa.valor_total, 2563.6);
assert.deepEqual(remessa.formas_pagamento, [{ forma_pagamento: "90", valor_pagamento: 0 }], "tPag 90 sem valor e sem indPag");
assert.equal("duplicatas" in remessa, false);
const itemR = remessa.items[0];
assert.equal(itemR.cfop, "6915");
assert.equal(itemR.icms_situacao_tributaria, "50");
assert.equal("icms_aliquota" in itemR, false, "CST 50 sem base nem aliquota");
assert.equal(itemR.codigo_beneficio_fiscal, "SC840007");
assert.equal(itemR.ipi_situacao_tributaria, "55");
assert.equal(itemR.ipi_codigo_enquadramento_legal, "108");
assert.equal("ipi_valor" in itemR, false);
assert.equal(itemR.pis_situacao_tributaria, "08");
assert.equal("pis_valor" in itemR, false);
assert.equal(itemR.ibs_cbs_situacao_tributaria, "410");
assert.equal(itemR.ibs_cbs_classificacao_tributaria, "410999");
assert.equal("ibs_uf_aliquota" in itemR, false, "CST 410: nem aliquota zerada (cStat 1021)");
assert.equal("cbs_aliquota" in itemR, false);
assert.equal("ibs_cbs_base_calculo" in itemR, false, "CST 410 sem grupo de valores");
assert.equal("cbs_valor" in itemR, false);
assert.equal(itemR.valor_total_item, 2563.6);
assert.equal(remessa.ibs_cbs_base_calculo, 0);
assert.equal(remessa.cbs_valor_total, 0);
assert.equal(remessa.ibs_cbs_is_valor_total, 2563.6, "vNFTot continua a soma dos itens");
assert.equal("valor_total_tributos" in remessa, false);
assert.equal(
  remessa.informacoes_adicionais_contribuinte,
  "ICMS suspenso, conforme o inciso I do art. 27 do Anexo 2 do Decreto nº 2.870/01 - RICMS-SC/01 (cBenef SC840007) | "
  + "IPI suspenso, conforme o inciso VI do art. 43 do Decreto nº 7.212/10 - RIPI/10 | "
  + "Mercadoria remetida para conserto ou análise em garantia, com retorno ao estabelecimento de origem no prazo de 180 dias | "
  + "Pedido de compra do cliente: PC-123",
);
assert.doesNotMatch(remessa.informacoes_adicionais_contribuinte, /Destinação informada/);
// Remessa com tributacao de venda nao sai.
assert.throws(() => montarPayloadNfe(contextoRemessa({}, [itemRemessa({ cst_icms: "00", aliquota_icms: 12 })])), /não está tributado como remessa para conserto: CST ICMS 00/);
assert.throws(() => montarPayloadNfe(contextoRemessa({}, [itemRemessa({ cbenef: null })])), /cBenef vazio \(esperado SC840007\)/);
assert.throws(() => montarPayloadNfe(contextoRemessa({}, [itemRemessa({ cst_ipi: "53", ipi_codigo_enquadramento_legal: "999" })])), /CST IPI 53 \(esperado 55\)/);
assert.throws(() => montarPayloadNfe(contextoRemessa({}, [itemRemessa({ cfop: "5915" })])), /nao possui cClassTrib aprovado para o CFOP 5915/);
// Remessa com pagamento, ou venda sem pagamento, nao saem.
assert.throws(() => montarPayloadNfe(contextoRemessa({ pagamento: { forma: "15", indicador: 0 } })), /remessa para conserto sai sem pagamento \(tPag 90\)/);
assert.throws(
  () => montarPayloadNfe(contexto({ solicitacao: solicitacao({ operacao_snapshot: { ...solicitacao().operacao_snapshot, pagamento: { forma: "90", indicador: 0 } } }) })),
  /forma de pagamento 90 \(sem pagamento\) só vale para remessa/,
);
// Dentro de SC: 5915.
const remessaInterna = montarPayloadNfe(contexto({
  solicitacao: solicitacao({ operacao_snapshot: { ...solicitacao().operacao_snapshot, natureza_operacao: "REMESSA_CONSERTO_INTERNA", destinacao_mercadoria: null, consumidor_final: 0, pagamento: { forma: "90", indicador: 0 } } }),
  itens: [itemRemessa({ cfop: "5915" })],
}));
assert.equal(remessaInterna.natureza_operacao, "REMESSA PARA CONSERTO DENTRO DO ESTADO");
assert.equal(remessaInterna.local_destino, 1);

// Sem a excecao a trava continua bloqueando manutencao a 12%.
assert.throws(
  () => montarPayloadNfe(contexto({
    solicitacao: solicitacao({ operacao_snapshot: { ...solicitacao().operacao_snapshot, destinacao_mercadoria: "MANUTENCAO", consumidor_final: 0 } }),
    itens: [linha({ ncm: "90328911", aliquota_icms: 12, cbenef: null })],
  })),
  /destinação manutenção exige alíquota interna de 17%, e a nota está com 12%/,
);

// Retorno de mercadoria de terceiros (16/09/2026): a NF-e 900356/1 da WEG Tintas (CFOP 5901,
// 4 GL de tinta a R$ 400) volta inteira em 5902. Espelho da origem, NFref com a chave, ICMS 50
// com SC840008, IPI 55 cEnq 108, PIS/COFINS 08, IBS/CBS 410/410999, tPag 90, sem cobr, infAdFisco
// com a base legal e infCpl com a nota de origem; modFrete da tela sem transportadora.
const CHAVE_WEG = "42260660621141000404550010009003561304254706";
const itemRetorno = (extra = {}) => linha({
  codigo_produto: "000000000050017810", descricao: "MATERIAIS PARA PINTURA", ncm: "32099019", cfop: "5902",
  origem_mercadoria: 0, unidade: "GL", unidade_tributavel: "GL", quantidade: 4, valor_unitario: 400, valor_desconto: 0,
  cst_icms: "50", aliquota_icms: null, reducao_base_icms_percentual: 0, cbenef: "SC840008",
  cst_ipi: "55", ipi_codigo_enquadramento_legal: "108", aliquota_ipi: null,
  cst_pis: "08", cst_cofins: "08", aliquota_pis: null, aliquota_cofins: null, ...extra,
});
const contextoRetorno = (extraOperacao = {}, itens = [itemRetorno()], extraSolicitacao = {}) => contexto({
  solicitacao: solicitacao({
    pedido_cliente: null,
    observacao: "Retorno das latas da OP 1234",
    destinatario_snapshot: {
      id: null, nome: "WEG TINTAS LTDA", documento: "60621141000404", inscricao_estadual: "257843876", indicador_ie: "1",
      logradouro: "RODOVIA BR 280 - KM50", numero_endereco: "6918", complemento: "BLOCO A", bairro: "CAIXA D AGUA",
      cidade: "Guaramirim", uf: "SC", cep: "89270000", codigo_ibge_municipio: "4206504", telefone: "4732764000",
    },
    operacao_snapshot: {
      ...solicitacao().operacao_snapshot,
      natureza_operacao: "RETORNO_REMESSA_TERCEIROS",
      destinacao_mercadoria: null,
      consumidor_final: 0,
      presenca_comprador: 9,
      modalidade_frete: 9,
      nfe_referenciada: CHAVE_WEG,
      pagamento: { forma: "90", indicador: 0, descricao: null, parcelas: null, fatura_numero: null },
      retorno_terceiros: { remessa_id: "r", chave: CHAVE_WEG, numero: "900356", serie: "1", data_emissao: "10/06/2026", cfop_origem: "5901", tipo: "INDUSTRIALIZACAO" },
      ...extraOperacao,
    },
    ...extraSolicitacao,
  }),
  itens,
});
const retorno = montarPayloadNfe(contextoRetorno());
assert.equal(retorno.natureza_operacao, "RETORNO DE MERCADORIA UTILIZADA NA INDUSTRIALIZACAO");
assert.equal(retorno.natureza_operacao.length <= 60, true);
assert.equal(retorno.finalidade_emissao, 1, "retorno nao e devolucao (finNFe 4)");
assert.equal(retorno.tipo_documento, 1);
assert.equal(retorno.local_destino, 1);
assert.equal(retorno.consumidor_final, 0);
assert.equal(retorno.presenca_comprador, 9);
assert.equal(retorno.cnpj_destinatario, "60621141000404");
assert.equal(retorno.inscricao_estadual_destinatario, "257843876");
assert.equal(retorno.municipio_destinatario, "Guaramirim");
assert.equal(retorno.codigo_municipio_destinatario, "4206504");
// NFref so na nota real: a SEFAZ de homologacao nao conhece a chave de producao (cStat 267).
assert.equal("notas_referenciadas" in retorno, false, "homologacao sem NFref");
const retornoProducao = montarPayloadNfe({ ...contextoRetorno(), emissao: { ambiente: "PRODUCAO", referencia_externa: "NFEP-TESTE", tenant_id: "t", empresa_id: "e" } });
assert.deepEqual(retornoProducao.notas_referenciadas, [{ chave_nfe: CHAVE_WEG }], "NFref com a chave da origem em producao");
assert.equal(retornoProducao.nome_destinatario, "WEG TINTAS LTDA");
assert.doesNotThrow(() => validarPayloadProducaoContraHomologacao(retorno, retornoProducao), "NFref a mais na producao nao e divergencia");
assert.equal(retorno.items.length, 1);
const itemT = retorno.items[0];
assert.equal(itemT.codigo_produto, "000000000050017810", "cProd igual ao da origem, com os zeros");
assert.equal(itemT.descricao, "MATERIAIS PARA PINTURA");
assert.equal(itemT.codigo_ncm, "32099019");
assert.equal(itemT.cfop, "5902");
assert.equal(itemT.unidade_comercial, "GL");
assert.equal(itemT.quantidade_comercial, 4);
assert.equal(itemT.valor_unitario_comercial, 400);
assert.equal(itemT.valor_bruto, 1600);
assert.equal(itemT.icms_origem, 0);
assert.equal(itemT.icms_situacao_tributaria, "50");
assert.equal("icms_base_calculo" in itemT, false, "CST 50 sem base");
assert.equal("icms_valor" in itemT, false);
assert.equal(itemT.codigo_beneficio_fiscal, "SC840008", "cBenef do retorno, nao o SC840007 da origem");
assert.equal(itemT.ipi_situacao_tributaria, "55");
assert.equal(itemT.ipi_codigo_enquadramento_legal, "108");
assert.equal("ipi_valor" in itemT, false);
assert.equal(itemT.pis_situacao_tributaria, "08");
assert.equal(itemT.cofins_situacao_tributaria, "08");
assert.equal("pis_valor" in itemT, false);
assert.equal(itemT.ibs_cbs_situacao_tributaria, "410");
assert.equal(itemT.ibs_cbs_classificacao_tributaria, "410999");
assert.equal("ibs_uf_aliquota" in itemT, false, "CST 410 so com CST e cClassTrib");
assert.equal(itemT.valor_total_item, 1600);
assert.equal(retorno.valor_produtos, 1600);
assert.equal(retorno.valor_total, 1600, "vNF = vProd");
assert.equal(retorno.valor_frete, 0);
assert.equal(retorno.ibs_cbs_is_valor_total, 1600);
assert.equal("valor_total_tributos" in retorno, false);
assert.deepEqual(retorno.formas_pagamento, [{ forma_pagamento: "90", valor_pagamento: 0 }], "tPag 90 vPag 0 sem indPag");
assert.equal("duplicatas" in retorno, false, "sem grupo cobr");
assert.equal("numero_fatura" in retorno, false);
assert.equal(retorno.modalidade_frete, 9);
assert.equal("nome_transportador" in retorno, false);
assert.equal("volumes" in retorno, false);
// infAdFisco no modelo da NF 3427 do Vertex: base do ICMS + nota de origem (+ IPI, porque o grupo vai).
assert.equal(
  retorno.informacoes_adicionais_fisco,
  "ICMS SUSPENSO CONFORME ANEXO 2, ART. 27, II, DO RICMS-SC. RETORNO DA NF-E 900356 DE 10/06/2026. IPI SUSPENSO CONFORME ART. 43, VII, DO RIPI (DECRETO 7.212/2010).",
);
assert.equal(
  retorno.informacoes_adicionais_contribuinte,
  `RETORNO INTEGRAL DA MERCADORIA RECEBIDA PELA NF-E N. 900356 SERIE 1 DE 10/06/2026, CHAVE ${CHAVE_WEG}. MERCADORIA DE TERCEIROS. SEM COBRANCA. | Retorno das latas da OP 1234`,
);
assert.doesNotMatch(retorno.informacoes_adicionais_contribuinte, /Chave da NF-e referenciada/);
assert.doesNotMatch(retorno.informacoes_adicionais_contribuinte, /Destinação informada/);
// modFrete da tela sem transportadora e sem rebaixar para 9; volumes da origem quando existem.
const retornoFrete4 = montarPayloadNfe(contextoRetorno({
  modalidade_frete: 4,
  volumes: [{ quantidade: 4, especie: "VOLUMES", peso_liquido: 5.56, peso_bruto: 5.56 }],
}));
assert.equal(retornoFrete4.modalidade_frete, 4);
assert.equal("nome_transportador" in retornoFrete4, false);
assert.deepEqual(retornoFrete4.volumes, [{ quantidade: 4, especie: "VOLUMES", marca: undefined, numero: undefined, peso_liquido: 5.56, peso_bruto: 5.56 }]);
const retornoFrete1SemVolume = montarPayloadNfe(contextoRetorno({ modalidade_frete: 1, volumes: [] }));
assert.equal(retornoFrete1SemVolume.modalidade_frete, 1, "sem volumes na origem a modalidade fica a da tela");
assert.equal("volumes" in retornoFrete1SemVolume, false);
assert.throws(() => montarPayloadNfe(contextoRetorno({ modalidade_frete: 2 })), /modalidade do frete 2 não vale para o retorno de terceiros/);
// Conserto (origem 5915): 5916 com a natureza de conserto; fora de SC, 6916.
const retornoConserto = montarPayloadNfe(contextoRetorno({ natureza_operacao: "RETORNO_REMESSA_TERCEIROS_CONSERTO" }, [itemRetorno({ cfop: "5916" })]));
assert.equal(retornoConserto.natureza_operacao, "RETORNO DE MERCADORIA RECEBIDA PARA CONSERTO");
assert.equal(retornoConserto.items[0].cfop, "5916");
// Fora da lista da natureza o IBS/CBS barra antes da trava do retorno.
assert.throws(() => montarPayloadNfe(contextoRetorno({}, [itemRetorno({ cfop: "5916" })])), /RETORNO_REMESSA_TERCEIROS nao possui cClassTrib aprovado para o CFOP 5916/);
// 6916 e da mesma natureza; se ele cabe no ambito e a RPC que decide (fn_remessa_terceiros_retorno_criar).
assert.equal(montarPayloadNfe(contextoRetorno({ natureza_operacao: "RETORNO_REMESSA_TERCEIROS_CONSERTO" }, [itemRetorno({ cfop: "6916" })])).items[0].cfop, "6916");
// Tributacao fora do retorno, pagamento, referencia e origem: a nota nao sai.
assert.throws(() => montarPayloadNfe(contextoRetorno({}, [itemRetorno({ cst_icms: "00", aliquota_icms: 17 })])), /não está tributado como retorno de mercadoria de terceiros: CST ICMS 00/);
assert.throws(() => montarPayloadNfe(contextoRetorno({}, [itemRetorno({ cbenef: "SC840007" })])), /cBenef SC840007 \(esperado SC840008\)/);
assert.throws(() => montarPayloadNfe(contextoRetorno({}, [itemRetorno({ cst_ipi: "53", ipi_codigo_enquadramento_legal: "999" })])), /CST IPI 53 \(esperado 55\)/);
assert.throws(() => montarPayloadNfe(contextoRetorno({}, [itemRetorno({ valor_desconto: 10 })])), /desconto 10/);
assert.throws(() => montarPayloadNfe(contextoRetorno({ pagamento: { forma: "15", indicador: 0 } })), /retorno de terceiros sai sem pagamento \(tPag 90/);
assert.throws(() => montarPayloadNfe(contextoRetorno({ nfe_referenciada: "42260660621141000404550010009003571304254700" })), /chave referenciada do retorno não é a da NF-e de origem/);
assert.throws(() => montarPayloadNfe(contextoRetorno({ retorno_terceiros: null })), /retorno de terceiros sem a nota de origem/);
// A venda continua exigindo destinacao e pagamento de verdade.
assert.throws(
  () => montarPayloadNfe(contexto({ solicitacao: solicitacao({ operacao_snapshot: { ...solicitacao().operacao_snapshot, destinacao_mercadoria: null } }) })),
  /destinação da mercadoria não confirmada/,
);

// Devolucao de compra (17/09/2026): 41,55 kg do tubo 401014 da NF-e 121481/3 da Acos America
// voltam em 5201, finNFe 4 com NFref nos dois ambientes, impostos da origem (ICMS 00 a 12% com
// o IPI fora da base, IPI 50/999 a 3,25%, PIS/COFINS 01), IBS/CBS 000/000001, tPag 90, sem
// cobr, volumes da tela sem transportadora, infAdFisco e infCpl com a nota de origem.
const CHAVE_ACOS = "42260808819200000182550030001214811001242895";
const itemDevolucao = (extra = {}) => linha({
  codigo_produto: "401014", descricao: 'TB RED 76,10x3,75 NBR5580 2.1/2" (66)', ncm: "73063090", cfop: "5201",
  origem_mercadoria: 0, unidade: "KG", unidade_tributavel: "KG", quantidade: 41.55, valor_unitario: 7.3, valor_desconto: 0,
  cst_icms: "00", aliquota_icms: 12, reducao_base_icms_percentual: 0, cbenef: null, icms_modalidade_base_calculo: "3",
  cst_ipi: "50", ipi_codigo_enquadramento_legal: "999", aliquota_ipi: 3.25,
  cst_pis: "01", cst_cofins: "01", aliquota_pis: 1.65, aliquota_cofins: 7.6, ...extra,
});
const contextoDevolucao = (extraOperacao = {}, itens = [itemDevolucao()], extraSolicitacao = {}) => contexto({
  solicitacao: solicitacao({
    pedido_cliente: null,
    observacao: "Tubo fora de medida",
    destinatario_snapshot: {
      id: null, nome: "ACOS AMERICA LTDA", documento: "08819200000182", inscricao_estadual: "255387644", indicador_ie: "1",
      logradouro: "RUA DONA FRANCISCA", numero_endereco: "7796", complemento: null, bairro: "DISTRITO INDUSTRIAL",
      cidade: "Joinville", uf: "SC", cep: "89219600", codigo_ibge_municipio: "4209102", telefone: "4734179500",
    },
    operacao_snapshot: {
      ...solicitacao().operacao_snapshot,
      natureza_operacao: "DEVOLUCAO_COMPRA",
      finalidade_emissao: 4,
      destinacao_mercadoria: null,
      consumidor_final: 0,
      presenca_comprador: 9,
      modalidade_frete: 0,
      transportador: null,
      volumes: [{ quantidade: 1, peso_liquido: 41.55, peso_bruto: 41.55 }],
      nfe_referenciada: CHAVE_ACOS,
      pagamento: { forma: "90", indicador: 0, descricao: null, parcelas: null, fatura_numero: null },
      devolucao_compra: {
        nf_entrada_id: 2205, operacao_id: "o", chave: CHAVE_ACOS, numero: "121481", serie: "3", data_emissao: "24/08/2026",
        emitente_nome: "ACOS AMERICA LTDA", cfop: "5201", ambito: "INTERNA", itens_texto: "ITEM 2 (401014): 41,55 KG DE 2.742,30 KG",
        itens: [{ ordem: 1, nitem: 2, codigo: "401014" }],
        chave_referencia_homologacao: "42260913671448000189550020000000641164283751",
        referencia_homologacao_nitem: 1,
      },
      ...extraOperacao,
    },
    ...extraSolicitacao,
  }),
  itens,
});
const devolucao = montarPayloadNfe(contextoDevolucao());
assert.equal(devolucao.natureza_operacao, "DEVOLUCAO DE COMPRA PARA INDUSTRIALIZACAO");
assert.equal(devolucao.finalidade_emissao, 4, "devolucao e finNFe 4 nos dois ambientes");
assert.equal(devolucao.local_destino, 1);
assert.equal(devolucao.consumidor_final, 0);
assert.equal(devolucao.presenca_comprador, 9);
// Nota de teste: destinatario = a propria empresa (VC02-50), com o nome de homologacao.
assert.equal(devolucao.cnpj_destinatario, devolucao.cnpj_emitente, "em homologacao a devolucao sai para a propria empresa");
assert.equal(devolucao.inscricao_estadual_destinatario, devolucao.inscricao_estadual_emitente);
assert.equal(devolucao.municipio_destinatario, devolucao.municipio_emitente);
assert.equal(devolucao.nome_destinatario, "NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL");
// NFref: em homologacao a NF-e de homologacao da empresa para ela mesma (a SEFAZ de teste
// recusa com 321 a chave real, uma NF-e de venda da empresa e a origem como nota modelo 1);
// em producao a chave real. A comparacao entre ambientes tolera o grupo.
const CHAVE_HOM = "42260913671448000189550020000000641164283751";
assert.equal("notas_referenciadas" in devolucao, false, "devolucao sem NFref no cabecalho: a referencia e por item (rejeicao 1010 com os dois)");
assert.throws(
  () => montarPayloadNfe(contextoDevolucao({ devolucao_compra: { ...contextoDevolucao().solicitacao.operacao_snapshot.devolucao_compra, chave_referencia_homologacao: null } })),
  /devolução em homologação precisa de uma NF-e de homologação da empresa para ela mesma/,
);
// DFeReferenciado do item (NT 2025.002-RTC): na nota de teste, a referencia e o item 1 dela; na
// real, a chave de entrada e o nItem 2 de origem.
assert.equal(devolucao.items[0].chave_acesso_dfe_referenciado, CHAVE_HOM);
assert.equal(devolucao.items[0].numero_item_dfe_referenciado, "1");
const devolucaoProducao = montarPayloadNfe({ ...contextoDevolucao(), emissao: { ambiente: "PRODUCAO", referencia_externa: "NFEP-DEV", tenant_id: "t", empresa_id: "e" } });
assert.equal(devolucaoProducao.finalidade_emissao, 4);
assert.equal("notas_referenciadas" in devolucaoProducao, false);
assert.equal(devolucaoProducao.items[0].chave_acesso_dfe_referenciado, CHAVE_ACOS, "a nota real referencia a chave de entrada no item");
assert.equal(devolucaoProducao.items[0].numero_item_dfe_referenciado, "2", "nItem de origem do item devolvido");
assert.equal(devolucaoProducao.cnpj_destinatario, "08819200000182", "a nota real vai ao fornecedor");
assert.equal(devolucaoProducao.inscricao_estadual_destinatario, "255387644");
assert.equal(devolucaoProducao.nome_destinatario, "ACOS AMERICA LTDA");
assert.doesNotThrow(() => validarPayloadProducaoContraHomologacao(devolucao, devolucaoProducao), "destinatario e referencias diferentes entre ambientes nao sao divergencia na devolucao");
assert.throws(
  () => validarPayloadProducaoContraHomologacao(devolucao, { ...devolucaoProducao, items: [{ ...devolucaoProducao.items[0], icms_aliquota: 17 }] }),
  /diverge da homologacao autorizada no campo items\[0\]\.icms_aliquota/,
);
assert.throws(
  () => montarPayloadNfe(contextoDevolucao({ devolucao_compra: { ...contextoDevolucao().solicitacao.operacao_snapshot.devolucao_compra, itens: [] } })),
  /sem a nota de origem/,
);
// A finalidade continua congelada entre os ambientes.
assert.throws(
  () => validarPayloadProducaoContraHomologacao(retorno, { ...retornoProducao, finalidade_emissao: 4 }),
  /diverge da homologacao autorizada no campo finalidade_emissao/,
);
assert.equal(devolucaoProducao.nome_destinatario, "ACOS AMERICA LTDA");
assert.doesNotThrow(() => validarPayloadProducaoContraHomologacao(devolucao, devolucaoProducao));
assert.equal(devolucao.items.length, 1);
const itemD = devolucao.items[0];
assert.equal(itemD.cfop, "5201");
assert.equal(itemD.codigo_produto, "401014");
assert.equal(itemD.unidade_comercial, "KG");
assert.equal(itemD.quantidade_comercial, 41.55);
assert.equal(itemD.valor_unitario_comercial, 7.3);
assert.ok(Math.abs(itemD.valor_bruto - 303.315) < 0.006, `vProd proporcional (${itemD.valor_bruto})`);
const vProdD = itemD.valor_bruto;
assert.equal(itemD.icms_origem, 0);
assert.equal(itemD.icms_situacao_tributaria, "00");
assert.equal(itemD.icms_modalidade_base_calculo, "3");
assert.equal(itemD.icms_base_calculo, vProdD, "IPI fora da base do ICMS, como na origem");
assert.equal(itemD.icms_aliquota, 12);
assert.equal(itemD.icms_valor, Math.round(vProdD * 12) / 100);
assert.equal("codigo_beneficio_fiscal" in itemD, false);
assert.equal(itemD.ipi_situacao_tributaria, "50");
assert.equal(itemD.ipi_codigo_enquadramento_legal, "999");
assert.equal(itemD.ipi_base_calculo, vProdD);
assert.equal(itemD.ipi_aliquota, 3.25);
assert.equal(itemD.ipi_valor, Math.round(vProdD * 3.25) / 100);
assert.equal(itemD.pis_situacao_tributaria, "01");
assert.equal(itemD.pis_base_calculo, Math.round((vProdD - itemD.icms_valor) * 100) / 100, "PIS/COFINS sem o ICMS na base, como na origem");
assert.equal(itemD.pis_aliquota_porcentual, 1.65);
assert.equal(itemD.cofins_situacao_tributaria, "01");
assert.equal(itemD.cofins_aliquota_porcentual, 7.6);
assert.equal(itemD.ibs_cbs_situacao_tributaria, "000");
assert.equal(itemD.ibs_cbs_classificacao_tributaria, "000001");
assert.equal(itemD.ibs_uf_aliquota, 0.1);
assert.equal(itemD.cbs_aliquota, 0.9);
assert.equal(itemD.valor_total_item, Math.round((vProdD + itemD.ipi_valor) * 100) / 100, "vItem com o IPI");
assert.equal("valor_total_tributos" in devolucao, false, "sem tributos aproximados: nao e venda");
assert.equal(devolucao.valor_produtos, vProdD);
assert.equal(devolucao.valor_total, Math.round((vProdD + itemD.ipi_valor) * 100) / 100, "vNF = vProd + IPI");
assert.deepEqual(devolucao.formas_pagamento, [{ forma_pagamento: "90", valor_pagamento: 0 }]);
assert.equal("duplicatas" in devolucao, false);
assert.equal(devolucao.modalidade_frete, 0, "modalidade da tela sem transportadora");
assert.equal("nome_transportador" in devolucao, false);
assert.deepEqual(devolucao.volumes, [{ quantidade: 1, especie: undefined, marca: undefined, numero: undefined, peso_liquido: 41.55, peso_bruto: 41.55 }]);
assert.equal(
  devolucao.informacoes_adicionais_fisco,
  "DEVOLUCAO DE COMPRA REFERENTE A NF-E 121481 DE 24/08/2026. ICMS, IPI, PIS E COFINS DESTACADOS PROPORCIONALMENTE CONFORME A NOTA DE ORIGEM.",
);
assert.equal(
  devolucao.informacoes_adicionais_contribuinte,
  `DEVOLUCAO PARCIAL DA MERCADORIA RECEBIDA PELA NF-E N. 121481 SERIE 3 DE 24/08/2026, CHAVE ${CHAVE_ACOS}. ITEM 2 (401014): 41,55 KG DE 2.742,30 KG. SEM COBRANCA. | Tubo fora de medida`,
);
assert.doesNotMatch(devolucao.informacoes_adicionais_contribuinte, /Chave da NF-e referenciada/);
assert.doesNotMatch(devolucao.informacoes_adicionais_contribuinte, /Destinação informada/);
// Transportadora informada entra com a modalidade escolhida.
const devolucaoTransp = montarPayloadNfe(contextoDevolucao({ modalidade_frete: 1, transportador: { nome: "EXPRESSO SAO MIGUEL", documento: "01234567000189", uf: "SC" } }));
assert.equal(devolucaoTransp.modalidade_frete, 1);
assert.equal(devolucaoTransp.nome_transportador, "EXPRESSO SAO MIGUEL");
assert.equal(devolucaoTransp.cnpj_transportador, "01234567000189");
// Origem 1 da nota do fornecedor nao pede equiparacao: e espelho, nao venda.
assert.doesNotThrow(() => montarPayloadNfe(contextoDevolucao({}, [itemDevolucao({ origem_mercadoria: 1 })])));
// O que barra: finalidade errada, CFOP fora da natureza, desconto, pagamento, referencia, origem, frete.
assert.throws(() => montarPayloadNfe(contextoDevolucao({ finalidade_emissao: 1 })), /devolução de compra sai com finalidade 4, e a conferência trouxe 1/);
assert.throws(
  () => montarPayloadNfe(contexto({ solicitacao: solicitacao({ operacao_snapshot: { ...solicitacao().operacao_snapshot, finalidade_emissao: 4 } }) })),
  /finalidade 4 \(devolução\) só vale para a devolução de compra/,
);
assert.throws(() => montarPayloadNfe(contextoDevolucao({}, [itemDevolucao({ cfop: "5902" })])), /DEVOLUCAO_COMPRA nao possui cClassTrib aprovado para o CFOP 5902/);
assert.throws(() => montarPayloadNfe(contextoDevolucao({}, [itemDevolucao({ valor_desconto: 10 })])), /desconto 10 \(a devolução espelha a origem/);
assert.throws(() => montarPayloadNfe(contextoDevolucao({ pagamento: { forma: "15", indicador: 0 } })), /devolução de compra sai sem pagamento \(tPag 90/);
assert.throws(() => montarPayloadNfe(contextoDevolucao({ nfe_referenciada: "42260808819200000182550030001214821001242890" })), /chave referenciada da devolução não é a da NF-e de entrada/);
assert.throws(() => montarPayloadNfe(contextoDevolucao({ devolucao_compra: null })), /devolução de compra sem a nota de origem/);
assert.throws(() => montarPayloadNfe(contextoDevolucao({ modalidade_frete: 5 })), /modalidade do frete 5 não vale para a devolução de compra/);
assert.throws(() => montarPayloadNfe(contextoDevolucao({ volumes: [] })), /informe ao menos um volume quando houver transporte/);

// Importacao por remessa expressa (17/09/2026): NF-e de ENTRADA da CPU OMRON CQM1H-CPU61 (UPS
// 1ZJ451C10441551106, DIR 260191366846): tpNF 0, idDest 3, exportador no exterior sem CNPJ, item
// origem 1 CST 00 a 17% por dentro (BC 844,28 = (437,97 + 262,78) / 0,83), II 262,78, IPI 02/319 (RTS),
// PIS/COFINS 98, IBS/CBS sobre 700,75 (valor aduaneiro + II, sem o ICMS: LC 214 art. 69 § 2º, II),
// vOutro = ICMS 143,53, vNF 844,28, grupo DI, tPag 90.
const itemImportacao = (extra = {}) => linha({
  codigo_produto: "CQM1HCPU61", descricao: "CONTROLADOR PROGRAMAVEL PLC CPU", ncm: "85371020", cfop: "3101",
  origem_mercadoria: 1, unidade: "UN", unidade_tributavel: "UN", quantidade: 1, valor_unitario: 437.97, valor_desconto: 0,
  cst_icms: "00", aliquota_icms: 17, reducao_base_icms_percentual: 0, cbenef: null, icms_modalidade_base_calculo: "3",
  cst_ipi: "02", ipi_codigo_enquadramento_legal: "319", aliquota_ipi: null,
  cst_pis: "71", cst_cofins: "71", aliquota_pis: null, aliquota_cofins: null, ...extra,
});
const snapshotImportacao = (extra = {}) => ({
  importacao_id: "imp-1", awb: "1ZJ451C10441551106", courier_nome: "UPS DO BRASIL REMESSAS EXPRESSAS LTDA", courier_cnpj: "74155052000173",
  dir_numero: "260191366846", dir_data_registro: "2026-09-09", dir_data_registro_texto: "09/09/2026", ua_entrada: "0817700",
  local_desembaraco: "AEROPORTO INTERNACIONAL DE VIRACOPOS - CAMPINAS", uf_desembaraco: "SP", data_desembaraco: "2026-09-09",
  via_transporte: 4, forma_intermedio: 1, exportador_codigo: "SHENZHEN-HAOXIN-XUNJI", remetente_dir: "SHENZHEN COOL DREAM SUPPLY CO LTD", regime_tributacao: "7",
  cambio: 5.0856, valor_mercadoria_usd: 45, frete_usd: 41.12, valor_aduaneiro: 437.97, ii: 262.78, aliquota_icms: 17, bc_icms: 844.28, icms: 143.53, valor_nota: 844.28,
  base_ibs_cbs: 700.75,
  gnre: { numero: "1234567890", receita: "10005-6", uf: "SC", valor: 143.53 }, nota_debito: { numero: "2953830", valor: 557.25 },
  courier_servicos: 138.53, courier_armazenagem: 12.41, credito_icms: true,
  itens: [{ ordem: 1, sequencia_dir: "00001", adicao: 1, sequencial_adicao: 1, fabricante: "OMRON", valor_aduaneiro: 437.97, ii: 262.78, bc_icms: 844.28, icms: 143.53, outras_despesas: 143.53, base_ibs_cbs: 700.75 }],
  texto_fisco: "NF-E DE ENTRADA DE IMPORTACAO POR REMESSA EXPRESSA (RTS, REGIME DE TRIBUTACAO SIMPLIFICADA). DIR 260191366846 DE 09/09/2026. II RECOLHIDO NA DIR. ICMS RECOLHIDO POR GNRE RECEITA 10005-6.",
  texto_complementar: "IMPORTACAO POR REMESSA EXPRESSA. AWB 1ZJ451C10441551106 UPS DO BRASIL REMESSAS EXPRESSAS LTDA. DIR 260191366846 REGISTRADA EM 09/09/2026. SEM COBRANCA.",
  ...extra,
});
const destinatarioExportador = {
  id: null, documento: null, id_estrangeiro: null, nome: "SHENZHEN HAOXIN XUNJI ELECTRONIC TECHNOLOGY TRADING CO., LTD", inscricao_estadual: null, indicador_ie: "9",
  logradouro: "JIAXIAN ROAD, YOU SUOWEI BUILDING, UNIT B1-A6", numero_endereco: "2000", complemento: "BANTIAN, LONGGANG", bairro: "SHENZHEN", cidade: "EXTERIOR", uf: "EX",
  codigo_ibge_municipio: "9999999", cep: null, pais_codigo: "1600", pais_nome: "CHINA",
};
const contextoImportacao = (extraOperacao = {}, itens = [itemImportacao()], extraSolicitacao = {}) => contexto({
  solicitacao: solicitacao({
    pedido_cliente: null,
    observacao: "CPU de CLP para a bancada",
    destinatario_snapshot: { ...destinatarioExportador },
    operacao_snapshot: {
      ...solicitacao().operacao_snapshot,
      natureza_operacao: "IMPORTACAO_INDUSTRIALIZACAO", finalidade_emissao: 1, consumidor_final: 0, presenca_comprador: 9,
      tipo_documento: 0, local_destino: 3, modalidade_frete: 9, valor_frete: 0, valor_seguro: 0, valor_outras_despesas: 143.53, valor_total_ii: 262.78,
      destinacao_mercadoria: null, nfe_referenciada: null, transportador: null, volumes: null,
      pagamento: { forma: "90", indicador: 0, descricao: null, parcelas: null, fatura_numero: null },
      importacao: snapshotImportacao(),
      ...extraOperacao,
    },
    ...extraSolicitacao,
  }),
  itens,
});
const imp = montarPayloadNfe(contextoImportacao());
assert.equal(imp.natureza_operacao, "COMPRA PARA INDUSTRIALIZACAO - IMPORTACAO");
assert.equal(imp.tipo_documento, 0, "nota de entrada");
assert.equal(imp.local_destino, 3, "operacao com o exterior");
assert.equal(imp.finalidade_emissao, 1);
assert.equal(imp.consumidor_final, 0);
assert.equal(imp.presenca_comprador, 9);
assert.equal(imp.modalidade_frete, 9);
assert.equal("volumes" in imp, false);
assert.equal("nome_transportador" in imp, false);
// Destinatario no exterior: sem CNPJ/CPF, IE, CEP e UF; municipio 9999999 EXTERIOR; pais BACEN.
assert.equal("cnpj_destinatario" in imp, false);
assert.equal("cpf_destinatario" in imp, false);
assert.equal("id_estrangeiro_destinatario" in imp, false, "idEstrangeiro so quando informado");
assert.equal("inscricao_estadual_destinatario" in imp, false);
assert.equal("uf_destinatario" in imp, false, "a Focus manda omitir a UF em operacao com o exterior");
assert.equal("cep_destinatario" in imp, false);
assert.equal(imp.indicador_inscricao_estadual_destinatario, 9);
assert.equal(imp.nome_destinatario, "NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL");
assert.equal(imp.logradouro_destinatario, "JIAXIAN ROAD, YOU SUOWEI BUILDING, UNIT B1-A6");
assert.equal(imp.numero_destinatario, "2000");
assert.equal(imp.complemento_destinatario, "BANTIAN, LONGGANG");
assert.equal(imp.bairro_destinatario, "SHENZHEN");
assert.equal(imp.municipio_destinatario, "EXTERIOR");
assert.equal(imp.codigo_municipio_destinatario, "9999999");
assert.equal(imp.codigo_pais_destinatario, 1600);
assert.equal(imp.pais_destinatario, "CHINA");
// Totais: vNF = vProd + II + vOutro (= ICMS) = base do ICMS; vNFTot igual; sem frete e seguro.
assert.equal(imp.valor_produtos, 437.97);
assert.equal(imp.valor_total_ii, 262.78);
assert.equal(imp.valor_outras_despesas, 143.53);
assert.equal(imp.valor_frete, 0);
assert.equal(imp.valor_seguro, 0);
assert.equal(imp.valor_total, 844.28);
assert.equal(imp.ibs_cbs_is_valor_total, 844.28, "vNFTot = soma dos vItem (vProd + II + vOutro)");
assert.equal(imp.ibs_cbs_base_calculo, 700.75, "base IBS/CBS = valor aduaneiro + II, sem o ICMS (LC 214, art. 69, § 2º, II)");
assert.equal(imp.ibs_uf_valor_total, 0.7);
assert.equal(imp.cbs_valor_total, 6.31);
assert.equal("valor_total_tributos" in imp, false, "sem vTotTrib: nao e venda");
assert.deepEqual(imp.formas_pagamento, [{ forma_pagamento: "90", valor_pagamento: 0 }]);
assert.equal("numero_fatura" in imp, false);
assert.equal("notas_referenciadas" in imp, false);
assert.equal(imp.informacoes_adicionais_fisco, snapshotImportacao().texto_fisco);
assert.match(imp.informacoes_adicionais_contribuinte, /^IMPORTACAO POR REMESSA EXPRESSA\. AWB 1ZJ451C10441551106 .* SEM COBRANCA\. \| CPU de CLP para a bancada$/);
// Item: origem 1, CST 00 modBC 3 com a base por dentro, II, sem IPI/PIS/COFINS, IBS/CBS, vOutro, DI.
assert.equal(imp.items.length, 1);
const itemI = imp.items[0];
assert.equal(itemI.cfop, "3101");
assert.equal(itemI.codigo_produto, "CQM1HCPU61");
assert.equal(itemI.codigo_ncm, "85371020");
assert.equal(itemI.quantidade_comercial, 1);
assert.equal(itemI.valor_unitario_comercial, 437.97);
assert.equal(itemI.valor_bruto, 437.97);
assert.equal("valor_desconto" in itemI, false);
assert.equal(itemI.icms_origem, 1);
assert.equal(itemI.icms_situacao_tributaria, "00");
assert.equal(itemI.icms_modalidade_base_calculo, "3");
assert.equal(itemI.icms_base_calculo, 844.28, "BC por dentro: (437,97 + 262,78) / (1 - 0,17)");
assert.equal(itemI.icms_aliquota, 17);
assert.equal(itemI.icms_valor, 143.53);
assert.equal("icms_reducao_base_calculo" in itemI, false);
assert.equal("codigo_beneficio_fiscal" in itemI, false);
assert.equal(itemI.ipi_situacao_tributaria, "02");
assert.equal(itemI.ipi_codigo_enquadramento_legal, "319");
assert.equal("ipi_valor" in itemI, false);
assert.equal(itemI.pis_situacao_tributaria, "71");
assert.equal("pis_valor" in itemI, false);
assert.equal(itemI.cofins_situacao_tributaria, "71");
assert.equal("cofins_valor" in itemI, false);
assert.equal(itemI.ibs_cbs_situacao_tributaria, "000");
assert.equal(itemI.ibs_cbs_classificacao_tributaria, "000001");
assert.equal(itemI.ibs_cbs_base_calculo, 700.75, "base do item = 437,97 + 262,78");
assert.equal(itemI.ibs_uf_valor, 0.7);
assert.equal(itemI.ibs_mun_valor, 0);
assert.equal(itemI.cbs_valor, 6.31);
// Snapshot gravado com o ICMS na base (a primeira homologacao): a emissao para.
assert.throws(
  () => montarPayloadNfe(contextoImportacao({ importacao: snapshotImportacao({ base_ibs_cbs: 844.28, itens: [{ ...snapshotImportacao().itens[0], base_ibs_cbs: 844.28 }] }) })),
  /base do IBS\/CBS \(844\.28\) não é valor aduaneiro \+ II \(700\.75\); o ICMS fica fora/,
);
// Snapshot antigo, sem a base gravada: o montador calcula sozinho.
assert.equal(montarPayloadNfe(contextoImportacao({ importacao: snapshotImportacao({ base_ibs_cbs: undefined, itens: [{ ...snapshotImportacao().itens[0], base_ibs_cbs: undefined }] }) })).ibs_cbs_base_calculo, 700.75);
assert.equal(itemI.valor_outras_despesas, 143.53, "vOutro do item = ICMS");
assert.equal(itemI.valor_total_item, 844.28, "vItem = vProd + II + vOutro");
assert.equal(itemI.ii_base_calculo, 437.97);
assert.equal(itemI.ii_despesas_aduaneiras, 0);
assert.equal(itemI.ii_valor, 262.78);
assert.equal(itemI.ii_valor_iof, 0);
assert.deepEqual(itemI.documentos_importacao, [{
  numero: "260191366846", data_registro: "2026-09-09", local_desembaraco_aduaneiro: "AEROPORTO INTERNACIONAL DE VIRACOPOS - CAMPINAS",
  uf_desembaraco_aduaneiro: "SP", data_desembaraco_aduaneiro: "2026-09-09", via_transporte: 4, forma_intermedio: 1, codigo_exportador: "SHENZHEN-HAOXIN-XUNJI",
  adicoes: [{ numero: 1, numero_sequencial_item: 1, codigo_fabricante_estrangeiro: "OMRON" }],
}]);
assert.equal("chave_acesso_dfe_referenciado" in itemI, false);
assert.equal("pedido_compra" in itemI, false);
// Producao: o mesmo payload com o nome real do exportador; idEstrangeiro quando informado.
const impProducao = montarPayloadNfe({ ...contextoImportacao(), emissao: { ambiente: "PRODUCAO", referencia_externa: "NFEP-IMP", tenant_id: "t", empresa_id: "e" } });
assert.equal(impProducao.nome_destinatario, "SHENZHEN HAOXIN XUNJI ELECTRONIC TECHNOLOGY TRADING CO., LTD");
assert.equal(impProducao.tipo_documento, 0);
assert.doesNotThrow(() => validarPayloadProducaoContraHomologacao(imp, impProducao));
assert.throws(
  () => validarPayloadProducaoContraHomologacao(imp, { ...impProducao, items: [{ ...impProducao.items[0], ii_valor: 100 }] }),
  /diverge da homologacao autorizada no campo items\[0\]\.ii_valor/,
);
const impId = montarPayloadNfe(contextoImportacao({}, [itemImportacao()], { destinatario_snapshot: { ...destinatarioExportador, id_estrangeiro: "91440300MA5F" } }));
assert.equal(impId.id_estrangeiro_destinatario, "91440300MA5F");
// 3556 (uso e consumo): indFinal 1, mesma conta; 3102 revenda; 3551 ativo.
const imp3556 = montarPayloadNfe(contextoImportacao({ natureza_operacao: "IMPORTACAO_CONSUMO", consumidor_final: 1 }, [itemImportacao({ cfop: "3556" })]));
assert.equal(imp3556.natureza_operacao, "COMPRA DE MATERIAL PARA USO OU CONSUMO - IMPORTACAO");
assert.equal(imp3556.consumidor_final, 1);
assert.equal(imp3556.valor_total, 844.28);
assert.equal(montarPayloadNfe(contextoImportacao({ natureza_operacao: "IMPORTACAO_COMERCIALIZACAO" }, [itemImportacao({ cfop: "3102" })])).natureza_operacao, "COMPRA PARA COMERCIALIZACAO - IMPORTACAO");
assert.equal(montarPayloadNfe(contextoImportacao({ natureza_operacao: "IMPORTACAO_ATIVO", consumidor_final: 1 }, [itemImportacao({ cfop: "3551" })])).natureza_operacao, "COMPRA DE BEM PARA O ATIVO IMOBILIZADO - IMPORTACAO");
// Dois itens: cada um com a sua adicao, II e ICMS; os totais somam.
// O ICMS de cada item e base x aliquota (98,31 + 45,21); o total da nota (143,52) anda um centavo
// em relacao aos 17% da base total, e o vNF acompanha (844,27).
const impDois = montarPayloadNfe(
  contextoImportacao(
    { valor_outras_despesas: 143.52, importacao: snapshotImportacao({ icms: 143.52, valor_nota: 844.27, itens: [
      { ordem: 1, adicao: 1, sequencial_adicao: 1, fabricante: "OMRON", valor_aduaneiro: 300, ii: 180, bc_icms: 578.31, icms: 98.31, outras_despesas: 98.31, base_ibs_cbs: 480 },
      { ordem: 2, adicao: 1, sequencial_adicao: 2, fabricante: "OMRON", valor_aduaneiro: 137.97, ii: 82.78, bc_icms: 265.97, icms: 45.21, outras_despesas: 45.21, base_ibs_cbs: 220.75 },
    ] }) },
    [itemImportacao({ valor_unitario: 300 }), itemImportacao({ ordem: 2, codigo_produto: "CJ1W-ID211", descricao: "CARTAO DE ENTRADA", valor_unitario: 137.97 })],
  ),
);
assert.equal(impDois.items.length, 2);
assert.equal(impDois.items[1].documentos_importacao[0].adicoes[0].numero_sequencial_item, 2);
assert.equal(impDois.items[0].icms_base_calculo, 578.31);
assert.equal(impDois.items[1].icms_valor, 45.21);
assert.equal(impDois.items[1].ii_valor, 82.78);
assert.equal(impDois.valor_total_ii, 262.78);
assert.equal(impDois.valor_outras_despesas, 143.52);
assert.equal(impDois.valor_total, 844.27);
assert.equal(impDois.ibs_cbs_is_valor_total, 844.27);
assert.equal(impDois.items[0].ibs_cbs_base_calculo, 480);
assert.equal(impDois.items[1].ibs_cbs_base_calculo, 220.75);
assert.equal(impDois.ibs_cbs_base_calculo, 700.75);
assert.equal(impDois.ibs_uf_valor_total, 0.7, "0,48 + 0,22");
assert.equal(impDois.cbs_valor_total, 6.31, "4,32 + 1,99");
// O que barra: CFOP fora da natureza, origem, CST, IPI destacado, PIS/COFINS, desconto, base e
// valores fora da DIR, outras despesas, frete, pagamento, finalidade, transporte, destinatario no Brasil.
assert.throws(() => montarPayloadNfe(contextoImportacao({}, [itemImportacao({ cfop: "3102" })])), /IMPORTACAO_INDUSTRIALIZACAO nao possui cClassTrib aprovado para o CFOP 3102/);
assert.throws(() => montarPayloadNfe(contextoImportacao({}, [itemImportacao({ origem_mercadoria: 0 })])), /origem 0 \(importação direta é origem 1\)/);
assert.throws(() => montarPayloadNfe(contextoImportacao({}, [itemImportacao({ cst_icms: "20", reducao_base_icms_percentual: 10 })])), /alíquota de ICMS da importação deve ser 17% sem redução/);
assert.throws(() => montarPayloadNfe(contextoImportacao({}, [itemImportacao({ cst_ipi: "50", ipi_codigo_enquadramento_legal: "999", aliquota_ipi: 5 })])), /IPI 50\/999 \(esperado 02\/319\)/);
assert.throws(() => montarPayloadNfe(contextoImportacao({}, [itemImportacao({ cst_pis: "01", aliquota_pis: 1.65 })])), /PIS\/COFINS 01\/71 \(esperado 71\/71\)/);
// Desconto tira o vProd do valor aduaneiro da DIR antes mesmo da checagem do item.
assert.throws(() => montarPayloadNfe(contextoImportacao({}, [itemImportacao({ valor_desconto: 10 })])), /vProd \(427\.97\) difere do valor aduaneiro da DIR \(437\.97\)/);
assert.throws(() => montarPayloadNfe(contextoImportacao({}, [itemImportacao({ valor_unitario: 400 })])), /vProd \(400\.00\) difere do valor aduaneiro da DIR \(437\.97\)/);
assert.throws(() => montarPayloadNfe(contextoImportacao({}, [itemImportacao({ aliquota_icms: 12 })])), /alíquota de ICMS da importação deve ser 17%/);
assert.throws(() => montarPayloadNfe(contextoImportacao({ importacao: snapshotImportacao({ bc_icms: 700.75 }) })), /base do ICMS da importação \(700\.75\) não é \(vProd \+ II\) \/ \(1 − 17%\) = 844\.28/);
assert.throws(() => montarPayloadNfe(contextoImportacao({ importacao: snapshotImportacao({ icms: 100, valor_nota: 800.75 }) })), /ICMS da importação \(100\.00\) não é 17% de 844\.28/);
assert.throws(() => montarPayloadNfe(contextoImportacao({ importacao: snapshotImportacao({ itens: [{ ...snapshotImportacao().itens[0], outras_despesas: 0 }] }) })), /vOutro \(0\.00\) deve ser o ICMS \(143\.53\)/);
assert.throws(() => montarPayloadNfe(contextoImportacao({ valor_outras_despesas: 0 })), /outras despesas da importação \(0\.00\) devem ser a soma do ICMS dos itens \(143\.53\)/);
assert.throws(() => montarPayloadNfe(contextoImportacao({ valor_frete: 50 })), /sai sem frete e sem seguro na nota/);
assert.throws(() => montarPayloadNfe(contextoImportacao({ pagamento: { forma: "15", indicador: 0 } })), /importação sai sem pagamento na nota \(tPag 90/);
assert.throws(() => montarPayloadNfe(contextoImportacao({ finalidade_emissao: 2 })), /importação sai com finalidade 1 \(normal\), e a conferência trouxe 2/);
assert.throws(() => montarPayloadNfe(contextoImportacao({ modalidade_frete: 0, volumes: [{ quantidade: 1, peso_liquido: 1, peso_bruto: 1 }] })), /sai sem transporte na nota \(modalidade 9/);
assert.throws(() => montarPayloadNfe(contextoImportacao({}, [itemImportacao()], { destinatario_snapshot: { ...destinatarioExportador, uf: "SC" } })), /a importação sai para o exterior \(UF EX, indicador de IE 9\)/);
assert.throws(() => montarPayloadNfe(contextoImportacao({}, [itemImportacao()], { destinatario_snapshot: { ...destinatarioExportador, pais_codigo: "1058", pais_nome: "BRASIL" } })), /país do exportador \(código BACEN diferente de 1058/);
assert.throws(() => montarPayloadNfe(contextoImportacao({ importacao: null })), /importação sem os dados da DIR/);
assert.throws(() => montarPayloadNfe(contextoImportacao({ importacao: snapshotImportacao({ itens: [] }) })), /importação sem os itens/);
assert.throws(() => montarPayloadNfe(contextoImportacao({}, [itemImportacao(), itemImportacao({ ordem: 2 })])), /importação sem os valores do item 2/);
// Sem equiparacao a industrial: a origem 1 nasce na propria nota de entrada.
assert.doesNotThrow(() => montarPayloadNfe(contextoImportacao({}, [itemImportacao({ equiparado_industrial: undefined })])));

console.log("327 cenarios locais do pipeline NF-e passaram.");
