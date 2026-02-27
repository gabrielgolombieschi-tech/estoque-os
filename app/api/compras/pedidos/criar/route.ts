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
  const osReferencia = String(body.osReferencia ?? body.os_referencia ?? "").trim();
  const observacoesInput = String(body.observacoes ?? "").trim();
  const solicitanteUsuarioIdRaw = String(body.solicitanteUsuarioId ?? body.solicitante_usuario_id ?? "").trim();
  const solicitanteUsuarioId =
    solicitanteUsuarioIdRaw && /^[0-9a-f-]{36}$/i.test(solicitanteUsuarioIdRaw) ? solicitanteUsuarioIdRaw : null;

  if (!Number.isFinite(fornecedorId) || fornecedorId <= 0) return jsonError(400, "fornecedorId invalido.");

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
      solicitante_usuario_id: solicitanteUsuarioId,
    })
    .select("id,codigo,status,fornecedor_id,solicitante_usuario_id,created_at,total_geral")
    .single();

  if (error) return jsonError(400, error.message);

  return Response.json({
    data,
    pedido_id: data?.id ?? null,
  });
}
