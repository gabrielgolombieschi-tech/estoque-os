import { NextRequest } from "next/server";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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
