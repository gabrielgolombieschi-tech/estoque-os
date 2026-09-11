import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
import {tenantId,empresaId,diretorio,validarEscopo,impressaoTecnica} from './lib/controle-revisoes.mjs';
import {pares049,pendentes049,ids049,depois049,conferir049} from './lib/reservas-049.mjs';

const modo=process.argv[2];assert.ok(['--consultar','--apply','--verify'].includes(modo));
const env=Object.fromEntries(fs.readFileSync('.env.local','utf8').split(/\r?\n/).filter(l=>l.includes('=')&&!l.trim().startsWith('#')).map(l=>{const p=l.indexOf('=');return[l.slice(0,p).trim(),l.slice(p+1).trim().replace(/^(["'])(.*)\1$/,'$2')];}));
const db=createClient(env.NEXT_PUBLIC_SUPABASE_URL,env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});
const scope=q=>q.eq('tenant_id',tenantId).eq('empresa_id',empresaId);
async function ler(tabela){const {data,error}=await scope(db.from(tabela).select('*')).in(tabela==='itens'?'id':'item_id',ids049).order(tabela==='itens'?'id':'item_id');if(error)throw new Error(error.message);data.forEach(validarEscopo);return data;}
const pasta='backups/reservas-049',arquivo=`${pasta}/antes.json`,destino=`${diretorio}/marcacao-reservas-049.json`;
const atuais=await ler('itens'),fiscais=await ler('fiscal_itens');assert.deepEqual(atuais.map(i=>i.id),ids049);
if(modo==='--consultar'){
  for(const p of pares049)for(const id of [p.usar,p.reserva]){const i=atuais.find(i=>i.id===id);assert.equal(i.codigo_interno.replace(/[^a-z0-9]/gi,'').toUpperCase(),p.referencia);assert.equal(i.fornecedor_id,3);assert.equal(i.unidade_medida,'UN');assert.equal(Number(i.fator_conversao_estoque),1);}
  fs.mkdirSync(pasta,{recursive:true});fs.writeFileSync(arquivo,JSON.stringify({tenant_id:tenantId,empresa_id:empresaId,consultado_em:new Date().toISOString(),itens:atuais,fiscal_itens:fiscais},null,2),{flag:'wx'});
  console.log(JSON.stringify({backup:arquivo,itens:atuais.map(({id,codigo_interno,nome,ncm,ativo})=>({id,codigo_interno,nome,ncm,ativo}))}));
}else{
  const base=JSON.parse(fs.readFileSync(arquivo,'utf8'));validarEscopo(base);assert.deepEqual(base.itens.map(i=>i.id),ids049);assert.deepEqual(fiscais,base.fiscal_itens);
  const alterar=[];
  for(const i of atuais){const antes=base.itens.find(a=>a.id===i.id),reserva=pares049.some(p=>p.reserva===i.id),aplicado=reserva&&i.codigo_interno===depois049(i).codigo_interno;
    conferir049(antes,i,aplicado);if(reserva&&!aplicado)alterar.push(i);
  }
  const {data:colisoes,error}=await scope(db.from('itens').select('id,codigo_interno')).eq('fornecedor_id',3).in('codigo_interno',pares049.map(p=>`RESERVA-${p.reserva}`));if(error)throw new Error(error.message);
  for(const i of colisoes)assert.equal(i.codigo_interno,`RESERVA-${i.id}`,'Código ocupado por outro cadastro');
  if(modo==='--verify')assert.equal(alterar.length,0);
  if(modo==='--apply')for(const i of alterar){
    let q=scope(db.from('itens').update(depois049(i)));
    for(const [c,v] of Object.entries(i))if(v===null)q=q.is(c,null);else if(['string','number','boolean'].includes(typeof v))q=q.eq(c,v);
    const {data,error}=await q.select('*');if(error||data?.length!==1)throw new Error(`Parou no ID ${i.id}: ${error?.message??'mudança concorrente'}`);
    fs.appendFileSync(`${pasta}/resultado.jsonl`,JSON.stringify({registrado_em:new Date().toISOString(),antes:i,depois:data[0]})+'\n');conferir049(i,data[0],true);
  }
  const depois=await ler('itens');
  for(const antes of base.itens)conferir049(antes,depois.find(i=>i.id===antes.id),pares049.some(p=>p.reserva===antes.id));
  assert.deepEqual(await ler('fiscal_itens'),base.fiscal_itens);
  if(!fs.existsSync(destino)){
    assert.equal(modo,'--apply');
    const registro={tenant_id:tenantId,empresa_id:empresaId,decisao:'D-049',status:'aplicado_verificado',aplicado_em:new Date().toISOString(),autorizacao:'pode aplicar.... os outros deixa pendente... depois vemos',escopo:'Somente nome e codigo_interno dos três duplicados. Principais preservados. Sem aprovação técnica/fiscal implícita.',backup:arquivo,pendentes:pendentes049,pares:pares049.map(p=>({...p,antes:base.itens.find(i=>i.id===p.reserva),depois:depois.find(i=>i.id===p.reserva),principal_preservado:depois.find(i=>i.id===p.usar),impressao_tecnica:impressaoTecnica(depois.find(i=>i.id===p.reserva))}))};
    fs.writeFileSync(destino,JSON.stringify(registro,null,2),{flag:'wx'});
  }else{const r=JSON.parse(fs.readFileSync(destino,'utf8'));validarEscopo(r);assert.equal(r.status,'aplicado_verificado');for(const p of r.pares)assert.deepEqual(p.depois,depois.find(i=>i.id===p.reserva));}
  console.log(JSON.stringify({alterados:modo==='--apply'?alterar.length:0,reservas_verificadas:3,principais_intactos:3,pendentes_intactos:pendentes049.length,fiscais_preservados:fiscais.length,registro:destino}));
}
