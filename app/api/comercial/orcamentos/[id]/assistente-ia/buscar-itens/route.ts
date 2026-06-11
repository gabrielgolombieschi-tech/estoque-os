import { NextRequest } from "next/server";
import { getAuthSupabase, jsonError, resolveTenantEmpresa } from "@/app/api/compras/_lib";

export const runtime = "nodejs";

type AssistenteIAStatusBusca = "encontrado_exato" | "encontrado_provavel" | "nao_encontrado";
type AssistenteIAStatusPreco = "preco_atualizado" | "preco_antigo" | "preco_muito_antigo" | "sem_historico";

type AssistenteIAItemPlanilha = {
  linha: number;
  qtd: number;
  componente: string;
  codigo: string;
  marca: string;
};

type AssistenteIAResultadoBusca = AssistenteIAItemPlanilha & {
  statusBusca: AssistenteIAStatusBusca;
  produtoId?: string;
  produtoCodigo?: string;
  produtoDescricao?: string;
  produtoMarca?: string;
  fornecedorNome?: string;
  confianca: number;
  ultimaCompraData?: string;
  ultimaCompraValorUnitario?: number;
  statusPreco: AssistenteIAStatusPreco;
  observacao: string;
};

type ItemRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  descricao: string | null;
  fabricante: string | null;
  fornecedor_id: number | null;
  fornecedores?: { nome?: string | null } | Array<{ nome?: string | null }> | null;
};

type PedidoItemRow = {
  pedido_compra_id: string | null;
  item_id: number | null;
  valor_unitario: number | string | null;
  created_at: string | null;
};

type PedidoCompraRow = {
  id: string;
  created_at: string | null;
  status: string | null;
};

type UltimaCompra = {
  data: string;
  valorUnitario: number;
};

type AuthResult = Awaited<ReturnType<typeof getAuthSupabase>>;
type AuthedSupabase = Extract<AuthResult, { supabase: unknown }>["supabase"];

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{12}$/i;
const MAX_ROWS = 200;

function normalizeCode(value: unknown): string {
  return String(value ?? "")
    .trim()
    .toUpperCase()
    .replace(/[\s.\-/]/g, "");
}

function normalizeText(value: unknown): string {
  return String(value ?? "")
    .trim()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
}

function toNumber(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : NaN;
}

function extractDescriptionTerms(value: string): string[] {
  const ignored = new Set(["COM", "PARA", "DOS", "DAS", "POR", "UMA", "UNO", "UND", "UN", "MM", "CM"]);
  return Array.from(
    new Set(
      normalizeText(value)
        .replace(/[^A-Z0-9]+/g, " ")
        .split(/\s+/)
        .map((term) => term.trim())
        .filter((term) => term.length >= 3 && !ignored.has(term))
    )
  ).slice(0, 8);
}

function getFornecedorNome(row: ItemRow): string | null {
  const raw = row.fornecedores ?? null;
  const fornecedor = Array.isArray(raw) ? raw[0] ?? null : raw;
  const nome = String(fornecedor?.nome ?? "").trim();
  return nome || null;
}

function itemDescription(row: ItemRow): string {
  return String(row.nome ?? row.descricao ?? "").trim() || String(row.codigo_interno ?? "").trim() || `Item ${row.id}`;
}

function brandMatches(planilhaMarca: string, item: ItemRow): boolean {
  const marca = normalizeText(planilhaMarca);
  if (!marca) return false;
  const fabricante = normalizeText(item.fabricante);
  const fornecedor = normalizeText(getFornecedorNome(item));
  return Boolean((fabricante && fabricante.includes(marca)) || (fornecedor && fornecedor.includes(marca)));
}

function buildItemCodeMap(items: ItemRow[]): Map<string, ItemRow[]> {
  const map = new Map<string, ItemRow[]>();
  for (const item of items) {
    const code = normalizeCode(item.codigo_interno);
    if (!code) continue;
    const list = map.get(code) ?? [];
    list.push(item);
    map.set(code, list);
  }
  return map;
}

function pickExactCodeMatch(candidates: ItemRow[], marca: string): ItemRow {
  if (!marca.trim()) return candidates[0];
  return candidates.find((item) => brandMatches(marca, item)) ?? candidates[0];
}

function scoreDescriptionMatch(item: ItemRow, source: AssistenteIAItemPlanilha): number {
  const terms = extractDescriptionTerms(source.componente);
  if (terms.length === 0) return 0;
  const itemText = normalizeText(`${item.nome ?? ""} ${item.descricao ?? ""} ${item.codigo_interno ?? ""}`);
  const matches = terms.filter((term) => itemText.includes(term)).length;
  const minMatches = Math.min(2, terms.length);
  if (matches < minMatches) return 0;

  const marca = normalizeText(source.marca);
  const matchedBrand = brandMatches(source.marca, item);
  if (marca && !matchedBrand) return 0;

  const ratio = matches / terms.length;
  return Math.min(80, Math.round(60 + ratio * 10 + (matchedBrand ? 10 : 0)));
}

function findProbableMatch(items: ItemRow[], source: AssistenteIAItemPlanilha): { item: ItemRow; confianca: number } | null {
  let best: { item: ItemRow; confianca: number } | null = null;
  for (const item of items) {
    const confianca = scoreDescriptionMatch(item, source);
    if (confianca <= 0) continue;
    if (!best || confianca > best.confianca) best = { item, confianca };
  }
  return best;
}

function classifyPriceStatus(ultimaCompra: UltimaCompra | null): AssistenteIAStatusPreco {
  if (!ultimaCompra?.data) return "sem_historico";
  const time = Date.parse(ultimaCompra.data);
  if (!Number.isFinite(time)) return "sem_historico";
  const diffMs = Date.now() - time;
  const months = diffMs / (1000 * 60 * 60 * 24 * 30.4375);
  if (months <= 12) return "preco_atualizado";
  if (months <= 24) return "preco_antigo";
  return "preco_muito_antigo";
}

function buildObservation(statusBusca: AssistenteIAStatusBusca, statusPreco: AssistenteIAStatusPreco): string {
  if (statusBusca === "nao_encontrado") {
    return "Produto não encontrado no banco. Recomenda-se cotação ou cadastro.";
  }
  if (statusBusca === "encontrado_provavel") {
    return "Produto semelhante encontrado. Revisar antes de usar.";
  }
  if (statusPreco === "preco_atualizado") {
    return "Produto encontrado no banco com preço recente.";
  }
  if (statusPreco === "preco_antigo") {
    return "Produto encontrado, mas a última compra tem mais de 12 meses. Recomenda-se atualizar o preço.";
  }
  if (statusPreco === "preco_muito_antigo") {
    return "Produto encontrado, mas a última compra tem mais de 24 meses. Recomenda-se nova cotação.";
  }
  return "Produto encontrado, mas sem histórico de compra.";
}

function validatePayloadRows(value: unknown): AssistenteIAItemPlanilha[] | null {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_ROWS) return null;

  const rows: AssistenteIAItemPlanilha[] = [];
  for (const raw of value) {
    const row = raw as Record<string, unknown>;
    const linha = Number(row.linha);
    const qtd = Number(row.qtd);
    const componente = String(row.componente ?? "").trim();
    const codigo = String(row.codigo ?? "").trim();
    const marca = String(row.marca ?? "").trim();

    if (!Number.isFinite(linha) || linha <= 0) return null;
    if (!Number.isFinite(qtd) || qtd <= 0) return null;
    if (!componente) return null;

    rows.push({ linha, qtd, componente, codigo, marca });
  }
  return rows;
}

async function canReadOrcamento(supabase: AuthedSupabase) {
  const checks = await Promise.allSettled([
    supabase.rpc("can", { p_resource: "financeiro", p_action: "read" }),
    supabase.rpc("can", { p_resource: "financeiro", p_action: "write" }),
    supabase.rpc("can", { p_resource: "os", p_action: "read" }),
    supabase.rpc("can", { p_resource: "os", p_action: "write" }),
  ]);
  return checks.some((result) => result.status === "fulfilled" && Boolean(result.value.data));
}

async function ensureOrcamentoExists(
  supabase: AuthedSupabase,
  params: { tenantId: string; empresaId: string; idOrCodigo: string }
): Promise<boolean> {
  const raw = params.idOrCodigo.trim();
  if (!raw) return false;

  let query = supabase
    .schema("m")
    .from("orcamento")
    .select("id")
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId)
    .is("deleted_at", null)
    .limit(1);

  query = UUID_RE.test(raw) ? query.eq("id", raw) : query.eq("codigo", raw);

  const { data, error } = await query.maybeSingle<{ id: string }>();
  if (error) throw error;
  return Boolean(data?.id);
}

async function loadItems(
  supabase: AuthedSupabase,
  tenantId: string,
  empresaId: string
): Promise<ItemRow[]> {
  const { data, error } = await supabase
    .from("itens")
    .select(
      "id,codigo_interno,nome,descricao,fabricante,fornecedor_id,fornecedores!itens_tenant_empresa_fornecedor_fk(nome)"
    )
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .eq("ativo", true)
    .is("mesclado_em_item_id", null)
    .order("nome", { ascending: true })
    .limit(10000)
    .returns<ItemRow[]>();

  if (error) throw error;
  return data ?? [];
}

async function loadUltimasCompras(
  supabase: AuthedSupabase,
  params: { tenantId: string; empresaId: string; itemIds: number[] }
): Promise<Map<number, UltimaCompra>> {
  const itemIds = Array.from(new Set(params.itemIds.filter((id) => Number.isFinite(id) && id > 0)));
  const result = new Map<number, UltimaCompra>();
  if (itemIds.length === 0) return result;

  const { data: itemRows, error: itemErr } = await supabase
    .schema("m")
    .from("pedido_compra_item")
    .select("pedido_compra_id,item_id,valor_unitario,created_at")
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId)
    .is("deleted_at", null)
    .in("item_id", itemIds)
    .order("created_at", { ascending: false })
    .limit(5000)
    .returns<PedidoItemRow[]>();
  if (itemErr) throw itemErr;

  const rows = itemRows ?? [];
  const pedidoIds = Array.from(new Set(rows.map((row) => String(row.pedido_compra_id ?? "").trim()).filter(Boolean)));
  const pedidoById = new Map<string, PedidoCompraRow>();

  if (pedidoIds.length > 0) {
    const { data: pedidos, error: pedidosErr } = await supabase
      .schema("m")
      .from("pedido_compra")
      .select("id,created_at,status")
      .eq("tenant_id", params.tenantId)
      .eq("empresa_id", params.empresaId)
      .is("deleted_at", null)
      .in("id", pedidoIds)
      .returns<PedidoCompraRow[]>();
    if (pedidosErr) throw pedidosErr;
    for (const pedido of pedidos ?? []) {
      pedidoById.set(String(pedido.id), pedido);
    }
  }

  for (const row of rows) {
    const itemId = Number(row.item_id ?? 0);
    if (!Number.isFinite(itemId) || itemId <= 0 || result.has(itemId)) continue;

    const pedido = pedidoById.get(String(row.pedido_compra_id ?? ""));
    if (pedido && String(pedido.status ?? "").trim().toUpperCase() === "CANCELADO") continue;

    const valorUnitario = toNumber(row.valor_unitario);
    if (!Number.isFinite(valorUnitario) || valorUnitario < 0) continue;

    const data = String(pedido?.created_at ?? row.created_at ?? "").trim();
    if (!data) continue;

    result.set(itemId, { data, valorUnitario });
  }

  return result;
}

function buildResultRow(
  source: AssistenteIAItemPlanilha,
  item: ItemRow | null,
  opts: { statusBusca: AssistenteIAStatusBusca; confianca: number; ultimaCompra: UltimaCompra | null }
): AssistenteIAResultadoBusca {
  const statusPreco = classifyPriceStatus(opts.ultimaCompra);
  if (!item) {
    return {
      ...source,
      statusBusca: "nao_encontrado",
      confianca: 0,
      statusPreco: "sem_historico",
      observacao: buildObservation("nao_encontrado", "sem_historico"),
    };
  }

  return {
    ...source,
    statusBusca: opts.statusBusca,
    produtoId: String(item.id),
    produtoCodigo: String(item.codigo_interno ?? "").trim() || undefined,
    produtoDescricao: itemDescription(item),
    produtoMarca: String(item.fabricante ?? "").trim() || undefined,
    fornecedorNome: getFornecedorNome(item) ?? undefined,
    confianca: opts.confianca,
    ultimaCompraData: opts.ultimaCompra?.data,
    ultimaCompraValorUnitario: opts.ultimaCompra?.valorUnitario,
    statusPreco,
    observacao: buildObservation(opts.statusBusca, statusPreco),
  };
}

function errorMessage(error: unknown, fallback: string): string {
  if (error instanceof Error && error.message) return error.message;
  if (typeof error === "object" && error !== null && "message" in error) {
    return String((error as { message?: unknown }).message ?? fallback);
  }
  return fallback;
}

export async function POST(req: NextRequest, context: { params: Promise<{ id?: string }> }) {
  try {
    const auth = await getAuthSupabase(req);
    if ("error" in auth) return auth.error;
    const { supabase } = auth;

    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const ctx = await resolveTenantEmpresa(supabase, body, req.nextUrl.searchParams);
    if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");

    if (!(await canReadOrcamento(supabase))) return jsonError(403, "Sem permissao para consultar itens do orcamento.");

    const { id: rawId = "" } = await context.params;
    const idOrCodigo = decodeURIComponent(String(rawId ?? "")).trim();
    if (!idOrCodigo) return jsonError(400, "Orcamento invalido.");

    const exists = await ensureOrcamentoExists(supabase, { tenantId: ctx.tenantId, empresaId: ctx.empresaId, idOrCodigo });
    if (!exists) return jsonError(404, "Orcamento nao encontrado.");

    const rows = validatePayloadRows(body.itens);
    if (!rows) return jsonError(400, "Itens da planilha invalidos.");

    const items = await loadItems(supabase, ctx.tenantId, ctx.empresaId);
    const byCode = buildItemCodeMap(items);

    const itemByLinha = new Map<number, { item: ItemRow; statusBusca: AssistenteIAStatusBusca; confianca: number }>();
    const foundIds: number[] = [];

    for (const row of rows) {
      const normalizedCode = normalizeCode(row.codigo);
      const exactCandidates = normalizedCode ? byCode.get(normalizedCode) ?? [] : [];
      if (exactCandidates.length > 0) {
        const item = pickExactCodeMatch(exactCandidates, row.marca);
        const confianca = row.marca.trim() && brandMatches(row.marca, item) ? 100 : 90;
        itemByLinha.set(row.linha, { item, statusBusca: "encontrado_exato", confianca });
        foundIds.push(Number(item.id));
        continue;
      }

      const probable = findProbableMatch(items, row);
      if (probable) {
        itemByLinha.set(row.linha, { item: probable.item, statusBusca: "encontrado_provavel", confianca: probable.confianca });
        foundIds.push(Number(probable.item.id));
      }
    }

    const ultimasCompras = await loadUltimasCompras(supabase, { tenantId: ctx.tenantId, empresaId: ctx.empresaId, itemIds: foundIds });
    const resultados = rows.map((row) => {
      const match = itemByLinha.get(row.linha);
      if (!match) return buildResultRow(row, null, { statusBusca: "nao_encontrado", confianca: 0, ultimaCompra: null });
      return buildResultRow(row, match.item, {
        statusBusca: match.statusBusca,
        confianca: match.confianca,
        ultimaCompra: ultimasCompras.get(Number(match.item.id)) ?? null,
      });
    });

    return Response.json({ resultados });
  } catch (e: unknown) {
    return jsonError(500, errorMessage(e, "Erro ao buscar itens no banco."));
  }
}
