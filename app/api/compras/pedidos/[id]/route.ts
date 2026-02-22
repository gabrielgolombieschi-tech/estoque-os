import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../../_lib";

export const runtime = "nodejs";

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;
  const { id } = await params;
  if (!id) return jsonError(400, "id obrigatorio.");

  const ctx = await resolveTenantEmpresa(supabase, undefined, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");
  if (!(await canCompras(supabase, "read"))) return jsonError(403, "Sem permissao (compras.read).");

  const { data: pedido, error: pedidoErr } = await supabase
    .schema("m")
    .from("pedido_compra")
    .select("*")
    .eq("id", id)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .single();
  if (pedidoErr) return jsonError(400, pedidoErr.message);

  const [itensRes, eventosRes, recebRes] = await Promise.all([
    supabase
      .schema("m")
      .from("pedido_compra_item")
      .select("*")
      .eq("pedido_compra_id", id)
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .is("deleted_at", null)
      .order("seq", { ascending: true }),
    supabase
      .schema("m")
      .from("pedido_compra_evento")
      .select("*")
      .eq("pedido_compra_id", id)
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .order("created_at", { ascending: false }),
    supabase
      .schema("m")
      .from("pedido_compra_recebimento")
      .select("*")
      .eq("pedido_compra_id", id)
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .is("deleted_at", null)
      .order("created_at", { ascending: false }),
  ]);

  if (itensRes.error) return jsonError(400, itensRes.error.message);
  if (eventosRes.error) return jsonError(400, eventosRes.error.message);
  if (recebRes.error) return jsonError(400, recebRes.error.message);

  const itens = (itensRes.data ?? []) as Array<Record<string, unknown>>;
  const itemIds = Array.from(
    new Set(
      itens
        .map((it) => Number(it.item_id))
        .filter((n) => Number.isFinite(n) && n > 0)
    )
  );
  const codigoByItemId = new Map<number, string>();
  if (itemIds.length > 0) {
    const { data: itensCatalogo, error: itensCatalogoErr } = await supabase
      .from("itens")
      .select("id,codigo_interno")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .in("id", itemIds);
    if (itensCatalogoErr) return jsonError(400, itensCatalogoErr.message);
    for (const row of Array.isArray(itensCatalogo) ? (itensCatalogo as Array<Record<string, unknown>>) : []) {
      const itemId = Number(row.id);
      if (!Number.isFinite(itemId) || itemId <= 0) continue;
      codigoByItemId.set(itemId, String(row.codigo_interno ?? ""));
    }
  }

  const itensEnriquecidos = itens.map((it) => {
    const itemId = Number(it.item_id);
    const itemCodigo = Number.isFinite(itemId) && itemId > 0 ? codigoByItemId.get(itemId) ?? "" : "";
    return { ...it, item_codigo: itemCodigo || null };
  });

  return Response.json({
    data: {
      pedido,
      itens: itensEnriquecidos,
      eventos: eventosRes.data ?? [],
      recebimentos: recebRes.data ?? [],
    },
  });
}
