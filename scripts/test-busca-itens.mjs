import assert from "node:assert/strict";
import { aplicarBuscaItem, correspondeBuscaItem, normalizarBuscaItem, termosBuscaItem } from "../lib/itens/busca.ts";

const casos = [
  [["CABO FLEXÍVEL AZUL 1,5MM²"], "cabo 1,5", true],
  [["CABO FLEXÍVEL AZUL 1,5MM²"], "1.5 cabo", true],
  [["CABO FLEXIVEL 1.5MM²"], "  flexível\t1,5\ncabo  ", true],
  [["CABO FLEXÍVEL 2,5MM²"], "cabo 1,5", false],
  [["CABO FLEXÍVEL 1,5MM²"], "cabo 1,5 vermelho", false],
  [["INVERSOR DE FREQUÊNCIA", "GA800U4023ABM", "YASKAWA"], "yaskawa frequencia GA800", true],
  [["ARMÁRIO ELÉTRICO"], "eletrico armario", true],
  [["6XV1870-3QH20"], "6xv1870-3qh20", true],
  [["CABO 1,5"], "15", false],
  [[null, undefined, ""], "", true],
  [["CABO"], "%", false],
  [["AB_CD"], "ab_cd", true],
];
for (const [values, term, expected] of casos) {
  assert.equal(correspondeBuscaItem(values, term), expected, `${term} em ${values}`);
}
assert.equal(normalizarBuscaItem("1,5 2,5 M3X0,5 AZUL,VERDE"), "1.5 2.5 M3X0.5 AZUL,VERDE");
assert.deepEqual(termosBuscaItem("CÁBO cabo 1,5 1.5"), ["CABO", "1.5"]);
const filtros = [];
const query = { ilike(column, pattern) { filtros.push([column, pattern]); return this; } };
assert.equal(aplicarBuscaItem(query, "cabo 1,5"), query);
assert.deepEqual(filtros, [["busca_item", "%CABO%"], ["busca_item", "%1.5%"]]);
filtros.length = 0;
aplicarBuscaItem(query, "AB_CD 50% X\\Y", "nome_item_busca");
assert.deepEqual(filtros, [["nome_item_busca", "%AB\\_CD%"], ["nome_item_busca", "%50\\%%"], ["nome_item_busca", "%X\\\\Y%"]]);
console.log(`Busca de itens validada: ${casos.length} cenários, termos, decimais e filtros literais.`);
