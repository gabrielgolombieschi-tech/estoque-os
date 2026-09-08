import fs from "node:fs";
import { execFileSync } from "node:child_process";
// Somente documentos públicos do fabricante; nenhum acesso ao ERP.
const referencias = [
  "3RT2026-1AK60", "3RT2026-1AN10", "3RT2028-1AK60", "3RT2027-1AK60", "3RT2036-1AK60",
  "3RV2011-1EA10", "3RV2011-1CA10", "3RV2011-1AA20", "3RV2011-1CA20", "3RV2011-4AA10",
  "3RV2011-1FA10", "3RV2011-1AA10", "3RV2011-1BA10", "3RV2011-1JA10", "3RV2011-1HA10",
  "3RV2011-1EA20", "3RV2011-1GA20", "3RV2011-1BA20", "3RV2011-1GA10", "3RV2011-1DA10",
];
const pastaFontes = "backups/fontes-lotes-003-004";
const bin = `${pastaFontes}/poppler/poppler-26.07.0/Library/bin`;
fs.mkdirSync(pastaFontes, { recursive: true });
for (let inicio = 0; inicio < referencias.length; inicio += 4) {
  await Promise.all(referencias.slice(inicio, inicio + 4).map(async (ref) => {
    const destino = `${pastaFontes}/${ref}.pdf`;
    const url = `https://tableeditor.cicservice.siemens.com/teddatasheet/?caller=documentservice&format=PDF&language=en&mlfbs=${ref}`;
    if (!fs.existsSync(destino)) {
      const resposta = await fetch(url, { signal: AbortSignal.timeout(45000) });
      if (!resposta.ok) throw new Error(`${ref}: HTTP ${resposta.status}`);
      const bytes = Buffer.from(await resposta.arrayBuffer());
      if (bytes.subarray(0, 5).toString() !== "%PDF-") throw new Error(`Não é PDF: ${ref}`);
      fs.writeFileSync(destino, bytes, { flag: "wx" });
    }
    execFileSync(`${bin}/pdftotext.exe`, ["-layout", destino, `${pastaFontes}/${ref}.txt`]);
    console.log(ref);
  }));
}
