import type { SupabaseClient } from "@supabase/supabase-js";
import type { ConfigOrcamentoRow } from "@/lib/comercial/types";
import { upperTrim } from "@/lib/comercial/utils";

export const DEFAULT_CONJUNTO_CATEGORIAS = ["PAINEIS AUTOPORTANTE", "PAINEIS DE COMANDO"] as const;

export function normalizeConjuntoCategorias(input: Iterable<unknown> | null | undefined): string[] {
  const uniq = new Set<string>();

  for (const raw of input ?? []) {
    const value = upperTrim(String(raw ?? ""));
    if (value) uniq.add(value);
  }

  if (uniq.size === 0) {
    DEFAULT_CONJUNTO_CATEGORIAS.forEach((value) => uniq.add(value));
  }

  return Array.from(uniq);
}

export function getConjuntoCategorias(cfg: Pick<ConfigOrcamentoRow, "conjunto_categorias"> | null | undefined): string[] {
  return normalizeConjuntoCategorias(cfg?.conjunto_categorias ?? null);
}

export async function getConfig(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string }
): Promise<ConfigOrcamentoRow | null> {
  const { data, error } = await supabase
    .schema("a")
    .from("config_orcamento")
    .select("*")
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId)
    .is("deleted_at", null)
    .maybeSingle<ConfigOrcamentoRow>();

  if (error) throw error;
  return data?.id ? (data as ConfigOrcamentoRow) : null;
}

export async function ensureConfig(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string }
): Promise<ConfigOrcamentoRow> {
  const { error } = await supabase
    .schema("a")
    .rpc("ensure_config_orcamento", { p_tenant: params.tenantId, p_empresa: params.empresaId });
  if (error) throw error;

  const cfg = await getConfig(supabase, params);
  if (!cfg?.id) throw new Error("Configuração de orçamento não encontrada.");
  return cfg;
}

export async function updateConfig(
  supabase: SupabaseClient,
  params: {
    tenantId: string;
    empresaId: string;
    id: string;
    patch: Pick<
      ConfigOrcamentoRow,
      | "margem_lucro_padrao_percent"
      | "margem_mao_obra_padrao_percent"
      | "desconto_max_percent"
      | "condicao_pagamento_padrao_id"
      | "conjunto_categorias"
    >;
  }
): Promise<void> {
  const payload: Partial<ConfigOrcamentoRow> & { updated_at: string } = {
    ...params.patch,
    conjunto_categorias: normalizeConjuntoCategorias(params.patch.conjunto_categorias ?? null),
    updated_at: new Date().toISOString(),
  };

  const { error } = await supabase
    .schema("a")
    .from("config_orcamento")
    .update(payload)
    .eq("id", params.id)
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId);

  if (error) throw error;
}
