import type { OrcamentoStatus } from "@/lib/comercial/types";

export type OrcamentoStatusCanonical = "ANDAMENTO" | "FECHADO" | "PERDIDO";

type LegacyStatus = "RASCUNHO" | "FINALIZADO" | "CANCELADO";
type KnownStatus = OrcamentoStatusCanonical | LegacyStatus;

const CANONICAL_LABELS: Record<OrcamentoStatusCanonical, string> = {
  ANDAMENTO: "Andamento",
  FECHADO: "Fechado",
  PERDIDO: "Perdido",
};

function upper(input: string | null | undefined): string {
  return String(input ?? "").trim().toUpperCase();
}

export function normalizeOrcamentoStatus(status: string | null | undefined): OrcamentoStatusCanonical | string {
  const s = upper(status);
  if (!s) return "";
  if (s === "ANDAMENTO" || s === "RASCUNHO") return "ANDAMENTO";
  if (s === "FECHADO" || s === "FINALIZADO") return "FECHADO";
  if (s === "PERDIDO" || s === "CANCELADO") return "PERDIDO";
  return s;
}

export function isOrcamentoEditableStatus(status: string | null | undefined): boolean {
  return normalizeOrcamentoStatus(status) === "ANDAMENTO";
}

export function getOrcamentoStatusLabel(status: string | null | undefined): string {
  const normalized = normalizeOrcamentoStatus(status);
  if (!normalized) return "-";
  if (normalized in CANONICAL_LABELS) {
    return CANONICAL_LABELS[normalized as OrcamentoStatusCanonical];
  }
  return normalized;
}

export function getOrcamentoStatusFilterValues(status: OrcamentoStatus): string[] {
  const normalized = normalizeOrcamentoStatus(status) as KnownStatus | string;
  if (normalized === "ANDAMENTO") return ["ANDAMENTO", "RASCUNHO"];
  if (normalized === "FECHADO") return ["FECHADO", "FINALIZADO"];
  if (normalized === "PERDIDO") return ["PERDIDO", "CANCELADO"];
  return normalized ? [normalized] : [];
}

export function isCanonicalOrcamentoStatus(status: string | null | undefined): status is OrcamentoStatusCanonical {
  const s = upper(status);
  return s === "ANDAMENTO" || s === "FECHADO" || s === "PERDIDO";
}

