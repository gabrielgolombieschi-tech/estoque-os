/**
 * Registra a revisao fiscal de perfis NF-e pela tela /faturamento/perfis.
 * ESCREVE NO BANCO (f.perfil_operacao + evento de revisao), como o usuario logado.
 *
 *   node scripts/chrome-perfis-revisar.mjs SEG-VENDA-TERCEIROS-SC-5102-O2-CST00 [outros codigos...]
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const codigos = process.argv.slice(2);
if (codigos.length === 0) {
  console.error("Informe ao menos um codigo de perfil.");
  process.exit(1);
}
const saida = path.join(raiz, "tests", "e2e", ".saida", "perfis");
fs.mkdirSync(saida, { recursive: true });

// Aprovado em 03/09/2026 como regra legal (ADCT art. 125; LC 214/2025) para
// VENDA_MERCADORIA_TERCEIROS / CFOP 5102 no exercicio de 2026.
const IBS_CBS = {
  cst: "000",
  cclass: "000001",
  versao: "Transicao 2026 - ADCT art. 125 e LC 214/2025 (leiaute NT 2025.002)",
  ibsUf: "0.10",
  ibsMun: "0",
  cbs: "0.90",
};

function justificativa(codigo) {
  const dezessete = codigo.endsWith("-17");
  return [
    "Revisao fiscal de 05/09/2026 com base no documento da Status Contabilidade (24/11/2021), no e-mail de cBenef obrigatorio e na carta da Portobello.",
    "CFOP 5102, CST ICMS 00, base integral, sem beneficio: o NCM 8537.10.20 nao esta no Anexo 2, art. 7, VII do RICMS/SC.",
    dezessete
      ? "Aliquota interna de 17% para uso e consumo ou ativo imobilizado do adquirente (RICMS/SC, art. 26, I)."
      : "Aliquota interna de 12% para destinatario contribuinte que revende, industrializa, usa como insumo, manutencao ou consignado (Lei 10.297/96, art. 19, III, n; Lei 17.878/2019). Manutencao a 12% confirmada pelo responsavel em 05/09/2026.",
    "PIS 1,65% e COFINS 7,6%, CST 01, Lucro Real. IPI CST 53 com cEnq 999 para revenda.",
    "IBS/CBS 2026: CST 000, cClassTrib 000001, IBS UF 0,10%, IBS municipal 0%, CBS 0,90% (ADCT art. 125; LC 214/2025, art. 348).",
  ].join(" ");
}

const { pagina, encerrar } = await conectar();

for (const codigo of codigos) {
  console.log(`\n== ${codigo}`);
  await pagina.goto(new URL("/faturamento/perfis", baseURL).toString(), { waitUntil: "domcontentloaded" });
  await garantirSessao(pagina);
  await pagina.waitForTimeout(4000);

  await pagina.getByLabel("Buscar perfil fiscal").fill(codigo);
  await pagina.waitForTimeout(1500);
  const cartao = pagina.getByRole("button").filter({ hasText: codigo }).first();
  if ((await cartao.count()) === 0) {
    console.log("   perfil nao encontrado na lista");
    continue;
  }
  await cartao.click();
  await pagina.waitForTimeout(2500);

  await pagina.locator("#cst-ibs-cbs").fill(IBS_CBS.cst);
  await pagina.locator("#cclass-trib").fill(IBS_CBS.cclass);
  await pagina.locator("#cclass-versao").fill(IBS_CBS.versao);
  await pagina.locator("#ibs-uf").fill(IBS_CBS.ibsUf);
  await pagina.locator("#ibs-municipal").fill(IBS_CBS.ibsMun);
  await pagina.locator("#cbs").fill(IBS_CBS.cbs);
  await pagina.locator("#justificativa-revisao").fill(justificativa(codigo));
  await pagina.screenshot({ path: path.join(saida, `${codigo}-01-preenchido.png`), timeout: 8000 }).catch(() => {});

  const salvar = pagina.getByRole("button", { name: /Salvar revisao/ });
  if (!(await salvar.isEnabled())) {
    console.log("   botao de salvar desabilitado");
    continue;
  }
  await salvar.click();
  await pagina.waitForTimeout(6000);
  await pagina.screenshot({ path: path.join(saida, `${codigo}-02-resposta.png`), timeout: 8000 }).catch(() => {});
  const avisos = [...new Set((await pagina.locator('[role="alert"], [role="status"], .text-emerald-300, .text-rose-200, .text-rose-300, .text-emerald-200').allTextContents())
    .map((t) => t.replace(/\s+/g, " ").trim()).filter(Boolean))];
  console.log("   retorno:", avisos.join(" | ").slice(0, 400));
}

console.log("\nCapturas em:", saida);
await encerrar();
