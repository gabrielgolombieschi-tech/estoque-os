/**
 * Cancela uma NF-e REAL (producao) pela tela NF-e -> Ciclo de vida, com
 * Chrome headless logado. ACAO FISCAL IRREVERSIVEL: executar somente com
 * autorizacao explicita do responsavel.
 *
 *   node scripts/chrome-nfe-cancelar-producao.mjs <documento_fiscal_id> "justificativa (15 a 255)"
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
const documentoId = process.argv[2];
const justificativa = process.argv[3];
if (!documentoId || !justificativa || justificativa.length < 15 || justificativa.length > 255) {
  console.error('Uso: node scripts/chrome-nfe-cancelar-producao.mjs <documento_fiscal_id> "justificativa (15 a 255)"');
  process.exit(1);
}
const saida = path.join(raiz, "tests", "e2e", ".saida", "cancelamento-producao");
fs.mkdirSync(saida, { recursive: true });

const navegador = await chromium.launch({ channel: "chrome", headless: true });
const pagina = await navegador.newPage({ viewport: { width: 1360, height: 900 } });
let passo = 0;
async function foto(nome) {
  passo += 1;
  await pagina.screenshot({ path: path.join(saida, `${String(passo).padStart(2, "0")}-${nome}.png`), timeout: 15000 }).catch(() => {});
}
async function avisos() {
  return [...new Set((await pagina.locator('[role="alert"], [role="status"], .text-emerald-300, .text-rose-200, .text-sky-200').allTextContents())
    .map((t) => t.replace(/\s+/g, " ").trim()).filter(Boolean))].slice(0, 10);
}
pagina.on("dialog", async (d) => {
  console.log(`[${d.type()}] ${d.message().replace(/\s+/g, " ")}`);
  await d.accept();
});

await pagina.goto(new URL("/login", baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByPlaceholder("seu@email.com").fill(process.env.E2E_EMAIL ?? "");
await pagina.locator('input[type="password"]').first().fill(process.env.E2E_PASSWORD ?? "");
await pagina.getByRole("button", { name: "Entrar" }).click();
for (let i = 0; i < 60; i += 1) {
  if (!new URL(pagina.url()).pathname.startsWith("/login")) break;
  await pagina.waitForTimeout(500);
}

await pagina.goto(new URL(`/faturamento/nfe/${documentoId}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByText("Ciclo de vida da NF-e").first().waitFor({ state: "visible", timeout: 30000 });
await pagina.waitForTimeout(3000);
await foto("detalhe");
console.log("antes:", await avisos());

const botao = pagina.getByRole("button", { name: "Cancelar NF-e real na SEFAZ" });
await botao.waitFor({ state: "visible", timeout: 20000 }).catch(() => {});
if ((await botao.count()) === 0) {
  console.log("Botao de cancelamento real nao disponivel. Botoes:", (await pagina.locator("button:visible").allTextContents()).filter((t) => /cancel|estorno/i.test(t)));
  await navegador.close();
  process.exit(2);
}
await pagina.getByPlaceholder("Justificativa (15 a 255 caracteres)").fill(justificativa);
await foto("justificativa");
console.log("clicando em Cancelar NF-e real na SEFAZ (confirm sera aceito)");
await botao.click();
await pagina.waitForTimeout(20000);
await foto("resposta");
console.log("depois:", await avisos());
await pagina.reload({ waitUntil: "domcontentloaded" });
await pagina.waitForTimeout(6000);
await foto("recarregado");
const historico = (await pagina.locator("li, tr").allTextContents())
  .map((t) => t.replace(/\s+/g, " ").trim())
  .filter((t) => /CANCELAMENTO|AUTORIZACAO/.test(t)).slice(0, 8);
console.log("historico:", historico);
console.log("capturas em:", saida);
await navegador.close();
