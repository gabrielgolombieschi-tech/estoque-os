/**
 * Abre um Chromium visível já autenticado, para acompanhar/navegar a aplicação.
 * Reaproveita a sessão salva pelos testes; se não houver, faz login com as
 * credenciais de .env.e2e.local. A janela fica aberta até você fechá-la.
 *
 *   node scripts/e2e-navegador.mjs [caminho]
 *   node scripts/e2e-navegador.mjs /os?vista=lista
 */
import { chromium } from "@playwright/test";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

const arquivoEnv = path.join(raiz, ".env.e2e.local");
if (fs.existsSync(arquivoEnv)) {
  for (const linha of fs.readFileSync(arquivoEnv, "utf8").split(/\r?\n/)) {
    const par = linha.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (par && !process.env[par[1]]) process.env[par[1]] = par[2].replace(/^["']|["']$/g, "");
  }
}

const baseURL = process.env.E2E_BASE_URL ?? "http://localhost:3000";
const destino = process.argv[2] ?? "/os?vista=lista";
const arquivoSessao = path.join(raiz, "tests", "e2e", ".auth", "user.json");

const navegador = await chromium.launch({ headless: false, args: ["--start-maximized"] });
const contexto = await navegador.newContext({
  viewport: null,
  storageState: fs.existsSync(arquivoSessao) ? arquivoSessao : undefined,
});
// O Playwright descarta window.confirm/alert/prompt automaticamente quando ninguém
// escuta o evento — e aí botões que dependem de confirmação parecem não fazer nada.
// Como esta janela é para uso humano, aceitamos e registramos no console.
contexto.on("page", (nova) => ligarDialogos(nova));
function ligarDialogos(alvo) {
  alvo.on("dialog", async (dialogo) => {
    console.log(`[${dialogo.type()}] ${dialogo.message().replace(/\s+/g, " ").slice(0, 160)}`);
    console.log("  -> aceito automaticamente");
    await dialogo.accept();
  });
}

const pagina = await contexto.newPage();
ligarDialogos(pagina);

await pagina.goto(new URL(destino, baseURL).toString());

if (pagina.url().includes("/login")) {
  console.log("sessão expirada, logando de novo...");
  await pagina.getByPlaceholder("seu@email.com").fill(process.env.E2E_EMAIL ?? "");
  await pagina.locator('input[type="password"]').fill(process.env.E2E_PASSWORD ?? "");
  await pagina.getByRole("button", { name: "Entrar" }).click();
  await pagina.waitForURL((u) => !u.pathname.startsWith("/login"), { timeout: 30_000 });
  fs.mkdirSync(path.dirname(arquivoSessao), { recursive: true });
  await contexto.storageState({ path: arquivoSessao });
  await pagina.goto(new URL(destino, baseURL).toString());
}

console.log(`navegador aberto em ${pagina.url()} — feche a janela para encerrar`);
await new Promise((resolve) => navegador.on("disconnected", resolve));
console.log("janela fechada");
