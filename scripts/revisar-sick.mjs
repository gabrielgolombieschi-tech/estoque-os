import fs from "node:fs";
import { createClient } from "@supabase/supabase-js";
import { normalizarNomeCadastro } from "../lib/itens/normalizacaoNome.ts";

// Sem --apply, apenas consulta. O manifesto fixa os IDs, códigos e valores
// anteriores revisados; divergências posteriores exigem nova revisão humana.
const manifesto = JSON.parse(fs.readFileSync("docs/padroes-cadastro/revisao-sick-2026-09-05.json", "utf8"));

const tenantId = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
const empresaId = "f0e74f49-a127-46b4-901b-f7b37e43c690";
const env = Object.fromEntries(fs.readFileSync(".env.local", "utf8").split(/\r?\n/)
  .filter((line) => line.includes("=") && !line.trim().startsWith("#"))
  .map((line) => { const i = line.indexOf("="); return [line.slice(0, i).trim(), line.slice(i + 1).trim().replace(/^(["'])(.*)\1$/, "$2")]; }));
const db = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const scope = (query) => query.eq("tenant_id", tenantId).eq("empresa_id", empresaId);
const { data: fornecedores, error: fornecedorError } = await scope(db.from("fornecedores").select("id,nome")).ilike("nome", "%SICK%");
if (fornecedorError) throw new Error(fornecedorError.message);
const { data: itens, error } = await scope(db.from("itens").select("id,codigo_interno,nome,descricao,grupo_id,ativo,fornecedor_id,atualizado_em"))
  .in("fornecedor_id", fornecedores.map((row) => row.id)).order("id");
if (error) throw new Error(error.message);
console.log(JSON.stringify({ fornecedores, total: itens.length, ativos: itens.filter((i) => i.ativo).length }, null, 2));
if (process.argv.includes("--grupos")) {
  const { data, error: grupoError } = await scope(db.from("item_grupos").select("id,codigo,nome,grupo_pai_id")).order("id");
  if (grupoError) throw new Error(grupoError.message);
  console.log(JSON.stringify({ grupos: data.filter((g) => /REDE|SEGUR|RADAR|CHAVES/.test(g.codigo)) }, null, 2));
}
if (process.argv.includes("--origens")) {
  const { data, error: origensError } = await scope(db.from("nf_entrada_itens").select("item_id,codigo_fornecedor,descricao"))
    .in("item_id", itens.map((row) => row.id)).limit(1000);
  if (origensError) throw new Error(origensError.message);
  console.log(JSON.stringify({ origens: [...new Map(data.map((row) => [JSON.stringify(row), row])).values()] }, null, 2));
}

if (manifesto.tenant_id !== tenantId || manifesto.empresa_id !== empresaId || fornecedores.length !== 1 || fornecedores[0].id !== manifesto.fornecedor_id) {
  throw new Error("Escopo do manifesto diverge do fornecedor/empresa consultados.");
}
const { data: grupos, error: gruposError } = await scope(db.from("item_grupos").select("id,codigo")).eq("ativo", true);
if (gruposError) throw new Error(gruposError.message);
const plano = manifesto.itens.map((revisao) => {
  const atual = itens.find((i) => i.id === revisao.id);
  const grupo = grupos.find((g) => g.codigo === revisao.grupo_codigo);
  if (!grupo || !atual || !atual.ativo || atual.codigo_interno !== revisao.codigo || atual.fornecedor_id !== manifesto.fornecedor_id) {
    throw new Error(`Cadastro ou grupo divergente: ${revisao.codigo}`);
  }
  if (revisao.nome.length > 255 || normalizarNomeCadastro(revisao.nome) !== revisao.nome || !revisao.fontes.length) {
    throw new Error(`Nome ou evidência inválida: ${revisao.codigo}`);
  }
  const depois = { nome: revisao.nome, grupo_id: grupo.id };
  const aplicado = atual.nome === depois.nome && atual.grupo_id === depois.grupo_id;
  if (!aplicado && (atual.nome !== revisao.nome_anterior || atual.grupo_id !== revisao.grupo_id_anterior)) {
    throw new Error(`Item ${atual.id} mudou após a revisão; não será sobrescrito.`);
  }
  return { antes: atual, depois, aplicado, fontes: revisao.fontes, pendencias: revisao.pendencias };
});
const alteracoes = plano.filter((p) => !p.aplicado);
console.log(JSON.stringify({ revisados: plano.length, alteracoes: alteracoes.length, plano: plano.map((p) => ({ id: p.antes.id, codigo: p.antes.codigo_interno, ...p.depois, aplicado: p.aplicado, pendencias: p.pendencias })) }, null, 2));
if (process.argv.includes("--verify") && alteracoes.length) throw new Error("Há itens ainda não aplicados.");
if (process.argv.includes("--apply") && alteracoes.length) {
  const diretorio = "backups/revisao-sick";
  fs.mkdirSync(diretorio, { recursive: true });
  const arquivo = `${diretorio}/${new Date().toISOString().replace(/[:.]/g, "-")}.json`;
  fs.writeFileSync(arquivo, JSON.stringify({ tenant_id: tenantId, empresa_id: empresaId, fornecedor_id: manifesto.fornecedor_id, alteracoes }, null, 2), { flag: "wx" });
  console.log(`Backup antes da gravação: ${arquivo}`);
  let atualizados = 0;
  for (const p of alteracoes) {
    // Compare-and-set protege alterações concorrentes. Só nome e grupo mudam.
    let query = scope(db.from("itens").update(p.depois))
      .eq("id", p.antes.id).eq("codigo_interno", p.antes.codigo_interno)
      .eq("fornecedor_id", manifesto.fornecedor_id).eq("ativo", true)
      .eq("nome", p.antes.nome).eq("grupo_id", p.antes.grupo_id);
    query = p.antes.atualizado_em == null ? query.is("atualizado_em", null) : query.eq("atualizado_em", p.antes.atualizado_em);
    const { data, error: updateError } = await query.select("id,nome,grupo_id");
    if (updateError || data?.length !== 1) {
      throw new Error(`Interrompido no item ${p.antes.id}; ${atualizados} já atualizados. Backup: ${arquivo}. ${updateError?.message ?? "Conflito concorrente"}`);
    }
    if (data[0].nome !== p.depois.nome || data[0].grupo_id !== p.depois.grupo_id) throw new Error(`Verificação de retorno falhou: ${p.antes.id}`);
    atualizados++;
  }
  console.log(JSON.stringify({ atualizados, backup: arquivo }));
}
