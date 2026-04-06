import type { SupabaseClient } from "@supabase/supabase-js";
import { applyTenantEmpresa } from "@/lib/db/scopes";

export type OsLookupRow = {
  id: number;
  numero_os: string | null;
  cliente_nome: string | null;
  descricao_servico: string | null;
  status: string | null;
};

export type OsSelection = {
  id: number;
  numeroOs: string;
  clienteNome: string;
  descricao: string;
  status: string | null;
};

type ScopedParams = {
  supabase: SupabaseClient;
  tenantId: string;
  empresaId: string;
};

const OS_SEARCH_FETCH_LIMIT = 300;

export function normalizeOsSelection(row: OsLookupRow): OsSelection {
  return {
    id: Number(row.id),
    numeroOs: String(row.numero_os ?? row.id),
    clienteNome: String(row.cliente_nome ?? "").trim(),
    descricao: String(row.descricao_servico ?? "").trim(),
    status: row.status ? String(row.status) : null,
  };
}

function sanitizeSearchTerm(raw: string): string {
  return raw.replace(/[%_,()]/g, " ").replace(/\s+/g, " ").trim();
}

function normalizeSearchText(raw: string): string {
  return sanitizeSearchTerm(raw)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}

function buildSearchableOsText(selection: OsSelection): string {
  return normalizeSearchText(
    [selection.id, selection.numeroOs, selection.clienteNome, selection.descricao, selection.status]
      .filter(Boolean)
      .join(" ")
  );
}

export async function fetchOsSelectionById({
  supabase,
  tenantId,
  empresaId,
  osId,
}: ScopedParams & { osId: number | null | undefined }): Promise<OsSelection | null> {
  if (!Number.isFinite(osId) || Number(osId) <= 0) return null;

  const { data, error } = await applyTenantEmpresa(
    supabase
      .from("ordens_servico")
      .select("id,numero_os,cliente_nome,descricao_servico,status")
      .eq("id", Number(osId))
      .maybeSingle(),
    tenantId,
    empresaId
  ).returns<OsLookupRow | null>();

  if (error) throw error;
  return data ? normalizeOsSelection(data) : null;
}

export async function fetchOsSelectionByExactInput({
  supabase,
  tenantId,
  empresaId,
  input,
}: ScopedParams & { input: string }): Promise<OsSelection | null> {
  const normalized = sanitizeSearchTerm(input);
  if (!normalized) return null;

  const byNumero = await applyTenantEmpresa(
    supabase
      .from("ordens_servico")
      .select("id,numero_os,cliente_nome,descricao_servico,status")
      .eq("numero_os", normalized)
      .neq("status", "cancelada")
      .maybeSingle(),
    tenantId,
    empresaId
  ).returns<OsLookupRow | null>();

  if (byNumero.error) throw byNumero.error;
  if (byNumero.data) return normalizeOsSelection(byNumero.data);

  const asId = Number(normalized);
  if (!Number.isFinite(asId) || asId <= 0) return null;

  const byId = await fetchOsSelectionById({
    supabase,
    tenantId,
    empresaId,
    osId: asId,
  });

  if (byId && String(byId.status ?? "").toLowerCase() === "cancelada") return null;
  return byId;
}

export async function searchOsSelections({
  supabase,
  tenantId,
  empresaId,
  term,
  limit = 50,
}: ScopedParams & { term: string; limit?: number }): Promise<OsSelection[]> {
  const normalized = normalizeSearchText(term);
  const fetchLimit = Math.max(limit, OS_SEARCH_FETCH_LIMIT);

  const { data, error } = await applyTenantEmpresa(
    supabase
      .from("ordens_servico")
      .select("id,numero_os,cliente_nome,descricao_servico,status")
      .in("status", ["aberta", "em_andamento"])
      .order("id", { ascending: false })
      .limit(fetchLimit),
    tenantId,
    empresaId
  ).returns<OsLookupRow[]>();

  if (error) throw error;

  const selections = (data ?? []).map(normalizeOsSelection);
  if (!normalized) return selections.slice(0, limit);

  return selections
    .filter((selection) => buildSearchableOsText(selection).includes(normalized))
    .slice(0, limit);
}
