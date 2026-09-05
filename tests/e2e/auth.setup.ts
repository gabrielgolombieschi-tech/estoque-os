import { test as setup, expect } from "@playwright/test";
import fs from "node:fs";
import path from "node:path";

const arquivoSessao = path.join(__dirname, ".auth", "user.json");

setup("autentica e guarda a sessão", async ({ page }) => {
  const email = process.env.E2E_EMAIL;
  const senha = process.env.E2E_PASSWORD;
  if (!email || !senha) {
    throw new Error("Defina E2E_EMAIL e E2E_PASSWORD em .env.e2e.local");
  }

  await page.goto("/login");
  await page.getByPlaceholder("seu@email.com").fill(email);
  await page.locator('input[type="password"]').fill(senha);
  await page.getByRole("button", { name: "Entrar" }).click();

  // O login mostra o erro do Supabase na própria tela; falha rápido em vez de esperar timeout.
  const erro = page.locator("p.text-red-400");
  await expect
    .poll(async () => (await erro.isVisible()) ? await erro.textContent() : "sem-erro", {
      timeout: 30_000,
      message: "aguardando sair de /login",
    })
    .toBe("sem-erro");
  await page.waitForURL((url) => !url.pathname.startsWith("/login"), { timeout: 30_000 });

  // Contas com mais de uma empresa param na tela de seleção.
  if (page.url().includes("/selecionar-empresa")) {
    await page.locator("button").filter({ hasNotText: /^$/ }).first().click();
    await page.waitForURL((url) => !url.pathname.includes("/selecionar-empresa"), {
      timeout: 30_000,
    });
  }

  fs.mkdirSync(path.dirname(arquivoSessao), { recursive: true });
  await page.context().storageState({ path: arquivoSessao });
});
