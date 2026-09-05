/**
 * Emite a NF-e de PRODUCAO de uma OV pela tela, com Chrome headless logado.
 * EMISSAO FISCAL REAL. Executar somente com autorizacao explicita do responsavel.
 *
 *   node scripts/chrome-nfe-producao.mjs 344
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "@playwright/test";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
for (const linha of fs.readFileSync(path.join(raiz, ".env.e2e.local"), "utf8").split(/\r?\n/)) {
  const par = linha.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
  if (par && !process.env[par[1]]) process.env[par[1]] = par[2].replace(/^["']|["']$/g, "");
}
const baseURL = process.env.E2E_BASE_URL ?? "http://localhost:3000";
const ovId = process.argv[2] ?? "344";
const saida = path.join(raiz, "tests", "e2e", ".saida", "producao");
fs.mkdirSync(saida, { recursive: true });

const navegador = await chromium.launch({ channel: "chrome", headless: true });
const pagina = await navegador.newPage({ viewport: { width: 1360, height: 900 } });
let passo = 0;
async function foto(nome) {
  passo += 1;
  await pagina.screenshot({ path: path.join(saida, `${String(passo).padStart(2, "0")}-${nome}.png`), timeout: 15000 }).catch(() => {});
}
async function avisos() {
  return [...new Set((await pagina.locator('[role="alert"], [role="status"]').allTextContents())
    .map((t) => t.replace(/\s+/g, " ").trim()).filter((t) => t && !t.startsWith("OV-")))];
}
async function sair(codigo, msg) {
  if (msg) console.log(msg);
  await navegador.close();
  process.exit(codigo);
}

pagina.on("dialog", async (d) => {
  console.log(`[${d.type()}] ${d.message().replace(/\s+/g, " ")}`);
  await d.accept();
});

// login
await pagina.goto(new URL("/login", baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByPlaceholder("seu@email.com").fill(process.env.E2E_EMAIL ?? "");
await pagina.locator('input[type="password"]').first().fill(process.env.E2E_PASSWORD ?? "");
await pagina.getByRole("button", { name: "Entrar" }).click();
for (let i = 0; i < 60; i += 1) {
  if (!new URL(pagina.url()).pathname.startsWith("/login")) break;
  await pagina.waitForTimeout(500);
}

async function irParaOv() {
  await pagina.goto(new URL(`/comercial/vendas/${ovId}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
  await pagina.waitForTimeout(4000);
  await pagina.getByRole("button", { name: /^Faturamento \(/ }).click();
  await pagina.waitForTimeout(4000);
}

await irParaOv();
const botaoProd = pagina.getByRole("button", { name: "Conferir e emitir em produção" });
await botaoProd.first().waitFor({ state: "visible", timeout: 60000 }).catch(() => {});
if ((await botaoProd.count()) === 0) {
  await foto("sem-botao-producao");
  await sair(2, `Botao de producao nao apareceu. Avisos: ${(await avisos()).join(" | ")}`);
}
await foto("ov-antes");
console.log("[1] abrindo conferência de produção");
await botaoProd.first().click();
await pagina.waitForTimeout(5000);
const conf = pagina.locator("div.fixed.inset-0").filter({ has: pagina.locator("button") }).last();
const titulo = (await conf.locator("h2").first().textContent().catch(() => ""))?.trim();
console.log("   modal:", titulo);
await foto("modal-producao");

if (!/produção/i.test(titulo ?? "")) {
  await sair(4, `A conferência aberta não é de produção ("${titulo}"). Abortado sem emitir.`);
}
// Etapa 1 (destino e destinacao) ja vem preenchida a partir do snapshot
// congelado da homologacao; so avancar. Nao altera nada.
const continuar = conf.getByRole("button", { name: /^Continuar para conferência fiscal/ });
if ((await continuar.count()) > 0) {
  const destino = await conf.locator("button.border-sky-500").first().textContent().catch(() => "");
  const destinacao = await conf.getByLabel("Destinação da mercadoria").inputValue().catch(() => "");
  console.log("   etapa 1:", destino?.replace(/\s+/g, " ").trim(), "| destinação:", destinacao);
  if (!(await continuar.isEnabled())) await sair(5, "Etapa de destino sem avanço habilitado.");
  await continuar.click();
  await pagina.waitForTimeout(6000);
  await foto("modal-etapa-2");
}

const emitir = conf.getByRole("button", { name: /^Emitir NF-e real em produção/ });
// O perfil por linha resolve de forma assincrona; o rotulo do botao muda quando termina.
for (let i = 0; i < 40; i += 1) {
  if ((await emitir.count()) > 0 && (await emitir.isEnabled())) break;
  await pagina.waitForTimeout(1000);
}
if ((await emitir.count()) === 0 || !(await emitir.isEnabled())) {
  const rodape = await conf.locator("button").last().textContent().catch(() => "");
  console.log("   botão do rodapé:", rodape?.trim());
  const pend = (await conf.locator("li").allTextContents()).map((t) => t.replace(/\s+/g, " ").trim()).filter(Boolean);
  await foto("emitir-indisponivel");
  await sair(3, `Botao "Emitir em produção" indisponivel. Avisos: ${(await avisos()).join(" | ")} || ${pend.join(" | ").slice(0, 600)}`);
}
console.log("[2] clicando em Emitir em produção (confirm sera aceito)");
await emitir.click();
await pagina.waitForTimeout(15000);
await foto("pos-emissao");
console.log("   avisos:", (await avisos()).join(" | ").slice(0, 500));

console.log("[3] aguardando autorização em produção");
let resultado = null;
for (let espera = 0; espera < 30; espera += 1) {
  await irParaOv();
  const txt = (await pagina.locator("body").innerText()).replace(/\s+/g, " ");
  const i = txt.indexOf("NF-E · PRODUÇÃO");
  const trecho = i >= 0 ? txt.slice(i, i + 400) : "";
  if (/Autorizada|AUTORIZADA/.test(trecho) && !/homologação/i.test(trecho.slice(0, 80))) { resultado = trecho; break; }
  if (/REJEITADA|Rejeitada|ERRO/.test(trecho)) { resultado = trecho; break; }
  await pagina.waitForTimeout(5000);
}
await foto("final");
console.log("resultado:", resultado ?? "(sem estado final em ~3 min)");
console.log("capturas em:", saida);
await navegador.close();
