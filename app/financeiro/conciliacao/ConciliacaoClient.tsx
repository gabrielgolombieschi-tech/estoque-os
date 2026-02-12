"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { formatDecimalBR } from "@/lib/decimal";

type ContaBancariaRow = { id: string; codigo: string; nome: string };

type ExtratoLinhaRow = {
  id: string;
  conta_bancaria_id: string;
  data_movimento: string;
  descricao: string | null;
  documento: string | null;
  valor: number | string;
  status: string;
};

type PagamentoRow = {
  id: string;
  conta_bancaria_id: string;
  data_pagamento: string;
  forma_pagamento: string;
  valor: number | string;
  observacoes: string | null;
  conciliado_at: string | null;
};

type SugestaoApRow = {
  tenant_id: string;
  empresa_id: string;
  conta_bancaria_id: string;
  extrato_linha_id: string;
  data_movimento: string;
  valor_extrato: number | string;
  descricao: string | null;
  documento: string | null;
  pagamento_id: string;
  data_pagamento: string;
  forma_pagamento: string;
  valor_pagamento: number | string;
  diferenca_valor: number | string;
  score_data: number | string;
};

type ConciliacaoRow = {
  id: string;
  conta_bancaria_id: string;
  status: string;
  extrato_linha_id: string | null;
  pagamento_id: string | null;
  valor_conciliado: number | string | null;
  diferenca: number | string | null;
  conciliado_em: string | null;
  observacoes: string | null;
  referencia: string | null;
};

function n(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

function formatDateBR(iso?: string | null): string {
  if (!iso) return "";
  const d = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleDateString("pt-BR");
}

function pillClass(kind: "ok" | "warn" | "muted") {
  if (kind === "ok") return "bg-emerald-500/15 text-emerald-200 border-emerald-500/30";
  if (kind === "warn") return "bg-amber-500/15 text-amber-200 border-amber-500/30";
  return "bg-zinc-700/40 text-zinc-200 border-zinc-700";
}

function Pill({ text, kind }: { text: string; kind: "ok" | "warn" | "muted" }) {
  return <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-xs ${pillClass(kind)}`}>{text}</span>;
}

export default function ConciliacaoClient() {
  const te = useTenantEmpresa();
  const router = useRouter();

  const canFinanceiro = useMemo(() => {
    const r = te.has("financeiro.read");
    const w = te.has("financeiro.write");
    if (r === undefined || w === undefined) return undefined;
    return Boolean(r || w);
  }, [te]);

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  const [tab, setTab] = useState<"sugestoes" | "pendencias" | "historico">("sugestoes");

  const [contas, setContas] = useState<ContaBancariaRow[]>([]);
  const [contaId, setContaId] = useState<string>("");
  const [startDate, setStartDate] = useState<string>("");
  const [endDate, setEndDate] = useState<string>("");

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [sugestoes, setSugestoes] = useState<SugestaoApRow[]>([]);
  const [pendExtrato, setPendExtrato] = useState<ExtratoLinhaRow[]>([]);
  const [pendPag, setPendPag] = useState<PagamentoRow[]>([]);
  const [historico, setHistorico] = useState<ConciliacaoRow[]>([]);

  const [busyKey, setBusyKey] = useState<string | null>(null);

  const resumo = useMemo(() => {
    const totalSug = sugestoes.length;
    const extratoPend = pendExtrato.length;
    const pagPend = pendPag.length;
    const historicoCount = historico.length;

    const totalExtratoPend = pendExtrato.reduce((acc, e) => acc + n(e.valor), 0);
    const totalPagPend = pendPag.reduce((acc, p) => acc + n(p.valor), 0);

    return { totalSug, extratoPend, pagPend, historicoCount, totalExtratoPend, totalPagPend };
  }, [historico.length, pendExtrato, pendPag, sugestoes.length]);

  const reload = async () => {
    if (typeof te.sessionUserId !== "string") return;
    if (!te.tenantId) return;
    if (!te.empresaId && te.empresas.length !== 1) return;
    if (canFinanceiro !== true) return;

    setLoading(true);
    setError(null);

    const supabase = getSupabaseBrowser();

    try {
      const { data: contasData, error: contasErr } = await supabase
        .schema("f")
        .from("conta_bancaria")
        .select("id,codigo,nome")
        .eq("tenant_id", te.tenantId)
        .eq("ativo", true)
        .is("deleted_at", null)
        .order("nome", { ascending: true });

      if (contasErr) throw contasErr;
      const contasMapped = (contasData ?? []).map((row) => {
        const r = row as Record<string, unknown>;
        return { id: String(r.id), codigo: String(r.codigo), nome: String(r.nome) };
      });
      setContas(contasMapped);

      const effectiveContaId = contaId || (contasMapped.length === 1 ? contasMapped[0].id : "");
      setContaId(effectiveContaId);

      if (!effectiveContaId) {
        setSugestoes([]);
        setPendExtrato([]);
        setPendPag([]);
        setHistorico([]);
        return;
      }

      let s = supabase
        .schema("f")
        .from("r_sugestoes_conciliacao_ap")
        .select(
          "tenant_id,empresa_id,conta_bancaria_id,extrato_linha_id,data_movimento,valor_extrato,descricao,documento,pagamento_id,data_pagamento,forma_pagamento,valor_pagamento,diferenca_valor,score_data"
        )
        .eq("conta_bancaria_id", effectiveContaId)
        .order("score_data", { ascending: false })
        .order("data_movimento", { ascending: false })
        .limit(200);

      if (startDate) s = s.gte("data_movimento", startDate);
      if (endDate) s = s.lte("data_movimento", endDate);

      const { data: sugestoesData, error: sugErr } = await s;
      if (sugErr) throw sugErr;
      setSugestoes((sugestoesData ?? []) as unknown as SugestaoApRow[]);

      // Pendências: extrato pendente (negativos e positivos)
      let qExtr = supabase
        .schema("f")
        .from("extrato_bancario_linha")
        .select("id,conta_bancaria_id,data_movimento,descricao,documento,valor,status")
        .eq("conta_bancaria_id", effectiveContaId)
        .eq("status", "PENDENTE")
        .is("deleted_at", null)
        .order("data_movimento", { ascending: false })
        .limit(250);
      if (startDate) qExtr = qExtr.gte("data_movimento", startDate);
      if (endDate) qExtr = qExtr.lte("data_movimento", endDate);

      const { data: extrData, error: extrErr } = await qExtr;
      if (extrErr) throw extrErr;
      setPendExtrato((extrData ?? []) as unknown as ExtratoLinhaRow[]);

      // Pendências: pagamentos não conciliados
      let qPag = supabase
        .schema("f")
        .from("pagamento")
        .select("id,conta_bancaria_id,data_pagamento,forma_pagamento,valor,observacoes,conciliado_at")
        .eq("conta_bancaria_id", effectiveContaId)
        .is("deleted_at", null)
        .is("conciliado_at", null)
        .order("data_pagamento", { ascending: false })
        .limit(250);
      if (startDate) qPag = qPag.gte("data_pagamento", startDate);
      if (endDate) qPag = qPag.lte("data_pagamento", endDate);

      const { data: pagData, error: pagErr } = await qPag;
      if (pagErr) throw pagErr;
      setPendPag((pagData ?? []) as unknown as PagamentoRow[]);

      // Histórico
      let qHist = supabase
        .schema("f")
        .from("conciliacao_bancaria")
        .select("id,conta_bancaria_id,status,extrato_linha_id,pagamento_id,valor_conciliado,diferenca,conciliado_em,observacoes,referencia")
        .eq("conta_bancaria_id", effectiveContaId)
        .is("deleted_at", null)
        .order("conciliado_em", { ascending: false })
        .limit(200);
      if (startDate) qHist = qHist.gte("conciliado_em", `${startDate}T00:00:00`);
      if (endDate) qHist = qHist.lte("conciliado_em", `${endDate}T23:59:59`);

      const { data: histData, error: histErr } = await qHist;
      if (histErr) throw histErr;
      setHistorico((histData ?? []) as unknown as ConciliacaoRow[]);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao carregar conciliação.");
      setSugestoes([]);
      setPendExtrato([]);
      setPendPag([]);
      setHistorico([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canFinanceiro, te.sessionUserId, te.tenantId, te.empresaId, te.empresas.length]);

  useEffect(() => {
    void reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [contaId, startDate, endDate]);

  const conciliarSugestao = async (row: SugestaoApRow) => {
    if (!te.tenantId || !te.empresaId) return;

    const key = `sug:${row.extrato_linha_id}:${row.pagamento_id}`;
    setBusyKey(key);
    setError(null);

    try {
      const supabase = getSupabaseBrowser();
      const valorConciliado = n(row.valor_pagamento);
      const diferenca = n(row.diferenca_valor);

      // IMPORTANT: ck_conciliacao_bancaria__status only allows CONCILIADO/DESCONCILIADO.
      const { error: insErr } = await supabase
        .schema("f")
        .from("conciliacao_bancaria")
        .insert({
          tenant_id: te.tenantId,
          empresa_id: te.empresaId,
          conta_bancaria_id: row.conta_bancaria_id,
          referencia: `AUTO AP ${row.data_movimento}`,
          status: "CONCILIADO",
          extrato_linha_id: row.extrato_linha_id,
          pagamento_id: row.pagamento_id,
          valor_conciliado: valorConciliado,
          diferenca,
          observacoes: "Conciliado via sugestão automática (AP).",
          conciliado_em: new Date().toISOString(),
        });

      if (insErr) throw insErr;

      // Best-effort: mark extrato line + payment.
      await supabase
        .schema("f")
        .from("extrato_bancario_linha")
        .update({ status: "CONCILIADO", updated_at: new Date().toISOString() })
        .eq("id", row.extrato_linha_id);

      await supabase
        .schema("f")
        .from("pagamento")
        .update({ conciliado_at: new Date().toISOString() })
        .eq("id", row.pagamento_id);

      await reload();
      setTab("historico");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao conciliar sugestão.");
    } finally {
      setBusyKey(null);
    }
  };

  const selectedConta = contas.find((c) => c.id === contaId) ?? null;

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Conciliação Bancária</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Sugestões automáticas (AP) + pendências + histórico (f.r_sugestoes_conciliacao_ap / f.conciliacao_bancaria).
          </p>
          <p className="text-xs text-zinc-500 mt-1">
            Lucro Real: conciliação é rastreabilidade de caixa/banco; competência e classificação ficam no título.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href="/financeiro/extratos"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Extratos
          </Link>
          <Link
            href="/financeiro/contas-pagar/pagamentos"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Pagamentos
          </Link>
          <Link
            href="/financeiro"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Voltar
          </Link>
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-3">
        <div className="flex flex-wrap items-end gap-2">
          <label className="block text-xs text-zinc-400">
            Conta bancária
            <select
              value={contaId}
              onChange={(e) => setContaId(e.target.value)}
              aria-label="Conta bancária"
              className="mt-1 w-[320px] max-w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            >
              <option value="">Selecione…</option>
              {contas.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.codigo} — {c.nome}
                </option>
              ))}
            </select>
          </label>

          <label className="block text-xs text-zinc-400">
            De
            <input
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              aria-label="Data inicial"
              className="mt-1 rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            />
          </label>
          <label className="block text-xs text-zinc-400">
            Até
            <input
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              aria-label="Data final"
              className="mt-1 rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            />
          </label>

          <button
            type="button"
            onClick={() => {
              setStartDate("");
              setEndDate("");
            }}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Limpar período
          </button>

          {selectedConta && <div className="text-xs text-zinc-500">Conta: {selectedConta.codigo} — {selectedConta.nome}</div>}
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-4 gap-3">
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Sugestões (AP)</div>
            <div className="text-lg font-semibold">{resumo.totalSug}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Extrato pendente</div>
            <div className="text-lg font-semibold">{resumo.extratoPend}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Pagamentos pendentes</div>
            <div className="text-lg font-semibold">{resumo.pagPend}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
            <div className="text-xs text-zinc-400">Histórico</div>
            <div className="text-lg font-semibold">{resumo.historicoCount}</div>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => setTab("sugestoes")}
            className={`px-3 py-2 rounded-md border text-sm ${tab === "sugestoes" ? "border-zinc-100 bg-zinc-100 text-zinc-900" : "border-zinc-800 bg-zinc-950 hover:bg-zinc-900"}`}
          >
            Sugestões
          </button>
          <button
            type="button"
            onClick={() => setTab("pendencias")}
            className={`px-3 py-2 rounded-md border text-sm ${tab === "pendencias" ? "border-zinc-100 bg-zinc-100 text-zinc-900" : "border-zinc-800 bg-zinc-950 hover:bg-zinc-900"}`}
          >
            Pendências
          </button>
          <button
            type="button"
            onClick={() => setTab("historico")}
            className={`px-3 py-2 rounded-md border text-sm ${tab === "historico" ? "border-zinc-100 bg-zinc-100 text-zinc-900" : "border-zinc-800 bg-zinc-950 hover:bg-zinc-900"}`}
          >
            Histórico
          </button>

          {loading && <div className="text-xs text-zinc-400">Carregando…</div>}
        </div>
      </div>

      {error && <div className="text-sm text-red-300">{error}</div>}

      {tab === "sugestoes" && (
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
          <div className="px-4 py-3 border-b border-zinc-800">
            <div className="font-semibold">Sugestões automáticas (AP)</div>
            <div className="text-xs text-zinc-500 mt-1">
              Baseada em igualdade de valor (saída no extrato x pagamento) e proximidade de data (±2 dias).
            </div>
          </div>

          <div className="overflow-auto">
            <table className="min-w-[1180px] w-full text-sm">
              <thead className="bg-zinc-950/60">
                <tr className="text-left text-xs text-zinc-400">
                  <th className="px-4 py-3">Extrato</th>
                  <th className="px-4 py-3">Pagamento</th>
                  <th className="px-4 py-3 text-right">Dif.</th>
                  <th className="px-4 py-3">Score</th>
                  <th className="px-4 py-3">Ação</th>
                </tr>
              </thead>
              <tbody>
                {!loading && sugestoes.length === 0 && (
                  <tr>
                    <td className="px-4 py-6 text-zinc-400" colSpan={5}>
                      Nenhuma sugestão encontrada.
                    </td>
                  </tr>
                )}

                {sugestoes.map((r) => {
                  const key = `sug:${r.extrato_linha_id}:${r.pagamento_id}`;
                  const diff = n(r.diferenca_valor);
                  const score = n(r.score_data);
                  return (
                    <tr key={key} className="border-t border-zinc-900 hover:bg-zinc-900/40">
                      <td className="px-4 py-3">
                        <div className="text-zinc-100">
                          {formatDateBR(r.data_movimento)} — {formatDecimalBR(n(r.valor_extrato), 2)}
                        </div>
                        <div className="text-xs text-zinc-500 mt-1">{r.descricao ?? "-"}</div>
                        {r.documento && <div className="text-xs text-zinc-500">Doc: {r.documento}</div>}
                      </td>
                      <td className="px-4 py-3">
                        <div className="text-zinc-100">
                          {formatDateBR(r.data_pagamento)} — {formatDecimalBR(n(r.valor_pagamento), 2)}
                        </div>
                        <div className="text-xs text-zinc-500 mt-1">
                          Forma: <span className="text-zinc-300">{r.forma_pagamento}</span> — ID: {r.pagamento_id}
                        </div>
                      </td>
                      <td className="px-4 py-3 text-right">
                        {diff === 0 ? <Pill text="OK" kind="ok" /> : <Pill text={formatDecimalBR(diff, 2)} kind="warn" />}
                      </td>
                      <td className="px-4 py-3">
                        {score >= 3 ? <Pill text="D0" kind="ok" /> : score === 2 ? <Pill text="±1" kind="warn" /> : <Pill text="±2" kind="muted" />}
                      </td>
                      <td className="px-4 py-3">
                        <button
                          type="button"
                          onClick={() => conciliarSugestao(r)}
                          disabled={busyKey === key || !te.empresaId}
                          className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
                        >
                          {busyKey === key ? "Conciliando…" : "Conciliar"}
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {tab === "pendencias" && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
            <div className="px-4 py-3 border-b border-zinc-800">
              <div className="font-semibold">Extrato pendente</div>
              <div className="text-xs text-zinc-500 mt-1">Linhas em PENDENTE na conta selecionada.</div>
            </div>
            <div className="overflow-auto">
              <table className="min-w-[720px] w-full text-sm">
                <thead className="bg-zinc-950/60">
                  <tr className="text-left text-xs text-zinc-400">
                    <th className="px-4 py-3">Data</th>
                    <th className="px-4 py-3">Descrição</th>
                    <th className="px-4 py-3 text-right">Valor</th>
                  </tr>
                </thead>
                <tbody>
                  {!loading && pendExtrato.length === 0 && (
                    <tr>
                      <td className="px-4 py-6 text-zinc-400" colSpan={3}>
                        Nenhuma pendência de extrato.
                      </td>
                    </tr>
                  )}
                  {pendExtrato.map((e) => (
                    <tr key={e.id} className="border-t border-zinc-900 hover:bg-zinc-900/40">
                      <td className="px-4 py-3 whitespace-nowrap">{formatDateBR(e.data_movimento)}</td>
                      <td className="px-4 py-3">
                        <div className="text-zinc-100">{e.descricao ?? "-"}</div>
                        {e.documento && <div className="text-xs text-zinc-500">Doc: {e.documento}</div>}
                      </td>
                      <td className={`px-4 py-3 text-right font-medium ${n(e.valor) < 0 ? "text-amber-200" : "text-emerald-200"}`}>
                        {formatDecimalBR(n(e.valor), 2)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
            <div className="px-4 py-3 border-b border-zinc-800">
              <div className="font-semibold">Pagamentos pendentes</div>
              <div className="text-xs text-zinc-500 mt-1">Pagamentos com conciliado_at NULL.</div>
            </div>
            <div className="overflow-auto">
              <table className="min-w-[760px] w-full text-sm">
                <thead className="bg-zinc-950/60">
                  <tr className="text-left text-xs text-zinc-400">
                    <th className="px-4 py-3">Data</th>
                    <th className="px-4 py-3">Forma</th>
                    <th className="px-4 py-3">Obs.</th>
                    <th className="px-4 py-3 text-right">Valor</th>
                  </tr>
                </thead>
                <tbody>
                  {!loading && pendPag.length === 0 && (
                    <tr>
                      <td className="px-4 py-6 text-zinc-400" colSpan={4}>
                        Nenhum pagamento pendente.
                      </td>
                    </tr>
                  )}
                  {pendPag.map((p) => (
                    <tr key={p.id} className="border-t border-zinc-900 hover:bg-zinc-900/40">
                      <td className="px-4 py-3 whitespace-nowrap">{formatDateBR(p.data_pagamento)}</td>
                      <td className="px-4 py-3">{p.forma_pagamento}</td>
                      <td className="px-4 py-3 text-zinc-300">{p.observacoes ?? "-"}</td>
                      <td className="px-4 py-3 text-right font-medium text-amber-200">{formatDecimalBR(n(p.valor), 2)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {tab === "historico" && (
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
          <div className="px-4 py-3 border-b border-zinc-800">
            <div className="font-semibold">Histórico de conciliações</div>
            <div className="text-xs text-zinc-500 mt-1">Registros em f.conciliacao_bancaria.</div>
          </div>

          <div className="overflow-auto">
            <table className="min-w-[1120px] w-full text-sm">
              <thead className="bg-zinc-950/60">
                <tr className="text-left text-xs text-zinc-400">
                  <th className="px-4 py-3">Quando</th>
                  <th className="px-4 py-3">Status</th>
                  <th className="px-4 py-3">Extrato linha</th>
                  <th className="px-4 py-3">Pagamento</th>
                  <th className="px-4 py-3 text-right">Valor</th>
                  <th className="px-4 py-3 text-right">Dif.</th>
                  <th className="px-4 py-3">Obs.</th>
                </tr>
              </thead>
              <tbody>
                {!loading && historico.length === 0 && (
                  <tr>
                    <td className="px-4 py-6 text-zinc-400" colSpan={7}>
                      Nenhuma conciliação encontrada.
                    </td>
                  </tr>
                )}
                {historico.map((h) => {
                  const st = String(h.status || "").toUpperCase();
                  const ok = st === "CONCILIADO";
                  return (
                    <tr key={h.id} className="border-t border-zinc-900 hover:bg-zinc-900/40">
                      <td className="px-4 py-3 whitespace-nowrap">{h.conciliado_em ? new Date(h.conciliado_em).toLocaleString("pt-BR") : "-"}</td>
                      <td className="px-4 py-3">{ok ? <Pill text="CONCILIADO" kind="ok" /> : <Pill text={st || "-"} kind="muted" />}</td>
                      <td className="px-4 py-3 text-zinc-300">{h.extrato_linha_id ?? "-"}</td>
                      <td className="px-4 py-3 text-zinc-300">{h.pagamento_id ?? "-"}</td>
                      <td className="px-4 py-3 text-right font-medium">{formatDecimalBR(n(h.valor_conciliado), 2)}</td>
                      <td className="px-4 py-3 text-right">{formatDecimalBR(n(h.diferenca), 2)}</td>
                      <td className="px-4 py-3 text-zinc-300">{h.observacoes ?? h.referencia ?? "-"}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
