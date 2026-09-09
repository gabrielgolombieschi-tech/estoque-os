import fs from "node:fs";
import { execFileSync } from "node:child_process";
import { validarEscopo } from "./lib/controle-revisoes.mjs";
const base = JSON.parse(fs.readFileSync("backups/base-revisao/2026-09-09T13-00-31-806Z.json", "utf8"));
validarEscopo(base);
const ids = [231,720,733,815,935,960,3227,3228,3229,3289,3441,232,734,817,937,942,961,962,963,964,1205,1206,3230,241,257,772,775,791,807,813,1620,3231,228,920,921,953,954,2453,2460,195,196,197,198,237,238,943,2921,687,2136,2991,2992,2459];
const pasta = "backups/fontes-lote-006";
const bin = "backups/fontes-lotes-003-004/poppler/poppler-26.07.0/Library/bin";
fs.mkdirSync(pasta, { recursive: true });
for (let k = 0; k < ids.length; k += 4) {
  const resultados = await Promise.allSettled(ids.slice(k, k + 4).map(async (id) => {
    const item = base.itens.find((i) => i.id === id);
    validarEscopo(item);
    const destino = `${pasta}/${id}.pdf`;
    if (!fs.existsSync(destino)) {
      const resposta = await fetch(`https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=${item.codigo_interno}`, { signal: AbortSignal.timeout(45000) });
      if (!resposta.ok) throw new Error(`${id}: HTTP ${resposta.status}`);
      const bytes = Buffer.from(await resposta.arrayBuffer());
      if (bytes.subarray(0, 5).toString() !== "%PDF-") throw new Error(`Não é PDF: ${id}`);
      fs.writeFileSync(destino, bytes, { flag: "wx" });
    }
    execFileSync(`${bin}/pdftotext.exe`, ["-layout", destino, `${pasta}/${id}.txt`]);
    console.log(`${id}: ${item.codigo_interno}`);
  }));
  for (const r of resultados) if (r.status === "rejected") console.log(`PENDENTE: ${r.reason.message}`);
}
