import type { SupabaseClient } from "@supabase/supabase-js";
import { applyTenantEmpresa } from "@/lib/db/scopes";

export type SortDir = "asc" | "desc";

export type PagedResult<T> = {
  rows: T[];
  count: number;
};

export type FornecedorOption = { id: number; nome: string };

export type SaldoFinalidade = "todas" | "materia_prima" | "consumo" | "revenda" | "imobilizado" | "outros" | string;

export type SaldoEmEstoqueFilters = {
  fornecedorPrefix: string;
  fornecedorIds: number[];
  semFornecedor: boolean;
  busca: string;
  finalidade: SaldoFinalidade; // "todas" = sem filtro
  abaixoMinimo: boolean;
  separarPorFornecedor: boolean;
  localizacao: string;
};

export type SaldoEmEstoqueSortKey = "codigo" | "nome";

export type SaldoEmEstoqueRow = {
  item_id: number;
  codigo_interno: string;
  item_nome: string;
  unidade_medida: string | null;
  quantidade_atual: number;
  quantidade_comprada_pendente: number;
  preco_unitario: number | string | null;
  custo_medio: number | string | null;
  valor_estoque: number | string | null;
  fornecedor_id: number | null;
  fornecedor_nome: string | null;
  estoque_minimo: number | string | null;
  estoque_ideal: number | string | null;
  estoque_maximo: number | string | null;
  localizacao: string | null;
  finalidade: string | null;
  controla_estoque: boolean | null;
  abaixo_minimo: boolean | null;
};

const PEDIDO_COMPRA_STATUS_COMPRADO = ["RASCUNHO", "AGUARDANDO_APROVACAO", "APROVADO", "ENVIADO", "PARCIAL_RECEBIDO"] as const;

function safeNumber(v: unknown): number {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : 0;
}

function pickPositiveUnitValue(values: unknown[]): number {
  for (const value of values) {
    const parsed = safeNumber(value);
    if (parsed > 0) return parsed;
  }
  return 0;
}

function normalizeNullableText(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const trimmed = v.trim();
  return trimmed ? trimmed : null;
}

function normalizeNumberOrString(v: unknown): number | string | null {
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  if (typeof v === "string") {
    const trimmed = v.trim();
    return trimmed ? trimmed : null;
  }
  return null;
}

function normalizeNullableNumber(v: unknown): number | null {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

function normalizeNullableBoolean(v: unknown): boolean | null {
  return typeof v === "boolean" ? v : null;
}

function chunkArray<T>(values: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < values.length; i += size) chunks.push(values.slice(i, i + size));
  return chunks;
}

async function listPedidoCompraAbertoIds(
  supabase: SupabaseClient,
  ctx: { tenantId: string; empresaId: string }
): Promise<string[]> {
  const ids: string[] = [];
  const pageSize = 1000;
  let from = 0;

  while (true) {
    const { data, error } = await supabase
      .schema("m")
      .from("pedido_compra")
      .select("id")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .is("deleted_at", null)
      .in("status", [...PEDIDO_COMPRA_STATUS_COMPRADO])
      .range(from, from + pageSize - 1);

    if (error) throw error;

    const rows = Array.isArray(data) ? (data as Array<{ id?: unknown }>) : [];
    ids.push(...rows.map((row) => String(row.id ?? "").trim()).filter(Boolean));

    if (rows.length < pageSize) break;
    from += pageSize;
  }

  return ids;
}

async function getQuantidadeCompradaPendenteByItem(
  supabase: SupabaseClient,
  ctx: { tenantId: string; empresaId: string },
  itemIdsRaw: number[]
): Promise<Map<number, number>> {
  const itemIds = Array.from(new Set(itemIdsRaw.filter((id) => Number.isFinite(id) && id > 0)));
  const totals = new Map<number, number>();
  if (itemIds.length === 0) return totals;

  const pedidoIds = await listPedidoCompraAbertoIds(supabase, ctx);
  if (pedidoIds.length === 0) return totals;

  for (const pedidoChunk of chunkArray(pedidoIds, 400)) {
    for (const itemChunk of chunkArray(itemIds, 400)) {
      const { data, error } = await supabase
        .schema("m")
        .from("pedido_compra_item")
        .select("item_id,quantidade,quantidade_recebida")
        .eq("tenant_id", ctx.tenantId)
        .eq("empresa_id", ctx.empresaId)
        .is("deleted_at", null)
        .in("pedido_compra_id", pedidoChunk)
        .in("item_id", itemChunk);

      if (error) throw error;

      for (const row of Array.isArray(data) ? (data as Array<Record<string, unknown>>) : []) {
        const itemId = safeNumber(row.item_id);
        if (!Number.isFinite(itemId) || itemId <= 0) continue;
        const pendente = Math.max(0, safeNumber(row.quantidade) - safeNumber(row.quantidade_recebida));
        if (pendente <= 0) continue;
        totals.set(itemId, (totals.get(itemId) ?? 0) + pendente);
      }
    }
  }

  return totals;
}

async function attachQuantidadeCompradaPendente(
  supabase: SupabaseClient,
  ctx: { tenantId: string; empresaId: string },
  rows: SaldoEmEstoqueRow[]
): Promise<SaldoEmEstoqueRow[]> {
  if (rows.length === 0) return rows;
  let compradoByItem = new Map<number, number>();

  try {
    compradoByItem = await getQuantidadeCompradaPendenteByItem(
      supabase,
      ctx,
      rows.map((row) => row.item_id)
    );
  } catch (error) {
    console.warn("[Relatorio estoque] Nao foi possivel carregar compras pendentes.", error);
  }

  return rows.map((row) => ({
    ...row,
    quantidade_comprada_pendente: compradoByItem.get(row.item_id) ?? 0,
  }));
}

function splitOrEmpty(s: string): string[] {
  return String(s ?? "")
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);
}

export async function listFornecedores(
  supabase: SupabaseClient,
  tenantId: string
): Promise<FornecedorOption[]> {
  const { data, error } = await supabase
    .from("fornecedores")
    .select("id,nome")
    .eq("tenant_id", tenantId)
    .eq("ativo", true)
    .order("nome", { ascending: true })
    .limit(2000);

  if (error) throw error;

  const rows = Array.isArray(data) ? (data as Array<{ id: unknown; nome: unknown }>) : [];
  return rows
    .map((r) => ({ id: safeNumber(r.id), nome: String(r.nome ?? "").trim() }))
    .filter((r) => Number.isFinite(r.id) && r.id > 0 && r.nome);
}

// TAB A
// Fonte oficial: public.estoque + join public.itens + left join public.fornecedores.
export async function listSaldoEmEstoque(
  supabase: SupabaseClient,
  ctx: { tenantId: string; empresaId: string },
  args: {
    page: number; // 1-based
    pageSize: number;
    sort: { key: SaldoEmEstoqueSortKey; dir: SortDir };
    filters: SaldoEmEstoqueFilters;
  }
): Promise<PagedResult<SaldoEmEstoqueRow>> {
  const page = Math.max(1, Math.floor(args.page || 1));
  const pageSize = Math.max(10, Math.min(500, Math.floor(args.pageSize || 50)));
  const { tenantId, empresaId } = ctx;
  const { filters } = args;
  const { data, error } = await supabase.rpc("search_relatorio_estoque", {
    p_tenant_id: tenantId,
    p_empresa_id: empresaId,
    p_busca: filters.busca.trim() || null,
    p_fornecedor: filters.fornecedorPrefix.trim() || null,
    p_finalidade: filters.finalidade && filters.finalidade !== "todas" ? filters.finalidade : null,
    p_localizacao: filters.localizacao.trim() || null,
    p_abaixo_minimo: filters.abaixoMinimo,
    p_sem_fornecedor: filters.semFornecedor,
    p_page: page,
    p_page_size: pageSize,
    p_sort_key: args.sort.key,
    p_sort_dir: args.sort.dir,
  });
  if (error) throw error;

  const rpcRows = Array.isArray(data) ? (data as Array<Record<string, unknown>>) : [];
  const rows = rpcRows.map((row): SaldoEmEstoqueRow => ({
    item_id: safeNumber(row.item_id),
    codigo_interno: String(row.codigo_interno ?? ""),
    item_nome: String(row.item_nome ?? ""),
    unidade_medida: normalizeNullableText(row.unidade_medida),
    quantidade_atual: safeNumber(row.quantidade_atual),
    quantidade_comprada_pendente: 0,
    preco_unitario: normalizeNumberOrString(row.preco_unitario),
    custo_medio: normalizeNumberOrString(row.custo_medio),
    valor_estoque: safeNumber(row.quantidade_atual) * pickPositiveUnitValue([row.preco_unitario, row.custo_medio]),
    fornecedor_id: normalizeNullableNumber(row.fornecedor_id),
    fornecedor_nome: normalizeNullableText(row.fornecedor_nome),
    estoque_minimo: normalizeNumberOrString(row.estoque_minimo),
    estoque_ideal: normalizeNumberOrString(row.estoque_ideal),
    estoque_maximo: normalizeNumberOrString(row.estoque_maximo),
    localizacao: normalizeNullableText(row.localizacao),
    finalidade: normalizeNullableText(row.finalidade),
    controla_estoque: normalizeNullableBoolean(row.controla_estoque),
    abaixo_minimo: normalizeNullableBoolean(row.abaixo_minimo),
  }));

  return {
    rows: await attachQuantidadeCompradaPendente(supabase, ctx, rows),
    count: rpcRows.length > 0 ? safeNumber(rpcRows[0].total_count) : 0,
  };
}
// TAB B
export type EntradasToggleOs = "todos" | "com_os" | "sem_os";

export type EntradasNoPeriodoFilters = {
  dataIni: string; // YYYY-MM-DD
  dataFim: string; // YYYY-MM-DD
  fornecedorPrefix: string;
  fornecedorIds: number[];
  buscaItem: string;
  osMode: EntradasToggleOs;
  comNf: boolean;
  destacarSaldoAlto: boolean;
};

export type EntradasNoPeriodoSortKey = "item" | "qtd_comprada" | "saldo_atual";

export type EntradaConsolidadaRow = {
  item_id: number;
  fornecedor_id: number | null;
  codigo_interno: string;
  item_nome: string;
  fornecedor_nome: string;
  motivo: string;
  unidade_medida: string | null;
  qtd_comprada: number;
  qtd_para_os: number;
  qtd_para_estoque: number;
  percentual_os: number;
  destino_os: string;
  saldo_atual: number;
  saldo_ajustado: number;
  estoque_ideal: number;
  situacao: "OK" | "ALERTA";
};

export type EntradaDetalheRow = {
  movimentacao_id: number;
  data_movimentacao: string;
  nf: string;
  quantidade: number;
  os_id: number | null;
  realizado_por: string | null;
  tipo: "DIRETO OS" | "ENTRADA ESTOQUE";
};

export type EntradaExclusaoRow = {
  tenant_id: string;
  empresa_id: string;
  item_id: number;
  codigo_interno: string;
  item_nome: string;
  motivo: string | null;
  created_at: string;
  created_by: string | null;
};

export async function listEntradasNoPeriodo(
  supabase: SupabaseClient,
  ctx: { tenantId: string; empresaId: string },
  args: {
    page: number;
    pageSize: number;
    sort: { key: EntradasNoPeriodoSortKey; dir: SortDir };
    filters: EntradasNoPeriodoFilters;
  }
): Promise<PagedResult<EntradaConsolidadaRow>> {
  const page = Math.max(1, Math.floor(args.page || 1));
  const pageSize = Math.max(10, Math.min(300, Math.floor(args.pageSize || 50)));
  const from = (page - 1) * pageSize;
  const to = from + pageSize;

  const { tenantId, empresaId } = ctx;
  const { filters } = args;

  const { data, error } = await supabase.rpc("rel_entradas_periodo_consolidado", {
    p_tenant_id: tenantId,
    p_empresa_id: empresaId,
    p_data_ini: filters.dataIni,
    p_data_fim: filters.dataFim,
    p_fornecedor_prefix: filters.fornecedorPrefix.trim() || null,
    p_busca_item: filters.buscaItem.trim() || null,
    p_os_mode: filters.osMode,
    p_com_nf: filters.comNf,
    p_destacar_saldo_alto: filters.destacarSaldoAlto,
  });
  if (error) throw error;

  const rowsMapped: EntradaConsolidadaRow[] = (Array.isArray(data) ? data : []).map((r) => ({
    item_id: safeNumber((r as Record<string, unknown>).item_id),
    fornecedor_id: (() => {
      const raw = (r as Record<string, unknown>).fornecedor_id;
      if (raw === null || raw === undefined) return null;
      const n = safeNumber(raw);
      return Number.isFinite(n) ? n : null;
    })(),
    codigo_interno: String((r as Record<string, unknown>).codigo_interno ?? ""),
    item_nome: String((r as Record<string, unknown>).item_nome ?? ""),
    fornecedor_nome: String((r as Record<string, unknown>).fornecedor_nome ?? "SEM FORNECEDOR"),
    motivo: String((r as Record<string, unknown>).motivo ?? "MOV. MANUAL"),
    unidade_medida: ((r as Record<string, unknown>).unidade_medida as string | null) ?? null,
    qtd_comprada: safeNumber((r as Record<string, unknown>).qtd_comprada),
    qtd_para_os: safeNumber((r as Record<string, unknown>).qtd_para_os),
    qtd_para_estoque: safeNumber((r as Record<string, unknown>).qtd_para_estoque),
    percentual_os: safeNumber((r as Record<string, unknown>).percentual_os),
    destino_os: String((r as Record<string, unknown>).destino_os ?? "-"),
    saldo_atual: safeNumber((r as Record<string, unknown>).saldo_atual),
    saldo_ajustado: safeNumber((r as Record<string, unknown>).saldo_ajustado),
    estoque_ideal: safeNumber((r as Record<string, unknown>).estoque_ideal),
    situacao:
      String((r as Record<string, unknown>).situacao ?? "OK").toUpperCase() === "ALERTA"
        ? "ALERTA"
        : "OK",
  }));

  const sorted = [...rowsMapped].sort((a, b) => {
    if (args.sort.key === "qtd_comprada") {
      return args.sort.dir === "asc" ? a.qtd_comprada - b.qtd_comprada : b.qtd_comprada - a.qtd_comprada;
    }
    if (args.sort.key === "saldo_atual") {
      return args.sort.dir === "asc" ? a.saldo_atual - b.saldo_atual : b.saldo_atual - a.saldo_atual;
    }
    const cmp = a.item_nome.localeCompare(b.item_nome, "pt-BR", { sensitivity: "base" });
    return args.sort.dir === "asc" ? cmp : -cmp;
  });

  return { rows: sorted.slice(from, to), count: sorted.length };
}

export async function listEntradasNoPeriodoDetalhes(
  supabase: SupabaseClient,
  ctx: { tenantId: string; empresaId: string },
  args: {
    filters: EntradasNoPeriodoFilters;
    itemId: number;
    fornecedorId: number | null;
  }
): Promise<EntradaDetalheRow[]> {
  const { data, error } = await supabase.rpc("rel_entradas_periodo_detalhes", {
    p_tenant_id: ctx.tenantId,
    p_empresa_id: ctx.empresaId,
    p_data_ini: args.filters.dataIni,
    p_data_fim: args.filters.dataFim,
    p_item_id: args.itemId,
    p_fornecedor_id: args.fornecedorId,
    p_os_mode: args.filters.osMode,
    p_com_nf: args.filters.comNf,
  });

  if (error) throw error;

  return (Array.isArray(data) ? data : []).map((r) => ({
    movimentacao_id: safeNumber((r as Record<string, unknown>).movimentacao_id),
    data_movimentacao: String((r as Record<string, unknown>).data_movimentacao ?? ""),
    nf: String((r as Record<string, unknown>).nf ?? "-"),
    quantidade: safeNumber((r as Record<string, unknown>).quantidade),
    os_id: (() => {
      const raw = (r as Record<string, unknown>).os_id;
      if (raw === null || raw === undefined) return null;
      const n = safeNumber(raw);
      return Number.isFinite(n) && n > 0 ? n : null;
    })(),
    realizado_por: (() => {
      const raw = (r as Record<string, unknown>).realizado_por;
      if (raw === null || raw === undefined) return null;
      const s = String(raw).trim();
      return s || null;
    })(),
    tipo:
      String((r as Record<string, unknown>).tipo ?? "ENTRADA ESTOQUE").toUpperCase() === "DIRETO OS"
        ? "DIRETO OS"
        : "ENTRADA ESTOQUE",
  }));
}

export async function listEntradasExclusoes(
  supabase: SupabaseClient,
  ctx: { tenantId: string; empresaId: string }
): Promise<EntradaExclusaoRow[]> {
  const { data, error } = await applyTenantEmpresa(
    supabase
      .from("relatorio_operacional_exclusoes")
      .select("tenant_id,empresa_id,item_id,motivo,created_at,created_by")
      .order("created_at", { ascending: false })
      .limit(2000),
    ctx.tenantId,
    ctx.empresaId
  );
  if (error) throw error;

  const base = Array.isArray(data)
    ? (data as Array<Record<string, unknown>>).map((r) => ({
        tenant_id: String(r.tenant_id ?? ""),
        empresa_id: String(r.empresa_id ?? ""),
        item_id: safeNumber(r.item_id),
        motivo: typeof r.motivo === "string" ? r.motivo : null,
        created_at: String(r.created_at ?? ""),
        created_by: typeof r.created_by === "string" ? r.created_by : null,
      }))
    : [];

  const itemIds = Array.from(new Set(base.map((r) => r.item_id).filter((n) => Number.isFinite(n) && n > 0)));
  const itemMap = new Map<number, { codigo_interno: string; nome: string }>();

  if (itemIds.length) {
    const { data: itensData, error: itensErr } = await applyTenantEmpresa(
      supabase.from("itens").select("id,codigo_interno,nome").in("id", itemIds),
      ctx.tenantId,
      ctx.empresaId
    );
    if (itensErr) throw itensErr;
    for (const raw of Array.isArray(itensData) ? (itensData as Array<Record<string, unknown>>) : []) {
      const id = safeNumber(raw.id);
      if (!Number.isFinite(id) || id <= 0) continue;
      itemMap.set(id, {
        codigo_interno: String(raw.codigo_interno ?? ""),
        nome: String(raw.nome ?? ""),
      });
    }
  }

  return base
    .map((r) => ({
      tenant_id: r.tenant_id,
      empresa_id: r.empresa_id,
      item_id: r.item_id,
      codigo_interno: itemMap.get(r.item_id)?.codigo_interno ?? "",
      item_nome: itemMap.get(r.item_id)?.nome ?? "",
      motivo: r.motivo,
      created_at: r.created_at,
      created_by: r.created_by,
    }))
    .sort((a, b) => a.item_nome.localeCompare(b.item_nome, "pt-BR", { sensitivity: "base" }));
}

export async function addEntradasExclusao(
  supabase: SupabaseClient,
  ctx: { tenantId: string; empresaId: string },
  args: { itemId: number; motivo?: string | null; createdBy?: string | null }
): Promise<void> {
  const payload = {
    tenant_id: ctx.tenantId,
    empresa_id: ctx.empresaId,
    item_id: args.itemId,
    motivo: args.motivo?.trim() ? args.motivo.trim() : null,
    created_by: args.createdBy ?? null,
  };
  const { error } = await applyTenantEmpresa(
    supabase.from("relatorio_operacional_exclusoes").upsert(payload, { onConflict: "tenant_id,empresa_id,item_id" }),
    ctx.tenantId,
    ctx.empresaId
  );
  if (error) throw error;
}

export async function removeEntradasExclusao(
  supabase: SupabaseClient,
  ctx: { tenantId: string; empresaId: string },
  itemId: number
): Promise<void> {
  const { error } = await applyTenantEmpresa(
    supabase.from("relatorio_operacional_exclusoes").delete().eq("item_id", itemId),
    ctx.tenantId,
    ctx.empresaId
  );
  if (error) throw error;
}

export function parseCsvIds(value: string | null): number[] {
  return splitOrEmpty(String(value ?? ""))
    .map((x) => Number.parseInt(x, 10))
    .filter((n) => Number.isFinite(n) && n > 0);
}
