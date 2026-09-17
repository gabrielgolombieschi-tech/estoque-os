/**
 * Importacao por remessa expressa (courier): a Segau e a importadora e emite a NF-e de ENTRADA
 * (tpNF 0) que da origem fiscal a mercadoria desembaracada pela DIR do Siscomex Remessa.
 *
 * Primeiro caso (17/09/2026): remessa UPS 1ZJ451C10441551106, DIR 260191366846 registrada em
 * 09/09/2026 (UA 0817700, Viracopos/SP), CPU de CLP OMRON CQM1H-CPU61, US$ 45,00 + frete
 * US$ 41,12 a 5,0856. Regime de tributacao simplificada (RTS, regime 7): II de 60% recolhido na
 * DIR (R$ 262,78), ICMS por GNRE (receita 10005-6, R$ 143,53), sem IPI, PIS ou COFINS.
 *
 * A nota:
 *   - tpNF 0, idDest 3, finNFe 1, indPres 9; destinatario = exportador no exterior (idEstrangeiro
 *     opcional, UF EX, municipio 9999999 EXTERIOR, pais da tabela BACEN, indIEDest 9);
 *   - item: origem 1, CST ICMS 00 com modBC 3 e base "por dentro" (vProd + II) / (1 - aliquota),
 *     grupo II (vBC = vProd, vDespAdu 0, vII, vIOF 0), grupo DI com uma adicao, IPI CST 03/999,
 *     PIS/COFINS CST 98, IBS/CBS 000/000001 sobre valor aduaneiro + II — base do II acrescida dos
 *     tributos do caput, sem o ICMS (LC 214/2025, art. 69, caput e §§ 1º e 2º) —, vOutro = ICMS
 *     (para o vNF fechar com a base do ICMS);
 *   - totais: vNF = vProd + vII + vOutro; sem frete (modFrete 9), sem cobranca (tPag 90).
 * f.fn_importacao_remessa_criar calcula e grava tudo em operacao_snapshot.importacao; aqui so se
 * le, confere e monta o payload da Focus.
 */

export const IMPORTACAO_REMESSA = {
  tipoDocumento: 0,
  localDestino: 3,
  finalidadeEmissao: 1,
  presencaComprador: 9,
  formaPagamento: "90",
  modalidadeFrete: 9,
  ufExterior: "EX",
  codigoMunicipioExterior: "9999999",
  municipioExterior: "EXTERIOR",
  indicadorIe: "9",
  item: {
    origem: 1,
    cstIcms: "00",
    modalidadeBase: "3",
    cstIpi: "03",
    cEnqIpi: "999",
    cstPis: "98",
    cstCofins: "98",
  },
  naturezas: {
    // natOp aceita 60 caracteres.
    IMPORTACAO_INDUSTRIALIZACAO: { cfops: ["3101"], natOp: "COMPRA PARA INDUSTRIALIZACAO - IMPORTACAO", consumidorFinal: 0, creditoIcms: true },
    IMPORTACAO_COMERCIALIZACAO: { cfops: ["3102"], natOp: "COMPRA PARA COMERCIALIZACAO - IMPORTACAO", consumidorFinal: 0, creditoIcms: true },
    IMPORTACAO_CONSUMO: { cfops: ["3556"], natOp: "COMPRA DE MATERIAL PARA USO OU CONSUMO - IMPORTACAO", consumidorFinal: 1, creditoIcms: false },
    IMPORTACAO_ATIVO: { cfops: ["3551"], natOp: "COMPRA DE BEM PARA O ATIVO IMOBILIZADO - IMPORTACAO", consumidorFinal: 1, creditoIcms: false },
  },
} as const;

export type NaturezaImportacao = keyof typeof IMPORTACAO_REMESSA.naturezas;

export function ehNaturezaImportacao(codigo: string): codigo is NaturezaImportacao {
  return codigo in IMPORTACAO_REMESSA.naturezas;
}

export type ItemImportacao = {
  ordem: number;
  adicao: number;
  sequencialAdicao: number;
  fabricante: string;
  valorAduaneiro: number;
  ii: number;
  bcIcms: number;
  icms: number;
  outrasDespesas: number;
  /** Base do IBS/CBS conferida pelo banco (valor aduaneiro + II); null nas importacoes gravadas antes de 18/09/2026. */
  baseIbsCbs: number | null;
};

/** O que f.fn_importacao_remessa_criar gravou em operacao_snapshot.importacao. */
export type OrigemImportacao = {
  importacaoId: string;
  awb: string;
  courierNome: string | null;
  dirNumero: string;
  /** aaaa-mm-dd */
  dirDataRegistro: string;
  /** dd/mm/aaaa */
  dirDataRegistroTexto: string;
  uaEntrada: string;
  localDesembaraco: string;
  ufDesembaraco: string;
  /** aaaa-mm-dd */
  dataDesembaraco: string;
  viaTransporte: number;
  formaIntermedio: number;
  exportadorCodigo: string;
  remetenteDir: string | null;
  cambio: number;
  valorAduaneiro: number;
  ii: number;
  aliquotaIcms: number;
  bcIcms: number;
  icms: number;
  valorNota: number;
  creditoIcms: boolean;
  itens: ItemImportacao[];
  textoFisco: string;
  textoComplementar: string;
};

function numero(valor: unknown) {
  if (valor === null || valor === undefined || String(valor).trim() === "") return null;
  const n = Number(valor);
  return Number.isFinite(n) ? n : null;
}

function round(valor: number) {
  return Math.round((valor + Number.EPSILON) * 100) / 100;
}

export function lerOrigemImportacao(valor: unknown): OrigemImportacao {
  const origem = valor && typeof valor === "object" && !Array.isArray(valor) ? valor as Record<string, unknown> : null;
  const texto = (chave: string) => String(origem?.[chave] ?? "").trim();
  const falta = (campo: string) => new Error(`Solicitação incompleta: importação sem ${campo} na conferência (operacao_snapshot.importacao).`);
  if (!origem) throw falta("os dados da DIR");
  const dirNumero = texto("dir_numero").replace(/\D/g, "");
  if (dirNumero.length < 6) throw falta("o número da DIR");
  const awb = texto("awb");
  if (!awb) throw falta("o AWB");
  const dirDataRegistro = texto("dir_data_registro");
  const dataDesembaraco = texto("data_desembaraco");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dirDataRegistro) || !/^\d{4}-\d{2}-\d{2}$/.test(dataDesembaraco)) throw falta("as datas de registro e desembaraço");
  const localDesembaraco = texto("local_desembaraco");
  const ufDesembaraco = texto("uf_desembaraco").toUpperCase();
  if (!localDesembaraco || !/^[A-Z]{2}$/.test(ufDesembaraco)) throw falta("o local e a UF do desembaraço");
  const viaTransporte = numero(origem.via_transporte);
  const formaIntermedio = numero(origem.forma_intermedio);
  if (viaTransporte === null || !Number.isInteger(viaTransporte) || viaTransporte < 1 || viaTransporte > 13) throw falta("a via de transporte (1 a 13)");
  if (formaIntermedio === null || ![1, 2, 3].includes(formaIntermedio)) throw falta("a forma de intermediação (1, 2 ou 3)");
  const exportadorCodigo = texto("exportador_codigo");
  if (!exportadorCodigo) throw falta("o código do exportador");
  const cambio = numero(origem.cambio);
  const valorAduaneiro = numero(origem.valor_aduaneiro);
  const ii = numero(origem.ii);
  const aliquotaIcms = numero(origem.aliquota_icms);
  const bcIcms = numero(origem.bc_icms);
  const icms = numero(origem.icms);
  const valorNota = numero(origem.valor_nota);
  if (cambio === null || cambio <= 0) throw falta("a taxa de câmbio");
  if (valorAduaneiro === null || valorAduaneiro <= 0 || ii === null || ii < 0) throw falta("o valor aduaneiro e o II");
  if (aliquotaIcms === null || aliquotaIcms < 0 || aliquotaIcms >= 100 || bcIcms === null || icms === null || valorNota === null) throw falta("a base, a alíquota e o valor do ICMS");
  const itensBrutos = Array.isArray(origem.itens) ? origem.itens as unknown[] : [];
  const itens: ItemImportacao[] = itensBrutos.map((bruto, indice) => {
    const item = bruto && typeof bruto === "object" ? bruto as Record<string, unknown> : {};
    const ordem = numero(item.ordem);
    const adicao = numero(item.adicao) ?? 1;
    const sequencialAdicao = numero(item.sequencial_adicao) ?? indice + 1;
    const fabricante = String(item.fabricante ?? "").trim();
    const vAdu = numero(item.valor_aduaneiro);
    const vIi = numero(item.ii);
    const vBc = numero(item.bc_icms);
    const vIcms = numero(item.icms);
    const vOutro = numero(item.outras_despesas);
    const vBaseIbsCbs = numero(item.base_ibs_cbs);
    if (ordem === null || !Number.isInteger(ordem) || ordem < 1 || !fabricante || vAdu === null || vIi === null || vBc === null || vIcms === null || vOutro === null) {
      throw falta(`os valores do item ${indice + 1} (ordem, fabricante, valor aduaneiro, II, base e valor do ICMS, outras despesas)`);
    }
    if (Math.abs(vOutro - vIcms) > 0.005) {
      throw new Error(`Emissão bloqueada: item ${ordem} da importação, vOutro (${vOutro.toFixed(2)}) deve ser o ICMS (${vIcms.toFixed(2)}) para o total fechar com a base.`);
    }
    // Base do IBS/CBS = valor aduaneiro + II (LC 214/2025, art. 69, §§ 1º e 2º): sem ICMS e sem IPI.
    if (vBaseIbsCbs !== null && Math.abs(vBaseIbsCbs - round(vAdu + vIi)) > 0.005) {
      throw new Error(`Emissão bloqueada: item ${ordem} da importação, base do IBS/CBS (${vBaseIbsCbs.toFixed(2)}) não é valor aduaneiro + II (${round(vAdu + vIi).toFixed(2)}); o ICMS fica fora (LC 214/2025, art. 69, § 2º, II).`);
    }
    return { ordem, adicao, sequencialAdicao, fabricante: fabricante.slice(0, 60), valorAduaneiro: vAdu, ii: vIi, bcIcms: vBc, icms: vIcms, outrasDespesas: vOutro, baseIbsCbs: vBaseIbsCbs };
  });
  if (itens.length === 0) throw falta("os itens");
  // Base "por dentro": BC = (vProd + II) / (1 - aliquota) (LC 87/96, art. 13, V e § 1º). O ICMS
  // de cada item e base x aliquota; o total e a soma dos itens, que anda centavos com varios itens.
  const bcEsperada = round((valorAduaneiro + ii) / (1 - aliquotaIcms / 100));
  if (Math.abs(bcEsperada - bcIcms) > 0.011) {
    throw new Error(`Emissão bloqueada: base do ICMS da importação (${bcIcms.toFixed(2)}) não é (vProd + II) / (1 − ${aliquotaIcms}%) = ${bcEsperada.toFixed(2)}.`);
  }
  const tolerancia = 0.005 + 0.01 * itens.length;
  if (Math.abs(round(bcIcms * aliquotaIcms / 100) - icms) > tolerancia) {
    throw new Error(`Emissão bloqueada: ICMS da importação (${icms.toFixed(2)}) não é ${aliquotaIcms}% de ${bcIcms.toFixed(2)}.`);
  }
  if (Math.abs(round(valorAduaneiro + ii + icms) - valorNota) > 0.005) {
    throw new Error(`Emissão bloqueada: valor da nota de importação (${valorNota.toFixed(2)}) não é vProd + II + ICMS.`);
  }
  const soma = (campo: keyof ItemImportacao) => round(itens.reduce((acc, i) => acc + Number(i[campo]), 0));
  if (Math.abs(soma("valorAduaneiro") - valorAduaneiro) > 0.005 || Math.abs(soma("ii") - ii) > 0.005 || Math.abs(soma("icms") - icms) > 0.005 || Math.abs(soma("bcIcms") - bcIcms) > 0.005) {
    throw new Error("Emissão bloqueada: os itens da importação não somam o valor aduaneiro, o II, a base e o ICMS da DIR.");
  }
  const textoFisco = texto("texto_fisco");
  const textoComplementar = texto("texto_complementar");
  if (!textoFisco || !textoComplementar) throw falta("os textos da nota");
  return {
    importacaoId: texto("importacao_id"),
    awb,
    courierNome: texto("courier_nome") || null,
    dirNumero,
    dirDataRegistro,
    dirDataRegistroTexto: texto("dir_data_registro_texto") || `${dirDataRegistro.slice(8, 10)}/${dirDataRegistro.slice(5, 7)}/${dirDataRegistro.slice(0, 4)}`,
    uaEntrada: texto("ua_entrada"),
    localDesembaraco: localDesembaraco.slice(0, 60),
    ufDesembaraco,
    dataDesembaraco,
    viaTransporte,
    formaIntermedio,
    exportadorCodigo: exportadorCodigo.slice(0, 60),
    remetenteDir: texto("remetente_dir") || null,
    cambio,
    valorAduaneiro,
    ii,
    aliquotaIcms,
    bcIcms,
    icms,
    valorNota,
    creditoIcms: origem.credito_icms === true,
    itens,
    textoFisco: textoFisco.slice(0, 2000),
    textoComplementar: textoComplementar.slice(0, 5000),
  };
}

export function itemDaImportacao(origem: OrigemImportacao, ordem: number): ItemImportacao {
  const item = origem.itens.find((i) => i.ordem === ordem);
  if (!item) throw new Error(`Solicitação incompleta: importação sem os valores do item ${ordem} na conferência.`);
  return item;
}

/** Grupo DI (nDI, datas, desembaraco, via, intermedio, exportador) com a adicao do item — campos da Focus. */
export function documentoImportacaoDoItem(origem: OrigemImportacao, item: ItemImportacao) {
  return {
    documentos_importacao: [{
      numero: origem.dirNumero,
      data_registro: origem.dirDataRegistro,
      local_desembaraco_aduaneiro: origem.localDesembaraco,
      uf_desembaraco_aduaneiro: origem.ufDesembaraco,
      data_desembaraco_aduaneiro: origem.dataDesembaraco,
      via_transporte: origem.viaTransporte,
      forma_intermedio: origem.formaIntermedio,
      codigo_exportador: origem.exportadorCodigo,
      adicoes: [{
        numero: item.adicao,
        numero_sequencial_item: item.sequencialAdicao,
        codigo_fabricante_estrangeiro: item.fabricante,
      }],
    }],
  };
}

/** Grupo II do item: vBC = valor aduaneiro do item, sem despesas aduaneiras nem IOF (RTS). */
export function impostoImportacaoDoItem(item: ItemImportacao) {
  return {
    ii_base_calculo: item.valorAduaneiro,
    ii_despesas_aduaneiras: 0,
    ii_valor: item.ii,
    ii_valor_iof: 0,
  };
}

/**
 * Destinatario no exterior (o exportador): sem CNPJ/CPF, sem IE, sem CEP e sem UF (a Focus manda
 * omitir a UF em operacao com o exterior); municipio 9999999 EXTERIOR e pais da tabela BACEN.
 */
export function destinatarioExteriorPayload(destinatario: Record<string, unknown>) {
  const texto = (chave: string) => String(destinatario[chave] ?? "").trim();
  const idEstrangeiro = texto("id_estrangeiro");
  const paisCodigo = texto("pais_codigo").replace(/\D/g, "");
  const paisNome = texto("pais_nome").toUpperCase();
  const logradouro = texto("logradouro");
  const bairro = texto("bairro");
  if (!logradouro || !bairro) throw new Error("Solicitação incompleta: endereço do exportador (logradouro e bairro).");
  if (!/^\d{2,4}$/.test(paisCodigo) || paisCodigo === "1058" || !paisNome) {
    throw new Error("Solicitação incompleta: país do exportador (código BACEN diferente de 1058 e nome).");
  }
  if (String(destinatario.uf ?? "").trim().toUpperCase() !== IMPORTACAO_REMESSA.ufExterior) {
    throw new Error(`Solicitação incompleta: o destinatário da importação deve ter UF ${IMPORTACAO_REMESSA.ufExterior}.`);
  }
  if (idEstrangeiro && (idEstrangeiro.length < 5 || idEstrangeiro.length > 20)) {
    throw new Error("Solicitação incompleta: idEstrangeiro do exportador deve ter de 5 a 20 caracteres.");
  }
  return {
    ...(idEstrangeiro ? { id_estrangeiro_destinatario: idEstrangeiro } : {}),
    indicador_inscricao_estadual_destinatario: Number(IMPORTACAO_REMESSA.indicadorIe),
    logradouro_destinatario: logradouro.slice(0, 60),
    numero_destinatario: (texto("numero_endereco") || "S/N").slice(0, 60),
    ...(texto("complemento") ? { complemento_destinatario: texto("complemento").slice(0, 60) } : {}),
    bairro_destinatario: bairro.slice(0, 60),
    municipio_destinatario: IMPORTACAO_REMESSA.municipioExterior,
    codigo_municipio_destinatario: IMPORTACAO_REMESSA.codigoMunicipioExterior,
    codigo_pais_destinatario: Number(paisCodigo),
    pais_destinatario: paisNome.slice(0, 60),
  };
}

/** Confere, item a item, o que a conferencia gravou para a importacao. */
export function motivoItemForaDaImportacao(item: {
  codigo: string;
  cfop: string;
  origem: number;
  situacaoIcms: string;
  modalidadeBase: string | null;
  cstIpi: string;
  cEnqIpi: string;
  aliquotaIpi: number | null;
  cstPis: string;
  cstCofins: string;
  desconto: number;
}, natureza: NaturezaImportacao): string | null {
  const esperado = IMPORTACAO_REMESSA.naturezas[natureza];
  const regra = IMPORTACAO_REMESSA.item;
  const problemas: string[] = [];
  if (!(esperado.cfops as readonly string[]).includes(item.cfop)) problemas.push(`CFOP ${item.cfop} (esperado ${esperado.cfops.join(", ")})`);
  if (item.origem !== regra.origem) problemas.push(`origem ${item.origem} (importação direta é origem ${regra.origem})`);
  if (item.situacaoIcms !== regra.cstIcms) problemas.push(`CST ICMS ${item.situacaoIcms} (esperado ${regra.cstIcms})`);
  if (item.modalidadeBase !== regra.modalidadeBase) problemas.push(`modBC ${item.modalidadeBase ?? "?"} (esperado ${regra.modalidadeBase}, valor da operação)`);
  if (item.cstIpi !== regra.cstIpi || item.cEnqIpi !== regra.cEnqIpi) problemas.push(`IPI ${item.cstIpi}/${item.cEnqIpi} (esperado ${regra.cstIpi}/${regra.cEnqIpi})`);
  if (item.aliquotaIpi !== null && item.aliquotaIpi !== 0) problemas.push("alíquota de IPI (a entrada por RTS não tem IPI)");
  if (item.cstPis !== regra.cstPis || item.cstCofins !== regra.cstCofins) problemas.push(`PIS/COFINS ${item.cstPis}/${item.cstCofins} (esperado ${regra.cstPis}/${regra.cstCofins})`);
  if (item.desconto !== 0) problemas.push(`desconto ${item.desconto} (a importação não tem desconto)`);
  if (problemas.length === 0) return null;
  return `item ${item.codigo} não está montado como importação por remessa expressa: ${problemas.join("; ")}. Gere a importação de novo`;
}
