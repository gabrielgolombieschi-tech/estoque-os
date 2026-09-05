/**
 * Descarta o rascunho de NF-e da OV e mede o efeito no saldo.
 * ESCREVE NO BANCO — é o teste do ciclo cancelar/refazer.
 *
 *   npm run chrome:nfe:descartar -- 344
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const ovId = process.argv[2] ?? "344";
const JUSTIFICATIVA = "Teste do ciclo cancelar e refazer rascunho de NF-e";

const { pagina, encerrar } = await conectar(); // com handler de dialog: o descarte usa confirm()

async function estado(rotulo) {
  await pagina.waitForTimeout(2500);
  const linha = (await pagina.locator("table").first().locator("tbody tr").first().textContent())
    ?.replace(/\s+/g, " ")
    .trim();
  const faturar = pagina.getByRole("button", { name: "Faturar", exact: true });
  const habilitado = (await faturar.count()) > 0 ? await faturar.isEnabled() : null;
  const cartoes = await pagina.locator("article").count().catch(() => 0);
  console.log(`\n[${rotulo}]`);
  console.log("  progresso:", linha);
  console.log("  botão Faturar:", habilitado === null ? "ausente" : habilitado ? "HABILITADO" : "desabilitado");
  console.log("  solicitações na aba:", cartoes);
  return { linha, habilitado };
}

const url = new URL(`/comercial/vendas/${ovId}`, baseURL).toString();
await pagina.goto(url, { waitUntil: "domcontentloaded" });
await garantirSessao(pagina);
await pagina.getByRole("button", { name: /^Faturamento \(/ }).click();

const antes = await estado("ANTES");

const botaoDescartar = pagina.getByRole("button", { name: "Descartar rascunho" });
if ((await botaoDescartar.count()) === 0) {
  console.log("\nNão há rascunho descartável nesta OV.");
  await encerrar();
  process.exit(0);
}

console.log("\n-> abrindo o painel de descarte");
await botaoDescartar.first().click();

const campo = pagina.getByRole("textbox", { name: /Justificativa/i }).or(pagina.locator("textarea")).first();
await campo.fill(JUSTIFICATIVA);
console.log(`-> justificativa (${JUSTIFICATIVA.length} caracteres) preenchida`);

const confirmar = pagina.getByRole("button", { name: "Confirmar descarte" });
await confirmar.waitFor({ state: "visible", timeout: 10_000 });
console.log("-> botão Confirmar descarte habilitado:", await confirmar.isEnabled());
await confirmar.click();
console.log("-> clicado (o confirm() nativo é aceito pelo handler)");

await pagina.waitForTimeout(5000);
const depois = await estado("DEPOIS");

const destino = path.join(raiz, "tests", "e2e", ".saida", "nfe-pos-descarte.png");
fs.mkdirSync(path.dirname(destino), { recursive: true });
await pagina.screenshot({ path: destino, fullPage: true });
console.log("\nCaptura:", destino);

console.log("\n=== VEREDITO ===");
console.log("progresso antes :", antes.linha);
console.log("progresso depois:", depois.linha);
console.log("Faturar antes:", antes.habilitado, "-> depois:", depois.habilitado);

await encerrar();
