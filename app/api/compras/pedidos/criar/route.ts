import { NextRequest } from "next/server";
import {
  canCompras,
  getAuthSupabase,
  jsonError,
  resolvePedidoTransporte,
  resolveCondicaoPagamento,
  resolvePedidoSolicitanteUsuarioId,
  resolveTenantEmpresa,
} from "../../_lib";

export const runtime = "nodejs";
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function parseIsoDate(value: unknown) {
  const raw = String(value ?? "").trim();
  if (!raw) return null;
  if (!ISO_DATE_RE.test(raw)) return undefined;
  const date = new Date(`${raw}T00:00:00`);
  return Number.isFinite(date.getTime()) ? raw : undefined;
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
  const osReferencia = String(body.osReferencia ?? body.os_referencia ?? "").trim();
  const observacoesInput = String(body.observacoes ?? "").trim();
  const solicitanteUsuarioIdRaw = String(body.solicitanteUsuarioId ?? body.solicitante_usuario_id ?? "").trim();
  const previsaoEntregaDate = parseIsoDate(body.previsaoEntregaDate ?? body.previsao_entrega_date);
  const condicaoPagamentoIdRaw = String(body.condicaoPagamentoId ?? body.condicao_pagamento_id ?? "").trim();
  const transporteResult = resolvePedidoTransporte({
    hasTransporteField: Object.prototype.hasOwnProperty.call(body, "transporteTipo") || Object.prototype.hasOwnProperty.call(body, "transporte_tipo"),
    hasTransportadoraField:
      Object.prototype.hasOwnProperty.call(body, "transportadoraNome") || Object.prototype.hasOwnProperty.call(body, "transportadora_nome"),
    transporteTipo: body.transporteTipo ?? body.transporte_tipo,
    transportadoraNome: body.transportadoraNome ?? body.transportadora_nome,
  });

  if (!Number.isFinite(fornecedorId) || fornecedorId <= 0) return jsonError(400, "fornecedorId invalido.");
  if (previsaoEntregaDate === undefined) return jsonError(400, "Data de entrega invalida.");
  if (transporteResult.error) return jsonError(400, transporteResult.error);

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

  const { data: fornecedor, error: fornecedorErr } = await supabase
    .from("fornecedores")
    .select("id,nome")
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .eq("id", fornecedorId)
    .maybeSingle();

  if (fornecedorErr) return jsonError(400, fornecedorErr.message);
  if (!fornecedor) return jsonError(404, "Fornecedor nao encontrado para a empresa selecionada.");

  const obsPartes: string[] = [];
  if (osReferencia) obsPartes.push(`OS vinculada (opcional): ${osReferencia}`);
  if (observacoesInput) obsPartes.push(observacoesInput);
  const observacoes = obsPartes.length > 0 ? obsPartes.join(" | ") : null;

  const { data, error } = await supabase
    .schema("m")
    .from("pedido_compra")
    .insert({
      tenant_id: ctx.tenantId,
      empresa_id: ctx.empresaId,
      fornecedor_id: fornecedorId,
      status: "RASCUNHO",
      observacoes,
      solicitante_usuario_id: solicitanteResult.id,
      previsao_entrega_date: previsaoEntregaDate ?? null,
      condicao_pagamento_id: condicaoPagamentoResult.row?.id ?? null,
      transporte_tipo: transporteResult.transporteTipo,
      transportadora_nome: transporteResult.transportadoraNome,
    })
    .select("id,codigo,status,fornecedor_id,solicitante_usuario_id,previsao_entrega_date,condicao_pagamento_id,transporte_tipo,transportadora_nome,created_at,total_geral")
    .single();

  if (error) return jsonError(400, error.message);

  return Response.json({
    data,
    pedido_id: data?.id ?? null,
  });
}
