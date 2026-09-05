/**
 * Baixa DANFE/XML das notas listadas em /os/[id]/faturar (URL assinada obtida
 * pela propria tela) e tira uma captura da tela.
 *
 *   node scripts/chrome-os-nfe-arquivos.mjs <os_id> <pasta_destino> [numero ...]
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
const [osId, destino, ...numeros] = process.argv.slice(2);
if (!osId || !destino) { console.error("Uso: node scripts/chrome-os-nfe-arquivos.mjs <os_id> <pasta> [numero ...]"); process.exit(1); }
fs.mkdirSync(destino, { recursive: true });

const navegador = await chromium.launch({ channel: "chrome", headless: true });
const contexto = await navegador.newContext({ viewport: { width: 1360, height: 1100 } });
const pagina = await contexto.newPage();
await pagina.goto(new URL("/login", baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByPlaceholder("seu@email.com").fill(process.env.E2E_EMAIL ?? "");
await pagina.locator('input[type="password"]').first().fill(process.env.E2E_PASSWORD ?? "");
await pagina.getByRole("button", { name: "Entrar" }).click();
for (let i = 0; i < 60; i += 1) { if (!new URL(pagina.url()).pathname.startsWith("/login")) break; await pagina.waitForTimeout(500); }

await pagina.goto(new URL(`/os/${osId}/faturar`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByText("Notas desta OS").waitFor({ state: "visible", timeout: 30000 });
await pagina.waitForTimeout(4000);
await pagina.screenshot({ path: path.join(destino, `os-${osId}-faturar.png`), fullPage: true, timeout: 20000 }).catch(() => {});

const linhas = pagina.locator("table tbody tr");
const total = await linhas.count();
for (let i = 0; i < total; i += 1) {
  const linha = linhas.nth(i);
  const texto = (await linha.innerText()).replace(/\s+/g, " ");
  const m = texto.match(/^(?:NF-e )?(\d+)\/(\d+)\b/);
  if (!m) continue;
  if (numeros.length > 0 && !numeros.includes(m[2])) continue;
  for (const tipo of ["DANFE", "XML"]) {
    const botao = linha.getByRole("button", { name: tipo === "DANFE" ? /^(DANFE|DANFSe)$/ : /^XML$/ });
    if ((await botao.count()) === 0) continue;
    const [navegacao] = await Promise.all([
      pagina.waitForEvent("framenavigated", { timeout: 20000 }).catch(() => null),
      botao.click(),
    ]);
    const url = navegacao ? navegacao.url() : pagina.url();
    if (!/^https?:/.test(url) || url.includes("/os/")) { console.log(`${tipo} ${m[1]}/${m[2]}: sem URL`); continue; }
    const resposta = await fetch(url);
    const arquivo = path.join(destino, `nfe-${m[1]}-${m[2]}.${tipo === "DANFE" ? "pdf" : "xml"}`);
    fs.writeFileSync(arquivo, Buffer.from(await resposta.arrayBuffer()));
    console.log(`${tipo} ${m[1]}/${m[2]} -> ${arquivo} (${fs.statSync(arquivo).size} bytes)`);
    await pagina.goto(new URL(`/os/${osId}/faturar`, baseURL).toString(), { waitUntil: "domcontentloaded" });
    await pagina.getByText("Notas desta OS").waitFor({ state: "visible", timeout: 30000 });
    await pagina.waitForTimeout(3000);
  }
}
await navegador.close();
