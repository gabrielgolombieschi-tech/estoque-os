/**
 * Cenario de homologacao da NFS-e Nacional pela tela /os/[id]/faturar, com
 * Chrome headless logado. CHAMA A FOCUS DE HOMOLOGACAO (sem valor fiscal).
 *
 *   node scripts/chrome-os-nfse-homologacao.mjs --os 326 --perfil 14.06 \
 *     [--valor 3000] [--municipio 4218004] [--competencia 2026-09-05] \
 *     [--iss sim|nao] [--pcc sim|nao] [--irrf sim|nao] [--inss sim|nao] [--justificativa "texto"] \
 *     [--add-os 287] [--forma 15] [--indicador 1] [--dias 30] [--pedido 1307761] [--item 10] \
 *     [--obs "texto"] [--so-conferir] [--cancelar "justificativa"] [--substituir "motivo"]
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
const perfilItem = arg("perfil");
if (!osId) { console.error("--os e obrigatorio"); process.exit(1); }
const saida = path.join(raiz, "tests", "e2e", ".saida", `os-nfse-${osId}`);
fs.mkdirSync(saida, { recursive: true });

const navegador = await chromium.launch({ channel: "chrome", headless: true });
const pagina = await navegador.newPage({ viewport: { width: 1360, height: 1100 } });
let passo = 0;
async function foto(nome) { passo += 1; await pagina.screenshot({ path: path.join(saida, `${String(passo).padStart(2, "0")}-${nome}.png`), fullPage: true, timeout: 20000 }).catch(() => {}); }
async function avisos() {
  return [...new Set((await pagina.locator('[role="alert"], [role="status"], li').allTextContents()).map((t) => t.replace(/\s+/g, " ").trim()).filter((t) => t && t.length < 500))].slice(0, 14);
}
async function status() {
  const txt = (await pagina.locator("body").innerText()).replace(/\s+/g, " ");
  const st = txt.indexOf("Status:");
  return st >= 0 ? txt.slice(st, st + 320) : "";
}
pagina.on("dialog", async (d) => {
  console.log(`[${d.type()}] ${d.message().replace(/\s+/g, " ").slice(0, 160)}`);
  if (d.type() === "prompt") {
    const msg = d.message();
    if (/Código de justificativa/i.test(msg)) return d.accept("99");
    if (/Motivo da substituição/i.test(msg)) return d.accept(arg("substituir") ?? "Substituicao no cenario de homologacao 13");
    if (/E-mails para envio/i.test(msg)) return d.accept(arg("email") ?? "");
    // accept() sem texto devolve string vazia no prompt; o motivo precisa de 15+ caracteres.
    return d.accept("Rascunho refeito no cenario de homologacao da NFS-e");
  }
  await d.accept();
});

await pagina.goto(new URL("/login", baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByPlaceholder("seu@email.com").fill(process.env.E2E_EMAIL ?? "");
await pagina.locator('input[type="password"]').first().fill(process.env.E2E_PASSWORD ?? "");
await pagina.getByRole("button", { name: "Entrar" }).click();
for (let i = 0; i < 60; i += 1) { if (!new URL(pagina.url()).pathname.startsWith("/login")) break; await pagina.waitForTimeout(500); }

await pagina.goto(new URL(`/os/${osId}/faturar`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByText("Notas desta OS").waitFor({ state: "visible", timeout: 30000 });
await pagina.waitForTimeout(4000);

// Perfil de servico no cabecalho (se ainda nao houver rascunho).
async function escolherPerfil() {
  const seletor = pagina.getByLabel(/Operação \(perfil da nota\)/);
  if (perfilItem && (await seletor.isEnabled())) {
    let opcoes = [];
    for (let i = 0; i < 20; i += 1) {
      opcoes = await seletor.locator("option").evaluateAll((els) => els.map((e) => ({ value: e.value, label: e.textContent ?? "", disabled: e.disabled })));
      if (opcoes.some((o) => o.label.trim().startsWith(`${perfilItem} `))) break;
      await pagina.waitForTimeout(1500);
    }
    const alvo = opcoes.find((o) => o.label.trim().startsWith(`${perfilItem} `));
    if (!alvo) { console.log("perfil nao encontrado:", perfilItem, opcoes.map((o) => o.label)); await navegador.close(); process.exit(2); }
    if (alvo.disabled) { console.log(`perfil ${perfilItem} bloqueado: ${alvo.label}`); await foto("perfil-bloqueado"); await navegador.close(); process.exit(0); }
    if ((await seletor.inputValue()) !== alvo.value) { await seletor.selectOption(alvo.value); await pagina.waitForTimeout(3000); }
  }
  await pagina.getByText("Linhas da NFS-e").waitFor({ state: "visible", timeout: 30000 });
  await pagina.getByText("Carregando dados da NFS-e").waitFor({ state: "hidden", timeout: 60000 }).catch(() => {});
  await pagina.waitForTimeout(1500);
}
await escolherPerfil();
await foto("inicio");
const cab = (await pagina.locator("body").innerText()).replace(/\s+/g, " ");
const posSaldo = cab.toUpperCase().indexOf("SALDO A FATURAR");
console.log("[1]", posSaldo >= 0 ? cab.slice(posSaldo, posSaldo + 150) : "(saldo nao encontrado)");

// Descarte do rascunho atual (rejeitado ou nao) para recomecar com cadastro atualizado.
if (tem("descartar")) {
  const botao = pagina.getByRole("button", { name: /Descartar rascunho|Abandonar homologação/ });
  if ((await botao.count()) === 0) { console.log("[descartar] nada para descartar"); }
  else { await botao.click(); await pagina.waitForTimeout(6000); console.log("[descartar]", (await avisos()).filter((t) => /abandon|descart|erro|saldo/i.test(t)).slice(0, 3)); }
  await pagina.reload({ waitUntil: "domcontentloaded" });
  await pagina.getByText("Notas desta OS").waitFor({ state: "visible", timeout: 30000 });
  await pagina.waitForTimeout(4000);
  await escolherPerfil();
}
// Producao: emite a NFS-e real da solicitacao ja homologada (perfil liberado).
if (tem("producao")) {
  const botao = pagina.getByRole("button", { name: /^Emitir NFS-e real/ });
  await botao.waitFor({ state: "visible", timeout: 20000 }).catch(() => {});
  if ((await botao.count()) === 0) { console.log("[producao] botao ausente:", (await avisos()).filter((t) => /Produção|Producao|pronta|perfil/i.test(t)).slice(0, 4)); await foto("producao-indisponivel"); await navegador.close(); process.exit(5); }
  await botao.click();
  await pagina.waitForTimeout(12000);
  console.log("[producao] avisos:", (await avisos()).filter((t) => /Focus|DPS|erro|PRODU|real/i.test(t)).slice(0, 5));
  let resultado = null;
  for (let i = 0; i < 24; i += 1) {
    const trecho = await status();
    if (/AUTORIZADA · NFS-e REAL/.test(trecho) || /REJEITADA|ERRO/.test(trecho)) { resultado = trecho; break; }
    await pagina.waitForTimeout(5000);
    await pagina.reload({ waitUntil: "domcontentloaded" });
    await pagina.waitForTimeout(4000);
  }
  await foto("producao-final");
  console.log("[producao]", resultado ?? `sem estado final em ~3 min: ${await status()}`);
  await navegador.close(); process.exit(0);
}
// E-mail da NFS-e real (XML + DANFSe pela Focus). --email destinatario@dominio
if (arg("email")) {
  const botao = pagina.getByRole("button", { name: "Enviar por e-mail", exact: true });
  await botao.waitFor({ state: "visible", timeout: 20000 }).catch(() => {});
  if ((await botao.count()) === 0) { console.log("[email] botao ausente (a nota precisa estar AUTORIZADA em producao)"); await foto("email-indisponivel"); await navegador.close(); process.exit(6); }
  await botao.click();
  await pagina.waitForTimeout(8000);
  await foto("email-enviado");
  console.log("[email]", (await avisos()).filter((t) => /e-mail|E-mail|erro/i.test(t)).slice(0, 4));
  await navegador.close(); process.exit(0);
}
// Segunda nota parcial na mesma OS: abre composicao nova ignorando a autorizada.
if (tem("nova")) {
  const botao = pagina.getByRole("button", { name: /^Nova NFS-e parcial/ });
  if ((await botao.count()) === 0) { console.log("[nova] botao ausente (sem nota autorizada ou saldo zero)"); }
  else { await botao.click(); await pagina.waitForTimeout(6000); console.log("[nova] composicao nova aberta"); }
}
// Cancelamento / substituicao de uma nota ja autorizada nesta OS.
if (tem("cancelar")) {
  await pagina.getByLabel(/Justificativa do cancelamento/).fill(arg("cancelar"));
  await pagina.getByRole("button", { name: /^Cancelar NFS-e/ }).click();
  await pagina.waitForTimeout(15000);
  await foto("cancelada");
  console.log("[cancelar]", (await avisos()).filter((t) => /cancel|erro|Status/i.test(t)).slice(0, 5));
  await navegador.close(); process.exit(0);
}
if (tem("substituir")) {
  await pagina.getByRole("button", { name: "Substituir", exact: true }).click();
  await pagina.waitForTimeout(6000);
  await foto("substituta-rascunho");
  console.log("[substituir]", (await avisos()).filter((t) => /substitut|erro/i.test(t)).slice(0, 4));
  // Continua: reconfere e emite a substituta.
}

const jaConferida = (await pagina.getByRole("button", { name: /Reconferir|Tentar emitir novamente|Emitir NFS-e em homologação/ }).count()) > 0
  && (await pagina.getByRole("button", { name: "Salvar rascunho e conferir" }).count()) === 0;
// Rascunho ja tentado (REJEITADA/ERRO): o material fiscal esta congelado; so o retry com DPS nova.
const soEmitir = tem("so-emitir") || (jaConferida && (await pagina.getByRole("button", { name: /Tentar emitir novamente/ }).count()) > 0);
if (!jaConferida && !soEmitir) {
  if (arg("valor")) await pagina.getByLabel("Valor (R$)").first().fill(arg("valor"));
  if (arg("descricao")) await pagina.getByLabel("Descrição do serviço").first().fill(arg("descricao"));
  if (arg("add-os")) {
    const sel = pagina.locator("select").filter({ hasText: "Adicionar OS do mesmo tomador" }).first();
    const opcoes = await sel.locator("option").evaluateAll((els) => els.map((e) => ({ value: e.value, label: e.textContent ?? "" })));
    const alvo = opcoes.find((o) => o.label.includes(`OS ${arg("add-os")} `));
    if (!alvo) { console.log("OS adicional nao encontrada:", opcoes.map((o) => o.label)); }
    else { await sel.selectOption(alvo.value); await pagina.waitForTimeout(500); if (arg("valor2")) await pagina.getByLabel("Valor (R$)").nth(1).fill(arg("valor2")); }
  }
}
if (soEmitir) console.log("[2] rascunho congelado; pulando a conferencia");
if (!soEmitir) {
if (arg("municipio")) await pagina.getByLabel(/Município de prestação/).fill(arg("municipio"));
if (arg("competencia")) await pagina.getByLabel("Competência").fill(arg("competencia"));
for (const [nome, rotulo] of [["iss", /ISS retido pelo tomador/], ["pcc", /PIS\/COFINS\/CSLL retidos/], ["irrf", /IRRF retido/], ["inss", /INSS retido/]]) {
  if (arg(nome)) { const s = pagina.getByLabel(rotulo); if (await s.isEnabled()) await s.selectOption(arg(nome)); }
}
if (arg("justificativa")) { const j = pagina.getByLabel(/Justificativa da retenção/); if ((await j.count()) > 0) await j.fill(arg("justificativa")); }
// --conserto: marca a OS como conserto isolado (dispensa a CRF no 14.01, IN RFB 2.141/2023 art. 2 §2 II).
if (tem("conserto")) { const c = pagina.getByRole("checkbox").filter({ has: pagina.locator("xpath=..") }).first(); const caixa = pagina.locator('label:has-text("Conserto isolado") input[type="checkbox"]'); if ((await caixa.count()) > 0 && !(await caixa.isChecked())) await caixa.check(); void c; }
if (arg("material")) { const m = pagina.getByLabel(/Material fornecido e incorporado/); if ((await m.count()) > 0) await m.fill(arg("material")); }
if (arg("pedido") !== null) await pagina.getByLabel(/Pedido de compra do tomador/).fill(arg("pedido"));
if (arg("item")) await pagina.getByLabel("Item do pedido").fill(arg("item"));
if (arg("forma")) await pagina.getByLabel("Forma de pagamento").selectOption(arg("forma"));
if (arg("indicador")) await pagina.getByLabel("À vista ou a prazo").selectOption(arg("indicador"));
if (arg("dias")) { const d = pagina.getByLabel("Dias").first(); if ((await d.count()) > 0) await d.fill(arg("dias")); }
if (arg("obs")) await pagina.getByLabel(/Observação livre/).fill(arg("obs"));
await foto("preenchido");
console.log("[2] conferindo");
const botaoConferir = pagina.getByRole("button", { name: jaConferida ? "Reconferir" : "Salvar rascunho e conferir" });
if (!(await botaoConferir.isEnabled())) {
  console.log("conferir indisponivel:", (await avisos()).filter((t) => /indispon|bloque|Escolha|fixture/i.test(t)).slice(0, 6));
  await foto("conferir-indisponivel");
  await navegador.close();
  process.exit(4);
}
await botaoConferir.click();
await pagina.waitForTimeout(9000);
await foto("conferido");
const depoisConferir = await avisos();
console.log("   avisos:", depoisConferir.filter((t) => /Confer|Bloqueio|bloqueio|Linha|pend|cadastro|acima|indefinid|inscri|Aviso/i.test(t)).slice(0, 10));
const previa = (await pagina.locator("body").innerText()).replace(/\s+/g, " ");
const pb = previa.indexOf("Bruto ");
if (pb >= 0) console.log("   previa:", previa.slice(pb, pb + 260));
const disc = pagina.getByLabel(/Discriminação/);
if ((await disc.count()) > 0) console.log("   discriminacao:", (await disc.inputValue()).slice(0, 400));
}

if (tem("so-conferir")) { console.log("--so-conferir: parando antes de emitir"); await navegador.close(); process.exit(0); }

const emitir = pagina.getByRole("button", { name: /^(Emitir NFS-e em homologação|Tentar emitir novamente)/ });
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
console.log("   avisos:", (await avisos()).filter((t) => /Focus|Status|DPS|erro|Autorizada|processamento|habilitad/i.test(t)).slice(0, 6));
let resultado = null;
for (let i = 0; i < 24; i += 1) {
  const trecho = await status();
  if (/Autorizada em homologação/.test(trecho)) { resultado = trecho; break; }
  if (/REJEITADA|ERRO/.test(trecho)) { resultado = trecho; break; }
  await pagina.waitForTimeout(5000);
  await pagina.reload({ waitUntil: "domcontentloaded" });
  await pagina.waitForTimeout(4000);
}
await foto("final");
console.log("[4]", resultado ?? `sem estado final em ~3 min: ${await status()}`);
console.log("capturas em:", saida);
await navegador.close();
