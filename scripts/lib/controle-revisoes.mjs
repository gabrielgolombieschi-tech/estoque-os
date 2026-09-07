import assert from "node:assert/strict";
import { createHash } from "node:crypto";

export const tenantId = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
export const empresaId = "f0e74f49-a127-46b4-901b-f7b37e43c690";
export const criterios = { CONTATORES: "CONTATORES:1" };
export const diretorio = "docs/padroes-cadastro/revisoes";
export function validarEscopo(registro) {
  assert.equal(registro.tenant_id, tenantId, "Tenant divergente");
  assert.equal(registro.empresa_id, empresaId, "Empresa divergente");
}

// Não reabrir revisão por preço, saldo, atividade ou timestamp administrativo.
// Inclui todos os campos de unidade/conversão existentes, sem presumir seu nome.
export function impressaoTecnica(item) {
  const fixos = ["id", "codigo_interno", "nome", "descricao", "fabricante", "fornecedor_id", "grupo_id", "tipo", "finalidade"];
  const campos = [...new Set([...fixos, ...Object.keys(item).filter((c) => /unidade|multiplicador|conversao|fator|modelo|referencia|especificacao/.test(c))])].sort();
  return createHash("sha256").update(JSON.stringify(campos.map((c) => [c, item[c] ?? null]))).digest("hex");
}

export function situacaoRevisao(item, eventos, historico = [], informado = []) {
  for (const e of eventos) validarEscopo(e);
  const registros = eventos.filter((e) => e.item_id === item.id).sort((a, b) => a.revisado_em.localeCompare(b.revisado_em));
  const ultimo = registros.at(-1);
  if (!ultimo) {
    if (historico.some((h) => h.id === item.id)) return "historico_recuperado";
    if (informado.some((h) => h.id === item.id && h.codigo === item.codigo_interno)) return "historico_informado";
    return "nao_revisado";
  }
  if (ultimo.criterio !== criterios[ultimo.familia] || ultimo.impressao_tecnica !== impressaoTecnica(item)) return "reavaliar";
  assert.ok(["aprovado", "pendente"].includes(ultimo.status), "Status inválido");
  return ultimo.status;
}

export function validarLote(manifesto) {
  validarEscopo(manifesto);
  assert.equal(manifesto.criterio, criterios[manifesto.familia]);
  const todos = [...manifesto.itens, ...manifesto.pendentes];
  assert.equal(new Set(todos.map((i) => i.id)).size, todos.length, "IDs duplicados no lote");
  assert.deepEqual(manifesto.pendentes_fora_do_lote.slice().sort(), manifesto.pendentes.map((i) => i.id).sort());
  for (const i of manifesto.itens) {
    assert.equal(i.pendencias.length, 0, "Pendência não pode virar aprovação");
    assert.match(i.nome, /^CONTATOR 3P AC-3 \d+A EM \d+VCA .* BOBINA \d+VC[AC]/);
    assert.match(i.nome, /\dN[AF]/);
    assert.match(i.nome, /CONEXÃO POR (MOLA|PARAFUSO)$/);
    if (/BOBINA \d+VCA/.test(i.nome)) assert.match(i.nome, /50\/60Hz/);
    if (/BOBINA \d+VCC/.test(i.nome)) assert.ok(!/Hz/.test(i.nome));
  }
}
