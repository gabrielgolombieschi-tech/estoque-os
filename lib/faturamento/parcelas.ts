/**
 * Rateio das parcelas (duplicatas da NF-e) entre as telas que emitem nota: o card
 * de faturamento da OV e a tela de faturar a OS. Uma implementacao so para as duas
 * nao divergirem no centavo.
 */

/**
 * Divide o total da nota entre as parcelas em partes iguais. Trabalha em centavos
 * para a soma fechar exatamente no total, e o resto da divisao vai na PRIMEIRA
 * parcela — decisao do Gabriel em 11/09/2026: R$ 263,07 em duas fica 131,54 e
 * 131,53, nunca 131,53 e 131,53, que perderia um centavo.
 *
 * Com uma parcela so o valor volta a ficar vazio, que e como a tela e o backend
 * dizem "use o total da nota".
 */
export function ratearParcelas(total: number, quantidade: number): string[] {
  if (quantidade <= 1) return [""];
  const centavos = Math.round(total * 100);
  if (!Number.isFinite(centavos) || centavos <= 0) {
    return Array.from({ length: quantidade }, () => "");
  }
  const base = Math.floor(centavos / quantidade);
  const resto = centavos - base * quantidade;
  return Array.from({ length: quantidade }, (_, indice) => {
    const valor = (indice === 0 ? base + resto : base) / 100;
    return valor.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  });
}
