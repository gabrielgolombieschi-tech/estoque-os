import fs from "node:fs";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { diretorio, criterios } from "./lib/controle-revisoes.mjs";
import { ids003,ids004,ids005,ids006,ids007,ids008,familiasNovas008,validarCinquenta,exigirAutorizacao,planejarCinquenta,conferirCinquenta,assinatura } from "./lib/lotes-cinquenta.mjs";
const m = JSON.parse(fs.readFileSync(`${diretorio}/lote-008-cinquenta-itens.json`,"utf8"));
validarCinquenta(m);
assert.equal(assinatura(m),"86c374ac97fe7099f31182b085b7d533cb89015861bf670368d7ec14524feb9b");
assert.equal(new Set([...ids003,...ids004,...ids005,...ids006,...ids007,...ids008]).size,300);
assert.throws(()=>exigirAutorizacao(m),/aprovação humana/);
const aprovada007 = JSON.parse(fs.readFileSync(`${diretorio}/aprovacao-007.json`,"utf8"));
assert.throws(()=>exigirAutorizacao(m,aprovada007));
const aprovada008 = JSON.parse(fs.readFileSync(`${diretorio}/aprovacao-008.json`,"utf8"));
exigirAutorizacao(m,aprovada008);
assert.throws(()=>exigirAutorizacao({...m,autorizacao:"aprovado"},aprovada008),/mudou após aprovação/);
assert.throws(()=>exigirAutorizacao(m,{...aprovada008,empresa_id:"outra"}));
for (const f of familiasNovas008) assert.equal(criterios[f],`${f}:1`);
const plano = planejarCinquenta(m,m.itens.map(i=>i.antes));
assert.ok(plano.every(p=>!p.aplicado));
assert.ok(planejarCinquenta(m,m.itens.map(i=>({...i.antes,...i.depois}))).every(p=>p.aplicado));
for (const campo of ["grupo_id","empresa_id","fator_conversao_estoque","nome","ativo"]) {
  const alterados = structuredClone(m.itens.map(i=>i.antes));
  alterados[0][campo] = campo==="ativo"?false:"divergente";
  assert.throws(()=>planejarCinquenta(m,alterados));
}
assert.throws(()=>conferirCinquenta(plano[0],{...plano[0].antes,...plano[0].depois,grupo_id:999}));
const eventos = fs.readdirSync(diretorio).filter(f=>/^eventos-.*\.json$/.test(f)).flatMap(f=>JSON.parse(fs.readFileSync(`${diretorio}/${f}`,"utf8")));
for (const i of m.itens) {
  assert.ok(!eventos.some(e=>e.item_id===i.id && e.lote!==m.lote));
  assert.equal(createHash("sha256").update(fs.readFileSync(i.evidencia.arquivo)).digest("hex"),i.evidencia.sha256);
  for (const p of i.evidencia.paginas) assert.ok(fs.existsSync(`backups/fontes-lote-008/${i.id}-p${p}.png`));
  if (i.antes.descricao) assert.ok(i.depois.descricao.includes(i.antes.descricao));
}
const item = id=>m.itens.find(i=>i.id===id);
assert.match(item(190).descricao_tecnica,/Sem entradas ou saídas analógicas integradas.*programa 250KB, dados 750KB/);
assert.match(item(1093).descricao_tecnica,/não são doze entradas independentes/);
assert.match(item(1091).descricao_tecnica,/1-5V 13bit; 4-20mA 14bit/);
assert.match(item(913).nome,/14BIT.*13BIT/);
assert.match(item(3434).nome,/NOVO GRUPO/);
assert.match(item(3435).nome,/CONTINUA GRUPO/);
assert.match(item(3439).nome,/SEM BUSADAPTER/);
assert.equal(item(3733).antes.grupo_id,55);
assert.ok(!ids008.includes(2461));
const relatorio = fs.readFileSync(`${diretorio}/lote-008-cinquenta-itens.md`,"utf8");
assert.equal(relatorio.split("\n").filter(l=>/^\| \d+ \|/.test(l)).length,50);
console.log("OK: lote 008 aprovado por conteúdo exato, 300 IDs distintos, fichas íntegras, grupos/conversões protegidos e concorrência.");
