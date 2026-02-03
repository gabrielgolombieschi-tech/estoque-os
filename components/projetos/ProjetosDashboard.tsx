"use client";

import Image from "next/image";
import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/hooks";

type Area = "eletrico" | "mecanico" | "seguranca" | "software";

type DashRow = {
  os_id: number;
  item_tipo: "projeto";
  area: Area;
  habilitado: boolean;
  responsavel_id: string | null;
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

type SortDir = "asc" | "desc";

const formatPercent = (v: number) =>
  `${(Number(v || 0)).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}%`;

function firstWord(value: string | null | undefined): string {
  const s = String(value ?? "").trim();
  if (!s) return "-";
  return s.split(/\s+/)[0] ?? "-";
}

function isOverdue(row: DashRow, today: Date) {
  const progress = Number(row.progresso_percent ?? 0);
  const date = row.data_prevista ? new Date(row.data_prevista) : null;
  return progress < 100 && !!date && date < today;
}

function clampPercent(v: unknown): number {
  const n = Number(v ?? 0);
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.min(100, n));
}

function resolveProgressColor(opts: { overdue: boolean; percent: number }) {
  if (opts.overdue) return "progress-bar--danger";
  if (opts.percent >= 100) return "progress-bar--ok";
  if (opts.percent === 0) return "progress-bar--muted";
  return "progress-bar--info";
}

function Icon({ kind, className = "" }: { kind: "list" | "check" | "play" | "alert"; className?: string }) {
  const common = "w-5 h-5";
  if (kind === "check") {
    return (
      <svg viewBox="0 0 24 24" fill="none" className={`${common} ${className}`} aria-hidden="true">
        <path
          d="M20 6L9 17l-5-5"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    );
  }
  if (kind === "play") {
    return (
      <svg viewBox="0 0 24 24" fill="none" className={`${common} ${className}`} aria-hidden="true">
        <path
          d="M8 5v14l11-7-11-7z"
          fill="currentColor"
          opacity="0.9"
        />
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
      <path
        d="M4 6h16M4 12h16M4 18h16"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
      />
    </svg>
  );
}

export default function ProjetosDashboard({ initialRows, emptyMessage }: Props) {
  const te = useTenantEmpresa();
  const areaOrder: Area[] = ["eletrico", "seguranca", "mecanico", "software"];
  const [areaIndex, setAreaIndex] = useState(0);
  const [sortDir, setSortDir] = useState<SortDir>("asc");
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const isPainelTv = useMemo(() => {
    const papel = te.empresa?.papel;
    return typeof papel === "string" && papel.trim().toUpperCase() === "PAINEL_TV";
  }, [te.empresa?.papel]);
  const [rows, setRows] = useState<DashRow[]>(initialRows);
  const [selected, setSelected] = useState<DashRow | null>(null);
  const [progressValue, setProgressValue] = useState<string>("0");
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  useEffect(() => {
    setRows(initialRows);
  }, [initialRows]);

  const today = useMemo(() => {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    return d;
  }, []);

  useEffect(() => {
    const id = setInterval(() => {
      setAreaIndex((prev) => (prev + 1) % areaOrder.length);
    }, 30000);
    return () => clearInterval(id);
  }, [areaOrder.length]);

  const areaAtual = areaOrder[areaIndex % areaOrder.length];

  const rowsBase = useMemo(() => rows.filter((r) => r.habilitado && r.area === areaAtual && r.item_tipo === "projeto"), [areaAtual, rows]);

  const anoVigente = today.getFullYear();

  const tableRows = useMemo(
    () => rowsBase.filter((r) => Number(r.progresso_percent ?? 0) < 100),
    [rowsBase]
  );

  const sortedTable = useMemo(() => {
    return [...tableRows].sort((a, b) => {
      const da = a.data_prevista ? new Date(a.data_prevista).getTime() : null;
      const db = b.data_prevista ? new Date(b.data_prevista).getTime() : null;
      if (da === null && db === null) return 0;
      if (da === null) return 1;
      if (db === null) return -1;
      return sortDir === "asc" ? da - db : db - da;
    });
  }, [tableRows, sortDir]);

  const rowsConcluidosAno = useMemo(
    () =>
      rowsBase.filter((r) => {
        if (!r.data_prevista) return false;
        const year = new Date(r.data_prevista).getFullYear();
        return Number(r.progresso_percent ?? 0) === 100 && year === anoVigente;
      }),
    [rowsBase, anoVigente]
  );

  const kpis = useMemo(() => {
    const total = rowsBase.length;
    const concluidos = rowsConcluidosAno.length;
    const andamento = rowsBase.filter((r) => {
      const p = Number(r.progresso_percent ?? 0);
      return p > 0 && p < 100;
    }).length;
    const atrasados = rowsBase.filter((r) => isOverdue(r, today)).length;
    return { total, concluidos, andamento, atrasados };
  }, [rowsBase, rowsConcluidosAno.length, today]);

  const toggleSort = () => setSortDir((d) => (d === "asc" ? "desc" : "asc"));

  const areaLabel: Record<Area, string> = {
    eletrico: "Eletricos",
    seguranca: "Seguranca",
    mecanico: "Mecanicos",
    software: "Software",
  };

  const handleRowClick = (row: DashRow) => {
    setSelected(row);
    setProgressValue(String(Math.max(0, Math.min(100, Math.trunc(Number(row.progresso_percent ?? 0))))));
    setSaveError(null);
  };

  const closeModal = () => {
    if (saving) return;
    setSelected(null);
    setSaveError(null);
  };

  const handleSave = async () => {
    if (!selected) return;
    if (isPainelTv) return;
    setSaving(true);
    setSaveError(null);

    const progressNum = Math.max(0, Math.min(100, Math.trunc(Number(progressValue))));

    const { error } = await supabase
      .from("os_gestao_itens")
      .update({ progresso_percent: progressNum })
      .eq("os_id", selected.os_id)
      .eq("item_tipo", selected.item_tipo)
      .eq("area", selected.area);

    setSaving(false);

    if (error) {
      setSaveError(error.message);
      return;
    }

    setRows((prev) =>
      prev.map((r) =>
        r.os_id === selected.os_id && r.area === selected.area && r.item_tipo === selected.item_tipo
          ? { ...r, progresso_percent: progressNum }
          : r
      )
    );
    setSelected(null);
  };

  const rootClassName = isPainelTv ? "tv-mode" : "";
  const tableWrapClass = isPainelTv ? "overflow-x-hidden" : "overflow-x-auto";

  return (
    <div className={`space-y-5 ${rootClassName}`}>
      <header className="rounded-2xl shadow-[0_12px_30px_rgba(15,23,42,0.55)] bg-[color:var(--bg-banner)] text-[color:var(--text-banner)]">
        <div className="flex items-center justify-between px-6 py-4">
          <div>
            <h1 className="text-2xl font-bold tracking-tight">Projetos {areaLabel[areaAtual]}</h1>
            <div className="text-xs opacity-70 mt-1">Alternando area a cada 30s</div>
          </div>
          <div className="relative w-40 h-14">
            <Image src="/Segau2.png" alt="Segau" fill className="object-contain" />
          </div>
        </div>
      </header>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <KpiCard label="Quantidade Projetos" value={kpis.total} icon="list" accent="text-purple-300" />
        <KpiCard label="Projetos Concluídos" value={kpis.concluidos} icon="check" accent="text-[color:var(--green-ok)]" />
        <KpiCard label="Em andamento" value={kpis.andamento} icon="play" accent="text-[color:var(--blue-info)]" />
        <KpiCard label="Atrasados" value={kpis.atrasados} icon="alert" accent="text-[color:var(--red-danger)]" />
      </div>

      <div className="rounded-2xl overflow-hidden bg-[color:var(--bg-card)] border border-white/10 shadow-[0_16px_40px_rgba(15,23,42,0.55)]">
        <div className={`${tableWrapClass} overflow-y-auto max-h-[calc(100dvh-320px)]`}> 
          <table className="w-full table-fixed text-base">
            <thead className="bg-[color:var(--bg-card)]">
              <tr className="text-left sticky top-0 z-10">
                <Th>OS</Th>
                <Th>Cliente</Th>
                <Th>Descricao</Th>
                <Th>Responsavel</Th>
                <Th onClick={toggleSort} className="cursor-pointer select-none">
                  Data de entrega {sortDir === "asc" ? "(asc)" : "(desc)"}
                </Th>
                <Th className="text-right pr-4">Progresso</Th>
              </tr>
            </thead>
            <tbody>
              {sortedTable.map((r, idx) => {
                const overdue = isOverdue(r, today);
                const dateBg = overdue
                  ? "bg-[color:var(--red-danger)]/30 text-[color:var(--text-main)]"
                  : "bg-[color:var(--green-ok)]/12 text-[color:var(--text-main)]";
                const dateCell =
                  r.data_prevista && !Number.isNaN(new Date(r.data_prevista).getTime())
                    ? new Date(r.data_prevista).toLocaleDateString("pt-BR")
                    : "-";
                const percent = clampPercent(r.progresso_percent);
                const barColor = resolveProgressColor({ overdue, percent });
                const zebra = idx % 2 === 0 ? "bg-[color:var(--bg-card)]" : "";
                return (
                  <tr
                    key={`${r.os_id}-${r.area}-${r.item_tipo}-${idx}`}
                    className={`transition-all duration-200 ${overdue ? "overdue-row overdue-blink" : zebra} ${isPainelTv ? "" : "hover:bg-[color:var(--bg-hover)] cursor-pointer"}`}
                    onClick={() => handleRowClick(r)}
                  >
                    <Td className="w-[90px] whitespace-nowrap">{r.numero_os}</Td>
                    <Td className="w-[210px] truncate">{firstWord(r.cliente_nome)}</Td>
                    <Td className="truncate">{r.descricao_servico || "Sem descricao"}</Td>
                    <Td className="w-[160px] truncate">{r.responsavel_id || "-"}</Td>
                    <Td className={`w-[170px] whitespace-nowrap ${r.data_prevista ? dateBg : ""}`}>{dateCell}</Td>
                    <Td className="w-[240px] pr-4">
                      <div className="flex items-center justify-end gap-3">
                        <progress
                          className={`progress-bar w-[140px] h-3 ${barColor}`}
                          value={percent}
                          max={100}
                          aria-label="Progresso"
                        />
                        <div className="text-right tabular-nums text-sm text-[color:var(--text-muted)] min-w-[64px]">
                          {formatPercent(percent)}
                        </div>
                      </div>
                    </Td>
                  </tr>
                );
              })}

              {sortedTable.length === 0 && (
                <tr>
                  <Td colSpan={6} className="text-center py-6 text-zinc-400">
                    {emptyMessage ?? "Nenhum registro para os filtros selecionados."}
                  </Td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {selected && (
        <div
          className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50"
          onClick={(e) => {
            if (e.target === e.currentTarget) closeModal();
          }}
        >
          <div
            className="w-full max-w-xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl flex flex-col max-h-[calc(100dvh-2rem)] min-h-0 overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between gap-3 shrink-0">
              <div>
                <div className="text-lg font-semibold text-zinc-100">Atualizar status da OS {selected.numero_os}</div>
                <div className="text-sm text-zinc-400">
                  {selected.cliente_nome} • {selected.area.toUpperCase()}
                </div>
              </div>
              <button
                onClick={closeModal}
                className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
                disabled={saving}
              >
                Fechar
              </button>
            </div>

            <div className="px-5 py-4 overflow-y-auto min-h-0">
              <div className="space-y-2 text-sm">
                <div>
                  <div className="text-zinc-400 uppercase text-[11px]">Descrição</div>
                  <div className="text-zinc-100 whitespace-pre-wrap">{selected.descricao_servico || "Sem descrição"}</div>
                </div>

                <div className="space-y-1">
                  <div className="text-zinc-400 uppercase text-[11px]">Status - {selected.area.toUpperCase()}</div>
                  <input
                    type="number"
                    min={0}
                    max={100}
                    value={progressValue}
                    onChange={(e) => setProgressValue(e.target.value)}
                    disabled={saving || isPainelTv}
                    className="w-full rounded-md bg-zinc-900 border border-zinc-800 px-3 py-2 text-zinc-100"
                    placeholder="0 a 100%"
                  />
                </div>

                {saveError && <div className="text-sm text-red-400">{saveError}</div>}
                {isPainelTv && <div className="text-xs text-zinc-400">Somente leitura (PAINEL_TV).</div>}
              </div>
            </div>

            <div className="px-5 py-4 border-t border-zinc-800 flex items-center justify-end gap-2 shrink-0">
              <button
                onClick={closeModal}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                disabled={saving}
              >
                Cancelar
              </button>
              {!isPainelTv && (
                <button
                  onClick={handleSave}
                  disabled={saving}
                  className="px-4 py-2 rounded-md bg-emerald-300 text-emerald-950 hover:bg-emerald-200 font-medium"
                >
                  {saving ? "Salvando..." : "Salvar"}
                </button>
              )}
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
    <div className="relative rounded-2xl bg-[color:var(--bg-card)] border border-white/10 shadow-[0_14px_34px_rgba(15,23,42,0.55)] p-5 overflow-hidden">
      <div className="absolute right-4 top-4 opacity-70">
        <Icon kind={icon} className={`${accent ?? "text-[color:var(--text-muted)]"}`} />
      </div>

      <div className="text-xs tracking-wide uppercase text-[color:var(--text-muted)]">{label}</div>
      <div className={`mt-2 text-4xl font-semibold ${accent ?? "text-[color:var(--text-main)]"}`}>{value}</div>
      <div className="mt-4 h-1 w-full rounded-full bg-slate-900/30 overflow-hidden">
        <div className={`h-1 w-1/3 ${accent ?? "bg-[color:var(--blue-info)]"} opacity-35`} />
      </div>
    </div>
  );
}

type ThProps = React.ComponentPropsWithoutRef<"th">;

const Th = ({ children, className = "", ...rest }: ThProps) => {
  return (
    <th
      {...rest}
      className={`px-4 py-4 text-sm font-semibold text-[color:var(--text-main)] bg-[color:var(--bg-card)] ${className}`}
    >
      {children}
    </th>
  );
};

function Td({
  children,
  className,
  colSpan,
}: {
  children: React.ReactNode;
  className?: string;
  colSpan?: number;
}) {
  return (
    <td className={`px-4 py-4 text-[color:var(--text-main)] ${className ?? ""}`} colSpan={colSpan}>
      {children}
    </td>
  );
}
