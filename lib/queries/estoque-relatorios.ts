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
  custo_medio: number | string | null;
  valor_estoque: number | string | null;
  fornecedor_id: number | null;
  fornecedor_nome: string | null;
  estoque_minimo: number | string | null;
  estoque_ideal: number | string | null;
  localizacao: string | null;
  finalidade: string | null;
  controla_estoque: boolean | null;
  abaixo_minimo: boolean | null;
};

function safeNumber(v: unknown): number {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : 0;
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

async function resolveFornecedorIdsByPrefix(
  supabase: SupabaseClient,
  ctx: { tenantId: string; empresaId: string },
  prefixRaw: string
): Promise<number[]> {
  const prefix = String(prefixRaw ?? "").trim();
  if (!prefix) return [];

  const { tenantId, empresaId } = ctx;

  const { data, error } = await applyTenantEmpresa(
    supabase
      .from("fornecedores")
      .select("id")
      .eq("ativo", true)
      .ilike("nome", `${prefix}%`)
      .order("nome", { ascending: true })
      .limit(500),
    tenantId,
    empresaId
  );

  if (error) throw error;

  const rows = Array.isArray(data) ? (data as Array<{ id: unknown }>) : [];
  return rows.map((r) => safeNumber(r.id)).filter((n) => Number.isFinite(n) && n > 0);
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
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  const { tenantId, empresaId } = ctx;
  const { filters } = args;

  const resolvedFornecedorIds =
    filters.fornecedorIds.length > 0
      ? filters.fornecedorIds
      : filters.fornecedorPrefix.trim()
        ? await resolveFornecedorIdsByPrefix(supabase, ctx, filters.fornecedorPrefix)
        : [];

  if (filters.fornecedorPrefix.trim() && resolvedFornecedorIds.length === 0 && !filters.semFornecedor) {
    return { rows: [], count: 0 };
  }

  let qb = applyTenantEmpresa(
    supabase
      .from("estoque")
      .select(
        [
          "item_id",
          "quantidade_atual",
          "localizacao",
          "empresa_id",
          "itens:itens!estoque_item_id_fkey(id,codigo_interno,nome,unidade_medida,custo_medio,estoque_minimo,fornecedor_id,finalidade,controla_estoque,fornecedores!itens_tenant_empresa_fornecedor_fk(nome))",
        ].join(","),
        { count: "exact" }
      )
      .eq("empresa_id", empresaId)
      .gt("quantidade_atual", 0),
    tenantId,
    empresaId
  );

  qb = qb.eq("itens.controla_estoque", true);

  if (filters.finalidade && filters.finalidade !== "todas") qb = qb.eq("itens.finalidade", filters.finalidade);

  if (filters.localizacao.trim()) qb = qb.ilike("localizacao", `%${filters.localizacao.trim()}%`);

  const busca = filters.busca.trim();
  if (busca) {
    qb = qb.or([`itens.nome.ilike.%${busca}%`, `itens.codigo_interno.ilike.%${busca}%`].join(","));
  }

  if (resolvedFornecedorIds.length && filters.semFornecedor) {
    qb = qb.or([`itens.fornecedor_id.in.(${resolvedFornecedorIds.join(",")})`, "itens.fornecedor_id.is.null"].join(","));
  } else if (resolvedFornecedorIds.length) {
    qb = qb.in("itens.fornecedor_id", resolvedFornecedorIds);
  } else if (filters.semFornecedor) {
    qb = qb.is("itens.fornecedor_id", null);
  }

  if (args.sort.key === "codigo") {
    qb = qb.order("itens(codigo_interno)", { ascending: args.sort.dir === "asc" });
  } else {
    qb = qb.order("itens(nome)", { ascending: args.sort.dir === "asc" });
  }

  const { data, error, count } = await qb.range(from, to);
  if (error) throw error;

  const mapped: SaldoEmEstoqueRow[] = (data ?? []).map((r: unknown) => {
    const row = r as {
      item_id?: unknown;
      quantidade_atual?: unknown;
      localizacao?: unknown;
      itens?: unknown;
    };

    const itensRaw = row.itens ?? null;
    const itens = Array.isArray(itensRaw) ? itensRaw[0] ?? null : itensRaw;

    const fornRaw = itens?.fornecedores ?? null;
    const forn = Array.isArray(fornRaw) ? fornRaw[0] ?? null : fornRaw;

    const saldo = safeNumber(row.quantidade_atual);
    const custo = itens?.custo_medio ?? null;
    const valor = saldo * safeNumber(custo);
    const estoqueMin = itens?.estoque_minimo ?? null;
    const abaixoMin = saldo < safeNumber(estoqueMin);

    return {
      item_id: safeNumber(itens?.id ?? row.item_id),
      codigo_interno: String(itens?.codigo_interno ?? ""),
      item_nome: String(itens?.nome ?? ""),
      unidade_medida: itens?.unidade_medida ?? null,
      quantidade_atual: saldo,
      custo_medio: custo,
      valor_estoque: valor,
      fornecedor_id: itens?.fornecedor_id ?? null,
      fornecedor_nome: forn?.nome ? String(forn.nome) : null,
      estoque_minimo: itens?.estoque_minimo ?? null,
      estoque_ideal: null,
      localizacao: typeof row.localizacao === "string" ? row.localizacao : null,
      finalidade: itens?.finalidade ?? null,
      controla_estoque: itens?.controla_estoque ?? null,
      abaixo_minimo: abaixoMin,
    };
  });

  const filtered = filters.abaixoMinimo ? mapped.filter((x) => x.abaixo_minimo) : mapped;

  return { rows: filtered, count: Number(count ?? 0) };
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
