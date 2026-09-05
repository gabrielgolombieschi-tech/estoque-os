/**
 * "Onde você parou?" — conecta na aba atual, tira uma captura e resume o estado
 * visível, sem clicar em nada. Desconecta em seguida.
 *
 *   npm run chrome:ver
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { conectar } from "./chrome.mjs";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const destino = path.join(raiz, "tests", "e2e", ".saida", "tela-atual.png");

const { pagina, encerrar } = await conectar({ aceitarDialogos: false });

console.log("URL:", pagina.url());
console.log("Título:", await pagina.title());

fs.mkdirSync(path.dirname(destino), { recursive: true });
await pagina.screenshot({ path: destino, fullPage: true });
console.log("Captura:", destino);

// Sinais que costumam explicar por que a tela está travada.
const avisos = await pagina
  .locator('[role="alert"]')
  .allTextContents()
  .catch(() => []);
if (avisos.length) {
  console.log("\nAvisos na tela:");
  for (const aviso of avisos) console.log("  •", aviso.replace(/\s+/g, " ").trim().slice(0, 200));
}

const desabilitados = await pagina
  .locator("button:disabled")
  .allTextContents()
  .catch(() => []);
if (desabilitados.length) {
  console.log("\nBotões desabilitados:");
  for (const texto of [...new Set(desabilitados)]) {
    const limpo = texto.replace(/\s+/g, " ").trim();
    if (limpo) console.log("  •", limpo.slice(0, 80));
  }
}

await encerrar();
