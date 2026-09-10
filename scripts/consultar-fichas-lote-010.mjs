import fs from "node:fs";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { validarEscopo,diretorio } from "./lib/controle-revisoes.mjs";
// Apenas documentos públicos. A seleção usa base local com escopo validado.
const base=JSON.parse(fs.readFileSync("backups/base-revisao/2026-09-09T21-16-35-648Z.json","utf8"));
validarEscopo(base);
const eventos=fs.readdirSync(diretorio).filter(f=>/^eventos-.*\.json$/.test(f)).flatMap(f=>JSON.parse(fs.readFileSync(`${diretorio}/${f}`,"utf8")));
eventos.forEach(validarEscopo);
const candidatos=base.itens.filter(i=>i.ativo && i.grupo_id && (/^3SU/.test(i.codigo_interno)||[1627,2454,3567].includes(i.id)) && !eventos.some(e=>e.item_id===i.id));
assert.equal(candidatos.length,50);
const pasta="backups/fontes-lote-010",bin="backups/fontes-lotes-003-004/poppler/poppler-26.07.0/Library/bin";
fs.mkdirSync(pasta,{recursive:true});
for(let k=0;k<candidatos.length;k+=4) {
  const resultados=await Promise.allSettled(candidatos.slice(k,k+4).map(async i=>{
    validarEscopo(i);
    const arquivo=`${pasta}/${i.id}.pdf`,url=`https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=${i.codigo_interno}`;
    if(!fs.existsSync(arquivo)) {
      const r=await fetch(url,{signal:AbortSignal.timeout(45000)});
      if(!r.ok) throw new Error(`${i.id}: HTTP ${r.status}`);
      const bytes=Buffer.from(await r.arrayBuffer());
      assert.equal(bytes.subarray(0,5).toString(),"%PDF-");
      fs.writeFileSync(arquivo,bytes,{flag:"wx"});
      fs.writeFileSync(`${pasta}/${i.id}.fonte.json`,JSON.stringify({url,consultado_em:new Date().toISOString()},null,2),{flag:"wx"});
    }
    execFileSync(`${bin}/pdftotext.exe`,["-layout",arquivo,`${pasta}/${i.id}.txt`],{stdio:"ignore"});
    execFileSync(`${bin}/pdftoppm.exe`,["-f","1","-l","1","-scale-to","1500","-singlefile","-png",arquivo,`${pasta}/${i.id}-p1`],{stdio:"ignore"});
    console.log(`${i.id}: ${i.codigo_interno}`);
  }));
  for(const r of resultados) if(r.status==="rejected") console.log(`PENDENTE: ${r.reason.message}`);
}
