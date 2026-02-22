import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../../../_lib";

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

  const itemIdRaw = body.item_id ?? body.itemId ?? null;
  const itemId = itemIdRaw == null || String(itemIdRaw).trim() === "" ? null : Number(itemIdRaw);
  const itemNome = String(body.item_nome ?? body.itemNome ?? "").trim();
  const unidade = String(body.unidade ?? "UN").trim() || "UN";
  const quantidade = asNum(body.quantidade, 0);
  const valorUnitario = asNum(body.valor_unitario ?? body.valorUnitario, 0);

  if (!itemId && !itemNome) return jsonError(400, "Informe item_id ou item_nome.");
  if (quantidade <= 0) return jsonError(400, "Quantidade invalida.");
  if (valorUnitario < 0) return jsonError(400, "Valor unitario invalido.");

  const { data: pedido, error: pedidoErr } = await supabase
    .schema("m")
    .from("pedido_compra")
    .select("id,status")
    .eq("id", id)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .single();
  if (pedidoErr || !pedido) return jsonError(404, "Pedido nao encontrado.");

  const status = String((pedido as { status?: string }).status ?? "");
  if (["APROVADO", "ENVIADO", "PARCIAL_RECEBIDO", "RECEBIDO", "CANCELADO"].includes(status)) {
    return jsonError(400, `Pedido em status ${status} nao permite incluir item.`);
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
  };

  const { data, error } = await supabase
    .schema("m")
    .from("pedido_compra_item")
    .insert(payload)
    .select("*")
    .single();
  if (error) return jsonError(400, error.message);

  return Response.json({ data });
}
