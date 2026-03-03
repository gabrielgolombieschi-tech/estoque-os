import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../../_lib";
import { getAllowedEmpresas } from "@/lib/auth/empresa";
import { supabaseAdmin } from "@/lib/supabase/admin";

export const runtime = "nodejs";

const ITEM_LOOKUP_ALLOWED_ROLES = new Set([
  "ADMIN",
  "FINANCEIRO",
  "COORDENACAO",
  "COMPRAS",
  "ALMOXARIFADO",
  "APONTAMENTO_RH",
]);

function toNum(v: unknown, def = 0): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : def;
}

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
  if (!codigo) return jsonError(400, "codigo obrigatorio.");

  const fornecedorIdRaw = String(req.nextUrl.searchParams.get("fornecedorId") ?? "").trim();
  const fornecedorId = fornecedorIdRaw ? Number(fornecedorIdRaw) : null;

  let item: Record<string, unknown> | null = null;

  const byCodigo = await db
    .from("itens")
    .select("id,codigo_interno,nome,descricao,unidade_medida,preco_unitario")
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .eq("codigo_interno", codigo)
    .limit(1)
    .maybeSingle();
  if (byCodigo.error) return jsonError(400, byCodigo.error.message);
  item = (byCodigo.data as Record<string, unknown> | null) ?? null;

  if (!item) {
    const codigoAsId = Number(codigo);
    if (Number.isFinite(codigoAsId) && codigoAsId > 0) {
      const byId = await db
        .from("itens")
        .select("id,codigo_interno,nome,descricao,unidade_medida,preco_unitario")
        .eq("tenant_id", ctx.tenantId)
        .eq("empresa_id", ctx.empresaId)
        .eq("id", codigoAsId)
        .limit(1)
        .maybeSingle();
      if (byId.error) return jsonError(400, byId.error.message);
      item = (byId.data as Record<string, unknown> | null) ?? null;
    }
  }

  if (!item) return jsonError(404, `Codigo de item nao encontrado: ${codigo}`);

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
  return Response.json({
    data: {
      item_id: itemId,
      item_codigo: String(item.codigo_interno ?? "").trim() || null,
      item_nome: itemNome || null,
      unidade,
      valor_unitario_cadastro: valorCadastro,
      valor_unitario_sugerido: valorSugerido,
    },
  });
}
