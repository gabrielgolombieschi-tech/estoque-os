import { test, expect, type Page } from "@playwright/test";

// Somente leituras reais: o fechamento é interceptado antes de chegar ao banco.
// O erro simulado também verifica que uma falha não apaga o formulário.
async function prepararFechamento(page: Page, detalhe = false) {
  const envios: Record<string, unknown>[] = [];
  const erros: string[] = [];
  page.on("pageerror", (error) => erros.push(error.message));
  await page.route("**/rest/v1/rpc/fn_orcamento_atualizar_status*", async (route) => {
    envios.push(route.request().postDataJSON());
    await route.fulfill({
      status: 400,
      json: { code: "P0001", message: "Teste: fechamento interceptado, nenhum dado gravado." },
    });
  });
  await page.route("**/rest/v1/orcamento?**", async (route) => {
    const url = new URL(route.request().url());
    if (route.request().method() === "GET" && url.searchParams.get("select") === "pedido_compra_cliente,os_id") {
      expect(url.searchParams.get("tenant_id")).toMatch(/^eq\./);
      expect(url.searchParams.get("empresa_id")).toMatch(/^eq\./);
      await route.fulfill({ json: { pedido_compra_cliente: null, os_id: null } });
    } else await route.continue();
  });
  await page.goto("/comercial/orcamentos");
  await page.getByRole("button", { name: "Lista", exact: true }).click();
  await expect(page.getByRole("button", { name: "Fechado", exact: true }).first()).toBeEnabled();
  if (detalhe) {
    await page.locator("tbody tr").first().getByRole("link").first().click();
    await expect(page).toHaveURL(/\/comercial\/orcamentos\/[^/?]+/);
    await expect(page.getByRole("heading", { name: "Orcamento", exact: true })).toBeVisible();
    await expect(page.getByLabel("Titulo", { exact: true })).toBeVisible();
  }
  await page.getByRole("button", { name: "Fechado", exact: true }).first().click();
  const modal = page.getByRole("dialog", { name: "Marcar como Fechado" });
  await expect(modal).toBeVisible();
  return { modal, envios, erros };
}

for (const detalhe of [false, true]) {
  test(`fechamento preserva o formulário e permite preencher o pedido: ${detalhe ? "detalhe" : "lista"}`, async ({ page }, testInfo) => {
    const { modal, envios, erros } = await prepararFechamento(page, detalhe);
    const followup = modal.getByRole("textbox", { name: /^Followup/ });
    const valor = modal.getByLabel("Valor fechado", { exact: true });
    const pedido = modal.getByRole("textbox", { name: /^Pedido de compra do cliente/ });
    const gerar = modal.getByRole("checkbox", { name: "Gerar documento ao fechar", exact: true });
    const importar = modal.getByRole("checkbox", { name: "Importar os itens para o documento", exact: true });
    const documento = modal.getByRole("button", { name: detalhe ? /^Material · OV/ : /^Projeto · OS/ });

    await followup.fill("Pedido recebido, aguardando material");
    await valor.fill("1.234,56");
    await pedido.fill(detalhe ? "   " : "");
    await gerar.check();
    await documento.click();
    await importar.check();

    await page.mouse.click(2, 2);
    await expect(modal).toBeVisible();
    const area = await followup.boundingBox();
    expect(area).not.toBeNull();
    await page.mouse.move(area!.x + 15, area!.y + 15);
    await page.mouse.down();
    await page.mouse.move(2, 2);
    await page.mouse.up();
    await page.keyboard.press("Escape");
    await expect(modal).toBeVisible();
    await expect(followup).toHaveValue("Pedido recebido, aguardando material");
    await expect(valor).toHaveValue("1.234,56");
    await expect(importar).toBeChecked();

    await modal.getByRole("button", { name: "Salvar", exact: true }).click();
    const aviso = modal.getByRole("alert");
    await expect(aviso).toContainText("Realmente não tem pedido?");
    if (detalhe) await modal.screenshot({ path: testInfo.outputPath("confirmacao-sem-pedido.png") });
    expect(envios).toHaveLength(0);
    await page.mouse.click(2, 2);
    await page.keyboard.press("Escape");
    await expect(aviso).toBeVisible();
    await modal.getByRole("button", { name: "Voltar e preencher", exact: true }).click();
    await expect(aviso).toBeHidden();
    await expect(pedido).toBeFocused();
    await expect(pedido).toHaveValue(detalhe ? "   " : "");
    await expect(followup).toHaveValue("Pedido recebido, aguardando material");
    await expect(valor).toHaveValue("1.234,56");
    await expect(gerar).toBeChecked();
    await expect(importar).toBeChecked();
    await expect(documento).toHaveAttribute("aria-pressed", "true");

    await pedido.fill("  PC-PREENCHIDO/026  ");
    await modal.getByRole("button", { name: "Salvar", exact: true }).click();
    await expect.poll(() => envios.length).toBe(1);
    expect(envios[0]).toMatchObject({
      p_pedido_compra_cliente: "PC-PREENCHIDO/026",
      p_status: "FECHADO",
      p_followup: "Pedido recebido, aguardando material",
      p_valor_fechado: 1234.56,
      p_abrir_os: true,
      p_importar_itens_os: true,
      p_tipo_documento: detalhe ? "OV" : "OS",
    });
    expect(envios[0].p_tenant_id).toBeTruthy();
    expect(envios[0].p_empresa_id).toBeTruthy();
    await expect(modal.getByRole("button", { name: "Salvar", exact: true })).toBeEnabled();
    await expect(aviso).toBeHidden();
    await expect(pedido).toHaveValue("  PC-PREENCHIDO/026  ");
    await expect(followup).toHaveValue("Pedido recebido, aguardando material");
    await modal.getByRole("button", { name: "Cancelar", exact: true }).click();
    await expect(modal).toBeHidden();
    expect(erros).toEqual([]);
  });
}

test("fechamento sem pedido exige confirmação a cada tentativa e preserva os dados na falha", async ({ page }) => {
  const { modal, envios, erros } = await prepararFechamento(page);
  const followup = modal.getByRole("textbox", { name: /^Followup/ });
  const pedido = modal.getByRole("textbox", { name: /^Pedido de compra do cliente/ });
  await followup.fill("Cliente confirmou que não emite pedido");
  await pedido.fill("   ");
  await modal.getByRole("checkbox", { name: "Gerar documento ao fechar", exact: true }).uncheck();

  for (let tentativa = 1; tentativa <= 2; tentativa++) {
    await modal.getByRole("button", { name: "Salvar", exact: true }).click();
    await expect(modal.getByRole("alert")).toContainText("Realmente não tem pedido?");
    expect(envios).toHaveLength(tentativa - 1);
    await modal.getByRole("button", { name: "Confirmar sem pedido", exact: true }).click();
    await expect.poll(() => envios.length).toBe(tentativa);
    expect(envios[tentativa - 1]).toMatchObject({
      p_pedido_compra_cliente: null,
      p_status: "FECHADO",
      p_abrir_os: false,
      p_tipo_documento: null,
    });
    await expect(modal.getByRole("button", { name: "Salvar", exact: true })).toBeEnabled();
    await expect(pedido).toHaveValue("   ");
    await expect(followup).toHaveValue("Cliente confirmou que não emite pedido");
  }
  await modal.getByRole("button", { name: "Cancelar", exact: true }).click();
  await expect(modal).toBeHidden();
  expect(erros).toEqual([]);
});

test("validação do followup antecede o aviso de pedido e outros status não pedem confirmação", async ({ page }) => {
  const { modal, envios, erros } = await prepararFechamento(page);
  await modal.getByRole("textbox", { name: /^Followup/ }).fill("");
  await modal.getByRole("button", { name: "Salvar", exact: true }).click();
  await expect(modal.getByText("Followup obrigatorio (minimo de 5 caracteres).", { exact: true })).toBeVisible();
  await expect(modal.getByText("Realmente não tem pedido?", { exact: true })).toBeHidden();
  expect(envios).toHaveLength(0);
  await modal.getByRole("button", { name: "Cancelar", exact: true }).click();

  await page.getByRole("button", { name: "Perdido", exact: true }).first().click();
  const perdido = page.getByRole("dialog", { name: "Marcar como Perdido" });
  await perdido.getByRole("combobox", { name: /^Motivo da perda/ }).selectOption("Prazo de entrega nao atendeu");
  await page.mouse.click(2, 2);
  await expect(perdido).toBeVisible();
  await perdido.getByRole("button", { name: "Salvar", exact: true }).click();
  await expect.poll(() => envios.length).toBe(1);
  expect(envios[0].p_status).toBe("PERDIDO");
  await expect(perdido.getByText("Realmente não tem pedido?", { exact: true })).toBeHidden();
  await expect(perdido.getByRole("button", { name: "Salvar", exact: true })).toBeEnabled();
  await perdido.getByRole("button", { name: "Cancelar", exact: true }).click();
  expect(erros).toEqual([]);
});
