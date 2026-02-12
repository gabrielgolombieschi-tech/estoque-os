import type { SupabaseClient } from "@supabase/supabase-js";
import type { CondicaoPagamentoRow } from "@/lib/comercial/types";

type UniqueViolationLike = { code?: string; message?: string; details?: string };

export function isUniqueViolation(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const e = error as UniqueViolationLike;
  return String(e.code ?? "") === "23505" || String(e.message ?? "").toLowerCase().includes("duplicate key");
}

export async function list(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; onlyActive?: boolean }
): Promise<CondicaoPagamentoRow[]> {
  let q = supabase
    .schema("c")
    .from("condicao_pagamento")
    .select("*")
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId)
    .is("deleted_at", null)
    .order("dias", { ascending: true, nullsFirst: false })
    .order("codigo", { ascending: true })
    .limit(5000);

  if (params.onlyActive) q = q.eq("ativo", true);

  const { data, error } = await q.returns<CondicaoPagamentoRow[]>();
  if (error) throw error;
  return (data ?? []) as CondicaoPagamentoRow[];
}

export async function create(
  supabase: SupabaseClient,
  params: {
    tenantId: string;
    empresaId: string;
    payload: Pick<CondicaoPagamentoRow, "codigo" | "nome" | "dias" | "acrescimo_percent" | "ativo">;
  }
): Promise<void> {
  const row: Omit<CondicaoPagamentoRow, "id" | "created_at" | "updated_at" | "deleted_at"> & { updated_at: string } = {
    tenant_id: params.tenantId,
    empresa_id: params.empresaId,
    codigo: params.payload.codigo,
    nome: params.payload.nome,
    dias: params.payload.dias ?? null,
    acrescimo_percent: params.payload.acrescimo_percent,
    ativo: params.payload.ativo,
    updated_at: new Date().toISOString(),
  };

  const { error } = await supabase.schema("c").from("condicao_pagamento").insert(row);
  if (error) throw error;
}

export async function update(
  supabase: SupabaseClient,
  params: {
    tenantId: string;
    empresaId: string;
    id: string;
    patch: Pick<CondicaoPagamentoRow, "codigo" | "nome" | "dias" | "acrescimo_percent" | "ativo">;
  }
): Promise<void> {
  const payload: Partial<CondicaoPagamentoRow> & { updated_at: string } = {
    ...params.patch,
    updated_at: new Date().toISOString(),
  };
  const { error } = await supabase
    .schema("c")
    .from("condicao_pagamento")
    .update(payload)
    .eq("id", params.id)
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId);
  if (error) throw error;
}

export async function softDelete(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; id: string }
): Promise<void> {
  const now = new Date().toISOString();
  const { error } = await supabase
    .schema("c")
    .from("condicao_pagamento")
    .update({ deleted_at: now, updated_at: now })
    .eq("id", params.id)
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId);
  if (error) throw error;
}
