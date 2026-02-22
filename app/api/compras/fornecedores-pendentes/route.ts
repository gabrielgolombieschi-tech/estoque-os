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

  const { data, error } = await supabase
    .schema("r")
    .from("r_compra_fornecedores_pendentes")
    .select("*")
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .gt("qtd_pendencias_abertas", 0)
    .order("fornecedor_nome", { ascending: true });

  if (error) return jsonError(400, error.message);
  return Response.json({ data: data ?? [] });
}
