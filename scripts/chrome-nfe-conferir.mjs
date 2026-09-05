/**
 * Abre a conferencia do rascunho que JA existe na OV (sem clicar em Faturar) e
 * reporta o estado: bloqueios, se o "Continuar" avanca e se da para fechar.
 * Serve pra reproduzir travamento sem criar rascunho novo.
 *
 *   node scripts/chrome-nfe-conferir.mjs 344
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const ovId = process.argv[2] ?? "344";
const saida = path.join(raiz, "tests", "e2e", ".saida", "conferir");
fs.mkdirSync(saida, { recursive: true });

let n = 0;
const { pagina, encerrar } = await conectar();
async function foto(nome) {
  n += 1;
  const arquivo = path.join(saida, `${String(n).padStart(2, "0")}-${nome}.png`);
  await pagina.screenshot({ path: arquivo, fullPage: true });
  console.log("   foto:", path.basename(arquivo));
}

async function mensagens(rotulo) {
  const textos = await pagina.locator('[role="alert"], [role="status"]').allTextContents();
  const limpos = textos.map((t) => t.replace(/\s+/g, " ").trim()).filter((t) => t && !t.startsWith("OV-"));
  console.log(`   ${rotulo}:`, limpos.length ? limpos.map((t) => t.slice(0, 220)).join(" | ") : "(nenhuma)");
  const itens = await pagina.locator("div.fixed.inset-0 li").allTextContents();
  const pend = itens.map((t) => t.replace(/\s+/g, " ").trim()).filter(Boolean);
  if (pend.length) console.log("   pendências:", pend.join(" · "));
}

await pagina.goto(new URL(`/comercial/vendas/${ovId}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await garantirSessao(pagina);
await pagina.waitForTimeout(3500);

await pagina.getByRole("button", { name: /^Faturamento \(/ }).click();
await pagina.waitForTimeout(2500);

const abrir = pagina.getByRole("button", { name: /^(Conferir e emitir em homologação|Continuar conferência)/ }).first();
if ((await abrir.count()) === 0) {
  console.log("Não há rascunho para conferir nesta OV.");
  await foto("sem-rascunho");
  await encerrar();
  process.exit(0);
}
console.log("[1] abrindo:", (await abrir.textContent())?.trim());
await abrir.click();
await pagina.waitForTimeout(4000);

const conf = pagina.locator("div.fixed.inset-0").filter({ has: pagina.locator("button") }).last();
await foto("etapa1");
await mensagens("etapa 1");

const fechar = conf.getByRole("button", { name: "Fechar" });
console.log("   'Fechar' habilitado:", (await fechar.count()) > 0 ? await fechar.isEnabled() : "(ausente)");

const continuar = conf.getByRole("button", { name: /^Continuar para conferência fiscal/ });
console.log("[2] Continuar sem destinação (deve estar travado):", await continuar.isEnabled());

const destinacao = conf.getByLabel("Destinação da mercadoria");
const escolha = process.env.DESTINACAO ?? "REVENDA";
await destinacao.selectOption(escolha);
console.log("   destinação escolhida:", escolha);
console.log("   Continuar habilitado:", await continuar.isEnabled());
await continuar.click();
await pagina.waitForTimeout(6000);
await foto("apos-continuar");
await mensagens("após continuar");

const etapa = (await conf.locator("p").first().textContent())?.replace(/\s+/g, " ").trim();
console.log("   etapa agora:", etapa);
console.log("   'Fechar' habilitado:", (await fechar.count()) > 0 ? await fechar.isEnabled() : "(ausente)");

if (!process.argv.includes("--emitir")) {
  console.log("\n(sem --emitir: paro aqui)\ncapturas em:", saida);
  await encerrar();
  process.exit(0);
}

const formaPagamento = conf.getByLabel("Forma de pagamento");
if ((await formaPagamento.inputValue()) === "") {
  await formaPagamento.selectOption("15");
  await conf.getByLabel("Indicador de pagamento").selectOption("1");
  console.log("[3] pagamento: escolhido 15 · Boleto bancário, a prazo");
} else {
  console.log("[3] pagamento herdado:", await formaPagamento.inputValue());
}

const emitir = conf.getByRole("button", {
  name: /^(Emitir em homologação|Tentar emitir novamente|Complete os campos obrigatórios)/,
});
const rotulo = (await emitir.textContent())?.trim() ?? "";
console.log("   botão:", rotulo, "| habilitado:", await emitir.isEnabled());
if (rotulo.startsWith("Complete")) {
  await mensagens("bloqueio");
  await foto("bloqueada");
  await encerrar();
  process.exit(1);
}

console.log("[4] emitindo");
await emitir.click();
await pagina.waitForTimeout(15_000);
await foto("pos-emissao");
await mensagens("após emitir");

console.log("\ncapturas em:", saida);
await encerrar();
