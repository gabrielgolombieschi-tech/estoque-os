"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { downloadCsv, formatDateBR } from "../relatoriosShared";

type RecordValue = Record<string, unknown>;
type Periodo = "mensal" | "anual";
type Situacao = "ABERTA" | "IGNORADA" | "TODAS";

type ResumoTipo = { tipo: string; quantidade: number; valor: number };
type ResumoPrioridade = { prioridade: string; quantidade: number };
type Resumo = {
  titulosEscopo: number;
  titulosComInconsistencia: number;
  titulosSemInconsistencia: number;
  qualidadePercentual: number;
  totalInconsistencias: number;
  totalAbertas: number;
  totalIgnoradas: number;
  valorTitulosAfetados: number;
  oportunidadesAutomacao: number;
  porTipo: ResumoTipo[];
  porPrioridade: ResumoPrioridade[];
};
type Item = {
  tituloId: string;
  tipo: string;
  prioridade: string;
  status: string;
  dataReferencia: string | null;
  fornecedorNome: string | null;
  documento: string | null;
  descricao: string | null;
  valorTotal: number;
  motivoCompraId: string | null;
  motivoCodigo: string | null;
  motivoNome: string | null;
  planoAtualId: string | null;
  planoAtualCodigo: string | null;
  planoAtualNome: string | null;
  centroAtualId: string | null;
  centroAtualCodigo: string | null;
  centroAtualNome: string | null;
  totalRateios: number;
  totalPercentual: number;
  totalRateado: number;
  detalhe: string;
  sugestao: string;
  corrigivel: boolean;
  podeCriarRegra: boolean;
  fingerprint: string;
  justificativaIgnorada: string | null;
  dados: RecordValue;
};
type Payload = {
  resumo: Resumo;
  total: number;
  itens: Item[];
};
type CatalogRow = { id: string; codigo: string; nome: string };
type Filters = {
  periodo: Periodo;
  ano: number;
  mes: number;
  tipo: string;
  prioridade: string;
  situacao: Situacao;
  busca: string;
  pagina: number;
  porPagina: number;
};

const MONTHS = [
  "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
  "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro",
] as const;
const KNOWN_TYPES = [
  "SEM_MOTIVO_COMPRA", "SEM_REGRA_RATEIO", "SEM_RATEIO", "SEM_PLANO_CONTAS",
  "SEM_CENTRO_CUSTO", "DESP_GERAL", "RATEIO_PERCENTUAL_INCORRETO",
  "RATEIO_VALOR_INCORRETO", "PLANO_INVALIDO", "CENTRO_INVALIDO",
  "PLANO_DIVERGENTE_MOTIVO", "POSSIVEL_DUPLICIDADE",
] as const;
const EMPTY_SUMMARY: Resumo = {
  titulosEscopo: 0,
  titulosComInconsistencia: 0,
  titulosSemInconsistencia: 0,
  qualidadePercentual: 100,
  totalInconsistencias: 0,
  totalAbertas: 0,
  totalIgnoradas: 0,
  valorTitulosAfetados: 0,
  oportunidadesAutomacao: 0,
  porTipo: [],
  porPrioridade: [],
};
const money = new Intl.NumberFormat("pt-BR", {
  style: "currency", currency: "BRL", minimumFractionDigits: 2, maximumFractionDigits: 2,
});

function record(value: unknown): RecordValue {
  return value && typeof value === "object" && !Array.isArray(value) ? value as RecordValue : {};
}
function first(row: RecordValue, keys: string[]): unknown {
  for (const key of keys) if (row[key] !== undefined && row[key] !== null) return row[key];
  return undefined;
}
function text(value: unknown, fallback = ""): string {
  return String(value ?? "").trim() || fallback;
}
function optionalText(value: unknown): string | null {
  return text(value) || null;
}
function numberValue(value: unknown): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const raw = text(value);
  const parsed = Number(raw.includes(",") ? raw.replace(/\./g, "").replace(",", ".") : raw);
  return Number.isFinite(parsed) ? parsed : 0;
}
function booleanValue(value: unknown): boolean {
  return value === true || ["TRUE", "T", "1", "SIM", "S"].includes(text(value).toUpperCase());
}
function code(value: unknown, fallback = ""): string {
  return text(value, fallback).normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, "_").toUpperCase();
}
function priority(value: unknown): string {
  const normalized = code(value, "MEDIA");
  if (["CRITICO", "CRITICA", "CRITICAL"].includes(normalized)) return "CRITICA";
  if (["ALTO", "ALTA", "HIGH"].includes(normalized)) return "ALTA";
  if (["MEDIO", "MEDIA", "MEDIUM", "ATENCAO"].includes(normalized)) return "MEDIA";
  if (["BAIXO", "BAIXA", "LOW"].includes(normalized)) return "BAIXA";
  return normalized;
}
function humanize(value: string): string {
  return value.replace(/_/g, " ").toLocaleLowerCase("pt-BR")
    .replace(/(^|\s)\p{L}/gu, (letter) => letter.toLocaleUpperCase("pt-BR"));
}
function priorityLabel(value: string): string {
  return ({ CRITICA: "Crítica", ALTA: "Alta", MEDIA: "Média", BAIXA: "Baixa" } as Record<string, string>)[priority(value)] ?? humanize(value);
}
function priorityTone(value: string): string {
  if (priority(value) === "CRITICA") return "border-rose-500/40 bg-rose-500/15 text-rose-200";
  if (priority(value) === "ALTA") return "border-orange-500/40 bg-orange-500/15 text-orange-200";
  if (priority(value) === "MEDIA") return "border-amber-500/40 bg-amber-500/15 text-amber-200";
  if (priority(value) === "BAIXA") return "border-sky-500/40 bg-sky-500/15 text-sky-200";
  return "border-zinc-700 bg-zinc-800/50 text-zinc-300";
}
function statusTone(value: string): string {
  if (code(value) === "IGNORADA") return "border-zinc-700 bg-zinc-900 text-zinc-300";
  if (code(value) === "RESOLVIDA") return "border-emerald-500/30 bg-emerald-500/10 text-emerald-200";
  return "border-amber-500/30 bg-amber-500/10 text-amber-200";
}
function formatMoney(value: number): string { return money.format(Number.isFinite(value) ? value : 0); }
function formatPercent(value: number): string {
  return `${value.toLocaleString("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`;
}
function itemKey(item: Item): string { return `${item.tipo}:${item.tituloId}:${item.fingerprint}`; }
function isAutomation(item: Item): boolean { return item.tipo === "SEM_REGRA_RATEIO"; }
function isBlockedType(item: Item): boolean {
  return /DUPLIC|LEGADO|RATEIO_MULTIPLO|MULTIPLOS_RATEIOS/.test(item.tipo);
}
function isCorrectable(item: Item, canWrite: boolean | undefined): boolean {
  return canWrite === true && item.status === "ABERTA"
    && (item.corrigivel || (isAutomation(item) && item.podeCriarRegra))
    && !isBlockedType(item);
}

function parseItem(value: unknown): Item | null {
  const row = record(value);
  const tituloId = text(first(row, ["tituloId", "titulo_id"]));
  const tipo = code(first(row, ["tipo", "codigo"]), "OUTRA");
  if (!tituloId) return null;
  return {
    tituloId,
    tipo,
    prioridade: priority(first(row, ["prioridade", "severidade"])),
    status: code(first(row, ["status", "situacao"]), "ABERTA"),
    dataReferencia: optionalText(first(row, ["dataReferencia", "data_referencia", "data"])),
    fornecedorNome: optionalText(first(row, ["fornecedorNome", "fornecedor_nome"])),
    documento: optionalText(first(row, ["documento", "numeroDocumento", "numero_documento"])),
    descricao: optionalText(row.descricao),
    valorTotal: numberValue(first(row, ["valorTotal", "valor_total", "valor"])),
    motivoCompraId: optionalText(first(row, ["motivoCompraId", "motivo_compra_id"])),
    motivoCodigo: optionalText(first(row, ["motivoCodigo", "motivo_codigo"])),
    motivoNome: optionalText(first(row, ["motivoNome", "motivo_nome"])),
    planoAtualId: optionalText(first(row, ["planoAtualId", "plano_atual_id"])),
    planoAtualCodigo: optionalText(first(row, ["planoAtualCodigo", "plano_atual_codigo"])),
    planoAtualNome: optionalText(first(row, ["planoAtualNome", "plano_atual_nome"])),
    centroAtualId: optionalText(first(row, ["centroAtualId", "centro_atual_id"])),
    centroAtualCodigo: optionalText(first(row, ["centroAtualCodigo", "centro_atual_codigo"])),
    centroAtualNome: optionalText(first(row, ["centroAtualNome", "centro_atual_nome"])),
    totalRateios: numberValue(first(row, ["totalRateios", "total_rateios"])),
    totalPercentual: numberValue(first(row, ["totalPercentual", "total_percentual"])),
    totalRateado: numberValue(first(row, ["totalRateado", "total_rateado"])),
    detalhe: text(row.detalhe),
    sugestao: text(row.sugestao),
    corrigivel: booleanValue(first(row, ["corrigivel", "podeCorrigir", "pode_corrigir"])),
    podeCriarRegra: booleanValue(first(row, ["podeCriarRegra", "pode_criar_regra"])),
    fingerprint: text(first(row, ["fingerprint", "chave", "id"]), `${tipo}:${tituloId}`),
    justificativaIgnorada: optionalText(first(row, ["justificativaIgnorada", "justificativa_ignorada"])),
    dados: record(first(row, ["dados", "metadata"])),
  };
}

function parsePayload(value: unknown): Payload {
  let root = record(Array.isArray(value) ? value[0] : value);
  if (!root.resumo && !root.itens) root = record(first(root, ["resultado", "data"]));
  const summary = record(first(root, ["resumo", "summary"]));
  const pagination = record(first(root, ["paginacao", "pagination"]));
  const rawTypes = Array.isArray(first(summary, ["porTipo", "por_tipo"])) ? first(summary, ["porTipo", "por_tipo"]) as unknown[] : [];
  const rawPriorities = Array.isArray(first(summary, ["porPrioridade", "por_prioridade"])) ? first(summary, ["porPrioridade", "por_prioridade"]) as unknown[] : [];
  const rawItems = Array.isArray(first(root, ["itens", "items"])) ? first(root, ["itens", "items"]) as unknown[] : [];
  return {
    resumo: {
      titulosEscopo: numberValue(first(summary, ["titulosEscopo", "titulos_escopo"])),
      titulosComInconsistencia: numberValue(first(summary, ["titulosComInconsistencia", "titulos_com_inconsistencia"])),
      titulosSemInconsistencia: numberValue(first(summary, ["titulosSemInconsistencia", "titulos_sem_inconsistencia"])),
      qualidadePercentual: numberValue(first(summary, ["qualidadePercentual", "qualidade_percentual"])),
      totalInconsistencias: numberValue(first(summary, ["totalInconsistencias", "total_inconsistencias"])),
      totalAbertas: numberValue(first(summary, ["totalAbertas", "total_abertas"])),
      totalIgnoradas: numberValue(first(summary, ["totalIgnoradas", "total_ignoradas"])),
      valorTitulosAfetados: numberValue(first(summary, ["valorTitulosAfetados", "valor_titulos_afetados"])),
      oportunidadesAutomacao: numberValue(first(summary, ["oportunidadesAutomacao", "oportunidades_automacao"])),
      porTipo: rawTypes.map((entry) => record(entry)).map((row) => ({
        tipo: code(first(row, ["tipo", "codigo"])),
        quantidade: numberValue(first(row, ["quantidade", "qtd", "count"])),
        valor: numberValue(first(row, ["valor", "value"])),
      })).filter((entry) => entry.tipo),
      porPrioridade: rawPriorities.map((entry) => record(entry)).map((row) => ({
        prioridade: priority(first(row, ["prioridade", "severidade"])),
        quantidade: numberValue(first(row, ["quantidade", "qtd", "count"])),
      })),
    },
    total: numberValue(first(pagination, ["total", "totalItens", "total_itens"])),
    itens: rawItems.map(parseItem).filter((entry): entry is Item => entry !== null),
  };
}

function readFilters(params: URLSearchParams): Filters {
  const now = new Date();
  const year = Number(params.get("ano"));
  const month = Number(params.get("mes"));
  const page = Number(params.get("pagina"));
  const pageSize = Number(params.get("porPagina"));
  const rawStatus = code(params.get("status"), "ABERTA");
  return {
    periodo: params.get("periodo") === "anual" ? "anual" : "mensal",
    ano: Number.isInteger(year) && year >= 2000 && year <= 2100 ? year : now.getFullYear(),
    mes: Number.isInteger(month) && month >= 1 && month <= 12 ? month : now.getMonth() + 1,
    tipo: code(params.get("tipo")),
    prioridade: params.get("prioridade") ? priority(params.get("prioridade")) : "",
    situacao: rawStatus === "IGNORADA" ? "IGNORADA" : rawStatus === "TODAS" ? "TODAS" : "ABERTA",
    busca: text(params.get("q")),
    pagina: Number.isInteger(page) && page > 0 ? page : 1,
    porPagina: [25, 50, 100, 200].includes(pageSize) ? pageSize : 50,
  };
}
function periodRange(filters: Filters) {
  if (filters.periodo === "anual") {
    return { start: `${filters.ano}-01-01`, end: `${filters.ano}-12-31`, label: `Ano de ${filters.ano}` };
  }
  const month = String(filters.mes).padStart(2, "0");
  const last = new Date(filters.ano, filters.mes, 0).getDate();
  return {
    start: `${filters.ano}-${month}-01`,
    end: `${filters.ano}-${month}-${String(last).padStart(2, "0")}`,
    label: `${MONTHS[filters.mes - 1]} de ${filters.ano}`,
  };
}
function currentClassification(item: Item): string {
  const plano = [item.planoAtualCodigo, item.planoAtualNome].filter(Boolean).join(" — ");
  const centro = [item.centroAtualCodigo, item.centroAtualNome].filter(Boolean).join(" — ");
  if (plano || centro) return [plano ? `Plano: ${plano}` : "Plano não informado", centro ? `Centro: ${centro}` : "Centro não informado"].join(" · ");
  if (item.motivoCodigo || item.motivoNome) return `Motivo: ${[item.motivoCodigo, item.motivoNome].filter(Boolean).join(" — ")}`;
  if (item.totalRateios > 0) return `${item.totalRateios} rateio(s) · ${formatPercent(item.totalPercentual)}`;
  return "Sem classificação";
}
function suggestedId(item: Item, kind: "plano" | "centro"): string {
  const keys = kind === "plano"
    ? ["planoSugeridoId", "plano_sugerido_id", "planoContasId", "plano_contas_id"]
    : ["centroSugeridoId", "centro_sugerido_id", "centroCustoId", "centro_custo_id"];
  return text(first(item.dados, keys));
}

export default function InconsistenciasFinanceirasClient() {
  const te = useTenantEmpresa();
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const filters = useMemo(() => readFilters(new URLSearchParams(searchParams.toString())), [searchParams]);
  const range = useMemo(() => periodRange(filters), [filters]);

  const canFinanceiro = useMemo(() => {
    const read = te.has("financeiro.read");
    const write = te.has("financeiro.write");
    return read === undefined || write === undefined ? undefined : Boolean(read || write);
  }, [te]);
  const canWrite = useMemo(() => {
    const write = te.has("financeiro.write");
    return write === undefined ? undefined : Boolean(write);
  }, [te]);
  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  const [payload, setPayload] = useState<Payload>({ resumo: EMPTY_SUMMARY, total: 0, itens: [] });
  const [planos, setPlanos] = useState<CatalogRow[]>([]);
  const [centros, setCentros] = useState<CatalogRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [catalogLoading, setCatalogLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);
  const [selectedKeys, setSelectedKeys] = useState<Set<string>>(new Set());
  const [detailItem, setDetailItem] = useState<Item | null>(null);
  const [correctionOpen, setCorrectionOpen] = useState(false);
  const [planId, setPlanId] = useState("");
  const [centerId, setCenterId] = useState("");
  const [justification, setJustification] = useState("");
  const [createRule, setCreateRule] = useState(false);
  const [saving, setSaving] = useState(false);
  const [actionBusy, setActionBusy] = useState(false);
  const [ignoreOpen, setIgnoreOpen] = useState(false);
  const [ignoreJustification, setIgnoreJustification] = useState("");

  const setUrl = useCallback((patch: Record<string, string | number | null>, keepPage = false) => {
    const params = new URLSearchParams(searchParams.toString());
    Object.entries(patch).forEach(([key, value]) => {
      if (value === null || value === "") params.delete(key);
      else params.set(key, String(value));
    });
    if (!keepPage && !("pagina" in patch)) params.delete("pagina");
    setSelectedKeys(new Set());
    setDetailItem(null);
    setCorrectionOpen(false);
    setIgnoreOpen(false);
    setIgnoreJustification("");
    const query = params.toString();
    router.replace(query ? `${pathname}?${query}` : pathname, { scroll: false });
  }, [pathname, router, searchParams]);

  useEffect(() => {
    const params = new URLSearchParams(searchParams.toString());
    let changed = false;
    const ensure = (key: string, value: string) => {
      if (!params.has(key)) { params.set(key, value); changed = true; }
    };
    ensure("periodo", filters.periodo);
    ensure("ano", String(filters.ano));
    if (filters.periodo === "mensal") ensure("mes", String(filters.mes));
    ensure("status", filters.situacao.toLocaleLowerCase("pt-BR"));
    if (changed) router.replace(`${pathname}?${params.toString()}`, { scroll: false });
  }, [filters.ano, filters.mes, filters.periodo, filters.situacao, pathname, router, searchParams]);

  const tenantId = te.tenantId;
  const empresaId = te.empresaId;
  const ready = typeof te.sessionUserId === "string" && Boolean(tenantId) && Boolean(empresaId) && canFinanceiro === true;

  useEffect(() => {
    if (!ready || !tenantId || !empresaId) return;
    let cancelled = false;
    const load = async () => {
      setLoading(true);
      setError(null);
      setIgnoreOpen(false);
      setIgnoreJustification("");
      try {
        const { data, error: rpcError } = await getSupabaseBrowser().schema("f").rpc("listar_inconsistencias_financeiras", {
          p_tenant_id: tenantId,
          p_empresa_id: empresaId,
          p_data_inicio: range.start,
          p_data_fim: range.end,
          p_tipo: filters.tipo || null,
          p_prioridade: filters.prioridade || null,
          p_status: filters.situacao,
          p_busca: filters.busca || null,
          p_limite: filters.porPagina,
          p_offset: (filters.pagina - 1) * filters.porPagina,
        });
        if (rpcError) throw rpcError;
        if (!cancelled) {
          setPayload(parsePayload(data));
          setSelectedKeys(new Set());
          setDetailItem(null);
          setCorrectionOpen(false);
        }
      } catch (cause: unknown) {
        if (!cancelled) {
          setPayload({ resumo: EMPTY_SUMMARY, total: 0, itens: [] });
          setError(cause instanceof Error ? cause.message : "Não foi possível carregar as inconsistências.");
        }
      } finally { if (!cancelled) setLoading(false); }
    };
    void load();
    return () => { cancelled = true; };
  }, [empresaId, filters.busca, filters.pagina, filters.porPagina, filters.prioridade, filters.situacao, filters.tipo, range.end, range.start, ready, reloadKey, tenantId]);

  useEffect(() => {
    if (!ready || !tenantId || !empresaId) return;
    let cancelled = false;
    const load = async () => {
      setCatalogLoading(true);
      try {
        const supabase = getSupabaseBrowser();
        const [plans, centers] = await Promise.all([
          supabase.schema("f").from("plano_contas").select("id,codigo,nome")
            .eq("tenant_id", tenantId).eq("tipo", "ANALITICA").neq("codigo", "DESP_GERAL").eq("ativo", true).is("deleted_at", null).order("codigo"),
          supabase.schema("f").from("centro_custo").select("id,codigo,nome")
            .eq("tenant_id", tenantId).eq("empresa_id", empresaId).eq("ativo", true).is("deleted_at", null).order("codigo"),
        ]);
        if (plans.error) throw plans.error;
        if (centers.error) throw centers.error;
        if (!cancelled) {
          setPlanos((plans.data ?? []) as CatalogRow[]);
          setCentros((centers.data ?? []) as CatalogRow[]);
        }
      } catch (cause: unknown) {
        if (!cancelled) setError(cause instanceof Error ? cause.message : "Não foi possível carregar planos e centros.");
      } finally { if (!cancelled) setCatalogLoading(false); }
    };
    void load();
    return () => { cancelled = true; };
  }, [empresaId, ready, tenantId]);

  const selectedItems = useMemo(() => payload.itens.filter((item) => selectedKeys.has(itemKey(item))), [payload.itens, selectedKeys]);
  const selectedTitleIds = useMemo(() => Array.from(new Set(selectedItems.map((item) => item.tituloId))), [selectedItems]);
  const correctable = useMemo(() => payload.itens.filter((item) => isCorrectable(item, canWrite)), [canWrite, payload.itens]);
  const allSelected = correctable.length > 0 && correctable.every((item) => selectedKeys.has(itemKey(item)));
  const selectedMotivos = useMemo(() => new Set(selectedItems.map((item) => item.motivoCompraId).filter(Boolean)), [selectedItems]);
  const canCreateRule = selectedItems.length > 0 && selectedMotivos.size === 1 && selectedItems.every((item) => item.podeCriarRegra && item.tipo !== "DESP_GERAL");
  const automationOnly = selectedItems.length > 0 && selectedItems.every(isAutomation);
  const totalPages = Math.max(1, Math.ceil(payload.total / filters.porPagina));
  const despGeral = payload.resumo.porTipo.find((entry) => entry.tipo === "DESP_GERAL");
  const semCentro = payload.resumo.porTipo.find((entry) => entry.tipo === "SEM_CENTRO_CUSTO");
  const automationCount = payload.resumo.oportunidadesAutomacao || payload.resumo.porTipo.find((entry) => entry.tipo === "SEM_REGRA_RATEIO")?.quantidade || 0;
  const empresaNome = te.empresa?.nome_fantasia?.trim() || te.empresa?.razao_social?.trim() || "empresa selecionada";

  const typeOptions = useMemo(() => {
    const values = new Set<string>(KNOWN_TYPES);
    payload.resumo.porTipo.forEach((entry) => values.add(entry.tipo));
    if (filters.tipo) values.add(filters.tipo);
    return Array.from(values).sort((a, b) => humanize(a).localeCompare(humanize(b), "pt-BR"));
  }, [filters.tipo, payload.resumo.porTipo]);

  const toggle = (item: Item) => setSelectedKeys((current) => {
    const next = new Set(current);
    const key = itemKey(item);
    if (next.has(key)) next.delete(key); else next.add(key);
    return next;
  });
  const toggleAll = () => setSelectedKeys((current) => {
    const next = new Set(current);
    correctable.forEach((item) => allSelected ? next.delete(itemKey(item)) : next.add(itemKey(item)));
    return next;
  });
  const openCorrection = (items = selectedItems) => {
    if (!items.length || items.some((item) => !isCorrectable(item, canWrite))) return;
    const motiveIds = new Set(items.map((item) => item.motivoCompraId).filter(Boolean));
    const automationEligible = items.every(isAutomation) && motiveIds.size === 1
      && items.every((item) => item.podeCriarRegra && item.tipo !== "DESP_GERAL");
    setSelectedKeys(new Set(items.map(itemKey)));
    setPlanId(items.map((item) => item.tipo === "DESP_GERAL" ? "" : text(first(item.dados, ["planoMotivoId", "plano_motivo_id"])) || suggestedId(item, "plano") || item.planoAtualId || "").find((id) => planos.some((row) => row.id === id)) ?? "");
    setCenterId(items.map((item) => suggestedId(item, "centro") || item.centroAtualId || "").find((id) => centros.some((row) => row.id === id)) ?? "");
    setJustification("");
    setCreateRule(automationEligible);
    setCorrectionOpen(true);
  };

  const saveCorrection = async () => {
    if (!tenantId || !empresaId || canWrite !== true || !selectedTitleIds.length) return;
    if (!planId || !centerId) { setError("Selecione o plano de contas e o centro de custo."); return; }
    if (justification.trim().length < 10) { setError("Informe uma justificativa com pelo menos 10 caracteres."); return; }
    const effectiveCreateRule = automationOnly ? true : createRule;
    if (effectiveCreateRule && !canCreateRule) { setError("Os selecionados não permitem criar uma única regra segura."); return; }
    setSaving(true); setError(null); setNotice(null);
    try {
      const { data, error: rpcError } = await getSupabaseBrowser().schema("f").rpc("corrigir_inconsistencias_financeiras", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaId,
        p_titulo_ids: selectedTitleIds,
        p_plano_contas_id: planId,
        p_centro_custo_id: centerId,
        p_justificativa: justification.trim(),
        p_criar_regra: effectiveCreateRule,
      });
      if (rpcError) throw rpcError;
      const result = record(data);
      const count = numberValue(first(result, ["corrigidos", "corrected"]));
      const ruleId = optionalText(first(result, ["regraCriadaId", "regra_criada_id"]));
      setNotice(`${count.toLocaleString("pt-BR")} lançamento(ões) corrigido(s).${ruleId ? " Regra automática criada." : ""}`);
      setCorrectionOpen(false); setSelectedKeys(new Set()); setReloadKey((value) => value + 1);
    } catch (cause: unknown) {
      setError(cause instanceof Error ? cause.message : "Não foi possível corrigir os lançamentos.");
    } finally { setSaving(false); }
  };

  const submitSearch = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const value = text(new FormData(event.currentTarget).get("q"));
    setUrl({ q: value || null });
  };
  const clearFilters = () => {
    const now = new Date();
    setUrl({ periodo: "mensal", ano: now.getFullYear(), mes: now.getMonth() + 1, tipo: null, prioridade: null, status: "aberta", q: null, pagina: null, porPagina: null });
  };
  const exportPage = () => downloadCsv(
    `inconsistencias_${filters.ano}_${filters.pagina}.csv`,
    ["Prioridade", "Status", "Tipo", "Título", "Fornecedor", "Documento", "Data", "Motivo", "Valor", "Detalhe", "Sugestão"],
    payload.itens.map((item) => [priorityLabel(item.prioridade), humanize(item.status), humanize(item.tipo), item.tituloId,
      item.fornecedorNome ?? "", item.documento ?? "", item.dataReferencia ? formatDateBR(item.dataReferencia) : "",
      currentClassification(item), item.valorTotal.toLocaleString("pt-BR", { minimumFractionDigits: 2 }), item.detalhe, item.sugestao]),
  );

  const ignoreItem = async () => {
    if (!tenantId || !empresaId || !detailItem || canWrite !== true || ignoreJustification.trim().length < 10) return;
    setActionBusy(true); setError(null); setNotice(null);
    try {
      const { data, error: rpcError } = await getSupabaseBrowser().schema("f").rpc("ignorar_inconsistencias_financeiras", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaId,
        p_itens: [{ titulo_id: detailItem.tituloId, tipo: detailItem.tipo }],
        p_justificativa: ignoreJustification.trim(),
      });
      if (rpcError) throw rpcError;
      const result = record(data);
      const ignored = numberValue(first(result, ["ignoradas", "ignored"]));
      const already = numberValue(first(result, ["jaIgnoradas", "ja_ignoradas"]));
      setNotice(`${ignored || already} inconsistência(s) marcada(s) como ignorada(s).`);
      setIgnoreOpen(false); setDetailItem(null); setReloadKey((value) => value + 1);
    } catch (cause: unknown) {
      setError(cause instanceof Error ? cause.message : "Não foi possível ignorar a inconsistência.");
    } finally { setActionBusy(false); }
  };

  const reopenItem = async () => {
    if (!tenantId || !empresaId || !detailItem || canWrite !== true) return;
    setActionBusy(true); setError(null); setNotice(null);
    try {
      const { error: rpcError } = await getSupabaseBrowser().schema("f").rpc("reabrir_inconsistencia_financeira", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaId,
        p_titulo_id: detailItem.tituloId,
        p_tipo: detailItem.tipo,
      });
      if (rpcError) throw rpcError;
      setNotice("Inconsistência reaberta para tratamento.");
      setDetailItem(null); setReloadKey((value) => value + 1);
    } catch (cause: unknown) {
      setError(cause instanceof Error ? cause.message : "Não foi possível reabrir a inconsistência.");
    } finally { setActionBusy(false); }
  };

  if (canFinanceiro === undefined) {
    return <div role="status" className="rounded-xl border border-zinc-800 bg-zinc-950 p-8 text-center text-sm text-zinc-400">Carregando permissões…</div>;
  }
  if (canFinanceiro === false) return null;
  if (typeof te.sessionUserId === "string" && (!tenantId || !empresaId)) {
    return <div role="alert" className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">Selecione uma empresa no topo para abrir a Central de Inconsistências.</div>;
  }

  return (
    <main className="space-y-5" aria-busy={loading}>
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <div className="text-xs font-medium uppercase tracking-[0.18em] text-sky-400">Qualidade financeira</div>
          <h1 className="mt-1 text-2xl font-semibold text-zinc-100">Central de Inconsistências</h1>
          <p className="mt-1 max-w-3xl text-sm text-zinc-400">
            Priorize e corrija lançamentos que reduzem a confiança dos relatórios da empresa <span className="font-medium text-zinc-200">{empresaNome}</span>.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link href="/financeiro/relatorios/saude-financeira" className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm hover:bg-zinc-900">Saúde Financeira</Link>
          <Link href="/financeiro/cadastros/regras-rateio" className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm hover:bg-zinc-900">Regras de rateio</Link>
          <button type="button" onClick={exportPage} disabled={loading || !payload.itens.length} className="rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm hover:bg-zinc-800 disabled:opacity-40">Exportar página CSV</button>
        </div>
      </header>

      <section aria-label="Filtros" className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div>
            <div className="mb-1 text-xs text-zinc-400">Período</div>
            <div className="inline-flex rounded-lg border border-zinc-800 bg-black p-1">
              {(["mensal", "anual"] as Periodo[]).map((period) => (
                <button key={period} type="button" onClick={() => setUrl({ periodo: period, mes: period === "mensal" ? filters.mes : null })}
                  className={`rounded-md px-3 py-1.5 text-sm ${filters.periodo === period ? "bg-zinc-800 text-zinc-100" : "text-zinc-400"}`}>
                  {period === "mensal" ? "Mensal" : "Anual"}
                </button>
              ))}
            </div>
          </div>
          <FilterSelect label="Ano" value={String(filters.ano)} onChange={(value) => setUrl({ ano: value })}
            options={Array.from({ length: 12 }, (_, index) => String(new Date().getFullYear() + 1 - index)).map((value) => ({ value, label: value }))} />
          <FilterSelect label="Mês" value={String(filters.mes)} disabled={filters.periodo === "anual"} onChange={(value) => setUrl({ mes: value })}
            options={MONTHS.map((label, index) => ({ value: String(index + 1), label }))} />
          <FilterSelect label="Prioridade" value={filters.prioridade} onChange={(value) => setUrl({ prioridade: value.toLocaleLowerCase("pt-BR") || null })}
            options={[{ value: "", label: "Todas" }, { value: "ALTA", label: "Alta" }, { value: "MEDIA", label: "Média" }, { value: "BAIXA", label: "Baixa" }]} />
          <FilterSelect label="Tipo" value={filters.tipo} onChange={(value) => setUrl({ tipo: value || null })}
            options={[{ value: "", label: "Todos" }, ...typeOptions.map((value) => ({ value, label: value === "SEM_REGRA_RATEIO" ? "Oportunidade de automação" : humanize(value) }))]} />
          <FilterSelect label="Situação" value={filters.situacao} onChange={(value) => setUrl({ status: value.toLocaleLowerCase("pt-BR") })}
            options={[{ value: "ABERTA", label: "Pendentes" }, { value: "IGNORADA", label: "Ignoradas" }, { value: "TODAS", label: "Todas" }]} />
          <form onSubmit={submitSearch} className="min-w-[240px] flex-1">
            <label className="block text-xs text-zinc-400">Buscar
              <div className="mt-1 flex">
                <input key={filters.busca} name="q" defaultValue={filters.busca} placeholder="Fornecedor, documento…"
                  className="min-w-0 flex-1 rounded-l-md border border-r-0 border-zinc-800 bg-zinc-900 px-3 py-2 text-sm placeholder:text-zinc-600" />
                <button type="submit" className="rounded-r-md border border-zinc-700 bg-zinc-800 px-3 text-xs hover:bg-zinc-700">Filtrar</button>
              </div>
            </label>
          </form>
        </div>
        <div className="mt-3 flex flex-wrap items-center justify-between gap-2 text-xs text-zinc-500">
          <span>{range.label} · {range.start.split("-").reverse().join("/")} a {range.end.split("-").reverse().join("/")}</span>
          <button type="button" onClick={clearFilters} className="underline decoration-zinc-700 underline-offset-4 hover:text-zinc-200">Limpar filtros</button>
        </div>
      </section>

      {error ? <section role="alert" className="rounded-xl border border-rose-500/30 bg-rose-500/10 p-4 text-sm text-rose-100">
        <div>{error}</div><button type="button" onClick={() => setReloadKey((value) => value + 1)} className="mt-2 rounded-md border border-rose-400/30 px-3 py-1.5">Tentar novamente</button>
      </section> : null}
      {notice ? <section role="status" className="rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-100">{notice}</section> : null}

      <section className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-6">
        <MetricCard title="Qualidade dos dados" value={formatPercent(payload.resumo.qualidadePercentual)} subtitle={`${payload.resumo.titulosSemInconsistencia} de ${payload.resumo.titulosEscopo} títulos sem pendência`} tone={payload.resumo.qualidadePercentual >= 95 ? "emerald" : payload.resumo.qualidadePercentual >= 80 ? "amber" : "rose"} />
        <MetricCard title="Pendências abertas" value={payload.resumo.totalInconsistencias.toLocaleString("pt-BR")} subtitle={`${payload.resumo.titulosComInconsistencia} títulos afetados`} tone={payload.resumo.totalInconsistencias ? "rose" : "emerald"} />
        <MetricCard title="Valor afetado" value={formatMoney(payload.resumo.valorTitulosAfetados)} subtitle="Sem duplicar alertas do mesmo título" tone={payload.resumo.valorTitulosAfetados ? "amber" : "emerald"} />
        <MetricCard title="Despesas gerais" value={(despGeral?.quantidade ?? 0).toLocaleString("pt-BR")} subtitle={despGeral ? `${formatMoney(despGeral.valor)} para revisar` : "Nenhuma no período"} tone={despGeral ? "amber" : "emerald"} />
        <MetricCard title="Sem centro de custo" value={(semCentro?.quantidade ?? 0).toLocaleString("pt-BR")} subtitle={semCentro ? `${formatMoney(semCentro.valor)} para classificar` : "Cobertura completa"} tone={semCentro ? "amber" : "emerald"} />
        <MetricCard title="Oportunidades de automação" value={automationCount.toLocaleString("pt-BR")} subtitle="Motivos sem regra de rateio" tone="sky" />
      </section>

      {payload.resumo.porPrioridade.length ? <section className="flex flex-wrap items-center gap-2 rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <span className="mr-1 text-xs uppercase tracking-wide text-zinc-500">Fila por prioridade</span>
        {payload.resumo.porPrioridade.map((entry) => <button key={entry.prioridade} type="button" onClick={() => setUrl({ prioridade: entry.prioridade.toLocaleLowerCase("pt-BR") })}
          className={`rounded-full border px-2.5 py-1 text-xs ${priorityTone(entry.prioridade)}`}>{priorityLabel(entry.prioridade)} · <strong>{entry.quantidade}</strong></button>)}
        <span className="ml-auto text-xs text-zinc-500">{payload.resumo.totalIgnoradas} ignorada(s)</span>
      </section> : null}

      {selectedItems.length ? <section className="sticky top-3 z-20 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-sky-500/30 bg-sky-950/95 px-4 py-3 shadow-xl backdrop-blur">
        <div><div className="font-medium text-sky-100">{selectedItems.length} ocorrência(s) selecionada(s)</div><div className="text-xs text-sky-200/70">{selectedTitleIds.length} lançamento(ões) distintos</div></div>
        <div className="flex gap-2"><button type="button" onClick={() => setSelectedKeys(new Set())} className="rounded-md border border-sky-400/20 px-3 py-2 text-sm">Limpar</button>
          <button type="button" onClick={() => openCorrection()} className="rounded-md bg-zinc-100 px-3 py-2 text-sm font-medium text-zinc-900">{automationOnly ? "Automatizar selecionados" : "Corrigir selecionados"}</button></div>
      </section> : null}

      <section className="overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950">
        <div className="flex items-center justify-between border-b border-zinc-800 px-4 py-3">
          <div><h2 className="font-semibold">Fila de tratamento</h2><p className="mt-0.5 text-xs text-zinc-500">Somente ocorrências marcadas como corrigíveis podem ser selecionadas.</p></div>
          <div className="text-xs text-zinc-500">{loading ? "Carregando…" : `${payload.total.toLocaleString("pt-BR")} ocorrência(s)`}</div>
        </div>
        {loading ? <div role="status" className="space-y-2 p-4">{Array.from({ length: 5 }, (_, index) => <div key={index} className="h-16 animate-pulse rounded-lg bg-zinc-900" />)}</div> :
          <div className="overflow-x-auto"><table className="min-w-[1260px] w-full text-sm">
            <thead className="bg-zinc-900/50 text-zinc-400"><tr>
              <th className="w-12 px-4 py-3 text-left"><input type="checkbox" aria-label="Selecionar corrigíveis" checked={allSelected} onChange={toggleAll} disabled={!correctable.length} className="accent-zinc-100 disabled:opacity-30" /></th>
              <th className="px-4 py-3 text-left font-medium">Prioridade</th><th className="px-4 py-3 text-left font-medium">Problema</th>
              <th className="px-4 py-3 text-left font-medium">Lançamento</th><th className="px-4 py-3 text-left font-medium">Classificação atual</th>
              <th className="px-4 py-3 text-left font-medium">Sugestão</th><th className="px-4 py-3 text-right font-medium">Valor</th><th className="px-4 py-3 text-right font-medium">Ações</th>
            </tr></thead>
            <tbody className="divide-y divide-zinc-900">
              {payload.itens.map((item) => {
                const key = itemKey(item); const allowed = isCorrectable(item, canWrite); const opportunity = isAutomation(item);
                return <tr key={key} className="align-top hover:bg-zinc-900/30">
                  <td className="px-4 py-4"><input type="checkbox" aria-label={`Selecionar ${item.tipo}`} checked={selectedKeys.has(key)} onChange={() => toggle(item)} disabled={!allowed} className="accent-zinc-100 disabled:opacity-25" /></td>
                  <td className="px-4 py-4"><span className={`rounded-full border px-2 py-0.5 text-xs ${opportunity ? "border-sky-500/30 bg-sky-500/10 text-sky-200" : priorityTone(item.prioridade)}`}>{opportunity ? "Automação" : priorityLabel(item.prioridade)}</span>
                    <div className="mt-2"><span className={`rounded-full border px-2 py-0.5 text-[11px] ${statusTone(item.status)}`}>{humanize(item.status)}</span></div></td>
                  <td className="max-w-[340px] px-4 py-4"><div className={`font-medium ${opportunity ? "text-sky-200" : "text-zinc-100"}`}>{opportunity ? "Oportunidade de automação" : humanize(item.tipo)}</div><div className="mt-1 text-xs leading-5 text-zinc-500">{item.detalhe}</div></td>
                  <td className="max-w-[260px] px-4 py-4"><div className="truncate font-medium text-zinc-200" title={item.fornecedorNome ?? undefined}>{item.fornecedorNome ?? "Fornecedor não informado"}</div>
                    <div className="mt-1 text-xs text-zinc-500">{item.documento ? `Documento ${item.documento}` : `Título ${item.tituloId.slice(0, 8)}`}{item.dataReferencia ? ` · ${formatDateBR(item.dataReferencia)}` : ""}</div>
                    {item.descricao ? <div className="mt-1 truncate text-xs text-zinc-500" title={item.descricao}>{item.descricao}</div> : null}</td>
                  <td className="max-w-[250px] px-4 py-4 text-zinc-300">{currentClassification(item)}{item.totalRateios ? <div className="mt-1 text-xs tabular-nums text-zinc-500">{formatMoney(item.totalRateado)} rateados</div> : null}</td>
                  <td className="max-w-[280px] px-4 py-4"><div className="text-zinc-300">{item.sugestao || "Revisão manual necessária"}</div>{item.podeCriarRegra ? <div className="mt-1 text-xs text-emerald-300">Pode gerar regra para os próximos</div> : null}</td>
                  <td className="whitespace-nowrap px-4 py-4 text-right font-medium tabular-nums">{formatMoney(item.valorTotal)}</td>
                  <td className="px-4 py-4"><div className="flex justify-end gap-2"><button type="button" onClick={() => setDetailItem(item)} className="rounded-md border border-zinc-800 px-3 py-1.5 text-xs hover:bg-zinc-900">Detalhes</button>
                    <button type="button" onClick={() => openCorrection([item])} disabled={!allowed} className={`rounded-md border px-3 py-1.5 text-xs disabled:opacity-25 ${opportunity ? "border-sky-500/30 bg-sky-500/10 text-sky-200" : "border-emerald-500/30 bg-emerald-500/10 text-emerald-200"}`}>{opportunity ? "Automatizar" : "Corrigir"}</button></div></td>
                </tr>;
              })}
              {!payload.itens.length ? <tr><td colSpan={8} className="px-4 py-12 text-center text-zinc-500">Nenhuma inconsistência encontrada para os filtros atuais.</td></tr> : null}
            </tbody>
          </table></div>}
        <div className="flex flex-wrap items-center justify-between gap-3 border-t border-zinc-800 px-4 py-3 text-sm">
          <label className="text-zinc-400">Itens por página <select value={filters.porPagina} onChange={(event) => setUrl({ porPagina: event.target.value, pagina: null })} className="ml-2 rounded-md border border-zinc-800 bg-zinc-900 px-2 py-1 text-zinc-100">{[25, 50, 100, 200].map((value) => <option key={value}>{value}</option>)}</select></label>
          <div className="flex items-center gap-2"><button type="button" onClick={() => setUrl({ pagina: Math.max(1, filters.pagina - 1) }, true)} disabled={filters.pagina <= 1 || loading} className="rounded-md border border-zinc-800 px-3 py-1.5 disabled:opacity-40">Anterior</button>
            <span className="min-w-28 text-center text-zinc-400">Página {filters.pagina} de {totalPages}</span>
            <button type="button" onClick={() => setUrl({ pagina: Math.min(totalPages, filters.pagina + 1) }, true)} disabled={filters.pagina >= totalPages || loading} className="rounded-md border border-zinc-800 px-3 py-1.5 disabled:opacity-40">Próxima</button></div>
        </div>
      </section>

      {detailItem ? <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4">
        <div role="dialog" aria-modal="true" aria-labelledby="inconsistencia-detalhe-titulo" className="max-h-[92vh] w-full max-w-3xl overflow-y-auto rounded-xl border border-zinc-800 bg-zinc-950 shadow-2xl">
          <div className="sticky top-0 flex items-start justify-between gap-3 border-b border-zinc-800 bg-zinc-950 px-5 py-4">
            <div><h2 id="inconsistencia-detalhe-titulo" className="text-lg font-semibold">Detalhes da inconsistência</h2><p className="mt-1 text-xs text-zinc-400">Título {detailItem.tituloId}</p></div>
            <button type="button" onClick={() => setDetailItem(null)} className="rounded-md border border-zinc-800 px-3 py-1.5 text-sm">Fechar</button>
          </div>
          <div className="space-y-4 p-5">
            <div className="flex gap-2"><span className={`rounded-full border px-2 py-0.5 text-xs ${isAutomation(detailItem) ? "border-sky-500/30 bg-sky-500/10 text-sky-200" : priorityTone(detailItem.prioridade)}`}>{isAutomation(detailItem) ? "Automação" : priorityLabel(detailItem.prioridade)}</span>
              <span className={`rounded-full border px-2 py-0.5 text-xs ${statusTone(detailItem.status)}`}>{humanize(detailItem.status)}</span></div>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <Detail label="Tipo" value={isAutomation(detailItem) ? "Oportunidade de automação" : humanize(detailItem.tipo)} />
              <Detail label="Valor afetado" value={formatMoney(detailItem.valorTotal)} numeric />
              <Detail label="Fornecedor" value={detailItem.fornecedorNome ?? "Não informado"} />
              <Detail label="Documento" value={detailItem.documento ?? "Não informado"} />
              <Detail label="Data de referência" value={detailItem.dataReferencia ? formatDateBR(detailItem.dataReferencia) : "Não informada"} />
              <Detail label="Classificação atual" value={currentClassification(detailItem)} />
            </div>
            <TextBox title="Diagnóstico" text={detailItem.detalhe || "Sem detalhe adicional."} />
            <TextBox title="Ação sugerida" text={detailItem.sugestao || "Revisar manualmente o lançamento."} sky />
            {detailItem.justificativaIgnorada ? <TextBox title="Justificativa para ignorar" text={detailItem.justificativaIgnorada} /> : null}
          </div>
          <div className="sticky bottom-0 flex justify-end gap-2 border-t border-zinc-800 bg-zinc-950 px-5 py-4">
            <button type="button" onClick={() => setDetailItem(null)} className="rounded-md border border-zinc-800 px-3 py-2 text-sm">Voltar</button>
            {detailItem.status === "IGNORADA" ?
              <button type="button" disabled={canWrite !== true || actionBusy} onClick={() => void reopenItem()} className="rounded-md border border-sky-500/30 bg-sky-500/10 px-3 py-2 text-sm text-sky-200 disabled:opacity-30">{actionBusy ? "Reabrindo…" : "Reabrir"}</button> :
              <button type="button" disabled={canWrite !== true || actionBusy} onClick={() => { setIgnoreJustification(""); setIgnoreOpen(true); }} className="rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm text-zinc-200 disabled:opacity-30">Ignorar com justificativa</button>}
            <button type="button" disabled={!isCorrectable(detailItem, canWrite)} onClick={() => { const item = detailItem; setDetailItem(null); openCorrection([item]); }}
              className="rounded-md bg-zinc-100 px-4 py-2 text-sm font-medium text-zinc-900 disabled:opacity-30">Corrigir lançamento</button>
          </div>
        </div>
      </div> : null}

      {correctionOpen ? <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4">
        <div role="dialog" aria-modal="true" aria-labelledby="inconsistencia-correcao-titulo" className="max-h-[92vh] w-full max-w-4xl overflow-y-auto rounded-xl border border-zinc-800 bg-zinc-950 shadow-2xl">
          <div className="sticky top-0 z-10 flex items-start justify-between gap-3 border-b border-zinc-800 bg-zinc-950 px-5 py-4">
            <div><h2 id="inconsistencia-correcao-titulo" className="text-lg font-semibold">{automationOnly ? "Automatizar classificação" : "Corrigir classificação"}</h2><p className="mt-1 text-xs text-zinc-400">{selectedTitleIds.length} lançamento(ões) · {empresaNome}</p></div>
            <button type="button" onClick={() => setCorrectionOpen(false)} disabled={saving} className="rounded-md border border-zinc-800 px-3 py-1.5 text-sm disabled:opacity-40">Fechar</button>
          </div>
          <div className="space-y-5 p-5">
            <div className="rounded-lg border border-amber-500/25 bg-amber-500/10 p-3 text-xs leading-5 text-amber-100">
              A correção altera somente a classificação financeira. Valores, vencimentos, pagamentos, documentos e vínculos de OS permanecem intactos.
            </div>
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
              <label className="text-xs text-zinc-400">Plano de contas
                <select value={planId} onChange={(event) => setPlanId(event.target.value)} disabled={catalogLoading || saving} className="mt-1 w-full rounded-md border border-zinc-800 bg-black px-3 py-2 text-sm disabled:opacity-50">
                  <option value="">Selecione o plano analítico…</option>{planos.map((row) => <option key={row.id} value={row.id}>{row.codigo} — {row.nome}</option>)}
                </select>
              </label>
              <label className="text-xs text-zinc-400">Centro de custo
                <select value={centerId} onChange={(event) => setCenterId(event.target.value)} disabled={catalogLoading || saving} className="mt-1 w-full rounded-md border border-zinc-800 bg-black px-3 py-2 text-sm disabled:opacity-50">
                  <option value="">Selecione o centro…</option>{centros.map((row) => <option key={row.id} value={row.id}>{row.codigo} — {row.nome}</option>)}
                </select>
              </label>
            </div>
            <label className="block text-xs text-zinc-400">Justificativa da correção
              <textarea value={justification} onChange={(event) => setJustification(event.target.value)} rows={3} minLength={10} disabled={saving} placeholder="Explique o critério usado nesta classificação…"
                className="mt-1 w-full resize-y rounded-md border border-zinc-800 bg-black px-3 py-2 text-sm placeholder:text-zinc-600 disabled:opacity-50" />
              <span className="mt-1 block text-[11px] text-zinc-500">Mínimo de 10 caracteres. A justificativa ficará no histórico de auditoria.</span>
            </label>
            <label className={`flex items-start gap-3 rounded-lg border p-3 ${canCreateRule ? "border-emerald-500/25 bg-emerald-500/5" : "border-zinc-800 bg-black/30 opacity-70"}`}>
              <input type="checkbox" checked={createRule} onChange={(event) => setCreateRule(event.target.checked)} disabled={automationOnly || !canCreateRule || saving} className="mt-0.5 accent-emerald-400" />
              <span><span className="block text-sm font-medium">Criar regra para os próximos lançamentos</span><span className="mt-0.5 block text-xs leading-5 text-zinc-500">{canCreateRule ? "O mesmo motivo será vinculado ao plano e ao centro selecionados." : "Disponível somente para títulos corrigíveis com o mesmo motivo elegível."}</span></span>
            </label>
          </div>
          <div className="sticky bottom-0 flex justify-end gap-2 border-t border-zinc-800 bg-zinc-950 px-5 py-4">
            <button type="button" onClick={() => setCorrectionOpen(false)} disabled={saving} className="rounded-md border border-zinc-800 px-3 py-2 text-sm disabled:opacity-40">Cancelar</button>
            <button type="button" onClick={() => void saveCorrection()} disabled={saving || !planId || !centerId || justification.trim().length < 10}
              className="rounded-md bg-zinc-100 px-4 py-2 text-sm font-medium text-zinc-900 disabled:opacity-30">{saving ? (automationOnly ? "Automatizando…" : "Corrigindo…") : `${automationOnly ? "Automatizar" : "Corrigir"} ${selectedTitleIds.length} lançamento(ões)`}</button>
          </div>
        </div>
      </div> : null}

      {ignoreOpen && detailItem ? <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/80 p-4">
        <div role="dialog" aria-modal="true" aria-labelledby="inconsistencia-ignorar-titulo" className="w-full max-w-xl rounded-xl border border-zinc-800 bg-zinc-950 shadow-2xl">
          <div className="border-b border-zinc-800 px-5 py-4"><h2 id="inconsistencia-ignorar-titulo" className="text-lg font-semibold">Ignorar inconsistência</h2><p className="mt-1 text-xs text-zinc-400">{humanize(detailItem.tipo)} · título {detailItem.tituloId.slice(0, 8)}</p></div>
          <div className="space-y-3 p-5">
            <div className="rounded-lg border border-amber-500/25 bg-amber-500/10 p-3 text-xs leading-5 text-amber-100">A ocorrência sairá da fila pendente, mas continuará disponível no filtro “Ignoradas”. Se o lançamento mudar, o fingerprint permitirá uma nova avaliação.</div>
            <label className="block text-xs text-zinc-400">Justificativa
              <textarea value={ignoreJustification} onChange={(event) => setIgnoreJustification(event.target.value)} minLength={10} rows={3} disabled={actionBusy} placeholder="Explique por que esta ocorrência não exige correção…" className="mt-1 w-full resize-y rounded-md border border-zinc-800 bg-black px-3 py-2 text-sm placeholder:text-zinc-600 disabled:opacity-40" />
              <span className="mt-1 block text-[11px] text-zinc-500">Mínimo de 10 caracteres.</span>
            </label>
          </div>
          <div className="flex justify-end gap-2 border-t border-zinc-800 px-5 py-4"><button type="button" disabled={actionBusy} onClick={() => setIgnoreOpen(false)} className="rounded-md border border-zinc-800 px-3 py-2 text-sm disabled:opacity-40">Cancelar</button>
            <button type="button" disabled={actionBusy || ignoreJustification.trim().length < 10} onClick={() => void ignoreItem()} className="rounded-md bg-zinc-100 px-4 py-2 text-sm font-medium text-zinc-900 disabled:opacity-30">{actionBusy ? "Registrando…" : "Confirmar e ignorar"}</button></div>
        </div>
      </div> : null}

      <div className="sr-only" aria-live="polite">{loading ? "Carregando inconsistências financeiras." : `${payload.total} inconsistências encontradas.`}</div>
    </main>
  );
}

function FilterSelect({ label, value, options, onChange, disabled = false }: {
  label: string; value: string; options: Array<{ value: string; label: string }>;
  onChange: (value: string) => void; disabled?: boolean;
}) {
  return <label className="block min-w-[130px] text-xs text-zinc-400">{label}
    <select value={value} disabled={disabled} onChange={(event) => onChange(event.target.value)} className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-900 px-3 py-2 text-sm text-zinc-100 disabled:opacity-40">
      {options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
    </select>
  </label>;
}

function MetricCard({ title, value, subtitle, tone = "neutral" }: {
  title: string; value: string; subtitle: string; tone?: "neutral" | "emerald" | "amber" | "rose" | "sky";
}) {
  const valueTone = tone === "emerald" ? "text-emerald-200" : tone === "amber" ? "text-amber-200" : tone === "rose" ? "text-rose-200" : tone === "sky" ? "text-sky-200" : "text-zinc-100";
  return <article className={`rounded-xl border bg-zinc-950 p-4 ${tone === "sky" ? "border-sky-500/20" : "border-zinc-800"}`}>
    <div className="text-xs font-medium uppercase tracking-wide text-zinc-500">{title}</div>
    <div className={`mt-2 text-xl font-semibold tabular-nums ${valueTone}`}>{value}</div>
    <div className="mt-1 text-xs leading-5 text-zinc-500">{subtitle}</div>
  </article>;
}

function Detail({ label, value, numeric = false }: { label: string; value: string; numeric?: boolean }) {
  return <div className="rounded-lg border border-zinc-800 bg-black/30 p-3"><div className="text-xs text-zinc-500">{label}</div><div className={`mt-1 text-sm font-medium ${numeric ? "text-right tabular-nums" : ""}`}>{value}</div></div>;
}

function TextBox({ title, text: body, sky = false }: { title: string; text: string; sky?: boolean }) {
  return <div className={`rounded-lg border p-4 ${sky ? "border-sky-500/25 bg-sky-500/10" : "border-zinc-800 bg-black/30"}`}><div className={`text-xs font-medium uppercase tracking-wide ${sky ? "text-sky-300" : "text-zinc-500"}`}>{title}</div><div className={`mt-2 text-sm leading-6 ${sky ? "text-sky-100" : "text-zinc-200"}`}>{body}</div></div>;
}
