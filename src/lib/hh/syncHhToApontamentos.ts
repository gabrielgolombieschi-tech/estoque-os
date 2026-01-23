
import { applyTenant } from "@/lib/db/scopes";

type SyncArgs = {
  supabase: any;
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
  const msg = typeof err === "object" && err && "message" in err ? String((err as any).message ?? "").toLowerCase() : "";
  if (col) return msg.includes(`column \"${col.toLowerCase()}\"`) && msg.includes("does not exist");
  return msg.includes("column") && msg.includes("does not exist");
}

function formatSbError(err: any): string {
  if (!err) return "Erro desconhecido do Supabase.";
  if (typeof err === "string") return err;
  if (typeof err === "object") {
    const parts = [err.message, err.details, err.hint].filter(Boolean);
    return parts.join(" | ");
  }
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
  let deleteError = null;
  try {
    await supabase
      .from("apontamentos_horas")
      .delete()
      .match({
        tenant_id: tenantId,
        os_id: osId,
        colaborador_id: colaboradorId,
        data: dataISO,
        gerado_por_hh: true,
      });
  } catch (e: any) {
    if (isMissingColumnError(e, "gerado_por_hh")) {
      // Fallback: remover filtro gerado_por_hh
      try {
        await supabase
          .from("apontamentos_horas")
          .delete()
          .match({
            tenant_id: tenantId,
            os_id: osId,
            colaborador_id: colaboradorId,
            data: dataISO,
          });
      } catch (e2) {
        deleteError = e2;
      }
    } else {
      deleteError = e;
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
  let payload: any = {
    tenant_id: tenantId,
    os_id: osId,
    colaborador_id: colaboradorId,
    data: dataISO,
    horas: Number(totalHoras.toFixed(2)),
    tipo_hora_id: tipoHoraId,
    gerado_por_hh: true,
    descricao: descricao ?? null,
  };
  if (empresaId) payload.empresa_id = empresaId;

  // Fallbacks para colunas opcionais
  let insertError = null;
  try {
    await supabase.from("apontamentos_horas").insert(payload);
  } catch (e: any) {
    if (isMissingColumnError(e, "empresa_id")) {
      const { empresa_id, ...p2 } = payload;
      try {
        await supabase.from("apontamentos_horas").insert(p2);
      } catch (e2: any) {
        if (isMissingColumnError(e2, "descricao")) {
          const { descricao, ...p3 } = p2;
          try {
            await supabase.from("apontamentos_horas").insert(p3);
          } catch (e3: any) {
            if (isMissingColumnError(e3, "gerado_por_hh")) {
              const { gerado_por_hh, ...p4 } = p3;
              try {
                await supabase.from("apontamentos_horas").insert(p4);
              } catch (e4) {
                insertError = e4;
              }
            } else {
              insertError = e3;
            }
          }
        } else {
          insertError = e2;
        }
      }
    } else if (isMissingColumnError(e, "descricao")) {
      const { descricao, ...p2 } = payload;
      try {
        await supabase.from("apontamentos_horas").insert(p2);
      } catch (e2: any) {
        if (isMissingColumnError(e2, "gerado_por_hh")) {
          const { gerado_por_hh, ...p3 } = p2;
          try {
            await supabase.from("apontamentos_horas").insert(p3);
          } catch (e3) {
            insertError = e3;
          }
        } else {
          insertError = e2;
        }
      }
    } else if (isMissingColumnError(e, "gerado_por_hh")) {
      const { gerado_por_hh, ...p2 } = payload;
      try {
        await supabase.from("apontamentos_horas").insert(p2);
      } catch (e2) {
        insertError = e2;
      }
    } else {
      insertError = e;
    }
  }
  if (insertError) throw new Error(formatSbError(insertError));
}

