import assert from "node:assert/strict";
import {
  normalizarNomeCadastro,
  normalizarUnidadesNoNome,
} from "../lib/itens/normalizacaoNome.ts";

const casos = [
  [
    "CONTATOR 3P AC-3 115 A 2NA+2NF 110-127 VCA/CC 50/60 Hz CONEXÃO POR PARAFUSO",
    "CONTATOR 3P AC-3 115A 2NA+2NF 110-127VCA/CC 50/60Hz CONEXÃO POR PARAFUSO",
  ],
  ["DISJUNTOR MOTOR 4,5-6,3 A", "DISJUNTOR MOTOR 4,5-6,3A"],
  ["SINAL ANALÓGICO 4-20 mA", "SINAL ANALÓGICO 4-20mA"],
  ["RELÉ DE INTERFACE 5 A 31 mm", "RELÉ DE INTERFACE 5A 31mm"],
  ["CHAVE DE SEGURANÇA 0,2 A CABO 3 m 25 mm", "CHAVE DE SEGURANÇA 0,2A CABO 3m 25mm"],
  ["MOTOR 15 HP 50 HZ", "MOTOR 15HP 50HZ"],
  ["THINNER 5 L", "THINNER 5L"],
  ["RELE TEMP. 8A 1NAF 24 A 240VCA/CC", "RELE TEMP. 8A 1NAF 24 A 240VCA/CC"],
  ["CHAVE ALLEN JG. 1,5 A 10,0MM", "CHAVE ALLEN JG. 1,5 A 10,0MM"],
  ["ARRUELA PRESSAO DIN 127 M 8", "ARRUELA PRESSAO DIN 127 M 8"],
  ["PORCA SEXT INOX DIN 934 A2 MA 8 X 1.25", "PORCA SEXT INOX DIN 934 A2 MA 8 X 1.25"],
  ["MACHO MANUAL BRILHANTE 241 M3X0,5 3P", "MACHO MANUAL BRILHANTE 241 M3X0,5 3P"],
  ["CONEC SINDAL 4MM 812 W-A12 BARRA C/12", "CONEC SINDAL 4MM 812 W-A12 BARRA C/12"],
  ["CABO COM CONECTOR RETO M12 4 V", "CABO COM CONECTOR RETO M12 4 V"],
];

for (const [entrada, esperado] of casos) {
  assert.equal(normalizarUnidadesNoNome(entrada), esperado, entrada);
}

const casosCadastro = [
  [
    "FUSO TRAPEZOIDAL TR25X5X2000 DIREITA - Pedido 2025/114583",
    "FUSO TRAPEZOIDAL TR25X5X2000 DIREITA",
  ],
  [
    "PORCA FLANGEADA TR40 BRONZE DIREITA - PEDIDO 2025/121959 -",
    "PORCA FLANGEADA TR40 BRONZE DIREITA",
  ],
  ["ITEM TÉCNICO - PEDIDO DE COMPRA Nº 2026/81006", "ITEM TÉCNICO"],
  ["MOTOR PARA PEDIDO ESPECIAL", "MOTOR PARA PEDIDO ESPECIAL"],
];

for (const [entrada, esperado] of casosCadastro) {
  assert.equal(normalizarNomeCadastro(entrada), esperado, entrada);
}

console.log(`Normalização de nomes validada em ${casos.length + casosCadastro.length} casos.`);
