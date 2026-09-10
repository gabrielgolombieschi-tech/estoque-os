import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
import {tenantId,empresaId,diretorio,impressaoTecnica} from './lib/controle-revisoes.mjs';
import {conferirCinquenta} from './lib/lotes-cinquenta.mjs';
import {validar048,planejar048,hash048} from './lib/reavaliacao-048.mjs';
const m=JSON.parse(fs.readFileSync(`${diretorio}/reavaliacao-048.json`,'utf8'));validar048(m);
const base=JSON.parse(fs.readFileSync(m.base,'utf8'));
const env=Object.fromEntries(fs.readFileSync('.env.local','utf8').split(/\r?\n/).filter(l=>l.includes('=')&&!l.trim().startsWith('#')).map(l=>{const p=l.indexOf('=');return [l.slice(0,p).trim(),l.slice(p+1).trim().replace(/^(["'])(.*)\1$/,'$2')];}));
const db=createClient(env.NEXT_PUBLIC_SUPABASE_URL,env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});
const scope=q=>q.eq('tenant_id',tenantId).eq('empresa_id',empresaId);
async function ler(tabela){const {data,error}=await scope(db.from(tabela).select('*')).in(tabela==='itens'?'id':'item_id',base.itens.map(i=>i.id));if(error)throw new Error(error.message);return data;}
const atuais=await ler('itens'),fiscais=await ler('fiscal_itens'),plano=planejar048(m,atuais),alterar=plano.filter(p=>!p.aplicado);
for(const f of fiscais)assert.deepEqual(f,base.fiscal_itens.find(a=>a.item_id===f.item_id),'Fiscal mudou desde a comparação; refazer análise');
assert.equal(fiscais.length,base.fiscal_itens.length);
const semAlteracao=atuais.filter(i=>!m.itens.some(p=>p.id===i.id));
for(const i of semAlteracao)assert.equal(impressaoTecnica(i),impressaoTecnica(base.itens.find(a=>a.id===i.id)),'Pendente/duplicado sofreu mudança técnica');
console.log(JSON.stringify({claros:plano.length,a_alterar:alterar.length,pendentes:m.pendentes.length,duplicados_sem_marcacao:m.pares.length*2}));
if(process.argv.includes('--verify'))assert.equal(alterar.length,0);
if(process.argv.includes('--apply')){
 let backup=null;
 if(alterar.length){backup=`backups/reavaliacao-048/aplicacao-${new Date().toISOString().replace(/[:.]/g,'-')}.json`;fs.writeFileSync(backup,JSON.stringify({tenant_id:tenantId,empresa_id:empresaId,manifesto:m,atuais,fiscais},null,2),{flag:'wx'});
  for(const p of alterar){let q=scope(db.from('itens').update(p.depois));for(const c of ['id','codigo_interno','nome','descricao','atualizado_em','updated_at','ativo','grupo_id','fornecedor_id','fabricante','unidade_medida','unidade_compra','fator_conversao_estoque','ncm','preco_unitario'])q=p.antes[c]==null?q.is(c,null):q.eq(c,p.antes[c]);const {data,error}=await q.select('*');if(error||data?.length!==1)throw new Error(`Parou no ID ${p.item.id}: ${error?.message??'concorrência'}`);fs.appendFileSync(`${backup}.resultado.jsonl`,JSON.stringify(data[0])+'\n');conferirCinquenta(p,data[0]);}
 }
 const depois=await ler('itens');for(const p of plano)conferirCinquenta(p,depois.find(i=>i.id===p.item.id));for(const i of semAlteracao)assert.deepEqual(depois.find(a=>a.id===i.id),i);assert.deepEqual((await ler('fiscal_itens')).sort((a,b)=>a.id-b.id),fiscais.sort((a,b)=>a.id-b.id));
 const destino=`${diretorio}/eventos-${m.lote}.json`;
 const eventos=plano.map(p=>({tenant_id:tenantId,empresa_id:empresaId,item_id:p.item.id,codigo:p.antes.codigo_interno,nome:p.depois.nome,familia:p.item.familia,criterio:p.item.criterio,lote:m.lote,revisado_em:new Date().toISOString(),responsavel:'Codex: reavaliação D-048 sob continuidade autorizada D-047',status:'aprovado',origem_aprovacao:'autorizacao_condicional_D-048',fontes:p.item.fontes,pendencias:[],atributos_nao_confirmados:p.item.limites_nao_bloqueantes,impressao_tecnica:impressaoTecnica(depois.find(i=>i.id===p.item.id)),backup,assinatura_lote:hash048}));
 if(fs.existsSync(destino)){const anteriores=JSON.parse(fs.readFileSync(destino,'utf8'));assert.equal(anteriores.length,eventos.length);for(const e of eventos)assert.equal(anteriores.find(a=>a.item_id===e.item_id)?.impressao_tecnica,e.impressao_tecnica);}else fs.writeFileSync(destino,JSON.stringify(eventos,null,2),{flag:'wx'});
 console.log(JSON.stringify({atualizados:alterar.length,verificados:plano.length,fiscais_preservados:fiscais.length,demais_intactos:semAlteracao.length,backup}));
}
