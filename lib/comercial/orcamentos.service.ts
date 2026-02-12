import { applyTenantEmpresa } from "@/lib/db/scopes";
import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  ClienteLookupRow,
  ConfigOrcamentoRow,
  ItemLookupRow,
  OrcamentoItemRow,
  OrcamentoListaRow,
  OrcamentoRow,
  OrcamentoStatus,
  UsuarioLookupRow,
} from "@/lib/comercial/types";

export type ListOrcamentosFilters = {
  tenantId: string;
  empresaId: string;
  q?: string;
  status?: "TODOS" | OrcamentoStatus;
  from?: string;
  to?: string;
  page?: number;
  pageSize?: number;
};

export async function listOrcamentos(
  supabase: SupabaseClient,
  filters: ListOrcamentosFilters
): Promise<{ rows: OrcamentoListaRow[]; count: number }> {
  const page = Math.max(1, Number(filters.page ?? 1));
  const pageSize = Math.min(200, Math.max(1, Number(filters.pageSize ?? 50)));
  const fromIdx = (page - 1) * pageSize;
  const toIdx = fromIdx + pageSize - 1;

  let query = applyTenantEmpresa(
    supabase
      .schema("r")
      .from("r_orcamento_lista")
      .select(
        [
          "id",
          "codigo",
          "numero",
          "versao",
          "status",
          "emissao_date",
          "titulo",
          "cliente_id",
          "cliente_nome",
          "vendedor_usuario_id",
          "vendedor_nome",
          "condicao_pagamento_id",
          "condicao_pagamento_nome",
          "desconto_global_percent",
          "acrescimo_cond_pag_percent",
          "valor_frete",
          "total_produtos",
          "total_servicos",
          "total_bruto",
          "total_desconto_global",
          "total_liquido",
          "created_at",
          "updated_at",
        ].join(","),
        { count: "exact" }
      )
      .order("emissao_date", { ascending: false })
      .order("numero", { ascending: false })
      .range(fromIdx, toIdx),
    filters.tenantId,
    filters.empresaId
  );

  const status = filters.status ?? "TODOS";
  if (status !== "TODOS") query = query.eq("status", status);

  const from = String(filters.from ?? "").trim();
  const to = String(filters.to ?? "").trim();
  if (from) query = query.gte("emissao_date", from);
  if (to) query = query.lte("emissao_date", to);

  const term = String(filters.q ?? "").trim();
  if (term) {
    const like = `%${term}%`;
    query = query.or(`codigo.ilike.${like},titulo.ilike.${like},cliente_nome.ilike.${like}`);
  }

  const { data, error, count } = await query.returns<OrcamentoListaRow[]>();
  if (error) throw error;
  return { rows: (data ?? []) as OrcamentoListaRow[], count: typeof count === "number" ? count : 0 };
}

export async function getOrcamento(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; id: string }
): Promise<{ orcamento: OrcamentoRow; itens: OrcamentoItemRow[] }> {
  const { data: orc, error: oErr } = await applyTenantEmpresa(
    supabase
      .schema("m")
      .from("orcamento")
      .select("*")
      .eq("id", params.id)
      .is("deleted_at", null)
      .maybeSingle<OrcamentoRow>(),
    params.tenantId,
    params.empresaId
  );

  if (oErr) throw oErr;
  if (!orc?.id) throw new Error("Orçamento não encontrado.");

  const { data: itens, error: iErr } = await applyTenantEmpresa(
    supabase
      .schema("r")
      .from("r_orcamento_itens")
      .select(
        [
          "id",
          "orcamento_id",
          "seq",
          "item_id",
          "item_tipo",
          "item_nome",
          "unidade",
          "quantidade",
          "valor_unitario",
          "desconto_item_percent",
          "acrescimo_cond_pag_percent",
          "desconto_global_percent",
          "valor_total_bruto",
          "valor_total",
          "valor_unitario_liquido",
          "created_at",
          "updated_at",
        ].join(",")
      )
      .eq("orcamento_id", params.id)
      .order("seq", { ascending: true }),
    params.tenantId,
    params.empresaId
  ).returns<OrcamentoItemRow[]>();

  if (iErr) throw iErr;
  return { orcamento: orc as OrcamentoRow, itens: (itens ?? []) as OrcamentoItemRow[] };
}

export async function createOrcamento(
  supabase: SupabaseClient,
  params: {
    tenantId: string;
    empresaId: string;
    titulo: string;
    clienteId: number;
    vendedorUsuarioId: string;
    condicaoPagamentoId?: string | null;
  }
): Promise<string> {
  const payload: Pick<
    OrcamentoRow,
    "tenant_id" | "empresa_id" | "titulo" | "cliente_id" | "vendedor_usuario_id" | "condicao_pagamento_id"
  > = {
    tenant_id: params.tenantId,
    empresa_id: params.empresaId,
    titulo: params.titulo,
    cliente_id: params.clienteId,
    vendedor_usuario_id: params.vendedorUsuarioId,
    condicao_pagamento_id: params.condicaoPagamentoId ?? null,
  };

  const { data, error } = await supabase
    .schema("m")
    .from("orcamento")
    .insert(payload)
    .select("id")
    .single<{ id: string }>();

  if (error) throw error;
  if (!data?.id) throw new Error("Falha ao criar orçamento.");
  return String(data.id);
}

export async function updateOrcamento(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; id: string; patch: Partial<OrcamentoRow> }
) {
  const patch: Partial<OrcamentoRow> & { updated_at: string } = {
    ...params.patch,
    updated_at: new Date().toISOString(),
  };
  const { error } = await applyTenantEmpresa(
    supabase.schema("m").from("orcamento").update(patch).eq("id", params.id),
    params.tenantId,
    params.empresaId
  );
  if (error) throw error;
}

export async function addItem(
  supabase: SupabaseClient,
  params: {
    tenantId: string;
    empresaId: string;
    orcamentoId: string;
    itemId: number;
    quantidade: number;
    valorUnitario: number;
    descontoItemPercent: number;
  }
): Promise<string> {
  const payload: {
    tenant_id: string;
    empresa_id: string;
    orcamento_id: string;
    item_id: number;
    quantidade: number;
    valor_unitario: number;
    desconto_item_percent: number;
  } = {
    tenant_id: params.tenantId,
    empresa_id: params.empresaId,
    orcamento_id: params.orcamentoId,
    item_id: params.itemId,
    quantidade: params.quantidade,
    valor_unitario: params.valorUnitario,
    desconto_item_percent: params.descontoItemPercent,
  };

  const { data, error } = await applyTenantEmpresa(
    supabase.schema("m").from("orcamento_item").insert(payload).select("id").single<{ id: string }>(),
    params.tenantId,
    params.empresaId
  );

  if (error) throw error;
  if (!data?.id) throw new Error("Falha ao inserir item.");
  return String(data.id);
}

export async function updateItem(
  supabase: SupabaseClient,
  params: {
    tenantId: string;
    empresaId: string;
    id: string;
    patch: Partial<Pick<OrcamentoItemRow, "quantidade" | "valor_unitario" | "desconto_item_percent">>;
  }
) {
  const patch: Partial<OrcamentoItemRow> & { updated_at: string } = {
    ...params.patch,
    updated_at: new Date().toISOString(),
  };
  const { error } = await applyTenantEmpresa(
    supabase.schema("m").from("orcamento_item").update(patch).eq("id", params.id),
    params.tenantId,
    params.empresaId
  );
  if (error) throw error;
}

export async function deleteItem(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; id: string }
) {
  const { error } = await applyTenantEmpresa(
    supabase
      .schema("m")
      .from("orcamento_item")
      .update({ deleted_at: new Date().toISOString(), updated_at: new Date().toISOString() })
      .eq("id", params.id),
    params.tenantId,
    params.empresaId
  );
  if (error) throw error;
}

export async function finalizarOrcamento(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; id: string }
) {
  await updateOrcamento(supabase, { ...params, patch: { status: "FINALIZADO" } });
}

export async function cancelarOrcamento(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; id: string }
) {
  await updateOrcamento(supabase, { ...params, patch: { status: "CANCELADO" } });
}

export async function deleteOrcamento(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; id: string }
) {
  await updateOrcamento(supabase, { ...params, patch: { deleted_at: new Date().toISOString() } });
}

export async function listCondicoesPagamentoAtivas(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string }
): Promise<Array<{ id: string; nome: string | null; acrescimo_percent: number | string | null }>> {
  const { data, error } = await applyTenantEmpresa(
    supabase
      .schema("c")
      .from("condicao_pagamento")
      .select("id,nome,acrescimo_percent")
      .eq("ativo", true)
      .is("deleted_at", null)
      .order("nome", { ascending: true })
      .limit(5000),
    params.tenantId,
    params.empresaId
  ).returns<Array<{ id: string; nome: string | null; acrescimo_percent: number | string | null }>>();
  if (error) throw error;
  return data ?? [];
}

export async function getOrcamentoConfig(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string }
): Promise<ConfigOrcamentoRow> {
  const { data: ensured, error: eErr } = await supabase
    .schema("a")
    .rpc("ensure_config_orcamento", { p_tenant: params.tenantId, p_empresa: params.empresaId });
  if (eErr) throw eErr;
  void ensured;

  const { data, error } = await applyTenantEmpresa(
    supabase
      .schema("a")
      .from("config_orcamento")
      .select("*")
      .is("deleted_at", null)
      .maybeSingle<ConfigOrcamentoRow>(),
    params.tenantId,
    params.empresaId
  );

  if (error) throw error;
  if (!data?.id) throw new Error("Configuração de orçamento não encontrada.");
  return data as ConfigOrcamentoRow;
}

export async function getUsuarioIdByAuthUserId(
  supabase: SupabaseClient,
  params: { authUserId: string }
): Promise<UsuarioLookupRow | null> {
  const { data, error } = await supabase
    .schema("a")
    .from("usuario")
    .select("id,nome")
    .eq("auth_user_id", params.authUserId)
    .is("deleted_at", null)
    .maybeSingle<UsuarioLookupRow>();
  if (error) throw error;
  return data?.id ? (data as UsuarioLookupRow) : null;
}

export async function listVendedores(supabase: SupabaseClient): Promise<UsuarioLookupRow[]> {
  const { data, error } = await supabase
    .schema("a")
    .from("usuario")
    .select("id,nome")
    .eq("ativo", true)
    .is("deleted_at", null)
    .order("nome", { ascending: true })
    .limit(5000)
    .returns<UsuarioLookupRow[]>();
  if (error) throw error;
  return (data ?? []) as UsuarioLookupRow[];
}

export async function searchClientes(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; term: string }
): Promise<ClienteLookupRow[]> {
  const t = String(params.term ?? "").trim();
  if (!t) return [];

  let query = applyTenantEmpresa(
    supabase
      .from("clientes")
      .select("id,nome")
      .order("nome", { ascending: true })
      .limit(25),
    params.tenantId,
    params.empresaId
  );

  const maybeId = Number(t);
  if (Number.isFinite(maybeId) && maybeId > 0) {
    query = query.or(`id.eq.${maybeId},nome.ilike.%${t}%`);
  } else {
    query = query.ilike("nome", `%${t}%`);
  }

  const { data, error } = await query.returns<ClienteLookupRow[]>();
  if (error) throw error;
  return (data ?? []) as ClienteLookupRow[];
}

export async function searchItens(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; term: string }
): Promise<ItemLookupRow[]> {
  const t = String(params.term ?? "").trim();
  if (!t) return [];

  let query = applyTenantEmpresa(
    supabase
      .from("itens")
      .select("id,nome,tipo,unidade_medida,preco_unitario,ativo")
      .eq("ativo", true)
      .in("tipo", ["produto", "servico"])
      .order("nome", { ascending: true })
      .limit(30),
    params.tenantId,
    params.empresaId
  );

  const maybeId = Number(t);
  if (Number.isFinite(maybeId) && maybeId > 0) {
    query = query.or(`id.eq.${maybeId},nome.ilike.%${t}%`);
  } else {
    query = query.ilike("nome", `%${t}%`);
  }

  const { data, error } = await query.returns<ItemLookupRow[]>();
  if (error) throw error;
  return (data ?? []) as ItemLookupRow[];
}
