/**
 * Alertas de cadastro por NCM. Nao bloqueiam o salvamento: apontam uma classificacao
 * que costuma sair errada e pedem para a pessoa confirmar.
 *
 * 8536.41.00 e "Reles para tensao nao superior a 60 V". Os 60 V sao do circuito
 * manobrado, nao da bobina — um contator com bobina de 24 V que chaveia 400 V nao e
 * rele ate 60 V, e contator de potencia costuma ir em 8536.49.00 (Gabriel, 16/09/2026).
 */
const ALERTAS_POR_NCM: Record<string, string> = {
  "85364100":
    "Relés até 60 V: confirme se os 60 V são do circuito manobrado. Contatores de potência costumam ir em 85364900.",
};

/** Aceita o NCM com ou sem pontos (85364100 ou 8536.41.00). */
export function alertaCadastroNcm(ncm: string | null | undefined): string | null {
  const digitos = String(ncm ?? "").replace(/\D/g, "");
  if (digitos.length !== 8) return null;
  return ALERTAS_POR_NCM[digitos] ?? null;
}
