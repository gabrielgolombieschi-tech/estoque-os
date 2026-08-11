import { NextRequest } from "next/server";
import { getAuthSupabase, jsonError, resolveTenantEmpresa } from "../_lib";

export const runtime = "nodejs";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function GET(req: NextRequest) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;

  const ctx = await resolveTenantEmpresa(supabase, undefined, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");

  const tenantHint = String(
    req.nextUrl.searchParams.get("tenant_id") ?? req.nextUrl.searchParams.get("tenantId") ?? ""
  ).trim();
  const empresaHint = String(
    req.nextUrl.searchParams.get("empresa_id") ?? req.nextUrl.searchParams.get("empresaId") ?? ""
  ).trim();
  if ((tenantHint && !UUID_RE.test(tenantHint)) || (empresaHint && !UUID_RE.test(empresaHint))) {
    return jsonError(400, "Tenant/empresa invalidos.");
  }

  const search = String(req.nextUrl.searchParams.get("search") ?? "").trim();
  const { data, error } = await supabase.rpc("list_compras_fornecedores", {
    p_tenant_id: tenantHint || ctx.tenantId,
    p_empresa_id: empresaHint || ctx.empresaId,
    p_search: search || null,
  });
  if (error) return jsonError(400, error.message);
  return Response.json({ data: data ?? [] });
}
