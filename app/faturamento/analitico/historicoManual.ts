import manualHistoricalData from "./historicoManual.data.json";

export type ManualHistoricalEntry = {
  year: number;
  month: number;
  clientName: string;
  amount: number;
};

type ManualHistoricalTuple = [year: number, month: number, clientName: string, amount: number];

const tuples = manualHistoricalData as ManualHistoricalTuple[];

// Fontes manuais consolidadas:
// 2017-2023: controles historicos enviados, com distribuicao por cliente preservada
//            e ajuste para os totais mensais informados.
// 2024-2025: CONTROLE 2024/2025.xlsx (SEGAU + SGU)
export const manualHistoricalEntries: ManualHistoricalEntry[] = tuples.map(([year, month, clientName, amount]) => ({
  year,
  month,
  clientName,
  amount,
}));

export const manualHistoricalYears = Array.from(new Set(tuples.map(([year]) => year))).sort((a, b) => a - b);
