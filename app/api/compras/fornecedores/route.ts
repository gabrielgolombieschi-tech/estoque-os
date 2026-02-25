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

  const search = String(req.nextUrl.searchParams.get("search") ?? "").trim();

  let q = supabase
    .from("fornecedores")
    .select("id,nome,ativo")
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .order("nome", { ascending: true });

  if (search) q = q.ilike("nome", `%${search}%`);

  const { data, error } = await q;
  if (error) return jsonError(400, error.message);
  return Response.json({ data: data ?? [] });
}
