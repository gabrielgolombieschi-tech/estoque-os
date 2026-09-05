/**
 * Altera um campo do cadastro fiscal do cliente pela tela /clientes/cadastro-fiscal
 * (Chrome headless logado) e salva. Decisao humana registrada no comando.
 *
 *   node scripts/chrome-cliente-fiscal-campo.mjs --cliente 1 --campo "CEP" --valor 88200122 [--campo "Bairro" --valor CENTRO ...]
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
const args = process.argv.slice(2);
const clienteId = args[args.indexOf("--cliente") + 1];
const pares = [];
for (let i = 0; i < args.length; i += 1) if (args[i] === "--campo") pares.push({ campo: args[i + 1], valor: args[args.indexOf("--valor", i) + 1] });
if (!clienteId || pares.length === 0) { console.error("Uso: --cliente <id> --campo <rotulo> --valor <valor>"); process.exit(1); }

const navegador = await chromium.launch({ channel: "chrome", headless: true });
const pagina = await navegador.newPage({ viewport: { width: 1360, height: 1000 } });
await pagina.goto(new URL("/login", baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByPlaceholder("seu@email.com").fill(process.env.E2E_EMAIL ?? "");
await pagina.locator('input[type="password"]').first().fill(process.env.E2E_PASSWORD ?? "");
await pagina.getByRole("button", { name: "Entrar" }).click();
for (let i = 0; i < 60; i += 1) { if (!new URL(pagina.url()).pathname.startsWith("/login")) break; await pagina.waitForTimeout(500); }
await pagina.goto(new URL(`/clientes/cadastro-fiscal?cliente_id=${clienteId}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByRole("button", { name: /Salvar e liberar cliente/ }).waitFor({ state: "visible", timeout: 30000 });
await pagina.waitForTimeout(2000);
for (const { campo, valor } of pares) {
  const alvo = pagina.locator("label", { hasText: new RegExp(`^\\s*${campo}`) }).locator("input, select").first();
  const tag = await alvo.evaluate((e) => e.tagName.toLowerCase());
  if (tag === "select") await alvo.selectOption(valor); else await alvo.fill(valor);
  console.log(`${campo} <- ${valor}`);
}
await pagina.waitForTimeout(500);
const salvar = pagina.getByRole("button", { name: /Salvar e liberar cliente/ });
if (!(await salvar.isEnabled())) {
  console.log("salvar desabilitado; pendencias:", (await pagina.locator("li").allTextContents()).map((t) => t.trim()).filter((t) => t.startsWith("•")).slice(0, 8));
  await navegador.close(); process.exit(2);
}
await salvar.click();
await pagina.waitForTimeout(4000);
console.log((await pagina.locator('[role="alert"], [role="status"], .text-emerald-300, .text-red-300').allTextContents()).map((t) => t.trim()).filter(Boolean).slice(0, 4));
await navegador.close();
