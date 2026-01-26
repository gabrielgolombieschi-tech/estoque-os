"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { contaLabel, downloadCsv, formatDateBR, formatMoney, getDefaultRange, n, type ContaBancariaOption } from "../fluxoCaixaShared";

type ContaBancariaRow = {
  id: string;
  codigo: string | null;
  nome: string | null;
  banco: string | null;
  tipo: string | null;
};

type DiarioBreakRow = {
  data_ref: string;
  conta_bancaria_id?: string | null;
  valor_previsto?: number | string | null;
  valor_realizado?: number | string | null;
  motivo_codigo?: string | null;
  motivo_nome?: string | null;
  motivo_compra_id?: string | null;
  fornecedor_nome?: string | null;
  fornecedor_id?: string | null;
  os_id?: string | null;
  os_codigo?: string | null;
  os_numero?: string | null;
  conta_bancaria_codigo?: string | null;
  conta_bancaria_nome?: string | null;
  conta_codigo?: string | null;
  conta_nome?: string | null;
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

function pickGroupLabel(row: DiarioBreakRow, fallback: string) {
  const motivo = [row.motivo_codigo, row.motivo_nome].filter(Boolean).join(" - ");
  if (motivo) return motivo;
  if (row.fornecedor_nome) return row.fornecedor_nome;
  const os = row.os_codigo ?? row.os_numero ?? row.os_id;
  if (os) return `OS ${os}`;

  const conta =
    [row.conta_bancaria_codigo ?? row.conta_codigo, row.conta_bancaria_nome ?? row.conta_nome]
      .filter(Boolean)
      .join(" - ") || null;
  if (conta) return conta;

  return fallback;
}

export default function FluxoCaixaDiarioClient() {
  const te = useTenantEmpresa();
  const router = useRouter();

  const [range, setRange] = useState(getDefaultRange);
  const [contaId, setContaId] = useState<string>("");
  const [breakdown, setBreakdown] = useState<"conta" | "motivo" | "fornecedor" | "os">("conta");
  const [group, setGroup] = useState<"dia" | "dia_grupo">("dia");

  const [contas, setContas] = useState<ContaBancariaOption[]>([]);
  const contasById = useMemo(() => new Map(contas.map((c) => [c.id, c])), [contas]);

  const [rows, setRows] = useState<DiarioBreakRow[]>([]);
  const [loading, setLoading] = useState(true);
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

      const supabase = getSupabaseBrowser();

      // Load contas for labels
      try {
        const { data: contasData, error: contasErr } = await supabase
          .schema("f")
          .from("conta_bancaria")
          .select("id,codigo,nome,banco,tipo")
          .eq("ativo", true)
          .is("deleted_at", null)
          .order("nome", { ascending: true });

        if (contasErr) throw contasErr;
        const mapped = (contasData ?? []) as unknown as ContaBancariaRow[];
        const opts: ContaBancariaOption[] = mapped.map((c) => ({
          id: String(c.id),
          codigo: c.codigo ?? null,
          nome: c.nome ?? null,
          banco: c.banco ?? null,
          tipo: c.tipo ?? null,
        }));
        if (!cancelled) setContas(opts);
      } catch {
        if (!cancelled) setContas([]);
      }

      const fetchFrom = async (view: string, selects: string[]) => {
        for (const sel of selects) {
          const base = supabase
            .schema("f")
            .from(view)
            .select(sel)
            .gte("data_ref", range.start)
            .lte("data_ref", range.end)
            .order("data_ref", { ascending: true });

          const { data, error: qErr } = contaId ? await base.eq("conta_bancaria_id", contaId) : await base;
          if (!qErr) return (data ?? []) as unknown as DiarioBreakRow[];
        }
        throw new Error(`Nao foi possivel consultar view ${view}.`);
      };

      try {
        let data: DiarioBreakRow[] = [];

        if (breakdown === "conta") {
          // Prefer resolved view (may include conta labels), but fallback to base.
          try {
            data = await fetchFrom("r_fluxo_caixa_diario_conta_resolvida", [
              "data_ref,conta_bancaria_id,conta_bancaria_codigo,conta_bancaria_nome,valor_previsto,valor_realizado",
              "data_ref,conta_bancaria_id,conta_codigo,conta_nome,valor_previsto,valor_realizado",
              "data_ref,conta_bancaria_id,valor_previsto,valor_realizado",
            ]);
          } catch {
            data = await fetchFrom("r_fluxo_caixa_diario", ["data_ref,conta_bancaria_id,valor_previsto,valor_realizado"]);
          }
        }

        if (breakdown === "motivo") {
          try {
            data = await fetchFrom("r_fluxo_caixa_diario_por_motivo_rotulado", [
              "data_ref,conta_bancaria_id,motivo_compra_id,motivo_codigo,motivo_nome,valor_previsto,valor_realizado",
              "data_ref,motivo_compra_id,motivo_codigo,motivo_nome,valor_previsto,valor_realizado",
            ]);
          } catch {
            data = await fetchFrom("r_fluxo_caixa_diario_por_motivo", [
              "data_ref,conta_bancaria_id,motivo_compra_id,valor_previsto,valor_realizado",
              "data_ref,motivo_compra_id,valor_previsto,valor_realizado",
            ]);
          }
        }

        if (breakdown === "fornecedor") {
          data = await fetchFrom("r_fluxo_caixa_diario_por_fornecedor", [
            "data_ref,conta_bancaria_id,fornecedor_id,fornecedor_nome,valor_previsto,valor_realizado",
            "data_ref,fornecedor_id,fornecedor_nome,valor_previsto,valor_realizado",
          ]);
        }

        if (breakdown === "os") {
          data = await fetchFrom("r_fluxo_caixa_diario_por_os", [
            "data_ref,conta_bancaria_id,os_id,os_codigo,valor_previsto,valor_realizado",
            "data_ref,os_id,os_codigo,valor_previsto,valor_realizado",
            "data_ref,os_id,valor_previsto,valor_realizado",
          ]);
        }

        if (!cancelled) setRows(data);
      } catch (e: unknown) {
        if (!cancelled) {
          setRows([]);
          setError(e instanceof Error ? e.message : "Erro ao carregar fluxo diário.");
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [breakdown, contaId, range.end, range.start, ready]);

  const normalized = useMemo(() => {
    // Normalize + aggregate for table.
    const items = rows.map((r) => {
      const date = String(r.data_ref);
      const previsto = n(r.valor_previsto);
      const realizado = n(r.valor_realizado);

      const fallback = r.conta_bancaria_id ? String(r.conta_bancaria_id) : "(sem grupo)";
      const label = breakdown === "conta"
        ? r.conta_bancaria_id
          ? contaLabel(contasById.get(String(r.conta_bancaria_id)) ?? {
              id: String(r.conta_bancaria_id),
              codigo: r.conta_bancaria_codigo ?? r.conta_codigo ?? null,
              nome: r.conta_bancaria_nome ?? r.conta_nome ?? null,
              banco: null,
              tipo: null,
            })
          : "(sem conta)"
        : pickGroupLabel(r, fallback);

      return { date, label, previsto, realizado };
    });

    const totalPrevisto = items.reduce((acc, it) => acc + it.previsto, 0);
    const totalRealizado = items.reduce((acc, it) => acc + it.realizado, 0);

    const entradasPrev = items.reduce((acc, it) => acc + (it.previsto > 0 ? it.previsto : 0), 0);
    const saidasPrev = items.reduce((acc, it) => acc + (it.previsto < 0 ? it.previsto : 0), 0);

    const entradasReal = items.reduce((acc, it) => acc + (it.realizado > 0 ? it.realizado : 0), 0);
    const saidasReal = items.reduce((acc, it) => acc + (it.realizado < 0 ? it.realizado : 0), 0);

    const byKey = new Map<string, { date: string; label: string; previsto: number; realizado: number }>();
    for (const it of items) {
      const key = group === "dia" ? it.date : `${it.date}::${it.label}`;
      const cur = byKey.get(key) ?? { date: it.date, label: group === "dia" ? "" : it.label, previsto: 0, realizado: 0 };
      cur.previsto += it.previsto;
      cur.realizado += it.realizado;
      byKey.set(key, cur);
    }

    const table = Array.from(byKey.values()).sort((a, b) => {
      const d = a.date.localeCompare(b.date);
      if (d !== 0) return d;
      return a.label.localeCompare(b.label);
    });

    return {
      entradasPrev,
      saidasPrev,
      totalPrevisto,
      entradasReal,
      saidasReal,
      totalRealizado,
      delta: totalRealizado - totalPrevisto,
      table,
    };
  }, [breakdown, contasById, group, rows]);

  const exportCsv = () => {
    const header = [
      "data_ref",
      group === "dia" ? "" : breakdown === "conta" ? "conta" : breakdown,
      "valor_previsto",
      "valor_realizado",
      "delta",
    ].filter((h) => h.length > 0);

    const dataRows = normalized.table.map((r) => {
      const cols = [
        r.date,
        group === "dia" ? null : r.label,
        String(r.previsto),
        String(r.realizado),
        String(r.realizado - r.previsto),
      ];
      return cols.filter((_, idx) => (group === "dia" ? idx !== 1 : true)) as string[];
    });

    downloadCsv(`fluxo_caixa_diario_${breakdown}_${range.start}_a_${range.end}.csv`, header, dataRows);
  };

  if (canFinanceiro !== true) return null;

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Fluxo de Caixa — Diário</h1>
          <p className="text-sm text-zinc-400 mt-1">Comparativo previsto vs realizado no dia.</p>
        </div>
        <div className="flex gap-2">
          <Link
            href="/financeiro/relatorios/fluxo-caixa"
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Voltar
          </Link>
          <button
            type="button"
            onClick={exportCsv}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
          >
            Exportar CSV
          </button>
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <div className="grid grid-cols-1 md:grid-cols-5 gap-3 items-end">
          <div>
            <label className="text-xs text-zinc-400" htmlFor="dia-start">
              Início
            </label>
            <input
              id="dia-start"
              type="date"
              value={range.start}
              onChange={(e) => setRange((p) => ({ ...p, start: e.target.value }))}
              className="mt-1 w-full rounded-md bg-zinc-900 border border-zinc-800 px-3 py-2 text-sm"
            />
          </div>

          <div>
            <label className="text-xs text-zinc-400" htmlFor="dia-end">
              Fim
            </label>
            <input
              id="dia-end"
              type="date"
              value={range.end}
              onChange={(e) => setRange((p) => ({ ...p, end: e.target.value }))}
              className="mt-1 w-full rounded-md bg-zinc-900 border border-zinc-800 px-3 py-2 text-sm"
            />
          </div>

          <div>
            <label className="text-xs text-zinc-400" htmlFor="dia-conta">
              Conta (opcional)
            </label>
            <select
              id="dia-conta"
              value={contaId}
              onChange={(e) => setContaId(e.target.value)}
              className="mt-1 w-full rounded-md bg-zinc-900 border border-zinc-800 px-3 py-2 text-sm"
            >
              <option value="">Todas</option>
              {contas.map((c) => (
                <option key={c.id} value={c.id}>
                  {contaLabel(c)}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="text-xs text-zinc-400" htmlFor="dia-break">
              Visão
            </label>
            <select
              id="dia-break"
              value={breakdown}
              onChange={(e) => setBreakdown(e.target.value as "conta" | "motivo" | "fornecedor" | "os")}
              className="mt-1 w-full rounded-md bg-zinc-900 border border-zinc-800 px-3 py-2 text-sm"
            >
              <option value="conta">Por conta</option>
              <option value="motivo">Por motivo</option>
              <option value="fornecedor">Por fornecedor</option>
              <option value="os">Por OS</option>
            </select>
          </div>

          <div>
            <label className="text-xs text-zinc-400" htmlFor="dia-group">
              Agrupar
            </label>
            <select
              id="dia-group"
              value={group}
              onChange={(e) => setGroup(e.target.value as "dia" | "dia_grupo")}
              className="mt-1 w-full rounded-md bg-zinc-900 border border-zinc-800 px-3 py-2 text-sm"
            >
              <option value="dia">Por dia (somando grupos)</option>
              <option value="dia_grupo">Por dia + grupo</option>
            </select>
          </div>
        </div>

        {error ? <div className="mt-3 text-sm text-red-400">{error}</div> : null}
        {loading ? <div className="mt-3 text-sm text-zinc-400">Carregando…</div> : null}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <Stat title="Previsto (entradas)" value={formatMoney(normalized.entradasPrev)} />
        <Stat title="Previsto (saídas)" value={formatMoney(normalized.saidasPrev)} />
        <Stat title="Previsto (total)" value={formatMoney(normalized.totalPrevisto)} />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <Stat title="Realizado (entradas)" value={formatMoney(normalized.entradasReal)} />
        <Stat title="Realizado (saídas)" value={formatMoney(normalized.saidasReal)} />
        <Stat title="Realizado (total)" value={formatMoney(normalized.totalRealizado)} />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        <Stat title="Delta (Realizado - Previsto)" value={formatMoney(normalized.delta)} subtitle="Desvio no período" />
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 text-sm text-zinc-300">
          <div className="font-semibold text-zinc-100">Dica</div>
          <div className="mt-1 text-zinc-400">
            Use a visão por <span className="text-zinc-200">motivo</span> / <span className="text-zinc-200">fornecedor</span> /
            <span className="text-zinc-200"> OS</span> para rastrear o que “puxou” o caixa.
          </div>
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
        <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
          <div className="text-sm font-semibold text-zinc-100">Tabela</div>
          <div className="text-xs text-zinc-500">{normalized.table.length} linhas</div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/60 text-zinc-300">
              <tr>
                <th className="text-left px-4 py-2 font-medium">Data</th>
                {group === "dia_grupo" ? (
                  <th className="text-left px-4 py-2 font-medium">
                    {breakdown === "conta" ? "Conta" : breakdown === "os" ? "OS" : breakdown}
                  </th>
                ) : null}
                <th className="text-right px-4 py-2 font-medium">Previsto</th>
                <th className="text-right px-4 py-2 font-medium">Realizado</th>
                <th className="text-right px-4 py-2 font-medium">Delta</th>
              </tr>
            </thead>
            <tbody>
              {normalized.table.map((r, idx) => (
                <tr key={`${r.date}-${r.label}-${idx}`} className="border-t border-zinc-900">
                  <td className="px-4 py-2 text-zinc-200 whitespace-nowrap">{formatDateBR(r.date)}</td>
                  {group === "dia_grupo" ? (
                    <td className="px-4 py-2 text-zinc-200 max-w-[420px] truncate" title={r.label}>
                      {r.label || "(total do dia)"}
                    </td>
                  ) : null}
                  <td className="px-4 py-2 text-right tabular-nums text-zinc-100">{formatMoney(r.previsto)}</td>
                  <td className="px-4 py-2 text-right tabular-nums text-zinc-100">{formatMoney(r.realizado)}</td>
                  <td className="px-4 py-2 text-right tabular-nums text-zinc-100">{formatMoney(r.realizado - r.previsto)}</td>
                </tr>
              ))}

              {!normalized.table.length && !loading ? (
                <tr>
                  <td className="px-4 py-4 text-zinc-400" colSpan={group === "dia_grupo" ? 5 : 4}>
                    Sem dados no período.
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
