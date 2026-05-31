import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../../_lib";

export const runtime = "nodejs";

const OPEN_STATUSES = new Set(["ENVIADO", "PARCIAL_RECEBIDO"]);

type PedidoRow = {
  id: string;
  status: string | null;
};

type PedidoItemRow = {
  id: string;
  pedido_compra_id: string;
  item_id: number | null;
};

type ItemRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  descricao: string | null;
};

function numberId(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.trunc(n) : null;
}

function textId(value: unknown): string | null {
  const text = String(value ?? "").trim();
  return text || null;
}

export async function POST(req: NextRequest) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;

  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const ctx = await resolveTenantEmpresa(supabase, body, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");
  if (!(await canCompras(supabase, "write"))) return jsonError(403, "Sem permissao (compras.write).");

  const pedidoId = textId(body.pedidoId ?? body.pedido_id);
  const pedidoItemId = textId(body.pedidoItemId ?? body.pedido_item_id);
  const itemId = numberId(body.itemId ?? body.item_id);

  if (!pedidoId) return jsonError(400, "pedidoId obrigatorio.");
  if (!pedidoItemId) return jsonError(400, "pedidoItemId obrigatorio.");
  if (!itemId) return jsonError(400, "itemId obrigatorio.");

  const { data: pedido, error: pedidoErr } = await supabase
    .schema("m")
    .from("pedido_compra")
    .select("id,status")
    .eq("id", pedidoId)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .maybeSingle<PedidoRow>();

  if (pedidoErr) return jsonError(400, pedidoErr.message);
  if (!pedido?.id) return jsonError(404, "Pedido nao encontrado.");

  const status = String(pedido.status ?? "").trim().toUpperCase();
  if (!OPEN_STATUSES.has(status)) {
    return jsonError(400, `Pedido em status ${status || "-"} nao permite correcao de item manual.`);
  }

  const { data: pedidoItem, error: pedidoItemErr } = await supabase
    .schema("m")
    .from("pedido_compra_item")
    .select("id,pedido_compra_id,item_id")
    .eq("id", pedidoItemId)
    .eq("pedido_compra_id", pedidoId)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .maybeSingle<PedidoItemRow>();

  if (pedidoItemErr) return jsonError(400, pedidoItemErr.message);
  if (!pedidoItem?.id) return jsonError(404, "Item nao encontrado no pedido.");

  const currentItemId = numberId(pedidoItem.item_id);
  if (currentItemId && currentItemId !== itemId) {
    return jsonError(409, "Item do pedido ja esta vinculado a outro cadastro interno. Remova o vinculo manualmente antes de alterar.");
  }

  const { data: item, error: itemErr } = await supabase
    .from("itens")
    .select("id,codigo_interno,nome,descricao")
    .eq("id", itemId)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .maybeSingle<ItemRow>();

  if (itemErr) return jsonError(400, itemErr.message);
  if (!item?.id) return jsonError(404, "Item interno nao encontrado.");

  const itemCodigo = String(item.codigo_interno ?? "").trim() || null;
  const itemNome = String(item.nome ?? item.descricao ?? "").trim() || itemCodigo || `Item ${item.id}`;

  const { data: updated, error: updateErr } = await supabase
    .schema("m")
    .from("pedido_compra_item")
    .update({
      item_id: item.id,
      item_codigo: itemCodigo,
      item_nome: itemNome,
      updated_by: null,
    })
    .eq("id", pedidoItemId)
    .eq("pedido_compra_id", pedidoId)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .select("id,pedido_compra_id,item_id,item_codigo,item_nome")
    .single();

  if (updateErr) return jsonError(400, updateErr.message);

  try {
    await supabase.schema("m").rpc("fn_pedido_compra_log_evento", {
      p_pedido_id: pedidoId,
      p_tipo: "ITEM",
      p_status_de: status || null,
      p_status_para: status || null,
      p_mensagem: "Item manual do pedido vinculado ao cadastro interno pela importacao XML.",
    });
  } catch {
    // Log best-effort: o vinculo nao deve falhar por indisponibilidade do evento.
  }

  return Response.json({
    ok: true,
    pedidoItem: updated,
  });
}
