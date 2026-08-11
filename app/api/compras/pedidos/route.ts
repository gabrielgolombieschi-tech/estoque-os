import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../_lib";
import { getAllowedEmpresas } from "@/lib/auth/empresa";
import { supabaseAdmin } from "@/lib/supabase/admin";

export const runtime = "nodejs";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PEDIDO_LOOKUP_ALLOWED_ROLES = new Set([
  "ADMIN",
  "DIRETOR",
  "FINANCEIRO",
  "FATURAMENTO",
  "COORDENACAO",
  "COMPRAS",
  "ALMOXARIFADO",
  "APONTAMENTO_RH",
]);

export async function GET(req: NextRequest) {
  const auth = await getAuthSupabase(req);
  if ("error" in auth) return auth.error;
  const { supabase } = auth;

  const ctx = await resolveTenantEmpresa(supabase, undefined, req.nextUrl.searchParams);
  if (!ctx) return jsonError(400, "Tenant/empresa nao carregados.");

  const canReadCompras = await canCompras(supabase, "read");
  let canLookupByRole = false;
  if (!canReadCompras) {
    try {
      const allowed = await getAllowedEmpresas(supabase, ctx.tenantId);
      const empresa = allowed.find((e) => String(e.id) === ctx.empresaId);
      const role = String(empresa?.papel ?? "").trim().toUpperCase();
      canLookupByRole = PEDIDO_LOOKUP_ALLOWED_ROLES.has(role);
    } catch {
      canLookupByRole = false;
    }
  }

  if (!canReadCompras && !canLookupByRole) {
    return jsonError(403, "Sem permissao (compras.read).");
  }

  const db = supabaseAdmin();

  const status = String(req.nextUrl.searchParams.get("status") ?? "").trim().toUpperCase();
  const fornecedorIdRaw = String(req.nextUrl.searchParams.get("fornecedorId") ?? "").trim();
  const fornecedorId = fornecedorIdRaw ? Number(fornecedorIdRaw) : null;

  let q = db
    .schema("m")
    .from("pedido_compra")
    .select(
      "id,codigo,status,fornecedor_id,solicitante_usuario_id,previsao_entrega_date,condicao_pagamento_id,transporte_tipo,transportadora_nome,observacoes,destacar_ipi,total_ipi,total_itens,created_at,total_geral"
    )
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null);

  if (status === "ANDAMENTO") {
    q = q.neq("status", "CANCELADO").neq("status", "RECEBIDO");
  } else if (status) {
    q = q.eq("status", status);
  }
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
  const solicitanteIds = Array.from(
    new Set(
      rows
        .map((r) => String(r.solicitante_usuario_id ?? "").trim())
        .filter((id) => UUID_RE.test(id))
    )
  );
  const condicaoIds = Array.from(
    new Set(
      rows
        .map((r) => String(r.condicao_pagamento_id ?? "").trim())
        .filter((id) => UUID_RE.test(id))
    )
  );

  const fornecedorMap = new Map<number, string>();
  const solicitanteMap = new Map<string, string>();
  const condicaoMap = new Map<string, string>();

  const [fDataRes, solicitanteRes, condicaoRes] = await Promise.all([
    fornecedorIds.length > 0
      ? db
          .from("fornecedores")
          .select("id,nome")
          .eq("tenant_id", ctx.tenantId)
          .eq("empresa_id", ctx.empresaId)
          .in("id", fornecedorIds)
      : Promise.resolve({ data: [], error: null }),
    solicitanteIds.length > 0
      ? db
          .schema("a")
          .from("usuario")
          .select("id,nome,email")
          .is("deleted_at", null)
          .in("id", solicitanteIds)
      : Promise.resolve({ data: [], error: null }),
    condicaoIds.length > 0
      ? db
          .schema("c")
          .from("condicao_pagamento")
          .select("id,nome,codigo")
          .eq("tenant_id", ctx.tenantId)
          .eq("empresa_id", ctx.empresaId)
          .is("deleted_at", null)
          .in("id", condicaoIds)
      : Promise.resolve({ data: [], error: null }),
  ]);

  if (fDataRes.error) return jsonError(400, fDataRes.error.message);
  if (solicitanteRes.error) return jsonError(400, solicitanteRes.error.message);
  if (condicaoRes.error) return jsonError(400, condicaoRes.error.message);

  for (const f of Array.isArray(fDataRes.data) ? (fDataRes.data as Array<Record<string, unknown>>) : []) {
    const id = Number(f.id);
    if (!Number.isFinite(id) || id <= 0) continue;
    fornecedorMap.set(id, String(f.nome ?? ""));
  }
  for (const row of Array.isArray(solicitanteRes.data) ? (solicitanteRes.data as Array<Record<string, unknown>>) : []) {
    const id = String(row.id ?? "").trim();
    if (!UUID_RE.test(id)) continue;
    const nome = String(row.nome ?? "").trim();
    const email = String(row.email ?? "").trim();
    solicitanteMap.set(id, nome || email);
  }
  for (const row of Array.isArray(condicaoRes.data) ? (condicaoRes.data as Array<Record<string, unknown>>) : []) {
    const id = String(row.id ?? "").trim();
    if (!UUID_RE.test(id)) continue;
    const nome = String(row.nome ?? "").trim();
    const codigo = String(row.codigo ?? "").trim();
    condicaoMap.set(id, nome || codigo);
  }

  const enriched = rows.map((r) => {
    const fornecedorIdValue = Number(r.fornecedor_id);
    const solicitanteId = String(r.solicitante_usuario_id ?? "").trim();
    const condicaoId = String(r.condicao_pagamento_id ?? "").trim();
    return {
      ...r,
      fornecedor_nome:
        Number.isFinite(fornecedorIdValue) && fornecedorIdValue > 0
          ? fornecedorMap.get(fornecedorIdValue) ?? "SEM FORNECEDOR"
          : "SEM FORNECEDOR",
      solicitante_nome: UUID_RE.test(solicitanteId) ? solicitanteMap.get(solicitanteId) ?? null : null,
      condicao_pagamento_nome: UUID_RE.test(condicaoId) ? condicaoMap.get(condicaoId) ?? null : null,
    };
  });

  return Response.json({ data: enriched });
}
