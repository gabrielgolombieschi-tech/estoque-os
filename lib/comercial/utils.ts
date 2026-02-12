export type SupabaseErrorLike = { code?: string; message?: string } | null | undefined;

export function toSupabaseErrorLike(error: unknown): SupabaseErrorLike {
  if (!error || typeof error !== "object") return null;
  const e = error as Record<string, unknown>;
  const code = typeof e.code === "string" ? e.code : undefined;
  const message = typeof e.message === "string" ? e.message : undefined;
  if (!code && !message) return null;
  return { code, message };
}

export function n(value: unknown): number {
  if (value === null || value === undefined) return 0;
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  if (typeof value === "string") {
    const v = Number(value);
    return Number.isFinite(v) ? v : 0;
  }
  return 0;
}

export function upperTrim(v: string): string {
  return String(v ?? "")
    .trim()
    .toUpperCase();
}

export function isOrcamentoReadOnly(status: string | null | undefined): boolean {
  return String(status ?? "").toUpperCase() !== "RASCUNHO";
}

export function mapOrcamentoError(error: SupabaseErrorLike, fallback: string): string {
  const msg = typeof error?.message === "string" ? error.message : "";
  if (!msg) return fallback;

  const lower = msg.toLowerCase();
  if (lower.includes("desconto global") && lower.includes("excede")) {
    return "Desconto global (%) excede o máximo configurado.";
  }
  if (lower.includes("cliente inválido") || lower.includes("cliente invalido")) {
    return "Cliente inválido para este tenant/empresa.";
  }
  if (lower.includes("condição de pagamento inválida") || lower.includes("condicao de pagamento invalida")) {
    return "Condição de pagamento inválida.";
  }
  if (lower.includes("vendedor inválido") || lower.includes("vendedor invalido")) {
    return "Vendedor inválido.";
  }
  return msg;
}
