/**
 * Roda o processo ate a emissao, capturando cada etapa para inspecao visual.
 * Nao abandona no final: deixa a nota na tela para ver o resultado.
 *
 *   node scripts/chrome-nfe-mostrar.mjs 344
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const ovId = process.argv[2] ?? "344";
const saida = path.join(raiz, "tests", "e2e", ".saida", "mostrar");
fs.rmSync(saida, { recursive: true, force: true });
fs.mkdirSync(saida, { recursive: true });

let n = 0;
const { pagina, encerrar } = await conectar();
async function foto(nome) {
  n += 1;
  const arquivo = path.join(saida, `${String(n).padStart(2, "0")}-${nome}.png`);
  // fullPage numa OV com dezenas de notas de teste estoura o timeout e derruba
  // a execucao inteira por causa de uma captura. Tenta a pagina toda e, se
  // demorar, cai para o visivel — a captura e diagnostico, nao o teste.
  try {
    await pagina.screenshot({ path: arquivo, fullPage: true, timeout: 60_000 });
  } catch {
    await pagina.screenshot({ path: arquivo, timeout: 20_000 });
    console.log("   (captura só do visível: página longa demais)");
  }
  console.log("   foto:", path.basename(arquivo));
}

await pagina.goto(new URL(`/comercial/vendas/${ovId}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await garantirSessao(pagina);
await pagina.waitForTimeout(3500);

console.log("[1] Faturar -> salvar rascunho");
await pagina.getByRole("button", { name: "Faturar", exact: true }).first().click();
await pagina.locator('[role="dialog"]').waitFor({ state: "visible", timeout: 20_000 });
await foto("modal-faturar");
await pagina.getByRole("button", { name: "Salvar rascunho da NF-e" }).click();
await pagina.waitForTimeout(6000);

console.log("[2] abrindo a conferência");
await pagina.getByRole("button", { name: /^Faturamento \(/ }).click();
await pagina.waitForTimeout(2500);
await pagina.getByRole("button", { name: /^Conferir e emitir em homologação$/ }).first().click();
await pagina.waitForTimeout(4000);

const conf = pagina.locator("div.fixed.inset-0").filter({ has: pagina.locator("button") }).last();
await foto("etapa1-destino-pre-selecionado");

const sugestao = conf.getByText(/Sugerido .* a partir do cadastro/);
console.log("   sugestão de destino:", (await sugestao.count()) > 0
  ? (await sugestao.textContent())?.replace(/\s+/g, " ").trim()
  : "(não apareceu)");

const continuar = conf.getByRole("button", { name: /^Continuar para conferência fiscal/ });
console.log("   'Continuar' antes da destinação (deve travar):", await continuar.isEnabled());

// Destinacao decide a aliquota interna (12% x 17%) e nao vem da memoria de
// proposito: o cliente recusa a nota se divergir da utilizacao da OC dele.
const destinacao = process.env.DESTINACAO ?? "REVENDA";
await conf.getByLabel("Destinação da mercadoria").selectOption(destinacao);
console.log("   destinação escolhida:", destinacao);
console.log("   'Continuar' habilitado:", await continuar.isEnabled());
await continuar.click();
await pagina.waitForTimeout(6000);
await foto("etapa2-fiscal");

// Pagamento: enquanto nao houver nota anterior com a forma gravada, a memoria
// nao tem o que herdar e a conferencia precisa da escolha explicita.
const formaPagamento = conf.getByLabel("Forma de pagamento");
if ((await formaPagamento.inputValue()) === "") {
  await formaPagamento.selectOption("15");
  await conf.getByLabel("Indicador de pagamento").selectOption("1");
  console.log("   pagamento: escolhido 15 · Boleto bancário, a prazo");
} else {
  console.log("   pagamento herdado:", await formaPagamento.inputValue());
}

const memoria = conf.getByText(/Da última nota conferida desta OV/);
console.log("   memória:", (await memoria.count()) > 0
  ? (await memoria.textContent())?.replace(/\s+/g, " ").trim()
  : "(não apareceu)");

// Inclui "Complete os campos obrigatórios": quando a nota esta bloqueada e esse
// o rotulo do botao, e esperar so pelos dois rotulos de emissao dava timeout de
// 30s sem dizer o motivo real.
const emitir = conf.getByRole("button", { name: /^(Emitir em homologação|Tentar emitir novamente|Complete os campos obrigatórios)/ });
const rotuloEmitir = (await emitir.textContent())?.trim() ?? "";
console.log("   botão de emissão:", rotuloEmitir, "| habilitado:", await emitir.isEnabled());
if (rotuloEmitir.startsWith("Complete")) {
  const faltando = await conf.locator("li").allTextContents();
  console.log("   BLOQUEADA — pendências:", faltando.map((t) => t.replace(/\s+/g, " ").trim()).filter(Boolean).join(" · ") || "(a tela não listou)");
  await foto("bloqueada");
  await encerrar();
  process.exit(1);
}
await foto("etapa2-pronto");

console.log("[3] emitindo");
await emitir.click();
await pagina.waitForTimeout(14_000);
await foto("pos-emissao");

const mensagens = await pagina.locator('[role="alert"], [role="status"]').allTextContents();
for (const m of mensagens) {
  const t = m.replace(/\s+/g, " ").trim();
  if (t && !t.startsWith("OV-")) console.log("   tela:", t.slice(0, 200));
}

await pagina.goto(new URL(`/comercial/vendas/${ovId}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
await pagina.waitForTimeout(4000);
await pagina.getByRole("button", { name: /^Faturamento \(/ }).click();
await pagina.waitForTimeout(4000);
await foto("resultado-final");

console.log("\ncapturas em:", saida);
await encerrar();
