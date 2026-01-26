"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { formatDecimalBR } from "@/lib/decimal";

type ContaBancaria = { id: string; codigo: string; nome: string };

type ItemRow = {
  id: string;
  valor: number | string;
  pagamento?: {
    id: string;
    data_pagamento: string;
    forma_pagamento: string;
    valor: number | string;
    observacoes: string | null;
    conciliado_at: string | null;
    conta_bancaria?: { id: string; codigo: string; nome: string } | null;
  } | null;
  titulo_parcela?: {
    id: string;
    numero: string | null;
    vencimento_date: string;
    valor: number | string;
    valor_aberto: number | string;
    titulo?: {
      id: string;
      tipo: string;
      descricao: string | null;
      competencia_date: string | null;
      cliente_id: number | null;
      clientes?: { nome: string | null } | null;
    } | null;
  } | null;
};

type RecebimentoRow = {
  pagamentoId: string;
  data: string;
  forma: string;
  conta: string;
  conciliadoAt: string | null;
  observacoes: string | null;
  totalAplicado: number;
  itensCount: number;
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

function classForConciliacao(conciliadoAt: string | null | undefined) {
  return conciliadoAt
    ? "bg-emerald-500/15 text-emerald-200 border-emerald-500/30"
    : "bg-amber-500/15 text-amber-200 border-amber-500/30";
}

function ConciliacaoPill({ conciliadoAt }: { conciliadoAt: string | null }) {
  return (
    <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-xs ${classForConciliacao(conciliadoAt)}`}>
      {conciliadoAt ? "CONCILIADO" : "PENDENTE"}
    </span>
  );
}

export default function ContasReceberRecebimentosClient() {
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

  const [q, setQ] = useState("");
  const [startDate, setStartDate] = useState<string>("");
  const [endDate, setEndDate] = useState<string>("");
  const [contaId, setContaId] = useState<string>("");
  const [forma, setForma] = useState<string>("");
  const [conciliacao, setConciliacao] = useState<"" | "pendente" | "conciliado">("");

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [contas, setContas] = useState<ContaBancaria[]>([]);
  const [recebimentos, setRecebimentos] = useState<RecebimentoRow[]>([]);

  const [selectedPagamentoId, setSelectedPagamentoId] = useState<string | null>(null);
  const [itens, setItens] = useState<ItemRow[]>([]);
  const [itensLoading, setItensLoading] = useState(false);

  const resumo = useMemo(() => {
    const total = recebimentos.reduce((acc, r) => acc + r.totalAplicado, 0);
    const conciliado = recebimentos.filter((r) => Boolean(r.conciliadoAt)).reduce((acc, r) => acc + r.totalAplicado, 0);
    return { total, conciliado, pendente: total - conciliado, count: recebimentos.length };
  }, [recebimentos]);

  useEffect(() => {
    if (typeof te.sessionUserId !== "string") return;
    if (!te.tenantId) return;
    if (!te.empresaId && te.empresas.length !== 1) return;
    if (canFinanceiro !== true) return;

    let cancelled = false;

    const run = async () => {
      setLoading(true);
      setError(null);

      try {
        const supabase = getSupabaseBrowser();

        const { data: contasData } = await supabase
          .schema("f")
          .from("conta_bancaria")
          .select("id,codigo,nome")
          .eq("tenant_id", te.tenantId)
          .eq("ativo", true)
          .is("deleted_at", null)
          .order("nome", { ascending: true });

        if (cancelled) return;
        setContas((contasData ?? []).map((r: any) => ({ id: String(r.id), codigo: String(r.codigo), nome: String(r.nome) })));

        // Base query: payment items whose underlying title is AR.
        let query = supabase
          .schema("f")
          .from("pagamento_item")
          .select(
            [
              "id",
              "valor",
              "pagamento:pagamento_id(id,data_pagamento,forma_pagamento,valor,observacoes,conciliado_at,conta_bancaria:conta_bancaria_id(id,codigo,nome))",
              "titulo_parcela:titulo_parcela_id!inner(id,numero,vencimento_date,valor,valor_aberto,titulo:titulo_id!inner(id,tipo,descricao,competencia_date,cliente_id,clientes:cliente_id(nome)))",
            ].join(",")
          )
          .is("deleted_at", null)
          .order("created_at", { ascending: false })
          .limit(2000);

        query = query.eq("titulo.tipo", "AR");

        if (startDate) query = query.gte("pagamento.data_pagamento", startDate);
        if (endDate) query = query.lte("pagamento.data_pagamento", endDate);
        if (contaId) query = query.eq("pagamento.conta_bancaria_id", contaId);
        if (forma) query = query.eq("pagamento.forma_pagamento", forma);
        if (conciliacao === "pendente") query = query.is("pagamento.conciliado_at", null);
        if (conciliacao === "conciliado") query = query.not("pagamento.conciliado_at", "is", null);

        const term = q.trim();
        if (term) {
          query = query.or([`pagamento.observacoes.ilike.%${term}%`, `pagamento.id.eq.${term}`, `clientes.nome.ilike.%${term}%`].join(","));
        }

        const { data, error: qErr } = await query;
        if (cancelled) return;
        if (qErr) {
          setRecebimentos([]);
          setError(qErr.message ?? "Erro ao carregar recebimentos." );
          return;
        }

        const items = (data ?? []) as unknown as ItemRow[];
        const grouped = new Map<string, RecebimentoRow>();

        for (const it of items) {
          const p = it.pagamento;
          if (!p?.id) continue;
          const key = String(p.id);

          const conta = p.conta_bancaria ? `${p.conta_bancaria.codigo} — ${p.conta_bancaria.nome}` : "—";

          const prev = grouped.get(key);
          if (!prev) {
            grouped.set(key, {
              pagamentoId: key,
              data: p.data_pagamento,
              forma: p.forma_pagamento,
              conta,
              conciliadoAt: p.conciliado_at ?? null,
              observacoes: p.observacoes ?? null,
              totalAplicado: n(it.valor),
              itensCount: 1,
            });
          } else {
            prev.totalAplicado += n(it.valor);
            prev.itensCount += 1;
          }
        }

        const list = Array.from(grouped.values()).sort((a, b) => {
          if (a.data !== b.data) return b.data.localeCompare(a.data);
          return b.totalAplicado - a.totalAplicado;
        });

        setRecebimentos(list);

        if (selectedPagamentoId && !list.some((r) => r.pagamentoId === selectedPagamentoId)) {
          setSelectedPagamentoId(null);
          setItens([]);
        }
      } catch (e: unknown) {
        if (cancelled) return;
        setRecebimentos([]);
        setError(e instanceof Error ? e.message : "Erro inesperado ao carregar recebimentos." );
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [canFinanceiro, conciliacao, contaId, endDate, forma, q, selectedPagamentoId, startDate, te.empresas.length, te.empresaId, te.sessionUserId, te.tenantId]);

  useEffect(() => {
    if (!selectedPagamentoId) return;

    let cancelled = false;
    const run = async () => {
      setItensLoading(true);
      setError(null);

      try {
        const supabase = getSupabaseBrowser();
        const { data, error } = await supabase
          .schema("f")
          .from("pagamento_item")
          .select(
            [
              "id",
              "valor",
              "titulo_parcela:titulo_parcela_id!inner(id,numero,vencimento_date,valor,valor_aberto,titulo:titulo_id!inner(id,tipo,descricao,competencia_date,cliente_id,clientes:cliente_id(nome)))",
            ].join(",")
          )
          .eq("pagamento_id", selectedPagamentoId)
          .is("deleted_at", null)
          .order("created_at", { ascending: true });

        if (cancelled) return;
        if (error) {
          setItens([]);
          setError(error.message ?? "Erro ao carregar itens do recebimento." );
          return;
        }

        const all = (data ?? []) as unknown as ItemRow[];
        const arOnly = all.filter((it) => String(it.titulo_parcela?.titulo?.tipo ?? "") === "AR");
        setItens(arOnly);
      } finally {
        if (!cancelled) setItensLoading(false);
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [selectedPagamentoId]);

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Contas a Receber — Recebimentos</h1>
          <p className="text-sm text-zinc-400 mt-1">Recebimentos (via f.pagamento/f.pagamento_item) aplicados em títulos AR.</p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href="/financeiro/contas-receber/lancamentos"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Lançamentos
          </Link>
          <Link
            href="/financeiro/conciliacao"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Conciliação
          </Link>
          <Link href="/financeiro" className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm">
            Voltar
          </Link>
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-3">
        <div className="flex flex-wrap items-end gap-2">
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Buscar por observação, cliente ou id…"
            aria-label="Buscar"
            className="w-full sm:w-[420px] rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
          />

          <label className="block text-xs text-zinc-400">
            Data de
            <input
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              aria-label="Data inicial"
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
            />
          </label>
          <label className="block text-xs text-zinc-400">
            Data até
            <input
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              aria-label="Data final"
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
            />
          </label>

          <label className="block text-xs text-zinc-400">
            Conta
            <select
              value={contaId}
              onChange={(e) => setContaId(e.target.value)}
              aria-label="Conta bancária"
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
            >
              <option value="">Todas</option>
              {contas.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.codigo} — {c.nome}
                </option>
              ))}
            </select>
          </label>

          <label className="block text-xs text-zinc-400">
            Forma
            <select
              value={forma}
              onChange={(e) => setForma(e.target.value)}
              aria-label="Forma de recebimento"
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
            >
              <option value="">Todas</option>
              <option value="PIX">PIX</option>
              <option value="BOLETO">BOLETO</option>
              <option value="TRANSFERENCIA">TRANSFERÊNCIA</option>
              <option value="DINHEIRO">DINHEIRO</option>
              <option value="CARTAO">CARTÃO</option>
              <option value="OUTROS">OUTROS</option>
            </select>
          </label>

          <label className="block text-xs text-zinc-400">
            Conciliação
            <select
              value={conciliacao}
              onChange={(e) => setConciliacao(e.target.value as "" | "pendente" | "conciliado")}
              aria-label="Status de conciliação"
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
            >
              <option value="">Todos</option>
              <option value="pendente">Pendente</option>
              <option value="conciliado">Conciliado</option>
            </select>
          </label>

          <div className="flex-1" />
          <div className="text-xs text-zinc-500">
            {resumo.count} recebimento(s) · Total R$ {formatDecimalBR(resumo.total, 2)} · Conciliado R$ {formatDecimalBR(resumo.conciliado, 2)}
          </div>
        </div>

        <div className="text-xs text-zinc-600">
          Lucro Real: concilie os recebimentos e garanta aplicação por parcela para rastreabilidade.
        </div>
      </div>

      {error ? (
        <div className="rounded-xl border border-rose-900/50 bg-rose-950/20 p-4 text-rose-200 text-sm">{error}</div>
      ) : null}

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <div className="xl:col-span-2 rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
          <div className="overflow-auto">
            <table className="w-full text-sm">
              <thead className="text-xs text-zinc-400">
                <tr className="border-b border-zinc-800">
                  <th className="py-2 px-3 text-left font-medium">Data</th>
                  <th className="py-2 px-3 text-left font-medium">Conta</th>
                  <th className="py-2 px-3 text-left font-medium">Forma</th>
                  <th className="py-2 px-3 text-left font-medium">Conciliação</th>
                  <th className="py-2 px-3 text-right font-medium">Aplicado (AR)</th>
                  <th className="py-2 px-3 text-right font-medium">Itens</th>
                  <th className="py-2 px-3 text-left font-medium">Obs.</th>
                </tr>
              </thead>
              <tbody>
                {loading ? (
                  <tr>
                    <td colSpan={7} className="py-6 text-center text-zinc-500">Carregando…</td>
                  </tr>
                ) : null}

                {!loading && recebimentos.length === 0 ? (
                  <tr>
                    <td colSpan={7} className="py-6 text-center text-zinc-500">Nenhum recebimento encontrado.</td>
                  </tr>
                ) : null}

                {recebimentos.map((r) => (
                  <tr
                    key={r.pagamentoId}
                    className={
                      selectedPagamentoId === r.pagamentoId
                        ? "border-b border-zinc-900/70 bg-zinc-900/40"
                        : "border-b border-zinc-900/70 hover:bg-zinc-900/30"
                    }
                  >
                    <td className="py-2 px-3 whitespace-nowrap">
                      <button type="button" onClick={() => setSelectedPagamentoId(r.pagamentoId)} className="text-left" title={r.pagamentoId}>
                        {formatDateBR(r.data)}
                      </button>
                    </td>
                    <td className="py-2 px-3">{r.conta}</td>
                    <td className="py-2 px-3">{r.forma}</td>
                    <td className="py-2 px-3"><ConciliacaoPill conciliadoAt={r.conciliadoAt} /></td>
                    <td className="py-2 px-3 text-right tabular-nums font-medium">R$ {formatDecimalBR(r.totalAplicado, 2)}</td>
                    <td className="py-2 px-3 text-right tabular-nums">{r.itensCount}</td>
                    <td className="py-2 px-3 max-w-[360px] truncate text-zinc-300">{r.observacoes ?? ""}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="text-sm font-semibold">Itens do recebimento</div>
          <div className="text-xs text-zinc-500 mt-1">Aplicações em parcelas AR.</div>

          {!selectedPagamentoId ? (
            <div className="mt-4 text-sm text-zinc-500">Selecione um recebimento para ver os itens.</div>
          ) : (
            <div className="mt-4 space-y-3">
              <div className="rounded-lg border border-zinc-800 p-3">
                <div className="text-xs text-zinc-500">Pagamento</div>
                <div className="mt-1 text-sm text-zinc-100 break-all">{selectedPagamentoId}</div>
              </div>

              <div className="rounded-lg border border-zinc-800 p-3">
                <div className="text-xs text-zinc-400">Itens</div>
                {itensLoading ? <div className="mt-2 text-sm text-zinc-500">Carregando itens…</div> : null}

                {!itensLoading && itens.length === 0 ? (
                  <div className="mt-2 text-sm text-zinc-500">Sem itens AR vinculados (ou sem acesso).</div>
                ) : null}

                {!itensLoading && itens.length > 0 ? (
                  <div className="mt-2 space-y-2 text-sm">
                    {itens.map((it) => {
                      const cliente = it.titulo_parcela?.titulo?.clientes?.nome ?? "—";
                      const comp = it.titulo_parcela?.titulo?.competencia_date ?? null;
                      const venc = it.titulo_parcela?.vencimento_date ?? null;
                      const parcelaNum = it.titulo_parcela?.numero ?? "—";
                      return (
                        <div key={it.id} className="rounded-md border border-zinc-900 p-2">
                          <div className="flex items-center justify-between gap-3">
                            <div className="min-w-0">
                              <div className="truncate text-zinc-200">{cliente}</div>
                              <div className="text-xs text-zinc-500">Comp.: {formatDateBR(comp)} · Venc.: {formatDateBR(venc)} · Parcela: {parcelaNum}</div>
                            </div>
                            <div className="tabular-nums text-zinc-200 whitespace-nowrap">R$ {formatDecimalBR(n(it.valor), 2)}</div>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                ) : null}
              </div>

              <div className="text-xs text-zinc-600">Se houver diferença entre pagamento e aplicado, revise itens/parcelas vinculadas.</div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
