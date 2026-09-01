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

  const documentoId = Number(req.nextUrl.searchParams.get("documentoId") ?? 0);
  if (Number.isInteger(documentoId) && documentoId > 0) {
    const { data: pendencias, error: pendenciasError } = await supabase
      .schema("r")
      .from("r_compra_pendencias_detalhadas")
      .select("fornecedor_id,fornecedor_nome,quantidade")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId)
      .eq("origem_os_id", documentoId)
      .in("status", ["PENDENTE", "EM_PEDIDO"]);
    if (pendenciasError) return jsonError(400, pendenciasError.message);

    const agrupado = new Map<
      string,
      { fornecedor_id: number | null; fornecedor_nome: string; fornecedor_documento: null; qtd_pendencias_abertas: number; qtd_total_pendente: number }
    >();
    for (const row of pendencias ?? []) {
      const fornecedorId = row.fornecedor_id == null ? null : Number(row.fornecedor_id);
      const key = fornecedorId == null ? "sem-fornecedor" : String(fornecedorId);
      const atual = agrupado.get(key) ?? {
        fornecedor_id: fornecedorId,
        fornecedor_nome: String(row.fornecedor_nome ?? "SEM FORNECEDOR"),
        fornecedor_documento: null,
        qtd_pendencias_abertas: 0,
        qtd_total_pendente: 0,
      };
      atual.qtd_pendencias_abertas += 1;
      atual.qtd_total_pendente += Number(row.quantidade ?? 0);
      agrupado.set(key, atual);
    }
    return Response.json({ data: Array.from(agrupado.values()) });
  }

  const { data, error } = await supabase.rpc("list_compras_fornecedores_pendentes", {
    p_tenant_id: ctx.tenantId,
    p_empresa_id: ctx.empresaId,
  });

  if (error) return jsonError(400, error.message);
  return Response.json({ data: data ?? [] });
}
