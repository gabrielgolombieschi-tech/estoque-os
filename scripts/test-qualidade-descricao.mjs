import assert from "node:assert/strict";
import fs from "node:fs";
import { pendenciasDescricaoTecnica, REGRAS_SENSORES_SEGURANCA } from "../lib/itens/qualidadeDescricao.ts";
import { normalizarNomeCadastro } from "../lib/itens/normalizacaoNome.ts";

const pendencias = (descricao, extras = {}) => pendenciasDescricaoTecnica({ descricao, ...extras });
assert.equal(pendencias("CONTATOR 3P 115A 110-127VCA/CC").length, 0);
assert.equal(pendencias("SUPORTE PARA SENSOR FOTOELÉTRICO").length, 0, "Acessório não deve ser validado como sensor");
assert.equal(pendencias("SENSOR INDUSTRIAL 9M").length, 1);
assert.equal(pendencias("SENSOR FOTOELÉTRICO").length, 5);
assert.equal(pendencias("SENSOR ULTRASSÔNICO").length, 4);
assert.equal(pendencias("SENSOR ULTRASSÔNICO UM12-1172211 M12 20-150MM PNP 10-30VCC M12 4 PINOS").length, 0);
assert.equal(pendencias("CORTINA DE LUZ DE SEGURANÇA RECEPTORA").length, 4);
assert.equal(pendencias("CORTINA DE LUZ DE SEGURANÇA RECEPTORA C4-RD ALTURA 1200MM RESOLUÇÃO 30MM ALCANCE 4,5M TIPO 4").length, 0);
assert.equal(pendencias("SWITCH DE REDE INDUSTRIAL", { origem: "STR1-SACM0PR5 TRANSP.-SAF. SWITCH" }).length, 1);
assert.equal(pendencias("SWITCH ETHERNET 5 PORTAS", { grupoCodigo: "SWITCHES_REDE_INDUSTRIAL" }).length, 0);
assert.equal(pendencias("CHAVE DE SEGURANÇA RFID STR1-SACM0PR5 SAO 10MM 2OSSD 24VCC M12 5 PINOS").length, 0);
assert.equal(pendencias("CHAVE DE SEGURANÇA RFID STR1-SACM0PR5 SAO 10MM 2OSSD 24VCC M12 5 PINOS", { grupoCodigo: "SWITCHES_REDE_INDUSTRIAL" }).length, 1);
assert.equal(pendencias("SENSOR RADAR DE SEGURANÇA 9M").length, 1);
assert.equal(pendencias("SENSOR RADAR DE SEGURANÇA ALCANCE 0,2-9M").length, 0);
assert.equal(pendencias("ACOPLAMENTO KUP-0610-B", { codigo: "5312982", modeloReferencia: "KUP-0610-B" }).length, 0);
assert.equal(pendencias("ACOPLAMENTO", { codigo: "5312982", modeloReferencia: "KUP-0610-B" }).length, 1);
assert.equal(pendencias("ACOPLAMENTO", { codigo: "5312982", modeloReferencia: null }).length, 1);
assert.equal(pendencias("SENSOR ULTRASSÔNICO 20-150MM PNP 10-30VCC M12 4 PINOS", { codigo: "6053542" }).length, 0, "Importador não dispõe do campo modelo");
assert.match(REGRAS_SENSORES_SEGURANCA, /tensão do cabo isolado/);
assert.match(REGRAS_SENSORES_SEGURANCA, /120ohms/);
assert.equal(pendencias("CABO PARA SENSOR 5M").length, 6);
assert.equal(pendencias("CABO PARA SENSOR 5M 4X0,34MM² CAPA PUR ISOLAÇÃO PVC SEM BLINDAGEM 250VCA/CC M12 FÊMEA 4 PINOS / PONTA LIVRE").length, 0);
assert.equal(pendencias("ACESSÓRIO PARA SENSOR INDUSTRIAL").length, 1);

const manifesto = JSON.parse(fs.readFileSync("docs/padroes-cadastro/revisao-sick-2026-09-05.json", "utf8"));
assert.equal(manifesto.itens.length, 21);
assert.equal(new Set(manifesto.itens.map((i) => i.id)).size, 21);
for (const item of manifesto.itens) {
  assert.equal(normalizarNomeCadastro(item.nome), item.nome);
  assert.ok(item.nome.length <= 255);
  assert.ok(item.fontes.every((f) => new URL(f).hostname === "www.sick.com"));
  if (pendencias(item.nome, { grupoCodigo: item.grupo_codigo }).length) {
    assert.ok(item.pendencias.length, `Lacuna deve estar documentada: ${item.codigo}`);
  }
}
console.log("Qualidade de descrição: 23 verificações e 21 itens do manifesto aprovados.");
