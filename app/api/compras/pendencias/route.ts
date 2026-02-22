import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../_lib";

export const runtime = "nodejs";

export async function GET(req: NextRequest) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;

  const ctx = await resolveTenantEmpresa(supabase, undefined, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");
  if (!(await canCompras(supabase, "read"))) return jsonError(403, "Sem permissao (compras.read).");

  const modo = String(req.nextUrl.searchParams.get("modo") ?? "DETALHADO").toUpperCase();
  const fornecedorIdRaw = String(req.nextUrl.searchParams.get("fornecedorId") ?? "").trim();
  const fornecedorId = fornecedorIdRaw ? Number(fornecedorIdRaw) : null;

  if (modo === "AGRUPADO") {
    let q = supabase
      .schema("r")
      .from("r_compra_pendencias_agrupadas_item")
      .select("*")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId);
    if (Number.isFinite(fornecedorId)) q = q.eq("fornecedor_id", fornecedorId);
    const { data, error } = await q.order("item_nome", { ascending: true });
    if (error) return jsonError(400, error.message);
    return Response.json({ data: data ?? [] });
  }

  let q = supabase
    .schema("r")
    .from("r_compra_pendencias_detalhadas")
    .select("*")
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .in("status", ["PENDENTE", "EM_PEDIDO"]);
  if (Number.isFinite(fornecedorId)) q = q.eq("fornecedor_id", fornecedorId);
  const { data, error } = await q.order("necessario_em", { ascending: true, nullsFirst: true });
  if (error) return jsonError(400, error.message);
  return Response.json({ data: data ?? [] });
}

export async function POST(req: NextRequest) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;

  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const ctx = await resolveTenantEmpresa(supabase, body, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");
  if (!(await canCompras(supabase, "write"))) return jsonError(403, "Sem permissao (compras.write).");

  const origemTipo = String(body.origem_tipo ?? body.origemTipo ?? "OUTROS").toUpperCase();
  let origemOsId = body.origem_os_id ?? body.origemOsId ?? null;
  const origemOsNumero = String(
    body.origem_os_numero ?? body.origemOsNumero ?? body.numero_os ?? body.os_num ?? body.osNumero ?? ""
  ).trim();

  if (origemTipo === "OS" && !origemOsId && origemOsNumero) {
    const numeroParsed = Number(origemOsNumero);
    let q = supabase
      .from("ordens_servico")
      .select("id")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .limit(1);

    if (Number.isFinite(numeroParsed) && Number.isInteger(numeroParsed)) {
      q = q.or(`numero_os.eq.${numeroParsed},os_num.eq.${numeroParsed}`);
    } else {
      q = q.eq("numero_os", origemOsNumero);
    }

    const { data: osRows, error: osErr } = await q;
    if (osErr) return jsonError(400, osErr.message);
    const osId = Number((osRows ?? [])[0]?.id ?? 0);
    if (!Number.isFinite(osId) || osId <= 0) return jsonError(400, "OS nao encontrada para vinculacao.");
    origemOsId = osId;
  }

  const payload = {
    tenant_id: ctx.tenantId,
    empresa_id: ctx.empresaId,
    status: "PENDENTE",
    fornecedor_id: body.fornecedor_id ?? body.fornecedorId ?? null,
    origem_tipo: origemTipo,
    origem_os_id: origemOsId,
    item_id: body.item_id ?? body.itemId ?? null,
    item_nome: body.item_nome ?? body.itemNome ?? null,
    unidade: body.unidade ?? null,
    quantidade: body.quantidade,
    prioridade: body.prioridade ?? "MEDIA",
    necessario_em: body.necessario_em ?? body.necessarioEm ?? null,
    observacoes: body.observacoes ?? null,
    estoque_meta: body.estoque_meta ?? body.estoqueMeta ?? null,
  };

  const { data, error } = await supabase
    .schema("m")
    .from("compra_pendencia")
    .insert(payload)
    .select("*")
    .single();
  if (error) return jsonError(400, error.message);
  return Response.json({ data });
}
