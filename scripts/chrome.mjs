/**
 * Helper de conexão ao Chrome de teste (aberto por scripts/chrome-abrir.mjs).
 *
 * Conecta por CDP, devolve a aba que está na aplicação, e um `encerrar()` que
 * SÓ desconecta — nunca fecha o Chrome. Assim a janela continua sendo do usuário.
 */
import { chromium } from "@playwright/test";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
export const PORTA = 9222;

const arquivoEnv = path.join(raiz, ".env.e2e.local");
if (fs.existsSync(arquivoEnv)) {
  for (const linha of fs.readFileSync(arquivoEnv, "utf8").split(/\r?\n/)) {
    const par = linha.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (par && !process.env[par[1]]) process.env[par[1]] = par[2].replace(/^["']|["']$/g, "");
  }
}

export const baseURL = process.env.E2E_BASE_URL ?? "http://localhost:3000";

export async function conectar({ aceitarDialogos = true } = {}) {
  const navegador = await chromium.connectOverCDP(`http://127.0.0.1:${PORTA}`);
  const contexto = navegador.contexts()[0];
  if (!contexto) throw new Error("Chrome sem contexto. Rode `npm run chrome` primeiro.");

  const paginas = contexto.pages();
  const pagina =
    paginas.find((p) => p.url().startsWith(baseURL)) ?? paginas[0];
  if (!pagina) throw new Error("Nenhuma aba aberta no Chrome de teste.");

  // Só enquanto EU estou dirigindo: sem isso o Playwright descarta os confirm()
  // e botões que dependem de confirmação falham em silêncio. Ao desconectar, o
  // Chrome volta a mostrar os diálogos normalmente para o usuário.
  if (aceitarDialogos) {
    pagina.on("dialog", async (dialogo) => {
      console.log(`  [${dialogo.type()}] ${dialogo.message().replace(/\s+/g, " ").slice(0, 140)}`);
      await dialogo.accept();
    });
  }

  return { navegador, contexto, pagina, encerrar: () => navegador.close() };
}

/**
 * Login only-if-needed, reaproveitando o perfil persistente do Chrome.
 * O redirect para /login é client-side, então esperamos o formulário aparecer
 * em vez de conferir a URL logo após o goto (que ainda seria a de destino).
 */
export async function garantirSessao(pagina) {
  const campoEmail = pagina.getByPlaceholder("seu@email.com");
  try {
    await campoEmail.waitFor({ state: "visible", timeout: 8000 });
  } catch {
    return false; // não caiu no login: já está autenticado
  }
  await campoEmail.fill(process.env.E2E_EMAIL ?? "");
  await pagina.locator('input[type="password"]').fill(process.env.E2E_PASSWORD ?? "");
  await pagina.getByRole("button", { name: "Entrar" }).click();
  await pagina.waitForURL((u) => !u.pathname.startsWith("/login"), { timeout: 30_000 });
  return true;
}
