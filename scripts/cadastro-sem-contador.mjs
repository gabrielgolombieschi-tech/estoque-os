import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { createClient } from "@supabase/supabase-js";

function loadEnvFile(file) {
  if (!fs.existsSync(file)) return;
  for (const rawLine of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const separator = line.indexOf("=");
    if (separator < 1) continue;
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
}

loadEnvFile(path.resolve(".env.local"));
loadEnvFile(path.resolve(".env"));

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !serviceKey) throw new Error("NEXT_PUBLIC_SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são obrigatórias.");

const supabase = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function normalizeName(value) {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function municipalityUf(row) {
  return row?.microrregiao?.mesorregiao?.UF?.sigla
    ?? row?.["regiao-imediata"]?.["regiao-intermediaria"]?.UF?.sigla
    ?? null;
}

async function must(label, promise) {
  const result = await promise;
  if (result.error) throw new Error(`${label}: ${result.error.message}`);
  return result.data;
}

async function exactCount(label, query) {
  const result = await query;
  if (result.error) throw new Error(`${label}: ${result.error.message}`);
  return result.count ?? 0;
}

async function loadMunicipalities() {
  const response = await fetch("https://servicodados.ibge.gov.br/api/v1/localidades/municipios?orderBy=nome");
  if (!response.ok) throw new Error(`IBGE respondeu HTTP ${response.status}.`);
  const raw = await response.json();
  const now = new Date().toISOString();
  const rows = raw.map((row) => ({
    codigo_ibge: String(row.id),
    nome: row.nome,
    nome_normalizado: normalizeName(row.nome),
    uf: municipalityUf(row),
    fonte: "IBGE API Localidades",
    fonte_versao: now.slice(0, 10),
    atualizado_em: now,
  }));
  const invalid = rows.filter((row) => !/^\d{7}$/.test(row.codigo_ibge) || !/^[A-Z]{2}$/.test(row.uf ?? ""));
  if (invalid.length) throw new Error(`IBGE retornou ${invalid.length} município(s) sem código/UF válido.`);
  for (let index = 0; index < rows.length; index += 500) {
    await must("carga de municípios IBGE", supabase
      .from("municipios_ibge")
      .upsert(rows.slice(index, index + 500), { onConflict: "codigo_ibge" }));
  }
  return rows.length;
}

async function tenantIds() {
  const explicit = process.argv.find((value) => value.startsWith("--tenant="))?.split("=")[1];
  if (explicit) return [explicit];
  const rows = await must("leitura de tenants", supabase.from("tenants").select("id").order("id"));
  return rows.map((row) => row.id);
}

async function runTenant(tenantId) {
  const dataReferencia = new Date().toISOString().slice(0, 10);
  const municipioLegado = await must("correção do município legado", supabase.rpc("fn_clientes_ibge_legado_codigo_cidade", {
    p_tenant_id: tenantId,
    p_data_referencia: dataReferencia,
    p_aplicar: true,
  }));
  const clientesPrevia = await must("prévia de clientes", supabase.rpc("fn_clientes_cadastro_sem_contador", {
    p_tenant_id: tenantId,
    p_data_referencia: dataReferencia,
    p_aplicar: false,
  }));
  const clientesAplicado = await must("saneamento de clientes", supabase.rpc("fn_clientes_cadastro_sem_contador", {
    p_tenant_id: tenantId,
    p_data_referencia: dataReferencia,
    p_aplicar: true,
  }));

  const lotes = [];
  for (let passagem = 1; passagem <= 2; passagem += 1) {
    const loteId = await must(`preparação do backfill ${passagem}`, supabase.rpc("fn_fiscal_xml_backfill_preparar", {
      p_tenant_id: tenantId,
      p_data_referencia: dataReferencia,
    }));
    const aplicado = await must(`aplicação do backfill ${passagem}`, supabase.rpc("fn_fiscal_xml_backfill_aplicar", {
      p_lote_id: loteId,
    }));
    const lote = await must(`conferência do lote ${passagem}`, supabase
      .from("fiscal_backfill_lote")
      .select("*")
      .eq("id", loteId)
      .single());
    const pendencias = await must(`pendências do lote ${passagem}`, supabase
      .from("fiscal_backfill_item")
      .select("item_id,empresa_id,documentos_evidencia,origem_antes,origem_proposta,origem_conflito,ncm_antes,ncm_proposta,ncm_conflito,cest_antes,cest_proposta,cest_conflito,unidade_antes,unidade_proposta,unidade_conflito")
      .eq("lote_id", loteId)
      .or("origem_conflito.eq.true,ncm_conflito.eq.true,cest_conflito.eq.true,unidade_conflito.eq.true,documentos_evidencia.eq.0"));
    const pendenciasResumo = {
      sem_documento: await exactCount("itens sem documento", supabase.from("fiscal_backfill_item").select("item_id", { count: "exact", head: true }).eq("lote_id", loteId).eq("documentos_evidencia", 0)),
      origem_sem_valor: await exactCount("origem pendente", supabase.from("fiscal_backfill_item").select("item_id", { count: "exact", head: true }).eq("lote_id", loteId).is("origem_antes", null)),
      origem_conflito: await exactCount("origem conflitante", supabase.from("fiscal_backfill_item").select("item_id", { count: "exact", head: true }).eq("lote_id", loteId).eq("origem_conflito", true)),
      ncm_sem_valor: await exactCount("NCM pendente", supabase.from("fiscal_backfill_item").select("item_id", { count: "exact", head: true }).eq("lote_id", loteId).is("ncm_antes", null)),
      ncm_conflito: await exactCount("NCM conflitante", supabase.from("fiscal_backfill_item").select("item_id", { count: "exact", head: true }).eq("lote_id", loteId).eq("ncm_conflito", true)),
      cest_sem_valor: await exactCount("CEST pendente", supabase.from("fiscal_backfill_item").select("item_id", { count: "exact", head: true }).eq("lote_id", loteId).is("cest_antes", null)),
      cest_conflito: await exactCount("CEST conflitante", supabase.from("fiscal_backfill_item").select("item_id", { count: "exact", head: true }).eq("lote_id", loteId).eq("cest_conflito", true)),
      unidade_sem_valor: await exactCount("unidade pendente", supabase.from("fiscal_backfill_item").select("item_id", { count: "exact", head: true }).eq("lote_id", loteId).is("unidade_antes", null)),
      unidade_conflito: await exactCount("unidade conflitante", supabase.from("fiscal_backfill_item").select("item_id", { count: "exact", head: true }).eq("lote_id", loteId).eq("unidade_conflito", true)),
    };
    lotes.push({ passagem, lote, aplicado, pendencias_resumo: pendenciasResumo, pendencias });
  }

  return { tenant_id: tenantId, municipio_legado: municipioLegado, clientes_previa: clientesPrevia, clientes_aplicado: clientesAplicado, lotes };
}

const municipios = await loadMunicipalities();
const tenants = await tenantIds();
const resultados = [];
for (const tenantId of tenants) resultados.push(await runTenant(tenantId));

const compact = process.argv.includes("--compact");
const saida = compact
  ? resultados.map((resultado) => ({
      ...resultado,
      lotes: resultado.lotes.map((lote) => ({
        passagem: lote.passagem,
        lote: lote.lote,
        aplicado: lote.aplicado,
        pendencias_resumo: lote.pendencias_resumo,
      })),
    }))
  : resultados;

console.log(JSON.stringify({
  executado_em: new Date().toISOString(),
  fonte_municipios: "IBGE API Localidades",
  municipios_carregados: municipios,
  resultados: saida,
}, null, 2));
