"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { downloadCsv, formatDateBR, formatMoney, n } from "../relatoriosShared";

type ResumoRow = {
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

type DetalheRow = {
  fornecedor_nome: string | null;
  motivo_codigo: string | null;
  motivo_nome: string | null;
  vencimento_date: string | null;
  dias_atraso: number | string | null;
  valor_aberto: number | string | null;
  valor_parcela: number | string | null;
  status: string | null;
  competencia_date: string | null;
  titulo_id?: string | null;
  parcela_id?: string | null;
  descricao?: string | null;
};

function Stat({ title, value, subtitle }: { title: string; value: string; subtitle?: string }) {
  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
      <div className="text-xs text-zinc-400">{title}</div>
      <div className="mt-2 text-2xl font-semibold text-zinc-100 tabular-nums">{value}</div>
      {subtitle ? <div className="mt-1 text-xs text-zinc-500">{subtitle}</div> : null}
    </div>
  );
}

function cleanUpper(s: string) {
  return s.trim().toUpperCase();
}

export default function ApAgingClient() {
  const te = useTenantEmpresa();
  const router = useRouter();

  const [q, setQ] = useState<string>("");
  const [onlyOverdue, setOnlyOverdue] = useState(false);
  const [minTotal, setMinTotal] = useState<string>("");
  const [limitResumo, setLimitResumo] = useState(25);

  const [startDue, setStartDue] = useState<string>("");
  const [endDue, setEndDue] = useState<string>("");

  const [selected, setSelected] = useState<{ fornecedor: string | null; motivo: string | null } | null>(null);

  const [resumo, setResumo] = useState<ResumoRow[]>([]);
  const [detalhe, setDetalhe] = useState<DetalheRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [detalheLoading, setDetalheLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const canFinanceiro = useMemo(() => {
    const r = te.has("financeiro.read");
    const w = te.has("financeiro.write");
    if (r === undefined || w === undefined) return undefined;
    return Boolean(r || w);
  }, [te]);

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  const ready =
    typeof te.sessionUserId === "string" &&
    Boolean(te.tenantId) &&
    (Boolean(te.empresaId) || te.empresas.length === 1) &&
    canFinanceiro === true;

  useEffect(() => {
    if (!ready) return;

    let cancelled = false;

    const run = async () => {
      setLoading(true);
      setError(null);

      try {
        const supabase = getSupabaseBrowser();

        let query = supabase
          .schema("f")
          .from("r_ap_aging_resumo")
          .select(
            "fornecedor_nome,motivo_codigo,motivo_nome,a_vencer,vencido_0_30,vencido_31_60,vencido_61_90,vencido_90_mais,total_aberto"
          )
          .order("total_aberto", { ascending: false })
          .limit(Math.max(5, Math.min(100, limitResumo)));

        const term = q.trim();
        if (term) {
          query = query.or([`fornecedor_nome.ilike.%${term}%`, `motivo_nome.ilike.%${term}%`, `motivo_codigo.ilike.%${term}%`].join(","));
        }

        const { data, error: qErr } = await query;
        if (cancelled) return;
        if (qErr) throw qErr;

        const rows = ((data ?? []) as unknown) as ResumoRow[];

        const min = Number(minTotal.replace(",", "."));
        const filtered = Number.isFinite(min)
          ? rows.filter((r) => Math.abs(n(r.total_aberto)) >= min)
          : rows;

        setResumo(filtered);

        // Default selection: first row (for drilldown).
        if (!selected && filtered.length) {
          setSelected({ fornecedor: filtered[0].fornecedor_nome ?? null, motivo: filtered[0].motivo_codigo ?? null });
        }
      } catch (e: unknown) {
        if (cancelled) return;
        setResumo([]);
        setError(e instanceof Error ? e.message : "Erro ao carregar aging AP.");
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [limitResumo, minTotal, q, ready, selected]);

  useEffect(() => {
    if (!ready) return;
    if (!selected) return;

    let cancelled = false;

    const run = async () => {
      setDetalheLoading(true);
      setError(null);

      try {
        const supabase = getSupabaseBrowser();

        let query = supabase
          .schema("f")
          .from("r_ap_aging_detalhe")
          .select(
            "fornecedor_nome,motivo_codigo,motivo_nome,vencimento_date,dias_atraso,valor_parcela,valor_aberto,status,competencia_date"
          )
          .order("dias_atraso", { ascending: false })
          .limit(500);

        if (selected.fornecedor) query = query.eq("fornecedor_nome", selected.fornecedor);
        if (selected.motivo) query = query.eq("motivo_codigo", selected.motivo);

        if (onlyOverdue) query = query.gte("dias_atraso", 0);
        if (startDue) query = query.gte("vencimento_date", startDue);
        if (endDue) query = query.lte("vencimento_date", endDue);

        const { data, error: qErr } = await query;
        if (cancelled) return;
        if (qErr) throw qErr;

        setDetalhe(((data ?? []) as unknown) as DetalheRow[]);
      } catch (e: unknown) {
        if (cancelled) return;
        setDetalhe([]);
        setError(e instanceof Error ? e.message : "Erro ao carregar detalhes do aging AP.");
      } finally {
        if (!cancelled) setDetalheLoading(false);
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [endDue, onlyOverdue, ready, selected, startDue]);

  const totals = useMemo(() => {
    const sum = resumo.reduce(
      (acc, r) => {
        acc.a_vencer += n(r.a_vencer);
        acc.v0 += n(r.vencido_0_30);
        acc.v31 += n(r.vencido_31_60);
        acc.v61 += n(r.vencido_61_90);
        acc.v90 += n(r.vencido_90_mais);
        acc.total += n(r.total_aberto);
        return acc;
      },
      { a_vencer: 0, v0: 0, v31: 0, v61: 0, v90: 0, total: 0 }
    );
    return sum;
  }, [resumo]);

  const exportResumo = () => {
    const header = [
      "fornecedor",
      "motivo_codigo",
      "motivo",
      "a_vencer",
      "vencido_0_30",
      "vencido_31_60",
      "vencido_61_90",
      "vencido_90_mais",
      "total_aberto",
    ];

    const rows = resumo.map((r) => [
      r.fornecedor_nome ?? "",
      r.motivo_codigo ?? "",
      r.motivo_nome ?? "",
      String(n(r.a_vencer)),
      String(n(r.vencido_0_30)),
      String(n(r.vencido_31_60)),
      String(n(r.vencido_61_90)),
      String(n(r.vencido_90_mais)),
      String(n(r.total_aberto)),
    ]);

    downloadCsv(`aging_ap_resumo.csv`, header, rows);
  };

  const exportDetalhe = () => {
    const header = [
      "fornecedor",
      "motivo_codigo",
      "motivo",
      "vencimento",
      "dias_atraso",
      "valor_parcela",
      "valor_aberto",
      "status",
      "competencia",
    ];

    const rows = detalhe.map((r) => [
      r.fornecedor_nome ?? "",
      r.motivo_codigo ?? "",
      r.motivo_nome ?? "",
      r.vencimento_date ?? "",
      String(n(r.dias_atraso)),
      String(n(r.valor_parcela)),
      String(n(r.valor_aberto)),
      r.status ?? "",
      r.competencia_date ?? "",
    ]);

    downloadCsv(`aging_ap_detalhe.csv`, header, rows);
  };

  if (canFinanceiro !== true) return null;

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Aging — Contas a Pagar (AP)</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Visão de risco de vencimento (base: parcelas em aberto). Alinhado ao Lucro Real: competência ≠ caixa.
          </p>
        </div>
        <div className="flex gap-2">
          <Link href="/financeiro" className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm">
            Voltar
          </Link>
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <div className="grid grid-cols-1 md:grid-cols-5 gap-3 items-end">
          <div className="md:col-span-2">
            <label className="text-xs text-zinc-400" htmlFor="ap-q">
              Buscar (fornecedor/motivo)
            </label>
            <input
              id="ap-q"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Ex: ACME, NAO_CLASSIFICADO, combustivel…"
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            />
          </div>

          <div>
            <label className="text-xs text-zinc-400" htmlFor="ap-min">
              Mín. total (opcional)
            </label>
            <input
              id="ap-min"
              value={minTotal}
              onChange={(e) => setMinTotal(e.target.value)}
              placeholder="0,00"
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            />
          </div>

          <div>
            <label className="text-xs text-zinc-400" htmlFor="ap-limit">
              Top N
            </label>
            <select
              id="ap-limit"
              value={String(limitResumo)}
              onChange={(e) => setLimitResumo(Number(e.target.value))}
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            >
              {[10, 25, 50, 100].map((n) => (
                <option key={n} value={String(n)}>
                  {n}
                </option>
              ))}
            </select>
          </div>

          <div className="flex items-center gap-2">
            <input
              id="ap-overdue"
              type="checkbox"
              checked={onlyOverdue}
              onChange={(e) => setOnlyOverdue(e.target.checked)}
              className="h-4 w-4"
            />
            <label htmlFor="ap-overdue" className="text-sm text-zinc-200 select-none">
              Só vencidas
            </label>
          </div>
        </div>

        <div className="mt-3 flex flex-wrap items-end gap-3">
          <div>
            <label className="text-xs text-zinc-400" htmlFor="ap-start">
              Vencimento (de)
            </label>
            <input
              id="ap-start"
              type="date"
              value={startDue}
              onChange={(e) => setStartDue(e.target.value)}
              className="mt-1 rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label className="text-xs text-zinc-400" htmlFor="ap-end">
              Vencimento (até)
            </label>
            <input
              id="ap-end"
              type="date"
              value={endDue}
              onChange={(e) => setEndDue(e.target.value)}
              className="mt-1 rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            />
          </div>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={exportResumo}
              className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
            >
              Exportar resumo
            </button>
            <button
              type="button"
              onClick={exportDetalhe}
              className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
            >
              Exportar detalhes
            </button>
          </div>
        </div>

        {error ? <div className="mt-3 text-sm text-red-400">{error}</div> : null}
        {loading ? <div className="mt-3 text-sm text-zinc-400">Carregando…</div> : null}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <Stat title="Total em aberto" value={formatMoney(totals.total)} />
        <Stat title="A vencer" value={formatMoney(totals.a_vencer)} />
        <Stat title="Vencidas (0+ dias)" value={formatMoney(totals.v0 + totals.v31 + totals.v61 + totals.v90)} />
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
        <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
          <div className="text-sm font-semibold text-zinc-100">Resumo (por fornecedor x motivo)</div>
          <div className="text-xs text-zinc-500">{resumo.length} linhas</div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/60 text-zinc-300">
              <tr>
                <th className="text-left px-4 py-2 font-medium">Fornecedor</th>
                <th className="text-left px-4 py-2 font-medium">Motivo</th>
                <th className="text-right px-4 py-2 font-medium">A vencer</th>
                <th className="text-right px-4 py-2 font-medium">Venc. 0–30</th>
                <th className="text-right px-4 py-2 font-medium">Venc. 31–60</th>
                <th className="text-right px-4 py-2 font-medium">Venc. 61–90</th>
                <th className="text-right px-4 py-2 font-medium">Venc. 90+</th>
                <th className="text-right px-4 py-2 font-medium">Total</th>
              </tr>
            </thead>
            <tbody>
              {resumo.map((r, idx) => {
                const motivo = [r.motivo_codigo, r.motivo_nome].filter(Boolean).join(" - ") || "—";
                const fornecedor = r.fornecedor_nome ?? "—";

                const isSelected =
                  Boolean(selected) && selected?.fornecedor === fornecedor && selected?.motivo === (r.motivo_codigo ?? null);

                return (
                  <tr
                    key={`${fornecedor}-${motivo}-${idx}`}
                    className={
                      "border-t border-zinc-900 cursor-pointer " +
                      (isSelected ? "bg-zinc-900/40" : "hover:bg-zinc-900/20")
                    }
                    onClick={() => setSelected({ fornecedor, motivo: r.motivo_codigo ?? null })}
                    role="button"
                    tabIndex={0}
                    onKeyDown={(e) => {
                      if (cleanUpper(e.key) === "ENTER") setSelected({ fornecedor, motivo: r.motivo_codigo ?? null });
                    }}
                  >
                    <td className="px-4 py-2 text-zinc-200 max-w-[260px] truncate" title={fornecedor}>
                      {fornecedor}
                    </td>
                    <td className="px-4 py-2 text-zinc-200 max-w-[260px] truncate" title={motivo}>
                      {motivo}
                    </td>
                    <td className="px-4 py-2 text-right tabular-nums">{formatMoney(r.a_vencer)}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{formatMoney(r.vencido_0_30)}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{formatMoney(r.vencido_31_60)}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{formatMoney(r.vencido_61_90)}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{formatMoney(r.vencido_90_mais)}</td>
                    <td className="px-4 py-2 text-right tabular-nums font-medium text-zinc-100">{formatMoney(r.total_aberto)}</td>
                  </tr>
                );
              })}

              {!resumo.length && !loading ? (
                <tr>
                  <td className="px-4 py-4 text-zinc-400" colSpan={8}>
                    Sem dados.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
        <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
          <div className="text-sm font-semibold text-zinc-100">
            Detalhes {selected ? `— ${selected.fornecedor ?? ""}` : ""}
          </div>
          <div className="text-xs text-zinc-500">{detalhe.length} parcelas</div>
        </div>

        {detalheLoading ? <div className="px-4 py-3 text-sm text-zinc-400">Carregando detalhes…</div> : null}

        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/60 text-zinc-300">
              <tr>
                <th className="text-left px-4 py-2 font-medium">Vencimento</th>
                <th className="text-right px-4 py-2 font-medium">Dias</th>
                <th className="text-left px-4 py-2 font-medium">Motivo</th>
                <th className="text-left px-4 py-2 font-medium">Status</th>
                <th className="text-left px-4 py-2 font-medium">Competência</th>
                <th className="text-right px-4 py-2 font-medium">Valor aberto</th>
              </tr>
            </thead>
            <tbody>
              {detalhe.map((r, idx) => {
                const motivo = [r.motivo_codigo, r.motivo_nome].filter(Boolean).join(" - ") || "—";
                return (
                  <tr key={`${r.vencimento_date}-${idx}`} className="border-t border-zinc-900">
                    <td className="px-4 py-2 text-zinc-200 whitespace-nowrap">{formatDateBR(r.vencimento_date)}</td>
                    <td className="px-4 py-2 text-right tabular-nums text-zinc-200">{String(r.dias_atraso ?? "")}</td>
                    <td className="px-4 py-2 text-zinc-200 max-w-[260px] truncate" title={motivo}>
                      {motivo}
                    </td>
                    <td className="px-4 py-2 text-zinc-200">{r.status ?? "—"}</td>
                    <td className="px-4 py-2 text-zinc-200 whitespace-nowrap">{formatDateBR(r.competencia_date)}</td>
                    <td className="px-4 py-2 text-right tabular-nums text-zinc-100">{formatMoney(r.valor_aberto)}</td>
                  </tr>
                );
              })}
              {!detalhe.length && !detalheLoading ? (
                <tr>
                  <td className="px-4 py-4 text-zinc-400" colSpan={6}>
                    Sem detalhes para o filtro.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
