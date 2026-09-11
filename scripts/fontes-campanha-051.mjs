import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
const dir='backups/campanha-051/fontes';fs.mkdirSync(dir,{recursive:true});
const bin='backups/fontes-lotes-003-004/poppler/poppler-26.07.0/Library/bin';
const fontes={brm:'https://brm.com.br/wp-content/uploads/2025/06/Catalogo-BRM-Outubro-2023_compressed.pdf'};
for(const [id,url] of Object.entries(fontes)){
 const path=`${dir}/${id}.pdf`;
 if(!fs.existsSync(path)){const r=await fetch(url);if(!r.ok)throw Error(`${id}: ${r.status}`);fs.writeFileSync(path,Buffer.from(await r.arrayBuffer()));}
 execFileSync(`${bin}/pdftotext.exe`,['-layout',path,`${dir}/${id}.txt`]);
 fs.writeFileSync(`${dir}/${id}.fonte.json`,JSON.stringify({url,consultado_em:new Date().toISOString()}));
 const pages=fs.readFileSync(`${dir}/${id}.txt`,'utf8').split('\f');
 for(let p=0;p<pages.length;p++)if(/UC[PFTL ]*210|UCP 205|UCFL 210|UC 210|UCF 205/.test(pages[p])){
 console.log(id,'pagina',p+1,pages[p].split('\n').filter(l=>/210|205|206|209|UCP|UCFL|UCF/.test(l)).join('\n'));
 execFileSync(`${bin}/pdftoppm.exe`,['-f',String(p+1),'-l',String(p+1),'-scale-to','1700','-singlefile','-png',path,`${dir}/${id}-p${p+1}`]);}
}
