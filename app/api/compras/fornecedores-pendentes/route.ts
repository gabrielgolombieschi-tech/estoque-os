import { NextRequest } from "next/server";
import { getAuthSupabase, jsonError, resolveTenantEmpresa, canCompras } from "../_lib";

export const runtime = "nodejs";

export async function GET(req: NextRequest) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;

  const ctx = await resolveTenantEmpresa(supabase, undefined, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");

  if (!(await canCompras(supabase, "read"))) return jsonError(403, "Sem permissao (compras.read).");

  const { data, error } = await supabase.rpc("list_compras_fornecedores_pendentes", {
    p_tenant_id: ctx.tenantId,
    p_empresa_id: ctx.empresaId,
  });

  if (error) return jsonError(400, error.message);
  return Response.json({ data: data ?? [] });
}
