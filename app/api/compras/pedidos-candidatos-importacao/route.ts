import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../_lib";
import { getAllowedEmpresas } from "@/lib/auth/empresa";
import { supabaseAdmin } from "@/lib/supabase/admin";

export const runtime = "nodejs";

const PEDIDO_LOOKUP_ALLOWED_ROLES = new Set([
  "ADMIN",
  "DIRETOR",
  "FINANCEIRO",
  "FATURAMENTO",
  "COORDENACAO",
  "COMPRAS",
  "ALMOXARIFADO",
  "APONTAMENTO_RH",
]);
const OPEN_PEDIDO_STATUSES = ["ENVIADO", "PARCIAL_RECEBIDO"];

type PedidoRow = {
  id: string;
  codigo: string | null;
  status: string | null;
  fornecedor_id: number | null;
  solicitante_usuario_id: string | null;
  created_at: string | null;
  total_geral: number | string | null;
};

type PedidoItemRow = {
  id: string;
  pedido_compra_id: string;
  seq: number | null;
  item_id: number | string | null;
  item_codigo: string | null;
  item_nome: string | null;
  quantidade: number | string | null;
  quantidade_recebida: number | string | null;
  valor_unitario: number | string | null;
  valor_total: number | string | null;
  origem_os_id: number | null;
};

type OsLookupRow = {
  id: number;
  numero_os: string | number | null;
  os_num: string | number | null;
};

type CatalogItemRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  descricao: string | null;
};

function toNumber(value: unknown) {
  const n = Number(value ?? 0);
  return Number.isFinite(n) ? n : 0;
}

function clampLimit(value: string | null) {
  const n = Number(value ?? 20);
  if (!Number.isFinite(n)) return 20;
  return Math.min(50, Math.max(1, Math.trunc(n)));
}

async function canLookupPedidos(supabase: Parameters<typeof canCompras>[0], tenantId: string, empresaId: string) {
  const canReadCompras = await canCompras(supabase, "read");
  if (canReadCompras) return true;

  try {
    const allowed = await getAllowedEmpresas(supabase, tenantId);
    const empresa = allowed.find((e) => String(e.id) === empresaId);
    const role = String(empresa?.papel ?? "").trim().toUpperCase();
    return PEDIDO_LOOKUP_ALLOWED_ROLES.has(role);
  } catch {
    return false;
  }
}

export async function GET(req: NextRequest) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;

  const ctx = await resolveTenantEmpresa(supabase, undefined, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");

  if (!(await canLookupPedidos(supabase, ctx.tenantId, ctx.empresaId))) {
    return jsonError(403, "Sem permissao (compras.read).");
  }

  const fornecedorIdRaw = String(req.nextUrl.searchParams.get("fornecedorId") ?? "").trim();
  const fornecedorId = Number(fornecedorIdRaw);
  if (!Number.isFinite(fornecedorId) || fornecedorId <= 0) {
    return jsonError(400, "fornecedorId obrigatorio.");
  }

  const limit = clampLimit(req.nextUrl.searchParams.get("limit"));
  const db = supabaseAdmin();

  const { data: pedidosData, error: pedidosErr } = await db
    .schema("m")
    .from("pedido_compra")
    .select("id,codigo,status,fornecedor_id,solicitante_usuario_id,created_at,total_geral")
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .eq("fornecedor_id", fornecedorId)
    .in("status", OPEN_PEDIDO_STATUSES)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(limit)
    .returns<PedidoRow[]>();

  if (pedidosErr) return jsonError(400, pedidosErr.message);

  const pedidos = Array.isArray(pedidosData) ? pedidosData : [];
  if (pedidos.length === 0) return Response.json({ data: [] });

  const pedidoIds = pedidos.map((pedido) => pedido.id).filter(Boolean);

  const [{ data: fornecedorData, error: fornecedorErr }, { data: itensData, error: itensErr }] = await Promise.all([
    db
      .from("fornecedores")
      .select("id,nome")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .eq("id", fornecedorId)
      .maybeSingle<{ id: number; nome: string | null }>(),
    db
      .schema("m")
      .from("pedido_compra_item")
      .select("id,pedido_compra_id,seq,item_id,item_codigo,item_nome,quantidade,quantidade_recebida,valor_unitario,valor_total,origem_os_id")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .is("deleted_at", null)
      .in("pedido_compra_id", pedidoIds)
      .order("seq", { ascending: true })
      .returns<PedidoItemRow[]>(),
  ]);

  if (fornecedorErr) return jsonError(400, fornecedorErr.message);
  if (itensErr) return jsonError(400, itensErr.message);

  const itens = Array.isArray(itensData) ? itensData : [];
  const itemIds = Array.from(
    new Set(
      itens
        .map((item) => Number(item.item_id ?? 0))
        .filter((id) => Number.isFinite(id) && id > 0)
    )
  );

  const catalogById = new Map<number, CatalogItemRow>();
  if (itemIds.length > 0) {
    const { data: catalogData, error: catalogErr } = await db
      .from("itens")
      .select("id,codigo_interno,nome,descricao")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .in("id", itemIds)
      .returns<CatalogItemRow[]>();

    if (catalogErr) return jsonError(400, catalogErr.message);

    for (const row of Array.isArray(catalogData) ? catalogData : []) {
      const itemId = Number(row.id);
      if (Number.isFinite(itemId) && itemId > 0) catalogById.set(itemId, row);
    }
  }

  const osIds = Array.from(
    new Set(
      itens
        .map((item) => Number(item.origem_os_id ?? 0))
        .filter((id) => Number.isFinite(id) && id > 0)
    )
  );

  const osById = new Map<number, { numero: string | null; label: string }>();
  if (osIds.length > 0) {
    const { data: osData, error: osErr } = await db
      .from("ordens_servico")
      .select("id,numero_os,os_num")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .in("id", osIds)
      .returns<OsLookupRow[]>();

    if (osErr) return jsonError(400, osErr.message);

    for (const row of Array.isArray(osData) ? osData : []) {
      const osId = Number(row.id);
      if (!Number.isFinite(osId) || osId <= 0) continue;

      const numeroOs = String(row.numero_os ?? "").trim();
      const osNum = Number(row.os_num);
      const numero = numeroOs || (Number.isFinite(osNum) && osNum > 0 ? String(osNum) : null);
      osById.set(osId, {
        numero,
        label: numero ? `OS ${numero}` : `OS ${osId}`,
      });
    }
  }

  const itensByPedido = new Map<string, PedidoItemRow[]>();
  for (const item of itens) {
    const pedidoId = String(item.pedido_compra_id ?? "").trim();
    if (!pedidoId) continue;
    const current = itensByPedido.get(pedidoId) ?? [];
    current.push(item);
    itensByPedido.set(pedidoId, current);
  }

  const fornecedorNome = String(fornecedorData?.nome ?? "").trim() || null;

  const data = pedidos.map((pedido) => {
    const pedidoItens = itensByPedido.get(pedido.id) ?? [];
    let totalPendente = 0;

    const itensPayload = pedidoItens.map((item) => {
      const itemId = Number(item.item_id ?? 0);
      const catalogItem = Number.isFinite(itemId) && itemId > 0 ? catalogById.get(itemId) ?? null : null;
      const origemOsId = item.origem_os_id ?? null;
      const osInfo = origemOsId ? osById.get(Number(origemOsId)) ?? null : null;
      const quantidade = toNumber(item.quantidade);
      const quantidadeRecebida = toNumber(item.quantidade_recebida);
      const valorUnitario = toNumber(item.valor_unitario);
      const saldo = Math.max(0, quantidade - quantidadeRecebida);
      totalPendente += saldo * valorUnitario;

      const itemCodigo = String(item.item_codigo ?? catalogItem?.codigo_interno ?? "").trim() || null;
      const itemNome = String(item.item_nome ?? catalogItem?.nome ?? catalogItem?.descricao ?? "").trim() || null;
      const descricao = String(catalogItem?.descricao ?? itemNome ?? "").trim() || null;

      return {
        id: item.id,
        seq: item.seq ?? null,
        item_id: Number.isFinite(itemId) && itemId > 0 ? itemId : null,
        item_codigo: itemCodigo,
        item_nome: itemNome,
        descricao,
        quantidade: item.quantidade ?? null,
        quantidade_recebida: item.quantidade_recebida ?? null,
        valor_unitario: item.valor_unitario ?? null,
        valor_total: item.valor_total ?? null,
        origem_os_id: origemOsId,
        origem_os_numero: osInfo?.numero ?? null,
        origem_os_label: osInfo?.label ?? (origemOsId ? `OS ${origemOsId}` : null),
      };
    });

    return {
      id: pedido.id,
      codigo: pedido.codigo ?? null,
      status: pedido.status ?? null,
      fornecedor_id: pedido.fornecedor_id ?? null,
      fornecedor_nome: fornecedorNome,
      solicitante_usuario_id: pedido.solicitante_usuario_id ?? null,
      total_geral: pedido.total_geral ?? null,
      total_pendente: Math.round(totalPendente * 100) / 100,
      itens: itensPayload,
    };
  });

  return Response.json({ data });
}
