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

  const incluirOs = body.incluirOs ?? body.incluir_os ?? true;
  const incluirEstoque = body.incluirEstoque ?? body.incluir_estoque ?? true;

  const { data, error } = await supabase.schema("m").rpc("fn_compra_varredura", {
    p_tenant_id: ctx.tenantId,
    p_empresa_id: ctx.empresaId,
    p_incluir_os: Boolean(incluirOs),
    p_incluir_estoque: Boolean(incluirEstoque),
  });
  if (error) return jsonError(400, error.message);

  return Response.json({ data });
}

