/**
 * Abandona todas as homologacoes autorizadas de uma OS pela tela /os/[id]/faturar
 * (devolve o saldo; as NF-e de teste continuam autorizadas na SEFAZ de homologacao).
 *
 *   node scripts/chrome-os-nfe-abandonar.mjs 303
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
const osId = process.argv[2];
if (!osId) { console.error("Uso: node scripts/chrome-os-nfe-abandonar.mjs <os_id>"); process.exit(1); }

const navegador = await chromium.launch({ channel: "chrome", headless: true });
const pagina = await navegador.newPage({ viewport: { width: 1360, height: 1000 } });
pagina.on("dialog", async (d) => {
  console.log(`[${d.type()}] ${d.message().replace(/\s+/g, " ").slice(0, 120)}`);
  await d.accept(d.type() === "prompt" ? "Homologacao concluida no cenario de teste; saldo devolvido a OS." : undefined);
});
await pagina.goto(new URL("/login", baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByPlaceholder("seu@email.com").fill(process.env.E2E_EMAIL ?? "");
await pagina.locator('input[type="password"]').first().fill(process.env.E2E_PASSWORD ?? "");
await pagina.getByRole("button", { name: "Entrar" }).click();
for (let i = 0; i < 60; i += 1) { if (!new URL(pagina.url()).pathname.startsWith("/login")) break; await pagina.waitForTimeout(500); }

for (let rodada = 0; rodada < 6; rodada += 1) {
  await pagina.goto(new URL(`/os/${osId}/faturar`, baseURL).toString(), { waitUntil: "domcontentloaded" });
  await pagina.getByText("Notas desta OS").waitFor({ state: "visible", timeout: 30000 });
  await pagina.waitForTimeout(4000);
  const botao = pagina.getByRole("button", { name: "abandonar homologação" });
  if ((await botao.count()) === 0) break;
  console.log(`rodada ${rodada + 1}: ${await botao.count()} homologacao(oes) para abandonar`);
  await botao.first().click();
  await pagina.waitForTimeout(6000);
  const status = (await pagina.locator('[role="status"], [role="alert"]').allTextContents()).map((t) => t.replace(/\s+/g, " ").trim()).filter(Boolean);
  console.log("  ", status.slice(0, 2));
}
const txt = (await pagina.locator("body").innerText()).replace(/\s+/g, " ");
const i = txt.indexOf("Saldo a faturar");
console.log("final:", txt.slice(i, i + 120));
await navegador.close();
