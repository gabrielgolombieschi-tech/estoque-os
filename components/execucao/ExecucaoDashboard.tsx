"use client";

import Image from "next/image";
import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

type Area = "eletrico" | "mecanico";

type DashRow = {
  os_id: number;
  item_tipo: "execucao";
  area: Area;
  habilitado: boolean;
  responsavel_id: string | null;
  data_prevista: string;
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

function isOverdue(row: DashRow, today: Date) {
  const progress = Number(row.progresso_percent ?? 0);
  const date = new Date(row.data_prevista);
  return progress < 100 && date < today;
}

export default function ExecucaoDashboard({ initialRows, emptyMessage }: Props) {
  const areaOrder: Area[] = ["eletrico", "mecanico"];
  const [areaIndex, setAreaIndex] = useState(0);
  const [sortDir, setSortDir] = useState<SortDir>("asc");
  const supabase = useMemo(() => supabaseBrowser(), []);
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

  const rowsBase = useMemo(() => {
    const base = rows.filter((r) => r.habilitado && r.item_tipo === "execucao" && r.area === areaAtual);
    return base;
  }, [areaAtual, rows]);

  const anoVigente = today.getFullYear();

  const tableRows = useMemo(
    () => rowsBase.filter((r) => r.data_prevista && Number(r.progresso_percent ?? 0) < 100),
    [rowsBase]
  );


  // KPIs continuam considerando todos (concluídos inclusos, mas apenas concluidos do ano vigente contam no KPI de concluidos)
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

  useEffect(() => {
    console.log("execucao total rows", rows.length);
    console.log("execucao rowsBase (habilitado/item_tipo/area)", rowsBase.length);
    console.log("execucao table rows (<100)", tableRows.length);
    console.log("has49", rows.find((r) => r.os_id === 49));
  }, [rows, rowsBase.length, tableRows.length]);

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

  return (
    <div className="space-y-5">
      <header className="bg-blue-700 text-white rounded-xl shadow-md">
        <div className="flex items-center justify-between px-6 py-4">
          <div>
            <h1 className="text-2xl font-bold tracking-tight">Execução {areaAtual === "eletrico" ? "Elétrica" : "Mecânica"}</h1>
            <div className="text-xs text-blue-100/80 mt-1">Alternando área a cada 30s</div>
          </div>
          <div className="relative w-28 h-10">
            <Image src="/Segau.png" alt="Segau" fill className="object-contain" />
          </div>
        </div>
      </header>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
        <KpiCard label="Quantidade Execuções" value={kpis.total} />
        <KpiCard label="Execuções Concluídas" value={kpis.concluidos} accent="text-emerald-500" />
        <KpiCard label="Execuções em Andamento" value={kpis.andamento} accent="text-blue-400" />
        <KpiCard label="Execuções Atrasadas" value={kpis.atrasados} accent="text-red-500" />
      </div>

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950 shadow">
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-zinc-900">
              <tr className="text-left text-zinc-200">
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
              {tableRows.map((r, idx) => {
                const overdue = isOverdue(r, today);
                const dateBg = overdue ? "bg-red-900/70 text-red-100" : "bg-emerald-900/50 text-emerald-100";
                return (
                  <tr
                    key={`${r.os_id}-${r.area}-${idx}`}
                    className={`${idx % 2 === 0 ? "bg-zinc-900/40" : ""} hover:bg-zinc-900/70 cursor-pointer`}
                    onClick={() => handleRowClick(r)}
                  >
                    <Td>{r.numero_os}</Td>
                    <Td>{r.cliente_nome}</Td>
                    <Td>{r.descricao_servico || "Sem descricao"}</Td>
                    <Td>{r.responsavel_id || "-"}</Td>
                    <Td className={`whitespace-nowrap ${dateBg}`}>
                      {new Date(r.data_prevista).toLocaleDateString("pt-BR")}
                    </Td>
                    <Td className="text-right pr-4">{formatPercent(Number(r.progresso_percent ?? 0))}</Td>
                  </tr>
                );
              })}

              {tableRows.length === 0 && (
                <tr>
                  <Td colSpan={6} className="text-center py-6 text-zinc-400">
                    {emptyMessage ?? "Nenhuma execução em aberto."}
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
            className="w-full max-w-xl bg-zinc-950 border border-zinc-800 rounded-xl p-5 shadow-xl space-y-4"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between gap-3">
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
                disabled={saving}
                className="w-full rounded-md bg-zinc-900 border border-zinc-800 px-3 py-2 text-zinc-100"
                placeholder="0 a 100%"
              />
            </div>

            {saveError && <div className="text-sm text-red-400">{saveError}</div>}
          </div>

            <div className="flex items-center justify-end gap-2 pt-2">
              <button
                onClick={closeModal}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                disabled={saving}
              >
                Cancelar
              </button>
              <button
                onClick={handleSave}
                disabled={saving}
                className="px-4 py-2 rounded-md bg-emerald-300 text-emerald-950 hover:bg-emerald-200 font-medium"
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

function KpiCard({ label, value, accent }: { label: string; value: number; accent?: string }) {
  return (
    <div className="bg-zinc-950 border border-zinc-800 rounded-xl p-4 shadow-sm">
      <div className="text-sm font-semibold text-zinc-300">{label}</div>
      <div className={`text-4xl font-bold mt-2 ${accent ?? "text-purple-400"}`}>{value}</div>
    </div>
  );
}

type ThProps = React.ThHTMLAttributes<HTMLTableCellElement> & { children: React.ReactNode };

function Th({ children, className = "", ...rest }: ThProps) {
  return (
    <th {...rest} className={`px-4 py-3 ${className}`}>
      {children}
    </th>
  );
}

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
    <td className={`px-4 py-3 text-zinc-100 ${className ?? ""}`} colSpan={colSpan}>
      {children}
    </td>
  );
}
