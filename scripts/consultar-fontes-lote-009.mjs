import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
const lista = JSON.parse(fs.readFileSync('scripts/fontes-lote-009.json','utf8'));
const pasta='backups/fontes-lote-009';
const poppler='backups/fontes-lotes-003-004/poppler/poppler-26.07.0/Library/bin';
fs.mkdirSync(pasta,{recursive:true});
let cursor=0;
await Promise.all(Array.from({length:4},async()=>{
  while(cursor<lista.length){
    const i=lista[cursor++]; if(!i.url) continue;
    const chave=i.arquivo ?? String(i.id);
    const pdf=`${pasta}/${chave}.pdf`;
    try {
      if(!fs.existsSync(pdf)){
        const r=await fetch(i.url,{signal:AbortSignal.timeout(45000)});
        if(!r.ok) throw new Error(`HTTP ${r.status}`);
        const b=Buffer.from(await r.arrayBuffer()); if(b.subarray(0,4).toString()!=='%PDF') throw new Error('Resposta não é PDF');
        fs.writeFileSync(pdf,b,{flag:'wx'});
        fs.writeFileSync(`${pasta}/${chave}.fonte.json`,JSON.stringify({...i,consultado_em:new Date().toISOString()},null,2),{flag:'wx'});
      }
      if(!fs.existsSync(`${pasta}/${chave}.txt`)) execFileSync(`${poppler}/pdftotext.exe`,['-layout',pdf,`${pasta}/${chave}.txt`]);
      const texto=fs.readFileSync(`${pasta}/${chave}.txt`,'utf8');
      if(!texto.includes(i.c)) throw new Error('Código exato ausente na ficha');
      for(const p of i.paginas ?? [2,3]){
        if(texto.split('\f').length<=p) continue;
        if(!fs.existsSync(`${pasta}/${chave}-p${p}.png`)) execFileSync(`${poppler}/pdftoppm.exe`,['-f',String(p),'-l',String(p),'-singlefile','-scale-to','1500','-png',pdf,`${pasta}/${chave}-p${p}`]);
      }
      console.log(JSON.stringify({id:i.id,ok:true}));
    } catch(e){console.log(JSON.stringify({id:i.id,erro:e.message}));}
  }
}));
