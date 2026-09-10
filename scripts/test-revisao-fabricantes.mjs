import assert from "node:assert/strict";
import fs from "node:fs";
import { montarPlano, verificarRetorno, camposPermitidos } from "./lib/plano-revisao-fabricantes.mjs";
import { pendenciasDescricaoTecnica } from "../lib/itens/qualidadeDescricao.ts";
import { normalizarNomeCadastro } from "../lib/itens/normalizacaoNome.ts";

const manifesto = JSON.parse(fs.readFileSync("docs/padroes-cadastro/revisao-cinco-fabricantes-2026-09-05.json", "utf8"));
const atuais = manifesto.itens.map((i) => ({ ...i.antes, unidade_medida: "UN", preco_unitario: 123.45 }));
const grupos = [{ id: 30, codigo: "RELES_SEGURANCA", ativo: true }, { id: 123, codigo: "CORTINAS_LUZ_SEGURANCA", ativo: true }];
const plano = montarPlano(manifesto, atuais, grupos);
assert.equal(plano.length, 16);
assert.equal(plano.filter((p) => p.depois.grupo_id !== p.antes.grupo_id).length, 3);
assert.ok(plano.every((p) => !p.aplicado));
const retornos = plano.map((p) => ({ ...p.antes, ...p.depois, atualizado_em: "2026-09-05T13:00:00" }));
for (const [i, p] of plano.entries()) {
  assert.deepEqual(Object.keys(p.depois).sort(), [...camposPermitidos].sort());
  verificarRetorno(p, retornos[i]);
  assert.ok(p.depois.descricao.includes(p.fontes[0]));
  assert.ok(p.depois.descricao.includes(manifesto.itens[i].descricao_tecnica));
}
assert.ok(montarPlano(manifesto, retornos, grupos).every((p) => p.aplicado), "Reexecução idempotente");
for (const campo of ["nome", "descricao", "grupo_id", "atualizado_em", "codigo_interno", "fabricante", "fornecedor_id"]) {
  const concorrentes = structuredClone(atuais);
  concorrentes[0][campo] = "ALTERADO APÓS REVISÃO";
  assert.throws(() => montarPlano(manifesto, concorrentes, grupos), /alterad|mudou/);
}
assert.throws(() => montarPlano(manifesto, atuais.slice(1), grupos), /Quantidade/);
assert.throws(() => montarPlano(manifesto, atuais, []), /Grupo não encontrado/);
assert.throws(() => montarPlano(manifesto, atuais, grupos.map((g) => ({ ...g, ativo: false }))), /Grupo não encontrado/);
const repetido = structuredClone(manifesto);
repetido.itens[1] = repetido.itens[0];
assert.throws(() => montarPlano(repetido, atuais, grupos), /repetidos/);
const pendente = structuredClone(manifesto);
pendente.pendentes_fora_do_lote.push(pendente.itens[0].id);
assert.throws(() => montarPlano(pendente, atuais, grupos), /pendente/);
for (const campo of ["unidade_medida", "preco_unitario", "codigo_interno", "fornecedor_id"]) {
  assert.throws(() => verificarRetorno(plano[0], { ...retornos[0], [campo]: "ALTERADO" }), /protegido/);
}

const pendencias = (descricao, extras = {}) => pendenciasDescricaoTecnica({ descricao, ...extras });
assert.equal(pendencias("RESISTOR DE FRENAGEM FIXO 18KW").length, 2);
assert.equal(pendencias("RESISTOR DE FRENAGEM 30Ω POTÊNCIA NOMINAL 925W PICO 18,5kW").length, 2);
assert.equal(pendencias("RELÉ DE ESTADO SÓLIDO 24VCC 2 SAÍDAS").length, 5);
assert.equal(pendencias("MÓDULO SFP 1 PORTA 1000MBPS").length, 2);
assert.equal(pendencias("MÓDULO SFP 1 PORTA 1Gbit/s COBRE RJ45").length, 0);
assert.equal(pendencias("POTENCIÔMETRO PLÁSTICO 4 7K").length, 2);
assert.equal(pendencias("CONJUNTO DE CORTINA DE LUZ").length, 4);
assert.equal(pendencias("CONTATOR", { codigo: "LC1G300" }).length, 1);
assert.equal(pendencias("CONTATOR 3P 300A", { codigo: "LC1G300KUEC" }).length, 0);
assert.equal(pendencias("SUPORTE PARA RESISTOR DE FRENAGEM").length, 0);
assert.equal(pendencias("ACESSÓRIO PARA MÓDULO SFP").length, 0);
for (const item of manifesto.itens) {
  assert.equal(normalizarNomeCadastro(item.nome), item.nome);
  const lacunas = pendencias(item.nome);
  assert.equal(lacunas.length, item.id === 3612 ? 1 : 0, `${item.id}: ${lacunas.join("; ")}`);
  if (lacunas.length) assert.ok(item.pendencias.length);
}
const camera = manifesto.itens.find((i) => i.id === 3612);
assert.equal(pendencias(`${camera.nome} USB 3.0`).length, 0);
assert.equal(normalizarNomeCadastro("POTENCIÔMETRO 4,7 kΩ Ø22 mm"), "POTENCIÔMETRO 4,7kΩ Ø22mm");
assert.equal(normalizarNomeCadastro("RESISTOR 30 Ω 925 W"), "RESISTOR 30Ω 925W");
assert.equal(normalizarNomeCadastro("MÓDULO SFP 1000 Mbit/s"), "MÓDULO SFP 1000Mbit/s");
const yaml = fs.readFileSync("docs/padroes-cadastro/catalogo-paineis-eletricos.yaml", "utf8").split("\nhistorico_decisoes:")[0];
assert.match(yaml, /versao_padrao: "1\.35\.0"/);
assert.match(yaml, /decisao: D-035/);
assert.match(yaml, /não gerar enriquecimento automático/);
console.log("D-035: lote de 16 itens, idempotência, concorrência, campos protegidos e regras técnicas aprovados.");
