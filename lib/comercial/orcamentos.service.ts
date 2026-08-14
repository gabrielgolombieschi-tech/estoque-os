import { applyTenantEmpresa } from "@/lib/db/scopes";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { OrcamentoStatusCanonical } from "@/lib/comercial/status";
import { getOrcamentoStatusFilterValues } from "@/lib/comercial/status";
import type {
  OrcamentoAnaliticoRow,
  ClienteContatoLookupRow,
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

function trimToNull(value: string | null | undefined): string | null {
  const trimmed = String(value ?? "").trim();
  return trimmed ? trimmed : null;
}

function normalizeEmail(value: string | null | undefined): string | null {
  const email = trimToNull(value);
  return email ? email.toLowerCase() : null;
}

type ClienteContatoOrcamentoRow = {
  id: number | string;
  nome: string | null;
  setor: string | null;
  email: string | null;
  telefone: string | null;
  vezes_usado: number | string | null;
};

export async function salvarContatoClienteDoOrcamento(
  supabase: SupabaseClient,
  params: {
    tenantId: string;
    empresaId: string;
    clienteId: number | null | undefined;
    solicitanteNome?: string | null;
    solicitanteSetor?: string | null;
    solicitanteEmail?: string | null;
    solicitanteTelefone?: string | null;
  }
): Promise<void> {
  const tenantId = trimToNull(params.tenantId);
  const empresaId = trimToNull(params.empresaId);
  const clienteId = Number(params.clienteId ?? null);
  const email = normalizeEmail(params.solicitanteEmail);

  if (!tenantId || !empresaId || !Number.isFinite(clienteId) || clienteId <= 0 || !email) return;

  const nome = trimToNull(params.solicitanteNome);
  const setor = trimToNull(params.solicitanteSetor);
  const telefone = trimToNull(params.solicitanteTelefone);

  const warn = (error: unknown) => {
    console.warn("Falha ao salvar contato do cliente a partir do orcamento.", error);
  };

  const findExisting = async (): Promise<ClienteContatoOrcamentoRow | null> => {
    const { data, error } = await supabase
      .from("cliente_contatos")
      .select("id,nome,setor,email,telefone,vezes_usado")
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .eq("cliente_id", clienteId)
      .not("email", "is", null)
      .limit(500)
      .returns<ClienteContatoOrcamentoRow[]>();

    if (error) throw error;

    return (
      (data ?? []).find((row) => {
        return normalizeEmail(row.email) === email;
      }) ?? null
    );
  };

  const updateExisting = async (row: ClienteContatoOrcamentoRow): Promise<void> => {
    const now = new Date().toISOString();
    const currentUses = Number(row.vezes_usado ?? 0);
    const patch: {
      nome?: string;
      setor?: string;
      telefone?: string;
      email: string;
      ativo: boolean;
      ultimo_uso_em: string;
      vezes_usado: number;
      updated_at: string;
    } = {
      email,
      ativo: true,
      ultimo_uso_em: now,
      vezes_usado: (Number.isFinite(currentUses) ? currentUses : 0) + 1,
      updated_at: now,
    };

    if (nome) patch.nome = nome;
    if (setor) patch.setor = setor;
    if (telefone) patch.telefone = telefone;

    const { error } = await supabase
      .from("cliente_contatos")
      .update(patch)
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .eq("cliente_id", clienteId)
      .eq("id", row.id);
    if (error) throw error;
  };

  try {
    const existing = await findExisting();
    if (existing) {
      await updateExisting(existing);
      return;
    }

    const now = new Date().toISOString();
    const { error: insertError } = await supabase.from("cliente_contatos").insert({
      tenant_id: tenantId,
      empresa_id: empresaId,
      cliente_id: clienteId,
      nome,
      setor,
      email,
      telefone,
      ativo: true,
      principal: false,
      vezes_usado: 1,
      ultimo_uso_em: now,
    });

    if (!insertError) return;

    if (insertError.code === "23505") {
      const concurrentExisting = await findExisting();
      if (concurrentExisting) {
        await updateExisting(concurrentExisting);
        return;
      }
    }

    throw insertError;
  } catch (error) {
    warn(error);
  }
}

export async function listarContatosClienteParaOrcamento(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; clienteId: number | null | undefined }
): Promise<ClienteContatoLookupRow[]> {
  const tenantId = trimToNull(params.tenantId);
  const empresaId = trimToNull(params.empresaId);
  const clienteId = Number(params.clienteId ?? null);

  if (!tenantId || !empresaId || !Number.isFinite(clienteId) || clienteId <= 0) return [];

  const { data, error } = await supabase
    .from("cliente_contatos")
    .select("id,nome,setor,email,telefone,principal,vezes_usado,ultimo_uso_em")
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .eq("cliente_id", clienteId)
    .eq("ativo", true)
    .order("principal", { ascending: false })
    .order("ultimo_uso_em", { ascending: false, nullsFirst: false })
    .order("vezes_usado", { ascending: false })
    .order("nome", { ascending: true, nullsFirst: false })
    .limit(25)
    .returns<ClienteContatoLookupRow[]>();

  if (error) throw error;
  return (data ?? []) as ClienteContatoLookupRow[];
}

export async function sincronizarOrcamentoComDriveViaAppsScript(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; orcamentoId: string }
): Promise<void> {
  const tenantId = trimToNull(params.tenantId);
  const empresaId = trimToNull(params.empresaId);
  const orcamentoId = trimToNull(params.orcamentoId);
  if (!tenantId || !empresaId || !orcamentoId) return;

  const requestedAt = new Date().toISOString();
  const updateSyncStatus = async (patch: {
    drive_sync_status: string;
    drive_sync_error: string | null;
    drive_sync_requested_at: string;
    drive_synced_at: string | null;
  }) => {
    const { error } = await supabase
      .schema("m")
      .from("orcamento")
      .update(patch)
      .eq("id", orcamentoId)
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId);
    if (error) console.warn("Falha ao atualizar status de sincronizacao Drive do orcamento.", error);
  };

  const markError = async (message: string) => {
    await updateSyncStatus({
      drive_sync_status: "error",
      drive_sync_error: message.slice(0, 1500),
      drive_sync_requested_at: requestedAt,
      drive_synced_at: null,
    });
  };

  try {
    await updateSyncStatus({
      drive_sync_status: "pending",
      drive_sync_error: null,
      drive_sync_requested_at: requestedAt,
      drive_synced_at: null,
    });

    const { data, error } = await supabase.auth.getSession();
    if (error) throw error;

    const token = data.session?.access_token ?? null;
    if (!token) {
      const message = "Sessao ausente para sincronizar orcamento com Drive.";
      await markError(message);
      console.warn(message);
      return;
    }

    const qs = new URLSearchParams({ tenantId, empresaId });
    const res = await fetch(`/api/comercial/orcamentos/${encodeURIComponent(orcamentoId)}/drive-sync?${qs.toString()}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ tenantId, empresaId }),
    });

    const json = (await res.json().catch(() => null)) as { ok?: boolean; error?: string } | null;
    if (!res.ok || json?.ok === false) {
      const message = String(json?.error ?? `HTTP ${res.status}`).trim();
      await markError(message);
      console.warn("Falha ao sincronizar orcamento com Drive via Apps Script.", message);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "Falha ao sincronizar orcamento com Drive via Apps Script.";
    await markError(message);
    console.warn("Falha ao sincronizar orcamento com Drive via Apps Script.", error);
  }
}

export async function listOrcamentos(
  supabase: SupabaseClient,
  filters: ListOrcamentosFilters
): Promise<{ rows: OrcamentoListaRow[]; count: number }> {
  const page = Math.max(1, Number(filters.page ?? 1));
  const pageSize = Math.min(200, Math.max(1, Number(filters.pageSize ?? 50)));
  const fromIdx = (page - 1) * pageSize;

  const status = filters.status ?? "TODOS";
  const statusValues = status === "TODOS" ? null : getOrcamentoStatusFilterValues(status);
  const { data, error } = await supabase.schema("m").rpc("fn_orcamento_listar", {
    p_tenant_id: filters.tenantId,
    p_empresa_id: filters.empresaId,
    p_statuses: statusValues,
    p_emissao_de: trimToNull(filters.from),
    p_emissao_ate: trimToNull(filters.to),
    p_busca: trimToNull(filters.q),
    p_offset: fromIdx,
    p_limit: pageSize,
  });

  if (error) throw error;

  const result = (data ?? {}) as { rows?: OrcamentoListaRow[]; count?: number | string };
  const count = Number(result.count ?? 0);
  return {
    rows: Array.isArray(result.rows) ? result.rows : [],
    count: Number.isFinite(count) ? count : 0,
  };
}

export async function listOrcamentosAnalitico(
  supabase: SupabaseClient,
  filters: { tenantId: string; empresaId: string; from?: string; to?: string }
): Promise<OrcamentoAnaliticoRow[]> {
  const rows: OrcamentoAnaliticoRow[] = [];
  let offset = 0;
  const pageSize = 1000;

  while (true) {
    let query = applyTenantEmpresa(
      supabase
        .schema("r")
        .from("r_orcamento_lista")
        .select(
          [
            "id",
            "codigo",
            "titulo",
            "status",
            "emissao_date",
            "cliente_id",
            "cliente_nome",
            "vendedor_usuario_id",
            "vendedor_nome",
            "total_liquido",
            "valor_fechado",
            "desconto_fechamento_valor",
            "desconto_fechamento_percent",
            "updated_at",
          ].join(",")
        )
        .order("emissao_date", { ascending: true, nullsFirst: false })
        .order("numero", { ascending: true })
        .range(offset, offset + pageSize - 1),
      filters.tenantId,
      filters.empresaId
    );

    const from = String(filters.from ?? "").trim();
    const to = String(filters.to ?? "").trim();
    if (from) query = query.gte("emissao_date", from);
    if (to) query = query.lte("emissao_date", to);

    const { data, error } = await query.returns<OrcamentoAnaliticoRow[]>();
    if (error) throw error;

    rows.push(...((data ?? []) as OrcamentoAnaliticoRow[]));
    if ((data ?? []).length < pageSize) break;
    offset += pageSize;
  }

  return rows;
}

export async function getOrcamento(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; idOrCodigo: string }
): Promise<{ orcamento: OrcamentoRow }> {
  const raw = String(params.idOrCodigo ?? "").trim();
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(raw);

  let orcQuery = applyTenantEmpresa(
    supabase.schema("m").from("orcamento").select("*").is("deleted_at", null),
    params.tenantId,
    params.empresaId
  );

  if (isUuid) {
    orcQuery = orcQuery.eq("id", raw);
  } else {
    // Allow route param to be the human-friendly codigo (ex.: SEG-001-026).
    orcQuery = orcQuery.eq("codigo", raw).order("versao", { ascending: false }).limit(1);
  }

  const { data: orc, error: oErr } = await orcQuery.maybeSingle<OrcamentoRow>();

  if (oErr) throw oErr;
  if (!orc?.id) throw new Error("Orçamento não encontrado.");

  return { orcamento: orc as OrcamentoRow };
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
    solicitanteNome?: string | null;
    solicitanteSetor?: string | null;
    solicitanteEmail?: string | null;
    solicitanteTelefone?: string | null;
  }
): Promise<{ id: string; codigo: string | null }> {
  const payload: Pick<
    OrcamentoRow,
    | "tenant_id"
    | "empresa_id"
    | "titulo"
    | "cliente_id"
    | "vendedor_usuario_id"
    | "condicao_pagamento_id"
    | "solicitante_nome"
    | "solicitante_setor"
    | "solicitante_email"
    | "solicitante_telefone"
  > = {
    tenant_id: params.tenantId,
    empresa_id: params.empresaId,
    titulo: params.titulo,
    cliente_id: params.clienteId,
    vendedor_usuario_id: params.vendedorUsuarioId,
    condicao_pagamento_id: params.condicaoPagamentoId ?? null,
    solicitante_nome: trimToNull(params.solicitanteNome),
    solicitante_setor: trimToNull(params.solicitanteSetor),
    solicitante_email: trimToNull(params.solicitanteEmail),
    solicitante_telefone: trimToNull(params.solicitanteTelefone),
  };

  const { data, error } = await supabase
    .schema("m")
    .from("orcamento")
    .insert(payload)
    .select("id,codigo")
    .single<{ id: string; codigo: string | null }>();

  if (error) throw error;
  const id = data?.id ? String(data.id) : null;
  if (!id) throw new Error("Falha ao criar orçamento.");

  let codigo = data?.codigo ? String(data.codigo) : null;
  // In case codigo is generated by triggers that don't reflect immediately in RETURNING.
  if (!codigo) {
    const { data: row, error: e2 } = await applyTenantEmpresa(
      supabase.schema("m").from("orcamento").select("codigo").eq("id", id).maybeSingle<{ codigo: string | null }>(),
      params.tenantId,
      params.empresaId
    );
    if (!e2 && row?.codigo) codigo = String(row.codigo);
  }

  await salvarContatoClienteDoOrcamento(supabase, {
    tenantId: params.tenantId,
    empresaId: params.empresaId,
    clienteId: params.clienteId,
    solicitanteNome: params.solicitanteNome,
    solicitanteSetor: params.solicitanteSetor,
    solicitanteEmail: params.solicitanteEmail,
    solicitanteTelefone: params.solicitanteTelefone,
  });

  await sincronizarOrcamentoComDriveViaAppsScript(supabase, {
    tenantId: params.tenantId,
    empresaId: params.empresaId,
    orcamentoId: id,
  });

  return { id, codigo };
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
    observacoes?: string | null;
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
    observacoes: string | null;
  } = {
    tenant_id: params.tenantId,
    empresa_id: params.empresaId,
    orcamento_id: params.orcamentoId,
    item_id: params.itemId,
    quantidade: params.quantidade,
    valor_unitario: params.valorUnitario,
    desconto_item_percent: params.descontoItemPercent,
    observacoes: params.observacoes ?? null,
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
    patch: Partial<Pick<OrcamentoItemRow, "quantidade" | "valor_unitario" | "desconto_item_percent" | "observacoes">>;
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
  await updateOrcamento(supabase, { ...params, patch: { status: "FECHADO" } });
}

export async function cancelarOrcamento(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; id: string }
) {
  await updateOrcamento(supabase, { ...params, patch: { status: "PERDIDO" } });
}

export async function reabrirOrcamento(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; id: string }
) {
  await updateOrcamento(supabase, { ...params, patch: { status: "ANDAMENTO" } });
}

export async function atualizarStatusOrcamento(
  supabase: SupabaseClient,
  params: {
    tenantId: string;
    empresaId: string;
    id: string;
    status: OrcamentoStatusCanonical;
    followup: string;
    valorFechado?: number | null;
    abrirOs?: boolean;
    importarItensOs?: boolean;
  }
): Promise<{
  osId: number | null;
  numeroOs: string | null;
  valorOrcado: number;
  valorFechado: number;
  descontoValor: number;
  itensImportados: boolean;
}> {
  const { data, error } = await supabase.schema("m").rpc("fn_orcamento_atualizar_status", {
    p_orcamento_id: params.id,
    p_status: params.status,
    p_followup: params.followup,
    p_valor_fechado: params.status === "FECHADO" ? params.valorFechado ?? null : null,
    p_abrir_os: params.abrirOs ?? false,
    p_importar_itens_os: params.importarItensOs ?? false,
  });

  if (error) throw error;

  const row = (Array.isArray(data) ? data[0] : data) as
    | {
        os_id?: number | null;
        numero_os?: string | null;
        valor_orcado?: number | string | null;
        valor_fechado?: number | string | null;
        desconto_valor?: number | string | null;
        itens_importados?: boolean | null;
      }
    | null;

  return {
    osId: typeof row?.os_id === "number" ? row.os_id : null,
    numeroOs: row?.numero_os ? String(row.numero_os) : null,
    valorOrcado: Number(row?.valor_orcado ?? 0) || 0,
    valorFechado: Number(row?.valor_fechado ?? 0) || 0,
    descontoValor: Number(row?.desconto_valor ?? 0) || 0,
    itensImportados: row?.itens_importados === true,
  };
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

  const { data, error } = await supabase.rpc("search_orcamento_clientes", {
    p_tenant_id: params.tenantId,
    p_empresa_id: params.empresaId,
    p_term: t,
    p_limit: 25,
  });
  if (error) throw error;
  return (data ?? []) as ClienteLookupRow[];
}

export async function getClienteById(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; clienteId: number }
): Promise<ClienteLookupRow | null> {
  const id = Number(params.clienteId);
  if (!Number.isFinite(id) || id <= 0) return null;

  const { data, error } = await applyTenantEmpresa(
    supabase.from("clientes").select("id,nome,documento").eq("id", id).maybeSingle<ClienteLookupRow>(),
    params.tenantId,
    params.empresaId
  );
  if (error) throw error;
  return data?.id ? (data as ClienteLookupRow) : null;
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

export type ItemByIdRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  descricao: string | null;
  tipo: string | null;
  unidade_medida: string | null;
  preco_unitario: number | string | null;
  custo_ultima_compra: number | string | null;
  fornecedor_id: number | null;
  fornecedores?: { nome: string | null } | null;
  ativo: boolean | null;
};

export async function getItemById(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; id: number }
): Promise<ItemByIdRow | null> {
  const { data, error } = await applyTenantEmpresa(
    supabase
      .from("itens")
      .select(
        "id,codigo_interno,nome,descricao,tipo,unidade_medida,preco_unitario,custo_ultima_compra,fornecedor_id,fornecedores!itens_tenant_empresa_fornecedor_fk(nome),ativo"
      )
      .eq("id", params.id)
      .maybeSingle<ItemByIdRow>(),
    params.tenantId,
    params.empresaId
  );
  if (error) throw error;
  return data?.id ? (data as ItemByIdRow) : null;
}

export async function getItemByCodigo(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; codigo: string }
): Promise<ItemByIdRow | null> {
  const codigo = String(params.codigo ?? "").trim();
  if (!codigo) return null;

  try {
    const { data: resolvedId, error: resolveErr } = await supabase.rpc("itens_resolver_por_codigo", {
      p_tenant_id: params.tenantId,
      p_empresa_id: params.empresaId,
      p_codigo: codigo,
    });
    if (!resolveErr) {
      const id = Number(resolvedId ?? 0);
      if (Number.isFinite(id) && id > 0) {
        return getItemById(supabase, { tenantId: params.tenantId, empresaId: params.empresaId, id });
      }
    }
  } catch {
    // fallback below
  }

  // Fallback: codigo generico para orcamentos sem cadastro previo.
  if (codigo === "9999") {
    const { data: ensuredId, error: ensureErr } = await supabase.rpc("ensure_orcamento_item_generico", {
      p_tenant_id: params.tenantId,
      p_empresa_id: params.empresaId,
      p_codigo: codigo,
    });
    if (ensureErr) throw ensureErr;
    const genId = Number(ensuredId ?? 0);
    if (Number.isFinite(genId) && genId > 0) {
      return getItemById(supabase, { tenantId: params.tenantId, empresaId: params.empresaId, id: genId });
    }
  }

  // Fallback final: tenta buscar diretamente por codigo_interno.
  const { data: byCodigo, error: byCodigoErr } = await applyTenantEmpresa(
    supabase
      .from("itens")
      .select(
        "id,codigo_interno,nome,descricao,tipo,unidade_medida,preco_unitario,custo_ultima_compra,fornecedor_id,fornecedores!itens_tenant_empresa_fornecedor_fk(nome),ativo"
      )
      .eq("codigo_interno", codigo)
      .eq("ativo", true)
      .is("mesclado_em_item_id", null)
      .order("id", { ascending: false })
      .maybeSingle<ItemByIdRow>(),
    params.tenantId,
    params.empresaId
  );
  if (byCodigoErr) throw byCodigoErr;
  if (byCodigo?.id) return byCodigo as ItemByIdRow;

  return null;
}
