import { expect, test, type Page } from "@playwright/test";

// Leituras do catalogo existente. Nao cadastra, altera nem movimenta itens.
const termosEquivalentes = ["cabo 1,5", "1.5 CABO", "CÁBO 1.5"];
type ItemEncontrado = { id: number; nome: string };

async function consultar(
  page: Page,
  coluna: "nome_item_busca" | "busca_item",
  acao: () => Promise<unknown>,
): Promise<number[]> {
  const respostaPendente = page.waitForResponse((resposta) => {
    const url = new URL(resposta.url());
    const filtros = url.searchParams.getAll(coluna);
    return url.pathname.endsWith("/rest/v1/itens")
      && resposta.request().method() === "GET"
      && filtros.includes("ilike.%CABO%")
      && filtros.includes("ilike.%1.5%");
  });
  await acao();
  const resposta = await respostaPendente;
  expect(resposta.ok(), `Consulta de ${coluna}: HTTP ${resposta.status()}`).toBe(true);
  const url = new URL(resposta.url());
  expect(url.searchParams.get("tenant_id")).toMatch(/^eq\./);
  expect(url.searchParams.get("empresa_id")).toMatch(/^eq\./);
  const itens = await resposta.json() as ItemEncontrado[];
  expect(itens.length, "O catalogo deve ter cabos de 1,5 para este teste de regressao").toBeGreaterThan(0);
  await expect(page.locator("table").first()).toBeVisible();
  return itens.map((item) => Number(item.id)).sort((a, b) => a - b);
}

test.beforeEach(async ({ page }) => {
  await page.route("**/rest/v1/**", async (route) => {
    const request = route.request();
    const mutation = ["PATCH", "DELETE", "PUT"].includes(request.method())
      || (request.method() === "POST" && !new URL(request.url()).pathname.includes("/rpc/"));
    if (mutation) throw new Error("O teste de consulta tentou alterar dados.");
    await route.continue();
  });
});

test("ajuste de nomes encontra palavras separadas e decimais equivalentes", async ({ page }) => {
  const erros: string[] = [];
  page.on("pageerror", (erro) => erros.push(erro.message));
  await page.goto("/estoque/ajuste-nome");
  const resultados: number[][] = [];
  for (const termo of termosEquivalentes) {
    resultados.push(await consultar(page, "nome_item_busca", async () => {
      await page.getByRole("textbox", { name: "Filtrar por produto", exact: true }).fill(termo);
      await page.getByRole("button", { name: "Aplicar filtros", exact: true }).click();
    }));
  }
  expect(resultados[1]).toEqual(resultados[0]);
  expect(resultados[2]).toEqual(resultados[0]);
  expect(erros).toEqual([]);
});

test("impressao mantem o filtro de produto e sua busca por termos", async ({ page }) => {
  const erros: string[] = [];
  page.on("pageerror", (erro) => erros.push(erro.message));
  const resultados: number[][] = [];
  for (const termo of termosEquivalentes) {
    resultados.push(await consultar(page, "nome_item_busca", () => page.goto(
      `/itens/imprimir?${new URLSearchParams({ produto: termo, ativo: "ativos" })}`,
    )));
  }
  expect(resultados[1]).toEqual(resultados[0]);
  expect(resultados[2]).toEqual(resultados[0]);
  // Links legados usam q; nao podem perder a virgula de 1,5.
  const livres = await consultar(page, "busca_item", () => page.goto(
    `/itens/imprimir?${new URLSearchParams({ q: "cabo 1,5", ativo: "ativos" })}`,
  ));
  expect(livres).toEqual(expect.arrayContaining(resultados[0]));
  expect(erros).toEqual([]);
});

test("pesos usa a mesma busca sem alterar os valores cadastrados", async ({ page }) => {
  const erros: string[] = [];
  page.on("pageerror", (erro) => erros.push(erro.message));
  await page.goto("/itens/pesos");
  await page.getByRole("checkbox").uncheck();
  const resultados: number[][] = [];
  for (const termo of termosEquivalentes) {
    resultados.push(await consultar(page, "busca_item", () => page.getByRole("textbox", { name: "Buscar item", exact: true }).fill(termo)));
    await expect(page.getByRole("button", { name: "Recarregar", exact: true })).toBeEnabled();
  }
  expect(resultados[1]).toEqual(resultados[0]);
  expect(resultados[2]).toEqual(resultados[0]);
  expect(erros).toEqual([]);
});

test("localizador da baixa de OS pesquisa sem selecionar ou baixar item", async ({ page }) => {
  const erros: string[] = [];
  page.on("pageerror", (erro) => erros.push(erro.message));
  await page.goto("/baixa_os");
  await page.getByPlaceholder("ID do item", { exact: true }).first().click();
  const busca = page.getByPlaceholder("Ex: 123 ou descricao do item", { exact: true });
  const resultados: number[][] = [];
  for (const termo of termosEquivalentes) {
    resultados.push(await consultar(page, "busca_item", async () => {
      await busca.fill(termo);
      await busca.press("Enter");
    }));
  }
  expect(resultados[1]).toEqual(resultados[0]);
  expect(resultados[2]).toEqual(resultados[0]);
  await page.getByRole("button", { name: "Fechar", exact: true }).click();
  expect(erros).toEqual([]);
});
