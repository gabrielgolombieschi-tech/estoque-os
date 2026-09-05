/* eslint-disable @typescript-eslint/no-require-imports */
/*
 * Normaliza os 19 itens da ATI Brasil revisados na decisão D-029.
 * Sem --apply, apenas diagnostica. A descrição fiscal da NF-e não é alterada.
 */
const fs = require("fs");
const { createClient } = require("@supabase/supabase-js");

const TENANT_ID = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
const EMPRESA_ID = "f0e74f49-a127-46b4-901b-f7b37e43c690";
const FORNECEDOR_ID = 35;
const FORNECEDOR_NOME = "A T I BRASIL ARTIGOS TECNICOS INDUSTRIAIS LTDA";
const TOTAL_ESPERADO = 19;
const APPLY = process.argv.includes("--apply");

const env = {};
for (const line of fs.readFileSync(".env.local", "utf8").split(/\r?\n/)) {
  const i = line.indexOf("=");
  if (i <= 0) continue;
  env[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^['"]|['"]$/g, "");
}

const supabase = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const NOMES_APROVADOS = new Map([
  ["BMTR25X2000", "FUSO DE ROSCA TRAPEZOIDAL TR25X5 2000MM ROSCA DIREITA"],
  ["BMCH25B", "PORCA CILÍNDRICA TR25X5 BRONZE ROSCA DIREITA"],
  ["BQECRM3Z16R1", "ENGRENAGEM CÔNICA MÓDULO 3 Z16 RELAÇÃO 1:1"],
  ["BQECRM3Z30R1", "ENGRENAGEM CÔNICA MÓDULO 3 Z30 RELAÇÃO 1:1"],
  ["BQAFN01-30X55", "ANEL DE FIXAÇÃO Nº 1 30X55MM"],
  ["BMTR40X4000", "FUSO DE ROSCA TRAPEZOIDAL TR40X7 4000MM ROSCA DIREITA"],
  ["BMCHF40B", "PORCA CILÍNDRICA FLANGEADA TR40X7 BRONZE ROSCA DIREITA"],
  ["BQCHBAR20", "CHAVETA 20X12X1000MM H9XH11"],
  ["BQCHBAR25", "CHAVETA 25X14X1000MM H9XH11"],
  ["OP1000H150ATI", "CORREIA DENTADA PERFIL H 200 DENTES COMPRIMENTO 2540MM LARGURA 38,1MM"],
  ["BQCTA40-1X5MB", "CORRENTE DE ROLOS SIMPLES ASA 40-1"],
  ["BQEMA40-1CLB", "EMENDA PARA CORRENTE DE ROLOS SIMPLES ASA 40-1"],
  ["BQECASA40-1Z14", "ENGRENAGEM PARA CORRENTE SIMPLES ASA 40 Z14"],
  ["BQPS30-H150", "POLIA SINCRONIZADORA 30H150"],
  ["BQPS14-H150", "POLIA SINCRONIZADORA 14H150"],
  ["CI22HBM25AR", "PORCA CILÍNDRICA TR25X5 BRONZE LAMINADO ROSCA DIREITA"],
  ["ELGN.35532", "PINO INDEXADOR COM POSIÇÃO DE DESCANSO GN 617.1-10-AK COM PORCA"],
  ["BQEM08-B1CLB", "EMENDA PARA CORRENTE DE ROLOS SIMPLES 08B-1"],
  ["BQCT08-B1X5MB", "CORRENTE DE ROLOS SIMPLES 08B-1"],
]);

const GRUPO_POR_CODIGO_ITEM = new Map([
  ["BQCTA40-1X5MB", "CORRENTES_SIMPLES"],
  ["BQCT08-B1X5MB", "CORRENTES_SIMPLES"],
  ["BQEMA40-1CLB", "EMENDAS_SIMPLES"],
  ["BQEM08-B1CLB", "EMENDAS_SIMPLES"],
]);

async function buscarDados() {
  const { data: fornecedores, error: fornecedorError } = await supabase
    .from("fornecedores")
    .select("id,nome,ativo")
    .eq("tenant_id", TENANT_ID)
    .eq("empresa_id", EMPRESA_ID)
    .eq("id", FORNECEDOR_ID)
    .eq("nome", FORNECEDOR_NOME);
  if (fornecedorError) throw fornecedorError;
  if (fornecedores.length !== 1) {
    throw new Error(`Proteção de escopo: fornecedor ATI esperado não foi localizado de forma inequívoca.`);
  }

  const { data: itens, error: itensError } = await supabase
    .from("itens")
    .select("id,codigo_interno,nome,grupo_id,ativo")
    .eq("tenant_id", TENANT_ID)
    .eq("empresa_id", EMPRESA_ID)
    .eq("fornecedor_id", FORNECEDOR_ID)
    .order("id");
  if (itensError) throw itensError;

  const { data: grupos, error: gruposError } = await supabase
    .from("item_grupos")
    .select("id,codigo,nome")
    .eq("tenant_id", TENANT_ID)
    .eq("empresa_id", EMPRESA_ID)
    .eq("ativo", true)
    .in("codigo", ["CORRENTES_SIMPLES", "EMENDAS_SIMPLES"]);
  if (gruposError) throw gruposError;
  return { itens, grupos };
}

async function atualizar(alteracoes) {
  for (const item of alteracoes) {
    const agora = new Date().toISOString();
    const { data, error } = await supabase
      .from("itens")
      .update({ nome: item.nomeProposto, grupo_id: item.grupoIdProposto, atualizado_em: agora })
      .eq("id", item.id)
      .eq("tenant_id", TENANT_ID)
      .eq("empresa_id", EMPRESA_ID)
      .eq("fornecedor_id", FORNECEDOR_ID)
      .eq("nome", item.nomeAtual)
      .select("id");
    if (error) throw new Error(`Item ${item.id}: ${error.message}`);
    if ((data ?? []).length !== 1) {
      throw new Error(`Item ${item.id}: o cadastro mudou após o diagnóstico; correção interrompida.`);
    }
  }
}

async function main() {
  const { itens, grupos } = await buscarDados();
  if (itens.length !== TOTAL_ESPERADO || NOMES_APROVADOS.size !== TOTAL_ESPERADO) {
    throw new Error(
      `Proteção de escopo: esperados ${TOTAL_ESPERADO} itens e propostas; encontrados ${itens.length} itens e ${NOMES_APROVADOS.size} propostas.`
    );
  }

  const grupoPorCodigo = new Map(grupos.map((grupo) => [grupo.codigo, grupo]));
  if (!grupoPorCodigo.has("CORRENTES_SIMPLES") || !grupoPorCodigo.has("EMENDAS_SIMPLES")) {
    throw new Error("Grupos de correntes e emendas não foram localizados no tenant/empresa.");
  }

  const codigosEncontrados = new Set(itens.map((item) => item.codigo_interno));
  const semProposta = itens.filter((item) => !NOMES_APROVADOS.has(item.codigo_interno));
  const propostasSemItem = [...NOMES_APROVADOS.keys()].filter((codigo) => !codigosEncontrados.has(codigo));
  if (semProposta.length || propostasSemItem.length) {
    console.log(JSON.stringify({ semProposta, propostasSemItem }, null, 2));
    throw new Error("A lista de códigos ATI mudou; nenhuma alteração foi aplicada.");
  }

  const propostas = itens.map((item) => {
    const codigoGrupo = GRUPO_POR_CODIGO_ITEM.get(item.codigo_interno);
    return {
      id: item.id,
      codigo: item.codigo_interno,
      nomeAtual: item.nome,
      nomeProposto: NOMES_APROVADOS.get(item.codigo_interno),
      grupoIdAtual: item.grupo_id,
      grupoIdProposto: codigoGrupo ? grupoPorCodigo.get(codigoGrupo).id : item.grupo_id,
    };
  });

  const nomesRepetidos = [...propostas.reduce((map, item) => {
    const chave = item.nomeProposto.toUpperCase();
    map.set(chave, (map.get(chave) ?? 0) + 1);
    return map;
  }, new Map()).entries()].filter(([, quantidade]) => quantidade > 1);
  const pedidosDepois = propostas.filter((item) => /\bPEDIDO\b|\b\d{4}\s*\/\s*\d+\b/i.test(item.nomeProposto));
  if (nomesRepetidos.length || pedidosDepois.length) {
    console.log(JSON.stringify({ nomesRepetidos, pedidosDepois }, null, 2));
    throw new Error("A pré-validação das propostas ATI falhou; nenhuma alteração foi aplicada.");
  }

  const alteracoes = propostas.filter(
    (item) => item.nomeAtual !== item.nomeProposto || Number(item.grupoIdAtual) !== Number(item.grupoIdProposto)
  );
  const resumo = {
    modo: APPLY ? "APLICAR" : "DIAGNOSTICO",
    totalAti: propostas.length,
    alteracoesNecessarias: alteracoes.length,
    nomesAlterados: alteracoes.filter((item) => item.nomeAtual !== item.nomeProposto).length,
    gruposAlterados: alteracoes.filter((item) => Number(item.grupoIdAtual) !== Number(item.grupoIdProposto)).length,
    nomesComPedidoAntes: propostas.filter((item) => /\bPEDIDO\b/i.test(item.nomeAtual)).length,
    nomesComPedidoDepois: pedidosDepois.length,
    nomesRepetidosDepois: nomesRepetidos.length,
    alteracoes,
  };
  console.log(JSON.stringify(resumo, null, 2));

  if (!APPLY || alteracoes.length === 0) return;
  await atualizar(alteracoes);
  console.log(JSON.stringify({ aplicado: true, itensAtualizados: alteracoes.length }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
