/**
 * Devolucao de compra: a Segau devolve ao fornecedor parte (ou o todo) de uma mercadoria que
 * entrou por NF-e. E a operacao inversa da compra, com finNFe 4 e a nota de origem em NFref.
 *
 * Orientacao da contadora para a NF 121481/3 da Acos America (17/09/2026):
 *   - CFOP 5201 (devolucao de compra para industrializacao); fora do estado, 6201;
 *   - saida tributada: ICMS com o CST da origem (CST 00) e a mesma aliquota (12%);
 *   - o IPI nao integra a base do ICMS, como na nota de origem (compra entre contribuintes
 *     para industrializacao);
 *   - transporte com a quantidade de volumes e o peso do que volta.
 *
 * A nota espelha a linha de origem proporcionalmente a quantidade devolvida: cProd, xProd,
 * NCM, unidade e valor unitario iguais; ICMS, IPI, PIS e COFINS com os CST e aliquotas do
 * XML de entrada (f.fn_devolucao_compra_preparar le o XML; f.fn_devolucao_compra_nfe_criar
 * grava o snapshot). IBS/CBS pela regra de 2026 da operacao tributada (CST 000 / 000001).
 * Sem cobranca: tPag 90, vPag 0, sem grupo cobr.
 */

export const DEVOLUCAO_COMPRA = {
  finalidadeEmissao: 4,
  formaPagamento: "90",
  /** Modalidades aceitas; a transportadora e opcional (a tela pode informar). */
  modalidadesFrete: [0, 1, 2, 3, 4, 9],
  modalidadeFretePadrao: 0,
  naturezas: {
    // natOp aceita 60 caracteres.
    DEVOLUCAO_COMPRA: {
      cfops: ["5201", "6201", "5202", "6202"],
      natOp: "DEVOLUCAO DE COMPRA PARA INDUSTRIALIZACAO",
    },
  },
} as const;

export type NaturezaDevolucaoCompra = keyof typeof DEVOLUCAO_COMPRA.naturezas;

export function ehNaturezaDevolucaoCompra(codigo: string): codigo is NaturezaDevolucaoCompra {
  return codigo in DEVOLUCAO_COMPRA.naturezas;
}

/** Nota de origem, como f.fn_devolucao_compra_nfe_criar gravou em operacao_snapshot.devolucao_compra. */
export type OrigemDevolucaoCompra = {
  numero: string;
  serie: string;
  /** dd/mm/aaaa */
  dataEmissao: string;
  chave: string;
  /** "ITEM 2 (401014): 41,55 KG DE 2.742,30 KG" — uma frase por item, ja formatada pelo banco. */
  itensTexto: string;
  /** nItem de origem de cada item devolvido, pela ordem na devolucao (DFeReferenciado da nota real). */
  itens: Array<{ ordem: number; nitem: number }>;
  /**
   * NF-e de HOMOLOGACAO da propria empresa destinada a ela mesma (remessa 5915 Segau -> Segau,
   * NF-e 2/64 de 17/09/2026) e o primeiro item dela, gravados pelo banco no snapshot. Sao a
   * referencia da nota de teste: desde 01/09/2026 (NT 2025.002-RTC) a devolucao referencia a
   * origem item a item (DFeReferenciado, regra VC02-14) e o destinatario tem de ser o emitente
   * da nota referenciada (VC02-50); a SEFAZ de homologacao nao conhece a nota do fornecedor.
   */
  chaveReferenciaHomologacao: string | null;
  referenciaHomologacaoNitem: number;
};

export function lerOrigemDevolucaoCompra(valor: unknown): OrigemDevolucaoCompra {
  const origem = valor && typeof valor === "object" ? valor as Record<string, unknown> : null;
  const texto = (chave: string) => String(origem?.[chave] ?? "").trim();
  const chave = texto("chave").replace(/\D/g, "");
  const numero = texto("numero");
  const serie = texto("serie");
  const dataEmissao = texto("data_emissao");
  const itensTexto = texto("itens_texto");
  const chaveHom = texto("chave_referencia_homologacao").replace(/\D/g, "");
  const nitemHom = Number(texto("referencia_homologacao_nitem") || 1);
  const itens = (Array.isArray(origem?.itens) ? origem.itens as unknown[] : [])
    .map((i) => {
      const item = i && typeof i === "object" ? i as Record<string, unknown> : {};
      return { ordem: Number(item.ordem), nitem: Number(item.nitem) };
    })
    .filter((i) => Number.isInteger(i.ordem) && i.ordem > 0 && Number.isInteger(i.nitem) && i.nitem > 0);
  if (chave.length !== 44 || !numero || !serie || !/^\d{2}\/\d{2}\/\d{4}$/.test(dataEmissao) || !itensTexto || itens.length === 0) {
    throw new Error("Solicitação incompleta: devolução de compra sem a nota de origem (número, série, data, chave e itens com o nItem de origem) na conferência.");
  }
  return {
    numero, serie, dataEmissao, chave, itensTexto, itens,
    chaveReferenciaHomologacao: chaveHom.length === 44 ? chaveHom : null,
    referenciaHomologacaoNitem: Number.isInteger(nitemHom) && nitemHom > 0 ? nitemHom : 1,
  };
}

function chaveDeReferencia(origem: OrigemDevolucaoCompra, ambiente: "HOMOLOGACAO" | "PRODUCAO") {
  if (ambiente === "PRODUCAO") return origem.chave;
  if (!origem.chaveReferenciaHomologacao) {
    throw new Error(
      "Emissão bloqueada: a devolução em homologação precisa de uma NF-e de homologação da empresa para ela mesma "
      + "(remessa para conserto com a própria empresa como destinatária, emitida em homologação) para referenciar. "
      + "Emita uma e gere a devolução de novo.",
    );
  }
  return origem.chaveReferenciaHomologacao;
}

/**
 * DFeReferenciado do item (chaveAcesso + nItem, NT 2025.002-RTC): na nota real, a chave de
 * entrada e o nItem de origem daquele item; na de teste, a NF-e de referencia e o item dela.
 * E a unica referencia da nota: com o NFref do cabecalho junto a SEFAZ recusa (rejeicao 1010).
 */
export function documentoReferenciadoDoItem(origem: OrigemDevolucaoCompra, ambiente: "HOMOLOGACAO" | "PRODUCAO", ordem: number) {
  const chave = chaveDeReferencia(origem, ambiente);
  if (ambiente === "HOMOLOGACAO") {
    return { chave_acesso_dfe_referenciado: chave, numero_item_dfe_referenciado: String(origem.referenciaHomologacaoNitem) };
  }
  const item = origem.itens.find((i) => i.ordem === ordem);
  if (!item) {
    throw new Error(`Solicitação incompleta: devolução de compra sem o nItem de origem do item ${ordem} na conferência.`);
  }
  return { chave_acesso_dfe_referenciado: chave, numero_item_dfe_referenciado: String(item.nitem) };
}

/**
 * Destinatario da nota de teste: a propria empresa (VC02-50 — o destinatario da devolucao e o
 * emitente da nota referenciada, e em homologacao a referencia e a NF-e da empresa para ela
 * mesma). A nota real leva o fornecedor. Os campos sao os do snapshot do destinatario.
 */
export function destinatarioDeTesteDevolucao(emitente: Record<string, unknown>): Record<string, unknown> {
  return {
    id: null,
    documento: emitente.cnpj,
    nome: emitente.razao_social,
    inscricao_estadual: emitente.inscricao_estadual,
    indicador_ie: "1",
    email: null,
    telefone: emitente.telefone ?? null,
    logradouro: emitente.logradouro,
    numero_endereco: emitente.numero,
    complemento: emitente.complemento ?? null,
    bairro: emitente.bairro,
    cidade: emitente.cidade,
    uf: emitente.uf,
    codigo_ibge_municipio: emitente.codigo_municipio_ibge,
    cep: emitente.cep,
  };
}

/** Chaves do payload que so mudam entre a nota de teste e a real na devolucao (ver f.fn_nfe_payload_comparavel). */
export const CHAVES_DESTINATARIO_PAYLOAD = [
  "cnpj_destinatario", "cpf_destinatario", "inscricao_estadual_destinatario", "indicador_inscricao_estadual_destinatario",
  "logradouro_destinatario", "numero_destinatario", "complemento_destinatario", "bairro_destinatario", "municipio_destinatario",
  "codigo_municipio_destinatario", "uf_destinatario", "cep_destinatario", "telefone_destinatario", "local_destino",
] as const;
export const CHAVES_ITEM_DFE_REFERENCIADO = ["chave_acesso_dfe_referenciado", "numero_item_dfe_referenciado"] as const;

/** infAdFisco: a nota de origem e o criterio dos impostos. */
export function textoFiscoDevolucaoCompra(origem: OrigemDevolucaoCompra) {
  return `DEVOLUCAO DE COMPRA REFERENTE A NF-E ${origem.numero} DE ${origem.dataEmissao}. ICMS, IPI, PIS E COFINS DESTACADOS PROPORCIONALMENTE CONFORME A NOTA DE ORIGEM.`;
}

/** Frase do infCpl, antes da observacao livre. */
export function textoDevolucaoCompra(origem: OrigemDevolucaoCompra) {
  return `DEVOLUCAO PARCIAL DA MERCADORIA RECEBIDA PELA NF-E N. ${origem.numero} SERIE ${origem.serie} DE ${origem.dataEmissao}, CHAVE ${origem.chave}. ${origem.itensTexto}. SEM COBRANCA.`;
}

/**
 * Confere, item a item, o que a conferencia gravou para a devolucao. Os CST e aliquotas vem do
 * XML de origem e nao sao conferidos aqui (variam por fornecedor); o que nao muda e o CFOP da
 * devolucao e a ausencia de desconto — o valor e o proporcional da origem.
 */
export function motivoItemForaDaDevolucaoCompra(item: {
  codigo: string;
  cfop: string;
  desconto: number;
}, natureza: NaturezaDevolucaoCompra): string | null {
  const esperado = DEVOLUCAO_COMPRA.naturezas[natureza];
  const problemas: string[] = [];
  if (!(esperado.cfops as readonly string[]).includes(item.cfop)) problemas.push(`CFOP ${item.cfop} (esperado ${esperado.cfops.join(", ")})`);
  if (item.desconto !== 0) problemas.push(`desconto ${item.desconto} (a devolução espelha a origem, sem desconto)`);
  if (problemas.length === 0) return null;
  return `item ${item.codigo} não está montado como devolução de compra: ${problemas.join("; ")}. Gere a devolução de novo`;
}
