import fs from "node:fs";
import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {spawnSync} from "node:child_process";
import yaml from "js-yaml";
import {diretorio,criterios} from "./lib/controle-revisoes.mjs";
import {ids011,grupos011,validarCinquenta,exigirAutorizacao,planejarCinquenta,conferirCinquenta,assinatura} from "./lib/lotes-cinquenta.mjs";
const m=JSON.parse(fs.readFileSync(`${diretorio}/lote-011-cinquenta-itens.json`,"utf8")); validarCinquenta(m);
assert.equal(assinatura(m),"588f94f2467f6f9871276cb46677686cf52c6284dbd131e701b0432552417219");
const ids=fs.readdirSync(diretorio).filter(f=>/^lote-00[3-9]-cinquenta-itens.json$|^lote-01[01]-cinquenta-itens.json$/.test(f)).flatMap(f=>JSON.parse(fs.readFileSync(`${diretorio}/${f}`,"utf8")).itens.map(i=>i.id));
assert.equal(ids.length,450); assert.equal(new Set(ids).size,450);
const a10=JSON.parse(fs.readFileSync(`${diretorio}/aprovacao-010.json`,"utf8"));
assert.throws(()=>exigirAutorizacao(m),/nova aprovação humana/);
assert.throws(()=>exigirAutorizacao(m,a10),/nova aprovação humana/);
assert.throws(()=>exigirAutorizacao({...m,autorizacao:"aprovado"},{...a10,lote:m.lote,assinatura_lote:assinatura(m)}),/nova aprovação humana/);
// Somente lote NÃO aprovado: comprovar bloqueio antes de conexão. Nunca testar apply 010.
const r=spawnSync(process.execPath,["scripts/aplicar-lote-cinquenta.mjs","--lote=011","--apply"],{encoding:"utf8"});
assert.notEqual(r.status,0); assert.match(r.stderr,/Lote 011 exige nova aprovação humana/);
const atuais=m.itens.map(i=>i.antes),plano=planejarCinquenta(m,atuais);
assert.ok(plano.every(p=>!p.aplicado));
assert.ok(planejarCinquenta(m,m.itens.map(i=>({...i.antes,...i.depois}))).every(p=>p.aplicado));
for(const campo of ["tenant_id","empresa_id","codigo_interno","grupo_id","ativo","unidade_medida","fator_conversao_estoque","nome","descricao"]){const mudados=structuredClone(atuais); mudados[0][campo]=campo==="ativo"?false:"divergente"; assert.throws(()=>planejarCinquenta(m,mudados));}
assert.throws(()=>conferirCinquenta(plano[0],{...plano[0].antes,...plano[0].depois,preco:999}));
const eventos=fs.readdirSync(diretorio).filter(f=>/^eventos-.*\.json$/.test(f)).flatMap(f=>JSON.parse(fs.readFileSync(`${diretorio}/${f}`,"utf8")));
for(const i of m.itens){
  assert.ok(ids011.includes(i.id)); assert.ok(!eventos.some(e=>e.item_id===i.id && e.lote!==m.lote));
  assert.equal(createHash("sha256").update(fs.readFileSync(i.evidencia.arquivo)).digest("hex"),i.evidencia.sha256);
  const prefixo=i.evidencia.arquivo.slice(0,-4); assert.ok(fs.readFileSync(`${prefixo}.txt`,"utf8").includes(i.referencia));
  for(const p of i.evidencia.paginas) assert.ok(fs.existsSync(`${prefixo}-p${p}.png`));
  assert.ok(i.depois.descricao.includes(i.antes.nome));
  if(i.antes.descricao) assert.ok(i.depois.descricao.includes(i.antes.descricao));
}
for(const familia of Object.keys(grupos011)) assert.equal(criterios[familia],["ATUADORES_CHAVES_SEGURANCA","INTERRUPTORES_DR","CONEXOES_PARTIDA","FONTES_ALIMENTACAO","RELES_INTERFACE","RELES_MONITORAMENTO"].includes(familia)?`${familia}:1`:undefined);
const item=id=>m.itens.find(i=>i.id===id);
for(const id of [226,227,737,2135]) {assert.match(item(id).nome,/50Hz/); assert.ok(!item(id).nome.includes("60Hz"));}
for(const id of [738,744,745,816]) assert.match(item(id).nome,/60Hz/);
assert.match(item(922).nome,/100-120\/200-240VCA/);
assert.match(item(925).descricao_tecnica,/contínua admissível 85-264VCA/);
assert.match(item(926).nome,/3F 400-500VCA/);
assert.match(item(256).nome,/67mm/); assert.match(item(346).nome,/77mm/);
assert.match(item(1616).nome,/PROTEÇÃO PE/); assert.ok(!item(1616).nome.includes("PEN"));
assert.match(item(2535).descricao_tecnica,/embalagem de 50 unidades/);
for(const id of [944,1616,1618,957,1619]){assert.match(item(id).descricao_tecnica,/PARCIAL/); assert.ok(item(id).atributos_nao_confirmados.length);}
assert.match(item(2641).descricao_tecnica,/2698/);
assert.match(item(1623).descricao_tecnica,/Sem interface PC/);
const relatorio=fs.readFileSync(`${diretorio}/lote-011-cinquenta-itens.md`,"utf8");
assert.equal(relatorio.split("\n").filter(l=>/^\| \d+ \|/.test(l)).length,50);
assert.match(relatorio,/AGUARDANDO SUA APROVAÇÃO — NÃO APLICADO|APLICAÇÃO PARCIAL SOB AUTORIZAÇÃO CONDICIONAL/);
const catalogo=yaml.load(fs.readFileSync("docs/padroes-cadastro/catalogo-paineis-eletricos.yaml","utf8"));
assert.equal(catalogo.versao_padrao,"1.35.0"); assert.equal(catalogo.historico_decisoes.filter(d=>d.id==="D-046").length,1);
assert.equal(catalogo.historico_decisoes.filter(d=>d.id==="D-047").length,1);
console.log("OK: 50 propostas 011, 450 IDs únicos, fontes/páginas íntegras, ressalvas, campos protegidos e aplicação bloqueada antes da conexão.");
