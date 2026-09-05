/**
 * Carta de correcao eletronica em HOMOLOGACAO, pela tela NF-e -> Ciclo de vida.
 * ESCREVE NA FOCUS/SEFAZ DE HOMOLOGACAO.
 *
 *   node scripts/chrome-nfe-cce-hom.mjs <documento_fiscal_id> "texto da correcao"
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const documentoId = process.argv[2];
const correcao = process.argv[3];
if (!documentoId || !correcao || correcao.length < 15) {
  console.error('Uso: node scripts/chrome-nfe-cce-hom.mjs <documento_fiscal_id> "correcao com 15 a 1000 caracteres"');
  process.exit(1);
}
const saida = path.join(raiz, "tests", "e2e", ".saida", "cce");
fs.mkdirSync(saida, { recursive: true });

const { pagina, encerrar } = await conectar();

await pagina.goto(new URL(`/faturamento/nfe/${documentoId}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await garantirSessao(pagina);
await pagina.waitForTimeout(5000);

const campo = pagina.getByPlaceholder(/Correção completa/);
if ((await campo.count()) === 0) {
  console.log("Campo da CC-e não apareceu nesta nota.");
  await encerrar();
  process.exit(2);
}
await campo.fill(correcao);
const botao = pagina.getByRole("button", { name: "Emitir carta de correção" });
if (!(await botao.isEnabled())) {
  console.log("Botão de CC-e desabilitado (nota não autorizada em homologação?).");
  await encerrar();
  process.exit(3);
}
await pagina.screenshot({ path: path.join(saida, "01-antes.png"), fullPage: true });
await botao.click();
await pagina.waitForTimeout(15_000);
await pagina.screenshot({ path: path.join(saida, "02-resposta.png"), fullPage: true });
const avisos = [...new Set((await pagina.locator('[role="alert"], [role="status"], .text-rose-200, .text-emerald-300').allTextContents())
  .map((t) => t.replace(/\s+/g, " ").trim()).filter(Boolean))];
console.log("Avisos:", avisos);
console.log("Capturas em:", saida);
await encerrar();
