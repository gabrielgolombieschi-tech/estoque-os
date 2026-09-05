/* eslint-disable @typescript-eslint/no-require-imports */
/*
 * Normaliza os cinco cabos HELUKABEL PUR-JZ da NF de entrada 2268.
 * Sem --apply, apenas diagnostica. A descrição fiscal da NF-e não é alterada.
 */
const fs = require("fs");
const { createClient } = require("@supabase/supabase-js");

const TENANT_ID = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
const EMPRESA_ID = "f0e74f49-a127-46b4-901b-f7b37e43c690";
const FORNECEDOR_ID = 700;
const GRUPO_ID = 165;
const APPLY = process.argv.includes("--apply");

const PROPOSTAS = new Map([
  [3734, { codigo: "18043996", nome: "CABO DE CONTROLE FLEXÍVEL PUR-JZ 12G0,5MM² 300/500V ISOLAÇÃO PVC CAPA PUR SEM BLINDAGEM" }],
  [3735, { codigo: "18043997", nome: "CABO DE CONTROLE FLEXÍVEL PUR-JZ 20G0,5MM² 300/500V ISOLAÇÃO PVC CAPA PUR SEM BLINDAGEM" }],
  [3736, { codigo: "18043998", nome: "CABO DE CONTROLE FLEXÍVEL PUR-JZ 25G0,5MM² 300/500V ISOLAÇÃO PVC CAPA PUR SEM BLINDAGEM" }],
  [3737, { codigo: "18043999", nome: "CABO DE CONTROLE FLEXÍVEL PUR-JZ 35G0,5MM² 300/500V ISOLAÇÃO PVC CAPA PUR SEM BLINDAGEM" }],
  [3738, { codigo: "18044000", nome: "CABO DE CONTROLE FLEXÍVEL PUR-JZ 21G1MM² 300/500V ISOLAÇÃO PVC CAPA PUR SEM BLINDAGEM" }],
]);

const env = {};
for (const line of fs.readFileSync(".env.local", "utf8").split(/\r?\n/)) {
  const i = line.indexOf("=");
  if (i <= 0) continue;
  env[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^['"]|['"]$/g, "");
}

const supabase = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

async function main() {
  const ids = [...PROPOSTAS.keys()];
  const { data: itens, error: itensError } = await supabase
    .from("itens")
    .select("id,codigo_interno,nome,grupo_id,fornecedor_id,unidade_medida,ativo")
    .eq("tenant_id", TENANT_ID)
    .eq("empresa_id", EMPRESA_ID)
    .eq("fornecedor_id", FORNECEDOR_ID)
    .in("id", ids)
    .order("id");
  if (itensError) throw itensError;

  if (itens.length !== PROPOSTAS.size) {
    throw new Error(`Proteção de escopo: esperados ${PROPOSTAS.size} itens, encontrados ${itens.length}.`);
  }

  const alteracoes = itens.map((item) => {
    const proposta = PROPOSTAS.get(item.id);
    if (!proposta || item.codigo_interno !== proposta.codigo) {
      throw new Error(`Proteção de escopo: o item ${item.id} não corresponde ao código esperado.`);
    }
    if (item.unidade_medida !== "M" || item.ativo !== true) {
      throw new Error(`Proteção de escopo: unidade ou situação inesperada no item ${item.id}.`);
    }
    return {
      id: item.id,
      codigo: item.codigo_interno,
      nomeAtual: item.nome,
      nomeProposto: proposta.nome,
      grupoIdAtual: item.grupo_id,
      grupoIdProposto: GRUPO_ID,
    };
  }).filter((item) => item.nomeAtual !== item.nomeProposto || item.grupoIdAtual !== item.grupoIdProposto);

  console.log(JSON.stringify({
    modo: APPLY ? "APLICAR" : "DIAGNOSTICO",
    totalValidado: itens.length,
    alteracoesNecessarias: alteracoes.length,
    alteracoes,
  }, null, 2));

  if (!APPLY) return;
  for (const item of alteracoes) {
    const { data, error } = await supabase
      .from("itens")
      .update({ nome: item.nomeProposto, grupo_id: item.grupoIdProposto, atualizado_em: new Date().toISOString() })
      .eq("tenant_id", TENANT_ID)
      .eq("empresa_id", EMPRESA_ID)
      .eq("fornecedor_id", FORNECEDOR_ID)
      .eq("id", item.id)
      .eq("codigo_interno", item.codigo)
      .eq("nome", item.nomeAtual)
      .select("id")
      .single();
    if (error || !data) throw new Error(`Item ${item.id}: ${error?.message ?? "não atualizado"}`);
  }
  console.log(JSON.stringify({ aplicado: true, itensAtualizados: alteracoes.length }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
