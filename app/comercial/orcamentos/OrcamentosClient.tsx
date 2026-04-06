"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { formatMoneyBR } from "@/lib/decimal";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import type { OrcamentoListaRow, OrcamentoStatus } from "@/lib/comercial/types";
import type { OrcamentoStatusCanonical } from "@/lib/comercial/status";
import { getOrcamentoStatusLabel } from "@/lib/comercial/status";
import { mapOrcamentoError, n, toSupabaseErrorLike } from "@/lib/comercial/utils";
import { atualizarStatusOrcamento, listOrcamentos } from "@/lib/comercial/orcamentos.service";
import OrcamentoStatusDialog, { type OrcamentoStatusDialogPayload } from "./OrcamentoStatusDialog";

const PAGE_SIZE = 50;
const STATUS_OPTIONS: Array<{ value: OrcamentoStatus | "TODOS"; label: string }> = [
  { value: "TODOS", label: "Todos" },
  { value: "ANDAMENTO", label: "Andamento" },
  { value: "FECHADO", label: "Fechado" },
  { value: "PERDIDO", label: "Perdido" },
];

type StatusDialogState =
  | { open: false }
  | { open: true; row: OrcamentoListaRow; status: OrcamentoStatusCanonical };

function formatDateBR(iso?: string | null) {
  if (!iso) return "-";
  const [y, m, d] = String(iso).slice(0, 10).split("-");
  if (!y || !m || !d) return String(iso);
  return `${d}/${m}/${y}`;
}

function truncateFollowup(value: string, max = 70): string {
  if (value.length <= max) return value;
  return `${value.slice(0, max - 1)}...`;
}

function hasAny(caps: Capabilities | null, keys: CapabilityKey[]): boolean {
  return requireAny(caps, keys);
}

export default function OrcamentosClient() {
  const router = useRouter();
  const te = useTenantEmpresa();
  const { loading: permissionsLoading, ready, capabilities } = usePermissions();

  const canView = hasAny(capabilities, ["financeiro.read", "financeiro.write", "os.read", "os.write"]);
  const canWrite = hasAny(capabilities, ["financeiro.write", "os.write"]);
  const canOpenOs = hasAny(capabilities, ["os.write"]);

  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

  const tenantId = te.tenantId;
  const empresaId = te.empresaId;

  const [rows, setRows] = useState<OrcamentoListaRow[]>([]);
  const [count, setCount] = useState(0);

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [ultimoFollowupById, setUltimoFollowupById] = useState<Record<string, string>>({});

  const [q, setQ] = useState("");
  const [status, setStatus] = useState<OrcamentoStatus | "TODOS">("ANDAMENTO");
  const [from, setFrom] = useState<string>("");
  const [to, setTo] = useState<string>("");
  const [page, setPage] = useState(1);

  const totalPages = Math.max(1, Math.ceil(count / PAGE_SIZE));
  const pageSafe = Math.min(Math.max(1, page), totalPages);
  const [statusDialog, setStatusDialog] = useState<StatusDialogState>({ open: false });

  const reload = useCallback(async () => {
    setErr(null);
    setOk(null);

    if (!supabase) return;
    if (!tenantId || !empresaId) {
      setErr("Contexto (tenant/empresa) nao carregado.");
      setRows([]);
      setCount(0);
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const res = await listOrcamentos(supabase, {
        tenantId,
        empresaId,
        q,
        status,
        from,
        to,
        page: pageSafe,
        pageSize: PAGE_SIZE,
      });
      setRows(res.rows);
      setCount(res.count);
    } catch (e: unknown) {
      setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao carregar orcamentos."));
      setRows([]);
      setCount(0);
    } finally {
      setLoading(false);
    }
  }, [empresaId, from, pageSafe, q, status, supabase, tenantId, to]);

  useEffect(() => {
    void reload();
  }, [reload]);

  useEffect(() => {
    if (page !== pageSafe) setPage(pageSafe);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pageSafe]);

  const startNew = useCallback(() => {
    router.push("/comercial/orcamentos/novo");
  }, [router]);

  const openStatusDialog = useCallback((row: OrcamentoListaRow, nextStatus: OrcamentoStatusCanonical) => {
    setStatusDialog({ open: true, row, status: nextStatus });
  }, []);

  const closeStatusDialog = useCallback(() => {
    if (busy) return;
    setStatusDialog({ open: false });
  }, [busy]);

  const submitStatusDialog = useCallback(
    async (payload: OrcamentoStatusDialogPayload) => {
      if (!statusDialog.open) return;
      if (!canWrite || !supabase || !tenantId || !empresaId) return;

      const targetRowId = statusDialog.row.id;
      const prevRows = rows;
      const prevFollowup = ultimoFollowupById[targetRowId];

      setBusy(true);
      setErr(null);
      setOk(null);

      setRows((prev) =>
        prev.map((row) =>
          row.id === targetRowId
            ? {
                ...row,
                status: payload.status,
                observacoes: payload.followup,
                valor_fechado: payload.status === "FECHADO" ? payload.valorFechado : row.valor_fechado,
              }
            : row
        )
      );
      setUltimoFollowupById((prev) => ({ ...prev, [targetRowId]: payload.followup }));

      try {
        const result = await atualizarStatusOrcamento(supabase, {
          tenantId,
          empresaId,
          id: targetRowId,
          status: payload.status,
          followup: payload.followup,
          valorFechado: payload.valorFechado,
          abrirOs: payload.abrirOs,
          importarItensOs: payload.importarItensOs,
        });
        setRows((prev) =>
          prev.map((row) =>
            row.id === targetRowId
              ? {
                  ...row,
                  status: payload.status,
                  observacoes: payload.followup,
                  valor_fechado: payload.status === "FECHADO" ? result.valorFechado : row.valor_fechado,
                  os_id: result.osId ?? row.os_id,
                  os_itens_importados_at: payload.importarItensOs ? new Date().toISOString() : row.os_itens_importados_at,
                }
              : row
          )
        );
        setStatusDialog({ open: false });
        if (payload.abrirOs && result.osId) {
          router.push(`/os/${result.osId}`);
          return;
        }
        setOk(`Status atualizado para ${getOrcamentoStatusLabel(payload.status)}.`);
      } catch (e: unknown) {
        setRows(prevRows);
        setUltimoFollowupById((prev) => {
          const next = { ...prev };
          if (prevFollowup) next[targetRowId] = prevFollowup;
          else delete next[targetRowId];
          return next;
        });
        setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao atualizar status do orcamento."));
      } finally {
        setBusy(false);
      }
    },
    [canWrite, empresaId, router, rows, statusDialog, supabase, tenantId, ultimoFollowupById]
  );

  if (!ready && permissionsLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissoes...</div>;
  }

  if (!canView) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Orcamentos</h1>
          <p className="text-sm text-zinc-400 mt-1">Crie, edite e atualize status dos orcamentos.</p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <button
            type="button"
            onClick={startNew}
            disabled={!canWrite}
            className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
          >
            Novo
          </button>
          <button
            type="button"
            onClick={() => void reload()}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Atualizar
          </button>
          <Link href="/" className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm">
            Voltar
          </Link>
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-3">
        <div className="flex flex-wrap items-end gap-2">
          <input
            value={q}
            onChange={(e) => {
              setQ(e.target.value);
              setPage(1);
            }}
            placeholder="Buscar por cliente, titulo ou codigo..."
            aria-label="Buscar"
            className="w-full sm:w-[420px] rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
          />

          <label className="block text-xs text-zinc-400">
            Status
            <select
              value={status}
              onChange={(e) => {
                setStatus(e.target.value as OrcamentoStatus | "TODOS");
                setPage(1);
              }}
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
              aria-label="Status"
            >
              {STATUS_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </label>

          <label className="block text-xs text-zinc-400">
            Emissao (de)
            <input
              type="date"
              value={from}
              onChange={(e) => {
                setFrom(e.target.value);
                setPage(1);
              }}
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
            />
          </label>

          <label className="block text-xs text-zinc-400">
            Emissao (ate)
            <input
              type="date"
              value={to}
              onChange={(e) => {
                setTo(e.target.value);
                setPage(1);
              }}
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
            />
          </label>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => void reload()}
              disabled={loading}
              className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
            >
              Buscar
            </button>
            <button
              type="button"
              onClick={() => {
                setQ("");
                setStatus("ANDAMENTO");
                setFrom("");
                setTo("");
                setPage(1);
              }}
              className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
            >
              Limpar
            </button>
          </div>
        </div>
      </div>

      {err && <div className="text-sm text-red-400">{err}</div>}
      {ok && <div className="text-sm text-emerald-300">{ok}</div>}

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <div className="overflow-auto">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/70">
              <tr className="text-zinc-200">
                <th className="px-3 py-3 text-left whitespace-nowrap">Codigo</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Emissao</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Titulo</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Cliente</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Vendedor</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Cond. Pgto</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Status</th>
                <th className="px-3 py-3 text-right whitespace-nowrap">Total Liquido</th>
                <th className="px-3 py-3 text-right whitespace-nowrap">Acoes</th>
              </tr>
            </thead>
            <tbody>
              {!loading && rows.length === 0 && (
                <tr>
                  <td colSpan={9} className="px-3 py-6 text-zinc-400">
                    Nenhum orcamento encontrado.
                  </td>
                </tr>
              )}
              {rows.map((r) => {
                const followup = String(ultimoFollowupById[r.id] ?? r.observacoes ?? "").trim();
                return (
                  <tr
                    key={r.id}
                    className="border-t border-zinc-900/60 hover:bg-zinc-900/30 cursor-pointer"
                    onClick={() => router.push(`/comercial/orcamentos/${encodeURIComponent(r.codigo ?? r.id)}`)}
                  >
                    <td className="px-3 py-2 whitespace-nowrap">
                      <span className="underline decoration-zinc-700/60 underline-offset-2 hover:text-zinc-100">{r.codigo}</span>
                    </td>
                    <td className="px-3 py-2 whitespace-nowrap">{formatDateBR(r.emissao_date)}</td>
                    <td className="px-3 py-2 whitespace-normal break-words">{r.titulo}</td>
                    <td className="px-3 py-2">{r.cliente_nome ?? `#${r.cliente_id}`}</td>
                    <td className="px-3 py-2">{r.vendedor_nome ?? "-"}</td>
                    <td className="px-3 py-2">{r.condicao_pagamento_nome ?? "-"}</td>
                    <td className="px-3 py-2">
                      <div className="whitespace-nowrap">{getOrcamentoStatusLabel(r.status)}</div>
                      {followup && <div className="text-xs text-zinc-400 mt-0.5">Ultimo followup: {truncateFollowup(followup)}</div>}
                    </td>
                    <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{formatMoneyBR(n(r.total_liquido))}</td>
                    <td className="px-3 py-2 text-right whitespace-nowrap">
                      <div className="inline-flex items-center gap-2">
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            openStatusDialog(r, "FECHADO");
                          }}
                          disabled={!canWrite || busy}
                          className="px-3 py-1.5 rounded-md border border-emerald-500/30 bg-emerald-500/10 hover:bg-emerald-500/15 text-emerald-200 disabled:opacity-60"
                        >
                          Fechado
                        </button>
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            openStatusDialog(r, "PERDIDO");
                          }}
                          disabled={!canWrite || busy}
                          className="px-3 py-1.5 rounded-md border border-red-500/30 bg-red-500/10 hover:bg-red-500/15 text-red-200 disabled:opacity-60"
                        >
                          Perdido
                        </button>
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            openStatusDialog(r, "ANDAMENTO");
                          }}
                          disabled={!canWrite || busy}
                          className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 disabled:opacity-60"
                        >
                          Andamento
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}
              {loading && (
                <tr>
                  <td colSpan={9} className="px-3 py-6 text-zinc-400">
                    Carregando...
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        <div className="px-4 py-3 border-t border-zinc-800 flex items-center justify-between gap-3 flex-wrap">
          <div className="text-xs text-zinc-400">
            {count ? (
              <>
                Pagina {pageSafe} de {totalPages} - {count} registros
              </>
            ) : (
              <>-</>
            )}
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={pageSafe <= 1}
              className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
            >
              Anterior
            </button>
            <button
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
              disabled={pageSafe >= totalPages}
              className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
            >
              Proxima
            </button>
          </div>
        </div>
      </div>

      {statusDialog.open && (
        <OrcamentoStatusDialog
          open={statusDialog.open}
          status={statusDialog.status}
          loading={busy}
          initialFollowup={statusDialog.row.observacoes}
          initialValorFechado={statusDialog.row.valor_fechado}
          valorOrcado={statusDialog.row.total_liquido}
          canOpenOs={canOpenOs}
          onCancel={closeStatusDialog}
          onSave={submitStatusDialog}
        />
      )}
    </div>
  );
}
