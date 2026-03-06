import { NextRequest } from "next/server";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type AuthedSupabase = ReturnType<typeof supabaseFromAuthHeader>;
type SyncPedidoTotaisResult =
  | { error: string }
  | {
      data: {
        totalItens: number;
        totalGeral: number;
      };
    };

export function jsonError(status: number, error: string, details?: unknown) {
  return Response.json({ error, ...(details !== undefined ? { details } : {}) }, { status });
}

export async function getAuthSupabase(req: NextRequest) {
  const authorization = req.headers.get("authorization");
  if (!authorization) return { error: jsonError(401, "Nao autenticado.") } as const;

  const supabase = supabaseFromAuthHeader(req);
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return { error: jsonError(401, "Nao autenticado.") } as const;

  return { supabase, user: data.user } as const;
}

type BodyLike = Record<string, unknown> | null | undefined;

export async function resolveTenantEmpresa(
  supabase: ReturnType<typeof supabaseFromAuthHeader>,
  body?: BodyLike,
  query?: URLSearchParams
) {
  const tenantHint = String(
    body?.tenant_id ??
      body?.tenantId ??
      query?.get("tenant_id") ??
      query?.get("tenantId") ??
      ""
  ).trim();
  const empresaHint = String(
    body?.empresa_id ??
      body?.empresaId ??
      query?.get("empresa_id") ??
      query?.get("empresaId") ??
      ""
  ).trim();

  let tenantId: string | null = null;
  let empresaId: string | null = null;

  try {
    const { data } = await supabase.rpc("current_tenant_id");
    tenantId = data ? String(data) : null;
  } catch {
    tenantId = null;
  }

  if (!tenantId && tenantHint && UUID_RE.test(tenantHint)) {
    try {
      await supabase.rpc("set_current_tenant", { p_tenant_id: tenantHint });
      const { data } = await supabase.rpc("current_tenant_id");
      tenantId = data ? String(data) : tenantHint;
    } catch {
      tenantId = null;
    }
  }

  try {
    const { data } = await supabase.rpc("current_empresa_id");
    empresaId = data ? String(data) : null;
  } catch {
    empresaId = null;
  }

  if (!empresaId && empresaHint && UUID_RE.test(empresaHint)) {
    try {
      await supabase.rpc("set_current_empresa", { p_empresa_id: empresaHint });
      const { data } = await supabase.rpc("current_empresa_id");
      empresaId = data ? String(data) : empresaHint;
    } catch {
      empresaId = null;
    }
  }

  if (!tenantId || !empresaId) return null;
  return { tenantId, empresaId };
}

export async function canCompras(
  supabase: ReturnType<typeof supabaseFromAuthHeader>,
  action: "read" | "write" | "approve" | "receive"
) {
  const { data } = await supabase.rpc("can", { p_resource: "compras", p_action: action });
  return Boolean(data);
}

function roundMoney(value: number) {
  if (!Number.isFinite(value)) return 0;
  return Math.round(value * 100) / 100;
}

export function calcPedidoItemValorTotal(quantidade: number, valorUnitario: number) {
  return roundMoney((Number.isFinite(quantidade) ? quantidade : 0) * (Number.isFinite(valorUnitario) ? valorUnitario : 0));
}

export async function syncPedidoTotais(
  supabase: AuthedSupabase,
  pedidoId: string,
  tenantId: string,
  empresaId: string
): Promise<SyncPedidoTotaisResult> {
  const { data: pedido, error: pedidoErr } = await supabase
    .schema("m")
    .from("pedido_compra")
    .select("id,total_frete,total_desconto")
    .eq("id", pedidoId)
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .is("deleted_at", null)
    .single();
  if (pedidoErr || !pedido) {
    return { error: pedidoErr?.message ?? "Pedido nao encontrado para recalculo." } as const;
  }

  const { data: itens, error: itensErr } = await supabase
    .schema("m")
    .from("pedido_compra_item")
    .select("valor_total")
    .eq("pedido_compra_id", pedidoId)
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .is("deleted_at", null);
  if (itensErr) return { error: itensErr.message } as const;

  const totalItens = roundMoney(
    (Array.isArray(itens) ? itens : []).reduce((acc, row) => acc + Number((row as Record<string, unknown>).valor_total ?? 0), 0)
  );
  const totalFrete = roundMoney(Number((pedido as Record<string, unknown>).total_frete ?? 0));
  const totalDesconto = roundMoney(Number((pedido as Record<string, unknown>).total_desconto ?? 0));
  const totalGeral = roundMoney(totalItens + totalFrete - totalDesconto);

  const { error: updErr } = await supabase
    .schema("m")
    .from("pedido_compra")
    .update({
      total_itens: totalItens,
      total_geral: totalGeral,
      updated_by: null,
    })
    .eq("id", pedidoId)
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .is("deleted_at", null);
  if (updErr) return { error: updErr.message } as const;

  return { data: { totalItens, totalGeral } } as const;
}
