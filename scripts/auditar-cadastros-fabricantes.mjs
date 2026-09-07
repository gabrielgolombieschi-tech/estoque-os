// Auditoria somente leitura. Não altera cadastros nem gera movimentações.
import fs from "node:fs";
import { createClient } from "@supabase/supabase-js";

const tenantId = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
const empresaId = "f0e74f49-a127-46b4-901b-f7b37e43c690";
const marcas = ["SIEMENS", "PHOENIX", "SCHNEIDER", "WEG", "RITTAL"];
const env = Object.fromEntries(fs.readFileSync(".env.local", "utf8").split(/\r?\n/).filter((l) => l.includes("=") && !l.trim().startsWith("#")).map((l) => { const i = l.indexOf("="); return [l.slice(0, i).trim(), l.slice(i + 1).trim().replace(/^(["'])(.*)\1$/, "$2")]; }));
const db = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const scope = (q) => q.eq("tenant_id", tenantId).eq("empresa_id", empresaId);
const { data: fornecedores, error: ef } = await scope(db.from("fornecedores").select("id,nome")).or(marcas.map((m) => `nome.ilike.%${m}%`).join(","));
if (ef) throw new Error(ef.message);
const { data: grupos, error: eg } = await scope(db.from("item_grupos").select("id,codigo,nome,grupo_pai_id"));
if (eg) throw new Error(eg.message);
const filtro = [...(fornecedores.length ? [`fornecedor_id.in.(${fornecedores.map((f) => f.id).join(",")})`] : []), ...marcas.map((m) => `fabricante.ilike.%${m}%`)];
const itens = [];
for (let inicio = 0; ; inicio += 1000) {
  const { data, error } = await scope(db.from("itens").select("id,codigo_interno,nome,descricao,fabricante,grupo_id,ativo,fornecedor_id,atualizado_em")).or(filtro.join(",")).order("id").range(inicio, inicio + 999);
  if (error) throw new Error(error.message);
  itens.push(...data);
  if (data.length < 1000) break;
}
const identificar = (s) => marcas.find((m) => new RegExp(`\\b${m}\\b`, "i").test(s ?? ""));
const resultado = marcas.map((marca) => {
  const registros = itens.filter((i) => (identificar(i.fabricante) ?? identificar(fornecedores.find((f) => f.id === i.fornecedor_id)?.nome)) === marca);
  const ativos = registros.filter((i) => i.ativo);
  const prioridade = (i) => {
    const nome = i.nome ?? "";
    return (nome.length < 38 ? 5 : 0) + (/ACESS[ÓO]RIO|COMPONENTE|M[ÓO]DULO INDUSTRIAL|MATERIAL EL[ÉE]TRICO|KIT PARA|PE[ÇC]A/.test(nome) ? 3 : 0) + (i.id >= 3500 ? 4 : 0) + (!i.grupo_id ? 5 : 0);
  };
  return { marca, total: registros.length, ativos: ativos.length, candidatos: ativos.sort((a, b) => prioridade(b) - prioridade(a) || b.id - a.id).slice(0, 22).map((i) => ({ ...i, grupo: grupos.find((g) => g.id === i.grupo_id)?.codigo })) };
});
const destino = "backups/auditoria-fabricantes";
fs.mkdirSync(destino, { recursive: true });
const arquivo = `${destino}/${new Date().toISOString().replace(/[:.]/g, "-")}.json`;
fs.writeFileSync(arquivo, JSON.stringify({ tenant_id: tenantId, empresa_id: empresaId, fornecedores, grupos, itens }, null, 2), { flag: "wx" });
console.log(JSON.stringify({ arquivo, total_unico: itens.length, ativos: itens.filter((i) => i.ativo).length, sem_grupo: itens.filter((i) => i.ativo && !i.grupo_id).length, resumo: resultado.map((r) => ({ ...r, candidatos: process.argv.includes("--candidatos") ? r.candidatos.map((i) => ({ id: i.id, codigo: i.codigo_interno, nome: i.nome, grupo: i.grupo })) : undefined })) }, null, 2));
if (process.argv.includes("--origens")) {
  const ids = [3612,3613,3614,3615,3616,3617,2956,2493,1394,1395,547,2908];
  if (!ids.every((id) => itens.some((i) => i.id === id))) throw new Error("ID fora do recorte consultado.");
  const { data, error } = await scope(db.from("nf_entrada_itens").select("item_id,codigo_fornecedor,descricao")).in("item_id", ids).limit(1000);
  if (error) throw new Error(error.message);
  const origens = [...new Map(data.map((i) => [JSON.stringify(i), i])).values()];
  console.log(JSON.stringify({ origens }, null, 2));
  fs.writeFileSync(arquivo.replace(/\.json$/, "-origens.json"), JSON.stringify(origens, null, 2), { flag: "wx" });
}
