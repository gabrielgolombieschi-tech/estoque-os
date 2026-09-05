/**
 * Captura as telas do guia de perfis fiscais com Chrome headless (login proprio,
 * nao usa o Chrome de teste). So le; nao clica em nada que grave.
 *
 *   node scripts/guia-perfis-capturas.mjs
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
const saida = path.join(raiz, "docs", "faturamento", "guia-perfis-fiscais-imagens");
fs.mkdirSync(saida, { recursive: true });

const PERFIL = "SEG-VENDA-TERCEIROS-SC-5102-O2-CST00";
const OV = "344";

const navegador = await chromium.launch({ channel: "chrome", headless: true });
const contexto = await navegador.newContext({ viewport: { width: 1360, height: 900 }, deviceScaleFactor: 1.5, colorScheme: "dark" });
const pagina = await contexto.newPage();

async function login() {
  await pagina.goto(new URL("/login", baseURL).toString(), { waitUntil: "domcontentloaded" });
  const email = pagina.getByPlaceholder("seu@email.com");
  await email.waitFor({ state: "visible", timeout: 15000 });
  await email.fill(process.env.E2E_EMAIL ?? "");
  await pagina.locator('input[type="password"]').first().fill(process.env.E2E_PASSWORD ?? "");
  await pagina.getByRole("button", { name: /entrar/i }).first().click();
  // A home nao dispara "load" de forma confiavel; basta a URL sair de /login.
  for (let i = 0; i < 60; i += 1) {
    if (!new URL(pagina.url()).pathname.startsWith("/login")) return;
    await pagina.waitForTimeout(500);
  }
  throw new Error("Login nao saiu de /login.");
}

async function foto(nome, locator) {
  const alvo = locator ?? pagina;
  await alvo.screenshot({ path: path.join(saida, `${nome}.png`), timeout: 20000 });
  console.log("ok", nome);
}

await login();

// Captura a viewport depois de rolar ate um texto-ancora (element screenshots
// sao frageis com rotulos em CSS uppercase).
async function fotoEm(nome, texto) {
  const alvo = pagina.getByText(texto, { exact: false }).first();
  await alvo.waitFor({ state: "visible", timeout: 20000 });
  await alvo.evaluate((el) => el.scrollIntoView({ block: "start" }));
  await pagina.waitForTimeout(600);
  await foto(nome);
}

// 1. Perfis: lista + cabecalho do perfil
await pagina.goto(new URL("/faturamento/perfis", baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.waitForTimeout(4000);
await foto("01-perfis-tela");
await pagina.getByLabel("Buscar perfil fiscal").fill(PERFIL);
await pagina.waitForTimeout(1500);
await pagina.getByRole("button").filter({ hasText: PERFIL }).first().click();
await pagina.waitForTimeout(3000);
await foto("02-perfil-cabecalho");
await fotoEm("03-bloco-revisao-ibs-cbs", "Campos IBS/CBS sujeitos a revisao");
await fotoEm("04-bloco-liberacao", "Liberacao separada para producao");
await pagina.getByLabel("Buscar perfil fiscal").fill("CSV63-02");
await pagina.waitForTimeout(1500);
await fotoEm("05-lista-etiquetas", "Perfis da empresa");

// 2. OV: aba Faturamento
await pagina.goto(new URL(`/comercial/vendas/${OV}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.waitForTimeout(4000);
await pagina.getByRole("button", { name: /^Faturamento \(/ }).click();
await pagina.waitForTimeout(4000);
await fotoEm("06-ov-aba-faturamento", "VALOR DO PEDIDO").catch(() => foto("06-ov-aba-faturamento"));
await fotoEm("07-ov-cartao-nfe", "Autorizada em homologação").catch(() => {});

// 3. Detalhe / ciclo de vida da NF-e
const linkCiclo = pagina.getByRole("link", { name: "Abrir detalhes e ciclo da NF-e" }).first();
if ((await linkCiclo.count()) > 0) {
  await linkCiclo.click();
  await pagina.waitForTimeout(5000);
  await fotoEm("08-nfe-ciclo-vida", "Ciclo de vida da NF-e").catch(() => foto("08-nfe-ciclo-vida"));
}

await navegador.close();
console.log("imagens em", saida);
