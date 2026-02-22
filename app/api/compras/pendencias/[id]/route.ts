import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../../_lib";

export const runtime = "nodejs";

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;

  const { id } = await params;
  if (!id) return jsonError(400, "id obrigatorio.");

  const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const ctx = await resolveTenantEmpresa(supabase, body, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");
  if (!(await canCompras(supabase, "write"))) return jsonError(403, "Sem permissao (compras.write).");

  const patch: Record<string, unknown> = {};
  const fields = [
    "fornecedor_id",
    "origem_os_id",
    "item_id",
    "item_nome",
    "unidade",
    "quantidade",
    "prioridade",
    "necessario_em",
    "observacoes",
    "estoque_meta",
  ];
  for (const f of fields) {
    const camel = f.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase());
    if (f in body) patch[f] = body[f];
    else if (camel in body) patch[f] = body[camel];
  }
  patch.updated_by = null;

  const { data, error } = await supabase
    .schema("m")
    .from("compra_pendencia")
    .update(patch)
    .eq("id", id)
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .select("*")
    .single();

  if (error) return jsonError(400, error.message);
  return Response.json({ data });
}
