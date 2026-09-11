import { test, expect } from "@playwright/test";

// Leituras reais; toda confirmação é interceptada antes de chegar ao banco.
// Nenhum orçamento é fechado e nenhuma OS/OV é criada por estes testes.
for (const cenario of ["OV", "OS", "SEM_DOCUMENTO", "DETALHE"] as const) {
  test(`pedido do cliente no fechamento: ${cenario}`, async ({ page }, testInfo) => {
    const erros: string[] = [];
    const envios: Record<string, unknown>[] = [];
    page.on("pageerror", (error) => erros.push(error.message));
    await page.route("**/rest/v1/rpc/fn_orcamento_atualizar_status*", async (route) => {
      expect(route.request().url()).toContain("fn_orcamento_atualizar_status_com_pedido");
      envios.push(route.request().postDataJSON());
      await route.fulfill({ status: 400, json: { code: "P0001", message: "Teste: fechamento interceptado, nenhum dado gravado." } });
    });
    // Exercita carregamento de pedido preexistente sem inserir fixture remota.
    await page.route("**/rest/v1/orcamento?**", async (route) => {
      const url = new URL(route.request().url());
      if (route.request().method() === "GET" && url.searchParams.get("select") === "pedido_compra_cliente,os_id") {
        expect(url.searchParams.get("tenant_id")).toMatch(/^eq\./);
        expect(url.searchParams.get("empresa_id")).toMatch(/^eq\./);
        await route.fulfill({ json: { pedido_compra_cliente: "PC-ANTERIOR/001", os_id: null } });
      } else await route.continue();
    });

    await page.goto("/comercial/orcamentos");
    await page.getByRole("button", { name: "Lista", exact: true }).click();
    await expect(page.getByRole("button", { name: "Fechado", exact: true }).first()).toBeEnabled();
    if (cenario === "DETALHE") {
      const codigo = await page.locator("tbody tr").first().locator("td").first().innerText();
      await page.goto(`/comercial/orcamentos/${encodeURIComponent(codigo.trim())}`);
    }
    await page.getByRole("button", { name: "Fechado", exact: true }).first().click();
    const modal = page.getByRole("dialog", { name: "Marcar como Fechado" });
    const pedido = modal.getByRole("textbox", { name: /^Pedido de compra do cliente/ });
    await expect(pedido).toHaveValue("PC-ANTERIOR/001");
    await pedido.fill("  PC-000123/26  ");
    await modal.getByLabel("Followup", { exact: true }).fill("Pedido recebido");
    const gerar = modal.getByRole("checkbox", { name: "Gerar documento ao fechar", exact: true });
    if (cenario === "SEM_DOCUMENTO" || cenario === "DETALHE") await gerar.uncheck();
    else {
      await gerar.check();
      await modal.getByRole("button", { name: cenario === "OS" ? /^Projeto · OS/ : /^Material · OV/ }).click();
    }
    await expect(pedido).toBeVisible();
    await modal.screenshot({ path: testInfo.outputPath("pedido-cliente.png") });
    await modal.getByRole("button", { name: "Salvar", exact: true }).click();
    await expect.poll(() => envios.length).toBe(1);
    expect(envios[0].p_pedido_compra_cliente).toBe("PC-000123/26");
    expect(envios[0].p_tenant_id).toBeTruthy();
    expect(envios[0].p_empresa_id).toBeTruthy();
    expect(envios[0].p_status).toBe("FECHADO");
    expect(envios[0].p_importar_itens_os).toBe(false);
    expect(envios[0].p_tipo_documento).toBe(cenario === "OS" || cenario === "OV" ? cenario : null);
    expect(envios[0].p_abrir_os).toBe(cenario === "OS" || cenario === "OV");
    await expect(modal.getByRole("button", { name: "Salvar", exact: true })).toBeEnabled();
    // Falha mantém o formulário e o pedido, permitindo nova tentativa.
    await expect(pedido).toHaveValue("  PC-000123/26  ");
    await modal.getByRole("button", { name: "Cancelar", exact: true }).click();
    await expect(modal).toBeHidden();
    await page.getByRole("button", { name: "Perdido", exact: true }).first().click();
    await expect(page.getByRole("dialog").getByRole("textbox", { name: /^Pedido de compra/ })).toHaveCount(0);
    expect(erros).toEqual([]);
  });
}
