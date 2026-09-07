import fs from "node:fs";
import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
import { montarPlano, verificarRetorno } from "./lib/plano-revisao-fabricantes.mjs";
import { tenantId, empresaId, diretorio, validarLote, impressaoTecnica } from "./lib/controle-revisoes.mjs";

// Sem argumentos: somente leitura remota. --apply: nomes/descrições aprovados.
const lotes = {
  "001": { arquivo: "001-contatores-siemens", aprovados: 18, pendentes: 2 },
  "002": { arquivo: "002-contatores-agrupados", aprovados: 20, pendentes: 0 },
};
const selecao = process.argv.find((a) => a.startsWith("--lote="))?.slice(7) ?? "001";
assert.ok(Object.hasOwn(lotes, selecao), "Lote não autorizado neste roteiro");
const lote = lotes[selecao];
const manifesto = JSON.parse(fs.readFileSync(`${diretorio}/lote-${lote.arquivo}.json`, "utf8"));
validarLote(manifesto);
assert.equal(manifesto.lote, lote.arquivo);
assert.equal(manifesto.itens.length, lote.aprovados);
assert.equal(manifesto.pendentes.length, lote.pendentes);
if (selecao === "002") {
  const recorte = JSON.parse(fs.readFileSync(`${diretorio}/historico-informado-grupos.json`, "utf8"));
  assert.equal(recorte.tenant_id, tenantId);
  assert.equal(recorte.empresa_id, empresaId);
  for (const p of manifesto.itens) {
    assert.equal(p.antes.grupo_id, 17);
    assert.ok(recorte.itens.some((i) => i.id === p.id && i.codigo === p.antes.codigo_interno && i.grupo_id === 17));
  }
}
const env = Object.fromEntries(fs.readFileSync(".env.local", "utf8").split(/\r?\n/).filter((l) => l.includes("=") && !l.trim().startsWith("#")).map((l) => {
  const i = l.indexOf("="); return [l.slice(0, i).trim(), l.slice(i + 1).trim().replace(/^(["'])(.*)\1$/, "$2")];
}));
const db = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const scope = (q) => q.eq("tenant_id", tenantId).eq("empresa_id", empresaId);
const ids = [...manifesto.itens, ...manifesto.pendentes].map((i) => i.id);
async function consultar() {
  const { data, error } = await scope(db.from("itens").select("*")).in("id", ids);
  if (error) throw new Error(error.message);
  assert.equal(data.length, ids.length);
  return data;
}
const atuais = await consultar();
for (const p of manifesto.pendentes) {
  const atual = atuais.find((i) => i.id === p.id);
  for (const [campo, valor] of Object.entries(p.antes)) assert.deepEqual(atual[campo], valor, `Pendente mudou: ${p.id}/${campo}`);
}
const aprovados = atuais.filter((i) => manifesto.itens.some((p) => p.id === i.id));
const plano = montarPlano(manifesto, aprovados, []);
// Este lote não altera classificação, unidade, código, fabricante ou fornecedor.
for (const p of plano) assert.equal(p.depois.grupo_id, p.antes.grupo_id);
const alteracoes = plano.filter((p) => !p.aplicado);
console.log(JSON.stringify({ avaliados: ids.length, aprovados: plano.length, pendentes: manifesto.pendentes_fora_do_lote, alteracoes: alteracoes.length, nomes: plano.map((p) => ({ id: p.antes.id, nome: p.depois.nome })) }, null, 2));
if (process.argv.includes("--verify")) assert.equal(alteracoes.length, 0);
if (process.argv.includes("--apply")) {
  let backup = null;
  if (alteracoes.length) {
    fs.mkdirSync("backups/revisao-contatores", { recursive: true });
    backup = `backups/revisao-contatores/${new Date().toISOString().replace(/[:.]/g, "-")}.json`;
    fs.writeFileSync(backup, JSON.stringify({ tenant_id: tenantId, empresa_id: empresaId, manifesto, alteracoes }, null, 2), { flag: "wx" });
    console.log(`Backup: ${backup}`);
    for (const p of alteracoes) {
      let q = scope(db.from("itens").update({ nome: p.depois.nome, descricao: p.depois.descricao }));
      for (const campo of ["id", "codigo_interno", "fornecedor_id", "fabricante", "ativo", "nome", "descricao", "grupo_id", "atualizado_em"]) {
        q = p.antes[campo] == null ? q.is(campo, null) : q.eq(campo, p.antes[campo]);
      }
      const { data, error } = await q.select("*");
      if (error || data?.length !== 1) throw new Error(`Interrompido no ID ${p.antes.id}: ${error?.message ?? "alteração concorrente"}. Consulte ${backup}`);
      fs.appendFileSync(`${backup}.resultado.jsonl`, `${JSON.stringify(data[0])}\n`);
      verificarRetorno(p, data[0]);
    }
  }
  const confirmados = await consultar();
  for (const p of plano) verificarRetorno(p, confirmados.find((i) => i.id === p.antes.id));
  for (const p of manifesto.pendentes) assert.deepEqual(confirmados.find((i) => i.id === p.id), atuais.find((i) => i.id === p.id));
  const arquivo = `${diretorio}/eventos-${lote.arquivo}.json`;
  const eventos = confirmados.map((i) => {
    const proposta = manifesto.itens.find((p) => p.id === i.id);
    const pendente = manifesto.pendentes.find((p) => p.id === i.id);
    return { tenant_id: tenantId, empresa_id: empresaId, item_id: i.id, codigo: i.codigo_interno, nome: i.nome,
      familia: manifesto.familia, criterio: manifesto.criterio, lote: manifesto.lote,
      revisado_em: new Date().toISOString(), responsavel: manifesto.responsavel,
      status: proposta ? "aprovado" : "pendente", fontes: (proposta ?? pendente).fontes,
      pendencias: pendente ? [pendente.motivo] : [], impressao_tecnica: impressaoTecnica(i), backup };
  });
  if (fs.existsSync(arquivo)) {
    const anteriores = JSON.parse(fs.readFileSync(arquivo, "utf8"));
    assert.equal(anteriores.length, eventos.length);
    for (const e of eventos) {
      const anterior = anteriores.find((a) => a.item_id === e.item_id);
      for (const c of ["tenant_id", "empresa_id", "criterio", "status", "impressao_tecnica"]) assert.equal(anterior?.[c], e[c], `Evento incompatível: ${e.item_id}/${c}`);
    }
  } else fs.writeFileSync(arquivo, JSON.stringify(eventos, null, 2), { flag: "wx" });
  console.log(JSON.stringify({ atualizados: alteracoes.length, verificados: confirmados.length, registro: arquivo }));
}
