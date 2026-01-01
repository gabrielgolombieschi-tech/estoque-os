"use client";

import Image from "next/image";
import { useEffect, useMemo, useState } from "react";

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
};

type Props = {
  initialRows: DashRow[];
};

type SortDir = "asc" | "desc";

const formatPercent = (v: number) =>
  `${(Number(v || 0)).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}%`;

function isOverdue(row: DashRow, today: Date) {
  const progress = Number(row.progresso_percent ?? 0);
  const date = new Date(row.data_prevista);
  return progress < 100 && date < today;
}

export default function ExecucaoDashboard({ initialRows }: Props) {
  const areaOrder: Area[] = ["eletrico", "mecanico"];
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

  const rowsBase = useMemo(() => {
    const base = initialRows.filter(
      (r) => r.habilitado && r.item_tipo === "execucao" && r.area === areaAtual
    );
    return base;
  }, [areaAtual, initialRows]);

  const anoVigente = today.getFullYear();

  const tableRows = useMemo(
    () => rowsBase.filter((r) => r.data_prevista && Number(r.progresso_percent ?? 0) < 100),
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
    console.log("execucao total rows", initialRows.length);
    console.log("execucao rowsBase (habilitado/item_tipo/area)", rowsBase.length);
    console.log("execucao table rows (<100)", tableRows.length);
    console.log("has49", initialRows.find((r) => r.os_id === 49));
  }, [initialRows, rowsBase.length, tableRows.length]);

  const areaLabel: Record<Area, string> = {
    eletrico: "Execucao Eletrica",
    mecanico: "Execucao Mecanica",
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
                <Th className="text-right pr-4">Status</Th>
              </tr>
            </thead>
            <tbody>
              {tableRows.map((r, idx) => {
                const overdue = isOverdue(r, today);
                const dateBg = overdue ? "bg-red-900/70 text-red-100" : "bg-emerald-900/50 text-emerald-100";
                return (
                  <tr key={`${r.os_id}-${r.area}-${idx}`} className={idx % 2 === 0 ? "bg-zinc-900/40" : ""}>
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
                    Nenhuma execução em aberto.
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
