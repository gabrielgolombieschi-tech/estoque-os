import fs from 'node:fs';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {validarEscopo} from './lib/controle-revisoes.mjs';
const base=JSON.parse(fs.readFileSync('backups/base-revisao/2026-09-10T17-44-54-468Z.json','utf8'));
validarEscopo(base);
const ids=[447,800,769,1580,1581,1584,1587];
const pasta='backups/fontes-complemento-paineis',bin='backups/fontes-lotes-003-004/poppler/poppler-26.07.0/Library/bin';
fs.mkdirSync(pasta,{recursive:true});
for(const id of ids){
 const i=base.itens.find(i=>i.id===id);validarEscopo(i);
 const url=`https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=${encodeURIComponent(i.codigo_interno)}`;
 const arquivo=`${pasta}/${id}.pdf`;
 try{
  if(!fs.existsSync(arquivo)){
   const r=await fetch(url,{signal:AbortSignal.timeout(45000)});
   if(!r.ok)throw new Error(`HTTP ${r.status}`);
   const bytes=Buffer.from(await r.arrayBuffer());assert.equal(bytes.subarray(0,5).toString(),'%PDF-');
   fs.writeFileSync(arquivo,bytes,{flag:'wx'});
   fs.writeFileSync(`${pasta}/${id}.fonte.json`,JSON.stringify({url,consultado_em:new Date().toISOString()}),{flag:'wx'});
  }
  execFileSync(`${bin}/pdftotext.exe`,['-layout',arquivo,`${pasta}/${id}.txt`]);
  for(const page of id===800?[1,2]:[1])execFileSync(`${bin}/pdftoppm.exe`,['-f',String(page),'-l',String(page),'-scale-to','1500','-singlefile','-png',arquivo,`${pasta}/${id}-p${page}`]);
  console.log(`${id}: ficha extraída`);
 }catch(e){fs.writeFileSync(`${pasta}/${id}.falha.json`,JSON.stringify({id,codigo:i.codigo_interno,url,erro:e.message,consultado_em:new Date().toISOString()},null,2));console.log(`${id}: ${e.message}`);}
}
