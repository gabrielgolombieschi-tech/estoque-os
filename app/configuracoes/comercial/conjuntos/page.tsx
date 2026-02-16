"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import { mapOrcamentoError, toSupabaseErrorLike } from "@/lib/comercial/utils";
import type { ConjuntoRow } from "@/src/services/conjunto";
import { listConjuntos, softDeleteConjunto } from "@/src/services/conjunto";

type ConfirmOptions = {
  title: string;
  description?: string;
  confirmText?: string;
  cancelText?: string;
  destructive?: boolean;
};

function hasAny(caps: Capabilities | null, keys: CapabilityKey[]): boolean {
  return requireAny(caps, keys);
}

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

export default function ConjuntosPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const te = useTenantEmpresa();
  const tenantId = te.tenantId;
  const empresaId = te.empresaId;

  const { loading: permissionsLoading, ready, capabilities } = usePermissions();
  const canView = hasAny(capabilities, ["financeiro.config", "financeiro.write", "os.write"]);

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const [term, setTerm] = useState("");
  const [onlyActive, setOnlyActive] = useState(true);
  const [rows, setRows] = useState<ConjuntoRow[]>([]);

  const { confirm, dialog: confirmDialog } = useConfirmDialog();

  const load = useCallback(async () => {
    setErr(null);
    setOk(null);

    if (!supabase) return;
    if (te.loading) return;

    if (!tenantId || !empresaId) {
      setLoading(false);
      setErr("Contexto (tenant/empresa) não carregado.");
      return;
    }

    setLoading(true);
    try {
      const data = await listConjuntos(supabase, { tenantId, empresaId, term, onlyActive });
      setRows(data);
    } catch (e: unknown) {
      setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao carregar conjuntos."));
      setRows([]);
    } finally {
      setLoading(false);
    }
  }, [empresaId, onlyActive, supabase, te.loading, tenantId, term]);

  useEffect(() => {
    void load();
  }, [load]);

  const doDelete = useCallback(
    async (row: ConjuntoRow) => {
      if (!supabase || !tenantId || !empresaId) return;
      const ok = await confirm({
        title: `Excluir conjunto ${row.codigo ?? row.nome ?? ""}?`,
        description: "Exclusão é arquivamento (soft delete).",
        confirmText: "Excluir",
        destructive: true,
      });
      if (!ok) return;

      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        await softDeleteConjunto(supabase, { tenantId, empresaId, id: row.id });
        setOk("Conjunto excluído.");
        await load();
      } catch (e: unknown) {
        setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao excluir."));
      } finally {
        setBusy(false);
      }
    },
    [confirm, empresaId, load, supabase, tenantId]
  );

  if (!ready && permissionsLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissões...</div>;
  }

  if (!canView) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;
  }

  return (
    <div className="space-y-4">
      {confirmDialog}

      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Conjuntos (Kits)</h1>
          <p className="text-sm text-zinc-400 mt-1">Cadastro de conjuntos para inclusão rápida em orçamentos.</p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href="/configuracoes/comercial/orcamentos"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Voltar
          </Link>
          <Link
            href="/configuracoes/comercial/conjuntos/novo"
            className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
          >
            Novo
          </Link>
        </div>
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-3">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <label className="block text-xs text-zinc-400">
            Buscar (código ou nome)
            <input
              value={term}
              onChange={(e) => setTerm(e.target.value)}
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
              placeholder="Ex.: KIT-001 ou MANUTENÇÃO"
            />
          </label>

          <label className="block text-xs text-zinc-400">
            Ativo
            <select
              value={onlyActive ? "1" : "0"}
              onChange={(e) => setOnlyActive(e.target.value === "1")}
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
            >
              <option value="1">Somente ativos</option>
              <option value="0">Todos</option>
            </select>
          </label>

          <div className="flex items-end">
            <button
              type="button"
              onClick={() => void load()}
              disabled={busy}
              className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
            >
              Atualizar
            </button>
          </div>
        </div>

        {err && <div className="text-sm text-red-400">{err}</div>}
        {ok && <div className="text-sm text-emerald-300">{ok}</div>}
        {loading && <div className="text-sm text-zinc-400">Carregando...</div>}
      </div>

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <div className="overflow-auto">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/70">
              <tr className="text-zinc-200">
                <th className="px-3 py-3 text-left whitespace-nowrap">Código</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Nome</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Categoria</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Precificação</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Ativo</th>
                <th className="px-3 py-3 text-right whitespace-nowrap">Ações</th>
              </tr>
            </thead>
            <tbody>
              {!loading && rows.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-3 py-6 text-zinc-400">
                    Nenhum conjunto.
                  </td>
                </tr>
              )}
              {rows.map((r) => (
                <tr key={r.id} className="border-t border-zinc-900/60 hover:bg-zinc-900/30">
                  <td className="px-3 py-2 whitespace-nowrap">{r.codigo ?? "—"}</td>
                  <td className="px-3 py-2 min-w-[320px]">{r.nome ?? "—"}</td>
                  <td className="px-3 py-2 whitespace-nowrap">{r.categoria ?? "—"}</td>
                  <td className="px-3 py-2 whitespace-nowrap">{r.precificacao ?? "—"}</td>
                  <td className="px-3 py-2 whitespace-nowrap">{r.ativo ? "Sim" : "Não"}</td>
                  <td className="px-3 py-2 text-right whitespace-nowrap">
                    <div className="flex items-center justify-end gap-2">
                      <Link
                        href={`/configuracoes/comercial/conjuntos/${r.id}`}
                        className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
                      >
                        Editar
                      </Link>
                      <button
                        type="button"
                        onClick={() => void doDelete(r)}
                        disabled={busy}
                        className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
                      >
                        Excluir
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
