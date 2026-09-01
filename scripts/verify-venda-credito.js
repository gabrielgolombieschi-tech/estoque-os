/* eslint-disable no-console */
const { Client } = require("pg");
const { createClient } = require("@supabase/supabase-js");

async function count(label, query) {
  const { count: total, error } = await query;
  if (error) throw new Error(`${label}: ${error.message || error.code || JSON.stringify(error)}`);
  return total ?? 0;
}

async function verifyViaApi(tenantId, empresaId) {
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) throw new Error("Credenciais Supabase ausentes.");
  const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const scope = (query) => query.eq("tenant_id", tenantId).eq("empresa_id", empresaId);
  const [unidades, portobello, osSemCliente, docsPendentes, creditosSemCliente, creditos, statusRows, origemRows] = await Promise.all([
    count("cliente_unidades", scope(supabase.from("cliente_unidades").select("id", { count: "exact", head: true }))),
    count("portobello", scope(supabase.from("cliente_unidades").select("id", { count: "exact", head: true })).eq("cliente_id", 1)),
    count("ordens_servico", scope(supabase.from("ordens_servico").select("id", { count: "exact", head: true })).is("cliente_id", null)),
    count("documentos_pendentes", scope(supabase.schema("r").from("r_clientes_documento_pendencia").select("cliente_id", { count: "exact", head: true }))),
    count("gestao_cobranca_os", scope(supabase.schema("f").from("gestao_cobranca_os").select("id", { count: "exact", head: true })).is("deleted_at", null).is("cliente_id", null)),
    count("r_venda_credito", scope(supabase.schema("r").from("r_venda_credito").select("credito_id", { count: "exact", head: true }))),
    scope(supabase.schema("f").from("gestao_cobranca_os").select("status,valor_estimado,valor_confirmado")).is("deleted_at", null),
    scope(supabase.schema("f").from("gestao_cobranca_os").select("origem")).is("deleted_at", null),
  ]);
  if (statusRows.error) throw new Error(`status: ${statusRows.error.message || statusRows.error.code || JSON.stringify(statusRows.error)}`);
  if (origemRows.error) throw new Error(`origens: ${origemRows.error.message || origemRows.error.code || JSON.stringify(origemRows.error)}`);
  const statusMap = new Map();
  for (const row of statusRows.data ?? []) {
    const current = statusMap.get(row.status) ?? { status: row.status, qtd: 0, valor: 0 };
    current.qtd += 1;
    current.valor += Number(row.valor_confirmado ?? row.valor_estimado ?? 0);
    statusMap.set(row.status, current);
  }
  const origemMap = new Map();
  for (const row of origemRows.data ?? []) origemMap.set(row.origem, (origemMap.get(row.origem) ?? 0) + 1);
  return {
    resumo: { unidades, portobello, os_sem_cliente: osSemCliente, docs_pendentes: docsPendentes, creditos_sem_cliente: creditosSemCliente, creditos },
    status: Array.from(statusMap.values()),
    origens: Array.from(origemMap, ([origem, qtd]) => ({ origem, qtd })),
    via: "supabase-api",
  };
}

async function main() {
  const tenantId = process.env.VENDA_CREDITO_TENANT_ID;
  const empresaId = process.env.VENDA_CREDITO_EMPRESA_ID;
  if (!process.env.DATABASE_URL || !tenantId || !empresaId) {
    throw new Error("Informe DATABASE_URL, VENDA_CREDITO_TENANT_ID e VENDA_CREDITO_EMPRESA_ID.");
  }

  const db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  try {
    await db.connect();
    const params = [tenantId, empresaId];
    const resumo = await db.query(
      `select
        (select count(*) from public.cliente_unidades where tenant_id=$1 and empresa_id=$2) unidades,
        (select count(*) from public.cliente_unidades where tenant_id=$1 and empresa_id=$2 and cliente_id=1) portobello,
        (select count(*) from public.ordens_servico where tenant_id=$1 and empresa_id=$2 and cliente_id is null) os_sem_cliente,
        (select count(*) from r.r_clientes_documento_pendencia where tenant_id=$1 and empresa_id=$2) docs_pendentes,
        (select count(*) from f.gestao_cobranca_os where tenant_id=$1 and empresa_id=$2 and deleted_at is null and cliente_id is null) creditos_sem_cliente,
        (select count(*) from r.r_venda_credito where tenant_id=$1 and empresa_id=$2) creditos`,
      params
    );
    const status = await db.query(
      `select status,count(*)::int qtd,round(sum(coalesce(valor_confirmado,valor_estimado,0)),2) valor
       from f.gestao_cobranca_os
       where tenant_id=$1 and empresa_id=$2 and deleted_at is null
       group by status order by status`,
      params
    );
    const origens = await db.query(
      `select origem,count(*)::int qtd
       from f.gestao_cobranca_os
       where tenant_id=$1 and empresa_id=$2 and deleted_at is null
       group by origem order by origem`,
      params
    );
    const migrations = await db.query(
      "select version from supabase_migrations.schema_migrations where version like '202608291%' order by version"
    );
    console.log(JSON.stringify({ resumo: resumo.rows[0], status: status.rows, origens: origens.rows, migrations: migrations.rows }, null, 2));
  } catch (error) {
    console.warn(`Conexão PostgreSQL direta indisponível (${error.message}); validando pela API.`);
    console.log(JSON.stringify(await verifyViaApi(tenantId, empresaId), null, 2));
  } finally {
    await db.end();
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
