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

  const status = String(req.nextUrl.searchParams.get("status") ?? "").trim().toUpperCase();
  const fornecedorIdRaw = String(req.nextUrl.searchParams.get("fornecedorId") ?? "").trim();
  const fornecedorId = fornecedorIdRaw ? Number(fornecedorIdRaw) : null;

  let q = supabase
    .schema("m")
    .from("pedido_compra")
    .select("id,codigo,status,fornecedor_id,solicitante_usuario_id,created_at,total_geral")
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null);

  if (status) q = q.eq("status", status);
  if (Number.isFinite(fornecedorId)) q = q.eq("fornecedor_id", fornecedorId);

  const { data, error } = await q.order("created_at", { ascending: false });
  if (error) return jsonError(400, error.message);

  const rows = Array.isArray(data) ? (data as Array<Record<string, unknown>>) : [];
  const fornecedorIds = Array.from(
    new Set(
      rows
        .map((r) => Number(r.fornecedor_id))
        .filter((n) => Number.isFinite(n) && n > 0)
    )
  );

  const fornecedorMap = new Map<number, string>();
  if (fornecedorIds.length > 0) {
    const { data: fData, error: fErr } = await supabase
      .from("fornecedores")
      .select("id,nome")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .in("id", fornecedorIds);
    if (fErr) return jsonError(400, fErr.message);
    for (const f of Array.isArray(fData) ? (fData as Array<Record<string, unknown>>) : []) {
      const id = Number(f.id);
      if (!Number.isFinite(id) || id <= 0) continue;
      fornecedorMap.set(id, String(f.nome ?? ""));
    }
  }

  const enriched = rows.map((r) => {
    const id = Number(r.fornecedor_id);
    return {
      ...r,
      fornecedor_nome: Number.isFinite(id) && id > 0 ? fornecedorMap.get(id) ?? "SEM FORNECEDOR" : "SEM FORNECEDOR",
    };
  });

  return Response.json({ data: enriched });
}
