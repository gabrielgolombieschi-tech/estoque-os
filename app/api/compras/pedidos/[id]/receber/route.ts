import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../../../_lib";
import { supabaseAdmin } from "@/lib/supabase/admin";

export const runtime = "nodejs";

function isMissingReceberWithSkipSignature(message: string) {
  const msg = String(message ?? "").toLowerCase();
  return msg.includes("could not find the function m.fn_pedido_compra_receber") && msg.includes("p_skip_movimentacao");
}

function toPositiveNumber(value: unknown) {
  const n = Number(value ?? 0);
  return Number.isFinite(n) && n > 0 ? n : null;
}

async function registrarRecebimentoSemMovimentacao(opts: {
  pedidoId: string;
  tenantId: string;
  empresaId: string;
  recebimentoDate: unknown;
  documentoRef: unknown;
  observacoes: unknown;
  itens: unknown[];
}) {
  const admin = supabaseAdmin();
  const pedidoId = String(opts.pedidoId ?? "").trim();
  const tenantId = String(opts.tenantId ?? "").trim();
  const empresaId = String(opts.empresaId ?? "").trim();
  const documentoRef = String(opts.documentoRef ?? "").trim();
  const observacoes = String(opts.observacoes ?? "").trim() || null;
  const recebimentoDate = String(opts.recebimentoDate ?? "").trim() || new Date().toISOString().slice(0, 10);

  const requestedByItemId = new Map<string, number>();
  for (const raw of opts.itens) {
    const row = (raw ?? {}) as Record<string, unknown>;
    const pedidoItemId = String(row.pedidoItemId ?? row.pedido_item_id ?? "").trim();
    const quantidade = toPositiveNumber(row.quantidade);
    if (!pedidoItemId || !quantidade) throw new Error("Item invalido no recebimento.");
    requestedByItemId.set(pedidoItemId, (requestedByItemId.get(pedidoItemId) ?? 0) + quantidade);
  }

  const pedidoItemIds = Array.from(requestedByItemId.keys());
  const { data: pedido, error: pedidoErr } = await admin
    .schema("m")
    .from("pedido_compra")
    .select("id,status,codigo,tenant_id,empresa_id")
    .eq("id", pedidoId)
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .is("deleted_at", null)
    .single();
  if (pedidoErr || !pedido) throw new Error(pedidoErr?.message ?? "Pedido nao encontrado.");

  const { data: itemRows, error: itemErr } = await admin
    .schema("m")
    .from("pedido_compra_item")
    .select("id,item_id,quantidade,quantidade_recebida")
    .eq("pedido_compra_id", pedidoId)
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .is("deleted_at", null)
    .in("id", pedidoItemIds);
  if (itemErr) throw new Error(itemErr.message);

  const itemById = new Map<string, Record<string, unknown>>();
  for (const row of Array.isArray(itemRows) ? (itemRows as Array<Record<string, unknown>>) : []) {
    const itemId = String(row.id ?? "").trim();
    if (itemId) itemById.set(itemId, row);
  }

  for (const [pedidoItemId, quantidade] of requestedByItemId.entries()) {
    const item = itemById.get(pedidoItemId);
    if (!item) throw new Error("Pedido item nao encontrado para recebimento.");
    const saldo = Math.max(0, Number(item.quantidade ?? 0) - Number(item.quantidade_recebida ?? 0));
    if (quantidade - saldo > 1e-9) throw new Error("Quantidade excede saldo.");
  }

  const { data: recebimento, error: recebErr } = await admin
    .schema("m")
    .from("pedido_compra_recebimento")
    .insert({
      tenant_id: tenantId,
      empresa_id: empresaId,
      pedido_compra_id: pedidoId,
      recebimento_date: recebimentoDate,
      documento_ref: documentoRef,
      observacoes,
      updated_by: null,
    })
    .select("id")
    .single();
  if (recebErr || !recebimento?.id) throw new Error(recebErr?.message ?? "Falha ao criar recebimento do pedido.");

  const recebimentoId = String(recebimento.id);
  const recebimentoItens = Array.from(requestedByItemId.entries()).map(([pedidoItemId, quantidade]) => {
    const item = itemById.get(pedidoItemId) ?? {};
    return {
      tenant_id: tenantId,
      empresa_id: empresaId,
      recebimento_id: recebimentoId,
      pedido_compra_item_id: pedidoItemId,
      item_id: item.item_id ?? null,
      quantidade,
    };
  });
  const { error: recebItemErr } = await admin
    .schema("m")
    .from("pedido_compra_recebimento_item")
    .insert(recebimentoItens);
  if (recebItemErr) throw new Error(recebItemErr.message);

  for (const [pedidoItemId, quantidade] of requestedByItemId.entries()) {
    const item = itemById.get(pedidoItemId) ?? {};
    const novaQuantidadeRecebida = Number(item.quantidade_recebida ?? 0) + quantidade;
    const { error: updItemErr } = await admin
      .schema("m")
      .from("pedido_compra_item")
      .update({
        quantidade_recebida: novaQuantidadeRecebida,
        updated_by: null,
      })
      .eq("id", pedidoItemId)
      .eq("pedido_compra_id", pedidoId)
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .is("deleted_at", null);
    if (updItemErr) throw new Error(updItemErr.message);
  }

  const { data: pedidoItensAtualizados, error: allItensErr } = await admin
    .schema("m")
    .from("pedido_compra_item")
    .select("id,quantidade,quantidade_recebida")
    .eq("pedido_compra_id", pedidoId)
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .is("deleted_at", null);
  if (allItensErr) throw new Error(allItensErr.message);

  const allReceived = (Array.isArray(pedidoItensAtualizados) ? pedidoItensAtualizados : []).every(
    (row) => Number(row.quantidade_recebida ?? 0) + 1e-9 >= Number(row.quantidade ?? 0)
  );
  const nextStatus = allReceived ? "RECEBIDO" : "PARCIAL_RECEBIDO";

  const { error: updPedidoErr } = await admin
    .schema("m")
    .from("pedido_compra")
    .update({
      status: nextStatus,
      updated_by: null,
    })
    .eq("id", pedidoId)
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .is("deleted_at", null);
  if (updPedidoErr) throw new Error(updPedidoErr.message);

  const { error: eventoErr } = await admin
    .schema("m")
    .from("pedido_compra_evento")
    .insert({
      tenant_id: tenantId,
      empresa_id: empresaId,
      pedido_compra_id: pedidoId,
      tipo: "RECEBIMENTO",
      status_de: String(pedido.status ?? "").trim() || null,
      status_para: nextStatus,
      mensagem: observacoes || "Conciliacao manual de recebimento sem movimentacao de estoque",
      created_by: null,
    });
  if (eventoErr) throw new Error(eventoErr.message);

  const { data: origensRows, error: origensErr } = await admin
    .schema("m")
    .from("pedido_compra_item_origem")
    .select("pedido_compra_item_id,pendencia_id")
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .is("deleted_at", null)
    .in("pedido_compra_item_id", pedidoItemIds);
  if (origensErr) throw new Error(origensErr.message);

  const pendenciaIds = Array.from(
    new Set(
      (Array.isArray(origensRows) ? origensRows : [])
        .map((row) => String(row.pendencia_id ?? "").trim())
        .filter(Boolean)
    )
  );

  if (pendenciaIds.length > 0) {
    const { data: allOrigemRows, error: allOrigensErr } = await admin
      .schema("m")
      .from("pedido_compra_item_origem")
      .select("pedido_compra_item_id,pendencia_id")
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .is("deleted_at", null)
      .in("pendencia_id", pendenciaIds);
    if (allOrigensErr) throw new Error(allOrigensErr.message);

    const allPedidoItemIds = Array.from(
      new Set(
        (Array.isArray(allOrigemRows) ? allOrigemRows : [])
          .map((row) => String(row.pedido_compra_item_id ?? "").trim())
          .filter(Boolean)
      )
    );

    const { data: origemItensRows, error: origemItensErr } = await admin
      .schema("m")
      .from("pedido_compra_item")
      .select("id,quantidade,quantidade_recebida")
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .is("deleted_at", null)
      .in("id", allPedidoItemIds);
    if (origemItensErr) throw new Error(origemItensErr.message);

    const itemStatusById = new Map<string, { quantidade: number; quantidade_recebida: number }>();
    for (const row of Array.isArray(origemItensRows) ? origemItensRows : []) {
      const itemId = String(row.id ?? "").trim();
      if (!itemId) continue;
      itemStatusById.set(itemId, {
        quantidade: Number(row.quantidade ?? 0),
        quantidade_recebida: Number(row.quantidade_recebida ?? 0),
      });
    }

    const concluidas = pendenciaIds.filter((pendenciaId) => {
      const ligados = (Array.isArray(allOrigemRows) ? allOrigemRows : []).filter(
        (row) => String(row.pendencia_id ?? "").trim() === pendenciaId
      );
      if (!ligados.length) return false;
      return ligados.every((row) => {
        const itemId = String(row.pedido_compra_item_id ?? "").trim();
        const status = itemStatusById.get(itemId);
        return Boolean(status) && status.quantidade_recebida + 1e-9 >= status.quantidade;
      });
    });

    if (concluidas.length > 0) {
      const { error: pendErr } = await admin
        .schema("m")
        .from("compra_pendencia")
        .update({
          status: "CONCLUIDO",
          concluido_em: new Date().toISOString(),
          updated_by: null,
        })
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .eq("status", "EM_PEDIDO")
        .is("deleted_at", null)
        .in("id", concluidas);
      if (pendErr) throw new Error(pendErr.message);
    }
  }

  return recebimentoId;
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;
  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const { id } = await params;
  const ctx = await resolveTenantEmpresa(supabase, body, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");
  const canReceiveCompras = await canCompras(supabase, "receive");
  const { data: canWriteEstoqueRaw } = await supabase.rpc("can", { p_resource: "estoque", p_action: "write" });
  const canWriteEstoque = Boolean(canWriteEstoqueRaw);
  if (!canReceiveCompras && !canWriteEstoque) return jsonError(403, "Sem permissao para registrar recebimento.");

  const itens = (Array.isArray(body.itens) ? body.itens : []) as unknown[];
  if (!itens.length) return jsonError(400, "itens obrigatorio.");
  const skipStockMovement = Boolean(body.skipStockMovement ?? body.skip_stock_movement ?? false);
  const documentoRef = body.documentoRef ?? body.documento_ref ?? null;
  if (skipStockMovement && !String(documentoRef ?? "").trim()) {
    return jsonError(400, "Informe a NF/documento para conciliar o recebimento.");
  }
  if (!skipStockMovement && !canReceiveCompras) {
    return jsonError(403, "Sem permissao para receber com movimentacao de estoque.");
  }

  const rpcArgs = {
    p_pedido_id: id,
    p_recebimento_date: body.recebimentoDate ?? body.recebimento_date ?? null,
    p_documento_ref: documentoRef,
    p_observacoes: body.observacoes ?? null,
    p_itens: itens,
    p_skip_movimentacao: skipStockMovement,
  };

  let { data, error } = await supabase.schema("m").rpc("fn_pedido_compra_receber", rpcArgs);
  if (error && isMissingReceberWithSkipSignature(error.message ?? "")) {
    if (skipStockMovement) {
      try {
        const recebimentoId = await registrarRecebimentoSemMovimentacao({
          pedidoId: id,
          tenantId: ctx.tenantId,
          empresaId: ctx.empresaId,
          recebimentoDate: body.recebimentoDate ?? body.recebimento_date ?? null,
          documentoRef,
          observacoes: body.observacoes ?? null,
          itens,
        });
        return Response.json({ recebimento_id: recebimentoId, fallback: true });
      } catch (fallbackErr: unknown) {
        const message = fallbackErr instanceof Error ? fallbackErr.message : "Erro ao registrar recebimento manual.";
        return jsonError(400, message);
      }
    }

    const legacy = await supabase.schema("m").rpc("fn_pedido_compra_receber", {
      p_pedido_id: id,
      p_recebimento_date: body.recebimentoDate ?? body.recebimento_date ?? null,
      p_documento_ref: documentoRef,
      p_observacoes: body.observacoes ?? null,
      p_itens: itens,
    });
    data = legacy.data;
    error = legacy.error;
  }

  if (error) return jsonError(400, error.message);
  return Response.json({ recebimento_id: data ? String(data) : null });
}
