/**
 * Libera um perfil NF-e para producao pela tela /faturamento/perfis, vinculado
 * a uma solicitacao homologada. ATO FISCAL: executar com autorizacao do responsavel.
 *
 *   node scripts/chrome-perfil-liberar.mjs <codigo-perfil> <solicitacao_id> "justificativa (15 a 1000)"
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
const [codigo, solicitacaoId, justificativa] = process.argv.slice(2);
if (!codigo || !solicitacaoId || !justificativa || justificativa.length < 15) {
  console.error('Uso: node scripts/chrome-perfil-liberar.mjs <codigo> <solicitacao_id> "justificativa"');
  process.exit(1);
}
const saida = path.join(raiz, "tests", "e2e", ".saida", "perfis");
fs.mkdirSync(saida, { recursive: true });

const navegador = await chromium.launch({ channel: "chrome", headless: true });
const pagina = await navegador.newPage({ viewport: { width: 1360, height: 900 } });
pagina.on("dialog", async (d) => { console.log(`[${d.type()}] ${d.message().replace(/\s+/g, " ").slice(0, 200)}`); await d.accept(); });

await pagina.goto(new URL("/login", baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.getByPlaceholder("seu@email.com").fill(process.env.E2E_EMAIL ?? "");
await pagina.locator('input[type="password"]').first().fill(process.env.E2E_PASSWORD ?? "");
await pagina.getByRole("button", { name: "Entrar" }).click();
for (let i = 0; i < 60; i += 1) {
  if (!new URL(pagina.url()).pathname.startsWith("/login")) break;
  await pagina.waitForTimeout(500);
}

await pagina.goto(new URL("/faturamento/perfis", baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.waitForTimeout(4000);
await pagina.getByLabel("Buscar perfil fiscal").fill(codigo);
await pagina.waitForTimeout(1500);
await pagina.getByRole("button").filter({ hasText: codigo }).first().click();
await pagina.waitForTimeout(3000);

await pagina.locator("#solicitacao-homologada").fill(solicitacaoId);
await pagina.waitForTimeout(2500);
await pagina.locator("#justificativa-liberacao").fill(justificativa);
const caixa = pagina.getByRole("checkbox").filter({ hasText: "" }).last();
const checkboxes = pagina.locator('input[type="checkbox"]');
await checkboxes.last().check();
void caixa;
await pagina.waitForTimeout(800);
await pagina.screenshot({ path: path.join(saida, `${codigo}-liberar-01.png`), timeout: 15000 }).catch(() => {});
const avisosAntes = (await pagina.locator(".text-emerald-300, .text-emerald-200, .text-rose-200, li").allTextContents())
  .map((t) => t.replace(/\s+/g, " ").trim()).filter((t) => /pendencia|posterior|anterior|Confirme|UUID/i.test(t));
console.log("antes:", avisosAntes.slice(0, 6));

const botao = pagina.getByRole("button", { name: /Conferir e liberar para esta homologacao/ });
if ((await botao.count()) === 0 || !(await botao.isEnabled())) {
  console.log("botao de liberar indisponivel");
  await navegador.close();
  process.exit(2);
}
await botao.click();
await pagina.waitForTimeout(8000);
await pagina.screenshot({ path: path.join(saida, `${codigo}-liberar-02.png`), timeout: 15000 }).catch(() => {});
const txt = (await pagina.locator("body").innerText()).replace(/\s+/g, " ");
const i = txt.indexOf("Liberacao separada para producao");
console.log("bloco:", txt.slice(i, i + 260));
const avisos = (await pagina.locator('[role="alert"], [role="status"], .text-emerald-300, .text-emerald-200, .text-rose-200').allTextContents())
  .map((t) => t.replace(/\s+/g, " ").trim()).filter(Boolean);
console.log("avisos:", [...new Set(avisos)].slice(0, 8));
await navegador.close();
