"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { formatMoneyBR } from "@/lib/decimal";
import { fetchOsSelectionById } from "@/lib/os-vinculo";
import PeriodoMesAnoFilter, { buildPeriodoMesAnoRange } from "@/app/faturamento/components/PeriodoMesAnoFilter";
import {
  buildEmpresaDisplayById,
  buildEmpresaDisplayOptions,
  fetchTenantEmpresas,
  mergeEmpresaInfos,
} from "@/app/faturamento/components/empresaDisplay";
import EmpresaScopeFilter from "@/app/faturamento/components/EmpresaScopeFilter";
import {
  normalizeEmpresaScopeParam,
  resolveScopeEmpresaIds,
  runAcrossEmpresas,
  type EmpresaScope,
} from "@/app/faturamento/components/empresaScope";
import NfeImportModal from "./NfeImportModal";

type DocumentoFiscalRow = {
  id: string;
  operacao: "ENTRADA" | "SAIDA" | string;
  emissao_date: string | null;
  modelo: string | null;
  serie: string | null;
  numero: string | null;
  chave_acesso: string;
  empresa_id: string | null;
  cliente_id: number | null;
  fornecedor_id: number | null;
  os_id_import: number | null;
  valor_total: number | string | null;
  nfe_status?: string | null;
  created_at: string;
};

type TituloFinanceiroRow = {
  id: string;
  documento_fiscal_id: string;
  tipo: string | null;
  status: string | null;
  valor_total: number | string | null;
  valor_aberto: number | string | null;
};

type ParcelaFinanceiraRow = {
  id: string;
  titulo_id: string;
  vencimento_date: string | null;
  valor: number | string | null;
  valor_aberto: number | string | null;
};

type PagamentoStatus = "PAGO" | "A_PAGAR" | "ATRASADO";
type PagamentoFiltro = "TODOS" | "PAGOS" | "A_PAGAR" | "ATRASADOS";

type PagamentoMeta = {
  status: PagamentoStatus;
  pago: number;
  aPagar: number;
  atrasado: number;
};

type ClienteRow = { id: number; nome: string };
type FornecedorRow = { id: number; nome: string | null };

const PAGE_SIZE = 50;
const PAYMENT_EPSILON = 0.009;

function n(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

function formatDateBR(iso?: string | null): string {
  if (!iso) return "";
  const d = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleDateString("pt-BR");
}

function shortKey(key: string): string {
  const k = String(key || "");
  if (k.length <= 12) return k;
  return `${k.slice(0, 4)}...${k.slice(-6)}`;
}

function normalizePagamentoFiltro(value: string | null): PagamentoFiltro {
  const normalized = String(value ?? "")
    .trim()
    .toUpperCase()
    .replace(/-/g, "_");

  switch (normalized) {
    case "PAGOS":
    case "PAGO":
      return "PAGOS";
    case "A_PAGAR":
    case "APAGAR":
    case "EM_ABERTO":
      return "A_PAGAR";
    case "ATRASADOS":
    case "ATRASADO":
      return "ATRASADOS";
    default:
      return "TODOS";
  }
}

function matchesPagamentoFiltro(status: PagamentoStatus, filtro: PagamentoFiltro): boolean {
  if (filtro === "PAGOS") return status === "PAGO";
  if (filtro === "A_PAGAR") return status === "A_PAGAR";
  if (filtro === "ATRASADOS") return status === "ATRASADO";
  return true;
}

function todayIsoDate(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function isPastDue(vencimentoDate?: string | null): boolean {
  const normalized = String(vencimentoDate ?? "").slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(normalized)) return false;
  return normalized < todayIsoDate();
}

function pagamentoStatusLabel(status: PagamentoStatus): string {
  if (status === "PAGO") return "Pago";
  if (status === "ATRASADO") return "Atrasado";
  return "A pagar";
}

function pagamentoStatusBadgeClass(status: PagamentoStatus): string {
  if (status === "PAGO") {
    return "border-emerald-500/30 bg-emerald-500/10 text-emerald-300";
  }
  if (status === "ATRASADO") {
    return "border-rose-500/30 bg-rose-500/10 text-rose-300";
  }
  return "border-amber-500/30 bg-amber-500/10 text-amber-200";
}

function pagamentoRowClass(status: PagamentoStatus): string {
  if (status === "PAGO") return "bg-emerald-950/10 hover:bg-emerald-950/20";
  if (status === "ATRASADO") return "bg-rose-950/10 hover:bg-rose-950/20";
  return "bg-amber-950/10 hover:bg-amber-950/20";
}

function buildPagamentoFallback(row: DocumentoFiscalRow): PagamentoMeta {
  const total = Math.max(0, n(row.valor_total));
  if (total <= PAYMENT_EPSILON) {
    return { status: "PAGO", pago: 0, aPagar: 0, atrasado: 0 };
  }
  return { status: "A_PAGAR", pago: 0, aPagar: total, atrasado: 0 };
}

function computePagamentoMeta(
  row: DocumentoFiscalRow,
  titulos: TituloFinanceiroRow[],
  parcelasByTituloId: Record<string, ParcelaFinanceiraRow[]>
): PagamentoMeta {
  if (!titulos.length) return buildPagamentoFallback(row);

  const totalTitulos = titulos.reduce((sum, titulo) => sum + n(titulo.valor_total), 0);
  const totalAberto = titulos.reduce((sum, titulo) => sum + n(titulo.valor_aberto), 0);
  const parcelasEmAberto = titulos.flatMap((titulo) =>
    (parcelasByTituloId[String(titulo.id)] ?? []).filter((parcela) => n(parcela.valor_aberto) > PAYMENT_EPSILON)
  );

  const pago = Math.max(0, totalTitulos - totalAberto);
  const aPagar = Math.max(0, totalAberto);
  const valorAtrasado = parcelasEmAberto.reduce(
    (sum, parcela) => (isPastDue(parcela.vencimento_date) ? sum + Math.max(0, n(parcela.valor_aberto)) : sum),
    0
  );
  const status: PagamentoStatus =
    aPagar <= PAYMENT_EPSILON ? "PAGO" : valorAtrasado > PAYMENT_EPSILON ? "ATRASADO" : "A_PAGAR";

  return { status, pago, aPagar, atrasado: Math.max(0, valorAtrasado) };
}

function pagamentoResumoLabel(filtro: PagamentoFiltro): string {
  if (filtro === "PAGOS") return "Total pago";
  if (filtro === "A_PAGAR") return "Total a receber";
  if (filtro === "ATRASADOS") return "Total em atraso";
  return "Valor total filtrado";
}

function pagamentoResumoValor(
  filtro: PagamentoFiltro,
  totals: { valor: number; pago: number; aPagar: number; atrasado: number }
): number {
  if (filtro === "PAGOS") return totals.pago;
  if (filtro === "A_PAGAR") return totals.aPagar;
  if (filtro === "ATRASADOS") return totals.atrasado;
  return totals.valor;
}

function compareDocsDesc(a: DocumentoFiscalRow, b: DocumentoFiscalRow): number {
  const dateA = a.emissao_date ?? "";
  const dateB = b.emissao_date ?? "";
  if (dateA !== dateB) return dateB.localeCompare(dateA);
  return String(b.created_at ?? "").localeCompare(String(a.created_at ?? ""));
}

export default function NfeList() {
  const te = useTenantEmpresa();
  const router = useRouter();
  const searchParams = useSearchParams();

  const empresaRole = useMemo(() => {
    const role = te.empresa?.papel ?? te.empresas.find((e) => e.id === te.empresaId)?.papel ?? null;
    return typeof role === "string" ? role.trim().toUpperCase() : "";
  }, [te.empresa?.papel, te.empresaId, te.empresas]);
  const isFinanceiroEmpresaRole = empresaRole === "FINANCEIRO" || empresaRole === "FATURAMENTO";

  const canFinanceiro = useMemo(() => {
    if (isFinanceiroEmpresaRole) return true;
    const values = [
      te.has("financeiro.read"),
      te.has("financeiro.write"),
      te.has("faturamento.read"),
      te.has("faturamento.write"),
    ];
    if (values.some((value) => value === undefined)) return undefined;
    return values.some(Boolean);
  }, [isFinanceiroEmpresaRole, te]);

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  const [docs, setDocs] = useState<DocumentoFiscalRow[]>([]);
  const [clientesById, setClientesById] = useState<Record<string, string>>({});
  const [fornecedoresById, setFornecedoresById] = useState<Record<string, string>>({});
  const [osNumeroById, setOsNumeroById] = useState<Record<string, string>>({});
  const [pagamentosByDocId, setPagamentosByDocId] = useState<Record<string, PagamentoMeta>>({});
  const [empresaCatalog, setEmpresaCatalog] = useState(te.empresas);

  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [offsetsByEmpresa, setOffsetsByEmpresa] = useState<Record<string, number>>({});
  const [moreByEmpresa, setMoreByEmpresa] = useState<Record<string, boolean>>({});
  const hasMore = Object.values(moreByEmpresa).some(Boolean);

  const [search, setSearch] = useState("");
  const [importOpen, setImportOpen] = useState(false);

  const canImportXmlFaturamento = useMemo(() => {
    if (canFinanceiro === undefined) return undefined;
    return canFinanceiro === true;
  }, [canFinanceiro]);
  const empresasById = useMemo(() => buildEmpresaDisplayById(empresaCatalog), [empresaCatalog]);
  // Catalogo de exibicao pode incluir empresas do tenant so para fins de rotulo;
  // o escopo de busca fica restrito as empresas que o usuario de fato acessa (te.empresas),
  // que e o mesmo conjunto validado pela RPC set_current_empresa.
  const allowedEmpresaIds = useMemo(() => te.empresas.map((e) => e.id), [te.empresas]);
  const empresaScopeOptions = useMemo(() => {
    const options = buildEmpresaDisplayOptions(empresaCatalog);
    return options.filter((option) => allowedEmpresaIds.includes(option.id));
  }, [empresaCatalog, allowedEmpresaIds]);
  const empresaScope = useMemo(
    () => normalizeEmpresaScopeParam(searchParams.get("empresa"), allowedEmpresaIds),
    [searchParams, allowedEmpresaIds]
  );
  const setEmpresaScope = (scope: EmpresaScope) => {
    const params = new URLSearchParams(searchParams.toString());
    if (scope === "ALL") {
      params.delete("empresa");
    } else {
      params.set("empresa", scope);
    }
    const nextUrl = params.toString() ? `/faturamento/nfe?${params.toString()}` : "/faturamento/nfe";
    router.replace(nextUrl, { scroll: false });
  };
  const ready =
    typeof te.sessionUserId === "string" &&
    Boolean(te.tenantId) &&
    (Boolean(te.empresaId) || te.empresas.length === 1) &&
    canFinanceiro === true;

  useEffect(() => {
    setEmpresaCatalog((prev) => mergeEmpresaInfos(prev, te.empresas));
  }, [te.empresas]);

  useEffect(() => {
    if (!ready || !te.tenantId) return;

    let cancelled = false;

    const loadEmpresas = async () => {
      try {
        const empresas = await fetchTenantEmpresas(supabaseBrowser(), te.tenantId!);
        if (!cancelled) setEmpresaCatalog((prev) => mergeEmpresaInfos(prev, empresas));
      } catch {
        // keep current catalog if tenant-wide lookup is not available
      }
    };

    void loadEmpresas();

    return () => {
      cancelled = true;
    };
  }, [ready, te.tenantId]);

  useEffect(() => {
    const wantsImport = searchParams.get("import");
    if (!wantsImport) return;
    if (wantsImport !== "1" && wantsImport.toLowerCase() !== "true") return;
    if (canImportXmlFaturamento !== true) return;
    setImportOpen(true);
  }, [canImportXmlFaturamento, searchParams]);

  const pagamentoFiltro = normalizePagamentoFiltro(searchParams.get("pagamento"));
  const periodo = useMemo(() => buildPeriodoMesAnoRange(searchParams), [searchParams]);

  const setPagamentoFiltro = (filtro: PagamentoFiltro) => {
    const params = new URLSearchParams(searchParams.toString());
    if (filtro === "TODOS") {
      params.delete("pagamento");
    } else {
      params.set("pagamento", filtro.toLowerCase());
    }
    const nextUrl = params.toString() ? `/faturamento/nfe?${params.toString()}` : "/faturamento/nfe";
    router.replace(nextUrl, { scroll: false });
  };

  const resolveClientes = async (rows: DocumentoFiscalRow[]) => {
    if (!te.tenantId) return;
    const ids = Array.from(
      new Set(
        rows
          .map((r) => (typeof r.cliente_id === "number" ? r.cliente_id : null))
          .filter((v): v is number => typeof v === "number")
      )
    );
    const missing = ids.filter((id) => !(String(id) in clientesById));
    if (!missing.length) return;

    const supabase = supabaseBrowser();
    const tenantId = te.tenantId;
    const empresaId = te.empresaId ?? te.empresas[0]?.id ?? "";

    const q = applyTenantEmpresa(
      supabase.from("clientes").select("id,nome").in("id", missing),
      tenantId,
      empresaId
    );

    const { data, error: cErr } = await q.returns<ClienteRow[]>();
    if (cErr) throw cErr;

    setClientesById((prev) => {
      const next = { ...prev };
      for (const c of data ?? []) {
        if (typeof c?.id === "number") next[String(c.id)] = String(c.nome ?? "");
      }
      return next;
    });
  };

  const resolveFornecedores = async (rows: DocumentoFiscalRow[]) => {
    if (!te.tenantId) return;
    const ids = Array.from(
      new Set(
        rows
          .map((r) => (typeof r.fornecedor_id === "number" ? r.fornecedor_id : null))
          .filter((v): v is number => typeof v === "number")
      )
    );
    const missing = ids.filter((id) => !(String(id) in fornecedoresById));
    if (!missing.length) return;

    const supabase = supabaseBrowser();
    const tenantId = te.tenantId;
    const empresaId = te.empresaId ?? te.empresas[0]?.id ?? "";

    const { data, error: fErr } = await applyTenantEmpresa(
      supabase.from("fornecedores").select("id,nome").in("id", missing),
      tenantId,
      empresaId
    ).returns<FornecedorRow[]>();
    if (fErr) throw fErr;

    setFornecedoresById((prev) => {
      const next = { ...prev };
      for (const f of data ?? []) {
        if (typeof f?.id === "number") next[String(f.id)] = String(f.nome ?? "");
      }
      return next;
    });
  };

  // f.titulo e RLS-restrito a `empresa_id = current_empresa_id()`, por isso e buscado
  // dentro do loop por empresa (fetchDocsAndTitulosForEmpresa). f.titulo_parcela nao tem
  // essa restricao (so tenant), entao e combinado aqui apos o merge das empresas.
  const buildPagamentosFromTitulos = async (
    rows: DocumentoFiscalRow[],
    titulos: TituloFinanceiroRow[]
  ): Promise<Record<string, PagamentoMeta>> => {
    if (!te.tenantId || !rows.length) return {};

    const supabase = supabaseBrowser();
    const tenantId = te.tenantId;
    const empresaId = te.empresaId ?? te.empresas[0]?.id ?? "";

    const titulosRelevantes = titulos.filter((titulo) => {
      const tipo = String(titulo.tipo ?? "").trim().toUpperCase();
      const status = String(titulo.status ?? "").trim().toUpperCase();
      return tipo === "AR" && status !== "CANCELADO";
    });

    const tituloIds = titulosRelevantes.map((titulo) => String(titulo.id)).filter(Boolean);
    const { data: parcelaData, error: parcErr } = tituloIds.length
      ? await applyTenantEmpresa(
          supabase
            .schema("f")
            .from("titulo_parcela")
            .select("id,titulo_id,vencimento_date,valor,valor_aberto")
            .in("titulo_id", tituloIds)
            .is("deleted_at", null),
          tenantId,
          empresaId
        ).returns<ParcelaFinanceiraRow[]>()
      : { data: [] as ParcelaFinanceiraRow[], error: null };
    if (parcErr) throw parcErr;

    const titulosByDocumentoId: Record<string, TituloFinanceiroRow[]> = {};
    for (const titulo of titulosRelevantes) {
      const docId = String(titulo.documento_fiscal_id ?? "");
      if (!docId) continue;
      if (!titulosByDocumentoId[docId]) titulosByDocumentoId[docId] = [];
      titulosByDocumentoId[docId].push(titulo);
    }

    const parcelasByTituloId: Record<string, ParcelaFinanceiraRow[]> = {};
    for (const parcela of parcelaData ?? []) {
      const tituloId = String(parcela.titulo_id ?? "");
      if (!tituloId) continue;
      if (!parcelasByTituloId[tituloId]) parcelasByTituloId[tituloId] = [];
      parcelasByTituloId[tituloId].push(parcela);
    }

    const next: Record<string, PagamentoMeta> = {};
    for (const row of rows) {
      next[String(row.id)] = computePagamentoMeta(
        row,
        titulosByDocumentoId[String(row.id)] ?? [],
        parcelasByTituloId
      );
    }
    return next;
  };

  const resolveOrdensServico = async (rows: DocumentoFiscalRow[]) => {
    if (!te.tenantId) return;

    const ids = Array.from(
      new Set(
        rows
          .map((r) => (typeof r.os_id_import === "number" ? r.os_id_import : null))
          .filter((v): v is number => typeof v === "number")
      )
    );
    const missing = ids.filter((id) => !(String(id) in osNumeroById));
    if (!missing.length) return;

    const supabase = supabaseBrowser();
    const tenantId = te.tenantId;
    const empresaId = te.empresaId ?? te.empresas[0]?.id ?? "";

    const resolved = await Promise.all(
      missing.map(async (osId) => {
        const selection = await fetchOsSelectionById({ supabase, tenantId, empresaId, osId });
        return { osId, numeroOs: selection?.numeroOs ?? "" };
      })
    );

    setOsNumeroById((prev) => {
      const next = { ...prev };
      for (const item of resolved) {
        next[String(item.osId)] = item.numeroOs;
      }
      return next;
    });
  };

  const fetchDocsAndTitulosForEmpresa = async (empresaId: string, offset: number) => {
    const supabase = supabaseBrowser();
    const tenantId = te.tenantId!;

    let query = applyTenantEmpresa(
      supabase
        .schema("f")
        .from("documento_fiscal")
        .select(
          "id,operacao,emissao_date,modelo,serie,numero,chave_acesso,empresa_id,cliente_id,fornecedor_id,os_id_import,valor_total,nfe_status,created_at"
        )
        .eq("operacao", "SAIDA")
        .eq("natureza", "PRODUTO")
        .or("modelo.is.null,modelo.neq.NFSE")
        .is("deleted_at", null),
      tenantId,
      empresaId
    )
      // Filtro explicito alem do RLS (current_empresa_id()): como runAcrossEmpresas
      // troca o contexto de empresa via RPC de forma sequencial mas o contexto e
      // compartilhado (tabela user_empresa_context, nao por conexao), uma race entre
      // reloads concorrentes pode fazer esta query rodar com o contexto errado.
      // O .eq aqui garante que so voltam linhas da empresa pedida nesta iteracao.
      .eq("empresa_id", empresaId)
      .order("emissao_date", { ascending: false, nullsFirst: false })
      .order("created_at", { ascending: false })
      .range(offset, offset + PAGE_SIZE - 1);

    if (periodo.startDate) {
      query = query.gte("emissao_date", periodo.startDate);
    }
    if (periodo.endDate) {
      query = query.lte("emissao_date", periodo.endDate);
    }

    const { data, error: qErr } = await query;
    if (qErr) throw qErr;

    const rows = (data ?? []) as unknown as DocumentoFiscalRow[];

    const documentoIds = rows.map((row) => String(row.id));
    const { data: tituloData, error: titErr } = documentoIds.length
      ? await applyTenantEmpresa(
          supabase
            .schema("f")
            .from("titulo")
            .select("id,documento_fiscal_id,tipo,status,valor_total,valor_aberto")
            .in("documento_fiscal_id", documentoIds)
            .eq("empresa_id", empresaId)
            .is("deleted_at", null),
          tenantId,
          empresaId
        ).returns<TituloFinanceiroRow[]>()
      : { data: [] as TituloFinanceiroRow[], error: null };
    if (titErr) throw titErr;

    return {
      rows,
      titulos: (tituloData ?? []) as TituloFinanceiroRow[],
      more: rows.length === PAGE_SIZE,
    };
  };

  const reload = async () => {
    if (!ready) return;

    setLoading(true);
    setError(null);
    try {
      const supabase = supabaseBrowser();
      const targetIds = resolveScopeEmpresaIds(empresaScope, allowedEmpresaIds);
      const restoreId = te.empresaId ?? targetIds[0] ?? null;

      const perEmpresa = await runAcrossEmpresas(supabase, targetIds, restoreId, (empresaId) =>
        fetchDocsAndTitulosForEmpresa(empresaId, 0)
      );

      const rows = targetIds.flatMap((id) => perEmpresa[id]?.rows ?? []).sort(compareDocsDesc);
      const titulos = targetIds.flatMap((id) => perEmpresa[id]?.titulos ?? []);
      const nextOffsets: Record<string, number> = {};
      const nextMore: Record<string, boolean> = {};
      for (const id of targetIds) {
        nextOffsets[id] = perEmpresa[id]?.rows.length ?? 0;
        nextMore[id] = perEmpresa[id]?.more ?? false;
      }

      const pagamentos = await buildPagamentosFromTitulos(rows, titulos);
      await Promise.all([resolveClientes(rows), resolveFornecedores(rows), resolveOrdensServico(rows)]);

      setDocs(rows);
      setPagamentosByDocId(pagamentos);
      setOffsetsByEmpresa(nextOffsets);
      setMoreByEmpresa(nextMore);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro inesperado ao carregar NF-e.");
      setDocs([]);
      setOsNumeroById({});
      setPagamentosByDocId({});
      setOffsetsByEmpresa({});
      setMoreByEmpresa({});
    } finally {
      setLoading(false);
    }
  };

  const loadMore = async () => {
    if (loadingMore || loading) return;
    if (!hasMore) return;
    if (!ready) return;

    setLoadingMore(true);
    setError(null);
    try {
      const supabase = supabaseBrowser();
      const targetIds = resolveScopeEmpresaIds(empresaScope, allowedEmpresaIds).filter(
        (id) => moreByEmpresa[id] !== false
      );
      const restoreId = te.empresaId ?? targetIds[0] ?? null;

      const perEmpresa = await runAcrossEmpresas(supabase, targetIds, restoreId, (empresaId) =>
        fetchDocsAndTitulosForEmpresa(empresaId, offsetsByEmpresa[empresaId] ?? 0)
      );

      const newRows = targetIds.flatMap((id) => perEmpresa[id]?.rows ?? []).sort(compareDocsDesc);
      const newTitulos = targetIds.flatMap((id) => perEmpresa[id]?.titulos ?? []);

      const pagamentos = await buildPagamentosFromTitulos(newRows, newTitulos);
      await Promise.all([resolveClientes(newRows), resolveFornecedores(newRows), resolveOrdensServico(newRows)]);

      setDocs((prev) => [...prev, ...newRows].sort(compareDocsDesc));
      setPagamentosByDocId((prev) => ({ ...prev, ...pagamentos }));
      setOffsetsByEmpresa((prev) => {
        const next = { ...prev };
        for (const id of targetIds) {
          next[id] = (prev[id] ?? 0) + (perEmpresa[id]?.rows.length ?? 0);
        }
        return next;
      });
      setMoreByEmpresa((prev) => {
        const next = { ...prev };
        for (const id of targetIds) {
          next[id] = perEmpresa[id]?.more ?? false;
        }
        return next;
      });
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro inesperado ao carregar mais NF-e.");
    } finally {
      setLoadingMore(false);
    }
  };

  useEffect(() => {
    if (!ready) return;
    void reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    ready,
    canFinanceiro,
    te.sessionUserId,
    te.tenantId,
    te.empresaId,
    te.empresas.length,
    empresaScope,
    periodo.startDate,
    periodo.endDate,
  ]);

  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();

    return docs.filter((r) => {
      const pagamento = pagamentosByDocId[String(r.id)] ?? buildPagamentoFallback(r);
      if (!matchesPagamentoFiltro(pagamento.status, pagamentoFiltro)) return false;

      if (!term) return true;

      const numero = String(r.numero ?? "").toLowerCase();
        const modelo = String(r.modelo ?? "").toLowerCase();
        const serie = String(r.serie ?? "").toLowerCase();
        const chave = String(r.chave_acesso ?? "").toLowerCase();
        const clienteNome = r.cliente_id ? String(clientesById[String(r.cliente_id)] ?? "").toLowerCase() : "";
        const fornecedorNome = r.fornecedor_id ? String(fornecedoresById[String(r.fornecedor_id)] ?? "").toLowerCase() : "";
        const empresaNome = r.empresa_id ? empresasById[String(r.empresa_id)]?.searchText ?? "" : "";
        return (
          numero.includes(term) ||
          clienteNome.includes(term) ||
          fornecedorNome.includes(term) ||
          empresaNome.includes(term) ||
          chave.includes(term) ||
          `${modelo} ${serie} ${numero}`.replace(/\s+/g, " ").trim().includes(term)
        );
      });
  }, [clientesById, docs, empresasById, fornecedoresById, pagamentoFiltro, pagamentosByDocId, search]);

  const resumoFiltro = useMemo(() => {
    const totals = filtered.reduce(
      (acc, row) => {
        const pagamento = pagamentosByDocId[String(row.id)] ?? buildPagamentoFallback(row);
        acc.valor += Math.max(0, n(row.valor_total));
        acc.pago += pagamento.pago;
        acc.aPagar += pagamento.aPagar;
        acc.atrasado += pagamento.atrasado;
        return acc;
      },
      { valor: 0, pago: 0, aPagar: 0, atrasado: 0 }
    );

    return {
      label: pagamentoResumoLabel(pagamentoFiltro),
      value: pagamentoResumoValor(pagamentoFiltro, totals),
      ...totals,
    };
  }, [filtered, pagamentoFiltro, pagamentosByDocId]);

  const headerRight = canImportXmlFaturamento ? (
    <button
      type="button"
      onClick={() => setImportOpen(true)}
      className="inline-flex items-center rounded-md bg-zinc-800 px-3 py-2 text-sm font-medium text-zinc-100 hover:bg-zinc-700"
    >
      Importar XML
    </button>
  ) : null;

  return (
    <div className="w-full px-4 py-6">
      <NfeImportModal
        open={importOpen}
        onClose={() => {
          setImportOpen(false);
          if (!searchParams.get("import")) return;
          const params = new URLSearchParams(searchParams.toString());
          params.delete("import");
          const nextUrl = params.toString() ? `/faturamento/nfe?${params.toString()}` : "/faturamento/nfe";
          router.replace(nextUrl, { scroll: false });
        }}
      />
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold text-zinc-100">NF-e</h1>
          <p className="text-sm text-zinc-400">Listagem (somente leitura)</p>
        </div>
        {headerRight}
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-[minmax(0,1fr)_auto]">
        <div>
          <label className="block text-xs font-medium text-zinc-400">Buscar</label>
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Numero, chave de acesso ou parceiro"
            className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 placeholder:text-zinc-500 focus:outline-none focus:ring-2 focus:ring-zinc-700"
          />
        </div>

        <EmpresaScopeFilter options={empresaScopeOptions} value={empresaScope} onChange={setEmpresaScope} />

        <div className="lg:min-w-[360px]">
          <label className="block text-xs font-medium text-zinc-400">Pagamento</label>
          <div className="mt-1 flex flex-wrap gap-2">
            {[
              { value: "TODOS" as const, label: "Todos" },
              { value: "PAGOS" as const, label: "Pagos" },
              { value: "A_PAGAR" as const, label: "A pagar" },
              { value: "ATRASADOS" as const, label: "Atrasados" },
            ].map((option) => {
              const active = pagamentoFiltro === option.value;
              return (
                <button
                  key={option.value}
                  type="button"
                  onClick={() => setPagamentoFiltro(option.value)}
                  className={[
                    "rounded-md border px-3 py-2 text-sm transition-colors",
                    active
                      ? "border-zinc-600 bg-zinc-800 text-zinc-100"
                      : "border-zinc-800 bg-zinc-950 text-zinc-300 hover:bg-zinc-900",
                  ].join(" ")}
                >
                  {option.label}
                </button>
              );
            })}
          </div>
        </div>
      </div>

      <PeriodoMesAnoFilter basePath="/faturamento/nfe" />

      <div className="mt-4 rounded-xl border border-zinc-800 bg-zinc-950 px-4 py-4">
        <div className="text-xs font-medium uppercase tracking-wide text-zinc-500">Resumo</div>
        <div className="mt-2 flex flex-wrap items-end justify-between gap-4">
          <div>
            <div className="text-sm text-zinc-400">{resumoFiltro.label}</div>
            <div className="mt-1 text-2xl font-semibold tabular-nums text-zinc-100">
              {formatMoneyBR(resumoFiltro.value)}
            </div>
          </div>
          <div className="grid gap-2 text-right sm:grid-cols-3 sm:gap-4">
            <div>
              <div className="text-xs uppercase tracking-wide text-zinc-500">Pago</div>
              <div className="text-sm font-medium tabular-nums text-emerald-300">{formatMoneyBR(resumoFiltro.pago)}</div>
            </div>
            <div>
              <div className="text-xs uppercase tracking-wide text-zinc-500">A receber</div>
              <div className="text-sm font-medium tabular-nums text-amber-200">{formatMoneyBR(resumoFiltro.aPagar)}</div>
            </div>
            <div>
              <div className="text-xs uppercase tracking-wide text-zinc-500">Em atraso</div>
              <div className="text-sm font-medium tabular-nums text-rose-300">{formatMoneyBR(resumoFiltro.atrasado)}</div>
            </div>
          </div>
        </div>
      </div>

      <div className="mt-4 overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950">
        <div className="flex items-center justify-between border-b border-zinc-800 px-4 py-3">
          <div className="text-sm text-zinc-200">{loading ? "Carregando..." : `${filtered.length} registro(s)`}</div>
          <button
            type="button"
            onClick={() => void reload()}
            className="text-sm text-zinc-300 hover:text-zinc-100"
            disabled={loading || loadingMore}
          >
            Recarregar
          </button>
        </div>

        {error ? <div className="px-4 py-3 text-sm text-rose-200">{error}</div> : null}

        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-zinc-950/60 text-zinc-400">
              <tr>
                <th className="px-4 py-3 text-left font-medium">Operacao</th>
                <th className="px-4 py-3 text-left font-medium">Emissao</th>
                <th className="px-4 py-3 text-left font-medium">Empresa</th>
                <th className="px-4 py-3 text-left font-medium">Modelo</th>
                <th className="px-4 py-3 text-left font-medium">Serie</th>
                <th className="px-4 py-3 text-left font-medium">Numero</th>
                <th className="px-4 py-3 text-left font-medium">Parceiro</th>
                <th className="px-4 py-3 text-left font-medium">OS vinculada</th>
                <th className="px-4 py-3 text-left font-medium">Chave</th>
                <th className="px-4 py-3 text-left font-medium">Status NF-e</th>
                <th className="px-4 py-3 text-left font-medium">Pagamento</th>
                <th className="px-4 py-3 text-right font-medium">Pago</th>
                <th className="px-4 py-3 text-right font-medium">A pagar</th>
                <th className="px-4 py-3 text-right font-medium">Valor</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {!loading && filtered.length === 0 ? (
                <tr>
                  <td className="px-4 py-6 text-center text-zinc-500" colSpan={14}>
                    Nenhum registro encontrado.
                  </td>
                </tr>
              ) : null}

              {filtered.map((r) => {
                const pagamento = pagamentosByDocId[String(r.id)] ?? buildPagamentoFallback(r);
                return (
                  <tr
                    key={r.id}
                    className={`${pagamentoRowClass(pagamento.status)} cursor-pointer transition-colors`}
                    onClick={() => router.push(`/faturamento/nfe/${r.id}`)}
                  >
                    <td className="px-4 py-3 text-zinc-200">{String(r.operacao ?? "").toUpperCase() || "-"}</td>
                    <td className="whitespace-nowrap px-4 py-3 text-zinc-200">{formatDateBR(r.emissao_date) || "-"}</td>
                    <td className="px-4 py-3 text-zinc-200" title={r.empresa_id ? empresasById[String(r.empresa_id)]?.fullName ?? "" : ""}>
                      {r.empresa_id ? empresasById[String(r.empresa_id)]?.label ?? "Sem empresa" : "-"}
                    </td>
                    <td className="px-4 py-3 text-zinc-200">{r.modelo ?? "-"}</td>
                    <td className="px-4 py-3 text-zinc-200">{r.serie ?? "-"}</td>
                    <td className="px-4 py-3 tabular-nums text-zinc-200">{r.numero ?? "-"}</td>
                    <td className="px-4 py-3 text-zinc-200">
                      {typeof r.cliente_id === "number" ? clientesById[String(r.cliente_id)] ?? `ID ${r.cliente_id}` : "-"}
                    </td>
                    <td className="px-4 py-3 text-zinc-200">
                      {typeof r.os_id_import === "number"
                        ? osNumeroById[String(r.os_id_import)] || `ID ${r.os_id_import}`
                        : "-"}
                    </td>
                    <td className="px-4 py-3 font-mono text-xs text-zinc-200" title={r.chave_acesso}>
                      {shortKey(r.chave_acesso)}
                    </td>
                    <td className="px-4 py-3 text-zinc-200">{r.nfe_status ? String(r.nfe_status) : "-"}</td>
                    <td className="px-4 py-3">
                      <span
                        className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-medium ${pagamentoStatusBadgeClass(
                          pagamento.status
                        )}`}
                      >
                        {pagamentoStatusLabel(pagamento.status)}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums text-zinc-200">
                      {formatMoneyBR(pagamento.pago)}
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums text-zinc-200">
                      {formatMoneyBR(pagamento.aPagar)}
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums text-zinc-200">{formatMoneyBR(n(r.valor_total))}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        <div className="flex items-center justify-between border-t border-zinc-800 px-4 py-3">
          <div className="text-xs text-zinc-500">{docs.length} carregado(s)</div>
          {hasMore ? (
            <button
              type="button"
              onClick={() => void loadMore()}
              disabled={loadingMore || loading}
              className="rounded-md bg-zinc-800 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-700 disabled:opacity-50"
            >
              {loadingMore ? "Carregando..." : "Carregar mais"}
            </button>
          ) : (
            <div className="text-xs text-zinc-500">Fim da lista</div>
          )}
        </div>
      </div>
    </div>
  );
}
