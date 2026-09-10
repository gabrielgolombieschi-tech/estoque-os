import fs from "node:fs";
import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {validarEscopo,criterios,impressaoTecnica} from "./controle-revisoes.mjs";
import {assinatura,validarCinquenta} from "./lotes-cinquenta.mjs";
import {normalizarNomeCadastro} from "../../lib/itens/normalizacaoNome.ts";
export function validarManifestoClaro(m) {
  if(m.formato!=="referencias_claras_v1")return validarCinquenta(m);
  validarEscopo(m);assert.equal(m.decisao,"D-047");
  assert.match(m.numero,/^\d{3}$/);assert.equal(m.lote,`${m.numero}-referencias-claras`);
  assert.ok(m.itens.length>0);assert.equal(new Set(m.itens.map(i=>i.id)).size,m.itens.length);
  for(const i of m.itens){
    validarEscopo(i.antes);assert.equal(i.id,i.antes.id);
    assert.equal(i.impressao_antes,impressaoTecnica(i.antes));
    assert.ok(i.antes.ativo&&i.antes.grupo_id);assert.equal(i.criterio,criterios[i.familia]);
    assert.equal(i.nome,normalizarNomeCadastro(i.nome));assert.ok(i.nome.length<=255&&i.nome!==i.antes.nome);
    assert.deepEqual(Object.keys(i.depois).sort(),["descricao","nome"]);assert.equal(i.nome,i.depois.nome);
    assert.ok(i.depois.descricao.includes(i.descricao_tecnica)&&i.descricao_tecnica.includes(i.referencia));
    assert.equal(i.pendencias.length,0);assert.ok(i.fontes.length&&i.fontes.every(f=>new URL(f).protocol==="https:"));
  }
}
export function planejarReferenciasClaras(m,atuais){
  validarManifestoClaro(m);assert.equal(atuais.length,m.itens.length);
  return m.itens.map(i=>{
    const atual=atuais.find(a=>a.id===i.id);assert.ok(atual);validarEscopo(atual);
    const aplicado=atual.nome===i.depois.nome&&atual.descricao===i.depois.descricao;
    assert.equal(impressaoTecnica(atual),impressaoTecnica(aplicado?{...i.antes,...i.depois}:i.antes),`Mudança técnica concorrente: ${i.id}`);
    assert.equal(atual.ativo,i.antes.ativo);return {item:i,antes:atual,depois:i.depois,aplicado};
  });
}
export function validarLiberacaoClara(m,liberacao,autorizacao) {
  validarManifestoClaro(m); validarEscopo(liberacao); validarEscopo(autorizacao);
  assert.equal(autorizacao.decisao,"D-047"); assert.equal(autorizacao.status,"autorizado_condicionalmente");
  assert.deepEqual(autorizacao.campos_permitidos,["nome","descricao"]);
  assert.equal(liberacao.decisao,autorizacao.decisao);
  assert.equal(liberacao.lote,m.lote); assert.equal(liberacao.assinatura_lote,assinatura(m));
  assert.ok(liberacao.ids_claros.length); assert.equal(new Set(liberacao.ids_claros).size,liberacao.ids_claros.length);
  assert.deepEqual([...liberacao.ids_claros,...liberacao.retidos].sort((a,b)=>a-b),m.itens.map(i=>i.id).sort((a,b)=>a-b));
  const claros=m.itens.filter(i=>liberacao.ids_claros.includes(i.id));
  assert.equal(claros.length,liberacao.ids_claros.length);
  for(const i of claros) {
    assert.equal(i.atributos_nao_confirmados?.length ?? 0,0,`Lacuna técnica: ${i.id}`);
    assert.ok(!Object.hasOwn(liberacao.exclusoes_adicionais,i.id),`Exclusão técnica: ${i.id}`);
    assert.ok(criterios[i.familia],`Critério não ativo: ${i.familia}`);
    assert.equal(i.referencia.replace(/-/g,""),i.antes.codigo_interno.replace(/-/g,""));
    assert.equal(createHash("sha256").update(fs.readFileSync(i.evidencia.arquivo)).digest("hex"),i.evidencia.sha256);
    assert.ok(i.evidencia.paginas.length && i.fontes.length);
  }
  return claros;
}
