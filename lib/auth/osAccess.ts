export type EmpresaPapel =
  | "ADMIN"
  | "FINANCEIRO"
  | "FATURAMENTO"
  | "COORDENACAO"
  | "COMPRAS"
  | "ALMOXARIFADO"
  | "TECNICO"
  | "APONTAMENTO_RH"
  | "PAINEL_TV"
  | string;

function normalizePapel(papel: EmpresaPapel | null | undefined): string {
  return typeof papel === "string" ? papel.trim().toUpperCase() : "";
}

export function getOsListAccess(papel: EmpresaPapel | null | undefined): {
  canView: boolean;
  readOnly: boolean;
  hideValorPedido: boolean;
} {
  const p = normalizePapel(papel);

  if (p === "PAINEL_TV") return { canView: false, readOnly: true, hideValorPedido: true };

  if (p === "ADMIN" || p === "FINANCEIRO" || p === "FATURAMENTO" || p === "COORDENACAO") {
    return { canView: true, readOnly: false, hideValorPedido: false };
  }

  if (p === "COMPRAS") return { canView: true, readOnly: true, hideValorPedido: false };

  if (p === "ALMOXARIFADO" || p === "TECNICO" || p === "APONTAMENTO_RH") {
    return { canView: true, readOnly: false, hideValorPedido: true };
  }

  return { canView: false, readOnly: true, hideValorPedido: true };
}

export function getOsDetailAccess(papel: EmpresaPapel | null | undefined): {
  canView: boolean;
  readOnly: boolean;
  hideCustos: boolean;
  hideTotais: boolean;
} {
  const p = normalizePapel(papel);

  if (p === "PAINEL_TV") return { canView: false, readOnly: true, hideCustos: true, hideTotais: true };

  if (p === "ADMIN" || p === "FINANCEIRO" || p === "FATURAMENTO" || p === "COORDENACAO") {
    return { canView: true, readOnly: false, hideCustos: false, hideTotais: false };
  }

  if (p === "COMPRAS") return { canView: true, readOnly: true, hideCustos: false, hideTotais: false };

  if (p === "ALMOXARIFADO" || p === "TECNICO" || p === "APONTAMENTO_RH") {
    return { canView: true, readOnly: false, hideCustos: true, hideTotais: true };
  }

  return { canView: false, readOnly: true, hideCustos: true, hideTotais: true };
}
