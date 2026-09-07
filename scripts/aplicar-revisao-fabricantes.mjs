import fs from "node:fs";
import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
import { montarPlano, verificarRetorno } from "./lib/plano-revisao-fabricantes.mjs";

// Somente leitura por padrão. --apply grava apenas os campos aprovados.
const manifesto = JSON.parse(fs.readFileSync("docs/padroes-cadastro/revisao-cinco-fabricantes-2026-09-05.json", "utf8"));
const tenantId = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
const empresaId = "f0e74f49-a127-46b4-901b-f7b37e43c690";
assert.equal(manifesto.tenant_id, tenantId);
assert.equal(manifesto.empresa_id, empresaId);
assert.equal(manifesto.itens.length, 16);
const env = Object.fromEntries(fs.readFileSync(".env.local", "utf8").split(/\r?\n/)
  .filter((line) => line.includes("=") && !line.trim().startsWith("#"))
  .map((line) => { const i = line.indexOf("="); return [line.slice(0, i).trim(), line.slice(i + 1).trim().replace(/^(["'])(.*)\1$/, "$2")]; }));
const db = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const scope = (q) => q.eq("tenant_id", tenantId).eq("empresa_id", empresaId);
const ids = manifesto.itens.map((i) => i.id);
const { data: atuais, error } = await scope(db.from("itens").select("*")).in("id", ids);
if (error) throw new Error(error.message);
const { data: grupos, error: grupoError } = await scope(db.from("item_grupos").select("id,codigo,ativo")).eq("ativo", true);
if (grupoError) throw new Error(grupoError.message);
const plano = montarPlano(manifesto, atuais, grupos);
const alteracoes = plano.filter((p) => !p.aplicado);
console.log(JSON.stringify({ revisados: plano.length, alteracoes: alteracoes.length, pendentes_fora_do_lote: manifesto.pendentes_fora_do_lote, plano: plano.map((p) => ({ id: p.antes.id, nome: p.depois.nome, grupo_id: p.depois.grupo_id, aplicado: p.aplicado })) }, null, 2));
if (process.argv.includes("--verify")) assert.equal(alteracoes.length, 0, "Há itens ainda não aplicados");
if (process.argv.includes("--apply") && alteracoes.length) {
  const diretorio = "backups/revisao-cinco-fabricantes";
  fs.mkdirSync(diretorio, { recursive: true });
  const arquivo = `${diretorio}/${new Date().toISOString().replace(/[:.]/g, "-")}.json`;
  fs.writeFileSync(arquivo, JSON.stringify({ tenant_id: tenantId, empresa_id: empresaId, manifesto, alteracoes }, null, 2), { flag: "wx" });
  console.log(`Backup anterior à gravação: ${arquivo}`);
  const resultados = [];
  for (const p of alteracoes) {
    let query = scope(db.from("itens").update(p.depois));
    // Compare-and-set inclusive para campos nulos, sem sobrescrever concorrência.
    for (const campo of ["id", "codigo_interno", "fornecedor_id", "fabricante", "ativo", "nome", "descricao", "grupo_id", "atualizado_em"]) {
      query = p.antes[campo] == null ? query.is(campo, null) : query.eq(campo, p.antes[campo]);
    }
    const { data, error: updateError } = await query.select("*");
    if (updateError || data?.length !== 1) {
      throw new Error(`Interrompido no ID ${p.antes.id}; ${resultados.length} itens já gravados. Backup: ${arquivo}. ${updateError?.message ?? "Conflito concorrente"}`);
    }
    resultados.push(data[0]);
    fs.appendFileSync(`${arquivo}.resultado.jsonl`, `${JSON.stringify(data[0])}\n`);
    verificarRetorno(p, data[0]);
  }
  const { data: confirmados, error: verifyError } = await scope(db.from("itens").select("*")).in("id", ids);
  if (verifyError) throw new Error(verifyError.message);
  assert.equal(confirmados.length, plano.length);
  for (const p of plano) verificarRetorno(p, confirmados.find((i) => i.id === p.antes.id));
  console.log(JSON.stringify({ atualizados: resultados.length, verificados: confirmados.length, backup: arquivo }));
}
