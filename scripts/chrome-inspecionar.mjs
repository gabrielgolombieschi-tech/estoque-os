/**
 * Descreve a tela ATUAL sem navegar nem clicar. Se houver overlay/modal aberto,
 * descreve o conteudo dele separadamente do resto.
 *
 *   node scripts/chrome-inspecionar.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { conectar } from "./chrome.mjs";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const { pagina, encerrar } = await conectar({ aceitarDialogos: false });

console.log("URL:", pagina.url());

const overlay = pagina.locator("div.fixed.inset-0").filter({ has: pagina.locator("button") }).last();
const temOverlay = (await overlay.count()) > 0 && (await overlay.isVisible().catch(() => false));
const escopo = temOverlay ? overlay : pagina;
console.log("overlay aberto:", temOverlay);

if (temOverlay) {
  const texto = (await overlay.textContent())?.replace(/\s+/g, " ").trim();
  console.log("\n=== texto do overlay ===");
  console.log(texto?.slice(0, 2000));
}

console.log("\n=== botões no escopo ===");
for (const botao of await escopo.locator("button:visible").all()) {
  const texto = (await botao.textContent())?.replace(/\s+/g, " ").trim();
  if (texto && texto.length < 70) console.log(`  ${(await botao.isEnabled()) ? "[on ]" : "[off]"} ${texto}`);
}

console.log("\n=== campos no escopo ===");
for (const campo of await escopo.locator("input:visible, select:visible, textarea:visible").all()) {
  const rotulo = (await campo.getAttribute("aria-label"))
    ?? (await campo.getAttribute("placeholder"))
    ?? "(sem rótulo)";
  const valor = await campo.inputValue().catch(() => "");
  console.log(`  ${rotulo} = ${JSON.stringify(valor).slice(0, 70)}`);
}

const avisos = await pagina.locator('[role="alert"]').allTextContents();
if (avisos.some((a) => a.trim())) {
  console.log("\n=== avisos ===");
  for (const a of avisos) if (a.trim()) console.log("  •", a.replace(/\s+/g, " ").trim().slice(0, 300));
}

const destino = path.join(raiz, "tests", "e2e", ".saida", "inspecao.png");
fs.mkdirSync(path.dirname(destino), { recursive: true });
await pagina.screenshot({ path: destino, fullPage: true });
console.log("\nCaptura:", destino);

await encerrar();
