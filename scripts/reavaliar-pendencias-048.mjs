import fs from 'node:fs';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createClient} from '@supabase/supabase-js';
import {tenantId,empresaId,diretorio} from './lib/controle-revisoes.mjs';
const env=Object.fromEntries(fs.readFileSync('.env.local','utf8').split(/\r?\n/).filter(l=>l.includes('=')&&!l.trim().startsWith('#')).map(l=>{const p=l.indexOf('=');return [l.slice(0,p).trim(),l.slice(p+1).trim().replace(/^(["'])(.*)\1$/,'$2')];}));
const db=createClient(env.NEXT_PUBLIC_SUPABASE_URL,env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});
const ids=JSON.parse(fs.readFileSync(`${diretorio}/excecoes-referencias-claras.json`,'utf8')).itens.map(i=>i.id);
const pasta='backups/reavaliacao-048';fs.mkdirSync(pasta,{recursive:true});
if(process.argv.includes('--origens')){
 const {data,error}=await db.from('nf_entrada_itens').select('item_id,descricao').eq('tenant_id',tenantId).eq('empresa_id',empresaId).in('item_id',[769,1580,1581,1584,1587,2535,2641,2642,2643,2698,2699,2700]);
 if(error)throw new Error(error.message);fs.writeFileSync(`${pasta}/origens-notas.json`,JSON.stringify({tenant_id:tenantId,empresa_id:empresaId,consultado_em:new Date().toISOString(),itens:data},null,2));console.log(JSON.stringify(data));
}
if(process.argv.includes('--consultar')){
 const resultados={tenant_id:tenantId,empresa_id:empresaId,consultado_em:new Date().toISOString()};
 for(const tabela of ['itens','fiscal_itens']){
  const {data,error}=await db.from(tabela).select('*').eq('tenant_id',tenantId).eq('empresa_id',empresaId).in(tabela==='itens'?'id':'item_id',ids);
  if(error)throw new Error(`${tabela}: ${error.message}`);resultados[tabela]=data;
 }
 const arquivo=`${pasta}/cadastro-${new Date().toISOString().replace(/[:.]/g,'-')}.json`;fs.writeFileSync(arquivo,JSON.stringify(resultados,null,2),{flag:'wx'});
 console.log(JSON.stringify({arquivo,itens:resultados.itens.length,fiscais:resultados.fiscal_itens.length,pares:resultados.itens.filter(i=>[2641,2642,2643,2698,2699,2700].includes(i.id)).map(i=>({id:i.id,ncm:i.ncm,fiscal:resultados.fiscal_itens.find(f=>f.item_id===i.id)}))}));
}
if(process.argv.includes('--catalogo')){
 const url='https://cache.industry.siemens.com/dl/files/653/109750653/att_1088610/v1/14_TerminalBlocks_LV10_102021_EN_202111300957253644.pdf';
 const arquivo=`${pasta}/bornes-2021.pdf`;
 if(!fs.existsSync(arquivo)){const r=await fetch(url,{signal:AbortSignal.timeout(60000)});assert.ok(r.ok);const bytes=Buffer.from(await r.arrayBuffer());assert.equal(bytes.subarray(0,5).toString(),'%PDF-');fs.writeFileSync(arquivo,bytes,{flag:'wx'});fs.writeFileSync(`${pasta}/bornes-2021.fonte.json`,JSON.stringify({url,consultado_em:new Date().toISOString()}),{flag:'wx'});}
 execFileSync('backups/fontes-lotes-003-004/poppler/poppler-26.07.0/Library/bin/pdftotext.exe',['-layout',arquivo,`${pasta}/bornes-2021.txt`]);
 console.log('Catálogo de bornes baixado e extraído.');
}
if(process.argv.includes('--fontes'))for(const [nome,url] of [
 ['reles-2025','https://support.industry.siemens.com/cs/attachments/109771997/SIRIUS_IC10_chap05_English_2025_202501240949051090.pdf'],
 ['atuadores-2023','https://cache.industry.siemens.com/dl/files/593/24236593/att_1139519/v1/A5E51063887001A_RS-AB_002_202304240859463018.pdf']
]){
 if(process.argv.some(a=>a.startsWith('--documento='))&&!process.argv.includes(`--documento=${nome}`))continue;
 const arquivo=`${pasta}/${nome}.pdf`;
 if(!fs.existsSync(arquivo)){const r=await fetch(url,{signal:AbortSignal.timeout(60000)});assert.ok(r.ok);const bytes=Buffer.from(await r.arrayBuffer());assert.equal(bytes.subarray(0,5).toString(),'%PDF-');fs.writeFileSync(arquivo,bytes,{flag:'wx'});fs.writeFileSync(`${pasta}/${nome}.fonte.json`,JSON.stringify({url,consultado_em:new Date().toISOString()}),{flag:'wx'});}
 execFileSync('backups/fontes-lotes-003-004/poppler/poppler-26.07.0/Library/bin/pdftotext.exe',['-layout',arquivo,`${pasta}/${nome}.txt`]);console.log(`${nome} extraído`);
}
