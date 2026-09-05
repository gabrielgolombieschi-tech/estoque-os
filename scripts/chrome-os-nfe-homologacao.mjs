/**
 * Cenario de homologacao da NF-e de industrializacao pela tela /os/[id]/faturar,
 * com Chrome headless logado. CHAMA A FOCUS DE HOMOLOGACAO (sem valor fiscal).
 *
 *   node scripts/chrome-os-nfe-homologacao.mjs --os 303 --cliente 42 \
 *     --valor 5266,10 --destinacao USO_CONSUMO \
 *     --criar "ADICIONAL BARRA NO CARRO|73269090|0|UN|53|" \
 *     [--produto FAB-OS304] [--dias 30] [--obs "texto"] [--so-conferir]
 *
 * --criar  nome|ncm|origem|unidade|cst_ipi|aliquota_ipi   (cria o produto da OS)
 * --produto termo                                          (busca produto existente)
 * --cliente id                                             (confirma indIEDest=1 no cadastro fiscal se estiver vazio)
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
const clienteId = arg("cliente");
const valor = arg("valor");
const destinacao = arg("destinacao", "USO_CONSUMO");
const criar = arg("criar");
const produto = arg("produto");
const dias = arg("dias", "30");
const obs = arg("obs", "");
if (!osId) { console.error("--os e obrigatorio"); process.exit(1); }
const saida = path.join(raiz, "tests", "e2e", ".saida", `os-nfe-${osId}`);
fs.mkdirSync(saida, { recursive: true });

const navegador = await chromium.launch({ channel: "chrome", headless: true });
const pagina = await navegador.newPage({ viewport: { width: 1360, height: 1000 } });
let passo = 0;
async function foto(nome) { passo += 1; await pagina.screenshot({ path: path.join(saida, `${String(passo).padStart(2, "0")}-${nome}.png`), timeout: 15000 }).catch(() => {}); }
async function avisos() {
  return [...new Set((await pagina.locator('[role="alert"], [role="status"], li').allTextContents()).map((t) => t.replace(/\s+/g, " ").trim()).filter((t) => t && t.length < 400))].slice(0, 12);
}
pagina.on("dialog", async (d) => { console.log(`[${d.type()}] ${d.message().replace(/\s+/g, " ").slice(0, 200)}`); await d.accept(); });

await pagina.goto(new URL("/login", baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByPlaceholder("seu@email.com").fill(process.env.E2E_EMAIL ?? "");
await pagina.locator('input[type="password"]').first().fill(process.env.E2E_PASSWORD ?? "");
await pagina.getByRole("button", { name: "Entrar" }).click();
for (let i = 0; i < 60; i += 1) { if (!new URL(pagina.url()).pathname.startsWith("/login")) break; await pagina.waitForTimeout(500); }

// 0. indIEDest do cliente (decisao humana registrada aqui, para homologacao)
if (clienteId) {
  await pagina.goto(new URL(`/clientes/cadastro-fiscal?cliente_id=${clienteId}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
  const sel = pagina.getByLabel(/Indicador de IE/);
  await sel.waitFor({ state: "visible", timeout: 30000 }).catch(() => {});
  await pagina.waitForTimeout(1500);
  if ((await sel.count()) > 0 && (await sel.inputValue()) === "") {
    await sel.selectOption("1");
    await pagina.waitForTimeout(500);
    const salvar = pagina.getByRole("button", { name: /Salvar e liberar cliente/ });
    if (await salvar.isEnabled()) { await salvar.click(); await pagina.waitForTimeout(4000); console.log("[0] cliente", clienteId, "indIEDest=1 salvo:", (await avisos()).slice(0, 3)); }
    else console.log("[0] cadastro fiscal com pendencias:", (await avisos()).slice(0, 6));
    await foto("cliente-fiscal");
  } else {
    console.log("[0] cliente", clienteId, "indIEDest ja preenchido ou campo ausente");
  }
}

// 1. tela de faturar
await pagina.goto(new URL(`/os/${osId}/faturar`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByText("Linhas da nota").waitFor({ state: "visible", timeout: 30000 });
await pagina.waitForTimeout(4000);
await foto("faturar-inicio");
const cabecalho = (await pagina.locator("body").innerText()).replace(/\s+/g, " ");
console.log("[1]", cabecalho.slice(cabecalho.indexOf("Saldo a faturar"), cabecalho.indexOf("Saldo a faturar") + 160));

const jaConferida = (await pagina.getByRole("button", { name: /Reconferir|Tentar emitir novamente|Emitir em homologação/ }).count()) > 0
  && (await pagina.getByRole("button", { name: "Salvar rascunho e conferir" }).count()) === 0;
if (!jaConferida) {
  if (valor) await pagina.getByLabel("Valor unitário").first().fill(valor);
  if (produto) {
    await pagina.getByPlaceholder(/Buscar produto fabricado/).first().fill(produto);
    await pagina.getByRole("button", { name: "Buscar", exact: true }).first().click();
    await pagina.waitForTimeout(2500);
    const primeiro = pagina.locator("div.max-h-40 button").first();
    if ((await primeiro.count()) === 0) { console.log("produto nao encontrado:", produto); await navegador.close(); process.exit(2); }
    console.log("[2] produto:", (await primeiro.textContent())?.trim());
    await primeiro.click();
  } else if (criar) {
    const [nome, ncm, origem, unidade, cstIpi, aliq] = criar.split("|");
    await pagina.getByRole("button", { name: "Criar da OS" }).first().click();
    await pagina.waitForTimeout(500);
    const bloco = pagina.locator("div.border-sky-900\\/60").first();
    await bloco.getByLabel("Descrição").fill(nome);
    await bloco.getByLabel(/^NCM/).fill(ncm);
    await bloco.getByLabel(/Origem da mercadoria/).selectOption(origem);
    await bloco.getByLabel(/Unidade tributável/).fill(unidade);
    await bloco.getByLabel(/^CST IPI/).selectOption(cstIpi);
    if (aliq) await bloco.getByLabel(/Alíquota IPI/).fill(aliq);
    await foto("criar-produto");
    await bloco.getByRole("button", { name: "Criar e vincular" }).click();
    await pagina.waitForTimeout(4000);
    console.log("[2] criar da OS:", (await avisos()).filter((t) => /Produto fabricado|Linha|erro|NCM|origem/i.test(t)).slice(0, 4));
  }
  await pagina.getByLabel(/Destinação declarada/).selectOption(destinacao);
  const campoDias = pagina.getByLabel("Dias").first();
  if ((await campoDias.count()) > 0) await campoDias.fill(dias);
  if (obs) await pagina.getByLabel(/Observação livre/).fill(obs);
  await foto("preenchido");
  console.log("[3] salvar rascunho e conferir");
  await pagina.getByRole("button", { name: "Salvar rascunho e conferir" }).click();
  await pagina.waitForTimeout(9000);
  await foto("conferido");
  console.log("   avisos:", (await avisos()).filter((t) => /Confer|Bloqueio|Linha|pend|cadastro|acima|Total/i.test(t)).slice(0, 8));
}

// Rascunho ja existente: reconfere para refazer a validacao do cadastro.
if (jaConferida) {
  const reconferir = pagina.getByRole("button", { name: "Reconferir" });
  if ((await reconferir.count()) > 0 && (await reconferir.isEnabled())) {
    console.log("[3] reconferindo rascunho existente");
    await reconferir.click();
    await pagina.waitForTimeout(9000);
    await foto("reconferido");
    console.log("   avisos:", (await avisos()).filter((t) => /Confer|Bloqueio|Linha|pend|cadastro|acima|Total/i.test(t)).slice(0, 8));
  }
}

if (tem("so-conferir")) { console.log("--so-conferir: parando antes de emitir"); await navegador.close(); process.exit(0); }

const emitir = pagina.getByRole("button", { name: /^(Emitir em homologação|Tentar emitir novamente)/ });
await emitir.waitFor({ state: "visible", timeout: 20000 }).catch(() => {});
if ((await emitir.count()) === 0 || !(await emitir.isEnabled())) {
  await foto("emitir-indisponivel");
  console.log("emissao indisponivel:", (await avisos()).slice(0, 10));
  await navegador.close();
  process.exit(3);
}
console.log("[4] emitindo em homologacao");
await emitir.click();
await pagina.waitForTimeout(12000);
await foto("pos-emissao");
console.log("   avisos:", (await avisos()).filter((t) => /Focus|Status|cStat|erro|Autorizada|processamento/i.test(t)).slice(0, 6));

let resultado = null;
for (let i = 0; i < 24; i += 1) {
  const txt = (await pagina.locator("body").innerText()).replace(/\s+/g, " ");
  const st = txt.indexOf("Status:");
  const trecho = st >= 0 ? txt.slice(st, st + 260) : "";
  if (/Autorizada em homologação/.test(trecho)) { resultado = trecho; break; }
  if (/REJEITADA|ERRO|cStat/.test(trecho)) { resultado = trecho; break; }
  await pagina.waitForTimeout(5000);
  await pagina.reload({ waitUntil: "domcontentloaded" });
  await pagina.waitForTimeout(4000);
}
await foto("final");
console.log("[5]", resultado ?? "sem estado final em ~3 min");
console.log("capturas em:", saida);
await navegador.close();
