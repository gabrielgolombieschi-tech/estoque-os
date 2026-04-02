"use client";

import Link from "next/link";
import { useEffect, useMemo, useState, type ReactNode } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { formatMoneyBR } from "@/lib/decimal";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import { normalizeOrcamentoStatus } from "@/lib/comercial/status";
import { listOrcamentosAnalitico } from "@/lib/comercial/orcamentos.service";
import type { OrcamentoAnaliticoRow } from "@/lib/comercial/types";

type ViewMode = "mes" | "mes-cliente" | "ano" | "ano-cliente";
type StatusScope = "abertos" | "fechados" | "perdidos" | "todos";
type OrcamentoStatusAnalitico = "ANDAMENTO" | "FECHADO" | "PERDIDO";

type OrcamentoAnalitico = {
  id: string;
  codigo: string;
  titulo: string;
  status: OrcamentoStatusAnalitico;
  emissaoDate: string;
  year: number;
  month: number;
  clienteKey: string;
  clienteNome: string;
  vendedorKey: string;
  vendedorNome: string;
  valor: number;
};

type AnoResumo = {
  ano: number;
  totalValor: number;
  quantidade: number;
  clientes: number;
  vendedores: number;
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

type MonthBucket = {
  valores: number[];
  quantidades: number[];
};

type StatusSummary = Record<OrcamentoStatusAnalitico, { valor: number; quantidade: number }>;

const BASE_YEAR = 2017;
const DEFAULT_TOP_N = 20;
const MONTH_LABELS = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"] as const;

function n(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

function hasAny(caps: Capabilities | null, keys: CapabilityKey[]): boolean {
  return requireAny(caps, keys);
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function parsePositiveInt(value: string | null, fallback: number): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.trunc(parsed);
}

function parseViewMode(value: string | null): ViewMode {
  if (value === "mes") return "mes";
  if (value === "mes-cliente") return "mes-cliente";
  if (value === "ano") return "ano";
  if (value === "ano-cliente") return "ano-cliente";
  return "mes";
}

function parseStatusScope(value: string | null): StatusScope {
  if (value === "abertos") return "abertos";
  if (value === "fechados") return "fechados";
  if (value === "perdidos") return "perdidos";
  if (value === "todos") return "todos";
  return "todos";
}

function formatCount(count: number): string {
  return `${count} orc.`;
}

function formatPercent(value: number | null): string {
  if (value === null || !Number.isFinite(value)) return "-";
  return `${value.toFixed(1).replace(".", ",")}%`;
}

function getStatusLabel(scope: StatusScope): string {
  if (scope === "abertos") return "abertos";
  if (scope === "fechados") return "fechados";
  if (scope === "perdidos") return "perdidos";
  return "todos os status";
}

function getStatusTone(scope: StatusScope): string {
  if (scope === "abertos") return "border-zinc-700 bg-zinc-900 text-zinc-100";
  if (scope === "fechados") return "border-emerald-500/40 bg-emerald-500/10 text-emerald-200";
  if (scope === "perdidos") return "border-rose-500/40 bg-rose-500/10 text-rose-200";
  return "border-sky-500/40 bg-sky-500/10 text-sky-200";
}

function getClientName(row: OrcamentoAnaliticoRow): string {
  const nome = String(row.cliente_nome ?? "").trim();
  if (nome) return nome;
  if (typeof row.cliente_id === "number" && Number.isFinite(row.cliente_id)) return `Cliente #${row.cliente_id}`;
  return "(Sem cliente)";
}

function getClientKey(row: OrcamentoAnaliticoRow): string {
  if (typeof row.cliente_id === "number" && Number.isFinite(row.cliente_id)) return `cliente:${row.cliente_id}`;
  return `cliente-nome:${getClientName(row).toUpperCase()}`;
}

function getVendorName(row: OrcamentoAnaliticoRow): string {
  const nome = String(row.vendedor_nome ?? "").trim();
  if (nome) return nome;
  if (row.vendedor_usuario_id) return "Vendedor sem nome";
  return "(Sem vendedor)";
}

function getVendorKey(row: OrcamentoAnaliticoRow): string {
  const id = String(row.vendedor_usuario_id ?? "").trim();
  if (id) return `vendedor:${id}`;
  return `vendedor-nome:${getVendorName(row).toUpperCase()}`;
}

function matchesScope(status: OrcamentoStatusAnalitico, scope: StatusScope): boolean {
  if (scope === "todos") return true;
  if (scope === "abertos") return status === "ANDAMENTO";
  if (scope === "fechados") return status === "FECHADO";
  return status === "PERDIDO";
}

function mapRow(row: OrcamentoAnaliticoRow): OrcamentoAnalitico | null {
  const date = String(row.emissao_date ?? "").slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;

  const normalized = normalizeOrcamentoStatus(row.status);
  if (normalized !== "ANDAMENTO" && normalized !== "FECHADO" && normalized !== "PERDIDO") return null;

  const year = Number(date.slice(0, 4));
  const month = Number(date.slice(5, 7));
  if (!Number.isFinite(year) || !Number.isFinite(month) || month < 1 || month > 12) return null;

  return {
    id: String(row.id),
    codigo: String(row.codigo ?? row.id),
    titulo: String(row.titulo ?? "").trim(),
    status: normalized,
    emissaoDate: date,
    year,
    month,
    clienteKey: getClientKey(row),
    clienteNome: getClientName(row),
    vendedorKey: getVendorKey(row),
    vendedorNome: getVendorName(row),
    valor: n(row.total_liquido),
  };
}

function MetricCell({ value, count }: { value: number; count: number }) {
  return (
    <>
      <div className="tabular-nums text-zinc-100">{formatMoneyBR(value)}</div>
      <div className="mt-1 text-[11px] text-zinc-500">{formatCount(count)}</div>
    </>
  );
}

function TabButton({ active, onClick, label }: { active: boolean; onClick: () => void; label: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-md border px-3 py-2 text-sm transition ${
        active
          ? "border-zinc-200 bg-zinc-100 text-zinc-900"
          : "border-zinc-800 bg-zinc-950 text-zinc-200 hover:bg-zinc-900"
      }`}
    >
      {label}
    </button>
  );
}

function StatusButton({
  active,
  onClick,
  label,
  tone,
}: {
  active: boolean;
  onClick: () => void;
  label: string;
  tone: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-md border px-3 py-2 text-sm transition ${
        active ? tone : "border-zinc-800 bg-zinc-950 text-zinc-300 hover:bg-zinc-900"
      }`}
    >
      {label}
    </button>
  );
}

function StatCard({ title, value, subtitle }: { title: string; value: string; subtitle?: string }) {
  return (
    <section className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
      <div className="text-xs uppercase tracking-[0.16em] text-zinc-500">{title}</div>
      <div className="mt-2 text-2xl font-semibold text-zinc-100">{value}</div>
      {subtitle ? <div className="mt-1 text-xs text-zinc-500">{subtitle}</div> : null}
    </section>
  );
}

function TableCard({ title, subtitle, children }: { title: string; subtitle?: string; children: ReactNode }) {
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

export default function AnaliticoOrcamentosClient() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const te = useTenantEmpresa();
  const { loading: permissionsLoading, ready, capabilities } = usePermissions();

  const currentYear = new Date().getFullYear();
  const defaultFromYear = Math.max(BASE_YEAR, currentYear - 4);
  const initialFromYear = clamp(parsePositiveInt(searchParams.get("from"), defaultFromYear), BASE_YEAR, currentYear);
  const initialToYear = clamp(parsePositiveInt(searchParams.get("to"), currentYear), BASE_YEAR, currentYear);
  const normalizedInitialFromYear = Math.min(initialFromYear, initialToYear);
  const normalizedInitialToYear = Math.max(initialFromYear, initialToYear);
  const initialFocusYear = clamp(
    parsePositiveInt(searchParams.get("focus"), normalizedInitialToYear),
    normalizedInitialFromYear,
    normalizedInitialToYear
  );

  const canView = hasAny(capabilities, ["financeiro.read", "financeiro.write", "os.read", "os.write"]);

  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

  const tenantId = te.tenantId;
  const empresaId = te.empresaId;

  const [view, setView] = useState<ViewMode>(parseViewMode(searchParams.get("view")));
  const [statusScope, setStatusScope] = useState<StatusScope>(parseStatusScope(searchParams.get("status")));
  const [fromYear, setFromYear] = useState<number>(normalizedInitialFromYear);
  const [toYear, setToYear] = useState<number>(normalizedInitialToYear);
  const [focusYear, setFocusYear] = useState<number>(initialFocusYear);
  const [clientQuery, setClientQuery] = useState<string>(searchParams.get("cliente") ?? "");
  const [topN, setTopN] = useState<number>(clamp(parsePositiveInt(searchParams.get("top"), DEFAULT_TOP_N), 5, 200));

  const [rows, setRows] = useState<OrcamentoAnaliticoRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

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
    if (!canView) return;
    if (!supabase) return;
    if (!tenantId || !empresaId) {
      setRows([]);
      setLoading(false);
      setError("Contexto (tenant/empresa) nao carregado.");
      return;
    }

    let cancelled = false;

    const run = async () => {
      setLoading(true);
      setError(null);

      try {
        const data = await listOrcamentosAnalitico(supabase, {
          tenantId,
          empresaId,
          from: `${fromYear}-01-01`,
          to: `${toYear}-12-31`,
        });

        if (cancelled) return;
        setRows(data);
      } catch (loadError: unknown) {
        if (cancelled) return;
        setRows([]);
        setError(loadError instanceof Error ? loadError.message : "Erro ao carregar o analitico de orcamentos.");
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    void run();

    return () => {
      cancelled = true;
    };
  }, [canView, empresaId, fromYear, supabase, tenantId, toYear]);

  const orcamentos = useMemo(
    () =>
      rows
        .map(mapRow)
        .filter((row): row is OrcamentoAnalitico => Boolean(row))
        .filter((row) => row.year >= fromYear && row.year <= toYear),
    [fromYear, rows, toYear]
  );

  const summaryByStatus = useMemo<StatusSummary>(() => {
    const base: StatusSummary = {
      ANDAMENTO: { valor: 0, quantidade: 0 },
      FECHADO: { valor: 0, quantidade: 0 },
      PERDIDO: { valor: 0, quantidade: 0 },
    };

    for (const row of orcamentos) {
      base[row.status].valor += row.valor;
      base[row.status].quantidade += 1;
    }

    return base;
  }, [orcamentos]);

  const filteredRows = useMemo(
    () => orcamentos.filter((row) => matchesScope(row.status, statusScope)),
    [orcamentos, statusScope]
  );

  const filteredClientTerm = clientQuery.trim().toLowerCase();
  const activeClientTerm = view === "mes-cliente" || view === "ano-cliente" ? filteredClientTerm : "";

  const filteredByClientQuery = useMemo(
    () =>
      activeClientTerm
        ? filteredRows.filter((row) => row.clienteNome.toLowerCase().includes(activeClientTerm))
        : filteredRows,
    [activeClientTerm, filteredRows]
  );

  const totalValor = useMemo(() => filteredRows.reduce((acc, row) => acc + row.valor, 0), [filteredRows]);
  const totalOrcamentos = filteredRows.length;
  const clientesAtivos = useMemo(() => new Set(filteredRows.map((row) => row.clienteKey)).size, [filteredRows]);
  const vendedoresAtivos = useMemo(() => new Set(filteredRows.map((row) => row.vendedorKey)).size, [filteredRows]);
  const ticketMedio = totalOrcamentos > 0 ? totalValor / totalOrcamentos : 0;

  const decisoesQtd = summaryByStatus.FECHADO.quantidade + summaryByStatus.PERDIDO.quantidade;
  const decisoesValor = summaryByStatus.FECHADO.valor + summaryByStatus.PERDIDO.valor;
  const conversaoQtd = decisoesQtd > 0 ? (summaryByStatus.FECHADO.quantidade / decisoesQtd) * 100 : null;
  const conversaoValor = decisoesValor > 0 ? (summaryByStatus.FECHADO.valor / decisoesValor) * 100 : null;

  const yearIndexMap = useMemo(() => new Map(years.map((year, index) => [year, index])), [years]);

  const yearRows = useMemo<AnoResumo[]>(() => {
    const totals = new Map<number, { totalValor: number; quantidade: number; clientes: Set<string>; vendedores: Set<string> }>();

    for (const year of years) {
      totals.set(year, { totalValor: 0, quantidade: 0, clientes: new Set<string>(), vendedores: new Set<string>() });
    }

    for (const row of filteredRows) {
      const bucket = totals.get(row.year);
      if (!bucket) continue;
      bucket.totalValor += row.valor;
      bucket.quantidade += 1;
      bucket.clientes.add(row.clienteKey);
      bucket.vendedores.add(row.vendedorKey);
    }

    return years.map((year) => {
      const bucket = totals.get(year) ?? { totalValor: 0, quantidade: 0, clientes: new Set<string>(), vendedores: new Set<string>() };
      return {
        ano: year,
        totalValor: bucket.totalValor,
        quantidade: bucket.quantidade,
        clientes: bucket.clientes.size,
        vendedores: bucket.vendedores.size,
        ticketMedio: bucket.quantidade > 0 ? bucket.totalValor / bucket.quantidade : 0,
      };
    });
  }, [filteredRows, years]);

  const monthByYear = useMemo(() => {
    const byYear = new Map<number, MonthBucket>();
    for (const year of years) {
      byYear.set(year, {
        valores: Array.from({ length: 12 }, () => 0),
        quantidades: Array.from({ length: 12 }, () => 0),
      });
    }

    for (const row of filteredRows) {
      const bucket = byYear.get(row.year);
      if (!bucket) continue;
      bucket.valores[row.month - 1] += row.valor;
      bucket.quantidades[row.month - 1] += 1;
    }

    return byYear;
  }, [filteredRows, years]);

  const monthClientRows = useMemo<ClienteMesResumo[]>(() => {
    const byClient = new Map<string, ClienteMesResumo>();

    for (const row of filteredByClientQuery) {
      if (row.year !== focusYear) continue;

      const current =
        byClient.get(row.clienteKey) ??
        {
          clienteKey: row.clienteKey,
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
      byClient.set(row.clienteKey, current);
    }

    return Array.from(byClient.values())
      .sort((a, b) => b.totalValor - a.totalValor || b.quantidade - a.quantidade || a.clienteNome.localeCompare(b.clienteNome))
      .slice(0, topN);
  }, [filteredByClientQuery, focusYear, topN]);

  const yearClientRows = useMemo<ClienteAnoResumo[]>(() => {
    const byClient = new Map<string, ClienteAnoResumo>();

    for (const row of filteredByClientQuery) {
      const yearIndex = yearIndexMap.get(row.year);
      if (yearIndex === undefined) continue;

      const current =
        byClient.get(row.clienteKey) ??
        {
          clienteKey: row.clienteKey,
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
      byClient.set(row.clienteKey, current);
    }

    return Array.from(byClient.values())
      .sort((a, b) => b.totalValor - a.totalValor || b.quantidade - a.quantidade || a.clienteNome.localeCompare(b.clienteNome))
      .slice(0, topN);
  }, [filteredByClientQuery, topN, yearIndexMap, years.length]);

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

  if (!ready && permissionsLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissoes...</div>;
  }

  if (!canView) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <div className="text-xs uppercase tracking-[0.18em] text-zinc-500">Comercial</div>
          <h1 className="mt-1 text-2xl font-semibold text-zinc-100">Analitico</h1>
          <p className="mt-1 text-sm text-zinc-400">
            Base: orcamentos por emissao. Status considerados: abertos, fechados e perdidos.
          </p>
          <p className="mt-1 text-xs text-zinc-500">
            O filtro principal usa os orcamentos {getStatusLabel(statusScope)} dentro do periodo selecionado.
          </p>
        </div>
        <Link
          href="/comercial/orcamentos"
          className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-900"
        >
          Voltar para Orcamentos
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
          <StatusButton active={statusScope === "abertos"} onClick={() => setStatusScope("abertos")} label="Abertos" tone={getStatusTone("abertos")} />
          <StatusButton active={statusScope === "fechados"} onClick={() => setStatusScope("fechados")} label="Fechados" tone={getStatusTone("fechados")} />
          <StatusButton active={statusScope === "perdidos"} onClick={() => setStatusScope("perdidos")} label="Perdidos" tone={getStatusTone("perdidos")} />
          <StatusButton active={statusScope === "todos"} onClick={() => setStatusScope("todos")} label="Todos" tone={getStatusTone("todos")} />
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
            <div className="md:col-span-3 flex items-end">
              <div className={`rounded-md border px-3 py-2 text-xs ${getStatusTone(statusScope)}`}>
                Filtros sincronizados na URL para compartilhamento da visao.
              </div>
            </div>
          )}
        </div>
      </section>

      <div className="grid grid-cols-1 gap-3 md:grid-cols-6">
        <StatCard
          title="Total filtrado"
          value={formatMoneyBR(totalValor)}
          subtitle={`${formatCount(totalOrcamentos)} | ${getStatusLabel(statusScope)} | ${fromYear} a ${toYear}`}
        />
        <StatCard
          title="Base filtrada"
          value={String(totalOrcamentos)}
          subtitle={`Clientes: ${clientesAtivos} | Vendedores: ${vendedoresAtivos}`}
        />
        <StatCard
          title="Em aberto"
          value={formatMoneyBR(summaryByStatus.ANDAMENTO.valor)}
          subtitle={formatCount(summaryByStatus.ANDAMENTO.quantidade)}
        />
        <StatCard
          title="Fechados"
          value={formatMoneyBR(summaryByStatus.FECHADO.valor)}
          subtitle={formatCount(summaryByStatus.FECHADO.quantidade)}
        />
        <StatCard
          title="Perdidos"
          value={formatMoneyBR(summaryByStatus.PERDIDO.valor)}
          subtitle={formatCount(summaryByStatus.PERDIDO.quantidade)}
        />
        <StatCard
          title="Conversao"
          value={formatPercent(conversaoQtd)}
          subtitle={`Valor: ${formatPercent(conversaoValor)} | Base: ${decisoesQtd} decididos`}
        />
      </div>

      <section className="rounded-xl border border-zinc-800 bg-zinc-950 px-4 py-3 text-sm text-zinc-300">
        Ticket medio filtrado: <span className="tabular-nums text-zinc-100">{formatMoneyBR(ticketMedio)}</span>
      </section>

      {error ? <div className="rounded-xl border border-rose-500/30 bg-rose-500/10 px-4 py-3 text-sm text-rose-200">{error}</div> : null}

      {loading ? (
        <section className="rounded-xl border border-zinc-800 bg-zinc-950 px-4 py-8 text-sm text-zinc-400">Carregando dados...</section>
      ) : null}

      {!loading && filteredRows.length === 0 ? (
        <section className="rounded-xl border border-zinc-800 bg-zinc-950 px-4 py-8 text-sm text-zinc-400">
          Nenhum orcamento encontrado para os filtros selecionados.
        </section>
      ) : null}

      {!loading && filteredRows.length > 0 && view === "mes" ? (
        <TableCard title="Mes x Ano" subtitle={`Totais por emissao para orcamentos ${getStatusLabel(statusScope)}.`}>
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
                <tr key={label} className="border-b border-zinc-900/70">
                  <th className="sticky left-0 bg-zinc-950 px-4 py-3 text-left font-medium text-zinc-300">{label}</th>
                  {years.map((year) => {
                    const bucket = monthByYear.get(year);
                    const value = bucket?.valores[monthIndex] ?? 0;
                    const count = bucket?.quantidades[monthIndex] ?? 0;
                    return (
                      <td key={`${label}-${year}`} className="px-4 py-3 text-right align-top">
                        <MetricCell value={value} count={count} />
                      </td>
                    );
                  })}
                  <td className="bg-zinc-900/30 px-4 py-3 text-right align-top">
                    <MetricCell value={monthRowTotals[monthIndex]?.valor ?? 0} count={monthRowTotals[monthIndex]?.quantidade ?? 0} />
                  </td>
                </tr>
              ))}
              <tr className="bg-zinc-900/40">
                <th className="sticky left-0 bg-zinc-900 px-4 py-3 text-left font-semibold text-zinc-100">Total</th>
                {yearColumnTotals.map((total, index) => (
                  <td key={years[index]} className="px-4 py-3 text-right align-top font-semibold">
                    <MetricCell value={total.valor} count={total.quantidade} />
                  </td>
                ))}
                <td className="px-4 py-3 text-right align-top font-semibold">
                  <MetricCell value={totalValor} count={totalOrcamentos} />
                </td>
              </tr>
            </tbody>
          </table>
        </TableCard>
      ) : null}

      {!loading && filteredRows.length > 0 && view === "ano" ? (
        <TableCard title="Ano" subtitle={`Resumo anual para orcamentos ${getStatusLabel(statusScope)}.`}>
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-800 text-zinc-400">
                <th className="px-4 py-3 text-left font-medium">Ano</th>
                <th className="px-4 py-3 text-right font-medium">Orcamentos</th>
                <th className="px-4 py-3 text-right font-medium">Clientes</th>
                <th className="px-4 py-3 text-right font-medium">Vendedores</th>
                <th className="px-4 py-3 text-right font-medium">Ticket medio</th>
                <th className="px-4 py-3 text-right font-medium">Total</th>
              </tr>
            </thead>
            <tbody>
              {yearRows.map((row) => (
                <tr key={row.ano} className="border-b border-zinc-900/70">
                  <td className="px-4 py-3 font-medium text-zinc-200">{row.ano}</td>
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{row.quantidade}</td>
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{row.clientes}</td>
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{row.vendedores}</td>
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{formatMoneyBR(row.ticketMedio)}</td>
                  <td className="px-4 py-3 text-right tabular-nums text-emerald-200">{formatMoneyBR(row.totalValor)}</td>
                </tr>
              ))}
              <tr className="bg-zinc-900/40">
                <td className="px-4 py-3 font-semibold text-zinc-100">Total</td>
                <td className="px-4 py-3 text-right tabular-nums font-semibold text-zinc-100">{totalOrcamentos}</td>
                <td className="px-4 py-3 text-right tabular-nums font-semibold text-zinc-100">{clientesAtivos}</td>
                <td className="px-4 py-3 text-right tabular-nums font-semibold text-zinc-100">{vendedoresAtivos}</td>
                <td className="px-4 py-3 text-right tabular-nums font-semibold text-zinc-100">{formatMoneyBR(ticketMedio)}</td>
                <td className="px-4 py-3 text-right tabular-nums font-semibold text-emerald-200">{formatMoneyBR(totalValor)}</td>
              </tr>
            </tbody>
          </table>
        </TableCard>
      ) : null}

      {!loading && filteredRows.length > 0 && view === "mes-cliente" ? (
        <TableCard
          title={`Mes / Cliente - ${focusYear}`}
          subtitle={`Top ${topN} clientes para orcamentos ${getStatusLabel(statusScope)} no ano selecionado.`}
        >
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-800 text-zinc-400">
                <th className="sticky left-0 bg-zinc-950 px-4 py-3 text-left font-medium">Cliente</th>
                {MONTH_LABELS.map((month) => (
                  <th key={month} className="px-4 py-3 text-right font-medium">
                    {month}
                  </th>
                ))}
                <th className="px-4 py-3 text-right font-medium">Total</th>
              </tr>
            </thead>
            <tbody>
              {monthClientRows.map((row) => (
                <tr key={row.clienteKey} className="border-b border-zinc-900/70">
                  <th className="sticky left-0 bg-zinc-950 px-4 py-3 text-left font-medium text-zinc-200">{row.clienteNome}</th>
                  {row.valores.map((value, index) => (
                    <td key={`${row.clienteKey}-${index}`} className="px-4 py-3 text-right align-top">
                      <MetricCell value={value} count={row.quantidades[index] ?? 0} />
                    </td>
                  ))}
                  <td className="bg-zinc-900/30 px-4 py-3 text-right align-top">
                    <MetricCell value={row.totalValor} count={row.quantidade} />
                  </td>
                </tr>
              ))}
              <tr className="bg-zinc-900/40">
                <th className="sticky left-0 bg-zinc-900 px-4 py-3 text-left font-semibold text-zinc-100">Subtotal</th>
                {subtotalMesCliente.valores.slice(0, 12).map((value, index) => (
                  <td key={`subtotal-${index}`} className="px-4 py-3 text-right align-top font-semibold">
                    <MetricCell value={value} count={subtotalMesCliente.quantidades[index] ?? 0} />
                  </td>
                ))}
                <td className="px-4 py-3 text-right align-top font-semibold">
                  <MetricCell value={subtotalMesCliente.valores[12] ?? 0} count={subtotalMesCliente.quantidades[12] ?? 0} />
                </td>
              </tr>
            </tbody>
          </table>
        </TableCard>
      ) : null}

      {!loading && filteredRows.length > 0 && view === "ano-cliente" ? (
        <TableCard title="Ano / Cliente" subtitle={`Top ${topN} clientes considerando ${fromYear} a ${toYear}.`}>
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-800 text-zinc-400">
                <th className="sticky left-0 bg-zinc-950 px-4 py-3 text-left font-medium">Cliente</th>
                {years.map((year) => (
                  <th key={year} className="px-4 py-3 text-right font-medium">
                    {year}
                  </th>
                ))}
                <th className="px-4 py-3 text-right font-medium">Total</th>
              </tr>
            </thead>
            <tbody>
              {yearClientRows.map((row) => (
                <tr key={row.clienteKey} className="border-b border-zinc-900/70">
                  <th className="sticky left-0 bg-zinc-950 px-4 py-3 text-left font-medium text-zinc-200">{row.clienteNome}</th>
                  {row.valores.map((value, index) => (
                    <td key={`${row.clienteKey}-${years[index]}`} className="px-4 py-3 text-right align-top">
                      <MetricCell value={value} count={row.quantidades[index] ?? 0} />
                    </td>
                  ))}
                  <td className="bg-zinc-900/30 px-4 py-3 text-right align-top">
                    <MetricCell value={row.totalValor} count={row.quantidade} />
                  </td>
                </tr>
              ))}
              <tr className="bg-zinc-900/40">
                <th className="sticky left-0 bg-zinc-900 px-4 py-3 text-left font-semibold text-zinc-100">Subtotal</th>
                {subtotalAnoCliente.valores.slice(0, years.length).map((value, index) => (
                  <td key={`subtotal-ano-${years[index]}`} className="px-4 py-3 text-right align-top font-semibold">
                    <MetricCell value={value} count={subtotalAnoCliente.quantidades[index] ?? 0} />
                  </td>
                ))}
                <td className="px-4 py-3 text-right align-top font-semibold">
                  <MetricCell
                    value={subtotalAnoCliente.valores[years.length] ?? 0}
                    count={subtotalAnoCliente.quantidades[years.length] ?? 0}
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </TableCard>
      ) : null}
    </div>
  );
}
