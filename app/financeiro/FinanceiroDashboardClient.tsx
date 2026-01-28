"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { formatDecimalBR } from "@/lib/decimal";
import { applyTenantEmpresa } from "@/lib/db/scopes";

type FluxoDiarioRow = {
  data_ref: string;
  valor_previsto: number | string | null;
  valor_realizado: number | string | null;
};

type SaldoProjetadoRow = {
  data_ref: string;
  saldo_projetado: number | string | null;
};

type ApAgingResumoRow = {
  fornecedor_nome: string | null;
  motivo_codigo: string | null;
  motivo_nome: string | null;
  a_vencer: number | string | null;
  vencido_0_30: number | string | null;
  vencido_31_60: number | string | null;
  vencido_61_90: number | string | null;
  vencido_90_mais: number | string | null;
  total_aberto: number | string | null;
};

type ApAgingDetalheRow = {
  fornecedor_nome: string | null;
  motivo_codigo: string | null;
  motivo_nome: string | null;
  vencimento_date: string | null;
  dias_atraso: number | string | null;
  valor_aberto: number | string | null;
  valor_parcela: number | string | null;
  status: string | null;
  competencia_date: string | null;
};

type SemMotivoRow = {
  fornecedor_nome: string | null;
  qtd_titulos_sem_motivo: number | string | null;
  total_aberto: number | string | null;
};

type SugestaoConciliacaoApRow = {
  extrato_linha_id: string | null;
  data_movimento: string | null;
  valor_extrato: number | string | null;
  descricao: string | null;
  pagamento_id: string | null;
  data_pagamento: string | null;
  forma_pagamento: string | null;
  valor_pagamento: number | string | null;
  diferenca_valor: number | string | null;
};

function n(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

function toISODate(d: Date): string {
  // Use local date parts (not UTC) to avoid day shifts.
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

function formatDateBR(iso?: string | null): string {
  if (!iso) return "";
  const d = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleDateString("pt-BR");
}

function StatCard({ title, value, subtitle }: { title: string; value: string; subtitle?: string }) {
  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
      <div className="text-xs text-zinc-400">{title}</div>
      <div className="mt-2 text-2xl font-semibold text-zinc-100 tabular-nums">{value}</div>
      {subtitle ? <div className="mt-1 text-xs text-zinc-500">{subtitle}</div> : null}
    </div>
  );
}

const BAR_HEIGHT_CLASSES = [
  "h-1",
  "h-2",
  "h-3",
  "h-4",
  "h-5",
  "h-6",
  "h-7",
  "h-8",
  "h-9",
  "h-10",
  "h-11",
  "h-12",
  "h-13",
  "h-14",
  "h-15",
  "h-16",
] as const;

function SimpleBars({
  series,
}: {
  series: { label: string; value: number; kind: "in" | "out" | "net" }[];
}) {
  const maxAbs = useMemo(() => {
    let m = 0;
    for (const s of series) m = Math.max(m, Math.abs(s.value));
    return m || 1;
  }, [series]);

  const barClass = (kind: "in" | "out" | "net") => {
    if (kind === "in") return "bg-emerald-500/70";
    if (kind === "out") return "bg-rose-500/70";
    return "bg-sky-500/70";
  };

  return (
    <div className="flex items-end gap-1 h-16" aria-hidden>
      {series.map((s, idx) => {
        const normalized = Math.abs(s.value) / maxAbs;
        const steps = Math.max(1, Math.min(16, Math.round(normalized * 16)));
        const hClass = BAR_HEIGHT_CLASSES[steps - 1] ?? "h-1";
        return (
          <div key={`${s.label}-${idx}`} className="flex-1">
            <div
              className={`w-full rounded-sm ${barClass(s.kind)} ${hClass}`}
              title={`${s.label}: ${formatDecimalBR(s.value, 2)}`}
            />
          </div>
        );
      })}
    </div>
  );
}

export default function FinanceiroDashboardClient() {
  const te = useTenantEmpresa();
  const router = useRouter();

  // Horizon for cashflow/saldo: last 15 days + next 45 days
  const [range, setRange] = useState(() => {
    const now = new Date();
    const start = new Date(now);
    start.setDate(start.getDate() - 15);
    const end = new Date(now);
    end.setDate(end.getDate() + 45);
    return { start: toISODate(start), end: toISODate(end) };
  });

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [fluxo, setFluxo] = useState<FluxoDiarioRow[]>([]);
  const [saldo, setSaldo] = useState<SaldoProjetadoRow[]>([]);
  const [agingResumo, setAgingResumo] = useState<ApAgingResumoRow[]>([]);
  const [agingDetalhe, setAgingDetalhe] = useState<ApAgingDetalheRow[]>([]);
  const [semMotivo, setSemMotivo] = useState<SemMotivoRow[]>([]);
  const [sugestoesConciliacao, setSugestoesConciliacao] = useState<SugestaoConciliacaoApRow[]>([]);
  const warnedMissingContextRef = useRef(false);

  const canFinanceiro = useMemo(() => {
    const r = te.has("financeiro.read");
    const w = te.has("financeiro.write");
    if (r === undefined || w === undefined) return undefined;
    return Boolean(r || w);
  }, [te]);

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  useEffect(() => {
    // Wait until auth + tenant + empresa are ready (AppShell already blocks rendering earlier).
    if (typeof te.sessionUserId !== "string") return;

    const tenantId = te.tenantId ?? null;
    const empresaId = te.empresaId ?? (te.empresas.length === 1 ? te.empresas[0]?.id : null);
    if (!tenantId || !empresaId) {
      if (process.env.NODE_ENV !== "production" && !warnedMissingContextRef.current) {
        console.debug("[financeiro] Contexto ausente ao carregar dashboard", {
          tenantId,
          empresaId: te.empresaId ?? null,
          empresasCount: te.empresas.length,
        });
        warnedMissingContextRef.current = true;
      }
      return;
    }
    warnedMissingContextRef.current = false;

    if (canFinanceiro !== true) return;

    let cancelled = false;

    const run = async () => {
      setLoading(true);
      setError(null);

      const supabase = getSupabaseBrowser();

      const safe = async <T,>(
        fn: () => PromiseLike<{ data: T | null; error: unknown }>,
        fallback: T
      ): Promise<T> => {
        try {
          const { data, error } = await fn();
          if (error) throw error;
          return (data ?? fallback) as T;
        } catch {
          return fallback;
        }
      };

      try {
        const [fluxoRows, saldoRows, resumoRows, detalheRows, semMotivoRows, sugestoesRows] = await Promise.all([
          safe(
            () =>
              applyTenantEmpresa(
                supabase.schema("f").from("r_fluxo_caixa_diario").select("data_ref,valor_previsto,valor_realizado"),
                tenantId,
                empresaId
              )
                .eq("empresa_id", empresaId)
                .gte("data_ref", range.start)
                .lte("data_ref", range.end)
                .order("data_ref", { ascending: true }),
            [] as FluxoDiarioRow[]
          ),
          safe(
            () =>
              applyTenantEmpresa(
                supabase.schema("f").from("r_saldo_projetado_diario_com_saldo_inicial").select("data_ref,saldo_projetado"),
                tenantId,
                empresaId
              )
                .eq("empresa_id", empresaId)
                .gte("data_ref", range.start)
                .lte("data_ref", range.end)
                .order("data_ref", { ascending: true }),
            [] as SaldoProjetadoRow[]
          ),
          safe(
            () =>
              applyTenantEmpresa(
                supabase
                  .schema("f")
                  .from("r_ap_aging_resumo")
                  .select(
                    "fornecedor_nome,motivo_codigo,motivo_nome,a_vencer,vencido_0_30,vencido_31_60,vencido_61_90,vencido_90_mais,total_aberto"
                  ),
                tenantId,
                empresaId
              )
                .eq("empresa_id", empresaId)
                .order("total_aberto", { ascending: false })
                .limit(12),
            [] as ApAgingResumoRow[]
          ),
          safe(
            () =>
              applyTenantEmpresa(
                supabase
                  .schema("f")
                  .from("r_ap_aging_detalhe")
                  .select(
                    "fornecedor_nome,motivo_codigo,motivo_nome,vencimento_date,dias_atraso,valor_parcela,valor_aberto,status,competencia_date"
                  ),
                tenantId,
                empresaId
              )
                .eq("empresa_id", empresaId)
                .order("dias_atraso", { ascending: false })
                .limit(12),
            [] as ApAgingDetalheRow[]
          ),
          safe(
            () =>
              applyTenantEmpresa(
                supabase
                  .schema("f")
                  .from("r_titulos_sem_motivo_por_fornecedor")
                  .select("fornecedor_nome,qtd_titulos_sem_motivo,total_aberto"),
                tenantId,
                empresaId
              )
                .eq("empresa_id", empresaId)
                .order("total_aberto", { ascending: false })
                .limit(8),
            [] as SemMotivoRow[]
          ),
          safe(
            () =>
              applyTenantEmpresa(
                supabase
                  .schema("f")
                  .from("r_sugestoes_conciliacao_ap")
                  .select(
                    "extrato_linha_id,data_movimento,valor_extrato,descricao,pagamento_id,data_pagamento,forma_pagamento,valor_pagamento,diferenca_valor"
                  ),
                tenantId,
                empresaId
              )
                .eq("empresa_id", empresaId)
                .order("diferenca_valor", { ascending: true })
                .limit(8),
            [] as SugestaoConciliacaoApRow[]
          ),
        ]);

        if (cancelled) return;
        setFluxo((fluxoRows ?? []) as FluxoDiarioRow[]);
        setSaldo((saldoRows ?? []) as SaldoProjetadoRow[]);
        setAgingResumo((resumoRows ?? []) as ApAgingResumoRow[]);
        setAgingDetalhe((detalheRows ?? []) as ApAgingDetalheRow[]);
        setSemMotivo((semMotivoRows ?? []) as SemMotivoRow[]);
        setSugestoesConciliacao((sugestoesRows ?? []) as SugestaoConciliacaoApRow[]);
      } catch (e: unknown) {
        if (cancelled) return;
        setError(e instanceof Error ? e.message : "Erro ao carregar dashboard.");
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    void run();

    return () => {
      cancelled = true;
    };
  }, [canFinanceiro, range.end, range.start, te.empresas, te.empresaId, te.sessionUserId, te.tenantId]);

  const fluxoPorDia = useMemo(() => {
    const map = new Map<string, { previsto: number; realizado: number }>();
    for (const r of fluxo) {
      const key = String(r.data_ref);
      const cur = map.get(key) ?? { previsto: 0, realizado: 0 };
      cur.previsto += n(r.valor_previsto);
      cur.realizado += n(r.valor_realizado);
      map.set(key, cur);
    }
    return Array.from(map.entries())
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([date, v]) => ({ date, ...v }));
  }, [fluxo]);

  const saldoPorDia = useMemo(() => {
    const map = new Map<string, number>();
    for (const r of saldo) {
      const key = String(r.data_ref);
      map.set(key, (map.get(key) ?? 0) + n(r.saldo_projetado));
    }
    return Array.from(map.entries())
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([date, total]) => ({ date, total }));
  }, [saldo]);

  const todayIso = useMemo(() => toISODate(new Date()), []);

  const resumo = useMemo(() => {
    const hojeSaldo = saldoPorDia.find((x) => x.date === todayIso)?.total ?? null;

    let previsto7 = 0;
    let realizado7 = 0;
    const now = new Date(`${todayIso}T00:00:00`);
    const d7 = new Date(now);
    d7.setDate(d7.getDate() + 7);
    const iso7 = toISODate(d7);

    for (const x of fluxoPorDia) {
      if (x.date >= todayIso && x.date <= iso7) {
        previsto7 += x.previsto;
        realizado7 += x.realizado;
      }
    }

    const agingTotals = agingResumo.reduce(
      (acc, r) => {
        acc.aVencer += n(r.a_vencer);
        acc.v0_30 += n(r.vencido_0_30);
        acc.v31_60 += n(r.vencido_31_60);
        acc.v61_90 += n(r.vencido_61_90);
        acc.v90Mais += n(r.vencido_90_mais);
        acc.total += n(r.total_aberto);
        return acc;
      },
      { aVencer: 0, v0_30: 0, v31_60: 0, v61_90: 0, v90Mais: 0, total: 0 }
    );

    const semMotivoTotal = semMotivo.reduce((acc, r) => acc + n(r.total_aberto), 0);

    return {
      hojeSaldo,
      previsto7,
      realizado7,
      apTotalAberto: agingTotals.total,
      apVencido: agingTotals.v0_30 + agingTotals.v31_60 + agingTotals.v61_90 + agingTotals.v90Mais,
      apAVencer: agingTotals.aVencer,
      semMotivoTotal,
      sugestoesCount: sugestoesConciliacao.length,
    };
  }, [agingResumo, fluxoPorDia, saldoPorDia, semMotivo, sugestoesConciliacao.length, todayIso]);

  const chartSeries = useMemo(() => {
    // pick last 30 points from range to keep chart readable
    const last = fluxoPorDia.slice(-30);
    return last.map((d) => ({
      label: d.date.slice(5),
      value: d.realizado - d.previsto,
      kind: "net" as const,
    }));
  }, [fluxoPorDia]);

  const agingBucketTotals = useMemo(() => {
    const totals = agingResumo.reduce(
      (acc, r) => {
        acc.aVencer += n(r.a_vencer);
        acc.v0_30 += n(r.vencido_0_30);
        acc.v31_60 += n(r.vencido_31_60);
        acc.v61_90 += n(r.vencido_61_90);
        acc.v90Mais += n(r.vencido_90_mais);
        acc.total += n(r.total_aberto);
        return acc;
      },
      { aVencer: 0, v0_30: 0, v31_60: 0, v61_90: 0, v90Mais: 0, total: 0 }
    );
    return totals;
  }, [agingResumo]);

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold">Dashboard Financeiro</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Visão operacional (caixa, AP, conciliação e pendências). Ideal para rotina do Lucro Real: disciplina de
            competência, classificação e conciliação.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <div className="text-xs text-zinc-400">Período</div>
          <input
            type="date"
            value={range.start}
            onChange={(e) => setRange((prev) => ({ ...prev, start: e.target.value }))}
            aria-label="Data inicial"
            title="Data inicial"
            className="rounded-md border border-zinc-800 bg-zinc-950 px-2 py-1 text-sm"
          />
          <span className="text-zinc-600 text-sm">→</span>
          <input
            type="date"
            value={range.end}
            onChange={(e) => setRange((prev) => ({ ...prev, end: e.target.value }))}
            aria-label="Data final"
            title="Data final"
            className="rounded-md border border-zinc-800 bg-zinc-950 px-2 py-1 text-sm"
          />
        </div>
      </div>

      {error ? (
        <div className="rounded-xl border border-rose-900/50 bg-rose-950/20 p-4 text-rose-200 text-sm">
          {error}
        </div>
      ) : null}

      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-3">
        <StatCard
          title="Saldo projetado (hoje)"
          value={resumo.hojeSaldo === null ? "—" : `R$ ${formatDecimalBR(resumo.hojeSaldo, 2)}`}
          subtitle="Soma de contas bancárias (contexto atual)"
        />
        <StatCard
          title="AP vencido (aberto)"
          value={`R$ ${formatDecimalBR(resumo.apVencido, 2)}`}
          subtitle="0–30, 31–60, 61–90, 90+"
        />
        <StatCard
          title="AP a vencer"
          value={`R$ ${formatDecimalBR(resumo.apAVencer, 2)}`}
          subtitle="Parcelas em aberto com vencimento futuro"
        />
        <StatCard
          title="Pendências de classificação"
          value={`R$ ${formatDecimalBR(resumo.semMotivoTotal, 2)}`}
          subtitle="Títulos sem motivo de compra (aberto)"
        />
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <div className="xl:col-span-2 rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="flex items-center justify-between gap-3">
            <div>
              <div className="text-sm font-semibold">Fluxo de caixa (delta realizado − previsto)</div>
              <div className="text-xs text-zinc-500 mt-1">Últimos 30 pontos dentro do período selecionado</div>
            </div>
            <div className="flex items-center gap-2 text-sm">
              <Link href="/financeiro/relatorios/fluxo-caixa/diario" className="text-zinc-200 hover:text-white">
                Ver relatório
              </Link>
            </div>
          </div>

          <div className="mt-4">
            <SimpleBars series={chartSeries} />
            <div className="mt-2 flex items-center justify-between text-xs text-zinc-500">
              <div>{formatDateBR(fluxoPorDia.at(-30)?.date ?? null)}</div>
              <div>{formatDateBR(fluxoPorDia.at(-1)?.date ?? null)}</div>
            </div>
          </div>

          <div className="mt-4 grid grid-cols-1 md:grid-cols-3 gap-3">
            <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
              <div className="text-xs text-zinc-500">Previsto (próx. 7 dias)</div>
              <div className="mt-1 text-lg font-semibold">R$ {formatDecimalBR(resumo.previsto7, 2)}</div>
            </div>
            <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
              <div className="text-xs text-zinc-500">Realizado (próx. 7 dias)</div>
              <div className="mt-1 text-lg font-semibold">R$ {formatDecimalBR(resumo.realizado7, 2)}</div>
            </div>
            <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
              <div className="text-xs text-zinc-500">Sugestões conciliação (AP)</div>
              <div className="mt-1 text-lg font-semibold">{resumo.sugestoesCount}</div>
            </div>
          </div>
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold">Atalhos</div>
          <div className="mt-3 grid grid-cols-1 gap-2 text-sm">
            <Link href="/financeiro/contas-pagar/lancamentos" className="rounded-md border border-zinc-800 bg-zinc-950 p-3 hover:bg-zinc-900">
              Contas a Pagar → Lançamentos
            </Link>
            <Link href="/financeiro/contas-pagar/aprovacoes" className="rounded-md border border-zinc-800 bg-zinc-950 p-3 hover:bg-zinc-900">
              Contas a Pagar → Aprovações
            </Link>
            <Link href="/financeiro/extratos" className="rounded-md border border-zinc-800 bg-zinc-950 p-3 hover:bg-zinc-900">
              Extratos bancários
            </Link>
            <Link href="/financeiro/conciliacao" className="rounded-md border border-zinc-800 bg-zinc-950 p-3 hover:bg-zinc-900">
              Conciliação bancária
            </Link>
            <Link href="/financeiro/configuracoes" className="rounded-md border border-zinc-800 bg-zinc-950 p-3 hover:bg-zinc-900">
              Configurações
            </Link>
          </div>

          <div className="mt-4 text-xs text-zinc-500">
            {loading ? "Carregando dados…" : "Dados carregados."}
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-sm font-semibold">Contas a pagar — Aging (resumo)</div>
              <div className="text-xs text-zinc-500 mt-1">Buckets por vencimento (aberto)</div>
            </div>
            <div className="text-xs text-zinc-500">Total: R$ {formatDecimalBR(agingBucketTotals.total, 2)}</div>
          </div>

          <div className="mt-3 grid grid-cols-2 md:grid-cols-5 gap-2 text-xs">
            <div className="rounded-md border border-zinc-800 p-2">
              <div className="text-zinc-500">A vencer</div>
              <div className="mt-1 font-semibold">R$ {formatDecimalBR(agingBucketTotals.aVencer, 2)}</div>
            </div>
            <div className="rounded-md border border-zinc-800 p-2">
              <div className="text-zinc-500">0–30</div>
              <div className="mt-1 font-semibold">R$ {formatDecimalBR(agingBucketTotals.v0_30, 2)}</div>
            </div>
            <div className="rounded-md border border-zinc-800 p-2">
              <div className="text-zinc-500">31–60</div>
              <div className="mt-1 font-semibold">R$ {formatDecimalBR(agingBucketTotals.v31_60, 2)}</div>
            </div>
            <div className="rounded-md border border-zinc-800 p-2">
              <div className="text-zinc-500">61–90</div>
              <div className="mt-1 font-semibold">R$ {formatDecimalBR(agingBucketTotals.v61_90, 2)}</div>
            </div>
            <div className="rounded-md border border-zinc-800 p-2">
              <div className="text-zinc-500">90+</div>
              <div className="mt-1 font-semibold">R$ {formatDecimalBR(agingBucketTotals.v90Mais, 2)}</div>
            </div>
          </div>

          <div className="mt-4 overflow-auto">
            <table className="w-full text-sm">
              <thead className="text-xs text-zinc-400">
                <tr className="border-b border-zinc-800">
                  <th className="py-2 text-left font-medium">Fornecedor</th>
                  <th className="py-2 text-left font-medium">Motivo</th>
                  <th className="py-2 text-right font-medium">Total aberto</th>
                </tr>
              </thead>
              <tbody>
                {(agingResumo ?? []).map((r, idx) => (
                  <tr key={idx} className="border-b border-zinc-900/70">
                    <td className="py-2 pr-2">{r.fornecedor_nome ?? "—"}</td>
                    <td className="py-2 pr-2 text-zinc-300">
                      {r.motivo_codigo ? `${r.motivo_codigo} — ${r.motivo_nome ?? ""}` : r.motivo_nome ?? "—"}
                    </td>
                    <td className="py-2 text-right tabular-nums">R$ {formatDecimalBR(n(r.total_aberto), 2)}</td>
                  </tr>
                ))}
                {!agingResumo.length ? (
                  <tr>
                    <td colSpan={3} className="py-4 text-center text-zinc-500 text-sm">
                      Sem dados de aging (ou sem AP em aberto).
                    </td>
                  </tr>
                ) : null}
              </tbody>
            </table>
          </div>
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold">Prioridades de rotina</div>
          <div className="text-xs text-zinc-500 mt-1">O que costuma “quebrar” Lucro Real na prática</div>

          <div className="mt-4 grid grid-cols-1 gap-3">
            <div className="rounded-lg border border-zinc-800 p-3">
              <div className="text-xs text-zinc-400">Títulos sem motivo (classificação pendente)</div>
              <div className="mt-2 space-y-2 text-sm">
                {semMotivo.map((r, idx) => (
                  <div key={idx} className="flex items-center justify-between gap-3">
                    <div className="truncate">{r.fornecedor_nome ?? "—"}</div>
                    <div className="tabular-nums text-zinc-200">R$ {formatDecimalBR(n(r.total_aberto), 2)}</div>
                  </div>
                ))}
                {!semMotivo.length ? <div className="text-zinc-500">Nenhuma pendência.</div> : null}
              </div>
            </div>

            <div className="rounded-lg border border-zinc-800 p-3">
              <div className="text-xs text-zinc-400">Aging detalhe (maiores atrasos)</div>
              <div className="mt-2 space-y-2 text-sm">
                {agingDetalhe.map((r, idx) => (
                  <div key={idx} className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <div className="truncate text-zinc-200">{r.fornecedor_nome ?? "—"}</div>
                      <div className="text-xs text-zinc-500">
                        Venc.: {formatDateBR(r.vencimento_date)} · Atraso: {n(r.dias_atraso)} dia(s)
                      </div>
                    </div>
                    <div className="tabular-nums text-zinc-200 whitespace-nowrap">R$ {formatDecimalBR(n(r.valor_aberto), 2)}</div>
                  </div>
                ))}
                {!agingDetalhe.length ? <div className="text-zinc-500">Sem parcelas vencidas.</div> : null}
              </div>
            </div>

            <div className="rounded-lg border border-zinc-800 p-3">
              <div className="flex items-center justify-between">
                <div className="text-xs text-zinc-400">Sugestões de conciliação (AP)</div>
                <Link href="/financeiro/conciliacao" className="text-xs text-zinc-300 hover:text-white">
                  Abrir conciliação
                </Link>
              </div>
              <div className="mt-2 space-y-2 text-sm">
                {sugestoesConciliacao.map((r, idx) => (
                  <div key={idx} className="rounded-md border border-zinc-900 p-2">
                    <div className="flex items-center justify-between gap-3">
                      <div className="text-zinc-200 truncate">{r.descricao ?? "Movimento"}</div>
                      <div className="tabular-nums text-zinc-200 whitespace-nowrap">
                        R$ {formatDecimalBR(Math.abs(n(r.valor_extrato)), 2)}
                      </div>
                    </div>
                    <div className="mt-1 text-xs text-zinc-500">
                      Extrato: {formatDateBR(r.data_movimento)} · Pagto: {formatDateBR(r.data_pagamento)} · Dif: R${" "}
                      {formatDecimalBR(n(r.diferenca_valor), 2)}
                    </div>
                  </div>
                ))}
                {!sugestoesConciliacao.length ? <div className="text-zinc-500">Sem sugestões no momento.</div> : null}
              </div>
            </div>
          </div>
        </div>
      </div>

      <div className="text-xs text-zinc-600">
        Dica: para Lucro Real, mantenha competência correta + classificação (motivo/plano/centro) + conciliação bancária
        em dia. Esse dashboard foi desenhado para evidenciar exatamente essas “travadas”.
      </div>
    </div>
  );
}
