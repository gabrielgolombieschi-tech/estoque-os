import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../../../../_lib";

export const runtime = "nodejs";

function asNum(v: unknown, def = 0) {
  const n = Number(v ?? def);
  return Number.isFinite(n) ? n : def;
}

async function loadPedido(
  supabase: ReturnType<typeof import("@/lib/supabase/serverFromAuthHeader").supabaseFromAuthHeader>,
  pedidoId: string,
  tenantId: string,
  empresaId: string
) {
  const { data, error } = await supabase
    .schema("m")
    .from("pedido_compra")
    .select("id,status")
    .eq("id", pedidoId)
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .is("deleted_at", null)
    .single();
  if (error || !data) return { error: "Pedido nao encontrado." } as const;
  return { data: data as { id: string; status: string } } as const;
}

export async function PATCH(
  req: NextRequest,
  { params }: { params: Promise<{ id: string; itemId: string }> }
) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;

  const { id: pedidoId, itemId } = await params;
  if (!pedidoId || !itemId) return jsonError(400, "id/itemId obrigatorios.");

  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const ctx = await resolveTenantEmpresa(supabase, body, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");
  if (!(await canCompras(supabase, "write"))) return jsonError(403, "Sem permissao (compras.write).");

  const pedido = await loadPedido(supabase, pedidoId, ctx.tenantId, ctx.empresaId);
  if ("error" in pedido) return jsonError(404, String(pedido.error ?? "Pedido nao encontrado."));
  if (["APROVADO", "ENVIADO", "PARCIAL_RECEBIDO", "RECEBIDO", "CANCELADO"].includes(String(pedido.data.status ?? ""))) {
    return jsonError(400, `Pedido em status ${pedido.data.status} nao permite alterar item.`);
  }

  const { data: item, error: itemErr } = await supabase
    .schema("m")
    .from("pedido_compra_item")
    .select("id,item_id,quantidade_recebida")
    .eq("id", itemId)
    .eq("pedido_compra_id", pedidoId)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .single();
  if (itemErr || !item) return jsonError(404, "Item nao encontrado no pedido.");
  if ((item as { item_id: number | null }).item_id != null) {
    return jsonError(400, "Apenas item manual pode ser editado nesta tela.");
  }

  const itemNome = String(body.item_nome ?? body.itemNome ?? "").trim();
  const unidade = String(body.unidade ?? "UN").trim() || "UN";
  const quantidade = asNum(body.quantidade, 0);
  const valorUnitario = asNum(body.valor_unitario ?? body.valorUnitario, 0);

  if (!itemNome) return jsonError(400, "Descricao do item obrigatoria.");
  if (quantidade <= 0) return jsonError(400, "Quantidade invalida.");
  if (valorUnitario < 0) return jsonError(400, "Valor unitario invalido.");
  if (quantidade < asNum((item as { quantidade_recebida?: unknown }).quantidade_recebida, 0)) {
    return jsonError(400, "Quantidade nao pode ser menor que a quantidade ja recebida.");
  }

  const { data, error } = await supabase
    .schema("m")
    .from("pedido_compra_item")
    .update({
      item_nome: itemNome,
      unidade,
      quantidade,
      valor_unitario: valorUnitario,
      updated_by: null,
    })
    .eq("id", itemId)
    .eq("pedido_compra_id", pedidoId)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .select("*")
    .single();

  if (error) return jsonError(400, error.message);
  return Response.json({ data });
}

export async function DELETE(
  req: NextRequest,
  { params }: { params: Promise<{ id: string; itemId: string }> }
) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;

  const { id: pedidoId, itemId } = await params;
  if (!pedidoId || !itemId) return jsonError(400, "id/itemId obrigatorios.");

  const ctx = await resolveTenantEmpresa(supabase, undefined, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");
  if (!(await canCompras(supabase, "write"))) return jsonError(403, "Sem permissao (compras.write).");

  const pedido = await loadPedido(supabase, pedidoId, ctx.tenantId, ctx.empresaId);
  if ("error" in pedido) return jsonError(404, String(pedido.error ?? "Pedido nao encontrado."));
  if (["APROVADO", "ENVIADO", "PARCIAL_RECEBIDO", "RECEBIDO", "CANCELADO"].includes(String(pedido.data.status ?? ""))) {
    return jsonError(400, `Pedido em status ${pedido.data.status} nao permite excluir item.`);
  }

  const { data: item, error: itemErr } = await supabase
    .schema("m")
    .from("pedido_compra_item")
    .select("id,item_id,quantidade_recebida")
    .eq("id", itemId)
    .eq("pedido_compra_id", pedidoId)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .single();

  if (itemErr || !item) return jsonError(404, "Item nao encontrado no pedido.");
  if ((item as { item_id: number | null }).item_id != null) {
    return jsonError(400, "Apenas item manual pode ser excluido nesta tela.");
  }
  if (asNum((item as { quantidade_recebida?: unknown }).quantidade_recebida, 0) > 0) {
    return jsonError(400, "Item manual com recebimento nao pode ser excluido.");
  }

  const { error } = await supabase
    .schema("m")
    .from("pedido_compra_item")
    .update({ deleted_at: new Date().toISOString(), updated_by: null })
    .eq("id", itemId)
    .eq("pedido_compra_id", pedidoId)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null);

  if (error) return jsonError(400, error.message);
  return Response.json({ ok: true });
}
