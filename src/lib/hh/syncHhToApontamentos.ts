import { applyTenant } from "@/lib/db/scopes";
import type { SupabaseClient } from "@supabase/supabase-js";

type SupabaseErrorLike = {
  message?: string;
  details?: string;
  hint?: string;
};

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
  horasNormais?: number | null;
  horasExtra50?: number | null;
  horasExtra100?: number | null;
};

type ApontamentoExistingRow = {
  id: string;
  horas?: number | null;
  gerado_por_hh?: boolean | null;
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

function normalizeHoras(value: number | null | undefined): number {
  const n = Number(value ?? 0);
  if (!Number.isFinite(n)) return 0;
  return Number(n.toFixed(2));
}

function normalizeFator(value: number): number {
  if (!Number.isFinite(value) || value <= 0) return 1;
  return Number(value.toFixed(3));
}

async function resolveTipoHoraId(
  supabase: SupabaseClient,
  tenantId: string,
  codigo: "NORMAL" | "EXTRA_50" | "EXTRA_100"
): Promise<string> {
  const { data, error } = await applyTenant(
    supabase.from("tipos_horas").select("id").eq("codigo", codigo).eq("ativo", true).maybeSingle(),
    tenantId
  );

  if (error || !data?.id) throw new Error(`Nao foi possivel resolver tipo_horas para ${codigo}`);
  return String(data.id);
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
  percentual,
  horasNormais,
  horasExtra50,
  horasExtra100,
}: SyncArgs): Promise<void> {
  const matchBase = {
    tenant_id: tenantId,
    ...(empresaId ? { empresa_id: empresaId } : {}),
    os_id: osId,
    colaborador_id: colaboradorId,
    data: dataISO,
  };

  const deleteGeneratedRows = async (exceptId?: string): Promise<void> => {
    let query = supabase
      .from("apontamentos_horas")
      .delete()
      .match({
        ...matchBase,
        gerado_por_hh: true,
      });
    if (exceptId) query = query.neq("id", exceptId);
    const result = await query;

    if (result.error && isMissingColumnError(result.error, "gerado_por_hh")) {
      let fallback = supabase.from("apontamentos_horas").delete().match(matchBase);
      if (exceptId) fallback = fallback.neq("id", exceptId);
      const fallbackResult = await fallback;
      if (fallbackResult.error) throw new Error(formatSbError(fallbackResult.error));
      return;
    }

    if (result.error) throw new Error(formatSbError(result.error));
  };

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

  totalHoras = normalizeHoras(totalHoras);

  const hasSplitOverride =
    horasNormais !== undefined || horasExtra50 !== undefined || horasExtra100 !== undefined;
  const extra50 = normalizeHoras(horasExtra50);
  const extra100 = normalizeHoras(horasExtra100);
  let normal = normalizeHoras(horasNormais);

  if (hasSplitOverride && totalHoras <= 0) {
    totalHoras = normalizeHoras(normal + extra50 + extra100);
  }

  if (hasSplitOverride && normal <= 0) {
    normal = normalizeHoras(totalHoras - extra50 - extra100);
  }

  if (extra50 < 0 || extra100 < 0 || normal < 0) {
    throw new Error("Horas normais/extras nao podem ser negativas.");
  }

  if (hasSplitOverride && normalizeHoras(normal + extra50 + extra100) > totalHoras) {
    throw new Error("Horas normais/extras excedem o total de horas do lancamento.");
  }

  if (!hasSplitOverride) {
    normal = percentual === 50 || percentual === 100 ? 0 : totalHoras;
  }

  const splitExtra50 = hasSplitOverride ? extra50 : percentual === 50 ? totalHoras : 0;
  const splitExtra100 = hasSplitOverride ? extra100 : percentual === 100 ? totalHoras : 0;

  if (totalHoras <= 0) {
    await deleteGeneratedRows();
    return;
  }

  const tipoNormalId = await resolveTipoHoraId(supabase, tenantId, "NORMAL");
  const fatorAplicado = normalizeFator((normal + splitExtra50 * 1.5 + splitExtra100 * 2) / totalHoras);

  const selectExisting = async (): Promise<ApontamentoExistingRow[]> => {
    const result = await supabase
      .from("apontamentos_horas")
      .select("id,horas,gerado_por_hh,criado_em")
      .match(matchBase)
      .order("gerado_por_hh", { ascending: false })
      .order("criado_em", { ascending: false })
      .limit(10);

    if (!result.error) return (result.data ?? []) as ApontamentoExistingRow[];
    if (!isMissingColumnError(result.error, "gerado_por_hh")) throw new Error(formatSbError(result.error));

    const fallback = await supabase
      .from("apontamentos_horas")
      .select("id,horas,criado_em")
      .match(matchBase)
      .order("criado_em", { ascending: false })
      .limit(10);

    if (fallback.error) throw new Error(formatSbError(fallback.error));
    return (fallback.data ?? []) as ApontamentoExistingRow[];
  };

  const updatePayload = async (id: string, value: Record<string, unknown>): Promise<void> => {
    const payload = { ...value };

    for (let attempt = 0; attempt < 5; attempt += 1) {
      const result = await supabase.from("apontamentos_horas").update(payload).eq("id", id).match(matchBase);
      if (!result.error) return;

      if (isMissingColumnError(result.error, "empresa_id")) {
        delete payload.empresa_id;
        continue;
      }
      if (isMissingColumnError(result.error, "descricao")) {
        delete payload.descricao;
        continue;
      }
      if (isMissingColumnError(result.error, "gerado_por_hh")) {
        delete payload.gerado_por_hh;
        continue;
      }
      if (isMissingColumnError(result.error, "fator_aplicado")) {
        delete payload.fator_aplicado;
        continue;
      }

      throw new Error(formatSbError(result.error));
    }

    throw new Error("Nao foi possivel atualizar apontamento de horas.");
  };

  const insertPayload = async (value: Record<string, unknown>): Promise<unknown | null> => {
    const result = await supabase.from("apontamentos_horas").insert(value);
    return result.error ?? null;
  };

  const aggregatePayload: Record<string, unknown> = {
    tenant_id: tenantId,
    ...(empresaId ? { empresa_id: empresaId } : {}),
    os_id: osId,
    colaborador_id: colaboradorId,
    data: dataISO,
    horas: totalHoras,
    tipo_hora_id: tipoNormalId,
    fator_aplicado: fatorAplicado,
    gerado_por_hh: true,
    status: "lancado",
    descricao: descricao ?? null,
  };

  const existingRows = await selectExisting();
  const existing = existingRows.find((row) => row.gerado_por_hh) ?? existingRows[0] ?? null;

  if (existing?.id) {
    await updatePayload(existing.id, aggregatePayload);
    await deleteGeneratedRows(existing.id);
    return;
  }

  let insertError: unknown | null = await insertPayload(aggregatePayload);
  if (insertError && isMissingColumnError(insertError, "empresa_id")) {
    const p2 = { ...aggregatePayload };
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
    const p2 = { ...aggregatePayload };
    delete p2.descricao;
    insertError = await insertPayload(p2);
    if (insertError && isMissingColumnError(insertError, "gerado_por_hh")) {
      const p3 = { ...p2 };
      delete p3.gerado_por_hh;
      insertError = await insertPayload(p3);
    }
  } else if (insertError && isMissingColumnError(insertError, "gerado_por_hh")) {
    const p2 = { ...aggregatePayload };
    delete p2.gerado_por_hh;
    insertError = await insertPayload(p2);
  }

  if (!insertError) return;

  const rowsAfterConflict = await selectExisting();
  const rowAfterConflict = rowsAfterConflict.find((row) => row.gerado_por_hh) ?? rowsAfterConflict[0] ?? null;
  if (rowAfterConflict?.id) {
    await updatePayload(rowAfterConflict.id, aggregatePayload);
    await deleteGeneratedRows(rowAfterConflict.id);
    return;
  }

  throw new Error(formatSbError(insertError));
}
