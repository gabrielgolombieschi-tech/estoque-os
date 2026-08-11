import { NextRequest } from "next/server";
import { canCompras, getAuthSupabase, jsonError, resolveTenantEmpresa } from "../_lib";
import { getAllowedEmpresas } from "@/lib/auth/empresa";
import { supabaseAdmin } from "@/lib/supabase/admin";
import { ensureDefaults as ensureCondicoesPagamentoDefaults } from "@/src/services/condicaoPagamento";

export const runtime = "nodejs";

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

  const [canRead, canWrite, canApprove, canReceive] = await Promise.all([
    canCompras(supabase, "read"),
    canCompras(supabase, "write"),
    canCompras(supabase, "approve"),
    canCompras(supabase, "receive"),
  ]);

  let canLookupByRole = false;
  if (!canRead && !canWrite && !canApprove && !canReceive) {
    try {
      const allowed = await getAllowedEmpresas(supabase, ctx.tenantId);
      const empresa = allowed.find((e) => String(e.id) === ctx.empresaId);
      const role = String(empresa?.papel ?? "").trim().toUpperCase();
      canLookupByRole = PEDIDO_LOOKUP_ALLOWED_ROLES.has(role);
    } catch {
      canLookupByRole = false;
    }
  }

  if (!canRead && !canWrite && !canApprove && !canReceive && !canLookupByRole) {
    return jsonError(403, "Sem permissao para listar condicoes de pagamento.");
  }

  const onlyActiveParam = String(req.nextUrl.searchParams.get("onlyActive") ?? "1").trim().toLowerCase();
  const onlyActive = onlyActiveParam !== "0" && onlyActiveParam !== "false";
  let admin: ReturnType<typeof supabaseAdmin> | null = null;
  try {
    admin = supabaseAdmin();
  } catch {
    admin = null;
  }

  if (admin) {
    try {
      await ensureCondicoesPagamentoDefaults(admin, { tenantId: ctx.tenantId, empresaId: ctx.empresaId });
    } catch {
      // Seed de apoio; se falhar, ainda tentamos listar o que já existe.
    }
  }

  let q = (admin ?? supabase)
    .schema("c")
    .from("condicao_pagamento")
    .select("id,codigo,nome,dias,acrescimo_percent,ativo")
    .eq("tenant_id", ctx.tenantId)
    .eq("empresa_id", ctx.empresaId)
    .is("deleted_at", null)
    .order("dias", { ascending: true, nullsFirst: false })
    .order("codigo", { ascending: true });

  if (onlyActive) q = q.eq("ativo", true);

  const { data, error } = await q;
  if (error) return jsonError(400, error.message);

  return Response.json({ data: data ?? [] });
}
