import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { ContextoEmissao } from "./nfe-payload.ts";
import type { IbptNcm } from "./fiscal/ibpt.ts";

/**
 * Anexa ao contexto as linhas da tabela IBPT (f.ibpt_ncm) dos NCMs da nota, na UF do
 * emitente. O builder (montarPayloadNfe) escolhe a versao vigente na data da emissao.
 *
 * So consulta com indFinal = 1: com 0 a nota nao leva o valor aproximado dos tributos
 * e a tabela nao importa. Falha de leitura aborta a emissao — mandar a nota sem a frase
 * porque a consulta caiu seria indistinguivel de "NCM sem tabela".
 */
export async function anexarIbpt(admin: SupabaseClient, contexto: ContextoEmissao): Promise<ContextoEmissao> {
  const operacao = (contexto.solicitacao?.operacao_snapshot ?? {}) as Record<string, unknown>;
  if (Number(operacao.consumidor_final) !== 1) return contexto;
  const emitente = (contexto.solicitacao?.emitente_snapshot ?? {}) as Record<string, unknown>;
  const uf = String(emitente.uf ?? "").trim().toUpperCase();
  const ncms = [...new Set(
    (contexto.itens ?? [])
      .map((linha) => String(linha.solicitacao_item?.ncm ?? "").replace(/\D/g, ""))
      .filter((ncm) => ncm.length === 8),
  )];
  if (!uf || ncms.length === 0) return contexto;
  const { data, error } = await admin.schema("f")
    .from("ibpt_ncm")
    .select("uf,codigo,ex,descricao,nacional_federal_pct,importados_federal_pct,estadual_pct,municipal_pct,vigencia_inicio,vigencia_fim,versao,chave,fonte")
    .eq("uf", uf)
    .in("codigo", ncms);
  if (error) throw new Error(`Nao foi possivel ler a tabela IBPT: ${error.message}`);
  return { ...contexto, ibpt: (data ?? []) as IbptNcm[] };
}
