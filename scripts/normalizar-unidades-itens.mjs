import fs from "node:fs";
import path from "node:path";
import { createClient } from "@supabase/supabase-js";
import { normalizarUnidadesNoNome } from "../lib/itens/normalizacaoNome.ts";

const APPLY = process.argv.includes("--apply");
const SUMMARY_ONLY = process.argv.includes("--summary-only");
const TENANT_ID = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
const EMPRESA_ID = "f0e74f49-a127-46b4-901b-f7b37e43c690";
const PAGE_SIZE = 1000;

function loadEnvFile(fileName) {
  const file = path.resolve(fileName);
  if (!fs.existsSync(file)) return;
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    if (!/^[A-Za-z_][A-Za-z0-9_]*=/.test(line)) continue;
    const index = line.indexOf("=");
    const key = line.slice(0, index).trim();
    if (process.env[key]) continue;
    process.env[key] = line.slice(index + 1).trim().replace(/^(["'])(.*)\1$/, "$2");
  }
}

loadEnvFile(".env.local");
loadEnvFile(".env");

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !serviceRoleKey) {
  throw new Error("NEXT_PUBLIC_SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são obrigatórias.");
}

const supabase = createClient(url, serviceRoleKey, { auth: { persistSession: false } });

async function listarItensDoEscopo() {
  const itens = [];
  for (let inicio = 0; ; inicio += PAGE_SIZE) {
    const { data, error } = await supabase
      .from("itens")
      .select("id,codigo_interno,nome")
      .eq("tenant_id", TENANT_ID)
      .eq("empresa_id", EMPRESA_ID)
      .not("nome", "is", null)
      .order("id")
      .range(inicio, inicio + PAGE_SIZE - 1);
    if (error) throw error;
    itens.push(...(data ?? []));
    if ((data ?? []).length < PAGE_SIZE) return itens;
  }
}

async function main() {
  const itens = await listarItensDoEscopo();
  const alteracoes = itens
    .map((item) => ({
      id: item.id,
      codigo: item.codigo_interno,
      nome_anterior: item.nome,
      nome_normalizado: normalizarUnidadesNoNome(item.nome),
    }))
    .filter((item) => item.nome_normalizado !== item.nome_anterior);

  const resumo = {
    modo: APPLY ? "APLICAR" : "DIAGNOSTICO",
    tenant_id: TENANT_ID,
    empresa_id: EMPRESA_ID,
    itens_analisados: itens.length,
    itens_a_corrigir: alteracoes.length,
    item_exemplo_atual: itens.find((item) => item.codigo_interno === "3RT10541AF36") ?? null,
    item_exemplo_pendente: alteracoes.find((item) => item.codigo === "3RT10541AF36") ?? null,
  };
  console.log(JSON.stringify(SUMMARY_ONLY ? resumo : { ...resumo, alteracoes }, null, 2));

  if (!APPLY) return;

  let atualizados = 0;
  for (const item of alteracoes) {
    const { data, error } = await supabase
      .from("itens")
      .update({ nome: item.nome_normalizado })
      .eq("tenant_id", TENANT_ID)
      .eq("empresa_id", EMPRESA_ID)
      .eq("id", item.id)
      .eq("nome", item.nome_anterior)
      .select("id");
    if (error) throw new Error(`Item ${item.id}: ${error.message}`);
    if ((data ?? []).length !== 1) {
      throw new Error(`Item ${item.id}: o nome mudou depois do diagnóstico; nenhuma alteração foi aplicada.`);
    }
    atualizados += 1;
  }

  console.log(JSON.stringify({ resultado: "concluido", itens_atualizados: atualizados }, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.stack : error);
  process.exit(1);
});
