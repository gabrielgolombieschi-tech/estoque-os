import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveItemByCodigoOuId, resolveTenantEmpresa } from "../../_lib";
import { getAllowedEmpresas } from "@/lib/auth/empresa";
import { supabaseAdmin } from "@/lib/supabase/admin";

export const runtime = "nodejs";

const ITEM_LOOKUP_ALLOWED_ROLES = new Set([
  "ADMIN",
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

type ItemLookupBaseRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  unidade_medida: string | null;
  preco_unitario: number | null;
  fornecedores?: { nome?: string | null } | Array<{ nome?: string | null }> | null;
};

type FiscalItemRow = {
  item_id: number;
  aliq_ipi: number | null;
};

type MovRow = {
  item_id: number;
  data_movimentacao: string;
};

type EstoqueRow = {
  item_id: number;
  quantidade_atual: number | null;
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
    const baseSelect = fornecedor
      ? "id,codigo_interno,nome,unidade_medida,preco_unitario,fornecedores!itens_tenant_empresa_fornecedor_fk!inner(nome)"
      : "id,codigo_interno,nome,unidade_medida,preco_unitario,fornecedores!itens_tenant_empresa_fornecedor_fk(nome)";

    let query = db
      .from("itens")
      .select(baseSelect)
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .eq("ativo", true);

    if (nome) {
      const termo = nome.replace(/[%]/g, "").trim();
      if (termo) {
        query = query.or(`nome.ilike.%${termo}%,codigo_interno.ilike.%${termo}%`);
      }
    }

    if (fornecedor) {
      query = query.ilike("fornecedores.nome", `%${fornecedor}%`);
    }

    const { data, error } = await query.order("nome", { ascending: true }).limit(100);
    if (error) return jsonError(400, error.message);

    const baseRows = (data ?? []) as ItemLookupBaseRow[];
    const itemIds = baseRows
      .map((row) => Number(row.id))
      .filter((id) => Number.isFinite(id) && id > 0);

    const ultimaEntradaPorItem = new Map<number, string>();
    const saldoPorItem = new Map<number, number>();
    const aliquotaIpiPorItem = new Map<number, number>();

    if (itemIds.length > 0) {
      const fiscalDb = supabaseAdmin();
      const [movRes, estoqueRes, fiscalRes] = await Promise.all([
        db
          .from("movimentacoes")
          .select("item_id,data_movimentacao")
          .eq("tenant_id", ctx.tenantId)
          .eq("empresa_id", ctx.empresaId)
          .eq("tipo", "entrada")
          .in("item_id", itemIds)
          .order("data_movimentacao", { ascending: false }),
        db
          .from("estoque")
          .select("item_id,quantidade_atual")
          .eq("tenant_id", ctx.tenantId)
          .eq("empresa_id", ctx.empresaId)
          .in("item_id", itemIds),
        fiscalDb
          .from("fiscal_itens")
          .select("item_id,aliq_ipi")
          .eq("tenant_id", ctx.tenantId)
          .eq("empresa_id", ctx.empresaId)
          .in("item_id", itemIds),
      ]);

      if (!movRes.error) {
        ((movRes.data ?? []) as MovRow[]).forEach((row) => {
          if (!ultimaEntradaPorItem.has(row.item_id)) {
            ultimaEntradaPorItem.set(row.item_id, row.data_movimentacao);
          }
        });
      }

      const { data: estoqueData, error: estoqueErr } = estoqueRes;
      if (!estoqueErr) {
        ((estoqueData ?? []) as EstoqueRow[]).forEach((row) => {
          saldoPorItem.set(row.item_id, Number(row.quantidade_atual ?? 0));
        });
      }

      if (!fiscalRes.error) {
        ((fiscalRes.data ?? []) as FiscalItemRow[]).forEach((row) => {
          aliquotaIpiPorItem.set(row.item_id, Math.max(0, toNum(row.aliq_ipi, 0)));
        });
      }
    }

    return Response.json({
      data: baseRows.map((row) => {
        const fornecedorNome = Array.isArray(row.fornecedores)
          ? String(row.fornecedores[0]?.nome ?? "").trim() || null
          : String(row.fornecedores?.nome ?? "").trim() || null;

        const precoUnitario = Math.max(0, toNum(row.preco_unitario, 0));
        const aliquotaIpi = aliquotaIpiPorItem.get(Number(row.id)) ?? 0;
        return {
          id: Number(row.id),
          codigo_interno: String(row.codigo_interno ?? "").trim() || null,
          nome: String(row.nome ?? "").trim() || null,
          unidade: String(row.unidade_medida ?? "UN").trim() || "UN",
          fornecedor: fornecedorNome,
          ultima_entrada: ultimaEntradaPorItem.get(Number(row.id)) ?? null,
          preco_unitario: precoUnitario,
          aliquota_ipi: aliquotaIpi,
          valor_ipi_unitario: Math.round(precoUnitario * aliquotaIpi * 100) / 10000,
          estoque_atual: saldoPorItem.has(Number(row.id)) ? saldoPorItem.get(Number(row.id)) ?? 0 : null,
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
