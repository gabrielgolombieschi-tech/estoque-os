import { isOrcamentoEditableStatus } from "@/lib/comercial/status";
import type { SupabaseClient } from "@supabase/supabase-js";

export type SupabaseErrorLike = { code?: string; message?: string } | null | undefined;

export function toSupabaseErrorLike(error: unknown): SupabaseErrorLike {
  if (!error || typeof error !== "object") return null;
  const e = error as Record<string, unknown>;
  const code = typeof e.code === "string" ? e.code : undefined;
  const message = typeof e.message === "string" ? e.message : undefined;
  if (!code && !message) return null;
  return { code, message };
}

export function n(value: unknown): number {
  if (value === null || value === undefined) return 0;
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  if (typeof value === "string") {
    const v = Number(value);
    return Number.isFinite(v) ? v : 0;
  }
  return 0;
}

export async function getSuggestedOrcamentoUnitPrice(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; itemId: number }
): Promise<number> {
  const { data, error } = await supabase.schema("m").rpc("fn_orcamento_preco_sugerido_item_por_id", {
    p_tenant_id: params.tenantId,
    p_empresa_id: params.empresaId,
    p_item_id: params.itemId,
  });
  if (error) throw error;
  const value = n(data);
  return Number.isFinite(value) && value > 0 ? value : 0;
}

export function upperTrim(v: string): string {
  return String(v ?? "")
    .trim()
    .toUpperCase();
}

export function isOrcamentoReadOnly(status: string | null | undefined): boolean {
  return !isOrcamentoEditableStatus(status);
}

export function mapOrcamentoError(error: SupabaseErrorLike, fallback: string): string {
  const msg = typeof error?.message === "string" ? error.message : "";
  if (!msg) return fallback;

  const lower = msg.toLowerCase();
  if (lower.includes("desconto global") && lower.includes("excede")) {
    return "Desconto global (%) excede o máximo configurado.";
  }
  if (lower.includes("cliente inválido") || lower.includes("cliente invalido")) {
    return "Cliente inválido para este tenant/empresa.";
  }
  if (lower.includes("condição de pagamento inválida") || lower.includes("condicao de pagamento invalida")) {
    return "Condição de pagamento inválida.";
  }
  if (lower.includes("vendedor inválido") || lower.includes("vendedor invalido")) {
    return "Vendedor inválido.";
  }
  return msg;
}
