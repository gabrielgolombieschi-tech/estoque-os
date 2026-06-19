"use client";

import Image from "next/image";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/hooks";

type Area = "eletrico" | "mecanico";

type DashRow = {
  os_id: number;
  item_tipo: "execucao";
  area: Area;
  habilitado: boolean;
  data_prevista: string | null;
  progresso_percent: number;
  numero_os: string;
  cliente_nome: string;
  descricao_servico: string | null;
  status: "aberta" | "em_andamento" | "concluida" | "cancelada" | null;
};

type Props = {
  initialRows: DashRow[];
  emptyMessage?: string;
};

type GroupedRow = {
  os_id: number;
  numero_os: string;
  cliente_nome: string;
  descricao_servico: string | null;
  status: DashRow["status"];
  executionItems: DashRow[];
};

type ClientGroup = { cliente: string; rows: GroupedRow[] };

const DEFAULT_ROW_HEIGHT = 64;
const PAGE_ROTATION_MS = 20_000;
const AREA_ORDER: Record<Area, number> = { eletrico: 0, mecanico: 1 };

function executionLabel(area: Area) {
  return area === "eletrico" ? "ELE" : "MEC";
}

function parseDateValue(value: string | null): number {
  if (!value) return Number.MAX_SAFE_INTEGER;
  const parsed = new Date(value).getTime();
  return Number.isNaN(parsed) ? Number.MAX_SAFE_INTEGER : parsed;
}

function isOverdue(row: DashRow, today: Date) {
  const progress = Number(row.progresso_percent ?? 0);
  const date = row.data_prevista ? new Date(row.data_prevista) : null;
  if (!date || Number.isNaN(date.getTime())) return false;
  return progress < 100 && date < today;
}

function groupIsOverdue(row: GroupedRow, today: Date) {
  return row.executionItems.some((item) => isOverdue(item, today));
}

function groupSortDate(row: GroupedRow) {
  return row.executionItems.reduce(
    (earliest, item) => Math.min(earliest, parseDateValue(item.data_prevista)),
    Number.MAX_SAFE_INTEGER
  );
}

function buildClientGroups(osRows: GroupedRow[]): ClientGroup[] {
  const map = new Map<string, GroupedRow[]>();
  for (const row of osRows) {
    const key = row.cliente_nome || "-";
    const existing = map.get(key) ?? [];
    existing.push(row);
    map.set(key, existing);
  }
  return Array.from(map.entries()).map(([cliente, rows]) => ({ cliente, rows }));
}

export default function ExecucaoDashboard({ initialRows, emptyMessage }: Props) {
  const te = useTenantEmpresa();
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const isPainelTv = useMemo(() => {
    const papel = te.empresa?.papel;
    return typeof papel === "string" && papel.trim().toUpperCase() === "PAINEL_TV";
  }, [te.empresa?.papel]);

  const [rows, setRows] = useState<DashRow[]>(initialRows);
  const [selected, setSelected] = useState<GroupedRow | null>(null);
  const [progressValues, setProgressValues] = useState<Partial<Record<Area, string>>>({});
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [rowsPerPage, setRowsPerPage] = useState(20);
  const [pageIndex, setPageIndex] = useState(0);
  const [fadeVisible, setFadeVisible] = useState(true);
  const [now, setNow] = useState(() => new Date());

  const colViewportRef = useRef<HTMLDivElement | null>(null);
  const sampleRowRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => { setRows(initialRows); }, [initialRows]);

  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(id);
  }, []);

  const today = useMemo(() => {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    return d;
  }, []);

  const timeStr = now.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });

  const tableRows = useMemo(
    () =>
      rows.filter((row) => {
        const progress = Number(row.progresso_percent ?? 0);
        return (
          row.habilitado &&
          row.item_tipo === "execucao" &&
          (row.area === "eletrico" || row.area === "mecanico") &&
          progress < 100 &&
          row.status !== "concluida" &&
          row.status !== "cancelada"
        );
      }),
    [rows]
  );

  const groupedTable = useMemo(() => {
    const grouped = new Map<number, GroupedRow>();
    for (const row of tableRows) {
      const current = grouped.get(row.os_id);
      if (current) { current.executionItems.push(row); continue; }
      grouped.set(row.os_id, {
        os_id: row.os_id,
        numero_os: row.numero_os,
        cliente_nome: row.cliente_nome,
        descricao_servico: row.descricao_servico,
        status: row.status,
        executionItems: [row],
      });
    }
    return Array.from(grouped.values())
      .map((row) => ({
        ...row,
        executionItems: [...row.executionItems].sort((a, b) => AREA_ORDER[a.area] - AREA_ORDER[b.area]),
      }))
      .sort((a, b) => {
        const od = Number(groupIsOverdue(b, today)) - Number(groupIsOverdue(a, today));
        if (od !== 0) return od;
        const dd = groupSortDate(a) - groupSortDate(b);
        if (dd !== 0) return dd;
        return a.numero_os.localeCompare(b.numero_os, "pt-BR", { numeric: true });
      });
  }, [tableRows, today]);

  const recomputeRowsPerPage = useCallback(() => {
    const viewportHeight = colViewportRef.current?.clientHeight ?? 0;
    if (viewportHeight <= 0) return;
    const rowHeight = sampleRowRef.current?.getBoundingClientRect().height ?? DEFAULT_ROW_HEIGHT;
    const perColumn = Math.max(1, Math.floor(viewportHeight / Math.max(rowHeight, 32)));
    const next = perColumn * 2; // two columns
    setRowsPerPage((prev) => (prev === next ? prev : next));
  }, []);

  useEffect(() => { recomputeRowsPerPage(); }, [recomputeRowsPerPage, groupedTable.length, pageIndex]);

  useEffect(() => {
    const observer = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(recomputeRowsPerPage);
    if (colViewportRef.current) observer?.observe(colViewportRef.current);
    if (sampleRowRef.current) observer?.observe(sampleRowRef.current);
    window.addEventListener("resize", recomputeRowsPerPage);
    return () => { observer?.disconnect(); window.removeEventListener("resize", recomputeRowsPerPage); };
  }, [recomputeRowsPerPage, groupedTable.length, pageIndex]);

  const totalPages = useMemo(() => {
    if (groupedTable.length === 0) return 1;
    return Math.max(1, Math.ceil(groupedTable.length / rowsPerPage));
  }, [groupedTable.length, rowsPerPage]);

  useEffect(() => {
    setPageIndex((current) => (current >= totalPages ? 0 : current));
  }, [totalPages]);

  useEffect(() => {
    if (totalPages <= 1) { setPageIndex(0); return; }
    let flipTimeout: number | null = null;
    const id = window.setInterval(() => {
      setFadeVisible(false);
      flipTimeout = window.setTimeout(() => {
        setPageIndex((prev) => (prev + 1) % totalPages);
        setFadeVisible(true);
      }, 380);
    }, PAGE_ROTATION_MS);
    return () => { window.clearInterval(id); if (flipTimeout) window.clearTimeout(flipTimeout); };
  }, [totalPages]);

  const pageRows = useMemo(() => {
    const start = pageIndex * rowsPerPage;
    return groupedTable.slice(start, start + rowsPerPage);
  }, [groupedTable, pageIndex, rowsPerPage]);

  // Split OS in half and group each half by client
  const { leftGroups, rightGroups } = useMemo(() => {
    const half = Math.ceil(pageRows.length / 2);
    return {
      leftGroups: buildClientGroups(pageRows.slice(0, half)),
      rightGroups: buildClientGroups(pageRows.slice(half)),
    };
  }, [pageRows]);

  const handleRowClick = (row: GroupedRow) => {
    if (isPainelTv) return;
    setSelected(row);
    setProgressValues(
      row.executionItems.reduce<Partial<Record<Area, string>>>((acc, item) => {
        acc[item.area] = String(Math.max(0, Math.min(100, Math.trunc(Number(item.progresso_percent ?? 0)))));
        return acc;
      }, {})
    );
    setSaveError(null);
  };

  const closeModal = () => {
    if (saving) return;
    setSelected(null);
    setProgressValues({});
    setSaveError(null);
  };

  const handleSave = async () => {
    if (!selected || isPainelTv) return;
    setSaving(true);
    setSaveError(null);
    const applied: Array<{ area: Area; progressNum: number }> = [];
    for (const item of selected.executionItems) {
      const progressNum = Math.max(0, Math.min(100, Math.trunc(Number(progressValues[item.area] ?? item.progresso_percent ?? 0))));
      const { error } = await supabase
        .from("os_gestao_itens")
        .update({ progresso_percent: progressNum })
        .eq("os_id", item.os_id)
        .eq("item_tipo", item.item_tipo)
        .eq("area", item.area);
      if (error) {
        if (applied.length > 0) {
          const m = new Map(applied.map((u) => [u.area, u.progressNum]));
          setRows((prev) => prev.map((r) => r.os_id === selected.os_id && m.has(r.area) ? { ...r, progresso_percent: m.get(r.area) ?? r.progresso_percent } : r));
        }
        setSaving(false);
        setSaveError(error.message);
        return;
      }
      applied.push({ area: item.area, progressNum });
    }
    const m = new Map(applied.map((u) => [u.area, u.progressNum]));
    setRows((prev) => prev.map((r) => r.os_id === selected.os_id && m.has(r.area) ? { ...r, progresso_percent: m.get(r.area) ?? r.progresso_percent } : r));
    setSaving(false);
    setSelected(null);
    setProgressValues({});
  };

  return (
    <div className="h-[calc(100dvh-3rem)] overflow-hidden flex flex-col bg-[#060C18] text-white">

      {/* ── Header — fundo claro para o logo aparecer ── */}
      <header
        className="shrink-0 flex items-center gap-5 px-8 h-[4.5rem]"
        style={{ background: "var(--bg-banner)", borderBottom: "1px solid #c7d9e8" }}
      >
        <div className="relative h-11 w-36 shrink-0">
          <Image src="/Segau2.png" alt="Segau" fill className="object-contain object-left" />
        </div>

        <div className="w-px h-8 shrink-0 bg-black/10" />

        <div className="flex flex-col leading-tight" style={{ color: "var(--text-banner)" }}>
          <span className="text-xl font-bold tracking-[0.2em] uppercase">Execução</span>
          <span className="text-[10px] tracking-widest uppercase opacity-50">Quadro de chão de fábrica</span>
        </div>

        <div className="flex-1" />

        <div className="flex items-center gap-6 shrink-0" style={{ color: "var(--text-banner)" }}>
          <div className="text-sm text-right font-mono opacity-70">
            <span className="font-bold opacity-100">{groupedTable.length}</span> OS em andamento
          </div>

          {totalPages > 1 && (
            <div className="flex items-center gap-1.5 px-3 py-1 rounded text-xs font-mono font-bold tracking-wider bg-[#0369a1]/10 text-[#0369a1] border border-[#0369a1]/30">
              <span className="inline-block w-1.5 h-1.5 rounded-full bg-[#0369a1] animate-pulse" />
              PÁG {pageIndex + 1} / {totalPages}
            </div>
          )}

          <div className="text-2xl font-mono font-bold tabular-nums text-[#0369a1]">
            {timeStr}
          </div>
        </div>
      </header>

      {/* ── Column labels — uma linha que cobre ambas as colunas ── */}
      <div
        className="shrink-0 grid grid-cols-2 bg-[#04080F]"
        style={{ borderBottom: "1px solid #0E1E30" }}
      >
        {(["left", "right"] as const).map((side) => (
          <div
            key={side}
            className="grid items-center px-6 h-10"
            style={{
              gridTemplateColumns: "7rem 1fr 12rem",
              gap: "1rem",
              borderRight: side === "left" ? "1px solid #0E1E30" : undefined,
            }}
          >
            <span className="text-sm font-bold tracking-widest uppercase text-[#4A7AA0]">Nº OS</span>
            <span className="text-sm font-bold tracking-widest uppercase text-[#4A7AA0]">Descrição do Serviço</span>
            <span className="text-sm font-bold tracking-widest uppercase text-[#4A7AA0] text-right">Tipo</span>
          </div>
        ))}
      </div>

      {/* ── Conteúdo em duas colunas ── */}
      <div
        className="flex-1 min-h-0 overflow-hidden grid grid-cols-2"
        style={{
          opacity: fadeVisible ? 1 : 0,
          transition: "opacity 0.38s ease",
        }}
      >
        {[leftGroups, rightGroups].map((groups, colIdx) => (
          <div
            key={colIdx}
            ref={colIdx === 0 ? colViewportRef : null}
            className="overflow-hidden"
            style={{ borderRight: colIdx === 0 ? "1px solid #0E1E30" : undefined }}
          >
            {groups.length === 0 ? (
              colIdx === 0 ? (
                <div className="flex h-full items-center justify-center text-xl text-[#1E3A5A]">
                  {emptyMessage ?? "Nenhuma OS em execução."}
                </div>
              ) : null
            ) : (
              <div className="px-6 pb-4">
                {groups.map(({ cliente, rows: clientRows }, groupIdx) => (
                  <div key={cliente} className={groupIdx === 0 ? "mt-3" : "mt-5"}>

                    {/* Client header */}
                    <div className="flex items-center gap-3 mb-0.5">
                      <div className="shrink-0 w-[3px] h-4 rounded-full bg-[#38BDF8]" />
                      <span className="text-sm font-bold uppercase tracking-widest text-[#38BDF8] shrink-0">
                        {cliente}
                      </span>
                      <div className="flex-1 h-px bg-[#0E1E30]" />
                    </div>

                    {/* OS rows */}
                    {clientRows.map((row, rowIdx) => {
                      const overdue = groupIsOverdue(row, today);
                      const isFirst = colIdx === 0 && groupIdx === 0 && rowIdx === 0;
                      const isEven = rowIdx % 2 === 0;

                      return (
                        <div
                          key={row.os_id}
                          ref={isFirst ? sampleRowRef : null}
                          className={`relative grid items-center min-h-[4rem] py-2 px-3 rounded transition-colors ${isPainelTv ? "" : "cursor-pointer group"}`}
                          style={{
                            gridTemplateColumns: "7rem 1fr 12rem",
                            gap: "1rem",
                            background: overdue
                              ? "rgba(239,68,68,0.07)"
                              : isEven
                              ? "transparent"
                              : "#080F1C",
                          }}
                          onClick={isPainelTv ? undefined : () => handleRowClick(row)}
                        >
                          {/* Barra vermelha para OS atrasada */}
                          {overdue && (
                            <div className="absolute left-0 top-2 bottom-2 w-[3px] rounded-full bg-[#EF4444]" />
                          )}

                          {/* Hover overlay */}
                          {!isPainelTv && (
                            <div className="absolute inset-0 rounded opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none bg-[#38BDF8]/[0.04]" />
                          )}

                          {/* Número OS */}
                          <div
                            className="text-5xl font-black tabular-nums leading-none tracking-tight"
                            style={{ color: overdue ? "#EF4444" : "#FFFFFF" }}
                          >
                            {row.numero_os}
                          </div>

                          {/* Descrição */}
                          <div
                            className="text-lg leading-snug line-clamp-2"
                            style={{ color: overdue ? "#FCA5A5" : "#7A9ABF" }}
                          >
                            {row.descricao_servico || "Sem descrição"}
                          </div>

                          {/* Badges ELE / MEC */}
                          <div className="flex items-center justify-end gap-2">
                            {row.executionItems.map((item) => {
                              const itemOverdue = isOverdue(item, today);
                              const isEle = item.area === "eletrico";
                              const style = itemOverdue
                                ? { background: "rgba(239,68,68,0.15)", color: "#FCA5A5", borderColor: "rgba(239,68,68,0.35)" }
                                : isEle
                                ? { background: "rgba(245,158,11,0.12)", color: "#FCD34D", borderColor: "rgba(245,158,11,0.3)" }
                                : { background: "rgba(56,189,248,0.12)", color: "#7DD3FC", borderColor: "rgba(56,189,248,0.3)" };

                              return (
                                <span
                                  key={`${row.os_id}-${item.area}`}
                                  className="inline-flex items-center justify-center rounded text-xs font-bold tracking-widest border"
                                  style={{ minWidth: "58px", padding: "5px 12px", ...style }}
                                >
                                  {executionLabel(item.area)}
                                </span>
                              );
                            })}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>

      {/* ── Modal de progresso (modo não-TV) ── */}
      {selected && !isPainelTv && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center p-4 backdrop-blur-sm bg-black/75"
          onClick={(e) => { if (e.target === e.currentTarget) closeModal(); }}
        >
          <div
            className="flex min-h-0 max-h-[calc(100dvh-2rem)] w-full max-w-xl flex-col overflow-hidden rounded-xl shadow-2xl bg-[#060C18] border border-[#12243A]"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex shrink-0 items-center justify-between gap-3 px-5 py-4 border-b border-[#12243A]">
              <div>
                <div className="text-lg font-semibold text-white">OS {selected.numero_os}</div>
                <div className="text-sm text-[#4A6A8A]">
                  {selected.cliente_nome} · {selected.executionItems.map((i) => executionLabel(i.area)).join(" / ")}
                </div>
              </div>
              <button
                type="button"
                onClick={closeModal}
                disabled={saving}
                className="rounded px-3 py-1.5 text-sm text-[#7A9ABF] bg-[#0B1525] border border-[#12243A]"
              >
                Fechar
              </button>
            </div>

            <div className="min-h-0 overflow-y-auto px-5 py-4 space-y-4 text-sm">
              <div>
                <div className="text-[10px] uppercase tracking-widest text-[#4A6A8A] mb-1">Descrição</div>
                <div className="text-[#CBD5E1] whitespace-pre-wrap">{selected.descricao_servico || "Sem descrição"}</div>
              </div>
              {selected.executionItems.map((item) => (
                <div key={`status-${item.area}`} className="space-y-1.5">
                  <div className="text-[10px] uppercase tracking-widest text-[#4A6A8A]">
                    Progresso — {executionLabel(item.area)}
                  </div>
                  <input
                    type="number"
                    min={0}
                    max={100}
                    value={progressValues[item.area] ?? ""}
                    onChange={(e) => setProgressValues((prev) => ({ ...prev, [item.area]: e.target.value }))}
                    disabled={saving}
                    className="w-full rounded px-3 py-2 text-white bg-[#0B1525] border border-[#12243A]"
                    placeholder="0 a 100%"
                  />
                </div>
              ))}
              {saveError && <div className="text-[#FCA5A5]">{saveError}</div>}
            </div>

            <div className="flex shrink-0 items-center justify-end gap-2 px-5 py-4 border-t border-[#12243A]">
              <button
                type="button"
                onClick={closeModal}
                disabled={saving}
                className="rounded px-4 py-2 text-sm text-[#7A9ABF] bg-[#0B1525] border border-[#12243A]"
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={handleSave}
                disabled={saving}
                className="rounded px-5 py-2 text-sm font-semibold bg-[#38BDF8] text-[#060C18]"
              >
                {saving ? "Salvando…" : "Salvar"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
