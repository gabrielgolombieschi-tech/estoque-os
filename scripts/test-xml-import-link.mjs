import assert from "node:assert/strict";
import { analyzeXmlImport, normalizeXmlItemCode } from "../lib/nfe/xmlImportAnalyzer.ts";

const codigoXml = "00003.012.003.1.23";
const codigoInterno = "3.012.003.1.23";

assert.equal(normalizeXmlItemCode(codigoXml), codigoInterno);

const result = analyzeXmlImport({
  nfe: {
    numero: "495223",
    serie: "1",
    cnpjEmitente: "61310256000190",
    valorTotal: 602.98,
  },
  itens: [
    {
      codigo: codigoXml,
      descricao: "Cabo FlexSil 750 V 0,50 Branco",
      quantidade: 1.4,
      valorUnit: 430.7,
      valorProd: 602.98,
      unidade: "KM",
      pedidoXml: "PC-SEG-00300-026",
    },
  ],
  fornecedor: {
    id: 663,
    nome: "FORNECEDOR TESTE",
    documento: "61310256000190",
  },
  itensCadastradosPorCodigo: [
    {
      id: 3692,
      codigo_interno: codigoInterno,
      nome: "CABO ELÉTRICO 750V 0,50MM² BRANCO",
      fornecedor_id: 663,
      finalidade: "materia_prima",
    },
  ],
  pedidosCandidatos: [
    {
      id: "pedido-300",
      codigo: "PC-SEG-00300-026",
      status: "ENVIADO",
      fornecedor_id: 663,
      total_geral: 1266.04,
      itens: [
        {
          id: "item-azul",
          seq: 1,
          item_nome: "CABO FLEX 750V 0,50MM2 AZUL",
          quantidade: 1400,
          quantidade_recebida: 0,
          valor_unitario: 0.4743,
        },
        {
          id: "item-branco",
          seq: 2,
          item_nome: "CABO FLEX 750V 0,50MM2 BRANCO",
          quantidade: 1400,
          quantidade_recebida: 0,
          valor_unitario: 0.4743,
        },
      ],
    },
  ],
  finalidadeSelecionada: "materia_prima",
  motivoSelecionadoId: "motivo-teste",
  solicitanteUsuarioId: "usuario-teste",
  pedidoCompraRefAtual: "PC-SEG-00300-026",
  parametros: { pedidoScoreMinimo: 0 },
});

const itemSuggestion = result.itemSuggestions[0];
assert.equal(itemSuggestion.internalItem?.id, 3692, "deve reconhecer o cadastro existente pelo código normalizado");
assert.equal(itemSuggestion.pedidoManualMatches?.length, 2, "deve calcular score para todos os itens manuais");

const scoreBranco = itemSuggestion.pedidoManualMatches?.find((match) => match.pedidoItemId === "item-branco")?.score;
const scoreAzul = itemSuggestion.pedidoManualMatches?.find((match) => match.pedidoItemId === "item-azul")?.score;
assert.equal(typeof scoreBranco, "number");
assert.equal(typeof scoreAzul, "number");
assert.ok(scoreBranco > scoreAzul, "o item branco deve pontuar acima do item azul");
assert.equal(itemSuggestion.pedidoManualMatches?.[0]?.pedidoItemId, "item-branco", "o candidato mais semelhante deve aparecer primeiro");
assert.ok(
  (itemSuggestion.pedidoManualMatches?.[0]?.descricaoSimilarity ?? 0) >
    (itemSuggestion.pedidoManualMatches?.[1]?.descricaoSimilarity ?? 0),
  "o desempate deve preservar a melhor similaridade de descrição"
);

console.log(`OK: cadastro ${itemSuggestion.internalItem?.id}; scores branco=${scoreBranco}, azul=${scoreAzul}`);
