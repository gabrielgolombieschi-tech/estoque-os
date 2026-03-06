
import { applyTenant } from "@/lib/db/scopes";
import type { SupabaseClient } from "@supabase/supabase-js";

type SupabaseErrorLike = {
  message?: string;
  details?: string;
  hint?: string;
};

function toSupabaseErrorLike(err: unknown): SupabaseErrorLike {
  if (!err || typeof err !== "object") return {};
  const e = err as Record<string, unknown>;
  return {
    message: typeof e.message === "string" ? e.message : undefined,
    details: typeof e.details === "string" ? e.details : undefined,
    hint: typeof e.hint === "string" ? e.hint : undefined,
  };
}

type SyncArgs = {
  supabase: SupabaseClient;
  tenantId: string;
  empresaId: string | null;
  osId: number;
  colaboradorId: string;
  dataISO: string;
  periodos: Array<{ entrada: string; saida: string }>;
  descricao?: string;
  percentual?: 0 | 50 | 100;
};

function parseHHMMToMinutes(hhmm: string): number | null {
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(hhmm);
  if (!m) return null;
  return Number(m[1]) * 60 + Number(m[2]);
}

function isMissingColumnError(err: unknown, col?: string): boolean {
  const msg = String(toSupabaseErrorLike(err).message ?? "").toLowerCase();
  if (col) return msg.includes(`column \"${col.toLowerCase()}\"`) && msg.includes("does not exist");
  return msg.includes("column") && msg.includes("does not exist");
}

function formatSbError(err: unknown): string {
  if (!err) return "Erro desconhecido do Supabase.";
  if (typeof err === "string") return err;
  const e = toSupabaseErrorLike(err);
  const parts = [e.message, e.details, e.hint].filter(Boolean);
  if (parts.length) return parts.join(" | ");
  return String(err);
}

export async function syncHhToApontamentos({
  supabase,
  tenantId,
  empresaId,
  osId,
  colaboradorId,
  dataISO,
  periodos,
  descricao,
  percentual
}: SyncArgs): Promise<void> {
  // 1. Resolve tipo_hora_id
  let codigoTipo = "NORMAL";
  if (percentual === 50) codigoTipo = "EXTRA_50";
  if (percentual === 100) codigoTipo = "EXTRA_100";
  const { data: tipoHoras, error: tipoHorasErr } = await applyTenant(
    supabase.from("tipos_horas").select("id").eq("codigo", codigoTipo).eq("ativo", true).maybeSingle(),
    tenantId
  );
  if (tipoHorasErr || !tipoHoras?.id) throw new Error(`Não foi possível resolver tipo_horas para ${codigoTipo}`);
  const tipoHoraId = tipoHoras.id;

  // 2. Delete apontamentos antigos
  const deleteMatchBase = {
    tenant_id: tenantId,
    ...(empresaId ? { empresa_id: empresaId } : {}),
    os_id: osId,
    colaborador_id: colaboradorId,
    data: dataISO,
  };

  let deleteError: unknown | null = null;
  const deleteWithHhFlag = await supabase
    .from("apontamentos_horas")
    .delete()
    .match({
      ...deleteMatchBase,
      gerado_por_hh: true,
    });

  if (deleteWithHhFlag.error) {
    if (isMissingColumnError(deleteWithHhFlag.error, "gerado_por_hh")) {
      // Fallback: remover filtro gerado_por_hh
      const deleteFallback = await supabase
        .from("apontamentos_horas")
        .delete()
        .match(deleteMatchBase);
      if (deleteFallback.error) {
        deleteError = deleteFallback.error;
      }
    } else {
      deleteError = deleteWithHhFlag.error;
    }
  }
  if (deleteError) throw new Error(formatSbError(deleteError));

  // 3. Calcular TOTAL de horas de todos os períodos
  let totalHoras = 0;
  for (const periodo of periodos) {
    const entrada = String(periodo.entrada ?? "").trim();
    const saida = String(periodo.saida ?? "").trim();
    if (!/^([01]\d|2[0-3]):([0-5]\d)$/.test(entrada) || !/^([01]\d|2[0-3]):([0-5]\d)$/.test(saida)) continue;
    const minEntrada = parseHHMMToMinutes(entrada);
    const minSaida = parseHHMMToMinutes(saida);
    if (minEntrada === null || minSaida === null || minSaida <= minEntrada) continue;
    totalHoras += (minSaida - minEntrada) / 60;
  }

  // Se não houver horas válidas, não inserir nada
  if (totalHoras <= 0) {
    return;
  }

  // 4. Inserir um ÚNICO lançamento em apontamentos_horas com total de horas
  // Campos: os_id, colaborador_id, data, tipo_hora_id, horas, gerado_por_hh=true
  // NÃO incluir entrada/saída - apontamentos_horas é simples (apenas quantidade)
  const payload: Record<string, unknown> = {
    tenant_id: tenantId,
    ...(empresaId ? { empresa_id: empresaId } : {}),
    os_id: osId,
    colaborador_id: colaboradorId,
    data: dataISO,
    horas: Number(totalHoras.toFixed(2)),
    tipo_hora_id: tipoHoraId,
    gerado_por_hh: true,
    descricao: descricao ?? null,
  };

  // Fallbacks para colunas opcionais
  const insertPayload = async (value: Record<string, unknown>) => {
    const result = await supabase.from("apontamentos_horas").insert(value);
    return result.error ?? null;
  };

  let insertError: unknown | null = await insertPayload(payload);
  if (insertError && isMissingColumnError(insertError, "empresa_id")) {
    const p2 = { ...payload };
    delete p2.empresa_id;
    insertError = await insertPayload(p2);
    if (insertError && isMissingColumnError(insertError, "descricao")) {
      const p3 = { ...p2 };
      delete p3.descricao;
      insertError = await insertPayload(p3);
      if (insertError && isMissingColumnError(insertError, "gerado_por_hh")) {
        const p4 = { ...p3 };
        delete p4.gerado_por_hh;
        insertError = await insertPayload(p4);
      }
    }
  } else if (insertError && isMissingColumnError(insertError, "descricao")) {
    const p2 = { ...payload };
    delete p2.descricao;
    insertError = await insertPayload(p2);
    if (insertError && isMissingColumnError(insertError, "gerado_por_hh")) {
      const p3 = { ...p2 };
      delete p3.gerado_por_hh;
      insertError = await insertPayload(p3);
    }
  } else if (insertError && isMissingColumnError(insertError, "gerado_por_hh")) {
    const p2 = { ...payload };
    delete p2.gerado_por_hh;
    insertError = await insertPayload(p2);
  }
  if (insertError) throw new Error(formatSbError(insertError));
}
