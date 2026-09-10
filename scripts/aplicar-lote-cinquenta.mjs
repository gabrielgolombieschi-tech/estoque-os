import fs from "node:fs";
import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
import { tenantId, empresaId, diretorio, criterios, impressaoTecnica } from "./lib/controle-revisoes.mjs";
import { validarCinquenta, exigirAutorizacao, planejarCinquenta, conferirCinquenta, assinatura } from "./lib/lotes-cinquenta.mjs";
const numero = process.argv.find((a) => a.startsWith("--lote="))?.slice(7) ?? "003";
assert.ok(["003", "004", "005", "006", "007", "008", "009", "010", "011"].includes(numero));
const m = JSON.parse(fs.readFileSync(`${diretorio}/lote-${numero}-cinquenta-itens.json`, "utf8"));
validarCinquenta(m);
const aplicar = process.argv.includes("--apply");
const arquivoAprovacao = `${diretorio}/aprovacao-${numero}.json`;
const aprovacao = fs.existsSync(arquivoAprovacao) ? JSON.parse(fs.readFileSync(arquivoAprovacao, "utf8")) : null;
if (aplicar) {
  exigirAutorizacao(m, aprovacao); // Falha antes de abrir conexão para lote não autorizado.
}
const env = Object.fromEntries(fs.readFileSync(".env.local", "utf8").split(/\r?\n/).filter((l) => l.includes("=") && !l.trim().startsWith("#")).map((l) => {
  const p = l.indexOf("="); return [l.slice(0, p).trim(), l.slice(p + 1).trim().replace(/^(["'])(.*)\1$/, "$2")];
}));
const db = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const scope = (q) => q.eq("tenant_id", tenantId).eq("empresa_id", empresaId);
async function consultar() {
  const { data, error } = await scope(db.from("itens").select("*")).in("id", m.itens.map((i) => i.id));
  if (error) throw new Error(error.message);
  return data;
}
const plano = planejarCinquenta(m, await consultar());
const alteracoes = plano.filter((p) => !p.aplicado);
console.log(JSON.stringify({ lote: m.lote, planejados: 50, a_alterar: alteracoes.length, ja_aplicados: 50 - alteracoes.length, autorizacao: aprovacao?.status ?? m.autorizacao }));
if (process.argv.includes("--verify")) assert.equal(alteracoes.length, 0);
if (aplicar) {
  let backup = null;
  if (alteracoes.length) {
    fs.mkdirSync("backups/revisao-lotes", { recursive: true });
    backup = `backups/revisao-lotes/${m.numero}-${new Date().toISOString().replace(/[:.]/g, "-")}.json`;
    fs.writeFileSync(backup, JSON.stringify({ tenant_id: tenantId, empresa_id: empresaId, manifesto: m, aprovacao, plano }, null, 2), { flag: "wx" });
    for (const p of alteracoes) {
      let q = scope(db.from("itens").update(p.depois));
      // CAS: protege a identidade, todos os campos técnicos e timestamp lido imediatamente antes.
      const campos = new Set(["id", "codigo_interno", "nome", "descricao", "fabricante", "fornecedor_id", "grupo_id", "tipo", "finalidade", "ativo", "atualizado_em", ...Object.keys(p.antes).filter((c) => /unidade|multiplicador|conversao|fator|modelo|referencia|especificacao/.test(c))]);
      for (const c of campos) q = p.antes[c] == null ? q.is(c, null) : q.eq(c, p.antes[c]);
      const { data, error } = await q.select("*");
      if (error || data?.length !== 1) throw new Error(`Parou em ${p.antes.id}: ${error?.message ?? "alteração concorrente"}. Backup: ${backup}`);
      fs.appendFileSync(`${backup}.resultado.jsonl`, `${JSON.stringify(data[0])}\n`);
      conferirCinquenta(p, data[0]);
    }
  }
  const atuais = await consultar();
  for (const p of plano) conferirCinquenta(p, atuais.find((i) => i.id === p.antes.id));
  const eventos = atuais.map((i) => {
    const proposta = m.itens.find((p) => p.id === i.id);
    return { tenant_id: tenantId, empresa_id: empresaId, item_id: i.id, codigo: i.codigo_interno, nome: i.nome, familia: proposta.familia, criterio: criterios[proposta.familia], lote: m.lote, revisado_em: new Date().toISOString(), responsavel: m.responsavel, status: "aprovado", fontes: proposta.fontes, pendencias: [], atributos_nao_confirmados: proposta.atributos_nao_confirmados ?? [], impressao_tecnica: impressaoTecnica(i), backup, assinatura_lote: assinatura(m) };
  });
  const arquivo = `${diretorio}/eventos-${m.lote}.json`;
  if (fs.existsSync(arquivo)) {
    const antigos = JSON.parse(fs.readFileSync(arquivo, "utf8"));
    assert.equal(antigos.length, 50);
    for (const e of eventos) {
      const anterior = antigos.find((a) => a.item_id === e.item_id);
      for (const c of ["tenant_id", "empresa_id", "criterio", "status", "impressao_tecnica", "assinatura_lote"]) assert.equal(anterior?.[c], e[c]);
    }
  } else fs.writeFileSync(arquivo, JSON.stringify(eventos, null, 2), { flag: "wx" });
  console.log(JSON.stringify({ atualizados: alteracoes.length, verificados: atuais.length, backup, eventos: arquivo }));
}
