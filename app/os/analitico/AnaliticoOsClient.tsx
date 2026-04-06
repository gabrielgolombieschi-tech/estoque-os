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

type ViewMode = "mes" | "mes-cliente" | "ano" | "ano-cliente";
type StatusScope = "em_andamento" | "concluida" | "todas";

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

type DocumentoFaturadoRow = {
  os_id_import: number | null;
  valor_total: number | string | null;
  modelo: string | null;
  nfe_status: string | null;
  nfse_status: string | null;
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

type AnoResumo = {
  ano: number;
  totalValor: number;
  quantidade: number;
  clientes: number;
  ticketMedio: number;
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

type MonthBucket = {
  valores: number[];
  quantidades: number[];
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
  concluida: "Concluidas",
  todas: "Todas",
};

const statusBadge: Record<OsAnalitico["status"], string> = {
  em_andamento: "bg-amber-500/15 text-amber-300 border-amber-500/30",
  concluida: "bg-emerald-500/15 text-emerald-300 border-emerald-500/30",
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
  if (row.status === "concluida") return toDateOnly(row.data_conclusao) ?? toDateOnly(row.data_abertura);
  if (row.status === "em_andamento") return toDateOnly(row.data_abertura);
  return null;
}

function getDateBasisLabel(scope: StatusScope): string {
  if (scope === "concluida") return "Data de referencia: conclusao da OS.";
  if (scope === "todas") return "Data de referencia: abertura para OS em andamento e conclusao para OS concluidas.";
  return "Data de referencia: abertura da OS.";
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

function shouldIncludeFaturamentoDocumento(row: DocumentoFaturadoRow): boolean {
  const modelo = String(row.modelo ?? "").trim().toUpperCase();
  const nfseStatus = String(row.nfse_status ?? "").trim().toUpperCase();
  const nfeStatus = String(row.nfe_status ?? "").trim().toUpperCase();

  if (modelo === "NFSE") return nfseStatus === "EMITIDA";
  if (!nfeStatus) return true;
  return nfeStatus === "EMITIDA";
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

async function fetchFaturadoByOs(params: {
  supabase: ReturnType<typeof supabaseBrowser>;
  tenantId: string;
  empresaId: string;
}): Promise<Record<number, number>> {
  const out: Record<number, number> = {};
  let offset = 0;

  while (true) {
    const { data, error } = await applyTenantEmpresa(
      params.supabase
        .schema("f")
        .from("documento_fiscal")
        .select("os_id_import,valor_total,modelo,nfe_status,nfse_status")
        .eq("operacao", "SAIDA")
        .not("os_id_import", "is", null)
        .is("deleted_at", null)
        .order("id", { ascending: true })
        .range(offset, offset + FETCH_BATCH_SIZE - 1),
      params.tenantId,
      params.empresaId
    ).returns<DocumentoFaturadoRow[]>();

    if (error) throw error;

    const rows = data ?? [];
    for (const row of rows) {
      if (!shouldIncludeFaturamentoDocumento(row)) continue;

      const osId = Number(row.os_id_import);
      if (!Number.isFinite(osId) || osId <= 0) continue;

      out[osId] = round2((out[osId] ?? 0) + n(row.valor_total));
    }

    if (rows.length < FETCH_BATCH_SIZE) break;
    offset += FETCH_BATCH_SIZE;
  }

  return out;
}

function StatCard({
  title,
  value,
  subtitle,
}: {
  title: string;
  value: string;
  subtitle?: string;
}) {
  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
      <div className="text-xs text-zinc-400">{title}</div>
      <div className="mt-2 text-2xl font-semibold text-zinc-100">{value}</div>
      {subtitle ? <div className="mt-1 text-xs text-zinc-500">{subtitle}</div> : null}
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
      className={[
        "rounded-md border px-3 py-2 text-sm transition-colors",
        active
          ? "border-emerald-500/40 bg-emerald-500/15 text-emerald-200"
          : "border-zinc-800 bg-zinc-950 text-zinc-200 hover:bg-zinc-900",
      ].join(" ")}
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
      className={[
        "rounded-md border px-3 py-2 text-sm transition-colors",
        active
          ? "border-amber-500/40 bg-amber-500/15 text-amber-200"
          : "border-zinc-800 bg-zinc-950 text-zinc-200 hover:bg-zinc-900",
      ].join(" ")}
    >
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
    <section className="rounded-xl border border-zinc-800 bg-zinc-950">
      <div className="border-b border-zinc-800 px-4 py-3">
        <div className="text-sm font-medium text-zinc-100">{title}</div>
        {subtitle ? <div className="mt-1 text-xs text-zinc-500">{subtitle}</div> : null}
      </div>
      <div className="overflow-x-auto">{children}</div>
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
  const valueClass = strong ? "text-zinc-100 font-semibold" : "text-zinc-100";
  const countClass = strong ? "text-zinc-400" : "text-zinc-500";

  if (hideValue) {
    return <div className={`tabular-nums ${valueClass}`}>{formatCount(count)}</div>;
  }

  return (
    <>
      <div className={`tabular-nums ${valueClass}`}>{formatMoneyBR(value)}</div>
      <div className={`mt-1 text-[11px] ${countClass}`}>{formatCount(count)} OS</div>
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
  const defaultFromYear = Math.max(BASE_YEAR, currentYear - 9);
  const initialFromYear = clamp(parsePositiveInt(searchParams.get("from"), defaultFromYear), BASE_YEAR, currentYear);
  const initialToYear = clamp(parsePositiveInt(searchParams.get("to"), currentYear), BASE_YEAR, currentYear);
  const normalizedInitialFromYear = Math.min(initialFromYear, initialToYear);
  const normalizedInitialToYear = Math.max(initialFromYear, initialToYear);
  const initialFocusYear = clamp(
    parsePositiveInt(searchParams.get("focus"), normalizedInitialToYear),
    normalizedInitialFromYear,
    normalizedInitialToYear
  );

  const [view, setView] = useState<ViewMode>(parseViewMode(searchParams.get("view")));
  const [statusScope, setStatusScope] = useState<StatusScope>(parseStatusScope(searchParams.get("status")));
  const [fromYear, setFromYear] = useState<number>(normalizedInitialFromYear);
  const [toYear, setToYear] = useState<number>(normalizedInitialToYear);
  const [focusYear, setFocusYear] = useState<number>(initialFocusYear);
  const [clientQuery, setClientQuery] = useState<string>(searchParams.get("cliente") ?? "");
  const [topN, setTopN] = useState<number>(clamp(parsePositiveInt(searchParams.get("top"), DEFAULT_TOP_N), 5, 200));

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

  useEffect(() => {
    if (focusYear < fromYear) setFocusYear(fromYear);
    if (focusYear > toYear) setFocusYear(toYear);
  }, [focusYear, fromYear, toYear]);

  useEffect(() => {
    if (!sessionReady || te.loading) return;
    if (!canView) router.replace("/forbidden");
  }, [canView, router, sessionReady, te.loading]);

  useEffect(() => {
    const params = new URLSearchParams();
    params.set("view", view);
    params.set("status", statusScope);
    params.set("from", String(fromYear));
    params.set("to", String(toYear));
    if (view === "mes-cliente") params.set("focus", String(focusYear));
    if (clientQuery.trim()) params.set("cliente", clientQuery.trim());
    if (topN !== DEFAULT_TOP_N) params.set("top", String(topN));

    const nextQuery = params.toString();
    const currentQuery = searchParams.toString();
    if (nextQuery !== currentQuery) {
      router.replace(nextQuery ? `${pathname}?${nextQuery}` : pathname);
    }
  }, [clientQuery, focusYear, fromYear, pathname, router, searchParams, statusScope, toYear, topN, view]);

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
        setError(loadError instanceof Error ? loadError.message : "Erro ao carregar o analitico de OS.");
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
        if (year < fromYear || year > toYear) return null;
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
  }, [clientesById, faturadoByOs, fromYear, hhFallbackByOs, hhPedidoByOs, rows, toYear]);

  const filteredClientTerm = clientQuery.trim().toLowerCase();
  const activeClientTerm = view === "mes-cliente" || view === "ano-cliente" ? filteredClientTerm : "";

  const rankingSourceRows = useMemo(
    () =>
      activeClientTerm
        ? ordens.filter((row) => row.clienteNome.toLowerCase().includes(activeClientTerm))
        : ordens,
    [activeClientTerm, ordens]
  );

  const totalValor = useMemo(() => ordens.reduce((acc, row) => acc + row.valor, 0), [ordens]);
  const totalOs = ordens.length;
  const clientesAtivos = useMemo(() => new Set(ordens.map((row) => row.clientKey)).size, [ordens]);
  const ticketMedio = totalOs > 0 ? totalValor / totalOs : 0;
  const valorResumoTitulo = statusScope === "em_andamento" ? "Valor a faturar no periodo" : "Valor total no periodo";
  const valorResumoSubtitulo =
    statusScope === "em_andamento"
      ? `${statusScopeLabels[statusScope]} | ${fromYear} ate ${toYear} | faturamento vinculado descontado`
      : `${statusScopeLabels[statusScope]} | ${fromYear} ate ${toYear}`;

  const rankingsBase = useMemo<ClienteRanking[]>(() => {
    const byClient = new Map<string, ClienteRanking>();

    for (const row of rankingSourceRows) {
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
  }, [rankingSourceRows]);

  const topClientesPorQuantidade = useMemo(
    () =>
      [...rankingsBase]
        .sort((a, b) => b.quantidade - a.quantidade || b.totalValor - a.totalValor || a.clienteNome.localeCompare(b.clienteNome))
        .slice(0, topN),
    [rankingsBase, topN]
  );

  const topClientesPorValor = useMemo(
    () =>
      [...rankingsBase]
        .sort((a, b) => b.totalValor - a.totalValor || b.quantidade - a.quantidade || a.clienteNome.localeCompare(b.clienteNome))
        .slice(0, topN),
    [rankingsBase, topN]
  );

  const maioresOs = useMemo(
    () =>
      [...rankingSourceRows]
        .sort((a, b) => b.valor - a.valor || b.referenceDate.localeCompare(a.referenceDate) || a.numeroOs.localeCompare(b.numeroOs))
        .slice(0, topN),
    [rankingSourceRows, topN]
  );

  const clienteLiderQuantidade = topClientesPorQuantidade[0] ?? null;
  const maiorOsRow = maioresOs[0] ?? null;

  const yearIndexMap = useMemo(() => new Map(years.map((year, index) => [year, index])), [years]);

  const yearRows = useMemo<AnoResumo[]>(() => {
    const totals = new Map<number, { totalValor: number; quantidade: number; clientes: Set<string> }>();

    for (const year of years) {
      totals.set(year, { totalValor: 0, quantidade: 0, clientes: new Set<string>() });
    }

    for (const row of ordens) {
      const bucket = totals.get(row.year);
      if (!bucket) continue;
      bucket.totalValor += row.valor;
      bucket.quantidade += 1;
      bucket.clientes.add(row.clientKey);
    }

    return years.map((year) => {
      const bucket = totals.get(year) ?? { totalValor: 0, quantidade: 0, clientes: new Set<string>() };
      return {
        ano: year,
        totalValor: bucket.totalValor,
        quantidade: bucket.quantidade,
        clientes: bucket.clientes.size,
        ticketMedio: bucket.quantidade > 0 ? bucket.totalValor / bucket.quantidade : 0,
      };
    });
  }, [ordens, years]);

  const monthByYear = useMemo(() => {
    const byYear = new Map<number, MonthBucket>();
    for (const year of years) {
      byYear.set(year, {
        valores: Array.from({ length: 12 }, () => 0),
        quantidades: Array.from({ length: 12 }, () => 0),
      });
    }

    for (const row of ordens) {
      const bucket = byYear.get(row.year);
      if (!bucket) continue;
      bucket.valores[row.month - 1] += row.valor;
      bucket.quantidades[row.month - 1] += 1;
    }

    return byYear;
  }, [ordens, years]);

  const monthClientRows = useMemo<ClienteMesResumo[]>(() => {
    const byClient = new Map<string, ClienteMesResumo>();

    for (const row of ordens) {
      if (row.year !== focusYear) continue;

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
      .filter((row) => (activeClientTerm ? row.clienteNome.toLowerCase().includes(activeClientTerm) : true))
      .sort((a, b) =>
        hideValorPedido
          ? b.quantidade - a.quantidade || b.totalValor - a.totalValor || a.clienteNome.localeCompare(b.clienteNome)
          : b.totalValor - a.totalValor || b.quantidade - a.quantidade || a.clienteNome.localeCompare(b.clienteNome)
      )
      .slice(0, topN);
  }, [activeClientTerm, focusYear, hideValorPedido, ordens, topN]);

  const yearClientRows = useMemo<ClienteAnoResumo[]>(() => {
    const byClient = new Map<string, ClienteAnoResumo>();

    for (const row of ordens) {
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
      .filter((row) => (activeClientTerm ? row.clienteNome.toLowerCase().includes(activeClientTerm) : true))
      .sort((a, b) =>
        hideValorPedido
          ? b.quantidade - a.quantidade || b.totalValor - a.totalValor || a.clienteNome.localeCompare(b.clienteNome)
          : b.totalValor - a.totalValor || b.quantidade - a.quantidade || a.clienteNome.localeCompare(b.clienteNome)
      )
      .slice(0, topN);
  }, [activeClientTerm, hideValorPedido, ordens, topN, yearIndexMap, years.length]);

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

  const monthRowTotals = useMemo(
    () =>
      MONTH_LABELS.map((_, monthIndex) => ({
        valor: years.reduce((acc, year) => acc + (monthByYear.get(year)?.valores[monthIndex] ?? 0), 0),
        quantidade: years.reduce((acc, year) => acc + (monthByYear.get(year)?.quantidades[monthIndex] ?? 0), 0),
      })),
    [monthByYear, years]
  );

  const yearColumnTotals = useMemo(
    () =>
      years.map((year) => ({
        valor: monthByYear.get(year)?.valores.reduce((acc, value) => acc + value, 0) ?? 0,
        quantidade: monthByYear.get(year)?.quantidades.reduce((acc, value) => acc + value, 0) ?? 0,
      })),
    [monthByYear, years]
  );

  if (!canView) return null;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <div className="text-xs uppercase tracking-[0.18em] text-zinc-500">OS</div>
          <h1 className="mt-1 text-2xl font-semibold text-zinc-100">Analitico</h1>
          <p className="mt-1 text-sm text-zinc-400">
            Valor considerado: OS comuns usam o valor orcado; OS com relatorio HH usam o total efetivo dos lancamentos.
            Para OS em andamento, o faturamento vinculado a OS e descontado do saldo a faturar.
          </p>
          <p className="mt-1 text-xs text-zinc-500">{getDateBasisLabel(statusScope)}</p>
          {hideValorPedido ? (
            <p className="mt-1 text-xs text-amber-300">Seu perfil pode acompanhar quantidades, mas os valores ficam ocultos.</p>
          ) : null}
        </div>
        <Link
          href="/os"
          className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-900"
        >
          Voltar para OS
        </Link>
      </div>

      <section className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <div className="flex flex-wrap gap-2">
          <TabButton active={view === "mes"} onClick={() => setView("mes")} label="Mes" />
          <TabButton active={view === "mes-cliente"} onClick={() => setView("mes-cliente")} label="Mes / Cliente" />
          <TabButton active={view === "ano"} onClick={() => setView("ano")} label="Ano" />
          <TabButton active={view === "ano-cliente"} onClick={() => setView("ano-cliente")} label="Ano / Cliente" />
        </div>

        <div className="mt-3 flex flex-wrap gap-2">
          <StatusButton
            active={statusScope === "em_andamento"}
            onClick={() => setStatusScope("em_andamento")}
            label="Em andamento"
          />
          <StatusButton active={statusScope === "concluida"} onClick={() => setStatusScope("concluida")} label="Concluidas" />
          <StatusButton active={statusScope === "todas"} onClick={() => setStatusScope("todas")} label="Todas" />
        </div>

        <div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-6">
          <label className="block">
            <span className="text-xs text-zinc-400">Ano inicial</span>
            <select
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none"
              value={fromYear}
              onChange={(event) => {
                const next = clamp(Number(event.target.value), BASE_YEAR, currentYear);
                setFromYear(next);
                if (next > toYear) setToYear(next);
                if (focusYear < next) setFocusYear(next);
              }}
            >
              {yearOptions.map((year) => (
                <option key={year} value={year}>
                  {year}
                </option>
              ))}
            </select>
          </label>

          <label className="block">
            <span className="text-xs text-zinc-400">Ano final</span>
            <select
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none"
              value={toYear}
              onChange={(event) => {
                const next = clamp(Number(event.target.value), BASE_YEAR, currentYear);
                setToYear(next);
                if (next < fromYear) setFromYear(next);
                if (focusYear > next) setFocusYear(next);
              }}
            >
              {yearOptions.map((year) => (
                <option key={year} value={year}>
                  {year}
                </option>
              ))}
            </select>
          </label>
          {view === "mes-cliente" ? (
            <label className="block">
              <span className="text-xs text-zinc-400">Ano foco</span>
              <select
                className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none"
                value={focusYear}
                onChange={(event) => setFocusYear(clamp(Number(event.target.value), fromYear, toYear))}
              >
                {years
                  .slice()
                  .reverse()
                  .map((year) => (
                    <option key={year} value={year}>
                      {year}
                    </option>
                  ))}
              </select>
            </label>
          ) : null}

          {view === "mes-cliente" || view === "ano-cliente" ? (
            <>
              <label className="block md:col-span-2">
                <span className="text-xs text-zinc-400">Buscar cliente</span>
                <input
                  type="text"
                  value={clientQuery}
                  onChange={(event) => setClientQuery(event.target.value)}
                  placeholder="Nome do cliente"
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none placeholder:text-zinc-500"
                />
              </label>

              <label className="block">
                <span className="text-xs text-zinc-400">Top clientes</span>
                <select
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none"
                  value={topN}
                  onChange={(event) => setTopN(clamp(Number(event.target.value), 5, 200))}
                >
                  {[10, 20, 50, 100, 200].map((value) => (
                    <option key={value} value={value}>
                      {value}
                    </option>
                  ))}
                </select>
              </label>
            </>
          ) : (
            <div className="flex items-end md:col-span-3">
              <div className="rounded-md border border-dashed border-zinc-800 px-3 py-2 text-xs text-zinc-500">
                Filtros sincronizados na URL para compartilhamento desta visao.
              </div>
            </div>
          )}
        </div>
      </section>

      <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
        <StatCard
          title={valorResumoTitulo}
          value={hideValorPedido ? "-" : formatMoneyBR(totalValor)}
          subtitle={valorResumoSubtitulo}
        />
        <StatCard
          title="Quantidade de OS"
          value={formatCount(totalOs)}
          subtitle={`${statusScopeLabels[statusScope]} no recorte`}
        />
        <StatCard
          title="Clientes com OS"
          value={formatCount(clientesAtivos)}
          subtitle="Clientes distintos no periodo"
        />
        <StatCard
          title="Ticket medio"
          value={hideValorPedido ? "-" : formatMoneyBR(ticketMedio)}
          subtitle="Valor medio por OS"
        />
        <StatCard
          title="Cliente com mais OS"
          value={clienteLiderQuantidade?.clienteNome ?? "-"}
          subtitle={clienteLiderQuantidade ? `${formatCount(clienteLiderQuantidade.quantidade)} OS` : "Sem registros"}
        />
        <StatCard
          title={hideValorPedido ? "Maior volume em OS" : "Maior OS"}
          value={maiorOsRow ? `OS ${maiorOsRow.numeroOs}` : "-"}
          subtitle={
            maiorOsRow
              ? hideValorPedido
                ? `${maiorOsRow.clienteNome} | ${formatDateBR(maiorOsRow.referenceDate)}`
                : `${maiorOsRow.clienteNome} | ${formatMoneyBR(maiorOsRow.valor)}`
              : "Sem registros"
          }
        />
      </div>

      {error ? (
        <div className="rounded-xl border border-rose-900/60 bg-rose-950/20 px-4 py-3 text-sm text-rose-200">{error}</div>
      ) : null}

      {!ready || loading ? (
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 px-4 py-8 text-center text-sm text-zinc-400">
          Carregando analitico de OS...
        </div>
      ) : null}

      {ready && !loading ? (
        <div className={`grid grid-cols-1 gap-3 ${hideValorPedido ? "xl:grid-cols-1" : "xl:grid-cols-3"}`}>
          <TableCard title="Clientes com mais OS" subtitle="Ranking por quantidade de OS no recorte atual.">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b border-zinc-800 text-zinc-400">
                  <th className="px-4 py-3 text-left font-medium">Cliente</th>
                  <th className="px-4 py-3 text-right font-medium">OS</th>
                  {!hideValorPedido ? <th className="px-4 py-3 text-right font-medium">Valor</th> : null}
                  {!hideValorPedido ? <th className="px-4 py-3 text-right font-medium">Ticket</th> : null}
                </tr>
              </thead>
              <tbody>
                {topClientesPorQuantidade.map((row) => (
                  <tr key={`qtd-${row.clienteKey}`} className="border-b border-zinc-900/70 hover:bg-zinc-900/30">
                    <td className="px-4 py-3 text-zinc-100">{row.clienteNome}</td>
                    <td className="px-4 py-3 text-right tabular-nums text-zinc-200">{formatCount(row.quantidade)}</td>
                    {!hideValorPedido ? (
                      <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{formatMoneyBR(row.totalValor)}</td>
                    ) : null}
                    {!hideValorPedido ? (
                      <td className="px-4 py-3 text-right tabular-nums text-zinc-200">{formatMoneyBR(row.ticketMedio)}</td>
                    ) : null}
                  </tr>
                ))}
                {topClientesPorQuantidade.length === 0 ? (
                  <tr>
                    <td colSpan={hideValorPedido ? 2 : 4} className="px-4 py-6 text-zinc-400">
                      Nenhum cliente encontrado para os filtros selecionados.
                    </td>
                  </tr>
                ) : null}
              </tbody>
            </table>
          </TableCard>

          {!hideValorPedido ? (
            <TableCard title="Clientes com maior valor" subtitle="Ranking por valor acumulado das OS no periodo.">
              <table className="min-w-full text-sm">
                <thead>
                  <tr className="border-b border-zinc-800 text-zinc-400">
                    <th className="px-4 py-3 text-left font-medium">Cliente</th>
                    <th className="px-4 py-3 text-right font-medium">Valor</th>
                    <th className="px-4 py-3 text-right font-medium">OS</th>
                    <th className="px-4 py-3 text-right font-medium">Ticket</th>
                  </tr>
                </thead>
                <tbody>
                  {topClientesPorValor.map((row) => (
                    <tr key={`valor-${row.clienteKey}`} className="border-b border-zinc-900/70 hover:bg-zinc-900/30">
                      <td className="px-4 py-3 text-zinc-100">{row.clienteNome}</td>
                      <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{formatMoneyBR(row.totalValor)}</td>
                      <td className="px-4 py-3 text-right tabular-nums text-zinc-200">{formatCount(row.quantidade)}</td>
                      <td className="px-4 py-3 text-right tabular-nums text-zinc-200">{formatMoneyBR(row.ticketMedio)}</td>
                    </tr>
                  ))}
                  {topClientesPorValor.length === 0 ? (
                    <tr>
                      <td colSpan={4} className="px-4 py-6 text-zinc-400">
                        Nenhum cliente encontrado para os filtros selecionados.
                      </td>
                    </tr>
                  ) : null}
                </tbody>
              </table>
            </TableCard>
          ) : null}

          {!hideValorPedido ? (
            <TableCard title="Maiores OS do periodo" subtitle="As OS com maior valor calculado dentro do recorte selecionado.">
              <table className="min-w-full text-sm">
                <thead>
                  <tr className="border-b border-zinc-800 text-zinc-400">
                    <th className="px-4 py-3 text-left font-medium">OS</th>
                    <th className="px-4 py-3 text-left font-medium">Cliente</th>
                    <th className="px-4 py-3 text-left font-medium">Status</th>
                    <th className="px-4 py-3 text-right font-medium">Valor</th>
                  </tr>
                </thead>
                <tbody>
                  {maioresOs.map((row) => (
                    <tr key={`os-${row.id}`} className="border-b border-zinc-900/70 hover:bg-zinc-900/30">
                      <td className="px-4 py-3 text-zinc-100">
                        <div>{row.numeroOs}</div>
                        <div className="text-xs text-zinc-500">{formatDateBR(row.referenceDate)}</div>
                      </td>
                      <td className="px-4 py-3 text-zinc-100">{row.clienteNome}</td>
                      <td className="px-4 py-3">
                        <span
                          className={[
                            "inline-flex items-center rounded-md border px-2 py-1 text-xs",
                            statusBadge[row.status] ?? "",
                          ].join(" ")}
                        >
                          {row.status === "em_andamento" ? "em_andamento" : "concluida"}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{formatMoneyBR(row.valor)}</td>
                    </tr>
                  ))}
                  {maioresOs.length === 0 ? (
                    <tr>
                      <td colSpan={4} className="px-4 py-6 text-zinc-400">
                        Nenhuma OS encontrada para os filtros selecionados.
                      </td>
                    </tr>
                  ) : null}
                </tbody>
              </table>
            </TableCard>
          ) : null}
        </div>
      ) : null}

      {ready && !loading && view === "mes" ? (
        <TableCard
          title="Mes a mes por ano"
          subtitle={hideValorPedido ? "Cada celula mostra apenas a quantidade de OS." : "Cada celula mostra valor acumulado e quantidade de OS."}
        >
          <table className="min-w-full text-sm">
            <thead className="bg-zinc-950/95">
              <tr className="border-b border-zinc-800 text-zinc-400">
                <th className="sticky left-0 bg-zinc-950 px-4 py-3 text-left font-medium">Mes</th>
                {years.map((year) => (
                  <th key={year} className="px-4 py-3 text-right font-medium">
                    {year}
                  </th>
                ))}
                <th className="px-4 py-3 text-right font-medium">Total</th>
              </tr>
            </thead>
            <tbody>
              {MONTH_LABELS.map((label, monthIndex) => (
                <tr key={label} className="border-b border-zinc-900/70 hover:bg-zinc-900/30">
                  <td className="sticky left-0 bg-zinc-950 px-4 py-3 text-zinc-200">{label}</td>
                  {years.map((year) => {
                    const bucket = monthByYear.get(year);
                    return (
                      <td key={`${year}-${label}`} className="px-4 py-3 text-right align-top">
                        <MetricBlock
                          value={bucket?.valores[monthIndex] ?? 0}
                          count={bucket?.quantidades[monthIndex] ?? 0}
                          hideValue={hideValorPedido}
                        />
                      </td>
                    );
                  })}
                  <td className="px-4 py-3 text-right align-top">
                    <MetricBlock
                      value={monthRowTotals[monthIndex]?.valor ?? 0}
                      count={monthRowTotals[monthIndex]?.quantidade ?? 0}
                      hideValue={hideValorPedido}
                      strong
                    />
                  </td>
                </tr>
              ))}
              <tr className="bg-zinc-900/60">
                <td className="sticky left-0 bg-zinc-900 px-4 py-3 font-semibold text-zinc-100">Total</td>
                {yearColumnTotals.map((bucket, index) => (
                  <td key={years[index]} className="px-4 py-3 text-right align-top">
                    <MetricBlock value={bucket.valor} count={bucket.quantidade} hideValue={hideValorPedido} strong />
                  </td>
                ))}
                <td className="px-4 py-3 text-right align-top">
                  <MetricBlock value={totalValor} count={totalOs} hideValue={hideValorPedido} strong />
                </td>
              </tr>
            </tbody>
          </table>
        </TableCard>
      ) : null}

      {ready && !loading && view === "ano" ? (
        <TableCard
          title="Resumo anual"
          subtitle="Consolidado por ano com quantidade de OS, clientes atendidos e ticket medio."
        >
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-800 text-zinc-400">
                <th className="px-4 py-3 text-left font-medium">Ano</th>
                {!hideValorPedido ? <th className="px-4 py-3 text-right font-medium">Valor</th> : null}
                <th className="px-4 py-3 text-right font-medium">OS</th>
                <th className="px-4 py-3 text-right font-medium">Clientes</th>
                {!hideValorPedido ? <th className="px-4 py-3 text-right font-medium">Ticket medio</th> : null}
              </tr>
            </thead>
            <tbody>
              {yearRows.map((row) => (
                <tr key={row.ano} className="border-b border-zinc-900/70 hover:bg-zinc-900/30">
                  <td className="px-4 py-3 text-zinc-100">{row.ano}</td>
                  {!hideValorPedido ? (
                    <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{formatMoneyBR(row.totalValor)}</td>
                  ) : null}
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-200">{formatCount(row.quantidade)}</td>
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-200">{formatCount(row.clientes)}</td>
                  {!hideValorPedido ? (
                    <td className="px-4 py-3 text-right tabular-nums text-zinc-200">{formatMoneyBR(row.ticketMedio)}</td>
                  ) : null}
                </tr>
              ))}
              <tr className="bg-zinc-900/60 font-semibold">
                <td className="px-4 py-3 text-zinc-100">Total</td>
                {!hideValorPedido ? (
                  <td className="px-4 py-3 text-right tabular-nums text-emerald-200">{formatMoneyBR(totalValor)}</td>
                ) : null}
                <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{formatCount(totalOs)}</td>
                <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{formatCount(clientesAtivos)}</td>
                {!hideValorPedido ? (
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{formatMoneyBR(ticketMedio)}</td>
                ) : null}
              </tr>
            </tbody>
          </table>
        </TableCard>
      ) : null}

      {ready && !loading && view === "mes-cliente" ? (
        <TableCard
          title={`Mes / Cliente (${focusYear})`}
          subtitle={
            hideValorPedido
              ? "Cada celula mostra a quantidade de OS do cliente no mes."
              : "Cada celula mostra valor acumulado e, abaixo, a quantidade de OS do cliente no mes."
          }
        >
          <table className="min-w-full text-sm">
            <thead className="bg-zinc-950/95">
              <tr className="border-b border-zinc-800 text-zinc-400">
                <th className="sticky left-0 bg-zinc-950 px-4 py-3 text-left font-medium">Cliente</th>
                {MONTH_LABELS.map((label) => (
                  <th key={label} className="px-4 py-3 text-right font-medium">
                    {label}
                  </th>
                ))}
                <th className="px-4 py-3 text-right font-medium">OS</th>
                {!hideValorPedido ? <th className="px-4 py-3 text-right font-medium">Valor total</th> : null}
              </tr>
            </thead>
            <tbody>
              {monthClientRows.map((row) => (
                <tr key={row.clienteKey} className="border-b border-zinc-900/70 hover:bg-zinc-900/30">
                  <td className="sticky left-0 bg-zinc-950 px-4 py-3 text-zinc-100">{row.clienteNome}</td>
                  {MONTH_LABELS.map((label, monthIndex) => (
                    <td key={`${row.clienteKey}-${label}`} className="px-4 py-3 text-right align-top">
                      <MetricBlock
                        value={row.valores[monthIndex] ?? 0}
                        count={row.quantidades[monthIndex] ?? 0}
                        hideValue={hideValorPedido}
                      />
                    </td>
                  ))}
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-200">{formatCount(row.quantidade)}</td>
                  {!hideValorPedido ? (
                    <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{formatMoneyBR(row.totalValor)}</td>
                  ) : null}
                </tr>
              ))}
              {monthClientRows.length === 0 ? (
                <tr>
                  <td colSpan={hideValorPedido ? 14 : 15} className="px-4 py-6 text-zinc-400">
                    Nenhum cliente encontrado para os filtros selecionados.
                  </td>
                </tr>
              ) : null}
              {monthClientRows.length > 0 ? (
                <tr className="bg-zinc-900/60">
                  <td className="sticky left-0 bg-zinc-900 px-4 py-3 font-semibold text-zinc-100">Subtotal</td>
                  {MONTH_LABELS.map((label, monthIndex) => (
                    <td key={`subtotal-${label}`} className="px-4 py-3 text-right align-top">
                      <MetricBlock
                        value={subtotalMesCliente.valores[monthIndex] ?? 0}
                        count={subtotalMesCliente.quantidades[monthIndex] ?? 0}
                        hideValue={hideValorPedido}
                        strong
                      />
                    </td>
                  ))}
                  <td className="px-4 py-3 text-right tabular-nums font-semibold text-zinc-100">
                    {formatCount(subtotalMesCliente.quantidades[12] ?? 0)}
                  </td>
                  {!hideValorPedido ? (
                    <td className="px-4 py-3 text-right tabular-nums font-semibold text-zinc-100">
                      {formatMoneyBR(subtotalMesCliente.valores[12] ?? 0)}
                    </td>
                  ) : null}
                </tr>
              ) : null}
            </tbody>
          </table>
        </TableCard>
      ) : null}

      {ready && !loading && view === "ano-cliente" ? (
        <TableCard
          title="Ano / Cliente"
          subtitle={
            hideValorPedido
              ? "Cada celula mostra a quantidade de OS do cliente no ano."
              : "Cada celula mostra valor acumulado e, abaixo, a quantidade de OS do cliente no ano."
          }
        >
          <table className="min-w-full text-sm">
            <thead className="bg-zinc-950/95">
              <tr className="border-b border-zinc-800 text-zinc-400">
                <th className="sticky left-0 bg-zinc-950 px-4 py-3 text-left font-medium">Cliente</th>
                {years.map((year) => (
                  <th key={year} className="px-4 py-3 text-right font-medium">
                    {year}
                  </th>
                ))}
                <th className="px-4 py-3 text-right font-medium">OS</th>
                {!hideValorPedido ? <th className="px-4 py-3 text-right font-medium">Valor total</th> : null}
              </tr>
            </thead>
            <tbody>
              {yearClientRows.map((row) => (
                <tr key={row.clienteKey} className="border-b border-zinc-900/70 hover:bg-zinc-900/30">
                  <td className="sticky left-0 bg-zinc-950 px-4 py-3 text-zinc-100">{row.clienteNome}</td>
                  {years.map((year, yearIndex) => (
                    <td key={`${row.clienteKey}-${year}`} className="px-4 py-3 text-right align-top">
                      <MetricBlock
                        value={row.valores[yearIndex] ?? 0}
                        count={row.quantidades[yearIndex] ?? 0}
                        hideValue={hideValorPedido}
                      />
                    </td>
                  ))}
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-200">{formatCount(row.quantidade)}</td>
                  {!hideValorPedido ? (
                    <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{formatMoneyBR(row.totalValor)}</td>
                  ) : null}
                </tr>
              ))}
              {yearClientRows.length === 0 ? (
                <tr>
                  <td colSpan={hideValorPedido ? years.length + 2 : years.length + 3} className="px-4 py-6 text-zinc-400">
                    Nenhum cliente encontrado para os filtros selecionados.
                  </td>
                </tr>
              ) : null}
              {yearClientRows.length > 0 ? (
                <tr className="bg-zinc-900/60">
                  <td className="sticky left-0 bg-zinc-900 px-4 py-3 font-semibold text-zinc-100">Subtotal</td>
                  {years.map((year, yearIndex) => (
                    <td key={`subtotal-${year}`} className="px-4 py-3 text-right align-top">
                      <MetricBlock
                        value={subtotalAnoCliente.valores[yearIndex] ?? 0}
                        count={subtotalAnoCliente.quantidades[yearIndex] ?? 0}
                        hideValue={hideValorPedido}
                        strong
                      />
                    </td>
                  ))}
                  <td className="px-4 py-3 text-right tabular-nums font-semibold text-zinc-100">
                    {formatCount(subtotalAnoCliente.quantidades[years.length] ?? 0)}
                  </td>
                  {!hideValorPedido ? (
                    <td className="px-4 py-3 text-right tabular-nums font-semibold text-zinc-100">
                      {formatMoneyBR(subtotalAnoCliente.valores[years.length] ?? 0)}
                    </td>
                  ) : null}
                </tr>
              ) : null}
            </tbody>
          </table>
        </TableCard>
      ) : null}
    </div>
  );
}
