/**
 * Sonda exploratoria: executa um clique nomeado e descreve o que apareceu.
 * Serve para mapear a tela sem chutar seletor.
 *
 *   node scripts/chrome-passo.mjs 344 "Faturar"
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const ovId = process.argv[2] ?? "344";
const clique = process.argv[3];
const aba = process.argv[4];

const { pagina, encerrar } = await conectar();

await pagina.goto(new URL(`/comercial/vendas/${ovId}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await garantirSessao(pagina);
await pagina.waitForTimeout(3500);

if (aba) {
  await pagina.getByRole("button", { name: new RegExp(`^${aba} \\(`) }).click();
  await pagina.waitForTimeout(2500);
}

if (clique) {
  const alvo = pagina.getByRole("button", { name: clique, exact: true }).first();
  console.log(`clicando "${clique}" (habilitado: ${await alvo.isEnabled()})`);
  await alvo.click();
  await pagina.waitForTimeout(3500);
}

const dialogo = pagina.locator('[role="dialog"]');
if ((await dialogo.count()) > 0) {
  console.log("\n=== MODAL ===");
  console.log((await dialogo.first().textContent())?.replace(/\s+/g, " ").trim().slice(0, 1200));
}

console.log("\n=== campos visíveis ===");
for (const campo of await pagina.locator("input:visible, select:visible, textarea:visible").all()) {
  const rotulo = (await campo.getAttribute("aria-label"))
    ?? (await campo.getAttribute("placeholder"))
    ?? (await campo.getAttribute("name"))
    ?? "(sem rótulo)";
  const tipo = await campo.getAttribute("type");
  const valor = await campo.inputValue().catch(() => "");
  console.log(`  [${tipo ?? "sel/txt"}] ${rotulo} = ${JSON.stringify(valor).slice(0, 60)}`);
}

console.log("\n=== botões visíveis ===");
for (const botao of await pagina.locator("button:visible").all()) {
  const texto = (await botao.textContent())?.replace(/\s+/g, " ").trim();
  if (texto && texto.length < 60) console.log(`  ${(await botao.isEnabled()) ? "[on ]" : "[off]"} ${texto}`);
}

const avisos = await pagina.locator('[role="alert"]').allTextContents();
if (avisos.some((a) => a.trim())) {
  console.log("\n=== avisos ===");
  for (const a of avisos) if (a.trim()) console.log("  •", a.replace(/\s+/g, " ").trim().slice(0, 250));
}

const destino = path.join(raiz, "tests", "e2e", ".saida", "passo.png");
fs.mkdirSync(path.dirname(destino), { recursive: true });
await pagina.screenshot({ path: destino, fullPage: true });
console.log("\nCaptura:", destino);

await encerrar();
