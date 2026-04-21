"use client";

import Link from "next/link";
import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny } from "@/lib/auth/capabilities";
import { formatDecimalBR, formatMoneyBR } from "@/lib/decimal";
import {
  listEntradasNoPeriodo,
  listEntradasNoPeriodoDetalhes,
  listFornecedores,
  listSaldoEmEstoque,
  type EntradasNoPeriodoFilters,
  type EntradasNoPeriodoSortKey,
  type EntradaConsolidadaRow,
  type EntradaDetalheRow,
  type FornecedorOption,
  type SaldoEmEstoqueRow,
  type SaldoEmEstoqueFilters,
  type SaldoEmEstoqueSortKey,
  type SortDir,
} from "@/lib/queries/estoque-relatorios";
import SaldoEmEstoqueFiltersPanel from "./components/SaldoEmEstoqueFilters";
import EntradasNoPeriodoFiltersPanel from "./components/EntradasNoPeriodoFilters";

type TabKey = "saldo" | "entradas";
const PAGE_SIZE = 50;

function getErrorMessage(e: unknown, fallback: string) {
  if (!e) return fallback;
  if (typeof e === "string" && e.trim()) return e;
  if (typeof e === "object" && e !== null && "message" in e) {
    const msg = (e as { message?: unknown }).message;
    if (typeof msg === "string" && msg.trim()) return msg;
  }
  return fallback;
}

function todayISO() {
  return new Date().toISOString().slice(0, 10);
}

function daysAgoISO(days: number) {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d.toISOString().slice(0, 10);
}

function downloadCsv(filename: string, header: string[], rows: string[][]) {
  const lines = [header, ...rows]
    .map((cols) => cols.map((c) => JSON.stringify(String(c ?? ""))).join(","))
    .join("\n");
  const blob = new Blob(["\uFEFF", lines], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function Pagination({ page, totalCount, onPage }: { page: number; totalCount: number; onPage: (p: number) => void }) {
  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));
  return (
    <div className="flex items-center justify-between gap-3">
      <div className="text-sm text-zinc-400">
        Pagina <span className="text-zinc-200 tabular-nums">{page}</span> de{" "}
        <span className="text-zinc-200 tabular-nums">{totalPages}</span> •{" "}
        <span className="text-zinc-200 tabular-nums">{totalCount}</span> registros
      </div>
      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={() => onPage(Math.max(1, page - 1))}
          disabled={page <= 1}
          className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 disabled:opacity-50"
        >
          Anterior
        </button>
        <button
          type="button"
          onClick={() => onPage(Math.min(totalPages, page + 1))}
          disabled={page >= totalPages}
          className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 disabled:opacity-50"
        >
          Proxima
        </button>
      </div>
    </div>
  );
}

function ThSort({ label, active, dir, onClick }: { label: string; active: boolean; dir: SortDir; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} className={`text-left w-full ${active ? "text-zinc-100" : "text-zinc-300 hover:text-zinc-100"}`}>
      <span className="inline-flex items-center gap-1">
        {label}
        {active ? <span className="text-zinc-500">{dir === "asc" ? "▲" : "▼"}</span> : null}
      </span>
    </button>
  );
}

function formatDateTimeBR(iso: string | null | undefined) {
  if (!iso) return "-";
  const d = new Date(String(iso));
  if (!Number.isFinite(d.getTime())) return String(iso);
  return d.toLocaleString("pt-BR");
}

function toFiniteNumberOrNull(value: unknown): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value !== "string") return null;

  const trimmed = value.trim();
  if (!trimmed) return null;

  const normalized = trimmed.includes(",")
    ? trimmed.replace(/\./g, "").replace(",", ".")
    : trimmed;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function toFiniteNumber(value: unknown): number {
  return toFiniteNumberOrNull(value) ?? 0;
}

function pickPositiveUnitValue(values: unknown[]): number {
  for (const value of values) {
    const parsed = toFiniteNumber(value);
    if (parsed > 0) return parsed;
  }
  return 0;
}

export default function RelatoriosEstoqueClient() {
  const te = useTenantEmpresa();
  const router = useRouter();
  const searchParams = useSearchParams();
  const { loading: permissionsLoading, ready: permissionsReady, capabilities } = usePermissions();
  const canView = requireAny(capabilities, ["estoque.read", "estoque.write"]);

  const tenantId = te.tenantId ?? null;
  const empresaId = te.empresaId ?? (te.empresas.length === 1 ? te.empresas[0]?.id : null);
  const contextReady = typeof te.sessionUserId === "string" && Boolean(tenantId) && Boolean(empresaId) && !te.loading && permissionsReady;
  const activeTab: TabKey = (String(searchParams.get("tab") ?? "").trim() as TabKey) || "saldo";
  const tab: TabKey = activeTab === "entradas" ? "entradas" : "saldo";

  const [fornecedores, setFornecedores] = useState<FornecedorOption[]>([]);
  const [fornLoading, setFornLoading] = useState(false);
  const warnedMissingContextRef = useRef(false);

  const appliedA = useMemo<SaldoEmEstoqueFilters>(() => {
    return {
      fornecedorPrefix: String(searchParams.get("a_forn_pref") ?? ""),
      fornecedorIds: [],
      semFornecedor: searchParams.get("a_sem_forn") === "1",
      busca: String(searchParams.get("a_busca") ?? ""),
      finalidade: String(searchParams.get("a_finalidade") ?? "materia_prima"),
      abaixoMinimo: searchParams.get("a_abaixo_minimo") === "1",
      separarPorFornecedor: searchParams.get("a_sep_forn") === "1",
      localizacao: "",
    };
  }, [searchParams]);

  const aPage = Math.max(1, Number(searchParams.get("a_page") ?? "1") || 1);
  const aSortKey = ((searchParams.get("a_sort") ?? "nome") as SaldoEmEstoqueSortKey) || "nome";
  const aSortDir: SortDir = (searchParams.get("a_dir") === "desc" ? "desc" : "asc") as SortDir;

  const appliedB = useMemo<EntradasNoPeriodoFilters>(() => {
    const osParam = String(searchParams.get("b_os") ?? "todos").trim();
    const osMode: EntradasNoPeriodoFilters["osMode"] = osParam === "com_os" || osParam === "sem_os" ? osParam : "todos";
    return {
      dataIni: String(searchParams.get("b_ini") ?? daysAgoISO(30)),
      dataFim: String(searchParams.get("b_fim") ?? todayISO()),
      fornecedorPrefix: String(searchParams.get("b_forn_pref") ?? ""),
      fornecedorIds: [],
      buscaItem: String(searchParams.get("b_busca") ?? ""),
      osMode,
      comNf: searchParams.get("b_com_nf") === "1",
      destacarSaldoAlto: searchParams.get("b_saldo_alto") === "1",
    };
  }, [searchParams]);
  const bPage = Math.max(1, Number(searchParams.get("b_page") ?? "1") || 1);
  const bSortKey = ((searchParams.get("b_sort") ?? "item") as EntradasNoPeriodoSortKey) || "item";
  const bSortDir: SortDir = (searchParams.get("b_dir") === "asc" ? "asc" : "desc") as SortDir;

  const [rowsA, setRowsA] = useState<SaldoEmEstoqueRow[]>([]);
  const [countA, setCountA] = useState(0);
  const [loadingA, setLoadingA] = useState(true);
  const [errorA, setErrorA] = useState<string | null>(null);
  const [rowsB, setRowsB] = useState<EntradaConsolidadaRow[]>([]);
  const [countB, setCountB] = useState(0);
  const [loadingB, setLoadingB] = useState(true);
  const [errorB, setErrorB] = useState<string | null>(null);
  const [expandedRowsB, setExpandedRowsB] = useState<Record<string, boolean>>({});
  const [detalhesRowsB, setDetalhesRowsB] = useState<Record<string, EntradaDetalheRow[]>>({});
  const [detalhesLoadingB, setDetalhesLoadingB] = useState<Record<string, boolean>>({});

  const setParam = useCallback(
    (updates: Record<string, string | null>, opts?: { keepTab?: boolean }) => {
      const next = new URLSearchParams(searchParams.toString());
      for (const [k, v] of Object.entries(updates)) {
        if (v === null || v === "") next.delete(k);
        else next.set(k, v);
      }
      if (!opts?.keepTab) next.set("tab", tab);
      const qs = next.toString();
      router.replace(qs ? `/estoque/relatorios?${qs}` : "/estoque/relatorios");
    },
    [router, searchParams, tab]
  );

  const clearTabParams = useCallback(
    (prefix: "a_" | "b_") => {
      const next = new URLSearchParams(searchParams.toString());
      for (const k of Array.from(next.keys())) if (k.startsWith(prefix)) next.delete(k);
      next.set("tab", tab);
      const qs = next.toString();
      router.replace(qs ? `/estoque/relatorios?${qs}` : "/estoque/relatorios");
    },
    [router, searchParams, tab]
  );

  useEffect(() => {
    if (!contextReady) {
      if (process.env.NODE_ENV !== "production" && typeof te.sessionUserId === "string" && !warnedMissingContextRef.current) {
        warnedMissingContextRef.current = true;
      }
      return;
    }
    warnedMissingContextRef.current = false;
    let cancelled = false;
    const run = async () => {
      setFornLoading(true);
      try {
        const supabase = getSupabaseBrowser();
        const list = await listFornecedores(supabase, tenantId!);
        if (!cancelled) setFornecedores(list);
      } catch {
        if (!cancelled) setFornecedores([]);
      } finally {
        if (!cancelled) setFornLoading(false);
      }
    };
    void run();
    return () => {
      cancelled = true;
    };
  }, [contextReady, te.sessionUserId, tenantId]);

  useEffect(() => {
    if (!contextReady || tab !== "saldo") return;
    let cancelled = false;
    const run = async () => {
      setLoadingA(true);
      setErrorA(null);
      try {
        const supabase = getSupabaseBrowser();
        const res = await listSaldoEmEstoque(supabase, { tenantId: tenantId!, empresaId: empresaId! }, { page: aPage, pageSize: PAGE_SIZE, sort: { key: aSortKey, dir: aSortDir }, filters: appliedA });
        if (cancelled) return;
        setRowsA(res.rows as SaldoEmEstoqueRow[]);
        setCountA(res.count);
      } catch (e) {
        if (cancelled) return;
        setRowsA([]);
        setCountA(0);
        setErrorA(getErrorMessage(e, "Erro ao carregar saldo em estoque."));
      } finally {
        if (!cancelled) setLoadingA(false);
      }
    };
    void run();
    return () => {
      cancelled = true;
    };
  }, [contextReady, tab, tenantId, empresaId, aPage, aSortKey, aSortDir, appliedA]);

  useEffect(() => {
    if (!contextReady || tab !== "entradas") return;
    let cancelled = false;
    const run = async () => {
      setLoadingB(true);
      setErrorB(null);
      try {
        const supabase = getSupabaseBrowser();
        const res = await listEntradasNoPeriodo(supabase, { tenantId: tenantId!, empresaId: empresaId! }, { page: bPage, pageSize: PAGE_SIZE, sort: { key: bSortKey, dir: bSortDir }, filters: appliedB });
        if (cancelled) return;
        setRowsB(res.rows);
        setCountB(res.count);
        setExpandedRowsB({});
        setDetalhesRowsB({});
        setDetalhesLoadingB({});
      } catch (e) {
        if (cancelled) return;
        setRowsB([]);
        setCountB(0);
        setErrorB(getErrorMessage(e, "Erro ao carregar entradas no periodo."));
      } finally {
        if (!cancelled) setLoadingB(false);
      }
    };
    void run();
    return () => {
      cancelled = true;
    };
  }, [contextReady, tab, tenantId, empresaId, bPage, bSortKey, bSortDir, appliedB]);

  const saldoRows = useMemo(() => {
    const mapped = rowsA.map((r) => {
      const fornecedorLabel = String(r.fornecedor_nome ?? "").trim() || "SEM FORNECEDOR";
      const saldoNumero = toFiniteNumber(r.quantidade_atual);
      const estoqueMinimoNumero = toFiniteNumber(r.estoque_minimo);
      const estoqueMaximoNumero = toFiniteNumber(r.estoque_maximo);
      const valorUnitario = pickPositiveUnitValue([r.preco_unitario, r.custo_medio]);
      const valorTotal = toFiniteNumberOrNull(r.valor_estoque) ?? saldoNumero * valorUnitario;
      return { ...r, fornecedorLabel, saldoNumero, estoqueMinimoNumero, estoqueMaximoNumero, valorUnitario, valorTotal };
    });
    if (!appliedA.separarPorFornecedor) return mapped;
    return mapped.sort((a, b) => {
      const f = a.fornecedorLabel.localeCompare(b.fornecedorLabel, "pt-BR", { sensitivity: "base" });
      if (f !== 0) return f;
      return String(a.item_nome ?? "").localeCompare(String(b.item_nome ?? ""), "pt-BR", { sensitivity: "base" });
    });
  }, [rowsA, appliedA.separarPorFornecedor]);

  const saldoGroups = useMemo(() => {
    if (!appliedA.separarPorFornecedor) return [] as Array<{ fornecedorNome: string; rows: typeof saldoRows; total: number; itens: number }>;
    const groups: Array<{ fornecedorNome: string; rows: typeof saldoRows; total: number; itens: number }> = [];
    for (const row of saldoRows) {
      const g = groups[groups.length - 1];
      if (!g || g.fornecedorNome !== row.fornecedorLabel) groups.push({ fornecedorNome: row.fornecedorLabel, rows: [row], total: row.valorTotal, itens: 1 });
      else {
        g.rows.push(row);
        g.total += row.valorTotal;
        g.itens += 1;
      }
    }
    return groups;
  }, [saldoRows, appliedA.separarPorFornecedor]);

  const saldoTotalItens = saldoRows.length;
  const saldoTotalEstoque = useMemo(() => saldoRows.reduce((acc, r) => acc + Number(r.valorTotal || 0), 0), [saldoRows]);
  const [printingSaldoPdf, setPrintingSaldoPdf] = useState(false);

  const exportSaldoCsv = () => {
    const header = ["id", "codigo", "item", "fornecedor", "und", "saldo", "est_min", "est_max", "val_uni", "valor_total"];
    const rows = saldoRows.map((r) => [
      String(r.item_id ?? ""),
      String(r.codigo_interno ?? ""),
      String(r.item_nome ?? ""),
      String(r.fornecedorLabel),
      String(r.unidade_medida ?? ""),
      String(r.saldoNumero),
      String(r.estoqueMinimoNumero),
      String(r.estoqueMaximoNumero),
      String(r.valorUnitario),
      String(r.valorTotal),
    ]);
    downloadCsv(`saldo_estoque_p${aPage}.csv`, header, rows);
  };
  const printSaldoPdf = async () => {
    if (!contextReady || printingSaldoPdf) return;
    setPrintingSaldoPdf(true);
    try {
      const [{ jsPDF }, autoTableMod] = await Promise.all([import("jspdf"), import("jspdf-autotable")]);
      const autoTable = autoTableMod.default;
      const supabase = getSupabaseBrowser();

      const pageSizePdf = 500;
      let page = 1;
      let totalBase = 0;
      let totalPages = 1;
      const allRows: SaldoEmEstoqueRow[] = [];

      while (page <= totalPages) {
        const res = await listSaldoEmEstoque(
          supabase,
          { tenantId: tenantId!, empresaId: empresaId! },
          {
            page,
            pageSize: pageSizePdf,
            sort: { key: aSortKey, dir: aSortDir },
            filters: appliedA,
          }
        );
        if (page === 1) {
          totalBase = Number(res.count ?? 0);
          totalPages = Math.max(1, Math.ceil(totalBase / pageSizePdf));
        }
        allRows.push(...res.rows);
        page += 1;
      }

      if (!allRows.length) return;

      const mapped = allRows.map((r) => {
        const fornecedorLabel = String(r.fornecedor_nome ?? "").trim() || "SEM FORNECEDOR";
        const saldoNumero = toFiniteNumber(r.quantidade_atual);
        const estoqueMinimoNumero = toFiniteNumber(r.estoque_minimo);
        const estoqueMaximoNumero = toFiniteNumber(r.estoque_maximo);
        const valorUnitario = pickPositiveUnitValue([r.preco_unitario, r.custo_medio]);
        const valorTotal = toFiniteNumberOrNull(r.valor_estoque) ?? saldoNumero * valorUnitario;
        return { ...r, fornecedorLabel, saldoNumero, estoqueMinimoNumero, estoqueMaximoNumero, valorUnitario, valorTotal };
      });

      const finalRows = appliedA.separarPorFornecedor
        ? [...mapped].sort((a, b) => {
            const f = a.fornecedorLabel.localeCompare(b.fornecedorLabel, "pt-BR", { sensitivity: "base" });
            if (f !== 0) return f;
            return String(a.item_nome ?? "").localeCompare(String(b.item_nome ?? ""), "pt-BR", { sensitivity: "base" });
          })
        : mapped;

      const totalItens = finalRows.length;
      const totalValor = finalRows.reduce((acc, r) => acc + Number(r.valorTotal || 0), 0);
      const filtrosTexto = [
        appliedA.fornecedorPrefix.trim() ? `Fornecedor: ${appliedA.fornecedorPrefix.trim()}*` : null,
        appliedA.semFornecedor ? "Sem fornecedor: sim" : null,
        appliedA.busca.trim() ? `Busca: ${appliedA.busca.trim()}` : null,
        appliedA.finalidade && appliedA.finalidade !== "todas" ? `Finalidade: ${String(appliedA.finalidade)}` : null,
        appliedA.abaixoMinimo ? "Abaixo do minimo: sim" : null,
        appliedA.separarPorFornecedor ? "Separado por fornecedor: sim" : "Separado por fornecedor: nao",
      ]
        .filter(Boolean)
        .join(" | ");

      const doc = new jsPDF({ orientation: "landscape", unit: "pt", format: "a4" });
      const margin = 36;
      const pageWidth = doc.internal.pageSize.getWidth();

      const header = () => {
        doc.setFontSize(14);
        doc.setTextColor(20);
        doc.text("Relatorio de Estoque - Saldo em estoque", margin, 34);
        doc.setFontSize(9);
        doc.setTextColor(70);
        doc.text(`Emitido em: ${new Date().toLocaleString("pt-BR")}`, margin, 50);
        doc.text(
          doc.splitTextToSize(`Filtros: ${filtrosTexto || "Nenhum"}`, pageWidth - margin * 2),
          margin,
          64
        );
        doc.text(`Itens: ${totalItens} | Total em estoque: ${formatMoneyBR(totalValor)}`, margin, 86);
      };

      const body: string[][] = [];
      if (appliedA.separarPorFornecedor) {
        let fornecedorAtual = "";
        let subtotal = 0;
        for (let i = 0; i < finalRows.length; i += 1) {
          const r = finalRows[i];
          if (r.fornecedorLabel !== fornecedorAtual) {
            if (fornecedorAtual) {
              body.push(["", "", `Subtotal ${fornecedorAtual}`, "", "", "", "", "", formatMoneyBR(subtotal)]);
            }
            fornecedorAtual = r.fornecedorLabel;
            subtotal = 0;
            body.push(["", "", `Fornecedor: ${fornecedorAtual}`, "", "", "", "", "", ""]);
          }
          subtotal += r.valorTotal;
          body.push([
            String(r.item_id ?? ""),
            String(r.codigo_interno ?? ""),
            String(r.item_nome ?? ""),
            String(r.unidade_medida ?? "-"),
            formatDecimalBR(r.saldoNumero, 3),
            formatDecimalBR(r.estoqueMinimoNumero, 3),
            formatDecimalBR(r.estoqueMaximoNumero, 3),
            formatMoneyBR(r.valorUnitario),
            formatMoneyBR(r.valorTotal),
          ]);
          if (i === finalRows.length - 1) {
            body.push(["", "", `Subtotal ${fornecedorAtual}`, "", "", "", "", "", formatMoneyBR(subtotal)]);
          }
        }
      } else {
        for (const r of finalRows) {
          body.push([
            String(r.item_id ?? ""),
            String(r.codigo_interno ?? ""),
            String(r.item_nome ?? ""),
            String(r.unidade_medida ?? "-"),
            formatDecimalBR(r.saldoNumero, 3),
            formatDecimalBR(r.estoqueMinimoNumero, 3),
            formatDecimalBR(r.estoqueMaximoNumero, 3),
            formatMoneyBR(r.valorUnitario),
            formatMoneyBR(r.valorTotal),
          ]);
        }
      }

      autoTable(doc, {
        startY: 98,
        head: [["ID", "Codigo", "Item", "Und", "Saldo", "Est. Min", "Est. Max", "Val. uni.", "Valor total"]],
        body,
        // Reserva a mesma altura do cabecalho em todas as paginas.
        margin: { left: margin, right: margin, top: 98, bottom: 28 },
        styles: { fontSize: 8.5, cellPadding: 4, overflow: "linebreak", lineColor: [220, 220, 220], lineWidth: 0.1 },
        headStyles: { fillColor: [28, 28, 30], textColor: 255, fontStyle: "bold" },
        alternateRowStyles: { fillColor: [245, 245, 245] },
        columnStyles: {
          0: { cellWidth: 38 },
          1: { cellWidth: 86 },
          2: { cellWidth: 260 },
          3: { cellWidth: 40 },
          4: { cellWidth: 64, halign: "right" },
          5: { cellWidth: 64, halign: "right" },
          6: { cellWidth: 64, halign: "right" },
          7: { cellWidth: 74, halign: "right" },
          8: { cellWidth: 80, halign: "right" },
        },
        didDrawPage: () => {
          header();
        },
      });

      const pages = doc.getNumberOfPages();
      for (let i = 1; i <= pages; i += 1) {
        doc.setPage(i);
        doc.setFontSize(9);
        doc.setTextColor(90);
        doc.text(`Pagina ${i} de ${pages}`, pageWidth - margin, doc.internal.pageSize.getHeight() - 14, {
          align: "right",
        });
      }

      doc.autoPrint();
      const url = doc.output("bloburl");
      const w = window.open(url, "_blank");
      if (!w) {
        doc.save(`saldo-estoque-${new Date().toISOString().slice(0, 10)}.pdf`);
      }
    } catch (e) {
      console.error(e);
      setErrorA("Falha ao gerar PDF do saldo.");
    } finally {
      setPrintingSaldoPdf(false);
    }
  };

  const getEntradaRowKey = useCallback((row: EntradaConsolidadaRow) => `${row.item_id}-${row.fornecedor_id ?? "sem"}`, []);

  const toggleEntradaExpand = useCallback(
    async (row: EntradaConsolidadaRow) => {
      const key = getEntradaRowKey(row);
      const isOpen = Boolean(expandedRowsB[key]);
      if (isOpen) {
        setExpandedRowsB((prev) => ({ ...prev, [key]: false }));
        return;
      }

      setExpandedRowsB((prev) => ({ ...prev, [key]: true }));
      if (detalhesRowsB[key] || detalhesLoadingB[key]) return;

      setDetalhesLoadingB((prev) => ({ ...prev, [key]: true }));
      try {
        const supabase = getSupabaseBrowser();
        const details = await listEntradasNoPeriodoDetalhes(
          supabase,
          { tenantId: tenantId!, empresaId: empresaId! },
          {
            filters: appliedB,
            itemId: row.item_id,
            fornecedorId: row.fornecedor_id,
          }
        );
        setDetalhesRowsB((prev) => ({ ...prev, [key]: details }));
      } catch {
        setDetalhesRowsB((prev) => ({ ...prev, [key]: [] }));
      } finally {
        setDetalhesLoadingB((prev) => ({ ...prev, [key]: false }));
      }
    },
    [appliedB, detalhesLoadingB, detalhesRowsB, empresaId, expandedRowsB, getEntradaRowKey, tenantId]
  );

  const exportEntradasCsv = () => {
    const header = [
      "id",
      "codigo",
      "item",
      "fornecedor",
      "motivo",
      "qtd_comprada",
      "qtd_para_os",
      "qtd_para_estoque",
      "percentual_os",
      "destino_os",
      "saldo_atual",
      "saldo_ajustado",
      "estoque_ideal",
      "situacao",
    ];

    const rows: string[][] = [];
    for (const r of rowsB) {
      rows.push([
        String(r.item_id ?? ""),
        r.codigo_interno ?? "",
        r.item_nome ?? "",
        r.fornecedor_nome ?? "SEM FORNECEDOR",
        r.motivo ?? "",
        String(r.qtd_comprada),
        String(r.qtd_para_os),
        String(r.qtd_para_estoque),
        `${r.percentual_os.toFixed(1)}%`,
        r.destino_os ?? "-",
        String(r.saldo_atual),
        String(r.saldo_ajustado),
        String(r.estoque_ideal),
        r.situacao,
      ]);

      const key = getEntradaRowKey(r);
      if (expandedRowsB[key] && detalhesRowsB[key]?.length) {
        for (const d of detalhesRowsB[key]) {
          rows.push([
            "",
            "DETALHE",
            "",
            "",
            "",
            String(d.quantidade),
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            `${formatDateTimeBR(d.data_movimentacao)} | NF ${d.nf} | OS ${d.os_id ?? "-"} | ${d.tipo} | Usuario ${d.realizado_por ?? "-"}`,
          ]);
        }
      }
    }

    downloadCsv(`entradas_periodo_p${bPage}.csv`, header, rows);
  };

  if (!permissionsReady && permissionsLoading) return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissoes...</div>;
  if (!canView) return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;

  return (
    <div className="space-y-4">
      <div className="no-print flex items-center gap-2">
        <button type="button" onClick={() => setParam({ tab: "saldo" }, { keepTab: true })} className={`px-3 py-1.5 rounded-md text-sm ${tab === "saldo" ? "bg-zinc-800 text-zinc-100" : "text-zinc-400 hover:text-zinc-100"}`}>Saldo em estoque</button>
        <button type="button" onClick={() => setParam({ tab: "entradas" }, { keepTab: true })} className={`px-3 py-1.5 rounded-md text-sm ${tab === "entradas" ? "bg-zinc-800 text-zinc-100" : "text-zinc-400 hover:text-zinc-100"}`}>Entradas no periodo</button>
      </div>

      {tab === "saldo" ? (
        <>
          <div className="no-print">
            <SaldoEmEstoqueFiltersPanel
              fornecedores={fornecedores}
              applied={appliedA}
              onApply={(next) => setParam({ a_forn_pref: next.fornecedorPrefix?.trim() ? next.fornecedorPrefix.trim() : null, a_sem_forn: next.semFornecedor ? "1" : null, a_busca: next.busca.trim() ? next.busca.trim() : null, a_finalidade: next.finalidade && next.finalidade !== "todas" ? String(next.finalidade) : "todas", a_abaixo_minimo: next.abaixoMinimo ? "1" : null, a_sep_forn: next.separarPorFornecedor ? "1" : null, a_page: "1" })}
              onClear={() => { clearTabParams("a_"); setParam({ tab: "saldo" }, { keepTab: true }); }}
            />
          </div>

          <div className="no-print flex items-center justify-between gap-3 flex-wrap">
            <div className="text-sm text-zinc-400">{loadingA ? "Carregando..." : <><span className="text-zinc-200 tabular-nums">{countA}</span> {countA === 1 ? "item" : "itens"}</>}{fornLoading ? <span className="ml-3 text-zinc-500">Carregando fornecedores...</span> : null}</div>
            <div className="flex items-center gap-2">
              <button type="button" onClick={() => void printSaldoPdf()} disabled={loadingA || saldoRows.length === 0 || printingSaldoPdf} className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50">{printingSaldoPdf ? "Gerando PDF..." : "Imprimir PDF"}</button>
              <button type="button" onClick={exportSaldoCsv} disabled={loadingA || saldoRows.length === 0} className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50">Exportar CSV</button>
            </div>
          </div>

          {errorA ? <div className="rounded-xl border border-red-900/50 bg-red-950/20 p-4 text-red-200">{errorA}</div> : null}

          <div className="print-report border border-zinc-800 rounded-xl bg-zinc-950 overflow-x-auto">
            <table className="w-full text-sm min-w-[1320px]">
              <thead className="text-zinc-300">
                <tr className="border-b border-zinc-800">
                  <th className="px-3 py-2 text-left">ID</th>
                  <th className="px-3 py-2 text-left"><ThSort label="Codigo" active={aSortKey === "codigo"} dir={aSortDir} onClick={() => setParam({ a_sort: "codigo", a_dir: aSortKey === "codigo" && aSortDir === "asc" ? "desc" : "asc", a_page: "1" })} /></th>
                  <th className="px-3 py-2 text-left"><ThSort label="Item" active={aSortKey === "nome"} dir={aSortDir} onClick={() => setParam({ a_sort: "nome", a_dir: aSortKey === "nome" && aSortDir === "asc" ? "desc" : "asc", a_page: "1" })} /></th>
                  <th className="px-3 py-2 text-left">Fornecedor</th>
                  <th className="px-3 py-2 text-left">Und</th>
                  <th className="px-3 py-2 text-right">Saldo</th>
                  <th className="px-3 py-2 text-right">Est. Min</th>
                  <th className="px-3 py-2 text-right">Est. Max</th>
                  <th className="px-3 py-2 text-right">Val. uni.</th>
                  <th className="px-3 py-2 text-right">Valor total</th>
                </tr>
              </thead>
              {loadingA ? (
                <tbody><tr><td colSpan={10} className="px-3 py-8 text-center text-zinc-300">Carregando...</td></tr></tbody>
              ) : saldoRows.length === 0 ? (
                <tbody><tr><td colSpan={10} className="px-3 py-10 text-center text-zinc-400">Nenhum resultado.</td></tr></tbody>
              ) : appliedA.separarPorFornecedor ? (
                <>
                  {saldoGroups.map((g, idx) => (
                    <tbody key={`g-${g.fornecedorNome}-${idx}`}>
                      <tr className={idx > 0 ? "print-group bg-zinc-900/60 border-y border-zinc-700" : "bg-zinc-900/60 border-y border-zinc-700"}>
                        <td colSpan={10} className="px-3 py-2 text-zinc-100 font-medium">{g.fornecedorNome} - Itens: {g.itens} - Total do fornecedor: {formatMoneyBR(g.total)}</td>
                      </tr>
                      {g.rows.map((r) => (
                        <tr key={`${r.fornecedorLabel}-${r.item_id}`} className="border-b border-zinc-900">
                          <td className="px-3 py-2 text-left tabular-nums">{r.item_id}</td>
                          <td className="px-3 py-2 text-left tabular-nums">{r.codigo_interno || "-"}</td>
                          <td className="px-3 py-2 text-left">{r.item_nome || "-"}</td>
                          <td className="px-3 py-2 text-left">{r.fornecedorLabel}</td>
                          <td className="px-3 py-2 text-left">{r.unidade_medida ?? "-"}</td>
                          <td className="px-3 py-2 text-right tabular-nums">{formatDecimalBR(r.saldoNumero, 3)}</td>
                          <td className="px-3 py-2 text-right tabular-nums">{formatDecimalBR(r.estoqueMinimoNumero, 3)}</td>
                          <td className="px-3 py-2 text-right tabular-nums">{formatDecimalBR(r.estoqueMaximoNumero, 3)}</td>
                          <td className="px-3 py-2 text-right tabular-nums">{formatMoneyBR(r.valorUnitario)}</td>
                          <td className="px-3 py-2 text-right tabular-nums">{formatMoneyBR(r.valorTotal)}</td>
                        </tr>
                      ))}
                      <tr className="border-b border-zinc-700 bg-zinc-900/40"><td colSpan={9} className="px-3 py-2 text-right">Subtotal do fornecedor</td><td className="px-3 py-2 text-right tabular-nums">{formatMoneyBR(g.total)}</td></tr>
                    </tbody>
                  ))}
                </>
              ) : (
                <tbody>
                  {saldoRows.map((r) => (
                    <tr key={`${r.item_id}`} className="border-b border-zinc-900">
                      <td className="px-3 py-2 text-left tabular-nums">{r.item_id}</td>
                      <td className="px-3 py-2 text-left tabular-nums">{r.codigo_interno || "-"}</td>
                      <td className="px-3 py-2 text-left">{r.item_nome || "-"}</td>
                      <td className="px-3 py-2 text-left">{r.fornecedorLabel}</td>
                      <td className="px-3 py-2 text-left">{r.unidade_medida ?? "-"}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{formatDecimalBR(r.saldoNumero, 3)}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{formatDecimalBR(r.estoqueMinimoNumero, 3)}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{formatDecimalBR(r.estoqueMaximoNumero, 3)}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{formatMoneyBR(r.valorUnitario)}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{formatMoneyBR(r.valorTotal)}</td>
                    </tr>
                  ))}
                </tbody>
              )}
              {!loadingA && saldoRows.length > 0 ? (
                <tfoot><tr className="border-t border-zinc-700 bg-zinc-900/50"><td colSpan={8} className="px-3 py-2">Total de itens: {saldoTotalItens}</td><td className="px-3 py-2 text-right">Total em estoque</td><td className="px-3 py-2 text-right tabular-nums">{formatMoneyBR(saldoTotalEstoque)}</td></tr></tfoot>
              ) : null}
            </table>
          </div>

          <div className="no-print"><Pagination page={aPage} totalCount={countA} onPage={(p) => setParam({ a_page: String(p) })} /></div>
        </>
      ) : (
        <>
          <EntradasNoPeriodoFiltersPanel fornecedores={fornecedores} applied={appliedB} onApply={(next) => setParam({ b_ini: next.dataIni, b_fim: next.dataFim, b_forn_pref: next.fornecedorPrefix?.trim() ? next.fornecedorPrefix.trim() : null, b_busca: next.buscaItem.trim() ? next.buscaItem.trim() : null, b_os: next.osMode !== "todos" ? next.osMode : null, b_com_nf: next.comNf ? "1" : null, b_saldo_alto: next.destacarSaldoAlto ? "1" : null, b_page: "1" })} onClear={() => { clearTabParams("b_"); setParam({ tab: "entradas" }, { keepTab: true }); }} />
          <div className="flex justify-end"><button type="button" onClick={exportEntradasCsv} disabled={loadingB || rowsB.length === 0} className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50">Exportar CSV</button></div>
          {errorB ? <div className="rounded-xl border border-red-900/50 bg-red-950/20 p-4 text-red-200">{errorB}</div> : null}
          <div className="border border-zinc-800 rounded-xl bg-zinc-950 overflow-x-auto">
            <table className="w-full text-sm min-w-[1760px]">
              <thead className="text-zinc-400">
                <tr className="border-b border-zinc-800">
                  <th className="px-3 py-2 w-[70px] text-left">ID</th>
                  <th className="px-3 py-2 w-[100px] text-left">Codigo</th>
                  <th className="px-3 py-2 text-left">Item</th>
                  <th className="px-3 py-2 w-[240px] text-left">Fornecedor</th>
                  <th className="px-3 py-2 w-[220px] text-left">Motivo</th>
                  <th className="px-3 py-2 w-[120px] text-right">Qtd Comprada</th>
                  <th className="px-3 py-2 w-[110px] text-right">Qtd p/ OS</th>
                  <th className="px-3 py-2 w-[130px] text-right">Qtd p/ Estoque</th>
                  <th className="px-3 py-2 w-[90px] text-right">% p/ OS</th>
                  <th className="px-3 py-2 w-[150px] text-left">OS destino</th>
                  <th className="px-3 py-2 w-[110px] text-right">Saldo Atual</th>
                  <th className="px-3 py-2 w-[130px] text-right">Saldo Ajustado</th>
                  <th className="px-3 py-2 w-[110px] text-right">Estoque Ideal</th>
                  <th className="px-3 py-2 w-[100px] text-center">Situacao</th>
                </tr>
              </thead>
              <tbody>
                {loadingB ? (
                  <tr>
                    <td colSpan={14} className="px-3 py-8 text-center text-zinc-300">
                      Carregando...
                    </td>
                  </tr>
                ) : rowsB.length === 0 ? (
                  <tr>
                    <td colSpan={14} className="px-3 py-10 text-center text-zinc-400">
                      Nenhum resultado.
                    </td>
                  </tr>
                ) : (
                  rowsB.map((r) => {
                    const key = getEntradaRowKey(r);
                    const isOpen = Boolean(expandedRowsB[key]);
                    const details = detalhesRowsB[key] ?? [];
                    const loadingDetails = Boolean(detalhesLoadingB[key]);

                    return (
                      <Fragment key={`grp-${key}`}>
                        <tr
                          key={`sum-${key}`}
                          className="border-b border-zinc-900 hover:bg-zinc-900/40 cursor-pointer"
                          onClick={() => void toggleEntradaExpand(r)}
                        >
                          <td className="px-3 py-2 text-left tabular-nums">{r.item_id}</td>
                          <td className="px-3 py-2 text-left tabular-nums">{r.codigo_interno || "-"}</td>
                          <td className="px-3 py-2 text-left">{r.item_nome || "-"}</td>
                          <td className="px-3 py-2 text-left">{r.fornecedor_nome || "SEM FORNECEDOR"}</td>
                          <td className="px-3 py-2 text-left">{r.motivo || "-"}</td>
                          <td className="px-3 py-2 text-right tabular-nums">{formatDecimalBR(r.qtd_comprada, 3)}</td>
                          <td className="px-3 py-2 text-right tabular-nums">{formatDecimalBR(r.qtd_para_os, 3)}</td>
                          <td className="px-3 py-2 text-right tabular-nums">{formatDecimalBR(r.qtd_para_estoque, 3)}</td>
                          <td className="px-3 py-2 text-right tabular-nums">{r.percentual_os.toFixed(1)}%</td>
                          <td className="px-3 py-2 text-left">{r.destino_os || "-"}</td>
                          <td className="px-3 py-2 text-right tabular-nums">{formatDecimalBR(r.saldo_atual, 3)}</td>
                          <td className="px-3 py-2 text-right tabular-nums">{formatDecimalBR(r.saldo_ajustado, 3)}</td>
                          <td className="px-3 py-2 text-right tabular-nums">{formatDecimalBR(r.estoque_ideal, 3)}</td>
                          <td className="px-3 py-2 text-center">
                            <span
                              className={
                                r.situacao === "ALERTA"
                                  ? "inline-flex rounded px-2 py-0.5 text-xs bg-red-900/50 text-red-100 border border-red-700"
                                  : "inline-flex rounded px-2 py-0.5 text-xs bg-emerald-900/50 text-emerald-100 border border-emerald-700"
                              }
                            >
                              {r.situacao}
                            </span>
                          </td>
                        </tr>
                        {isOpen ? (
                          <tr key={`det-${key}`} className="border-b border-zinc-800 bg-zinc-900/30">
                            <td colSpan={14} className="px-3 py-3">
                              {loadingDetails ? (
                                <div className="text-zinc-400">Carregando detalhes...</div>
                              ) : details.length === 0 ? (
                                <div className="text-zinc-500">Sem entradas detalhadas para este item/filtro.</div>
                              ) : (
                                <table className="w-full text-xs">
                                  <thead className="text-zinc-400">
                                    <tr className="border-b border-zinc-800">
                                      <th className="py-1 text-left">Data</th>
                                      <th className="py-1 text-left">NF</th>
                                      <th className="py-1 text-right">Qtd</th>
                                      <th className="py-1 text-left">OS</th>
                                      <th className="py-1 text-left">Tipo</th>
                                      <th className="py-1 text-left">Usuario</th>
                                    </tr>
                                  </thead>
                                  <tbody>
                                    {details.map((d) => (
                                      <tr key={`row-det-${d.movimentacao_id}`} className="border-b border-zinc-800/60">
                                        <td className="py-1 text-left">{formatDateTimeBR(d.data_movimentacao)}</td>
                                        <td className="py-1 text-left">{d.nf || "-"}</td>
                                        <td className="py-1 text-right tabular-nums">{formatDecimalBR(d.quantidade, 3)}</td>
                                        <td className="py-1 text-left">
                                          {d.os_id ? (
                                            <Link href={`/os/${d.os_id}`} className="underline text-zinc-200 hover:text-zinc-100">
                                              OS {d.os_id}
                                            </Link>
                                          ) : (
                                            "-"
                                          )}
                                        </td>
                                        <td className="py-1 text-left">{d.tipo}</td>
                                        <td className="py-1 text-left">{d.realizado_por ?? "-"}</td>
                                      </tr>
                                    ))}
                                  </tbody>
                                </table>
                              )}
                            </td>
                          </tr>
                        ) : null}
                      </Fragment>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
          <Pagination page={bPage} totalCount={countB} onPage={(p) => setParam({ b_page: String(p) })} />
        </>
      )}

      <style jsx global>{`
        @media print {
          .no-print { display: none !important; }
          .print-report { border: 0 !important; border-radius: 0 !important; overflow: visible !important; background: #fff !important; }
          .print-report table { min-width: 0 !important; width: 100% !important; font-size: 11px !important; }
          .print-report th, .print-report td { color: #000 !important; border-color: #d4d4d8 !important; }
          .print-group { break-before: page; page-break-before: always; }
        }
      `}</style>
    </div>
  );
}
