import { formatDecimalBR } from "@/lib/decimal";

export function n(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

export function toISODate(d: Date): string {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

export function formatDateBR(iso?: string | null): string {
  if (!iso) return "";
  const d = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleDateString("pt-BR");
}

export function formatMoney(value: unknown): string {
  return formatDecimalBR(n(value), 2);
}

export function downloadCsv(filename: string, header: string[], rows: string[][]) {
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

export function daysOverdue(dueIso: string): number {
  const d = new Date(`${dueIso}T00:00:00`);
  const today = new Date();
  const today0 = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const diff = today0.getTime() - d.getTime();
  return Math.floor(diff / (1000 * 60 * 60 * 24));
}

export type AgingBuckets = {
  a_vencer: number;
  vencido_0_30: number;
  vencido_31_60: number;
  vencido_61_90: number;
  vencido_90_mais: number;
  total_aberto: number;
};

export function emptyBuckets(): AgingBuckets {
  return { a_vencer: 0, vencido_0_30: 0, vencido_31_60: 0, vencido_61_90: 0, vencido_90_mais: 0, total_aberto: 0 };
}

export function addToBuckets(b: AgingBuckets, days: number, amount: number) {
  if (amount === 0) return;
  b.total_aberto += amount;
  if (days < 0) {
    b.a_vencer += amount;
    return;
  }
  if (days <= 30) {
    b.vencido_0_30 += amount;
    return;
  }
  if (days <= 60) {
    b.vencido_31_60 += amount;
    return;
  }
  if (days <= 90) {
    b.vencido_61_90 += amount;
    return;
  }
  b.vencido_90_mais += amount;
}
