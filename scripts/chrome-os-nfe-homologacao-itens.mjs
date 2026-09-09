/**
 * Homologacao da NF-e de industrializacao com VARIAS linhas, pela tela
 * /os/[id]/faturar, com Chrome headless logado. Irmao de
 * chrome-os-nfe-homologacao.mjs, que so compoe uma linha — aqui a nota sai com a
 * mesma composicao de itens da nota real, que e o que a contabilidade confere.
 * CHAMA A FOCUS DE HOMOLOGACAO (sem valor fiscal).
 *
 *   node scripts/chrome-os-nfe-homologacao-itens.mjs --os 281 --produto FAB-OS282-01 \
 *     --itens itens.json --destinacao ATIVO_IMOBILIZADO [--dias 30] [--obs "texto"] \
 *     [--abandonar "motivo"] [--so-conferir]
 *
 * --itens: JSON [{ descricao, quantidade, valor_unitario }], valores em pt-BR ("1.234,56").
 * --abandonar: antes de compor, abandona a homologacao autorizada que estiver segurando
 *   o saldo da OS (a tela pede motivo, de 15 a 255 caracteres).
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
const arg = (nome, padrao = null) => { const i = process.argv.indexOf(`--${nome}`); return i >= 0 ? process.argv[i + 1] : padrao; };
const tem = (nome) => process.argv.includes(`--${nome}`);
const osId = arg("os");
const produto = arg("produto");
const itensPath = arg("itens");
const destinacao = arg("destinacao", "ATIVO_IMOBILIZADO");
const dias = arg("dias", "30");
const obs = arg("obs", "");
const abandonar = arg("abandonar");
if (!osId || !produto || !itensPath) { console.error("--os, --produto e --itens sao obrigatorios"); process.exit(1); }
const itens = JSON.parse(fs.readFileSync(itensPath, "utf8"));
if (!Array.isArray(itens) || itens.length === 0) { console.error("--itens precisa ser um array nao vazio"); process.exit(1); }

const saida = path.join(raiz, "tests", "e2e", ".saida", `os-nfe-itens-${osId}`);
fs.mkdirSync(saida, { recursive: true });

const navegador = await chromium.launch({ channel: "chrome", headless: true });
const pagina = await navegador.newPage({ viewport: { width: 1360, height: 1200 } });
let passo = 0;
async function foto(nome) { passo += 1; await pagina.screenshot({ path: path.join(saida, `${String(passo).padStart(2, "0")}-${nome}.png`), fullPage: true, timeout: 20000 }).catch(() => {}); }
async function avisos() {
  return [...new Set((await pagina.locator('[role="alert"], [role="status"], li').allTextContents()).map((t) => t.replace(/\s+/g, " ").trim()).filter((t) => t && t.length < 400))].slice(0, 12);
}
pagina.on("dialog", async (d) => {
  console.log(`[${d.type()}] ${d.message().replace(/\s+/g, " ").slice(0, 180)}`);
  if (d.type() === "prompt") await d.accept(abandonar ?? "Abandono para recompor a nota com os itens corretos");
  else await d.accept();
});

await pagina.goto(new URL("/login", baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByPlaceholder("seu@email.com").fill(process.env.E2E_EMAIL ?? "");
await pagina.locator('input[type="password"]').first().fill(process.env.E2E_PASSWORD ?? "");
await pagina.getByRole("button", { name: "Entrar" }).click();
for (let i = 0; i < 60; i += 1) { if (!new URL(pagina.url()).pathname.startsWith("/login")) break; await pagina.waitForTimeout(500); }

await pagina.goto(new URL(`/os/${osId}/faturar`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByText("Linhas da nota").waitFor({ state: "visible", timeout: 30000 });
await pagina.waitForTimeout(4000);
await foto("inicio");

// Homologacao autorizada segurando o saldo: abandona para poder compor de novo.
if (abandonar) {
  // O bloco de emissao monta depois do resto da tela; sem esperar por ele o script
  // concluia "nada a abandonar" com a homologacao ainda segurando o saldo.
  const botao = pagina.getByRole("button", { name: /Abandonar homologação e liberar saldo|Descartar rascunho/ }).first();
  await botao.waitFor({ state: "visible", timeout: 25000 }).catch(() => {});
  if ((await botao.count()) > 0) {
    console.log("[0] abandonando composicao anterior:", (await botao.textContent())?.trim());
    await botao.click();
    await pagina.waitForTimeout(10000);
    await foto("abandonado");
    console.log("   avisos:", (await avisos()).filter((t) => /abandon|saldo|descart|erro/i.test(t)).slice(0, 4));
    await pagina.reload({ waitUntil: "domcontentloaded" });
    await pagina.waitForTimeout(5000);
  } else {
    console.log("[0] nada a abandonar");
  }
}

// So ha o que compor quando a tela volta com os campos de linha editaveis.
const buscaInicial = pagina.getByPlaceholder(/Buscar produto fabricado/).first();
await buscaInicial.waitFor({ state: "visible", timeout: 25000 }).catch(() => {});
if ((await buscaInicial.count()) === 0) {
  console.log("A OS ainda tem composicao ativa; nao ha linhas editaveis. Use --abandonar.");
  await foto("sem-linhas-editaveis");
  await navegador.close();
  process.exit(4);
}

// Uma linha ja vem na tela; as demais entram por "Adicionar linha".
for (let i = 1; i < itens.length; i += 1) {
  await pagina.getByRole("button", { name: "Adicionar linha" }).click();
  await pagina.waitForTimeout(400);
}
console.log(`[1] ${itens.length} linhas na tela`);

for (let i = 0; i < itens.length; i += 1) {
  const item = itens[i];
  const busca = pagina.getByPlaceholder(/Buscar produto fabricado/).nth(i);
  await busca.fill(produto);
  await pagina.getByRole("button", { name: "Buscar", exact: true }).nth(i).click();
  await pagina.waitForTimeout(2200);
  const opcao = pagina.locator("div.max-h-40 button").first();
  if ((await opcao.count()) === 0) { console.log(`linha ${i + 1}: produto ${produto} nao encontrado`); await foto("produto-nao-encontrado"); await navegador.close(); process.exit(2); }
  await opcao.click();
  await pagina.waitForTimeout(500);
  await pagina.getByLabel("Descrição impressa").nth(i).fill(item.descricao);
  await pagina.getByLabel("Quantidade").nth(i).fill(String(item.quantidade));
  await pagina.getByLabel("Valor unitário").nth(i).fill(String(item.valor_unitario));
  console.log(`   linha ${i + 1}: ${item.descricao} · ${item.quantidade} x ${item.valor_unitario}`);
}
await foto("linhas");

await pagina.getByLabel(/Destinação declarada/).selectOption(destinacao);
const campoDias = pagina.getByLabel("Dias").first();
if ((await campoDias.count()) > 0) await campoDias.fill(dias);
if (obs) await pagina.getByLabel(/Observação livre/).fill(obs);
await foto("preenchido");

console.log("[2] salvar rascunho e conferir");
await pagina.getByRole("button", { name: "Salvar rascunho e conferir" }).click();
await pagina.waitForTimeout(10000);
await foto("conferido");
console.log("   avisos:", (await avisos()).filter((t) => /Confer|Bloqueio|Linha|pend|cadastro|acima|Total/i.test(t)).slice(0, 8));

if (tem("so-conferir")) { console.log("--so-conferir: parando antes de emitir"); await navegador.close(); process.exit(0); }

const emitir = pagina.getByRole("button", { name: /^(Emitir em homologação|Tentar emitir novamente)/ });
await emitir.waitFor({ state: "visible", timeout: 20000 }).catch(() => {});
if ((await emitir.count()) === 0 || !(await emitir.isEnabled())) {
  await foto("emitir-indisponivel");
  console.log("emissao indisponivel:", (await avisos()).slice(0, 10));
  await navegador.close();
  process.exit(3);
}
console.log("[3] emitindo em homologacao");
await emitir.click();
await pagina.waitForTimeout(12000);
await foto("pos-emissao");

let resultado = null;
for (let i = 0; i < 24; i += 1) {
  const txt = (await pagina.locator("body").innerText()).replace(/\s+/g, " ");
  const m = txt.match(/Status: (Autorizada em homologação|Rejeitada|Erro|Em processamento)[^|]{0,200}/);
  if (m && !/Em processamento/.test(m[1])) { resultado = m[0]; break; }
  await pagina.waitForTimeout(5000);
  await pagina.reload({ waitUntil: "domcontentloaded" });
  await pagina.waitForTimeout(4000);
}
await foto("final");
console.log("[4]", resultado ?? "sem estado final em ~3 min");
console.log("capturas em:", saida);
await navegador.close();
