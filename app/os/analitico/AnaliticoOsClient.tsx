"use client";

import Link from "next/link";
import { useEffect, useMemo, useState, type ReactNode } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { useSessionReady } from "@/lib/auth/useSessionReady";
import { getOsListAccess } from "@/lib/auth/osAccess";
import { formatMoneyBR } from "@/lib/decimal";
import { getHorasTrabalhadasEfetivas, getValorTotalEfetivo } from "@/lib/hh/hhLancamentosCalc";
import { fetchFaturadoByOs } from "@/lib/os/faturadoPorOs";

type ViewMode = "mes" | "mes-cliente" | "ano" | "ano-cliente";
type Granularity = "mes" | "ano";
type StatusScope = "em_andamento" | "concluida" | "todas";
type RankingOrder = "valor" | "os" | "ticket" | "nome";
type RangeMode = "anos" | "ultimos-12";

type OsSourceRow = {
  id: number;
  numero_os: string | null;
  cliente_nome: string | null;
  cliente_id: number | null;
  status: "aberta" | "em_andamento" | "concluida" | "cancelada" | null;
  data_abertura: string | null;
  data_conclusao: string | null;
  orcado: number | string | null;
  usa_relatorio_hh: boolean | null;
};

type ClienteRow = {
  id: number;
  nome: string | null;
};

type HhFallbackRow = {
  os_id: number;
  total_hh: number | string | null;
};

type HhCalcRow = {
  os_id: number | null;
  entrada_1: string | null;
  saida_1: string | null;
  entrada_2: string | null;
  saida_2: string | null;
  hora_entrada: string | null;
  hora_saida: string | null;
  horas_trabalhadas: number | null;
  valor_hora: number | null;
  valor_total: number | null;
};

type OsAnalitico = {
  id: number;
  clientKey: string;
  numeroOs: string;
  clienteNome: string;
  status: "em_andamento" | "concluida";
  referenceDate: string;
  year: number;
  month: number;
  valor: number;
};

type ClienteMesResumo = {
  clienteKey: string;
  clienteNome: string;
  valores: number[];
  quantidades: number[];
  totalValor: number;
  quantidade: number;
};

type ClienteAnoResumo = {
  clienteKey: string;
  clienteNome: string;
  valores: number[];
  quantidades: number[];
  totalValor: number;
  quantidade: number;
};

type ClienteRanking = {
  clienteKey: string;
  clienteNome: string;
  quantidade: number;
  totalValor: number;
  ticketMedio: number;
};

type TemporalBucket = {
  key: string;
  label: string;
  totalValor: number;
  quantidade: number;
  dominantOs: string[];
};

type AgingBucket = {
  key: "ate-30" | "30-90" | "90-365" | "mais-365";
  label: string;
  totalValor: number;
  quantidade: number;
  rows: OsAnalitico[];
};

const BASE_YEAR = 2017;
const FETCH_BATCH_SIZE = 1000;
const IN_BATCH_SIZE = 200;
const DEFAULT_TOP_N = 20;
const MONTH_LABELS = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"] as const;
const FIXED_TENANT_ID = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
const FIXED_EMPRESA_ID = "f0e74f49-a127-46b4-901b-f7b37e43c690";

const statusScopeLabels: Record<StatusScope, string> = {
  em_andamento: "Em andamento",
  concluida: "Concluídas",
  todas: "Todas",
};

function n(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

function round2(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function formatCount(value: number): string {
  return Math.trunc(Number(value || 0)).toLocaleString("pt-BR");
}

function parseViewMode(value: string | null): ViewMode {
  if (value === "mes") return "mes";
  if (value === "mes-cliente") return "mes-cliente";
  if (value === "ano") return "ano";
  if (value === "ano-cliente") return "ano-cliente";
  return "mes";
}

function parseRankingOrder(value: string | null): RankingOrder {
  if (value === "os" || value === "ticket" || value === "nome") return value;
  return "valor";
}

function parseStatusScope(value: string | null): StatusScope {
  if (value === "em_andamento") return "em_andamento";
  if (value === "concluida") return "concluida";
  if (value === "todas") return "todas";
  return "em_andamento";
}

function parsePositiveInt(value: string | null, fallback: number): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.trunc(parsed);
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function toDateOnly(value: string | null | undefined): string | null {
  const raw = String(value ?? "").slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(raw) ? raw : null;
}

function formatDateBR(value: string | null | undefined): string {
  const date = toDateOnly(value);
  if (!date) return "-";
  return `${date.slice(8, 10)}/${date.slice(5, 7)}/${date.slice(0, 4)}`;
}

function resolveReferenceDate(row: OsSourceRow): string | null {
  return toDateOnly(row.data_abertura);
}

function isoToday(): string {
  const date = new Date();
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function rollingTwelveMonthStart(): string {
  const date = new Date();
  date.setDate(1);
  date.setMonth(date.getMonth() - 11);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  return `${year}-${month}-01`;
}

function daysSince(iso: string): number {
  const [year, month, day] = iso.slice(0, 10).split("-").map(Number);
  const start = new Date(year, month - 1, day).getTime();
  const today = new Date();
  const end = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
  return Math.max(0, Math.floor((end - start) / 86400000));
}

function formatCompactMoney(value: number): string {
  const abs = Math.abs(value);
  if (abs >= 1_000_000) return `R$ ${(value / 1_000_000).toLocaleString("pt-BR", { maximumFractionDigits: 1 })} mi`;
  if (abs >= 1_000) return `R$ ${(value / 1_000).toLocaleString("pt-BR", { maximumFractionDigits: 0 })} mil`;
  return formatMoneyBR(value);
}

function formatPercent(value: number): string {
  return `${value.toLocaleString("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`;
}

function formatMonthYear(key: string): string {
  const [year, month] = key.split("-").map(Number);
  return new Intl.DateTimeFormat("pt-BR", { month: "short", year: "numeric" })
    .format(new Date(year, month - 1, 1))
    .replace(" de ", "/")
    .replace(".", "");
}

function getClientKey(row: { cliente_id: number | null; cliente_nome: string | null }): string {
  if (typeof row.cliente_id === "number" && Number.isFinite(row.cliente_id) && row.cliente_id > 0) {
    return `id:${row.cliente_id}`;
  }

  const rawName = String(row.cliente_nome ?? "").trim() || "(Sem cliente)";
  return `name:${rawName}`;
}

function pickPreferredClientName(options: Map<string, { count: number; total: number }>): string {
  return Array.from(options.entries())
    .sort((left, right) => {
      const countDiff = right[1].count - left[1].count;
      if (countDiff !== 0) return countDiff;

      const totalDiff = right[1].total - left[1].total;
      if (totalDiff !== 0) return totalDiff;

      const lengthDiff = right[0].length - left[0].length;
      if (lengthDiff !== 0) return lengthDiff;

      return left[0].localeCompare(right[0], "pt-BR");
    })[0]?.[0] ?? "(Sem cliente)";
}

async function fetchClientesByIds(params: {
  supabase: ReturnType<typeof supabaseBrowser>;
  tenantId: string;
  empresaId: string;
  ids: number[];
}): Promise<Record<number, string>> {
  const out: Record<number, string> = {};

  for (let offset = 0; offset < params.ids.length; offset += IN_BATCH_SIZE) {
    const chunk = params.ids.slice(offset, offset + IN_BATCH_SIZE);
    if (!chunk.length) continue;

    const { data, error } = await applyTenantEmpresa(
      params.supabase.from("clientes").select("id,nome").in("id", chunk),
      params.tenantId,
      params.empresaId
    ).returns<ClienteRow[]>();

    if (error) throw error;

    for (const row of data ?? []) {
      const id = Number(row.id);
      if (!Number.isFinite(id)) continue;
      const nome = String(row.nome ?? "").trim();
      if (nome) out[id] = nome;
    }
  }

  return out;
}

async function fetchHhFallbackTotals(params: {
  supabase: ReturnType<typeof supabaseBrowser>;
  ids: number[];
}): Promise<Record<number, number>> {
  const out: Record<number, number> = {};

  for (let offset = 0; offset < params.ids.length; offset += IN_BATCH_SIZE) {
    const chunk = params.ids.slice(offset, offset + IN_BATCH_SIZE);
    if (!chunk.length) continue;

    const { data, error } = await params.supabase
      .from("vw_hh_total_os")
      .select("os_id,total_hh")
      .in("os_id", chunk)
      .returns<HhFallbackRow[]>();

    if (error) throw error;

    for (const row of data ?? []) {
      const osId = Number(row.os_id);
      if (!Number.isFinite(osId)) continue;
      out[osId] = n(row.total_hh);
    }
  }

  return out;
}

async function fetchHhPedidoTotals(params: {
  supabase: ReturnType<typeof supabaseBrowser>;
  tenantId: string;
  empresaId: string;
  ids: number[];
}): Promise<Record<number, number>> {
  const out: Record<number, number> = {};

  for (let offset = 0; offset < params.ids.length; offset += IN_BATCH_SIZE) {
    const chunk = params.ids.slice(offset, offset + IN_BATCH_SIZE);
    if (!chunk.length) continue;

    const { data, error } = await applyTenantEmpresa(
      params.supabase
        .from("hh_lancamentos")
        .select(
          "os_id,entrada_1,saida_1,entrada_2,saida_2,hora_entrada,hora_saida,horas_trabalhadas,valor_hora,valor_total"
        )
        .in("os_id", chunk),
      params.tenantId,
      params.empresaId
    ).returns<HhCalcRow[]>();

    if (error) throw error;

    for (const row of data ?? []) {
      const osId = Number(row.os_id);
      if (!Number.isFinite(osId)) continue;

      const horasEfetivas = getHorasTrabalhadasEfetivas(row);
      const total = getValorTotalEfetivo(row, horasEfetivas);
      out[osId] = Math.round(((out[osId] ?? 0) + total) * 100) / 100;
    }
  }

  return out;
}

function StatCard({
  title,
  value,
  subtitle,
  hero = false,
  warning = false,
}: {
  title: string;
  value: string;
  subtitle?: string;
  hero?: boolean;
  warning?: boolean;
}) {
  return (
    <div className={`oa-stat-card${hero ? " oa-stat-card-hero" : ""}`}>
      <div className="oa-stat-label">{title}</div>
      <div className="oa-stat-value">{value}</div>
      {subtitle ? <div className={`oa-stat-caption${warning ? " oa-stat-caption-warning" : ""}`}>{subtitle}</div> : null}
    </div>
  );
}

function TabButton({
  active,
  onClick,
  label,
}: {
  active: boolean;
  onClick: () => void;
  label: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`oa-segment-button${active ? " is-active" : ""}`}
      aria-pressed={active}
    >
      {label}
    </button>
  );
}

function StatusButton({
  active,
  onClick,
  label,
}: {
  active: boolean;
  onClick: () => void;
  label: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`oa-status-button${active ? " is-active" : ""}`}
      aria-pressed={active}
    >
      <span className="oa-status-dot" aria-hidden="true" />
      {label}
    </button>
  );
}

function TableCard({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children: ReactNode;
}) {
  return (
    <section className="oa-card">
      <div className="oa-card-head">
        <div className="oa-card-title">{title}</div>
        {subtitle ? <div className="oa-card-subtitle">{subtitle}</div> : null}
      </div>
      <div className="oa-table-scroll">{children}</div>
    </section>
  );
}

function MetricBlock({
  value,
  count,
  hideValue,
  strong = false,
}: {
  value: number;
  count: number;
  hideValue: boolean;
  strong?: boolean;
}) {
  const valueClass = strong ? "oa-metric-value is-strong" : "oa-metric-value";
  const countClass = strong ? "oa-metric-count is-strong" : "oa-metric-count";

  if (hideValue) {
    return <div className={valueClass}>{formatCount(count)}</div>;
  }

  return (
    <>
      <div className={valueClass}>{formatMoneyBR(value)}</div>
      <div className={countClass}>{formatCount(count)} OS</div>
    </>
  );
}

export default function AnaliticoOsClient() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const te = useTenantEmpresa();
  const { has } = usePermissions();
  const { session, sessionReady } = useSessionReady();
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

  const currentYear = new Date().getFullYear();
  const initialFromParam = searchParams.get("de") ?? searchParams.get("from");
  const initialToParam = searchParams.get("ate") ?? searchParams.get("to");
  const initialFromYear = clamp(parsePositiveInt(initialFromParam?.slice(0, 4) ?? null, BASE_YEAR), BASE_YEAR, currentYear);
  const initialToYear = clamp(parsePositiveInt(initialToParam?.slice(0, 4) ?? null, currentYear), BASE_YEAR, currentYear);
  const normalizedInitialFromYear = Math.min(initialFromYear, initialToYear);
  const normalizedInitialToYear = Math.max(initialFromYear, initialToYear);
  const initialFocusYear = clamp(
    parsePositiveInt(searchParams.get("focus"), normalizedInitialToYear),
    normalizedInitialFromYear,
    normalizedInitialToYear
  );

  const initialGranularity: Granularity = searchParams.get("granularidade") === "ano" ? "ano" : "mes";
  const initialOpenByClient = searchParams.get("abrir_cliente") === "1";
  const initialView = searchParams.has("granularidade")
    ? (`${initialGranularity}${initialOpenByClient ? "-cliente" : ""}` as ViewMode)
    : parseViewMode(searchParams.get("view"));
  const [view, setView] = useState<ViewMode>(initialView);
  const [statusScope, setStatusScope] = useState<StatusScope>(parseStatusScope(searchParams.get("status")));
  const [fromYear, setFromYear] = useState<number>(normalizedInitialFromYear);
  const [toYear, setToYear] = useState<number>(normalizedInitialToYear);
  const [rangeMode, setRangeMode] = useState<RangeMode>(
    searchParams.get("periodo") === "ultimos-12" || String(initialFromParam ?? "").length > 4 ? "ultimos-12" : "anos"
  );
  const [focusYear, setFocusYear] = useState<number>(initialFocusYear);
  const [clientQuery, setClientQuery] = useState<string>(searchParams.get("cliente") ?? "");
  const [topN, setTopN] = useState<number>(clamp(parsePositiveInt(searchParams.get("top"), DEFAULT_TOP_N), 5, 200));
  const [rankingOrder, setRankingOrder] = useState<RankingOrder>(parseRankingOrder(searchParams.get("ordem")));

  const [rows, setRows] = useState<OsSourceRow[]>([]);
  const [clientesById, setClientesById] = useState<Record<number, string>>({});
  const [hhFallbackByOs, setHhFallbackByOs] = useState<Record<number, number>>({});
  const [hhPedidoByOs, setHhPedidoByOs] = useState<Record<number, number>>({});
  const [faturadoByOs, setFaturadoByOs] = useState<Record<number, number>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const effectiveTenantId = te.tenantId ?? FIXED_TENANT_ID;
  const effectiveEmpresaId = te.empresaId ?? FIXED_EMPRESA_ID;

  const empresaPapel = useMemo(() => {
    const byId = (te.empresas ?? []).find((empresa) => empresa.id === effectiveEmpresaId) ?? null;
    if (byId?.papel) return byId.papel;
    if (te.empresa?.id === effectiveEmpresaId) return te.empresa?.papel ?? null;
    return null;
  }, [effectiveEmpresaId, te.empresa, te.empresas]);

  const canReadOs = Boolean(has("os.read"));
  const canWriteOs = Boolean(has("os.write"));
  const osAccess = useMemo(() => getOsListAccess(empresaPapel), [empresaPapel]);
  const canView = canReadOs || canWriteOs || osAccess.canView;
  const hideValorPedido = osAccess.hideValorPedido;

  const ready = sessionReady && Boolean(session?.access_token) && Boolean(supabase) && canView;
  const granularity: Granularity = view.startsWith("ano") ? "ano" : "mes";
  const openByClient = view.endsWith("-cliente");

  const yearOptions = useMemo(() => {
    const years: number[] = [];
    for (let year = currentYear; year >= BASE_YEAR; year -= 1) years.push(year);
    return years;
  }, [currentYear]);

  const years = useMemo(() => {
    const list: number[] = [];
    for (let year = fromYear; year <= toYear; year += 1) list.push(year);
    return list;
  }, [fromYear, toYear]);
  const effectiveFocusYear = clamp(focusYear, fromYear, toYear);

  const rangeBounds = useMemo(
    () =>
      rangeMode === "ultimos-12"
        ? { from: rollingTwelveMonthStart(), to: isoToday() }
        : { from: `${fromYear}-01-01`, to: `${toYear}-12-31` },
    [fromYear, rangeMode, toYear]
  );

  useEffect(() => {
    if (!sessionReady || te.loading) return;
    if (!canView) router.replace("/forbidden");
  }, [canView, router, sessionReady, te.loading]);

  useEffect(() => {
    const params = new URLSearchParams();
    params.set("granularidade", granularity);
    if (openByClient) params.set("abrir_cliente", "1");
    params.set("status", statusScope);
    params.set("de", rangeMode === "ultimos-12" ? rangeBounds.from : String(fromYear));
    params.set("ate", rangeMode === "ultimos-12" ? rangeBounds.to : String(toYear));
    if (rangeMode === "ultimos-12") params.set("periodo", "ultimos-12");
    if (view === "mes-cliente") params.set("focus", String(effectiveFocusYear));
    if (clientQuery.trim()) params.set("cliente", clientQuery.trim());
    if (topN !== DEFAULT_TOP_N) params.set("top", String(topN));
    if (rankingOrder !== "valor") params.set("ordem", rankingOrder);

    const nextQuery = params.toString();
    const currentQuery = searchParams.toString();
    if (nextQuery !== currentQuery) {
      router.replace(nextQuery ? `${pathname}?${nextQuery}` : pathname);
    }
  }, [clientQuery, effectiveFocusYear, fromYear, granularity, openByClient, pathname, rangeBounds.from, rangeBounds.to, rangeMode, rankingOrder, router, searchParams, statusScope, toYear, topN, view]);

  useEffect(() => {
    if (!ready || !supabase) return;

    let cancelled = false;

    const run = async () => {
      setLoading(true);
      setError(null);

      try {
        const nextRows: OsSourceRow[] = [];
        let offset = 0;

        while (true) {
          let query = applyTenantEmpresa(
            supabase
              .from("ordens_servico")
              .select("id,numero_os,cliente_nome,cliente_id,status,data_abertura,data_conclusao,orcado,usa_relatorio_hh")
              .eq("tipo_documento", "OS")
              .order("id", { ascending: true })
              .range(offset, offset + FETCH_BATCH_SIZE - 1),
            effectiveTenantId,
            effectiveEmpresaId
          );

          if (statusScope === "todas") {
            query = query.in("status", ["em_andamento", "concluida"]);
          } else {
            query = query.eq("status", statusScope);
          }

          const { data, error: queryError } = await query.returns<OsSourceRow[]>();
          if (queryError) throw queryError;

          nextRows.push(...(data ?? []));
          if ((data ?? []).length < FETCH_BATCH_SIZE) break;
          offset += FETCH_BATCH_SIZE;
        }

        const hhOsIds = nextRows
          .filter((row) => Boolean(row.usa_relatorio_hh))
          .map((row) => Number(row.id))
          .filter((value) => Number.isFinite(value) && value > 0);

        const clienteIds = Array.from(
          new Set(
            nextRows
              .map((row) => (typeof row.cliente_id === "number" ? row.cliente_id : null))
              .filter((value): value is number => typeof value === "number" && Number.isFinite(value))
          )
        );

        const [nextHhFallbackByOs, nextHhPedidoByOs, nextClientesById, nextFaturadoByOs] = await Promise.all([
          hhOsIds.length ? fetchHhFallbackTotals({ supabase, ids: hhOsIds }) : Promise.resolve({}),
          hhOsIds.length
            ? fetchHhPedidoTotals({
                supabase,
                tenantId: effectiveTenantId,
                empresaId: effectiveEmpresaId,
                ids: hhOsIds,
              })
            : Promise.resolve({}),
          clienteIds.length
            ? fetchClientesByIds({
                supabase,
                tenantId: effectiveTenantId,
                empresaId: effectiveEmpresaId,
                ids: clienteIds,
              }).catch(() => ({}))
            : Promise.resolve({}),
          statusScope === "concluida"
            ? Promise.resolve({})
            : fetchFaturadoByOs({
                supabase,
                tenantId: effectiveTenantId,
                empresaId: effectiveEmpresaId,
              }),
        ]);

        if (cancelled) return;

        setRows(nextRows);
        setClientesById(nextClientesById);
        setHhFallbackByOs(nextHhFallbackByOs);
        setHhPedidoByOs(nextHhPedidoByOs);
        setFaturadoByOs(nextFaturadoByOs);
      } catch (loadError: unknown) {
        if (cancelled) return;
        setRows([]);
        setClientesById({});
        setHhFallbackByOs({});
        setHhPedidoByOs({});
        setFaturadoByOs({});
        setError(loadError instanceof Error ? loadError.message : "Erro ao carregar o analítico de OS.");
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    void run();

    return () => {
      cancelled = true;
    };
  }, [effectiveEmpresaId, effectiveTenantId, ready, statusScope, supabase]);

  const ordens = useMemo<OsAnalitico[]>(() => {
    const rawRows = rows
      .map((row) => {
        const referenceDate = resolveReferenceDate(row);
        if (!referenceDate) return null;

        const year = Number(referenceDate.slice(0, 4));
        const month = Number(referenceDate.slice(5, 7));
        if (!Number.isFinite(year) || !Number.isFinite(month) || month < 1 || month > 12) return null;
        if (referenceDate < rangeBounds.from || referenceDate > rangeBounds.to) return null;
        if (row.status !== "em_andamento" && row.status !== "concluida") return null;

        const clientKey = getClientKey(row);
        const clienteNomeCadastro =
          typeof row.cliente_id === "number" && Number.isFinite(row.cliente_id) ? clientesById[row.cliente_id] : undefined;
        const clienteNome = clienteNomeCadastro || String(row.cliente_nome ?? "").trim() || "(Sem cliente)";
        const valorBase = row.usa_relatorio_hh ? hhPedidoByOs[row.id] ?? hhFallbackByOs[row.id] ?? 0 : n(row.orcado);
        const valorFaturado = round2(faturadoByOs[row.id] ?? 0);
        const valor = row.status === "em_andamento" ? Math.max(0, round2(valorBase - valorFaturado)) : valorBase;

        if (row.status === "em_andamento" && valor <= 0.009) return null;

        return {
          id: row.id,
          clientKey,
          numeroOs: String(row.numero_os ?? row.id),
          clienteNome,
          status: row.status,
          referenceDate,
          year,
          month,
          valor,
        };
      })
      .filter((row): row is OsAnalitico => Boolean(row));

    const namesByKey = new Map<string, Map<string, { count: number; total: number }>>();
    for (const row of rawRows) {
      const bucket = namesByKey.get(row.clientKey) ?? new Map<string, { count: number; total: number }>();
      const current = bucket.get(row.clienteNome) ?? { count: 0, total: 0 };
      current.count += 1;
      current.total += row.valor;
      bucket.set(row.clienteNome, current);
      namesByKey.set(row.clientKey, bucket);
    }

    const preferredNameByKey = new Map<string, string>();
    for (const [clientKey, names] of namesByKey.entries()) {
      preferredNameByKey.set(clientKey, pickPreferredClientName(names));
    }

    return rawRows.map((row) => ({
      ...row,
      clienteNome: preferredNameByKey.get(row.clientKey) ?? row.clienteNome,
    }));
  }, [clientesById, faturadoByOs, hhFallbackByOs, hhPedidoByOs, rangeBounds.from, rangeBounds.to, rows]);

  const osExcedentes = useMemo(() => {
    return rows
      .filter((row) => row.status === "em_andamento")
      .map((row) => {
        const clienteNomeCadastro =
          typeof row.cliente_id === "number" && Number.isFinite(row.cliente_id) ? clientesById[row.cliente_id] : undefined;
        const clienteNome = clienteNomeCadastro || String(row.cliente_nome ?? "").trim() || "(Sem cliente)";
        const valorPedido = row.usa_relatorio_hh ? hhPedidoByOs[row.id] ?? hhFallbackByOs[row.id] ?? 0 : n(row.orcado);
        const valorFaturado = round2(faturadoByOs[row.id] ?? 0);
        const excesso = round2(valorFaturado - valorPedido);
        return {
          id: row.id,
          numeroOs: String(row.numero_os ?? row.id),
          clienteNome,
          valorPedido,
          valorFaturado,
          excesso,
        };
      })
      .filter((row) => row.excesso > 0.009)
      .sort((a, b) => b.excesso - a.excesso);
  }, [clientesById, faturadoByOs, hhFallbackByOs, hhPedidoByOs, rows]);

  const filteredClientTerm = clientQuery.trim().toLowerCase();
  const filteredOrdens = useMemo(
    () =>
      filteredClientTerm
        ? ordens.filter((row) => row.clienteNome.toLowerCase() === filteredClientTerm)
        : ordens,
    [filteredClientTerm, ordens]
  );

  const totalValor = useMemo(() => filteredOrdens.reduce((acc, row) => acc + row.valor, 0), [filteredOrdens]);
  const totalOs = filteredOrdens.length;
  const clientesAtivos = useMemo(() => new Set(filteredOrdens.map((row) => row.clientKey)).size, [filteredOrdens]);
  const ticketMedio = totalOs > 0 ? totalValor / totalOs : 0;
  const periodLabel =
    rangeMode === "ultimos-12"
      ? `${formatMonthYear(rangeBounds.from.slice(0, 7))} – ${formatMonthYear(rangeBounds.to.slice(0, 7))}`
      : fromYear === toYear
        ? String(fromYear)
        : `${fromYear} – ${toYear}`;
  const valorResumoTitulo = statusScope === "em_andamento" ? "Valor a faturar no período" : "Valor total no período";
  const valorResumoSubtitulo =
    statusScope === "em_andamento"
      ? `${formatCount(totalOs)} OS em andamento · faturamento vinculado já descontado`
      : `${formatCount(totalOs)} OS ${statusScopeLabels[statusScope].toLocaleLowerCase("pt-BR")} · ${periodLabel}`;

  const rankingsBase = useMemo<ClienteRanking[]>(() => {
    const byClient = new Map<string, ClienteRanking>();

    for (const row of filteredOrdens) {
      const current =
        byClient.get(row.clientKey) ??
        {
          clienteKey: row.clientKey,
          clienteNome: row.clienteNome,
          quantidade: 0,
          totalValor: 0,
          ticketMedio: 0,
        };
      current.quantidade += 1;
      current.totalValor += row.valor;
      current.ticketMedio = current.quantidade > 0 ? current.totalValor / current.quantidade : 0;
      if (!current.clienteNome && row.clienteNome) current.clienteNome = row.clienteNome;
      byClient.set(row.clientKey, current);
    }

    return Array.from(byClient.values());
  }, [filteredOrdens]);

  const clientesOrdenados = useMemo(() => {
    const next = [...rankingsBase];
    next.sort((a, b) => {
      if (hideValorPedido) return b.quantidade - a.quantidade || a.clienteNome.localeCompare(b.clienteNome, "pt-BR");
      if (rankingOrder === "os") return b.quantidade - a.quantidade || b.totalValor - a.totalValor;
      if (rankingOrder === "ticket") return b.ticketMedio - a.ticketMedio || b.totalValor - a.totalValor;
      if (rankingOrder === "nome") return a.clienteNome.localeCompare(b.clienteNome, "pt-BR");
      return b.totalValor - a.totalValor || b.quantidade - a.quantidade;
    });
    return next;
  }, [hideValorPedido, rankingOrder, rankingsBase]);

  const clientesPorValor = useMemo(
    () => [...rankingsBase].sort((a, b) => b.totalValor - a.totalValor || b.quantidade - a.quantidade),
    [rankingsBase]
  );
  const maioresOs = useMemo(
    () =>
      [...filteredOrdens]
        .sort((a, b) => b.valor - a.valor || b.referenceDate.localeCompare(a.referenceDate) || a.numeroOs.localeCompare(b.numeroOs))
        .slice(0, topN),
    [filteredOrdens, topN]
  );

  const topTwoOsValue = useMemo(() => [...filteredOrdens].sort((a, b) => b.valor - a.valor).slice(0, 2).reduce((sum, row) => sum + row.valor, 0), [filteredOrdens]);
  const topTwoOsShare = totalValor > 0 ? (topTwoOsValue / totalValor) * 100 : 0;
  const topTwoClientsValue = clientesPorValor.slice(0, 2).reduce((sum, row) => sum + row.totalValor, 0);
  const topTwoClientsShare = totalValor > 0 ? (topTwoClientsValue / totalValor) * 100 : 0;

  const yearIndexMap = useMemo(() => new Map(years.map((year, index) => [year, index])), [years]);

  const monthClientRows = useMemo<ClienteMesResumo[]>(() => {
    const byClient = new Map<string, ClienteMesResumo>();

    for (const row of filteredOrdens) {
      if (row.year !== effectiveFocusYear) continue;

      const current =
        byClient.get(row.clientKey) ??
        {
          clienteKey: row.clientKey,
          clienteNome: row.clienteNome,
          valores: Array.from({ length: 12 }, () => 0),
          quantidades: Array.from({ length: 12 }, () => 0),
          totalValor: 0,
          quantidade: 0,
        };

      current.valores[row.month - 1] += row.valor;
      current.quantidades[row.month - 1] += 1;
      current.totalValor += row.valor;
      current.quantidade += 1;
      if (!current.clienteNome && row.clienteNome) current.clienteNome = row.clienteNome;
      byClient.set(row.clientKey, current);
    }

    return Array.from(byClient.values())
      .sort((a, b) =>
        hideValorPedido
          ? b.quantidade - a.quantidade || b.totalValor - a.totalValor || a.clienteNome.localeCompare(b.clienteNome)
          : b.totalValor - a.totalValor || b.quantidade - a.quantidade || a.clienteNome.localeCompare(b.clienteNome)
      )
      .slice(0, topN);
  }, [effectiveFocusYear, filteredOrdens, hideValorPedido, topN]);

  const yearClientRows = useMemo<ClienteAnoResumo[]>(() => {
    const byClient = new Map<string, ClienteAnoResumo>();

    for (const row of filteredOrdens) {
      const yearIndex = yearIndexMap.get(row.year);
      if (yearIndex === undefined) continue;

      const current =
        byClient.get(row.clientKey) ??
        {
          clienteKey: row.clientKey,
          clienteNome: row.clienteNome,
          valores: Array.from({ length: years.length }, () => 0),
          quantidades: Array.from({ length: years.length }, () => 0),
          totalValor: 0,
          quantidade: 0,
        };

      current.valores[yearIndex] += row.valor;
      current.quantidades[yearIndex] += 1;
      current.totalValor += row.valor;
      current.quantidade += 1;
      if (!current.clienteNome && row.clienteNome) current.clienteNome = row.clienteNome;
      byClient.set(row.clientKey, current);
    }

    return Array.from(byClient.values())
      .sort((a, b) =>
        hideValorPedido
          ? b.quantidade - a.quantidade || b.totalValor - a.totalValor || a.clienteNome.localeCompare(b.clienteNome)
          : b.totalValor - a.totalValor || b.quantidade - a.quantidade || a.clienteNome.localeCompare(b.clienteNome)
      )
      .slice(0, topN);
  }, [filteredOrdens, hideValorPedido, topN, yearIndexMap, years.length]);

  const subtotalMesCliente = useMemo(
    () =>
      monthClientRows.reduce(
        (acc, row) => {
          for (let index = 0; index < 12; index += 1) {
            acc.valores[index] += row.valores[index] ?? 0;
            acc.quantidades[index] += row.quantidades[index] ?? 0;
          }
          acc.valores[12] += row.totalValor;
          acc.quantidades[12] += row.quantidade;
          return acc;
        },
        {
          valores: Array.from({ length: 13 }, () => 0),
          quantidades: Array.from({ length: 13 }, () => 0),
        }
      ),
    [monthClientRows]
  );

  const subtotalAnoCliente = useMemo(
    () =>
      yearClientRows.reduce(
        (acc, row) => {
          for (let index = 0; index < years.length; index += 1) {
            acc.valores[index] += row.valores[index] ?? 0;
            acc.quantidades[index] += row.quantidades[index] ?? 0;
          }
          acc.valores[years.length] += row.totalValor;
          acc.quantidades[years.length] += row.quantidade;
          return acc;
        },
        {
          valores: Array.from({ length: years.length + 1 }, () => 0),
          quantidades: Array.from({ length: years.length + 1 }, () => 0),
        }
      ),
    [yearClientRows, years.length]
  );

  const clientOptions = useMemo(
    () => Array.from(new Set(ordens.map((row) => row.clienteNome))).sort((a, b) => a.localeCompare(b, "pt-BR")),
    [ordens]
  );

  const temporalBuckets = useMemo<TemporalBucket[]>(() => {
    const grouped = new Map<string, OsAnalitico[]>();
    for (const row of filteredOrdens) {
      const key = granularity === "mes" ? row.referenceDate.slice(0, 7) : String(row.year);
      const bucket = grouped.get(key) ?? [];
      bucket.push(row);
      grouped.set(key, bucket);
    }

    return Array.from(grouped.entries())
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, bucketRows]) => {
        const total = bucketRows.reduce((sum, row) => sum + row.valor, 0);
        const sortedRows = [...bucketRows].sort((a, b) => b.valor - a.valor);
        const dominant = sortedRows.filter((row) => total > 0 && row.valor / total >= 0.25).slice(0, 2);
        return {
          key,
          label: granularity === "mes" ? formatMonthYear(key) : key,
          totalValor: total,
          quantidade: bucketRows.length,
          dominantOs: dominant.map((row) => row.numeroOs),
        };
      });
  }, [filteredOrdens, granularity]);

  const chartMax = Math.max(1, ...temporalBuckets.map((bucket) => bucket.totalValor));
  const concentrationTop = clientesPorValor.slice(0, 6);
  const concentrationOther = clientesPorValor.slice(6).reduce(
    (acc, row) => ({ totalValor: acc.totalValor + row.totalValor, quantidade: acc.quantidade + 1 }),
    { totalValor: 0, quantidade: 0 }
  );
  const concentrationSecondGroup = clientesPorValor.slice(2, 6).reduce((sum, row) => sum + row.totalValor, 0);
  const concentrationRest = Math.max(0, totalValor - topTwoClientsValue - concentrationSecondGroup);

  const agingBuckets = useMemo<AgingBucket[]>(() => {
    const buckets: AgingBucket[] = [
      { key: "ate-30", label: "até 30 dias", totalValor: 0, quantidade: 0, rows: [] },
      { key: "30-90", label: "30 a 90 dias", totalValor: 0, quantidade: 0, rows: [] },
      { key: "90-365", label: "90 dias a 1 ano", totalValor: 0, quantidade: 0, rows: [] },
      { key: "mais-365", label: "mais de 1 ano", totalValor: 0, quantidade: 0, rows: [] },
    ];

    for (const row of filteredOrdens.filter((item) => item.status === "em_andamento")) {
      const age = daysSince(row.referenceDate);
      const index = age <= 30 ? 0 : age <= 90 ? 1 : age <= 365 ? 2 : 3;
      buckets[index].totalValor += row.valor;
      buckets[index].quantidade += 1;
      buckets[index].rows.push(row);
    }
    return buckets;
  }, [filteredOrdens]);
  const agingMax = Math.max(1, ...agingBuckets.map((bucket) => bucket.totalValor));

  const setGranularity = (next: Granularity) => {
    setView(`${next}${openByClient ? "-cliente" : ""}` as ViewMode);
  };

  const setOpenByClient = (next: boolean) => {
    setView(`${granularity}${next ? "-cliente" : ""}` as ViewMode);
  };

  const visibleOsIds = new Set(filteredOrdens.map((row) => row.id));
  const visibleExcess = osExcedentes.filter((row) => visibleOsIds.has(row.id));

  const exportCsv = () => {
    const header = ["OS", "Cliente", "Status", "Data de abertura", "Valor"];
    const lines = filteredOrdens.map((row) => [
      row.numeroOs,
      row.clienteNome,
      statusScopeLabels[row.status],
      formatDateBR(row.referenceDate),
      row.valor.toFixed(2).replace(".", ","),
    ]);
    const csv = [header, ...lines]
      .map((line) => line.map((cell) => `"${String(cell).replace(/"/g, '""')}"`).join(";"))
      .join("\r\n");
    const blob = new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `os-analitico-${periodLabel.replace(/[^0-9]+/g, "-")}.csv`;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 500);
  };

  if (!canView) return null;

  return (
    <div className="carteira-theme os-analytics-page">
      <header className="oa-page-header">
        <div>
          <div className="oa-breadcrumb">
            <Link href="/os">OS</Link><span>›</span><span>Analítico</span>
          </div>
          <h1>Analítico de OS</h1>
          <p>
            OS comuns usam o valor orçado; OS com relatório HH usam o total efetivo dos lançamentos. Em OS em andamento,
            o faturamento já vinculado é descontado do saldo a faturar. Data de referência: abertura da OS.
          </p>
          {hideValorPedido ? <div className="oa-permission-note">Seu perfil pode acompanhar quantidades, mas os valores ficam ocultos.</div> : null}
        </div>
        <div className="oa-page-actions">
          <button type="button" onClick={exportCsv} disabled={loading || filteredOrdens.length === 0} className="carteira-button">
            Exportar
          </button>
          <Link href="/os" className="carteira-button">Voltar para OS</Link>
        </div>
      </header>

      <section className="oa-toolbar" aria-label="Controles do analítico">
        <div className="oa-status-group" role="group" aria-label="Situação das OS">
          <StatusButton active={statusScope === "em_andamento"} onClick={() => setStatusScope("em_andamento")} label="Em andamento" />
          <StatusButton active={statusScope === "concluida"} onClick={() => setStatusScope("concluida")} label="Concluídas" />
          <StatusButton active={statusScope === "todas"} onClick={() => setStatusScope("todas")} label="Todas" />
        </div>

        <span className="oa-toolbar-divider" aria-hidden="true" />

        <div className="oa-segmented" role="group" aria-label="Granularidade">
          <TabButton active={granularity === "mes"} onClick={() => setGranularity("mes")} label="Mês" />
          <TabButton active={granularity === "ano"} onClick={() => setGranularity("ano")} label="Ano" />
        </div>

        <label className="oa-switch-label">
          <input type="checkbox" checked={openByClient} onChange={(event) => setOpenByClient(event.target.checked)} />
          <span className="oa-switch-track" aria-hidden="true"><span /></span>
          Abrir por cliente
        </label>

        <span className="oa-toolbar-divider" aria-hidden="true" />

        <details className="oa-toolbar-details oa-range-details">
          <summary className="carteira-control">{periodLabel}<span>▾</span></summary>
          <div className="oa-popover oa-range-popover">
            <div className="oa-popover-title">Intervalo</div>
            <div className="oa-range-selects">
              <label>De
                <select value={fromYear} onChange={(event) => {
                  const next = clamp(Number(event.target.value), BASE_YEAR, currentYear);
                  setRangeMode("anos");
                  setFromYear(Math.min(next, toYear));
                }}>
                  {yearOptions.map((year) => <option key={`from-${year}`} value={year}>{year}</option>)}
                </select>
              </label>
              <label>Até
                <select value={toYear} onChange={(event) => {
                  const next = clamp(Number(event.target.value), BASE_YEAR, currentYear);
                  setRangeMode("anos");
                  setToYear(Math.max(next, fromYear));
                }}>
                  {yearOptions.map((year) => <option key={`to-${year}`} value={year}>{year}</option>)}
                </select>
              </label>
            </div>
            <div className="oa-shortcuts">
              <button type="button" onClick={() => { setRangeMode("anos"); setFromYear(currentYear); setToYear(currentYear); }}>este ano</button>
              <button type="button" onClick={() => { setRangeMode("ultimos-12"); setFromYear(Number(rollingTwelveMonthStart().slice(0, 4))); setToYear(currentYear); }}>últimos 12 meses</button>
              <button type="button" onClick={() => { setRangeMode("anos"); setFromYear(BASE_YEAR); setToYear(currentYear); }}>tudo</button>
            </div>
          </div>
        </details>

        <select className="carteira-control oa-client-select" value={clientQuery} onChange={(event) => setClientQuery(event.target.value)} aria-label="Cliente">
          <option value="">Todos os clientes</option>
          {clientOptions.map((cliente) => <option key={cliente} value={cliente}>{cliente}</option>)}
        </select>

        <details className="oa-toolbar-details oa-more-details">
          <summary className="carteira-control">Mais filtros <span>▾</span></summary>
          <div className="oa-popover oa-more-popover">
            {granularity === "mes" && openByClient ? (
              <label>Ano em foco
                <select value={effectiveFocusYear} onChange={(event) => setFocusYear(Number(event.target.value))}>
                  {years.slice().reverse().map((year) => <option key={year} value={year}>{year}</option>)}
                </select>
              </label>
            ) : null}
            <label>Linhas nos rankings
              <select value={topN} onChange={(event) => setTopN(clamp(Number(event.target.value), 5, 200))}>
                {[10, 20, 50, 100, 200].map((value) => <option key={value} value={value}>{value}</option>)}
              </select>
            </label>
            <div className="oa-reference-note">Referência temporal: abertura da OS.</div>
          </div>
        </details>
      </section>

      <section className="oa-stats" aria-label="Indicadores do período">
        <StatCard title={valorResumoTitulo} value={hideValorPedido ? "—" : formatMoneyBR(totalValor)} subtitle={valorResumoSubtitulo} hero />
        <StatCard title="Quantidade de OS" value={formatCount(totalOs)} subtitle={`em ${formatCount(clientesAtivos)} clientes distintos`} />
        <StatCard
          title="Ticket médio"
          value={hideValorPedido ? "—" : formatMoneyBR(ticketMedio)}
          subtitle={topTwoOsShare > 40 ? `distorcido — 2 OS somam ${Math.round(topTwoOsShare)}%` : "valor médio por OS"}
          warning={topTwoOsShare > 40}
        />
        <StatCard
          title="Concentração"
          value={hideValorPedido ? "—" : formatPercent(topTwoClientsShare)}
          subtitle={`do valor está em 2 dos ${formatCount(clientesAtivos)} clientes`}
        />
      </section>

      {error ? <div className="oa-error">{error}</div> : null}
      {!ready || loading ? <div className="oa-loading">Carregando analítico de OS...</div> : null}

      {ready && !loading ? (
        <>
          {!hideValorPedido ? (
            <section className="oa-card oa-chart-card">
              <div className="oa-card-head oa-card-head-inline">
                <div>
                  <div className="oa-card-title">Valor a faturar por {granularity === "mes" ? "mês" : "ano"} de abertura</div>
                  <div className="oa-card-subtitle">Valor no eixo; quantidade de OS disponível ao passar o mouse.</div>
                </div>
                <div className="oa-mini-segmented">
                  <TabButton active={granularity === "mes"} onClick={() => setGranularity("mes")} label="Mês" />
                  <TabButton active={granularity === "ano"} onClick={() => setGranularity("ano")} label="Ano" />
                </div>
              </div>

              {temporalBuckets.length ? (
                <div className="oa-chart-viewport">
                  <div className="oa-y-axis" aria-hidden="true">
                    <span>{formatCompactMoney(chartMax)}</span>
                    <span>{formatCompactMoney(chartMax / 2)}</span>
                    <span>0</span>
                  </div>
                  <div className="oa-chart-plot" style={{ minWidth: `${Math.max(620, temporalBuckets.length * 44)}px` }}>
                    <span className="oa-grid-line oa-grid-line-top" aria-hidden="true" />
                    <span className="oa-grid-line oa-grid-line-mid" aria-hidden="true" />
                    <span className="oa-zero-line" aria-hidden="true" />
                    <div className="oa-bars">
                      {temporalBuckets.map((bucket) => {
                        const dominantText = bucket.dominantOs.length ? ` · OS ${bucket.dominantOs.join(" e ")}` : "";
                        return (
                          <div key={bucket.key} className="oa-bar-column">
                            <button
                              type="button"
                              className="oa-chart-bar"
                              style={{ height: `${Math.max(2, (bucket.totalValor / chartMax) * 100)}%` }}
                              aria-label={`${bucket.label}: ${formatMoneyBR(bucket.totalValor)}, ${formatCount(bucket.quantidade)} OS${dominantText}`}
                            >
                              <span className="oa-chart-tooltip">
                                <strong>{bucket.label}</strong>
                                <span>{formatMoneyBR(bucket.totalValor)}</span>
                                <span>{formatCount(bucket.quantidade)} OS{dominantText}</span>
                              </span>
                            </button>
                            <span className="oa-bar-label">{bucket.label.replace(/\/\d{4}$/, "")}</span>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                </div>
              ) : <div className="oa-empty">Nenhum valor encontrado no período.</div>}

              <div className="oa-table-scroll oa-aggregate-table-wrap">
                <table className="oa-data-table">
                  <thead><tr><th>{granularity === "mes" ? "Mês" : "Ano"}</th><th className="is-number">Valor</th><th className="is-number">OS</th><th className="is-number">Ticket</th></tr></thead>
                  <tbody>
                    {temporalBuckets.map((bucket) => (
                      <tr key={`table-${bucket.key}`}><td>{bucket.label}</td><td className="is-number">{formatMoneyBR(bucket.totalValor)}</td><td className="is-number">{formatCount(bucket.quantidade)}</td><td className="is-number">{formatMoneyBR(bucket.quantidade ? bucket.totalValor / bucket.quantidade : 0)}</td></tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          ) : null}

          {!hideValorPedido ? (
            <div className={`oa-analysis-grid${statusScope === "concluida" ? " is-single" : ""}`}>
              <section className="oa-card oa-concentration-card">
                <div className="oa-card-head">
                  <div className="oa-card-title">Concentração por cliente</div>
                  <div className="oa-card-subtitle">Valor acumulado. À direita, a fatia de cada cliente no total.</div>
                </div>
                <div className="oa-concentration-list">
                  {concentrationTop.map((row, index) => (
                    <div key={row.clienteKey} className="oa-concentration-row">
                      <span className="oa-concentration-name">{row.clienteNome}</span>
                      <span className="oa-concentration-track"><span className={`oa-concentration-fill tone-${Math.min(index + 1, 3)}`} style={{ width: `${concentrationTop[0]?.totalValor ? (row.totalValor / concentrationTop[0].totalValor) * 100 : 0}%` }} /></span>
                      <strong>{formatMoneyBR(row.totalValor)}</strong>
                      <span>{formatPercent(totalValor ? (row.totalValor / totalValor) * 100 : 0)}</span>
                    </div>
                  ))}
                  {concentrationOther.quantidade > 0 ? (
                    <div className="oa-concentration-row is-other">
                      <span className="oa-concentration-name">Outros {formatCount(concentrationOther.quantidade)} clientes</span>
                      <span className="oa-concentration-track"><span className="oa-concentration-fill tone-3" style={{ width: `${concentrationTop[0]?.totalValor ? (concentrationOther.totalValor / concentrationTop[0].totalValor) * 100 : 0}%` }} /></span>
                      <strong>{formatMoneyBR(concentrationOther.totalValor)}</strong>
                      <span>{formatPercent(totalValor ? (concentrationOther.totalValor / totalValor) * 100 : 0)}</span>
                    </div>
                  ) : null}
                </div>
                <div className="oa-concentration-strip" aria-label="Distribuição da concentração">
                  <span className="tone-1" style={{ width: `${topTwoClientsShare}%` }} />
                  <span className="tone-2" style={{ width: `${totalValor ? (concentrationSecondGroup / totalValor) * 100 : 0}%` }} />
                  <span className="tone-3" style={{ width: `${totalValor ? (concentrationRest / totalValor) * 100 : 0}%` }} />
                </div>
                <div className="oa-strip-legend">
                  <span><i className="tone-1" />2 clientes · <strong>{formatPercent(topTwoClientsShare)}</strong></span>
                  <span><i className="tone-2" />4 seguintes · <strong>{formatPercent(totalValor ? (concentrationSecondGroup / totalValor) * 100 : 0)}</strong></span>
                  <span><i className="tone-3" />{Math.max(0, clientesAtivos - 6)} restantes · <strong>{formatPercent(totalValor ? (concentrationRest / totalValor) * 100 : 0)}</strong></span>
                </div>
              </section>

              {statusScope !== "concluida" ? (
                <section className="oa-card oa-aging-card">
                  <div className="oa-card-head">
                    <div className="oa-card-title">Envelhecimento das OS em andamento</div>
                    <div className="oa-card-subtitle">Tempo desde a abertura. Valor a faturar em cada faixa.</div>
                  </div>
                  <div className="oa-aging-chart">
                    {agingBuckets.map((bucket) => {
                      const content = (
                        <>
                          <strong>{formatCompactMoney(bucket.totalValor)}</strong>
                          <span className={`oa-aging-bar${bucket.key === "mais-365" ? " is-alert" : ""}`} style={{ height: `${Math.max(3, (bucket.totalValor / agingMax) * 100)}%` }} />
                          <span className="oa-aging-label">{bucket.label}</span>
                          <small>{formatCount(bucket.quantidade)} OS</small>
                        </>
                      );
                      return bucket.key === "mais-365" ? (
                        <Link key={bucket.key} href="/os?status=em_andamento&idade=mais_de_1_ano" className="oa-aging-column is-clickable" aria-label={`${bucket.label}: ${formatMoneyBR(bucket.totalValor)}, ${formatCount(bucket.quantidade)} OS. Abrir lista filtrada.`}>{content}</Link>
                      ) : <div key={bucket.key} className="oa-aging-column">{content}</div>;
                    })}
                  </div>
                  <div className="oa-aging-note">A faixa em âmbar abre a lista de OS já filtrada.</div>
                </section>
              ) : null}
            </div>
          ) : null}

          <div className={`oa-rankings-grid${hideValorPedido ? " is-single" : ""}`}>
            <TableCard title="Clientes" subtitle={`Ordenado por ${rankingOrder === "os" ? "quantidade de OS" : rankingOrder === "ticket" ? "ticket" : rankingOrder === "nome" ? "nome" : "valor"}. Clique no cabeçalho para trocar a ordem.`}>
              <table className="oa-data-table">
                <thead><tr>
                  <th><button type="button" onClick={() => setRankingOrder("nome")}>Cliente {rankingOrder === "nome" ? "↓" : ""}</button></th>
                  <th className="is-number"><button type="button" onClick={() => setRankingOrder("os")}>OS {rankingOrder === "os" ? "↓" : ""}</button></th>
                  {!hideValorPedido ? <th className="is-number"><button type="button" onClick={() => setRankingOrder("valor")}>Valor {rankingOrder === "valor" ? "↓" : ""}</button></th> : null}
                  {!hideValorPedido ? <th className="is-number"><button type="button" onClick={() => setRankingOrder("ticket")}>Ticket {rankingOrder === "ticket" ? "↓" : ""}</button></th> : null}
                </tr></thead>
                <tbody>
                  {clientesOrdenados.slice(0, topN).map((row) => (
                    <tr key={row.clienteKey}><td>{row.clienteNome}</td><td className="is-number">{formatCount(row.quantidade)}</td>{!hideValorPedido ? <td className="is-number">{formatMoneyBR(row.totalValor)}</td> : null}{!hideValorPedido ? <td className="is-number">{formatMoneyBR(row.ticketMedio)}</td> : null}</tr>
                  ))}
                  {!clientesOrdenados.length ? <tr><td colSpan={hideValorPedido ? 2 : 4} className="oa-empty-cell">Nenhum cliente encontrado.</td></tr> : null}
                </tbody>
              </table>
            </TableCard>

            {!hideValorPedido ? (
              <TableCard title="Maiores OS do período" subtitle="Por valor calculado dentro do recorte.">
                <table className="oa-data-table">
                  <thead><tr><th>OS</th><th>Cliente</th><th className="is-number">Valor ↓</th></tr></thead>
                  <tbody>
                    {maioresOs.map((row) => {
                      const age = daysSince(row.referenceDate);
                      return (
                        <tr key={row.id}>
                          <td><Link href={`/os/${row.id}`} className="oa-os-link">{row.numeroOs}</Link><span className={`oa-os-age${age > 365 ? " is-alert" : ""}`}>{formatCount(age)} dias</span></td>
                          <td>{row.clienteNome}</td>
                          <td className="is-number">{formatMoneyBR(row.valor)}</td>
                        </tr>
                      );
                    })}
                    {!maioresOs.length ? <tr><td colSpan={3} className="oa-empty-cell">Nenhuma OS encontrada.</td></tr> : null}
                  </tbody>
                </table>
              </TableCard>
            ) : null}
          </div>

          {openByClient ? (
            <TableCard
              title={granularity === "mes" ? `Mês / Cliente (${effectiveFocusYear})` : "Ano / Cliente"}
              subtitle={hideValorPedido ? "Cada célula mostra a quantidade de OS." : "Cada célula mostra valor acumulado e quantidade de OS."}
            >
              {granularity === "mes" ? (
                <table className="oa-data-table oa-client-breakdown">
                  <thead><tr><th>Cliente</th>{MONTH_LABELS.map((label) => <th key={label} className="is-number">{label}</th>)}<th className="is-number">OS</th>{!hideValorPedido ? <th className="is-number">Valor total</th> : null}</tr></thead>
                  <tbody>
                    {monthClientRows.map((row) => <tr key={row.clienteKey}><td>{row.clienteNome}</td>{MONTH_LABELS.map((label, index) => <td key={`${row.clienteKey}-${label}`} className="is-number"><MetricBlock value={row.valores[index] ?? 0} count={row.quantidades[index] ?? 0} hideValue={hideValorPedido} /></td>)}<td className="is-number">{formatCount(row.quantidade)}</td>{!hideValorPedido ? <td className="is-number">{formatMoneyBR(row.totalValor)}</td> : null}</tr>)}
                    {monthClientRows.length ? <tr className="oa-total-row"><td>Subtotal</td>{MONTH_LABELS.map((label, index) => <td key={`subtotal-${label}`} className="is-number"><MetricBlock value={subtotalMesCliente.valores[index] ?? 0} count={subtotalMesCliente.quantidades[index] ?? 0} hideValue={hideValorPedido} strong /></td>)}<td className="is-number">{formatCount(subtotalMesCliente.quantidades[12] ?? 0)}</td>{!hideValorPedido ? <td className="is-number">{formatMoneyBR(subtotalMesCliente.valores[12] ?? 0)}</td> : null}</tr> : null}
                  </tbody>
                </table>
              ) : (
                <table className="oa-data-table oa-client-breakdown">
                  <thead><tr><th>Cliente</th>{years.map((year) => <th key={year} className="is-number">{year}</th>)}<th className="is-number">OS</th>{!hideValorPedido ? <th className="is-number">Valor total</th> : null}</tr></thead>
                  <tbody>
                    {yearClientRows.map((row) => <tr key={row.clienteKey}><td>{row.clienteNome}</td>{years.map((year, index) => <td key={`${row.clienteKey}-${year}`} className="is-number"><MetricBlock value={row.valores[index] ?? 0} count={row.quantidades[index] ?? 0} hideValue={hideValorPedido} /></td>)}<td className="is-number">{formatCount(row.quantidade)}</td>{!hideValorPedido ? <td className="is-number">{formatMoneyBR(row.totalValor)}</td> : null}</tr>)}
                    {yearClientRows.length ? <tr className="oa-total-row"><td>Subtotal</td>{years.map((year, index) => <td key={`subtotal-${year}`} className="is-number"><MetricBlock value={subtotalAnoCliente.valores[index] ?? 0} count={subtotalAnoCliente.quantidades[index] ?? 0} hideValue={hideValorPedido} strong /></td>)}<td className="is-number">{formatCount(subtotalAnoCliente.quantidades[years.length] ?? 0)}</td>{!hideValorPedido ? <td className="is-number">{formatMoneyBR(subtotalAnoCliente.valores[years.length] ?? 0)}</td> : null}</tr> : null}
                  </tbody>
                </table>
              )}
            </TableCard>
          ) : null}

          {!hideValorPedido && statusScope === "em_andamento" && visibleExcess.length > 0 ? (
            <section className="oa-excess-card">
              <div className="oa-card-title">OS faturadas acima do orçado</div>
              <div className="oa-card-subtitle">Corrija o valor orçado da OS ou revise o faturamento vinculado.</div>
              <div className="oa-table-scroll"><table className="oa-data-table"><thead><tr><th>OS</th><th>Cliente</th><th className="is-number">Valor orçado</th><th className="is-number">Faturado</th><th className="is-number">Excesso</th></tr></thead><tbody>{visibleExcess.map((row) => <tr key={row.id}><td><Link href={`/os/${row.id}`} className="oa-os-link">OS {row.numeroOs}</Link></td><td>{row.clienteNome}</td><td className="is-number">{formatMoneyBR(row.valorPedido)}</td><td className="is-number">{formatMoneyBR(row.valorFaturado)}</td><td className="is-number oa-excess-value">{formatMoneyBR(row.excesso)}</td></tr>)}</tbody></table></div>
            </section>
          ) : null}
        </>
      ) : null}
    </div>
  );
}
