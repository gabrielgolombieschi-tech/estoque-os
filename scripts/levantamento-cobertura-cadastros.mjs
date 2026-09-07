// Levantamento somente leitura: não altera itens, histórico nem regras do agente.
import fs from "node:fs";
import assert from "node:assert/strict";
import yaml from "js-yaml";
import { createClient } from "@supabase/supabase-js";

const tenantId = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
const empresaId = "f0e74f49-a127-46b4-901b-f7b37e43c690";
const ler = (p) => fs.readFileSync(p, "utf8");
const env = Object.fromEntries(ler(".env.local").split(/\r?\n/).filter((l) => l.includes("=") && !l.trim().startsWith("#")).map((l) => {
  const i = l.indexOf("=");
  return [l.slice(0, i).trim(), l.slice(i + 1).trim().replace(/^(["'])(.*)\1$/, "$2")];
}));
const db = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const scope = (q) => q.eq("tenant_id", tenantId).eq("empresa_id", empresaId);
async function paginas(tabela, colunas) {
  const linhas = [];
  for (let inicio = 0; ; inicio += 1000) {
    const { data, error } = await scope(db.from(tabela).select(colunas)).order("id").range(inicio, inicio + 999);
    if (error) throw new Error(`${tabela}: ${error.message}`);
    linhas.push(...data);
    if (data.length < 1000) return linhas;
  }
}
const [itens, sugestoes] = await Promise.all([
  paginas("itens", "id,codigo_interno,nome,ativo,tipo,finalidade,fornecedor_id,grupo_id,criado_em"),
  paginas("item_cadastro_agente_sugestoes", "id,item_id,codigo_interno,confirmado_em"),
]);
const porId = new Map(itens.map((i) => [i.id, i]));
const evidencias = new Map();
const lacunas = [];
const fontes = [];
const codigo = (v) => String(v ?? "").toUpperCase().replace(/[\s-]/g, "");
function adicionar(ids, fonte) {
  const existentes = new Set();
  for (const id of ids) {
    if (!porId.has(id)) { lacunas.push({ fonte, id, motivo: "ID não está mais no recorte atual" }); continue; }
    existentes.add(id);
    if (!evidencias.has(id)) evidencias.set(id, new Set());
    evidencias.get(id).add(fonte);
  }
  fontes.push({ fonte, itens_identificados: existentes.size });
}
for (const arquivo of ["revisao-sick-2026-09-05.json", "revisao-cinco-fabricantes-2026-09-05.json"]) {
  const m = JSON.parse(ler(`docs/padroes-cadastro/${arquivo}`));
  assert.equal(m.tenant_id, tenantId);
  assert.equal(m.empresa_id, empresaId);
  adicionar(m.itens.map((i) => i.id), arquivo);
}
const cabos = ler("scripts/corrigir-cabos-sem-terminacao.js").split("const env = {};")[0];
const idsCabos = [...cabos.matchAll(/(?:\[|propor\()\s*(\d+)\s*,\s*"/g)].map((m) => Number(m[1]));
assert.equal(new Set(idsCabos).size, 143, "Extração do roteiro de cabos divergente");
adicionar(idsCabos, "D-031: cabos avaliados, incluindo 24 com pendências");
const ati = ler("scripts/corrigir-ati-brasil.js").split("const NOMES_APROVADOS = new Map([")[1].split("]);", 1)[0];
const codigosAti = [...ati.matchAll(/\["([^"]+)"/g)].map((m) => codigo(m[1]));
assert.equal(codigosAti.length, 19);
adicionar(itens.filter((i) => i.fornecedor_id === 35 && codigosAti.includes(codigo(i.codigo_interno))).map((i) => i.id), "D-029: ATI, correspondência de código e fornecedor");
// Recuperar também os mapas individualizados antigos, sem executar scripts de correção.
const mapaSick = ler("scripts/normalizar-wago-phoenix-sick.js").split("const SICK_POR_CODIGO = new Map([")[1].split("]);", 1)[0];
const codigosSick = [...mapaSick.matchAll(/^\s*\["([^"]+)"/gm)].map((m) => codigo(m[1]));
adicionar(itens.filter((i) => i.fornecedor_id === 14 && codigosSick.includes(codigo(i.codigo_interno))).map((i) => i.id), "D-026: referências SICK individualizadas no mapa legado");
const phoenix = ler("scripts/corrigir-phoenix-referencias.js");
const codigosPhoenix = ["REFERENCIAS_FIXAS", "NOMES_FIXOS"].flatMap((mapa) => {
  const bloco = phoenix.split(`const ${mapa} = new Map([`)[1].split("]);", 1)[0];
  return [...bloco.matchAll(/^\s*\["([^"]+)"/gm)].map((m) => codigo(m[1]));
});
adicionar(itens.filter((i) => i.fornecedor_id === 1 && codigosPhoenix.includes(codigo(i.codigo_interno))).map((i) => i.id), "D-028: referências Phoenix individualizadas; não representa os 135 do lote inteiro");
const catalogo = yaml.load(ler("docs/padroes-cadastro/catalogo-paineis-eletricos.yaml"));
const exemplos = [];
function visitar(v) {
  if (!v || typeof v !== "object") return;
  if (v.codigo_origem) exemplos.push({ codigo: codigo(v.codigo_origem), id: v.id });
  Object.values(v).forEach(visitar);
}
visitar(catalogo.exemplos_aprovados);
const idsExemplos = [];
for (const e of exemplos) {
  const encontrados = itens.filter((i) => codigo(i.codigo_interno) === e.codigo && (!e.id || e.id === i.id));
  if (encontrados.length === 1) idsExemplos.push(encontrados[0].id);
  else lacunas.push({ fonte: "Exemplo aprovado", codigo: e.codigo, correspondencias: encontrados.length, motivo: "Não somar correspondência ausente/ambígua" });
}
adicionar(idsExemplos, "Exemplos individualizados aprovados no catálogo (inclui revisões antigas)");
adicionar(sugestoes.map((s) => s.item_id), "Propostas do agente confirmadas e auditadas no banco");
// Eventos novos são emitidos somente após verificação; não contar manifestos propostos.
const diretorioRevisoes = "docs/padroes-cadastro/revisoes";
if (fs.existsSync(diretorioRevisoes)) {
  for (const arquivo of fs.readdirSync(diretorioRevisoes).filter((n) => /^eventos-.*\.json$/.test(n))) {
    const eventos = JSON.parse(ler(`${diretorioRevisoes}/${arquivo}`));
    for (const evento of eventos) {
      assert.equal(evento.tenant_id, tenantId);
      assert.equal(evento.empresa_id, empresaId);
    }
    adicionar(eventos.map((e) => e.item_id), `Controle por item: ${arquivo}; inclui pendentes, não equivale a aprovação atual`);
  }
}
const avaliados = itens.filter((i) => evidencias.has(i.id));
const totalizar = (lista) => ({ total: lista.length, ativos: lista.filter((i) => i.ativo === true).length, inativos: lista.filter((i) => i.ativo === false).length, status_nulo: lista.filter((i) => i.ativo == null).length });
const resultado = {
  data_consulta: new Date().toISOString(), tenant_id: tenantId, empresa_id: empresaId,
  cadastrados: totalizar(itens),
  por_tipo: [...new Set(itens.map((i) => i.tipo))].map((tipo) => ({ tipo, ...totalizar(itens.filter((i) => i.tipo === tipo)) })),
  materias_primas: totalizar(itens.filter((i) => i.finalidade === "materia_prima")),
  avaliados_minimo_comprovavel: totalizar(avaliados),
  materias_primas_avaliadas_minimo: totalizar(avaliados.filter((i) => i.finalidade === "materia_prima")),
  percentual_minimo: Number((100 * avaliados.length / itens.length).toFixed(2)),
  sem_evidencia_individual_recuperada: itens.length - avaliados.length,
  fontes_sobrepostas_nao_somar: fontes, lacunas,
  limite: "Mínimo comprovável por IDs/códigos individualizados, não total histórico exato. Avaliado não significa tecnicamente completo. Não conta inventários, grupo preenchido, data de alteração ou simples remoção de espaços como revisão técnica. Lotes antigos apenas agregados não foram somados para evitar duplicidades.",
  itens_com_evidencia: avaliados.map((i) => ({ id: i.id, codigo: i.codigo_interno, ativo: i.ativo, fontes: [...evidencias.get(i.id)] })),
};
fs.mkdirSync("backups/levantamento-cadastros", { recursive: true });
const arquivo = `backups/levantamento-cadastros/${resultado.data_consulta.replace(/[:.]/g, "-")}.json`;
fs.writeFileSync(arquivo, JSON.stringify(resultado, null, 2), { flag: "wx" });
console.log(JSON.stringify({ arquivo, ...resultado, itens_com_evidencia: undefined }, null, 2));
