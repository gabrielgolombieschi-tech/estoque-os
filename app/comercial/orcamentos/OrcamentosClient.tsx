"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { formatMoneyBR } from "@/lib/decimal";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import type { OrcamentoListaRow, OrcamentoStatus } from "@/lib/comercial/types";
import { mapOrcamentoError, n, toSupabaseErrorLike } from "@/lib/comercial/utils";
import {
  cancelarOrcamento,
  deleteOrcamento,
  finalizarOrcamento,
  listOrcamentos,
} from "@/lib/comercial/orcamentos.service";

const PAGE_SIZE = 50;
const STATUS_OPTIONS: Array<OrcamentoStatus | "TODOS"> = ["RASCUNHO", "FINALIZADO", "CANCELADO", "TODOS"];

type ConfirmOptions = {
  title: string;
  description?: string;
  confirmText?: string;
  cancelText?: string;
  destructive?: boolean;
};

function useConfirmDialog() {
  const [opts, setOpts] = useState<ConfirmOptions | null>(null);
  const resolverRef = useRef<((v: boolean) => void) | null>(null);

  const confirm = useCallback((next: ConfirmOptions) => {
    return new Promise<boolean>((resolve) => {
      resolverRef.current = resolve;
      setOpts(next);
    });
  }, []);

  const close = useCallback((value: boolean) => {
    const resolve = resolverRef.current;
    resolverRef.current = null;
    setOpts(null);
    resolve?.(value);
  }, []);

  const dialog = opts ? (
    <div
      className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
      onClick={(e) => e.target === e.currentTarget && close(false)}
      role="presentation"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={opts.title}
        className="w-full max-w-lg bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
          <div className="font-semibold text-zinc-100">{opts.title}</div>
          {opts.description && <div className="text-xs text-zinc-400 mt-1">{opts.description}</div>}
        </div>
        <div className="px-5 py-4 flex items-center justify-end gap-2">
          <button
            type="button"
            onClick={() => close(false)}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
          >
            {opts.cancelText ?? "Cancelar"}
          </button>
          <button
            type="button"
            onClick={() => close(true)}
            className={
              opts.destructive
                ? "px-4 py-2 rounded-md bg-red-600 text-white hover:bg-red-500 font-medium"
                : "px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
            }
          >
            {opts.confirmText ?? "Confirmar"}
          </button>
        </div>
      </div>
    </div>
  ) : null;

  return { confirm, dialog };
}

function formatDateBR(iso?: string | null) {
  if (!iso) return "-";
  const [y, m, d] = String(iso).slice(0, 10).split("-");
  if (!y || !m || !d) return String(iso);
  return `${d}/${m}/${y}`;
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
  const canDelete = hasAny(capabilities, ["financeiro.delete", "os.delete"]);

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

  // filtros
  const [q, setQ] = useState("");
  const [status, setStatus] = useState<OrcamentoStatus | "TODOS">("TODOS");
  const [from, setFrom] = useState<string>("");
  const [to, setTo] = useState<string>("");
  const [page, setPage] = useState(1);

  const totalPages = Math.max(1, Math.ceil(count / PAGE_SIZE));
  const pageSafe = Math.min(Math.max(1, page), totalPages);

  const { confirm, dialog: confirmDialog } = useConfirmDialog();

  const reload = useCallback(async () => {
    setErr(null);
    setOk(null);

    if (!supabase) return;
    if (!tenantId || !empresaId) {
      setErr("Contexto (tenant/empresa) não carregado.");
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
      setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao carregar orçamentos."));
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

  const doFinalizar = useCallback(
    async (row: OrcamentoListaRow) => {
      if (!canWrite) return;
      if (!supabase || !tenantId || !empresaId) return;
      const ok = await confirm({
        title: `Finalizar orçamento ${row.codigo}?`,
        description: "Após finalizar, a edição fica bloqueada.",
        confirmText: "Finalizar",
      });
      if (!ok) return;
      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        await finalizarOrcamento(supabase, { tenantId, empresaId, id: row.id });
        setOk("Orçamento finalizado.");
        await reload();
      } catch (e: unknown) {
        setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao finalizar."));
      } finally {
        setBusy(false);
      }
    },
    [canWrite, confirm, empresaId, reload, supabase, tenantId]
  );

  const doCancelar = useCallback(
    async (row: OrcamentoListaRow) => {
      if (!canWrite) return;
      if (!supabase || !tenantId || !empresaId) return;
      const ok = await confirm({
        title: `Cancelar orçamento ${row.codigo}?`,
        description: "A edição ficará bloqueada.",
        confirmText: "Cancelar",
        destructive: true,
      });
      if (!ok) return;
      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        await cancelarOrcamento(supabase, { tenantId, empresaId, id: row.id });
        setOk("Orçamento cancelado.");
        await reload();
      } catch (e: unknown) {
        setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao cancelar."));
      } finally {
        setBusy(false);
      }
    },
    [canWrite, confirm, empresaId, reload, supabase, tenantId]
  );

  const doExcluir = useCallback(
    async (row: OrcamentoListaRow) => {
      if (!canDelete) return;
      if (!supabase || !tenantId || !empresaId) return;
      const ok = await confirm({
        title: `Excluir orçamento ${row.codigo}?`,
        description: "Exclusão é arquivamento (soft delete).",
        confirmText: "Excluir",
        destructive: true,
      });
      if (!ok) return;
      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        await deleteOrcamento(supabase, { tenantId, empresaId, id: row.id });
        setOk("Orçamento excluído.");
        await reload();
      } catch (e: unknown) {
        setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao excluir."));
      } finally {
        setBusy(false);
      }
    },
    [canDelete, confirm, empresaId, reload, supabase, tenantId]
  );

  if (!ready && permissionsLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissões...</div>;
  }

  if (!canView) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Orçamentos</h1>
          <p className="text-sm text-zinc-400 mt-1">Crie, edite e finalize orçamentos (cálculos automáticos no banco).</p>
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
          <Link
            href="/"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
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
            placeholder="Buscar por cliente, título ou código…"
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
              {STATUS_OPTIONS.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
          </label>

          <label className="block text-xs text-zinc-400">
            Emissão (de)
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
            Emissão (até)
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
                setStatus("TODOS");
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
                <th className="px-3 py-3 text-left whitespace-nowrap">Código</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Emissão</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Título</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Cliente</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Vendedor</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Cond. Pgto</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Status</th>
                <th className="px-3 py-3 text-right whitespace-nowrap">Total Líquido</th>
                <th className="px-3 py-3 text-right whitespace-nowrap">Ações</th>
              </tr>
            </thead>
            <tbody>
              {!loading && rows.length === 0 && (
                <tr>
                  <td colSpan={9} className="px-3 py-6 text-zinc-400">
                    Nenhum orçamento encontrado.
                  </td>
                </tr>
              )}
              {rows.map((r) => (
                <tr
                  key={r.id}
                  className="border-t border-zinc-900/60 hover:bg-zinc-900/30 cursor-pointer"
                  onClick={() => router.push(`/comercial/orcamentos/${encodeURIComponent(r.codigo ?? r.id)}`)}
                >
                  <td className="px-3 py-2 whitespace-nowrap">
                    <span className="underline decoration-zinc-700/60 underline-offset-2 hover:text-zinc-100">
                      {r.codigo}
                    </span>
                  </td>
                  <td className="px-3 py-2 whitespace-nowrap">{formatDateBR(r.emissao_date)}</td>
                  <td className="px-3 py-2 whitespace-normal break-words">{r.titulo}</td>
                  <td className="px-3 py-2">{r.cliente_nome ?? `#${r.cliente_id}`}</td>
                  <td className="px-3 py-2">{r.vendedor_nome ?? "-"}</td>
                  <td className="px-3 py-2">{r.condicao_pagamento_nome ?? "-"}</td>
                  <td className="px-3 py-2 whitespace-nowrap">{String(r.status ?? "").toUpperCase()}</td>
                  <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{formatMoneyBR(n(r.total_liquido))}</td>
                  <td className="px-3 py-2 text-right whitespace-nowrap">
                    <div className="inline-flex items-center gap-2">
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          void doFinalizar(r);
                        }}
                        disabled={!canWrite || busy || String(r.status).toUpperCase() !== "RASCUNHO"}
                        className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 disabled:opacity-60"
                      >
                        Finalizar
                      </button>
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          void doCancelar(r);
                        }}
                        disabled={!canWrite || busy || String(r.status).toUpperCase() !== "RASCUNHO"}
                        className="px-3 py-1.5 rounded-md border border-amber-500/30 bg-amber-500/10 hover:bg-amber-500/15 text-amber-200 disabled:opacity-60"
                      >
                        Cancelar
                      </button>
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          void doExcluir(r);
                        }}
                        disabled={!canDelete || busy}
                        className="px-3 py-1.5 rounded-md border border-red-900/60 bg-red-950/40 hover:bg-red-950/70 text-red-200 disabled:opacity-60"
                      >
                        Excluir
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
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
                Página {pageSafe} de {totalPages} — {count} registros
              </>
            ) : (
              <>—</>
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
              Próxima
            </button>
          </div>
        </div>
      </div>

      {confirmDialog}
    </div>
  );
}
