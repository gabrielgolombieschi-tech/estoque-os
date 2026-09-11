/**
 * Codigos de tributacao nacional que exigem o grupo obra na DPS. Lista do proprio ambiente
 * nacional, na rejeicao E0370 (DPS 2/20 da OS 139, 11/09/2026). A mesma lista esta na
 * conferencia (f.fn_os_nfse_conferir_homologacao), que bloqueia antes de gastar DPS.
 *
 * Sem dependencias: e importado pela Edge Function e pela tela de faturar a OS.
 */
export const CODIGOS_TRIBUTACAO_COM_OBRA = [
  "070201", "070202", "070401", "070501", "070502", "070601", "070602", "070701", "070801", "071701", "071901", "141403", "141404",
];

export function codigoTributacaoExigeObra(codigoTributacaoNacional: unknown): boolean {
  return CODIGOS_TRIBUTACAO_COM_OBRA.includes(String(codigoTributacaoNacional ?? "").replace(/\D/g, ""));
}
