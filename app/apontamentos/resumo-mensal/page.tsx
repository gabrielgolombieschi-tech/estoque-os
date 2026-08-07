"use client";

import { Fragment, useCallback, useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { applyTenantEmpresa } from "@/lib/db/scopes";

type Colaborador = { id: string; nome: string; ativo: boolean };

type ApontamentoRow = {
  data?: string | null;
  os_id: number | null;
  colaborador_id: string;
  horas: number | null;
  horas_trabalhadas?: number | null;
};

type ResumoHhFilter = "todos" | "os_hh";
type ActiveTab = "resumo" | "extrato";

type ExtratoRow = {
  data: string;
  os_id: number | null;
  numero_os: string;
  cliente_nome: string;
  descricao_servico: string;
  total_horas: number;
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

function formatData(value: string) {
  return new Date(`${value.slice(0, 10)}T12:00:00`).toLocaleDateString("pt-BR", {
    weekday: "long",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  });
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
  const [resumoHhFilter, setResumoHhFilter] = useState<ResumoHhFilter>("todos");
  const [activeTab, setActiveTab] = useState<ActiveTab>("resumo");

  const [colaboradores, setColaboradores] = useState<Colaborador[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [rows, setRows] = useState<Array<{ colaborador_id: string; colaborador_nome: string; total_horas: number }>>(
    []
  );
  const [extratoRows, setExtratoRows] = useState<ExtratoRow[]>([]);
  const [extratoLoading, setExtratoLoading] = useState(false);
  const totalHorasResumo = useMemo(() => rows.reduce((sum, row) => sum + row.total_horas, 0), [rows]);
  const totalHorasExtrato = useMemo(
    () => extratoRows.reduce((sum, row) => sum + row.total_horas, 0),
    [extratoRows]
  );
  const extratoPorDia = useMemo(() => {
    const grouped = new Map<string, ExtratoRow[]>();
    for (const row of extratoRows) {
      const list = grouped.get(row.data) ?? [];
      list.push(row);
      grouped.set(row.data, list);
    }
    return Array.from(grouped.entries()).map(([data, lancamentos]) => ({
      data,
      lancamentos,
      total_horas: lancamentos.reduce((sum, row) => sum + row.total_horas, 0),
    }));
  }, [extratoRows]);
  const colaboradorSelecionado = useMemo(
    () => colaboradores.find((colaborador) => colaborador.id === colaboradorId) ?? null,
    [colaboradorId, colaboradores]
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
    if (!tenantId || !empresaId || activeTab !== "resumo") return;

    setLoading(true);
    setError(null);
    try {
      await ensureContext();

      const dataIni = startOfMonthISO(year, month);
      const dataFim = endOfMonthISO(year, month);

      const candidates = ["os_id,colaborador_id,horas,horas_trabalhadas", "os_id,colaborador_id,horas"];

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

      let filteredData = data;
      if (resumoHhFilter === "os_hh") {
        const osIds = Array.from(
          new Set(
            data
              .map((r) => Number(r.os_id))
              .filter((id) => Number.isFinite(id) && id > 0)
          )
        );

        if (osIds.length === 0) {
          filteredData = [];
        } else {
          const { data: osHhRows, error: osHhError } = await applyTenantEmpresa(
            supabase.from("ordens_servico").select("id").in("id", osIds).eq("usa_relatorio_hh", true),
            tenantId,
            empresaId
          );
          if (osHhError) throw osHhError;

          const osHhIds = new Set((osHhRows ?? []).map((row) => Number(row.id)).filter((id) => Number.isFinite(id)));
          filteredData = data.filter((row) => osHhIds.has(Number(row.os_id)));
        }
      }

      const nomeById = new Map(colaboradores.map((c) => [c.id, c.nome] as const));
      const totals = new Map<string, number>();
      for (const r of filteredData ?? []) {
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
  }, [activeTab, colaboradores, colaboradorId, empresaId, ensureContext, month, resumoHhFilter, supabase, tenantId, year]);

  const loadExtrato = useCallback(async () => {
    if (!tenantId || !empresaId || activeTab !== "extrato") return;
    if (!colaboradorId) {
      setExtratoRows([]);
      setError(null);
      return;
    }

    setExtratoLoading(true);
    setError(null);
    try {
      await ensureContext();

      const dataIni = startOfMonthISO(year, month);
      const dataFim = endOfMonthISO(year, month);
      const candidates = ["data,os_id,colaborador_id,horas,horas_trabalhadas", "data,os_id,colaborador_id,horas"];

      let data: ApontamentoRow[] | null = null;
      const attempts: string[] = [];

      for (const sel of candidates) {
        const res = await applyTenantEmpresa(
          supabase.from("apontamentos_horas").select(sel),
          tenantId,
          empresaId
        )
          .eq("empresa_id", empresaId)
          .eq("colaborador_id", colaboradorId)
          .gte("data", dataIni)
          .lte("data", dataFim)
          .order("data", { ascending: true })
          .order("os_id", { ascending: true });

        if (!res.error) {
          data = (res.data ?? []) as unknown as ApontamentoRow[];
          break;
        }

        attempts.push(
          `select=${sel} | status=${String(res.status)} ${String(res.statusText ?? "").trim()} | ${describeSupabaseError(res.error)}`
        );
        if (!isMissingColumnError(res.error)) break;
      }

      if (!data) {
        throw new Error(`Falha ao consultar apontamentos_horas. Tentativas: ${attempts.join(" || ") || "(sem detalhes)"}`);
      }

      const osIds = Array.from(
        new Set(data.map((row) => Number(row.os_id)).filter((id) => Number.isFinite(id) && id > 0))
      );
      const osById = new Map<
        number,
        { numero_os: string | null; cliente_nome: string | null; descricao_servico: string | null }
      >();

      if (osIds.length > 0) {
        let osQuery = applyTenantEmpresa(
          supabase
            .from("ordens_servico")
            .select("id,numero_os,cliente_nome,descricao_servico,usa_relatorio_hh")
            .in("id", osIds),
          tenantId,
          empresaId
        );
        if (resumoHhFilter === "os_hh") osQuery = osQuery.eq("usa_relatorio_hh", true);

        const { data: osData, error: osError } = await osQuery;
        if (osError) throw osError;

        for (const osRow of osData ?? []) {
          osById.set(Number(osRow.id), {
            numero_os: osRow.numero_os,
            cliente_nome: osRow.cliente_nome,
            descricao_servico: osRow.descricao_servico,
          });
        }
      }

      const totals = new Map<string, ExtratoRow>();
      for (const row of data) {
        const dataRow = String(row.data ?? "").slice(0, 10);
        if (!dataRow) continue;

        const osId = row.os_id == null ? null : Number(row.os_id);
        const osInfo = osId == null ? null : osById.get(osId);
        if (resumoHhFilter === "os_hh" && !osInfo) continue;

        const horas =
          (typeof row.horas === "number" ? row.horas : null) ??
          (typeof row.horas_trabalhadas === "number" ? row.horas_trabalhadas : null) ??
          0;
        const key = `${dataRow}|${osId ?? "sem-os"}`;
        const current = totals.get(key);

        totals.set(key, {
          data: dataRow,
          os_id: osId,
          numero_os: osInfo?.numero_os?.trim() || (osId ? String(osId) : "Sem OS"),
          cliente_nome: osInfo?.cliente_nome?.trim() || "—",
          descricao_servico: osInfo?.descricao_servico?.trim() || "—",
          total_horas: Number(((current?.total_horas ?? 0) + horas).toFixed(2)),
        });
      }

      setExtratoRows(
        Array.from(totals.values())
          .filter((row) => row.total_horas > 0)
          .sort((a, b) => a.data.localeCompare(b.data) || a.numero_os.localeCompare(b.numero_os, "pt-BR"))
      );
    } catch (e: unknown) {
      setExtratoRows([]);
      console.error("[Extrato Horas] erro ao carregar", e);
      setError(`Erro ao carregar extrato: ${describeSupabaseError(e)}`);
    } finally {
      setExtratoLoading(false);
    }
  }, [activeTab, colaboradorId, empresaId, ensureContext, month, resumoHhFilter, supabase, tenantId, year]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void loadResumo();
  }, [loadResumo]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void loadExtrato();
  }, [loadExtrato]);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold text-zinc-100">Resumo de Horas (Mês)</h1>
      </div>

      <div className="flex gap-1 border-b border-zinc-800">
        <button
          type="button"
          onClick={() => setActiveTab("resumo")}
          className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
            activeTab === "resumo"
              ? "border-emerald-400 text-emerald-300"
              : "border-transparent text-zinc-400 hover:text-zinc-200"
          }`}
        >
          Resumo
        </button>
        <button
          type="button"
          onClick={() => setActiveTab("extrato")}
          className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
            activeTab === "extrato"
              ? "border-emerald-400 text-emerald-300"
              : "border-transparent text-zinc-400 hover:text-zinc-200"
          }`}
        >
          Extrato
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
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
            <option value="">{activeTab === "extrato" ? "Selecione..." : "Todos"}</option>
            {colaboradores.map((c) => (
              <option key={c.id} value={c.id}>
                {c.nome}
              </option>
            ))}
          </select>
        </label>

        <label className="space-y-1">
          <div className="text-xs text-zinc-400">Tipo de OS</div>
          <select
            value={resumoHhFilter}
            onChange={(e) => setResumoHhFilter(e.target.value as ResumoHhFilter)}
            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
          >
            <option value="todos">Todas</option>
            <option value="os_hh">Somente OS HH</option>
          </select>
        </label>
      </div>

      {error && <div className="text-sm text-red-400">{error}</div>}

      {activeTab === "resumo" ? (
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
                    <td className="px-3 py-2 text-right text-zinc-100 tabular-nums">
                      {formatHoras(r.total_horas)}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
            {!loading && rows.length > 0 ? (
              <tfoot className="border-t border-zinc-700 bg-zinc-950/80">
                <tr>
                  <td className="px-3 py-2 text-left text-zinc-100 font-semibold">Total</td>
                  <td className="px-3 py-2 text-right text-zinc-100 font-semibold tabular-nums">
                    {formatHoras(totalHorasResumo)}
                  </td>
                </tr>
              </tfoot>
            ) : null}
          </table>
        </div>
      ) : !colaboradorId ? (
        <div className="border border-dashed border-zinc-700 rounded-lg px-4 py-10 text-center text-zinc-400">
          Selecione um colaborador para visualizar o extrato diário de horas e OS trabalhadas.
        </div>
      ) : (
        <div className="space-y-3">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div className="rounded-lg border border-zinc-800 bg-zinc-950/50 px-4 py-3 sm:col-span-1">
              <div className="text-xs text-zinc-400">Colaborador</div>
              <div className="mt-1 text-sm font-medium text-zinc-100">{colaboradorSelecionado?.nome ?? "—"}</div>
            </div>
            <div className="rounded-lg border border-zinc-800 bg-zinc-950/50 px-4 py-3">
              <div className="text-xs text-zinc-400">Dias trabalhados</div>
              <div className="mt-1 text-lg font-semibold text-zinc-100 tabular-nums">{extratoPorDia.length}</div>
            </div>
            <div className="rounded-lg border border-zinc-800 bg-zinc-950/50 px-4 py-3">
              <div className="text-xs text-zinc-400">Total no mês</div>
              <div className="mt-1 text-lg font-semibold text-emerald-300 tabular-nums">
                {formatHoras(totalHorasExtrato)} h
              </div>
            </div>
          </div>

          <div className="border border-zinc-800 rounded-lg overflow-x-auto">
            <table className="w-full min-w-[760px] text-sm">
              <thead className="bg-zinc-950/60 border-b border-zinc-800">
                <tr>
                  <th className="text-left px-3 py-2 text-zinc-200 font-medium">OS</th>
                  <th className="text-left px-3 py-2 text-zinc-200 font-medium">Cliente</th>
                  <th className="text-left px-3 py-2 text-zinc-200 font-medium">Serviço</th>
                  <th className="text-right px-3 py-2 text-zinc-200 font-medium">Horas</th>
                </tr>
              </thead>
              <tbody>
                {extratoLoading ? (
                  <tr>
                    <td className="px-3 py-3 text-zinc-400" colSpan={4}>Carregando...</td>
                  </tr>
                ) : extratoPorDia.length === 0 ? (
                  <tr>
                    <td className="px-3 py-3 text-zinc-400" colSpan={4}>
                      Nenhum apontamento encontrado para o colaborador no período.
                    </td>
                  </tr>
                ) : (
                  extratoPorDia.map((dia) => (
                    <Fragment key={dia.data}>
                      <tr className="bg-zinc-900/80">
                        <th colSpan={4} className="px-3 py-2 text-left font-semibold text-zinc-100 capitalize">
                          {formatData(dia.data)}
                        </th>
                      </tr>
                      {dia.lancamentos.map((row) => (
                        <tr key={`${row.data}-${row.os_id ?? "sem-os"}`} className="border-t border-zinc-800/70">
                          <td className="px-3 py-2 text-zinc-100 whitespace-nowrap">
                            {row.os_id ? `OS ${row.numero_os}` : "Sem OS"}
                          </td>
                          <td className="px-3 py-2 text-zinc-300">{row.cliente_nome}</td>
                          <td className="px-3 py-2 text-zinc-300">{row.descricao_servico}</td>
                          <td className="px-3 py-2 text-right text-zinc-100 tabular-nums">
                            {formatHoras(row.total_horas)}
                          </td>
                        </tr>
                      ))}
                      <tr className="border-t border-zinc-700 bg-zinc-950/60">
                        <td colSpan={3} className="px-3 py-2 text-right text-zinc-400 font-medium">Total do dia</td>
                        <td className="px-3 py-2 text-right text-zinc-100 font-semibold tabular-nums">
                          {formatHoras(dia.total_horas)}
                        </td>
                      </tr>
                    </Fragment>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
