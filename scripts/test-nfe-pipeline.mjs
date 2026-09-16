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
assert.equal(retorno.natureza_operacao, "RETORNO MERCADORIA RECEBIDA P/ INDUSTRIALIZACAO P/ ENCOMENDA");
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
assert.equal(
  retorno.informacoes_adicionais_fisco,
  "ICMS SUSPENSO CONFORME ART. 27, II, ANEXO 2 DO RICMS/SC. IPI SUSPENSO CONFORME ART. 43, VII, DO RIPI (DECRETO 7.212/2010).",
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

console.log("142 cenarios locais do pipeline NF-e passaram.");
