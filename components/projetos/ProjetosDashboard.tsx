"use client";

import Image from "next/image";
import { useEffect, useMemo, useState, type CSSProperties, type ReactNode, type ThHTMLAttributes } from "react";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { supabaseBrowser } from "@/lib/supabase/client";

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
  data_conclusao: string | null;
};

type Props = {
  initialRows: DashRow[];
  emptyMessage?: string;
};

type AreaPage = {
  area: Area;
  title: string;
  cardLabel: string;
  shortLabel: string;
  tableLabel: string;
  accent: string;
  progressColor: string;
  icon: "list" | "check" | "play" | "alert";
};

type DisplayRow = DashRow & {
  projectItems: DashRow[];
};

type SummaryKpi = {
  key: "projetos" | "concluidos" | "andamento" | "atrasado";
  label: string;
  value: number;
  detail: string;
  accent: string;
  icon: "list" | "check" | "play" | "alert";
  progressColor: string;
};

const PAGE_ROTATION_MS = 20_000;
const AREA_PAGES: AreaPage[] = [
  {
    area: "eletrico",
    title: "Projetos Eletricos",
    cardLabel: "Eletricos",
    shortLabel: "P.Ele",
    tableLabel: "Projeto Eletrico",
    accent: "text-amber-200",
    progressColor: "#fbbf24",
    icon: "list",
  },
  {
    area: "mecanico",
    title: "Projetos Mecanicos",
    cardLabel: "Mecanicos",
    shortLabel: "P.Mec",
    tableLabel: "Projeto Mecanico",
    accent: "text-sky-200",
    progressColor: "#7dd3fc",
    icon: "check",
  },
  {
    area: "software",
    title: "Automacao",
    cardLabel: "Automacao",
    shortLabel: "Auto",
    tableLabel: "Automacao",
    accent: "text-cyan-200",
    progressColor: "#67e8f9",
    icon: "play",
  },
  {
    area: "seguranca",
    title: "Seguranca",
    cardLabel: "Seguranca",
    shortLabel: "Seg",
    tableLabel: "Seguranca",
    accent: "text-emerald-200",
    progressColor: "#6ee7b7",
    icon: "alert",
  },
];

function areaPageFor(area: Area) {
  return AREA_PAGES.find((page) => page.area === area) ?? AREA_PAGES[0];
}

function areaOrder(area: Area) {
  const index = AREA_PAGES.findIndex((page) => page.area === area);
  return index === -1 ? AREA_PAGES.length : index;
}

function projectLabel(area: Area) {
  return areaPageFor(area).shortLabel;
}

function projectTitle(area: Area) {
  return areaPageFor(area).title;
}

function normalizeProgress(value: number | string | null | undefined) {
  return Math.max(0, Math.min(100, Math.trunc(Number(value ?? 0))));
}

function isHistoricalProjectRow(row: DashRow) {
  return row.habilitado || normalizeProgress(row.progresso_percent) >= 100;
}

function parseDateValue(value: string | null): number {
  if (!value) return Number.MAX_SAFE_INTEGER;
  const parsed = new Date(value).getTime();
  return Number.isNaN(parsed) ? Number.MAX_SAFE_INTEGER : parsed;
}

function parseDateYear(value: string | null) {
  const parsed = parseDateValue(value);
  if (parsed === Number.MAX_SAFE_INTEGER) return null;
  return new Date(parsed).getFullYear();
}

function formatDate(value: string | null) {
  if (!value) return "-";

  const [datePart] = value.split("T");
  const [year, month, day] = datePart.split("-");
  if (year && month && day) return `${day}/${month}/${year}`;

  return value;
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

function sortProjectRows(a: DashRow, b: DashRow, today: Date) {
  const overdueDelta = Number(isOverdue(b, today)) - Number(isOverdue(a, today));
  if (overdueDelta !== 0) return overdueDelta;

  const dateDelta = parseDateValue(a.data_prevista) - parseDateValue(b.data_prevista);
  if (dateDelta !== 0) return dateDelta;

  return a.numero_os.localeCompare(b.numero_os, "pt-BR", { numeric: true });
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
  const [selected, setSelected] = useState<DisplayRow | null>(null);
  const [progressValues, setProgressValues] = useState<Partial<Record<Area, string>>>({});
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [pageIndex, setPageIndex] = useState(0);

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

  const activePage = AREA_PAGES[pageIndex] ?? AREA_PAGES[0];
  const currentYear = today.getFullYear();
  const summaryKpis = useMemo<SummaryKpi[]>(() => {
    const baseRows = rows.filter(
      (row) =>
        row.item_tipo === "projeto" &&
        row.area === activePage.area &&
        isHistoricalProjectRow(row) &&
        row.status !== "cancelada"
    );
    const yearRows = baseRows.filter((row) => parseDateYear(row.data_conclusao) === currentYear);
    const concludedThisYear = yearRows.filter((row) => row.status === "concluida");
    const inProgress = baseRows.filter((row) => {
      const progress = Number(row.progresso_percent ?? 0);
      return row.status !== "concluida" && progress < 100;
    });
    const overdue = inProgress.filter((row) => isOverdue(row, today));

    return [
      {
        key: "projetos",
        label: "Projetos",
        value: concludedThisYear.length + inProgress.length,
        detail: "Concluidos + andamento",
        accent: "text-[color:var(--blue-info)]",
        icon: "list",
        progressColor: "#38bdf8",
      },
      {
        key: "concluidos",
        label: "Concluidos",
        value: concludedThisYear.length,
        detail: `Ano ${currentYear}`,
        accent: "text-emerald-200",
        icon: "check",
        progressColor: "#6ee7b7",
      },
      {
        key: "andamento",
        label: "Andamento",
        value: inProgress.length,
        detail: "Projetos ativos",
        accent: "text-sky-200",
        icon: "play",
        progressColor: "#7dd3fc",
      },
      {
        key: "atrasado",
        label: "Atrasado",
        value: overdue.length,
        detail: "Previsto vencido",
        accent: "text-[color:var(--red-danger)]",
        icon: "alert",
        progressColor: "#ef4444",
      },
    ];
  }, [activePage.area, currentYear, rows, today]);

  const projectItemsByOs = useMemo(() => {
    const grouped = new Map<number, DashRow[]>();

    for (const row of tableRows) {
      const current = grouped.get(row.os_id) ?? [];
      current.push(row);
      grouped.set(row.os_id, current);
    }

    for (const [osId, items] of grouped) {
      grouped.set(
        osId,
        [...items].sort((a, b) => areaOrder(a.area) - areaOrder(b.area))
      );
    }

    return grouped;
  }, [tableRows]);

  const activeRows = useMemo<DisplayRow[]>(
    () =>
      tableRows
        .filter((row) => row.area === activePage.area)
        .sort((a, b) => sortProjectRows(a, b, today))
        .map((row) => ({
          ...row,
          projectItems: projectItemsByOs.get(row.os_id) ?? [row],
        })),
    [activePage.area, projectItemsByOs, tableRows, today]
  );
  const activeOverdueCount = useMemo(() => activeRows.filter((row) => isOverdue(row, today)).length, [activeRows, today]);

  useEffect(() => {
    const id = window.setInterval(() => {
      setPageIndex((current) => (current + 1) % AREA_PAGES.length);
    }, PAGE_ROTATION_MS);

    return () => window.clearInterval(id);
  }, []);

  const handleRowClick = (row: DisplayRow) => {
    if (isPainelTv) return;
    setSelected(row);
    setProgressValues(
      row.projectItems.reduce<Partial<Record<Area, string>>>((acc, item) => {
        acc[item.area] = String(normalizeProgress(item.progresso_percent));
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

    if (!te.tenantId || !te.empresaId) {
      setSaveError("Tenant ou empresa nao definido.");
      return;
    }

    setSaving(true);
    setSaveError(null);

    const appliedUpdates: Array<{ area: Area; progressNum: number }> = [];

    for (const item of selected.projectItems) {
      const progressNum = normalizeProgress(progressValues[item.area] ?? item.progresso_percent);

      const { error } = await applyTenantEmpresa(
        supabase.from("os_gestao_itens").update({ progresso_percent: progressNum }),
        te.tenantId,
        te.empresaId
      )
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
  const pageLabel = `Pagina ${pageIndex + 1} de ${AREA_PAGES.length}`;

  return (
    <div className={`h-[calc(100dvh-3rem)] overflow-hidden ${rootClassName}`}>
      <div className="flex h-full flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        <header className="shrink-0 rounded-2xl shadow-[0_12px_30px_rgba(15,23,42,0.55)] bg-[color:var(--bg-banner)] text-[color:var(--text-banner)]">
          <div className="flex items-center justify-between gap-4 px-6 py-4">
            <div>
              <h1 className="text-2xl font-bold tracking-tight">{activePage.title}</h1>
              <div className="mt-1 text-xs opacity-70">Rotacao automatica entre areas a cada 20s</div>
            </div>
            <div className="flex items-center gap-4">
              <div className="hidden text-right text-xs text-[color:var(--text-banner)]/75 md:block">
                <div>{pageLabel}</div>
                <div>{activeRows.length} OS em andamento</div>
              </div>
              <div className="relative h-14 w-40">
                <Image src="/Segau2.png" alt="Segau" fill className="object-contain" />
              </div>
            </div>
          </div>
        </header>

        <div className="grid shrink-0 grid-cols-2 gap-4 xl:grid-cols-4">
          {summaryKpis.map((kpi) => (
            <KpiCard key={kpi.key} kpi={kpi} />
          ))}
        </div>

        <div className="min-h-0 flex flex-1 flex-col overflow-hidden rounded-2xl border border-white/10 bg-[color:var(--bg-card)] shadow-[0_16px_40px_rgba(15,23,42,0.55)]">
          <div className="shrink-0 flex items-center justify-between border-b border-white/10 px-4 py-3 text-sm text-[color:var(--text-muted)]">
            <div>{activePage.tableLabel}</div>
            <div>
              {pageLabel} | {activeOverdueCount} atrasadas
            </div>
          </div>

          <div className="min-h-0 flex-1 overflow-y-auto">
            <table className="w-full table-fixed text-base">
              <thead className="sticky top-0 z-10 bg-[color:var(--bg-card)]">
                <tr className="text-left">
                  <Th className="w-[110px]">OS</Th>
                  <Th className="w-[240px]">Cliente</Th>
                  <Th>Descricao</Th>
                  <Th className="w-[140px] text-right">Previsto</Th>
                  <Th className="w-[190px] text-right">Progresso</Th>
                </tr>
              </thead>
              <tbody>
                {activeRows.map((row, idx) => {
                  const overdue = isOverdue(row, today);
                  const progress = normalizeProgress(row.progresso_percent);
                  const zebra = idx % 2 === 0 ? "bg-[color:var(--bg-card)]" : "bg-white/[0.02]";
                  const rowClassName = overdue ? "bg-[color:var(--red-danger)]/6" : zebra;
                  const progressStyle = {
                    "--progress-color": overdue ? "var(--red-danger)" : activePage.progressColor,
                  } as CSSProperties;

                  return (
                    <tr
                      key={`${row.os_id}-${row.area}`}
                      className={`h-[69px] border-t border-white/5 transition-colors ${rowClassName} ${
                        isPainelTv ? "" : "cursor-pointer hover:bg-[color:var(--bg-hover)]"
                      }`}
                      onClick={isPainelTv ? undefined : () => handleRowClick(row)}
                    >
                      <Td className="w-[110px] whitespace-nowrap font-semibold">{row.numero_os}</Td>
                      <Td className="w-[240px] truncate">{row.cliente_nome || "-"}</Td>
                      <Td className="truncate">{row.descricao_servico || "Sem descricao"}</Td>
                      <Td className="w-[140px] whitespace-nowrap text-right tabular-nums">{formatDate(row.data_prevista)}</Td>
                      <Td className="w-[190px] text-right">
                        <div className="flex items-center justify-end gap-3">
                          <span
                            className={`w-12 shrink-0 tabular-nums ${
                              overdue ? "text-[color:var(--red-danger)]" : "text-[color:var(--text-main)]"
                            }`}
                          >
                            {progress}%
                          </span>
                          <progress
                            aria-label={`Progresso ${projectLabel(row.area)}`}
                            className="progress-bar h-2 w-24 shrink-0"
                            max={100}
                            value={progress}
                            style={progressStyle}
                          />
                        </div>
                      </Td>
                    </tr>
                  );
                })}

                {activeRows.length === 0 && (
                  <tr>
                    <Td colSpan={5} className="py-8 text-center text-zinc-400">
                      {tableRows.length === 0 ? emptyMessage ?? "Nenhum projeto em aberto." : `Nenhum ${activePage.tableLabel.toLowerCase()} em aberto.`}
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
                  {selected.cliente_nome} | {selected.projectItems.map((item) => projectTitle(item.area)).join(" / ")}
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

function KpiCard({ kpi }: { kpi: SummaryKpi }) {
  const progressStyle = {
    backgroundColor: kpi.progressColor,
  } as CSSProperties;

  return (
    <div className="relative min-h-[116px] overflow-hidden rounded-2xl border border-white/10 bg-[color:var(--bg-card)] p-5 text-left shadow-[0_14px_34px_rgba(15,23,42,0.55)]">
      <div className="absolute right-4 top-4 opacity-70">
        <Icon kind={kpi.icon} className={kpi.accent} />
      </div>

      <div className="text-xs uppercase tracking-wide text-[color:var(--text-muted)]">{kpi.label}</div>
      <div className={`mt-2 text-4xl font-semibold ${kpi.accent}`}>{kpi.value}</div>
      <div className="mt-3 flex items-center justify-between gap-3 text-xs text-[color:var(--text-muted)]">
        <span>{kpi.detail}</span>
      </div>
      <div className="mt-3 h-1 w-full overflow-hidden rounded-full bg-slate-900/30">
        <div className="h-1 w-1/3 opacity-45" style={progressStyle} />
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
