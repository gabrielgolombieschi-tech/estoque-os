import fs from "node:fs";
import path from "node:path";
import { chromium } from "@playwright/test";
const raiz = "C:/Users/gabri/Dropbox/Projeto_Estoque/estoque-os";
for (const linha of fs.readFileSync(path.join(raiz, ".env.e2e.local"), "utf8").split(/\r?\n/)) {
  const par = linha.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
  if (par && !process.env[par[1]]) process.env[par[1]] = par[2].replace(/^["']|["']$/g, "");
}
const baseURL = process.env.E2E_BASE_URL ?? "http://localhost:3000";
const doc = "31e83275-c3cd-430c-973a-f03c79be5c8d";
const navegador = await chromium.launch({ channel: "chrome", headless: true });
const ctx = await navegador.newContext({ acceptDownloads: true });
const pagina = await ctx.newPage();
await pagina.goto(new URL("/login", baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByPlaceholder("seu@email.com").fill(process.env.E2E_EMAIL ?? "");
await pagina.locator('input[type="password"]').first().fill(process.env.E2E_PASSWORD ?? "");
await pagina.getByRole("button", { name: "Entrar" }).click();
for (let i = 0; i < 60; i += 1) { if (!new URL(pagina.url()).pathname.startsWith("/login")) break; await pagina.waitForTimeout(500); }
await pagina.goto(new URL(`/faturamento/nfe/${doc}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByText("Ciclo de vida da NF-e").first().waitFor({ state: "visible", timeout: 30000 });
await pagina.waitForTimeout(3000);
const urlAntes = pagina.url();
const [download] = await Promise.all([
  pagina.waitForEvent("download", { timeout: 45000 }).catch(() => null),
  pagina.getByRole("button", { name: "Baixar XML" }).click(),
]);
await pagina.waitForTimeout(4000);
if (download) {
  const destino = path.join(process.env.SCRATCH, download.suggestedFilename());
  await download.saveAs(destino);
  console.log("DOWNLOAD OK · arquivo:", download.suggestedFilename(), "· bytes:", fs.statSync(destino).size);
} else {
  console.log("SEM DOWNLOAD · url agora:", pagina.url());
}
console.log("permaneceu na pagina:", pagina.url() === urlAntes);
await navegador.close();
