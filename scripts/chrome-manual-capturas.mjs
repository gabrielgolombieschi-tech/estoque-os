/**
 * Capturas de tela (pagina inteira) para o manual de emissao: abre cada
 * endereco logado e salva PNG em tests/e2e/.saida/manual. So le.
 *
 *   node scripts/chrome-manual-capturas.mjs "nome=/rota" "nome2=/rota2|clicar=Faturamento ("
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
const saida = path.join(raiz, "tests", "e2e", ".saida", "manual");
fs.mkdirSync(saida, { recursive: true });
const pedidos = process.argv.slice(2).map((p) => {
  const [nome, resto] = p.split("=", 2);
  const [rota, ...extras] = resto.split("|");
  const clicar = extras.find((e) => e.startsWith("clicar="))?.slice(7) ?? null;
  const buscar = extras.find((e) => e.startsWith("buscar="))?.slice(7) ?? null;
  return { nome, rota, clicar, buscar };
});

const navegador = await chromium.launch({ channel: "chrome", headless: true });
const pagina = await navegador.newPage({ viewport: { width: 1360, height: 900 } });
await pagina.goto(new URL("/login", baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByPlaceholder("seu@email.com").fill(process.env.E2E_EMAIL ?? "");
await pagina.locator('input[type="password"]').first().fill(process.env.E2E_PASSWORD ?? "");
await pagina.getByRole("button", { name: "Entrar" }).click();
for (let i = 0; i < 60; i += 1) { if (!new URL(pagina.url()).pathname.startsWith("/login")) break; await pagina.waitForTimeout(500); }

for (const p of pedidos) {
  await pagina.goto(new URL(p.rota, baseURL).toString(), { waitUntil: "domcontentloaded" });
  await pagina.waitForTimeout(6000);
  if (p.buscar) {
    await pagina.getByLabel("Buscar perfil fiscal").fill(p.buscar);
    await pagina.waitForTimeout(1500);
    await pagina.getByRole("button").filter({ hasText: p.buscar }).first().click();
    await pagina.waitForTimeout(3000);
  }
  if (p.clicar) {
    const botao = pagina.getByRole("button", { name: new RegExp("^" + p.clicar.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")) });
    if ((await botao.count()) > 0) { await botao.first().click(); await pagina.waitForTimeout(5000); }
  }
  await pagina.getByText(/Carregando/).first().waitFor({ state: "hidden", timeout: 30000 }).catch(() => {});
  await pagina.waitForTimeout(1500);
  await pagina.screenshot({ path: path.join(saida, `${p.nome}.png`), fullPage: true, timeout: 30000 });
  console.log("captura:", p.nome);
}
await navegador.close();
