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

// "Valor aproximado dos tributos" (Lei 12.741/2012) e vTotTrib — regra de 16/09/2026:
// so com indFinal = 1, e o valor e federal + estadual da tabela IBPT por NCM. Com
// indFinal = 0 nao ha frase nem valor_total_tributos; sem tabela vigente para algum NCM
// da nota, tambem nao (nunca uma aliquota inventada, nunca o ICMS + IPI da nota).
//
// As aliquotas abaixo sao FICTICIAS, so para exercitar a conta — nao sao do IBPT.
const IBPT_TESTE = [{
  uf: "SC", codigo: "85371020", ex: "", descricao: "teste",
  nacional_federal_pct: 13.45, importados_federal_pct: 15.45, estadual_pct: 17, municipal_pct: 0,
  vigencia_inicio: "2026-07-01", vigencia_fim: "2026-12-31", versao: "TESTE.1", chave: "TESTE", fonte: "IBPT",
}];
const AGORA = new Date("2026-09-16T15:00:00Z");

function payloadCom({ consumidorFinal, ibpt, origem = 0, natureza, cfop }) {
  const ctx = contexto(9000.00);
  ctx.solicitacao.operacao_snapshot.consumidor_final = consumidorFinal;
  if (natureza) ctx.solicitacao.operacao_snapshot.natureza_operacao = natureza;
  if (cfop) {
    ctx.itens[0].solicitacao_item.cfop = cfop;
    ctx.itens[0].documento_item.cfop = cfop;
  }
  if (origem === 1) {
    // Origem 1 exige a equiparacao a industrial (RIPI art. 9o, I).
    ctx.itens[0].solicitacao_item.origem_mercadoria = 1;
    ctx.itens[0].solicitacao_item.equiparado_industrial = true;
  }
  if (ibpt !== undefined) ctx.ibpt = ibpt;
  return montarPayloadNfe(ctx, AGORA);
}

function confere(nome, condicao, detalhe) {
  if (!condicao) falhas += 1;
  console.log(`  ${condicao ? "ok   " : "FALHA"} ${nome}${condicao ? "" : `  (${detalhe})`}`);
}

function semTributosAproximados(payload) {
  return !/Valor aproximado dos tributos/.test(String(payload.informacoes_adicionais_contribuinte ?? ""))
    && !("valor_total_tributos" in payload)
    && payload.items.every((item) => !("valor_total_tributos" in item));
}

{
  console.log("\nC · indFinal 0 (venda a contribuinte): sem frase e sem vTotTrib, mesmo com tabela");
  const p = payloadCom({ consumidorFinal: 0, ibpt: IBPT_TESTE });
  confere("sem frase, sem valor_total_tributos", semTributosAproximados(p), p.informacoes_adicionais_contribuinte);
}
{
  console.log("\nD · indFinal 1 sem tabela IBPT: sem frase e sem vTotTrib (nada de ICMS + IPI)");
  const p = payloadCom({ consumidorFinal: 1 });
  confere("sem frase, sem valor_total_tributos", semTributosAproximados(p), p.informacoes_adicionais_contribuinte);
}
{
  console.log("\nE · indFinal 1 com tabela vigente, origem nacional: federal + estadual");
  const p = payloadCom({ consumidorFinal: 1, ibpt: IBPT_TESTE });
  // 9.000,00 x 13,45% = 1.210,50 federal; 9.000,00 x 17% = 1.530,00 estadual.
  const frase = "Valor aproximado dos tributos: 2740,50 (federal 1210,50 e estadual 1530,00). Fonte: IBPT TESTE, versão TESTE.1.";
  confere("infCpl abre com a frase", String(p.informacoes_adicionais_contribuinte).startsWith(frase), p.informacoes_adicionais_contribuinte);
  confere("vTotTrib do item 2740,50", p.items[0].valor_total_tributos === 2740.50, p.items[0].valor_total_tributos);
  confere("vTotTrib total 2740,50", p.valor_total_tributos === 2740.50, p.valor_total_tributos);
}
{
  console.log("\nF · indFinal 1 com tabela, origem 1 (estrangeira): coluna de importados");
  const p = payloadCom({ consumidorFinal: 1, ibpt: IBPT_TESTE, origem: 1 });
  // 9.000,00 x 15,45% = 1.390,50 federal; + 1.530,00 estadual.
  confere("vTotTrib total 2920,50", p.valor_total_tributos === 2920.50, p.valor_total_tributos);
}
{
  console.log("\nG · indFinal 1 com tabela vencida na data da emissao: sem frase e sem vTotTrib");
  const vencida = [{ ...IBPT_TESTE[0], vigencia_fim: "2026-09-15" }];
  const p = payloadCom({ consumidorFinal: 1, ibpt: vencida });
  confere("sem frase, sem valor_total_tributos", semTributosAproximados(p), p.informacoes_adicionais_contribuinte);
}
{
  console.log("\nH · as contas de ICMS e IPI nao mudam com a regra dos tributos aproximados");
  const a = payloadCom({ consumidorFinal: 1 });
  const b = payloadCom({ consumidorFinal: 1, ibpt: IBPT_TESTE });
  const campos = ["icms_base_calculo", "icms_valor", "icms_aliquota", "ipi_base_calculo", "ipi_valor", "valor_total_item"];
  confere("ICMS/IPI do item iguais", campos.every((c) => a.items[0][c] === b.items[0][c]), campos.map((c) => `${c}:${a.items[0][c]}/${b.items[0][c]}`).join(" "));
  confere("vNF igual", a.valor_total === b.valor_total, `${a.valor_total}/${b.valor_total}`);
}

// A frase e so das vendas. Nao da para observar pelo infCpl: as tres naturezas de
// venda sao as unicas com cClassTrib mapeado para 2026, e qualquer outra para antes,
// no IBS/CBS. O caso negativo fica registrado — quando uma remessa passar a ser
// emissivel, e este ponto que tem de ser reconferido.
{
  let barrou = false;
  try {
    payloadCom({ consumidorFinal: 1, ibpt: IBPT_TESTE, natureza: "REMESSA_INDUSTRIALIZACAO_ENCOMENDA", cfop: "5901" });
  } catch (erro) {
    barrou = /sem cClassTrib mapeado/.test(String(erro.message));
  }
  console.log("\nI · Remessa p/ industrializacao ainda nao e emissivel");
  confere("barrada no IBS/CBS, antes do infCpl", barrou, "esperado bloqueio por cClassTrib nao mapeado");
}

console.log(falhas === 0 ? "\nTributos da NF-e: todos os cenarios passaram." : `\nTributos da NF-e: ${falhas} divergencia(s).`);
process.exit(falhas === 0 ? 0 : 1);
