/**
 * Valor aproximado dos tributos (Lei 12.741/2012, "Lei da Transparencia"), pela tabela
 * do IBPT ("De Olho no Imposto"), por NCM e UF do emitente.
 *
 * Regras decididas pelo Gabriel em 16/09/2026:
 *
 *   1. So existe em venda a consumidor final (indFinal = 1). Com indFinal = 0 a nota
 *      nao traz a frase nem o vTotTrib — a lei fala do consumidor, e a venda entre
 *      contribuintes nao tem a quem informar.
 *   2. O valor e federal + estadual da tabela IBPT, nunca o ICMS + IPI da propria nota
 *      (que era o que o emissor antigo somava, e o que este fazia ate 16/09/2026).
 *
 * Nada aqui inventa aliquota. Faltando a linha vigente de QUALQUER item, a nota inteira
 * sai sem a frase e sem o vTotTrib: um total que cobre metade dos itens afirmaria um
 * valor menor que o real. A conferencia mostra quais NCMs faltaram.
 *
 * O municipal da tabela e de servico (NBS/LC 116) e nao entra na NF-e de produto.
 */

export type IbptNcm = {
  uf: string;
  codigo: string;
  ex?: string | null;
  descricao?: string | null;
  nacional_federal_pct: number | string;
  importados_federal_pct: number | string;
  estadual_pct: number | string;
  municipal_pct?: number | string | null;
  vigencia_inicio: string;
  vigencia_fim: string;
  versao: string;
  chave?: string | null;
  fonte?: string | null;
};

/**
 * Origens da Tabela A do CST que o proprio layout chama de "Estrangeira" (1, 2, 6 e 7)
 * usam a coluna de importados. As demais (0, 3, 4, 5, 8) sao "Nacional", ainda que com
 * conteudo de importacao, e usam a coluna nacional — e a leitura literal da tabela.
 */
const ORIGENS_ESTRANGEIRAS = new Set([1, 2, 6, 7]);

export function origemUsaImportadosIbpt(origem: number) {
  return ORIGENS_ESTRANGEIRAS.has(origem);
}

function pct(valor: unknown) {
  const n = Number(valor);
  return Number.isFinite(n) && n >= 0 && n <= 100 ? n : null;
}

function round2(valor: number) {
  return Math.round((valor + Number.EPSILON) * 100) / 100;
}

/** Data civil (YYYY-MM-DD) em America/Sao_Paulo, a mesma do dhEmi. */
export function dataCivilSaoPaulo(data: Date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(data);
}

/**
 * Linha vigente do NCM na data, na UF. Com duas versoes cobrindo o mesmo dia (o IBPT
 * publica a nova antes de a velha vencer), vale a de inicio mais recente.
 */
export function linhaIbptVigente(
  linhas: IbptNcm[] | null | undefined,
  uf: string,
  ncm: string,
  data: string,
  ex = "",
) {
  const alvo = String(ncm ?? "").replace(/\D/g, "");
  const ufAlvo = String(uf ?? "").trim().toUpperCase();
  const candidatas = (linhas ?? []).filter((linha) =>
    String(linha.codigo ?? "").replace(/\D/g, "") === alvo
    && String(linha.uf ?? "").trim().toUpperCase() === ufAlvo
    && String(linha.ex ?? "").trim() === String(ex ?? "").trim()
    && String(linha.vigencia_inicio).slice(0, 10) <= data
    && String(linha.vigencia_fim).slice(0, 10) >= data
    && pct(linha.nacional_federal_pct) !== null
    && pct(linha.importados_federal_pct) !== null
    && pct(linha.estadual_pct) !== null
  );
  candidatas.sort((a, b) => String(b.vigencia_inicio).localeCompare(String(a.vigencia_inicio)));
  return candidatas[0] ?? null;
}

/** Federal (nacional ou importado, pela origem) + estadual sobre o valor do item. */
export function tributosAproximadosItem(valorItem: number, origem: number, linha: IbptNcm) {
  const federalPct = pct(origemUsaImportadosIbpt(origem) ? linha.importados_federal_pct : linha.nacional_federal_pct)!;
  const estadualPct = pct(linha.estadual_pct)!;
  const federal = round2(valorItem * federalPct / 100);
  const estadual = round2(valorItem * estadualPct / 100);
  return { federal, estadual, total: round2(federal + estadual), federalPct, estadualPct };
}

export type ItemIbpt = { codigo: string; ncm: string; origem: number; valor: number };

export type ResultadoIbpt =
  | { aplica: false; motivo: "NAO_CONSUMIDOR_FINAL" | "NAO_E_VENDA" }
  | { aplica: false; motivo: "SEM_TABELA"; ncmsSemTabela: string[] }
  | {
    aplica: true;
    itens: Array<{ federal: number; estadual: number; total: number }>;
    federal: number;
    estadual: number;
    total: number;
    versoes: string[];
    chaves: string[];
  };

/**
 * Decide e calcula para a nota inteira. `consumidorFinal` e o indFinal; `ehVenda` diz se
 * a natureza e de venda (remessa, retorno, devolucao nao levam a frase).
 */
export function tributosAproximadosNota(params: {
  consumidorFinal: number;
  ehVenda: boolean;
  uf: string;
  data: string;
  itens: ItemIbpt[];
  tabela: IbptNcm[] | null | undefined;
}): ResultadoIbpt {
  if (!params.ehVenda) return { aplica: false, motivo: "NAO_E_VENDA" };
  if (params.consumidorFinal !== 1) return { aplica: false, motivo: "NAO_CONSUMIDOR_FINAL" };
  const linhas = params.itens.map((item) => linhaIbptVigente(params.tabela, params.uf, item.ncm, params.data));
  const ncmsSemTabela = [...new Set(params.itens.filter((_, i) => !linhas[i]).map((item) => item.ncm))];
  if (ncmsSemTabela.length > 0) return { aplica: false, motivo: "SEM_TABELA", ncmsSemTabela };
  const itens = params.itens.map((item, i) => tributosAproximadosItem(item.valor, item.origem, linhas[i]!));
  const federal = round2(itens.reduce((soma, item) => soma + item.federal, 0));
  const estadual = round2(itens.reduce((soma, item) => soma + item.estadual, 0));
  return {
    aplica: true,
    itens: itens.map(({ federal: f, estadual: e, total }) => ({ federal: f, estadual: e, total })),
    federal,
    estadual,
    total: round2(federal + estadual),
    versoes: [...new Set(linhas.map((linha) => String(linha!.versao)))],
    chaves: [...new Set(linhas.map((linha) => String(linha!.chave ?? "")).filter(Boolean))],
  };
}

function moeda(valor: number) {
  return valor.toFixed(2).replace(".", ",");
}

/** Frase do infCpl, com a fonte que o IBPT exige citar. */
export function textoTributosAproximados(resultado: Extract<ResultadoIbpt, { aplica: true }>) {
  const versao = resultado.versoes.join("/");
  const chave = resultado.chaves.length === 1 ? ` ${resultado.chaves[0]}` : "";
  return `Valor aproximado dos tributos: ${moeda(resultado.total)} `
    + `(federal ${moeda(resultado.federal)} e estadual ${moeda(resultado.estadual)}). `
    + `Fonte: IBPT${chave}, versão ${versao}.`;
}
