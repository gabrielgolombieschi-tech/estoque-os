/**
 * Emite UMA NF-e de homologacao numa OV, como evidencia para liberar o perfil:
 *   (abandonar homologacao anterior se nao houver saldo) -> Faturar -> rascunho
 *   -> conferir -> emitir -> aguardar AUTORIZADA. Nao abandona no fim.
 * ESCREVE NO BANCO E CHAMA A FOCUS DE HOMOLOGACAO.
 *
 *   node scripts/chrome-nfe-evidencia.mjs 344 MANUTENCAO
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const ovId = process.argv[2] ?? "344";
const destinacao = process.argv[3] ?? "MANUTENCAO";
const saida = path.join(raiz, "tests", "e2e", ".saida", "evidencia");
fs.mkdirSync(saida, { recursive: true });

const { pagina, encerrar } = await conectar();
let passo = 0;
async function captura(nome) {
  passo += 1;
  await pagina.screenshot({ path: path.join(saida, `${String(passo).padStart(2, "0")}-${nome}.png`), timeout: 8000 }).catch(() => {});
}
function falhar(msg) {
  console.error("!!", msg);
  return encerrar().then(() => process.exit(2));
}

async function irParaOv() {
  await pagina.goto(new URL(`/comercial/vendas/${ovId}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
  await garantirSessao(pagina);
  await pagina.waitForTimeout(3500);
}
async function abaFaturamento() {
  await pagina.getByRole("button", { name: /^Faturamento \(/ }).click().catch(() => {});
  await pagina.waitForTimeout(2500);
}
async function faturarHabilitado() {
  const faturar = pagina.getByRole("button", { name: "Faturar", exact: true });
  return (await faturar.count()) > 0 && (await faturar.first().isEnabled());
}
async function avisos() {
  return [...new Set((await pagina.locator('[role="alert"], [role="status"]').allTextContents())
    .map((t) => t.replace(/\s+/g, " ").trim()).filter((t) => t && !t.startsWith("OV-")))];
}

await irParaOv();

// 0. liberar saldo se a homologacao anterior ainda o reserva
if (!(await faturarHabilitado())) {
  console.log("[0] sem saldo: abandonando homologacao anterior para liberar");
  await abaFaturamento();
  const abandonar = pagina.getByRole("button", { name: "Abandonar homologação e liberar saldo" });
  // A aba lista todas as solicitacoes da OV e demora a montar.
  await abandonar.first().waitFor({ state: "visible", timeout: 30_000 }).catch(() => {});
  if ((await abandonar.count()) === 0) await falhar("Faturar desabilitado e sem botao de abandono.");
  await abandonar.first().click();
  await pagina.locator("textarea").first().fill("Substituida pela NF-e de evidencia emitida apos a revisao fiscal do perfil (05/09/2026).");
  await pagina.getByRole("button", { name: "Abandonar e devolver saldo" }).click();
  await pagina.waitForTimeout(6000);
  await irParaOv();
  if (!(await faturarHabilitado())) await falhar("Saldo nao voltou apos o abandono.");
}

// 1. rascunho
console.log("[1] Faturar -> salvar rascunho");
await pagina.getByRole("button", { name: "Faturar", exact: true }).first().click();
await pagina.locator('[role="dialog"]').waitFor({ state: "visible", timeout: 20_000 });
const salvar = pagina.getByRole("button", { name: "Salvar rascunho da NF-e" });
if (!(await salvar.isEnabled())) await falhar('"Salvar rascunho da NF-e" desabilitado');
await salvar.click();
await pagina.waitForTimeout(6000);

// 2. conferencia
console.log("[2] Conferir e emitir em homologação");
await abaFaturamento();
const botao = pagina.getByRole("button", { name: /^(Conferir e emitir em homologação|Continuar conferência)$/ }).first();
if ((await botao.count()) === 0) await falhar("nenhum botao de conferencia");
await botao.click();
await pagina.waitForTimeout(4000);
const conf = pagina.locator("div.fixed.inset-0").filter({ has: pagina.locator("button") }).last();

const destinoSC = conf.getByRole("button", { name: /^Dentro de Santa Catarina/ });
if ((await destinoSC.count()) > 0) await destinoSC.click();
const selDestinacao = conf.getByLabel("Destinação da mercadoria");
if ((await selDestinacao.count()) > 0 && (await selDestinacao.isEnabled())) {
  await selDestinacao.selectOption(destinacao);
  console.log("   destinacao:", destinacao);
}
const continuar = conf.getByRole("button", { name: /^Continuar para conferência fiscal/ });
if ((await continuar.count()) > 0) {
  if (!(await continuar.isEnabled())) { await captura("destino-travado"); await falhar("avanco do destino desabilitado"); }
  await continuar.click();
  await pagina.waitForTimeout(5000);
}

const finalidade = conf.locator("label").filter({ hasText: /^\s*Finalidade/ }).locator("select").first();
for (let i = 0; i < 30; i += 1) {
  if (((await finalidade.inputValue().catch(() => "")) ?? "") !== "") break;
  await pagina.waitForTimeout(1000);
}

async function definir(tipo, rotulo, valor) {
  const alvo = conf.locator("label").filter({ hasText: new RegExp(`^\\s*${rotulo}`) })
    .locator(tipo === "select" ? "select" : "input").first();
  if ((await alvo.count()) === 0) return `campo "${rotulo}" nao encontrado`;
  if (!(await alvo.isEnabled())) return null;
  if (tipo === "select") await alvo.selectOption(valor); else await alvo.fill(valor);
  await pagina.waitForTimeout(300);
  return null;
}
const falhas = [];
for (const [tipo, rotulo, valor] of [
  ["select", "Presença do comprador", "9"],
  ["select", "Modalidade do frete", "9"],
  ["texto", "Frete", "0"],
  ["texto", "Seguro", "0"],
  ["texto", "Outras despesas", "0"],
  ["select", "Forma de pagamento", "15"],
  ["select", "À vista ou a prazo", "1"],
]) {
  const erro = await definir(tipo, rotulo, valor);
  if (erro) falhas.push(erro);
}
const selDest2 = conf.getByLabel("Destinação da mercadoria");
if ((await selDest2.count()) > 0 && (await selDest2.isEnabled()) && (await selDest2.inputValue()) === "") {
  await selDest2.selectOption(destinacao);
}
if (falhas.length) console.log("   campos:", falhas.join("; "));
await pagina.waitForTimeout(2000);

const emitir = conf.getByRole("button", { name: /^(Emitir em homologação|Tentar emitir novamente)/ });
if ((await emitir.count()) === 0 || !(await emitir.isEnabled())) {
  await captura("emissao-bloqueada");
  const pend = (await conf.locator("li").allTextContents()).map((t) => t.replace(/\s+/g, " ").trim()).filter(Boolean);
  await falhar(`emissao nao habilitou: ${(await avisos()).join(" | ")} || ${pend.join(" | ").slice(0, 600)}`);
}
await captura("pronto-para-emitir");
await emitir.click();
await pagina.waitForTimeout(12_000);
await captura("pos-emissao");
console.log("   retorno:", (await avisos()).join(" | ").slice(0, 400));
const pend = (await conf.locator("li").allTextContents().catch(() => [])).map((t) => t.replace(/\s+/g, " ").trim()).filter(Boolean);
if (pend.length) console.log("   pendencias:", pend.join(" | ").slice(0, 600));

// 3. autorizacao
console.log("[3] aguardando autorização");
let autorizada = false;
for (let espera = 0; espera < 24; espera += 1) {
  await irParaOv();
  await abaFaturamento();
  if ((await pagina.getByText("Autorizada em homologação").count()) > 0) { autorizada = true; break; }
  await pagina.waitForTimeout(5000);
}
await captura(autorizada ? "autorizada" : "sem-autorizacao");
console.log(autorizada ? "AUTORIZADA" : "nao chegou a AUTORIZADA em ~2 min");
console.log("Capturas em:", saida);
await encerrar();
process.exit(autorizada ? 0 : 1);
