/**
 * Competencia da NFS-e no mes da emissao, e nunca depois dela.
 *
 * Pedido da WEG Tintas (09/2026): as NFS-e 12 a 15 sairam com competencia 29/07 e emissao 03/08, e o tomador
 * recolhe o ISS e o INSS retidos pela competencia — outro mes gera multa e juros. Espelho de
 * f.fn_nfse_competencia_pendencia (migration 20260914135000), com as mesmas mensagens.
 *
 * Sem dependencias: e importado pela Edge Function e pela tela de faturar a OS.
 */

/** Data de hoje em Sao Paulo (AAAA-MM-DD). toISOString() da o dia em UTC e vira o dia seguinte as 21h locais. */
export function hojeSaoPaulo(agora = new Date()): string {
  const partes = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo", year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(agora);
  const valor = (tipo: string) => partes.find((p) => p.type === tipo)?.value ?? "";
  return `${valor("year")}-${valor("month")}-${valor("day")}`;
}

function dataBR(iso: string) {
  const [ano, mes, dia] = iso.split("-");
  return `${dia}/${mes}/${ano}`;
}

/** Pendencia da competencia frente ao dia da emissao (AAAA-MM-DD); nula quando esta tudo certo. */
export function pendenciaCompetenciaNfse(competencia: string | null | undefined, emissao: string): string | null {
  const c = String(competencia ?? "").slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(c)) return "Data de competencia invalida.";
  if (c > emissao) return `Competencia ${dataBR(c)} depois da data de emissao (${dataBR(emissao)}): a competencia nao pode ser posterior a nota.`;
  if (c.slice(0, 7) !== emissao.slice(0, 7)) {
    const [ano, mes] = emissao.split("-");
    return `Competencia ${dataBR(c)} fora do mes da emissao (${mes}/${ano}): use uma data de 01/${mes}/${ano} a ${dataBR(emissao)}. O tomador recolhe o ISS e o INSS retidos pela competencia, e competencia de outro mes gera multa e juros.`;
  }
  return null;
}
