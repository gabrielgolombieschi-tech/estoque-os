/**
 * Abandona a emissao de HOMOLOGACAO da OV e mede o efeito no saldo.
 * ESCREVE NO BANCO.
 *
 *   node scripts/chrome-nfe-abandonar.mjs 344
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const ovId = process.argv[2] ?? "344";
const JUSTIFICATIVA = "Abandono da homologacao para reiniciar o ciclo de teste da NF-e";

const { pagina, encerrar } = await conectar();

async function estado(rotulo) {
  await pagina.waitForTimeout(2500);
  const linha = (await pagina.locator("table").first().locator("tbody tr").first().textContent())
    ?.replace(/\s+/g, " ")
    .trim();
  const faturar = pagina.getByRole("button", { name: "Faturar", exact: true });
  const habilitado = (await faturar.count()) > 0 ? await faturar.isEnabled() : null;
  console.log(`\n[${rotulo}]`);
  console.log("  progresso:", linha);
  console.log("  Faturar:", habilitado === null ? "ausente" : habilitado ? "HABILITADO" : "desabilitado");
  return { linha, habilitado };
}

await pagina.goto(new URL(`/comercial/vendas/${ovId}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await garantirSessao(pagina);
await pagina.getByRole("button", { name: /^Faturamento \(/ }).click();

const antes = await estado("ANTES");

const botao = pagina.getByRole("button", { name: "Abandonar homologação e liberar saldo" });
if ((await botao.count()) === 0) {
  console.log("\nBotão de abandono não apareceu — nenhuma homologação autorizada nesta OV.");
  await encerrar();
  process.exit(0);
}

console.log("\n-> abrindo o painel de abandono");
await botao.first().click();
await pagina.locator("textarea").first().fill(JUSTIFICATIVA);

const confirmar = pagina.getByRole("button", { name: "Abandonar e devolver saldo" });
await confirmar.waitFor({ state: "visible", timeout: 10_000 });
console.log("-> habilitado:", await confirmar.isEnabled());
await confirmar.click();

await pagina.waitForTimeout(6000);
const depois = await estado("DEPOIS");

const destino = path.join(raiz, "tests", "e2e", ".saida", "nfe-pos-abandono.png");
fs.mkdirSync(path.dirname(destino), { recursive: true });
await pagina.screenshot({ path: destino, fullPage: true });
console.log("\nCaptura:", destino);

console.log("\n=== VEREDITO ===");
console.log("antes :", antes.linha, "| Faturar:", antes.habilitado);
console.log("depois:", depois.linha, "| Faturar:", depois.habilitado);

await encerrar();
