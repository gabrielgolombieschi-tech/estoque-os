import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../../_lib";

export const runtime = "nodejs";

export async function POST(req: NextRequest) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;
  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;

  const ctx = await resolveTenantEmpresa(supabase, body, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");
  if (!(await canCompras(supabase, "write"))) return jsonError(403, "Sem permissao (compras.write).");

  const fornecedorId = Number(body.fornecedorId ?? body.fornecedor_id ?? 0);
  const pendenciaIds = (Array.isArray(body.pendenciaIds) ? body.pendenciaIds : body.pendencia_ids) as unknown[];
  const quantidadeOverridesRaw = body.quantidadeOverrides ?? body.quantidade_overrides;
  const valorUnitOverridesRaw = body.valorUnitOverrides ?? body.valor_unit_overrides;
  if (!Number.isFinite(fornecedorId) || fornecedorId <= 0) return jsonError(400, "fornecedorId invalido.");
  if (!Array.isArray(pendenciaIds) || pendenciaIds.length === 0) return jsonError(400, "pendenciaIds obrigatorio.");

  const pendenciaSet = new Set(pendenciaIds.map((id) => String(id)));
  const quantidadeOverrides: Array<{ id: string; quantidade: number }> = [];
  if (Array.isArray(quantidadeOverridesRaw)) {
    for (const row of quantidadeOverridesRaw) {
      if (!row || typeof row !== "object") continue;
      const r = row as Record<string, unknown>;
      const id = String(r.id ?? r.pendencia_id ?? "").trim();
      const quantidade = Number(r.quantidade ?? NaN);
      if (!id || !pendenciaSet.has(id)) continue;
      if (!Number.isFinite(quantidade) || quantidade <= 0) continue;
      quantidadeOverrides.push({ id, quantidade });
    }
  } else if (quantidadeOverridesRaw && typeof quantidadeOverridesRaw === "object") {
    const map = quantidadeOverridesRaw as Record<string, unknown>;
    for (const [id, qtd] of Object.entries(map)) {
      const pendenciaId = String(id).trim();
      const quantidade = Number(qtd ?? NaN);
      if (!pendenciaId || !pendenciaSet.has(pendenciaId)) continue;
      if (!Number.isFinite(quantidade) || quantidade <= 0) continue;
      quantidadeOverrides.push({ id: pendenciaId, quantidade });
    }
  }

  const valorUnitOverrides: Array<{ id: string; valor_unitario: number }> = [];
  if (Array.isArray(valorUnitOverridesRaw)) {
    for (const row of valorUnitOverridesRaw) {
      if (!row || typeof row !== "object") continue;
      const r = row as Record<string, unknown>;
      const id = String(r.id ?? r.pendencia_id ?? "").trim();
      const valorUnitario = Number(r.valor_unitario ?? r.valorUnitario ?? NaN);
      if (!id || !pendenciaSet.has(id)) continue;
      if (!Number.isFinite(valorUnitario) || valorUnitario < 0) continue;
      valorUnitOverrides.push({ id, valor_unitario: valorUnitario });
    }
  } else if (valorUnitOverridesRaw && typeof valorUnitOverridesRaw === "object") {
    const map = valorUnitOverridesRaw as Record<string, unknown>;
    for (const [id, vlr] of Object.entries(map)) {
      const pendenciaId = String(id).trim();
      const valorUnitario = Number(vlr ?? NaN);
      if (!pendenciaId || !pendenciaSet.has(pendenciaId)) continue;
      if (!Number.isFinite(valorUnitario) || valorUnitario < 0) continue;
      valorUnitOverrides.push({ id: pendenciaId, valor_unitario: valorUnitario });
    }
  }

  for (const ov of quantidadeOverrides) {
    const { error: updErr } = await supabase
      .schema("m")
      .from("compra_pendencia")
      .update({ quantidade: ov.quantidade })
      .eq("id", ov.id)
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .eq("fornecedor_id", fornecedorId)
      .is("deleted_at", null);
    if (updErr) return jsonError(400, updErr.message);
  }

  const { data, error } = await supabase.schema("m").rpc("fn_pedido_compra_gerar", {
    p_tenant_id: ctx.tenantId,
    p_empresa_id: ctx.empresaId,
    p_fornecedor_id: fornecedorId,
    p_pendencia_ids: pendenciaIds,
    p_observacoes: body.observacoes ?? null,
  });
  if (error) return jsonError(400, error.message);
  const pedidoId = data ? String(data) : null;
  if (!pedidoId) return Response.json({ pedido_id: null });

  const { error: genericCodeErr } = await supabase
    .schema("m")
    .from("pedido_compra_item")
    .update({ item_codigo: "9999", updated_by: null })
    .eq("pedido_compra_id", pedidoId)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .is("item_id", null);
  if (genericCodeErr) return jsonError(400, genericCodeErr.message);

  if (valorUnitOverrides.length > 0) {
    const overrideMap = new Map(valorUnitOverrides.map((v) => [v.id, v.valor_unitario]));
    const { data: origens, error: origensErr } = await supabase
      .schema("m")
      .from("pedido_compra_item_origem")
      .select("pendencia_id,pedido_compra_item_id")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .in("pendencia_id", Array.from(overrideMap.keys()))
      .is("deleted_at", null);
    if (origensErr) return jsonError(400, origensErr.message);

    const itemIds = Array.from(new Set((origens ?? []).map((r) => String(r.pedido_compra_item_id ?? "")).filter(Boolean)));
    if (itemIds.length > 0) {
      const { data: itensPedido, error: itensErr } = await supabase
        .schema("m")
        .from("pedido_compra_item")
        .select("id")
        .eq("pedido_compra_id", pedidoId)
        .eq("tenant_id", ctx.tenantId)
        .eq("empresa_id", ctx.empresaId)
        .in("id", itemIds)
        .is("deleted_at", null);
      if (itensErr) return jsonError(400, itensErr.message);

      const validItemIds = new Set((itensPedido ?? []).map((r) => String(r.id ?? "")));
      const valueByItemId = new Map<string, number>();

      for (const origem of origens ?? []) {
        const pendenciaId = String(origem.pendencia_id ?? "");
        const pedidoItemId = String(origem.pedido_compra_item_id ?? "");
        if (!pendenciaId || !pedidoItemId || !validItemIds.has(pedidoItemId)) continue;
        const valor = overrideMap.get(pendenciaId);
        if (valor == null) continue;
        valueByItemId.set(pedidoItemId, valor);
      }

      for (const [itemId, valorUnitario] of valueByItemId.entries()) {
        const { error: updValorErr } = await supabase
          .schema("m")
          .from("pedido_compra_item")
          .update({ valor_unitario: valorUnitario, updated_by: null })
          .eq("id", itemId)
          .eq("pedido_compra_id", pedidoId)
          .eq("tenant_id", ctx.tenantId)
          .eq("empresa_id", ctx.empresaId)
          .is("deleted_at", null);
        if (updValorErr) return jsonError(400, updValorErr.message);
      }
    }
  }

  return Response.json({ pedido_id: pedidoId });
}
