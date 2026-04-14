"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import type { CondicaoPagamentoRow } from "@/lib/comercial/types";
import { mapOrcamentoError, n, toSupabaseErrorLike, upperTrim } from "@/lib/comercial/utils";
import {
  create as createCondicaoPagamento,
  ensureDefaults as ensureCondicoesPagamentoDefaults,
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

type DialogMode = "create" | "edit";

type FormState = {
  codigo: string;
  nome: string;
  acrescimo_percent: string;
  dias: string;
  ativo: boolean;
};

type CondicoesPagamentoManagerProps = {
  title: string;
  subtitle: string;
  backHref: string;
  backLabel: string;
  entitySingular: string;
  entityPlural: string;
  newLabel?: string;
  defaultsLabel?: string;
};

function emptyForm(): FormState {
  return { codigo: "", nome: "", acrescimo_percent: "0", dias: "", ativo: true };
}

function normalizeRole(value: string | null | undefined): string {
  return typeof value === "string" ? value.trim().toUpperCase() : "";
}

function capitalize(value: string): string {
  if (!value) return value;
  return `${value.charAt(0).toUpperCase()}${value.slice(1)}`;
}

function useConfirmDialog() {
  const [opts, setOpts] = useState<ConfirmOptions | null>(null);
  const resolverRef = useRef<((value: boolean) => void) | null>(null);

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
          {opts.description ? <div className="text-xs text-zinc-400 mt-1">{opts.description}</div> : null}
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

export default function CondicoesPagamentoManager({
  title,
  subtitle,
  backHref,
  backLabel,
  entitySingular,
  entityPlural,
  newLabel,
  defaultsLabel = "Instalar principais",
}: CondicoesPagamentoManagerProps) {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const te = useTenantEmpresa();
  const tenantId = te.tenantId;
  const empresaId = te.empresaId;

  const effectiveEmpresa = useMemo(() => {
    if (empresaId) return te.empresas.find((empresa) => empresa.id === empresaId) ?? null;
    if (te.empresas.length === 1) return te.empresas[0];
    return null;
  }, [empresaId, te.empresas]);

  const empresaRole = useMemo(() => normalizeRole(effectiveEmpresa?.papel), [effectiveEmpresa?.papel]);
  const permissionsReady = te.capabilities !== null;
  const roleCanManage = ["ADMIN", "FINANCEIRO", "COORDENACAO", "COMPRAS"].includes(empresaRole);

  const canView = useMemo(() => {
    if (!permissionsReady) return false;
    return Boolean(
      roleCanManage ||
      te.has("financeiro.config") ||
      te.has("financeiro.write") ||
      te.has("os.write") ||
      te.has("compras.read") ||
      te.has("compras.write") ||
      te.has("compras.approve") ||
      te.has("compras.receive")
    );
  }, [permissionsReady, roleCanManage, te]);

  const canManage = useMemo(() => {
    if (!permissionsReady) return false;
    return Boolean(
      roleCanManage ||
      te.has("financeiro.config") ||
      te.has("financeiro.write") ||
      te.has("os.write") ||
      te.has("compras.write")
    );
  }, [permissionsReady, roleCanManage, te]);

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [rows, setRows] = useState<CondicaoPagamentoRow[]>([]);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [dialogMode, setDialogMode] = useState<DialogMode>("create");
  const [editing, setEditing] = useState<CondicaoPagamentoRow | null>(null);
  const [form, setForm] = useState<FormState>(emptyForm());

  const singularTitle = capitalize(entitySingular);
  const newButtonLabel = newLabel ?? `Nova ${entitySingular}`;

  const { confirm, dialog: confirmDialog } = useConfirmDialog();

  const load = useCallback(
    async (options?: { seedDefaults?: boolean }) => {
      if (!supabase) return;
      if (te.loading) return;

      if (!tenantId || !empresaId) {
        setLoading(false);
        setErr("Contexto (tenant/empresa) não carregado.");
        return;
      }

      setLoading(true);
      setErr(null);
      try {
        if (options?.seedDefaults !== false && canManage) {
          await ensureCondicoesPagamentoDefaults(supabase, { tenantId, empresaId });
        }

        const data = await listCondicoesPagamento(supabase, { tenantId, empresaId });
        setRows(data);
      } catch (error: unknown) {
        setRows([]);
        setErr(mapOrcamentoError(toSupabaseErrorLike(error), `Erro ao carregar ${entityPlural}.`));
      } finally {
        setLoading(false);
      }
    },
    [canManage, empresaId, entityPlural, supabase, te.loading, tenantId]
  );

  useEffect(() => {
    if (!permissionsReady) return;
    if (!canView) {
      setLoading(false);
      return;
    }
    void load({ seedDefaults: true });
  }, [canView, load, permissionsReady]);

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

  const installDefaults = useCallback(async () => {
    if (!supabase || !tenantId || !empresaId || !canManage) return;

    setBusy(true);
    setErr(null);
    setOk(null);

    try {
      const result = await ensureCondicoesPagamentoDefaults(supabase, { tenantId, empresaId });
      const changed = result.inserted + result.reactivated;

      if (changed > 0) {
        setOk(`Principais ${entityPlural} cadastradas com sucesso.`);
      } else {
        setOk(`Principais ${entityPlural} já estavam cadastradas.`);
      }

      await load({ seedDefaults: false });
    } catch (error: unknown) {
      setErr(mapOrcamentoError(toSupabaseErrorLike(error), `Erro ao instalar ${entityPlural}.`));
    } finally {
      setBusy(false);
    }
  }, [canManage, empresaId, entityPlural, load, supabase, tenantId]);

  const submit = useCallback(
    async (event: FormEvent) => {
      event.preventDefault();
      if (!supabase || !tenantId || !empresaId || !canManage) return;

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
          setOk(`${singularTitle} atualizada com sucesso.`);
        } else {
          await createCondicaoPagamento(supabase, { tenantId, empresaId, payload });
          setOk(`${singularTitle} criada com sucesso.`);
        }

        closeDialog();
        await load({ seedDefaults: false });
      } catch (error: unknown) {
        if (isUniqueViolation(error)) {
          setErr("Código já existe. Escolha outro código.");
        } else {
          setErr(mapOrcamentoError(toSupabaseErrorLike(error), "Erro ao salvar."));
        }
      } finally {
        setBusy(false);
      }
    },
    [canManage, closeDialog, dialogMode, editing?.id, empresaId, form, load, singularTitle, supabase, tenantId]
  );

  const softDelete = useCallback(
    async (row: CondicaoPagamentoRow) => {
      if (!supabase || !tenantId || !empresaId || !canManage) return;

      const confirmed = await confirm({
        title: `Excluir ${entitySingular} ${row.nome}?`,
        description: "A exclusão é feita por arquivamento (soft delete).",
        confirmText: "Excluir",
        destructive: true,
      });

      if (!confirmed) return;

      setBusy(true);
      setErr(null);
      setOk(null);

      try {
        await softDeleteCondicaoPagamento(supabase, { tenantId, empresaId, id: row.id });
        setOk(`${singularTitle} excluída com sucesso.`);
        await load({ seedDefaults: false });
      } catch (error: unknown) {
        setErr(mapOrcamentoError(toSupabaseErrorLike(error), "Erro ao excluir."));
      } finally {
        setBusy(false);
      }
    },
    [canManage, confirm, empresaId, entitySingular, load, singularTitle, supabase, tenantId]
  );

  if (!permissionsReady) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissões...</div>;
  }

  if (!canView) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">{title}</h1>
          <p className="text-sm text-zinc-400 mt-1">{subtitle}</p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <Link href={backHref} className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm">
            {backLabel}
          </Link>
          <button
            type="button"
            onClick={() => void load({ seedDefaults: false })}
            disabled={busy}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
          >
            Atualizar
          </button>
          {canManage ? (
            <button
              type="button"
              onClick={() => void installDefaults()}
              disabled={busy}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm disabled:opacity-60"
            >
              {defaultsLabel}
            </button>
          ) : null}
          {canManage ? (
            <button
              type="button"
              onClick={openCreate}
              disabled={busy}
              className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
            >
              {newButtonLabel}
            </button>
          ) : null}
        </div>
      </div>

      {!canManage ? (
        <div className="text-xs text-zinc-500">Acesso em modo leitura para este cadastro.</div>
      ) : null}

      {err ? <div className="text-sm text-red-400">{err}</div> : null}
      {ok ? <div className="text-sm text-emerald-300">{ok}</div> : null}
      {loading ? <div className="text-sm text-zinc-400">Carregando...</div> : null}

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
              {!loading && rows.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-3 py-6 text-zinc-400">
                    Nenhuma {entitySingular} cadastrada.
                  </td>
                </tr>
              ) : null}
              {rows.map((row) => (
                <tr key={row.id} className="border-t border-zinc-900/60 hover:bg-zinc-900/30">
                  <td className="px-3 py-2 whitespace-nowrap">{row.codigo}</td>
                  <td className="px-3 py-2 min-w-[320px]">{row.nome}</td>
                  <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{n(row.acrescimo_percent)}</td>
                  <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{row.dias ?? "-"}</td>
                  <td className="px-3 py-2 whitespace-nowrap">{row.ativo ? "Sim" : "Não"}</td>
                  <td className="px-3 py-2 text-right whitespace-nowrap">
                    {canManage ? (
                      <div className="inline-flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => openEdit(row)}
                          disabled={busy}
                          className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 disabled:opacity-60"
                        >
                          Editar
                        </button>
                        <button
                          type="button"
                          onClick={() => void softDelete(row)}
                          disabled={busy}
                          className="px-3 py-1.5 rounded-md border border-red-900/60 bg-red-950/40 hover:bg-red-950/70 text-red-200 disabled:opacity-60"
                        >
                          Excluir
                        </button>
                      </div>
                    ) : (
                      <span className="text-zinc-500">-</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {dialogOpen ? (
        <div
          className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeDialog()}
          role="presentation"
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-label={dialogMode === "create" ? newButtonLabel : `Editar ${entitySingular}`}
            className="w-full max-w-xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div className="font-semibold text-zinc-100">
                {dialogMode === "create" ? newButtonLabel : `Editar ${entitySingular}`}
              </div>
            </div>

            <form onSubmit={submit} className="p-5 space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <label className="block text-xs text-zinc-400">
                  Código
                  <input
                    value={form.codigo}
                    onChange={(e) => setForm((prev) => ({ ...prev, codigo: e.target.value.toUpperCase() }))}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Ativo
                  <select
                    value={form.ativo ? "1" : "0"}
                    onChange={(e) => setForm((prev) => ({ ...prev, ativo: e.target.value === "1" }))}
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
                    onChange={(e) => setForm((prev) => ({ ...prev, nome: e.target.value.toUpperCase() }))}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Acréscimo (%)
                  <input
                    value={form.acrescimo_percent}
                    onChange={(e) => setForm((prev) => ({ ...prev, acrescimo_percent: e.target.value }))}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Dias
                  <input
                    value={form.dias}
                    onChange={(e) => setForm((prev) => ({ ...prev, dias: e.target.value }))}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="Opcional"
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
      ) : null}

      {confirmDialog}
    </div>
  );
}
