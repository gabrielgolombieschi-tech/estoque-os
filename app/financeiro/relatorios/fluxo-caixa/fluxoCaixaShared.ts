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

export function getDefaultRange(): { start: string; end: string } {
  const now = new Date();
  const start = new Date(now);
  start.setDate(start.getDate() - 15);
  const end = new Date(now);
  end.setDate(end.getDate() + 45);
  return { start: toISODate(start), end: toISODate(end) };
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

export type ContaBancariaOption = {
  id: string;
  codigo: string | null;
  nome: string | null;
  banco: string | null;
  tipo: string | null;
};

export function contaLabel(c: ContaBancariaOption): string {
  const parts = [c.codigo, c.nome].filter(Boolean);
  const base = parts.length ? parts.join(" - ") : c.id;
  const extra = c.banco ? ` (${c.banco})` : "";
  return `${base}${extra}`;
}
