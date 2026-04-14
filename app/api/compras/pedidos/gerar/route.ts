import { NextRequest } from "next/server";
import {
  canCompras,
  getAuthSupabase,
  jsonError,
  resolveCondicaoPagamento,
  resolvePedidoSolicitanteUsuarioId,
  resolveTenantEmpresa,
} from "../../_lib";

export const runtime = "nodejs";
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function normText(v: unknown) {
  return String(v ?? "").trim().toUpperCase();
}

function parseIsoDate(value: unknown) {
  const raw = String(value ?? "").trim();
  if (!raw) return null;
  if (!ISO_DATE_RE.test(raw)) return undefined;
  const date = new Date(`${raw}T00:00:00`);
  return Number.isFinite(date.getTime()) ? raw : undefined;
}

function parseItemId(v: unknown): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  if (!Number.isFinite(n) || n <= 0) return null;
  return n;
}

function pickPositivePrice(
  row: Partial<{ custo_ultima_compra: unknown; preco_unitario: unknown; custo_medio: unknown }>
): number | null {
  const candidates = [row.custo_ultima_compra, row.preco_unitario, row.custo_medio]
    .map((v) => Number(v ?? NaN))
    .filter((n) => Number.isFinite(n) && n > 0);
  return candidates.length > 0 ? candidates[0] : null;
}

export async function POST(req: NextRequest) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase, user } = auth;
  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;

  const ctx = await resolveTenantEmpresa(supabase, body, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");
  if (!(await canCompras(supabase, "write"))) return jsonError(403, "Sem permissao (compras.write).");

  const fornecedorId = Number(body.fornecedorId ?? body.fornecedor_id ?? 0);
  const pendenciaIds = (Array.isArray(body.pendenciaIds) ? body.pendenciaIds : body.pendencia_ids) as unknown[];
  const solicitanteUsuarioIdRaw = String(body.solicitanteUsuarioId ?? body.solicitante_usuario_id ?? "").trim();
  const previsaoEntregaDate = parseIsoDate(body.previsaoEntregaDate ?? body.previsao_entrega_date);
  const condicaoPagamentoIdRaw = String(body.condicaoPagamentoId ?? body.condicao_pagamento_id ?? "").trim();
  const quantidadeOverridesRaw = body.quantidadeOverrides ?? body.quantidade_overrides;
  const valorUnitOverridesRaw = body.valorUnitOverrides ?? body.valor_unit_overrides;
  if (!Number.isFinite(fornecedorId) || fornecedorId <= 0) return jsonError(400, "fornecedorId invalido.");
  if (!Array.isArray(pendenciaIds) || pendenciaIds.length === 0) return jsonError(400, "pendenciaIds obrigatorio.");
  if (previsaoEntregaDate === undefined) return jsonError(400, "Data de entrega invalida.");

  const solicitanteResult = await resolvePedidoSolicitanteUsuarioId({
    authUserId: user.id,
    empresaId: ctx.empresaId,
    requestedId: solicitanteUsuarioIdRaw || null,
  });
  if (solicitanteResult.error) return jsonError(400, solicitanteResult.error);

  const condicaoPagamentoResult = await resolveCondicaoPagamento({
    tenantId: ctx.tenantId,
    empresaId: ctx.empresaId,
    condicaoPagamentoId: condicaoPagamentoIdRaw || null,
  });
  if (condicaoPagamentoResult.error) return jsonError(400, condicaoPagamentoResult.error);

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

  if (solicitanteResult.id || previsaoEntregaDate || condicaoPagamentoResult.row?.id) {
    const { error: solErr } = await supabase
      .schema("m")
      .from("pedido_compra")
      .update({
        solicitante_usuario_id: solicitanteResult.id,
        previsao_entrega_date: previsaoEntregaDate ?? null,
        condicao_pagamento_id: condicaoPagamentoResult.row?.id ?? null,
        updated_by: null,
      })
      .eq("id", pedidoId)
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .is("deleted_at", null);
    if (solErr) return jsonError(400, solErr.message);
  }

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

  const overrideMap = new Map(valorUnitOverrides.map((v) => [v.id, v.valor_unitario]));

  const { data: pendenciasRows, error: pendenciasErr } = await supabase
    .schema("m")
    .from("compra_pendencia")
    .select("id,item_id,item_nome,unidade")
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .in("id", pendenciaIds.map((id) => String(id)));
  if (pendenciasErr) return jsonError(400, pendenciasErr.message);

  const pendencias = Array.isArray(pendenciasRows) ? (pendenciasRows as Array<Record<string, unknown>>) : [];
  const missingRows = pendencias.filter((p) => {
    const id = String(p.id ?? "").trim();
    return id && !overrideMap.has(id);
  });

  if (missingRows.length > 0) {
    const missingItemIds = Array.from(
      new Set(
        missingRows
          .map((p) => parseItemId(p.item_id))
          .filter((n): n is number => typeof n === "number" && n > 0)
      )
    );

    const priceByItemId = new Map<number, number>();
    if (missingItemIds.length > 0) {
      const { data: itensCad, error: itensCadErr } = await supabase
        .from("itens")
        .select("id,custo_ultima_compra,preco_unitario,custo_medio")
        .eq("tenant_id", ctx.tenantId)
        .eq("empresa_id", ctx.empresaId)
        .in("id", missingItemIds);
      if (itensCadErr) return jsonError(400, itensCadErr.message);

      for (const row of Array.isArray(itensCad) ? (itensCad as Array<Record<string, unknown>>) : []) {
        const itemId = parseItemId(row.id);
        if (itemId == null) continue;
        const price = pickPositivePrice(row);
        if (price != null) priceByItemId.set(itemId, price);
      }
    }

    const unresolvedByText = new Map<string, string>();
    for (const p of missingRows) {
      const pendId = String(p.id ?? "").trim();
      if (!pendId || overrideMap.has(pendId)) continue;
      const itemId = parseItemId(p.item_id);
      if (itemId != null) {
        const price = priceByItemId.get(itemId);
        if (price != null) {
          overrideMap.set(pendId, price);
          continue;
        }
      }
      const key = `${normText(p.item_nome)}|${normText(p.unidade || "UN")}`;
      if (key && key !== "|UN") unresolvedByText.set(pendId, key);
    }

    if (unresolvedByText.size > 0) {
      const { data: pedidosHist, error: pedidosHistErr } = await supabase
        .schema("m")
        .from("pedido_compra")
        .select("id,created_at")
        .eq("tenant_id", ctx.tenantId)
        .eq("empresa_id", ctx.empresaId)
        .eq("fornecedor_id", fornecedorId)
        .is("deleted_at", null)
        .neq("status", "CANCELADO")
        .neq("id", pedidoId)
        .order("created_at", { ascending: false })
        .limit(300);
      if (pedidosHistErr) return jsonError(400, pedidosHistErr.message);

      const pedidoIdsHist = (pedidosHist ?? [])
        .map((p) => String((p as { id?: unknown }).id ?? "").trim())
        .filter(Boolean);

      if (pedidoIdsHist.length > 0) {
        const rankByPedidoId = new Map<string, number>();
        for (let i = 0; i < pedidoIdsHist.length; i++) rankByPedidoId.set(pedidoIdsHist[i], i);

        const { data: itensHist, error: itensHistErr } = await supabase
          .schema("m")
          .from("pedido_compra_item")
          .select("pedido_compra_id,item_nome,unidade,valor_unitario")
          .eq("tenant_id", ctx.tenantId)
          .eq("empresa_id", ctx.empresaId)
          .is("deleted_at", null)
          .in("pedido_compra_id", pedidoIdsHist)
          .gt("valor_unitario", 0)
          .order("created_at", { ascending: false })
          .limit(5000);
        if (itensHistErr) return jsonError(400, itensHistErr.message);

        const histByText = new Map<string, { rank: number; valor: number }>();
        for (const row of Array.isArray(itensHist) ? (itensHist as Array<Record<string, unknown>>) : []) {
          const pedidoHistId = String(row.pedido_compra_id ?? "").trim();
          const rank = rankByPedidoId.get(pedidoHistId);
          if (rank == null) continue;
          const valor = Number(row.valor_unitario ?? NaN);
          if (!Number.isFinite(valor) || valor <= 0) continue;
          const key = `${normText(row.item_nome)}|${normText(row.unidade || "UN")}`;
          if (!key || key === "|UN") continue;
          const cur = histByText.get(key);
          if (!cur || rank < cur.rank) histByText.set(key, { rank, valor });
        }

        for (const [pendId, key] of unresolvedByText.entries()) {
          if (overrideMap.has(pendId)) continue;
          const hist = histByText.get(key);
          if (hist) overrideMap.set(pendId, hist.valor);
        }
      }
    }
  }

  if (overrideMap.size > 0) {
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
