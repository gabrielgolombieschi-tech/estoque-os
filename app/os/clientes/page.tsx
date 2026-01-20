"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenant } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";

type Cliente = {
  id: number;
  tenant_id: string;
  nome: string;
  documento: string | null;
  email: string | null;
  telefone: string | null;
  endereco: string | null;
  observacoes: string | null;
  ativo: boolean;
  habilita_hh: boolean;
  criado_em: string;
  atualizado_em: string;
};

type ClienteForm = {
  nome: string;
  documento: string;
  email: string;
  telefone: string;
  endereco: string;
  observacoes: string;
  ativo: boolean;
  habilita_hh: boolean;
};

type SupabaseErrorLike = { code?: string; message?: string } | null | undefined;

type ConfirmOptions = {
  title: string;
  description?: string;
  confirmText?: string;
  cancelText?: string;
  destructive?: boolean;
};

function normalizeDigits(value: string): string {
  return value.replace(/\D/g, "").trim();
}

function isValidEmail(email: string): boolean {
  const v = email.trim();
  if (!v) return true;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);
}

function emptyForm(): ClienteForm {
  return {
    nome: "",
    documento: "",
    email: "",
    telefone: "",
    endereco: "",
    observacoes: "",
    ativo: true,
    habilita_hh: false,
  };
}

function hasAny(caps: Capabilities | null, keys: CapabilityKey[]): boolean {
  return requireAny(caps, keys);
}

function mapClienteError(error: SupabaseErrorLike): string {
  const code = error?.code ?? "";
  const message = (error?.message ?? "").toLowerCase();

  if (code === "23505" || message.includes("duplicate") || message.includes("unique")) {
    return "Já existe cliente com este documento.";
  }

  return error?.message ?? "Erro inesperado.";
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

type ClienteDialogProps = {
  open: boolean;
  mode: "create" | "edit";
  initial?: Cliente | null;
  busy: boolean;
  canEdit: boolean;
  onClose: () => void;
  onSave: (payload: ClienteForm) => Promise<void>;
};

function ClienteDialog({ open, mode, initial, busy, canEdit, onClose, onSave }: ClienteDialogProps) {
  const [err, setErr] = useState<string | null>(null);
  const [form, setForm] = useState<ClienteForm>(() => {
    if (mode === "edit" && initial) {
      return {
        nome: initial.nome ?? "",
        documento: initial.documento ?? "",
        email: initial.email ?? "",
        telefone: initial.telefone ?? "",
        endereco: initial.endereco ?? "",
        observacoes: initial.observacoes ?? "",
        ativo: !!initial.ativo,
        habilita_hh: !!initial.habilita_hh,
      };
    }
    return emptyForm();
  });

  useEffect(() => {
    if (!open) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [open, onClose]);

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setErr(null);

    if (!canEdit) {
      setErr("Sem permissão para salvar clientes.");
      return;
    }

    const nome = form.nome.trim();
    if (!nome) {
      setErr("Nome é obrigatório.");
      return;
    }

    const digits = normalizeDigits(form.documento);
    if (digits && digits.length !== 11 && digits.length !== 14) {
      setErr("Documento deve ter 11 (CPF) ou 14 (CNPJ) dígitos, se informado.");
      return;
    }

    if (!isValidEmail(form.email)) {
      setErr("E-mail inválido.");
      return;
    }

    await onSave({
      ...form,
      nome,
      documento: form.documento.trim(),
      email: form.email.trim(),
      telefone: form.telefone.trim(),
      endereco: form.endereco.trim(),
      observacoes: form.observacoes.trim(),
    }).catch((e2: unknown) => {
      const msg = e2 instanceof Error ? e2.message : "Erro ao salvar.";
      setErr(msg);
    });
  };

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-40 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
      onClick={(e) => e.target === e.currentTarget && onClose()}
      role="presentation"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={mode === "edit" ? `Editar cliente #${initial?.id ?? ""}` : "Novo cliente"}
        className="w-full max-w-3xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
          <div>
            <div className="font-semibold">
              {mode === "edit" ? `Editar cliente #${initial?.id ?? ""}` : "Novo cliente"}
            </div>
            <div className="text-xs text-zinc-400 mt-0.5">Dados cadastrais do cliente.</div>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={onClose}
              className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
            >
              Cancelar
            </button>
            <button
              type="submit"
              form="cliente-form"
              disabled={busy || !canEdit}
              className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {busy ? "Salvando..." : "Salvar"}
            </button>
          </div>
        </div>

        <form id="cliente-form" onSubmit={onSubmit} className="p-5 space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div className="space-y-1 md:col-span-2">
              <div className="text-xs text-zinc-400">Nome *</div>
              <input
                autoFocus
                aria-label="Nome"
                className="w-full px-3 py-2"
                value={form.nome}
                onChange={(e) => setForm((s) => ({ ...s, nome: e.target.value }))}
              />
            </div>

            <div className="space-y-1">
              <div className="text-xs text-zinc-400">Documento (CPF/CNPJ)</div>
              <input
                aria-label="Documento"
                className="w-full px-3 py-2"
                value={form.documento}
                onChange={(e) => setForm((s) => ({ ...s, documento: e.target.value }))}
                placeholder="Somente números ou formatado"
              />
              <div className="text-[11px] text-zinc-500">Normalizado: {normalizeDigits(form.documento) || "-"}</div>
            </div>

            <div className="space-y-1">
              <div className="text-xs text-zinc-400">E-mail</div>
              <input
                aria-label="E-mail"
                className="w-full px-3 py-2"
                value={form.email}
                onChange={(e) => setForm((s) => ({ ...s, email: e.target.value }))}
                placeholder="cliente@empresa.com"
              />
            </div>

            <div className="space-y-1">
              <div className="text-xs text-zinc-400">Telefone</div>
              <input
                aria-label="Telefone"
                className="w-full px-3 py-2"
                value={form.telefone}
                onChange={(e) => setForm((s) => ({ ...s, telefone: e.target.value }))}
                placeholder="(xx) xxxxx-xxxx"
              />
            </div>

            <div className="space-y-1 md:col-span-2">
              <div className="text-xs text-zinc-400">Endereço</div>
              <textarea
                aria-label="Endereço"
                className="w-full px-3 py-2 min-h-[70px]"
                value={form.endereco}
                onChange={(e) => setForm((s) => ({ ...s, endereco: e.target.value }))}
              />
            </div>

            <div className="space-y-1 md:col-span-2">
              <div className="text-xs text-zinc-400">Observações</div>
              <textarea
                aria-label="Observações"
                className="w-full px-3 py-2 min-h-[90px]"
                value={form.observacoes}
                onChange={(e) => setForm((s) => ({ ...s, observacoes: e.target.value }))}
              />
            </div>
          </div>

          <div className="flex items-center justify-between gap-3 border border-zinc-800 rounded-lg p-3">
            <div className="text-sm">
              <div className="font-medium">Relatório HH (Hora-Homem)</div>
              <div className="text-xs text-zinc-400">Habilita lançamento e relatórios de horas nas OSs deste cliente.</div>
            </div>
            <label className="text-sm text-zinc-300 flex items-center gap-2">
              <input
                type="checkbox"
                checked={form.habilita_hh}
                onChange={(e) => setForm((s) => ({ ...s, habilita_hh: e.target.checked }))}
              />
              Habilitar HH
            </label>
          </div>

          {mode === "edit" && (
            <div className="flex items-center justify-between gap-3 border border-zinc-800 rounded-lg p-3">
              <div className="text-sm">
                <div className="font-medium">Status</div>
                <div className="text-xs text-zinc-400">Desativar mantém histórico (Lucro Real).</div>
              </div>
              <label className="text-sm text-zinc-300 flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={form.ativo}
                  onChange={(e) => setForm((s) => ({ ...s, ativo: e.target.checked }))}
                />
                Ativo
              </label>
            </div>
          )}

          {err && <div className="text-sm text-red-400">{err}</div>}
        </form>
      </div>
    </div>
  );
}

export default function ClientesPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { tenantId, loading: tenantEmpresaLoading } = useTenantEmpresa();
  const { loading: permissionsLoading, ready, capabilities } = usePermissions();

  const canView = hasAny(capabilities, ["os.read", "cad_clientes.write"]);
  const canEdit = hasAny(capabilities, ["cad_clientes.write"]);

  const [rows, setRows] = useState<Cliente[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [loadingList, setLoadingList] = useState(false);

  // filtros
  const [search, setSearch] = useState("");
  const [ativo, setAtivo] = useState<"todos" | "ativos" | "inativos">("ativos");

  // paginacao
  const [page, setPage] = useState(0);
  const pageSize = 25;

  // dialog
  const [dialogOpen, setDialogOpen] = useState(false);
  const [dialogMode, setDialogMode] = useState<"create" | "edit">("create");
  const [editing, setEditing] = useState<Cliente | null>(null);
  const [dialogKey, setDialogKey] = useState(0);

  const { confirm, dialog: confirmDialog } = useConfirmDialog();

  const filtered = useMemo(() => {
    const list = [...rows];
    list.sort((a, b) => (a.nome ?? "").localeCompare(b.nome ?? "", "pt-BR"));
    return list;
  }, [rows]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize));
  const pageSafe = Math.min(page, totalPages - 1);
  const pagedRows = filtered.slice(pageSafe * pageSize, pageSafe * pageSize + pageSize);

  const load = useCallback(async () => {
    setErr(null);
    setOk(null);

    if (tenantEmpresaLoading) return;
    if (!tenantId) {
      setErr("Tenant não carregado.");
      return;
    }

    setLoadingList(true);

    try {
      let query = applyTenant(
        supabase
          .from("clientes")
          .select("id,tenant_id,nome,documento,email,telefone,endereco,observacoes,ativo,habilita_hh,criado_em,atualizado_em"),
        tenantId
      ).order("nome", { ascending: true });

      if (ativo === "ativos") query = query.eq("ativo", true);
      if (ativo === "inativos") query = query.eq("ativo", false);

      const term = search.trim();
      if (term) {
        query = query.or(`nome.ilike.%${term}%,documento.ilike.%${term}%`);
      }

      const { data, error } = await query.limit(1000);
      if (error) {
        setErr(error.message);
        setRows([]);
        return;
      }

      setRows((data ?? []) as unknown as Cliente[]);
      setPage(0);
    } finally {
      setLoadingList(false);
    }
  }, [ativo, search, supabase, tenantEmpresaLoading, tenantId]);

  useEffect(() => {
    void load();
  }, [load]);

  function openCreate() {
    setErr(null);
    setOk(null);
    setEditing(null);
    setDialogMode("create");
    setDialogKey((k) => k + 1);
    setDialogOpen(true);
  }

  function openEdit(row: Cliente) {
    setErr(null);
    setOk(null);
    setEditing(row);
    setDialogMode("edit");
    setDialogKey((k) => k + 1);
    setDialogOpen(true);
  }

  async function handleSave(form: ClienteForm) {
    setErr(null);
    setOk(null);

    if (!tenantId) throw new Error("Tenant não carregado.");
    if (!canEdit) throw new Error("Sem permissão para salvar clientes.");

    setBusy(true);

    try {
      const payload = {
        nome: form.nome.trim(),
        documento: form.documento.trim() || null,
        email: form.email.trim() || null,
        telefone: form.telefone.trim() || null,
        endereco: form.endereco.trim() || null,
        observacoes: form.observacoes.trim() || null,
        ativo: !!form.ativo,
        atualizado_em: new Date().toISOString(),
      };

      if (dialogMode === "edit" && editing) {
        const res = await applyTenant(supabase.from("clientes").update(payload), tenantId).eq("id", editing.id);
        if (res.error) {
          throw new Error(mapClienteError(res.error as SupabaseErrorLike));
        }
        setOk("Cliente atualizado!");
      } else {
        const res = await supabase
          .from("clientes")
          .insert({ tenant_id: tenantId, ...payload, ativo: true })
          .select("id")
          .single();

        if (res.error) {
          throw new Error(mapClienteError(res.error as SupabaseErrorLike));
        }

        setOk("Cliente criado!");
      }

      setDialogOpen(false);
      setEditing(null);
      await load();
    } finally {
      setBusy(false);
    }
  }

  async function toggleAtivo(row: Cliente) {
    if (!tenantId) return setErr("Tenant não carregado.");
    if (!canEdit) return setErr("Sem permissão para editar clientes.");

    const to = !row.ativo;
    const confirmed = await confirm({
      title: to ? "Ativar cliente?" : "Desativar cliente?",
      description: to
        ? "O cliente voltará a aparecer nas seleções."
        : "Desativar mantém histórico (Lucro Real).",
      confirmText: to ? "Ativar" : "Desativar",
      destructive: !to,
    });
    if (!confirmed) return;

    setBusy(true);
    setErr(null);
    setOk(null);

    const { error } = await applyTenant(
      supabase.from("clientes").update({ ativo: to, atualizado_em: new Date().toISOString() }),
      tenantId
    ).eq("id", row.id);

    setBusy(false);
    if (error) return setErr(mapClienteError(error as SupabaseErrorLike));

    setOk(to ? "Cliente ativado." : "Cliente desativado.");
    await load();
  }

  if (!ready && permissionsLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissões...</div>
    );
  }

  if (!canView) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;
  }

  return (
    <div className="space-y-5 w-full pb-10">
      {confirmDialog}

      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Clientes</h1>
          <p className="text-sm text-zinc-400 mt-1">Cadastro e gestão de clientes.</p>
        </div>

        <div className="flex items-center gap-2">
          {canEdit && (
            <button
              onClick={openCreate}
              className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-100 text-zinc-900 hover:bg-white font-medium shadow-sm"
            >
              Novo cliente
            </button>
          )}

          <button
            onClick={() => void load()}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>
        </div>
      </div>

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="grid grid-cols-1 md:grid-cols-[1.2fr_0.8fr] gap-3">
          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Busca (nome/documento)</div>
            <input
              aria-label="Buscar cliente"
              className="w-full px-3 py-2"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Digite parte do nome ou documento..."
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Ativo</div>
            <select
              aria-label="Filtrar por ativo"
              className="w-full px-3 py-2"
              value={ativo}
              onChange={(e) => setAtivo(e.target.value as typeof ativo)}
            >
              <option value="todos">Todos</option>
              <option value="ativos">Ativos</option>
              <option value="inativos">Inativos</option>
            </select>
          </div>
        </div>

        <div className="flex items-center gap-2 mt-3">
          <button
            onClick={() => void load()}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
            disabled={loadingList}
          >
            Buscar
          </button>
          <button
            onClick={() => {
              setSearch("");
              setAtivo("ativos");
            }}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Limpar
          </button>
        </div>

        {err && <div className="text-sm text-red-400 mt-3">{err}</div>}
        {ok && <div className="text-sm text-emerald-300 mt-3">{ok}</div>}
      </div>

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950 shadow-sm">
        <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-900/80">
          <div className="text-sm text-zinc-300">Lista de clientes</div>
          <div className="text-xs text-zinc-500">Exibindo {filtered.length} registro(s)</div>
        </div>

        {loadingList ? (
          <div className="px-4 py-6 text-zinc-400">Carregando...</div>
        ) : (
          <div className="overflow-auto max-h-[70vh]">
            <table className="w-full text-sm">
              <thead className="bg-zinc-900/70">
                <tr className="text-zinc-200">
                  <th className="px-4 py-3 text-left min-w-[240px]">Nome</th>
                  <th className="px-4 py-3 text-left">Documento</th>
                  <th className="px-4 py-3 text-left">Email</th>
                  <th className="px-4 py-3 text-left">Telefone</th>
                  <th className="px-4 py-3 text-center">Ativo</th>
                  <th className="px-4 py-3 text-center">Ações</th>
                </tr>
              </thead>

              <tbody className="divide-y divide-zinc-800">
                {pagedRows.map((r) => (
                  <tr
                    key={r.id}
                    className={canEdit ? "hover:bg-zinc-900/40 cursor-pointer" : "hover:bg-zinc-900/40"}
                    onClick={() => canEdit && openEdit(r)}
                  >
                    <td className="px-4 py-3">
                      <div className="font-medium text-zinc-100">{r.nome}</div>
                      <div className="text-xs text-zinc-500 tabular-nums">#{r.id}</div>
                    </td>
                    <td className="px-4 py-3 text-zinc-300 tabular-nums">{r.documento ?? "-"}</td>
                    <td className="px-4 py-3 text-zinc-300">{r.email ?? "-"}</td>
                    <td className="px-4 py-3 text-zinc-300">{r.telefone ?? "-"}</td>
                    <td className="px-4 py-3 text-center">{r.ativo ? "Sim" : "Não"}</td>
                    <td className="px-4 py-3 text-center" onClick={(e) => e.stopPropagation()}>
                      {canEdit ? (
                        <div className="flex items-center justify-center gap-2">
                          <button
                            type="button"
                            onClick={() => openEdit(r)}
                            className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                          >
                            Editar
                          </button>
                          <button
                            type="button"
                            onClick={() => void toggleAtivo(r)}
                            className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                          >
                            {r.ativo ? "Desativar" : "Ativar"}
                          </button>
                        </div>
                      ) : (
                        <span className="text-xs text-zinc-500">—</span>
                      )}
                    </td>
                  </tr>
                ))}

                {filtered.length === 0 && !loadingList && (
                  <tr>
                    <td colSpan={6} className="px-4 py-6 text-zinc-400">
                      Nenhum cliente encontrado.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        )}

        <div className="flex items-center justify-between px-4 py-3 border-t border-zinc-900/80 text-sm text-zinc-300">
          <div className="text-xs text-zinc-500">
            Página {pageSafe + 1} de {totalPages}
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60"
              disabled={pageSafe <= 0}
              onClick={() => setPage((p) => Math.max(0, p - 1))}
            >
              Anterior
            </button>
            <button
              type="button"
              className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60"
              disabled={pageSafe >= totalPages - 1}
              onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
            >
              Próxima
            </button>
          </div>
        </div>
      </div>

      <ClienteDialog
        key={dialogKey}
        open={dialogOpen}
        mode={dialogMode}
        initial={editing}
        busy={busy}
        canEdit={canEdit}
        onClose={() => {
          setDialogOpen(false);
          setEditing(null);
        }}
        onSave={handleSave}
      />
    </div>
  );
}
