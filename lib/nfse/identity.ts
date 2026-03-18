export function digitsOnly(value: string | null | undefined): string {
  return String(value ?? "").replace(/\D/g, "");
}

export function normalizeNfseSerieIdentity(value: string | null | undefined): string {
  return String(value ?? "").trim().toUpperCase();
}

export function normalizeNfseNumeroIdentity(value: string | null | undefined, emissaoDate?: string | null): string {
  const raw = String(value ?? "").trim().toUpperCase();
  if (!raw) return "";

  const digits = digitsOnly(raw);
  if (!digits) return raw;

  const year = String(emissaoDate ?? "").slice(0, 4);
  let candidate = digits;

  if (/^\d{4}$/.test(year) && digits.startsWith(year) && digits.length > 4) {
    const withoutYear = digits.slice(4).replace(/^0+/, "");
    if (withoutYear) candidate = withoutYear;
  }

  const stripped = candidate.replace(/^0+/, "");
  return stripped || "0";
}

export function isNfseSerieCompatible(left: string | null | undefined, right: string | null | undefined): boolean {
  const a = normalizeNfseSerieIdentity(left);
  const b = normalizeNfseSerieIdentity(right);
  if (!a || !b) return true;
  if (a === b) return true;
  return a === "UNICA" || b === "UNICA";
}
