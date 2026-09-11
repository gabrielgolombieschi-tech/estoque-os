import { ratearParcelas } from "../lib/faturamento/parcelas.ts";

/**
 * Regressao do rateio das parcelas da NF-e (lib/faturamento/parcelas.ts).
 *
 *   node scripts/test-rateio-parcelas.mjs
 *
 * A soma das parcelas tem de fechar exatamente no total da nota, e o resto da
 * divisao vai na primeira — decisao do Gabriel em 11/09/2026.
 */
const paraNumero = (v) => Number(String(v).replace(/\./g, "").replace(",", "."));
let falhas = 0;
const casos = [
  [263.07, 2], [263.07, 3], [9000, 2], [18166.99, 2], [18166.99, 3],
  [21303.95, 2], [0.03, 2], [0.01, 2], [100, 4], [1, 3], [8702418.59, 7],
];
for (const [total, n] of casos) {
  const partes = ratearParcelas(total, n);
  const soma = partes.reduce((s, p) => s + paraNumero(p), 0);
  const fecha = Math.abs(soma - total) < 0.0001;
  const valores = partes.map(paraNumero);
  const restoNaPrimeira = valores.every((v, i) => i === 0 || Math.abs(v - valores[1]) < 0.0001)
    && valores[0] >= valores[1] - 0.0001;
  if (!fecha || !restoNaPrimeira) falhas += 1;
  console.log(`${fecha && restoNaPrimeira ? "ok   " : "FALHA"} ${String(total).padStart(11)} / ${n} = ${partes.join(" + ")} = ${soma.toFixed(2)}`);
}
// Uma parcela volta a ficar vazia (convencao "usa o total da nota").
const umaSo = ratearParcelas(263.07, 1);
const okUma = umaSo.length === 1 && umaSo[0] === "";
if (!okUma) falhas += 1;
console.log(`${okUma ? "ok   " : "FALHA"} uma parcela -> valor vazio`);
console.log(falhas === 0 ? "\nRateio das parcelas: todos os casos passaram." : `\n${falhas} falha(s).`);
process.exit(falhas === 0 ? 0 : 1);
