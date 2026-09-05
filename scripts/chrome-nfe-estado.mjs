/**
 * Abre a aba Faturamento da OV e descreve o estado dos rascunhos de NF-e.
 * Só lê — não clica em nada que altere dados.
 *
 *   npm run chrome:nfe -- 344
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const ovId = process.argv[2] ?? "344";
const destino = path.join(raiz, "tests", "e2e", ".saida", "nfe-estado.png");

const { pagina, encerrar } = await conectar({ aceitarDialogos: false });

const url = new URL(`/comercial/vendas/${ovId}`, baseURL).toString();
if (!pagina.url().startsWith(url)) {
  await pagina.goto(url, { waitUntil: "domcontentloaded" });
  await garantirSessao(pagina);
}

await pagina.getByRole("button", { name: /^Faturamento \(/ }).click();
await pagina.waitForTimeout(3000);

console.log("=== Progresso por item ===");
const progresso = await pagina
  .locator("table")
  .first()
  .locator("tbody tr")
  .allTextContents();
for (const linha of progresso) console.log(" ", linha.replace(/\s+/g, " ").trim());

console.log("\n=== Botões visíveis ===");
for (const botao of await pagina.locator("button:visible").all()) {
  const texto = (await botao.textContent())?.replace(/\s+/g, " ").trim();
  if (texto) console.log(`  ${(await botao.isEnabled()) ? "[on ]" : "[off]"} ${texto.slice(0, 70)}`);
}

console.log("\n=== Links visíveis ===");
for (const link of await pagina.locator("a:visible").all()) {
  const texto = (await link.textContent())?.replace(/\s+/g, " ").trim();
  if (texto && texto.length < 60) console.log("  •", texto);
}

const avisos = await pagina.locator('[role="alert"]').allTextContents();
if (avisos.length) {
  console.log("\n=== Avisos ===");
  for (const aviso of avisos) {
    const limpo = aviso.replace(/\s+/g, " ").trim();
    if (limpo) console.log("  •", limpo.slice(0, 300));
  }
}

fs.mkdirSync(path.dirname(destino), { recursive: true });
await pagina.screenshot({ path: destino, fullPage: true });
console.log("\nCaptura:", destino);

await encerrar();
