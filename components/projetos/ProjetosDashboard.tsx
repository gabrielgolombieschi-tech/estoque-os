"use client";

import Image from "next/image";
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode, type ThHTMLAttributes } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/hooks";

type Area = "eletrico" | "mecanico" | "seguranca" | "software";

type DashRow = {
  os_id: number;
  item_tipo: "projeto";
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
  projectItems: DashRow[];
};

const DEFAULT_ROW_HEIGHT = 69;
const PAGE_ROTATION_MS = 20_000;
const AREA_ORDER: Record<Area, number> = {
  eletrico: 0,
  mecanico: 1,
  seguranca: 2,
  software: 3,
};

function projectLabel(area: Area) {
  if (area === "eletrico") return "P.Ele";
  if (area === "mecanico") return "P.Mec";
  if (area === "seguranca") return "Seg";
  return "Soft";
}

function projectBadgeClass(area: Area, overdue: boolean) {
  if (overdue) {
    return "border border-[color:var(--red-danger)]/40 bg-[color:var(--red-danger)]/18 text-[color:var(--red-danger)]";
  }

  if (area === "eletrico") {
    return "border border-amber-400/30 bg-amber-400/12 text-amber-200";
  }

  if (area === "mecanico") {
    return "border border-sky-400/30 bg-sky-400/12 text-sky-200";
  }

  if (area === "seguranca") {
    return "border border-emerald-400/30 bg-emerald-400/12 text-emerald-200";
  }

  return "border border-slate-400/30 bg-slate-400/12 text-slate-200";
}

function parseDateValue(value: string | null): number {
  if (!value) return Number.MAX_SAFE_INTEGER;
  const parsed = new Date(value).getTime();
  return Number.isNaN(parsed) ? Number.MAX_SAFE_INTEGER : parsed;
}

function Icon({ kind, className = "" }: { kind: "list" | "check" | "play" | "alert"; className?: string }) {
  const common = "w-5 h-5";
  if (kind === "check") {
    return (
      <svg viewBox="0 0 24 24" fill="none" className={`${common} ${className}`} aria-hidden="true">
        <path d="M20 6L9 17l-5-5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    );
  }
  if (kind === "play") {
    return (
      <svg viewBox="0 0 24 24" fill="none" className={`${common} ${className}`} aria-hidden="true">
        <path d="M8 5v14l11-7-11-7z" fill="currentColor" opacity="0.9" />
      </svg>
    );
  }
  if (kind === "alert") {
    return (
      <svg viewBox="0 0 24 24" fill="none" className={`${common} ${className}`} aria-hidden="true">
        <path
          d="M12 9v4m0 4h.01M10.29 3.86l-8.4 14.53A2 2 0 003.62 21h16.76a2 2 0 001.73-3.01l-8.4-14.53a2 2 0 00-3.42 0z"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 24 24" fill="none" className={`${common} ${className}`} aria-hidden="true">
      <path d="M4 6h16M4 12h16M4 18h16" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}

function isOverdue(row: DashRow, today: Date) {
  const progress = Number(row.progresso_percent ?? 0);
  const date = row.data_prevista ? new Date(row.data_prevista) : null;
  if (!date || Number.isNaN(date.getTime())) return false;
  return progress < 100 && date < today;
}

function groupIsOverdue(row: GroupedRow, today: Date) {
  return row.projectItems.some((item) => isOverdue(item, today));
}

function groupSortDate(row: GroupedRow) {
  return row.projectItems.reduce((earliest, item) => Math.min(earliest, parseDateValue(item.data_prevista)), Number.MAX_SAFE_INTEGER);
}

export default function ProjetosDashboard({ initialRows, emptyMessage }: Props) {
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
  const [rowsPerPage, setRowsPerPage] = useState(8);
  const [pageIndex, setPageIndex] = useState(0);
  const tableViewportRef = useRef<HTMLDivElement | null>(null);
  const tableHeadRef = useRef<HTMLTableSectionElement | null>(null);
  const sampleRowRef = useRef<HTMLTableRowElement | null>(null);

  useEffect(() => {
    setRows(initialRows);
  }, [initialRows]);

  const today = useMemo(() => {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    return d;
  }, []);

  const tableRows = useMemo(
    () =>
      rows.filter((row) => {
        const progress = Number(row.progresso_percent ?? 0);
        return (
          row.habilitado &&
          row.item_tipo === "projeto" &&
          (row.area === "eletrico" || row.area === "mecanico" || row.area === "seguranca" || row.area === "software") &&
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
      if (current) {
        current.projectItems.push(row);
        continue;
      }

      grouped.set(row.os_id, {
        os_id: row.os_id,
        numero_os: row.numero_os,
        cliente_nome: row.cliente_nome,
        descricao_servico: row.descricao_servico,
        status: row.status,
        projectItems: [row],
      });
    }

    return Array.from(grouped.values())
      .map((row) => ({
        ...row,
        projectItems: [...row.projectItems].sort((a, b) => AREA_ORDER[a.area] - AREA_ORDER[b.area]),
      }))
      .sort((a, b) => {
        const overdueDelta = Number(groupIsOverdue(b, today)) - Number(groupIsOverdue(a, today));
        if (overdueDelta !== 0) return overdueDelta;

        const dateDelta = groupSortDate(a) - groupSortDate(b);
        if (dateDelta !== 0) return dateDelta;

        return a.numero_os.localeCompare(b.numero_os, "pt-BR", { numeric: true });
      });
  }, [tableRows, today]);

  const kpis = useMemo(() => {
    const emAndamento = groupedTable.length;
    const projetosEletricos = tableRows.filter((row) => row.area === "eletrico").length;
    const projetosMecanicos = tableRows.filter((row) => row.area === "mecanico").length;
    const seguranca = tableRows.filter((row) => row.area === "seguranca").length;
    const software = tableRows.filter((row) => row.area === "software").length;
    const atrasadas = groupedTable.filter((row) => groupIsOverdue(row, today)).length;
    return { emAndamento, projetosEletricos, projetosMecanicos, seguranca, software, atrasadas };
  }, [groupedTable, tableRows, today]);

  const recomputeRowsPerPage = useCallback(() => {
    const viewportHeight = tableViewportRef.current?.clientHeight ?? 0;
    if (viewportHeight <= 0) return;

    const headerHeight = tableHeadRef.current?.getBoundingClientRect().height ?? 0;
    const rowHeight = sampleRowRef.current?.getBoundingClientRect().height ?? DEFAULT_ROW_HEIGHT;
    const availableHeight = Math.max(viewportHeight - headerHeight, rowHeight);
    const nextRowsPerPage = Math.max(1, Math.floor(availableHeight / rowHeight));

    setRowsPerPage((current) => (current === nextRowsPerPage ? current : nextRowsPerPage));
  }, []);

  useEffect(() => {
    recomputeRowsPerPage();
  }, [recomputeRowsPerPage, groupedTable.length, pageIndex]);

  useEffect(() => {
    const observer = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(() => recomputeRowsPerPage());

    if (tableViewportRef.current) observer?.observe(tableViewportRef.current);
    if (tableHeadRef.current) observer?.observe(tableHeadRef.current);
    if (sampleRowRef.current) observer?.observe(sampleRowRef.current);

    window.addEventListener("resize", recomputeRowsPerPage);

    return () => {
      observer?.disconnect();
      window.removeEventListener("resize", recomputeRowsPerPage);
    };
  }, [recomputeRowsPerPage, groupedTable.length, pageIndex]);

  const totalPages = useMemo(() => {
    if (groupedTable.length === 0) return 1;
    return Math.max(1, Math.ceil(groupedTable.length / rowsPerPage));
  }, [groupedTable.length, rowsPerPage]);

  useEffect(() => {
    setPageIndex((current) => (current >= totalPages ? 0 : current));
  }, [totalPages]);

  useEffect(() => {
    if (totalPages <= 1) {
      setPageIndex(0);
      return;
    }

    const id = window.setInterval(() => {
      setPageIndex((current) => (current + 1) % totalPages);
    }, PAGE_ROTATION_MS);

    return () => window.clearInterval(id);
  }, [totalPages]);

  const pageRows = useMemo(() => {
    const start = pageIndex * rowsPerPage;
    return groupedTable.slice(start, start + rowsPerPage);
  }, [groupedTable, pageIndex, rowsPerPage]);

  const handleRowClick = (row: GroupedRow) => {
    if (isPainelTv) return;
    setSelected(row);
    setProgressValues(
      row.projectItems.reduce<Partial<Record<Area, string>>>((acc, item) => {
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
    if (!selected) return;
    if (isPainelTv) return;
    setSaving(true);
    setSaveError(null);

    const appliedUpdates: Array<{ area: Area; progressNum: number }> = [];

    for (const item of selected.projectItems) {
      const progressNum = Math.max(0, Math.min(100, Math.trunc(Number(progressValues[item.area] ?? item.progresso_percent ?? 0))));

      const { error } = await supabase
        .from("os_gestao_itens")
        .update({ progresso_percent: progressNum })
        .eq("os_id", item.os_id)
        .eq("item_tipo", item.item_tipo)
        .eq("area", item.area);

      if (error) {
        if (appliedUpdates.length > 0) {
          const appliedMap = new Map(appliedUpdates.map((update) => [update.area, update.progressNum]));

          setRows((prev) =>
            prev.map((row) =>
              row.os_id === selected.os_id && appliedMap.has(row.area)
                ? { ...row, progresso_percent: appliedMap.get(row.area) ?? row.progresso_percent }
                : row
            )
          );
        }

        setSaving(false);
        setSaveError(error.message);
        return;
      }

      appliedUpdates.push({ area: item.area, progressNum });
    }

    const appliedMap = new Map(appliedUpdates.map((update) => [update.area, update.progressNum]));

    setRows((prev) =>
      prev.map((row) =>
        row.os_id === selected.os_id && appliedMap.has(row.area)
          ? { ...row, progresso_percent: appliedMap.get(row.area) ?? row.progresso_percent }
          : row
      )
    );

    setSaving(false);
    setSelected(null);
    setProgressValues({});
  };

  const rootClassName = isPainelTv ? "tv-mode" : "";
  const pageLabel = totalPages > 1 ? `Pagina ${pageIndex + 1} de ${totalPages}` : "Pagina unica";

  return (
    <div className={`h-[calc(100dvh-3rem)] overflow-hidden ${rootClassName}`}>
      <div className="flex h-full flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        <header className="shrink-0 rounded-2xl shadow-[0_12px_30px_rgba(15,23,42,0.55)] bg-[color:var(--bg-banner)] text-[color:var(--text-banner)]">
          <div className="flex items-center justify-between gap-4 px-6 py-4">
            <div>
              <h1 className="text-2xl font-bold tracking-tight">Projetos</h1>
              <div className="mt-1 text-xs opacity-70">Rotacao automatica de paginas a cada 20s</div>
            </div>
            <div className="flex items-center gap-4">
              <div className="hidden text-right text-xs text-[color:var(--text-banner)]/75 md:block">
                <div>{pageLabel}</div>
                <div>{groupedTable.length} OS em andamento</div>
              </div>
              <div className="relative h-14 w-40">
                <Image src="/Segau2.png" alt="Segau" fill className="object-contain" />
              </div>
            </div>
          </div>
        </header>

        <div className="grid shrink-0 grid-cols-2 gap-4 lg:grid-cols-3 2xl:grid-cols-6">
          <KpiCard label="Em andamento" value={kpis.emAndamento} icon="play" accent="text-[color:var(--blue-info)]" />
          <KpiCard label="P.Ele" value={kpis.projetosEletricos} icon="list" accent="text-amber-200" />
          <KpiCard label="P.Mec" value={kpis.projetosMecanicos} icon="check" accent="text-sky-200" />
          <KpiCard label="Seg" value={kpis.seguranca} icon="check" accent="text-emerald-200" />
          <KpiCard label="Soft" value={kpis.software} icon="list" accent="text-slate-200" />
          <KpiCard label="Atrasadas" value={kpis.atrasadas} icon="alert" accent="text-[color:var(--red-danger)]" />
        </div>

        <div className="min-h-0 flex flex-1 flex-col overflow-hidden rounded-2xl border border-white/10 bg-[color:var(--bg-card)] shadow-[0_16px_40px_rgba(15,23,42,0.55)]">
          <div className="shrink-0 flex items-center justify-between border-b border-white/10 px-4 py-3 text-sm text-[color:var(--text-muted)]">
            <div>Quadro de projetos sem rolagem</div>
            <div>{pageLabel}</div>
          </div>

          <div ref={tableViewportRef} className="min-h-0 flex-1 overflow-hidden">
            <table className="w-full table-fixed text-base">
              <thead ref={tableHeadRef} className="bg-[color:var(--bg-card)]">
                <tr className="text-left">
                  <Th className="w-[110px]">OS</Th>
                  <Th className="w-[240px]">Cliente</Th>
                  <Th>Descricao</Th>
                  <Th className="w-[280px] text-center">Projetos</Th>
                </tr>
              </thead>
              <tbody>
                {pageRows.map((row, idx) => {
                  const overdue = groupIsOverdue(row, today);
                  const zebra = idx % 2 === 0 ? "bg-[color:var(--bg-card)]" : "bg-white/[0.02]";
                  const rowClassName = overdue ? "bg-[color:var(--red-danger)]/6" : zebra;
                  return (
                    <tr
                      key={`${row.os_id}-${idx}`}
                      ref={idx === 0 ? sampleRowRef : null}
                      className={`h-[69px] border-t border-white/5 transition-colors ${rowClassName} ${
                        isPainelTv ? "" : "cursor-pointer hover:bg-[color:var(--bg-hover)]"
                      }`}
                      onClick={isPainelTv ? undefined : () => handleRowClick(row)}
                    >
                      <Td className="w-[110px] whitespace-nowrap font-semibold">{row.numero_os}</Td>
                      <Td className="w-[240px] truncate">{row.cliente_nome || "-"}</Td>
                      <Td className="truncate">{row.descricao_servico || "Sem descricao"}</Td>
                      <Td className="w-[280px] text-center">
                        <div className="flex items-center justify-center gap-1.5">
                          {row.projectItems.map((item) => {
                            const itemOverdue = isOverdue(item, today);

                            return (
                              <span
                                key={`${row.os_id}-${item.area}`}
                                className={`inline-flex min-w-[60px] items-center justify-center rounded-full px-2.5 py-1 text-xs font-semibold tracking-[0.08em] ${projectBadgeClass(item.area, itemOverdue)}`}
                              >
                                {projectLabel(item.area)}
                              </span>
                            );
                          })}
                        </div>
                      </Td>
                    </tr>
                  );
                })}

                {pageRows.length === 0 && (
                  <tr>
                    <Td colSpan={4} className="py-8 text-center text-zinc-400">
                      {emptyMessage ?? "Nenhum projeto em aberto."}
                    </Td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {selected && !isPainelTv && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm"
          onClick={(e) => {
            if (e.target === e.currentTarget) closeModal();
          }}
        >
          <div
            className="flex min-h-0 max-h-[calc(100dvh-2rem)] w-full max-w-xl flex-col overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex shrink-0 items-center justify-between gap-3 border-b border-zinc-800 px-5 py-4">
              <div>
                <div className="text-lg font-semibold text-zinc-100">Atualizar status da OS {selected.numero_os}</div>
                <div className="text-sm text-zinc-400">
                  {selected.cliente_nome} | {selected.projectItems.map((item) => projectLabel(item.area)).join(" / ")}
                </div>
              </div>
              <button
                onClick={closeModal}
                className="rounded-md border border-zinc-700 bg-zinc-900 px-3 py-1.5 text-sm hover:bg-zinc-800"
                disabled={saving}
              >
                Fechar
              </button>
            </div>

            <div className="min-h-0 overflow-y-auto px-5 py-4">
              <div className="space-y-2 text-sm">
                <div>
                  <div className="text-[11px] uppercase text-zinc-400">Descricao</div>
                  <div className="whitespace-pre-wrap text-zinc-100">{selected.descricao_servico || "Sem descricao"}</div>
                </div>

                {selected.projectItems.map((item) => (
                  <div key={`status-${item.area}`} className="space-y-1">
                    <div className="text-[11px] uppercase text-zinc-400">Status - {projectLabel(item.area)}</div>
                    <input
                      type="number"
                      min={0}
                      max={100}
                      value={progressValues[item.area] ?? ""}
                      onChange={(e) =>
                        setProgressValues((prev) => ({
                          ...prev,
                          [item.area]: e.target.value,
                        }))
                      }
                      disabled={saving}
                      className="w-full rounded-md border border-zinc-800 bg-zinc-900 px-3 py-2 text-zinc-100"
                      placeholder="0 a 100%"
                    />
                  </div>
                ))}

                {saveError && <div className="text-sm text-red-400">{saveError}</div>}
              </div>
            </div>

            <div className="flex shrink-0 items-center justify-end gap-2 border-t border-zinc-800 px-5 py-4">
              <button
                onClick={closeModal}
                className="rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 hover:bg-zinc-800"
                disabled={saving}
              >
                Cancelar
              </button>
              <button
                onClick={handleSave}
                disabled={saving}
                className="rounded-md bg-emerald-300 px-4 py-2 font-medium text-emerald-950 hover:bg-emerald-200"
              >
                {saving ? "Salvando..." : "Salvar"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function KpiCard({
  label,
  value,
  accent,
  icon,
}: {
  label: string;
  value: number;
  accent?: string;
  icon: "list" | "check" | "play" | "alert";
}) {
  return (
    <div className="relative overflow-hidden rounded-2xl border border-white/10 bg-[color:var(--bg-card)] p-5 shadow-[0_14px_34px_rgba(15,23,42,0.55)]">
      <div className="absolute right-4 top-4 opacity-70">
        <Icon kind={icon} className={`${accent ?? "text-[color:var(--text-muted)]"}`} />
      </div>

      <div className="text-xs uppercase tracking-wide text-[color:var(--text-muted)]">{label}</div>
      <div className={`mt-2 text-4xl font-semibold ${accent ?? "text-[color:var(--text-main)]"}`}>{value}</div>
      <div className="mt-4 h-1 w-full overflow-hidden rounded-full bg-slate-900/30">
        <div className={`h-1 w-1/3 ${accent ?? "bg-[color:var(--blue-info)]"} opacity-35`} />
      </div>
    </div>
  );
}

type ThProps = ThHTMLAttributes<HTMLTableCellElement> & { children: ReactNode };

function Th({ children, className = "", ...rest }: ThProps) {
  return (
    <th
      {...rest}
      className={`px-4 py-4 text-sm font-semibold text-[color:var(--text-main)] bg-[color:var(--bg-card)] ${className}`}
    >
      {children}
    </th>
  );
}

function Td({
  children,
  className,
  colSpan,
}: {
  children: ReactNode;
  className?: string;
  colSpan?: number;
}) {
  return (
    <td className={`px-4 py-4 text-[color:var(--text-main)] ${className ?? ""}`} colSpan={colSpan}>
      {children}
    </td>
  );
}
