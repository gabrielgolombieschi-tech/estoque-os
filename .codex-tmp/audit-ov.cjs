const { createClient } = require("@supabase/supabase-js");

async function main() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("Credenciais Supabase ausentes.");

  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: vendas, error: vendasError } = await db
    .from("ordens_servico")
    .select("id,tenant_id,empresa_id,codigo,status,status_fluxo,cliente_nome,pedido_compra,data_abertura")
    .eq("tipo_documento", "OV")
    .order("id", { ascending: false });
  if (vendasError) throw vendasError;

  const ids = (vendas ?? []).map((row) => Number(row.id)).filter((id) => Number.isInteger(id) && id > 0);
  const [itensRes, pendenciasRes, pedidosRes] = ids.length
    ? await Promise.all([
        db.from("os_itens").select("id,os_id,item_id,quantidade,quantidade_baixada").in("os_id", ids),
        db.schema("m").from("compra_pendencia").select("id,origem_os_id,item_id,status,quantidade,origem_tipo").in("origem_os_id", ids).is("deleted_at", null),
        db.schema("m").from("pedido_compra_item").select("id,pedido_compra_id,origem_os_id,item_id,quantidade,quantidade_recebida").in("origem_os_id", ids).is("deleted_at", null),
      ])
    : [{ data: [], error: null }, { data: [], error: null }, { data: [], error: null }];
  if (itensRes.error) throw itensRes.error;
  if (pendenciasRes.error) throw pendenciasRes.error;
  if (pedidosRes.error) throw pedidosRes.error;

  const byVenda = new Map(ids.map((id) => [id, { itens: 0, faltantes: 0, pendencias: 0, itensPedido: 0 }]));
  for (const item of itensRes.data ?? []) {
    const agg = byVenda.get(Number(item.os_id));
    if (!agg) continue;
    agg.itens += 1;
    if (Number(item.quantidade ?? 0) > Number(item.quantidade_baixada ?? 0)) agg.faltantes += 1;
  }
  for (const row of pendenciasRes.data ?? []) {
    const agg = byVenda.get(Number(row.origem_os_id));
    if (agg && ["PENDENTE", "EM_PEDIDO"].includes(String(row.status))) agg.pendencias += 1;
  }
  for (const row of pedidosRes.data ?? []) {
    const agg = byVenda.get(Number(row.origem_os_id));
    if (agg) agg.itensPedido += 1;
  }

  const rows = (vendas ?? []).map((row) => ({
    id: row.id,
    codigo: row.codigo,
    status: row.status_fluxo ?? row.status,
    cliente: row.cliente_nome,
    oc_cliente: row.pedido_compra,
    ...byVenda.get(Number(row.id)),
  }));

  console.log(JSON.stringify({
    resumo: {
      ovs: rows.length,
      em_andamento: rows.filter((row) => row.status === "em_andamento").length,
      com_itens: rows.filter((row) => row.itens > 0).length,
      com_faltantes: rows.filter((row) => row.faltantes > 0).length,
      com_pendencias: rows.filter((row) => row.pendencias > 0).length,
      com_pedido_compra: rows.filter((row) => row.itensPedido > 0).length,
      com_oc_cliente: rows.filter((row) => String(row.oc_cliente ?? "").trim()).length,
    },
    vendas: rows,
  }, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
