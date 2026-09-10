import fs from "node:fs";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { diretorio,criterios } from "./lib/controle-revisoes.mjs";
import { ids003,ids004,ids005,ids006,ids007,ids008,ids009,grupos009,validarCinquenta,exigirAutorizacao,planejarCinquenta,conferirCinquenta,assinatura } from "./lib/lotes-cinquenta.mjs";
const m = JSON.parse(fs.readFileSync(`${diretorio}/lote-009-cinquenta-itens.json`,"utf8"));
validarCinquenta(m);
assert.equal(assinatura(m),"714df3a7c6a7ecd536a4e4be40768b1142f7854d5cd5f7e86f5d1db237d7d87b");
assert.equal(new Set([...ids003,...ids004,...ids005,...ids006,...ids007,...ids008,...ids009]).size,350);
assert.throws(()=>exigirAutorizacao(m),/aprovação humana/);
const a8 = JSON.parse(fs.readFileSync(`${diretorio}/aprovacao-008.json`,"utf8"));
assert.throws(()=>exigirAutorizacao(m,a8));
const a9 = JSON.parse(fs.readFileSync(`${diretorio}/aprovacao-009.json`,"utf8"));
exigirAutorizacao(m,a9);
assert.throws(()=>exigirAutorizacao({...m,autorizacao:"aprovado"},a9),/mudou após aprovação/);
assert.throws(()=>exigirAutorizacao(m,{...a9,empresa_id:"outra"}));
// Nunca executar --apply de lote aprovado dentro de testes.
const plano = planejarCinquenta(m,m.itens.map(i=>i.antes));
assert.ok(plano.every(p=>!p.aplicado));
assert.ok(planejarCinquenta(m,m.itens.map(i=>({...i.antes,...i.depois}))).every(p=>p.aplicado));
for (const campo of ["grupo_id","empresa_id","tenant_id","unidade_medida","fator_conversao_estoque","nome","ativo"]) {
  const alterados = structuredClone(m.itens.map(i=>i.antes));
  alterados[0][campo] = campo==="ativo"?false:"divergente";
  assert.throws(()=>planejarCinquenta(m,alterados));
}
assert.throws(()=>conferirCinquenta(plano[0],{...plano[0].antes,...plano[0].depois,grupo_id:999}));
const eventos = fs.readdirSync(diretorio).filter(f=>/^eventos-.*\.json$/.test(f)).flatMap(f=>JSON.parse(fs.readFileSync(`${diretorio}/${f}`,"utf8")));
for (const i of m.itens) {
  assert.ok(!eventos.some(e=>e.item_id===i.id && e.lote!==m.lote));
  assert.equal(createHash("sha256").update(fs.readFileSync(i.evidencia.arquivo)).digest("hex"),i.evidencia.sha256);
  const prefixo = i.evidencia.arquivo.slice(0,-4);
  const texto = fs.readFileSync(`${prefixo}.txt`,"utf8");
  assert.ok(texto.includes(i.antes.codigo_interno));
  assert.ok(texto.replace(/\s/g,"").toUpperCase().includes(i.referencia.toUpperCase()));
  for(const p of i.evidencia.paginas) assert.ok(fs.existsSync(`${prefixo}-p${p}.png`));
  assert.ok(i.depois.descricao.includes(i.antes.nome));
  if(i.antes.descricao) assert.ok(i.depois.descricao.includes(i.antes.descricao));
}
for(const f of Object.keys(grupos009)) assert.equal(criterios[f],`${f}:1`);
const item = id=>m.itens.find(i=>i.id===id);
assert.match(item(423).nome,/30VCA\/CC/);
assert.match(item(440).nome,/PVC.*250VCA\/CC/);
for(const id of [1712,1715]) assert.match(item(id).nome,/15-30VCC EM 0-10V/);
assert.match(item(434).descricao_tecnica,/500mA/);
assert.match(item(1700).descricao_tecnica,/300mA/);
assert.match(item(1708).descricao_tecnica,/PARCIAL.*2015/);
assert.equal(item(1708).atributos_nao_confirmados.length,2);
assert.match(item(438).descricao_tecnica,/38mm/);
assert.match(item(1714).descricao_tecnica,/não é saída resistiva/);
assert.match(item(439).descricao_tecnica,/IP65 no eixo/);
const relatorio = fs.readFileSync(`${diretorio}/lote-009-cinquenta-itens.md`,"utf8");
assert.equal(relatorio.split("\n").filter(l=>/^\| \d+ \|/.test(l)).length,50);
console.log("OK: lote 009 aprovado por conteúdo exato, 350 IDs distintos, PDFs/modelos exatos, ressalvas e campos protegidos.");
