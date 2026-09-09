import fs from "node:fs";
import { validarEscopo } from "./lib/controle-revisoes.mjs";
const base = JSON.parse(fs.readFileSync("backups/base-revisao/2026-09-09T19-10-20-018Z.json","utf8"));
validarEscopo(base);
const ids = [949,970,972,974,1102,1103,1104,1105,1106,1107,1108,1114,1397,1398,1597,1730,1805,1806,1807,1808,1809,1872,1873,1878,1879,1883,1884,1960,1961,1968,1969,2174,2175,2215,2224,2225,2227,2228,2314,2329,2350,2351,2352,2359,2497,2522,2523,2554,2861,2924,3213,3309,3324,3329,3408];
const pasta = "backups/fontes-lote-007";
fs.mkdirSync(pasta,{recursive:true});
for(let k=0;k<ids.length;k+=4) {
  const resultados = await Promise.allSettled(ids.slice(k,k+4).map(async id => {
    const item = base.itens.find(i => i.id === id);
    validarEscopo(item);
    const path = `${pasta}/${id}.html`;
    if(fs.existsSync(path)) return;
    const url = `https://www.weg.net/catalog/weg/BR/pt/p/${item.codigo_interno}`;
    const r = await fetch(url,{signal:AbortSignal.timeout(35000)});
    if(!r.ok) throw new Error(`${id}: HTTP ${r.status}`);
    const html = await r.text();
    if(!html.includes('product-card-title')) throw new Error(`${id}: página não identificada`);
    fs.writeFileSync(path,html,{flag:"wx"});
    fs.writeFileSync(`${pasta}/${id}.fonte.json`,JSON.stringify({id,codigo:item.codigo_interno,url,final_url:r.url,consultado_em:new Date().toISOString()},null,2),{flag:"wx"});
    console.log(`${id}: ${html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/)?.[1]?.trim()}`);
  }));
  resultados.filter(r=>r.status==='rejected').forEach(r=>console.log(r.reason.message));
}
