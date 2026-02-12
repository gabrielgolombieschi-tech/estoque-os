"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import type { CondicaoPagamentoRow } from "@/lib/comercial/types";
import { mapOrcamentoError, n, toSupabaseErrorLike, upperTrim } from "@/lib/comercial/utils";
import {
  create as createCondicaoPagamento,
  isUniqueViolation,
  list as listCondicoesPagamento,
  softDelete as softDeleteCondicaoPagamento,
  update as updateCondicaoPagamento,
} from "@/src/services/condicaoPagamento";

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

type DialogMode = "create" | "edit";

type FormState = {
  codigo: string;
  nome: string;
  acrescimo_percent: string;
  dias: string;
  ativo: boolean;
};

function emptyForm(): FormState {
  return { codigo: "", nome: "", acrescimo_percent: "0", dias: "", ativo: true };
}

export default function CondicoesPagamentoPage() {
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

  const [rows, setRows] = useState<CondicaoPagamentoRow[]>([]);

  const [dialogOpen, setDialogOpen] = useState(false);
  const [dialogMode, setDialogMode] = useState<DialogMode>("create");
  const [editing, setEditing] = useState<CondicaoPagamentoRow | null>(null);
  const [form, setForm] = useState<FormState>(emptyForm());

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
      const data = await listCondicoesPagamento(supabase, { tenantId, empresaId });
      setRows(data);
    } catch (e: unknown) {
      setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao carregar condições."));
      setRows([]);
    } finally {
      setLoading(false);
    }
  }, [empresaId, supabase, te.loading, tenantId]);

  useEffect(() => {
    void load();
  }, [load]);

  const openCreate = useCallback(() => {
    setDialogMode("create");
    setEditing(null);
    setForm(emptyForm());
    setDialogOpen(true);
  }, []);

  const openEdit = useCallback((row: CondicaoPagamentoRow) => {
    setDialogMode("edit");
    setEditing(row);
    setForm({
      codigo: row.codigo ?? "",
      nome: row.nome ?? "",
      acrescimo_percent: String(row.acrescimo_percent ?? "0"),
      dias: row.dias === null || row.dias === undefined ? "" : String(row.dias),
      ativo: Boolean(row.ativo),
    });
    setDialogOpen(true);
  }, []);

  const closeDialog = useCallback(() => {
    setDialogOpen(false);
    setEditing(null);
    setForm(emptyForm());
  }, []);

  const submit = useCallback(
    async (e: FormEvent) => {
      e.preventDefault();
      if (!supabase || !tenantId || !empresaId) return;

      const codigo = upperTrim(form.codigo);
      const nome = upperTrim(form.nome);
      if (!codigo) {
        setErr("Informe o código.");
        return;
      }
      if (!nome) {
        setErr("Informe o nome.");
        return;
      }

      const acrescimo = n(form.acrescimo_percent);
      if (acrescimo < 0 || acrescimo > 100) {
        setErr("Acréscimo (%) deve estar entre 0 e 100.");
        return;
      }

      const diasRaw = form.dias.trim();
      const dias = diasRaw ? Number(diasRaw) : null;
      if (diasRaw && (!Number.isFinite(dias as number) || (dias as number) < 0 || !Number.isInteger(dias as number))) {
        setErr("Dias deve ser um número inteiro maior ou igual a 0.");
        return;
      }

      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        const payload = {
          codigo,
          nome,
          dias,
          acrescimo_percent: acrescimo,
          ativo: Boolean(form.ativo),
        } satisfies Pick<CondicaoPagamentoRow, "codigo" | "nome" | "dias" | "acrescimo_percent" | "ativo">;

        if (dialogMode === "edit" && editing?.id) {
          await updateCondicaoPagamento(supabase, { tenantId, empresaId, id: editing.id, patch: payload });
        } else {
          await createCondicaoPagamento(supabase, { tenantId, empresaId, payload });
        }

        setOk(dialogMode === "edit" ? "Condição atualizada." : "Condição criada.");
        closeDialog();
        await load();
      } catch (e2: unknown) {
        if (isUniqueViolation(e2)) {
          setErr("Código já existe. Escolha outro código.");
        } else {
          setErr(mapOrcamentoError(toSupabaseErrorLike(e2), "Erro ao salvar."));
        }
      } finally {
        setBusy(false);
      }
    },
    [closeDialog, dialogMode, editing?.id, empresaId, form, load, supabase, tenantId]
  );

  const softDelete = useCallback(
    async (row: CondicaoPagamentoRow) => {
      if (!supabase || !tenantId || !empresaId) return;
      const ok = await confirm({
        title: `Excluir condição ${row.nome}?`,
        description: "Exclusão é arquivamento (soft delete).",
        confirmText: "Excluir",
        destructive: true,
      });
      if (!ok) return;

      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        await softDeleteCondicaoPagamento(supabase, { tenantId, empresaId, id: row.id });
        setOk("Condição excluída.");
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
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Condições de Pagamento</h1>
          <p className="text-sm text-zinc-400 mt-1">Cadastro de condições para orçamentos.</p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href="/configuracoes/comercial/orcamentos"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Voltar
          </Link>
          <button
            type="button"
            onClick={openCreate}
            className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
          >
            Nova
          </button>
        </div>
      </div>

      {err && <div className="text-sm text-red-400">{err}</div>}
      {ok && <div className="text-sm text-emerald-300">{ok}</div>}
      {loading && <div className="text-sm text-zinc-400">Carregando...</div>}

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <div className="overflow-auto">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/70">
              <tr className="text-zinc-200">
                <th className="px-3 py-3 text-left whitespace-nowrap">Código</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Nome</th>
                <th className="px-3 py-3 text-right whitespace-nowrap">Acréscimo (%)</th>
                <th className="px-3 py-3 text-right whitespace-nowrap">Dias</th>
                <th className="px-3 py-3 text-left whitespace-nowrap">Ativo</th>
                <th className="px-3 py-3 text-right whitespace-nowrap">Ações</th>
              </tr>
            </thead>
            <tbody>
              {!loading && rows.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-3 py-6 text-zinc-400">
                    Nenhuma condição.
                  </td>
                </tr>
              )}
              {rows.map((r) => (
                <tr key={r.id} className="border-t border-zinc-900/60 hover:bg-zinc-900/30">
                  <td className="px-3 py-2 whitespace-nowrap">{r.codigo}</td>
                  <td className="px-3 py-2 min-w-[320px]">{r.nome}</td>
                  <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{n(r.acrescimo_percent)}</td>
                  <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{r.dias ?? "-"}</td>
                  <td className="px-3 py-2 whitespace-nowrap">{r.ativo ? "Sim" : "Não"}</td>
                  <td className="px-3 py-2 text-right whitespace-nowrap">
                    <div className="inline-flex items-center gap-2">
                      <button
                        type="button"
                        onClick={() => openEdit(r)}
                        disabled={busy}
                        className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 disabled:opacity-60"
                      >
                        Editar
                      </button>
                      <button
                        type="button"
                        onClick={() => void softDelete(r)}
                        disabled={busy}
                        className="px-3 py-1.5 rounded-md border border-red-900/60 bg-red-950/40 hover:bg-red-950/70 text-red-200 disabled:opacity-60"
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

      {dialogOpen && (
        <div
          className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeDialog()}
          role="presentation"
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-label={dialogMode === "create" ? "Nova condição" : "Editar condição"}
            className="w-full max-w-xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div className="font-semibold text-zinc-100">{dialogMode === "create" ? "Nova condição" : "Editar condição"}</div>
            </div>

            <form onSubmit={submit} className="p-5 space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <label className="block text-xs text-zinc-400">
                  Código
                  <input
                    value={form.codigo}
                    onChange={(e) => setForm((p) => ({ ...p, codigo: e.target.value }))}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Ativo
                  <select
                    value={form.ativo ? "1" : "0"}
                    onChange={(e) => setForm((p) => ({ ...p, ativo: e.target.value === "1" }))}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                  >
                    <option value="1">Sim</option>
                    <option value="0">Não</option>
                  </select>
                </label>

                <label className="block text-xs text-zinc-400 md:col-span-2">
                  Nome
                  <input
                    value={form.nome}
                    onChange={(e) => setForm((p) => ({ ...p, nome: e.target.value }))}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Acréscimo (%)
                  <input
                    value={form.acrescimo_percent}
                    onChange={(e) => setForm((p) => ({ ...p, acrescimo_percent: e.target.value }))}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Dias
                  <input
                    value={form.dias}
                    onChange={(e) => setForm((p) => ({ ...p, dias: e.target.value }))}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="(opcional)"
                  />
                </label>
              </div>

              <div className="flex items-center justify-end gap-2">
                <button
                  type="button"
                  onClick={closeDialog}
                  disabled={busy}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60"
                >
                  Cancelar
                </button>
                <button
                  type="submit"
                  disabled={busy}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
                >
                  Salvar
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {confirmDialog}
    </div>
  );
}
