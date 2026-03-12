import { NextRequest } from "next/server";
import {
  calcPedidoItemValorTotal,
  canCompras,
  getAuthSupabase,
  jsonError,
  resolveItemByCodigoOuId,
  resolveTenantEmpresa,
  syncPedidoTotais,
} from "../../../_lib";

export const runtime = "nodejs";

function asNum(v: unknown, def = 0) {
  const n = Number(v ?? def);
  return Number.isFinite(n) ? n : def;
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;

  const { id } = await params;
  if (!id) return jsonError(400, "id obrigatorio.");

  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const ctx = await resolveTenantEmpresa(supabase, body, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");
  if (!(await canCompras(supabase, "write"))) return jsonError(403, "Sem permissao (compras.write).");

  const { data: pedido, error: pedidoErr } = await supabase
    .schema("m")
    .from("pedido_compra")
    .select("id,status,fornecedor_id")
    .eq("id", id)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .single();
  if (pedidoErr || !pedido) return jsonError(404, "Pedido nao encontrado.");

  const itemIdRaw = body.item_id ?? body.itemId ?? null;
  let itemId = itemIdRaw == null || String(itemIdRaw).trim() === "" ? null : Number(itemIdRaw);
  let itemNome = String(body.item_nome ?? body.itemNome ?? "").trim();
  const itemCodigo = String(body.item_codigo ?? body.itemCodigo ?? "").trim();
  const unidade = String(body.unidade ?? "UN").trim() || "UN";
  const quantidade = asNum(body.quantidade, 0);
  const valorUnitario = asNum(body.valor_unitario ?? body.valorUnitario, 0);
  const osIdRaw = body.origem_os_id ?? body.origemOsId ?? null;
  const osNumeroRaw = String(body.origem_os_numero ?? body.origemOsNumero ?? "").trim();

  if (itemId != null && (!Number.isFinite(itemId) || itemId <= 0)) {
    return jsonError(400, "item_id invalido.");
  }

  if (itemCodigo) {
    const itemResolved = await resolveItemByCodigoOuId(supabase, {
      tenantId: ctx.tenantId,
      empresaId: ctx.empresaId,
      codigo: itemCodigo,
      fornecedorId: Number((pedido as Record<string, unknown>).fornecedor_id ?? 0),
    });
    if ("error" in itemResolved) {
      return jsonError(itemResolved.status ?? 400, itemResolved.error);
    }

    const resolvedItemId = Number(itemResolved.data.id ?? 0);
    if (!Number.isFinite(resolvedItemId) || resolvedItemId <= 0) {
      return jsonError(404, `Codigo de item nao encontrado: ${itemCodigo}`);
    }

    if (itemId != null && Number.isFinite(itemId) && itemId > 0 && itemId !== resolvedItemId) {
      return jsonError(400, "item_id e item_codigo referenciam itens diferentes.");
    }

    itemId = resolvedItemId;
    if (!itemNome) itemNome = String(itemResolved.data.nome ?? itemResolved.data.descricao ?? "").trim();
  }

  if (!itemId && !itemNome) return jsonError(400, "Informe item_codigo existente, item_id ou item_nome.");
  if (quantidade <= 0) return jsonError(400, "Quantidade invalida.");
  if (valorUnitario < 0) return jsonError(400, "Valor unitario invalido.");
  const valorTotal = calcPedidoItemValorTotal(quantidade, valorUnitario);

  const status = String((pedido as { status?: string }).status ?? "");
  if (["APROVADO", "ENVIADO", "PARCIAL_RECEBIDO", "RECEBIDO", "CANCELADO"].includes(status)) {
    return jsonError(400, `Pedido em status ${status} nao permite incluir item.`);
  }

  let origemOsId: number | null = null;
  if (osIdRaw != null && String(osIdRaw).trim() !== "") {
    const parsed = Number(osIdRaw);
    origemOsId = Number.isFinite(parsed) && parsed > 0 ? parsed : null;
    if (!origemOsId) return jsonError(400, "origem_os_id invalido.");
  } else if (osNumeroRaw) {
    const { data: osByNumeroOs, error: osNumeroErr } = await supabase
      .from("ordens_servico")
      .select("id")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .eq("numero_os", osNumeroRaw)
      .limit(1)
      .maybeSingle();

    if (osNumeroErr) return jsonError(400, osNumeroErr.message);

    const idNumeroOs = Number((osByNumeroOs as Record<string, unknown> | null)?.id ?? 0);
    if (Number.isFinite(idNumeroOs) && idNumeroOs > 0) {
      origemOsId = idNumeroOs;
    } else {
      const osNumAsNumber = Number(osNumeroRaw);
      if (Number.isFinite(osNumAsNumber) && osNumAsNumber > 0) {
        const { data: osByOsNum, error: osNumErr } = await supabase
          .from("ordens_servico")
          .select("id")
          .eq("tenant_id", ctx.tenantId)
          .eq("empresa_id", ctx.empresaId)
          .eq("os_num", osNumAsNumber)
          .limit(1)
          .maybeSingle();
        if (osNumErr) return jsonError(400, osNumErr.message);
        const idOsNum = Number((osByOsNum as Record<string, unknown> | null)?.id ?? 0);
        origemOsId = Number.isFinite(idOsNum) && idOsNum > 0 ? idOsNum : null;
      }
    }

    if (!origemOsId) return jsonError(404, "OS nao encontrada para vinculo.");
  }

  const payload = {
    tenant_id: ctx.tenantId,
    empresa_id: ctx.empresaId,
    pedido_compra_id: id,
    item_id: itemId,
    item_nome: itemNome || "ITEM MANUAL",
    unidade,
    quantidade,
    valor_unitario: valorUnitario,
    valor_total: valorTotal,
    origem_os_id: origemOsId,
  };

  const { data, error } = await supabase
    .schema("m")
    .from("pedido_compra_item")
    .insert(payload)
    .select("*")
    .single();
  if (error) return jsonError(400, error.message);

  const syncResult = await syncPedidoTotais(supabase, id, ctx.tenantId, ctx.empresaId);
  if ("error" in syncResult) return jsonError(400, syncResult.error);

  return Response.json({ data });
}
