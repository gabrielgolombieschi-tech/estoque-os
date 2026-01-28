"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import {
  addToBuckets,
  daysOverdue,
  downloadCsv,
  emptyBuckets,
  formatDateBR,
  formatMoney,
  n,
  type AgingBuckets,
} from "../relatoriosShared";
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

type ClienteResumo = {
  cliente_nome: string;
  buckets: AgingBuckets;
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

export default function ArAgingClient() {
  const te = useTenantEmpresa();
  const router = useRouter();

  const [q, setQ] = useState<string>("");
  const [onlyOverdue, setOnlyOverdue] = useState(false);
  const [startDue, setStartDue] = useState<string>("");
  const [endDue, setEndDue] = useState<string>("");
  const [limit, setLimit] = useState(2000);
  const [topN, setTopN] = useState(25);

  const [rows, setRows] = useState<ParcelaRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
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

  const tenantId = te.tenantId ?? null;
  const empresaId = te.empresaId ?? (te.empresas.length === 1 ? te.empresas[0]?.id : null);

  const ready =
    typeof te.sessionUserId === "string" &&
    Boolean(tenantId) &&
    Boolean(empresaId) &&
    canFinanceiro === true;

  useEffect(() => {
    if (!ready) {
      if (
        process.env.NODE_ENV !== "production" &&
        typeof te.sessionUserId === "string" &&
        canFinanceiro === true &&
        (!tenantId || !empresaId) &&
        !warnedMissingContextRef.current
      ) {
        console.debug("[financeiro] Contexto ausente ao carregar aging AR", {
          tenantId,
          empresaId: te.empresaId ?? null,
          empresasCount: te.empresas.length,
        });
        warnedMissingContextRef.current = true;
      }
      return;
    }
    warnedMissingContextRef.current = false;

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
              ].join(",")
            ),
          tenantId!,
          empresaId!
        )
          .is("deleted_at", null)
          .order("vencimento_date", { ascending: true })
          .limit(Math.max(200, Math.min(5000, limit)));

        // only AR open
        query = query.eq("titulo.tipo", "AR");
        query = query.eq("titulo.empresa_id", empresaId!);
        query = query.gt("valor_aberto", 0);
        query = query.in("titulo.status", ["PENDENTE", "APROVADO", "AGENDADO"]);

        if (startDue) query = query.gte("vencimento_date", startDue);
        if (endDue) query = query.lte("vencimento_date", endDue);

        if (onlyOverdue) {
          query = query.lte("vencimento_date", new Date().toISOString().slice(0, 10));
        }

        const term = q.trim();
        if (term) {
          query = query.or([`titulo.descricao.ilike.%${term}%`, `clientes.nome.ilike.%${term}%`, `numero.ilike.%${term}%`].join(","));
        }

        const { data, error: qErr } = await query;
        if (cancelled) return;
        if (qErr) throw qErr;

        setRows(((data ?? []) as unknown) as ParcelaRow[]);
      } catch (e: unknown) {
        if (cancelled) return;
        setRows([]);
        setError(e instanceof Error ? e.message : "Erro ao carregar aging AR.");
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [endDue, limit, onlyOverdue, q, ready, startDue, canFinanceiro, empresaId, te.empresaId, te.empresas.length, te.sessionUserId, tenantId]);

  const computed = useMemo(() => {
    const overall = emptyBuckets();

    const byCliente = new Map<string, AgingBuckets>();
    for (const r of rows) {
      const valorAberto = n(r.valor_aberto);
      if (valorAberto <= 0) continue;

      const dias = daysOverdue(r.vencimento_date);
      addToBuckets(overall, dias, valorAberto);

      const nome = r.titulo?.clientes?.nome ?? "(Sem cliente)";
      const b = byCliente.get(nome) ?? emptyBuckets();
      addToBuckets(b, dias, valorAberto);
      byCliente.set(nome, b);
    }

    const clientes: ClienteResumo[] = Array.from(byCliente.entries())
      .map(([cliente_nome, buckets]) => ({ cliente_nome, buckets }))
      .sort((a, b) => b.buckets.total_aberto - a.buckets.total_aberto)
      .slice(0, Math.max(5, Math.min(200, topN)));

    return { overall, clientes };
  }, [rows, topN]);

  const exportResumo = () => {
    const header = [
      "cliente",
      "a_vencer",
      "vencido_0_30",
      "vencido_31_60",
      "vencido_61_90",
      "vencido_90_mais",
      "total_aberto",
    ];
    const dataRows = computed.clientes.map((c) => [
      c.cliente_nome,
      String(c.buckets.a_vencer),
      String(c.buckets.vencido_0_30),
      String(c.buckets.vencido_31_60),
      String(c.buckets.vencido_61_90),
      String(c.buckets.vencido_90_mais),
      String(c.buckets.total_aberto),
    ]);

    downloadCsv("aging_ar_resumo.csv", header, dataRows);
  };

  const exportDetalhe = () => {
    const header = ["cliente", "titulo_id", "parcela", "vencimento", "dias_atraso", "competencia", "descricao", "valor_aberto"]; 
    const dataRows = rows.map((r) => [
      r.titulo?.clientes?.nome ?? "",
      r.titulo?.id ?? "",
      r.numero ?? "",
      r.vencimento_date,
      String(daysOverdue(r.vencimento_date)),
      r.titulo?.competencia_date ?? "",
      r.titulo?.descricao ?? "",
      String(n(r.valor_aberto)),
    ]);

    downloadCsv("aging_ar_detalhe.csv", header, dataRows);
  };

  if (canFinanceiro !== true) return null;

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Aging — Contas a Receber (AR)</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Base: parcelas (tipo AR) com saldo em aberto. Útil para risco de inadimplência e planejamento de caixa.
          </p>
        </div>
        <Link href="/financeiro" className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm">
          Voltar
        </Link>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <div className="grid grid-cols-1 md:grid-cols-6 gap-3 items-end">
          <div className="md:col-span-2">
            <label className="text-xs text-zinc-400" htmlFor="ar-q">
              Buscar (cliente/descrição/parcela)
            </label>
            <input
              id="ar-q"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Ex: cliente, contrato, parcela…"
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            />
          </div>

          <div>
            <label className="text-xs text-zinc-400" htmlFor="ar-start">
              Vencimento (de)
            </label>
            <input
              id="ar-start"
              type="date"
              value={startDue}
              onChange={(e) => setStartDue(e.target.value)}
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            />
          </div>

          <div>
            <label className="text-xs text-zinc-400" htmlFor="ar-end">
              Vencimento (até)
            </label>
            <input
              id="ar-end"
              type="date"
              value={endDue}
              onChange={(e) => setEndDue(e.target.value)}
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            />
          </div>

          <div>
            <label className="text-xs text-zinc-400" htmlFor="ar-top">
              Top N
            </label>
            <select
              id="ar-top"
              value={String(topN)}
              onChange={(e) => setTopN(Number(e.target.value))}
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
            >
              {[10, 25, 50, 100, 200].map((n) => (
                <option key={n} value={String(n)}>
                  {n}
                </option>
              ))}
            </select>
          </div>

          <div className="flex items-center gap-2">
            <input
              id="ar-overdue"
              type="checkbox"
              checked={onlyOverdue}
              onChange={(e) => setOnlyOverdue(e.target.checked)}
              className="h-4 w-4"
            />
            <label htmlFor="ar-overdue" className="text-sm text-zinc-200 select-none">
              Só vencidas
            </label>
          </div>
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-2">
          <div className="text-xs text-zinc-500">Limite de parcelas carregadas (performance):</div>
          <select
            aria-label="Limite"
            value={String(limit)}
            onChange={(e) => setLimit(Number(e.target.value))}
            className="rounded-md border border-zinc-800 bg-zinc-950 px-2 py-1 text-xs"
          >
            {[500, 1000, 2000, 5000].map((n) => (
              <option key={n} value={String(n)}>
                {n}
              </option>
            ))}
          </select>
          <button
            type="button"
            onClick={exportResumo}
            className="ml-auto px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
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

        {error ? <div className="mt-3 text-sm text-red-400">{error}</div> : null}
        {loading ? <div className="mt-3 text-sm text-zinc-400">Carregando…</div> : null}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <Stat title="Total em aberto" value={formatMoney(computed.overall.total_aberto)} />
        <Stat title="A vencer" value={formatMoney(computed.overall.a_vencer)} />
        <Stat
          title="Vencidas (0+ dias)"
          value={formatMoney(
            computed.overall.vencido_0_30 +
              computed.overall.vencido_31_60 +
              computed.overall.vencido_61_90 +
              computed.overall.vencido_90_mais
          )}
        />
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
        <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
          <div className="text-sm font-semibold text-zinc-100">Resumo por cliente</div>
          <div className="text-xs text-zinc-500">{computed.clientes.length} linhas</div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/60 text-zinc-300">
              <tr>
                <th className="text-left px-4 py-2 font-medium">Cliente</th>
                <th className="text-right px-4 py-2 font-medium">A vencer</th>
                <th className="text-right px-4 py-2 font-medium">Venc. 0–30</th>
                <th className="text-right px-4 py-2 font-medium">Venc. 31–60</th>
                <th className="text-right px-4 py-2 font-medium">Venc. 61–90</th>
                <th className="text-right px-4 py-2 font-medium">Venc. 90+</th>
                <th className="text-right px-4 py-2 font-medium">Total</th>
              </tr>
            </thead>
            <tbody>
              {computed.clientes.map((c, idx) => (
                <tr key={`${c.cliente_nome}-${idx}`} className="border-t border-zinc-900">
                  <td className="px-4 py-2 text-zinc-200 max-w-[260px] truncate" title={c.cliente_nome}>
                    {c.cliente_nome}
                  </td>
                  <td className="px-4 py-2 text-right tabular-nums">{formatMoney(c.buckets.a_vencer)}</td>
                  <td className="px-4 py-2 text-right tabular-nums">{formatMoney(c.buckets.vencido_0_30)}</td>
                  <td className="px-4 py-2 text-right tabular-nums">{formatMoney(c.buckets.vencido_31_60)}</td>
                  <td className="px-4 py-2 text-right tabular-nums">{formatMoney(c.buckets.vencido_61_90)}</td>
                  <td className="px-4 py-2 text-right tabular-nums">{formatMoney(c.buckets.vencido_90_mais)}</td>
                  <td className="px-4 py-2 text-right tabular-nums font-medium text-zinc-100">{formatMoney(c.buckets.total_aberto)}</td>
                </tr>
              ))}
              {!computed.clientes.length && !loading ? (
                <tr>
                  <td className="px-4 py-4 text-zinc-400" colSpan={7}>
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
          <div className="text-sm font-semibold text-zinc-100">Detalhes (parcelas)</div>
          <div className="text-xs text-zinc-500">{rows.length} parcelas carregadas</div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/60 text-zinc-300">
              <tr>
                <th className="text-left px-4 py-2 font-medium">Cliente</th>
                <th className="text-left px-4 py-2 font-medium">Parcela</th>
                <th className="text-left px-4 py-2 font-medium">Vencimento</th>
                <th className="text-right px-4 py-2 font-medium">Dias</th>
                <th className="text-left px-4 py-2 font-medium">Competência</th>
                <th className="text-right px-4 py-2 font-medium">Em aberto</th>
              </tr>
            </thead>
            <tbody>
              {rows.slice(0, 200).map((r) => (
                <tr key={r.id} className="border-t border-zinc-900">
                  <td className="px-4 py-2 text-zinc-200 max-w-[260px] truncate" title={r.titulo?.clientes?.nome ?? ""}>
                    {r.titulo?.clientes?.nome ?? "—"}
                  </td>
                  <td className="px-4 py-2 text-zinc-200">{r.numero ?? "—"}</td>
                  <td className="px-4 py-2 text-zinc-200 whitespace-nowrap">{formatDateBR(r.vencimento_date)}</td>
                  <td className="px-4 py-2 text-right tabular-nums text-zinc-200">{daysOverdue(r.vencimento_date)}</td>
                  <td className="px-4 py-2 text-zinc-200 whitespace-nowrap">{formatDateBR(r.titulo?.competencia_date ?? null)}</td>
                  <td className="px-4 py-2 text-right tabular-nums text-zinc-100">{formatMoney(r.valor_aberto)}</td>
                </tr>
              ))}
              {rows.length > 200 ? (
                <tr>
                  <td className="px-4 py-3 text-zinc-500 text-xs" colSpan={6}>
                    Mostrando apenas as primeiras 200 linhas na tabela (use CSV para exportar tudo).
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 text-sm text-zinc-300">
        <div className="font-semibold text-zinc-100">Notas (Lucro Real)</div>
        <ul className="mt-2 list-disc list-inside space-y-1 text-zinc-300">
          <li>Aging é “risco por vencimento” (título em aberto), não fluxo de caixa realizado.</li>
          <li>Competência é usada para resultado; vencimento guia cobrança e planejamento.</li>
        </ul>
      </div>
    </div>
  );
}
