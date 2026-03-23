import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../../_lib";
import { getAllowedEmpresas } from "@/lib/auth/empresa";
import { supabaseAdmin } from "@/lib/supabase/admin";

export const runtime = "nodejs";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PEDIDO_LOOKUP_ALLOWED_ROLES = new Set([
  "ADMIN",
  "FINANCEIRO",
  "COORDENACAO",
  "COMPRAS",
  "ALMOXARIFADO",
  "APONTAMENTO_RH",
]);

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;
  const { id } = await params;
  if (!id) return jsonError(400, "id obrigatorio.");

  const ctx = await resolveTenantEmpresa(supabase, undefined, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");

  const canReadCompras = await canCompras(supabase, "read");
  let canLookupByRole = false;
  if (!canReadCompras) {
    try {
      const allowed = await getAllowedEmpresas(supabase, ctx.tenantId);
      const empresa = allowed.find((e) => String(e.id) === ctx.empresaId);
      const role = String(empresa?.papel ?? "").trim().toUpperCase();
      canLookupByRole = PEDIDO_LOOKUP_ALLOWED_ROLES.has(role);
    } catch {
      canLookupByRole = false;
    }
  }

  if (!canReadCompras && !canLookupByRole) return jsonError(403, "Sem permissao (compras.read).");
  const db = canReadCompras ? supabase : supabaseAdmin();

  const { data: pedido, error: pedidoErr } = await db
    .schema("m")
    .from("pedido_compra")
    .select("*")
    .eq("id", id)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .single();
  if (pedidoErr) return jsonError(400, pedidoErr.message);

  let fornecedorNome = "SEM FORNECEDOR";
  let solicitanteNome = "";
  const fornecedorId = Number((pedido as Record<string, unknown>).fornecedor_id);
  if (Number.isFinite(fornecedorId) && fornecedorId > 0) {
    const { data: fornecedor, error: fornecedorErr } = await db
      .from("fornecedores")
      .select("id,nome")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .eq("id", fornecedorId)
      .maybeSingle();
    if (fornecedorErr) return jsonError(400, fornecedorErr.message);
    fornecedorNome = String((fornecedor as Record<string, unknown> | null)?.nome ?? "").trim() || "SEM FORNECEDOR";
  }
  const solicitanteId = String((pedido as Record<string, unknown>).solicitante_usuario_id ?? "").trim();
  if (solicitanteId && UUID_RE.test(solicitanteId)) {
    const { data: solicitante } = await db
      .schema("a")
      .from("usuario")
      .select("id,nome,email")
      .eq("id", solicitanteId)
      .is("deleted_at", null)
      .maybeSingle();
    if (solicitante) {
      const nome = String((solicitante as Record<string, unknown>).nome ?? "").trim();
      const email = String((solicitante as Record<string, unknown>).email ?? "").trim();
      solicitanteNome = nome || email;
    }
  }

  const [itensRes, eventosRes, recebRes] = await Promise.all([
    db
      .schema("m")
      .from("pedido_compra_item")
      .select("*")
      .eq("pedido_compra_id", id)
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .is("deleted_at", null)
      .order("seq", { ascending: true }),
    db
      .schema("m")
      .from("pedido_compra_evento")
      .select("*")
      .eq("pedido_compra_id", id)
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .order("created_at", { ascending: false }),
    db
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
    const { data: itensCatalogo, error: itensCatalogoErr } = await db
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
  const origemOsByPedidoItemId = new Map<string, number>();
  const documentoRefsByPedidoItemId = new Map<string, Set<string>>();
  for (const it of itens) {
    const pedidoItemId = String(it.id ?? "").trim();
    const osId = Number(it.origem_os_id ?? 0);
    if (pedidoItemId && Number.isFinite(osId) && osId > 0) origemOsByPedidoItemId.set(pedidoItemId, osId);
  }
  const recebimentos = Array.isArray(recebRes.data) ? (recebRes.data as Array<Record<string, unknown>>) : [];
  const recebimentoById = new Map<string, Record<string, unknown>>();
  for (const row of recebimentos) {
    const recebimentoId = String(row.id ?? "").trim();
    if (recebimentoId) recebimentoById.set(recebimentoId, row);
  }
  if (pedidoItemIds.length > 0 && recebimentoById.size > 0) {
    const { data: recebItemRows, error: recebItemErr } = await db
      .schema("m")
      .from("pedido_compra_recebimento_item")
      .select("pedido_compra_item_id,recebimento_id")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .is("deleted_at", null)
      .in("pedido_compra_item_id", pedidoItemIds);
    if (recebItemErr) return jsonError(400, recebItemErr.message);

    for (const row of Array.isArray(recebItemRows) ? (recebItemRows as Array<Record<string, unknown>>) : []) {
      const pedidoItemId = String(row.pedido_compra_item_id ?? "").trim();
      const recebimentoId = String(row.recebimento_id ?? "").trim();
      if (!pedidoItemId || !recebimentoId) continue;
      const recebimento = recebimentoById.get(recebimentoId);
      const documentoRef = String(recebimento?.documento_ref ?? "").trim();
      if (!documentoRef) continue;
      if (!documentoRefsByPedidoItemId.has(pedidoItemId)) documentoRefsByPedidoItemId.set(pedidoItemId, new Set<string>());
      documentoRefsByPedidoItemId.get(pedidoItemId)?.add(documentoRef);
    }
  }
  const osLabelById = new Map<number, string>();
  if (pedidoItemIds.length > 0) {
    const { data: origensRows, error: origensErr } = await db
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
      const { data: pendenciasRows, error: pendenciasErr } = await db
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
    const osIdsManual = Array.from(new Set(Array.from(origemOsByPedidoItemId.values())));
    const osIdsTotal = Array.from(new Set([...osIds, ...osIdsManual]));
    if (osIdsTotal.length > 0) {
      const { data: osRows, error: osErr } = await db
        .from("ordens_servico")
        .select("id,numero_os,os_num")
        .eq("tenant_id", ctx.tenantId)
        .eq("empresa_id", ctx.empresaId)
        .in("id", osIdsTotal);
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
    const origemFromPendencia = origemResumoByPedidoItemId.get(pedidoItemId) ?? null;
    const origemOsId = origemOsByPedidoItemId.get(pedidoItemId) ?? null;
    const origemFromManualOs = origemOsId ? (osLabelById.get(origemOsId) ?? `OS ${origemOsId}`) : null;
    const origemResumo = origemFromPendencia ?? origemFromManualOs ?? null;
    const documentoRefResumo = Array.from(documentoRefsByPedidoItemId.get(pedidoItemId) ?? []).join(", ");
    return {
      ...it,
      item_codigo: itemCodigo || null,
      origem_resumo: origemResumo,
      documento_ref_resumo: documentoRefResumo || null,
    };
  });

  return Response.json({
    data: {
      pedido: {
        ...(pedido as Record<string, unknown>),
        fornecedor_nome: fornecedorNome,
        solicitante_nome: solicitanteNome || null,
      },
      itens: itensEnriquecidos,
      eventos: eventosRes.data ?? [],
      recebimentos: recebRes.data ?? [],
    },
  });
}

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;
  const { id } = await params;
  if (!id) return jsonError(400, "id obrigatorio.");

  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const ctx = await resolveTenantEmpresa(supabase, body, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");
  if (!(await canCompras(supabase, "write"))) return jsonError(403, "Sem permissao (compras.write).");

  const solicitanteRaw = String(body.solicitanteUsuarioId ?? body.solicitante_usuario_id ?? "").trim();
  const solicitante = solicitanteRaw ? (UUID_RE.test(solicitanteRaw) ? solicitanteRaw : null) : null;
  if (solicitanteRaw && !solicitante) return jsonError(400, "Solicitante invalido.");

  const { data: pedido } = await supabase
    .schema("m")
    .from("pedido_compra")
    .select("id,status")
    .eq("id", id)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .maybeSingle();
  if (!pedido) return jsonError(404, "Pedido nao encontrado.");

  const { data, error } = await supabase
    .schema("m")
    .from("pedido_compra")
    .update({ solicitante_usuario_id: solicitante, updated_by: null })
    .eq("id", id)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .select("id,solicitante_usuario_id")
    .single();
  if (error) return jsonError(400, error.message);

  return Response.json({ data });
}
