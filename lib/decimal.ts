export function parseDecimalBR(value: string | number | null | undefined): number {
  if (value === null || value === undefined) return NaN;
  if (typeof value === "number") return value;
  const trimmed = value.trim();
  if (!trimmed) return NaN;
  // troca vírgula por ponto e remove espaços
  const normalized = trimmed.replace(",", ".");
  const n = Number(normalized);
  return Number.isFinite(n) ? n : NaN;
}

export function formatDecimalBR(value: number | null | undefined, maxDecimals = 3): string {
  const n = Number(value ?? 0);
  if (!Number.isFinite(n)) return "0";
  return n.toLocaleString("pt-BR", { minimumFractionDigits: 0, maximumFractionDigits: maxDecimals });
}

export function parseMoneyBR(value: string | number | null | undefined): number {
  if (value === null || value === undefined) return NaN;
  if (typeof value === "number") return value;
  const trimmed = value.trim();
  if (!trimmed) return NaN;

  const normalized = trimmed
    .replace(/^R\\$\\s*/i, "")
    .replace(/\\./g, "")
    .replace(/\\s+/g, "")
    .replace(",", ".");

  const n = Number(normalized);
  return Number.isFinite(n) ? n : NaN;
}

export function formatMoneyBR(value: number | null | undefined): string {
  const n = Number(value ?? 0);
  if (!Number.isFinite(n)) return "0,00";
  return n.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
