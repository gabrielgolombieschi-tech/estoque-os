"use client";

import Image from "next/image";
import { useEffect, useMemo, useState } from "react";

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
};

type Props = {
  initialRows: DashRow[];
};

type SortDir = "asc" | "desc";

const formatPercent = (v: number) =>
  `${(Number(v || 0)).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}%`;

function isOverdue(row: DashRow, today: Date) {
  const progress = Number(row.progresso_percent ?? 0);
  const date = row.data_prevista ? new Date(row.data_prevista) : null;
  return progress < 100 && !!date && date < today;
}

export default function ProjetosDashboard({ initialRows }: Props) {
  const areaOrder: Area[] = ["eletrico", "seguranca", "mecanico", "software"];
  const [areaIndex, setAreaIndex] = useState(0);
  const [sortDir, setSortDir] = useState<SortDir>("asc");

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

  const rowsBase = useMemo(
    () => initialRows.filter((r) => r.habilitado && r.area === areaAtual && r.item_tipo === "projeto"),
    [areaAtual, initialRows]
  );

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

  return (
    <div className="space-y-5">
      <header className="bg-blue-700 text-white rounded-xl shadow-md">
        <div className="flex items-center justify-between px-6 py-4">
          <div>
            <h1 className="text-2xl font-bold tracking-tight">Projetos {areaLabel[areaAtual]}</h1>
            <div className="text-xs text-blue-100/80 mt-1">Alternando area a cada 30s</div>
          </div>
          <div className="relative w-28 h-10">
            <Image src="/Segau.png" alt="Segau" fill className="object-contain" />
          </div>
        </div>
      </header>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
        <KpiCard label="Quantidade Projetos" value={kpis.total} />
        <KpiCard label="Projetos Concluidos" value={kpis.concluidos} accent="text-emerald-500" />
        <KpiCard label="Projetos em Andamento" value={kpis.andamento} accent="text-blue-400" />
        <KpiCard label="Projetos Atrasados" value={kpis.atrasados} accent="text-red-500" />
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
                <Th className="text-right pr-4">Status</Th>
              </tr>
            </thead>
            <tbody>
              {sortedTable.map((r, idx) => {
                const overdue = isOverdue(r, today);
                const dateBg = overdue ? "bg-red-900/70 text-red-100" : "bg-emerald-900/50 text-emerald-100";
                const dateCell =
                  r.data_prevista && !Number.isNaN(new Date(r.data_prevista).getTime())
                    ? new Date(r.data_prevista).toLocaleDateString("pt-BR")
                    : "-";
                return (
                  <tr key={`${r.os_id}-${r.area}-${r.item_tipo}-${idx}`} className={idx % 2 === 0 ? "bg-zinc-900/40" : ""}>
                    <Td>{r.numero_os}</Td>
                    <Td>{r.cliente_nome}</Td>
                    <Td>{r.descricao_servico || "Sem descricao"}</Td>
                    <Td>{r.responsavel_id || "-"}</Td>
                    <Td className={`whitespace-nowrap ${r.data_prevista ? dateBg : ""}`}>{dateCell}</Td>
                    <Td className="text-right pr-4">{formatPercent(Number(r.progresso_percent ?? 0))}</Td>
                  </tr>
                );
              })}

              {sortedTable.length === 0 && (
                <tr>
                  <Td colSpan={6} className="text-center py-6 text-zinc-400">
                    Nenhum registro para os filtros selecionados.
                  </Td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
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

type ThProps = React.ComponentPropsWithoutRef<"th">;

const Th = ({ children, className = "", ...rest }: ThProps) => {
  return (
    <th {...rest} className={`px-4 py-3 ${className}`}>
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
    <td className={`px-4 py-3 text-zinc-100 ${className ?? ""}`} colSpan={colSpan}>
      {children}
    </td>
  );
}
