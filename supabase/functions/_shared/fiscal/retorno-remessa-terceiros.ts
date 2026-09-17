/**
 * Retorno de mercadoria de terceiros recebida para industrializacao por encomenda (origem
 * CFOP 5901/6901) ou para conserto (origem 5915/6915). A mercadoria e do remetente: nunca
 * entrou no estoque e volta inteira, sem cobranca. Nao e devolucao (finNFe 1, nao 4).
 *
 * A nota de retorno e o espelho da nota recebida (cProd, xProd, NCM, unidade, quantidade e
 * valor iguais, na mesma ordem) e referencia a chave dela em NFref. Tributacao (16/09/2026):
 *
 *   ICMS  CST 50 (suspensao), sem base e sem valor, orig da nota de origem, cBenef
 *         CBENEF_RETORNO_SC — RICMS/SC-01, Anexo 2, Art. 27, II. SC840008 e o padrao
 *         decidido pelo Gabriel e fica a confirmar com a contadora; nao se copia o cBenef
 *         da nota de origem, que e o da remessa (SC840007).
 *   IPI   CST 55 (suspensao), sem valor — RIPI/2010 (Decreto 7.212/10), art. 43, VII.
 *         cEnq 108, o codigo de suspensao que as NF-e de terceiros trazem (a confirmar).
 *   PIS/COFINS CST 08: operacao sem incidencia, nao ha receita.
 *   IBS/CBS CST 410 / cClassTrib 410999 (nao incidencia), so CST e cClassTrib no item.
 *   Pagamento tPag 90 (sem pagamento), vPag 0; sem grupo cobr.
 *
 * O mesmo valor esta em f.fn_retorno_terceiros_config() (migration 20260917100000), que
 * grava os itens da solicitacao; aqui o montador confere que a nota sai exatamente assim.
 */

export const RETORNO_REMESSA_TERCEIROS = {
  // TODO contadora: confirmar SC840008 (Anexo 2, Art. 27, II) para o retorno.
  cbenef: "SC840008",
  cstIcms: "50",
  cstIpi: "55",
  // TODO contadora: confirmar o cEnq 108 (suspensao) para o retorno com IPI CST 55.
  cEnqIpi: "108",
  cstPisCofins: "08",
  cstIbsCbs: "410",
  cClassTrib: "410999",
  formaPagamento: "90",
  /** Modalidades de frete aceitas sem o grupo transportadora (decisao do Gabriel, 16/09/2026); padrao 0, como na NF 3427 do Vertex. */
  modalidadesFrete: [0, 1, 3, 4, 9],
  modalidadeFretePadrao: 0,
  naturezas: {
    // natOp aceita 60 caracteres. O padrao pedido em 16/09/2026, "RETORNO DE MERCADORIA
    // UTILIZADA NA INDUSTRIALIZACAO POR ENCOMENDA" (descricao do CFOP 5902), tem 65: fica sem
    // o "POR ENCOMENDA". A NF 3427 do Vertex saiu como "RETORNO DE MERCAD. UTILIZADA NA INDUST.".
    RETORNO_REMESSA_TERCEIROS: {
      cfops: ["5902", "6902", "5903", "6903"],
      natOp: "RETORNO DE MERCADORIA UTILIZADA NA INDUSTRIALIZACAO",
      textoIcms: "ICMS SUSPENSO CONFORME ANEXO 2, ART. 27, II, DO RICMS-SC.",
    },
    RETORNO_REMESSA_TERCEIROS_CONSERTO: {
      cfops: ["5916", "6916", "5903", "6903"],
      natOp: "RETORNO DE MERCADORIA RECEBIDA PARA CONSERTO",
      // TODO contadora: inciso do art. 27 no retorno de conserto (a NF 3644 do Vertex vai dizer).
      textoIcms: "ICMS SUSPENSO CONFORME ANEXO 2, ART. 27, DO RICMS-SC.",
    },
  },
  // So enquanto a nota levar o grupo IPI (CST 55): sem o grupo, a frase sai junto.
  textoIpi: "IPI SUSPENSO CONFORME ART. 43, VII, DO RIPI (DECRETO 7.212/2010).",
} as const;

/**
 * infAdFisco do retorno, no modelo da NF 3427 do Vertex (23/09/2025, WEG): base legal do ICMS e
 * a nota de origem. O IPI entra porque o item sai com o grupo IPI (CST 55, cEnq 108).
 */
export function textoFiscoRetornoTerceiros(natureza: NaturezaRetornoTerceiros, origem: OrigemRetornoTerceiros, comGrupoIpi = true) {
  const partes = [
    RETORNO_REMESSA_TERCEIROS.naturezas[natureza].textoIcms,
    `RETORNO DA NF-E ${origem.numero} DE ${origem.dataEmissao}.`,
    ...(comGrupoIpi ? [RETORNO_REMESSA_TERCEIROS.textoIpi] : []),
  ];
  return partes.join(" ");
}

export type NaturezaRetornoTerceiros = keyof typeof RETORNO_REMESSA_TERCEIROS.naturezas;

export function ehNaturezaRetornoTerceiros(codigo: string): codigo is NaturezaRetornoTerceiros {
  return codigo in RETORNO_REMESSA_TERCEIROS.naturezas;
}

/** Nota de origem, como a conferencia gravou em operacao_snapshot.retorno_terceiros. */
export type OrigemRetornoTerceiros = {
  numero: string;
  serie: string;
  /** dd/mm/aaaa */
  dataEmissao: string;
  chave: string;
};

export function lerOrigemRetornoTerceiros(valor: unknown): OrigemRetornoTerceiros {
  const origem = valor && typeof valor === "object" ? valor as Record<string, unknown> : null;
  const texto = (chave: string) => String(origem?.[chave] ?? "").trim();
  const chave = texto("chave").replace(/\D/g, "");
  const numero = texto("numero");
  const serie = texto("serie");
  const dataEmissao = texto("data_emissao");
  if (chave.length !== 44 || !numero || !serie || !/^\d{2}\/\d{2}\/\d{4}$/.test(dataEmissao)) {
    throw new Error("Solicitação incompleta: retorno de terceiros sem a nota de origem (número, série, data e chave) na conferência.");
  }
  return { numero, serie, dataEmissao, chave };
}

/** Frase do infCpl, antes da observacao livre. */
export function textoRetornoTerceiros(origem: OrigemRetornoTerceiros) {
  return `RETORNO INTEGRAL DA MERCADORIA RECEBIDA PELA NF-E N. ${origem.numero} SERIE ${origem.serie} DE ${origem.dataEmissao}, CHAVE ${origem.chave}. MERCADORIA DE TERCEIROS. SEM COBRANCA.`;
}

/**
 * Confere, item a item, que a conferencia gravou a tributacao do retorno. Um CST de venda ou
 * uma aliquota aqui destacaria imposto numa mercadoria que nem e nossa.
 */
export function motivoItemForaDoRetornoTerceiros(item: {
  codigo: string;
  cfop: string;
  situacaoIcms: string;
  aliquotaIcms: number | null;
  cbenef: string | null;
  cstIpi: string;
  cEnqIpi: string;
  aliquotaIpi: number | null;
  cstPis: string;
  cstCofins: string;
  desconto: number;
}, natureza: NaturezaRetornoTerceiros): string | null {
  const esperado = RETORNO_REMESSA_TERCEIROS.naturezas[natureza];
  const problemas: string[] = [];
  if (!(esperado.cfops as readonly string[]).includes(item.cfop)) problemas.push(`CFOP ${item.cfop} (esperado ${esperado.cfops.join(", ")})`);
  if (item.situacaoIcms !== RETORNO_REMESSA_TERCEIROS.cstIcms) problemas.push(`CST ICMS ${item.situacaoIcms} (esperado ${RETORNO_REMESSA_TERCEIROS.cstIcms})`);
  if (item.aliquotaIcms !== null && item.aliquotaIcms !== 0) problemas.push(`alíquota de ICMS ${item.aliquotaIcms}% (retorno não destaca ICMS)`);
  if ((item.cbenef ?? "") !== RETORNO_REMESSA_TERCEIROS.cbenef) problemas.push(`cBenef ${item.cbenef ?? "vazio"} (esperado ${RETORNO_REMESSA_TERCEIROS.cbenef})`);
  if (item.cstIpi !== RETORNO_REMESSA_TERCEIROS.cstIpi) problemas.push(`CST IPI ${item.cstIpi} (esperado ${RETORNO_REMESSA_TERCEIROS.cstIpi})`);
  if (item.cEnqIpi !== RETORNO_REMESSA_TERCEIROS.cEnqIpi) problemas.push(`cEnq ${item.cEnqIpi} (esperado ${RETORNO_REMESSA_TERCEIROS.cEnqIpi})`);
  if (item.aliquotaIpi !== null && item.aliquotaIpi !== 0) problemas.push(`alíquota de IPI ${item.aliquotaIpi}% (retorno não destaca IPI)`);
  if (item.cstPis !== RETORNO_REMESSA_TERCEIROS.cstPisCofins || item.cstCofins !== RETORNO_REMESSA_TERCEIROS.cstPisCofins) {
    problemas.push(`PIS/COFINS ${item.cstPis}/${item.cstCofins} (esperado ${RETORNO_REMESSA_TERCEIROS.cstPisCofins})`);
  }
  if (item.desconto !== 0) problemas.push(`desconto ${item.desconto} (o retorno espelha a origem, sem desconto)`);
  if (problemas.length === 0) return null;
  return `item ${item.codigo} não está tributado como retorno de mercadoria de terceiros: ${problemas.join("; ")}. Gere o retorno de novo`;
}
