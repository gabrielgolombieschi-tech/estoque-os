"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { applyTenantEmpresa } from "@/lib/db/scopes";

type Colaborador = { id: string; nome: string; ativo: boolean };

type ApontamentoRow = {
  colaborador_id: string;
  horas: number | null;
  horas_trabalhadas?: number | null;
};

function describeSupabaseError(err: unknown): string {
  if (!err) return "(sem detalhes)";
  if (err instanceof Error) return err.message || "(erro sem mensagem)";
  if (typeof err === "string") return err;
  if (typeof err !== "object") return String(err);

  const anyErr = err as {
    message?: unknown;
    details?: unknown;
    hint?: unknown;
    code?: unknown;
    status?: unknown;
  };

  const parts = [
    anyErr.message,
    anyErr.details,
    anyErr.hint,
    anyErr.code ? `code=${String(anyErr.code)}` : null,
    anyErr.status ? `status=${String(anyErr.status)}` : null,
  ]
    .filter((p) => (typeof p === "string" ? p.trim() !== "" : p != null))
    .map((p) => String(p));

  if (parts.length) return parts.join(" | ");
  try {
    return JSON.stringify(err);
  } catch {
    return "(erro não serializável)";
  }
}

function startOfMonthISO(year: number, month1to12: number) {
  const mm = String(month1to12).padStart(2, "0");
  return `${year}-${mm}-01`;
}

function endOfMonthISO(year: number, month1to12: number) {
  const d = new Date(year, month1to12, 0); // day 0 => last day of previous month; month1to12 is 1-based here
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

function isMissingColumnError(err: unknown): boolean {
  const message =
    err && typeof err === "object" && "message" in err ? String((err as { message?: unknown }).message ?? "") : "";
  return (
    /column\s+"?[\w\.]+"?\s+does not exist/i.test(message) ||
    /could not find the '[\w\.]+' column/i.test(message)
  );
}

const MONTHS: Array<{ value: number; label: string }> = [
  { value: 1, label: "Jan" },
  { value: 2, label: "Fev" },
  { value: 3, label: "Mar" },
  { value: 4, label: "Abr" },
  { value: 5, label: "Mai" },
  { value: 6, label: "Jun" },
  { value: 7, label: "Jul" },
  { value: 8, label: "Ago" },
  { value: 9, label: "Set" },
  { value: 10, label: "Out" },
  { value: 11, label: "Nov" },
  { value: 12, label: "Dez" },
];

function formatHoras(n: number) {
  return new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n);
}

export default function ApontamentosResumoMensalPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

  const te = useTenantEmpresa();
  const tenantId = te.tenantId;
  const empresaId = te.empresaId;

  const now = useMemo(() => new Date(), []);
  const [year, setYear] = useState<number>(now.getFullYear());
  const [month, setMonth] = useState<number>(now.getMonth() + 1);
  const [colaboradorId, setColaboradorId] = useState<string>("");

  const [colaboradores, setColaboradores] = useState<Colaborador[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [rows, setRows] = useState<Array<{ colaborador_id: string; colaborador_nome: string; total_horas: number }>>(
    []
  );

  const ensureContext = useCallback(async () => {
    if (!tenantId || !empresaId) return;
    try {
      await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
      await supabase.rpc("set_current_empresa", { p_empresa_id: empresaId });
    } catch {
      // best-effort
    }
  }, [empresaId, supabase, tenantId]);

  const years = useMemo(() => {
    const y = now.getFullYear();
    return [y - 2, y - 1, y, y + 1, y + 2];
  }, [now]);

  useEffect(() => {
    let active = true;

    const run = async () => {
      if (!tenantId || !empresaId) return;
      setError(null);
      try {
        await ensureContext();
        const { data, error: e } = await applyTenantEmpresa(
          supabase.from("colaboradores").select("id,nome,ativo").eq("ativo", true).order("nome"),
          tenantId,
          empresaId
        );
        if (e) throw e;
        if (!active) return;
        setColaboradores((data ?? []) as Colaborador[]);
      } catch (e: unknown) {
        if (!active) return;
        setError(`Erro ao carregar colaboradores: ${describeSupabaseError(e)}`);
      }
    };

    void run();
    return () => {
      active = false;
    };
  }, [empresaId, ensureContext, supabase, tenantId]);

  const loadResumo = useCallback(async () => {
    if (!tenantId || !empresaId) return;

    setLoading(true);
    setError(null);
    try {
      await ensureContext();

      const dataIni = startOfMonthISO(year, month);
      const dataFim = endOfMonthISO(year, month);

      const candidates = ["colaborador_id,horas,horas_trabalhadas", "colaborador_id,horas"];

      let data: ApontamentoRow[] | null = null;
      const attempts: string[] = [];

      for (const sel of candidates) {
        let q = applyTenantEmpresa(supabase.from("apontamentos_horas").select(sel), tenantId, empresaId)
          .eq("empresa_id", empresaId)
          .gte("data", dataIni)
          .lte("data", dataFim);

        if (colaboradorId) q = q.eq("colaborador_id", colaboradorId);

        const res = await q;
        if (!res.error) {
          data = (res.data ?? []) as unknown as ApontamentoRow[];
          break;
        }

        attempts.push(
          `select=${sel} | status=${String(res.status)} ${String(res.statusText ?? "").trim()} | ${describeSupabaseError(res.error)}`
        );

        if (!isMissingColumnError(res.error)) {
          break;
        }
      }

      if (!data) {
        throw new Error(`Falha ao consultar apontamentos_horas. Tentativas: ${attempts.join(" || ") || "(sem detalhes)"}`);
      }

      const nomeById = new Map(colaboradores.map((c) => [c.id, c.nome] as const));
      const totals = new Map<string, number>();
      for (const r of data ?? []) {
        const horas =
          (typeof r.horas === "number" ? r.horas : null) ??
          (typeof r.horas_trabalhadas === "number" ? r.horas_trabalhadas : null) ??
          0;
        if (!r.colaborador_id) continue;
        totals.set(r.colaborador_id, (totals.get(r.colaborador_id) ?? 0) + horas);
      }

      const computed = Array.from(totals.entries())
        .map(([id, total]) => ({
          colaborador_id: id,
          colaborador_nome: nomeById.get(id) ?? id,
          total_horas: Number(total.toFixed(2)),
        }))
        .filter((r) => r.total_horas > 0)
        .sort((a, b) => b.total_horas - a.total_horas);

      setRows(computed);
    } catch (e: unknown) {
      setRows([]);
      console.error("[Resumo Horas] erro ao carregar", e);
      setError(`Erro ao carregar resumo: ${describeSupabaseError(e)}`);
    } finally {
      setLoading(false);
    }
  }, [colaboradores, colaboradorId, empresaId, ensureContext, month, supabase, tenantId, year]);

  useEffect(() => {
    void loadResumo();
  }, [loadResumo]);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold text-zinc-100">Resumo de Horas (Mês)</h1>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <label className="space-y-1">
          <div className="text-xs text-zinc-400">Ano</div>
          <select
            value={String(year)}
            onChange={(e) => setYear(Number(e.target.value))}
            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
          >
            {years.map((y) => (
              <option key={y} value={String(y)}>
                {y}
              </option>
            ))}
          </select>
        </label>

        <label className="space-y-1">
          <div className="text-xs text-zinc-400">Mês</div>
          <select
            value={String(month)}
            onChange={(e) => setMonth(Number(e.target.value))}
            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
          >
            {MONTHS.map((m) => (
              <option key={m.value} value={String(m.value)}>
                {m.label}
              </option>
            ))}
          </select>
        </label>

        <label className="space-y-1">
          <div className="text-xs text-zinc-400">Colaborador</div>
          <select
            value={colaboradorId}
            onChange={(e) => setColaboradorId(e.target.value)}
            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
          >
            <option value="">Todos</option>
            {colaboradores.map((c) => (
              <option key={c.id} value={c.id}>
                {c.nome}
              </option>
            ))}
          </select>
        </label>
      </div>

      {error && <div className="text-sm text-red-400">{error}</div>}

      <div className="border border-zinc-800 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-zinc-950/60 border-b border-zinc-800">
            <tr>
              <th className="text-left px-3 py-2 text-zinc-200 font-medium">Colaborador</th>
              <th className="text-right px-3 py-2 text-zinc-200 font-medium">Total (h)</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr>
                <td className="px-3 py-3 text-zinc-400" colSpan={2}>
                  Carregando...
                </td>
              </tr>
            ) : rows.length === 0 ? (
              <tr>
                <td className="px-3 py-3 text-zinc-400" colSpan={2}>
                  Nenhum apontamento encontrado para o período.
                </td>
              </tr>
            ) : (
              rows.map((r) => (
                <tr key={r.colaborador_id} className="border-t border-zinc-800">
                  <td className="px-3 py-2 text-zinc-100">{r.colaborador_nome}</td>
                  <td className="px-3 py-2 text-right text-zinc-100 tabular-nums">{formatHoras(r.total_horas)}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
