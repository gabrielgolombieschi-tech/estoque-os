"use client";

import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Fragment, Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { formatMoneyBR, parseMoneyBR } from "@/lib/decimal";
import { buildEmpresaDisplayOptions } from "@/app/faturamento/components/empresaDisplay";
import OsVinculoField from "@/app/faturamento/components/OsVinculoField";
import type { OsSelection } from "@/lib/os-vinculo";

type Kind = "AP" | "AR";
type DateBase = "vencimento" | "emissao" | "competencia";
type SortMode = "vencimento" | "valor" | "fornecedor" | "emissao";
type ActionTab = "APROVAR" | "PAGAR" | "REVISAR_VALOR" | "VENCIMENTO" | "RECEBER" | "CANCELAR_PAGAMENTO";

type UnifiedRow = {
  empresaId: string;
  empresaNome: string;
  kind: Kind;
  nfNumero: string | null;
  tituloId: string;
  parcelaId: string;
  parcelaNumero: string | null;
  parcelaTotal: number | null;
  emissao: string | null; // yyyy-mm-dd (AP manual / XML)
  competencia: string | null;
  vencimento: string; // yyyy-mm-dd
  dataBase: string;
  pessoaNome: string;
  descricao: string | null;
  motivoCodigo: string | null; // AP only
  motivoNome: string | null; // AP only
  aprovadoPorNome: string | null; // AP only
  valor: number;
  valorAberto: number;
  tituloStatus: string;
  formaPagamentoResumo: string | null;
  contaBancariaResumo: string | null;
  osId: number | null;
  osNumero: string | null;
};

type DisplayEntry = {
  id: string;
  primary: UnifiedRow;
  rows: UnifiedRow[];
  valor: number;
  valorAberto: number;
};

type DisplayGroup = {
  id: string;
  date: string | null;
  entries: DisplayEntry[];
};

type ContaSaldo = {
  empresaId: string;
  empresaNome: string;
  contaId: string;
  codigo: string;
  nome: string;
  configurada: boolean;
  saldoReferencia: number | null;
  saldoReferenciaData: string | null;
  saldoReferenciaMotivo: string | null;
  saldoInicialPeriodo: number | null;
  entradasPeriodo: number;
  saidasPeriodo: number;
  transferenciasPeriodo: number;
  saldoAtual: number | null;
};

type MotivoCompra = {
  id: string;
  codigo: string;
  nome: string;
  requires_text: boolean;
  requires_os: boolean;
};

type Fornecedor = {
  id: number;
  nome: string;
};

type Cliente = {
  id: number;
  nome: string;
};

type ContaBancaria = {
  id: string;
  codigo: string;
  nome: string;
};

type PagamentoAplicado = {
  valor: number;
  pagamento: {
    id: string;
    conta_bancaria_id: string;
    data_pagamento: string;
    forma_pagamento: string;
    valor: number;
  };
};

type RevisaoValorAp = {
  id: string;
  revisadoEm: string;
  valorAnterior: number;
  valorNovo: number;
  diferenca: number;
  valorPago: number;
  saldoAnterior: number;
  saldoNovo: number;
  motivo: string;
  origem: string;
  revisadoPor: string;
};

function normalizeFormaPagamentoLabel(value: unknown): string | null {
  const normalized = String(value ?? "")
    .trim()
    .replace(/\s+/g, "_")
    .replace(/-/g, "_")
    .toUpperCase();

  if (!normalized) return null;
  if (normalized === "PIX") return "PIX";
  if (normalized === "BOLETO") return "Boleto";
  if (normalized === "TRANSFERENCIA" || normalized === "TRANSFERÊNCIA") return "Transferência";
  if (normalized === "DINHEIRO") return "Dinheiro";
  if (normalized === "CARTAO" || normalized === "CARTÃO") return "Cartão";
  if (normalized === "FATURADO") return "Faturado";
  if (normalized === "A_VISTA" || normalized === "AVISTA" || normalized === "A_VISTA") return "À vista";
  if (normalized === "OUTROS") return "Outros";
  return String(value ?? "").trim() || null;
}

function readPagamentoImportEntries(value: unknown): Array<Record<string, unknown>> {
  if (Array.isArray(value)) {
    return value.filter((row): row is Record<string, unknown> => typeof row === "object" && row !== null);
  }
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    const pagamentos = record.pagamentos;
    if (Array.isArray(pagamentos)) {
      return pagamentos.filter((row): row is Record<string, unknown> => typeof row === "object" && row !== null);
    }
    const parcelas = record.parcelas;
    if (Array.isArray(parcelas)) {
      return parcelas.filter((row): row is Record<string, unknown> => typeof row === "object" && row !== null);
    }
  }
  return [];
}

function summarizeFormaPagamentoLabels(values: unknown[]): string | null {
  const labels = Array.from(
    new Set(
      values
        .map((value) => normalizeFormaPagamentoLabel(value))
        .filter((value): value is string => Boolean(value))
    )
  );
  if (labels.length === 0) return null;
  if (labels.length === 1) return labels[0];
  return labels.join(" + ");
}

function summarizeTextValues(values: unknown[]): string | null {
  const labels = Array.from(
    new Set(values.map((value) => String(value ?? "").trim()).filter(Boolean))
  );
  if (labels.length === 0) return null;
  return labels.join(" + ");
}

function accountBankName(codigo: string, nome: string): string {
  const source = `${codigo} ${nome}`.toUpperCase();
  if (source.includes("SICREDI") || codigo.toUpperCase() === "SGU") return "Sicredi";
  if (source.includes("SANTANDER")) return "Santander";
  if (source.includes("CAIXA") || codigo.toUpperCase() === "CX") return "Caixa";
  return nome.trim() || codigo.trim() || "Conta";
}

function accountDisplayLabel(codigo: string, nome: string, empresaNome: string): string {
  return `${accountBankName(codigo, nome)} - ${empresaNome}`;
}

function summarizeAccountLabels(values: unknown[], empresaNome: string): string | null {
  const labels = values
    .map((value) => String(value ?? "").trim())
    .filter(Boolean)
    .map((value) => {
      const parts = value.split(" - ");
      const codigo = parts.shift() ?? "";
      const nome = parts.join(" - ") || codigo;
      return accountDisplayLabel(codigo, nome, empresaNome);
    });
  return summarizeTextValues(labels);
}

function buildFormaPagamentoResumo({
  aplicada,
  agendada,
  importada,
  parcelasNoTitulo,
}: {
  aplicada: string | null;
  agendada: string | null;
  importada: string | null;
  parcelasNoTitulo: number;
}): string | null {
  const principal = aplicada ?? agendada ?? importada;
  if (principal) {
    if (parcelasNoTitulo > 1 && !principal.includes(" + ")) return `${principal} - ${parcelasNoTitulo}x`;
    return principal;
  }
  if (parcelasNoTitulo > 1) return `${parcelasNoTitulo}x`;
  return null;
}

function getErrorMessage(error: unknown, fallback: string): string {
  if (!error) return fallback;
  if (typeof error === "string") return error;
  if (typeof error === "object" && error !== null && "message" in error) {
    const msg = (error as { message?: unknown }).message;
    if (typeof msg === "string" && msg.trim()) return msg;
  }
  try {
    return JSON.stringify(error);
  } catch {
    return fallback;
  }
}

function isMissingRpc(error: unknown, functionName: string) {
  const msg = getErrorMessage(error, "").toLowerCase();
  // Supabase/PostgREST typical message:
  // "Could not find the function f.criar_titulo_ap_manual(...) in the schema cache"
  return msg.includes("could not find the function") && msg.includes(functionName.toLowerCase());
}

function pad2(n: number) {
  return String(n).padStart(2, "0");
}

function monthIso(date = new Date()) {
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}`;
}

function monthRange(month: string): { ini: string; fim: string } {
  const [y, m] = month.split("-").map((v) => Number(v));
  const first = new Date(y, m - 1, 1);
  const last = new Date(y, m, 0);
  const toISO = (d: Date) => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
  return { ini: toISO(first), fim: toISO(last) };
}

function toDateOnly(iso: string): Date {
  const [y, m, d] = iso.split("-").map((v) => Number(v));
  return new Date(y, (m ?? 1) - 1, d ?? 1);
}

function isOverdue(vencimentoISO: string): boolean {
  const today = new Date();
  const today0 = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  return toDateOnly(vencimentoISO).getTime() < today0.getTime();
}

function statusDisplay(row: UnifiedRow): {
  label: string;
  variant: "open" | "overdue" | "paid" | "partial" | "cancelled";
} {
  const status = String(row.tituloStatus ?? "").toUpperCase();
  if (status === "CANCELADO") {
    return { label: "Cancelado", variant: "cancelled" };
  }

  if (row.valorAberto <= 0) {
    return { label: row.kind === "AP" ? "Pago" : "Recebido", variant: "paid" };
  }

  if (isOverdue(row.vencimento)) {
    return { label: "Vencido", variant: "overdue" };
  }

  if (row.valorAberto < Math.abs(row.valor) - 0.005) {
    return { label: "Parcial", variant: "partial" };
  }

  return { label: "Em aberto", variant: "open" };
}

function isCancelledRow(row: UnifiedRow): boolean {
  return String(row.tituloStatus ?? "").toUpperCase() === "CANCELADO";
}

function fmtParcela(n: string | null, total?: number | null) {
  if (!n) return "Parcela";
  if (total && total > 1) return `${n}/${total}`;
  return `Parc. ${n}`;
}

function titleCaseDisplay(value: string): string {
  const normalized = value.trim().replace(/\s+/g, " ");
  if (!normalized) return "—";

  const lowercaseWords = new Set(["a", "as", "da", "das", "de", "do", "dos", "e", "em"]);
  const words = normalized.split(" ");
  return words
    .map((word, index) => {
      const lower = word.toLocaleLowerCase("pt-BR");
      const isInitial = /^[A-ZÀ-Ý]$/.test(word);
      const isInitialSequence =
        isInitial &&
        (Boolean(words[index - 1] && /^[A-ZÀ-Ý]$/.test(words[index - 1])) ||
          Boolean(words[index + 1] && /^[A-ZÀ-Ý]$/.test(words[index + 1])));
      if (isInitialSequence || /^[A-Z0-9]+(?:[./-][A-Z0-9]+)+$/.test(word) || word === "SGU") return word;
      if (index > 0 && lowercaseWords.has(lower)) return lower;
      return lower.charAt(0).toLocaleUpperCase("pt-BR") + lower.slice(1);
    })
    .join(" ");
}

function cleanDescriptionDisplay(row: UnifiedRow): string {
  const original = String(row.descricao ?? "").trim().replace(/\s+/g, " ");
  const person = String(row.pessoaNome ?? "").trim().replace(/\s+/g, " ");
  const originalLower = original.toLocaleLowerCase("pt-BR");
  const personLower = person.toLocaleLowerCase("pt-BR");
  let cleaned = original;

  if (cleaned && person && originalLower.startsWith(personLower)) {
    cleaned = cleaned.slice(person.length).replace(/^[\s\-–—:|]+/, "").trim();
  } else if (cleaned && person && originalLower.endsWith(personLower)) {
    cleaned = cleaned.slice(0, cleaned.length - person.length).replace(/[\s\-–—:|]+$/, "").trim();
  }

  if (!cleaned) {
    const nf = String(row.nfNumero ?? "").trim();
    cleaned = nf ? (/^nf/i.test(nf) ? nf : `NF-e ${nf}`) : original || "Sem descrição";
  }

  if (row.parcelaTotal && row.parcelaTotal > 1 && row.parcelaNumero) {
    const parcelaNumero = Number(row.parcelaNumero);
    const parcelaLabel = Number.isFinite(parcelaNumero) ? parcelaNumero : row.parcelaNumero;
    cleaned += ` · parcela ${parcelaLabel} de ${row.parcelaTotal}`;
  }

  return cleaned;
}

function relativeDueLabel(vencimentoISO: string): string {
  const today = toDateOnly(todayISO()).getTime();
  const due = toDateOnly(vencimentoISO).getTime();
  const days = Math.round((due - today) / 86_400_000);
  if (days === 0) return "vence hoje";
  if (days === 1) return "vence amanhã";
  if (days > 1) return `vence em ${days} dias`;
  const elapsed = Math.abs(days);
  return `há ${elapsed} ${elapsed === 1 ? "dia" : "dias"}`;
}

function relativeDateLabel(iso: string, base: DateBase): string {
  if (base === "vencimento") return relativeDueLabel(iso);
  const today = toDateOnly(todayISO()).getTime();
  const date = toDateOnly(iso).getTime();
  const days = Math.round((date - today) / 86_400_000);
  if (days === 0) return "hoje";
  if (days > 0) return `em ${days} ${days === 1 ? "dia" : "dias"}`;
  const elapsed = Math.abs(days);
  return `há ${elapsed} ${elapsed === 1 ? "dia" : "dias"}`;
}

function signedValueDisplay(row: UnifiedRow): string {
  return `${row.kind === "AP" ? "−" : "+"} ${formatMoneyBR(Math.abs(row.valor))}`;
}

function signedMoneyDisplay(kind: Kind, value: number): string {
  return `${kind === "AP" ? "−" : "+"} ${formatMoneyBR(Math.abs(value))}`;
}

function signedDeltaDisplay(value: number): string {
  if (Math.abs(value) < 0.005) return "—";
  return `${value < 0 ? "−" : "+"} ${formatMoneyBR(Math.abs(value))}`;
}

function dateBaseLabel(base: DateBase): string {
  if (base === "emissao") return "Emissão";
  if (base === "competencia") return "Competência";
  return "Vencimento";
}

function monthDisplay(month: string): string {
  const [year, monthNumber] = month.split("-").map(Number);
  const label = new Intl.DateTimeFormat("pt-BR", { month: "long", year: "numeric" }).format(
    new Date(year, Math.max(0, monthNumber - 1), 1)
  );
  return label.charAt(0).toLocaleUpperCase("pt-BR") + label.slice(1);
}

function groupDateDisplay(iso: string, base: DateBase): { date: string; weekday: string; relative: string } {
  const date = toDateOnly(iso);
  const dateLabel = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "long" }).format(date);
  const weekday = new Intl.DateTimeFormat("pt-BR", { weekday: "long" }).format(date);
  return { date: dateLabel, weekday, relative: relativeDateLabel(iso, base) };
}

function csvCell(value: unknown): string {
  const text = String(value ?? "");
  return `"${text.replace(/"/g, '""')}"`;
}

function FormError({ message }: { message: string | null }) {
  if (!message) return null;
  return <div className="text-sm text-red-300">{message}</div>;
}

function todayISO(): string {
  const d = new Date();
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

function formatDateBR(iso: string | null | undefined): string {
  if (!iso) return "";
  const [y, m, d] = String(iso).split("-");
  if (!y || !m || !d) return String(iso);
  return `${d}/${m}/${y}`;
}

function ContasPagarReceberContent() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const te = useTenantEmpresa();
  const supabase = useMemo(() => getSupabaseBrowser(), []);

  const canWriteFinanceiro = te.has("financeiro.write") ?? false;
  const canFinanceiro = (te.has("financeiro.read") ?? false) || canWriteFinanceiro;

  const initialMonth = /^\d{4}-\d{2}$/.test(searchParams.get("periodo") ?? "")
    ? String(searchParams.get("periodo"))
    : monthIso();
  const [month, setMonth] = useState<string>(initialMonth);
  const range = useMemo(() => monthRange(month), [month]);
  const [year, setYear] = useState<number>(() => Number(initialMonth.split("-")[0] ?? new Date().getFullYear()));
  const [monthNum, setMonthNum] = useState<number>(() => Number(initialMonth.split("-")[1] ?? new Date().getMonth() + 1));

  useEffect(() => {
    const next = `${year}-${pad2(monthNum)}`;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (next !== month) setMonth(next);
  }, [month, monthNum, year]);

  const [q, setQ] = useState(() => searchParams.get("q") ?? "");
  const [nfQuery, setNfQuery] = useState(() => searchParams.get("nf") ?? "");
  const [only, setOnly] = useState<"ALL" | Kind>(() => {
    const value = String(searchParams.get("tipo") ?? "").toUpperCase();
    return value === "AP" || value === "AR" ? value : "ALL";
  });
  const [onlyPendentes, setOnlyPendentes] = useState(() => searchParams.get("pendentes") === "1");
  const [onlyToday, setOnlyToday] = useState(false);
  const [dateFrom, setDateFrom] = useState<string>(() => searchParams.get("de") ?? "");
  const [dateTo, setDateTo] = useState<string>(() => searchParams.get("ate") ?? "");
  const [dateBase, setDateBase] = useState<DateBase>(() => {
    const value = searchParams.get("base");
    return value === "emissao" || value === "competencia" ? value : "vencimento";
  });
  const [sortMode, setSortMode] = useState<SortMode>(() => {
    const value = searchParams.get("ordem");
    return value === "valor" || value === "fornecedor" || value === "emissao" ? value : "vencimento";
  });
  const [groupByDay, setGroupByDay] = useState(() => searchParams.get("agrupar") !== "nao");
  const [contaFilter, setContaFilter] = useState(() => searchParams.get("conta") ?? "");
  const [motivoFilter, setMotivoFilter] = useState(() => searchParams.get("motivo") ?? "");
  const [aprovadorFilter, setAprovadorFilter] = useState(() => searchParams.get("aprovador") ?? "");
  const [formaFilter, setFormaFilter] = useState(() => searchParams.get("forma") ?? "");
  const [moreFiltersOpen, setMoreFiltersOpen] = useState(false);
  const [expandedRows, setExpandedRows] = useState<Set<string>>(() => new Set());
  const empresaOptions = useMemo(() => buildEmpresaDisplayOptions(te.empresas), [te.empresas]);
  const [empresaFilter, setEmpresaFilter] = useState<string>(() => {
    const value = searchParams.get("empresa");
    return value && value !== "ambas" ? value : "ALL";
  });
  const effectiveEmpresaFilter = useMemo(
    () => (empresaFilter === "ALL" || empresaOptions.some((empresa) => empresa.id === empresaFilter) ? empresaFilter : "ALL"),
    [empresaFilter, empresaOptions]
  );
  const selectedEmpresaIds = useMemo(
    () =>
      effectiveEmpresaFilter === "ALL"
        ? empresaOptions.map((empresa) => empresa.id)
        : [effectiveEmpresaFilter],
    [effectiveEmpresaFilter, empresaOptions]
  );
  const empresaNomeById = useMemo(
    () => new Map(empresaOptions.map((empresa) => [empresa.id, empresa.label])),
    [empresaOptions]
  );
  const lastFilterUrlRef = useRef("");

  useEffect(() => {
    const params = new URLSearchParams(searchParams.toString());
    params.set("periodo", month);
    params.set("tipo", only === "ALL" ? "ap+ar" : only.toLowerCase());
    params.set("empresa", effectiveEmpresaFilter === "ALL" ? "ambas" : effectiveEmpresaFilter);
    params.set("base", dateBase);
    params.set("pendentes", onlyPendentes ? "1" : "0");
    params.set("ordem", sortMode);
    params.set("agrupar", groupByDay ? "dia" : "nao");

    const optional: Array<[string, string]> = [
      ["q", q.trim()],
      ["nf", nfQuery.trim()],
      ["de", dateFrom.trim()],
      ["ate", dateTo.trim()],
      ["conta", contaFilter],
      ["motivo", motivoFilter],
      ["aprovador", aprovadorFilter],
      ["forma", formaFilter],
    ];
    for (const [key, value] of optional) {
      if (value) params.set(key, value);
      else params.delete(key);
    }

    const queryString = params.toString();
    const nextUrl = `${pathname}?${queryString}`;
    if (lastFilterUrlRef.current === nextUrl || queryString === searchParams.toString()) return;
    lastFilterUrlRef.current = nextUrl;
    router.replace(nextUrl, { scroll: false });
  }, [
    aprovadorFilter,
    contaFilter,
    dateBase,
    dateFrom,
    dateTo,
    effectiveEmpresaFilter,
    formaFilter,
    groupByDay,
    month,
    motivoFilter,
    nfQuery,
    only,
    onlyPendentes,
    pathname,
    q,
    router,
    searchParams,
    sortMode,
  ]);

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [rows, setRows] = useState<UnifiedRow[]>([]);
  const [todaySummary, setTodaySummary] = useState({ entradas: 0, saidas: 0 });
  const [accountBalances, setAccountBalances] = useState<ContaSaldo[]>([]);

  const [selected, setSelected] = useState<UnifiedRow | null>(null);
  const [tab, setTab] = useState<ActionTab>("APROVAR");

  const [createOpen, setCreateOpen] = useState(false);
  const [createKind, setCreateKind] = useState<Kind>("AP");
  const [createBusy, setCreateBusy] = useState(false);
  const [createErr, setCreateErr] = useState<string | null>(null);
  const [fornecedores, setFornecedores] = useState<Fornecedor[]>([]);
  const [clientes, setClientes] = useState<Cliente[]>([]);

  const [newEmpresaId, setNewEmpresaId] = useState<string>("");
  const [newFornecedorId, setNewFornecedorId] = useState<string>("");
  const [newClienteId, setNewClienteId] = useState<string>("");
  const [newOsSelection, setNewOsSelection] = useState<OsSelection | null>(null);
  const [newDescricao, setNewDescricao] = useState<string>("");
  const [newEmissaoDate, setNewEmissaoDate] = useState<string>(todayISO());
  const [newVencimento, setNewVencimento] = useState<string>(todayISO());
  const [newValor, setNewValor] = useState<string>("");
  const [newQuantidadeParcelas, setNewQuantidadeParcelas] = useState<number>(1);
  const [newMotivoId, setNewMotivoId] = useState<string>("");
  const [newRecorrente, setNewRecorrente] = useState<boolean>(false);
  const [newProvisionarMeses, setNewProvisionarMeses] = useState<number>(12);

  const [motivos, setMotivos] = useState<MotivoCompra[]>([]);
  const [contas, setContas] = useState<ContaBancaria[]>([]);
  const [aplicacoes, setAplicacoes] = useState<PagamentoAplicado[]>([]);
  const [revisoesValor, setRevisoesValor] = useState<RevisaoValorAp[]>([]);
  const [cancelPagamentoId, setCancelPagamentoId] = useState<string>("");
  const [cancelMotivo, setCancelMotivo] = useState<string>("");
  const [cancelConfirmOpen, setCancelConfirmOpen] = useState(false);

  const [actionBusy, setActionBusy] = useState(false);
  const [actionErr, setActionErr] = useState<string | null>(null);
  const [toastMsg, setToastMsg] = useState<string | null>(null);
  const toastTimeoutRef = useRef<number | null>(null);

  const [tituloMeta, setTituloMeta] = useState<{ emissaoDate: string | null; documentoFiscalId: string | null } | null>(
    null
  );
  const [arOsNumero, setArOsNumero] = useState<string | null>(null);
  const [editEmissaoDate, setEditEmissaoDate] = useState<string>("");
  const [editVencimentoDate, setEditVencimentoDate] = useState<string>("");
  const [emissaoBusy, setEmissaoBusy] = useState(false);
  const [emissaoErr, setEmissaoErr] = useState<string | null>(null);
  const [editDescricao, setEditDescricao] = useState<string>("");
  const [descricaoBusy, setDescricaoBusy] = useState(false);
  const [descricaoErr, setDescricaoErr] = useState<string | null>(null);

  // Aprovar
  const [motivoId, setMotivoId] = useState<string>("");
  const [motivoOutrosText, setMotivoOutrosText] = useState<string>("");
  const [osId, setOsId] = useState<string>("");

  // Pagar / Receber
  const [contaBancariaId, setContaBancariaId] = useState<string>("");
  const [dataPagamento, setDataPagamento] = useState<string>("");
  const [formaPagamento, setFormaPagamento] = useState<string>("PIX");
  const [valorMov, setValorMov] = useState<string>("");
  const [valorJuros, setValorJuros] = useState<string>("");
  const [valorMulta, setValorMulta] = useState<string>("");
  const [valorDesconto, setValorDesconto] = useState<string>("");
  const [observacoes, setObservacoes] = useState<string>("");
  const [pagamentoComoValorFinal, setPagamentoComoValorFinal] = useState(false);
  const [novoValorFinal, setNovoValorFinal] = useState<string>("");
  const [motivoRevisao, setMotivoRevisao] = useState<string>("");
  const [splitRecebimento, setSplitRecebimento] = useState(false);
  const [splitVencimentoDate, setSplitVencimentoDate] = useState<string>("");

  const resetModalState = useCallback(() => {
    setActionErr(null);
    setActionBusy(false);
    setEmissaoErr(null);
    setEmissaoBusy(false);
    setTituloMeta(null);
    setArOsNumero(null);
    setEditEmissaoDate("");
    setEditVencimentoDate("");
    setEditDescricao("");
    setDescricaoErr(null);
    setDescricaoBusy(false);
    setMotivoId("");
    setMotivoOutrosText("");
    setOsId("");
    setContaBancariaId("");
    setDataPagamento("");
    setFormaPagamento("PIX");
    setValorMov("");
    setValorJuros("");
    setValorMulta("");
    setValorDesconto("");
    setObservacoes("");
    setPagamentoComoValorFinal(false);
    setNovoValorFinal("");
    setMotivoRevisao("");
    setSplitRecebimento(false);
    setSplitVencimentoDate("");
    setAplicacoes([]);
    setRevisoesValor([]);
    setCancelPagamentoId("");
    setCancelMotivo("");
    setCancelConfirmOpen(false);
  }, []);

  const parseMoneyOrZero = useCallback((value: string) => {
    if (!value.trim()) return 0;
    const parsed = parseMoneyBR(value);
    return Number.isFinite(parsed) ? parsed : NaN;
  }, []);

  const toCents = useCallback((value: number) => {
    if (!Number.isFinite(value)) return NaN;
    return Math.round(value * 100);
  }, []);

  const centsToMoneyString = useCallback((cents: number) => {
    const n = Number.isFinite(cents) ? cents / 100 : NaN;
    return formatMoneyBR(Number.isFinite(n) ? n : 0);
  }, []);

  const centsToNumericString = useCallback((cents: number) => {
    const n = Number.isFinite(cents) ? cents / 100 : NaN;
    return (Number.isFinite(n) ? n : 0).toFixed(2);
  }, []);

  const movTotals = useMemo(() => {
    if (!selected) return null;
    if (tab !== "PAGAR" && tab !== "RECEBER") return null;

    const principal = parseMoneyOrZero(valorMov);
    const juros = parseMoneyOrZero(valorJuros);
    const multa = parseMoneyOrZero(valorMulta);
    const desconto = parseMoneyOrZero(valorDesconto);

    const principalCents = toCents(principal);
    const jurosCents = toCents(juros);
    const multaCents = toCents(multa);
    const descontoCents = toCents(desconto);
    const openCents = toCents(Number(selected.valorAberto ?? 0));

    if (
      !Number.isFinite(principalCents) ||
      !Number.isFinite(jurosCents) ||
      !Number.isFinite(multaCents) ||
      !Number.isFinite(descontoCents) ||
      !Number.isFinite(openCents)
    ) {
      return {
        principalCents,
        jurosCents,
        multaCents,
        descontoCents,
        openCents,
        totalCents: NaN,
      };
    }

    const totalCents = principalCents + jurosCents + multaCents - descontoCents;
    return { principalCents, jurosCents, multaCents, descontoCents, openCents, totalCents };
  }, [parseMoneyOrZero, selected, tab, toCents, valorDesconto, valorJuros, valorMov, valorMulta]);

  const valorPagoParcela = useMemo(
    () => aplicacoes.reduce((total, aplicacao) => total + Number(aplicacao.valor ?? 0), 0),
    [aplicacoes]
  );

  const pagamentoPrincipalMenorQueAberto = useMemo(() => {
    if (!selected || selected.kind !== "AP" || tab !== "PAGAR" || !movTotals) return false;
    return (
      Number.isFinite(movTotals.principalCents) &&
      Number.isFinite(movTotals.openCents) &&
      movTotals.principalCents > 0 &&
      movTotals.principalCents < movTotals.openCents
    );
  }, [movTotals, selected, tab]);

  const novoValorFinalNumero = useMemo(() => parseMoneyOrZero(novoValorFinal), [novoValorFinal, parseMoneyOrZero]);
  const saldoAposRevisao = Number.isFinite(novoValorFinalNumero)
    ? Math.max(0, novoValorFinalNumero - valorPagoParcela)
    : NaN;

  const requestIdRef = useRef(0);
  const loadLegacy = useCallback(async () => {
    if (!canFinanceiro) return;
    if (!te.tenantId || !te.empresaId) return;

    const from = dateFrom.trim();
    const to = dateTo.trim();
    if (from && to && from > to) {
      setError("Data 'De' não pode ser maior que 'Até'.");
      return;
    }

    const ini = from || range.ini;
    const fim = to || range.fim;

    const reqId = ++requestIdRef.current;
    setLoading(true);
    setError(null);

    try {
      const [{ data: apData, error: apErr }, { data: apPaidData, error: apPaidErr }, { data: arData, error: arErr }] = await Promise.all([
        supabase
          .schema("f")
          .from("r_ap_aging_detalhe")
          .select(
            "titulo_id,parcela_id,parcela_numero,total_parcelas,fornecedor_nome,motivo_codigo,motivo_nome,vencimento_date,valor_parcela,valor_aberto,status,descricao"
          )
          .eq("tenant_id", te.tenantId)
          .eq("empresa_id", te.empresaId)
          .gte("vencimento_date", ini)
          .lte("vencimento_date", fim),
        supabase
          .schema("f")
          .from("titulo_parcela")
          .select(
            "id,titulo_id,numero,vencimento_date,valor,valor_aberto,deleted_at,titulo:titulo_id!inner(id,tipo,status,fornecedor_id,motivo_compra_id,empresa_id,deleted_at)"
          )
          .eq("tenant_id", te.tenantId)
          .eq("titulo.tipo", "AP")
          .eq("titulo.empresa_id", te.empresaId)
          .is("deleted_at", null)
          .is("titulo.deleted_at", null)
          .eq("valor_aberto", 0)
          .gte("vencimento_date", ini)
          .lte("vencimento_date", fim),
        supabase
          .schema("f")
          .from("titulo_parcela")
          .select(
            "id,titulo_id,numero,vencimento_date,valor,valor_aberto,deleted_at,titulo:titulo_id!inner(id,tipo,status,cliente_id,descricao,empresa_id,deleted_at)"
          )
          .eq("tenant_id", te.tenantId)
          .eq("titulo.tipo", "AR")
          .eq("titulo.empresa_id", te.empresaId)
          .is("deleted_at", null)
          .is("titulo.deleted_at", null)
          .gte("vencimento_date", ini)
          .lte("vencimento_date", fim),
      ]);

      if (requestIdRef.current !== reqId) return;
      if (apErr) throw apErr;
      if (apPaidErr) throw apPaidErr;
      if (arErr) throw arErr;

      type ApAgingDetalheRow = {
        titulo_id: unknown;
        parcela_id: unknown;
        parcela_numero: unknown;
        total_parcelas: unknown;
        vencimento_date: unknown;
        fornecedor_nome: unknown;
        motivo_codigo: unknown;
        motivo_nome: unknown;
        valor_parcela: unknown;
        valor_aberto: unknown;
        status: unknown;
        descricao: unknown;
      };

      const apRows: UnifiedRow[] = ((apData ?? []) as ApAgingDetalheRow[]).map((r) => ({
        empresaId: te.empresaId ?? "",
        empresaNome: te.empresa?.nome_fantasia ?? te.empresa?.razao_social ?? "Empresa",
        kind: "AP",
        nfNumero: null,
        tituloId: String(r.titulo_id),
        parcelaId: String(r.parcela_id),
        parcelaNumero: r.parcela_numero ? String(r.parcela_numero) : null,
        parcelaTotal: r.total_parcelas ? Number(r.total_parcelas) : null,
        emissao: null,
        competencia: null,
        vencimento: String(r.vencimento_date),
        dataBase: String(r.vencimento_date),
        pessoaNome: r.fornecedor_nome ? String(r.fornecedor_nome) : "Fornecedor",
        descricao: r.descricao ? String(r.descricao) : null,
        motivoCodigo: r.motivo_codigo ? String(r.motivo_codigo) : null,
        motivoNome: r.motivo_nome ? String(r.motivo_nome) : null,
        aprovadoPorNome: null,
        valor: Number(r.valor_parcela ?? 0),
        valorAberto: Number(r.valor_aberto ?? 0),
        tituloStatus: String(r.status ?? ""),
        formaPagamentoResumo: null,
        contaBancariaResumo: null,
        osId: null,
        osNumero: null,
      }));

      type ApParcelaPaidRow = {
        id: unknown;
        titulo_id: unknown;
        numero: unknown;
        vencimento_date: unknown;
        valor: unknown;
        valor_aberto: unknown;
        deleted_at?: unknown;
        titulo?: {
          fornecedor_id?: unknown;
          motivo_compra_id?: unknown;
          status?: unknown;
          empresa_id?: unknown;
          deleted_at?: unknown;
        } | null;
      };

      const apPaidRaw = (apPaidData ?? []) as ApParcelaPaidRow[];
      const fornecedorIds = Array.from(
        new Set(
          apPaidRaw
            .map((r) => (r?.titulo?.fornecedor_id ? Number(r.titulo.fornecedor_id) : null))
            .filter((v): v is number => Number.isFinite(v))
        )
      );
      const motivoIds = Array.from(
        new Set(
          apPaidRaw
            .map((r) => (r?.titulo?.motivo_compra_id ? String(r.titulo.motivo_compra_id) : null))
            .filter((v): v is string => Boolean(v))
        )
      );

      const fornecedorNomeById = new Map<number, string>();
      if (fornecedorIds.length) {
        const { data: fornecedores, error: fornErr } = await supabase
          .from("fornecedores")
          .select("id,nome")
          .in("id", fornecedorIds);
        if (!fornErr) {
          type FornecedorRow = { id: unknown; nome: unknown };
          for (const f of (fornecedores ?? []) as FornecedorRow[]) {
            const id = Number(f.id);
            if (!Number.isFinite(id)) continue;
            fornecedorNomeById.set(id, f?.nome ? String(f.nome) : `Fornecedor ${id}`);
          }
        }
      }

      const motivoById = new Map<string, { codigo: string; nome: string }>();
      if (motivoIds.length) {
        const { data: motivosData, error: motErr } = await supabase
          .schema("f")
          .from("motivo_compra")
          .select("id,codigo,nome")
          .in("id", motivoIds)
          .is("deleted_at", null);
        if (!motErr) {
          type MotivoRow = { id: unknown; codigo: unknown; nome: unknown };
          for (const m of (motivosData ?? []) as MotivoRow[]) {
            const id = m?.id ? String(m.id) : "";
            if (!id) continue;
            motivoById.set(id, {
              codigo: m?.codigo ? String(m.codigo) : "",
              nome: m?.nome ? String(m.nome) : "",
            });
          }
        }
      }

      const apPaidRows: UnifiedRow[] = apPaidRaw.map((r) => {
        const fornecedorId = r?.titulo?.fornecedor_id ? Number(r.titulo.fornecedor_id) : NaN;
        const motivoId = r?.titulo?.motivo_compra_id ? String(r.titulo.motivo_compra_id) : "";
        const motivo = motivoById.get(motivoId);
        return {
          empresaId: te.empresaId ?? "",
          empresaNome: te.empresa?.nome_fantasia ?? te.empresa?.razao_social ?? "Empresa",
          kind: "AP",
          nfNumero: null,
          tituloId: String(r.titulo_id),
          parcelaId: String(r.id),
          parcelaNumero: r.numero ? String(r.numero) : null,
          parcelaTotal: null,
          emissao: null,
          competencia: null,
          vencimento: String(r.vencimento_date),
          dataBase: String(r.vencimento_date),
          pessoaNome: Number.isFinite(fornecedorId)
            ? fornecedorNomeById.get(fornecedorId) ?? `Fornecedor ${fornecedorId}`
            : "Fornecedor",
          descricao: null,
          motivoCodigo: motivo?.codigo || null,
          motivoNome: motivo?.nome || null,
          aprovadoPorNome: null,
          valor: Number(r.valor ?? 0),
          valorAberto: Number(r.valor_aberto ?? 0),
          tituloStatus: String(r?.titulo?.status ?? ""),
          formaPagamentoResumo: null,
          contaBancariaResumo: null,
          osId: null,
          osNumero: null,
        };
      });

      const apAllRows = [...apRows, ...apPaidRows];
      const apRowByParcelaId = new Map<string, UnifiedRow>();
      for (const r of apAllRows) apRowByParcelaId.set(r.parcelaId, r);
      const apRowsUnique = Array.from(apRowByParcelaId.values());

      // Enrich AP rows with approver name from f.titulo_aprovacao.aprovado_por (a.usuario.id)
      const apTituloIds = Array.from(new Set(apRowsUnique.map((r) => r.tituloId)));

      // Enrich AP rows with emissao_date from f.titulo (works for manual + XML titles).
      const emissaoByTituloId = new Map<string, string | null>();
      const nfByTituloId = new Map<string, string | null>();
      const pagamentoImportByTituloId = new Map<string, unknown>();
      if (apTituloIds.length) {
        try {
          const { data: titulos, error: titErr } = await supabase
            .schema("f")
            .from("titulo")
            .select("id,emissao_date,documento_fiscal:documento_fiscal_id(numero,pagamento_import_json)")
            .in("id", apTituloIds)
            .is("deleted_at", null);

          if (!titErr) {
            const tituloRows = (titulos ?? []) as Array<{
              id: unknown;
              emissao_date: unknown;
              documento_fiscal?: { numero?: unknown; pagamento_import_json?: unknown } | null;
            }>;
            for (const t of tituloRows) {
              const id = t?.id ? String(t.id) : "";
              if (!id) continue;
              emissaoByTituloId.set(id, t?.emissao_date ? String(t.emissao_date) : null);
              nfByTituloId.set(id, t?.documento_fiscal?.numero ? String(t.documento_fiscal.numero) : null);
              pagamentoImportByTituloId.set(id, t?.documento_fiscal?.pagamento_import_json ?? null);
            }
          }
        } catch {
          // ignore enrichment failures
        }
      }

      const aprovadoPorNomeByTituloId = new Map<string, string>();
      if (apTituloIds.length) {
        const { data: aprovacoes, error: aprovErr } = await supabase
          .schema("f")
          .from("titulo_aprovacao")
          .select("titulo_id,aprovado_por")
          .in("titulo_id", apTituloIds)
          .is("deleted_at", null);

        if (!aprovErr) {
          const aprovacaoRows = (aprovacoes ?? []) as Array<{ titulo_id: unknown; aprovado_por: unknown }>;
          const aprovadorIds = Array.from(
            new Set(
              aprovacaoRows
                .map((a) => (a?.aprovado_por ? String(a.aprovado_por) : null))
                .filter((v): v is string => Boolean(v))
            )
          );

          const aprovadorNomeById = new Map<string, string>();
          if (aprovadorIds.length) {
            const { data: usuarios, error: usrErr } = await supabase
              .schema("a")
              .from("usuario")
              .select("id,nome")
              .in("id", aprovadorIds)
              .is("deleted_at", null);
            if (!usrErr) {
              type UsuarioRow = { id: unknown; nome: unknown };
              for (const u of (usuarios ?? []) as UsuarioRow[]) {
                const id = u?.id ? String(u.id) : "";
                const nome = u?.nome ? String(u.nome) : "";
                if (id && nome) aprovadorNomeById.set(id, nome);
              }
            }
          }

          for (const a of aprovacaoRows) {
            const tituloId = a?.titulo_id ? String(a.titulo_id) : "";
            const aprovadorId = a?.aprovado_por ? String(a.aprovado_por) : "";
            if (!tituloId || !aprovadorId) continue;
            const nome = aprovadorNomeById.get(aprovadorId) ?? "";
            if (nome) aprovadoPorNomeByTituloId.set(tituloId, nome);
          }
        }
      }

      const apRowsEnriched: UnifiedRow[] = apRowsUnique.map((r) => ({
        ...r,
        emissao: emissaoByTituloId.get(r.tituloId) ?? null,
        nfNumero: nfByTituloId.get(r.tituloId) ?? null,
        aprovadoPorNome: aprovadoPorNomeByTituloId.get(r.tituloId) ?? null,
      }));

      type ArParcelaJoinedRow = {
        id: unknown;
        titulo_id: unknown;
        numero: unknown;
        vencimento_date: unknown;
        valor: unknown;
        valor_aberto: unknown;
        deleted_at?: unknown;
        titulo?: {
          cliente_id?: unknown;
          descricao?: unknown;
          status?: unknown;
          empresa_id?: unknown;
          deleted_at?: unknown;
        } | null;
      };

      const arRaw = (arData ?? []) as ArParcelaJoinedRow[];
      const clienteIds = Array.from(
        new Set(
          arRaw
            .map((r) => (r?.titulo?.cliente_id ? String(r.titulo.cliente_id) : null))
            .filter((v): v is string => Boolean(v))
        )
      );

      const clienteNomeById = new Map<string, string>();
      if (clienteIds.length) {
        const { data: clientes, error: clientesErr } = await supabase
          .from("clientes")
          .select("id,nome")
          .in("id", clienteIds);
        if (!clientesErr) {
          type ClienteRow = { id: unknown; nome: unknown };
          for (const c of (clientes ?? []) as ClienteRow[]) {
            const id = c?.id;
            const nome = c?.nome;
            if (id) clienteNomeById.set(String(id), nome ? String(nome) : "Cliente");
          }
        }
      }

      const arRows: UnifiedRow[] = arRaw.map((r) => {
        const clienteId = r?.titulo?.cliente_id ? String(r.titulo.cliente_id) : null;
        const pessoaNome = clienteId ? clienteNomeById.get(clienteId) ?? `Cliente ${clienteId}` : "Cliente";
        return {
          empresaId: te.empresaId ?? "",
          empresaNome: te.empresa?.nome_fantasia ?? te.empresa?.razao_social ?? "Empresa",
          kind: "AR",
          nfNumero: null,
          tituloId: String(r.titulo_id),
          parcelaId: String(r.id),
          parcelaNumero: r.numero ? String(r.numero) : null,
          parcelaTotal: null,
          emissao: null,
          competencia: null,
          vencimento: String(r.vencimento_date),
          dataBase: String(r.vencimento_date),
          pessoaNome,
          descricao: r?.titulo?.descricao ? String(r.titulo.descricao) : null,
          motivoCodigo: null,
          motivoNome: null,
          aprovadoPorNome: null,
          valor: Number(r.valor ?? 0),
          valorAberto: Number(r.valor_aberto ?? 0),
          tituloStatus: String(r?.titulo?.status ?? ""),
          formaPagamentoResumo: null,
          contaBancariaResumo: null,
          osId: null,
          osNumero: null,
        };
      });

      const arTituloIds = Array.from(new Set(arRows.map((r) => r.tituloId)));
      if (arTituloIds.length) {
        const { data: arTitulos, error: arTitErr } = await supabase
          .schema("f")
          .from("titulo")
          .select("id,documento_fiscal:documento_fiscal_id(numero,pagamento_import_json)")
          .in("id", arTituloIds)
          .is("deleted_at", null);
        if (!arTitErr) {
          const arTituloRows = (arTitulos ?? []) as Array<{
            id: unknown;
            documento_fiscal?: { numero?: unknown; pagamento_import_json?: unknown } | null;
          }>;
          for (const t of arTituloRows) {
            const id = t?.id ? String(t.id) : "";
            if (!id) continue;
            nfByTituloId.set(id, t?.documento_fiscal?.numero ? String(t.documento_fiscal.numero) : null);
            pagamentoImportByTituloId.set(id, t?.documento_fiscal?.pagamento_import_json ?? null);
          }
        }
      }

      const arRowsEnriched: UnifiedRow[] = arRows.map((r) => ({
        ...r,
        nfNumero: nfByTituloId.get(r.tituloId) ?? null,
      }));

      const parcelaCountByTituloId = new Map<string, number>();
      const formaAplicadaByParcelaId = new Map<string, string | null>();
      const formaAgendadaByTituloId = new Map<string, string | null>();
      const formaImportadaByTituloId = new Map<string, string | null>();

      const mergedBase = [...apRowsEnriched, ...arRowsEnriched];
      const allTituloIds = Array.from(new Set(mergedBase.map((r) => r.tituloId)));
      const allParcelaIds = Array.from(new Set(mergedBase.map((r) => r.parcelaId)));

      if (allTituloIds.length) {
        const [{ data: parcelasMeta }, { data: pagamentoItems }, { data: agendamentos }] = await Promise.all([
          supabase
            .schema("f")
            .from("titulo_parcela")
            .select("id,titulo_id")
            .in("titulo_id", allTituloIds)
            .is("deleted_at", null),
          allParcelaIds.length
            ? supabase
                .schema("f")
                .from("pagamento_item")
                .select("titulo_parcela_id,pagamento:pagamento_id(id,forma_pagamento)")
                .in("titulo_parcela_id", allParcelaIds)
                .is("deleted_at", null)
            : Promise.resolve({ data: [], error: null }),
          apTituloIds.length
            ? supabase
                .schema("f")
                .from("titulo_agendamento")
                .select("titulo_id,forma_pagamento")
                .in("titulo_id", apTituloIds)
                .is("deleted_at", null)
            : Promise.resolve({ data: [], error: null }),
        ]);

        type ParcelaMetaRow = { titulo_id: unknown };
        for (const parcela of (parcelasMeta ?? []) as ParcelaMetaRow[]) {
          const tituloId = parcela?.titulo_id ? String(parcela.titulo_id) : "";
          if (!tituloId) continue;
          parcelaCountByTituloId.set(tituloId, (parcelaCountByTituloId.get(tituloId) ?? 0) + 1);
        }

        type PagamentoItemMetaRow = {
          titulo_parcela_id: unknown;
          pagamento?: { id?: unknown; forma_pagamento?: unknown } | null;
        };
        const appliedFormsByParcelaId = new Map<string, string[]>();
        for (const item of (pagamentoItems ?? []) as PagamentoItemMetaRow[]) {
          const parcelaId = item?.titulo_parcela_id ? String(item.titulo_parcela_id) : "";
          const forma = normalizeFormaPagamentoLabel(item?.pagamento?.forma_pagamento);
          if (!parcelaId || !forma) continue;
          const current = appliedFormsByParcelaId.get(parcelaId) ?? [];
          current.push(forma);
          appliedFormsByParcelaId.set(parcelaId, current);
        }
        for (const [parcelaId, labels] of appliedFormsByParcelaId) {
          formaAplicadaByParcelaId.set(parcelaId, summarizeFormaPagamentoLabels(labels) ?? null);
        }

        type AgendamentoMetaRow = { titulo_id: unknown; forma_pagamento: unknown };
        const agendamentoFormsByTituloId = new Map<string, string[]>();
        for (const agendamento of (agendamentos ?? []) as AgendamentoMetaRow[]) {
          const tituloId = agendamento?.titulo_id ? String(agendamento.titulo_id) : "";
          const forma = normalizeFormaPagamentoLabel(agendamento?.forma_pagamento);
          if (!tituloId || !forma) continue;
          const current = agendamentoFormsByTituloId.get(tituloId) ?? [];
          current.push(forma);
          agendamentoFormsByTituloId.set(tituloId, current);
        }
        for (const [tituloId, labels] of agendamentoFormsByTituloId) {
          formaAgendadaByTituloId.set(tituloId, summarizeFormaPagamentoLabels(labels) ?? null);
        }
      }

      for (const [tituloId, pagamentoImport] of pagamentoImportByTituloId) {
        const entries = readPagamentoImportEntries(pagamentoImport);
        const labels = entries
          .map((entry) => entry.forma_pagamento ?? entry.forma ?? entry.modo ?? null)
          .filter((value) => value !== null && value !== undefined);
        formaImportadaByTituloId.set(tituloId, summarizeFormaPagamentoLabels(labels) ?? null);
      }

      const merged = mergedBase
        .map((row) => ({
          ...row,
          formaPagamentoResumo: buildFormaPagamentoResumo({
            aplicada: formaAplicadaByParcelaId.get(row.parcelaId) ?? null,
            agendada: formaAgendadaByTituloId.get(row.tituloId) ?? null,
            importada: formaImportadaByTituloId.get(row.tituloId) ?? null,
            parcelasNoTitulo: parcelaCountByTituloId.get(row.tituloId) ?? 1,
          }),
        }))
        .sort((a, b) => {
          const av = a.vencimento.localeCompare(b.vencimento);
          if (av !== 0) return av;
          if (a.kind !== b.kind) return a.kind === "AP" ? -1 : 1;
          return a.pessoaNome.localeCompare(b.pessoaNome);
        });

      if (requestIdRef.current !== reqId) return;
      setRows(merged);
    } catch (e: unknown) {
      if (requestIdRef.current !== reqId) return;
      setError(getErrorMessage(e, "Erro ao carregar contas."));
    } finally {
      if (requestIdRef.current === reqId) setLoading(false);
    }
  }, [canFinanceiro, dateFrom, dateTo, range.fim, range.ini, supabase, te.empresa, te.empresaId, te.tenantId]);

  const load = useCallback(async () => {
    if (!canFinanceiro || !te.tenantId || selectedEmpresaIds.length === 0) return;

    const from = dateFrom.trim();
    const to = dateTo.trim();
    if (from && to && from > to) {
      setError("Data 'De' nÃ£o pode ser maior que 'AtÃ©'.");
      return;
    }

    const ini = from || range.ini;
    const fim = to || range.fim;
    const reqId = ++requestIdRef.current;
    setLoading(true);
    setError(null);

    try {
      const [listaRes, hojeRes, saldosRes] = await Promise.all([
        supabase.schema("f").rpc("contas_pagar_receber_listar_v4", {
          p_tenant_id: te.tenantId,
          p_empresa_ids: selectedEmpresaIds,
          p_data_inicio: ini,
          p_data_fim: fim,
          p_data_base: dateBase,
        }),
        supabase.schema("f").rpc("contas_pagar_receber_resumo_hoje", {
          p_tenant_id: te.tenantId,
          p_empresa_ids: selectedEmpresaIds,
          p_data: todayISO(),
        }),
        supabase.schema("f").rpc("contas_bancarias_saldos_ativos", {
          p_tenant_id: te.tenantId,
          p_empresa_ids: selectedEmpresaIds,
          p_data_inicio: ini,
          p_data_fim: fim,
          p_data_referencia: todayISO(),
        }),
      ]);

      if (requestIdRef.current !== reqId) return;
      if (listaRes.error) throw listaRes.error;
      if (hojeRes.error) throw hojeRes.error;
      if (saldosRes.error) throw saldosRes.error;

      type ContasPagarReceberRpcRow = {
        empresa_id: unknown;
        tipo: unknown;
        nf_numero: unknown;
        titulo_id: unknown;
        parcela_id: unknown;
        parcela_numero: unknown;
        total_parcelas: unknown;
        emissao_date: unknown;
        competencia_date: unknown;
        vencimento_date: unknown;
        data_base: unknown;
        pessoa_nome: unknown;
        descricao: unknown;
        motivo_codigo: unknown;
        motivo_nome: unknown;
        aprovado_por_nome: unknown;
        os_id: unknown;
        os_numero: unknown;
        valor: unknown;
        valor_aberto: unknown;
        titulo_status: unknown;
        formas_aplicadas: unknown;
        formas_agendadas: unknown;
        contas_aplicadas: unknown;
        contas_agendadas: unknown;
        pagamento_import_json: unknown;
      };

      const mapped = ((listaRes.data ?? []) as ContasPagarReceberRpcRow[])
        .map((row): UnifiedRow | null => {
          const kind = String(row.tipo ?? "").toUpperCase();
          if (kind !== "AP" && kind !== "AR") return null;

          const empresaId = String(row.empresa_id ?? "");
          const empresaNome = empresaNomeById.get(empresaId) ?? "Empresa";
          const formasAplicadas = Array.isArray(row.formas_aplicadas) ? row.formas_aplicadas : [];
          const formasAgendadas = Array.isArray(row.formas_agendadas) ? row.formas_agendadas : [];
          const contasAplicadas = Array.isArray(row.contas_aplicadas) ? row.contas_aplicadas : [];
          const contasAgendadas = Array.isArray(row.contas_agendadas) ? row.contas_agendadas : [];
          const importEntries = readPagamentoImportEntries(row.pagamento_import_json);
          const formasImportadas = importEntries
            .map((entry) => entry.forma_pagamento ?? entry.forma ?? entry.modo ?? null)
            .filter((value) => value !== null && value !== undefined);
          const parcelasNoTitulo = Math.max(1, Number(row.total_parcelas ?? 1));

          return {
            empresaId,
            empresaNome,
            kind,
            nfNumero: row.nf_numero ? String(row.nf_numero) : null,
            tituloId: String(row.titulo_id),
            parcelaId: String(row.parcela_id),
            parcelaNumero: row.parcela_numero ? String(row.parcela_numero) : null,
            parcelaTotal: parcelasNoTitulo,
            emissao: row.emissao_date ? String(row.emissao_date) : null,
            competencia: row.competencia_date ? String(row.competencia_date) : null,
            vencimento: String(row.vencimento_date),
            dataBase: row.data_base ? String(row.data_base) : String(row.vencimento_date),
            pessoaNome: row.pessoa_nome ? String(row.pessoa_nome) : kind === "AP" ? "Fornecedor" : "Cliente",
            descricao: row.descricao ? String(row.descricao) : null,
            motivoCodigo: row.motivo_codigo ? String(row.motivo_codigo) : null,
            motivoNome: row.motivo_nome ? String(row.motivo_nome) : null,
            aprovadoPorNome: row.aprovado_por_nome ? String(row.aprovado_por_nome) : null,
            valor: Number(row.valor ?? 0),
            valorAberto: Number(row.valor_aberto ?? 0),
            tituloStatus: String(row.titulo_status ?? ""),
            formaPagamentoResumo: buildFormaPagamentoResumo({
              aplicada: summarizeFormaPagamentoLabels(formasAplicadas),
              agendada: summarizeFormaPagamentoLabels(formasAgendadas),
              importada: summarizeFormaPagamentoLabels(formasImportadas),
              parcelasNoTitulo,
            }),
            contaBancariaResumo:
              summarizeAccountLabels(contasAplicadas, empresaNome) ?? summarizeAccountLabels(contasAgendadas, empresaNome),
            osId: row.os_id === null || row.os_id === undefined ? null : Number(row.os_id),
            osNumero: row.os_numero ? String(row.os_numero) : null,
          };
        })
        .filter((row): row is UnifiedRow => row !== null);

      type ResumoHojeRpcRow = { entradas?: unknown; saidas?: unknown };
      const resumoHoje = ((hojeRes.data ?? []) as ResumoHojeRpcRow[])[0] ?? null;

      type SaldoRpcRow = {
        empresa_id: unknown;
        conta_bancaria_id: unknown;
        conta_codigo: unknown;
        conta_nome: unknown;
        configurada: unknown;
        saldo_referencia: unknown;
        saldo_referencia_data: unknown;
        saldo_referencia_motivo: unknown;
        saldo_inicial_periodo: unknown;
        entradas_periodo: unknown;
        saidas_periodo: unknown;
        transferencias_periodo: unknown;
        saldo_atual: unknown;
      };
      const saldos = ((saldosRes.data ?? []) as SaldoRpcRow[]).map((saldo): ContaSaldo => {
        const empresaId = String(saldo.empresa_id ?? "");
        return {
          empresaId,
          empresaNome: empresaNomeById.get(empresaId) ?? "Empresa",
          contaId: String(saldo.conta_bancaria_id ?? ""),
          codigo: String(saldo.conta_codigo ?? ""),
          nome: String(saldo.conta_nome ?? "Conta"),
          configurada: Boolean(saldo.configurada),
          saldoReferencia: saldo.saldo_referencia === null ? null : Number(saldo.saldo_referencia ?? 0),
          saldoReferenciaData: saldo.saldo_referencia_data ? String(saldo.saldo_referencia_data) : null,
          saldoReferenciaMotivo: saldo.saldo_referencia_motivo ? String(saldo.saldo_referencia_motivo) : null,
          saldoInicialPeriodo: saldo.saldo_inicial_periodo === null ? null : Number(saldo.saldo_inicial_periodo ?? 0),
          entradasPeriodo: Number(saldo.entradas_periodo ?? 0),
          saidasPeriodo: Number(saldo.saidas_periodo ?? 0),
          transferenciasPeriodo: Number(saldo.transferencias_periodo ?? 0),
          saldoAtual: saldo.saldo_atual === null ? null : Number(saldo.saldo_atual ?? 0),
        };
      });

      setRows(mapped);
      setAccountBalances(saldos);
      setTodaySummary({
        entradas: Number(resumoHoje?.entradas ?? 0),
        saidas: Number(resumoHoje?.saidas ?? 0),
      });
    } catch (e: unknown) {
      if (requestIdRef.current !== reqId) return;
      const missingListRpc = isMissingRpc(e, "f.contas_pagar_receber_listar_v4");
      const missingTodayRpc = isMissingRpc(e, "f.contas_pagar_receber_resumo_hoje");
      const missingBalancesRpc = isMissingRpc(e, "f.contas_bancarias_saldos_ativos");
      if (
        (missingListRpc || missingTodayRpc || missingBalancesRpc) &&
        selectedEmpresaIds.length === 1 &&
        selectedEmpresaIds[0] === te.empresaId
      ) {
        setAccountBalances([]);
        await loadLegacy();
        return;
      }
      setError(getErrorMessage(e, "Erro ao carregar contas."));
    } finally {
      if (requestIdRef.current === reqId) setLoading(false);
    }
  }, [
    canFinanceiro,
    dateBase,
    dateFrom,
    dateTo,
    empresaNomeById,
    loadLegacy,
    range.fim,
    range.ini,
    selectedEmpresaIds,
    supabase,
    te.empresaId,
    te.tenantId,
  ]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, [load]);

  const closeCreate = useCallback(() => {
    setCreateOpen(false);
    setCreateBusy(false);
    setCreateErr(null);
  }, []);

  const openCreate = useCallback(async (kind: Kind = "AP") => {
    setCreateErr(null);
    setCreateBusy(false);
    setCreateKind(kind);
    setCreateOpen(true);
    const defaultEmpresaId =
      selectedEmpresaIds.length === 1
        ? selectedEmpresaIds[0]
        : selectedEmpresaIds.includes(te.empresaId ?? "")
          ? te.empresaId ?? ""
          : selectedEmpresaIds[0] ?? "";
    setNewEmpresaId(defaultEmpresaId);

    // Defaults/suggestions
    setNewEmissaoDate(todayISO());
    setNewVencimento(todayISO());
    setNewDescricao("");
    setNewValor("");
    setNewQuantidadeParcelas(1);
    setNewFornecedorId("");
    setNewClienteId("");
    setNewOsSelection(null);

    if (kind === "AR") {
      try {
        if (clientes.length === 0) {
          const { data, error } = await supabase
            .from("clientes")
            .select("id,nome")
            .eq("ativo", true)
            .order("nome", { ascending: true })
            .limit(500);
          if (!error) {
            type ClienteRow = { id: unknown; nome: unknown };
            const mapped = (data ?? []) as ClienteRow[];
            setClientes(
              mapped
                .map((c) => ({ id: Number(c.id), nome: c?.nome ? String(c.nome) : "Cliente" }))
                .filter((c) => Number.isFinite(c.id))
            );
          }
        }
      } catch (e: unknown) {
        setCreateErr(getErrorMessage(e, "Erro ao preparar criação."));
      }
      return;
    }

    // Load motivos/fornecedores for manual AP.
    try {
      if (motivos.length === 0) {
        const { data, error } = await supabase
          .schema("f")
          .from("motivo_compra")
          .select("id,codigo,nome,requires_text,requires_os")
          .eq("ativo", true)
          .is("deleted_at", null)
          .order("nome", { ascending: true });
        if (!error) {
          type MotivoCompraRow = {
            id: unknown;
            codigo: unknown;
            nome: unknown;
            requires_text: unknown;
            requires_os: unknown;
          };
          const mapped = ((data ?? []) as MotivoCompraRow[]).map((m) => ({
            id: String(m.id),
            codigo: String(m.codigo),
            nome: String(m.nome),
            requires_text: Boolean(m.requires_text),
            requires_os: Boolean(m.requires_os),
          }));
          setMotivos(mapped);
          const estoque = mapped.find((m) => m.codigo === "ESTOQUE") ?? null;
          if (!newMotivoId && estoque) setNewMotivoId(estoque.id);
        }
      }

      if (fornecedores.length === 0) {
        const { data, error } = await supabase
          .from("fornecedores")
          .select("id,nome")
          .eq("ativo", true)
          .order("nome", { ascending: true })
          .limit(500);
        if (!error) {
          type FornecedorRow = { id: unknown; nome: unknown };
          const mapped = (data ?? []) as FornecedorRow[];
          setFornecedores(
            mapped
              .map((f) => ({ id: Number(f.id), nome: f?.nome ? String(f.nome) : "Fornecedor" }))
              .filter((f) => Number.isFinite(f.id))
          );
        }
      }
    } catch (e: unknown) {
      setCreateErr(getErrorMessage(e, "Erro ao preparar criação."));
    }
  }, [clientes.length, fornecedores.length, motivos.length, newMotivoId, selectedEmpresaIds, supabase, te.empresaId]);

  const doCreateAp = useCallback(async () => {
    setCreateErr(null);
    const desc = newDescricao.trim();
    const emissao = newEmissaoDate;
    const venc = newVencimento;
    const valorParsed = parseMoneyBR(newValor);
    const fornecedorIdParsed = newFornecedorId.trim() ? Number(newFornecedorId) : null;

    if (!desc) {
      setCreateErr("Informe a descrição.");
      return;
    }
    if (!venc) {
      setCreateErr("Informe o vencimento.");
      return;
    }
    if (!emissao) {
      setCreateErr("Informe a data da NF (Emissão).");
      return;
    }
    if (!Number.isFinite(valorParsed) || valorParsed <= 0) {
      setCreateErr("Informe um valor válido.");
      return;
    }
    if (!Number.isInteger(newQuantidadeParcelas) || newQuantidadeParcelas < 1 || newQuantidadeParcelas > 120) {
      setCreateErr("Informe uma quantidade de parcelas entre 1 e 120.");
      return;
    }
    if (newQuantidadeParcelas > 1 && newRecorrente) {
      setCreateErr("Escolha parcelamento ou recorrência, não os dois.");
      return;
    }

    if (!newEmpresaId || !selectedEmpresaIds.includes(newEmpresaId)) {
      setCreateErr("Selecione a empresa do novo AP.");
      return;
    }

    setCreateBusy(true);
    try {
      if (newEmpresaId !== te.empresaId) {
        await te.setEmpresaId(newEmpresaId);
      }

      let recorrenciaId: string | null = null;

      if (newQuantidadeParcelas > 1) {
        const { error } = await supabase.schema("f").rpc("criar_titulo_ap_manual_parcelado_v1", {
          p_descricao: desc,
          p_primeiro_vencimento: venc,
          p_valor_parcela: valorParsed,
          p_quantidade_parcelas: newQuantidadeParcelas,
          p_fornecedor_id: fornecedorIdParsed && Number.isFinite(fornecedorIdParsed) ? fornecedorIdParsed : null,
          p_motivo_compra_id: newMotivoId || null,
          p_emissao_date: emissao,
          p_change_reason: "UI:contas_pagar_receber:criar_ap_parcelado",
        });

        if (error) {
          if (isMissingRpc(error, "f.criar_titulo_ap_manual_parcelado_v1")) {
            throw new Error("Atualize o banco para habilitar AP parcelado.");
          }
          throw error;
        }
      } else {
        // IMPORTANT: RPC payload is strict. Do not send extra fields.
        const args = {
          p_descricao: desc,
          p_vencimento_date: venc,
          p_valor: valorParsed,
          p_fornecedor_id: fornecedorIdParsed && Number.isFinite(fornecedorIdParsed) ? fornecedorIdParsed : null,
          p_motivo_compra_id: newMotivoId || null,
          p_emissao_date: emissao,
          p_criar_recorrencia: Boolean(newRecorrente),
          p_dia_vencimento: null,
          p_auto_copiar_valor: true,
        };

        const { data, error } = await supabase.schema("f").rpc("criar_titulo_ap_manual_v2", args);

        if (error) {
          if (isMissingRpc(error, "f.criar_titulo_ap_manual_v2")) {
            throw new Error(
              "RPC f.criar_titulo_ap_manual_v2 não encontrada no banco. Aplique a migration/SQL do financeiro (AP manual v2)."
            );
          }
          throw error;
        }

        type CriarTituloApManualRes = { titulo_id?: unknown; recorrencia_id?: unknown };
        const row = (Array.isArray(data) ? data[0] : data) as CriarTituloApManualRes | null;
        recorrenciaId = row?.recorrencia_id ? String(row.recorrencia_id) : null;
      }

      if (newRecorrente && recorrenciaId && newProvisionarMeses > 0) {
        const { error: provErr } = await supabase.schema("f").rpc("provisionar_ap_recorrencia", {
          p_recorrencia_id: recorrenciaId,
          p_meses_a_frente: Number(newProvisionarMeses),
          p_change_reason: "UI:contas_pagar_receber:provisionar",
        });
        if (provErr) throw provErr;
      }

      await load();
      closeCreate();
    } catch (e: unknown) {
      setCreateErr(getErrorMessage(e, "Erro ao criar AP."));
    } finally {
      setCreateBusy(false);
    }
  }, [closeCreate, load, newDescricao, newEmissaoDate, newEmpresaId, newFornecedorId, newMotivoId, newQuantidadeParcelas, newRecorrente, newProvisionarMeses, newValor, newVencimento, selectedEmpresaIds, supabase, te]);

  const doCreateAr = useCallback(async () => {
    setCreateErr(null);
    const desc = newDescricao.trim();
    const emissao = newEmissaoDate;
    const venc = newVencimento;
    const valorParsed = parseMoneyBR(newValor);
    const clienteIdParsed = newClienteId.trim() ? Number(newClienteId) : null;

    if (!clienteIdParsed || !Number.isFinite(clienteIdParsed)) {
      setCreateErr("Selecione o cliente.");
      return;
    }
    if (!desc) {
      setCreateErr("Informe a descrição.");
      return;
    }
    if (!emissao) {
      setCreateErr("Informe a data de emissão.");
      return;
    }
    if (!venc) {
      setCreateErr("Informe o vencimento.");
      return;
    }
    if (!Number.isFinite(valorParsed) || valorParsed <= 0) {
      setCreateErr("Informe um valor válido.");
      return;
    }
    if (!newEmpresaId || !selectedEmpresaIds.includes(newEmpresaId)) {
      setCreateErr("Selecione a empresa do novo AR.");
      return;
    }

    setCreateBusy(true);
    try {
      if (newEmpresaId !== te.empresaId) {
        await te.setEmpresaId(newEmpresaId);
      }

      const { error } = await supabase.schema("f").rpc("criar_titulo_ar_manual_v1", {
        p_cliente_id: clienteIdParsed,
        p_descricao: desc,
        p_emissao_date: emissao,
        p_vencimento_date: venc,
        p_valor: valorParsed,
        p_os_id: newOsSelection?.id ?? null,
      });

      if (error) {
        if (isMissingRpc(error, "f.criar_titulo_ar_manual_v1")) {
          throw new Error(
            "RPC f.criar_titulo_ar_manual_v1 não encontrada no banco. Aplique a migration do financeiro (AR manual)."
          );
        }
        throw error;
      }

      await load();
      closeCreate();
    } catch (e: unknown) {
      setCreateErr(getErrorMessage(e, "Erro ao criar AR."));
    } finally {
      setCreateBusy(false);
    }
  }, [closeCreate, load, newClienteId, newDescricao, newEmissaoDate, newEmpresaId, newOsSelection, newValor, newVencimento, selectedEmpresaIds, supabase, te]);

  const doUpdateEmissaoDate = useCallback(async () => {
    if (!selected || selected.kind !== "AP") return;
    if (!editEmissaoDate) {
      setEmissaoErr("Informe a data da NF (Emissão).");
      return;
    }

    const canEdit = tituloMeta !== null && tituloMeta.documentoFiscalId === null;
    if (!canEdit) return;

    setEmissaoErr(null);
    setEmissaoBusy(true);
    try {
      const { error } = await supabase.schema("f").rpc("atualizar_titulo_emissao_date", {
        p_titulo_id: selected.tituloId,
        p_emissao_date: editEmissaoDate,
        p_atualizar_competencia: true,
        p_change_reason: "AJUSTE DATA NF (UI)",
      });
      if (error) throw error;

      setTituloMeta((prev) => (prev ? { ...prev, emissaoDate: editEmissaoDate } : prev));
      setSelected((prev) => (prev ? { ...prev, emissao: editEmissaoDate } : prev));
      await load();
    } catch (e: unknown) {
      setEmissaoErr(getErrorMessage(e, "Erro ao atualizar emissão."));
    } finally {
      setEmissaoBusy(false);
    }
  }, [editEmissaoDate, load, selected, supabase, tituloMeta]);

  const doUpdateDescricao = useCallback(async () => {
    if (!selected || selected.kind !== "AP") return;
    const novo = editDescricao.trim();
    if (novo === (selected.descricao ?? "")) {
      setDescricaoErr("A descrição precisa ser diferente da atual.");
      return;
    }
    setDescricaoErr(null);
    setDescricaoBusy(true);
    try {
      const { error } = await supabase.schema("f").rpc("atualizar_titulo_descricao", {
        p_titulo_id: selected.tituloId,
        p_descricao: novo,
        p_change_reason: "UI: editar descrição/observação",
      });
      if (error) throw error;
      setSelected((prev) => (prev ? { ...prev, descricao: novo || null } : prev));
      await load();
    } catch (e: unknown) {
      setDescricaoErr(getErrorMessage(e, "Erro ao salvar descrição."));
    } finally {
      setDescricaoBusy(false);
    }
  }, [editDescricao, load, selected, supabase]);

  const doUpdateVencimentoDate = useCallback(async () => {
    if (!selected || (selected.kind !== "AP" && selected.kind !== "AR")) return;
    if (!editVencimentoDate) {
      setActionErr("Informe o vencimento.");
      return;
    }
    if (editVencimentoDate === selected.vencimento) {
      setActionErr("O novo vencimento precisa ser diferente do atual.");
      return;
    }

    setActionErr(null);
    setActionBusy(true);
    try {
      const { error } = await supabase.schema("f").rpc("atualizar_titulo_parcela_vencimento_date", {
        p_parcela_id: selected.parcelaId,
        p_vencimento_date: editVencimentoDate,
        p_change_reason: "UI: alterar vencimento parcela",
      });
      if (error) throw error;

      setSelected((prev) => (prev ? { ...prev, vencimento: editVencimentoDate } : prev));
      await load();
      resetModalState();
      setSelected(null);
    } catch (e: unknown) {
      setActionErr(getErrorMessage(e, "Erro ao atualizar vencimento."));
    } finally {
      setActionBusy(false);
    }
  }, [editVencimentoDate, load, resetModalState, selected, supabase]);

  const filtered = useMemo(() => {
    const today = todayISO();
    const query = q.trim().toLowerCase();
    const nfTerm = nfQuery.trim().toLowerCase();
    const from = dateFrom.trim();
    const to = dateTo.trim();
    const useDateRange = Boolean(from || to);
    return rows.filter((r) => {
      if (only !== "ALL" && r.kind !== only) return false;
      if (onlyPendentes && r.valorAberto <= 0) return false;
      if (useDateRange) {
        if (from && r.dataBase < from) return false;
        if (to && r.dataBase > to) return false;
      } else {
        if (onlyToday && r.dataBase !== today) return false;
      }
      if (contaFilter && r.contaBancariaResumo !== contaFilter) return false;
      if (motivoFilter && r.motivoNome !== motivoFilter) return false;
      if (aprovadorFilter && r.aprovadoPorNome !== aprovadorFilter) return false;
      if (formaFilter && r.formaPagamentoResumo !== formaFilter) return false;
      const matchText = !query || (
        r.pessoaNome.toLowerCase().includes(query) ||
        (r.descricao ?? "").toLowerCase().includes(query) ||
        (r.motivoNome ?? "").toLowerCase().includes(query) ||
        (r.aprovadoPorNome ?? "").toLowerCase().includes(query) ||
        (r.formaPagamentoResumo ?? "").toLowerCase().includes(query) ||
        (r.contaBancariaResumo ?? "").toLowerCase().includes(query)
      );
      const matchNf = !nfTerm || (r.nfNumero ?? "").toLowerCase().includes(nfTerm);
      return matchText && matchNf;
    });
  }, [
    aprovadorFilter,
    contaFilter,
    dateFrom,
    dateTo,
    formaFilter,
    motivoFilter,
    nfQuery,
    only,
    onlyPendentes,
    onlyToday,
    q,
    rows,
  ]);

  const filterOptions = useMemo(() => {
    const unique = (values: Array<string | null>) =>
      Array.from(new Set(values.filter((value): value is string => Boolean(value)))).sort((a, b) =>
        a.localeCompare(b, "pt-BR")
      );
    return {
      contas: unique(rows.map((row) => row.contaBancariaResumo)),
      motivos: unique(rows.map((row) => row.motivoNome)),
      aprovadores: unique(rows.map((row) => row.aprovadoPorNome)),
      formas: unique(rows.map((row) => row.formaPagamentoResumo)),
    };
  }, [rows]);

  const displayGroups = useMemo<DisplayGroup[]>(() => {
    const sorted = [...filtered].sort((a, b) => {
      if (sortMode === "valor") return Math.abs(b.valor) - Math.abs(a.valor);
      if (sortMode === "fornecedor") return a.pessoaNome.localeCompare(b.pessoaNome, "pt-BR");
      if (sortMode === "emissao") {
        const byEmission = String(a.emissao ?? a.dataBase).localeCompare(String(b.emissao ?? b.dataBase));
        if (byEmission !== 0) return byEmission;
      }
      const byDate = a.dataBase.localeCompare(b.dataBase);
      if (byDate !== 0) return byDate;
      if (a.kind !== b.kind) return a.kind === "AP" ? -1 : 1;
      return a.pessoaNome.localeCompare(b.pessoaNome, "pt-BR");
    });

    const shouldGroup = groupByDay && sortMode === "vencimento";
    const rawGroups = new Map<string, UnifiedRow[]>();
    if (shouldGroup) {
      for (const row of sorted) {
        const current = rawGroups.get(row.dataBase) ?? [];
        current.push(row);
        rawGroups.set(row.dataBase, current);
      }
    } else {
      rawGroups.set("all", sorted);
    }

    return Array.from(rawGroups.entries()).map(([groupKey, groupRows]) => {
      const duplicateMap = new Map<string, UnifiedRow[]>();
      for (const row of groupRows) {
        const duplicateKey = shouldGroup
          ? [
              row.kind,
              row.empresaId,
              row.dataBase,
              row.pessoaNome.trim().toLocaleLowerCase("pt-BR"),
              Math.round(Math.abs(row.valor) * 100),
              String(row.motivoNome ?? "").trim().toLocaleLowerCase("pt-BR"),
            ].join("|")
          : `${row.kind}:${row.parcelaId}`;
        const current = duplicateMap.get(duplicateKey) ?? [];
        current.push(row);
        duplicateMap.set(duplicateKey, current);
      }

      const entries = Array.from(duplicateMap.entries()).map(([duplicateKey, duplicateRows]): DisplayEntry => {
        const activeRows = duplicateRows.filter((row) => !isCancelledRow(row));
        const rowsForTotal = activeRows.length > 0 ? activeRows : duplicateRows;
        return {
          id: duplicateRows.length > 1 ? `duplicate:${duplicateKey}` : `${duplicateRows[0].kind}:${duplicateRows[0].parcelaId}`,
          primary: activeRows[0] ?? duplicateRows[0],
          rows: duplicateRows,
          valor: rowsForTotal.reduce((total, row) => total + row.valor, 0),
          valorAberto: rowsForTotal.reduce((total, row) => total + row.valorAberto, 0),
        };
      });

      return { id: groupKey, date: shouldGroup ? groupKey : null, entries };
    });
  }, [filtered, groupByDay, sortMode]);

  const totalsOpen = useMemo(() => {
    const sumAP = filtered.filter((r) => r.kind === "AP" && r.valorAberto > 0).reduce((acc, r) => acc + r.valorAberto, 0);
    const sumAR = filtered.filter((r) => r.kind === "AR" && r.valorAberto > 0).reduce((acc, r) => acc + r.valorAberto, 0);
    return { sumAP, sumAR };
  }, [filtered]);

  const tableTotals = useMemo(() => {
    const activeRows = filtered.filter((row) => !isCancelledRow(row));
    const calculate = (kind: Kind) =>
      activeRows
        .filter((row) => row.kind === kind)
        .reduce(
          (total, row) => ({ valor: total.valor + row.valor, aberto: total.aberto + row.valorAberto }),
          { valor: 0, aberto: 0 }
        );
    return { AP: calculate("AP"), AR: calculate("AR") };
  }, [filtered]);

  const resumo = useMemo(() => {
    const rowsResumo = filtered.filter((r) => !isCancelledRow(r));
    const previstoReceitas = rowsResumo.filter((r) => r.kind === "AR").reduce((acc, r) => acc + Number(r.valor || 0), 0);
    const previstoDespesas = rowsResumo.filter((r) => r.kind === "AP").reduce((acc, r) => acc + Number(r.valor || 0), 0);
    const saldosConfigurados = accountBalances.filter((conta) => conta.configurada);
    const saldoInicial = saldosConfigurados.reduce((acc, conta) => acc + (conta.saldoInicialPeriodo ?? 0), 0);
    const realizadoReceitas = rowsResumo
      .filter((r) => r.kind === "AR")
      .reduce((acc, r) => acc + Math.max(0, Number(r.valor || 0) - Number(r.valorAberto || 0)), 0);
    const realizadoDespesas = rowsResumo
      .filter((r) => r.kind === "AP")
      .reduce((acc, r) => acc + Math.max(0, Number(r.valor || 0) - Number(r.valorAberto || 0)), 0);
    const saldoAtual = saldosConfigurados.reduce((acc, conta) => acc + (conta.saldoAtual ?? 0), 0);

    return {
      previsto: {
        saldoInicial,
        receitas: previstoReceitas,
        despesas: previstoDespesas,
        saldoFinal: saldoInicial + previstoReceitas - previstoDespesas,
      },
      realizado: {
        saldoInicial,
        receitas: realizadoReceitas,
        despesas: realizadoDespesas,
        transferencias: 0,
        saldoFinal: saldoInicial + realizadoReceitas - realizadoDespesas,
      },
      saldoAtual,
      contasConfiguradas: saldosConfigurados.length,
      contasPendentes: accountBalances.length - saldosConfigurados.length,
    };
  }, [accountBalances, filtered]);

  const balanceSummary = useMemo(() => {
    const configured = accountBalances
      .filter((conta) => conta.configurada)
      .sort((a, b) => Number(b.saldoAtual ?? 0) - Number(a.saldoAtual ?? 0));
    const referenceDates = configured
      .map((conta) => conta.saldoReferenciaData)
      .filter((value): value is string => Boolean(value))
      .sort();
    const latestReference = referenceDates.at(-1) ?? null;
    const ageDays = latestReference
      ? Math.max(0, Math.round((toDateOnly(todayISO()).getTime() - toDateOnly(latestReference).getTime()) / 86_400_000))
      : null;
    return { configured, latestReference, ageDays };
  }, [accountBalances]);

  const toggleExpanded = useCallback((entryId: string) => {
    setExpandedRows((current) => {
      const next = new Set(current);
      if (next.has(entryId)) next.delete(entryId);
      else next.add(entryId);
      return next;
    });
  }, []);

  const exportCsv = useCallback(() => {
    const header = [
      "Tipo",
      "Empresa",
      "NF",
      "Fornecedor/Cliente",
      "Descrição",
      "Motivo",
      "Aprovado por",
      "Parcela",
      "Forma de pagamento",
      "Conta bancária",
      "Emissão",
      "Competência",
      "Vencimento",
      "Base da data",
      "OS",
      "Valor",
      "Aberto",
      "Situação",
    ];
    const lines = filtered.map((row) => {
      const status = statusDisplay(row);
      return [
        row.kind,
        row.empresaNome,
        row.nfNumero ?? "",
        row.pessoaNome,
        row.descricao ?? "",
        row.motivoNome ?? "",
        row.aprovadoPorNome ?? "",
        row.parcelaTotal && row.parcelaTotal > 1 ? fmtParcela(row.parcelaNumero, row.parcelaTotal) : "",
        row.formaPagamentoResumo ?? "",
        row.contaBancariaResumo ?? "",
        row.emissao ? formatDateBR(row.emissao) : "",
        row.competencia ? formatDateBR(row.competencia) : "",
        formatDateBR(row.vencimento),
        formatDateBR(row.dataBase),
        row.osNumero ?? "",
        formatMoneyBR(row.valor),
        formatMoneyBR(row.valorAberto),
        status.label,
      ]
        .map(csvCell)
        .join(";");
    });
    const csv = `\uFEFF${header.map(csvCell).join(";")}\n${lines.join("\n")}`;
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `contas-pagar-receber-${month}.csv`;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 1_000);
  }, [filtered, month]);

  const selectedMotivo = useMemo(() => {
    if (!motivoId) return null;
    return motivos.find((m) => m.id === motivoId) ?? null;
  }, [motivoId, motivos]);

  const cancelAplicacaoSelecionada = useMemo(() => {
    if (!cancelPagamentoId) return null;
    return aplicacoes.find((a) => String(a.pagamento.id) === cancelPagamentoId) ?? null;
  }, [aplicacoes, cancelPagamentoId]);

  const open = useCallback(
    async (row: UnifiedRow, initialTab?: ActionTab) => {
      resetModalState();
      setSelected(row);
      setTab(initialTab ?? (row.kind === "AP" ? "APROVAR" : "RECEBER"));
      setEditVencimentoDate(row.vencimento);
      setEditDescricao(row.descricao ?? "");
      setNovoValorFinal(formatMoneyBR(row.valor));
      setSplitRecebimento(false);
      setSplitVencimentoDate(row.vencimento);

      try {
        if (row.empresaId && row.empresaId !== te.empresaId) {
          await te.setEmpresaId(row.empresaId);
        }

        // Prefill AP approval fields from:
        // 1) existing approval row (f.titulo_aprovacao)
        // 2) imported title values (f.titulo.motivo_compra_id and f.documento_fiscal.os_id_import)
        // 3) default motivo (ESTOQUE)
        let prefMotivoId: string | null = null;
        let prefMotivoOutrosText: string | null = null;
        let prefOsInternalId: number | null = null;

        if (row.kind === "AP") {
          type AprovacaoRow = { motivo_compra_id: unknown; motivo_outros_text: unknown; os_id: unknown };
          const { data: aprovacao } = await supabase
            .schema("f")
            .from("titulo_aprovacao")
            .select("motivo_compra_id,motivo_outros_text,os_id")
            .eq("titulo_id", row.tituloId)
            .is("deleted_at", null)
            .maybeSingle<AprovacaoRow>();

          if (aprovacao?.motivo_compra_id) prefMotivoId = String(aprovacao.motivo_compra_id);
          if (typeof aprovacao?.motivo_outros_text === "string") prefMotivoOutrosText = aprovacao.motivo_outros_text;
          if (aprovacao?.os_id !== null && aprovacao?.os_id !== undefined && aprovacao.os_id !== "") {
            const n = Number(aprovacao.os_id);
            if (Number.isFinite(n)) prefOsInternalId = n;
          }

          // Load title meta (emissao + origin) and also use it to prefill missing approval fields.
          type TituloRow = {
            motivo_compra_id: unknown;
            emissao_date: unknown;
            documento_fiscal_id: unknown;
            documento_fiscal?: { os_id_import?: unknown } | null;
          };
          const { data: titulo } = await supabase
            .schema("f")
            .from("titulo")
            .select("motivo_compra_id,emissao_date,documento_fiscal_id,documento_fiscal:documento_fiscal_id(os_id_import)")
            .eq("id", row.tituloId)
            .is("deleted_at", null)
            .maybeSingle<TituloRow>();

          const documentoFiscalId = titulo?.documento_fiscal_id ? String(titulo.documento_fiscal_id) : null;
          const emissaoDate = titulo?.emissao_date ? String(titulo.emissao_date) : null;
          setTituloMeta({ documentoFiscalId, emissaoDate });
          setEditEmissaoDate(emissaoDate ?? row.emissao ?? todayISO());

          if (!prefMotivoId && titulo?.motivo_compra_id) prefMotivoId = String(titulo.motivo_compra_id);
          if (prefOsInternalId === null) {
            const osImport = titulo?.documento_fiscal?.os_id_import;
            const n = osImport === null || osImport === undefined || osImport === "" ? NaN : Number(osImport);
            if (Number.isFinite(n)) prefOsInternalId = n;
          }

          if (prefMotivoId) setMotivoId(prefMotivoId);
          if (prefMotivoOutrosText) setMotivoOutrosText(prefMotivoOutrosText);

          // Convert internal OS id -> displayed OS number
          if (prefOsInternalId !== null) {
            type OsRow = { numero_os: unknown };
            const { data: osRow } = await supabase
              .from("ordens_servico")
              .select("numero_os")
              .eq("id", prefOsInternalId)
              .maybeSingle<OsRow>();

            const numero = osRow?.numero_os ? String(osRow.numero_os) : "";
            if (numero) setOsId(numero);
          }
        }

        if (row.kind === "AR") {
          type TituloArRow = { os_id: unknown };
          const { data: tituloAr } = await supabase
            .schema("f")
            .from("titulo")
            .select("os_id")
            .eq("id", row.tituloId)
            .is("deleted_at", null)
            .maybeSingle<TituloArRow>();

          const osInternalId = tituloAr?.os_id;
          const n =
            osInternalId === null || osInternalId === undefined || osInternalId === ""
              ? NaN
              : Number(osInternalId);

          if (Number.isFinite(n)) {
            type OsRow = { numero_os: unknown };
            const { data: osRow } = await supabase
              .from("ordens_servico")
              .select("numero_os")
              .eq("id", n)
              .maybeSingle<OsRow>();
            setArOsNumero(osRow?.numero_os ? String(osRow.numero_os) : null);
          }
        }

        if (row.kind === "AP" && motivos.length === 0) {
          const { data, error } = await supabase
            .schema("f")
            .from("motivo_compra")
            .select("id,codigo,nome,requires_text,requires_os")
            .eq("ativo", true)
            .is("deleted_at", null)
            .order("nome", { ascending: true });
          if (!error) {
            type MotivoCompraRow = {
              id: unknown;
              codigo: unknown;
              nome: unknown;
              requires_text: unknown;
              requires_os: unknown;
            };
            const mapped = ((data ?? []) as MotivoCompraRow[]).map((m) => ({
              id: String(m.id),
              codigo: String(m.codigo),
              nome: String(m.nome),
              requires_text: Boolean(m.requires_text),
              requires_os: Boolean(m.requires_os),
            }));
            setMotivos(mapped);

            // Only default to ESTOQUE when we couldn't prefill from import/approval.
            const estoque = mapped.find((m) => m.codigo === "ESTOQUE") ?? null;
            if (!prefMotivoId && estoque) setMotivoId(estoque.id);
          }
        }

        if (contas.length === 0 || row.empresaId !== te.empresaId) {
          const { data, error } = await supabase
            .schema("f")
            .from("conta_bancaria")
            .select("id,codigo,nome")
            .eq("ativo", true)
            .is("deleted_at", null)
            .order("nome", { ascending: true });
          if (!error) {
            type ContaBancariaRow = { id: unknown; codigo: unknown; nome: unknown };
            const mapped = ((data ?? []) as ContaBancariaRow[]).map((c) => ({
              id: String(c.id),
              codigo: String(c.codigo),
              nome: String(c.nome),
            }));
            setContas(mapped);
            if (mapped.length === 1) setContaBancariaId(mapped[0].id);
          }
        }

        const { data: applied, error: appliedErr } = await supabase
          .schema("f")
          .from("pagamento_item")
          .select("valor,pagamento:pagamento_id(id,conta_bancaria_id,data_pagamento,forma_pagamento,valor)")
          .eq("titulo_parcela_id", row.parcelaId)
          .is("deleted_at", null)
          .order("created_at", { ascending: false });
        if (!appliedErr) {
          const mapped = (applied ?? []) as unknown as PagamentoAplicado[];
          setAplicacoes(mapped);
          const totalPago = mapped.reduce((total, item) => total + Number(item.valor ?? 0), 0);
          setNovoValorFinal(formatMoneyBR(totalPago > 0 ? totalPago : row.valor));
          if (row.kind === "AP" && mapped.length > 0) {
            setCancelPagamentoId(String(mapped[0].pagamento.id));
          }
        }

        if (row.kind === "AP" && te.tenantId) {
          type RevisaoValorRow = {
            id: unknown;
            revisado_em: unknown;
            valor_anterior: unknown;
            valor_novo: unknown;
            diferenca: unknown;
            valor_pago: unknown;
            saldo_anterior: unknown;
            saldo_novo: unknown;
            motivo: unknown;
            origem: unknown;
            revisado_por: unknown;
          };
          const { data: revisoes, error: revisoesErr } = await supabase.schema("f").rpc("historico_revisoes_valor_ap", {
            p_tenant_id: te.tenantId,
            p_empresa_id: row.empresaId,
            p_titulo_id: row.tituloId,
            p_titulo_parcela_id: row.parcelaId,
          });
          if (!revisoesErr) {
            setRevisoesValor(
              ((revisoes ?? []) as RevisaoValorRow[]).map((revisao) => ({
                id: String(revisao.id),
                revisadoEm: String(revisao.revisado_em),
                valorAnterior: Number(revisao.valor_anterior ?? 0),
                valorNovo: Number(revisao.valor_novo ?? 0),
                diferenca: Number(revisao.diferenca ?? 0),
                valorPago: Number(revisao.valor_pago ?? 0),
                saldoAnterior: Number(revisao.saldo_anterior ?? 0),
                saldoNovo: Number(revisao.saldo_novo ?? 0),
                motivo: String(revisao.motivo ?? ""),
                origem: String(revisao.origem ?? ""),
                revisadoPor: String(revisao.revisado_por ?? "Sistema"),
              }))
            );
          }
        }
      } catch (e: unknown) {
        setActionErr(getErrorMessage(e, "Erro ao preparar modal."));
      }
    },
    [resetModalState, supabase, contas, motivos, te]
  );

  const close = useCallback(() => {
    setSelected(null);
    resetModalState();
  }, [resetModalState]);

  // UX: when opening/going to the "PAGAR" tab, prefill value with the current open amount.
  useEffect(() => {
    if (!selected) return;
    if (tab !== "PAGAR" && tab !== "RECEBER") return;
    if (tab === "PAGAR" && selected.kind !== "AP") return;
    if (tab === "RECEBER" && selected.kind !== "AR") return;
    if (valorMov.trim()) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setValorMov(formatMoneyBR(selected.valorAberto));
  }, [selected, tab, valorMov]);

  // UX: prefill payment/receipt date with today when entering PAGAR/RECEBER.
  useEffect(() => {
    if (!selected) return;
    if (tab !== "PAGAR" && tab !== "RECEBER") return;
    if (dataPagamento.trim()) return;

    const today = new Date();
    const iso = `${today.getFullYear()}-${pad2(today.getMonth() + 1)}-${pad2(today.getDate())}`;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setDataPagamento(iso);
  }, [dataPagamento, selected, tab]);

  useEffect(() => {
    if (!selected || selected.kind !== "AP") return;
    if (cancelPagamentoId) return;
    if (!aplicacoes.length) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setCancelPagamentoId(String(aplicacoes[0].pagamento.id));
  }, [aplicacoes, cancelPagamentoId, selected]);

  const doAprovar = useCallback(async () => {
    if (!selected || selected.kind !== "AP") return;
    if (!motivoId) {
      setActionErr("Selecione o motivo.");
      return;
    }
    if (selectedMotivo?.requires_text && !motivoOutrosText.trim()) {
      setActionErr("Preencha o motivo (texto).");
      return;
    }
    if (selectedMotivo?.requires_os && !osId.trim()) {
      setActionErr("Informe a OS.");
      return;
    }

    setActionBusy(true);
    setActionErr(null);
    try {
      let os: number | null = null;
      if (selectedMotivo?.requires_os) {
        const osNumero = osId.trim();
        type OsLookupRow = { id: unknown };

        // Prefer lookup by OS number (numero_os), since that's what the UI asks for.
        const { data: byNumero } = await supabase
          .from("ordens_servico")
          .select("id")
          .eq("numero_os", osNumero)
          .maybeSingle<OsLookupRow>();

        if (byNumero?.id) {
          const n = Number(byNumero.id);
          os = Number.isFinite(n) ? n : null;
        }

        // Fallback: accept direct internal id if user typed it.
        if (os === null) {
          const asId = Number(osNumero);
          if (Number.isFinite(asId)) {
            const { data: byId } = await supabase
              .from("ordens_servico")
              .select("id")
              .eq("id", asId)
              .maybeSingle<OsLookupRow>();
            if (byId?.id) os = asId;
          }
        }

        if (os === null) {
          setActionErr(`OS não encontrada: ${osNumero}`);
          setActionBusy(false);
          return;
        }
      }
      const { error } = await supabase.schema("f").rpc("aprovar_titulo_ap", {
        p_titulo_id: selected.tituloId,
        p_motivo_compra_id: motivoId,
        p_os_id: os,
        p_motivo_outros_text: selectedMotivo?.requires_text ? motivoOutrosText.trim() : null,
        p_change_reason: "UI:contas_pagar_receber",
      });
      if (error) throw error;

      await load();
      close();
    } catch (e: unknown) {
      setActionErr(getErrorMessage(e, "Erro ao aprovar."));
    } finally {
      setActionBusy(false);
    }
  }, [close, load, motivoId, motivoOutrosText, osId, selected, selectedMotivo, supabase]);

  const doRevisarValorFinal = useCallback(async () => {
    if (!selected || selected.kind !== "AP" || !te.tenantId) return;

    const novoValor = parseMoneyOrZero(novoValorFinal);
    if (!Number.isFinite(novoValor) || novoValor <= 0) {
      setActionErr("Informe um novo valor final válido e maior que zero.");
      return;
    }
    if (toCents(novoValor) < toCents(valorPagoParcela)) {
      setActionErr(`O valor final não pode ser menor que o total já pago (${formatMoneyBR(valorPagoParcela)}).`);
      return;
    }
    if (toCents(novoValor) === toCents(selected.valor)) {
      setActionErr("O novo valor final é igual ao valor atual.");
      return;
    }

    const motivo = motivoRevisao.trim();
    if (motivo.length < 5) {
      setActionErr("Informe o motivo da revisão (mínimo 5 caracteres).");
      return;
    }

    setActionBusy(true);
    setActionErr(null);
    try {
      const { error } = await supabase.schema("f").rpc("revisar_valor_final_ap", {
        p_tenant_id: te.tenantId,
        p_empresa_id: selected.empresaId,
        p_titulo_id: selected.tituloId,
        p_titulo_parcela_id: selected.parcelaId,
        p_novo_valor_final: novoValor.toFixed(2),
        p_motivo: motivo,
        p_origem: "REVISAO_MANUAL",
      });
      if (error) throw error;

      await load();
      const saldoNovo = Math.max(0, novoValor - valorPagoParcela);
      setToastMsg(
        saldoNovo === 0
          ? `Valor final revisado para ${formatMoneyBR(novoValor)}. A parcela foi encerrada sem novo pagamento.`
          : `Valor final revisado para ${formatMoneyBR(novoValor)}. Saldo atual: ${formatMoneyBR(saldoNovo)}.`
      );
      if (toastTimeoutRef.current !== null) window.clearTimeout(toastTimeoutRef.current);
      toastTimeoutRef.current = window.setTimeout(() => setToastMsg(null), 7000);
      close();
    } catch (e: unknown) {
      setActionErr(getErrorMessage(e, "Erro ao revisar o valor final."));
    } finally {
      setActionBusy(false);
    }
  }, [close, load, motivoRevisao, novoValorFinal, parseMoneyOrZero, selected, supabase, te.tenantId, toCents, valorPagoParcela]);

  const doMov = useCallback(
    async (mode: "PAGAR" | "RECEBER") => {
      if (!selected) return;
      if (mode === "PAGAR" && selected.kind !== "AP") return;
      if (mode === "RECEBER" && selected.kind !== "AR") return;

      const principal = parseMoneyOrZero(valorMov);
      const juros = parseMoneyOrZero(valorJuros);
      const multa = parseMoneyOrZero(valorMulta);
      const desconto = parseMoneyOrZero(valorDesconto);

      if (!Number.isFinite(principal) || principal <= 0) {
        setActionErr("Informe um valor principal válido.");
        return;
      }
      if (!Number.isFinite(juros) || juros < 0) {
        setActionErr("Juros deve ser >= 0.");
        return;
      }
      if (!Number.isFinite(multa) || multa < 0) {
        setActionErr("Multa deve ser >= 0.");
        return;
      }
      if (!Number.isFinite(desconto) || desconto < 0) {
        setActionErr("Desconto deve ser >= 0.");
        return;
      }

      const principalCents = toCents(principal);
      const jurosCents = toCents(juros);
      const multaCents = toCents(multa);
      const descontoCents = toCents(desconto);
      const openCents = toCents(Number(selected.valorAberto ?? 0));

      if (
        !Number.isFinite(principalCents) ||
        !Number.isFinite(jurosCents) ||
        !Number.isFinite(multaCents) ||
        !Number.isFinite(descontoCents) ||
        !Number.isFinite(openCents)
      ) {
        setActionErr("Valores inválidos.");
        return;
      }

      if (principalCents > openCents) {
        setActionErr("Valor principal maior que o saldo em aberto.");
        return;
      }

      const baseCents = principalCents + jurosCents + multaCents;
      if (descontoCents > baseCents) {
        setActionErr("Desconto não pode ser maior que (principal + juros + multa).");
        return;
      }

      const totalCents = baseCents - descontoCents;
      if (totalCents <= 0) {
        setActionErr("Total a pagar agora deve ser maior que zero.");
        return;
      }

      if (mode === "RECEBER" && splitRecebimento) {
        if (principalCents >= openCents) {
          setActionErr("Para desdobrar, o valor recebido deve ser menor que o saldo em aberto.");
          return;
        }
        if (!splitVencimentoDate) {
          setActionErr("Informe o vencimento da parcela remanescente.");
          return;
        }
      }

      const confirmarComoValorFinal =
        mode === "PAGAR" && pagamentoComoValorFinal && principalCents < openCents;
      if (confirmarComoValorFinal && motivoRevisao.trim().length < 5) {
        setActionErr("Informe o motivo da revisão do valor final (mínimo 5 caracteres).");
        return;
      }

      if (!contaBancariaId) {
        setActionErr("Selecione a conta bancária.");
        return;
      }
      if (!dataPagamento) {
        setActionErr("Informe a data.");
        return;
      }

      setActionBusy(true);
      setActionErr(null);
      try {
        if (mode === "RECEBER" && splitRecebimento) {
          const { error: splitErr } = await supabase.schema("f").rpc("desdobrar_parcela_ar_para_recebimento", {
            p_parcela_id: selected.parcelaId,
            p_valor_receber: centsToNumericString(principalCents),
            p_novo_vencimento_date: splitVencimentoDate,
            p_change_reason: "UI: desdobrar AR para recebimento parcial",
          });
          if (splitErr) throw splitErr;
        }

        const movementArgs = {
          p_titulo_id: selected.tituloId,
          p_conta_bancaria_id: contaBancariaId,
          p_data_pagamento: dataPagamento,
          p_forma_pagamento: formaPagamento,
          p_valor_principal: centsToNumericString(principalCents),
          p_valor_juros: centsToNumericString(jurosCents),
          p_valor_multa: centsToNumericString(multaCents),
          p_valor_desconto: centsToNumericString(descontoCents),
          p_observacoes: observacoes.trim() ? observacoes.trim() : null,
        };

        const { error } = confirmarComoValorFinal
          ? await supabase.schema("f").rpc("registrar_pagamento_ap_valor_final", {
              ...movementArgs,
              p_tenant_id: te.tenantId,
              p_empresa_id: selected.empresaId,
              p_titulo_parcela_id: selected.parcelaId,
              p_motivo_ajuste: motivoRevisao.trim(),
            })
          : await supabase
              .schema("f")
              .rpc(mode === "PAGAR" ? "registrar_pagamento_ap_v2" : "registrar_recebimento_ar_v2", {
                ...movementArgs,
                p_change_reason: "UI: popup pagar/receber (juros/multa/desconto)",
              });
        if (error) throw error;

        await load();

        const okMsg =
          `${mode === "PAGAR" ? "Pagamento" : "Recebimento"} registrado: ` +
          `principal R$ ${centsToMoneyString(principalCents)}` +
          `, juros R$ ${centsToMoneyString(jurosCents)}` +
          `, multa R$ ${centsToMoneyString(multaCents)}` +
          `, desconto R$ ${centsToMoneyString(descontoCents)}` +
          `, total R$ ${centsToMoneyString(totalCents)}.` +
          (confirmarComoValorFinal ? " Diferença da previsão encerrada com revisão auditada." : "");

        setToastMsg(okMsg);
        if (toastTimeoutRef.current !== null) window.clearTimeout(toastTimeoutRef.current);
        toastTimeoutRef.current = window.setTimeout(() => setToastMsg(null), 7000);

        close();
      } catch (e: unknown) {
        setActionErr(getErrorMessage(e, mode === "PAGAR" ? "Erro ao pagar." : "Erro ao receber."));
      } finally {
        setActionBusy(false);
      }
    },
    [
      centsToMoneyString,
      centsToNumericString,
      close,
      contaBancariaId,
      dataPagamento,
      formaPagamento,
      load,
      motivoRevisao,
      observacoes,
      pagamentoComoValorFinal,
      parseMoneyOrZero,
      selected,
      splitRecebimento,
      splitVencimentoDate,
      supabase,
      te.tenantId,
      toCents,
      valorDesconto,
      valorJuros,
      valorMov,
      valorMulta,
    ]
  );

  const doCancelarPagamento = useCallback(async () => {
    if (!selected || selected.kind !== "AP") return;
    if (!cancelPagamentoId) {
      setActionErr("Selecione o pagamento que deseja cancelar.");
      return;
    }

    const motivo = cancelMotivo.trim();
    if (motivo.length < 5) {
      setActionErr("Informe o motivo do cancelamento (minimo 5 caracteres).");
      return;
    }

    setActionBusy(true);
    setActionErr(null);
    setCancelConfirmOpen(false);
    try {
      const { error } = await supabase.schema("f").rpc("estornar_pagamento_ap", {
        p_pagamento_id: cancelPagamentoId,
        p_motivo: motivo,
      });
      if (error) throw error;

      await load();
      setToastMsg("Pagamento cancelado com sucesso.");
      if (toastTimeoutRef.current !== null) window.clearTimeout(toastTimeoutRef.current);
      toastTimeoutRef.current = window.setTimeout(() => setToastMsg(null), 6000);
      close();
    } catch (e: unknown) {
      if (isMissingRpc(e, "estornar_pagamento_ap")) {
        setActionErr("Funcao de cancelamento nao disponivel no banco (estornar_pagamento_ap).");
      } else {
        setActionErr(getErrorMessage(e, "Erro ao cancelar pagamento."));
      }
    } finally {
      setActionBusy(false);
    }
  }, [cancelMotivo, cancelPagamentoId, close, load, selected, supabase]);

  const doCancelarTitulo = useCallback(async () => {
    if (!selected || selected.kind !== "AP") return;

    const motivo = cancelMotivo.trim();
    if (motivo.length < 5) {
      setActionErr("Informe o motivo do cancelamento (minimo 5 caracteres).");
      return;
    }

    setActionBusy(true);
    setActionErr(null);
    setCancelConfirmOpen(false);
    try {
      const { error } = await supabase.schema("f").rpc("cancelar_titulo_ap", {
        p_titulo_id: selected.tituloId,
        p_motivo: motivo,
      });
      if (error) throw error;

      await load();
      setToastMsg("Lancamento cancelado com sucesso.");
      if (toastTimeoutRef.current !== null) window.clearTimeout(toastTimeoutRef.current);
      toastTimeoutRef.current = window.setTimeout(() => setToastMsg(null), 6000);
      close();
    } catch (e: unknown) {
      if (isMissingRpc(e, "cancelar_titulo_ap")) {
        setActionErr("Funcao de cancelamento nao disponivel no banco (cancelar_titulo_ap).");
      } else {
        setActionErr(getErrorMessage(e, "Erro ao cancelar lancamento."));
      }
    } finally {
      setActionBusy(false);
    }
  }, [cancelMotivo, close, load, selected, supabase]);

  if (!canFinanceiro) {
    return <div className="text-sm text-zinc-300">Sem permissão financeira.</div>;
  }

  const showEmpresaInRows = empresaOptions.length > 1 && effectiveEmpresaFilter === "ALL";
  const selectedEmpresaLabel =
    effectiveEmpresaFilter === "ALL"
      ? empresaOptions.map((empresa) => empresa.label).join(" + ") || "Empresas"
      : empresaNomeById.get(effectiveEmpresaFilter) ?? "Empresa";
  const positionOpen = totalsOpen.sumAR - totalsOpen.sumAP;
  const additionalFilterCount = [dateFrom, dateTo, nfQuery, contaFilter, motivoFilter, aprovadorFilter, formaFilter].filter(
    Boolean
  ).length;
  const comparisonRows = [
    {
      label: "Saldo inicial",
      planned: resumo.previsto.saldoInicial,
      actual: resumo.realizado.saldoInicial,
      delta: resumo.realizado.saldoInicial - resumo.previsto.saldoInicial,
      tone: "neutral",
      percent: null,
    },
    {
      label: "Receitas (+)",
      planned: resumo.previsto.receitas,
      actual: resumo.realizado.receitas,
      delta: resumo.realizado.receitas - resumo.previsto.receitas,
      tone: resumo.realizado.receitas >= resumo.previsto.receitas ? "positive" : "negative",
      percent: resumo.previsto.receitas > 0 ? (resumo.realizado.receitas / resumo.previsto.receitas) * 100 : null,
    },
    {
      label: "Despesas (−)",
      planned: resumo.previsto.despesas,
      actual: resumo.realizado.despesas,
      delta: resumo.realizado.despesas - resumo.previsto.despesas,
      tone: resumo.realizado.despesas <= resumo.previsto.despesas ? "positive" : "negative",
      percent: resumo.previsto.despesas > 0 ? (resumo.realizado.despesas / resumo.previsto.despesas) * 100 : null,
    },
    {
      label: "Saldo final",
      planned: resumo.previsto.saldoFinal,
      actual: resumo.realizado.saldoFinal,
      delta: resumo.realizado.saldoFinal - resumo.previsto.saldoFinal,
      tone: resumo.realizado.saldoFinal >= resumo.previsto.saldoFinal ? "positive" : "negative",
      percent: null,
    },
  ];

  return (
    <div className="carteira-theme contas-financeiras-page space-y-4">
      <header className="cf-page-header">
        <div>
          <div className="cf-breadcrumb">
            <Link href="/financeiro">Financeiro</Link><span>›</span><span>Contas a pagar e receber</span>
          </div>
          <h1>Contas a pagar e receber</h1>
          <p>{monthDisplay(month)} · {selectedEmpresaLabel} · base: {dateBaseLabel(dateBase).toLocaleLowerCase("pt-BR")}</p>
        </div>
        <div className="cf-header-actions">
          <button type="button" className="cf-outline-button" onClick={exportCsv}>Exportar</button>
          <button type="button" className="cf-outline-button" onClick={() => void load()}>Atualizar</button>
          {canWriteFinanceiro && only !== "AR" ? <button type="button" className="cf-outline-button" onClick={() => void openCreate("AP")}>Novo AP</button> : null}
          {canWriteFinanceiro && only !== "AP" ? <button type="button" className="cf-outline-button" onClick={() => void openCreate("AR")}>Novo AR</button> : null}
        </div>
      </header>

      <section className="cf-top-grid">
        <div className="cf-panel cf-comparison-panel">
          <div className="cf-panel-heading">
            <div>
              <h2>Previsto × Realizado</h2>
              <p>mesmo conjunto de títulos · {monthDisplay(month)}</p>
            </div>
            <span>{dateBaseLabel(dateBase)}</span>
          </div>
          <div className="cf-comparison-table" role="table" aria-label="Comparativo previsto e realizado">
            <div className="cf-comparison-row cf-comparison-head" role="row">
              <span role="columnheader" />
              <span role="columnheader">Previsto</span>
              <span role="columnheader">Realizado</span>
              <span role="columnheader">Diferença</span>
            </div>
            {comparisonRows.map((item, index) => (
              <div className={`cf-comparison-row ${index === comparisonRows.length - 1 ? "cf-comparison-total" : ""}`} role="row" key={item.label}>
                <strong role="rowheader">{item.label}</strong>
                <span className="cf-panel-money" role="cell">{formatMoneyBR(item.planned)}</span>
                <span className="cf-panel-money" role="cell">{formatMoneyBR(item.actual)}</span>
                <span className={`cf-comparison-delta cf-tone-${item.tone}`} role="cell">
                  <span>{signedDeltaDisplay(item.delta)}</span>
                  {item.percent !== null ? <small>{Math.round(item.percent)}% realizado</small> : null}
                </span>
              </div>
            ))}
          </div>
        </div>

        <div className="cf-panel cf-balance-panel">
          <div className="cf-panel-heading">
            <div><h2>Saldo atual</h2><p>soma das {balanceSummary.configured.length} contas bancárias</p></div>
            <Link href="/financeiro/cadastros/contas-bancarias">Ajustar saldos ›</Link>
          </div>
          <div className="cf-balance-total">R$ {formatMoneyBR(resumo.saldoAtual)}</div>
          <div className="cf-balance-accounts">
            {balanceSummary.configured.map((conta) => (
              <div key={conta.contaId}><span>{accountDisplayLabel(conta.codigo, conta.nome, conta.empresaNome)}</span><strong>{formatMoneyBR(conta.saldoAtual)}</strong></div>
            ))}
            {balanceSummary.configured.length === 0 ? <div><span>Nenhuma conta configurada</span><strong>—</strong></div> : null}
          </div>
          {balanceSummary.latestReference && balanceSummary.ageDays !== null && balanceSummary.ageDays > 7 ? (
            <div className="cf-balance-warning">⚠ Último ajuste em {formatDateBR(balanceSummary.latestReference)} — há {balanceSummary.ageDays} dias</div>
          ) : null}
          <div className="cf-today-line"><strong>Hoje, {formatDateBR(todayISO())}:</strong> {todaySummary.entradas === 0 && todaySummary.saidas === 0 ? "nenhuma entrada ou saída" : `+ ${formatMoneyBR(todaySummary.entradas)} · − ${formatMoneyBR(todaySummary.saidas)}`}</div>
        </div>
      </section>

      <section className="cf-open-indicators" aria-label="Posição em aberto">
        <div><span>AP em aberto</span><strong className="cf-value-negative">R$ {formatMoneyBR(totalsOpen.sumAP)}</strong><small>a pagar no conjunto filtrado</small></div>
        <div><span>AR em aberto</span><strong className="cf-value-positive">R$ {formatMoneyBR(totalsOpen.sumAR)}</strong><small>a receber no conjunto filtrado</small></div>
        <div><span>Posição líquida</span><strong className={positionOpen >= 0 ? "cf-value-positive" : "cf-value-negative"}>{positionOpen >= 0 ? "+ " : "− "}R$ {formatMoneyBR(Math.abs(positionOpen))}</strong><small>a receber menos a pagar</small></div>
      </section>

      <section className="cf-filter-section" aria-label="Filtros financeiros">
        <div className="cf-filter-bar">
          <input aria-label="Buscar" value={q} onChange={(event) => setQ(event.target.value)} placeholder="Fornecedor, cliente, descrição, motivo ou conta" />
          <input aria-label="Período" type="month" value={month} onChange={(event) => {
            const next = event.target.value;
            if (!/^\d{4}-\d{2}$/.test(next)) return;
            setOnlyToday(false);
            setYear(Number(next.slice(0, 4)));
            setMonthNum(Number(next.slice(5, 7)));
          }} />
          <select aria-label="Tipo" value={only} onChange={(event) => setOnly(event.target.value as "ALL" | Kind)}>
            <option value="ALL">AP + AR</option><option value="AP">AP</option><option value="AR">AR</option>
          </select>
          <select aria-label="Empresa" value={effectiveEmpresaFilter} onChange={(event) => setEmpresaFilter(event.target.value)}>
            {empresaOptions.length > 1 ? <option value="ALL">Ambas</option> : null}
            {empresaOptions.map((empresa) => <option key={empresa.id} value={empresa.id}>{empresa.label}</option>)}
          </select>
          <label className="cf-switch-label">
            <button type="button" role="switch" aria-checked={onlyPendentes} className={`cf-switch ${onlyPendentes ? "cf-switch-active" : ""}`} onClick={() => setOnlyPendentes((current) => !current)}><span /></button>
            Somente pendentes
          </label>
          <div className="cf-filter-divider" />
          <button type="button" className="cf-more-button" aria-expanded={moreFiltersOpen} onClick={() => setMoreFiltersOpen((current) => !current)}>
            Mais filtros{additionalFilterCount ? ` (${additionalFilterCount})` : ""} ▾
          </button>
        </div>

        {moreFiltersOpen ? (
          <div className="cf-more-panel">
            <div className="cf-more-panel-head"><div><strong>Mais filtros</strong><span>Refine o conjunto sem sair da tela.</span></div><button type="button" onClick={() => setMoreFiltersOpen(false)}>Fechar</button></div>
            <div className="cf-more-grid">
              <label><span>De</span><input type="date" value={dateFrom} onChange={(event) => { setOnlyToday(false); setDateFrom(event.target.value); }} /></label>
              <label><span>Até</span><input type="date" value={dateTo} onChange={(event) => { setOnlyToday(false); setDateTo(event.target.value); }} /></label>
              <label><span>Nota fiscal</span><input value={nfQuery} onChange={(event) => setNfQuery(event.target.value)} placeholder="Número da NF" /></label>
              <label><span>Conta bancária</span><select value={contaFilter} onChange={(event) => setContaFilter(event.target.value)}><option value="">Todas</option>{filterOptions.contas.map((value) => <option key={value} value={value}>{value}</option>)}</select></label>
              <label><span>Motivo</span><select value={motivoFilter} onChange={(event) => setMotivoFilter(event.target.value)}><option value="">Todos</option>{filterOptions.motivos.map((value) => <option key={value} value={value}>{value}</option>)}</select></label>
              <label><span>Aprovado por</span><select value={aprovadorFilter} onChange={(event) => setAprovadorFilter(event.target.value)}><option value="">Todos</option>{filterOptions.aprovadores.map((value) => <option key={value} value={value}>{value}</option>)}</select></label>
              <label><span>Forma de pagamento</span><select value={formaFilter} onChange={(event) => setFormaFilter(event.target.value)}><option value="">Todas</option>{filterOptions.formas.map((value) => <option key={value} value={value}>{value}</option>)}</select></label>
              <label><span>Base da data</span><select value={dateBase} onChange={(event) => setDateBase(event.target.value as DateBase)}><option value="vencimento">Vencimento</option><option value="emissao">Emissão</option><option value="competencia">Competência</option></select></label>
              <label><span>Ordenar por</span><select value={sortMode} onChange={(event) => setSortMode(event.target.value as SortMode)}><option value="vencimento">Vencimento</option><option value="valor">Valor</option><option value="fornecedor">Fornecedor</option><option value="emissao">Emissão</option></select></label>
              <label className="cf-group-option"><span>Agrupamento</span><button type="button" role="switch" aria-checked={groupByDay} className={`cf-switch ${groupByDay ? "cf-switch-active" : ""}`} onClick={() => setGroupByDay((current) => !current)}><span /></button><em>Faixa por dia</em></label>
            </div>
            <div className="cf-more-actions">
              <button type="button" onClick={() => { setDateFrom(""); setDateTo(""); setNfQuery(""); setContaFilter(""); setMotivoFilter(""); setAprovadorFilter(""); setFormaFilter(""); }}>Limpar adicionais</button>
              <button type="button" onClick={() => setMoreFiltersOpen(false)}>Aplicar filtros</button>
            </div>
          </div>
        ) : null}

        <div className="cf-filter-chips">
          <div>
            <span>{monthDisplay(month)}</span>
            <button type="button" onClick={() => setOnly("ALL")}>{only === "ALL" ? "AP + AR" : only}{only !== "ALL" ? " ×" : ""}</button>
            <button type="button" onClick={() => setEmpresaFilter("ALL")}>{selectedEmpresaLabel}{effectiveEmpresaFilter !== "ALL" ? " ×" : ""}</button>
            <button type="button" onClick={() => setDateBase("vencimento")}>Base: {dateBaseLabel(dateBase)}{dateBase !== "vencimento" ? " ×" : ""}</button>
            {q ? <button type="button" onClick={() => setQ("")}>Busca: {q} ×</button> : null}
            {nfQuery ? <button type="button" onClick={() => setNfQuery("")}>NF: {nfQuery} ×</button> : null}
            {contaFilter ? <button type="button" onClick={() => setContaFilter("")}>Conta: {contaFilter} ×</button> : null}
            {motivoFilter ? <button type="button" onClick={() => setMotivoFilter("")}>Motivo: {motivoFilter} ×</button> : null}
          </div>
          <strong>{filtered.length} título(s) · AP {formatMoneyBR(tableTotals.AP.valor)} · AR {formatMoneyBR(tableTotals.AR.valor)}</strong>
        </div>
      </section>


      {error && <div className="text-sm text-red-300">{error}</div>}
      {toastMsg && <div className="text-sm text-emerald-300">{toastMsg}</div>}
      {loading && <div className="text-sm text-zinc-400">Carregando...</div>}

      <div className="cf-table-shell">
        <table className="cf-table">
          <colgroup>
            <col className="w-[8%]" />
            <col className="w-[40%]" />
            <col className="w-[13%]" />
            <col className="w-[13%]" />
            <col className="w-[12%]" />
            <col className="w-[12%]" />
            <col className="w-[2%]" />
          </colgroup>
          <thead>
            <tr>
              <th>Tipo</th>
              <th>Fornecedor / cliente</th>
              <th>{dateBaseLabel(dateBase)}</th>
              <th className="cf-numeric">Valor</th>
              <th className="cf-numeric">Aberto</th>
              <th>Situação</th>
              <th aria-label="Abrir detalhes" />
            </tr>
          </thead>
          <tbody>
            {displayGroups.map((group) => {
            const groupMeta = group.date ? groupDateDisplay(group.date, dateBase) : null;
              const groupRows = group.entries.flatMap((entry) => entry.rows);
              const groupActiveRows = groupRows.filter((row) => !isCancelledRow(row));
              const groupNet = groupActiveRows.reduce(
                (total, row) => total + (row.kind === "AR" ? row.valor : -row.valor),
                0
              );
              const cancelledCount = groupRows.length - groupActiveRows.length;
              return (
                <Fragment key={group.id}>
                  {groupMeta ? (
                    <tr className="cf-day-row">
                      <td colSpan={7}>
                        <div>
                          <span><strong>{groupMeta.date}</strong><small>{groupMeta.weekday} · {groupMeta.relative}</small></span>
                          <span><strong className={groupNet >= 0 ? "cf-value-positive" : "cf-value-negative"}>{signedDeltaDisplay(groupNet)}</strong><small>{groupRows.length} título(s){cancelledCount ? ` · ${cancelledCount} cancelado(s)` : ""}</small></span>
                        </div>
                      </td>
                    </tr>
                  ) : null}
                  {group.entries.map((entry) => {
                    const row = entry.primary;
                    const status = statusDisplay(row);
                    const cancelled = isCancelledRow(row);
                    const overdue = !cancelled && entry.valorAberto > 0 && isOverdue(row.vencimento);
                    const reason = row.kind === "AP" ? row.motivoNome : null;
                    const expanded = expandedRows.has(entry.id);
                    const duplicate = entry.rows.length > 1;
                    return (
                      <Fragment key={entry.id}>
                        <tr
                          className="cf-main-row"
                          onClick={() => toggleExpanded(entry.id)}
                          onKeyDown={(event) => {
                            if (event.key === "Enter" || event.key === " ") {
                              event.preventDefault();
                              toggleExpanded(entry.id);
                            }
                          }}
                          tabIndex={0}
                          aria-expanded={expanded}
                        >
                          <td>
                            <span className={`cf-kind ${row.kind === "AR" ? "cf-kind--ar" : ""}`}>{row.kind}</span>
                            {showEmpresaInRows ? <div className="cf-company" title={row.empresaNome}>{titleCaseDisplay(row.empresaNome)}</div> : null}
                          </td>
                          <td>
                            <div className="cf-party">{titleCaseDisplay(row.pessoaNome)}</div>
                            <div className="cf-description-line">
                              <span className="cf-description" title={cleanDescriptionDisplay(row)}>{cleanDescriptionDisplay(row)}</span>
                              {duplicate ? <span className="cf-duplicate-badge">conferir · {entry.rows.length} iguais</span> : null}
                              {reason ? <span className="cf-reason" title={reason}>{reason}</span> : null}
                            </div>
                          </td>
                          <td className={overdue && dateBase === "vencimento" ? "cf-overdue" : undefined}>
                            <div className="cf-date">{formatDateBR(row.dataBase)}</div>
                            <div className="cf-relative">{relativeDateLabel(row.dataBase, dateBase)}</div>
                          </td>
                          <td className="cf-numeric">
                            <span className={`cf-money ${row.kind === "AR" ? "cf-money--income" : ""} ${cancelled && !duplicate ? "cf-money--cancelled" : ""}`}>
                              {signedMoneyDisplay(row.kind, entry.valor)}
                            </span>
                          </td>
                          <td className="cf-numeric">
                            <span className={`cf-money ${entry.valorAberto <= 0 ? "cf-open--zero" : ""} ${overdue ? "cf-open--overdue" : ""}`}>
                              {entry.valorAberto <= 0 ? "—" : formatMoneyBR(entry.valorAberto)}
                            </span>
                          </td>
                          <td><span className={`cf-status cf-status--${status.variant}`}>{status.label}</span></td>
                          <td className="cf-numeric" aria-hidden="true"><span className={`cf-arrow ${expanded ? "cf-arrow-open" : ""}`}>›</span></td>
                        </tr>
                        {expanded ? (
                          <tr className="cf-detail-row">
                            <td colSpan={7}>
                              {duplicate ? (
                                <div className="cf-duplicate-list">
                                  <strong>{entry.rows.length} títulos com fornecedor, valor, data e motivo idênticos</strong>
                                  {entry.rows.map((child) => {
                                    const childStatus = statusDisplay(child);
                                    return (
                                      <div key={child.parcelaId}>
                                        <span>{child.nfNumero ? `NF ${child.nfNumero}` : fmtParcela(child.parcelaNumero, child.parcelaTotal)}</span>
                                        <span>{formatDateBR(child.vencimento)}</span>
                                        <span>{signedValueDisplay(child)}</span>
                                        <span className={`cf-status cf-status--${childStatus.variant}`}>{childStatus.label}</span>
                                        <button type="button" onClick={() => void open(child)}>Ver</button>
                                      </div>
                                    );
                                  })}
                                </div>
                              ) : null}
                              <div className="cf-detail-grid">
                                <div><span>Nota fiscal</span><strong>{row.nfNumero ?? "—"}</strong></div>
                                <div><span>Emissão</span><strong>{row.emissao ? formatDateBR(row.emissao) : "—"}</strong></div>
                                <div><span>Parcela</span><strong>{row.parcelaTotal && row.parcelaTotal > 1 ? fmtParcela(row.parcelaNumero, row.parcelaTotal) : "Única"}</strong></div>
                                <div><span>Forma de pagamento</span><strong>{row.formaPagamentoResumo ?? "—"}</strong></div>
                                <div><span>Conta bancária</span><strong>{row.contaBancariaResumo ?? "—"}</strong></div>
                                <div><span>Empresa</span><strong>{titleCaseDisplay(row.empresaNome)}</strong></div>
                                <div><span>Aprovado por</span><strong>{row.aprovadoPorNome ? titleCaseDisplay(row.aprovadoPorNome) : "—"}</strong></div>
                                <div><span>Vínculo</span><strong>{row.osId ? <Link href={`/os/${row.osId}`}>OS {row.osNumero ?? row.osId} ›</Link> : "—"}</strong></div>
                              </div>
                              <div className="cf-detail-actions">
                                <button type="button" onClick={() => void open(row)}>Ver título</button>
                                <button type="button" disabled title="Nenhum anexo disponível para este título">Anexos</button>
                                <button type="button" disabled={!canWriteFinanceiro} onClick={() => void open(row, "VENCIMENTO")}>Editar</button>
                                <button type="button" disabled={!canWriteFinanceiro || row.kind !== "AP" || row.valorAberto >= row.valor || cancelled} onClick={() => void open(row, "CANCELAR_PAGAMENTO")}>Estornar baixa</button>
                              </div>
                            </td>
                          </tr>
                        ) : null}
                      </Fragment>
                    );
                  })}
                </Fragment>
              );
            })}
            {!filtered.length && !loading && (
              <tr>
                <td colSpan={7} className="cf-empty">
                  Nenhum item neste período.
                </td>
              </tr>
            )}
          </tbody>
          <tfoot>
            <tr>
              <td colSpan={7}>
                <div className="cf-footer">
                  <span className="cf-footer-label">Totais do conjunto filtrado</span>
                  <span>
                    AP · Valor <strong>− {formatMoneyBR(tableTotals.AP.valor)}</strong> · Aberto
                    <strong>{formatMoneyBR(tableTotals.AP.aberto)}</strong>
                  </span>
                  <span className="cf-footer-ar">
                    AR · Valor <strong>+ {formatMoneyBR(tableTotals.AR.valor)}</strong> · Aberto
                    <strong>{formatMoneyBR(tableTotals.AR.aberto)}</strong>
                  </span>
                </div>
              </td>
            </tr>
          </tfoot>
        </table>
      </div>

      {selected && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div
            className="absolute inset-0 bg-black/60"
            onClick={() => {
              if (cancelConfirmOpen) {
                setCancelConfirmOpen(false);
                return;
              }
              close();
            }}
          />
          <div className="relative w-full max-w-2xl rounded-lg border border-zinc-800 bg-zinc-950 p-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <div className="text-sm text-zinc-400">{selected.kind === "AP" ? "Conta a pagar" : "Conta a receber"}</div>
                <div className="text-lg font-semibold text-zinc-100">{selected.pessoaNome}</div>
                <div className="text-sm text-zinc-400">Empresa: {selected.empresaNome}</div>
                {selected.formaPagamentoResumo ? (
                  <div className="text-sm text-zinc-400">Forma: {selected.formaPagamentoResumo}</div>
                ) : null}
                {selected.contaBancariaResumo ? (
                  <div className="text-sm text-zinc-400">Conta: {selected.contaBancariaResumo}</div>
                ) : null}
                <div className="text-sm text-zinc-400">
                  {fmtParcela(selected.parcelaNumero, selected.parcelaTotal)} • Venc: {selected.vencimento} • Aberto: {formatMoneyBR(selected.valorAberto)}
                </div>
                {selected.kind === "AP" && (
                  <div className="text-sm text-zinc-400">
                    Emissão: {selected.emissao ? formatDateBR(selected.emissao) : tituloMeta?.emissaoDate ? formatDateBR(tituloMeta.emissaoDate) : "-"}
                  </div>
                )}
                {selected.kind === "AP" && (
                  <div className="text-sm text-zinc-400">Motivo: {selected.motivoNome ?? "-"}</div>
                )}
                {selected.kind === "AR" && selected.descricao && (
                  <div className="text-sm text-zinc-400">{selected.descricao}</div>
                )}
                {selected.kind === "AR" && arOsNumero && (
                  <div className="text-sm text-zinc-400">OS vinculada: {arOsNumero}</div>
                )}
              </div>
              <button
                type="button"
                onClick={close}
                className="px-2 py-1 rounded-md border border-zinc-800 text-zinc-200 hover:bg-zinc-900"
              >
                Fechar
              </button>
            </div>

            <div className="mt-4 flex flex-wrap items-center gap-2">
              {selected.kind === "AP" ? (
                <>
                  <button
                    type="button"
                    onClick={() => {
                      setCancelConfirmOpen(false);
                      setTab("APROVAR");
                    }}
                    className={`px-3 py-1.5 rounded-md text-sm border ${
                      tab === "APROVAR" ? "bg-zinc-100 text-zinc-900 border-zinc-100" : "border-zinc-800 text-zinc-200"
                    }`}
                  >
                    Aprovar
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setCancelConfirmOpen(false);
                      setTab("PAGAR");
                    }}
                    className={`px-3 py-1.5 rounded-md text-sm border ${
                      tab === "PAGAR" ? "bg-zinc-100 text-zinc-900 border-zinc-100" : "border-zinc-800 text-zinc-200"
                    }`}
                  >
                    Pagar
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setCancelConfirmOpen(false);
                      setTab("REVISAR_VALOR");
                    }}
                    className={`px-3 py-1.5 rounded-md text-sm border ${
                      tab === "REVISAR_VALOR" ? "bg-zinc-100 text-zinc-900 border-zinc-100" : "border-zinc-800 text-zinc-200"
                    }`}
                  >
                    Revisar valor
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setCancelConfirmOpen(false);
                      setTab("VENCIMENTO");
                    }}
                    className={`px-3 py-1.5 rounded-md text-sm border ${
                      tab === "VENCIMENTO" ? "bg-zinc-100 text-zinc-900 border-zinc-100" : "border-zinc-800 text-zinc-200"
                    }`}
                  >
                    Vencimento
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setCancelConfirmOpen(false);
                      setTab("CANCELAR_PAGAMENTO");
                    }}
                    className={`px-3 py-1.5 rounded-md text-sm border ${
                      tab === "CANCELAR_PAGAMENTO"
                        ? "bg-zinc-100 text-zinc-900 border-zinc-100"
                        : "border-zinc-800 text-zinc-200"
                    }`}
                  >
                    Cancelar pagamento
                  </button>
                </>
              ) : (
                <>
                  <button
                    type="button"
                    onClick={() => {
                      setCancelConfirmOpen(false);
                      setTab("RECEBER");
                    }}
                    className={`px-3 py-1.5 rounded-md text-sm border ${
                      tab === "RECEBER" ? "bg-zinc-100 text-zinc-900 border-zinc-100" : "border-zinc-800 text-zinc-200"
                    }`}
                  >
                    Receber
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setCancelConfirmOpen(false);
                      setTab("VENCIMENTO");
                    }}
                    className={`px-3 py-1.5 rounded-md text-sm border ${
                      tab === "VENCIMENTO" ? "bg-zinc-100 text-zinc-900 border-zinc-100" : "border-zinc-800 text-zinc-200"
                    }`}
                  >
                    Vencimento
                  </button>
                </>
              )}
            </div>

            <div className="mt-4 space-y-3">
              <FormError message={actionErr} />

              {selected.kind === "AP" && (
                <div className="rounded-md border border-zinc-800 bg-zinc-950/40 p-3">
                  <div className="flex items-start justify-between gap-3">
                    <div className="flex-1">
                      <div className="text-sm text-zinc-300">Descrição / Observação</div>
                      <textarea
                        aria-label="Descrição / Observação"
                        value={editDescricao}
                        onChange={(e) => setEditDescricao(e.target.value)}
                        placeholder="Ex: PARCELAMENTO ICMS - SEFAZ/SC (Série 1)"
                        className="w-full min-h-[60px] bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                      />
                      <div className="text-xs text-zinc-500 mt-1">
                        Texto que identifica o título na listagem (aparece na coluna Descrição).
                      </div>
                      <FormError message={descricaoErr} />
                    </div>
                    <button
                      type="button"
                      disabled={descricaoBusy || editDescricao.trim() === (selected.descricao ?? "")}
                      onClick={() => void doUpdateDescricao()}
                      className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
                    >
                      {descricaoBusy ? "Salvando..." : "Salvar descrição"}
                    </button>
                  </div>
                </div>
              )}

              {selected.kind === "AP" && (
                <div className="rounded-md border border-zinc-800 bg-zinc-950/40 p-3">
                  <div className="flex items-start justify-between gap-3">
                    <div className="flex-1">
                      <div className="text-sm text-zinc-300">Data da NF (Emissão)</div>
                      <input
                        aria-label="Data da NF (Emissão)"
                        type="date"
                        value={editEmissaoDate}
                        onChange={(e) => setEditEmissaoDate(e.target.value)}
                        disabled={
                          emissaoBusy ||
                          !tituloMeta ||
                          (tituloMeta.documentoFiscalId !== null && tituloMeta.documentoFiscalId !== "")
                        }
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100 disabled:opacity-60"
                      />
                      <div className="text-xs text-zinc-500 mt-1">Data da nota/serviço, usada para competência.</div>
                      {(tituloMeta?.documentoFiscalId ?? null) !== null && (
                        <div className="text-xs text-zinc-500 mt-1">Importado por XML: emissão é somente leitura.</div>
                      )}
                      {!tituloMeta && (
                        <div className="text-xs text-zinc-500 mt-1">Carregando origem do título...</div>
                      )}
                      <FormError message={emissaoErr} />
                    </div>
                    {tituloMeta && tituloMeta.documentoFiscalId === null && (
                      <button
                        type="button"
                        disabled={emissaoBusy || !editEmissaoDate || editEmissaoDate === (tituloMeta?.emissaoDate ?? selected.emissao ?? "")}
                        onClick={() => void doUpdateEmissaoDate()}
                        className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
                      >
                        {emissaoBusy ? "Salvando..." : "Salvar emissão"}
                      </button>
                    )}
                  </div>
                </div>
              )}

              {tab === "APROVAR" && selected.kind === "AP" && (
                <div className="space-y-3">
                  <div>
                    <div className="text-sm text-zinc-300">Motivo</div>
                    <select
                      aria-label="Motivo"
                      value={motivoId}
                      onChange={(e) => setMotivoId(e.target.value)}
                      className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                    >
                      <option value="">Selecione...</option>
                      {motivos.map((m) => (
                        <option key={m.id} value={m.id}>
                          {m.codigo} - {m.nome}
                        </option>
                      ))}
                    </select>
                  </div>

                  {selectedMotivo?.requires_os && (
                    <div>
                      <div className="text-sm text-zinc-300">OS</div>
                      <input
                        aria-label="OS"
                        value={osId}
                        onChange={(e) => setOsId(e.target.value)}
                        placeholder="Ex: 1234"
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                      />
                    </div>
                  )}

                  {selectedMotivo?.requires_text && (
                    <div>
                      <div className="text-sm text-zinc-300">Motivo (texto)</div>
                      <input
                        aria-label="Motivo texto"
                        value={motivoOutrosText}
                        onChange={(e) => setMotivoOutrosText(e.target.value)}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                      />
                    </div>
                  )}

                  <div className="flex justify-end">
                    <button
                      type="button"
                      disabled={actionBusy}
                      onClick={doAprovar}
                      className="px-3 py-2 rounded-md bg-emerald-500 text-zinc-950 hover:bg-emerald-400 text-sm font-medium disabled:opacity-60"
                    >
                      {actionBusy ? "Aprovando..." : "Confirmar aprovação"}
                    </button>
                  </div>
                </div>
              )}

              {tab === "REVISAR_VALOR" && selected.kind === "AP" && (
                <div className="space-y-4">
                  <div className="rounded-lg border border-amber-500/30 bg-amber-500/5 p-4">
                    <div className="text-sm font-medium text-zinc-100">Confirmar o valor efetivamente devido</div>
                    <p className="mt-1 text-xs leading-5 text-zinc-400">
                      Use quando o salário, imposto ou outra previsão vier diferente. Pagamentos já feitos permanecem
                      intactos; somente a previsão e o saldo em aberto são corrigidos.
                    </p>

                    <div className="mt-4 grid grid-cols-1 gap-2 sm:grid-cols-3">
                      <div className="rounded-md border border-zinc-800 bg-zinc-950/70 p-3">
                        <div className="text-xs text-zinc-500">Valor previsto atual</div>
                        <div className="mt-1 text-sm font-semibold text-zinc-100">{formatMoneyBR(selected.valor)}</div>
                      </div>
                      <div className="rounded-md border border-zinc-800 bg-zinc-950/70 p-3">
                        <div className="text-xs text-zinc-500">Já pago</div>
                        <div className="mt-1 text-sm font-semibold text-emerald-400">{formatMoneyBR(valorPagoParcela)}</div>
                      </div>
                      <div className="rounded-md border border-zinc-800 bg-zinc-950/70 p-3">
                        <div className="text-xs text-zinc-500">Saldo após revisão</div>
                        <div className={`mt-1 text-sm font-semibold ${saldoAposRevisao > 0 ? "text-amber-300" : "text-emerald-400"}`}>
                          {Number.isFinite(saldoAposRevisao) ? formatMoneyBR(saldoAposRevisao) : "Valor invalido"}
                        </div>
                      </div>
                    </div>

                    <div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-2">
                      <label className="block">
                        <span className="text-sm text-zinc-300">Novo valor final</span>
                        <input
                          aria-label="Novo valor final"
                          value={novoValorFinal}
                          onChange={(e) => setNovoValorFinal(e.target.value)}
                          placeholder="0,00"
                          className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100"
                        />
                      </label>
                      <label className="block">
                        <span className="text-sm text-zinc-300">Motivo da revisão</span>
                        <input
                          aria-label="Motivo da revisão"
                          value={motivoRevisao}
                          onChange={(e) => setMotivoRevisao(e.target.value)}
                          placeholder="Ex: valor final da folha confirmado"
                          className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100"
                        />
                      </label>
                    </div>

                    {Number.isFinite(novoValorFinalNumero) && novoValorFinalNumero < valorPagoParcela ? (
                      <div className="mt-3 text-xs text-red-300">
                        O valor final não pode ser menor que o total já pago. Nesse caso, registre o crédito a recuperar
                        separadamente.
                      </div>
                    ) : null}

                    <div className="mt-4 flex justify-end">
                      <button
                        type="button"
                        disabled={actionBusy}
                        onClick={() => void doRevisarValorFinal()}
                        className="rounded-md bg-amber-400 px-3 py-2 text-sm font-semibold text-zinc-950 hover:bg-amber-300 disabled:opacity-60"
                      >
                        {actionBusy ? "Revisando..." : "Confirmar valor final"}
                      </button>
                    </div>
                  </div>

                  <div className="rounded-lg border border-zinc-800 bg-zinc-950/40 p-4">
                    <div className="text-sm font-medium text-zinc-200">Histórico de revisões</div>
                    {revisoesValor.length === 0 ? (
                      <div className="mt-2 text-xs text-zinc-500">Nenhuma revisão registrada nesta parcela.</div>
                    ) : (
                      <div className="mt-3 space-y-2">
                        {revisoesValor.map((revisao) => (
                          <div key={revisao.id} className="rounded-md border border-zinc-800 px-3 py-2">
                            <div className="flex flex-wrap items-center justify-between gap-2 text-sm">
                              <span className="font-medium text-zinc-200">
                                {formatMoneyBR(revisao.valorAnterior)} para {formatMoneyBR(revisao.valorNovo)}
                              </span>
                              <span className="text-xs text-zinc-500">
                                {new Date(revisao.revisadoEm).toLocaleString("pt-BR")}
                              </span>
                            </div>
                            <div className="mt-1 text-xs text-zinc-400">{revisao.motivo}</div>
                            <div className="mt-1 text-xs text-zinc-600">Revisado por {revisao.revisadoPor}</div>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              )}

              {tab === "CANCELAR_PAGAMENTO" && selected.kind === "AP" && (
                <div className="space-y-3">
                  <div className="rounded-md border border-zinc-800 bg-zinc-950/40 p-3 space-y-2">
                    <div className="text-sm font-medium text-zinc-200">Pagamento aplicado na parcela</div>
                    {aplicacoes.length === 0 ? (
                      <div className="text-sm text-zinc-400">
                        Esta parcela ainda nao possui pagamento aplicado. Neste caso, voce pode cancelar o lancamento.
                      </div>
                    ) : (
                      <div className="space-y-2">
                        {aplicacoes.map((a) => (
                          <label
                            key={String(a.pagamento.id)}
                            className="flex items-center gap-3 rounded-md border border-zinc-800 px-3 py-2"
                          >
                            <input
                              type="radio"
                              name="cancel-pagamento-id"
                              checked={cancelPagamentoId === String(a.pagamento.id)}
                              onChange={() => setCancelPagamentoId(String(a.pagamento.id))}
                            />
                            <div className="text-sm text-zinc-200">
                              <span className="font-medium">{formatMoneyBR(Number(a.valor ?? 0))}</span>
                              <span className="text-zinc-500"> • </span>
                              <span>{formatDateBR(String(a.pagamento.data_pagamento ?? ""))}</span>
                              <span className="text-zinc-500"> • </span>
                              <span>{a.pagamento.forma_pagamento}</span>
                            </div>
                          </label>
                        ))}
                      </div>
                    )}
                  </div>

                  <div>
                    <div className="text-sm text-zinc-300">Motivo do cancelamento</div>
                    <textarea
                      aria-label="Motivo do cancelamento"
                      value={cancelMotivo}
                      onChange={(e) => setCancelMotivo(e.target.value)}
                      placeholder="Ex: pagamento registrado em conta errada"
                      className="w-full min-h-[88px] bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                    />
                  </div>

                  <div className="flex justify-end">
                    <button
                      type="button"
                      disabled={actionBusy}
                      onClick={() => {
                        const semPagamentoAplicado = aplicacoes.length === 0;
                        if (!semPagamentoAplicado && !cancelPagamentoId) {
                          setActionErr("Selecione o pagamento que deseja cancelar.");
                          return;
                        }
                        if (cancelMotivo.trim().length < 5) {
                          setActionErr("Informe o motivo do cancelamento (minimo 5 caracteres).");
                          return;
                        }
                        setActionErr(null);
                        setCancelConfirmOpen(true);
                      }}
                      className="px-3 py-2 rounded-md bg-red-500 text-zinc-950 hover:bg-red-400 text-sm font-medium disabled:opacity-60"
                    >
                      {aplicacoes.length > 0 ? "Solicitar cancelamento" : "Solicitar cancelamento do lancamento"}
                    </button>
                  </div>
                </div>
              )}

              {tab === "VENCIMENTO" && (selected.kind === "AP" || selected.kind === "AR") && (
                <div className="space-y-3">
                  <div className="rounded-md border border-zinc-800 bg-zinc-950/40 p-3">
                    <div className="text-sm text-zinc-300 mb-2">Alterar vencimento da parcela</div>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                      <div>
                        <div className="text-xs text-zinc-500">Vencimento atual</div>
                        <div className="text-sm text-zinc-200 mt-1">{formatDateBR(selected.vencimento)}</div>
                      </div>
                      <div>
                        <div className="text-sm text-zinc-300">Novo vencimento</div>
                        <input
                          aria-label="Novo vencimento"
                          type="date"
                          value={editVencimentoDate}
                          onChange={(e) => setEditVencimentoDate(e.target.value)}
                          className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                        />
                      </div>
                    </div>
                    <div className="text-xs text-zinc-500 mt-2">
                      Altera somente a data de vencimento desta parcela ({selected.kind}).
                    </div>
                  </div>
                  <div className="flex justify-end">
                    <button
                      type="button"
                      disabled={actionBusy || !editVencimentoDate || editVencimentoDate === selected.vencimento}
                      onClick={() => void doUpdateVencimentoDate()}
                      className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
                    >
                      {actionBusy ? "Salvando..." : "Salvar vencimento"}
                    </button>
                  </div>
                </div>
              )}

              {(tab === "PAGAR" || tab === "RECEBER") && (
                <div className="space-y-3">
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    <div>
                      <div className="text-sm text-zinc-300">Conta bancária</div>
                      <select
                        aria-label="Conta bancária"
                        value={contaBancariaId}
                        onChange={(e) => setContaBancariaId(e.target.value)}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                      >
                        <option value="">Selecione...</option>
                        {contas.map((c) => (
                          <option key={c.id} value={c.id}>
                            {accountDisplayLabel(c.codigo, c.nome, selected.empresaNome)}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div>
                      <div className="text-sm text-zinc-300">Data</div>
                      <input
                        aria-label="Data"
                        type="date"
                        value={dataPagamento}
                        onChange={(e) => setDataPagamento(e.target.value)}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                      />
                    </div>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    <div>
                      <div className="text-sm text-zinc-300">Forma</div>
                      <select
                        aria-label="Forma"
                        value={formaPagamento}
                        onChange={(e) => setFormaPagamento(e.target.value)}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                      >
                        <option value="PIX">PIX</option>
                        <option value="TRANSFERENCIA">TRANSFERÊNCIA</option>
                        <option value="BOLETO">BOLETO</option>
                        <option value="DINHEIRO">DINHEIRO</option>
                        <option value="CARTAO">CARTÃO</option>
                        <option value="OUTROS">OUTROS</option>
                      </select>
                    </div>

                    <div>
                      <div className="text-sm text-zinc-300">Valor principal</div>
                      <input
                        aria-label="Valor"
                        value={valorMov}
                        onChange={(e) => setValorMov(e.target.value)}
                        placeholder={formatMoneyBR(selected.valorAberto)}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                      />
                      <div className="text-xs text-zinc-500 mt-1">Dica: aceita &quot;1234,56&quot; ou &quot;R$ 1.234,56&quot;</div>
                    </div>
                  </div>

                  {tab === "PAGAR" && selected.kind === "AP" && pagamentoPrincipalMenorQueAberto && movTotals ? (
                    <div className="rounded-lg border border-amber-500/30 bg-amber-500/5 p-3">
                      <div className="text-sm font-medium text-zinc-100">
                        Como tratar a diferença de {formatMoneyBR((movTotals.openCents - movTotals.principalCents) / 100)}?
                      </div>
                      <div className="mt-3 grid grid-cols-1 gap-2 md:grid-cols-2">
                        <label
                          className={`cursor-pointer rounded-md border p-3 ${
                            !pagamentoComoValorFinal
                              ? "border-sky-500/70 bg-sky-500/10"
                              : "border-zinc-800 bg-zinc-950/60"
                          }`}
                        >
                          <div className="flex items-start gap-2">
                            <input
                              type="radio"
                              name="tratamento-pagamento-menor"
                              checked={!pagamentoComoValorFinal}
                              onChange={() => setPagamentoComoValorFinal(false)}
                              className="mt-1"
                            />
                            <div>
                              <div className="text-sm font-medium text-zinc-200">Pagamento parcial</div>
                              <div className="mt-1 text-xs text-zinc-500">Mantém a diferença em aberto para pagar depois.</div>
                            </div>
                          </div>
                        </label>
                        <label
                          className={`cursor-pointer rounded-md border p-3 ${
                            pagamentoComoValorFinal
                              ? "border-emerald-500/70 bg-emerald-500/10"
                              : "border-zinc-800 bg-zinc-950/60"
                          }`}
                        >
                          <div className="flex items-start gap-2">
                            <input
                              type="radio"
                              name="tratamento-pagamento-menor"
                              checked={pagamentoComoValorFinal}
                              onChange={() => setPagamentoComoValorFinal(true)}
                              className="mt-1"
                            />
                            <div>
                              <div className="text-sm font-medium text-zinc-200">Valor final confirmado</div>
                              <div className="mt-1 text-xs text-zinc-500">
                                Corrige a previsão e encerra a diferença sem gerar nova dívida.
                              </div>
                            </div>
                          </div>
                        </label>
                      </div>

                      {pagamentoComoValorFinal ? (
                        <label className="mt-3 block">
                          <span className="text-sm text-zinc-300">Motivo da revisão</span>
                          <input
                            aria-label="Motivo do valor final"
                            value={motivoRevisao}
                            onChange={(e) => setMotivoRevisao(e.target.value)}
                            placeholder="Ex: valor final da folha confirmado"
                            className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100"
                          />
                        </label>
                      ) : null}
                    </div>
                  ) : null}

                  <div className="border border-zinc-800 rounded-md p-3 bg-zinc-950/40 space-y-3">
                    <div>
                      <div className="text-sm font-medium text-zinc-200">Ajustes do pagamento</div>
                      <div className="text-xs text-zinc-500">Juros, multa e desconto afetam o total pago agora.</div>
                    </div>

                    <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                      <div>
                        <div className="text-sm text-zinc-300">Juros (R$)</div>
                        <input
                          aria-label="Juros"
                          value={valorJuros}
                          onChange={(e) => setValorJuros(e.target.value)}
                          placeholder="0,00"
                          className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                        />
                      </div>

                      <div>
                        <div className="text-sm text-zinc-300">Multa (R$)</div>
                        <input
                          aria-label="Multa"
                          value={valorMulta}
                          onChange={(e) => setValorMulta(e.target.value)}
                          placeholder="0,00"
                          className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                        />
                      </div>

                      <div>
                        <div className="text-sm text-zinc-300">Desconto (R$)</div>
                        <input
                          aria-label="Desconto"
                          value={valorDesconto}
                          onChange={(e) => setValorDesconto(e.target.value)}
                          placeholder="0,00"
                          className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                        />
                      </div>
                    </div>

                    <div className="flex items-center justify-between">
                      <div className="text-sm text-zinc-300">Total a pagar agora</div>
                      <div className="text-sm font-semibold text-zinc-100">
                        R$ {movTotals && Number.isFinite(movTotals.totalCents) ? (movTotals.totalCents / 100).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : "0,00"}
                      </div>
                    </div>
                  </div>

                  <div>
                    <div className="text-sm text-zinc-300">Observações</div>
                    <input
                      aria-label="Observações"
                      value={observacoes}
                      onChange={(e) => setObservacoes(e.target.value)}
                      className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                    />
                  </div>

                  {tab === "RECEBER" && selected.kind === "AR" && (
                    <div className="border border-zinc-800 rounded-md p-3 bg-zinc-950/40 space-y-3">
                      <label className="flex items-center gap-2 text-sm text-zinc-300">
                        <input
                          type="checkbox"
                          checked={splitRecebimento}
                          onChange={(e) => {
                            const checked = e.target.checked;
                            setSplitRecebimento(checked);
                            if (checked && !splitVencimentoDate) {
                              setSplitVencimentoDate(selected.vencimento);
                            }
                          }}
                        />
                        Desdobrar saldo remanescente em nova parcela
                      </label>
                      {splitRecebimento && (
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                          <div>
                            <div className="text-sm text-zinc-300">Vencimento da nova parcela</div>
                            <input
                              aria-label="Vencimento da nova parcela"
                              type="date"
                              value={splitVencimentoDate}
                              onChange={(e) => setSplitVencimentoDate(e.target.value)}
                              className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                            />
                          </div>
                          <div className="text-xs text-zinc-500 flex items-end">
                            O saldo restante ficara pendente em uma nova parcela.
                          </div>
                        </div>
                      )}
                    </div>
                  )}

                  <div className="flex justify-end">
                    {tab === "PAGAR" && (
                      <button
                        type="button"
                        disabled={actionBusy}
                        onClick={() => doMov("PAGAR")}
                        className="px-3 py-2 rounded-md bg-red-500 text-zinc-950 hover:bg-red-400 text-sm font-medium disabled:opacity-60"
                      >
                        {actionBusy ? "Pagando..." : "Confirmar pagamento"}
                      </button>
                    )}
                    {tab === "RECEBER" && (
                      <button
                        type="button"
                        disabled={actionBusy}
                        onClick={() => doMov("RECEBER")}
                        className="px-3 py-2 rounded-md bg-emerald-500 text-zinc-950 hover:bg-emerald-400 text-sm font-medium disabled:opacity-60"
                      >
                        {actionBusy ? "Recebendo..." : "Confirmar recebimento"}
                      </button>
                    )}
                  </div>
                </div>
              )}

              {!!aplicacoes.length && (
                <div className="border-t border-zinc-800 pt-3">
                  <div className="text-sm text-zinc-300 mb-2">Movimentos desta parcela</div>
                  <div className="space-y-2">
                    {aplicacoes.map((a) => {
                      const conta = contas.find((c) => c.id === a.pagamento.conta_bancaria_id) ?? null;
                      return (
                        <div
                          key={`${a.pagamento.id}:${a.pagamento.data_pagamento}:${a.valor}`}
                          className="text-sm text-zinc-300"
                        >
                          <span className="text-zinc-100 font-medium">{formatMoneyBR(Number(a.valor ?? 0))}</span>
                          <span className="text-zinc-500"> • </span>
                          <span>{a.pagamento.data_pagamento}</span>
                          <span className="text-zinc-500"> • </span>
                          <span>{a.pagamento.forma_pagamento}</span>
                          <span className="text-zinc-500"> • </span>
                           <span>
                             {conta
                               ? accountDisplayLabel(conta.codigo, conta.nome, selected.empresaNome)
                               : a.pagamento.conta_bancaria_id}
                           </span>
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              {cancelConfirmOpen && tab === "CANCELAR_PAGAMENTO" && selected.kind === "AP" && (
                <div className="absolute inset-0 z-20 flex items-center justify-center rounded-lg bg-black/70 p-4">
                  <div className="w-full max-w-md rounded-md border border-zinc-800 bg-zinc-950 p-4 space-y-3">
                    <div className="text-base font-semibold text-zinc-100">Confirmar cancelamento</div>
                    <div className="text-sm text-zinc-300">
                      {aplicacoes.length > 0
                        ? "Esse processo estorna o pagamento selecionado e reabre o saldo da parcela."
                        : "Esse processo cancela o lancamento e remove o saldo em aberto do titulo."}
                    </div>

                    {aplicacoes.length > 0 && cancelAplicacaoSelecionada && (
                      <div className="rounded-md border border-zinc-800 bg-zinc-950/40 p-3 text-sm text-zinc-300 space-y-1">
                        <div>
                          Valor:{" "}
                          <span className="font-medium text-zinc-100">
                            {formatMoneyBR(Number(cancelAplicacaoSelecionada.valor ?? 0))}
                          </span>
                        </div>
                        <div>Data: {formatDateBR(String(cancelAplicacaoSelecionada.pagamento.data_pagamento ?? ""))}</div>
                        <div>Forma: {cancelAplicacaoSelecionada.pagamento.forma_pagamento}</div>
                      </div>
                    )}
                    {aplicacoes.length === 0 && (
                      <div className="rounded-md border border-zinc-800 bg-zinc-950/40 p-3 text-sm text-zinc-300 space-y-1">
                        <div>
                          Titulo: <span className="font-medium text-zinc-100">{selected.tituloId}</span>
                        </div>
                        <div>Fornecedor: {selected.pessoaNome}</div>
                        <div>Parcela: {fmtParcela(selected.parcelaNumero, selected.parcelaTotal)}</div>
                      </div>
                    )}

                    <div className="rounded-md border border-zinc-800 bg-zinc-950/40 p-3 text-sm text-zinc-300">
                      <div className="text-xs uppercase tracking-wide text-zinc-500 mb-1">Motivo</div>
                      <div className="whitespace-pre-wrap break-words">{cancelMotivo.trim()}</div>
                    </div>

                    <div className="flex justify-end gap-2">
                      <button
                        type="button"
                        disabled={actionBusy}
                        onClick={() => setCancelConfirmOpen(false)}
                        className="px-3 py-2 rounded-md border border-zinc-800 text-zinc-200 hover:bg-zinc-900 text-sm disabled:opacity-60"
                      >
                        Voltar
                      </button>
                      <button
                        type="button"
                        disabled={actionBusy}
                        onClick={() => {
                          if (aplicacoes.length > 0) {
                            void doCancelarPagamento();
                            return;
                          }
                          void doCancelarTitulo();
                        }}
                        className="px-3 py-2 rounded-md bg-red-500 text-zinc-950 hover:bg-red-400 text-sm font-medium disabled:opacity-60"
                      >
                        {actionBusy ? "Cancelando..." : "Confirmar cancelamento"}
                      </button>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {createOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/60" onClick={closeCreate} />
          <div className="relative w-full max-w-2xl rounded-lg border border-zinc-800 bg-zinc-950 p-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <div className="text-sm text-zinc-400">{createKind === "AP" ? "Conta a pagar" : "Conta a receber"}</div>
                <div className="text-lg font-semibold text-zinc-100">
                  {createKind === "AP" ? "Novo AP (manual)" : "Novo AR (manual)"}
                </div>
                <div className="text-sm text-zinc-400">
                  {createKind === "AP"
                    ? "Para energia, água, aluguel, etc (sem XML)."
                    : "Para recebimentos sem nota fiscal emitida (ex: entrada lançada manualmente)."}
                </div>
              </div>
              <button
                type="button"
                onClick={closeCreate}
                className="px-2 py-1 rounded-md border border-zinc-800 text-zinc-200 hover:bg-zinc-900"
              >
                Fechar
              </button>
            </div>

            <div className="mt-4 space-y-3">
              <FormError message={createErr} />

              <div>
                <div className="text-sm text-zinc-300">Empresa</div>
                <select
                  aria-label={createKind === "AP" ? "Empresa do novo AP" : "Empresa do novo AR"}
                  value={newEmpresaId}
                  onChange={(e) => setNewEmpresaId(e.target.value)}
                  className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                >
                  {empresaOptions
                    .filter((empresa) => selectedEmpresaIds.includes(empresa.id))
                    .map((empresa) => (
                      <option key={empresa.id} value={empresa.id}>
                        {empresa.label}
                      </option>
                    ))}
                </select>
              </div>

              {createKind === "AP" ? (
                <div>
                  <div className="text-sm text-zinc-300">Fornecedor (opcional)</div>
                  <select
                    aria-label="Fornecedor"
                    value={newFornecedorId}
                    onChange={(e) => setNewFornecedorId(e.target.value)}
                    className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                  >
                    <option value="">Sem fornecedor</option>
                    {fornecedores.map((f) => (
                      <option key={f.id} value={String(f.id)}>
                        {f.nome}
                      </option>
                    ))}
                  </select>
                </div>
              ) : (
                <div>
                  <div className="text-sm text-zinc-300">Cliente</div>
                  <select
                    aria-label="Cliente"
                    value={newClienteId}
                    onChange={(e) => setNewClienteId(e.target.value)}
                    className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                  >
                    <option value="">Selecione um cliente</option>
                    {clientes.map((c) => (
                      <option key={c.id} value={String(c.id)}>
                        {c.nome}
                      </option>
                    ))}
                  </select>
                </div>
              )}

              <div>
                <div className="text-sm text-zinc-300">Descrição</div>
                <input
                  aria-label="Descrição"
                  value={newDescricao}
                  onChange={(e) => setNewDescricao(e.target.value)}
                  placeholder={createKind === "AP" ? "Ex: Energia - ENEL" : "Ex: Recebimento Uniplast - sem NF"}
                  className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                />
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div>
                  <div className="text-sm text-zinc-300">{createKind === "AP" ? "Data da NF (Emissão)" : "Emissão"}</div>
                  <input
                    aria-label={createKind === "AP" ? "Data da NF (Emissão)" : "Emissão"}
                    type="date"
                    value={newEmissaoDate}
                    onChange={(e) => setNewEmissaoDate(e.target.value)}
                    className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                  />
                  <div className="text-xs text-zinc-500 mt-1">Data da nota/serviço, usada para competência.</div>
                </div>
                <div>
                  <div className="text-sm text-zinc-300">Vencimento</div>
                  <input
                    aria-label="Vencimento"
                    type="date"
                    value={newVencimento}
                    onChange={(e) => setNewVencimento(e.target.value)}
                    className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                  />
                </div>
              </div>

              {createKind === "AP" ? (
                <>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    <div>
                      <div className="text-sm text-zinc-300">Valor por parcela</div>
                      <input
                        aria-label="Valor"
                        value={newValor}
                        onChange={(e) => setNewValor(e.target.value)}
                        placeholder='Ex: 450,00'
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                      />
                    </div>
                    <div>
                      <div className="text-sm text-zinc-300">Quantidade de parcelas</div>
                      <input
                        aria-label="Quantidade de parcelas"
                        type="number"
                        min={1}
                        max={120}
                        value={String(newQuantidadeParcelas)}
                        onChange={(e) => {
                          const quantidade = Number(e.target.value);
                          setNewQuantidadeParcelas(quantidade);
                          if (quantidade > 1) setNewRecorrente(false);
                        }}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                      />
                    </div>
                  </div>

                  {newQuantidadeParcelas > 1 && Number.isFinite(parseMoneyBR(newValor)) && parseMoneyBR(newValor) > 0 && (
                    <div className="rounded-md border border-zinc-800 bg-zinc-900/40 px-3 py-2 text-xs text-zinc-300">
                      Total da dívida: {formatMoneyBR(parseMoneyBR(newValor) * newQuantidadeParcelas)}. Os vencimentos serão mensais.
                    </div>
                  )}

                  <div>
                    <div className="text-sm text-zinc-300">Motivo (opcional)</div>
                    <select
                      aria-label="Motivo"
                      value={newMotivoId}
                      onChange={(e) => setNewMotivoId(e.target.value)}
                      className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                    >
                      <option value="">Sem motivo</option>
                      {motivos.map((m) => (
                        <option key={m.id} value={m.id}>
                          {m.codigo} - {m.nome}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div className="flex items-center gap-2">
                    <input
                      id="ap-recorrente"
                      type="checkbox"
                      disabled={newQuantidadeParcelas > 1}
                      checked={newRecorrente}
                      onChange={(e) => setNewRecorrente(e.target.checked)}
                    />
                    <label htmlFor="ap-recorrente" className="text-sm text-zinc-200">
                      É recorrente (provisionar próximos meses)
                    </label>
                  </div>

                  {newRecorrente && (
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                      <div>
                        <div className="text-sm text-zinc-300">Provisionar quantos meses</div>
                        <input
                          aria-label="Meses"
                          type="number"
                          min={0}
                          max={60}
                          value={String(newProvisionarMeses)}
                          onChange={(e) => setNewProvisionarMeses(Number(e.target.value))}
                          className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                        />
                        <div className="text-xs text-zinc-500 mt-1">Dica: ele copia o valor do mês anterior por padrão.</div>
                      </div>
                    </div>
                  )}
                </>
              ) : (
                <>
                  <div>
                    <div className="text-sm text-zinc-300">Valor</div>
                    <input
                      aria-label="Valor"
                      value={newValor}
                      onChange={(e) => setNewValor(e.target.value)}
                      placeholder='Ex: 450,00'
                      className="w-full bg-zinc-950 border border-zinc-800 rounded-md px-3 py-2 text-sm text-zinc-100"
                    />
                  </div>

                  <OsVinculoField
                    tenantId={te.tenantId ?? ""}
                    empresaId={newEmpresaId}
                    value={newOsSelection}
                    onChange={setNewOsSelection}
                    helperText="Opcional. Vincula este recebimento manual a uma OS existente."
                  />
                </>
              )}

              <div className="flex justify-end">
                <button
                  type="button"
                  disabled={createBusy}
                  onClick={() => void (createKind === "AP" ? doCreateAp() : doCreateAr())}
                  className="px-3 py-2 rounded-md bg-emerald-500 text-zinc-950 hover:bg-emerald-400 text-sm font-medium disabled:opacity-60"
                >
                  {createBusy ? "Salvando..." : "Criar"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default function ContasPagarReceberPage() {
  return (
    <Suspense fallback={<div className="text-sm text-zinc-400">Carregando financeiro...</div>}>
      <ContasPagarReceberContent />
    </Suspense>
  );
}
