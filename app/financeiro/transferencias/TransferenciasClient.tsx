"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { formatMoneyBR, parseMoneyBR } from "@/lib/decimal";

type ContaBancariaRow = {
  id: string;
  codigo: string;
  nome: string;
  tipo: string;
  banco: string | null;
  agencia: string | null;
  conta: string | null;
  saldo_atual: number | null;
  configurada: boolean;
};

type TransferenciaRow = {
  id: string;
  data_movimento: string;
  valor: number;
  descricao: string;
  status: string;
  conta_origem_id: string;
  origem_codigo: string;
  origem_nome: string;
  origem_banco: string | null;
  conta_destino_id: string;
  destino_codigo: string;
  destino_nome: string;
  destino_banco: string | null;
  linha_saida_status: string | null;
  linha_entrada_status: string | null;
  created_at: string;
};

function todayISO(): string {
  const today = new Date();
  return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
}

function firstDayOfMonthISO(): string {
  const today = new Date();
  return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-01`;
}

function formatDateBR(value: string): string {
  const [year, month, day] = value.split("-");
  return year && month && day ? `${day}/${month}/${year}` : value;
}

function formatDateTimeBR(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

function normalize(value: unknown): string {
  return String(value ?? "").trim().toLowerCase();
}

function contaLabel(conta: ContaBancariaRow): string {
  return `${conta.codigo} — ${conta.nome}`;
}

function conciliacaoLabel(row: TransferenciaRow): "CONCILIADA" | "PENDENTE" | "REGISTRADA" {
  if (!row.linha_saida_status && !row.linha_entrada_status) return "REGISTRADA";
  if (row.linha_saida_status === "CONCILIADO" && row.linha_entrada_status === "CONCILIADO") return "CONCILIADA";
  return "PENDENTE";
}

function conciliacaoClass(status: ReturnType<typeof conciliacaoLabel>): string {
  if (status === "CONCILIADA") return "border-emerald-500/30 bg-emerald-500/10 text-emerald-200";
  if (status === "PENDENTE") return "border-amber-500/30 bg-amber-500/10 text-amber-200";
  return "border-sky-500/30 bg-sky-500/10 text-sky-200";
}

export default function TransferenciasClient() {
  const te = useTenantEmpresa();
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const canFinanceiro = useMemo(() => {
    const read = te.has("financeiro.read");
    const write = te.has("financeiro.write");
    if (read === undefined || write === undefined) return undefined;
    return Boolean(read || write);
  }, [te]);

  const canWrite = useMemo(() => {
    const write = te.has("financeiro.write");
    if (write === undefined) return undefined;
    return Boolean(write);
  }, [te]);

  const effectiveEmpresaId = useMemo(() => {
    if (te.empresaId) return te.empresaId;
    if (te.empresas.length === 1) return te.empresas[0].id;
    return null;
  }, [te.empresaId, te.empresas]);

  const [startDate, setStartDate] = useState(() => searchParams.get("de") || firstDayOfMonthISO());
  const [endDate, setEndDate] = useState(() => searchParams.get("ate") || todayISO());
  const [accountFilter, setAccountFilter] = useState(() => searchParams.get("conta") || "");
  const [query, setQuery] = useState(() => searchParams.get("q") || "");

  const [contas, setContas] = useState<ContaBancariaRow[]>([]);
  const [rows, setRows] = useState<TransferenciaRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const [modalOpen, setModalOpen] = useState(false);
  const [origemId, setOrigemId] = useState("");
  const [destinoId, setDestinoId] = useState("");
  const [dataMovimento, setDataMovimento] = useState(todayISO());
  const [valor, setValor] = useState("");
  const [descricao, setDescricao] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  useEffect(() => {
    const params = new URLSearchParams();
    if (startDate) params.set("de", startDate);
    if (endDate) params.set("ate", endDate);
    if (accountFilter) params.set("conta", accountFilter);
    if (query.trim()) params.set("q", query.trim());
    const next = params.toString();
    router.replace(next ? `${pathname}?${next}` : pathname, { scroll: false });
  }, [accountFilter, endDate, pathname, query, router, startDate]);

  const reload = useCallback(async () => {
    if (typeof te.sessionUserId !== "string" || !te.tenantId || !effectiveEmpresaId || canFinanceiro !== true) return;

    if (startDate && endDate && startDate > endDate) {
      setError("A data inicial não pode ser maior que a data final.");
      setRows([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const supabase = getSupabaseBrowser();
      const today = todayISO();
      const [contasRes, saldosRes, transferenciasRes] = await Promise.all([
        supabase
          .schema("f")
          .from("conta_bancaria")
          .select("id,codigo,nome,tipo,banco,agencia,conta")
          .eq("tenant_id", te.tenantId)
          .eq("empresa_id", effectiveEmpresaId)
          .eq("ativo", true)
          .is("deleted_at", null)
          .order("nome", { ascending: true }),
        supabase.schema("f").rpc("contas_bancarias_saldos", {
          p_tenant_id: te.tenantId,
          p_empresa_ids: [effectiveEmpresaId],
          p_data_inicio: today,
          p_data_fim: today,
          p_data_referencia: today,
        }),
        supabase.schema("f").rpc("listar_transferencias_bancarias", {
          p_tenant_id: te.tenantId,
          p_empresa_id: effectiveEmpresaId,
          p_data_inicio: startDate || null,
          p_data_fim: endDate || null,
          p_conta_bancaria_id: accountFilter || null,
          p_limite: 1000,
        }),
      ]);

      if (contasRes.error) throw contasRes.error;
      if (saldosRes.error) throw saldosRes.error;
      if (transferenciasRes.error) throw transferenciasRes.error;

      type SaldoRow = { conta_bancaria_id: unknown; saldo_atual: unknown; configurada: unknown };
      const saldoByConta = new Map(
        ((saldosRes.data ?? []) as SaldoRow[]).map((saldo) => [String(saldo.conta_bancaria_id), saldo])
      );

      const contasMapeadas = (contasRes.data ?? []).map((raw) => {
        const row = raw as Record<string, unknown>;
        const saldo = saldoByConta.get(String(row.id));
        return {
          id: String(row.id),
          codigo: String(row.codigo ?? ""),
          nome: String(row.nome ?? ""),
          tipo: String(row.tipo ?? "BANCO"),
          banco: row.banco ? String(row.banco) : null,
          agencia: row.agencia ? String(row.agencia) : null,
          conta: row.conta ? String(row.conta) : null,
          saldo_atual: saldo?.saldo_atual === null || saldo?.saldo_atual === undefined ? null : Number(saldo.saldo_atual),
          configurada: Boolean(saldo?.configurada),
        } satisfies ContaBancariaRow;
      });

      const transferenciasMapeadas = (transferenciasRes.data ?? []).map((raw: unknown) => {
        const row = raw as Record<string, unknown>;
        return {
          id: String(row.id),
          data_movimento: String(row.data_movimento ?? ""),
          valor: Number(row.valor ?? 0),
          descricao: String(row.descricao ?? "Transferência entre contas"),
          status: String(row.status ?? "EFETIVADA"),
          conta_origem_id: String(row.conta_origem_id ?? ""),
          origem_codigo: String(row.origem_codigo ?? ""),
          origem_nome: String(row.origem_nome ?? ""),
          origem_banco: row.origem_banco ? String(row.origem_banco) : null,
          conta_destino_id: String(row.conta_destino_id ?? ""),
          destino_codigo: String(row.destino_codigo ?? ""),
          destino_nome: String(row.destino_nome ?? ""),
          destino_banco: row.destino_banco ? String(row.destino_banco) : null,
          linha_saida_status: row.linha_saida_status ? String(row.linha_saida_status) : null,
          linha_entrada_status: row.linha_entrada_status ? String(row.linha_entrada_status) : null,
          created_at: String(row.created_at ?? ""),
        } satisfies TransferenciaRow;
      });

      setContas(contasMapeadas);
      setRows(transferenciasMapeadas);
    } catch (caught: unknown) {
      setError(caught instanceof Error ? caught.message : "Não foi possível carregar as transferências.");
      setContas([]);
      setRows([]);
    } finally {
      setLoading(false);
    }
  }, [accountFilter, canFinanceiro, effectiveEmpresaId, endDate, startDate, te.sessionUserId, te.tenantId]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void reload();
  }, [reload]);

  const filteredRows = useMemo(() => {
    const term = normalize(query);
    if (!term) return rows;
    return rows.filter((row) =>
      normalize(
        `${row.descricao} ${row.origem_codigo} ${row.origem_nome} ${row.origem_banco ?? ""} ${row.destino_codigo} ${row.destino_nome} ${row.destino_banco ?? ""}`
      ).includes(term)
    );
  }, [query, rows]);

  const totals = useMemo(() => {
    const total = filteredRows.reduce((sum, row) => sum + row.valor, 0);
    const contasMovimentadas = new Set(filteredRows.flatMap((row) => [row.conta_origem_id, row.conta_destino_id])).size;
    const pendentes = filteredRows.filter((row) => conciliacaoLabel(row) === "PENDENTE").length;
    return { quantidade: filteredRows.length, total, contasMovimentadas, pendentes };
  }, [filteredRows]);

  const origem = useMemo(() => contas.find((conta) => conta.id === origemId) ?? null, [contas, origemId]);
  const destino = useMemo(() => contas.find((conta) => conta.id === destinoId) ?? null, [contas, destinoId]);
  const valorNumerico = parseMoneyBR(valor);
  const saldoInsuficiente = Boolean(
    origem && origem.saldo_atual !== null && Number.isFinite(valorNumerico) && valorNumerico > origem.saldo_atual
  );

  const openNew = () => {
    if (canWrite !== true) return;
    setOrigemId("");
    setDestinoId("");
    setDataMovimento(todayISO());
    setValor("");
    setDescricao("");
    setFormError(null);
    setSuccess(null);
    setModalOpen(true);
  };

  const swapAccounts = () => {
    setOrigemId(destinoId);
    setDestinoId(origemId);
  };

  const saveTransfer = async () => {
    if (!te.tenantId || !effectiveEmpresaId || canWrite !== true) return;

    if (!origemId || !destinoId) {
      setFormError("Selecione as contas de origem e destino.");
      return;
    }
    if (origemId === destinoId) {
      setFormError("As contas de origem e destino devem ser diferentes.");
      return;
    }
    if (!dataMovimento) {
      setFormError("Informe a data da transferência.");
      return;
    }
    if (!Number.isFinite(valorNumerico) || valorNumerico <= 0) {
      setFormError("Informe um valor maior que zero.");
      return;
    }
    if (descricao.trim().length > 500) {
      setFormError("A descrição deve ter no máximo 500 caracteres.");
      return;
    }

    setSaving(true);
    setFormError(null);
    try {
      const { error: rpcError } = await getSupabaseBrowser().schema("f").rpc("registrar_transferencia_bancaria", {
        p_tenant_id: te.tenantId,
        p_empresa_id: effectiveEmpresaId,
        p_conta_origem_id: origemId,
        p_conta_destino_id: destinoId,
        p_data_movimento: dataMovimento,
        p_valor: valorNumerico.toFixed(2),
        p_descricao: descricao.trim() || null,
      });
      if (rpcError) throw rpcError;

      setModalOpen(false);
      setSuccess(`Transferência de R$ ${formatMoneyBR(valorNumerico)} registrada com sucesso.`);
      await reload();
    } catch (caught: unknown) {
      setFormError(caught instanceof Error ? caught.message : "Não foi possível registrar a transferência.");
    } finally {
      setSaving(false);
    }
  };

  const clearFilters = () => {
    setStartDate(firstDayOfMonthISO());
    setEndDate(todayISO());
    setAccountFilter("");
    setQuery("");
  };

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <div className="flex items-center gap-2 text-xs text-zinc-500">
            <span>Financeiro</span>
            <span>/</span>
            <span>Caixa &amp; Bancos</span>
          </div>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight text-zinc-50">Transferências bancárias</h1>
          <p className="mt-1 max-w-3xl text-sm text-zinc-400">
            Movimente recursos entre contas da mesma empresa com saída, entrada e auditoria registradas em uma única operação.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Link
            href="/financeiro/extratos"
            className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-900"
          >
            Ver extratos
          </Link>
          <Link
            href="/financeiro/conciliacao"
            className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-900"
          >
            Conciliação
          </Link>
          <button
            type="button"
            onClick={openNew}
            disabled={canWrite !== true || !effectiveEmpresaId || contas.length < 2}
            className="rounded-md bg-zinc-100 px-4 py-2 text-sm font-semibold text-zinc-950 hover:bg-white disabled:cursor-not-allowed disabled:opacity-50"
          >
            + Nova transferência
          </button>
        </div>
      </div>

      {!effectiveEmpresaId && (
        <div className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">
          Selecione uma empresa no topo da aplicação para consultar ou registrar transferências.
        </div>
      )}

      {effectiveEmpresaId && !loading && contas.length < 2 && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">
          <span>Cadastre pelo menos duas contas bancárias ativas para realizar uma transferência.</span>
          <Link href="/financeiro/cadastros/contas-bancarias" className="font-semibold underline underline-offset-4">
            Gerenciar contas
          </Link>
        </div>
      )}

      {success && (
        <div className="flex items-center justify-between gap-3 rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-100">
          <span>{success}</span>
          <button type="button" onClick={() => setSuccess(null)} className="text-emerald-200 hover:text-white" aria-label="Fechar aviso">
            ×
          </button>
        </div>
      )}

      {error && (
        <div className="rounded-xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
          {error}
        </div>
      )}

      <section className="rounded-xl border border-zinc-800 bg-zinc-950/80 p-4 shadow-sm">
        <div className="flex flex-wrap items-end gap-3">
          <label className="block min-w-40 text-xs font-medium text-zinc-400">
            Data inicial
            <input
              type="date"
              value={startDate}
              onChange={(event) => setStartDate(event.target.value)}
              className="mt-1 block w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-zinc-600"
            />
          </label>
          <label className="block min-w-40 text-xs font-medium text-zinc-400">
            Data final
            <input
              type="date"
              value={endDate}
              onChange={(event) => setEndDate(event.target.value)}
              className="mt-1 block w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-zinc-600"
            />
          </label>
          <label className="block min-w-64 flex-1 text-xs font-medium text-zinc-400">
            Conta bancária
            <select
              value={accountFilter}
              onChange={(event) => setAccountFilter(event.target.value)}
              className="mt-1 block w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-zinc-600"
            >
              <option value="">Todas as contas</option>
              {contas.map((conta) => (
                <option key={conta.id} value={conta.id}>{contaLabel(conta)}</option>
              ))}
            </select>
          </label>
          <label className="block min-w-64 flex-1 text-xs font-medium text-zinc-400">
            Buscar
            <input
              type="search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Descrição, banco ou conta"
              className="mt-1 block w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none placeholder:text-zinc-600 focus:border-zinc-600"
            />
          </label>
          <button
            type="button"
            onClick={clearFilters}
            className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-300 hover:bg-zinc-900"
          >
            Limpar filtros
          </button>
        </div>

        <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 p-3">
            <div className="text-xs text-zinc-500">Transferências no período</div>
            <div className="mt-1 text-xl font-semibold text-zinc-100">{totals.quantidade}</div>
          </div>
          <div className="rounded-lg border border-sky-500/20 bg-sky-500/5 p-3">
            <div className="text-xs text-sky-300/80">Volume movimentado</div>
            <div className="mt-1 text-right text-xl font-semibold text-sky-100">R$ {formatMoneyBR(totals.total)}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 p-3">
            <div className="text-xs text-zinc-500">Contas movimentadas</div>
            <div className="mt-1 text-xl font-semibold text-zinc-100">{totals.contasMovimentadas}</div>
          </div>
          <div className="rounded-lg border border-amber-500/20 bg-amber-500/5 p-3">
            <div className="text-xs text-amber-300/80">Pendentes de conciliação</div>
            <div className="mt-1 text-xl font-semibold text-amber-100">{totals.pendentes}</div>
          </div>
        </div>
      </section>

      <section className="overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950/80 shadow-sm">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-zinc-800 px-4 py-3">
          <div>
            <h2 className="font-semibold text-zinc-100">Histórico de transferências</h2>
            <p className="mt-0.5 text-xs text-zinc-500">Cada registro representa as duas movimentações vinculadas da operação.</p>
          </div>
          <span className="text-xs text-zinc-500">{filteredRows.length} registro(s)</span>
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-[1100px] w-full text-sm">
            <thead className="bg-zinc-900/40 text-xs text-zinc-400">
              <tr className="text-left">
                <th className="px-4 py-3 font-medium">Data</th>
                <th className="px-4 py-3 font-medium">Origem</th>
                <th className="w-10 px-1 py-3"><span className="sr-only">Direção</span></th>
                <th className="px-4 py-3 font-medium">Destino</th>
                <th className="px-4 py-3 font-medium">Descrição</th>
                <th className="px-4 py-3 font-medium">Conciliação</th>
                <th className="px-4 py-3 text-right font-medium">Valor</th>
              </tr>
            </thead>
            <tbody>
              {loading && (
                <tr><td colSpan={7} className="px-4 py-10 text-center text-zinc-500">Carregando transferências…</td></tr>
              )}
              {!loading && filteredRows.length === 0 && (
                <tr>
                  <td colSpan={7} className="px-4 py-12 text-center">
                    <div className="font-medium text-zinc-300">Nenhuma transferência encontrada</div>
                    <div className="mt-1 text-sm text-zinc-500">Altere os filtros ou registre uma nova transferência.</div>
                  </td>
                </tr>
              )}
              {!loading && filteredRows.map((row) => {
                const conciliacao = conciliacaoLabel(row);
                return (
                  <tr key={row.id} className="border-t border-zinc-900 align-top hover:bg-zinc-900/30">
                    <td className="whitespace-nowrap px-4 py-4">
                      <div className="font-medium text-zinc-200">{formatDateBR(row.data_movimento)}</div>
                      <div className="mt-1 text-xs text-zinc-600" title={row.id}>#{row.id.slice(0, 8)}</div>
                    </td>
                    <td className="px-4 py-4">
                      <div className="font-medium text-zinc-100">{row.origem_codigo} — {row.origem_nome}</div>
                      <div className="mt-1 text-xs text-zinc-500">{row.origem_banco || "Conta interna"}</div>
                    </td>
                    <td className="px-1 py-4 text-center text-lg text-sky-300">→</td>
                    <td className="px-4 py-4">
                      <div className="font-medium text-zinc-100">{row.destino_codigo} — {row.destino_nome}</div>
                      <div className="mt-1 text-xs text-zinc-500">{row.destino_banco || "Conta interna"}</div>
                    </td>
                    <td className="max-w-sm px-4 py-4">
                      <div className="text-zinc-300">{row.descricao}</div>
                      <div className="mt-1 text-xs text-zinc-600">Registrada em {formatDateTimeBR(row.created_at)}</div>
                    </td>
                    <td className="px-4 py-4">
                      <span className={`inline-flex rounded-full border px-2 py-0.5 text-xs font-medium ${conciliacaoClass(conciliacao)}`}>
                        {conciliacao}
                      </span>
                    </td>
                    <td className="whitespace-nowrap px-4 py-4 text-right text-base font-semibold tabular-nums text-zinc-100">
                      R$ {formatMoneyBR(row.valor)}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>

      <div className="rounded-xl border border-sky-500/20 bg-sky-500/5 px-4 py-3 text-xs text-sky-100/80">
        Transferências não geram receita ou despesa e não alteram o saldo consolidado da empresa. Elas movimentam somente os saldos das contas envolvidas.
      </div>

      {modalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4" role="dialog" aria-modal="true" aria-labelledby="transferencia-title">
          <div className="max-h-[92vh] w-full max-w-3xl overflow-y-auto rounded-2xl border border-zinc-700 bg-zinc-950 shadow-2xl shadow-black/50">
            <div className="flex items-start justify-between gap-4 border-b border-zinc-800 px-5 py-4">
              <div>
                <h2 id="transferencia-title" className="text-lg font-semibold text-zinc-50">Nova transferência bancária</h2>
                <p className="mt-1 text-sm text-zinc-400">A saída e a entrada serão registradas juntas e ficarão disponíveis para conciliação.</p>
              </div>
              <button
                type="button"
                onClick={() => setModalOpen(false)}
                disabled={saving}
                className="rounded-md border border-zinc-800 px-2.5 py-1.5 text-sm text-zinc-400 hover:bg-zinc-900 hover:text-white disabled:opacity-50"
                aria-label="Fechar"
              >
                ×
              </button>
            </div>

            <div className="space-y-5 p-5">
              {formError && (
                <div className="rounded-lg border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-200">{formError}</div>
              )}

              <div className="grid grid-cols-1 items-end gap-3 md:grid-cols-[1fr_auto_1fr]">
                <label className="block text-xs font-medium text-zinc-400">
                  Conta de origem
                  <select
                    value={origemId}
                    onChange={(event) => setOrigemId(event.target.value)}
                    disabled={saving}
                    className="mt-1 block w-full rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-2.5 text-sm text-zinc-100 outline-none focus:border-sky-500 disabled:opacity-60"
                  >
                    <option value="">Selecione a origem</option>
                    {contas.map((conta) => <option key={conta.id} value={conta.id}>{contaLabel(conta)}</option>)}
                  </select>
                </label>

                <button
                  type="button"
                  onClick={swapAccounts}
                  disabled={saving || (!origemId && !destinoId)}
                  className="mb-0.5 rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-2 text-lg text-sky-300 hover:bg-zinc-800 disabled:opacity-40"
                  title="Inverter origem e destino"
                  aria-label="Inverter origem e destino"
                >
                  ⇄
                </button>

                <label className="block text-xs font-medium text-zinc-400">
                  Conta de destino
                  <select
                    value={destinoId}
                    onChange={(event) => setDestinoId(event.target.value)}
                    disabled={saving}
                    className="mt-1 block w-full rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-2.5 text-sm text-zinc-100 outline-none focus:border-sky-500 disabled:opacity-60"
                  >
                    <option value="">Selecione o destino</option>
                    {contas.filter((conta) => conta.id !== origemId).map((conta) => (
                      <option key={conta.id} value={conta.id}>{contaLabel(conta)}</option>
                    ))}
                  </select>
                </label>
              </div>

              {(origem || destino) && (
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <div className="rounded-xl border border-red-500/20 bg-red-500/5 p-3">
                    <div className="text-xs text-red-300/80">Saldo atual da origem</div>
                    <div className="mt-1 text-right text-lg font-semibold text-zinc-100">
                      {origem?.saldo_atual === null || origem?.saldo_atual === undefined ? "Não configurado" : `R$ ${formatMoneyBR(origem.saldo_atual)}`}
                    </div>
                    {origem && <div className="mt-1 truncate text-xs text-zinc-500">{contaLabel(origem)}</div>}
                  </div>
                  <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/5 p-3">
                    <div className="text-xs text-emerald-300/80">Saldo atual do destino</div>
                    <div className="mt-1 text-right text-lg font-semibold text-zinc-100">
                      {destino?.saldo_atual === null || destino?.saldo_atual === undefined ? "Não configurado" : `R$ ${formatMoneyBR(destino.saldo_atual)}`}
                    </div>
                    {destino && <div className="mt-1 truncate text-xs text-zinc-500">{contaLabel(destino)}</div>}
                  </div>
                </div>
              )}

              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <label className="block text-xs font-medium text-zinc-400">
                  Data da transferência
                  <input
                    type="date"
                    value={dataMovimento}
                    onChange={(event) => setDataMovimento(event.target.value)}
                    disabled={saving}
                    className="mt-1 block w-full rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-2.5 text-sm text-zinc-100 outline-none focus:border-sky-500 disabled:opacity-60"
                  />
                </label>
                <label className="block text-xs font-medium text-zinc-400">
                  Valor
                  <div className="relative mt-1">
                    <span className="pointer-events-none absolute inset-y-0 left-3 flex items-center text-sm text-zinc-500">R$</span>
                    <input
                      value={valor}
                      onChange={(event) => setValor(event.target.value)}
                      inputMode="decimal"
                      placeholder="0,00"
                      disabled={saving}
                      className="block w-full rounded-lg border border-zinc-700 bg-zinc-900 py-2.5 pl-10 pr-3 text-right text-sm font-medium tabular-nums text-zinc-100 outline-none placeholder:text-zinc-600 focus:border-sky-500 disabled:opacity-60"
                    />
                  </div>
                </label>
              </div>

              {saldoInsuficiente && (
                <div className="rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-sm text-amber-100">
                  O valor informado é maior que o saldo atual calculado da conta de origem. Confirme se a conta possui limite ou lançamentos ainda não conciliados.
                </div>
              )}

              <label className="block text-xs font-medium text-zinc-400">
                Descrição <span className="font-normal text-zinc-600">(opcional)</span>
                <textarea
                  value={descricao}
                  onChange={(event) => setDescricao(event.target.value)}
                  rows={3}
                  maxLength={500}
                  disabled={saving}
                  placeholder="Ex.: Reforço de caixa para pagamentos da semana"
                  className="mt-1 block w-full resize-none rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-2.5 text-sm text-zinc-100 outline-none placeholder:text-zinc-600 focus:border-sky-500 disabled:opacity-60"
                />
                <span className="mt-1 block text-right text-[11px] text-zinc-600">{descricao.length}/500</span>
              </label>

              <div className="rounded-lg border border-zinc-800 bg-zinc-900/40 p-3 text-xs leading-relaxed text-zinc-400">
                Esta operação não gera conta a pagar, conta a receber, receita ou despesa. Serão criadas duas linhas de extrato vinculadas: uma saída na origem e uma entrada no destino.
              </div>
            </div>

            <div className="flex items-center justify-end gap-2 border-t border-zinc-800 px-5 py-4">
              <button
                type="button"
                onClick={() => setModalOpen(false)}
                disabled={saving}
                className="rounded-md border border-zinc-700 bg-zinc-950 px-4 py-2 text-sm text-zinc-300 hover:bg-zinc-900 disabled:opacity-50"
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={() => void saveTransfer()}
                disabled={saving || !origemId || !destinoId || !dataMovimento || !Number.isFinite(valorNumerico) || valorNumerico <= 0}
                className="rounded-md bg-zinc-100 px-4 py-2 text-sm font-semibold text-zinc-950 hover:bg-white disabled:cursor-not-allowed disabled:opacity-50"
              >
                {saving ? "Registrando…" : "Confirmar transferência"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
