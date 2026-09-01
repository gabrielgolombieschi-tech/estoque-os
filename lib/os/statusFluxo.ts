export type OsStatusFluxo =
  | "em_andamento"
  | "concluida"
  | "faturada"
  | "em_andamento_garantia"
  | "concluida_garantia";

export type OsStatusExibicao = OsStatusFluxo | "aberta" | "cancelada";

export function normalizeOsStatusFluxo(
  statusFluxo: string | null | undefined,
  statusLegado?: string | null
): OsStatusExibicao | null {
  const legado = String(statusLegado ?? "").trim().toLowerCase();
  if (legado === "aberta" || legado === "cancelada") return legado;

  const fluxo = String(statusFluxo ?? "").trim().toLowerCase();
  if (
    fluxo === "em_andamento" ||
    fluxo === "concluida" ||
    fluxo === "faturada" ||
    fluxo === "em_andamento_garantia" ||
    fluxo === "concluida_garantia"
  ) {
    return fluxo;
  }

  if (legado === "em_andamento" || legado === "concluida") return legado;
  return null;
}

export function getOsStatusLabel(status: OsStatusExibicao | null): string {
  switch (status) {
    case "aberta":
      return "Aberta";
    case "em_andamento":
      return "Em andamento";
    case "concluida":
      return "Concluída · aguardando faturamento";
    case "faturada":
      return "Faturada";
    case "em_andamento_garantia":
      return "Em andamento · garantia";
    case "concluida_garantia":
      return "Concluída · garantia";
    case "cancelada":
      return "Cancelada";
    default:
      return "Sem status";
  }
}

export function isOsStatusLocked(status: OsStatusExibicao | null): boolean {
  return status === "concluida" || status === "faturada" || status === "concluida_garantia" || status === "cancelada";
}

