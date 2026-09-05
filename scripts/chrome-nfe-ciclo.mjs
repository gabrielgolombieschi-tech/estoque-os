/**
 * Ciclo completo de NF-e em homologacao numa OV, em tela:
 *   Faturar -> salvar rascunho -> conferir -> emitir -> abandonar -> repetir.
 * Registra cada trava encontrada. ESCREVE NO BANCO.
 *
 *   node scripts/chrome-nfe-ciclo.mjs 344 2
 *   node scripts/chrome-nfe-ciclo.mjs 344 2 --transportadora
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { conectar, garantirSessao, baseURL } from "./chrome.mjs";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const ovId = process.argv[2] ?? "344";
const voltas = Number(process.argv[3] ?? 1);
const COM_TRANSPORTADORA = process.argv.includes("--transportadora");
const saida = path.join(raiz, "tests", "e2e", ".saida", "ciclo");
fs.mkdirSync(saida, { recursive: true });

const dificuldades = [];
let passo = 0;

const { pagina, encerrar } = await conectar();

async function captura(nome) {
  passo += 1;
  await pagina.screenshot({
    path: path.join(saida, `${String(passo).padStart(2, "0")}-${nome}.png`),
    fullPage: true,
  });
}

function anota(volta, texto) {
  dificuldades.push(`volta ${volta}: ${texto}`);
  console.log(`   !! ${texto}`);
}

async function progresso() {
  const linha = (await pagina.locator("table").first().locator("tbody tr").first().textContent())
    ?.replace(/\s+/g, " ")
    .trim();
  const faturar = pagina.getByRole("button", { name: "Faturar", exact: true });
  const on = (await faturar.count()) > 0 ? await faturar.isEnabled() : null;
  return { linha, faturar: on };
}

async function irParaOv() {
  await pagina.goto(new URL(`/comercial/vendas/${ovId}`, baseURL).toString(), { waitUntil: "domcontentloaded" });
  await garantirSessao(pagina);
  await pagina.waitForTimeout(3500);
}

async function abaFaturamento() {
  await pagina.getByRole("button", { name: /^Faturamento \(/ }).click().catch(() => {});
  await pagina.waitForTimeout(2500);
}

const respostas = COM_TRANSPORTADORA
  ? [
      ["select", "Presença do comprador", "0"],
      ["select", "Modalidade do frete", "1"],
      ["texto", "Frete", "0"],
      ["texto", "Seguro", "0"],
      ["texto", "Outras despesas", "0"],
      ["texto", "Transportadora", "TEDE TRANSPORTES LTDA"],
      ["texto", "CNPJ/CPF transportadora", "02.484.555/0010-72"],
      ["texto", "Endereço transportadora", "R GUSTAVO HENSCHEL"],
      ["texto", "Município transportadora", "BLUMENAU"],
      ["texto", "UF transportadora", "SC"],
      ["texto", "Quantidade de volumes", "1"],
      ["texto", "Peso líquido", "0,20"],
      ["texto", "Peso bruto", "0,20"],
    ]
  : [
      ["select", "Presença do comprador", "0"],
      ["select", "Modalidade do frete", "9"],
      ["texto", "Frete", "0"],
      ["texto", "Seguro", "0"],
      ["texto", "Outras despesas", "0"],
    ];

/** Uma passada pela conferencia. Devolve o texto de retorno da tela, ou null. */
async function conferir(volta, rotulo) {
  const conf = pagina.locator("div.fixed.inset-0").filter({ has: pagina.locator("button") }).last();

  // Etapa 1: destino.
  const destinoSC = conf.getByRole("button", { name: /^Dentro de Santa Catarina/ });
  if ((await destinoSC.count()) > 0) {
    await destinoSC.click();
    const continuar = conf.getByRole("button", { name: /^Continuar para conferência fiscal/ });
    if (!(await continuar.isEnabled())) {
      anota(volta, "destino escolhido mas o avanço seguiu desabilitado");
      return "travado no destino";
    }
    await continuar.click();
    await pagina.waitForTimeout(4000);
  }

  // Os campos travados do perfil preenchem de forma assincrona.
  const finalidade = conf.locator("label").filter({ hasText: /^\s*Finalidade/ }).locator("select").first();
  for (let i = 0; i < 30; i += 1) {
    if (((await finalidade.inputValue().catch(() => "")) ?? "") !== "") break;
    await pagina.waitForTimeout(1000);
  }

  async function definir(tipo, rotuloCampo, valor) {
    const alvo = conf.locator("label").filter({ hasText: new RegExp(`^\\s*${rotuloCampo}`) })
      .locator(tipo === "select" ? "select" : "input").first();
    if ((await alvo.count()) === 0) return `campo "${rotuloCampo}" não encontrado`;
    if (!(await alvo.isEnabled())) return null; // travado pelo perfil: já vem pronto
    if (tipo === "select") await alvo.selectOption(valor);
    else await alvo.fill(valor);
    await pagina.waitForTimeout(350);
    return null;
  }

  const falhas = [];
  for (const [tipo, rotuloCampo, valor] of respostas) {
    const erro = await definir(tipo, rotuloCampo, valor);
    if (erro) falhas.push(erro);
  }
  if (falhas.length) anota(volta, `campos da operação: ${falhas.join("; ")}`);

  const banner = conf.getByText(/vieram da última nota desta OV/);
  if ((await banner.count()) > 0) {
    console.log("   memória aplicada:", (await banner.textContent())?.replace(/\s+/g, " ").trim().slice(0, 120));
  }

  await pagina.waitForTimeout(2000);
  // Na retentativa o rótulo muda para "Tentar emitir novamente".
  const emitir = conf.getByRole("button", { name: /^(Emitir em homologação|Tentar emitir novamente)/ });
  if ((await emitir.count()) === 0 || !(await emitir.isEnabled())) {
    const avisos = (await pagina.locator('[role="alert"]').allTextContents())
      .map((a) => a.replace(/\s+/g, " ").trim())
      .filter((a) => a && !a.startsWith("OV-"));
    anota(volta, `emissão não habilitou (${rotulo}): ${avisos.join(" | ").slice(0, 250)}`);
    await captura("emissao-bloqueada");
    return "não habilitou";
  }

  await captura(`pronto-para-emitir-${rotulo}`);
  await emitir.click();
  await pagina.waitForTimeout(12_000);
  await captura(`pos-emissao-${rotulo}`);

  const retorno = (await pagina.locator('[role="alert"], [role="status"]').allTextContents())
    .map((t) => t.replace(/\s+/g, " ").trim())
    .filter((t) => t && !t.startsWith("OV-"));
  if (retorno.length) console.log("   retorno:", [...new Set(retorno)].join(" | ").slice(0, 300));

  // As pendências de cadastro saem numa <ul> sem role — foi o que me escapou antes.
  const pendencias = (await conf.locator("li").allTextContents())
    .map((t) => t.replace(/\s+/g, " ").trim())
    .filter(Boolean);
  if (pendencias.length) {
    anota(volta, `pendências de cadastro barraram o envio: ${pendencias.join(" | ").slice(0, 400)}`);
  }
  return null;
}

for (let volta = 1; volta <= voltas; volta += 1) {
  console.log(`\n================ VOLTA ${volta} ================`);
  await irParaOv();

  const inicio = await progresso();
  console.log("estado inicial:", inicio.linha, "| Faturar:", inicio.faturar);
  if (!inicio.faturar) {
    anota(volta, 'botão "Faturar" desabilitado no início — sem saldo, ciclo não pode começar');
    break;
  }

  // ---- 1. criar o rascunho ----
  console.log("\n[1] Faturar -> salvar rascunho");
  await pagina.getByRole("button", { name: "Faturar", exact: true }).first().click();
  await pagina.locator('[role="dialog"]').waitFor({ state: "visible", timeout: 20_000 });
  const salvar = pagina.getByRole("button", { name: "Salvar rascunho da NF-e" });
  if (!(await salvar.isEnabled())) {
    anota(volta, '"Salvar rascunho da NF-e" veio desabilitado');
    break;
  }
  await salvar.click();
  await pagina.waitForTimeout(6000);
  console.log("   rascunho criado:", (await progresso()).linha);

  // ---- 2. conferir e emitir (pode exigir 2 passadas quando ha transportadora) ----
  console.log("\n[2] Conferir e emitir em homologação");
  await abaFaturamento();
  let emitido = false;
  for (let passada = 1; passada <= 2 && !emitido; passada += 1) {
    const botao = pagina.getByRole("button", { name: /^(Conferir e emitir em homologação|Continuar conferência)$/ }).first();
    if ((await botao.count()) === 0) {
      anota(volta, "nenhum botão de conferência disponível");
      break;
    }
    const nome = (await botao.textContent())?.trim();
    console.log(`   passada ${passada}: "${nome}"`);
    await botao.click();
    await pagina.waitForTimeout(4000);
    const erro = await conferir(volta, `p${passada}`);
    if (erro) break;

    await irParaOv();
    await abaFaturamento();
    if ((await pagina.getByRole("button", { name: "Continuar conferência" }).count()) === 0) {
      emitido = true;
    } else if (passada === 1) {
      anota(volta, 'com transportadora a emissão não completa numa passada só: a tela volta para "Continuar conferência" e exige repetir a conferência');
    }
  }
  if (!emitido) {
    anota(volta, "não consegui concluir a emissão");
    break;
  }

  // ---- 3. esperar autorização ----
  console.log("\n[3] aguardando autorização");
  let autorizada = false;
  for (let espera = 0; espera < 20; espera += 1) {
    await irParaOv();
    await abaFaturamento();
    if ((await pagina.getByText("Autorizada em homologação").count()) > 0) { autorizada = true; break; }
    await pagina.waitForTimeout(5000);
  }
  if (!autorizada) {
    anota(volta, "a NF-e não chegou a AUTORIZADA dentro de ~2 min");
    await captura("sem-autorizacao");
    break;
  }
  console.log("   autorizada");

  // ---- 4. abandonar e devolver saldo ----
  console.log("\n[4] abandonar homologação");
  const abandonar = pagina.getByRole("button", { name: "Abandonar homologação e liberar saldo" });
  if ((await abandonar.count()) === 0) {
    anota(volta, "botão de abandono não apareceu para a nota autorizada");
    break;
  }
  await abandonar.first().click();
  await pagina.locator("textarea").first().fill(`Volta ${volta} do ciclo de teste de NF-e em homologacao`);
  await pagina.getByRole("button", { name: "Abandonar e devolver saldo" }).click();
  await pagina.waitForTimeout(6000);

  const fim = await progresso();
  console.log("estado final:", fim.linha, "| Faturar:", fim.faturar);
  if (!fim.faturar) anota(volta, "saldo não voltou após o abandono");
}

console.log("\n================ DIFICULDADES ================");
if (dificuldades.length === 0) console.log("nenhuma trava encontrada");
else for (const d of dificuldades) console.log(" •", d);
console.log("\ncapturas em:", saida);

await encerrar();
