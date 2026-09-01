import assert from "node:assert/strict";
import {
  aplicarCorrecoesExatas,
  erroTabelaCorrecaoAusente,
  normalizarDescricaoAprendizado,
  substituirDescricaoSugestao,
} from "../lib/nfe/descricaoCorrecaoIa.ts";

const descricaoOrigem = "Cabo FlexSil 750 V 2,50 Brasileirinho";
const descricaoNormalizada = normalizarDescricaoAprendizado(descricaoOrigem);
const descricaoFinal = "CABO ELÉTRICO 750V 2,50MM² VERDE/AMARELO";

assert.equal(descricaoNormalizada, "CABO FLEXSIL 750 V 2 50 BRASILEIRINHO");

const correcoes = aplicarCorrecoesExatas(
  [{ descricao_nf: "CABO FLEXSIL 750 V 2.50 BRASILEIRINHO" }],
  [
    {
      descricao_origem: descricaoOrigem,
      descricao_origem_normalizada: descricaoNormalizada,
      descricao_corrigida: descricaoFinal,
    },
  ]
);

assert.equal(correcoes.get(descricaoNormalizada), descricaoFinal);

const sugestaoOriginal = {
  descricao_padronizada: "CABO ELÉTRICO 750V 2,50MM²",
  grupo_id: 42,
  ncm: "85444900",
  fiscal: { cst_icms: "020" },
};
const sugestaoCorrigida = substituirDescricaoSugestao(sugestaoOriginal, descricaoFinal);

assert.equal(sugestaoCorrigida.descricao_padronizada, descricaoFinal);
assert.equal(sugestaoCorrigida.grupo_id, sugestaoOriginal.grupo_id);
assert.equal(sugestaoCorrigida.ncm, sugestaoOriginal.ncm);
assert.deepEqual(sugestaoCorrigida.fiscal, sugestaoOriginal.fiscal);
assert.equal(erroTabelaCorrecaoAusente({ code: "PGRST205" }), true);
assert.equal(
  erroTabelaCorrecaoAusente({ message: "Could not find the table 'public.parametro_importacao_xml_descricao_ia'" }),
  true
);
assert.equal(erroTabelaCorrecaoAusente({ code: "23505", message: "duplicate key" }), false);

console.log("correcao de descricao IA: ok");
