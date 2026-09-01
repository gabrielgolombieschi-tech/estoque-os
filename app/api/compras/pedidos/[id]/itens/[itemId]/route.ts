import { NextRequest } from "next/server";
import {
  calcPedidoItemValorTotal,
  canCompras,
  getAuthSupabase,
  jsonError,
  resolveTenantEmpresa,
  syncPedidoTotais,
} from "../../../../_lib";
import { supabaseAdmin } from "@/lib/supabase/admin";

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
    .select("id,status,destacar_ipi")
    .eq("id", pedidoId)
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .is("deleted_at", null)
    .single();
  if (error || !data) return { error: "Pedido nao encontrado." } as const;
  return { data: data as { id: string; status: string; destacar_ipi?: boolean | null } } as const;
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
  const status = String(pedido.data.status ?? "").trim().toUpperCase();
  if (["RECEBIDO", "CANCELADO"].includes(status)) {
    return jsonError(400, `Pedido em status ${pedido.data.status} nao permite alterar item.`);
  }

  const { data: item, error: itemErr } = await supabase
    .schema("m")
    .from("pedido_compra_item")
    .select("id,item_id,quantidade_recebida,valor_ipi_unitario")
    .eq("id", itemId)
    .eq("pedido_compra_id", pedidoId)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .single();
  if (itemErr || !item) return jsonError(404, "Item nao encontrado no pedido.");
  const isLinkedItem = (item as { item_id: number | null }).item_id != null;

  const itemNome = String(body.item_nome ?? body.itemNome ?? "").trim();
  const unidade = String(body.unidade ?? "UN").trim() || "UN";
  const quantidade = asNum(body.quantidade, 0);
  const valorUnitario = asNum(body.valor_unitario ?? body.valorUnitario, 0);
  const hasValorIpiUnitario =
    Object.prototype.hasOwnProperty.call(body, "valor_ipi_unitario") ||
    Object.prototype.hasOwnProperty.call(body, "valorIpiUnitario");
  const valorIpiUnitario = hasValorIpiUnitario
    ? asNum(body.valor_ipi_unitario ?? body.valorIpiUnitario, 0)
    : asNum((item as Record<string, unknown>).valor_ipi_unitario, 0);
  const osIdRaw = body.origem_os_id ?? body.origemOsId ?? null;
  const osNumeroRaw = String(body.origem_os_numero ?? body.origemOsNumero ?? "").trim();

  if (quantidade <= 0) return jsonError(400, "Quantidade invalida.");
  if (valorUnitario < 0) return jsonError(400, "Valor unitario invalido.");
  if (valorIpiUnitario < 0) return jsonError(400, "Valor unitario do IPI invalido.");
  if (quantidade < asNum((item as { quantidade_recebida?: unknown }).quantidade_recebida, 0)) {
    return jsonError(400, "Quantidade nao pode ser menor que a quantidade ja recebida.");
  }
  const valorTotal = calcPedidoItemValorTotal(
    quantidade,
    valorUnitario,
    valorIpiUnitario,
    Boolean(pedido.data.destacar_ipi)
  );

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
      .or(`numero_os.eq.${osNumeroRaw},codigo.eq.${osNumeroRaw}`)
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

  const payload: Record<string, unknown> = {
    quantidade,
    valor_unitario: valorUnitario,
    valor_total: valorTotal,
    updated_by: null,
    origem_os_id: origemOsId,
  };
  if (hasValorIpiUnitario) {
    payload.valor_ipi_unitario = valorIpiUnitario;
  }

  if (!isLinkedItem) {
    if (!itemNome) return jsonError(400, "Descricao do item obrigatoria.");
    payload.item_nome = itemNome;
    payload.unidade = unidade;
  }

  const { data, error } = await supabase
    .schema("m")
    .from("pedido_compra_item")
    .update(payload)
    .eq("id", itemId)
    .eq("pedido_compra_id", pedidoId)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .select("*")
    .single();

  if (error) return jsonError(400, error.message);

  const syncResult = await syncPedidoTotais(supabase, pedidoId, ctx.tenantId, ctx.empresaId);
  if ("error" in syncResult) return jsonError(400, syncResult.error);

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
  const admin = supabaseAdmin();

  const ctx = await resolveTenantEmpresa(supabase, undefined, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");
  if (!(await canCompras(supabase, "write"))) return jsonError(403, "Sem permissao (compras.write).");

  const pedido = await loadPedido(supabase, pedidoId, ctx.tenantId, ctx.empresaId);
  if ("error" in pedido) return jsonError(404, String(pedido.error ?? "Pedido nao encontrado."));
  const status = String(pedido.data.status ?? "").trim().toUpperCase();
  if (["RECEBIDO", "CANCELADO"].includes(status)) {
    return jsonError(400, `Pedido em status ${pedido.data.status} nao permite excluir item.`);
  }

  const { data: item, error: itemErr } = await admin
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
  if (asNum((item as { quantidade_recebida?: unknown }).quantidade_recebida, 0) > 0) {
    return jsonError(400, "Item com recebimento nao pode ser excluido.");
  }

  const isLinkedItem = (item as { item_id: number | null }).item_id != null;
  const { data: origensRows, error: origensErr } = await admin
    .schema("m")
    .from("pedido_compra_item_origem")
    .select("id,pendencia_id")
    .eq("pedido_compra_item_id", itemId)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null);
  if (origensErr) return jsonError(400, origensErr.message);

  const origens = Array.isArray(origensRows) ? (origensRows as Array<{ id: string; pendencia_id: string }>) : [];
  if (origens.length > 0) {
    const origemIds = origens.map((o) => o.id);
    const pendenciaIds = Array.from(new Set(origens.map((o) => o.pendencia_id).filter(Boolean)));

    const { error: delOrigensErr } = await admin
      .schema("m")
      .from("pedido_compra_item_origem")
      .delete()
      .in("id", origemIds)
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId);
    if (delOrigensErr) return jsonError(400, delOrigensErr.message);

    if (isLinkedItem && pendenciaIds.length > 0) {
      const { data: vinculosRestantes, error: vincRestErr } = await admin
        .schema("m")
        .from("pedido_compra_item_origem")
        .select("pendencia_id,pedido_compra_item_id")
        .eq("tenant_id", ctx.tenantId)
        .eq("empresa_id", ctx.empresaId)
        .is("deleted_at", null)
        .in("pendencia_id", pendenciaIds);
      if (vincRestErr) return jsonError(400, vincRestErr.message);

      const vincRows = Array.isArray(vinculosRestantes) ? (vinculosRestantes as Array<Record<string, unknown>>) : [];
      const pedidoItemIds = Array.from(
        new Set(
          vincRows
            .map((r) => String(r.pedido_compra_item_id ?? "").trim())
            .filter((v) => v.length > 0)
        )
      );
      const pedidoByPedidoItemId = new Map<string, string>();
      if (pedidoItemIds.length > 0) {
        const { data: pedidoItensRows, error: pedidoItensErr } = await admin
          .schema("m")
          .from("pedido_compra_item")
          .select("id,pedido_compra_id,deleted_at")
          .in("id", pedidoItemIds)
          .eq("tenant_id", ctx.tenantId)
          .eq("empresa_id", ctx.empresaId);
        if (pedidoItensErr) return jsonError(400, pedidoItensErr.message);

        const ativos = (Array.isArray(pedidoItensRows) ? pedidoItensRows : []).filter((r) => r.deleted_at == null) as Array<{
          id: string;
          pedido_compra_id: string;
        }>;
        const pedidoIds = Array.from(new Set(ativos.map((r) => String(r.pedido_compra_id)).filter(Boolean)));
        const statusByPedidoId = new Map<string, string>();
        if (pedidoIds.length > 0) {
          const { data: pedidosRows, error: pedidosErr } = await admin
            .schema("m")
            .from("pedido_compra")
            .select("id,status,deleted_at")
            .in("id", pedidoIds)
            .eq("tenant_id", ctx.tenantId)
            .eq("empresa_id", ctx.empresaId);
          if (pedidosErr) return jsonError(400, pedidosErr.message);
          for (const p of Array.isArray(pedidosRows) ? pedidosRows : []) {
            if (p.deleted_at != null) continue;
            statusByPedidoId.set(String(p.id), String(p.status ?? "").toUpperCase());
          }
        }

        for (const it of ativos) {
          const st = statusByPedidoId.get(String(it.pedido_compra_id));
          if (!st) continue;
          pedidoByPedidoItemId.set(String(it.id), st);
        }
      }

      const pendenciasComVinculoAtivo = new Set<string>();
      for (const r of vincRows) {
        const pendId = String(r.pendencia_id ?? "").trim();
        const pedidoItemId = String(r.pedido_compra_item_id ?? "").trim();
        if (!pendId || !pedidoItemId) continue;
        const st = pedidoByPedidoItemId.get(pedidoItemId);
        if (!st) continue;
        if (["RASCUNHO", "AGUARDANDO_APROVACAO", "APROVADO", "ENVIADO", "PARCIAL_RECEBIDO"].includes(st)) {
          pendenciasComVinculoAtivo.add(pendId);
        }
      }

      const liberarPendencias = pendenciaIds.filter((idPend) => !pendenciasComVinculoAtivo.has(idPend));
      if (liberarPendencias.length > 0) {
        const { error: liberaErr } = await admin
          .schema("m")
          .from("compra_pendencia")
          .update({
            status: "PENDENTE",
            cancel_reason: null,
            concluido_em: null,
            updated_by: null,
          })
          .in("id", liberarPendencias)
          .eq("tenant_id", ctx.tenantId)
          .eq("empresa_id", ctx.empresaId)
          .eq("status", "EM_PEDIDO")
          .is("deleted_at", null);
        if (liberaErr) return jsonError(400, liberaErr.message);
      }
    }
  }

  const { data: deletedRows, error } = await admin
    .schema("m")
    .from("pedido_compra_item")
    .delete()
    .eq("id", itemId)
    .eq("pedido_compra_id", pedidoId)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .select("id");

  if (error) return jsonError(400, error.message);
  if (!Array.isArray(deletedRows) || deletedRows.length === 0) {
    return jsonError(403, "Item nao removido (sem permissao ou ja excluido).");
  }
  const { data: stillExists, error: checkErr } = await admin
    .schema("m")
    .from("pedido_compra_item")
    .select("id")
    .eq("id", itemId)
    .eq("pedido_compra_id", pedidoId)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .maybeSingle();
  if (checkErr) return jsonError(400, checkErr.message);
  if (stillExists?.id) {
    return jsonError(500, "Falha definitiva ao excluir item: registro ainda existe no banco.");
  }

  const syncResult = await syncPedidoTotais(supabase, pedidoId, ctx.tenantId, ctx.empresaId);
  if ("error" in syncResult) return jsonError(400, syncResult.error);

  return Response.json({ ok: true, deleted_item_id: itemId });
}
