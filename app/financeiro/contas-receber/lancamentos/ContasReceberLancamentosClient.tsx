"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { formatDecimalBR } from "@/lib/decimal";
import { applyTenantEmpresa } from "@/lib/db/scopes";

type ParcelaRow = {
  id: string;
  numero: string | null;
  vencimento_date: string;
  valor: number | string;
  valor_aberto: number | string;
  titulo?: {
    id: string;
    tipo: string;
    status: string;
    descricao: string | null;
    emissao_date: string | null;
    competencia_date: string | null;
    cliente_id: number | null;
    clientes?: { nome: string | null } | null;
  } | null;
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

function daysBetween(dueIso: string): number {
  const d = new Date(`${dueIso}T00:00:00`);
  const today = new Date();
  const today0 = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const diff = today0.getTime() - d.getTime();
  return Math.floor(diff / (1000 * 60 * 60 * 24));
}

function classForStatus(status: string) {
  const s = String(status ?? "").toUpperCase();
  if (s === "PENDENTE") return "bg-amber-500/15 text-amber-200 border-amber-500/30";
  if (s === "APROVADO") return "bg-sky-500/15 text-sky-200 border-sky-500/30";
  if (s === "AGENDADO") return "bg-emerald-500/15 text-emerald-200 border-emerald-500/30";
  if (s === "PAGO") return "bg-zinc-500/15 text-zinc-200 border-zinc-500/30";
  if (s === "CANCELADO") return "bg-rose-500/15 text-rose-200 border-rose-500/30";
  return "bg-zinc-500/10 text-zinc-200 border-zinc-500/20";
}

function Pill({ label }: { label: string }) {
  return <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-xs ${classForStatus(label)}`}>{label}</span>;
}

export default function ContasReceberLancamentosClient() {
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

  const [tab, setTab] = useState<"aberto" | "baixado">("aberto");
  const [q, setQ] = useState("");
  const [onlyOverdue, setOnlyOverdue] = useState(false);
  const [status, setStatus] = useState<string>("");
  const [startDue, setStartDue] = useState<string>("");
  const [endDue, setEndDue] = useState<string>("");

  const [page, setPage] = useState(0);
  const pageSize = 50;

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [rows, setRows] = useState<ParcelaRow[]>([]);
  const [total, setTotal] = useState<number>(0);
  const warnedMissingContextRef = useRef(false);

  const resumo = useMemo(() => {
    const totalValor = rows.reduce((acc, r) => acc + n(r.valor), 0);
    const totalAberto = rows.reduce((acc, r) => acc + n(r.valor_aberto), 0);
    const totalRecebido = totalValor - totalAberto;
    const vencidos = rows.filter((r) => daysBetween(r.vencimento_date) >= 0).reduce((acc, r) => acc + n(r.valor_aberto), 0);
    return { totalValor, totalAberto, totalRecebido, vencidos };
  }, [rows]);

  useEffect(() => {
    setPage(0);
  }, [tab, q, onlyOverdue, status, startDue, endDue]);

  useEffect(() => {
    if (typeof te.sessionUserId !== "string") return;
    const tenantId = te.tenantId ?? null;
    const empresaId = te.empresaId ?? (te.empresas.length === 1 ? te.empresas[0]?.id : null);
    if (!tenantId || !empresaId) {
      if (process.env.NODE_ENV !== "production" && !warnedMissingContextRef.current) {
        console.debug("[financeiro] Contexto ausente ao carregar lançamentos AR", {
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

      try {
        const supabase = getSupabaseBrowser();

        let query = applyTenantEmpresa(
          supabase
            .schema("f")
            .from("titulo_parcela")
            .select(
              [
                "id",
                "numero",
                "vencimento_date",
                "valor",
                "valor_aberto",
                "titulo:titulo_id!inner(id,empresa_id,tipo,status,descricao,emissao_date,competencia_date,cliente_id,clientes:cliente_id(nome))",
              ].join(","),
              { count: "exact" }
            ),
          tenantId,
          empresaId
        )
          .is("deleted_at", null)
          .order("vencimento_date", { ascending: true });

        // filter: only AR
        query = query.eq("titulo.tipo", "AR");
        query = query.eq("titulo.empresa_id", empresaId);

        // tab filter
        if (tab === "aberto") {
          query = query.gt("valor_aberto", 0);
          query = query.in("titulo.status", ["PENDENTE", "APROVADO", "AGENDADO"]);
        } else {
          query = query.lte("valor_aberto", 0);
          query = query.eq("titulo.status", "PAGO");
        }

        if (status) query = query.eq("titulo.status", status);
        if (startDue) query = query.gte("vencimento_date", startDue);
        if (endDue) query = query.lte("vencimento_date", endDue);

        if (onlyOverdue) {
          // daysBetween >= 0 -> vencimento_date <= current_date
          query = query.lte("vencimento_date", new Date().toISOString().slice(0, 10));
          query = query.gt("valor_aberto", 0);
        }

        const term = q.trim();
        if (term) {
          // best-effort search across description and client name; if PostgREST doesn't support, it will error and we fall back.
          query = query.or(
            [
              `titulo.descricao.ilike.%${term}%`,
              `titulo.id.eq.${term}`,
              `numero.ilike.%${term}%`,
              `clientes.nome.ilike.%${term}%`,
            ].join(",")
          );
        }

        const from = page * pageSize;
        const to = from + pageSize - 1;
        const { data, error: qErr, count } = await query.range(from, to);
        if (cancelled) return;
        if (qErr) {
          setRows([]);
          setTotal(0);
          setError(qErr.message ?? "Erro ao carregar lançamentos (AR)." );
          return;
        }

        setRows((data ?? []) as unknown as ParcelaRow[]);
        setTotal(typeof count === "number" ? count : 0);
      } catch (e: unknown) {
        if (cancelled) return;
        setRows([]);
        setTotal(0);
        setError(e instanceof Error ? e.message : "Erro inesperado ao carregar lançamentos (AR)." );
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [canFinanceiro, endDue, onlyOverdue, page, q, startDue, status, tab, te.empresas, te.empresaId, te.sessionUserId, te.tenantId]);

  const totalPages = Math.max(1, Math.ceil(total / pageSize));

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Contas a Receber — Lançamentos</h1>
          <p className="text-sm text-zinc-400 mt-1">Títulos e parcelas (tipo AR) com foco em competência, vencimento e saldo.</p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href="/financeiro/contas-receber/recebimentos"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Recebimentos
          </Link>
          <Link href="/financeiro" className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm">
            Voltar
          </Link>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={() => setTab("aberto")}
          className={
            tab === "aberto"
              ? "px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 text-sm font-medium"
              : "px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          }
        >
          Em aberto
        </button>
        <button
          type="button"
          onClick={() => setTab("baixado")}
          className={
            tab === "baixado"
              ? "px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 text-sm font-medium"
              : "px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          }
        >
          Recebidos
        </button>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-3">
        <div className="flex flex-wrap items-end gap-2">
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Buscar por cliente, descrição, parcela ou título…"
            aria-label="Buscar"
            className="w-full sm:w-[420px] rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
          />

          <label className="block text-xs text-zinc-400">
            Status
            <select
              value={status}
              onChange={(e) => setStatus(e.target.value)}
              aria-label="Status"
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
            >
              <option value="">Todos</option>
              <option value="PENDENTE">PENDENTE</option>
              <option value="APROVADO">APROVADO</option>
              <option value="AGENDADO">AGENDADO</option>
              <option value="PAGO">PAGO</option>
              <option value="CANCELADO">CANCELADO</option>
            </select>
          </label>

          <label className="block text-xs text-zinc-400">
            Venc. de
            <input
              type="date"
              value={startDue}
              onChange={(e) => setStartDue(e.target.value)}
              aria-label="Vencimento inicial"
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
            />
          </label>
          <label className="block text-xs text-zinc-400">
            Venc. até
            <input
              type="date"
              value={endDue}
              onChange={(e) => setEndDue(e.target.value)}
              aria-label="Vencimento final"
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
            />
          </label>

          <label className="flex items-center gap-2 text-sm mb-1">
            <input
              type="checkbox"
              checked={onlyOverdue}
              onChange={(e) => setOnlyOverdue(e.target.checked)}
              className="accent-zinc-200"
            />
            <span>Somente vencidos</span>
          </label>

          <div className="flex-1" />
          <div className="text-xs text-zinc-500 whitespace-nowrap">
            Página {page + 1}/{totalPages} · Itens {total}
          </div>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div className="rounded-lg border border-zinc-800 p-3">
            <div className="text-xs text-zinc-500">Valor</div>
            <div className="mt-1 text-lg font-semibold">R$ {formatDecimalBR(resumo.totalValor, 2)}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 p-3">
            <div className="text-xs text-zinc-500">Em aberto</div>
            <div className="mt-1 text-lg font-semibold">R$ {formatDecimalBR(resumo.totalAberto, 2)}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 p-3">
            <div className="text-xs text-zinc-500">Recebido</div>
            <div className="mt-1 text-lg font-semibold">R$ {formatDecimalBR(resumo.totalRecebido, 2)}</div>
          </div>
          <div className="rounded-lg border border-zinc-800 p-3">
            <div className="text-xs text-zinc-500">Vencidos (saldo)</div>
            <div className="mt-1 text-lg font-semibold">R$ {formatDecimalBR(resumo.vencidos, 2)}</div>
          </div>
        </div>

        <div className="text-xs text-zinc-600">
          Lucro Real: confira competência (1º dia do mês) e mantenha baixas bem amarradas aos recebimentos.
        </div>
      </div>

      {error ? (
        <div className="rounded-xl border border-rose-900/50 bg-rose-950/20 p-4 text-rose-200 text-sm">{error}</div>
      ) : null}

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
        <div className="overflow-auto">
          <table className="w-full text-sm">
            <thead className="text-xs text-zinc-400">
              <tr className="border-b border-zinc-800">
                <th className="py-2 px-3 text-left font-medium">Cliente</th>
                <th className="py-2 px-3 text-left font-medium">Título/Desc.</th>
                <th className="py-2 px-3 text-left font-medium">Status</th>
                <th className="py-2 px-3 text-left font-medium">Competência</th>
                <th className="py-2 px-3 text-left font-medium">Vencimento</th>
                <th className="py-2 px-3 text-right font-medium">Parcela</th>
                <th className="py-2 px-3 text-right font-medium">Valor</th>
                <th className="py-2 px-3 text-right font-medium">Aberto</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={8} className="py-6 text-center text-zinc-500">Carregando…</td>
                </tr>
              ) : null}

              {!loading && rows.length === 0 ? (
                <tr>
                  <td colSpan={8} className="py-6 text-center text-zinc-500">Nenhum lançamento encontrado.</td>
                </tr>
              ) : null}

              {rows.map((r) => {
                const t = r.titulo ?? null;
                const cliente = t?.clientes?.nome ?? "SEM CLIENTE";
                const atraso = daysBetween(r.vencimento_date);
                const atrasado = tab === "aberto" && atraso >= 0;
                return (
                  <tr key={r.id} className="border-b border-zinc-900/70 hover:bg-zinc-900/30">
                    <td className="py-2 px-3">
                      <div className="truncate text-zinc-100">{cliente}</div>
                      <div className="text-xs text-zinc-500 truncate">{t?.id ?? ""}</div>
                    </td>
                    <td className="py-2 px-3 max-w-[340px]">
                      <div className="truncate text-zinc-200">{t?.descricao ?? ""}</div>
                      <div className="text-xs text-zinc-500 truncate">Parcela: {r.numero ?? "—"}</div>
                    </td>
                    <td className="py-2 px-3"><Pill label={String(t?.status ?? "—")} /></td>
                    <td className="py-2 px-3 whitespace-nowrap">{formatDateBR(t?.competencia_date ?? null)}</td>
                    <td className="py-2 px-3 whitespace-nowrap">
                      <div className={atrasado ? "text-amber-200" : "text-zinc-200"}>{formatDateBR(r.vencimento_date)}</div>
                      {atrasado ? <div className="text-xs text-amber-300">{atraso}d atraso</div> : null}
                    </td>
                    <td className="py-2 px-3 text-right tabular-nums">{r.numero ?? "—"}</td>
                    <td className="py-2 px-3 text-right tabular-nums">R$ {formatDecimalBR(n(r.valor), 2)}</td>
                    <td className="py-2 px-3 text-right tabular-nums font-medium">R$ {formatDecimalBR(n(r.valor_aberto), 2)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      <div className="flex items-center justify-between gap-2">
        <button
          type="button"
          onClick={() => setPage((p) => Math.max(0, p - 1))}
          disabled={page <= 0}
          className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
        >
          Anterior
        </button>
        <div className="text-xs text-zinc-500">{total} item(ns)</div>
        <button
          type="button"
          onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
          disabled={page >= totalPages - 1}
          className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
        >
          Próxima
        </button>
      </div>
    </div>
  );
}
