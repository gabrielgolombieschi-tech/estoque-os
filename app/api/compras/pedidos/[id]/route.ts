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
  const pedidoItemIds = Array.from(
    new Set(
      itens
        .map((it) => String(it.id ?? "").trim())
        .filter((v) => v.length > 0)
    )
  );
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

  const origemResumoByPedidoItemId = new Map<string, string>();
  if (pedidoItemIds.length > 0) {
    const { data: origensRows, error: origensErr } = await supabase
      .schema("m")
      .from("pedido_compra_item_origem")
      .select("pedido_compra_item_id,pendencia_id")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .is("deleted_at", null)
      .in("pedido_compra_item_id", pedidoItemIds);
    if (origensErr) return jsonError(400, origensErr.message);

    const origensList = Array.isArray(origensRows) ? (origensRows as Array<Record<string, unknown>>) : [];
    const pendenciaIds = Array.from(
      new Set(
        origensList
          .map((r) => String(r.pendencia_id ?? "").trim())
          .filter((v) => v.length > 0)
      )
    );

    const pendenciaById = new Map<string, { origemTipo: string; origemOsId: number | null }>();
    if (pendenciaIds.length > 0) {
      const { data: pendenciasRows, error: pendenciasErr } = await supabase
        .schema("m")
        .from("compra_pendencia")
        .select("id,origem_tipo,origem_os_id")
        .eq("tenant_id", ctx.tenantId)
        .eq("empresa_id", ctx.empresaId)
        .in("id", pendenciaIds);
      if (pendenciasErr) return jsonError(400, pendenciasErr.message);

      const pendencias = Array.isArray(pendenciasRows) ? (pendenciasRows as Array<Record<string, unknown>>) : [];
      for (const p of pendencias) {
        const pendId = String(p.id ?? "").trim();
        if (!pendId) continue;
        const osId = Number(p.origem_os_id);
        pendenciaById.set(pendId, {
          origemTipo: String(p.origem_tipo ?? "").trim().toUpperCase(),
          origemOsId: Number.isFinite(osId) && osId > 0 ? osId : null,
        });
      }
    }

    const osIds = Array.from(
      new Set(
        Array.from(pendenciaById.values())
          .map((p) => p.origemOsId)
          .filter((id): id is number => typeof id === "number" && Number.isFinite(id) && id > 0)
      )
    );
    const osLabelById = new Map<number, string>();
    if (osIds.length > 0) {
      const { data: osRows, error: osErr } = await supabase
        .from("ordens_servico")
        .select("id,numero_os,os_num")
        .eq("tenant_id", ctx.tenantId)
        .eq("empresa_id", ctx.empresaId)
        .in("id", osIds);
      if (osErr) return jsonError(400, osErr.message);

      for (const os of Array.isArray(osRows) ? (osRows as Array<Record<string, unknown>>) : []) {
        const osId = Number(os.id);
        if (!Number.isFinite(osId) || osId <= 0) continue;
        const numeroOs = String(os.numero_os ?? "").trim();
        const osNum = Number(os.os_num);
        const numero =
          numeroOs.length > 0 ? numeroOs : Number.isFinite(osNum) && osNum > 0 ? String(osNum) : String(osId);
        osLabelById.set(osId, `OS ${numero}`);
      }
    }

    const labelsByPedidoItemId = new Map<string, Set<string>>();
    for (const row of origensList) {
      const pedidoItemId = String(row.pedido_compra_item_id ?? "").trim();
      const pendenciaId = String(row.pendencia_id ?? "").trim();
      if (!pedidoItemId || !pendenciaId) continue;

      const pend = pendenciaById.get(pendenciaId);
      if (!pend) continue;

      let label = "-";
      if (pend.origemTipo === "OS") {
        if (pend.origemOsId && osLabelById.has(pend.origemOsId)) label = osLabelById.get(pend.origemOsId) ?? "OS";
        else label = "OS";
      } else if (pend.origemTipo === "ESTOQUE") {
        label = "ESTOQUE";
      } else if (pend.origemTipo === "OUTROS") {
        label = "OUTROS";
      } else if (pend.origemTipo) {
        label = pend.origemTipo;
      }

      if (!labelsByPedidoItemId.has(pedidoItemId)) labelsByPedidoItemId.set(pedidoItemId, new Set<string>());
      labelsByPedidoItemId.get(pedidoItemId)?.add(label);
    }

    for (const [pedidoItemId, labels] of labelsByPedidoItemId.entries()) {
      origemResumoByPedidoItemId.set(pedidoItemId, Array.from(labels).join(", "));
    }
  }

  const itensEnriquecidos = itens.map((it) => {
    const pedidoItemId = String(it.id ?? "").trim();
    const itemId = Number(it.item_id);
    const itemCodigo = Number.isFinite(itemId) && itemId > 0 ? codigoByItemId.get(itemId) ?? "" : "";
    const origemResumo = origemResumoByPedidoItemId.get(pedidoItemId) ?? null;
    return { ...it, item_codigo: itemCodigo || null, origem_resumo: origemResumo };
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
