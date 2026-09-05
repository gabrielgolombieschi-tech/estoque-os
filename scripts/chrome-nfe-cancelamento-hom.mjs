/**
 * Bateria de cancelamento em HOMOLOGACAO, pela tela NF-e -> Ciclo de vida.
 * ESCREVE NA FOCUS/SEFAZ DE HOMOLOGACAO. Ver docs/faturamento/bateria-homologacao-cancelamento.md.
 *
 *   node scripts/chrome-nfe-cancelamento-hom.mjs dentro <documento_fiscal_id>
 *   node scripts/chrome-nfe-cancelamento-hom.mjs fora   <documento_fiscal_id>
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const cenario = process.argv[2];
const documentoId = process.argv[3];
if (!["dentro", "fora"].includes(cenario ?? "") || !documentoId) {
  console.error("Uso: node scripts/chrome-nfe-cancelamento-hom.mjs <dentro|fora> <documento_fiscal_id>");
  process.exit(1);
}
const saida = path.join(raiz, "tests", "e2e", ".saida", "cancelamento");
fs.mkdirSync(saida, { recursive: true });

const { pagina, encerrar } = await conectar();
let passo = 0;
async function captura(nome) {
  passo += 1;
  await pagina.screenshot({ path: path.join(saida, `${cenario}-${String(passo).padStart(2, "0")}-${nome}.png`), fullPage: true });
}

await pagina.goto(new URL(`/faturamento/nfe/${documentoId}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await garantirSessao(pagina);
await pagina.waitForTimeout(5000);
await captura("detalhe");

const cartao = pagina.getByText("Ciclo de vida da NF-e").first();
if ((await cartao.count()) === 0) {
  console.log("Cartão de ciclo de vida não apareceu. Botões visíveis:");
  for (const botao of await pagina.locator("button:visible").all()) {
    console.log("  -", (await botao.textContent())?.replace(/\s+/g, " ").trim().slice(0, 80));
  }
  await encerrar();
  process.exit(2);
}

async function historico() {
  const linhas = (await pagina.locator("li").allTextContents())
    .map((t) => t.replace(/\s+/g, " ").trim())
    .filter((t) => /CANCELAMENTO|AUTORIZACAO|ENVIO|REJEITADA|AUTORIZADA/.test(t));
  return linhas.slice(0, 12);
}

async function avisos() {
  return [...new Set((await pagina.locator('[role="alert"], [role="status"], .text-rose-200, .text-emerald-300, .text-amber-200').allTextContents())
    .map((t) => t.replace(/\s+/g, " ").trim())
    .filter(Boolean))].slice(0, 12);
}

console.log("Antes:", await avisos());

if (cenario === "dentro") {
  const botao = pagina.getByRole("button", { name: "Cancelar homologação na SEFAZ" });
  if ((await botao.count()) === 0) {
    console.log("Botão de cancelamento dentro do prazo não está disponível nesta nota.");
    console.log("Avisos:", await avisos());
    await encerrar();
    process.exit(3);
  }
  await pagina.getByPlaceholder("Justificativa (15 a 255 caracteres)").fill(
    "Cenario CAN-HOM-01: cancelamento dentro do prazo em homologacao, sem valor fiscal.",
  );
  await captura("justificativa");
  await botao.click();
} else {
  const botao = pagina.getByRole("button", { name: "Testar rejeição fora do prazo (homologação)" });
  if ((await botao.count()) === 0) {
    console.log("Botão de teste fora do prazo não está disponível nesta nota.");
    console.log("Avisos:", await avisos());
    await encerrar();
    process.exit(3);
  }
  await captura("antes-fora-prazo");
  await botao.click();
}

await pagina.waitForTimeout(15_000);
await captura("resposta");
console.log("Depois:", await avisos());
await pagina.reload({ waitUntil: "domcontentloaded" });
await pagina.waitForTimeout(5000);
await captura("recarregado");
console.log("Histórico:", await historico());
console.log("Capturas em:", saida);
await encerrar();
