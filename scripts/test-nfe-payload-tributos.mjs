/**
 * Regressao dos tributos do payload da NF-e, sobre o contexto real da OS 288
 * (supabase/tests/fixtures/nfe-contexto-os288.json). Nao chama a SEFAZ nem o banco.
 *
 *   npm run test:nfe-tributos
 *
 * Cobre a cadeia toda numa venda interna para ativo imobilizado: IPI destacado pela
 * TIPI, IPI dentro da base do ICMS, ICMS fora da base de PIS/COFINS, e a base do
 * IBS/CBS sem ICMS, PIS e COFINS — e sem subtrair o IPI, que nunca esteve em vProd.
 * Fecha com a rejeicao 1094: soma dos vItem igual ao vNFTot, os dois com o IPI.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { montarPayloadNfe } from "../supabase/functions/_shared/nfe-payload.ts";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const contextoBase = JSON.parse(
  fs.readFileSync(path.join(raiz, "supabase", "tests", "fixtures", "nfe-contexto-os288.json"), "utf8"),
);

/** Contexto da fixture com o item ja no cadastro fiscal corrigido. */
function contexto(valorUnitario) {
  const ctx = structuredClone(contextoBase);
  const item = ctx.itens[0];
  Object.assign(item.solicitacao_item, {
    ncm: "85371020",
    cst_ipi: "50",
    aliquota_ipi: 9.75,
    ipi_tipi_aliquota: 9.75,
    valor_unitario: valorUnitario,
  });
  item.documento_item.valor_unitario = valorUnitario;
  return ctx;
}

const cenarios = [
  {
    // Decisao de Gabriel em 09/09/2026: absorver o IPI para o total bater com o pedido
    // da Portobello. 8.200,46 e o unico vProd que fecha em 9.000,00 cravado — 8.200,45
    // da 8.999,99 e 8.200,47 da 9.000,02.
    nome: "B · IPI absorvido, total igual ao pedido (9.000,00)",
    valorUnitario: 8200.46,
    esperado: {
      vProd: 8200.46, vIPI: 799.54,
      bcICMS: 9000.00, vICMS: 1530.00,
      bcPisCofins: 6670.46, vPIS: 110.06, vCOFINS: 506.95,
      bcIbsCbs: 6053.45, vIBS: 6.05, vCBS: 54.48,
      vNF: 9000.00, vNFTot: 9000.00, vItem: 9000.00,
    },
  },
  {
    // Cenario A: o IPI somado por fora, como era antes da decisao de absorver.
    // Fica como segundo caso para a cadeia continuar coberta nos dois arranjos.
    nome: "A · IPI por fora do preco (9.877,50)",
    valorUnitario: 9000.00,
    esperado: {
      vProd: 9000.00, vIPI: 877.50,
      bcICMS: 9877.50, vICMS: 1679.18,
      bcPisCofins: 7320.82, vPIS: 120.79, vCOFINS: 556.38,
      bcIbsCbs: 6643.65, vIBS: 6.64, vCBS: 59.79,
      vNF: 9877.50, vNFTot: 9877.50, vItem: 9877.50,
    },
  },
];

let falhas = 0;
for (const cenario of cenarios) {
  const payload = montarPayloadNfe(contexto(cenario.valorUnitario));
  const item = payload.items[0];
  const obtido = {
    vProd: item.valor_bruto,
    vIPI: item.ipi_valor,
    bcICMS: item.icms_base_calculo,
    vICMS: item.icms_valor,
    bcPisCofins: item.pis_base_calculo,
    vPIS: item.pis_valor,
    vCOFINS: item.cofins_valor,
    bcIbsCbs: item.ibs_cbs_base_calculo,
    vIBS: item.ibs_valor_total,
    vCBS: item.cbs_valor,
    vNF: payload.valor_total,
    vNFTot: payload.ibs_cbs_is_valor_total,
    vItem: item.valor_total_item,
  };
  console.log(`\n${cenario.nome}`);
  for (const [campo, valor] of Object.entries(cenario.esperado)) {
    const bate = Math.abs(valor - obtido[campo]) < 0.005;
    if (!bate) falhas += 1;
    console.log(`  ${bate ? "ok   " : "FALHA"} ${campo.padEnd(12)} ${String(obtido[campo]).padStart(9)}${bate ? "" : `  (esperado ${valor})`}`);
  }
  // Rejeicao 1094: o vNFTot e a soma dos vItem. Com um item so a conta e a mesma do
  // campo acima, mas a asserçao e sobre a soma de propósito — foi ela que faltou quando
  // o IPI entrou no total e nao no item (NF-e 2/35, homologacao da OS 287).
  const somaItens = payload.items.reduce((soma, linha) => soma + linha.valor_total_item, 0);
  const somaBate = Math.abs(somaItens - payload.ibs_cbs_is_valor_total) < 0.005;
  if (!somaBate) falhas += 1;
  console.log(`  ${somaBate ? "ok   " : "FALHA"} ${"soma vItem".padEnd(12)} ${somaItens.toFixed(2).padStart(9)}${somaBate ? " = vNFTot" : `  (esperado vNFTot ${payload.ibs_cbs_is_valor_total})`}`);
  // A operacao nao muda com o arranjo do preco: painel montado no galpao e
  // industrializacao (RIPI art. 4o, III), e imobilizado nao alcanca os 12% da
  // Lei SC 17.878/2019 (Lei 10.297/96 art. 19, §3o, II; Consulta SEF/SC 057/20).
  for (const [campo, valor] of [["cfop", "5101"], ["icms_situacao_tributaria", "00"], ["codigo_ncm", "85371020"]]) {
    const bate = item[campo] === valor;
    if (!bate) falhas += 1;
    console.log(`  ${bate ? "ok   " : "FALHA"} ${campo.padEnd(12)} ${String(item[campo]).padStart(9)}${bate ? "" : `  (esperado ${valor})`}`);
  }
  if (Math.abs(item.icms_aliquota - 17) > 0.001) {
    falhas += 1;
    console.log(`  FALHA aliquota ICMS ${item.icms_aliquota} (esperado 17 — imobilizado nao pega os 12%)`);
  }
}

// "Valor aproximado dos tributos" (Lei 12.741/2012), so na revenda: mesma frase e
// mesma conta (ICMS + IPI da nota) do emissor antigo, pedido do Gabriel em 10/09/2026
// — conferido contra 20 notas reais dele (ver comentario em nfe-payload.ts). Reusa o
// cenario A (IPI por fora), so trocando a natureza e o CFOP do item para revenda.
{
  const ctx = contexto(9000.00);
  ctx.solicitacao.operacao_snapshot.natureza_operacao = "VENDA_MERCADORIA_TERCEIROS";
  ctx.itens[0].solicitacao_item.cfop = "5102";
  ctx.itens[0].documento_item.cfop = "5102";
  const payload = montarPayloadNfe(ctx);
  const infCpl = String(payload.informacoes_adicionais_contribuinte ?? "");
  const esperadoTexto = "Valor aproximado dos tributos: 2556,68.";
  const bate = infCpl.startsWith(esperadoTexto);
  if (!bate) falhas += 1;
  console.log(`\nC · Revenda (5102) — texto no infCpl`);
  console.log(`  ${bate ? "ok   " : "FALHA"} ${"infCpl".padEnd(12)} ${JSON.stringify(infCpl.slice(0, 60))}${bate ? "" : `  (esperado iniciar com ${JSON.stringify(esperadoTexto)})`}`);
}

console.log(falhas === 0 ? "\nTributos da NF-e: todos os cenarios passaram." : `\nTributos da NF-e: ${falhas} divergencia(s).`);
process.exit(falhas === 0 ? 0 : 1);
