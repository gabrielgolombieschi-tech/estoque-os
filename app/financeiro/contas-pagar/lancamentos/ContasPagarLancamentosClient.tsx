"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { formatDecimalBR } from "@/lib/decimal";

type TabKey = "aberto" | "sem_motivo" | "agendamentos";

type ApAgingDetalheRow = {
  titulo_id: string;
  parcela_id: string;
  parcela_numero: string | null;
  fornecedor_id: number | null;
  fornecedor_nome: string | null;
  motivo_codigo: string | null;
  motivo_nome: string | null;
  vencimento_date: string | null;
  dias_atraso: number | string | null;
  valor_parcela: number | string | null;
  valor_aberto: number | string | null;
  status: "PENDENTE" | "APROVADO" | "AGENDADO" | "PAGO" | "CANCELADO" | string | null;
  emissao_date: string | null;
  competencia_date: string | null;
};

type SemMotivoRow = {
  fornecedor_id: number | null;
  fornecedor_nome: string | null;
  qtd_titulos_sem_motivo: number | string | null;
  total_aberto: number | string | null;
};

type AgendamentoRow = {
  id: string;
  data_prevista: string;
  forma_pagamento: string;
  valor_previsto: number | string;
  observacoes: string | null;
  titulo_id: string;
  titulo?: {
    id: string;
    status: string;
    fornecedor_id: number | null;
    fornecedores?: { nome: string | null } | null;
    descricao: string | null;
    competencia_date: string | null;
    emissao_date: string | null;
  } | null;
  conta_bancaria?: { nome: string | null; banco_nome: string | null } | null;
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

function classForStatus(status: string | null | undefined) {
  const s = String(status ?? "").toUpperCase();
  if (s === "PENDENTE") return "bg-amber-500/15 text-amber-200 border-amber-500/30";
  if (s === "APROVADO") return "bg-sky-500/15 text-sky-200 border-sky-500/30";
  if (s === "AGENDADO") return "bg-emerald-500/15 text-emerald-200 border-emerald-500/30";
  if (s === "PAGO") return "bg-zinc-500/15 text-zinc-200 border-zinc-500/30";
  if (s === "CANCELADO") return "bg-rose-500/15 text-rose-200 border-rose-500/30";
  return "bg-zinc-500/10 text-zinc-200 border-zinc-500/20";
}

function Pill({ label, status }: { label: string; status?: string | null }) {
  return (
    <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-xs ${classForStatus(status)}`}>{label}</span>
  );
}

export default function ContasPagarLancamentosClient() {
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

  const [tab, setTab] = useState<TabKey>("aberto");

  // filtros (tab: aberto)
  const [q, setQ] = useState("");
  const [status, setStatus] = useState<string>("ABERTOS");
  const [onlyOverdue, setOnlyOverdue] = useState(false);
  const [onlySemMotivo, setOnlySemMotivo] = useState(false);
  const [orderBy, setOrderBy] = useState<"vencimento" | "atraso">("vencimento");
  const [startDate, setStartDate] = useState<string>("");
  const [endDate, setEndDate] = useState<string>("");

  // paginação
  const [page, setPage] = useState(1);
  const pageSize = 50;

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [rows, setRows] = useState<ApAgingDetalheRow[]>([]);
  const [totalCount, setTotalCount] = useState<number | null>(null);

  const [semMotivoRows, setSemMotivoRows] = useState<SemMotivoRow[]>([]);
  const [agendamentos, setAgendamentos] = useState<AgendamentoRow[]>([]);

  useEffect(() => {
    setPage(1);
  }, [q, status, onlyOverdue, onlySemMotivo, orderBy, startDate, endDate, tab]);

  useEffect(() => {
    if (typeof te.sessionUserId !== "string") return;
    if (!te.tenantId) return;
    if (!te.empresaId && te.empresas.length !== 1) return;
    if (canFinanceiro !== true) return;

    let cancelled = false;

    const run = async () => {
      setLoading(true);
      setError(null);

      const supabase = getSupabaseBrowser();

      try {
        if (tab === "aberto") {
          let query = supabase
            .schema("f")
            .from("r_ap_aging_detalhe")
            .select(
              "titulo_id,parcela_id,parcela_numero,fornecedor_id,fornecedor_nome,motivo_codigo,motivo_nome,vencimento_date,dias_atraso,valor_parcela,valor_aberto,status,emissao_date,competencia_date",
              { count: "exact" }
            );

          const term = q.trim();
          if (term) {
            // Busca simples por fornecedor/motivo/numero/titulo_id
            query = query.or(
              [
                `fornecedor_nome.ilike.%${term}%`,
                `motivo_nome.ilike.%${term}%`,
                `motivo_codigo.ilike.%${term}%`,
                `parcela_numero.ilike.%${term}%`,
                `titulo_id.eq.${term}`,
              ].join(",")
            );
          }

          if (startDate) query = query.gte("vencimento_date", startDate);
          if (endDate) query = query.lte("vencimento_date", endDate);

          if (onlyOverdue) query = query.gte("dias_atraso", 0);

          if (onlySemMotivo) {
            query = query.or("motivo_codigo.eq.NAO_CLASSIFICADO,motivo_codigo.is.null");
          }

          // ABERTOS (default): PENDENTE/APROVADO/AGENDADO
          if (status === "ABERTOS") {
            query = query.in("status", ["PENDENTE", "APROVADO", "AGENDADO"]);
          } else if (status && status !== "TODOS") {
            query = query.eq("status", status);
          }

          query =
            orderBy === "atraso"
              ? query.order("dias_atraso", { ascending: false })
              : query.order("vencimento_date", { ascending: true });

          const from = (page - 1) * pageSize;
          const to = from + pageSize - 1;
          query = query.range(from, to);

          const { data, error: qErr, count } = await query;

          if (cancelled) return;
          if (qErr) {
            setError(qErr.message ?? "Erro ao carregar lançamentos.");
            setRows([]);
            setTotalCount(null);
            return;
          }

          setRows((data ?? []) as ApAgingDetalheRow[]);
          setTotalCount(typeof count === "number" ? count : null);
          return;
        }

        if (tab === "sem_motivo") {
          const { data, error: qErr } = await supabase
            .schema("f")
            .from("r_titulos_sem_motivo_por_fornecedor")
            .select("fornecedor_id,fornecedor_nome,qtd_titulos_sem_motivo,total_aberto")
            .order("total_aberto", { ascending: false })
            .limit(50);

          if (cancelled) return;
          if (qErr) {
            setError(qErr.message ?? "Erro ao carregar pendências.");
            setSemMotivoRows([]);
            return;
          }

          const term = q.trim().toLowerCase();
          const list = (data ?? []) as SemMotivoRow[];
          const filtered = term
            ? list.filter((r) => String(r.fornecedor_nome ?? "").toLowerCase().includes(term))
            : list;

          setSemMotivoRows(filtered);
          return;
        }

        // tab === agendamentos
        // Observação: este trecho usa relações FK para "titulo" e "conta_bancaria".
        const { data, error: qErr } = await supabase
          .schema("f")
          .from("titulo_agendamento")
          .select(
            [
              "id",
              "data_prevista",
              "forma_pagamento",
              "valor_previsto",
              "observacoes",
              "titulo_id",
              "titulo:titulo_id(id,status,descricao,competencia_date,emissao_date,fornecedores:fornecedor_id(nome))",
              "conta_bancaria:conta_bancaria_id(nome,banco_nome)",
            ].join(",")
          )
          .is("deleted_at", null)
          .order("data_prevista", { ascending: true })
          .limit(80);

        if (cancelled) return;
        if (qErr) {
          setError(qErr.message ?? "Erro ao carregar agendamentos.");
          setAgendamentos([]);
          return;
        }

        const term = q.trim().toLowerCase();
        const list = (data ?? []) as unknown as AgendamentoRow[];
        const filtered = term
          ? list.filter((r) => {
              const forn = r.titulo?.fornecedores?.nome ?? "";
              const desc = r.titulo?.descricao ?? "";
              return (
                String(forn).toLowerCase().includes(term) ||
                String(desc).toLowerCase().includes(term) ||
                String(r.forma_pagamento ?? "").toLowerCase().includes(term)
              );
            })
          : list;

        setAgendamentos(filtered);
      } catch (e: unknown) {
        if (cancelled) return;
        setError(e instanceof Error ? e.message : "Erro inesperado ao carregar dados.");
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    void run();

    return () => {
      cancelled = true;
    };
  }, [canFinanceiro, endDate, onlyOverdue, onlySemMotivo, orderBy, page, q, startDate, status, tab, te.empresas.length, te.empresaId, te.sessionUserId, te.tenantId]);

  const resumo = useMemo(() => {
    const totalAberto = rows.reduce((acc, r) => acc + n(r.valor_aberto), 0);
    const vencido = rows.reduce((acc, r) => (n(r.dias_atraso) >= 0 ? acc + n(r.valor_aberto) : acc), 0);
    const aVencer = totalAberto - vencido;
    const semMotivo = rows.reduce(
      (acc, r) => (String(r.motivo_codigo ?? "").toUpperCase() === "NAO_CLASSIFICADO" ? acc + n(r.valor_aberto) : acc),
      0
    );
    return { totalAberto, vencido, aVencer, semMotivo };
  }, [rows]);

  const tabs: { key: TabKey; label: string; hint: string }[] = [
    { key: "aberto", label: "Em aberto", hint: "Parcelas AP com valor em aberto" },
    { key: "sem_motivo", label: "Sem motivo", hint: "Pendências de classificação" },
    { key: "agendamentos", label: "Agendamentos", hint: "Pagamentos previstos" },
  ];

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Contas a Pagar — Lançamentos</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Rotina Lucro Real: competência correta, classificação (motivo/plano/centro) e previsibilidade de caixa.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <Link
            href="/financeiro/contas-pagar/aprovacoes"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Aprovações
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
        <div className="flex flex-wrap items-center gap-2">
          {tabs.map((t) => (
            <button
              key={t.key}
              type="button"
              onClick={() => setTab(t.key)}
              className={
                tab === t.key
                  ? "px-3 py-1.5 rounded-md bg-zinc-100 text-zinc-900 text-sm font-medium"
                  : "px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
              }
              title={t.hint}
            >
              {t.label}
            </button>
          ))}

          <div className="flex-1" />

          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={tab === "agendamentos" ? "Buscar fornecedor/descrição/forma…" : "Buscar fornecedor/motivo…"}
            aria-label="Buscar"
            className="w-full sm:w-[360px] rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
          />
        </div>

        {tab === "aberto" ? (
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-3">
            <div className="lg:col-span-9 grid grid-cols-1 md:grid-cols-2 xl:grid-cols-6 gap-2">
              <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                <div className="text-xs text-zinc-500">Em aberto (lista)</div>
                <div className="mt-1 text-lg font-semibold tabular-nums">R$ {formatDecimalBR(resumo.totalAberto, 2)}</div>
              </div>
              <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                <div className="text-xs text-zinc-500">Vencido</div>
                <div className="mt-1 text-lg font-semibold tabular-nums">R$ {formatDecimalBR(resumo.vencido, 2)}</div>
              </div>
              <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                <div className="text-xs text-zinc-500">A vencer</div>
                <div className="mt-1 text-lg font-semibold tabular-nums">R$ {formatDecimalBR(resumo.aVencer, 2)}</div>
              </div>
              <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                <div className="text-xs text-zinc-500">Sem motivo (na lista)</div>
                <div className="mt-1 text-lg font-semibold tabular-nums">R$ {formatDecimalBR(resumo.semMotivo, 2)}</div>
              </div>
              <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
                <div className="text-xs text-zinc-500">Registros</div>
                <div className="mt-1 text-lg font-semibold tabular-nums">{totalCount ?? "—"}</div>
              </div>
            </div>

            <div className="lg:col-span-3 rounded-lg border border-zinc-800 bg-zinc-950 p-3 space-y-2">
              <div className="text-sm font-semibold">Filtros</div>

              <label className="block text-xs text-zinc-400">
                Status
                <select
                  value={status}
                  onChange={(e) => setStatus(e.target.value)}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                  aria-label="Status"
                >
                  <option value="ABERTOS">Abertos (PENDENTE/APROVADO/AGENDADO)</option>
                  <option value="PENDENTE">PENDENTE</option>
                  <option value="APROVADO">APROVADO</option>
                  <option value="AGENDADO">AGENDADO</option>
                  <option value="TODOS">Todos (apenas em aberto na view)</option>
                </select>
              </label>

              <div className="grid grid-cols-2 gap-2">
                <label className="block text-xs text-zinc-400">
                  Venc. de
                  <input
                    type="date"
                    value={startDate}
                    onChange={(e) => setStartDate(e.target.value)}
                    aria-label="Vencimento inicial"
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                  />
                </label>
                <label className="block text-xs text-zinc-400">
                  Venc. até
                  <input
                    type="date"
                    value={endDate}
                    onChange={(e) => setEndDate(e.target.value)}
                    aria-label="Vencimento final"
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                  />
                </label>
              </div>

              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={onlyOverdue}
                  onChange={(e) => setOnlyOverdue(e.target.checked)}
                  className="accent-zinc-200"
                />
                <span>Somente vencidos</span>
              </label>

              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={onlySemMotivo}
                  onChange={(e) => setOnlySemMotivo(e.target.checked)}
                  className="accent-zinc-200"
                />
                <span>Somente sem motivo</span>
              </label>

              <label className="block text-xs text-zinc-400">
                Ordenar
                <select
                  value={orderBy}
                  onChange={(e) => setOrderBy(e.target.value as any)}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                  aria-label="Ordenação"
                >
                  <option value="vencimento">Vencimento (asc)</option>
                  <option value="atraso">Maior atraso (desc)</option>
                </select>
              </label>

              <div className="text-xs text-zinc-500">
                Nota: esta tela usa a view `f.r_ap_aging_detalhe` (parcelas com valor em aberto).
              </div>
            </div>
          </div>
        ) : null}
      </div>

      {error ? (
        <div className="rounded-xl border border-rose-900/50 bg-rose-950/20 p-4 text-rose-200 text-sm">{error}</div>
      ) : null}

      {tab === "aberto" ? (
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
          <div className="overflow-auto">
            <table className="w-full text-sm">
              <thead className="text-xs text-zinc-400">
                <tr className="border-b border-zinc-800">
                  <th className="py-2 px-3 text-left font-medium">Venc.</th>
                  <th className="py-2 px-3 text-left font-medium">Atraso</th>
                  <th className="py-2 px-3 text-left font-medium">Fornecedor</th>
                  <th className="py-2 px-3 text-left font-medium">Motivo</th>
                  <th className="py-2 px-3 text-left font-medium">Status</th>
                  <th className="py-2 px-3 text-left font-medium">Compet.</th>
                  <th className="py-2 px-3 text-right font-medium">Parcela</th>
                  <th className="py-2 px-3 text-right font-medium">Valor</th>
                  <th className="py-2 px-3 text-right font-medium">Aberto</th>
                </tr>
              </thead>
              <tbody>
                {loading ? (
                  <tr>
                    <td colSpan={9} className="py-6 text-center text-zinc-500">
                      Carregando…
                    </td>
                  </tr>
                ) : null}

                {!loading && rows.length === 0 ? (
                  <tr>
                    <td colSpan={9} className="py-6 text-center text-zinc-500">
                      Nenhum lançamento encontrado para os filtros.
                    </td>
                  </tr>
                ) : null}

                {rows.map((r) => {
                  const atraso = n(r.dias_atraso);
                  const isOverdue = atraso >= 0;
                  const motivoCodigo = String(r.motivo_codigo ?? "").toUpperCase();
                  return (
                    <tr key={r.parcela_id} className="border-b border-zinc-900/70 hover:bg-zinc-900/40">
                      <td className="py-2 px-3 whitespace-nowrap">{formatDateBR(r.vencimento_date)}</td>
                      <td className="py-2 px-3 whitespace-nowrap">
                        {isOverdue ? <span className="text-rose-300">{atraso}d</span> : <span className="text-zinc-500">—</span>}
                      </td>
                      <td className="py-2 px-3 max-w-[320px] truncate">{r.fornecedor_nome ?? "—"}</td>
                      <td className="py-2 px-3 max-w-[320px] truncate">
                        {motivoCodigo === "NAO_CLASSIFICADO" ? (
                          <span className="text-amber-200">NAO CLASSIFICADO</span>
                        ) : (
                          <span className="text-zinc-200">
                            {r.motivo_codigo ? `${r.motivo_codigo} — ${r.motivo_nome ?? ""}` : r.motivo_nome ?? "—"}
                          </span>
                        )}
                      </td>
                      <td className="py-2 px-3">
                        <Pill label={String(r.status ?? "—")} status={String(r.status ?? "")} />
                      </td>
                      <td className="py-2 px-3 whitespace-nowrap">{formatDateBR(r.competencia_date)}</td>
                      <td className="py-2 px-3 text-right tabular-nums">{r.parcela_numero ?? "—"}</td>
                      <td className="py-2 px-3 text-right tabular-nums">R$ {formatDecimalBR(n(r.valor_parcela), 2)}</td>
                      <td className="py-2 px-3 text-right tabular-nums font-medium">R$ {formatDecimalBR(n(r.valor_aberto), 2)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          <div className="flex items-center justify-between gap-3 p-3 text-sm">
            <div className="text-zinc-500">
              Página {page}
              {typeof totalCount === "number" ? ` · ${totalCount} registros` : ""}
            </div>
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => setPage((p) => Math.max(1, p - 1))}
                disabled={page <= 1 || loading}
                className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 disabled:opacity-50"
              >
                Anterior
              </button>
              <button
                type="button"
                onClick={() => setPage((p) => p + 1)}
                disabled={loading || (typeof totalCount === "number" && page * pageSize >= totalCount)}
                className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 disabled:opacity-50"
              >
                Próxima
              </button>
            </div>
          </div>
        </div>
      ) : null}

      {tab === "sem_motivo" ? (
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-sm font-semibold">Pendências de classificação</div>
              <div className="text-xs text-zinc-500 mt-1">Fornecedores com AP em aberto sem motivo de compra</div>
            </div>
            <Link href="/financeiro/contas-pagar/aprovacoes" className="text-sm text-zinc-200 hover:text-white">
              Ir para aprovações
            </Link>
          </div>

          <div className="mt-4 overflow-auto">
            <table className="w-full text-sm">
              <thead className="text-xs text-zinc-400">
                <tr className="border-b border-zinc-800">
                  <th className="py-2 text-left font-medium">Fornecedor</th>
                  <th className="py-2 text-right font-medium">Qtd títulos</th>
                  <th className="py-2 text-right font-medium">Total aberto</th>
                </tr>
              </thead>
              <tbody>
                {loading ? (
                  <tr>
                    <td colSpan={3} className="py-6 text-center text-zinc-500">
                      Carregando…
                    </td>
                  </tr>
                ) : null}

                {!loading && semMotivoRows.length === 0 ? (
                  <tr>
                    <td colSpan={3} className="py-6 text-center text-zinc-500">
                      Nenhuma pendência encontrada.
                    </td>
                  </tr>
                ) : null}

                {semMotivoRows.map((r, idx) => (
                  <tr key={`${r.fornecedor_id ?? "x"}-${idx}`} className="border-b border-zinc-900/70">
                    <td className="py-2 pr-2">{r.fornecedor_nome ?? "—"}</td>
                    <td className="py-2 text-right tabular-nums">{n(r.qtd_titulos_sem_motivo)}</td>
                    <td className="py-2 text-right tabular-nums font-medium">R$ {formatDecimalBR(n(r.total_aberto), 2)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ) : null}

      {tab === "agendamentos" ? (
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-sm font-semibold">Agendamentos</div>
              <div className="text-xs text-zinc-500 mt-1">Pagamentos previstos (para controle de caixa)</div>
            </div>
            <Link href="/financeiro/extratos" className="text-sm text-zinc-200 hover:text-white">
              Abrir extratos
            </Link>
          </div>

          <div className="mt-4 overflow-auto">
            <table className="w-full text-sm">
              <thead className="text-xs text-zinc-400">
                <tr className="border-b border-zinc-800">
                  <th className="py-2 text-left font-medium">Data</th>
                  <th className="py-2 text-left font-medium">Fornecedor</th>
                  <th className="py-2 text-left font-medium">Forma</th>
                  <th className="py-2 text-left font-medium">Conta</th>
                  <th className="py-2 text-right font-medium">Valor</th>
                  <th className="py-2 text-left font-medium">Obs.</th>
                </tr>
              </thead>
              <tbody>
                {loading ? (
                  <tr>
                    <td colSpan={6} className="py-6 text-center text-zinc-500">
                      Carregando…
                    </td>
                  </tr>
                ) : null}

                {!loading && agendamentos.length === 0 ? (
                  <tr>
                    <td colSpan={6} className="py-6 text-center text-zinc-500">
                      Nenhum agendamento encontrado.
                    </td>
                  </tr>
                ) : null}

                {agendamentos.map((r) => (
                  <tr key={r.id} className="border-b border-zinc-900/70">
                    <td className="py-2 pr-2 whitespace-nowrap">{formatDateBR(r.data_prevista)}</td>
                    <td className="py-2 pr-2">{r.titulo?.fornecedores?.nome ?? "—"}</td>
                    <td className="py-2 pr-2">{r.forma_pagamento}</td>
                    <td className="py-2 pr-2">
                      {r.conta_bancaria?.nome ?? r.conta_bancaria?.banco_nome ?? "Conta"}
                    </td>
                    <td className="py-2 text-right tabular-nums font-medium">R$ {formatDecimalBR(n(r.valor_previsto), 2)}</td>
                    <td className="py-2 pr-2 max-w-[360px] truncate text-zinc-300">{r.observacoes ?? r.titulo?.descricao ?? ""}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ) : null}
    </div>
  );
}
