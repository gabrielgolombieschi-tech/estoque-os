import fs from "node:fs";
import { execFileSync } from "node:child_process";
import { validarEscopo } from "./lib/controle-revisoes.mjs";
const base = JSON.parse(fs.readFileSync("backups/base-revisao/2026-09-07T22-27-50-622Z.json", "utf8"));
validarEscopo(base);
const ids = [185,749,752,771,794,936,1089,2902,2945,247,753,766,767,796,797,1621,1632,2903,213,245,759,788,180,181,193,748,820,916,1048,1399,2302,2898,250,260,780,782,783,784,799,802,806,810,917,919,956,1125,1542,1547,1626,694];
const pasta = "backups/fontes-lote-005";
const bin = "backups/fontes-lotes-003-004/poppler/poppler-26.07.0/Library/bin";
fs.mkdirSync(pasta, { recursive: true });
for (let k = 0; k < ids.length; k += 4) {
  const resultados = await Promise.allSettled(ids.slice(k, k + 4).map(async (id) => {
    const item = base.itens.find((i) => i.id === id);
    validarEscopo(item);
    const ref = item.codigo_interno;
    const destino = `${pasta}/${id}.pdf`;
    if (!fs.existsSync(destino)) {
      const resposta = await fetch(`https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=${ref}`, { signal: AbortSignal.timeout(45000) });
      if (!resposta.ok) throw new Error(`${id}: HTTP ${resposta.status}`);
      const bytes = Buffer.from(await resposta.arrayBuffer());
      if (bytes.subarray(0, 5).toString() !== "%PDF-") throw new Error(`Não é PDF: ${id}`);
      fs.writeFileSync(destino, bytes, { flag: "wx" });
    }
    execFileSync(`${bin}/pdftotext.exe`, ["-layout", destino, `${pasta}/${id}.txt`]);
    console.log(`${id}: ${ref}`);
  }));
  for (const r of resultados) if (r.status === "rejected") console.log(`PENDENTE: ${r.reason.message}`);
}
