"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny } from "@/lib/auth/capabilities";
import { formatDecimalBR, formatMoneyBR } from "@/lib/decimal";
import {
  listEntradasNoPeriodo,
  listFornecedores,
  listSaldoEmEstoque,
  type EntradasNoPeriodoFilters,
  type EntradasNoPeriodoSortKey,
  type EntradaEnrichedRow,
  type FornecedorOption,
  type SaldoFinalidade,
  type SaldoEmEstoqueFilters,
  type SaldoEmEstoqueRow,
  type SaldoEmEstoqueSortKey,
  type SortDir,
} from "@/lib/queries/estoque-relatorios";
import SaldoEmEstoqueFiltersPanel from "./components/SaldoEmEstoqueFilters";
import EntradasNoPeriodoFiltersPanel from "./components/EntradasNoPeriodoFilters";

type TabKey = "saldo" | "entradas";

const PAGE_SIZE = 50;

function todayISO() {
  return new Date().toISOString().slice(0, 10);
}

function daysAgoISO(days: number) {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d.toISOString().slice(0, 10);
}

function getErrorMessage(e: unknown, fallback: string) {
  if (!e) return fallback;
  if (typeof e === "string" && e.trim()) return e;
  if (typeof e === "object" && e !== null && "message" in e) {
    const msg = (e as { message?: unknown }).message;
    if (typeof msg === "string" && msg.trim()) return msg;
  }
  return fallback;
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
        Página <span className="text-zinc-200 tabular-nums">{page}</span> de{" "}
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
          Próxima
        </button>
      </div>
    </div>
  );
}

function ThSort({
  label,
  active,
  dir,
  onClick,
}: {
  label: string;
  active: boolean;
  dir: SortDir;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`text-left w-full ${active ? "text-zinc-100" : "text-zinc-300 hover:text-zinc-100"}`}
      title="Ordenar"
    >
      <span className="inline-flex items-center gap-1">
        {label}
        {active ? <span className="text-zinc-500">{dir === "asc" ? "▲" : "▼"}</span> : null}
      </span>
    </button>
  );
}

function formatDateTimeBR(iso: string | null | undefined) {
  if (!iso) return "—";
  const d = new Date(String(iso));
  if (!Number.isFinite(d.getTime())) return String(iso);
  return d.toLocaleString("pt-BR");
}

function nfLabel(nf: EntradaEnrichedRow["mov"]["nf"]) {
  if (!nf) return "—";
  const modelo = String(nf.modelo ?? "").trim();
  const serie = nf.serie ?? "";
  const numero = nf.numero ?? "";
  const parts = [modelo, serie ? `S${serie}` : "", numero ? `N${numero}` : ""].filter(Boolean);
  return parts.length ? parts.join("/") : nf.chave ? String(nf.chave) : `#${nf.id}`;
}

export default function RelatoriosEstoqueClient() {
  const te = useTenantEmpresa();
  const router = useRouter();
  const searchParams = useSearchParams();

  const { loading: permissionsLoading, ready: permissionsReady, capabilities } = usePermissions();
  const canView = requireAny(capabilities, ["estoque.read", "estoque.write"]);

  const tenantId = te.tenantId ?? null;
  const empresaId = te.empresaId ?? (te.empresas.length === 1 ? te.empresas[0]?.id : null);

  const contextReady =
    typeof te.sessionUserId === "string" &&
    Boolean(tenantId) &&
    Boolean(empresaId) &&
    te.loading === false &&
    permissionsReady === true;

  const activeTab: TabKey = (String(searchParams.get("tab") ?? "").trim() as TabKey) || "saldo";
  const tab: TabKey = activeTab === "entradas" ? "entradas" : "saldo";

  // fornecedores
  const [fornecedores, setFornecedores] = useState<FornecedorOption[]>([]);
  const [fornLoading, setFornLoading] = useState(false);

  // TAB A state
  const appliedA = useMemo<SaldoEmEstoqueFilters>(() => {
    const finalidadeParam = String(searchParams.get("a_finalidade") ?? "materia_prima").trim() || "materia_prima";
    return {
      fornecedorPrefix: String(searchParams.get("a_forn_pref") ?? ""),
      fornecedorIds: [],
      semFornecedor: searchParams.get("a_sem_forn") === "1",
      busca: String(searchParams.get("a_busca") ?? ""),
      finalidade: finalidadeParam as SaldoFinalidade,
      abaixoMinimo: searchParams.get("a_abaixo_minimo") === "1",
      localizacao: "",
    };
  }, [searchParams]);

  const aPage = Math.max(1, Number(searchParams.get("a_page") ?? "1") || 1);
  const aSortKey = ((searchParams.get("a_sort") ?? "nome") as SaldoEmEstoqueSortKey) || "nome";
  const aSortDir: SortDir = (searchParams.get("a_dir") === "desc" ? "desc" : "asc") as SortDir;

  const [rowsA, setRowsA] = useState<SaldoEmEstoqueRow[]>([]);
  const [countA, setCountA] = useState(0);
  const [loadingA, setLoadingA] = useState(true);
  const [errorA, setErrorA] = useState<string | null>(null);

  // TAB B state
  const appliedB = useMemo<EntradasNoPeriodoFilters>(() => {
    const osParam = String(searchParams.get("b_os") ?? "todos").trim();
    const osMode: EntradasNoPeriodoFilters["osMode"] =
      osParam === "com_os" || osParam === "sem_os" ? osParam : "todos";
    return {
      dataIni: String(searchParams.get("b_ini") ?? daysAgoISO(30)),
      dataFim: String(searchParams.get("b_fim") ?? todayISO()),
      fornecedorPrefix: String(searchParams.get("b_forn_pref") ?? ""),
      fornecedorIds: [],
      buscaItem: String(searchParams.get("b_busca") ?? ""),
      osMode,
      comNf: searchParams.get("b_com_nf") === "1",
    };
  }, [searchParams]);

  const bPage = Math.max(1, Number(searchParams.get("b_page") ?? "1") || 1);
  const bSortKey = ((searchParams.get("b_sort") ?? "data") as EntradasNoPeriodoSortKey) || "data";
  const bSortDir: SortDir = (searchParams.get("b_dir") === "asc" ? "asc" : "desc") as SortDir;

  const [rowsB, setRowsB] = useState<EntradaEnrichedRow[]>([]);
  const [countB, setCountB] = useState(0);
  const [loadingB, setLoadingB] = useState(true);
  const [errorB, setErrorB] = useState<string | null>(null);

  const warnedMissingContextRef = useRef(false);

  const setParam = useCallback(
    (updates: Record<string, string | null>, opts?: { keepTab?: boolean }) => {
      const next = new URLSearchParams(searchParams.toString());

      for (const [k, v] of Object.entries(updates)) {
        if (v === null || v === "") next.delete(k);
        else next.set(k, v);
      }

      if (!opts?.keepTab) {
        next.set("tab", tab);
      }

      const qs = next.toString();
      router.replace(qs ? `/estoque/relatorios?${qs}` : "/estoque/relatorios");
    },
    [router, searchParams, tab]
  );

  const clearTabParams = useCallback(
    (prefix: "a_" | "b_") => {
      const next = new URLSearchParams(searchParams.toString());
      for (const k of Array.from(next.keys())) {
        if (k.startsWith(prefix)) next.delete(k);
      }
      next.set("tab", tab);
      const qs = next.toString();
      router.replace(qs ? `/estoque/relatorios?${qs}` : "/estoque/relatorios");
    },
    [router, searchParams, tab]
  );

  useEffect(() => {
    if (!contextReady) {
      if (
        process.env.NODE_ENV !== "production" &&
        typeof te.sessionUserId === "string" &&
        permissionsReady === true &&
        (!tenantId || !empresaId) &&
        !warnedMissingContextRef.current
      ) {
        console.debug("[estoque/relatorios] Contexto ausente", {
          tenantId,
          empresaId: empresaId ?? null,
          empresasCount: te.empresas.length,
        });
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
  }, [contextReady, empresaId, permissionsReady, te.empresas.length, te.sessionUserId, tenantId]);

  // TAB A load
  useEffect(() => {
    if (!contextReady) return;

    let cancelled = false;

    const run = async () => {
      setLoadingA(true);
      setErrorA(null);

      try {
        const supabase = getSupabaseBrowser();
        const res = await listSaldoEmEstoque(
          supabase,
          { tenantId: tenantId!, empresaId: empresaId! },
          {
            page: aPage,
            pageSize: PAGE_SIZE,
            sort: { key: aSortKey, dir: aSortDir },
            filters: appliedA,
          }
        );
        if (cancelled) return;
        setRowsA(res.rows);
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

    if (tab === "saldo") void run();
    return () => {
      cancelled = true;
    };
  }, [aPage, aSortDir, aSortKey, appliedA, contextReady, empresaId, tab, tenantId]);

  // TAB B load
  useEffect(() => {
    if (!contextReady) return;

    let cancelled = false;

    const run = async () => {
      setLoadingB(true);
      setErrorB(null);

      try {
        const supabase = getSupabaseBrowser();
        const res = await listEntradasNoPeriodo(
          supabase,
          { tenantId: tenantId!, empresaId: empresaId! },
          {
            page: bPage,
            pageSize: PAGE_SIZE,
            sort: { key: bSortKey, dir: bSortDir },
            filters: appliedB,
          }
        );
        if (cancelled) return;
        setRowsB(res.rows);
        setCountB(res.count);
      } catch (e) {
        if (cancelled) return;
        setRowsB([]);
        setCountB(0);
        setErrorB(getErrorMessage(e, "Erro ao carregar entradas no período."));
      } finally {
        if (!cancelled) setLoadingB(false);
      }
    };

    if (tab === "entradas") void run();
    return () => {
      cancelled = true;
    };
  }, [appliedB, bPage, bSortDir, bSortKey, contextReady, empresaId, tab, tenantId]);

  const setTab = (next: TabKey) => {
    setParam({ tab: next }, { keepTab: true });
  };

  const exportSaldoCsv = () => {
    const header = [
      "id",
      "codigo",
      "item",
      "unidade",
      "saldo",
      "custo_medio",
      "valor_estoque",
      "fornecedor",
      "minimo",
      "max",
    ];

    const rows = rowsA.map((r) => [
      String(r.item_id ?? ""),
      r.codigo_interno,
      r.item_nome,
      r.unidade_medida ?? "",
      String(r.quantidade_atual ?? 0),
      String(r.custo_medio ?? ""),
      String(r.valor_estoque ?? ""),
      r.fornecedor_nome ?? "",
      String(r.estoque_minimo ?? ""),
      String(r.estoque_ideal ?? ""),
    ]);

    downloadCsv(`saldo_estoque_p${aPage}.csv`, header, rows);
  };

  const [printingSaldoPdf, setPrintingSaldoPdf] = useState(false);

  const printSaldoPdf = async () => {
    if (!contextReady) return;
    if (printingSaldoPdf) return;

    setPrintingSaldoPdf(true);
    setErrorA(null);

    try {
      const [{ jsPDF }, autoTableMod] = await Promise.all([import("jspdf"), import("jspdf-autotable")]);
      const autoTable = autoTableMod.default;

      // Buscar todas as linhas filtradas (para o PDF não ficar com contagem/linhas divergentes)
      const supabase = getSupabaseBrowser();
      const all: SaldoEmEstoqueRow[] = [];
      const pageSizePdf = 500;
      let page = 1;
      let total = 0;

      while (true) {
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

        if (page === 1) total = Number(res.count ?? 0);
        if (!res.rows.length) break;
        all.push(...res.rows);
        if (total > 0 && all.length >= total) break;
        page += 1;
        if (page > 200) break;
      }

      if (all.length === 0) return;

      const doc = new jsPDF({ orientation: "landscape", unit: "pt", format: "a4" });
      const marginX = 40;
      let y = 42;

      doc.setFontSize(14);
      doc.text("Relatórios de Estoque — Saldo em estoque", marginX, y);
      y += 16;

      doc.setFontSize(10);
      doc.text(`Emissão: ${new Date().toLocaleString("pt-BR")}`, marginX, y);
      y += 12;

      const filtros: string[] = [];
      if (appliedA.fornecedorPrefix?.trim()) filtros.push(`Fornecedor: ${appliedA.fornecedorPrefix.trim()}*`);
      if (appliedA.semFornecedor) filtros.push("SEM FORNECEDOR");
      if (appliedA.busca?.trim()) filtros.push(`Busca: ${appliedA.busca.trim()}`);
      if (appliedA.finalidade && appliedA.finalidade !== "todas") filtros.push(`Finalidade: ${String(appliedA.finalidade)}`);
      if (appliedA.abaixoMinimo) filtros.push("Abaixo do mínimo");

      doc.text(`Filtros: ${filtros.length ? filtros.join(" • ") : "—"}`, marginX, y);
      y += 14;

      doc.text(`Itens filtrados: ${total || all.length}`, marginX, y);
      y += 14;

      const head = [["ID", "Código", "Item", "Und", "Saldo", "Custo Médio", "Valor em Estoque", "Mínimo", "Max"]];

      const body = all.map((r) => {
        const saldo = formatDecimalBR(r.quantidade_atual ?? 0, 3);
        const custo = formatMoneyBR(Number(r.custo_medio ?? 0));
        const valor = formatMoneyBR(Number(r.valor_estoque ?? 0));
        const minimo = formatDecimalBR(Number(r.estoque_minimo ?? 0), 3);
        const max = formatDecimalBR(Number(r.estoque_ideal ?? 0), 3);

        return [
          String(r.item_id ?? ""),
          String(r.codigo_interno ?? ""),
          String(r.item_nome ?? ""),
          String(r.unidade_medida ?? ""),
          saldo,
          custo,
          valor,
          minimo,
          max,
        ];
      });

      autoTable(doc, {
        startY: y + 6,
        head,
        body,
        margin: { left: marginX, right: marginX, top: 30, bottom: 30 },
        styles: {
          fontSize: 8,
          cellPadding: 3,
          overflow: "linebreak",
          lineWidth: 0.1,
          lineColor: [220, 220, 220],
        },
        headStyles: {
          fillColor: [245, 245, 245],
          textColor: [30, 30, 30],
          fontStyle: "bold",
        },
        columnStyles: {
          0: { cellWidth: 40 },
          1: { cellWidth: 90 },
          2: { cellWidth: 280 },
          3: { cellWidth: 40 },
          4: { cellWidth: 55, halign: "right" },
          5: { cellWidth: 70, halign: "right" },
          6: { cellWidth: 80, halign: "right" },
          7: { cellWidth: 55, halign: "right" },
          8: { cellWidth: 55, halign: "right" },
        },
      });

      doc.autoPrint();
      const url = doc.output("bloburl");
      const w = window.open(url, "_blank");
      if (!w) {
        const dataStr = new Date().toISOString().slice(0, 10);
        doc.save(`saldo-estoque-${dataStr}.pdf`);
      }
    } catch (e) {
      console.error(e);
      setErrorA("Falha ao gerar PDF.");
    } finally {
      setPrintingSaldoPdf(false);
    }
  };

  const exportEntradasCsv = () => {
    const header = [
      "data_entrada",
      "nf",
      "fornecedor",
      "item",
      "qtd",
      "destino",
      "os",
      "saldo_atual_item",
    ];

    const rows = rowsB.map((r) => {
      const forn = r.mov.nf?.fornecedores?.nome ?? "";
      const item = `${r.mov.itens?.codigo_interno ?? ""} ${r.mov.itens?.nome ?? ""}`.trim();
      const destino = r.mov.origem_os_id ? "OS" : "Estoque";
      const os = r.os
        ? `OS ${r.os.numero_os ?? r.os.id} - ${r.os.cliente_nome ?? ""} (${r.os.status ?? ""})`.trim()
        : "";

      return [
        formatDateTimeBR(r.mov.data_movimentacao),
        nfLabel(r.mov.nf),
        forn,
        item,
        String(r.mov.quantidade ?? 0),
        destino,
        os,
        r.saldoAtual === null ? "" : String(r.saldoAtual),
      ];
    });

    downloadCsv(`entradas_periodo_p${bPage}.csv`, header, rows);
  };

  if (!permissionsReady && permissionsLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando permissões...
      </div>
    );
  }

  if (!canView) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Acesso negado.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Relatórios de Estoque</h1>
          <p className="text-sm text-zinc-400 mt-1">Saldo atual e entradas no período, com filtros compartilháveis por URL.</p>
        </div>
      </div>

      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={() => setTab("saldo")}
          className={`px-3 py-1.5 rounded-md text-sm ${tab === "saldo" ? "bg-zinc-800 text-zinc-100" : "text-zinc-400 hover:text-zinc-100"}`}
        >
          Saldo em estoque
        </button>
        <button
          type="button"
          onClick={() => setTab("entradas")}
          className={`px-3 py-1.5 rounded-md text-sm ${tab === "entradas" ? "bg-zinc-800 text-zinc-100" : "text-zinc-400 hover:text-zinc-100"}`}
        >
          Entradas no período
        </button>
      </div>

      {tab === "saldo" ? (
        <>
          <SaldoEmEstoqueFiltersPanel
            fornecedores={fornecedores}
            applied={appliedA}
            onApply={(next) => {
              setParam({
                a_forn_pref: next.fornecedorPrefix?.trim() ? next.fornecedorPrefix.trim() : null,
                a_sem_forn: next.semFornecedor ? "1" : null,
                a_busca: next.busca.trim() ? next.busca.trim() : null,
                a_finalidade: next.finalidade && next.finalidade !== "todas" ? String(next.finalidade) : "todas",
                a_abaixo_minimo: next.abaixoMinimo ? "1" : null,
                a_page: "1",
              });
            }}
            onClear={() => {
              clearTabParams("a_");
              setParam({ tab: "saldo" }, { keepTab: true });
            }}
          />

          <div className="flex items-center justify-between gap-3 flex-wrap">
            <div className="text-sm text-zinc-400">
              {loadingA ? (
                "Carregando…"
              ) : (
                <>
                  <span className="text-zinc-200 tabular-nums">{countA}</span> {countA === 1 ? "item" : "itens"}
                </>
              )}
              {fornLoading ? <span className="ml-3 text-zinc-500">Carregando fornecedores…</span> : null}
            </div>
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={printSaldoPdf}
                disabled={loadingA || rowsA.length === 0 || printingSaldoPdf}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
              >
                {printingSaldoPdf ? "Gerando PDF…" : "Imprimir PDF"}
              </button>
              <button
                type="button"
                onClick={exportSaldoCsv}
                disabled={loadingA || rowsA.length === 0}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
              >
                Exportar CSV
              </button>
            </div>
          </div>

          {errorA ? (
            <div className="rounded-xl border border-red-900/50 bg-red-950/20 p-4 text-red-200">{errorA}</div>
          ) : null}

          <div className="border border-zinc-800 rounded-xl bg-zinc-950 overflow-x-auto">
            <table className="w-full text-sm min-w-[1050px]">
              <thead className="text-zinc-400">
                <tr className="border-b border-zinc-800">
                  <th className="px-3 py-2 w-[90px]">ID</th>
                  <th className="px-3 py-2 w-[120px]">
                    <ThSort
                      label="Código"
                      active={aSortKey === "codigo"}
                      dir={aSortDir}
                      onClick={() => {
                        const nextDir: SortDir = aSortKey === "codigo" ? (aSortDir === "asc" ? "desc" : "asc") : "asc";
                        setParam({ a_sort: "codigo", a_dir: nextDir, a_page: "1" });
                      }}
                    />
                  </th>
                  <th className="px-3 py-2">
                    <ThSort
                      label="Item"
                      active={aSortKey === "nome"}
                      dir={aSortDir}
                      onClick={() => {
                        const nextDir: SortDir = aSortKey === "nome" ? (aSortDir === "asc" ? "desc" : "asc") : "asc";
                        setParam({ a_sort: "nome", a_dir: nextDir, a_page: "1" });
                      }}
                    />
                  </th>
                  <th className="px-3 py-2 w-[70px]">Und</th>
                  <th className="px-3 py-2 w-[90px] text-right">Saldo</th>
                  <th className="px-3 py-2 w-[120px] text-right">Custo Médio</th>
                  <th className="px-3 py-2 w-[140px] text-right">Valor em Estoque</th>
                  <th className="px-3 py-2 w-[180px]">Fornecedor</th>
                  <th className="px-3 py-2 w-[90px] text-right">Mínimo</th>
                  <th className="px-3 py-2 w-[95px] text-right">Max</th>
                </tr>
              </thead>
              <tbody>
                {loadingA ? (
                  <tr>
                    <td colSpan={10} className="px-3 py-8 text-center text-zinc-300">
                      <div className="animate-pulse">Carregando…</div>
                    </td>
                  </tr>
                ) : rowsA.length === 0 ? (
                  <tr>
                    <td colSpan={10} className="px-3 py-10 text-center text-zinc-400">
                      Nenhum resultado. Dica: ajuste os filtros (fornecedor/finalidade/busca).
                    </td>
                  </tr>
                ) : (
                  rowsA.map((r) => {
                    const abaixo = Boolean(r.abaixo_minimo);
                    const valorEst = Number(r.valor_estoque ?? 0);
                    return (
                      <tr key={`${r.item_id}`} className="border-b border-zinc-900 hover:bg-zinc-900/30">
                        <td className="px-3 py-2 text-zinc-300 tabular-nums">{r.item_id}</td>
                        <td className="px-3 py-2 text-zinc-200 tabular-nums">{r.codigo_interno || "—"}</td>
                        <td className="px-3 py-2">
                          <div className="text-zinc-100">{r.item_nome || "—"}</div>
                          {abaixo ? <div className="text-xs text-amber-300">Abaixo do mínimo</div> : null}
                        </td>
                        <td className="px-3 py-2 text-zinc-300">{r.unidade_medida ?? "—"}</td>
                        <td className="px-3 py-2 text-right text-zinc-100 tabular-nums">
                          {formatDecimalBR(r.quantidade_atual ?? 0, 3)}
                        </td>
                        <td className="px-3 py-2 text-right text-zinc-300 tabular-nums">{formatMoneyBR(Number(r.custo_medio ?? 0))}</td>
                        <td className="px-3 py-2 text-right text-zinc-300 tabular-nums">{formatMoneyBR(valorEst)}</td>
                        <td className="px-3 py-2 text-zinc-300">{r.fornecedor_nome ?? "—"}</td>
                        <td className="px-3 py-2 text-right text-zinc-300 tabular-nums">{formatDecimalBR(Number(r.estoque_minimo ?? 0), 3)}</td>
                        <td className="px-3 py-2 text-right text-zinc-300 tabular-nums">{formatDecimalBR(Number(r.estoque_ideal ?? 0), 3)}</td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>

          <Pagination
            page={aPage}
            totalCount={countA}
            onPage={(p) => setParam({ a_page: String(p) })}
          />

          <div className="text-xs text-zinc-500">
            Obs.: se a view <span className="text-zinc-300">vw_estoque_saldo</span> não estiver instalada no banco, o filtro “Abaixo do mínimo” pode ter paginação/contagem aproximadas.
          </div>
        </>
      ) : (
        <>
          <EntradasNoPeriodoFiltersPanel
            fornecedores={fornecedores}
            applied={appliedB}
            onApply={(next) => {
              setParam({
                b_ini: next.dataIni,
                b_fim: next.dataFim,
                b_forn_pref: next.fornecedorPrefix?.trim() ? next.fornecedorPrefix.trim() : null,
                b_busca: next.buscaItem.trim() ? next.buscaItem.trim() : null,
                b_os: next.osMode !== "todos" ? next.osMode : null,
                b_com_nf: next.comNf ? "1" : null,
                b_page: "1",
              });
            }}
            onClear={() => {
              clearTabParams("b_");
              setParam({ tab: "entradas" }, { keepTab: true });
            }}
          />

          <div className="flex items-center justify-between gap-3 flex-wrap">
            <div />
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={exportEntradasCsv}
                disabled={loadingB || rowsB.length === 0}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
              >
                Exportar CSV
              </button>
            </div>
          </div>

          {errorB ? (
            <div className="rounded-xl border border-red-900/50 bg-red-950/20 p-4 text-red-200">{errorB}</div>
          ) : null}

          <div className="border border-zinc-800 rounded-xl bg-zinc-950 overflow-x-auto">
            <table className="w-full text-sm min-w-[1200px]">
              <thead className="text-zinc-400">
                <tr className="border-b border-zinc-800">
                  <th className="px-3 py-2 w-[190px]">
                    <ThSort
                      label="Data Entrada"
                      active={bSortKey === "data"}
                      dir={bSortDir}
                      onClick={() => {
                        const nextDir: SortDir = bSortKey === "data" ? (bSortDir === "asc" ? "desc" : "asc") : "desc";
                        setParam({ b_sort: "data", b_dir: nextDir, b_page: "1" });
                      }}
                    />
                  </th>
                  <th className="px-3 py-2 w-[180px]">NF</th>
                  <th className="px-3 py-2 w-[200px]">Fornecedor</th>
                  <th className="px-3 py-2">
                    <ThSort
                      label="Item"
                      active={bSortKey === "item"}
                      dir={bSortDir}
                      onClick={() => {
                        const nextDir: SortDir = bSortKey === "item" ? (bSortDir === "asc" ? "desc" : "asc") : "asc";
                        setParam({ b_sort: "item", b_dir: nextDir, b_page: "1" });
                      }}
                    />
                  </th>
                  <th className="px-3 py-2 w-[90px] text-right">Qtd</th>
                  <th className="px-3 py-2 w-[120px]">Destino</th>
                  <th className="px-3 py-2 w-[280px]">OS</th>
                  <th className="px-3 py-2 w-[120px] text-right">Saldo Atual</th>
                  <th className="px-3 py-2 w-[210px]">Ações</th>
                </tr>
              </thead>
              <tbody>
                {loadingB ? (
                  <tr>
                    <td colSpan={9} className="px-3 py-8 text-center text-zinc-300">
                      <div className="animate-pulse">Carregando…</div>
                    </td>
                  </tr>
                ) : rowsB.length === 0 ? (
                  <tr>
                    <td colSpan={9} className="px-3 py-10 text-center text-zinc-400">
                      Nenhum resultado. Dica: ajuste o período e os filtros.
                    </td>
                  </tr>
                ) : (
                  rowsB.map((r) => {
                    const forn = r.mov.nf?.fornecedores?.nome ?? "—";
                    const itemLabel = `${r.mov.itens?.codigo_interno ?? ""} ${r.mov.itens?.nome ?? ""}`.trim() || "—";
                    const destino = r.mov.origem_os_id ? "OS" : "Estoque";
                    const osLabel = r.os
                      ? `OS ${r.os.numero_os ?? r.os.id} • ${r.os.cliente_nome ?? ""} • ${r.os.status ?? ""}`.trim()
                      : "—";

                    const osHref = r.mov.origem_os_id ? `/os/${r.mov.origem_os_id}` : null;

                    return (
                      <tr key={`${r.mov.id}`} className="border-b border-zinc-900 hover:bg-zinc-900/30">
                        <td className="px-3 py-2 text-zinc-200 tabular-nums">{formatDateTimeBR(r.mov.data_movimentacao)}</td>
                        <td className="px-3 py-2 text-zinc-300">{nfLabel(r.mov.nf)}</td>
                        <td className="px-3 py-2 text-zinc-300">{forn}</td>
                        <td className="px-3 py-2 text-zinc-100">{itemLabel}</td>
                        <td className="px-3 py-2 text-right text-zinc-100 tabular-nums">{formatDecimalBR(r.mov.quantidade ?? 0, 3)}</td>
                        <td className="px-3 py-2 text-zinc-300">{destino}</td>
                        <td className="px-3 py-2 text-zinc-300">
                          {osHref ? (
                            <Link href={osHref} className="underline text-zinc-200 hover:text-zinc-100">
                              {osLabel}
                            </Link>
                          ) : (
                            osLabel
                          )}
                        </td>
                        <td className="px-3 py-2 text-right text-zinc-300 tabular-nums">
                          {r.saldoAtual === null ? "—" : formatDecimalBR(r.saldoAtual, 3)}
                        </td>
                        <td className="px-3 py-2">
                          <div className="flex flex-wrap gap-2">
                            <Link
                              href="/estoque/importar"
                              className="inline-flex px-2 py-1 rounded border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-200"
                              title="Abrir módulo de importação de NF"
                            >
                              Abrir NF
                            </Link>
                            {osHref ? (
                              <Link
                                href={osHref}
                                className="inline-flex px-2 py-1 rounded border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-200"
                              >
                                Abrir OS
                              </Link>
                            ) : null}
                            <Link
                              href="/itens"
                              className="inline-flex px-2 py-1 rounded border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-200"
                            >
                              Abrir Item
                            </Link>
                          </div>
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>

          <Pagination page={bPage} totalCount={countB} onPage={(p) => setParam({ b_page: String(p) })} />
        </>
      )}
    </div>
  );
}
