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
// Preferimos ler da view vw_estoque_saldo (se existir) para suportar abaixo_minimo server-side.
// Fallback: consulta direta em estoque + itens e aplica abaixo_minimo no client.
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

  const viewName = "vw_estoque_saldo";

  const resolvedFornecedorIds =
    filters.fornecedorIds.length > 0
      ? filters.fornecedorIds
      : filters.fornecedorPrefix.trim()
        ? await resolveFornecedorIdsByPrefix(supabase, ctx, filters.fornecedorPrefix)
        : [];

  if (filters.fornecedorPrefix.trim() && resolvedFornecedorIds.length === 0 && !filters.semFornecedor) {
    return { rows: [], count: 0 };
  }

  const runView = async (): Promise<PagedResult<SaldoEmEstoqueRow>> => {
    let qb = supabase
      .from(viewName)
      .select(
        [
          "item_id",
          "codigo_interno",
          "item_nome",
          "unidade_medida",
          "quantidade_atual",
          "custo_medio",
          "valor_estoque",
          "fornecedor_id",
          "fornecedor_nome",
          "estoque_minimo",
          "estoque_ideal",
          "localizacao",
          "finalidade",
          "controla_estoque",
          "abaixo_minimo",
          "tenant_id",
          "empresa_id",
        ].join(","),
        { count: "exact" }
      )
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .gt("quantidade_atual", 0);

    if (filters.finalidade && filters.finalidade !== "todas") qb = qb.eq("finalidade", filters.finalidade);

    if (filters.localizacao.trim()) qb = qb.ilike("localizacao", `%${filters.localizacao.trim()}%`);

    const busca = filters.busca.trim();
    if (busca) {
      qb = qb.or([`item_nome.ilike.%${busca}%`, `codigo_interno.ilike.%${busca}%`].join(","));
    }

    if (resolvedFornecedorIds.length && filters.semFornecedor) {
      qb = qb.or(
        [`fornecedor_id.in.(${resolvedFornecedorIds.join(",")})`, "fornecedor_id.is.null"].join(",")
      );
    } else if (resolvedFornecedorIds.length) {
      qb = qb.in("fornecedor_id", resolvedFornecedorIds);
    } else if (filters.semFornecedor) {
      qb = qb.is("fornecedor_id", null);
    }

    if (filters.abaixoMinimo) qb = qb.eq("abaixo_minimo", true);

    const sortCol = args.sort.key === "codigo" ? "codigo_interno" : "item_nome";
    qb = qb.order(sortCol, { ascending: args.sort.dir === "asc" });

    const { data, error, count } = await qb.range(from, to);
    if (error) throw error;

    const rows = (data ?? []) as unknown as SaldoEmEstoqueRow[];
    return { rows, count: Number(count ?? 0) };
  };

  const runFallback = async (): Promise<PagedResult<SaldoEmEstoqueRow>> => {
    // Fallback sem view: consulta base estoque + itens + fornecedores.
    // Observação: abaixoMinimo passa a ser filtrado no client (contagem/paginação pode divergir).
    let qb = applyTenantEmpresa(
      supabase
        .from("estoque")
        .select(
          [
            "item_id",
            "quantidade_atual",
            "localizacao",
            "empresa_id",
            "itens:itens!estoque_item_id_fkey(codigo_interno,nome,unidade_medida,custo_medio,estoque_minimo,estoque_ideal,fornecedor_id,finalidade,controla_estoque,fornecedores!itens_tenant_empresa_fornecedor_fk(nome))",
          ].join(","),
          { count: "exact" }
        )
        .eq("empresa_id", empresaId)
        .gt("quantidade_atual", 0),
      tenantId,
      empresaId
    );

    // Apenas itens que controlam estoque
    qb = qb.eq("itens.controla_estoque", true);

    if (filters.finalidade && filters.finalidade !== "todas") qb = qb.eq("itens.finalidade", filters.finalidade);

    if (filters.localizacao.trim()) qb = qb.ilike("localizacao", `%${filters.localizacao.trim()}%`);

    const busca = filters.busca.trim();
    if (busca) {
      qb = qb.or([`itens.nome.ilike.%${busca}%`, `itens.codigo_interno.ilike.%${busca}%`].join(","));
    }

    if (resolvedFornecedorIds.length && filters.semFornecedor) {
      qb = qb.or(
        [`itens.fornecedor_id.in.(${resolvedFornecedorIds.join(",")})`, "itens.fornecedor_id.is.null"].join(",")
      );
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
      const fornecedorNome = forn?.nome ?? null;
      const custo = itens?.custo_medio ?? null;
      const saldo = safeNumber(row.quantidade_atual);
      const valor = saldo * safeNumber(custo);
      const estoqueMin = itens?.estoque_minimo ?? null;
      const abaixoMin = saldo < safeNumber(estoqueMin);

      const localizacao = typeof row.localizacao === "string" ? row.localizacao : null;

      return {
        item_id: safeNumber(row.item_id),
        codigo_interno: String(itens?.codigo_interno ?? ""),
        item_nome: String(itens?.nome ?? ""),
        unidade_medida: itens?.unidade_medida ?? null,
        quantidade_atual: saldo,
        custo_medio: custo,
        valor_estoque: valor,
        fornecedor_id: itens?.fornecedor_id ?? null,
        fornecedor_nome: fornecedorNome ? String(fornecedorNome) : null,
        estoque_minimo: itens?.estoque_minimo ?? null,
        estoque_ideal: itens?.estoque_ideal ?? null,
        localizacao,
        finalidade: itens?.finalidade ?? null,
        controla_estoque: itens?.controla_estoque ?? null,
        abaixo_minimo: abaixoMin,
      };
    });

    const filtered = filters.abaixoMinimo ? mapped.filter((x) => x.abaixo_minimo) : mapped;

    return { rows: filtered, count: Number(count ?? 0) };
  };

  try {
    return await runView();
  } catch (e: unknown) {
    const msg =
      e && typeof e === "object" && "message" in e
        ? String((e as { message?: unknown }).message ?? "")
        : "";
    // Se a view não existe (migração não aplicada), faz fallback.
    const m = msg.toLowerCase();
    if (
      m.includes(viewName.toLowerCase()) &&
      (m.includes("does not exist") || m.includes("schema cache") || m.includes("could not find the table"))
    ) {
      return await runFallback();
    }
    throw e;
  }
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
};

export type EntradasNoPeriodoSortKey = "data" | "item";

export type EntradaMovRow = {
  id: number;
  item_id: number;
  quantidade: number;
  data_movimentacao: string;
  origem_nf_entrada_id: number | null;
  origem_os_id: number | null;
  itens: { id?: number; codigo_interno: string; nome: string; unidade_medida: string | null } | null;
  nf: {
    id: number;
    modelo: string | null;
    serie: string | number | null;
    numero: string | number | null;
    chave: string | null;
    data_emissao: string | null;
    fornecedor_id: number | null;
    os_id: number | null;
    fornecedores?: { id?: number; nome: string | null } | null;
  } | null;
};

export type OsInfo = { id: number; numero_os: string | number | null; cliente_nome: string | null; status: string | null };

export type EstoqueSaldoLookup = { item_id: number; quantidade_atual: number };

export type EntradaEnrichedRow = {
  mov: EntradaMovRow;
  os: OsInfo | null;
  saldoAtual: number | null;
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
): Promise<PagedResult<EntradaEnrichedRow>> {
  const page = Math.max(1, Math.floor(args.page || 1));
  const pageSize = Math.max(10, Math.min(200, Math.floor(args.pageSize || 50)));
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

  if (filters.fornecedorPrefix.trim() && resolvedFornecedorIds.length === 0) {
    return { rows: [], count: 0 };
  }

  // Interpretar como timestamp local do DB: evitar sufixo Z.
  const startTs = `${filters.dataIni}T00:00:00`;
  const endTs = `${filters.dataFim}T23:59:59`;

  // Para que filtros em colunas da NF (ex.: fornecedor_id) realmente filtrem a tabela raiz
  // (movimentacoes), precisamos usar join INNER no relacionamento embutido.
  // Caso contrário, o PostgREST pode apenas filtrar o objeto embutido e manter a linha raiz.
  const needsNfInnerJoin = Boolean(filters.comNf) || resolvedFornecedorIds.length > 0;
  const nfSelect = needsNfInnerJoin
    ? "nf:nf_entrada!inner!movimentacoes_origem_nf_entrada_id_fkey(id,modelo,serie,numero,chave,data_emissao,fornecedor_id,os_id,fornecedores(id,nome))"
    : "nf:nf_entrada!movimentacoes_origem_nf_entrada_id_fkey(id,modelo,serie,numero,chave,data_emissao,fornecedor_id,os_id,fornecedores(id,nome))";

  let qb = applyTenantEmpresa(
    supabase
      .from("movimentacoes")
      .select(
        [
          "id",
          "item_id",
          "tipo",
          "quantidade",
          "data_movimentacao",
          "origem_nf_entrada_id",
          "origem_os_id",
          "empresa_id",
          "itens:itens!movimentacoes_item_id_fkey(id,codigo_interno,nome,unidade_medida)",
          nfSelect,
        ].join(","),
        { count: "exact" }
      )
      .eq("empresa_id", empresaId)
      .eq("tipo", "entrada")
      .gte("data_movimentacao", startTs)
      .lte("data_movimentacao", endTs),
    tenantId,
    empresaId
  );

  // NF: opcionalmente exigir NF
  if (filters.comNf) {
    qb = qb.not("origem_nf_entrada_id", "is", null);
  }

  if (resolvedFornecedorIds.length) {
    qb = qb.in("nf.fornecedor_id", resolvedFornecedorIds);
  }

  const term = filters.buscaItem.trim();
  if (term) {
    qb = qb.or([`itens.nome.ilike.%${term}%`, `itens.codigo_interno.ilike.%${term}%`].join(","));
  }

  if (filters.osMode === "com_os") qb = qb.not("origem_os_id", "is", null);
  if (filters.osMode === "sem_os") qb = qb.is("origem_os_id", null);

  if (args.sort.key === "item") {
    qb = qb.order("itens(nome)", { ascending: args.sort.dir === "asc" });
  } else {
    qb = qb.order("data_movimentacao", { ascending: args.sort.dir === "asc" });
  }
  qb = qb.order("id", { ascending: false });

  const { data, error, count } = await qb.range(from, to);
  if (error) throw error;

  const movs = (data ?? []) as unknown as EntradaMovRow[];

  const osIds = Array.from(
    new Set(movs.map((m) => safeNumber(m.origem_os_id)).filter((n) => Number.isFinite(n) && n > 0))
  );

  const itemIds = Array.from(new Set(movs.map((m) => safeNumber(m.item_id)).filter((n) => n > 0)));

  const [osMap, saldoMap] = await Promise.all([
    (async () => {
      if (!osIds.length) return new Map<number, OsInfo>();
      const { data: osData, error: osErr } = await applyTenantEmpresa(
        supabase
          .from("ordens_servico")
          .select("id,numero_os,cliente_nome,status,empresa_id")
          .eq("empresa_id", empresaId)
          .in("id", osIds),
        tenantId,
        empresaId
      );
      if (osErr) throw osErr;
      const map = new Map<number, OsInfo>();
      const rows = (osData ?? []) as Array<{ id?: unknown; numero_os?: unknown; cliente_nome?: unknown; status?: unknown }>;
      for (const r of rows) {
        const id = safeNumber(r.id);
        if (!id) continue;

        const numeroOs =
          typeof r.numero_os === "string" || typeof r.numero_os === "number" ? r.numero_os : null;
        const clienteNome = typeof r.cliente_nome === "string" ? r.cliente_nome : null;
        const status = typeof r.status === "string" ? r.status : null;

        map.set(id, {
          id,
          numero_os: numeroOs,
          cliente_nome: clienteNome,
          status,
        });
      }
      return map;
    })(),
    (async () => {
      if (!itemIds.length) return new Map<number, number>();
      const { data: estData, error: estErr } = await applyTenantEmpresa(
        supabase
          .from("estoque")
          .select("item_id,quantidade_atual,empresa_id")
          .eq("empresa_id", empresaId)
          .in("item_id", itemIds),
        tenantId,
        empresaId
      );
      if (estErr) throw estErr;
      const map = new Map<number, number>();
      const rows = (estData ?? []) as Array<{ item_id?: unknown; quantidade_atual?: unknown }>;
      for (const r of rows) {
        const id = safeNumber(r.item_id);
        if (!id) continue;
        map.set(id, safeNumber(r.quantidade_atual));
      }
      return map;
    })(),
  ]);

  const enriched: EntradaEnrichedRow[] = movs.map((mov) => {
    const osId = safeNumber(mov.origem_os_id);
    return {
      mov,
      os: osId ? osMap.get(osId) ?? null : null,
      saldoAtual: saldoMap.has(safeNumber(mov.item_id)) ? (saldoMap.get(safeNumber(mov.item_id)) as number) : null,
    };
  });

  return { rows: enriched, count: Number(count ?? 0) };
}

export function parseCsvIds(value: string | null): number[] {
  return splitOrEmpty(String(value ?? ""))
    .map((x) => Number.parseInt(x, 10))
    .filter((n) => Number.isFinite(n) && n > 0);
}
