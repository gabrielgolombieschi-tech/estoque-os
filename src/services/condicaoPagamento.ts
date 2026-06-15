import type { SupabaseClient } from "@supabase/supabase-js";
import type { CondicaoPagamentoRow } from "@/lib/comercial/types";

type UniqueViolationLike = { code?: string; message?: string; details?: string };
type CondicaoPagamentoPayload = Pick<CondicaoPagamentoRow, "codigo" | "nome" | "dias" | "acrescimo_percent" | "ativo">;
type CondicaoPagamentoSeedLookupRow = Pick<CondicaoPagamentoRow, "id" | "codigo" | "nome" | "ativo" | "deleted_at">;

export type EnsureCondicaoPagamentoDefaultsResult = {
  inserted: number;
  reactivated: number;
  skipped: number;
};

export const DEFAULT_CONDICOES_PAGAMENTO: ReadonlyArray<CondicaoPagamentoPayload> = [
  { codigo: "AVISTA", nome: "A VISTA", dias: 0, acrescimo_percent: 0, ativo: true },
  { codigo: "07D", nome: "7 DIAS", dias: 7, acrescimo_percent: 0.26, ativo: true },
  { codigo: "14D", nome: "14 DIAS", dias: 14, acrescimo_percent: 0.52, ativo: true },
  { codigo: "21D", nome: "21 DIAS", dias: 21, acrescimo_percent: 0.78, ativo: true },
  { codigo: "28D", nome: "28 DIAS", dias: 28, acrescimo_percent: 1.04, ativo: true },
  { codigo: "30D", nome: "30 DIAS", dias: 30, acrescimo_percent: 1.12, ativo: true },
  { codigo: "45D", nome: "45 DIAS", dias: 45, acrescimo_percent: 1.68, ativo: true },
  { codigo: "60D", nome: "60 DIAS", dias: 60, acrescimo_percent: 2.25, ativo: true },
  { codigo: "90D", nome: "90 DIAS", dias: 90, acrescimo_percent: 3.4, ativo: true },
  { codigo: "28_56", nome: "28/56 DIAS", dias: null, acrescimo_percent: 1.57, ativo: true },
  { codigo: "30_60", nome: "30/60 DIAS", dias: null, acrescimo_percent: 1.68, ativo: true },
  { codigo: "30_60_90", nome: "30/60/90 DIAS", dias: null, acrescimo_percent: 2.25, ativo: true },
];

function normalizeLookupKey(value: unknown): string {
  return String(value ?? "").trim().toUpperCase();
}

function normalizePrazoKey(value: unknown): string {
  const normalized = normalizeLookupKey(value)
    .replace(/\bDIAS?\b/g, "")
    .replace(/D\b/g, "")
    .replace(/_/g, "/")
    .replace(/\s+/g, "");

  const tokens = normalized.match(/\d+/g);
  return tokens?.length ? tokens.map((token) => String(Number(token))).join("/") : normalized;
}

function seedMatchScore(row: CondicaoPagamentoSeedLookupRow | null | undefined): number {
  if (!row) return -1;
  let score = 0;
  if (!row.deleted_at) score += 100;
  if (row.ativo) score += 50;
  if (/\bDIAS?\b/i.test(String(row.nome ?? ""))) score += 10;
  if (/[D_]/i.test(String(row.codigo ?? ""))) score += 5;
  return score;
}

function setPreferredMatch(
  map: Map<string, CondicaoPagamentoSeedLookupRow>,
  key: string,
  row: CondicaoPagamentoSeedLookupRow
): void {
  if (!key) return;
  const current = map.get(key);
  if (!current || seedMatchScore(row) > seedMatchScore(current)) map.set(key, row);
}

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
    payload: CondicaoPagamentoPayload;
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
    patch: CondicaoPagamentoPayload;
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

export async function ensureDefaults(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string }
): Promise<EnsureCondicaoPagamentoDefaultsResult> {
  const { data, error } = await supabase
    .schema("c")
    .from("condicao_pagamento")
    .select("id,codigo,nome,ativo,deleted_at")
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId)
    .limit(5000)
    .returns<CondicaoPagamentoSeedLookupRow[]>();

  if (error) throw error;

  const byCode = new Map<string, CondicaoPagamentoSeedLookupRow>();
  const byName = new Map<string, CondicaoPagamentoSeedLookupRow>();
  const byPrazo = new Map<string, CondicaoPagamentoSeedLookupRow>();

  for (const row of data ?? []) {
    setPreferredMatch(byCode, normalizeLookupKey(row.codigo), row);
    setPreferredMatch(byName, normalizeLookupKey(row.nome), row);
    setPreferredMatch(byPrazo, normalizePrazoKey(row.codigo), row);
    setPreferredMatch(byPrazo, normalizePrazoKey(row.nome), row);
  }

  let inserted = 0;
  let reactivated = 0;

  for (const seed of DEFAULT_CONDICOES_PAGAMENTO) {
    const match =
      byCode.get(normalizeLookupKey(seed.codigo)) ??
      byName.get(normalizeLookupKey(seed.nome)) ??
      byPrazo.get(normalizePrazoKey(seed.codigo)) ??
      byPrazo.get(normalizePrazoKey(seed.nome)) ??
      null;

    if (!match) {
      try {
        await create(supabase, {
          tenantId: params.tenantId,
          empresaId: params.empresaId,
          payload: seed,
        });
        inserted += 1;
      } catch (createError: unknown) {
        if (!isUniqueViolation(createError)) throw createError;
      }
      continue;
    }

    if (!match.deleted_at && match.ativo) continue;

    const { error: updateError } = await supabase
      .schema("c")
      .from("condicao_pagamento")
      .update({
        codigo: seed.codigo,
        nome: seed.nome,
        dias: seed.dias ?? null,
        acrescimo_percent: seed.acrescimo_percent,
        ativo: seed.ativo,
        deleted_at: null,
        updated_at: new Date().toISOString(),
      })
      .eq("id", match.id)
      .eq("tenant_id", params.tenantId)
      .eq("empresa_id", params.empresaId);

    if (updateError) throw updateError;
    reactivated += 1;
  }

  return {
    inserted,
    reactivated,
    skipped: DEFAULT_CONDICOES_PAGAMENTO.length - inserted - reactivated,
  };
}
