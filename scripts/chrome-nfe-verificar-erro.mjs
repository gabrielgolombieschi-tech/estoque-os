/**
 * Verifica que uma falha de emissao aparece na tela como ERRO, e nao com a mesma
 * aparencia de sucesso. Força a falha com peso bruto menor que o liquido.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const ovId = process.argv[2] ?? "344";
const { pagina, encerrar } = await conectar();

await pagina.goto(new URL(`/comercial/vendas/${ovId}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await garantirSessao(pagina);
await pagina.waitForTimeout(3500);

// Reaproveita um rascunho existente; só cria um novo se houver saldo.
const faturar = pagina.getByRole("button", { name: "Faturar", exact: true }).first();
if (await faturar.isEnabled()) {
  await faturar.click();
  await pagina.locator('[role="dialog"]').waitFor({ state: "visible", timeout: 20_000 });
  await pagina.getByRole("button", { name: "Salvar rascunho da NF-e" }).click();
  await pagina.waitForTimeout(6000);
} else {
  console.log("usando o rascunho que já existe nesta OV");
}

await pagina.getByRole("button", { name: /^Faturamento \(/ }).click();
await pagina.waitForTimeout(2500);
await pagina.getByRole("button", { name: /^(Conferir e emitir em homologação|Continuar conferência)$/ }).first().click();
await pagina.waitForTimeout(4000);

const conf = pagina.locator("div.fixed.inset-0").filter({ has: pagina.locator("button") }).last();
const destinoSC = conf.getByRole("button", { name: /^Dentro de Santa Catarina/ });
if ((await destinoSC.count()) > 0) {
  await destinoSC.click();
  await conf.getByRole("button", { name: /^Continuar para conferência fiscal/ }).click();
  await pagina.waitForTimeout(5000);
}

async function definir(tipo, rotulo, valor) {
  const alvo = conf.locator("label").filter({ hasText: new RegExp(`^\\s*${rotulo}`) })
    .locator(tipo === "select" ? "select" : "input").first();
  if ((await alvo.count()) === 0 || !(await alvo.isEnabled())) return;
  if (tipo === "select") await alvo.selectOption(valor); else await alvo.fill(valor);
  await pagina.waitForTimeout(350);
}

await definir("select", "Presença do comprador", "0");
await definir("select", "Modalidade do frete", "1");
await definir("texto", "Frete", "0");
await definir("texto", "Seguro", "0");
await definir("texto", "Outras despesas", "0");
await definir("texto", "Transportadora", "TEDE TRANSPORTES LTDA");
await definir("texto", "Quantidade de volumes", "1");
await definir("texto", "Peso líquido", "0,20");
await definir("texto", "Peso bruto", "0,10"); // invalido de proposito
await pagina.waitForTimeout(1500);

const emitir = conf.getByRole("button", { name: /^(Emitir em homologação|Tentar emitir novamente)/ });
console.log("emitindo com peso bruto < líquido...");
await emitir.click();
await pagina.waitForTimeout(10_000);

// Lê no NÍVEL DA PÁGINA, não dentro do modal — foi o erro do meu diagnóstico anterior.
const alertas = await pagina.locator('[role="alert"]').allTextContents();
const status = await pagina.locator('[role="status"]').allTextContents();
console.log("\n[role=alert]  :", alertas.map((t) => t.replace(/\s+/g, " ").trim()).filter(Boolean).join(" | ").slice(0, 300));
console.log("[role=status] :", status.map((t) => t.replace(/\s+/g, " ").trim()).filter(Boolean).join(" | ").slice(0, 300));

const destino = path.join(raiz, "tests", "e2e", ".saida", "erro-emissao.png");
fs.mkdirSync(path.dirname(destino), { recursive: true });
await pagina.screenshot({ path: destino, fullPage: true });
console.log("\nCaptura:", destino);

await encerrar();
