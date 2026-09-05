import { test, expect } from "@playwright/test";

/**
 * Temporário: remove as linhas de item criadas pelas tentativas de calibração do
 * teste em 04/09/2026 entre 08:40 e 08:50, na OS indicada por OS_PATH.
 * Rode com REMOVER=1 para de fato apagar.
 */
const REMOVER = process.env.REMOVER === "1";
const OS_PATH = process.env.OS_PATH ?? "/os/345";
const ALVO = /^04\/09\/2026, 08:4[0-9]:/;

test("limpar linhas deixadas pelas tentativas", async ({ page }) => {
  test.setTimeout(300_000);

  await page.goto(OS_PATH);
  await page.waitForLoadState("networkidle");
  await page.waitForTimeout(3000);

  const tabela = page
    .locator("table")
    .filter({ has: page.getByRole("columnheader", { name: "Ações", exact: true }) });
  const linhas = tabela.locator("tbody tr:has(td:nth-child(4))");
  const datas = async () =>
    linhas.evaluateAll((trs) =>
      trs.map((tr) => tr.querySelectorAll("td")[7]?.textContent?.trim() ?? "")
    );

  const suspeitas = (await datas()).filter((d) => ALVO.test(d));
  console.log(`${OS_PATH} -> ${suspeitas.length} linha(s): ${suspeitas.join(" | ")}`);
  if (!REMOVER) return;

  for (const carimbo of suspeitas) {
    const linha = linhas.filter({ has: page.locator(`td:text-is("${carimbo}")`) }).first();
    page.once("dialog", (d) => void d.accept());
    await linha.getByRole("button", { name: "Remover" }).click();
    await expect
      .poll(async () => (await datas()).includes(carimbo), {
        timeout: 30_000,
        message: `removendo ${carimbo}`,
      })
      .toBe(false);
    console.log(`  removida ${carimbo}`);
  }

  console.log("restaram:", (await datas()).join(" | ") || "(nenhuma linha)");
});
