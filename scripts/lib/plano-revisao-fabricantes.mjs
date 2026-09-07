import assert from "node:assert/strict";
import { normalizarNomeCadastro, normalizarUnidadesNoNome } from "../../lib/itens/normalizacaoNome.ts";

const camposIdentidade = ["id", "codigo_interno", "fornecedor_id", "fabricante", "ativo"];
const camposRevisados = ["nome", "descricao", "grupo_id", "atualizado_em"];
export const camposPermitidos = ["nome", "descricao", "grupo_id"];

export function montarPlano(manifesto, atuais, grupos) {
  assert.equal(new Set(manifesto.itens.map((i) => i.id)).size, manifesto.itens.length, "IDs repetidos");
  assert.equal(atuais.length, manifesto.itens.length, "Quantidade de registros divergente");
  return manifesto.itens.map((item) => {
    assert.ok(!manifesto.pendentes_fora_do_lote.includes(item.id), "Item pendente no lote");
    const atual = atuais.find((i) => i.id === item.id);
    assert.ok(atual?.ativo && item.antes.id === item.id, `Item inválido: ${item.id}`);
    for (const campo of camposIdentidade) {
      assert.equal(atual[campo], item.antes[campo], `Identidade alterada: ${item.id}/${campo}`);
    }
    assert.ok(item.nome.length > 0 && item.nome.length <= 255 && normalizarNomeCadastro(item.nome) === item.nome, `Nome inválido: ${item.id}`);
    assert.ok(item.fontes.length && item.fontes.every((f) => new URL(f).protocol === "https:"), `Fontes ausentes: ${item.id}`);
    const grupo = item.grupo_codigo ? grupos.find((g) => g.codigo === item.grupo_codigo && g.ativo) : null;
    assert.ok(!item.grupo_codigo || grupo, `Grupo não encontrado: ${item.grupo_codigo}`);
    const descricao = [
      item.antes.descricao ? normalizarUnidadesNoNome(item.antes.descricao) : null,
      item.descricao_tecnica,
      `Fontes técnicas consultadas em ${manifesto.data}:\n${item.fontes.join("\n")}`,
    ].filter(Boolean).join("\n\n");
    const depois = { nome: item.nome, descricao, grupo_id: grupo ? grupo.id : item.antes.grupo_id };
    const aplicado = camposPermitidos.every((c) => atual[c] === depois[c]);
    if (!aplicado) {
      for (const campo of camposRevisados) {
        assert.equal(atual[campo], item.antes[campo], `Item mudou após revisão: ${item.id}/${campo}`);
      }
    }
    return { antes: atual, depois, aplicado, fontes: item.fontes, pendencias: item.pendencias };
  });
}

export function verificarRetorno(plano, retorno) {
  assert.ok(retorno, `Sem retorno: ${plano.antes.id}`);
  for (const campo of camposPermitidos) assert.equal(retorno[campo], plano.depois[campo], `Gravação divergente: ${plano.antes.id}/${campo}`);
  // Detecta efeitos inesperados em preço, unidade, código e demais campos.
  for (const campo of Object.keys(plano.antes)) {
    if (!camposPermitidos.includes(campo) && campo !== "atualizado_em") {
      assert.deepEqual(retorno[campo], plano.antes[campo], `Campo protegido alterado: ${plano.antes.id}/${campo}`);
    }
  }
}
