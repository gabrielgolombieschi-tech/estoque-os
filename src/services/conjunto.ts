import type { SupabaseClient } from "@supabase/supabase-js";

export type ConjuntoRow = {
  id: string;
  tenant_id: string;
  empresa_id: string;
  codigo: string | null;
  nome: string | null;
  categoria: string | null;
  precificacao: string | null;
  preco_fixo: number | string | null;
  ativo: boolean | null;
  descricao: string | null;
  observacoes: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

export type ConjuntoItemRow = {
  id: string;
  tenant_id: string;
  empresa_id: string;
  conjunto_id: string;
  ordem: number | null;
  item_id: number;
  quantidade: number | string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

export async function listConjuntos(
  supabase: SupabaseClient,
  params: {
    tenantId: string;
    empresaId: string;
    term?: string;
    onlyActive?: boolean;
  }
): Promise<ConjuntoRow[]> {
  let q = supabase
    .schema("c")
    .from("conjunto")
    .select("*")
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId)
    .is("deleted_at", null)
    .order("codigo", { ascending: true })
    .limit(5000);

  if (params.onlyActive) q = q.eq("ativo", true);

  const term = String(params.term ?? "").trim();
  if (term) {
    // Search by codigo OR nome
    q = q.or(`codigo.ilike.%${term}%,nome.ilike.%${term}%`);
  }

  const { data, error } = await q.returns<ConjuntoRow[]>();
  if (error) throw error;
  return (data ?? []) as ConjuntoRow[];
}

export async function getConjunto(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; id: string }
): Promise<ConjuntoRow | null> {
  const { data, error } = await supabase
    .schema("c")
    .from("conjunto")
    .select("*")
    .eq("id", params.id)
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId)
    .is("deleted_at", null)
    .maybeSingle<ConjuntoRow>();

  if (error) throw error;
  return (data ?? null) as ConjuntoRow | null;
}

export async function createConjunto(
  supabase: SupabaseClient,
  params: {
    tenantId: string;
    empresaId: string;
    payload: Pick<ConjuntoRow, "codigo" | "nome" | "categoria" | "precificacao" | "preco_fixo" | "ativo" | "descricao" | "observacoes">;
  }
): Promise<ConjuntoRow> {
  const now = new Date().toISOString();
  const row: Omit<ConjuntoRow, "id" | "created_at" | "updated_at" | "deleted_at"> & { updated_at: string } = {
    tenant_id: params.tenantId,
    empresa_id: params.empresaId,
    codigo: params.payload.codigo ?? null,
    nome: params.payload.nome ?? null,
    categoria: params.payload.categoria ?? null,
    precificacao: params.payload.precificacao ?? null,
    preco_fixo: params.payload.preco_fixo ?? null,
    ativo: params.payload.ativo ?? true,
    descricao: params.payload.descricao ?? null,
    observacoes: params.payload.observacoes ?? null,
    updated_at: now,
  };

  const { data, error } = await supabase
    .schema("c")
    .from("conjunto")
    .insert(row)
    .select("*")
    .single<ConjuntoRow>();
  if (error) throw error;
  return data as ConjuntoRow;
}

export async function updateConjunto(
  supabase: SupabaseClient,
  params: {
    tenantId: string;
    empresaId: string;
    id: string;
    patch: Pick<ConjuntoRow, "codigo" | "nome" | "categoria" | "precificacao" | "preco_fixo" | "ativo" | "descricao" | "observacoes">;
  }
): Promise<void> {
  const payload: Partial<ConjuntoRow> & { updated_at: string } = {
    ...params.patch,
    updated_at: new Date().toISOString(),
  };
  const { error } = await supabase
    .schema("c")
    .from("conjunto")
    .update(payload)
    .eq("id", params.id)
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId);
  if (error) throw error;
}

export async function softDeleteConjunto(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; id: string }
): Promise<void> {
  const now = new Date().toISOString();
  const { error } = await supabase
    .schema("c")
    .from("conjunto")
    .update({ deleted_at: now, updated_at: now })
    .eq("id", params.id)
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId);
  if (error) throw error;
}

export async function listConjuntoItens(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; conjuntoId: string }
): Promise<ConjuntoItemRow[]> {
  const { data, error } = await supabase
    .schema("c")
    .from("conjunto_item")
    .select("*")
    .eq("conjunto_id", params.conjuntoId)
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId)
    .is("deleted_at", null)
    .order("ordem", { ascending: true, nullsFirst: false })
    .limit(5000)
    .returns<ConjuntoItemRow[]>();
  if (error) throw error;
  return (data ?? []) as ConjuntoItemRow[];
}

export async function insertConjuntoItem(
  supabase: SupabaseClient,
  params: {
    tenantId: string;
    empresaId: string;
    conjuntoId: string;
    payload: Pick<ConjuntoItemRow, "ordem" | "item_id" | "quantidade">;
  }
): Promise<void> {
  const now = new Date().toISOString();
  const row: Omit<ConjuntoItemRow, "id" | "created_at" | "updated_at" | "deleted_at"> & { updated_at: string } = {
    tenant_id: params.tenantId,
    empresa_id: params.empresaId,
    conjunto_id: params.conjuntoId,
    ordem: params.payload.ordem ?? null,
    item_id: params.payload.item_id,
    quantidade: params.payload.quantidade ?? null,
    updated_at: now,
  };
  const { error } = await supabase.schema("c").from("conjunto_item").insert(row);
  if (error) throw error;
}

export async function updateConjuntoItem(
  supabase: SupabaseClient,
  params: {
    tenantId: string;
    empresaId: string;
    id: string;
    patch: Pick<ConjuntoItemRow, "ordem" | "item_id" | "quantidade">;
  }
): Promise<void> {
  const now = new Date().toISOString();
  const payload: Partial<ConjuntoItemRow> & { updated_at: string } = {
    ...params.patch,
    updated_at: now,
  };
  const { error } = await supabase
    .schema("c")
    .from("conjunto_item")
    .update(payload)
    .eq("id", params.id)
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId);
  if (error) throw error;
}

export async function softDeleteConjuntoItens(
  supabase: SupabaseClient,
  params: { tenantId: string; empresaId: string; ids: string[] }
): Promise<void> {
  if (params.ids.length === 0) return;
  const now = new Date().toISOString();
  const { error } = await supabase
    .schema("c")
    .from("conjunto_item")
    .update({ deleted_at: now, updated_at: now })
    .in("id", params.ids)
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId);
  if (error) throw error;
}
