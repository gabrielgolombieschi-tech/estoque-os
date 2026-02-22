import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../../../_lib";

export const runtime = "nodejs";

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;
  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const { id } = await params;
  const ctx = await resolveTenantEmpresa(supabase, body, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");
  if (!(await canCompras(supabase, "receive"))) return jsonError(403, "Sem permissao (compras.receive).");

  const itens = (Array.isArray(body.itens) ? body.itens : []) as unknown[];
  if (!itens.length) return jsonError(400, "itens obrigatorio.");

  const { data, error } = await supabase.schema("m").rpc("fn_pedido_compra_receber", {
    p_pedido_id: id,
    p_recebimento_date: body.recebimentoDate ?? body.recebimento_date ?? null,
    p_documento_ref: body.documentoRef ?? body.documento_ref ?? null,
    p_observacoes: body.observacoes ?? null,
    p_itens: itens,
  });

  if (error) return jsonError(400, error.message);
  return Response.json({ recebimento_id: data ? String(data) : null });
}
