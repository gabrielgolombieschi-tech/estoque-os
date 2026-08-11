import { NextRequest } from "next/server";
import { getAuthSupabase, jsonError, resolveTenantEmpresa } from "../_lib";

export const runtime = "nodejs";

export async function GET(req: NextRequest) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;

  const ctx = await resolveTenantEmpresa(supabase, undefined, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");

  const search = String(req.nextUrl.searchParams.get("search") ?? "").trim();
  const { data, error } = await supabase.rpc("list_compras_fornecedores", {
    p_tenant_id: ctx.tenantId,
    p_empresa_id: ctx.empresaId,
    p_search: search || null,
  });
  if (error) return jsonError(400, error.message);
  return Response.json({ data: data ?? [] });
}
