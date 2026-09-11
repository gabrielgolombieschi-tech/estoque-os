import type { SupabaseClient } from "@supabase/supabase-js";
import { applyTenantEmpresa } from "@/lib/db/scopes";

const FETCH_BATCH_SIZE = 1000;

export type DocumentoFaturadoRow = {
  os_id_import: number | null;
  valor_total: number | string | null;
  valor_servicos: number | string | null;
  valor_produtos: number | string | null;
  modelo: string | null;
  nfe_status: string | null;
  nfse_status: string | null;
};

function n(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

function round2(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

export function shouldIncludeFaturamentoDocumento(row: DocumentoFaturadoRow): boolean {
  const modelo = String(row.modelo ?? "").trim().toUpperCase();
  const nfseStatus = String(row.nfse_status ?? "").trim().toUpperCase();
  const nfeStatus = String(row.nfe_status ?? "").trim().toUpperCase();

  if (modelo === "NFSE") return nfseStatus === "EMITIDA";
  if (!nfeStatus) return true;
  return nfeStatus === "EMITIDA";
}

/**
 * Quanto o documento consome do pedido da OS. Espelho de `f.fn_documento_valor_faturado`:
 * NFS-e pelo bruto do servico, porque o `valor_total` dela e o liquido e as retencoes sao
 * imposto, nao desconto (OS 139, 11/09/2026); NF-e pelo vNF, que ja traz o IPI.
 */
export function valorFaturadoDocumento(row: DocumentoFaturadoRow): number {
  const modelo = String(row.modelo ?? "").trim().toUpperCase();
  const valor = modelo === "NFSE"
    ? n(row.valor_servicos) || n(row.valor_total)
    : row.valor_total != null ? n(row.valor_total) : n(row.valor_produtos);
  return round2(Math.max(valor, 0));
}

/**
 * Soma o valor faturado (documento_fiscal SAIDA emitido) por OS.
 * Sem `osIds`, pagina o tenant/empresa inteiro. Com `osIds`, escopa a busca a esse conjunto
 * (mais barato quando o chamador ja sabe quais OS quer, ex.: uma listagem paginada).
 *
 * Regra alinhada com `f.fn_os_saldo_a_faturar` (migrations 20260905170000 e 20260911160000): conta apenas
 * documento EMITIDA (producao) ou importado sem status NF-e. Documento que so passou pela
 * homologacao fica RASCUNHO e nao entra aqui nem no saldo. A reserva por solicitacao aberta
 * e a decisao "OS Faturada" (documento emitido E saldo zero) ficam em
 * `f.fn_os_saldo_a_faturar` / `f.fn_os_pronta_para_faturada`, nao neste helper.
 */
export async function fetchFaturadoByOs(params: {
  supabase: SupabaseClient;
  tenantId: string;
  empresaId: string;
  osIds?: number[];
}): Promise<Record<number, number>> {
  const out: Record<number, number> = {};

  if (params.osIds) {
    if (params.osIds.length === 0) return out;

    const { data, error } = await applyTenantEmpresa(
      params.supabase
        .schema("f")
        .from("documento_fiscal")
        .select("os_id_import,valor_total,valor_servicos,valor_produtos,modelo,nfe_status,nfse_status")
        .eq("operacao", "SAIDA")
        .not("os_id_import", "is", null)
        .is("deleted_at", null)
        .in("os_id_import", params.osIds),
      params.tenantId,
      params.empresaId
    ).returns<DocumentoFaturadoRow[]>();

    if (error) throw error;

    for (const row of data ?? []) {
      if (!shouldIncludeFaturamentoDocumento(row)) continue;
      const osId = Number(row.os_id_import);
      if (!Number.isFinite(osId) || osId <= 0) continue;
      out[osId] = round2((out[osId] ?? 0) + valorFaturadoDocumento(row));
    }

    return out;
  }

  let offset = 0;
  while (true) {
    const { data, error } = await applyTenantEmpresa(
      params.supabase
        .schema("f")
        .from("documento_fiscal")
        .select("os_id_import,valor_total,valor_servicos,valor_produtos,modelo,nfe_status,nfse_status")
        .eq("operacao", "SAIDA")
        .not("os_id_import", "is", null)
        .is("deleted_at", null)
        .order("id", { ascending: true })
        .range(offset, offset + FETCH_BATCH_SIZE - 1),
      params.tenantId,
      params.empresaId
    ).returns<DocumentoFaturadoRow[]>();

    if (error) throw error;

    const rows = data ?? [];
    for (const row of rows) {
      if (!shouldIncludeFaturamentoDocumento(row)) continue;
      const osId = Number(row.os_id_import);
      if (!Number.isFinite(osId) || osId <= 0) continue;
      out[osId] = round2((out[osId] ?? 0) + valorFaturadoDocumento(row));
    }

    if (rows.length < FETCH_BATCH_SIZE) break;
    offset += FETCH_BATCH_SIZE;
  }

  return out;
}
