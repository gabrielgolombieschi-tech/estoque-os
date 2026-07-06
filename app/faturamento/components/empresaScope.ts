"use client";

import type { SupabaseClient } from "@supabase/supabase-js";

// f.documento_fiscal e f.titulo sao restritos por RLS a
// `empresa_id = public.current_empresa_id()`. Para listar documentos de mais
// de uma empresa numa mesma tela, alternamos o contexto (RPC set_current_empresa)
// por empresa, coletamos os dados e restauramos o contexto original ao final.
// Isso segue o mesmo padrao ja usado em app/api/faturamento/nfe/importar-xml.

export const EMPRESA_SCOPE_ALL = "ALL" as const;
export type EmpresaScope = typeof EMPRESA_SCOPE_ALL | string;

export function resolveScopeEmpresaIds(scope: EmpresaScope, allowedIds: string[]): string[] {
  if (scope === EMPRESA_SCOPE_ALL) return allowedIds;
  return allowedIds.includes(scope) ? [scope] : allowedIds;
}

export function normalizeEmpresaScopeParam(value: string | null, allowedIds: string[]): EmpresaScope {
  if (!value) return EMPRESA_SCOPE_ALL;
  if (value === EMPRESA_SCOPE_ALL) return EMPRESA_SCOPE_ALL;
  return allowedIds.includes(value) ? value : EMPRESA_SCOPE_ALL;
}

/**
 * Executa `fetcher` uma vez por empresa em `targetEmpresaIds`, trocando o
 * current_empresa_id() da sessao a cada iteracao, e restaura `restoreEmpresaId`
 * ao final (mesmo em caso de erro).
 */
export async function runAcrossEmpresas<R>(
  supabase: SupabaseClient,
  targetEmpresaIds: string[],
  restoreEmpresaId: string | null,
  fetcher: (empresaId: string) => Promise<R>
): Promise<Record<string, R>> {
  const out: Record<string, R> = {};
  // O contexto vive em public.user_empresa_context (persistido por usuario,
  // nao por conexao), entao ele pode estar dessincronizado do te.empresaId da
  // sessao — por exemplo, se uma execucao anterior parou no meio. Por isso
  // sempre setamos antes de cada busca e sempre restauramos no final, mesmo
  // com uma unica empresa alvo.
  let lastSetEmpresaId: string | null = null;

  try {
    for (const empresaId of targetEmpresaIds) {
      await supabase.rpc("set_current_empresa", { p_empresa_id: empresaId });
      lastSetEmpresaId = empresaId;
      out[empresaId] = await fetcher(empresaId);
    }
  } finally {
    if (restoreEmpresaId && lastSetEmpresaId && lastSetEmpresaId !== restoreEmpresaId) {
      await supabase.rpc("set_current_empresa", { p_empresa_id: restoreEmpresaId });
    }
  }

  return out;
}
