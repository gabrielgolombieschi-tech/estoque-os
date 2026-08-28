import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveItemByCodigoOuId, resolveTenantEmpresa } from "../../_lib";
import { getAllowedEmpresas } from "@/lib/auth/empresa";
import { supabaseAdmin } from "@/lib/supabase/admin";

export const runtime = "nodejs";

const ITEM_LOOKUP_ALLOWED_ROLES = new Set([
  "ADMIN",
  "DIRETOR",
  "FINANCEIRO",
  "FATURAMENTO",
  "COORDENACAO",
  "COMPRAS",
  "ALMOXARIFADO",
  "APONTAMENTO_RH",
]);

function toNum(v: unknown, def = 0): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : def;
}

type ItemLookupSearchRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  unidade_medida: string | null;
  preco_unitario: number | null;
  aliquota_ipi: number | null;
  fornecedor: string | null;
  ultima_entrada: string | null;
  estoque_atual: number | null;
};

export async function GET(req: NextRequest) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;

  const ctx = await resolveTenantEmpresa(supabase, undefined, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");

  const canReadCompras = await canCompras(supabase, "read");
  const canWriteCompras = await canCompras(supabase, "write");
  let canLookupByRole = false;
  if (!canReadCompras && !canWriteCompras) {
    try {
      const allowed = await getAllowedEmpresas(supabase, ctx.tenantId);
      const empresa = allowed.find((e) => String(e.id) === ctx.empresaId);
      const role = String(empresa?.papel ?? "").trim().toUpperCase();
      canLookupByRole = ITEM_LOOKUP_ALLOWED_ROLES.has(role);
    } catch {
      canLookupByRole = false;
    }
  }

  if (!canReadCompras && !canWriteCompras && !canLookupByRole) {
    return jsonError(403, "Sem permissao (compras.read).");
  }

  const db = canReadCompras || canWriteCompras ? supabase : supabaseAdmin();

  const codigo = String(req.nextUrl.searchParams.get("codigo") ?? "").trim();
  const nome = String(req.nextUrl.searchParams.get("nome") ?? "").trim();
  const fornecedor = String(req.nextUrl.searchParams.get("fornecedor") ?? "").trim();

  if (!codigo && !nome && !fornecedor) {
    return jsonError(400, "Informe codigo ou filtros de busca.");
  }

  const fornecedorIdRaw = String(req.nextUrl.searchParams.get("fornecedorId") ?? "").trim();
  const fornecedorId = fornecedorIdRaw ? Number(fornecedorIdRaw) : null;

  if (!codigo && (nome || fornecedor)) {
    // A RPC valida o acesso uma vez e consulta saldo/ultima entrada no banco.
    // A consulta direta por nome + fornecedor reavaliava RLS para cada linha e
    // podia ultrapassar o statement_timeout em empresas com muitos itens.
    const { data, error } = await supabase.rpc("search_os_itens", {
      p_tenant_id: ctx.tenantId,
      p_empresa_id: ctx.empresaId,
      p_term: nome || null,
      p_fornecedor: fornecedor || null,
      p_despesa_only: false,
      p_limit: 100,
    });
    if (error) return jsonError(400, error.message);

    const baseRows = (data ?? []) as ItemLookupSearchRow[];

    return Response.json({
      data: baseRows.map((row) => {
        const precoUnitario = Math.max(0, toNum(row.preco_unitario, 0));
        const aliquotaIpi = Math.max(0, toNum(row.aliquota_ipi, 0));
        return {
          id: Number(row.id),
          codigo_interno: String(row.codigo_interno ?? "").trim() || null,
          nome: String(row.nome ?? "").trim() || null,
          unidade: String(row.unidade_medida ?? "UN").trim() || "UN",
          fornecedor: String(row.fornecedor ?? "").trim() || null,
          ultima_entrada: row.ultima_entrada ?? null,
          preco_unitario: precoUnitario,
          aliquota_ipi: aliquotaIpi,
          valor_ipi_unitario: Math.round(precoUnitario * aliquotaIpi * 100) / 10000,
          estoque_atual: row.estoque_atual == null ? null : toNum(row.estoque_atual, 0),
        };
      }),
    });
  }

  if (!codigo) return jsonError(400, "codigo obrigatorio.");

  const itemResolved = await resolveItemByCodigoOuId(db, {
    tenantId: ctx.tenantId,
    empresaId: ctx.empresaId,
    codigo,
    fornecedorId,
  });
  if ("error" in itemResolved) {
    return jsonError(itemResolved.status ?? 400, itemResolved.error);
  }

  const item = itemResolved.data as Record<string, unknown>;
  const itemId = toNum(item.id, 0);
  if (!Number.isFinite(itemId) || itemId <= 0) {
    return jsonError(404, `Codigo de item nao encontrado: ${codigo}`);
  }

  const valorCadastro = Math.max(0, toNum(item.preco_unitario, 0));
  let valorSugerido = valorCadastro;

  if (Number.isFinite(fornecedorId) && (fornecedorId as number) > 0) {
    const pedidosRes = await db
      .schema("m")
      .from("pedido_compra")
      .select("id,created_at")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .eq("fornecedor_id", fornecedorId as number)
      .is("deleted_at", null)
      .neq("status", "CANCELADO")
      .order("created_at", { ascending: false })
      .limit(300);
    if (pedidosRes.error) return jsonError(400, pedidosRes.error.message);

    const pedidoIds = (pedidosRes.data ?? [])
      .map((p) => String((p as Record<string, unknown>).id ?? "").trim())
      .filter(Boolean);
    if (pedidoIds.length > 0) {
      const rankByPedidoId = new Map<string, number>();
      for (let i = 0; i < pedidoIds.length; i++) rankByPedidoId.set(pedidoIds[i], i);

      const itensRes = await db
        .schema("m")
        .from("pedido_compra_item")
        .select("pedido_compra_id,valor_unitario,created_at")
        .eq("tenant_id", ctx.tenantId)
        .eq("empresa_id", ctx.empresaId)
        .eq("item_id", itemId)
        .is("deleted_at", null)
        .in("pedido_compra_id", pedidoIds)
        .order("created_at", { ascending: false })
        .limit(2000);
      if (itensRes.error) return jsonError(400, itensRes.error.message);

      let best: { rank: number; createdAt: number; valor: number } | null = null;
      for (const row of (itensRes.data ?? []) as Array<Record<string, unknown>>) {
        const pedidoId = String(row.pedido_compra_id ?? "").trim();
        const rank = rankByPedidoId.get(pedidoId);
        if (rank == null) continue;
        const valor = toNum(row.valor_unitario, -1);
        if (!Number.isFinite(valor) || valor < 0) continue;
        const createdAt = Date.parse(String(row.created_at ?? ""));
        const createdKey = Number.isFinite(createdAt) ? createdAt : 0;
        if (!best || rank < best.rank || (rank === best.rank && createdKey > best.createdAt)) {
          best = { rank, createdAt: createdKey, valor };
        }
      }

      if (best && Number.isFinite(best.valor) && best.valor >= 0) {
        valorSugerido = best.valor;
      }
    }
  }

  const itemNome = String(item.nome ?? item.descricao ?? "").trim();
  const unidade = String(item.unidade_medida ?? "UN").trim() || "UN";
  const fiscalDb = supabaseAdmin();
  const { data: fiscalItem, error: fiscalItemErr } = await fiscalDb
    .from("fiscal_itens")
    .select("aliq_ipi")
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .eq("item_id", itemId)
    .maybeSingle<{ aliq_ipi: number | null }>();
  if (fiscalItemErr) return jsonError(400, fiscalItemErr.message);
  const aliquotaIpi = Math.max(0, toNum(fiscalItem?.aliq_ipi, 0));
  const valorIpiUnitario = Math.round(valorSugerido * aliquotaIpi * 100) / 10000;
  return Response.json({
    data: {
      item_id: itemId,
      item_codigo: String(item.codigo_interno ?? "").trim() || null,
      item_nome: itemNome || null,
      unidade,
      valor_unitario_cadastro: valorCadastro,
      valor_unitario_sugerido: valorSugerido,
      aliquota_ipi: aliquotaIpi,
      valor_ipi_unitario_sugerido: valorIpiUnitario,
    },
  });
}
