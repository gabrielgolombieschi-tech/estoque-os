export function upper(value: unknown): string {
  return String(value ?? "").toUpperCase();
}

export function upperTrim(value: unknown): string {
  return String(value ?? "")
    .trim()
    .toUpperCase();
}

export function upperOrNull(value: unknown): string | null {
  const normalized = upperTrim(value);
  return normalized ? normalized : null;
}
