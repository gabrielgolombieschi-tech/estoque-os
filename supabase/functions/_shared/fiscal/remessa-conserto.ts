/**
 * Remessa para conserto (CFOP 5915 dentro de SC, 6915 para outra UF).
 *
 * Regras da Status Contabilidade em docs/faturamento/regras-icms-sc-contabilidade.md
 * ("cBenef obrigatorio" e "CFOP x CST de ICMS"):
 *
 *   ICMS  CST 50 (suspensao) com cBenef SC840007 — RICMS/SC-01, Anexo 2, Art. 27, I:
 *         a mercadoria precisa voltar em 180 dias.
 *   IPI   CST 55 (suspensao) — RIPI/2010 (Decreto 7.212/10), art. 43, VI. cEnq 108, o
 *         codigo de suspensao que as NF-e de remessa de terceiros trazem em 2026.
 *   PIS/COFINS CST 08 (operacao sem incidencia): nao ha receita.
 *   IBS/CBS CST 410 / cClassTrib 410999 (nao incidencia): remessa nao e fornecimento
 *         oneroso. E o que as remessas 5901 e retornos 6916 de terceiros trazem em 2026
 *         (WEG 878640, Keyence 4260).
 *   Pagamento tPag 90 (sem pagamento), vPag 0.
 *
 * Nada aqui e beneficio de reducao: a nota sai sem ICMS, sem IPI e sem PIS/COFINS, e o
 * texto abaixo vai nas informacoes complementares porque a SEFAZ exige a base legal em
 * dados adicionais desde 03/02/2025.
 */

export const REMESSA_CONSERTO = {
  cbenef: "SC840007",
  cstIcms: "50",
  cstIpi: "55",
  cEnqIpi: "108",
  cstPisCofins: "08",
  cstIbsCbs: "410",
  cClassTrib: "410999",
  formaPagamento: "90",
  prazoRetornoDias: 180,
  naturezas: {
    REMESSA_CONSERTO_INTERNA: { cfop: "5915", natOp: "REMESSA PARA CONSERTO DENTRO DO ESTADO" },
    REMESSA_CONSERTO_INTERESTADUAL: { cfop: "6915", natOp: "REMESSA PARA CONSERTO FORA DO ESTADO" },
  },
  textoIcms: "ICMS suspenso, conforme o inciso I do art. 27 do Anexo 2 do Decreto nº 2.870/01 - RICMS-SC/01 (cBenef SC840007)",
  textoIpi: "IPI suspenso, conforme o inciso VI do art. 43 do Decreto nº 7.212/10 - RIPI/10",
  textoRetorno: "Mercadoria remetida para conserto ou análise em garantia, com retorno ao estabelecimento de origem no prazo de 180 dias",
} as const;

export type NaturezaRemessaConserto = keyof typeof REMESSA_CONSERTO.naturezas;

export function ehNaturezaRemessaConserto(codigo: string): codigo is NaturezaRemessaConserto {
  return codigo in REMESSA_CONSERTO.naturezas;
}

/** Frases das informacoes complementares da remessa, na ordem em que a contabilidade as lista. */
export function textosRemessaConserto() {
  return [REMESSA_CONSERTO.textoIcms, REMESSA_CONSERTO.textoIpi, REMESSA_CONSERTO.textoRetorno];
}

/**
 * Confere, item a item, que a conferencia trouxe a tributacao da remessa. A nota nao sai com
 * outra coisa: um CST de venda numa remessa destacaria imposto que nao existe.
 */
export function motivoItemForaDaRemessaConserto(item: {
  codigo: string;
  cfop: string;
  situacaoIcms: string;
  aliquotaIcms: number | null;
  cbenef: string | null;
  cstIpi: string;
  aliquotaIpi: number | null;
  cstPis: string;
  cstCofins: string;
}, natureza: NaturezaRemessaConserto): string | null {
  const esperado = REMESSA_CONSERTO.naturezas[natureza];
  const problemas: string[] = [];
  if (item.cfop !== esperado.cfop) problemas.push(`CFOP ${item.cfop} (esperado ${esperado.cfop})`);
  if (item.situacaoIcms !== REMESSA_CONSERTO.cstIcms) problemas.push(`CST ICMS ${item.situacaoIcms} (esperado ${REMESSA_CONSERTO.cstIcms})`);
  if (item.aliquotaIcms !== null && item.aliquotaIcms !== 0) problemas.push(`alíquota de ICMS ${item.aliquotaIcms}% (remessa não destaca ICMS)`);
  if ((item.cbenef ?? "") !== REMESSA_CONSERTO.cbenef) problemas.push(`cBenef ${item.cbenef ?? "vazio"} (esperado ${REMESSA_CONSERTO.cbenef})`);
  if (item.cstIpi !== REMESSA_CONSERTO.cstIpi) problemas.push(`CST IPI ${item.cstIpi} (esperado ${REMESSA_CONSERTO.cstIpi})`);
  if (item.aliquotaIpi !== null && item.aliquotaIpi !== 0) problemas.push(`alíquota de IPI ${item.aliquotaIpi}% (remessa não destaca IPI)`);
  if (item.cstPis !== REMESSA_CONSERTO.cstPisCofins || item.cstCofins !== REMESSA_CONSERTO.cstPisCofins) {
    problemas.push(`PIS/COFINS ${item.cstPis}/${item.cstCofins} (esperado ${REMESSA_CONSERTO.cstPisCofins})`);
  }
  if (problemas.length === 0) return null;
  return `item ${item.codigo} não está tributado como remessa para conserto: ${problemas.join("; ")}. Refaça a conferência`;
}
