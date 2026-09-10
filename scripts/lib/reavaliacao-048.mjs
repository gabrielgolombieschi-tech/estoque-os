import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {validarEscopo,impressaoTecnica,criterios} from './controle-revisoes.mjs';
import {assinatura} from './lotes-cinquenta.mjs';
import {normalizarNomeCadastro} from '../../lib/itens/normalizacaoNome.ts';
export const hash048='d0e6cd2b9dccc1a8b5081aaf6ef6f47899b299e343827253a58b75906c9f4823';
export function validar048(m){
 validarEscopo(m);assert.equal(m.decisao,'D-048');assert.equal(m.lote,'013-reavaliacao-pendencias');assert.equal(assinatura(m),hash048,'Manifesto alterado');
 assert.deepEqual(m.campos_permitidos,['nome','descricao']);assert.equal(m.itens.length,23);
 const ids=[...m.itens.map(i=>i.id),...m.pendentes,...m.pares.flatMap(p=>[p.usar,p.reserva])];assert.equal(ids.length,36);assert.equal(new Set(ids).size,36);
 for(const i of m.itens){validarEscopo(i.antes);assert.equal(i.id,i.antes.id);assert.equal(i.impressao_antes,impressaoTecnica(i.antes));assert.equal(i.criterio,criterios[i.familia]);assert.deepEqual(Object.keys(i.depois).sort(),['descricao','nome']);assert.equal(i.depois.nome,normalizarNomeCadastro(i.depois.nome));assert.ok(i.depois.nome.length<=255&&i.depois.nome!==i.antes.nome);assert.ok(i.depois.descricao.includes(i.antes.nome));for(const e of i.evidencias)assert.equal(createHash('sha256').update(fs.readFileSync(e.arquivo)).digest('hex'),e.sha256);}
}
export function planejar048(m,atuais){
 validar048(m);return m.itens.map(item=>{const antes=atuais.find(i=>i.id===item.id);assert.ok(antes);validarEscopo(antes);const aplicado=antes.nome===item.depois.nome&&antes.descricao===item.depois.descricao;assert.equal(impressaoTecnica(antes),impressaoTecnica(aplicado?{...item.antes,...item.depois}:item.antes));assert.equal(antes.ativo,item.antes.ativo);return {item,antes,depois:item.depois,aplicado};});
}
