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
  if (!(await canCompras(supabase, "approve"))) return jsonError(403, "Sem permissao (compras.approve).");

  const { error } = await supabase.schema("m").rpc("fn_pedido_compra_transicionar", {
    p_pedido_id: id,
    p_status_para: "APROVADO",
    p_mensagem: body.motivo ?? body.mensagem ?? null,
  });
  if (error) return jsonError(400, error.message);
  return Response.json({ ok: true });
}
