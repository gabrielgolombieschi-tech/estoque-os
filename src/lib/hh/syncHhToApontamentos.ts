import { applyTenantEmpresa } from "@/lib/db/scopes";
import { addDaysISO, computeHHSegments } from "@/src/lib/hh/splitHoras";

export type SyncArgs = {
  supabase: any; // SupabaseClient
  tenantId: string;
  empresaId: string;
  osId: number;
  colaboradorId: string;
  dataISO: string; // YYYY-MM-DD
  periodos: Array<{ entrada?: string | null; saida?: string | null }>;
  descricao?: string | null;
  tipo?: string | null;
};

function toNull(v: string | null | undefined): string | null {
  const s = String(v ?? "").trim();
  return s ? s : null;
}

export async function syncHhToApontamentos(args: SyncArgs): Promise<void> {
  const supabase = args.supabase;
  const tenantId = String(args.tenantId);
  const empresaId = String(args.empresaId);
  const osId = Number(args.osId);
  const colaboradorId = String(args.colaboradorId);
  const dataISO = String(args.dataISO);

  const segments = computeHHSegments(dataISO, args.periodos ?? []);
  const datasAlvo = new Set(segments.map((s) => s.data));

  // Para limpeza correta, sempre considerar D e D+1.
  const datasPossiveis = [dataISO, addDaysISO(dataISO, 1)];

  const { data: existing, error: existingErr } = await applyTenantEmpresa(
    supabase
      .from("apontamentos_horas")
      .select("id,data")
      .eq("empresa_id", empresaId)
      .eq("os_id", osId)
      .eq("colaborador_id", colaboradorId)
      .eq("gerado_por_hh", true)
      .in("data", datasPossiveis),
    tenantId,
    empresaId
  );
  if (existingErr) throw existingErr;

  const existingDates = new Set(
    (existing ?? [])
      .map((r: any) => (r?.data ? String(r.data) : ""))
      .filter((d: string) => d)
  );

  if (segments.length > 0) {
    const desc = toNull(args.descricao);

    const rows = segments.map((s) => ({
      tenant_id: tenantId,
      empresa_id: empresaId,
      os_id: osId,
      colaborador_id: colaboradorId,
      data: s.data,
      horas: s.horas,
      gerado_por_hh: true,
      ...(desc !== null ? { descricao: desc } : null),
    }));

    const { error: upsertErr } = await applyTenantEmpresa(
      supabase
        .from("apontamentos_horas")
        .upsert(rows, { onConflict: "tenant_id,empresa_id,os_id,colaborador_id,data" }),
      tenantId,
      empresaId
    );
    if (upsertErr) throw upsertErr;
  }

  const datasParaDeletar = datasPossiveis.filter((d) => existingDates.has(d) && !datasAlvo.has(d));
  if (datasParaDeletar.length > 0) {
    const { error: delErr } = await applyTenantEmpresa(
      supabase
        .from("apontamentos_horas")
        .delete()
        .match({
          tenant_id: tenantId,
          empresa_id: empresaId,
          os_id: osId,
          colaborador_id: colaboradorId,
          gerado_por_hh: true,
        })
        .in("data", datasParaDeletar),
      tenantId,
      empresaId
    );
    if (delErr) throw delErr;
  }
}

