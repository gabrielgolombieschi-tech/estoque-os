import { test, expect, type Page } from "@playwright/test";
import fs from "node:fs/promises";

// Somente consultas: não seleciona/adiciona itens nem altera saldos.
const termos = ["cabo 1,5", "1,5 cabo", "CABO 1.5"];

async function pesquisar(page: Page, rpc: string, campo: string, botao: string, parametro: string, termo: string) {
  await page.getByLabel(campo, { exact: true }).fill(termo);
  const resposta = page.waitForResponse((r) => {
    if (!r.url().includes(`/rpc/${rpc}`) || r.request().method() !== "POST") return false;
    const payload = r.request().postDataJSON() as Record<string, unknown>;
    return String(payload[parametro]).toLowerCase().replace(/,/g, ".") === termo.toLowerCase().replace(/,/g, ".");
  });
  await page.getByRole("button", { name: botao, exact: true }).click();
  const response = await resposta;
  expect(response.ok(), await response.text()).toBe(true);
  const rows = await response.json() as Array<Record<string, unknown>>;
  expect(rows.length, `Resultados para ${termo} em ${rpc}`).toBeGreaterThan(0);
  return rows;
}

for (const config of [
  { url: "/estoque", rpc: "search_estoque_itens", campo: "Filtrar por produto", botao: "Aplicar filtros", parametro: "p_nome", id: "item_id" },
  { url: "/itens", rpc: "search_cadastro_itens", campo: "Filtrar por produto", botao: "Aplicar filtros", parametro: "p_produto", id: "id" },
  { url: "/mov", rpc: "movimentacoes_buscar", campo: "Buscar movimentacoes", botao: "Aplicar", parametro: "p_busca", id: "id" },
]) {
  test(`busca por palavras, ordem e decimais em ${config.url}`, async ({ page }) => {
    const erros: string[] = [];
    page.on("pageerror", (error) => erros.push(error.message));
    await page.goto(config.url);
    let idsEsperados: unknown[] | undefined;
    for (const termo of termos) {
      const rows = await pesquisar(page, config.rpc, config.campo, config.botao, config.parametro, termo);
      const ids = rows.map((r) => r[config.id]);
      if (idsEsperados) expect(ids).toEqual(idsEsperados);
      idsEsperados = ids;
      await expect(page.locator("tbody tr:has(td:nth-child(4))").first()).toBeVisible();
    }
    expect(erros).toEqual([]);
  });
}

test("relatório mantém busca na URL e no CSV", async ({ page }) => {
  await page.goto("/estoque/relatorios?tab=saldo");
  const rows = await pesquisar(page, "search_relatorio_estoque", "Buscar item", "Aplicar", "p_busca", "cabo 1,5");
  await expect(page).toHaveURL(/a_busca=cabo/);
  const baixar = page.waitForEvent("download");
  await page.getByRole("button", { name: "Exportar CSV", exact: true }).click();
  const download = await baixar;
  const arquivo = await download.path();
  expect(arquivo).not.toBeNull();
  const csv = await fs.readFile(arquivo!, "utf8");
  const codigo = String(rows[0].codigo_interno ?? "");
  expect(codigo).not.toBe("");
  expect(csv).toContain(codigo);
});
