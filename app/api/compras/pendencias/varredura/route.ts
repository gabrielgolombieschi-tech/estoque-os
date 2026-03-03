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

  let estoquePendenciasSemSugestaoCanceladas = 0;
  if (Boolean(incluirEstoque)) {
    const { data: agrupadas, error: agrErr } = await supabase
      .schema("r")
      .from("r_compra_pendencias_agrupadas_item")
      .select("fornecedor_id,item_id,qtd_estoque_pendencia,sugestao_min,sugestao_ideal,sugestao_max")
      .eq("tenant_id", ctx.tenantId)
      .eq("empresa_id", ctx.empresaId);
    if (agrErr) return jsonError(400, agrErr.message);

    const stalePairs = Array.from(
      new Set(
        (Array.isArray(agrupadas) ? agrupadas : [])
          .filter((r) => Number(r.qtd_estoque_pendencia ?? 0) > 0)
          .filter((r) => Number(r.sugestao_min ?? 0) <= 0)
          .filter((r) => Number(r.sugestao_ideal ?? 0) <= 0)
          .filter((r) => Number(r.sugestao_max ?? 0) <= 0)
          .map((r) => ({
            fornecedorId: Number(r.fornecedor_id ?? 0),
            itemId: Number(r.item_id ?? 0),
          }))
          .filter((r) => Number.isFinite(r.itemId) && r.itemId > 0)
          .map((r) => `${Number.isFinite(r.fornecedorId) ? r.fornecedorId : 0}:${r.itemId}`)
      )
    ).map((key) => {
      const [fornecedorId, itemId] = key.split(":").map((v) => Number(v));
      return { fornecedorId, itemId };
    });

    if (stalePairs.length > 0) {
      for (const pair of stalePairs) {
        let cancelQ = supabase
          .schema("m")
          .from("compra_pendencia")
          .update({
            status: "CANCELADO",
            cancel_reason: "Cancelado automaticamente: sem sugestao de reposicao (MIN/IDEAL/MAX = 0).",
            updated_by: null,
          })
          .eq("tenant_id", ctx.tenantId)
          .eq("empresa_id", ctx.empresaId)
          .eq("origem_tipo", "ESTOQUE")
          .eq("status", "PENDENTE")
          .is("deleted_at", null)
          .eq("item_id", pair.itemId);

        if (Number.isFinite(pair.fornecedorId) && pair.fornecedorId > 0) {
          cancelQ = cancelQ.eq("fornecedor_id", pair.fornecedorId);
        } else {
          cancelQ = cancelQ.is("fornecedor_id", null);
        }

        const { data: canceledRows, error: cancelErr } = await cancelQ.select("id");
        if (cancelErr) return jsonError(400, cancelErr.message);
        estoquePendenciasSemSugestaoCanceladas += Array.isArray(canceledRows) ? canceledRows.length : 0;
      }
    }
  }

  const payload = typeof data === "object" && data != null ? (data as Record<string, unknown>) : {};
  const totalBase = Number(payload.total_movimentadas ?? 0);
  const total = Number.isFinite(totalBase) ? totalBase : 0;
  return Response.json({
    data: {
      ...payload,
      estoque_pendencias_sem_sugestao_canceladas: estoquePendenciasSemSugestaoCanceladas,
      total_movimentadas: total + estoquePendenciasSemSugestaoCanceladas,
    },
  });
}
