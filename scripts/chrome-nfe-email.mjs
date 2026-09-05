/**
 * Envia XML + DANFE de uma NF-e de PRODUCAO por e-mail pela tela de ciclo de
 * vida (acao EMAIL da Focus). ENVIA E-MAIL REAL: executar com autorizacao.
 *
 *   node scripts/chrome-nfe-email.mjs <documento_fiscal_id> destinatario@dominio
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
const [documentoId, emails] = process.argv.slice(2);
if (!documentoId || !emails) {
  console.error("Uso: node scripts/chrome-nfe-email.mjs <documento_fiscal_id> <emails>");
  process.exit(1);
}
const saida = path.join(raiz, "tests", "e2e", ".saida", "email");
fs.mkdirSync(saida, { recursive: true });

const navegador = await chromium.launch({ channel: "chrome", headless: true });
const pagina = await navegador.newPage({ viewport: { width: 1360, height: 900 } });
pagina.on("dialog", async (d) => { console.log(`[${d.type()}] ${d.message().replace(/\s+/g, " ").slice(0, 220)}`); await d.accept(); });

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
const campo = pagina.getByPlaceholder("E-mails separados por vírgula");
await campo.fill(emails);
const botao = pagina.getByRole("button", { name: "Revisado: enviar XML + DANFE" });
await botao.waitFor({ state: "visible", timeout: 15000 });
if (!(await botao.isEnabled())) {
  console.log("botao de envio desabilitado (XML/DANFE arquivados? nota em producao e autorizada?)");
  await navegador.close();
  process.exit(2);
}
await pagina.screenshot({ path: path.join(saida, "01-antes.png"), timeout: 15000 }).catch(() => {});
await botao.click();
await pagina.waitForTimeout(15000);
await pagina.screenshot({ path: path.join(saida, "02-depois.png"), timeout: 15000 }).catch(() => {});
const avisos = [...new Set((await pagina.locator('[role="alert"], [role="status"], .text-sky-200, .text-emerald-300, .text-rose-200').allTextContents())
  .map((t) => t.replace(/\s+/g, " ").trim()).filter(Boolean))];
console.log("avisos:", avisos.slice(0, 8));
await navegador.close();
