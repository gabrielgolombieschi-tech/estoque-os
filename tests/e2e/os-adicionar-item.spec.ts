import { test, expect, type Page } from "@playwright/test";
import path from "node:path";

const PASTA_PASSOS = path.join(__dirname, ".saida", "passos");
const TERMO_ITEM = process.env.E2E_ITEM_TERM ?? "a";

let passo = 0;
async function registrar(page: Page, nome: string) {
  passo += 1;
  await page.screenshot({
    path: path.join(PASTA_PASSOS, `${String(passo).padStart(2, "0")}-${nome}.png`),
    fullPage: true,
  });
}

/** A seção "Adicionar item" some quando a OS é por HH e aparece travada quando a OS está fechada. */
async function seçãoDeItensUtilizável(page: Page) {
  const aba = page.getByRole("button", { name: "Adicionar item", exact: true });
  if ((await aba.count()) === 0) return false;
  const busca = page.getByLabel("Buscar item", { exact: true });
  if ((await busca.count()) === 0) return false;
  return await busca.isEnabled();
}

test("adicionar item numa OS e remover em seguida", async ({ page }) => {
  test.setTimeout(180_000);

  // ---- 1. lista de OS ----
  // A linha "Carregando..." é um <tr> de uma célula só; as linhas de verdade têm 6 colunas.
  const linhasOs = page.locator("tbody tr:has(td:nth-child(4))");

  async function abrirLista() {
    await page.goto("/os?vista=lista");
    await expect(linhasOs.first()).toBeVisible({ timeout: 60_000 });
  }

  await abrirLista();
  await registrar(page, "lista-os");

  // ---- 2. achar uma OS que aceite itens ----
  const total = Math.min(await linhasOs.count(), 8);
  let urlOs: string | null = null;
  for (let i = 0; i < total; i += 1) {
    if (i > 0) await abrirLista();
    await linhasOs.nth(i).locator("td").nth(1).click();
    await page.waitForURL(/\/os\/\d+/, { timeout: 30_000 });
    await page.waitForLoadState("networkidle");
    if (await seçãoDeItensUtilizável(page)) {
      urlOs = page.url();
      break;
    }
  }
  expect(urlOs, `nenhuma das ${total} primeiras OS tem a seção "Adicionar item" liberada`).toBeTruthy();
  console.log("OS usada no teste:", urlOs);
  await registrar(page, "os-aberta");

  const tabelaItens = page
    .locator("table")
    .filter({ has: page.getByRole("columnheader", { name: "Ações", exact: true }) });
  // A tabela mostra um <tr> de aviso quando está vazia; só as linhas reais têm 4+ colunas.
  const linhasItens = tabelaItens.locator("tbody tr:has(td:nth-child(4))");

  // A 1ª coluna é o ID do item de catálogo, que se repete quando o mesmo item entra
  // duas vezes. Quem identifica a linha é a coluna "Data" (índice 7), com hora e segundo.
  const carimbos = async () =>
    (await linhasItens.evaluateAll((trs) =>
      trs.map((tr) => tr.querySelectorAll("td")[7]?.textContent?.trim() ?? "")
    )).filter(Boolean);

  /** A tabela chega vazia e é preenchida por fetch; só vale ler depois de duas leituras iguais. */
  const carimbosEstaveis = async () => {
    let anterior = await carimbos();
    for (let tentativa = 0; tentativa < 20; tentativa += 1) {
      await page.waitForTimeout(750);
      const atual = await carimbos();
      if (atual.join("|") === anterior.join("|")) return atual;
      anterior = atual;
    }
    return anterior;
  };

  const carimbosAntes = await carimbosEstaveis();

  // ---- 3. buscar item (termo não numérico abre o modal "Localizar item") ----
  await page.getByLabel("Buscar item", { exact: true }).fill(TERMO_ITEM);
  await page.getByRole("button", { name: "Buscar", exact: true }).first().click();

  // Tudo daqui pra frente é escopado ao modal: a página por baixo tem um "Buscar" homônimo.
  const modal = page
    .locator("div.fixed.inset-0")
    .filter({ has: page.getByText("Localizar item", { exact: true }) });
  await expect(modal).toBeVisible({ timeout: 30_000 });
  await modal.getByLabel("Buscar item por nome").fill(TERMO_ITEM);
  await modal.getByRole("button", { name: "Buscar", exact: true }).click();

  const linhasModal = modal.locator("tbody tr:has(td:nth-child(4))");
  await expect(linhasModal.first()).toBeVisible({ timeout: 30_000 });
  await registrar(page, "modal-localizar-item");

  const nomeItem = (await linhasModal.first().locator("td").nth(2).textContent())?.trim() ?? "";
  await linhasModal.first().click();

  // ---- 4. preencher e adicionar ----
  await expect(page.getByText(/^Selecionado:/)).toBeVisible({ timeout: 15_000 });
  await page.getByLabel("Quantidade", { exact: true }).fill("1");

  // Sem baixa direta: o teste não deve mexer no saldo de estoque.
  const baixaDireta = page.getByRole("checkbox", { name: "Baixa direta" });
  if (await baixaDireta.isChecked()) await baixaDireta.uncheck();
  await registrar(page, "item-selecionado");

  const botaoAdicionar = page.getByRole("button", { name: "Adicionar", exact: true });
  await expect(botaoAdicionar).toBeEnabled();
  await botaoAdicionar.click();

  // O carimbo novo é capturado dentro do próprio poll: a tabela re-renderiza, então
  // ler de novo logo depois abriria uma corrida.
  let carimboNovo: string | undefined;
  await expect
    .poll(
      async () => {
        carimboNovo = (await carimbos()).find((c) => !carimbosAntes.includes(c));
        return Boolean(carimboNovo);
      },
      { timeout: 30_000, message: "linha nova na tabela de itens" }
    )
    .toBe(true);
  await registrar(page, "item-adicionado");

  const linhaNova = linhasItens.filter({ has: page.locator(`td:text-is("${carimboNovo}")`) });
  await expect(linhaNova).toHaveCount(1);
  expect(await linhaNova.textContent()).toContain(nomeItem.slice(0, 12));

  // ---- 5. limpeza: remove exatamente a linha que este teste criou ----
  page.once("dialog", (d) => void d.accept());
  await linhaNova.getByRole("button", { name: "Remover" }).click();
  await expect
    .poll(async () => await carimbos(), { timeout: 30_000, message: "linha removida" })
    .toEqual(carimbosAntes);
  await registrar(page, "item-removido");
});
