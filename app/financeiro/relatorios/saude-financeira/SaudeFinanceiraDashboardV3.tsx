"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";

type UnknownRecord = Record<string, unknown>;
type Periodo = "mensal" | "anual";
type Regime = "competencia" | "caixa";
type Dimensao = "plano" | "motivo" | "centro";

type Filters = {
  periodo: Periodo;
  ano: number;
  mes: number;
  regime: Regime;
};

type RankedItem = {
  label: string;
  value: number;
  count: number | null;
  percentage: number | null;
};

type SeriesItem = {
  label: string;
  entradas: number;
  saidas: number;
  resultado: number;
};

type AlertItem = {
  id: string;
  severity: string;
  type: string;
  title: string;
  detail: string;
  reference: string;
  date: string;
  action: string;
  value: number | null;
};

type CompetenciaData = {
  receita: number;
  despesa: number;
  resultado: number;
  margem: number;
  investimentos: number;
  dividaIdentificada: number;
  totalAp: number;
  naoClassificado: number;
  anterior: UnknownRecord;
  serie: SeriesItem[];
  porPlano: RankedItem[];
  porMotivo: RankedItem[];
  porCentro: RankedItem[];
  topFornecedores: RankedItem[];
};

type CaixaData = {
  recebimentos: number;
  pagamentos: number;
  saldo: number;
  investimentosPagos: number;
  dividaPaga: number;
  juros: number;
  multas: number;
  descontos: number;
  naoConciliado: number;
  movimentosSemDirecao: number;
  anterior: UnknownRecord;
  serie: SeriesItem[];
  porMotivo: RankedItem[];
  topFornecedores: RankedItem[];
};

type LegadoExcluidoData = {
  tituloQtd: number;
  parcelaQtd: number;
  valorAberto: number;
  valorParcelasAberto: number;
  corte: string;
  marcadoEm: string;
};

type CompromissosData = {
  apAberto: number;
  apVencido: number;
  apVencer30: number;
  arAberto: number;
  arVencido: number;
  arVencer30: number;
  cobertura30: number | null;
  dividaAberta: number;
  investimentosAbertos: number;
  apPeriodoTotal: number;
  apPeriodoAberto: number;
  apPeriodoQtd: number;
  agingAp: RankedItem[];
  legadoExcluido: LegadoExcluidoData;
};

type CommitmentCategoryData = {
  code: string;
  name: string;
  count: number;
  value: number;
  overdue: number;
  next30: number;
  percentage: number;
};

type CommitmentClassificationData = {
  referenceValue: number;
  classifiedOpen: number;
  financialOpen: number;
  adjustmentsOpen: number;
  debtOpen: number;
  investmentsOpen: number;
  referenceDifference: number;
  reconciliationDifference: number;
  operationalApOpen: number;
  operationalOutsideComposition: number;
  reviewCount: number;
  reviewValue: number;
  possibleUnclassifiedCount: number;
  possibleUnclassifiedValue: number;
  referenceDate: string;
  batchCode: string;
  categories: CommitmentCategoryData[];
};

type CommitmentReferenceCategoryData = {
  code: string;
  name: string;
  count: number;
  value: number;
  percentage: number;
};

type CommitmentReferenceData = {
  referenceValue: number;
  reconciledValue: number;
  reconciliationDifference: number;
  count: number;
  batchCode: string;
  categories: CommitmentReferenceCategoryData[];
};

type QualidadeData = {
  coberturaRateioPct: number;
  coberturaCentroPct: number;
  coberturaClassificacaoPct: number;
  totalAlertas: number;
  titulosAfetados: number;
  valorAfetado: number;
  porSeveridade: RankedItem[];
  porTipo: RankedItem[];
  itens: AlertItem[];
};

type EstoquePendenteItem = {
  type: "SEM_CADASTRO" | "SEM_ENTRADA";
  nfId: number;
  nfNumber: string;
  date: string;
  description: string;
  value: number;
};

type EstoqueSaudeData = {
  meta: {
    positionDate: string;
    valuationCriterion: string;
  };
  period: {
    purchasesForStock: number;
    directPurchasesForOs: number;
    otherEntries: number;
    stockConsumptionByOs: number;
    directOutputsForOs: number;
    otherOutputs: number;
    adjustments: number;
    outputsValuedAtCurrentCost: number;
    movementsWithoutValue: number;
  };
  position: {
    currentValue: number;
    openingValue: number;
    closingValue: number;
    periodVariation: number;
    itemsWithBalance: number;
    itemsWithoutCost: number;
    quantityWithoutCost: number;
    negativeItems: number;
    negativeQuantity: number;
    itemsWithoutMovement180d: number;
    valueWithoutMovement180d: number;
    itemsAboveIdeal: number;
    valueAboveIdeal: number;
  };
  quality: {
    expectedItems: number;
    itemsWithoutRegistration: number;
    valueWithoutRegistration: number;
    itemsWithoutEntry: number;
    valueWithoutEntry: number;
  };
  pending: EstoquePendenteItem[];
};

type HealthReport = {
  meta: UnknownRecord;
  competencia: CompetenciaData;
  caixa: CaixaData;
  compromissos: CompromissosData;
  qualidade: QualidadeData;
};

const MONTHS = [
  "Janeiro",
  "Fevereiro",
  "Março",
  "Abril",
  "Maio",
  "Junho",
  "Julho",
  "Agosto",
  "Setembro",
  "Outubro",
  "Novembro",
  "Dezembro",
] as const;

const moneyFormatter = new Intl.NumberFormat("pt-BR", {
  style: "currency",
  currency: "BRL",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

function asRecord(value: unknown): UnknownRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as UnknownRecord) : {};
}

function first(record: UnknownRecord, keys: string[]): unknown {
  for (const key of keys) {
    if (record[key] !== undefined && record[key] !== null) return record[key];
  }
  return undefined;
}

function num(value: unknown): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const raw = String(value ?? "").trim();
  if (!raw) return 0;
  const normalized = raw.includes(",") ? raw.replace(/\./g, "").replace(",", ".") : raw;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : 0;
}

function optionalNum(value: unknown): number | null {
  if (value === null || value === undefined || String(value).trim() === "") return null;
  return num(value);
}

function text(value: unknown, fallback = ""): string {
  const normalized = String(value ?? "").trim();
  return normalized || fallback;
}

function readNum(record: UnknownRecord, ...keys: string[]): number {
  return num(first(record, keys));
}

function normalizePct(value: number): number {
  return Math.max(0, Math.min(100, value));
}

function collection(value: unknown): UnknownRecord[] {
  if (Array.isArray(value)) {
    return value.map((item) => (typeof item === "object" && item !== null ? asRecord(item) : { valor: item }));
  }
  const record = asRecord(value);
  return Object.entries(record).map(([label, item]) =>
    typeof item === "object" && item !== null ? { label, ...asRecord(item) } : { label, valor: item }
  );
}

function itemLabel(row: UnknownRecord, fallback: string): string {
  const code = text(first(row, ["codigo", "code", "chave"]));
  const name = text(first(row, ["nome", "label", "descricao", "fornecedor", "fornecedor_nome", "categoria"]));
  if (code && name && code !== name) return `${code} — ${name}`;
  return name || code || fallback;
}

function normalizeRanked(value: unknown): RankedItem[] {
  return collection(value)
    .map((row, index) => ({
      label: itemLabel(row, `Item ${index + 1}`),
      value: readNum(row, "valor", "total", "amount", "despesa", "pagamentos", "valor_total", "total_aberto"),
      count: optionalNum(first(row, ["quantidade", "qtd", "count", "titulos"])),
      percentage: optionalNum(first(row, ["percentual", "percentage", "pct", "participacao"])),
    }))
    .sort((left, right) => Math.abs(right.value) - Math.abs(left.value));
}

function normalizeAging(value: unknown): RankedItem[] {
  const rows = normalizeRanked(value);
  if (Array.isArray(value)) return rows;

  const legacyLabels: Record<string, string> = {
    avencer: "A vencer",
    vencido030: "Vencido 0–30 dias",
    vencido0a30: "Vencido 0–30 dias",
    vencido3160: "Vencido 31–60 dias",
    vencido31a60: "Vencido 31–60 dias",
    vencido6190: "Vencido 61–90 dias",
    vencido61a90: "Vencido 61–90 dias",
    vencido90mais: "Vencido há mais de 90 dias",
    vencidomais90: "Vencido há mais de 90 dias",
    acima90: "Vencido há mais de 90 dias",
  };

  return rows.map((row) => {
    const key = row.label
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]/gi, "")
      .toLowerCase();
    return { ...row, label: legacyLabels[key] ?? row.label };
  });
}

function normalizeSeries(value: unknown, regime: Regime): SeriesItem[] {
  return collection(value).map((row, index) => {
    const entradas =
      regime === "competencia"
        ? readNum(row, "receita", "receitas", "entrada", "entradas")
        : readNum(row, "recebimentos", "recebimento", "entrada", "entradas");
    const saidas =
      regime === "competencia"
        ? Math.abs(readNum(row, "despesa", "despesas", "saida", "saidas"))
        : Math.abs(readNum(row, "pagamentos", "pagamento", "saida", "saidas"));
    const explicitResult = first(row, ["resultado", "saldo", "delta", "geracao_caixa", "geracaoCaixa"]);
    return {
      label: text(first(row, ["label", "periodo", "competencia", "mes", "data", "data_ref"]), String(index + 1)),
      entradas,
      saidas,
      resultado: explicitResult === undefined ? entradas - saidas : num(explicitResult),
    };
  });
}

function normalizeSeverity(value: unknown): string {
  const severity = text(value, "ATENÇÃO")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
  if (["CRITICO", "CRITICA", "CRITICAL"].includes(severity)) return "CRÍTICA";
  if (["ALTO", "ALTA", "HIGH", "ERRO", "ERROR"].includes(severity)) return "ALTA";
  if (["MEDIO", "MEDIA", "MEDIUM", "WARNING", "ATENCAO"].includes(severity)) return "MÉDIA";
  if (["BAIXO", "BAIXA", "LOW"].includes(severity)) return "BAIXA";
  return severity;
}

function normalizeAlerts(value: unknown): AlertItem[] {
  return collection(value).map((row, index) => ({
    id: text(first(row, ["id", "chave", "key"]), String(index + 1)),
    severity: normalizeSeverity(first(row, ["severidade", "severity", "nivel"])),
    type: text(first(row, ["tipo", "type", "categoria", "codigo"]), "OUTRA"),
    title: text(first(row, ["titulo", "title", "mensagem", "message"]), "Inconsistência"),
    detail: text(first(row, ["detalhe", "detail", "descricao", "description"])),
    reference: text(
      first(row, ["referencia", "reference", "titulo_numero", "documento", "fornecedor_nome", "entidade"]),
      "—"
    ),
    date: text(first(row, ["data", "date", "data_ref"])),
    action: text(first(row, ["acao", "action"]), "Revisar o lançamento e completar a classificação."),
    value: optionalNum(first(row, ["valor", "value", "valor_afetado", "amount"])),
  }));
}

function unwrapRpcPayload(value: unknown): UnknownRecord | null {
  let current: unknown = value;
  if (Array.isArray(current)) current = current[0] ?? null;
  let record = asRecord(current);
  if (!Object.keys(record).length) return null;
  if (!record.competencia && !record.caixa && !record.compromissos && !record.qualidade) {
    const nested = first(record, ["relatorio_saude_financeira", "resultado", "data"]);
    if (nested && typeof nested === "object") record = asRecord(nested);
  }
  return Object.keys(record).length ? record : null;
}

function normalizeReport(value: unknown): HealthReport | null {
  const root = unwrapRpcPayload(value);
  if (!root) return null;

  const competencia = asRecord(root.competencia);
  const caixa = asRecord(root.caixa);
  const compromissos = asRecord(root.compromissos);
  const legadoExcluido = asRecord(
    first(compromissos, ["legadoExcluido", "legado_excluido"])
  );
  const qualidade = asRecord(root.qualidade);

  return {
    meta: asRecord(root.meta),
    competencia: {
      receita: readNum(competencia, "receita"),
      despesa: readNum(competencia, "despesa"),
      resultado: readNum(competencia, "resultado"),
      margem: readNum(competencia, "margem"),
      investimentos: readNum(competencia, "investimentos"),
      dividaIdentificada: readNum(competencia, "dividaIdentificada", "divida_identificada"),
      totalAp: readNum(competencia, "totalAp", "total_ap"),
      naoClassificado: readNum(competencia, "naoClassificado", "nao_classificado"),
      anterior: asRecord(competencia.anterior),
      serie: normalizeSeries(competencia.serie, "competencia"),
      porPlano: normalizeRanked(first(competencia, ["porPlano", "por_plano"])),
      porMotivo: normalizeRanked(first(competencia, ["porMotivo", "por_motivo"])),
      porCentro: normalizeRanked(first(competencia, ["porCentro", "por_centro"])),
      topFornecedores: normalizeRanked(first(competencia, ["topFornecedores", "top_fornecedores"])),
    },
    caixa: {
      recebimentos: readNum(caixa, "recebimentos"),
      pagamentos: readNum(caixa, "pagamentos"),
      saldo: readNum(caixa, "saldo"),
      investimentosPagos: readNum(caixa, "investimentosPagos", "investimentos_pagos"),
      dividaPaga: readNum(caixa, "dividaPaga", "divida_paga"),
      juros: readNum(caixa, "juros"),
      multas: readNum(caixa, "multas"),
      descontos: readNum(caixa, "descontos"),
      naoConciliado: readNum(caixa, "naoConciliado", "nao_conciliado"),
      movimentosSemDirecao: readNum(caixa, "movimentosSemDirecao", "movimentos_sem_direcao"),
      anterior: asRecord(caixa.anterior),
      serie: normalizeSeries(caixa.serie, "caixa"),
      porMotivo: normalizeRanked(first(caixa, ["porMotivo", "por_motivo"])),
      topFornecedores: normalizeRanked(first(caixa, ["topFornecedores", "top_fornecedores"])),
    },
    compromissos: {
      apAberto: readNum(compromissos, "apAberto", "ap_aberto"),
      apVencido: readNum(compromissos, "apVencido", "ap_vencido"),
      apVencer30: readNum(compromissos, "apVencer30", "ap_vencer_30"),
      arAberto: readNum(compromissos, "arAberto", "ar_aberto"),
      arVencido: readNum(compromissos, "arVencido", "ar_vencido"),
      arVencer30: readNum(compromissos, "arVencer30", "ar_vencer_30"),
      cobertura30: optionalNum(first(compromissos, ["cobertura30", "cobertura_30"])),
      dividaAberta: readNum(compromissos, "dividaAberta", "divida_aberta"),
      investimentosAbertos: readNum(compromissos, "investimentosAbertos", "investimentos_abertos"),
      apPeriodoTotal: readNum(compromissos, "apPeriodoTotal", "ap_periodo_total"),
      apPeriodoAberto: readNum(compromissos, "apPeriodoAberto", "ap_periodo_aberto"),
      apPeriodoQtd: readNum(compromissos, "apPeriodoQtd", "ap_periodo_qtd"),
      agingAp: normalizeAging(first(compromissos, ["agingAp", "aging_ap"])),
      legadoExcluido: {
        tituloQtd: readNum(legadoExcluido, "tituloQtd", "titulo_qtd"),
        parcelaQtd: readNum(legadoExcluido, "parcelaQtd", "parcela_qtd"),
        valorAberto: readNum(legadoExcluido, "valorAberto", "valor_aberto"),
        valorParcelasAberto: readNum(
          legadoExcluido,
          "valorParcelasAberto",
          "valor_parcelas_aberto"
        ),
        corte: text(first(legadoExcluido, ["corte", "corte_date"])),
        marcadoEm: text(first(legadoExcluido, ["marcadoEm", "marcado_em"])),
      },
    },
    qualidade: {
      coberturaRateioPct: normalizePct(readNum(qualidade, "coberturaRateioPct", "cobertura_rateio_pct")),
      coberturaCentroPct: normalizePct(readNum(qualidade, "coberturaCentroPct", "cobertura_centro_pct")),
      coberturaClassificacaoPct: normalizePct(
        readNum(qualidade, "coberturaClassificacaoPct", "cobertura_classificacao_pct")
      ),
      totalAlertas: readNum(qualidade, "totalAlertas", "total_alertas"),
      titulosAfetados: readNum(qualidade, "titulosAfetados", "titulos_afetados"),
      valorAfetado: readNum(qualidade, "valorAfetado", "valor_afetado"),
      porSeveridade: normalizeRanked(first(qualidade, ["porSeveridade", "por_severidade"])),
      porTipo: normalizeRanked(first(qualidade, ["porTipo", "por_tipo"])),
      itens: normalizeAlerts(qualidade.itens),
    },
  };
}

function normalizeEstoqueSaude(value: unknown): EstoqueSaudeData | null {
  const root = asRecord(Array.isArray(value) ? value[0] : value);
  if (!Object.keys(root).length) return null;

  const meta = asRecord(root.meta);
  const period = asRecord(first(root, ["periodo", "period"]));
  const position = asRecord(first(root, ["posicao", "position"]));
  const quality = asRecord(first(root, ["qualidade", "quality"]));
  const pending = collection(first(root, ["pendencias", "pending"])).map((row, index) => ({
    type: text(first(row, ["tipo", "type"]), "SEM_CADASTRO") === "SEM_ENTRADA" ? "SEM_ENTRADA" as const : "SEM_CADASTRO" as const,
    nfId: readNum(row, "nfId", "nf_id") || index + 1,
    nfNumber: text(first(row, ["nfNumero", "nf_numero"]), "-"),
    date: text(first(row, ["data", "date"])),
    description: text(first(row, ["descricao", "description"]), "Item sem descrição"),
    value: readNum(row, "valor", "value"),
  }));

  return {
    meta: {
      positionDate: text(first(meta, ["posicaoAtualEm", "posicao_atual_em"])),
      valuationCriterion: text(first(meta, ["criterioValoracao", "criterio_valoracao"])),
    },
    period: {
      purchasesForStock: readNum(period, "comprasParaEstoque", "compras_para_estoque"),
      directPurchasesForOs: readNum(period, "comprasDiretasOs", "compras_diretas_os"),
      otherEntries: readNum(period, "outrasEntradas", "outras_entradas"),
      stockConsumptionByOs: readNum(period, "consumoEstoqueOs", "consumo_estoque_os"),
      directOutputsForOs: readNum(period, "saidasDiretasOs", "saidas_diretas_os"),
      otherOutputs: readNum(period, "outrasSaidas", "outras_saidas"),
      adjustments: readNum(period, "ajustes"),
      outputsValuedAtCurrentCost: readNum(period, "saidasValorizadasPorCustoAtual", "saidas_valorizadas_por_custo_atual"),
      movementsWithoutValue: readNum(period, "movimentosSemValor", "movimentos_sem_valor"),
    },
    position: {
      currentValue: readNum(position, "valorAtual", "valor_atual"),
      openingValue: readNum(position, "valorInicioPeriodo", "valor_inicio_periodo"),
      closingValue: readNum(position, "valorFimPeriodo", "valor_fim_periodo"),
      periodVariation: readNum(position, "variacaoPeriodo", "variacao_periodo"),
      itemsWithBalance: readNum(position, "itensComSaldo", "itens_com_saldo"),
      itemsWithoutCost: readNum(position, "itensSemCusto", "itens_sem_custo"),
      quantityWithoutCost: readNum(position, "quantidadeSemCusto", "quantidade_sem_custo"),
      negativeItems: readNum(position, "itensNegativos", "itens_negativos"),
      negativeQuantity: readNum(position, "quantidadeNegativa", "quantidade_negativa"),
      itemsWithoutMovement180d: readNum(position, "itensSemMovimento180d", "itens_sem_movimento_180d"),
      valueWithoutMovement180d: readNum(position, "valorSemMovimento180d", "valor_sem_movimento_180d"),
      itemsAboveIdeal: readNum(position, "itensAcimaIdeal", "itens_acima_ideal"),
      valueAboveIdeal: readNum(position, "valorAcimaIdeal", "valor_acima_ideal"),
    },
    quality: {
      expectedItems: readNum(quality, "itensEsperados", "itens_esperados"),
      itemsWithoutRegistration: readNum(quality, "itensSemCadastro", "itens_sem_cadastro"),
      valueWithoutRegistration: readNum(quality, "valorSemCadastro", "valor_sem_cadastro"),
      itemsWithoutEntry: readNum(quality, "itensSemEntrada", "itens_sem_entrada"),
      valueWithoutEntry: readNum(quality, "valorSemEntrada", "valor_sem_entrada"),
    },
    pending,
  };
}

function normalizeCommitmentClassification(value: unknown): CommitmentClassificationData | null {
  const root = unwrapRpcPayload(value);
  if (!root) return null;

  const meta = asRecord(root.meta);
  const review = asRecord(root.revisao);
  const categories = collection(root.categorias).map((row, index) => ({
    code: text(first(row, ["codigo", "code"]), `CATEGORIA_${index + 1}`),
    name: text(first(row, ["nome", "name", "label"]), `Categoria ${index + 1}`),
    count: readNum(row, "quantidade", "qtd", "count"),
    value: readNum(row, "valorAberto", "valor_aberto", "valor"),
    overdue: readNum(row, "vencido"),
    next30: readNum(row, "proximos30", "proximos_30"),
    percentage: readNum(row, "percentual", "percentage"),
  }));

  return {
    referenceValue: readNum(root, "valorReferenciaInformado", "valor_referencia_informado"),
    classifiedOpen: readNum(root, "totalClassificadoAberto", "total_classificado_aberto"),
    financialOpen: readNum(root, "totalFinanceiroAberto", "total_financeiro_aberto"),
    adjustmentsOpen: readNum(root, "ajustesAberto", "ajustes_aberto"),
    debtOpen: readNum(root, "dividaAberta", "divida_aberta"),
    investmentsOpen: readNum(root, "investimentosAbertos", "investimentos_abertos"),
    referenceDifference: readNum(root, "diferencaReferencia", "diferenca_referencia"),
    reconciliationDifference: readNum(root, "diferencaConciliacao", "diferenca_conciliacao"),
    operationalApOpen: readNum(root, "apOperacionalAberto", "ap_operacional_aberto"),
    operationalOutsideComposition: readNum(
      root,
      "apOperacionalForaComposicao",
      "ap_operacional_fora_composicao"
    ),
    reviewCount: readNum(review, "quantidade", "qtd"),
    reviewValue: readNum(review, "valorAberto", "valor_aberto"),
    possibleUnclassifiedCount: readNum(
      review,
      "possiveisSemClassificacaoQtd",
      "possiveis_sem_classificacao_qtd"
    ),
    possibleUnclassifiedValue: readNum(
      review,
      "possiveisSemClassificacaoValor",
      "possiveis_sem_classificacao_valor"
    ),
    referenceDate: text(first(meta, ["referencia", "referenceDate", "reference_date"])),
    batchCode: text(first(meta, ["loteCodigo", "lote_codigo"])),
    categories,
  };
}

function normalizeCommitmentReference(value: unknown): CommitmentReferenceData | null {
  const root = unwrapRpcPayload(value);
  if (!root) return null;

  return {
    referenceValue: readNum(root, "valorReferencia", "valor_referencia"),
    reconciledValue: readNum(root, "valorReconciliado", "valor_reconciliado"),
    reconciliationDifference: readNum(root, "diferencaConciliacao", "diferenca_conciliacao"),
    count: readNum(root, "quantidadeTitulos", "quantidade_titulos"),
    batchCode: text(first(root, ["loteCodigo", "lote_codigo"])),
    categories: collection(root.categorias).map((row, index) => ({
      code: text(first(row, ["codigo", "code"]), `CATEGORIA_${index + 1}`),
      name: text(first(row, ["nome", "name", "label"]), `Categoria ${index + 1}`),
      count: readNum(row, "quantidade", "qtd", "count"),
      value: readNum(row, "valor", "valorReferencia", "valor_referencia"),
      percentage: readNum(row, "percentual", "percentage"),
    })),
  };
}

function defaultFilters(): Filters {
  const now = new Date();
  return {
    periodo: "mensal",
    ano: now.getFullYear(),
    mes: now.getMonth() + 1,
    regime: "competencia",
  };
}

function parseLocationFilters(): Filters {
  const defaults = defaultFilters();
  if (typeof window === "undefined") return defaults;
  const params = new URLSearchParams(window.location.search);
  const year = Number(params.get("ano"));
  const month = Number(params.get("mes"));
  return {
    periodo: params.get("periodo") === "anual" ? "anual" : "mensal",
    ano: Number.isInteger(year) && year >= 2000 && year <= 2100 ? year : defaults.ano,
    mes: Number.isInteger(month) && month >= 1 && month <= 12 ? month : defaults.mes,
    regime: params.get("regime") === "caixa" ? "caixa" : "competencia",
  };
}

function periodRange(filters: Filters): { start: string; end: string; label: string } {
  if (filters.periodo === "anual") {
    return {
      start: `${filters.ano}-01-01`,
      end: `${filters.ano}-12-31`,
      label: `Ano de ${filters.ano}`,
    };
  }
  const month = String(filters.mes).padStart(2, "0");
  const lastDay = new Date(filters.ano, filters.mes, 0).getDate();
  return {
    start: `${filters.ano}-${month}-01`,
    end: `${filters.ano}-${month}-${String(lastDay).padStart(2, "0")}`,
    label: `${MONTHS[filters.mes - 1]} de ${filters.ano}`,
  };
}

function formatMoney(value: number): string {
  return moneyFormatter.format(Number.isFinite(value) ? value : 0);
}

function formatSignedMoney(value: number): string {
  return `${value > 0 ? "+" : ""}${formatMoney(value)}`;
}

function formatPercent(value: number): string {
  return `${value.toLocaleString("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`;
}

function formatDateBR(value: string): string {
  const raw = value.trim();
  if (!raw) return "";
  const iso = /^(\d{4})-(\d{2})-(\d{2})/.exec(raw);
  if (iso) {
    const year = Number(iso[1]);
    const month = Number(iso[2]);
    const day = Number(iso[3]);
    const local = new Date(year, month - 1, day);
    if (
      local.getFullYear() === year &&
      local.getMonth() === month - 1 &&
      local.getDate() === day
    ) {
      return local.toLocaleDateString("pt-BR");
    }
  }
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? raw : parsed.toLocaleDateString("pt-BR");
}

function previousValue(record: UnknownRecord, ...keys: string[]): number {
  return readNum(record, ...keys);
}

function comparison(current: number, previous: number, higherIsBetter: boolean): { label: string; tone: string } | null {
  if (!previous) return null;
  const delta = ((current - previous) / Math.abs(previous)) * 100;
  const favorable = higherIsBetter ? delta >= 0 : delta <= 0;
  return {
    label: `${delta >= 0 ? "+" : ""}${delta.toLocaleString("pt-BR", { maximumFractionDigits: 1 })}% vs. anterior`,
    tone: favorable ? "text-emerald-300" : "text-rose-300",
  };
}

function severityTone(severity: string): string {
  if (severity === "CRÍTICA") return "border-rose-500/40 bg-rose-500/15 text-rose-200";
  if (severity === "ALTA") return "border-orange-500/40 bg-orange-500/15 text-orange-200";
  if (severity === "MÉDIA") return "border-amber-500/40 bg-amber-500/15 text-amber-200";
  if (severity === "BAIXA") return "border-sky-500/40 bg-sky-500/15 text-sky-200";
  return "border-zinc-700 bg-zinc-800/50 text-zinc-300";
}

const commitmentCategoryTones: Record<
  string,
  { border: string; bar: string; value: string }
> = {
  DIVIDA_TRIBUTARIA: {
    border: "border-amber-500/25",
    bar: "bg-amber-400",
    value: "text-amber-200",
  },
  EMPRESTIMO: {
    border: "border-orange-500/25",
    bar: "bg-orange-400",
    value: "text-orange-200",
  },
  MAQUINA: {
    border: "border-violet-500/25",
    bar: "bg-violet-400",
    value: "text-violet-200",
  },
  VEICULO: {
    border: "border-sky-500/25",
    bar: "bg-sky-400",
    value: "text-sky-200",
  },
  AJUSTE: {
    border: "border-zinc-700",
    bar: "bg-zinc-500",
    value: "text-zinc-200",
  },
};

function commitmentTone(code: string) {
  return (
    commitmentCategoryTones[code] ?? {
      border: "border-zinc-700",
      bar: "bg-zinc-500",
      value: "text-zinc-200",
    }
  );
}

function MetricCard({
  title,
  value,
  subtitle,
  current,
  previous,
  higherIsBetter = true,
  valueTone = "text-zinc-100",
}: {
  title: string;
  value: string;
  subtitle: string;
  current?: number;
  previous?: number;
  higherIsBetter?: boolean;
  valueTone?: string;
}) {
  const change =
    typeof current === "number" && typeof previous === "number"
      ? comparison(current, previous, higherIsBetter)
      : null;
  return (
    <article className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
      <div className="text-xs font-medium uppercase tracking-wide text-zinc-500">{title}</div>
      <div className={`mt-2 text-xl font-semibold tabular-nums ${valueTone}`}>{value}</div>
      <div className="mt-1 text-xs text-zinc-500">{subtitle}</div>
      {change ? <div className={`mt-2 text-xs tabular-nums ${change.tone}`}>{change.label}</div> : null}
    </article>
  );
}

function RankBars({ rows, empty }: { rows: RankedItem[]; empty: string }) {
  const max = Math.max(1, ...rows.map((row) => Math.abs(row.value)));
  if (!rows.length) return <div className="py-8 text-center text-sm text-zinc-500">{empty}</div>;
  return (
    <div className="space-y-3">
      {rows.slice(0, 10).map((row) => {
        const width = Math.max(2, (Math.abs(row.value) / max) * 100);
        return (
          <div key={row.label}>
            <div className="mb-1 flex items-start justify-between gap-4 text-sm">
              <span className="min-w-0 truncate text-zinc-300" title={row.label}>
                {row.label}
              </span>
              <span className="shrink-0 text-right font-medium tabular-nums text-zinc-100">
                {formatMoney(row.value)}
              </span>
            </div>
            <div className="h-1.5 overflow-hidden rounded-full bg-zinc-900">
              <div className="h-full rounded-full bg-sky-500/70" style={{ width: `${width}%` }} />
            </div>
          </div>
        );
      })}
    </div>
  );
}

function TrendChart({ rows, regime }: { rows: SeriesItem[]; regime: Regime }) {
  const visible = rows.slice(-24);
  const max = Math.max(1, ...visible.flatMap((row) => [Math.abs(row.entradas), Math.abs(row.saidas)]));
  const aria = visible
    .map((row) => `${row.label}: entradas ${formatMoney(row.entradas)}, saídas ${formatMoney(row.saidas)}`)
    .join("; ");

  if (!visible.length) return <div className="py-12 text-center text-sm text-zinc-500">Sem série no período.</div>;
  return (
    <div className="overflow-x-auto">
      <div
        className="flex h-56 min-w-[680px] items-end gap-2 border-b border-zinc-800 px-2 pt-6"
        role="img"
        aria-label={`Tendência em ${regime === "competencia" ? "competência" : "caixa"}. ${aria}`}
      >
        {visible.map((row, index) => {
          const inHeight = Math.max(3, (Math.abs(row.entradas) / max) * 150);
          const outHeight = Math.max(3, (Math.abs(row.saidas) / max) * 150);
          return (
            <div key={`${row.label}-${index}`} className="flex min-w-0 flex-1 flex-col items-center">
              <div className="flex h-[156px] items-end gap-1">
                <div
                  className="w-2 rounded-t bg-emerald-500/75"
                  style={{ height: `${inHeight}px` }}
                  title={`${row.label}: ${formatMoney(row.entradas)}`}
                />
                <div
                  className="w-2 rounded-t bg-rose-500/70"
                  style={{ height: `${outHeight}px` }}
                  title={`${row.label}: ${formatMoney(row.saidas)}`}
                />
              </div>
              <div
                className={`mt-1 text-[10px] tabular-nums ${row.resultado >= 0 ? "text-emerald-300" : "text-rose-300"}`}
              >
                {row.resultado >= 0 ? "+" : ""}
                {Math.abs(row.resultado) >= 1000
                  ? `${(row.resultado / 1000).toLocaleString("pt-BR", { maximumFractionDigits: 0 })}k`
                  : row.resultado.toLocaleString("pt-BR", { maximumFractionDigits: 0 })}
              </div>
              <div className="mt-1 max-w-16 truncate text-[10px] text-zinc-500" title={row.label}>
                {row.label}
              </div>
            </div>
          );
        })}
      </div>
      <div className="mt-3 flex items-center gap-4 text-xs text-zinc-500">
        <span className="inline-flex items-center gap-1.5">
          <span className="h-2 w-2 rounded-sm bg-emerald-500/75" /> Entradas
        </span>
        <span className="inline-flex items-center gap-1.5">
          <span className="h-2 w-2 rounded-sm bg-rose-500/70" /> Saídas
        </span>
        <span>Valor sob as barras: resultado do período.</span>
      </div>
    </div>
  );
}

function csvCell(value: unknown): string {
  return `"${String(value ?? "").replace(/"/g, '""')}"`;
}

function csvNumber(value: number | null): string {
  return value === null ? "" : value.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

export default function SaudeFinanceiraDashboardV3() {
  const te = useTenantEmpresa();
  const router = useRouter();
  const pathname = usePathname();
  const [filters, setFilters] = useState<Filters>(defaultFilters);
  const [urlReady, setUrlReady] = useState(false);
  const [report, setReport] = useState<HealthReport | null>(null);
  const [commitmentClassification, setCommitmentClassification] =
    useState<CommitmentClassificationData | null>(null);
  const [commitmentReference, setCommitmentReference] =
    useState<CommitmentReferenceData | null>(null);
  const [inventoryHealth, setInventoryHealth] = useState<EstoqueSaudeData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [retryKey, setRetryKey] = useState(0);
  const [dimension, setDimension] = useState<Dimensao>("plano");
  const [severityFilter, setSeverityFilter] = useState("TODAS");
  const [typeFilter, setTypeFilter] = useState("TODOS");
  const [alertSearch, setAlertSearch] = useState("");

  const canFinanceiro = useMemo(() => {
    const read = te.has("financeiro.read");
    const write = te.has("financeiro.write");
    if (read === undefined || write === undefined) return undefined;
    return Boolean(read || write);
  }, [te]);

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  useEffect(() => {
    const applyLocation = () => {
      const next = parseLocationFilters();
      setFilters(next);
      setUrlReady(true);
    };
    applyLocation();
    window.addEventListener("popstate", applyLocation);
    return () => window.removeEventListener("popstate", applyLocation);
  }, []);

  const setFilter = useCallback(
    (patch: Partial<Filters>) => {
      const next = { ...filters, ...patch };
      setFilters(next);
      const params = new URLSearchParams(window.location.search);
      params.set("periodo", next.periodo);
      params.set("ano", String(next.ano));
      if (next.periodo === "mensal") params.set("mes", String(next.mes));
      else params.delete("mes");
      params.set("regime", next.regime);
      router.replace(`${pathname}?${params.toString()}`, { scroll: false });
    },
    [filters, pathname, router]
  );

  const tenantId = te.tenantId ?? null;
  const empresaId = te.empresaId ?? (te.empresas.length === 1 ? te.empresas[0]?.id ?? null : null);
  const ready =
    urlReady &&
    typeof te.sessionUserId === "string" &&
    Boolean(tenantId) &&
    Boolean(empresaId) &&
    canFinanceiro === true;
  const range = useMemo(() => periodRange(filters), [filters]);

  useEffect(() => {
    if (!ready || !tenantId || !empresaId) return;
    let cancelled = false;

    const load = async () => {
      setLoading(true);
      setError(null);
      setReport(null);
      setCommitmentClassification(null);
      setCommitmentReference(null);
      setInventoryHealth(null);
      try {
        const supabase = getSupabaseBrowser();
        const now = new Date();
        const positionDate = [
          now.getFullYear(),
          String(now.getMonth() + 1).padStart(2, "0"),
          String(now.getDate()).padStart(2, "0"),
        ].join("-");
        const [reportResult, classificationResult, referenceResult, inventoryResult] = await Promise.all([
          supabase.schema("f").rpc("relatorio_saude_financeira", {
            p_tenant_id: tenantId,
            p_empresa_id: empresaId,
            p_data_inicio: range.start,
            p_data_fim: range.end,
          }),
          supabase.schema("f").rpc("resumo_classificacao_compromissos", {
            p_tenant_id: tenantId,
            p_empresa_id: empresaId,
            p_data_referencia: positionDate,
          }),
          supabase.schema("f").rpc("resumo_classificacao_compromissos_referencia", {
            p_tenant_id: tenantId,
            p_empresa_id: empresaId,
          }),
          supabase.schema("f").rpc("resumo_estoque_saude_financeira", {
            p_tenant_id: tenantId,
            p_empresa_id: empresaId,
            p_data_inicio: range.start,
            p_data_fim: range.end,
          }),
        ]);
        if (reportResult.error) throw reportResult.error;
        if (classificationResult.error) throw classificationResult.error;
        if (referenceResult.error) throw referenceResult.error;
        if (inventoryResult.error) throw inventoryResult.error;
        if (!cancelled) {
          setReport(normalizeReport(reportResult.data));
          setCommitmentClassification(
            normalizeCommitmentClassification(classificationResult.data)
          );
          setCommitmentReference(
            normalizeCommitmentReference(referenceResult.data)
          );
          setInventoryHealth(normalizeEstoqueSaude(inventoryResult.data));
        }
      } catch (loadError: unknown) {
        if (!cancelled) {
          setError(loadError instanceof Error ? loadError.message : "Não foi possível carregar o diagnóstico financeiro.");
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    void load();
    return () => {
      cancelled = true;
    };
  }, [empresaId, range.end, range.start, ready, retryKey, tenantId]);

  const activeDimension: Dimensao = filters.regime === "caixa" ? "motivo" : dimension;
  const breakdown = useMemo(() => {
    if (!report) return [];
    if (filters.regime === "caixa") return report.caixa.porMotivo;
    if (activeDimension === "centro") return report.competencia.porCentro;
    if (activeDimension === "motivo") return report.competencia.porMotivo;
    return report.competencia.porPlano.map((item) =>
      item.label.toLocaleUpperCase("pt-BR").startsWith("EST_MAT_PRIMA")
        ? { ...item, label: `${item.label} (compras classificadas)` }
        : item
    );
  }, [activeDimension, filters.regime, report]);

  const classifiedStockPurchases = useMemo(
    () =>
      report?.competencia.porPlano.find((item) =>
        item.label.toLocaleUpperCase("pt-BR").startsWith("EST_MAT_PRIMA")
      )?.value ?? 0,
    [report]
  );

  const inventoryVariationOverPurchases = useMemo(() => {
    if (!inventoryHealth) return null;
    const physicalPurchases =
      inventoryHealth.period.purchasesForStock + inventoryHealth.period.directPurchasesForOs;
    if (physicalPurchases <= 0) return null;
    return (inventoryHealth.position.periodVariation / physicalPurchases) * 100;
  }, [inventoryHealth]);

  const series = filters.regime === "competencia" ? report?.competencia.serie ?? [] : report?.caixa.serie ?? [];
  const suppliers = useMemo(
    () =>
      filters.regime === "competencia"
        ? report?.competencia.topFornecedores ?? []
        : report?.caixa.topFornecedores ?? [],
    [filters.regime, report]
  );

  const severityOptions = useMemo(
    () => Array.from(new Set((report?.qualidade.itens ?? []).map((item) => item.severity))).sort(),
    [report]
  );
  const typeOptions = useMemo(
    () => Array.from(new Set((report?.qualidade.itens ?? []).map((item) => item.type))).sort(),
    [report]
  );
  const filteredAlerts = useMemo(() => {
    const query = alertSearch.trim().toLocaleLowerCase("pt-BR");
    return (report?.qualidade.itens ?? []).filter((item) => {
      if (severityFilter !== "TODAS" && item.severity !== severityFilter) return false;
      if (typeFilter !== "TODOS" && item.type !== typeFilter) return false;
      if (!query) return true;
      return [item.title, item.detail, item.reference, item.type, item.action, item.date].some((value) =>
        value.toLocaleLowerCase("pt-BR").includes(query)
      );
    });
  }, [alertSearch, report, severityFilter, typeFilter]);

  const health = useMemo(() => {
    if (!report) return null;
    const result = filters.regime === "competencia" ? report.competencia.resultado : report.caixa.saldo;
    const coverageRatio =
      report.compromissos.cobertura30 ?? (report.compromissos.apVencer30 <= 0 ? 1 : 0);
    const financialPoints = result > 0 ? 30 : result === 0 ? 15 : 0;
    const coveragePoints = Math.max(0, Math.min(20, coverageRatio * 20));
    const overdueRatio =
      report.compromissos.apAberto > 0
        ? Math.min(1, Math.max(0, report.compromissos.apVencido / report.compromissos.apAberto))
        : 0;
    const overduePoints = 15 * (1 - overdueRatio);
    const classificationPoints = report.qualidade.coberturaClassificacaoPct * 0.1;
    const centerPoints = report.qualidade.coberturaCentroPct * 0.1;
    const allocationPoints = report.qualidade.coberturaRateioPct * 0.05;
    const critical = report.qualidade.itens.filter((item) => item.severity === "CRÍTICA").length;
    const high = report.qualidade.itens.filter((item) => item.severity === "ALTA").length;
    const consistencyPoints = Math.max(0, 10 - critical * 3 - high * 2 - report.qualidade.totalAlertas * 0.25);
    const noMovement =
      report.competencia.receita === 0 &&
      report.competencia.despesa === 0 &&
      report.competencia.resultado === 0 &&
      report.caixa.recebimentos === 0 &&
      report.caixa.pagamentos === 0 &&
      report.caixa.saldo === 0 &&
      report.caixa.movimentosSemDirecao === 0;
    const noBase =
      noMovement &&
      report.compromissos.apAberto === 0 &&
      report.compromissos.arAberto === 0 &&
      report.qualidade.totalAlertas === 0;
    const calculatedScore = Math.round(
      Math.max(
        0,
        Math.min(
          100,
          financialPoints +
            coveragePoints +
            overduePoints +
            classificationPoints +
            centerPoints +
            allocationPoints +
            consistencyPoints
        )
      )
    );
    const score = noBase ? 0 : calculatedScore;
    const status = noBase ? "Sem base suficiente" : score >= 80 ? "Saudável" : score >= 60 ? "Atenção" : "Crítico";
    const tone = noBase
      ? "border-zinc-700 bg-zinc-900/50 text-zinc-200"
      : score >= 80
        ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-200"
        : score >= 60
          ? "border-amber-500/30 bg-amber-500/10 text-amber-200"
          : "border-rose-500/30 bg-rose-500/10 text-rose-200";
    const color = noBase ? "#71717a" : score >= 80 ? "#10b981" : score >= 60 ? "#f59e0b" : "#f43f5e";
    const diagnosis = noBase
      ? "Não há movimentos, compromissos em aberto ou alertas suficientes para avaliar a saúde financeira neste recorte."
      : result < 0
        ? "O período consumiu resultado. Revise os maiores destinos de gasto e despesas não classificadas."
        : coverageRatio < 1
          ? "A geração é positiva, mas os recebíveis dos próximos 30 dias não cobrem integralmente os pagamentos previstos."
          : report.qualidade.totalAlertas > 0
            ? "A posição financeira é favorável, com pendências de qualidade que reduzem a confiança do diagnóstico."
            : "Resultado, cobertura e qualidade dos lançamentos sustentam uma leitura financeira favorável.";
    return {
      score,
      status,
      tone,
      color,
      diagnosis,
      contributions: [
        ["Resultado do regime", noBase ? 0 : financialPoints, 30],
        ["Cobertura 30 dias", noBase ? 0 : coveragePoints, 20],
        ["Contas vencidas", noBase ? 0 : overduePoints, 15],
        ["Classificação", noBase ? 0 : classificationPoints, 10],
        ["Centro de custo", noBase ? 0 : centerPoints, 10],
        ["Rateio", noBase ? 0 : allocationPoints, 5],
        ["Consistência", noBase ? 0 : consistencyPoints, 10],
      ] as Array<[string, number, number]>,
    };
  }, [filters.regime, report]);

  const exportCsv = useCallback(() => {
    if (!report) return;
    const rows: string[][] = [
      ["Seção", "Indicador", "Categoria/Referência", "Valor", "Detalhe", "Ação recomendada"],
      ["Filtro", "Período", range.label, "", `${range.start} a ${range.end}`, ""],
      ["Filtro", "Regime", filters.regime === "competencia" ? "Competência" : "Caixa", "", "", ""],
    ];
    const add = (section: string, indicator: string, value: number, detail = "") => {
      rows.push([section, indicator, "", csvNumber(value), detail, ""]);
    };

    if (filters.regime === "competencia") {
      add("KPIs", "Receita", report.competencia.receita);
      add("KPIs", "Despesa", report.competencia.despesa);
      add("KPIs", "Resultado gerencial", report.competencia.resultado);
      add("KPIs", "Margem", report.competencia.margem, "%");
      add("KPIs", "Dívida identificada", report.competencia.dividaIdentificada);
      add("KPIs", "Investimentos", report.competencia.investimentos);
    } else {
      add("KPIs", "Recebimentos", report.caixa.recebimentos);
      add("KPIs", "Pagamentos", report.caixa.pagamentos);
      add("KPIs", "Geração de caixa", report.caixa.saldo);
      add("KPIs", "Dívida paga", report.caixa.dividaPaga);
      add("KPIs", "Investimentos pagos", report.caixa.investimentosPagos);
      add("KPIs", "Não conciliado", report.caixa.naoConciliado);
      add("Qualidade", "Movimentos sem direção AP/AR", report.caixa.movimentosSemDirecao);
    }
    add("Compromissos", "AP aberto", report.compromissos.apAberto);
    add("Compromissos", "AP vencido", report.compromissos.apVencido);
    add("Compromissos", "AP próximos 30 dias", report.compromissos.apVencer30);
    add("Compromissos", "AR próximos 30 dias", report.compromissos.arVencer30);
    add(
      "Legado de implantação",
      "Saldo excluído dos indicadores",
      report.compromissos.legadoExcluido.valorAberto,
      `${report.compromissos.legadoExcluido.tituloQtd} títulos; corte ${
        report.compromissos.legadoExcluido.corte || "não informado"
      }`
    );
    if (commitmentReference) {
      add(
        "Reclassificação dos compromissos",
        "Base histórica reconciliada",
        commitmentReference.referenceValue,
        `${commitmentReference.count.toLocaleString("pt-BR")} títulos; lote ${
          commitmentReference.batchCode || "não informado"
        }`
      );
      commitmentReference.categories.forEach((item) =>
        rows.push([
          "Composição histórica",
          "Categoria exclusiva",
          item.name,
          csvNumber(item.value),
          `${item.count.toLocaleString("pt-BR")} títulos; ${formatPercent(item.percentage)}`,
          "",
        ])
      );
    }
    if (commitmentClassification) {
      add(
        "Reclassificação dos compromissos",
        "Posição classificada atual",
        commitmentClassification.classifiedOpen,
        `Financeiro ${formatMoney(
          commitmentClassification.financialOpen
        )}; ajustes ${formatMoney(commitmentClassification.adjustmentsOpen)}`
      );
      add(
        "Reclassificação dos compromissos",
        "Dívida tributária e empréstimos atuais",
        commitmentClassification.debtOpen
      );
      add(
        "Reclassificação dos compromissos",
        "Investimentos atuais sem dupla contagem",
        commitmentClassification.investmentsOpen
      );
      commitmentClassification.categories.forEach((item) =>
        rows.push([
          "Composição atual",
          "Categoria exclusiva",
          item.name,
          csvNumber(item.value),
          `${item.count.toLocaleString("pt-BR")} títulos abertos; vencido ${formatMoney(
            item.overdue
          )}; próximos 30 dias ${formatMoney(item.next30)}`,
          "",
        ])
      );
      if (commitmentClassification.reviewCount > 0) {
        rows.push([
          "Revisão de classificação",
          "Confiança média",
          "Confirmar ativo dos contratos genéricos",
          csvNumber(commitmentClassification.reviewValue),
          `${commitmentClassification.reviewCount.toLocaleString("pt-BR")} títulos`,
          "Confirmar o ativo específico vinculado a cada contrato.",
        ]);
      }
    }
    if (inventoryHealth) {
      add("Estoque", "Compra física para estoque", inventoryHealth.period.purchasesForStock);
      add("Estoque", "Compra vinculada à OS", inventoryHealth.period.directPurchasesForOs);
      add("Estoque", "Baixa do estoque para OS", inventoryHealth.period.stockConsumptionByOs);
      add("Estoque", "Outras entradas", inventoryHealth.period.otherEntries);
      add("Estoque", "Outras saídas", inventoryHealth.period.otherOutputs);
      add("Estoque", "Variação líquida estimada", inventoryHealth.position.periodVariation);
      add("Estoque", "Valor estimado no início do período", inventoryHealth.position.openingValue);
      add("Estoque", "Valor estimado no fim do período", inventoryHealth.position.closingValue);
      add("Estoque", "Valor atual", inventoryHealth.position.currentValue);
      add("Estoque", "Compra classificada em EST_MAT_PRIMA", classifiedStockPurchases);
      add(
        "Qualidade do estoque",
        "Itens fiscais sem cadastro",
        inventoryHealth.quality.valueWithoutRegistration,
        `${inventoryHealth.quality.itemsWithoutRegistration.toLocaleString("pt-BR")} itens`
      );
      add(
        "Qualidade do estoque",
        "Itens cadastrados sem entrada",
        inventoryHealth.quality.valueWithoutEntry,
        `${inventoryHealth.quality.itemsWithoutEntry.toLocaleString("pt-BR")} itens`
      );
      add(
        "Qualidade do estoque",
        "Saldo sem custo cadastrado",
        0,
        `${inventoryHealth.position.itemsWithoutCost.toLocaleString("pt-BR")} itens; ${inventoryHealth.position.quantityWithoutCost.toLocaleString("pt-BR", { maximumFractionDigits: 3 })} unidades`
      );
      add(
        "Qualidade do estoque",
        "Sem movimentação há 180 dias",
        inventoryHealth.position.valueWithoutMovement180d,
        `${inventoryHealth.position.itemsWithoutMovement180d.toLocaleString("pt-BR")} itens`
      );
      inventoryHealth.pending.forEach((item) =>
        rows.push([
          "Pendências do estoque",
          item.type === "SEM_CADASTRO" ? "Cadastrar ou reclassificar" : "Registrar entrada",
          `NF ${item.nfNumber}`,
          csvNumber(item.value),
          `${item.description}${item.date ? ` · ${formatDateBR(item.date)}` : ""}`,
          item.type === "SEM_CADASTRO" ? "Cadastrar/vincular o item ou corrigir a finalidade da NF." : "Revisar e registrar a entrada física.",
        ])
      );
    }
    breakdown.forEach((item) =>
      rows.push(["Destino dos recursos", activeDimension, item.label, csvNumber(item.value), "", ""])
    );
    suppliers.forEach((item) =>
      rows.push(["Fornecedores", "Top fornecedor", item.label, csvNumber(item.value), "", ""])
    );
    filteredAlerts.forEach((item) =>
      rows.push([
        "Inconsistências",
        item.type,
        item.reference,
        csvNumber(item.value),
        `${item.severity}: ${item.title}${item.detail ? ` — ${item.detail}` : ""}${item.date ? ` · ${formatDateBR(item.date)}` : ""}`,
        item.action,
      ])
    );

    const content = rows.map((row) => row.map(csvCell).join(";")).join("\r\n");
    const blob = new Blob(["\uFEFF", content], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `saude-financeira_${filters.regime}_${filters.ano}${
      filters.periodo === "mensal" ? `-${String(filters.mes).padStart(2, "0")}` : ""
    }.csv`;
    anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }, [
    activeDimension,
    breakdown,
    commitmentClassification,
    commitmentReference,
    filteredAlerts,
    filters,
    classifiedStockPurchases,
    inventoryHealth,
    range,
    report,
    suppliers,
  ]);

  if (canFinanceiro === undefined || !urlReady) {
    return (
      <div role="status" className="rounded-xl border border-zinc-800 bg-zinc-950 px-4 py-10 text-center text-sm text-zinc-400">
        Carregando permissões...
      </div>
    );
  }
  if (canFinanceiro === false) return null;
  if (typeof te.sessionUserId === "string" && (!tenantId || !empresaId)) {
    return (
      <div role="alert" className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">
        Selecione uma empresa no topo para abrir a Saúde Financeira.
      </div>
    );
  }

  const competencia = report?.competencia;
  const caixa = report?.caixa;
  const compromissos = report?.compromissos;
  const qualidade = report?.qualidade;
  const headline = filters.regime === "competencia" ? competencia?.resultado ?? 0 : caixa?.saldo ?? 0;
  const widePosition = (caixa?.saldo ?? 0) + (compromissos?.arAberto ?? 0) - (compromissos?.apAberto ?? 0);
  const coverageUnavailable = compromissos?.cobertura30 == null;
  const coverageRatio = compromissos?.cobertura30 ?? ((compromissos?.apVencer30 ?? 0) <= 0 ? 1 : 0);
  const commitmentsReferenceRaw = text(
    first(report?.meta ?? {}, ["compromissosReferencia", "compromissos_referencia"])
  );
  const commitmentsReference = commitmentsReferenceRaw ? formatDateBR(commitmentsReferenceRaw) : "posição atual";
  const referenceAdjustments =
    commitmentReference?.categories.find((item) => item.code === "AJUSTE")
      ?.value ?? 0;
  const referenceFinancial =
    (commitmentReference?.referenceValue ?? 0) - referenceAdjustments;
  const currentFinancialDifference =
    (commitmentClassification?.financialOpen ?? 0) - referenceFinancial;
  const currentTotalDifference =
    (commitmentClassification?.classifiedOpen ?? 0) -
    (commitmentReference?.referenceValue ?? 0);

  return (
    <main className="space-y-5" aria-busy={loading}>
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <div className="text-xs font-medium uppercase tracking-[0.18em] text-sky-400">Relatório executivo</div>
          <h1 className="mt-1 text-2xl font-semibold text-zinc-100">Saúde Financeira</h1>
          <p className="mt-1 max-w-3xl text-sm text-zinc-400">
            Resultado, caixa, compromissos e qualidade dos lançamentos em uma leitura gerencial.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link
            href="/financeiro/contas-pagar/lancamentos"
            className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-900"
          >
            Abrir Contas a Pagar
          </Link>
          <button
            type="button"
            onClick={exportCsv}
            disabled={!report || loading}
            className="rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-800 disabled:opacity-50"
          >
            Exportar CSV
          </button>
        </div>
      </header>

      <section aria-label="Filtros do relatório" className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-[auto_1fr_auto] lg:items-end">
          <div>
            <div className="mb-2 text-xs font-medium uppercase tracking-wide text-zinc-500">Período</div>
            <div className="inline-flex rounded-lg border border-zinc-800 bg-black p-1">
              {(["mensal", "anual"] as Periodo[]).map((item) => (
                <button
                  key={item}
                  type="button"
                  aria-pressed={filters.periodo === item}
                  onClick={() => setFilter({ periodo: item })}
                  className={`rounded-md px-3 py-1.5 text-sm ${
                    filters.periodo === item ? "bg-zinc-800 text-zinc-100" : "text-zinc-400 hover:text-zinc-200"
                  }`}
                >
                  {item === "mensal" ? "Mensal" : "Anual"}
                </button>
              ))}
            </div>
          </div>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <label>
              <span className="text-xs text-zinc-400">Ano</span>
              <select
                value={filters.ano}
                onChange={(event) => setFilter({ ano: Number(event.target.value) })}
                className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-900 px-3 py-2 text-sm"
              >
                {Array.from({ length: 12 }, (_, index) => new Date().getFullYear() + 1 - index).map((year) => (
                  <option key={year} value={year}>
                    {year}
                  </option>
                ))}
              </select>
            </label>
            <label>
              <span className="text-xs text-zinc-400">Mês</span>
              <select
                value={filters.mes}
                disabled={filters.periodo === "anual"}
                onChange={(event) => setFilter({ mes: Number(event.target.value) })}
                className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-900 px-3 py-2 text-sm disabled:opacity-50"
              >
                {MONTHS.map((month, index) => (
                  <option key={month} value={index + 1}>
                    {month}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <div>
            <div className="mb-2 text-xs font-medium uppercase tracking-wide text-zinc-500">Regime de análise</div>
            <div className="inline-flex rounded-lg border border-zinc-800 bg-black p-1">
              {(["competencia", "caixa"] as Regime[]).map((item) => (
                <button
                  key={item}
                  type="button"
                  aria-pressed={filters.regime === item}
                  onClick={() => setFilter({ regime: item })}
                  className={`rounded-md px-3 py-1.5 text-sm ${
                    filters.regime === item
                      ? "bg-sky-500/20 text-sky-200"
                      : "text-zinc-400 hover:text-zinc-200"
                  }`}
                >
                  {item === "competencia" ? "Competência" : "Caixa"}
                </button>
              ))}
            </div>
          </div>
        </div>
        <div className="mt-3 text-xs text-zinc-500">
          {range.label} · {range.start.split("-").reverse().join("/")} a {range.end.split("-").reverse().join("/")}
        </div>
      </section>

      {error ? (
        <section role="alert" className="rounded-xl border border-rose-500/30 bg-rose-500/10 p-4">
          <div className="font-medium text-rose-100">Falha ao gerar o diagnóstico</div>
          <div className="mt-1 text-sm text-rose-200">{error}</div>
          <button
            type="button"
            onClick={() => setRetryKey((key) => key + 1)}
            className="mt-3 rounded-md border border-rose-400/30 bg-rose-950/30 px-3 py-2 text-sm text-rose-100 hover:bg-rose-950/50"
          >
            Tentar novamente
          </button>
        </section>
      ) : null}

      {loading ? (
        <section role="status" aria-live="polite" className="space-y-3">
          <div className="sr-only">Calculando a saúde financeira do período.</div>
          <div className="h-40 animate-pulse rounded-xl border border-zinc-800 bg-zinc-950" />
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
            {Array.from({ length: 4 }, (_, index) => (
              <div key={index} className="h-28 animate-pulse rounded-xl border border-zinc-800 bg-zinc-950" />
            ))}
          </div>
        </section>
      ) : null}

      {!loading && !error && !report ? (
        <section className="rounded-xl border border-zinc-800 bg-zinc-950 px-4 py-12 text-center">
          <div className="text-base font-medium text-zinc-200">Sem dados para este período</div>
          <p className="mt-1 text-sm text-zinc-500">Altere o mês, o ano ou confirme os lançamentos da empresa.</p>
          <button
            type="button"
            onClick={() => setRetryKey((key) => key + 1)}
            className="mt-4 rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-800"
          >
            Recarregar
          </button>
        </section>
      ) : null}

      {!loading && report && health ? (
        <>
          <section className={`rounded-2xl border p-5 ${health.tone}`}>
            <div className="grid gap-6 lg:grid-cols-[auto_1fr_1.2fr] lg:items-center">
              <div
                className="grid h-28 w-28 shrink-0 place-items-center rounded-full p-2"
                style={{
                  background: `conic-gradient(${health.color} ${health.score * 3.6}deg, rgba(63,63,70,.55) 0deg)`,
                }}
                role="img"
                aria-label={`Índice gerencial de saúde: ${health.score} de 100, status ${health.status}`}
              >
                <div className="grid h-full w-full place-items-center rounded-full bg-zinc-950 text-center">
                  <div>
                    <div className="text-3xl font-semibold tabular-nums text-zinc-100">{health.score}</div>
                    <div className="text-[10px] uppercase tracking-wide text-zinc-500">de 100</div>
                  </div>
                </div>
              </div>
              <div>
                <div className="text-xs font-medium uppercase tracking-wide opacity-80">Diagnóstico gerencial</div>
                <div className="mt-1 text-2xl font-semibold">{health.status}</div>
                <p className="mt-2 text-sm leading-6 text-zinc-300">{health.diagnosis}</p>
                <div className="mt-3 text-xs text-zinc-500">
                  {filters.regime === "competencia" ? "Resultado por competência" : "Geração de caixa"}:{" "}
                  <span className={`font-medium tabular-nums ${headline >= 0 ? "text-emerald-300" : "text-rose-300"}`}>
                    {formatMoney(headline)}
                  </span>
                </div>
              </div>
              <div>
                <div className="mb-2 text-xs font-medium uppercase tracking-wide text-zinc-500">
                  Composição transparente do índice
                </div>
                <div className="grid gap-2 sm:grid-cols-2">
                  {health.contributions.map(([label, points, maximum]) => (
                    <div key={label} className="rounded-lg border border-zinc-800/80 bg-zinc-950/70 px-3 py-2">
                      <div className="text-xs text-zinc-400">{label}</div>
                      <div className="mt-1 text-sm font-medium tabular-nums text-zinc-100">
                        {points.toLocaleString("pt-BR", { maximumFractionDigits: 1 })} / {maximum}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </section>

          <section aria-label="Indicadores principais" className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
            {filters.regime === "competencia" ? (
              <>
                <MetricCard
                  title={competencia!.resultado >= 0 ? "Lucro gerencial" : "Prejuízo gerencial"}
                  value={formatMoney(competencia!.resultado)}
                  subtitle={`Margem ${formatPercent(competencia!.margem)}`}
                  current={competencia!.resultado}
                  previous={previousValue(competencia!.anterior, "resultado")}
                  valueTone={competencia!.resultado >= 0 ? "text-emerald-300" : "text-rose-300"}
                />
                <MetricCard
                  title="Receita"
                  value={formatMoney(competencia!.receita)}
                  subtitle="Reconhecida no período"
                  current={competencia!.receita}
                  previous={previousValue(competencia!.anterior, "receita")}
                />
                <MetricCard
                  title="Despesas"
                  value={formatMoney(competencia!.despesa)}
                  subtitle="Operacionais classificadas no período"
                  current={competencia!.despesa}
                  previous={previousValue(competencia!.anterior, "despesa")}
                  higherIsBetter={false}
                />
              </>
            ) : (
              <>
                <MetricCard
                  title="Geração de caixa"
                  value={formatMoney(caixa!.saldo)}
                  subtitle="Recebimentos menos pagamentos"
                  current={caixa!.saldo}
                  previous={previousValue(caixa!.anterior, "saldo")}
                  valueTone={caixa!.saldo >= 0 ? "text-emerald-300" : "text-rose-300"}
                />
                <MetricCard
                  title="Recebimentos"
                  value={formatMoney(caixa!.recebimentos)}
                  subtitle="Entradas efetivas"
                  current={caixa!.recebimentos}
                  previous={previousValue(caixa!.anterior, "recebimentos")}
                />
                <MetricCard
                  title="Pagamentos"
                  value={formatMoney(caixa!.pagamentos)}
                  subtitle="Saídas efetivas"
                  current={caixa!.pagamentos}
                  previous={previousValue(caixa!.anterior, "pagamentos")}
                  higherIsBetter={false}
                />
              </>
            )}
            <MetricCard
              title="Posição ampla"
              value={formatMoney(widePosition)}
              subtitle="Caixa do período + AR aberto − AP aberto"
              valueTone={widePosition >= 0 ? "text-sky-300" : "text-rose-300"}
            />
            <MetricCard
              title={filters.regime === "competencia" ? "Dívida identificada" : "Dívida paga"}
              value={formatMoney(
                filters.regime === "competencia" ? competencia!.dividaIdentificada : caixa!.dividaPaga
              )}
              subtitle={`Tributos e empréstimos abertos: ${formatMoney(
                commitmentClassification?.debtOpen ?? compromissos!.dividaAberta
              )}`}
              valueTone="text-amber-200"
            />
            <MetricCard
              title={filters.regime === "competencia" ? "Investimentos" : "Investimentos pagos"}
              value={formatMoney(filters.regime === "competencia" ? competencia!.investimentos : caixa!.investimentosPagos)}
              subtitle={`Investimentos abertos, sem dupla contagem: ${formatMoney(
                commitmentClassification?.investmentsOpen ??
                  compromissos!.investimentosAbertos
              )}`}
              valueTone="text-violet-200"
            />
          </section>

          <div className="rounded-lg border border-emerald-500/20 bg-emerald-500/5 px-4 py-3 text-xs leading-5 text-emerald-100/80">
            A composição dos compromissos agora é exclusiva: cada título pertence a
            uma única categoria. Dívida, investimentos e ajustes reconciliam com o
            total sem sobreposição.
          </div>

          {commitmentClassification &&
          commitmentReference &&
          commitmentReference.referenceValue > 0 ? (
            <section
              aria-labelledby="composicao-compromissos-title"
              className="rounded-xl border border-zinc-800 bg-zinc-950 p-4"
            >
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div>
                  <div className="text-xs font-medium uppercase tracking-[0.16em] text-sky-400">
                    Reconciliação auditada
                  </div>
                  <h2
                    id="composicao-compromissos-title"
                    className="mt-1 text-base font-semibold text-zinc-100"
                  >
                    Composição dos R$ 2,129 milhões
                  </h2>
                  <p className="mt-1 max-w-3xl text-xs leading-5 text-zinc-500">
                    A base histórica foi congelada título a título. A posição atual
                    usa o saldo vivo e, por isso, reflete pagamentos e novos
                    contratos posteriores. Esta posição não muda com o filtro de
                    mês e ano.
                  </p>
                </div>
                <div className="rounded-lg border border-emerald-500/25 bg-emerald-500/10 px-3 py-2 text-right">
                  <div className="text-xs text-emerald-200/75">
                    {commitmentReference.count.toLocaleString("pt-BR")} títulos na
                    base
                  </div>
                  <div className="mt-0.5 text-sm font-semibold tabular-nums text-emerald-200">
                    Conciliação {formatMoney(commitmentReference.reconciliationDifference)}
                  </div>
                </div>
              </div>

              <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
                <div className="rounded-lg border border-sky-500/25 bg-sky-500/5 p-3">
                  <div className="text-xs text-zinc-500">Base histórica reclassificada</div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-sky-200">
                    {formatMoney(commitmentReference.referenceValue)}
                  </div>
                  <div className="mt-1 text-xs text-zinc-500">
                    Fotografia preservada para auditoria
                  </div>
                </div>
                <div className="rounded-lg border border-amber-500/25 bg-amber-500/5 p-3">
                  <div className="text-xs text-zinc-500">
                    Dívida tributária + empréstimos
                  </div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-amber-200">
                    {formatMoney(commitmentClassification.debtOpen)}
                  </div>
                  <div className="mt-1 text-xs text-zinc-500">
                    Tributária + empréstimos
                  </div>
                </div>
                <div className="rounded-lg border border-violet-500/25 bg-violet-500/5 p-3">
                  <div className="text-xs text-zinc-500">Investimentos atuais</div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-violet-200">
                    {formatMoney(commitmentClassification.investmentsOpen)}
                  </div>
                  <div className="mt-1 text-xs text-zinc-500">
                    Máquinas + veículos
                  </div>
                </div>
                <div className="rounded-lg border border-zinc-700 bg-zinc-900/40 p-3">
                  <div className="text-xs text-zinc-500">Ajustes de implantação</div>
                  <div className="mt-1 text-lg font-semibold tabular-nums text-zinc-200">
                    {formatMoney(commitmentClassification.adjustmentsOpen)}
                  </div>
                  <div className="mt-1 text-xs text-zinc-500">
                    Fora da dívida e dos investimentos
                  </div>
                </div>
              </div>

              <div className="mt-4 overflow-hidden rounded-full bg-zinc-900">
                <div className="flex h-2.5 w-full">
                  {commitmentReference.categories.map((item) => (
                    <div
                      key={item.code}
                      className={commitmentTone(item.code).bar}
                      style={{ width: `${Math.max(0, item.percentage)}%` }}
                      title={`${item.name}: ${formatMoney(item.value)} (${formatPercent(
                        item.percentage
                      )})`}
                    />
                  ))}
                </div>
              </div>

              <div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-5">
                {commitmentReference.categories.map((referenceItem) => {
                  const currentItem = commitmentClassification.categories.find(
                    (item) => item.code === referenceItem.code
                  );
                  const currentValue = currentItem?.value ?? 0;
                  const difference = currentValue - referenceItem.value;
                  const tone = commitmentTone(referenceItem.code);
                  return (
                    <article
                      key={referenceItem.code}
                      className={`rounded-lg border bg-black/25 p-3 ${tone.border}`}
                    >
                      <div className="min-h-10 text-xs font-medium leading-5 text-zinc-300">
                        {referenceItem.name}
                      </div>
                      <dl className="mt-2 space-y-2 text-xs">
                        <div>
                          <dt className="text-zinc-600">Base histórica</dt>
                          <dd className="mt-0.5 text-right font-medium tabular-nums text-zinc-300">
                            {formatMoney(referenceItem.value)}
                          </dd>
                        </div>
                        <div>
                          <dt className="text-zinc-500">Posição atual</dt>
                          <dd
                            className={`mt-0.5 text-right text-sm font-semibold tabular-nums ${tone.value}`}
                          >
                            {formatMoney(currentValue)}
                          </dd>
                        </div>
                        <div className="flex items-center justify-between gap-2 border-t border-zinc-900 pt-2">
                          <dt className="text-zinc-600">Variação</dt>
                          <dd
                            className={`text-right font-medium tabular-nums ${
                              difference > 0
                                ? "text-amber-200"
                                : difference < 0
                                  ? "text-emerald-300"
                                  : "text-zinc-500"
                            }`}
                          >
                            {formatSignedMoney(difference)}
                          </dd>
                        </div>
                      </dl>
                      <div className="mt-3 text-[11px] leading-4 text-zinc-600">
                        {referenceItem.count.toLocaleString("pt-BR")} na base ·{" "}
                        {(currentItem?.count ?? 0).toLocaleString("pt-BR")} em
                        aberto
                      </div>
                      {currentItem && (currentItem.overdue > 0 || currentItem.next30 > 0) ? (
                        <div className="mt-1 text-[11px] leading-4 text-zinc-600">
                          Vencido {formatMoney(currentItem.overdue)} · 30d{" "}
                          {formatMoney(currentItem.next30)}
                        </div>
                      ) : null}
                    </article>
                  );
                })}
              </div>

              <div className="mt-4 grid grid-cols-1 gap-3 lg:grid-cols-3">
                <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                  <div className="text-xs text-zinc-500">
                    Posição financeira atual, sem ajustes
                  </div>
                  <div className="mt-1 flex flex-wrap items-baseline justify-between gap-2">
                    <span className="font-semibold tabular-nums text-zinc-100">
                      {formatMoney(commitmentClassification.financialOpen)}
                    </span>
                    <span
                      className={`text-xs tabular-nums ${
                        currentFinancialDifference > 0
                          ? "text-amber-200"
                          : "text-emerald-300"
                      }`}
                    >
                      {formatSignedMoney(currentFinancialDifference)} vs. base
                      comparável
                    </span>
                  </div>
                </div>
                <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                  <div className="text-xs text-zinc-500">
                    Total classificado atual
                  </div>
                  <div className="mt-1 flex flex-wrap items-baseline justify-between gap-2">
                    <span className="font-semibold tabular-nums text-zinc-100">
                      {formatMoney(commitmentClassification.classifiedOpen)}
                    </span>
                    <span className="text-xs tabular-nums text-amber-200">
                      {formatSignedMoney(currentTotalDifference)} vs. fotografia
                    </span>
                  </div>
                </div>
                <div className="rounded-lg border border-emerald-500/20 bg-emerald-500/5 px-3 py-2">
                  <div className="text-xs text-emerald-200/70">
                    Teste de integridade
                  </div>
                  <div className="mt-1 font-semibold tabular-nums text-emerald-200">
                    Dívida + investimentos + ajustes = total
                  </div>
                </div>
              </div>

              {commitmentClassification.reviewCount > 0 ? (
                <div className="mt-4 rounded-lg border border-amber-500/25 bg-amber-500/5 px-3 py-2 text-xs leading-5 text-amber-100/85">
                  <strong className="font-medium text-amber-200">
                    Confirmação pendente:
                  </strong>{" "}
                  {commitmentClassification.reviewCount.toLocaleString("pt-BR")}{" "}
                  contratos de leasing com descrição genérica, somando{" "}
                  {formatMoney(commitmentClassification.reviewValue)}, foram
                  classificados provisoriamente em máquinas. Confirme o ativo
                  específico de cada contrato.
                </div>
              ) : null}

              {commitmentClassification.possibleUnclassifiedCount > 0 ? (
                <div className="mt-3 rounded-lg border border-rose-500/25 bg-rose-500/5 px-3 py-2 text-xs leading-5 text-rose-100/85">
                  Foram encontrados{" "}
                  {commitmentClassification.possibleUnclassifiedCount.toLocaleString(
                    "pt-BR"
                  )}{" "}
                  novos títulos com indício de financiamento ainda não
                  classificados, totalizando{" "}
                  {formatMoney(
                    commitmentClassification.possibleUnclassifiedValue
                  )}.
                </div>
              ) : null}
            </section>
          ) : null}

          <section className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h2 className="text-base font-semibold text-zinc-100">Tendência do período</h2>
                <p className="mt-1 text-xs text-zinc-500">Entradas e saídas; valores calculados no regime selecionado.</p>
              </div>
              <div className="text-xs text-zinc-500">{series.length} pontos</div>
            </div>
            <div className="mt-4">
              <TrendChart rows={series} regime={filters.regime} />
            </div>
          </section>

          <section className="grid grid-cols-1 gap-4 xl:grid-cols-3">
            <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 xl:col-span-2">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h2 className="text-base font-semibold text-zinc-100">Para onde foi o dinheiro</h2>
                  <p className="mt-1 text-xs text-zinc-500">
                    Ranking financeiro. EST_MAT_PRIMA representa compras classificadas; o estoque líquido é analisado abaixo.
                  </p>
                </div>
                {filters.regime === "competencia" ? (
                  <div className="flex flex-wrap gap-1">
                    {(["plano", "motivo", "centro"] as Dimensao[]).map((item) => (
                      <button
                        key={item}
                        type="button"
                        aria-pressed={activeDimension === item}
                        onClick={() => setDimension(item)}
                        className={`rounded-md px-2.5 py-1.5 text-xs ${
                          activeDimension === item
                            ? "bg-zinc-800 text-zinc-100"
                            : "text-zinc-400 hover:bg-zinc-900"
                        }`}
                      >
                        {item === "plano" ? "Plano de contas" : item === "centro" ? "Centro de custo" : "Motivo"}
                      </button>
                    ))}
                  </div>
                ) : (
                  <div className="rounded-md border border-zinc-800 px-2.5 py-1.5 text-xs text-zinc-400">Por motivo</div>
                )}
              </div>
              <div className="mt-5">
                <RankBars rows={breakdown} empty="Sem distribuição para esta dimensão." />
              </div>
            </div>
            <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
              <h2 className="text-base font-semibold text-zinc-100">Custos financeiros</h2>
              <p className="mt-1 text-xs text-zinc-500">Efeitos efetivamente observados no caixa.</p>
              <dl className="mt-5 space-y-3 text-sm">
                {[
                  ["Juros", caixa!.juros],
                  ["Multas", caixa!.multas],
                  ["Descontos", caixa!.descontos],
                  ["Não conciliado", caixa!.naoConciliado, caixa!.naoConciliado > 0 ? "text-amber-200" : "text-zinc-100"],
                  ["Movimentos sem direção AP/AR", caixa!.movimentosSemDirecao, caixa!.movimentosSemDirecao > 0 ? "text-rose-300" : "text-zinc-100"],
                  ["Sem classificação", competencia!.naoClassificado, competencia!.naoClassificado > 0 ? "text-amber-200" : "text-zinc-100"],
                ].map(([label, value, valueTone]) => (
                  <div key={String(label)} className="flex items-center justify-between gap-3 border-b border-zinc-900 pb-3">
                    <dt className="text-zinc-400">{label}</dt>
                    <dd className={`text-right font-medium tabular-nums ${valueTone}`}>{formatMoney(Number(value))}</dd>
                  </div>
                ))}
              </dl>
            </div>
          </section>

          {inventoryHealth ? (
            <section
              aria-labelledby="estoque-saude-title"
              className="overflow-hidden rounded-xl border border-sky-500/20 bg-zinc-950"
            >
              <div className="flex flex-wrap items-start justify-between gap-3 border-b border-zinc-800 px-4 py-4">
                <div>
                  <div className="text-xs font-medium uppercase tracking-[0.16em] text-sky-400">Análise operacional</div>
                  <h2 id="estoque-saude-title" className="mt-1 text-base font-semibold text-zinc-100">
                    Estoque e materiais das OS
                  </h2>
                  <p className="mt-1 max-w-3xl text-xs leading-5 text-zinc-500">
                    Separa compra sem OS, compra vinculada a OS e material efetivamente retirado do estoque.
                  </p>
                </div>
                <div className="rounded-full border border-zinc-800 bg-black/30 px-3 py-1.5 text-xs text-zinc-400">
                  Fluxo: {range.label}
                </div>
              </div>

              <div className="space-y-4 p-4">
                <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
                  <article className="rounded-lg border border-sky-500/25 bg-sky-500/5 p-3">
                    <div className="text-xs text-zinc-500">Compra para estoque</div>
                    <div className="mt-1 text-lg font-semibold tabular-nums text-sky-200">
                      {formatMoney(inventoryHealth.period.purchasesForStock)}
                    </div>
                    <div className="mt-1 text-[11px] leading-4 text-zinc-600">NF sem destino direto para OS</div>
                  </article>
                  <article className="rounded-lg border border-violet-500/25 bg-violet-500/5 p-3">
                    <div className="text-xs text-zinc-500">Compra vinculada à OS</div>
                    <div className="mt-1 text-lg font-semibold tabular-nums text-violet-200">
                      {formatMoney(inventoryHealth.period.directPurchasesForOs)}
                    </div>
                    <div className="mt-1 text-[11px] leading-4 text-zinc-600">Destino informado na entrada da NF</div>
                  </article>
                  <article className="rounded-lg border border-rose-500/25 bg-rose-500/5 p-3">
                    <div className="text-xs text-zinc-500">Estoque consumido por OS</div>
                    <div className="mt-1 text-lg font-semibold tabular-nums text-rose-200">
                      {formatMoney(inventoryHealth.period.stockConsumptionByOs)}
                    </div>
                    <div className="mt-1 text-[11px] leading-4 text-zinc-600">Baixas do almoxarifado vinculadas à OS</div>
                  </article>
                  <article
                    className={`rounded-lg border p-3 ${
                      inventoryHealth.position.periodVariation >= 0
                        ? "border-emerald-500/25 bg-emerald-500/5"
                        : "border-amber-500/25 bg-amber-500/5"
                    }`}
                  >
                    <div className="text-xs text-zinc-500">Variação líquida</div>
                    <div
                      className={`mt-1 text-lg font-semibold tabular-nums ${
                        inventoryHealth.position.periodVariation >= 0 ? "text-emerald-200" : "text-amber-200"
                      }`}
                    >
                      {formatSignedMoney(inventoryHealth.position.periodVariation)}
                    </div>
                    <div className="mt-1 text-[11px] leading-4 text-zinc-600">
                      {inventoryVariationOverPurchases === null
                        ? "Sem compra para comparar"
                        : `${formatPercent(Math.abs(inventoryVariationOverPurchases))} do total comprado`}
                    </div>
                  </article>
                  <article className="rounded-lg border border-emerald-500/25 bg-emerald-500/5 p-3">
                    <div className="text-xs text-zinc-500">Valor atual do estoque</div>
                    <div className="mt-1 text-lg font-semibold tabular-nums text-emerald-200">
                      {formatMoney(inventoryHealth.position.currentValue)}
                    </div>
                    <div className="mt-1 text-[11px] leading-4 text-zinc-600">
                      {inventoryHealth.position.itemsWithBalance.toLocaleString("pt-BR")} itens com saldo
                    </div>
                  </article>
                </div>

                <div className="grid gap-3 xl:grid-cols-[1.15fr_0.85fr]">
                  <article className="rounded-lg border border-zinc-800 bg-black/25 p-4">
                    <h3 className="text-sm font-semibold text-zinc-100">Leitura crítica do período</h3>
                    <p className="mt-2 text-sm leading-6 text-zinc-300">
                      {inventoryHealth.position.periodVariation >= 0 ? (
                        <>
                          O estoque aumentou <strong className="font-semibold text-emerald-200">{formatMoney(inventoryHealth.position.periodVariation)}</strong>.
                        </>
                      ) : (
                        <>
                          O estoque diminuiu <strong className="font-semibold text-amber-200">{formatMoney(Math.abs(inventoryHealth.position.periodVariation))}</strong>; as saídas superaram as entradas valorizadas.
                        </>
                      )}{" "}
                      Compras de <strong className="font-semibold text-violet-200">{formatMoney(inventoryHealth.period.directPurchasesForOs)}</strong> entraram vinculadas a OS. A variação líquida considera o que efetivamente permaneceu após todas as entradas e saídas físicas.
                    </p>

                    <dl className="mt-4 grid gap-2 text-xs sm:grid-cols-3">
                      <div className="rounded-md border border-zinc-800 bg-zinc-950/80 px-3 py-2">
                        <dt className="text-zinc-500">EST_MAT_PRIMA financeiro</dt>
                        <dd className="mt-1 text-right font-semibold tabular-nums text-zinc-200">
                          {formatMoney(classifiedStockPurchases)}
                        </dd>
                      </div>
                      <div className="rounded-md border border-zinc-800 bg-zinc-950/80 px-3 py-2">
                        <dt className="text-zinc-500">Compra física para estoque</dt>
                        <dd className="mt-1 text-right font-semibold tabular-nums text-sky-200">
                          {formatMoney(inventoryHealth.period.purchasesForStock)}
                        </dd>
                      </div>
                      <div className="rounded-md border border-zinc-800 bg-zinc-950/80 px-3 py-2">
                        <dt className="text-zinc-500">Diferença a conciliar</dt>
                        <dd
                          className={`mt-1 text-right font-semibold tabular-nums ${
                            Math.abs(classifiedStockPurchases - inventoryHealth.period.purchasesForStock) < 0.01
                              ? "text-emerald-300"
                              : "text-amber-200"
                          }`}
                        >
                          {formatSignedMoney(classifiedStockPurchases - inventoryHealth.period.purchasesForStock)}
                        </dd>
                      </div>
                    </dl>
                    <div className="mt-3 text-[11px] leading-5 text-zinc-600">
                      O valor financeiro segue competência e classificação do AP; o valor físico segue as movimentações de itens. Diferenças podem indicar data, frete, imposto ou classificação a revisar.
                    </div>
                  </article>

                  <article className="rounded-lg border border-zinc-800 bg-black/25 p-4">
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <h3 className="text-sm font-semibold text-zinc-100">Qualidade e risco do estoque</h3>
                        <p className="mt-1 text-xs text-zinc-500">Pontos que reduzem a confiança da avaliação.</p>
                      </div>
                      <Link href="/estoque/importar" className="shrink-0 text-xs text-sky-300 hover:text-sky-200 hover:underline">
                        Revisar entradas
                      </Link>
                    </div>
                    <dl className="mt-3 grid grid-cols-2 gap-2 text-xs">
                      {[
                        ["Sem cadastro/vínculo", inventoryHealth.quality.itemsWithoutRegistration, formatMoney(inventoryHealth.quality.valueWithoutRegistration), "text-rose-200"],
                        ["Sem entrada física", inventoryHealth.quality.itemsWithoutEntry, formatMoney(inventoryHealth.quality.valueWithoutEntry), "text-amber-200"],
                        ["Saldo sem custo", inventoryHealth.position.itemsWithoutCost, `${inventoryHealth.position.quantityWithoutCost.toLocaleString("pt-BR", { maximumFractionDigits: 3 })} un.`, "text-amber-200"],
                        ["Parado há 180 dias", inventoryHealth.position.itemsWithoutMovement180d, formatMoney(inventoryHealth.position.valueWithoutMovement180d), "text-zinc-200"],
                        ["Acima do ideal", inventoryHealth.position.itemsAboveIdeal, formatMoney(inventoryHealth.position.valueAboveIdeal), "text-zinc-200"],
                        ["Saldo negativo", inventoryHealth.position.negativeItems, `${inventoryHealth.position.negativeQuantity.toLocaleString("pt-BR", { maximumFractionDigits: 3 })} un.`, inventoryHealth.position.negativeItems > 0 ? "text-rose-200" : "text-emerald-300"],
                      ].map(([label, count, detail, tone]) => (
                        <div key={String(label)} className="rounded-md border border-zinc-800 bg-zinc-950/80 px-3 py-2">
                          <dt className="text-zinc-500">{label}</dt>
                          <dd className={`mt-1 font-semibold tabular-nums ${tone}`}>
                            {Number(count).toLocaleString("pt-BR")} itens
                          </dd>
                          <div className="mt-0.5 text-[11px] tabular-nums text-zinc-600">{detail}</div>
                        </div>
                      ))}
                    </dl>
                  </article>
                </div>

                {inventoryHealth.pending.length ? (
                  <div className="rounded-lg border border-amber-500/20 bg-amber-500/5 p-3">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <div>
                        <h3 className="text-sm font-semibold text-amber-100">Itens que exigem ação</h3>
                        <p className="mt-0.5 text-xs text-amber-100/55">Amostra das pendências fiscais do período selecionado.</p>
                      </div>
                      <Link href="/itens" className="text-xs text-amber-200 hover:text-amber-100 hover:underline">Abrir cadastro de itens</Link>
                    </div>
                    <div className="mt-3 grid gap-2 md:grid-cols-2 xl:grid-cols-4">
                      {inventoryHealth.pending.map((item) => (
                        <div key={`${item.type}-${item.nfId}-${item.description}`} className="rounded-md border border-amber-500/15 bg-black/20 px-3 py-2">
                          <div className="flex items-center justify-between gap-2 text-[11px]">
                            <span className={item.type === "SEM_CADASTRO" ? "text-rose-200" : "text-amber-200"}>
                              {item.type === "SEM_CADASTRO" ? "Cadastrar / reclassificar" : "Registrar entrada"}
                            </span>
                            <span className="text-zinc-600">NF {item.nfNumber}</span>
                          </div>
                          <div className="mt-1 truncate text-xs font-medium text-zinc-200" title={item.description}>{item.description}</div>
                          <div className="mt-1 flex items-center justify-between gap-2 text-[11px] text-zinc-600">
                            <span>{item.date ? formatDateBR(item.date) : "Sem data"}</span>
                            <span className="tabular-nums text-zinc-400">{formatMoney(item.value)}</span>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                ) : null}

                <div className="text-[11px] leading-5 text-zinc-600">
                  Valores históricos de saída são estimados pelo custo médio atual quando a movimentação não possui custo gravado. Posição estimada no início e no fim do período; posição atual em {inventoryHealth.meta.positionDate ? formatDateBR(inventoryHealth.meta.positionDate) : "data não informada"}.
                </div>
              </div>
            </section>
          ) : null}

          <section className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h2 className="text-base font-semibold text-zinc-100">Posição de compromissos</h2>
                <p className="mt-1 text-xs text-zinc-500">
                  Pressão de curto prazo e capacidade de cobertura · Referência: {commitmentsReference}.
                </p>
              </div>
              <div
                className={`rounded-lg border px-3 py-2 text-sm font-medium tabular-nums ${
                  coverageUnavailable || coverageRatio >= 1
                    ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-200"
                    : "border-rose-500/30 bg-rose-500/10 text-rose-200"
                }`}
              >
                {coverageUnavailable
                  ? "Sem AP a vencer"
                  : `Cobertura 30d: ${coverageRatio.toLocaleString("pt-BR", {
                      minimumFractionDigits: 2,
                      maximumFractionDigits: 2,
                    })}x`}
              </div>
            </div>
            {compromissos!.legadoExcluido.tituloQtd > 0 ? (
              <div className="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-sky-500/25 bg-sky-500/10 px-3 py-2 text-sm text-sky-100">
                <div>
                  <span className="font-medium">Legado de implantação excluído dos indicadores</span>
                  <span className="ml-2 text-sky-200/75">
                    {compromissos!.legadoExcluido.tituloQtd.toLocaleString("pt-BR")} títulos ·{" "}
                    {compromissos!.legadoExcluido.parcelaQtd.toLocaleString("pt-BR")} parcelas
                  </span>
                </div>
                <div className="text-right font-semibold tabular-nums">
                  {formatMoney(compromissos!.legadoExcluido.valorAberto)}
                  {compromissos!.legadoExcluido.corte ? (
                    <span className="ml-2 font-normal text-sky-200/70">
                      corte em {formatDateBR(compromissos!.legadoExcluido.corte)}
                    </span>
                  ) : null}
                </div>
              </div>
            ) : null}
            <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-3">
              <div className="rounded-lg border border-zinc-800 bg-black/30 p-3">
                <div className="text-xs text-zinc-500">Títulos no filtro</div>
                <div className="mt-1 text-sm font-semibold tabular-nums text-zinc-100">
                  {compromissos!.apPeriodoQtd.toLocaleString("pt-BR")} títulos
                </div>
              </div>
              <div className="rounded-lg border border-zinc-800 bg-black/30 p-3">
                <div className="text-xs text-zinc-500">AP total no filtro</div>
                <div className="mt-1 text-sm font-semibold tabular-nums text-zinc-100">
                  {formatMoney(compromissos!.apPeriodoTotal)}
                </div>
              </div>
              <div className="rounded-lg border border-zinc-800 bg-black/30 p-3">
                <div className="text-xs text-zinc-500">AP em aberto no filtro</div>
                <div className="mt-1 text-sm font-semibold tabular-nums text-amber-200">
                  {formatMoney(compromissos!.apPeriodoAberto)}
                </div>
              </div>
            </div>
            <div className="mt-3 grid grid-cols-2 gap-3 lg:grid-cols-6">
              {[
                ["AP aberto", compromissos!.apAberto, "text-zinc-100"],
                ["AP vencido", compromissos!.apVencido, "text-rose-300"],
                ["AP próx. 30d", compromissos!.apVencer30, "text-amber-200"],
                ["AR aberto", compromissos!.arAberto, "text-zinc-100"],
                ["AR vencido", compromissos!.arVencido, "text-amber-200"],
                ["AR próx. 30d", compromissos!.arVencer30, "text-emerald-300"],
              ].map(([label, value, tone]) => (
                <div key={String(label)} className="rounded-lg border border-zinc-800 bg-black/30 p-3">
                  <div className="text-xs text-zinc-500">{label}</div>
                  <div className={`mt-1 text-sm font-semibold tabular-nums ${tone}`}>{formatMoney(Number(value))}</div>
                </div>
              ))}
            </div>
          </section>

          <section className="grid grid-cols-1 gap-4 xl:grid-cols-2">
            <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <h2 className="text-base font-semibold text-zinc-100">Aging de contas a pagar</h2>
                  <p className="mt-1 text-xs text-zinc-500">Concentração dos valores por faixa de vencimento.</p>
                </div>
                <Link href="/financeiro/relatorios/ap-aging" className="text-xs text-sky-300 hover:text-sky-200">
                  Ver detalhes
                </Link>
              </div>
              <div className="mt-5">
                <RankBars rows={compromissos!.agingAp} empty="Sem aging de AP no período." />
              </div>
            </div>
            <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
              <h2 className="text-base font-semibold text-zinc-100">Principais fornecedores</h2>
              <p className="mt-1 text-xs text-zinc-500">Maior concentração de despesas no regime selecionado.</p>
              <div className="mt-5">
                <RankBars rows={suppliers} empty="Sem fornecedores para o período." />
              </div>
            </div>
          </section>

          <section className="rounded-xl border border-zinc-800 bg-zinc-950">
            <div className="border-b border-zinc-800 p-4">
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div>
                  <h2 className="text-base font-semibold text-zinc-100">Qualidade e inconsistências</h2>
                  <p className="mt-1 text-xs text-zinc-500">
                    Erros de lançamento e lacunas que reduzem a confiabilidade do diagnóstico.
                  </p>
                </div>
                <div className="text-right">
                  <div className="text-2xl font-semibold tabular-nums text-rose-200">{qualidade!.totalAlertas}</div>
                  <div className="text-xs text-zinc-500">
                    alertas · {qualidade!.titulosAfetados.toLocaleString("pt-BR")} títulos ·{" "}
                    {formatMoney(qualidade!.valorAfetado)} afetados
                  </div>
                </div>
              </div>
              {qualidade!.porSeveridade.length ? (
                <div className="mt-3 flex flex-wrap gap-2" aria-label="Alertas por severidade">
                  {qualidade!.porSeveridade.map((item, index) => {
                    const severity = normalizeSeverity(item.label);
                    const count = item.count ?? item.value;
                    return (
                      <span
                        key={`${item.label}-${index}`}
                        className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs ${severityTone(severity)}`}
                      >
                        {severity}: <strong className="tabular-nums">{Math.round(count).toLocaleString("pt-BR")}</strong>
                      </span>
                    );
                  })}
                </div>
              ) : null}
              <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-3">
                {[
                  ["Classificação", qualidade!.coberturaClassificacaoPct],
                  ["Centro de custo", qualidade!.coberturaCentroPct],
                  ["Rateio", qualidade!.coberturaRateioPct],
                ].map(([label, value]) => (
                  <div key={String(label)} className="rounded-lg border border-zinc-800 bg-black/30 p-3">
                    <div className="flex items-center justify-between gap-3 text-xs">
                      <span className="text-zinc-400">{label}</span>
                      <span className="tabular-nums text-zinc-100">{formatPercent(Number(value))}</span>
                    </div>
                    <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-zinc-900">
                      <div
                        className={`h-full rounded-full ${Number(value) >= 90 ? "bg-emerald-500" : "bg-amber-500"}`}
                        style={{ width: `${Number(value)}%` }}
                      />
                    </div>
                  </div>
                ))}
              </div>
              <div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-3">
                <label>
                  <span className="text-xs text-zinc-400">Severidade</span>
                  <select
                    value={severityFilter}
                    onChange={(event) => setSeverityFilter(event.target.value)}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-900 px-3 py-2 text-sm"
                  >
                    <option value="TODAS">Todas</option>
                    {severityOptions.map((severity) => (
                      <option key={severity} value={severity}>
                        {severity}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  <span className="text-xs text-zinc-400">Tipo</span>
                  <select
                    value={typeFilter}
                    onChange={(event) => setTypeFilter(event.target.value)}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-900 px-3 py-2 text-sm"
                  >
                    <option value="TODOS">Todos</option>
                    {typeOptions.map((item) => (
                      <option key={item} value={item}>
                        {item}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  <span className="text-xs text-zinc-400">Buscar</span>
                  <input
                    value={alertSearch}
                    onChange={(event) => setAlertSearch(event.target.value)}
                    placeholder="Título, referência ou ação recomendada"
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-900 px-3 py-2 text-sm placeholder:text-zinc-600"
                  />
                </label>
              </div>
            </div>
            <div className="overflow-x-auto">
              <table className="min-w-[1120px] w-full text-sm">
                <thead className="bg-zinc-900/50 text-zinc-400">
                  <tr>
                    <th className="px-4 py-3 text-left font-medium">Severidade</th>
                    <th className="px-4 py-3 text-left font-medium">Tipo</th>
                    <th className="px-4 py-3 text-left font-medium">Inconsistência</th>
                    <th className="px-4 py-3 text-left font-medium">Referência</th>
                    <th className="px-4 py-3 text-left font-medium">Ação recomendada</th>
                    <th className="px-4 py-3 text-right font-medium">Valor afetado</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-900">
                  {filteredAlerts.map((item) => (
                    <tr key={`${item.id}-${item.type}`} className="hover:bg-zinc-900/30">
                      <td className="px-4 py-3">
                        <span className={`inline-flex rounded-full border px-2 py-0.5 text-xs ${severityTone(item.severity)}`}>
                          {item.severity}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-zinc-300">{item.type}</td>
                      <td className="px-4 py-3">
                        <div className="font-medium text-zinc-100">{item.title}</div>
                        {item.detail ? <div className="mt-1 max-w-xl text-xs text-zinc-500">{item.detail}</div> : null}
                      </td>
                      <td className="px-4 py-3 text-zinc-400">
                        <div>{item.reference}</div>
                        {item.date ? <div className="mt-1 text-xs text-zinc-500">{formatDateBR(item.date)}</div> : null}
                      </td>
                      <td className="max-w-xs px-4 py-3 text-zinc-300">{item.action}</td>
                      <td className="px-4 py-3 text-right tabular-nums text-zinc-100">
                        {item.value === null ? "—" : formatMoney(item.value)}
                      </td>
                    </tr>
                  ))}
                  {!filteredAlerts.length ? (
                    <tr>
                      <td colSpan={6} className="px-4 py-8 text-center text-zinc-500">
                        Nenhuma inconsistência para os filtros selecionados.
                      </td>
                    </tr>
                  ) : null}
                </tbody>
              </table>
            </div>
          </section>

          <details className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 text-sm text-zinc-400">
            <summary className="cursor-pointer font-medium text-zinc-200">Metodologia e limites da análise</summary>
            <div className="mt-3 space-y-2 leading-6">
              <p>
                O índice atribui 30 pontos ao resultado do regime, 20 à cobertura de 30 dias, 15 à ausência de contas
                vencidas, 10 à classificação, 10 ao centro de custo, 5 ao rateio e 10 à consistência dos lançamentos.
                Quando há AP aberto, a parcela de contas vencidas perde pontos proporcionalmente a AP vencido ÷ AP aberto.
              </p>
              <p>
                O resultado gerencial considera as despesas operacionais classificadas e exclui investimentos e
                lançamentos sem rateio ou plano. A confiança do índice cai quando existem lançamentos não classificados.
              </p>
              <p>
                “Lucro” e “prejuízo” nesta tela representam resultado gerencial com base nos dados cadastrados; não
                substituem DRE, fechamento contábil ou apuração fiscal.
              </p>
              <p>
                Os filtros alteram o resultado por competência e o caixa do período. AP/AR aberto, aging e cobertura
                mostram a posição atual na referência indicada. Na composição auditada, cada compromisso pertence a
                uma única categoria principal; a forma de contratação permanece registrada separadamente.
              </p>
              <p>
                Títulos explicitamente marcados como legado de implantação não participam de AP aberto, aging,
                cobertura ou qualidade. A marca não cria pagamento, não altera caixa e não reescreve o resultado
                histórico; o total retirado permanece visível e auditável.
              </p>
              <p>
                A análise de estoque cruza movimentações físicas com notas de entrada e OS. Compras diretas para OS
                são separadas das compras para armazenagem. A posição histórica e as saídas sem custo gravado são
                estimadas pelo custo médio atual, enquanto pendências sem cadastro ou sem entrada permanecem fora da
                valorização até a regularização.
              </p>
            </div>
          </details>
        </>
      ) : null}

      <div className="sr-only" aria-live="polite">
        {loading ? "Relatório em atualização." : error ? "Erro ao atualizar relatório." : "Relatório atualizado."}
      </div>
    </main>
  );
}
