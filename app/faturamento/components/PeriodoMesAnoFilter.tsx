"use client";

import { useMemo } from "react";
import { useRouter, useSearchParams } from "next/navigation";

type SearchParamsLike = {
  get(name: string): string | null;
};

type PeriodoMesAnoRange = {
  anoInicial: string;
  anoFinal: string;
  mesInicial: string;
  mesFinal: string;
  startDate: string | null;
  endDate: string | null;
  hasFilter: boolean;
};

const MONTH_OPTIONS = [
  { value: "1", label: "Janeiro" },
  { value: "2", label: "Fevereiro" },
  { value: "3", label: "Marco" },
  { value: "4", label: "Abril" },
  { value: "5", label: "Maio" },
  { value: "6", label: "Junho" },
  { value: "7", label: "Julho" },
  { value: "8", label: "Agosto" },
  { value: "9", label: "Setembro" },
  { value: "10", label: "Outubro" },
  { value: "11", label: "Novembro" },
  { value: "12", label: "Dezembro" },
] as const;

function normalizeYear(raw: string | null): string {
  const digits = String(raw ?? "")
    .replace(/\D/g, "")
    .slice(0, 4);
  if (!digits) return "";
  const year = Number(digits);
  if (!Number.isInteger(year) || year < 2000 || year > 2100) return "";
  return String(year);
}

function normalizeMonth(raw: string | null): string {
  const month = Number(String(raw ?? "").trim());
  if (!Number.isInteger(month) || month < 1 || month > 12) return "";
  return String(month);
}

function getLastDayOfMonth(year: number, month: number): number {
  return new Date(year, month, 0).getDate();
}

export function buildPeriodoMesAnoRange(searchParams: SearchParamsLike): PeriodoMesAnoRange {
  const anoInicial = normalizeYear(searchParams.get("ano_inicial"));
  const anoFinal = normalizeYear(searchParams.get("ano_final"));
  const mesInicial = anoInicial ? normalizeMonth(searchParams.get("mes_inicial")) : "";
  const mesFinal = anoFinal ? normalizeMonth(searchParams.get("mes_final")) : "";

  const startDate = anoInicial ? `${anoInicial}-${String(Number(mesInicial || "1")).padStart(2, "0")}-01` : null;
  const endDate = anoFinal
    ? `${anoFinal}-${String(Number(mesFinal || "12")).padStart(2, "0")}-${String(
        getLastDayOfMonth(Number(anoFinal), Number(mesFinal || "12"))
      ).padStart(2, "0")}`
    : null;

  return {
    anoInicial,
    anoFinal,
    mesInicial,
    mesFinal,
    startDate,
    endDate,
    hasFilter: Boolean(anoInicial || anoFinal || mesInicial || mesFinal),
  };
}

export default function PeriodoMesAnoFilter({ basePath }: { basePath: string }) {
  const router = useRouter();
  const searchParams = useSearchParams();

  const periodo = useMemo(() => buildPeriodoMesAnoRange(searchParams), [searchParams]);
  const fieldPrefix = useMemo(() => basePath.replace(/[^a-z0-9-]+/gi, "-"), [basePath]);
  const currentYear = new Date().getFullYear();
  const yearOptions = useMemo(() => {
    const startYear = 2000;
    const endYear = currentYear + 2;
    return Array.from({ length: endYear - startYear + 1 }, (_, index) => String(endYear - index));
  }, [currentYear]);

  const updateParam = (name: string, value: string) => {
    const params = new URLSearchParams(searchParams.toString());
    if (value) {
      params.set(name, value);
    } else {
      params.delete(name);
    }

    if (name === "ano_inicial" && !value) {
      params.delete("mes_inicial");
    }
    if (name === "ano_final" && !value) {
      params.delete("mes_final");
    }

    const nextUrl = params.toString() ? `${basePath}?${params.toString()}` : basePath;
    router.replace(nextUrl, { scroll: false });
  };

  const clearPeriodo = () => {
    const params = new URLSearchParams(searchParams.toString());
    params.delete("ano_inicial");
    params.delete("ano_final");
    params.delete("mes_inicial");
    params.delete("mes_final");
    const nextUrl = params.toString() ? `${basePath}?${params.toString()}` : basePath;
    router.replace(nextUrl, { scroll: false });
  };

  return (
    <div className="mt-3 rounded-xl border border-zinc-800 bg-zinc-950 px-4 py-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <div className="text-xs font-medium uppercase tracking-wide text-zinc-500">Periodo</div>
          <div className="mt-1 text-sm text-zinc-400">Filtre por mes e ano de emissao.</div>
        </div>
        {periodo.hasFilter ? (
          <button
            type="button"
            onClick={clearPeriodo}
            className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-900"
          >
            Limpar periodo
          </button>
        ) : null}
      </div>

      <div className="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        <div>
          <label htmlFor={`${fieldPrefix}-ano-inicial`} className="block text-xs font-medium text-zinc-400">
            Ano inicial
          </label>
          <select
            id={`${fieldPrefix}-ano-inicial`}
            value={periodo.anoInicial}
            onChange={(e) => updateParam("ano_inicial", e.target.value)}
            className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-700"
          >
            <option value="">Todos</option>
            {yearOptions.map((year) => (
              <option key={year} value={year}>
                {year}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label htmlFor={`${fieldPrefix}-mes-inicial`} className="block text-xs font-medium text-zinc-400">
            Mes inicial
          </label>
          <select
            id={`${fieldPrefix}-mes-inicial`}
            value={periodo.mesInicial}
            onChange={(e) => updateParam("mes_inicial", e.target.value)}
            disabled={!periodo.anoInicial}
            className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <option value="">Todos</option>
            {MONTH_OPTIONS.map((month) => (
              <option key={month.value} value={month.value}>
                {month.label}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label htmlFor={`${fieldPrefix}-ano-final`} className="block text-xs font-medium text-zinc-400">
            Ano final
          </label>
          <select
            id={`${fieldPrefix}-ano-final`}
            value={periodo.anoFinal}
            onChange={(e) => updateParam("ano_final", e.target.value)}
            className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-700"
          >
            <option value="">Todos</option>
            {yearOptions.map((year) => (
              <option key={year} value={year}>
                {year}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label htmlFor={`${fieldPrefix}-mes-final`} className="block text-xs font-medium text-zinc-400">
            Mes final
          </label>
          <select
            id={`${fieldPrefix}-mes-final`}
            value={periodo.mesFinal}
            onChange={(e) => updateParam("mes_final", e.target.value)}
            disabled={!periodo.anoFinal}
            className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <option value="">Todos</option>
            {MONTH_OPTIONS.map((month) => (
              <option key={month.value} value={month.value}>
                {month.label}
              </option>
            ))}
          </select>
        </div>
      </div>
    </div>
  );
}
