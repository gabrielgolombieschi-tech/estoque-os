import { test, expect } from "@playwright/test";

/**
 * Temporário: varre a carteira atrás da linha de item que uma tentativa de calibração
 * do teste deixou para trás, identificada pelo carimbo exato, e remove.
 */
const ALVO = process.env.ALVO ?? "04/09/2026, 08:43:04";

test("achar e remover a linha perdida", async ({ page }) => {
  test.setTimeout(3_600_000);

  const linhasOs = page.locator("tbody tr:has(td:nth-child(4))");

  async function abrirLista() {
    for (let tentativa = 0; tentativa < 3; tentativa += 1) {
      await page.goto("/os?vista=lista");
      try {
        await expect(linhasOs.first()).toBeVisible({ timeout: 45_000 });
        return true;
      } catch {
        /* tenta de novo */
      }
    }
    return false;
  }

  if (!(await abrirLista())) throw new Error("lista de OS não carregou");
  const quantas = await linhasOs.count();
  console.log(`varrendo ${quantas} OS atrás de "${ALVO}"`);

  for (let i = 0; i < quantas; i += 1) {
    if (!(await abrirLista())) {
      console.log(`indice ${i}: lista não carregou, pulando`);
      continue;
    }
    try {
      await linhasOs.nth(i).locator("td").nth(1).click();
      await page.waitForURL(/\/os\/\d+/, { timeout: 20_000 });
    } catch {
      console.log(`indice ${i}: não abriu, pulando`);
      continue;
    }
    const url = new URL(page.url()).pathname;
    await page.waitForTimeout(2500);

    const tabela = page
      .locator("table")
      .filter({ has: page.getByRole("columnheader", { name: "Ações", exact: true }) });
    if ((await tabela.count()) === 0) continue;
    const linhas = tabela.locator("tbody tr:has(td:nth-child(4))");
    const datas = async () =>
      linhas.evaluateAll((trs) =>
        trs.map((tr) => tr.querySelectorAll("td")[7]?.textContent?.trim() ?? "")
      );

    if (!(await datas()).includes(ALVO)) continue;

    console.log(`ACHOU em ${url}`);
    const linha = linhas.filter({ has: page.locator(`td:text-is("${ALVO}")`) }).first();
    console.log(`  conteudo: ${(await linha.textContent())?.replace(/\s+/g, " ").trim()}`);

    page.once("dialog", (d) => void d.accept());
    await linha.getByRole("button", { name: "Remover" }).click();
    await expect
      .poll(async () => (await datas()).includes(ALVO), { timeout: 30_000, message: "removendo" })
      .toBe(false);
    console.log("  removida");
    return;
  }

  console.log("varredura concluída sem encontrar a linha");
});
