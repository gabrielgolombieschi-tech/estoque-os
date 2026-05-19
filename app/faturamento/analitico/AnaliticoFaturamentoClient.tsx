"use client";

import Link from "next/link";
import { useEffect, useMemo, useState, type ReactNode } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { formatMoneyBR } from "@/lib/decimal";
import { buildEmpresaDisplayOptions, fetchTenantEmpresas, mergeEmpresaInfos } from "@/app/faturamento/components/empresaDisplay";
import { manualHistoricalEntries, manualHistoricalYears } from "./historicoManual";

type ViewMode = "mes" | "mes-cliente" | "ano" | "ano-cliente";

type DocumentoFiscalRow = {
  id: string;
  emissao_date: string | null;
  competencia_date: string | null;
  empresa_id: string | null;
  cliente_id: number | null;
  valor_total: number | string | null;
  modelo: string | null;
  nfe_status: string | null;
  nfse_status: string | null;
  created_at: string;
};

type ClienteRow = {
  id: number;
  nome: string;
};

type DocumentoAnalitico = {
  id: string;
  year: number;
  month: number;
  valor: number;
  clienteNome: string;
};

type AnoResumo = {
  ano: number;
  total: number;
  documentos: number;
  clientes: number;
  ticketMedio: number;
};

type ClienteMesResumo = {
  clienteNome: string;
  meses: number[];
  total: number;
};

type ClienteAnoResumo = {
  clienteNome: string;
  anos: number[];
  total: number;
};

type MetaStatus = "met" | "near" | "below" | "none";
type ClientNameSignature = {
  fullKey: string;
  cleanKey: string;
  baseKey: string;
  familyKey: string | null;
};

const BASE_YEAR = 2017;
const FETCH_BATCH_SIZE = 1000;
const CLIENT_BATCH_SIZE = 200;
const DEFAULT_TOP_N = 20;
const MONTH_LABELS = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"] as const;
const MANUAL_HISTORICAL_YEAR_SET = new Set(manualHistoricalYears);
const CLIENT_NAME_NOISE_TOKENS = new Set(["SA", "LTDA", "EIRELI", "ME", "EPP", "MATRIZ", "FILIAL", "FAB", "FABRICA"]);
const CLIENT_NAME_FAMILY_CANONICAL: Partial<Record<string, string>> = {
  ARCELORMITTAL: "ARCELORMITTAL",
  CREMER: "CREMER",
  TUPY: "TUPY",
  EMBRACO: "EMBRACO",
  "KRAH-ICE": "KRAH-ICE",
  KOALA: "KOALA",
  WHIRLPOOL: "WHIRLPOOL",
  ELIANE: "ELIANE",
  SCHULZ: "SCHULZ",
  "REGIONAL TELHAS": "REGIONAL TELHAS",
  WEG_TINTAS: "WEG TINTAS",
  POINTER: "POINTER",
  INCEPA: "INCEPA",
  "FOCUS SUL": "FOCUS SUL",
  FAMOSSUL: "FAMOSSUL",
  FORTLEV: "FORTLEV",
  "CT SERVICES": "CT SERVICES",
  MEBIUS: "MEBIUS",
  SIEMENS: "SIEMENS HEALTHCARE DIAGNOSTICOS LTDA.",
  KRONA: "KRONA",
  MOHAWK: "MOHAWK",
  RIOSULENSE: "RIOSULENSE",
};
const CLIENT_NAME_EXACT_CANONICAL: Partial<Record<string, string>> = {
  ARCELORMITTAL: "ARCELORMITTAL",
  "ARCELORMITTAL BRASIL SA": "ARCELORMITTAL",
  "CT SERVICES": "CT SERVICES",
  "CT SERVICES SOLUCOES EM AUTOMACAO LTDA": "CT SERVICES",
  "FAMOS SUL": "FAMOSSUL",
  FAMOSSUL: "FAMOSSUL",
  "FAMOSSUL MADEIRAS NORDESTE LTDA": "FAMOSSUL",
  "FAMOSSUL MADEIRAS SA MADEIRAS": "FAMOSSUL",
  FORTLEV: "FORTLEV",
  "FORTLEV INDUS E COMERC DE PLASTICO LTDA": "FORTLEV",
  FOCUSSUL: "FOCUS SUL",
  "INCEPA REVESTIMENTOS CERAMICOS LTDA": "INCEPA",
  KRONA: "KRONA",
  "KRONA TUBOS E CONEXOES LTDA": "KRONA",
  MEBIUS: "MEBIUS",
  "MEBIUS COMERCIO DE MAQUINAS INDUSTRIAIS LTDA": "MEBIUS",
  "METALURGICA RIOSULENSE SA": "RIOSULENSE",
  MOHAWK: "MOHAWK",
  "MOHAWK REVESTIMENTOS COCAL DO SUL LTDA": "MOHAWK",
  RIOSULENSE: "RIOSULENSE",
  SIEMENS: "SIEMENS HEALTHCARE DIAGNOSTICOS LTDA.",
  "SIEMENS HEALTHC": "SIEMENS HEALTHCARE DIAGNOSTICOS LTDA.",
  "SIEMENS HEALTHCARE": "SIEMENS HEALTHCARE DIAGNOSTICOS LTDA.",
  "SIEMENS HEALTHCARE DIAGNOSTICOS LTDA": "SIEMENS HEALTHCARE DIAGNOSTICOS LTDA.",
  "SIEMENS PERINI": "SIEMENS HEALTHCARE DIAGNOSTICOS LTDA.",
  TUPER: "TUPER",
  "TUPER SA DIV TUBOS": "TUPER",
  "WEG TINTAS": "WEG TINTAS",
  "WEG TINTAS LTDA": "WEG TINTAS",
};
const CLIENT_NAME_BASE_NOISE_TOKENS = new Set([
  "SA",
  "LTDA",
  "EIRELI",
  "ME",
  "EPP",
  "MATRIZ",
  "FILIAL",
  "FAB",
  "FABRICA",
  "CIA",
  "COMPANHIA",
  "SOCIEDADE",
  "IND",
  "INDUSTRIA",
  "INDUSTRIAL",
  "COM",
  "COMERCIO",
  "COMERCIAL",
  "DE",
  "DA",
  "DO",
  "DAS",
  "DOS",
  "E",
  "PROD",
  "PRODS",
  "PRODUTO",
  "PRODUTOS",
  "SIDERURGICO",
  "SIDERURGICOS",
]);
const FATURAMENTO_TARGETS_BY_YEAR: Partial<Record<number, number>> = {
  2017: 190000,
  2018: 214700,
  2019: 242611,
  2020: 274150.43,
  2021: 309789.99,
  2022: 350062.68,
  2023: 395570.83,
  2024: 446995.04,
  2025: 558743.8,
  2026: 698429.75,
};

function n(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

function parseViewMode(value: string | null): ViewMode {
  if (value === "mes") return "mes";
  if (value === "mes-cliente") return "mes-cliente";
  if (value === "ano") return "ano";
  if (value === "ano-cliente") return "ano-cliente";
  return "mes";
}

function parsePositiveInt(value: string | null, fallback: number): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.trunc(parsed);
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function normalizeSelectedEmpresaIds(selectedIds: string[], availableIds: string[]): string[] {
  if (!availableIds.length) return [];

  const availableSet = new Set(availableIds);
  const selectedSet = new Set(selectedIds.filter((id) => availableSet.has(id)));
  if (!selectedSet.size) return availableIds;
  return availableIds.filter((id) => selectedSet.has(id));
}

function getReferenceDate(row: DocumentoFiscalRow): string | null {
  const raw = String(row.competencia_date ?? row.emissao_date ?? "").slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return null;
  return raw;
}

function shouldIncludeDocumento(row: DocumentoFiscalRow): boolean {
  const modelo = String(row.modelo ?? "").trim().toUpperCase();
  const nfseStatus = String(row.nfse_status ?? "").trim().toUpperCase();
  const nfeStatus = String(row.nfe_status ?? "").trim().toUpperCase();

  if (modelo === "NFSE") return nfseStatus === "EMITIDA";
  if (!nfeStatus) return true;
  return nfeStatus === "EMITIDA";
}

function mapLiveDocumento(
  row: DocumentoFiscalRow,
  clientesById: Record<string, string>,
  range?: { fromYear?: number; toYear?: number }
): DocumentoAnalitico | null {
  const date = getReferenceDate(row);
  if (!date) return null;

  const year = Number(date.slice(0, 4));
  const month = Number(date.slice(5, 7));
  if (!Number.isFinite(year) || !Number.isFinite(month) || month < 1 || month > 12) return null;
  if (typeof range?.fromYear === "number" && year < range.fromYear) return null;
  if (typeof range?.toYear === "number" && year > range.toYear) return null;
  if (MANUAL_HISTORICAL_YEAR_SET.has(year)) return null;

  const clienteNome =
    typeof row.cliente_id === "number"
      ? clientesById[String(row.cliente_id)]?.trim() || `Cliente ${row.cliente_id}`
      : "(Sem cliente)";

  return {
    id: String(row.id),
    year,
    month,
    valor: n(row.valor_total),
    clienteNome,
  };
}

function getMetaStatus(value: number, target: number | null | undefined): MetaStatus {
  if (!target || target <= 0) return "none";
  if (value >= target) return "met";
  if (value > target * 0.9) return "near";
  return "below";
}

function getMetaToneClass(status: MetaStatus): string {
  if (status === "met") return "bg-emerald-500/10 text-emerald-200";
  if (status === "near") return "bg-amber-500/10 text-amber-200";
  if (status === "below") return "bg-rose-500/10 text-rose-200";
  return "text-zinc-100";
}

function normalizeClientNameText(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/\bS[\s./-]*A\b/g, " SA ")
    .replace(/\bFAB\.?\s*([IVX]+)\b/g, " $1 ")
    .replace(/[^\w\s]/g, " ")
    .replace(/_/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function getClientNameSignature(value: string): ClientNameSignature {
  const fullKey = normalizeClientNameText(value);
  const cleanTokens = fullKey.split(" ").filter((token) => token && !CLIENT_NAME_NOISE_TOKENS.has(token));
  const cleanKey = cleanTokens.join(" ");
  const baseTokens = cleanTokens.filter((token) => token && !CLIENT_NAME_BASE_NOISE_TOKENS.has(token));
  const baseKey = baseTokens.join(" ");
  const hasWegFamily = baseTokens.includes("WEG") && (baseTokens.includes("TINTAS") || baseTokens.includes("PAUMAR") || baseTokens.length === 1);
  const hasArcelorFamily = baseTokens.includes("ARCELORMITTAL");
  const hasCremerFamily = baseTokens.includes("CREMER");
  const hasTupyFamily = baseTokens.includes("TUPY");
  const hasEmbracoFamily = baseTokens.includes("EMBRACO");
  const hasKrahIceFamily = baseTokens.includes("KRAH") && baseTokens.includes("ICE");
  const hasKoalaFamily = baseTokens.includes("KOALA");
  const hasWhirlpoolFamily = baseTokens.includes("WHIRLPOOL");
  const hasElianeFamily = baseTokens.includes("ELIANE");
  const hasSchulzFamily = baseTokens.includes("SCHULZ");
  const hasRegionalTelhasFamily = baseTokens.includes("REGIONAL") && baseTokens.includes("TELHAS");
  const hasPointerFamily = baseTokens.includes("POINTER");
  const hasIncepaFamily = baseTokens.includes("INCEPA");
  const hasFocusSulFamily = baseTokens.includes("FOCUSSUL") || (baseTokens.includes("FOCUS") && baseTokens.includes("SUL"));
  const hasFamossulFamily = baseTokens.includes("FAMOSSUL") || (baseTokens.includes("FAMOS") && baseTokens.includes("SUL"));
  const hasFortlevFamily = baseTokens.includes("FORTLEV");
  const hasCtServicesFamily = baseTokens.includes("CT") && baseTokens.includes("SERVICES");
  const hasMebiusFamily = baseTokens.includes("MEBIUS");
  const hasSiemensFamily = baseTokens.includes("SIEMENS");
  const hasKronaFamily = baseTokens.includes("KRONA");
  const hasMohawkFamily = baseTokens.includes("MOHAWK");
  const hasRiosulenseFamily = baseTokens.includes("RIOSULENSE");

  return {
    fullKey,
    cleanKey,
    baseKey,
    familyKey: hasArcelorFamily
      ? "ARCELORMITTAL"
      : hasCremerFamily
        ? "CREMER"
      : hasTupyFamily
        ? "TUPY"
      : hasEmbracoFamily
        ? "EMBRACO"
      : hasKrahIceFamily
        ? "KRAH-ICE"
      : hasKoalaFamily
        ? "KOALA"
      : hasWhirlpoolFamily
        ? "WHIRLPOOL"
        : hasElianeFamily
          ? "ELIANE"
          : hasSchulzFamily
            ? "SCHULZ"
        : hasRegionalTelhasFamily
          ? "REGIONAL TELHAS"
          : hasPointerFamily
            ? "POINTER"
          : hasIncepaFamily
            ? "INCEPA"
          : hasFocusSulFamily
            ? "FOCUS SUL"
          : hasFamossulFamily
            ? "FAMOSSUL"
          : hasFortlevFamily
            ? "FORTLEV"
          : hasCtServicesFamily
            ? "CT SERVICES"
          : hasMebiusFamily
            ? "MEBIUS"
          : hasSiemensFamily
            ? "SIEMENS"
          : hasKronaFamily
            ? "KRONA"
          : hasMohawkFamily
            ? "MOHAWK"
          : hasRiosulenseFamily
            ? "RIOSULENSE"
          : hasWegFamily
            ? "WEG_TINTAS"
            : null,
  };
}

function resolveExactCanonicalClientName(value: string): string {
  let current = value;
  const seen = new Set<string>();

  while (true) {
    const signature = getClientNameSignature(current);
    if (!signature.fullKey || seen.has(signature.fullKey)) return current;
    seen.add(signature.fullKey);

    const next = CLIENT_NAME_EXACT_CANONICAL[signature.fullKey];
    if (!next || next === current) return current;
    current = next;
  }
}

function pickPreferredReferenceName(names: string[], totals: Map<string, number>): string | null {
  const uniqueNames = Array.from(new Set(names));
  if (!uniqueNames.length) return null;

  return uniqueNames.sort((left, right) => {
    const totalDiff = (totals.get(right) ?? 0) - (totals.get(left) ?? 0);
    if (totalDiff !== 0) return totalDiff;

    const leftSignature = getClientNameSignature(left);
    const rightSignature = getClientNameSignature(right);
    const cleanLengthDiff = leftSignature.cleanKey.length - rightSignature.cleanKey.length;
    if (cleanLengthDiff !== 0) return cleanLengthDiff;

    const fullLengthDiff = leftSignature.fullKey.length - rightSignature.fullKey.length;
    if (fullLengthDiff !== 0) return fullLengthDiff;

    return left.localeCompare(right);
  })[0];
}

async function fetchClientesByIds(params: {
  tenantId: string;
  empresaId: string;
  ids: number[];
}): Promise<Record<string, string>> {
  const supabase = getSupabaseBrowser();
  const out: Record<string, string> = {};

  for (let offset = 0; offset < params.ids.length; offset += CLIENT_BATCH_SIZE) {
    const chunk = params.ids.slice(offset, offset + CLIENT_BATCH_SIZE);
    if (!chunk.length) continue;

    const { data, error } = await applyTenantEmpresa(
      supabase.from("clientes").select("id,nome").in("id", chunk),
      params.tenantId,
      params.empresaId
    ).returns<ClienteRow[]>();

    if (error) throw error;

    for (const row of data ?? []) {
      if (typeof row?.id !== "number") continue;
      out[String(row.id)] = String(row.nome ?? "").trim();
    }
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
      <div className="mt-2 text-2xl font-semibold text-zinc-100 tabular-nums">{value}</div>
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

export default function AnaliticoFaturamentoClient() {
  const te = useTenantEmpresa();
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

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
  const [fromYear, setFromYear] = useState<number>(normalizedInitialFromYear);
  const [toYear, setToYear] = useState<number>(normalizedInitialToYear);
  const [focusYear, setFocusYear] = useState<number>(initialFocusYear);
  const [clientQuery, setClientQuery] = useState<string>(searchParams.get("cliente") ?? "");
  const [topN, setTopN] = useState<number>(clamp(parsePositiveInt(searchParams.get("top"), DEFAULT_TOP_N), 5, 200));
  const [empresaCatalog, setEmpresaCatalog] = useState(te.empresas);

  const [rows, setRows] = useState<DocumentoFiscalRow[]>([]);
  const [clientesById, setClientesById] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const empresaOptions = useMemo(() => buildEmpresaDisplayOptions(empresaCatalog), [empresaCatalog]);
  const allEmpresaIds = useMemo(() => empresaOptions.map((empresa) => empresa.id), [empresaOptions]);
  const selectedEmpresaIds = useMemo(
    () => normalizeSelectedEmpresaIds(searchParams.getAll("empresa"), allEmpresaIds),
    [allEmpresaIds, searchParams]
  );
  const selectedEmpresaIdSet = useMemo(() => new Set(selectedEmpresaIds), [selectedEmpresaIds]);
  const hasPendingEmpresaSelection = allEmpresaIds.length === 0 && searchParams.getAll("empresa").length > 0;
  const hasEmpresaFilter = allEmpresaIds.length > 0 && selectedEmpresaIds.length < allEmpresaIds.length;
  const selectedEmpresaLabels = useMemo(
    () => empresaOptions.filter((empresa) => selectedEmpresaIdSet.has(empresa.id)).map((empresa) => empresa.label),
    [empresaOptions, selectedEmpresaIdSet]
  );

  const empresaRole = useMemo(() => {
    const role = te.empresa?.papel ?? te.empresas.find((empresa) => empresa.id === te.empresaId)?.papel ?? null;
    return typeof role === "string" ? role.trim().toUpperCase() : "";
  }, [te.empresa?.papel, te.empresaId, te.empresas]);
  const isFinanceiroEmpresaRole = empresaRole === "FINANCEIRO";

  const canFinanceiro = useMemo(() => {
    const canRead = te.has("financeiro.read");
    const canWrite = te.has("financeiro.write");
    if (isFinanceiroEmpresaRole) return true;
    if (canRead === undefined || canWrite === undefined) return undefined;
    return Boolean(canRead || canWrite);
  }, [isFinanceiroEmpresaRole, te]);

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  const tenantId = te.tenantId ?? null;
  const empresaId = te.empresaId ?? (te.empresas.length === 1 ? te.empresas[0]?.id ?? null : null);
  const ready = typeof te.sessionUserId === "string" && Boolean(tenantId) && Boolean(empresaId) && canFinanceiro === true;

  useEffect(() => {
    setEmpresaCatalog((prev) => mergeEmpresaInfos(prev, te.empresas));
  }, [te.empresas]);

  useEffect(() => {
    if (!tenantId || canFinanceiro !== true) return;

    let cancelled = false;

    const loadEmpresas = async () => {
      try {
        const empresas = await fetchTenantEmpresas(getSupabaseBrowser(), tenantId);
        if (!cancelled) setEmpresaCatalog((prev) => mergeEmpresaInfos(prev, empresas));
      } catch {
        // keep current catalog if tenant-wide lookup is not available
      }
    };

    void loadEmpresas();

    return () => {
      cancelled = true;
    };
  }, [canFinanceiro, tenantId]);

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
    if (hasPendingEmpresaSelection) return;

    const params = new URLSearchParams();
    params.set("view", view);
    params.set("from", String(fromYear));
    params.set("to", String(toYear));
    if (view === "mes-cliente") params.set("focus", String(focusYear));
    if (clientQuery.trim()) params.set("cliente", clientQuery.trim());
    if (topN !== DEFAULT_TOP_N) params.set("top", String(topN));
    if (hasEmpresaFilter) {
      for (const empresa of empresaOptions) {
        if (selectedEmpresaIdSet.has(empresa.id)) params.append("empresa", empresa.id);
      }
    }

    const nextQuery = params.toString();
    const currentQuery = searchParams.toString();
    if (nextQuery !== currentQuery) {
      router.replace(nextQuery ? `${pathname}?${nextQuery}` : pathname);
    }
  }, [
    clientQuery,
    empresaOptions,
    focusYear,
    fromYear,
    hasEmpresaFilter,
    pathname,
    router,
    searchParams,
    hasPendingEmpresaSelection,
    selectedEmpresaIdSet,
    toYear,
    topN,
    view,
  ]);

  const toggleEmpresa = (empresaIdToToggle: string) => {
    const nextSelected = new Set(selectedEmpresaIds);
    if (nextSelected.has(empresaIdToToggle)) {
      nextSelected.delete(empresaIdToToggle);
      if (!nextSelected.size) {
        for (const empresaId of allEmpresaIds) nextSelected.add(empresaId);
      }
    } else {
      nextSelected.add(empresaIdToToggle);
    }

    const normalizedSelection = allEmpresaIds.filter((empresaId) => nextSelected.has(empresaId));
    const params = new URLSearchParams(searchParams.toString());
    params.delete("empresa");
    if (normalizedSelection.length < allEmpresaIds.length) {
      for (const empresaId of normalizedSelection) params.append("empresa", empresaId);
    }

    const nextQuery = params.toString();
    router.replace(nextQuery ? `${pathname}?${nextQuery}` : pathname, { scroll: false });
  };

  useEffect(() => {
    if (!ready || !tenantId || !empresaId) return;

    let cancelled = false;

    const run = async () => {
      setLoading(true);
      setError(null);

      try {
        const supabase = getSupabaseBrowser();
        const queryFromYear = Math.min(fromYear, currentYear);
        const queryToYear = Math.max(toYear, currentYear);
        const startDate = `${queryFromYear}-01-01`;
        const endDate = `${queryToYear + 1}-01-01`;
        const docs: DocumentoFiscalRow[] = [];
        let offset = 0;

        while (true) {
          let query = applyTenantEmpresa(
            supabase
              .schema("f")
              .from("documento_fiscal")
              .select("id,emissao_date,competencia_date,empresa_id,cliente_id,valor_total,modelo,nfe_status,nfse_status,created_at")
              .eq("operacao", "SAIDA")
              .is("deleted_at", null)
              .gte("emissao_date", startDate)
              .lt("emissao_date", endDate)
              .order("emissao_date", { ascending: true, nullsFirst: false })
              .order("created_at", { ascending: true })
              .range(offset, offset + FETCH_BATCH_SIZE - 1),
            tenantId,
            empresaId
          );
          if (hasEmpresaFilter && selectedEmpresaIds.length) {
            query = query.in("empresa_id", selectedEmpresaIds);
          }

          const { data, error: queryError } = await query.returns<DocumentoFiscalRow[]>();

          if (queryError) throw queryError;

          docs.push(...(data ?? []));
          if ((data ?? []).length < FETCH_BATCH_SIZE) break;
          offset += FETCH_BATCH_SIZE;
        }

        const clientIds = Array.from(
          new Set(
            docs
              .map((row) => (typeof row.cliente_id === "number" ? row.cliente_id : null))
              .filter((value): value is number => typeof value === "number")
          )
        );

        const clientMap = clientIds.length ? await fetchClientesByIds({ tenantId, empresaId, ids: clientIds }) : {};

        if (cancelled) return;

        setRows(docs);
        setClientesById(clientMap);
      } catch (loadError: unknown) {
        if (cancelled) return;
        setRows([]);
        setClientesById({});
        setError(loadError instanceof Error ? loadError.message : "Erro ao carregar o analitico de faturamento.");
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    void run();

    return () => {
      cancelled = true;
    };
  }, [currentYear, empresaId, fromYear, hasEmpresaFilter, ready, selectedEmpresaIds, tenantId, toYear]);

  const rawDocumentos = useMemo<DocumentoAnalitico[]>(() => {
    const liveRows = rows
      .filter((row) => !hasEmpresaFilter || (row.empresa_id ? selectedEmpresaIdSet.has(row.empresa_id) : false))
      .filter(shouldIncludeDocumento)
      .map((row) => mapLiveDocumento(row, clientesById, { fromYear, toYear }))
      .filter((row): row is DocumentoAnalitico => Boolean(row));

    const manualRows = hasEmpresaFilter
      ? []
      : manualHistoricalEntries
          .filter((entry) => entry.year >= fromYear && entry.year <= toYear)
          .map((entry, index) => ({
            id: `manual-${entry.year}-${entry.month}-${index}`,
            year: entry.year,
            month: entry.month,
            valor: entry.amount,
            clienteNome: entry.clientName,
          }));

    return [...manualRows, ...liveRows];
  }, [clientesById, fromYear, hasEmpresaFilter, rows, selectedEmpresaIdSet, toYear]);

  const referenceDocumentos = useMemo<DocumentoAnalitico[]>(
    () =>
      rows
        .filter((row) => !hasEmpresaFilter || (row.empresa_id ? selectedEmpresaIdSet.has(row.empresa_id) : false))
        .filter(shouldIncludeDocumento)
        .map((row) => mapLiveDocumento(row, clientesById, { fromYear: currentYear, toYear: currentYear }))
        .filter((row): row is DocumentoAnalitico => Boolean(row)),
    [clientesById, currentYear, hasEmpresaFilter, rows, selectedEmpresaIdSet]
  );

  const canonicalClientNames = useMemo(() => {
    const allTotals = new Map<string, number>();
    const referenceTotals = new Map<string, number>();

    for (const row of rawDocumentos) {
      allTotals.set(row.clienteNome, (allTotals.get(row.clienteNome) ?? 0) + row.valor);
    }
    for (const row of referenceDocumentos) {
      referenceTotals.set(row.clienteNome, (referenceTotals.get(row.clienteNome) ?? 0) + row.valor);
    }

    const fallbackTotals = referenceTotals.size ? referenceTotals : allTotals;
    const fullLookup = new Map<string, string>();
    const cleanBuckets = new Map<string, string[]>();
    const baseBuckets = new Map<string, string[]>();
    const familyBuckets = new Map<string, string[]>();
    const referenceNames = Array.from(fallbackTotals.keys());

    for (const clientName of referenceNames) {
      const signature = getClientNameSignature(clientName);
      if (signature.fullKey && !fullLookup.has(signature.fullKey)) {
        fullLookup.set(signature.fullKey, clientName);
      }
      if (signature.cleanKey) {
        cleanBuckets.set(signature.cleanKey, [...(cleanBuckets.get(signature.cleanKey) ?? []), clientName]);
      }
      if (signature.baseKey) {
        baseBuckets.set(signature.baseKey, [...(baseBuckets.get(signature.baseKey) ?? []), clientName]);
      }
      if (signature.familyKey) {
        familyBuckets.set(signature.familyKey, [...(familyBuckets.get(signature.familyKey) ?? []), clientName]);
      }
    }

    const cleanLookup = new Map<string, string>();
    for (const [key, names] of cleanBuckets.entries()) {
      const preferredName = pickPreferredReferenceName(names, fallbackTotals);
      if (preferredName) cleanLookup.set(key, preferredName);
    }

    const baseLookup = new Map<string, string>();
    for (const [key, names] of baseBuckets.entries()) {
      const preferredName = pickPreferredReferenceName(names, fallbackTotals);
      if (preferredName) baseLookup.set(key, preferredName);
    }

    const familyLookup = new Map<string, string>();
    for (const [key, names] of familyBuckets.entries()) {
      const preferredName = pickPreferredReferenceName(names, fallbackTotals);
      if (preferredName) familyLookup.set(key, preferredName);
    }

    const resolved = new Map<string, string>();
    for (const clientName of allTotals.keys()) {
      const signature = getClientNameSignature(clientName);
      const canonicalName =
        CLIENT_NAME_EXACT_CANONICAL[signature.fullKey] ??
        fullLookup.get(signature.fullKey) ??
        (signature.cleanKey ? cleanLookup.get(signature.cleanKey) : undefined) ??
        (signature.baseKey ? baseLookup.get(signature.baseKey) : undefined) ??
        (signature.familyKey ? CLIENT_NAME_FAMILY_CANONICAL[signature.familyKey] ?? familyLookup.get(signature.familyKey) : undefined) ??
        clientName;
      resolved.set(clientName, resolveExactCanonicalClientName(canonicalName));
    }

    return resolved;
  }, [rawDocumentos, referenceDocumentos]);

  const documentos = useMemo<DocumentoAnalitico[]>(
    () =>
      rawDocumentos.map((row) => ({
        ...row,
        clienteNome: canonicalClientNames.get(row.clienteNome) ?? row.clienteNome,
      })),
    [canonicalClientNames, rawDocumentos]
  );

  const totalPeriodo = useMemo(() => documentos.reduce((acc, row) => acc + row.valor, 0), [documentos]);
  const clientesAtivos = useMemo(() => new Set(documentos.map((row) => row.clienteNome)).size, [documentos]);

  const yearRows = useMemo<AnoResumo[]>(() => {
    const totals = new Map<number, { total: number; documentos: number; clientes: Set<string> }>();

    for (const year of years) {
      totals.set(year, { total: 0, documentos: 0, clientes: new Set<string>() });
    }

    for (const row of documentos) {
      const bucket = totals.get(row.year);
      if (!bucket) continue;
      bucket.total += row.valor;
      bucket.documentos += 1;
      bucket.clientes.add(row.clienteNome);
    }

    return years.map((year) => {
      const bucket = totals.get(year) ?? { total: 0, documentos: 0, clientes: new Set<string>() };
      return {
        ano: year,
        total: bucket.total,
        documentos: bucket.documentos,
        clientes: bucket.clientes.size,
        ticketMedio: bucket.documentos > 0 ? bucket.total / bucket.documentos : 0,
      };
    });
  }, [documentos, years]);

  const monthByYear = useMemo(() => {
    const byYear = new Map<number, number[]>();
    for (const year of years) byYear.set(year, Array.from({ length: 12 }, () => 0));

    for (const row of documentos) {
      const bucket = byYear.get(row.year);
      if (!bucket) continue;
      bucket[row.month - 1] += row.valor;
    }

    return byYear;
  }, [documentos, years]);

  const monthTargets = useMemo(
    () => years.map((year) => FATURAMENTO_TARGETS_BY_YEAR[year] ?? null),
    [years]
  );

  const monthTargetTotal = useMemo(
    () => monthTargets.reduce<number>((acc, value) => acc + (value ?? 0), 0),
    [monthTargets]
  );

  const yearTargets = useMemo(
    () => monthTargets.map((value) => (value !== null ? value * 12 : null)),
    [monthTargets]
  );

  const yearTargetTotal = useMemo(
    () => yearTargets.reduce<number>((acc, value) => acc + (value ?? 0), 0),
    [yearTargets]
  );

  const filteredClientTerm = clientQuery.trim().toLowerCase();

  const monthClientRows = useMemo<ClienteMesResumo[]>(() => {
    const byClient = new Map<string, ClienteMesResumo>();

    for (const row of documentos) {
      if (row.year !== focusYear) continue;
      const current =
        byClient.get(row.clienteNome) ??
        {
          clienteNome: row.clienteNome,
          meses: Array.from({ length: 12 }, () => 0),
          total: 0,
        };

      current.meses[row.month - 1] += row.valor;
      current.total += row.valor;
      byClient.set(row.clienteNome, current);
    }

    return Array.from(byClient.values())
      .filter((row) => (filteredClientTerm ? row.clienteNome.toLowerCase().includes(filteredClientTerm) : true))
      .sort((a, b) => b.total - a.total)
      .slice(0, topN);
  }, [documentos, filteredClientTerm, focusYear, topN]);

  const yearClientRows = useMemo<ClienteAnoResumo[]>(() => {
    const byClient = new Map<string, ClienteAnoResumo>();

    for (const row of documentos) {
      const yearIndex = years.indexOf(row.year);
      if (yearIndex < 0) continue;

      const current =
        byClient.get(row.clienteNome) ??
        {
          clienteNome: row.clienteNome,
          anos: Array.from({ length: years.length }, () => 0),
          total: 0,
        };

      current.anos[yearIndex] += row.valor;
      current.total += row.valor;
      byClient.set(row.clienteNome, current);
    }

    return Array.from(byClient.values())
      .filter((row) => (filteredClientTerm ? row.clienteNome.toLowerCase().includes(filteredClientTerm) : true))
      .sort((a, b) => b.total - a.total)
      .slice(0, topN);
  }, [documentos, filteredClientTerm, topN, years]);

  const subtotalMesCliente = useMemo(
    () =>
      monthClientRows.reduce(
        (acc, row) => {
          for (let index = 0; index < 12; index += 1) acc[index] += row.meses[index];
          acc[12] += row.total;
          return acc;
        },
        Array.from({ length: 13 }, () => 0)
      ),
    [monthClientRows]
  );

  const subtotalAnoCliente = useMemo(
    () =>
      yearClientRows.reduce(
        (acc, row) => {
          for (let index = 0; index < years.length; index += 1) acc[index] += row.anos[index] ?? 0;
          acc[years.length] += row.total;
          return acc;
        },
        Array.from({ length: years.length + 1 }, () => 0)
      ),
    [yearClientRows, years.length]
  );

  const monthRowTotals = useMemo(
    () =>
      MONTH_LABELS.map((_, monthIndex) =>
        years.reduce((acc, year) => acc + (monthByYear.get(year)?.[monthIndex] ?? 0), 0)
      ),
    [monthByYear, years]
  );

  const yearColumnTotals = useMemo(
    () => years.map((year) => monthByYear.get(year)?.reduce((acc, value) => acc + value, 0) ?? 0),
    [monthByYear, years]
  );

  if (canFinanceiro !== true) return null;

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <div className="text-xs uppercase tracking-[0.18em] text-zinc-500">Faturamento</div>
          <h1 className="mt-1 text-2xl font-semibold text-zinc-100">Analitico</h1>
          <p className="mt-1 text-sm text-zinc-400">
            Base: documentos fiscais de saida por competencia (fallback emissao). NFS-e conta somente quando estiver
            emitida.
          </p>
          {manualHistoricalYears.length ? (
            <p className="mt-1 text-xs text-zinc-500">
              Historico manual ativo: {manualHistoricalYears.join(", ")}. Anos com historico manual prevalecem sobre o
              sistema. Para os controles antigos, os totais seguem o historico enviado.
            </p>
          ) : null}
          {hasEmpresaFilter ? (
            <p className="mt-1 text-xs text-amber-200">
              Filtro por empresa ativo para {selectedEmpresaLabels.join(" + ")}. O historico manual consolidado do
              grupo fica oculto neste modo.
            </p>
          ) : null}
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Link
            href="/faturamento/nfse"
            className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-900"
          >
            Voltar para Faturamento
          </Link>
          {empresaOptions.length > 1
            ? empresaOptions.map((empresa) => {
                const active = selectedEmpresaIdSet.has(empresa.id);
                return (
                  <button
                    key={empresa.id}
                    type="button"
                    onClick={() => toggleEmpresa(empresa.id)}
                    className={[
                      "rounded-md border px-3 py-2 text-sm transition-colors",
                      active
                        ? "border-emerald-500/40 bg-emerald-500/15 text-emerald-200"
                        : "border-zinc-800 bg-zinc-950 text-zinc-300 hover:bg-zinc-900",
                    ].join(" ")}
                    title={empresa.fullName}
                  >
                    {empresa.label}
                  </button>
                );
              })
            : null}
        </div>
      </div>

      <section className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <div className="flex flex-wrap gap-2">
          <TabButton active={view === "mes"} onClick={() => setView("mes")} label="Mes" />
          <TabButton active={view === "mes-cliente"} onClick={() => setView("mes-cliente")} label="Mes / Cliente" />
          <TabButton active={view === "ano"} onClick={() => setView("ano")} label="Ano" />
          <TabButton active={view === "ano-cliente"} onClick={() => setView("ano-cliente")} label="Ano / Cliente" />
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
              <div className="rounded-md border border-dashed border-zinc-800 px-3 py-2 text-xs text-zinc-500">
                Filtros sincronizados na URL para compartilhamento desta visao.
              </div>
            </div>
          )}
        </div>
      </section>

      <div className="grid grid-cols-1 gap-3 md:grid-cols-4">
        <StatCard title="Faturamento no periodo" value={formatMoneyBR(totalPeriodo)} subtitle={`${fromYear} ate ${toYear}`} />
        <StatCard title="Documentos emitidos" value={String(documentos.length)} subtitle="Apenas saida considerada" />
        <StatCard title="Clientes com faturamento" value={String(clientesAtivos)} subtitle="Inclui sem cliente quando houver" />
        <StatCard
          title="Ticket medio"
          value={formatMoneyBR(documentos.length > 0 ? totalPeriodo / documentos.length : 0)}
          subtitle="Media por documento fiscal"
        />
      </div>

      {error ? (
        <div className="rounded-xl border border-rose-900/60 bg-rose-950/20 px-4 py-3 text-sm text-rose-200">{error}</div>
      ) : null}

      {!ready || loading ? (
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 px-4 py-8 text-center text-sm text-zinc-400">
          Carregando analitico de faturamento...
        </div>
      ) : null}

      {ready && !loading && view === "mes" ? (
        <TableCard
          title="Mes a mes por ano"
          subtitle="Metas mensais por ano: verde quando atinge a meta, amarelo abaixo da meta sem ultrapassar 10%, vermelho com 10% ou mais abaixo."
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
              <tr className="border-b border-zinc-800 bg-amber-500/5">
                <td className="sticky left-0 bg-zinc-950 px-4 py-3 font-medium text-amber-200">Meta</td>
                {monthTargets.map((value, index) => (
                  <td key={`meta-${years[index]}`} className="px-4 py-3 text-right tabular-nums text-amber-100">
                    {value !== null ? formatMoneyBR(value) : "-"}
                  </td>
                ))}
                <td className="px-4 py-3 text-right tabular-nums font-medium text-amber-100">
                  {monthTargetTotal > 0 ? formatMoneyBR(monthTargetTotal) : "-"}
                </td>
              </tr>
              {MONTH_LABELS.map((label, monthIndex) => (
                <tr key={label} className="border-b border-zinc-900/70 hover:bg-zinc-900/30">
                  <td className="sticky left-0 bg-zinc-950 px-4 py-3 text-zinc-200">{label}</td>
                  {years.map((year, yearIndex) => {
                    const value = monthByYear.get(year)?.[monthIndex] ?? 0;
                    const status = getMetaStatus(value, monthTargets[yearIndex]);
                    return (
                      <td
                        key={`${year}-${label}`}
                        className={[
                          "px-4 py-3 text-right tabular-nums",
                          getMetaToneClass(status),
                        ].join(" ")}
                      >
                        {formatMoneyBR(value)}
                      </td>
                    );
                  })}
                  <td
                    className={[
                      "px-4 py-3 text-right tabular-nums font-medium",
                      getMetaToneClass(getMetaStatus(monthRowTotals[monthIndex] ?? 0, monthTargetTotal)),
                    ].join(" ")}
                  >
                    {formatMoneyBR(monthRowTotals[monthIndex] ?? 0)}
                  </td>
                </tr>
              ))}
              <tr className="bg-zinc-900/60 font-semibold">
                <td className="sticky left-0 bg-zinc-900 px-4 py-3 text-zinc-100">Total</td>
                {yearColumnTotals.map((value, index) => (
                  <td
                    key={years[index]}
                    className={[
                      "px-4 py-3 text-right tabular-nums",
                      getMetaToneClass(getMetaStatus(value, yearTargets[index])),
                    ].join(" ")}
                  >
                    {formatMoneyBR(value)}
                  </td>
                ))}
                <td
                  className={[
                    "px-4 py-3 text-right tabular-nums font-semibold",
                    getMetaToneClass(getMetaStatus(totalPeriodo, yearTargetTotal)),
                  ].join(" ")}
                >
                  {formatMoneyBR(totalPeriodo)}
                </td>
              </tr>
            </tbody>
          </table>
        </TableCard>
      ) : null}

      {ready && !loading && view === "ano" ? (
        <TableCard title="Resumo anual" subtitle="Total consolidado por ano, com volume de documentos e ticket medio.">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-800 text-zinc-400">
                <th className="px-4 py-3 text-left font-medium">Ano</th>
                <th className="px-4 py-3 text-right font-medium">Faturamento</th>
                <th className="px-4 py-3 text-right font-medium">Documentos</th>
                <th className="px-4 py-3 text-right font-medium">Clientes</th>
                <th className="px-4 py-3 text-right font-medium">Ticket medio</th>
              </tr>
            </thead>
            <tbody>
              {yearRows.map((row) => (
                <tr key={row.ano} className="border-b border-zinc-900/70 hover:bg-zinc-900/30">
                  <td className="px-4 py-3 text-zinc-100">{row.ano}</td>
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{formatMoneyBR(row.total)}</td>
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-200">{row.documentos}</td>
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-200">{row.clientes}</td>
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-200">{formatMoneyBR(row.ticketMedio)}</td>
                </tr>
              ))}
              <tr className="bg-zinc-900/60 font-semibold">
                <td className="px-4 py-3 text-zinc-100">Total</td>
                <td className="px-4 py-3 text-right tabular-nums text-emerald-200">{formatMoneyBR(totalPeriodo)}</td>
                <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{documentos.length}</td>
                <td className="px-4 py-3 text-right tabular-nums text-zinc-100">{clientesAtivos}</td>
                <td className="px-4 py-3 text-right tabular-nums text-zinc-100">
                  {formatMoneyBR(documentos.length > 0 ? totalPeriodo / documentos.length : 0)}
                </td>
              </tr>
            </tbody>
          </table>
        </TableCard>
      ) : null}

      {ready && !loading && view === "mes-cliente" ? (
        <TableCard title={`Mes / Cliente - ${focusYear}`} subtitle={`Top ${topN} clientes por faturamento no ano selecionado.`}>
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-800 text-zinc-400">
                <th className="sticky left-0 bg-zinc-950 px-4 py-3 text-left font-medium">Cliente</th>
                {MONTH_LABELS.map((label) => (
                  <th key={label} className="px-4 py-3 text-right font-medium">
                    {label}
                  </th>
                ))}
                <th className="px-4 py-3 text-right font-medium">Total</th>
              </tr>
            </thead>
            <tbody>
              {monthClientRows.length ? (
                monthClientRows.map((row) => (
                  <tr key={row.clienteNome} className="border-b border-zinc-900/70 hover:bg-zinc-900/30">
                    <td className="sticky left-0 bg-zinc-950 px-4 py-3 text-zinc-100">{row.clienteNome}</td>
                    {row.meses.map((value, index) => (
                      <td key={`${row.clienteNome}-${index}`} className="px-4 py-3 text-right tabular-nums text-zinc-100">
                        {formatMoneyBR(value)}
                      </td>
                    ))}
                    <td className="px-4 py-3 text-right tabular-nums font-medium text-emerald-200">{formatMoneyBR(row.total)}</td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={14} className="px-4 py-8 text-center text-zinc-500">
                    Nenhum cliente encontrado para os filtros informados.
                  </td>
                </tr>
              )}
              {monthClientRows.length ? (
                <tr className="bg-zinc-900/60 font-semibold">
                  <td className="sticky left-0 bg-zinc-900 px-4 py-3 text-zinc-100">Subtotal exibido</td>
                  {subtotalMesCliente.slice(0, 12).map((value, index) => (
                    <td key={index} className="px-4 py-3 text-right tabular-nums text-zinc-100">
                      {formatMoneyBR(value)}
                    </td>
                  ))}
                  <td className="px-4 py-3 text-right tabular-nums text-emerald-200">
                    {formatMoneyBR(subtotalMesCliente[12] ?? 0)}
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </TableCard>
      ) : null}

      {ready && !loading && view === "ano-cliente" ? (
        <TableCard title="Ano / Cliente" subtitle={`Top ${topN} clientes considerando o intervalo de ${fromYear} ate ${toYear}.`}>
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
              {yearClientRows.length ? (
                yearClientRows.map((row) => (
                  <tr key={row.clienteNome} className="border-b border-zinc-900/70 hover:bg-zinc-900/30">
                    <td className="sticky left-0 bg-zinc-950 px-4 py-3 text-zinc-100">{row.clienteNome}</td>
                    {row.anos.map((value, index) => (
                      <td key={`${row.clienteNome}-${years[index]}`} className="px-4 py-3 text-right tabular-nums text-zinc-100">
                        {formatMoneyBR(value)}
                      </td>
                    ))}
                    <td className="px-4 py-3 text-right tabular-nums font-medium text-emerald-200">{formatMoneyBR(row.total)}</td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={years.length + 2} className="px-4 py-8 text-center text-zinc-500">
                    Nenhum cliente encontrado para os filtros informados.
                  </td>
                </tr>
              )}
              {yearClientRows.length ? (
                <tr className="bg-zinc-900/60 font-semibold">
                  <td className="sticky left-0 bg-zinc-900 px-4 py-3 text-zinc-100">Subtotal exibido</td>
                  {years.map((year, index) => (
                    <td key={year} className="px-4 py-3 text-right tabular-nums text-zinc-100">
                      {formatMoneyBR(subtotalAnoCliente[index] ?? 0)}
                    </td>
                  ))}
                  <td className="px-4 py-3 text-right tabular-nums text-emerald-200">
                    {formatMoneyBR(subtotalAnoCliente[years.length] ?? 0)}
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </TableCard>
      ) : null}
    </div>
  );
}
