import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
import {tenantId,empresaId,diretorio,validarEscopo,impressaoTecnica} from './lib/controle-revisoes.mjs';
import {hash051,conferirPreservacao051,camposPermitidos051} from './lib/campanha-051.mjs';
const m=JSON.parse(fs.readFileSync(`${diretorio}/campanha-051-plano.json`,'utf8'));validarEscopo(m);
const base=JSON.parse(fs.readFileSync(m.base,'utf8'));validarEscopo(base);assert.equal(hash051(base),m.base_sha256);
const assinatura=hash051(m),aplicar=process.argv.includes('--apply');
if(aplicar)assert.equal(process.argv.find(a=>a.startsWith('--assinatura='))?.split('=')[1],assinatura,'Assinatura do plano obrigatória');
const destino=`${diretorio}/campanha-051-resultado.json`;
assert.ok(!fs.existsSync(destino),'Já encerrado: usar verificação, não reaplicar.');
const env=Object.fromEntries(fs.readFileSync('.env.local','utf8').split(/\r?\n/).filter(l=>l.includes('=')&&!l.trim().startsWith('#')).map(l=>{const p=l.indexOf('=');return[l.slice(0,p).trim(),l.slice(p+1).trim().replace(/^(["'])(.*)\1$/,'$2')];}));
const db=createClient(env.NEXT_PUBLIC_SUPABASE_URL,env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});
const scope=q=>q.eq('tenant_id',tenantId).eq('empresa_id',empresaId);
async function ler(tabela){const rows=[];for(let offset=0;;offset+=1000){const {data,error}=await scope(db.from(tabela).select('*')).order('id').range(offset,offset+999);if(error)throw Error(error.message);rows.push(...data);if(data.length<1000)return rows;}}
const [atuais,fiscais,grupos]=await Promise.all([ler('itens'),ler('fiscal_itens'),ler('item_grupos')]);
const ignorados=[],planos=[];
for(const r of m.itens.filter(r=>Object.keys(r.alteracoes).length)){
 assert.ok(['melhoria_parcial','revisao_tecnica_confirmada'].includes(r.situacao));
 assert.ok(Object.keys(r.alteracoes).every(c=>camposPermitidos051.includes(c)));
 const antes=atuais.find(i=>i.id===r.id);if(!antes||impressaoTecnica(antes)!==r.impressao_antes){ignorados.push({id:r.id,motivo:'Dados técnicos mudaram depois da fotografia; não sobrescrever.'});continue;}
 validarEscopo(antes);
 if(r.alteracoes.grupo_id){const g=grupos.find(g=>g.id===r.alteracoes.grupo_id);assert.ok(g&&g.ativo!==false,'Grupo inexistente/inativo');validarEscopo(g);}
 planos.push({r,antes});
}
console.log(JSON.stringify({assinatura,planejados:planos.length,ignorados,modo:aplicar?'aplicacao':'somente_leitura'}));
if(!aplicar)process.exit(0);
const backup=`backups/campanha-051/aplicacao-${new Date().toISOString().replace(/[:.]/g,'-')}.json`;
fs.writeFileSync(backup,JSON.stringify({tenant_id:tenantId,empresa_id:empresaId,assinatura,manifesto:m,itens:atuais,fiscal_itens:fiscais},null,2),{flag:'wx'});
const aplicados=[],falhas=[];
for(let pos=0;pos<planos.length;pos+=4){
 const resultados=await Promise.all(planos.slice(pos,pos+4).map(async({r,antes})=>{
  let q=scope(db.from('itens').update(r.alteracoes)).eq('id',r.id);
  for(const c of ['codigo_interno','nome','descricao','atualizado_em','updated_at','ativo','grupo_id','fornecedor_id','fabricante','unidade_medida','unidade_compra','fator_conversao_estoque','ncm','preco_unitario'])q=antes[c]==null?q.is(c,null):q.eq(c,antes[c]);
  const {data,error}=await q.select('*');
  if(error||data?.length!==1)return {id:r.id,erro:error?.message??'Concorrência: registro preservado'};
  // Diário persistido antes da validação, inclusive se um trigger modificar campo inesperado.
  fs.appendFileSync(`${backup}.resultado.jsonl`,JSON.stringify({id:r.id,depois:data[0]})+'\n');
  conferirPreservacao051(antes,data[0],r.alteracoes);
  return {id:r.id,impressao_depois:impressaoTecnica(data[0]),nome:data[0].nome};
 }));
 for(const r of resultados)(r.erro?falhas:aplicados).push(r);
 if(pos%100===0||pos+4>=planos.length)console.log(JSON.stringify({aplicados:aplicados.length,falhas:falhas.length,total:planos.length}));
 if(falhas.length)break;
}
const [depois,fiscalDepois]=await Promise.all([ler('itens'),ler('fiscal_itens')]);
for(const r of aplicados){const p=planos.find(p=>p.r.id===r.id);conferirPreservacao051(p.antes,depois.find(i=>i.id===r.id),p.r.alteracoes);}
assert.deepEqual(fiscalDepois,fiscais,'Dados fiscais sofreram mudança concorrente; não certificar preservação sem análise.');
const preservados=atuais.filter(i=>!aplicados.some(a=>a.id===i.id));
const concorrentes=preservados.filter(i=>hash051(i)!==hash051(depois.find(d=>d.id===i.id))).map(i=>i.id);
const resultado={tenant_id:tenantId,empresa_id:empresaId,decisao:'D-051',status:falhas.length?'parcial_com_falhas':'aplicado_verificado',verificado_em:new Date().toISOString(),assinatura,backup,aplicados,ignorados,falhas,nao_processados:planos.filter(p=>!aplicados.some(a=>a.id===p.r.id)&&!falhas.some(a=>a.id===p.r.id)).map(p=>p.r.id),fiscais_preservados:fiscais.length,itens_nao_alterados_pela_campanha:preservados.length,alteracoes_concorrentes_fora_lote:concorrentes,itens_atuais:depois};
fs.writeFileSync(destino,JSON.stringify(resultado,null,2),{flag:'wx'});
console.log(JSON.stringify({...resultado,itens_atuais:undefined,aplicados:aplicados.length}));
