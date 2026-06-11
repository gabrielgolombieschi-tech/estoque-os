import { NextRequest } from "next/server";
import { getAuthSupabase, jsonError, resolveTenantEmpresa } from "@/app/api/compras/_lib";
import { isOrcamentoEditableStatus } from "@/lib/comercial/status";

export const runtime = "nodejs";

type AssistenteIAItemAceitoPayload = {
  linha: number;
  produtoId: string;
  qtd: number;
};

type AssistenteIAAdicionarItemAdicionado = {
  linha: number;
  produtoId: string;
  itemOrcamentoId?: string;
  mensagem: string;
};

type AssistenteIAAdicionarItemIgnorado = {
  linha: number;
  produtoId?: string;
  motivo: string;
};

type AssistenteIAAdicionarItemErro = {
  linha: number;
  produtoId?: string;
  erro: string;
};

type AssistenteIAAdicionarItemAviso = {
  linha: number;
  produtoId?: string;
  aviso: string;
};

type OrcamentoRow = {
  id: string;
  codigo: string | null;
  tenant_id: string;
  empresa_id: string;
  status: string | null;
};

type ItemRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  tipo: string | null;
  ativo: boolean | null;
  custo_ultima_compra: number | string | null;
  preco_unitario: number | string | null;
  mesclado_em_item_id: number | null;
};

type OrcamentoItemExistingRow = {
  id: string;
  item_id: number | null;
};

type AuthResult = Awaited<ReturnType<typeof getAuthSupabase>>;
type AuthedSupabase = Extract<AuthResult, { supabase: unknown }>["supabase"];

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_ROWS = 200;

function toNumber(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : NaN;
}

function roundMoney(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.round(value * 100) / 100;
}

function validatePayloadRows(value: unknown): AssistenteIAItemAceitoPayload[] | null {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_ROWS) return null;

  const rows: AssistenteIAItemAceitoPayload[] = [];
  for (const raw of value) {
    const row = raw as Record<string, unknown>;
    const linha = Number(row.linha);
    const qtd = Number(row.qtd);
    const produtoId = String(row.produtoId ?? "").trim();
    const produtoIdNumber = Number(produtoId);

    if (!Number.isInteger(linha) || linha <= 0) return null;
    if (!Number.isFinite(qtd) || qtd <= 0) return null;
    if (!Number.isInteger(produtoIdNumber) || produtoIdNumber <= 0) return null;

    rows.push({ linha, produtoId, qtd });
  }

  return rows;
}

async function canWriteOrcamento(supabase: AuthedSupabase): Promise<boolean> {
  const checks = await Promise.allSettled([
    supabase.rpc("can", { p_resource: "financeiro", p_action: "write" }),
    supabase.rpc("can", { p_resource: "os", p_action: "write" }),
  ]);
  return checks.some((result) => result.status === "fulfilled" && Boolean(result.value.data));
}

async function loadOrcamento(
  supabase: AuthedSupabase,
  params: { tenantId: string; empresaId: string; idOrCodigo: string }
): Promise<OrcamentoRow | null> {
  const raw = params.idOrCodigo.trim();
  if (!raw) return null;

  let query = supabase
    .schema("m")
    .from("orcamento")
    .select("id,codigo,tenant_id,empresa_id,status")
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId)
    .is("deleted_at", null)
    .limit(1);

  query = UUID_RE.test(raw) ? query.eq("id", raw) : query.eq("codigo", raw);

  const { data, error } = await query.maybeSingle<OrcamentoRow>();
  if (error) throw error;
  return data?.id ? data : null;
}

async function loadItems(
  supabase: AuthedSupabase,
  params: { tenantId: string; empresaId: string; produtoIds: number[] }
): Promise<Map<number, ItemRow>> {
  const ids = Array.from(new Set(params.produtoIds.filter((id) => Number.isInteger(id) && id > 0)));
  const result = new Map<number, ItemRow>();
  if (ids.length === 0) return result;

  const { data, error } = await supabase
    .from("itens")
    .select("id,codigo_interno,nome,tipo,ativo,custo_ultima_compra,preco_unitario,mesclado_em_item_id")
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId)
    .eq("ativo", true)
    .is("mesclado_em_item_id", null)
    .in("id", ids)
    .returns<ItemRow[]>();

  if (error) throw error;
  for (const item of data ?? []) {
    result.set(Number(item.id), item);
  }
  return result;
}

async function loadExistingItemIds(
  supabase: AuthedSupabase,
  params: { orcamentoId: string; produtoIds: number[] }
): Promise<Set<number>> {
  const ids = Array.from(new Set(params.produtoIds.filter((id) => Number.isInteger(id) && id > 0)));
  const result = new Set<number>();
  if (ids.length === 0) return result;

  const { data, error } = await supabase
    .schema("m")
    .from("orcamento_item")
    .select("id,item_id")
    .eq("orcamento_id", params.orcamentoId)
    .is("deleted_at", null)
    .in("item_id", ids)
    .returns<OrcamentoItemExistingRow[]>();

  if (error) throw error;
  for (const row of data ?? []) {
    const itemId = Number(row.item_id ?? 0);
    if (Number.isInteger(itemId) && itemId > 0) result.add(itemId);
  }
  return result;
}

async function getValorUnitarioSugerido(
  supabase: AuthedSupabase,
  params: { tenantId: string; empresaId: string; item: ItemRow }
): Promise<{ valorUnitario: number; aviso: string | null }> {
  const { data, error } = await supabase.schema("m").rpc("fn_orcamento_preco_sugerido_item", {
    p_tenant_id: params.tenantId,
    p_empresa_id: params.empresaId,
    p_custo_ultima_compra: params.item.custo_ultima_compra,
    p_preco_unitario: params.item.preco_unitario,
  });

  if (error) throw error;

  const valorUnitario = roundMoney(toNumber(data));
  if (!Number.isFinite(valorUnitario) || valorUnitario <= 0) {
    return { valorUnitario: 0, aviso: "Produto sem preço/custo para sugerir valor unitário. Inserido com valor 0." };
  }

  return { valorUnitario, aviso: null };
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
    const rows = validatePayloadRows(body.itens);
    if (!rows) return jsonError(400, "Itens aceitos invalidos.");

    const ctx = await resolveTenantEmpresa(supabase, body, req.nextUrl.searchParams);
    if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");

    if (!(await canWriteOrcamento(supabase))) return jsonError(403, "Sem permissao para adicionar itens ao orcamento.");

    const { id: rawId = "" } = await context.params;
    const idOrCodigo = decodeURIComponent(String(rawId ?? "")).trim();
    if (!idOrCodigo) return jsonError(400, "Orcamento invalido.");

    const orcamento = await loadOrcamento(supabase, { tenantId: ctx.tenantId, empresaId: ctx.empresaId, idOrCodigo });
    if (!orcamento) return jsonError(404, "Orcamento nao encontrado.");
    if (!isOrcamentoEditableStatus(orcamento.status)) {
      return jsonError(409, "Orcamento nao permite inclusao de itens neste status.");
    }

    const produtoIds = rows.map((row) => Number(row.produtoId));
    const [itemsById, existingItemIds] = await Promise.all([
      loadItems(supabase, { tenantId: ctx.tenantId, empresaId: ctx.empresaId, produtoIds }),
      loadExistingItemIds(supabase, { orcamentoId: orcamento.id, produtoIds }),
    ]);

    const adicionados: AssistenteIAAdicionarItemAdicionado[] = [];
    const ignorados: AssistenteIAAdicionarItemIgnorado[] = [];
    const erros: AssistenteIAAdicionarItemErro[] = [];
    const avisos: AssistenteIAAdicionarItemAviso[] = [];
    const produtoIdsProcessados = new Set<number>();

    for (const row of rows) {
      const produtoIdNumber = Number(row.produtoId);
      const produtoId = String(produtoIdNumber);

      if (produtoIdsProcessados.has(produtoIdNumber) || existingItemIds.has(produtoIdNumber)) {
        ignorados.push({
          linha: row.linha,
          produtoId,
          motivo: "Produto ja existe no orcamento. Revise manualmente.",
        });
        continue;
      }

      const item = itemsById.get(produtoIdNumber);
      if (!item?.id) {
        erros.push({
          linha: row.linha,
          produtoId,
          erro: "Produto invalido, inativo, mesclado ou fora do tenant/empresa atual.",
        });
        continue;
      }

      try {
        const { valorUnitario, aviso } = await getValorUnitarioSugerido(supabase, {
          tenantId: ctx.tenantId,
          empresaId: ctx.empresaId,
          item,
        });

        const { data, error } = await supabase
          .schema("m")
          .from("orcamento_item")
          .insert({
            tenant_id: ctx.tenantId,
            empresa_id: ctx.empresaId,
            orcamento_id: orcamento.id,
            item_id: produtoIdNumber,
            quantidade: row.qtd,
            valor_unitario: valorUnitario,
            desconto_item_percent: 0,
            observacoes: null,
          })
          .select("id")
          .single<{ id: string }>();

        if (error) throw error;

        produtoIdsProcessados.add(produtoIdNumber);
        adicionados.push({
          linha: row.linha,
          produtoId,
          itemOrcamentoId: data?.id ? String(data.id) : undefined,
          mensagem: "Item adicionado ao orcamento.",
        });

        if (aviso) avisos.push({ linha: row.linha, produtoId, aviso });
      } catch (e: unknown) {
        erros.push({
          linha: row.linha,
          produtoId,
          erro: errorMessage(e, "Erro ao adicionar item ao orcamento."),
        });
      }
    }

    return Response.json({
      adicionados,
      ignorados,
      erros,
      avisos,
      resumo: {
        totalSolicitado: rows.length,
        totalAdicionado: adicionados.length,
        totalIgnorado: ignorados.length,
        totalErro: erros.length,
      },
    });
  } catch (e: unknown) {
    return jsonError(400, errorMessage(e, "Erro ao adicionar itens aceitos."));
  }
}
