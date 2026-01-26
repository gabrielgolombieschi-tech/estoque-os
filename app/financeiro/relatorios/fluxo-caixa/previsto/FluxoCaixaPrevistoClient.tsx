"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { contaLabel, downloadCsv, formatDateBR, formatMoney, getDefaultRange, n, type ContaBancariaOption } from "../fluxoCaixaShared";

type PrevistoRow = {
  data_ref: string;
  conta_bancaria_id: string | null;
  valor_previsto: number | string | null;
};

type ContaBancariaRow = {
  id: string;
  codigo: string | null;
  nome: string | null;
  banco: string | null;
  tipo: string | null;
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

export default function FluxoCaixaPrevistoClient() {
  const te = useTenantEmpresa();
  const router = useRouter();

  const [range, setRange] = useState(getDefaultRange);
  const [contaId, setContaId] = useState<string>("");
  const [group, setGroup] = useState<"dia" | "dia_conta">("dia");

  const [contas, setContas] = useState<ContaBancariaOption[]>([]);
  const contasById = useMemo(() => new Map(contas.map((c) => [c.id, c])), [contas]);

  const [rows, setRows] = useState<PrevistoRow[]>([]);
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

      try {
        const base = supabase
          .schema("f")
          .from("r_fluxo_caixa_previsto_diario")
          .select("data_ref,conta_bancaria_id,valor_previsto")
          .gte("data_ref", range.start)
          .lte("data_ref", range.end)
          .order("data_ref", { ascending: true });

        const { data, error: qErr } = contaId ? await base.eq("conta_bancaria_id", contaId) : await base;
        if (qErr) throw qErr;
        if (!cancelled) setRows(((data ?? []) as unknown) as PrevistoRow[]);
      } catch (e: unknown) {
        if (!cancelled) {
          setRows([]);
          setError(e instanceof Error ? e.message : "Erro ao carregar fluxo previsto.");
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [contaId, range.end, range.start, ready]);

  const normalized = useMemo(() => {
    const items = rows.map((r) => {
      const date = String(r.data_ref);
      const conta = r.conta_bancaria_id ? String(r.conta_bancaria_id) : null;
      const value = n(r.valor_previsto);
      return { date, conta, value };
    });

    const entradas = items.reduce((acc, it) => acc + (it.value > 0 ? it.value : 0), 0);
    const saidas = items.reduce((acc, it) => acc + (it.value < 0 ? it.value : 0), 0);
    const saldo = entradas + saidas;

    const byKey = new Map<string, { date: string; conta: string | null; value: number }>();
    for (const it of items) {
      const key = group === "dia" ? it.date : `${it.date}::${it.conta ?? ""}`;
      const cur = byKey.get(key) ?? { date: it.date, conta: group === "dia" ? null : it.conta, value: 0 };
      cur.value += it.value;
      byKey.set(key, cur);
    }

    const table = Array.from(byKey.values()).sort((a, b) => {
      const d = a.date.localeCompare(b.date);
      if (d !== 0) return d;
      return String(a.conta ?? "").localeCompare(String(b.conta ?? ""));
    });

    return { entradas, saidas, saldo, table };
  }, [group, rows]);

  const exportCsv = () => {
    const header = ["data_ref", group === "dia" ? "" : "conta_bancaria", "valor_previsto"]
      .filter((h) => h.length > 0);

    const dataRows = normalized.table.map((r) => {
      const conta = r.conta ? contaLabel(contasById.get(r.conta) ?? { id: r.conta, codigo: null, nome: null, banco: null, tipo: null }) : "";
      const cols = [r.date, group === "dia" ? null : conta, String(r.value)];
      return cols.filter((_, idx) => (group === "dia" ? idx !== 1 : true)) as string[];
    });

    downloadCsv(`fluxo_caixa_previsto_${range.start}_a_${range.end}.csv`, header, dataRows);
  };

  if (canFinanceiro !== true) return null;

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Fluxo de Caixa — Previsto</h1>
          <p className="text-sm text-zinc-400 mt-1">Planejamento por data (títulos/parcelas/agendamentos).</p>
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
        <div className="grid grid-cols-1 md:grid-cols-4 gap-3 items-end">
          <div>
            <label className="text-xs text-zinc-400" htmlFor="prev-start">
              Início
            </label>
            <input
              id="prev-start"
              type="date"
              value={range.start}
              onChange={(e) => setRange((p) => ({ ...p, start: e.target.value }))}
              className="mt-1 w-full rounded-md bg-zinc-900 border border-zinc-800 px-3 py-2 text-sm"
            />
          </div>

          <div>
            <label className="text-xs text-zinc-400" htmlFor="prev-end">
              Fim
            </label>
            <input
              id="prev-end"
              type="date"
              value={range.end}
              onChange={(e) => setRange((p) => ({ ...p, end: e.target.value }))}
              className="mt-1 w-full rounded-md bg-zinc-900 border border-zinc-800 px-3 py-2 text-sm"
            />
          </div>

          <div>
            <label className="text-xs text-zinc-400" htmlFor="prev-conta">
              Conta (opcional)
            </label>
            <select
              id="prev-conta"
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
            <label className="text-xs text-zinc-400" htmlFor="prev-group">
              Agrupar
            </label>
            <select
              id="prev-group"
              value={group}
              onChange={(e) => setGroup(e.target.value as "dia" | "dia_conta")}
              className="mt-1 w-full rounded-md bg-zinc-900 border border-zinc-800 px-3 py-2 text-sm"
            >
              <option value="dia">Por dia (somando contas)</option>
              <option value="dia_conta">Por dia + conta</option>
            </select>
          </div>
        </div>

        {error ? <div className="mt-3 text-sm text-red-400">{error}</div> : null}
        {loading ? <div className="mt-3 text-sm text-zinc-400">Carregando…</div> : null}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <Stat title="Entradas (previsto)" value={formatMoney(normalized.entradas)} subtitle="Somatório de valores positivos" />
        <Stat title="Saídas (previsto)" value={formatMoney(normalized.saidas)} subtitle="Somatório de valores negativos" />
        <Stat title="Saldo (previsto)" value={formatMoney(normalized.saldo)} subtitle="Entradas + Saídas" />
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
                {group === "dia_conta" ? <th className="text-left px-4 py-2 font-medium">Conta</th> : null}
                <th className="text-right px-4 py-2 font-medium">Valor</th>
              </tr>
            </thead>
            <tbody>
              {normalized.table.map((r, idx) => {
                const conta = r.conta ? contasById.get(r.conta) : null;
                const contaText = r.conta
                  ? conta
                    ? contaLabel(conta)
                    : r.conta
                  : "";

                return (
                  <tr key={`${r.date}-${r.conta ?? ""}-${idx}`} className="border-t border-zinc-900">
                    <td className="px-4 py-2 text-zinc-200 whitespace-nowrap">{formatDateBR(r.date)}</td>
                    {group === "dia_conta" ? (
                      <td className="px-4 py-2 text-zinc-200 max-w-[420px] truncate" title={contaText}>
                        {contaText}
                      </td>
                    ) : null}
                    <td className="px-4 py-2 text-right tabular-nums text-zinc-100">{formatMoney(r.value)}</td>
                  </tr>
                );
              })}
              {!normalized.table.length && !loading ? (
                <tr>
                  <td className="px-4 py-4 text-zinc-400" colSpan={group === "dia_conta" ? 3 : 2}>
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
