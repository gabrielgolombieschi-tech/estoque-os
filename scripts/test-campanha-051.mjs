import fs from 'node:fs';
import assert from 'node:assert/strict';
import {tenantId,empresaId,impressaoTecnica} from './lib/controle-revisoes.mjs';
import {melhorarRedacao051,grupoMecanico051,conferirPreservacao051,hash051} from './lib/campanha-051.mjs';
const exemplos=[
 ['PARAF SX DIN 933 5.8 RI M 8 X 20 ZB','PARAFUSO SEXTAVADO DIN 933 CLASSE 5.8 ROSCA INTEIRA M8 X 20 ACABAMENTO ZINCADO BRANCO'],
 ['PARAFUSO SEXT.8.8MA 10 X 20MM RI','PARAFUSO SEXTAVADO 8.8MA 10 X 20MM ROSCA INTEIRA'],
 ['PORCA SEXT.ZB M 08','PORCA SEXTAVADA ACABAMENTO ZINCADO BRANCO M08'],
 ['BARRA ROSCADA DIN 975 M 10 X 1 M ZB','BARRA ROSCADA DIN 975 M10 X 1M ACABAMENTO ZINCADO BRANCO'],
 ['PARAF ALLEN DIN 916 S/ CAB. PONTA CONC M 5 X 10','PARAFUSO ALLEN DIN 916 SEM CABEÇA PONTA CÔNCAVA M5 X 10'],
 ['CABO 25G0,5MM² 300/500V','CABO 25G0,5MM² 300/500V'],
 ['CHAVE ALLEN 1,5 A 10,0MM','CHAVE ALLEN 1,5 A 10,0MM'],
 ['NS 35/ 7,5 ZN PERF 2000MM','NS 35/ 7,5 ZN PERF 2000MM'],
 ['EL 1300 ELETROCALHA 100X50 #16 PZ','ELETROCALHA 100X50 #16 PZ EL 1300'],
];
for(const [a,b] of exemplos){assert.equal(melhorarRedacao051(a),b);assert.equal(melhorarRedacao051(b),b,'Idempotência');}
for(const n of ['PORCA CILÍNDRICA TR25X5 BRONZE','PARAFUSO TENSIONADOR P/KIT CORDA CHAVE SEG','PARAFUSO OLHAL P/ CHAVE EMG'])assert.equal(grupoMecanico051(n),null);
const antes={tenant_id:tenantId,empresa_id:empresaId,id:1,nome:'A',descricao:null,grupo_id:null,preco_unitario:10,ncm:'12345678',unidade_medida:'M',fator_conversao_estoque:100,updated_at:'a'};
conferirPreservacao051(antes,{...antes,nome:'B',updated_at:'b'},{nome:'B'});
for(const campo of ['preco_unitario','ncm','fator_conversao_estoque','unidade_medida'])assert.throws(()=>conferirPreservacao051(antes,{...antes,nome:'B',[campo]:99},{nome:'B'}));
assert.throws(()=>conferirPreservacao051(antes,{...antes,empresa_id:'outra'},{nome:'B'}));
const plano=JSON.parse(fs.readFileSync('docs/padroes-cadastro/revisoes/campanha-051-plano.json','utf8'));
const base=JSON.parse(fs.readFileSync(plano.base,'utf8'));
assert.equal(hash051(base),plano.base_sha256);assert.equal(plano.itens.length,base.itens.length);
assert.equal(new Set(plano.itens.map(i=>i.id)).size,plano.itens.length);
for(const r of plano.itens){const i=base.itens.find(i=>i.id===r.id);assert.equal(impressaoTecnica(i),r.impressao_antes);if(Object.keys(r.alteracoes).length){assert.equal(i.tipo,'produto');assert.ok(!/^(RESERVA|USAR)\b/.test(i.nome));assert.notEqual(r.status_anterior,'aprovado');conferirPreservacao051(i,{...i,...r.alteracoes},r.alteracoes);}}
for(const id of [1612,2908,2491,3807,2535,2641,2642,2643])assert.deepEqual(plano.itens.find(i=>i.id===id).alteracoes,{});
assert.equal(plano.itens.find(i=>i.id===3810).alteracoes.grupo_id,142);
assert.match(plano.itens.find(i=>i.id===3817).alteracoes.nome,/BOBINA 24VCA 50\/60Hz/);
assert.match(plano.itens.find(i=>i.id===3717).alteracoes.nome,/MANCAL COMPLETO/);
console.log(`D-051: ${exemplos.length} casos de redação, preservação fiscal/escopo, idempotência e ${plano.itens.length} registros validados.`);
