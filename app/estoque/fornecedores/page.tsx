"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import { upper, upperOrNull, upperTrim } from "@/lib/text";

type FornecedorFinalidade = "consumo" | "materia_prima" | "revenda" | "imobilizado" | "outros";

type Fornecedor = {
  id: number;
  tenant_id: string;
  nome: string;
  documento: string | null;
  email: string | null;
  telefone: string | null;
  endereco: string | null;
  observacoes: string | null;
  finalidade_padrao: FornecedorFinalidade | null;
  gerar_contas_pagar_auto: boolean;
  ativo: boolean;
  criado_em: string;
  atualizado_em: string;
};

type FornecedorForm = {
  nome: string;
  documento: string;
  email: string;
  telefone: string;
  endereco: string;
  observacoes: string;
  finalidade_padrao: "" | FornecedorFinalidade;
  gerar_contas_pagar_auto: boolean;
  ativo: boolean;
};

type SupabaseErrorLike = { code?: string; message?: string } | null | undefined;

function normalizeDigits(value: string): string {
  return value.replace(/\D/g, "").trim();
}

function isValidEmail(email: string): boolean {
  const v = email.trim();
  if (!v) return true;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);
}

function emptyForm(): FornecedorForm {
  return {
    nome: "",
    documento: "",
    email: "",
    telefone: "",
    endereco: "",
    observacoes: "",
    finalidade_padrao: "",
    gerar_contas_pagar_auto: false,
    ativo: true,
  };
}

function formatFinalidade(value: FornecedorFinalidade | null | undefined): string {
  if (!value) return "-";
  return value.replace(/_/g, " ");
}

function hasAny(caps: Capabilities | null, keys: CapabilityKey[]): boolean {
  return requireAny(caps, keys);
}

function mapFornecedorError(error: SupabaseErrorLike): string {
  const code = error?.code ?? "";
  const message = (error?.message ?? "").toLowerCase();

  if (code === "23505" || message.includes("duplicate") || message.includes("unique")) {
    return "Já existe fornecedor com este documento.";
  }

  return error?.message ?? "Erro inesperado.";
}

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

type FornecedorDialogProps = {
  open: boolean;
  mode: "create" | "edit";
  initial?: Fornecedor | null;
  busy: boolean;
  canEdit: boolean;
  onClose: () => void;
  onSave: (payload: FornecedorForm) => Promise<void>;
};

function FornecedorDialog({
  open,
  mode,
  initial,
  busy,
  canEdit,
  onClose,
  onSave,
}: FornecedorDialogProps) {
  const [err, setErr] = useState<string | null>(null);
  const [form, setForm] = useState<FornecedorForm>(() => {
    if (mode === "edit" && initial) {
      return {
        nome: upper(initial.nome),
        documento: upper(initial.documento),
        email: upper(initial.email),
        telefone: upper(initial.telefone),
        endereco: upper(initial.endereco),
        observacoes: upper(initial.observacoes),
        finalidade_padrao: (initial.finalidade_padrao ?? "") as FornecedorForm["finalidade_padrao"],
        gerar_contas_pagar_auto: Boolean(initial.gerar_contas_pagar_auto),
        ativo: !!initial.ativo,
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
      setErr("Sem permissão para salvar fornecedores.");
      return;
    }

    const nome = upperTrim(form.nome);
    if (!nome) {
      setErr("Nome é obrigatório.");
      return;
    }

    const digits = normalizeDigits(form.documento);
    if (digits && digits.length !== 11 && digits.length !== 14) {
      setErr("Documento deve ter 11 (CPF) ou 14 (CNPJ) dígitos.");
      return;
    }

    if (!isValidEmail(form.email)) {
      setErr("E-mail inválido.");
      return;
    }

    await onSave({
      ...form,
      nome,
      documento: upperTrim(form.documento),
      email: upperTrim(form.email),
      telefone: upperTrim(form.telefone),
      endereco: upperTrim(form.endereco),
      observacoes: upperTrim(form.observacoes),
    }).catch((e2: unknown) => {
      const msg = e2 instanceof Error ? e2.message : "Erro ao salvar.";
      setErr(msg);
    });
  };

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-[60] bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
      onClick={(e) => e.target === e.currentTarget && onClose()}
      role="presentation"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={mode === "edit" ? `Editar fornecedor #${initial?.id ?? ""}` : "Novo fornecedor"}
        className="w-full max-w-3xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
          <div>
            <div className="font-semibold">
              {mode === "edit" ? `Editar fornecedor #${initial?.id ?? ""}` : "Novo fornecedor"}
            </div>
            <div className="text-xs text-zinc-400 mt-0.5">Dados cadastrais do fornecedor.</div>
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
              form="fornecedor-form"
              disabled={busy || !canEdit}
              className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {busy ? "Salvando..." : "Salvar"}
            </button>
          </div>
        </div>

        <form id="fornecedor-form" onSubmit={onSubmit} className="p-5 space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div className="space-y-1 md:col-span-2">
              <div className="text-xs text-zinc-400">Nome *</div>
              <input
                autoFocus
                aria-label="Nome"
                className="w-full px-3 py-2"
                value={form.nome}
                onChange={(e) => setForm((s) => ({ ...s, nome: upper(e.target.value) }))}
              />
            </div>

            <div className="space-y-1">
              <div className="text-xs text-zinc-400">Documento (CPF/CNPJ)</div>
              <input
                aria-label="Documento"
                className="w-full px-3 py-2"
                value={form.documento}
                onChange={(e) => setForm((s) => ({ ...s, documento: upper(e.target.value) }))}
                placeholder="Somente números ou formatado"
              />
              <div className="text-[11px] text-zinc-500">
                Normalizado: {normalizeDigits(form.documento) || "-"}
              </div>
            </div>

            <div className="space-y-1">
              <div className="text-xs text-zinc-400">Finalidade padrão</div>
              <select
                aria-label="Finalidade padrão"
                className="w-full px-3 py-2"
                value={form.finalidade_padrao}
                onChange={(e) => setForm((s) => ({ ...s, finalidade_padrao: e.target.value as FornecedorForm["finalidade_padrao"] }))}
              >
                <option value="">(Sem)</option>
                <option value="consumo">Consumo</option>
                <option value="materia_prima">Matéria-prima</option>
                <option value="revenda">Revenda</option>
                <option value="imobilizado">Imobilizado</option>
                <option value="outros">Outros</option>
              </select>
            </div>

            <div className="space-y-1">
              <div className="text-xs text-zinc-400">E-mail</div>
              <input
                aria-label="E-mail"
                className="w-full px-3 py-2"
                value={form.email}
                onChange={(e) => setForm((s) => ({ ...s, email: upper(e.target.value) }))}
                placeholder="contato@fornecedor.com"
              />
            </div>

            <div className="space-y-1">
              <div className="text-xs text-zinc-400">Telefone</div>
              <input
                aria-label="Telefone"
                className="w-full px-3 py-2"
                value={form.telefone}
                onChange={(e) => setForm((s) => ({ ...s, telefone: upper(e.target.value) }))}
                placeholder="(xx) xxxxx-xxxx"
              />
            </div>

            <div className="space-y-1 md:col-span-2">
              <div className="text-xs text-zinc-400">Endereço</div>
              <textarea
                aria-label="Endereço"
                className="w-full px-3 py-2 min-h-[70px]"
                value={form.endereco}
                onChange={(e) => setForm((s) => ({ ...s, endereco: upper(e.target.value) }))}
              />
            </div>

            <div className="space-y-1 md:col-span-2">
              <div className="text-xs text-zinc-400">Observações</div>
              <textarea
                aria-label="Observações"
                className="w-full px-3 py-2 min-h-[90px]"
                value={form.observacoes}
                onChange={(e) => setForm((s) => ({ ...s, observacoes: upper(e.target.value) }))}
              />
            </div>

            <div className="md:col-span-2">
              <div className="flex items-start justify-between gap-3 border border-zinc-800 rounded-lg p-3">
                <div className="text-sm">
                  <div className="font-medium text-zinc-100">Financeiro</div>
                  <div className="text-xs text-zinc-400">
                    Quando habilitado, importações de XML deste fornecedor tentam gerar automaticamente contas a pagar.
                  </div>
                </div>
                <label className="text-sm text-zinc-300 flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={form.gerar_contas_pagar_auto}
                    onChange={(e) => setForm((s) => ({ ...s, gerar_contas_pagar_auto: e.target.checked }))}
                    disabled={!canEdit}
                  />
                  Gerar contas a pagar automaticamente
                </label>
              </div>
            </div>
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

export default function FornecedoresPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { tenantId, empresaId, empresa, loading: tenantEmpresaLoading, error: tenantEmpresaError } = useTenantEmpresa();
  const { loading: permissionsLoading, ready, capabilities } = usePermissions();

  const empresaPapel = String(empresa?.papel ?? "")
    .trim()
    .toUpperCase();
  const canAccessByPapel = Boolean(empresaPapel && ["ADMIN", "FINANCEIRO", "COORDENACAO", "COMPRAS"].includes(empresaPapel));

  const canView = hasAny(capabilities, ["estoque.read", "cad_fornecedores.write"]) || canAccessByPapel;
  const canEdit = hasAny(capabilities, ["estoque.write", "cad_fornecedores.write"]) || canAccessByPapel;
  const canDelete = empresaPapel === "ADMIN";

  const [rows, setRows] = useState<Fornecedor[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [loadingList, setLoadingList] = useState(false);

  // filtros
  const [search, setSearch] = useState("");
  const [ativo, setAtivo] = useState<"todos" | "ativos" | "inativos">("ativos");
  const [finalidade, setFinalidade] = useState<"todos" | FornecedorFinalidade>("todos");

  // paginacao
  const [page, setPage] = useState(0);
  const pageSize = 25;

  // dialog
  const [dialogOpen, setDialogOpen] = useState(false);
  const [dialogMode, setDialogMode] = useState<"create" | "edit">("create");
  const [editing, setEditing] = useState<Fornecedor | null>(null);
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
    if (!tenantId || !empresaId) {
      // Contexto ainda não disponível; evita manter dados antigos na tela.
      setRows([]);
      return;
    }

    setLoadingList(true);

    try {
      let query = applyTenantEmpresa(
        supabase
          .from("fornecedores")
          .select(
            "id,tenant_id,nome,documento,email,telefone,endereco,observacoes,finalidade_padrao,gerar_contas_pagar_auto,ativo,criado_em,atualizado_em"
          ),
        tenantId,
        empresaId
      ).order("nome", { ascending: true });

      if (ativo === "ativos") query = query.eq("ativo", true);
      if (ativo === "inativos") query = query.eq("ativo", false);
      if (finalidade !== "todos") query = query.eq("finalidade_padrao", finalidade);

      const term = search.trim();
      if (term) {
        // PostgREST OR syntax
        query = query.or(`nome.ilike.%${term}%,documento.ilike.%${term}%`);
      }

      const { data, error } = await query.limit(1000);
      if (error) {
        setErr(error.message);
        setRows([]);
        return;
      }

      setRows((data ?? []) as unknown as Fornecedor[]);
      setPage(0);
    } finally {
      setLoadingList(false);
    }
  }, [ativo, finalidade, search, supabase, tenantEmpresaLoading, tenantId, empresaId]);

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

  function openEdit(row: Fornecedor) {
    setErr(null);
    setOk(null);
    setEditing(row);
    setDialogMode("edit");
    setDialogKey((k) => k + 1);
    setDialogOpen(true);
  }

  async function handleSave(form: FornecedorForm) {
    setErr(null);
    setOk(null);

    if (!tenantId || !empresaId) throw new Error("Tenant ou empresa não carregados.");
    if (!canEdit) throw new Error("Sem permissão para salvar fornecedores.");

    setBusy(true);

    try {
      const payload = {
        nome: upperTrim(form.nome),
        documento: upperOrNull(form.documento),
        email: upperOrNull(form.email),
        telefone: upperOrNull(form.telefone),
        endereco: upperOrNull(form.endereco),
        observacoes: upperOrNull(form.observacoes),
        finalidade_padrao: form.finalidade_padrao || null,
        gerar_contas_pagar_auto: Boolean(form.gerar_contas_pagar_auto),
        ativo: !!form.ativo,
        atualizado_em: new Date().toISOString(),
      };

      if (dialogMode === "edit" && editing) {
        const res = await applyTenantEmpresa(supabase.from("fornecedores").update(payload), tenantId, empresaId).eq(
          "id",
          editing.id
        );
        if (res.error) {
          throw new Error(mapFornecedorError(res.error as SupabaseErrorLike));
        }

        setOk("Fornecedor atualizado!");
      } else {
        const res = await supabase
          .from("fornecedores")
          .insert({ tenant_id: tenantId, empresa_id: empresaId, ...payload, ativo: true })
          .select("id")
          .single();

        if (res.error) {
          throw new Error(mapFornecedorError(res.error as SupabaseErrorLike));
        }

        setOk("Fornecedor criado!");
      }

      setDialogOpen(false);
      setEditing(null);
      await load();
    } finally {
      setBusy(false);
    }
  }

  async function toggleAtivo(row: Fornecedor) {
    if (!tenantId || !empresaId) return setErr("Tenant ou empresa não carregados.");
    if (!canEdit) return setErr("Sem permissão para editar fornecedores.");

    const to = !row.ativo;
    const confirmed = await confirm({
      title: to ? "Ativar fornecedor?" : "Desativar fornecedor?",
      description: to
        ? "O fornecedor voltará a aparecer nas seleções."
        : "Desativar mantém histórico (Lucro Real).",
      confirmText: to ? "Ativar" : "Desativar",
      destructive: !to,
    });
    if (!confirmed) return;

    setBusy(true);
    setErr(null);
    setOk(null);

    const { error } = await applyTenantEmpresa(
      supabase.from("fornecedores").update({ ativo: to, atualizado_em: new Date().toISOString() }),
      tenantId,
      empresaId
    ).eq("id", row.id);

    setBusy(false);
    if (error) return setErr(mapFornecedorError(error as SupabaseErrorLike));

    setOk(to ? "Fornecedor ativado." : "Fornecedor desativado.");
    await load();
  }

  async function deleteFornecedor(row: Fornecedor) {
    if (!tenantId || !empresaId) return setErr("Tenant ou empresa não carregados.");
    if (!canDelete) return setErr("Sem permissão para excluir fornecedores.");

    const confirmed = await confirm({
      title: "Excluir definitivamente?",
      description:
        "Preferimos desativar para manter histórico. Tentaremos excluir; se houver vínculos fiscais/estoque, o fornecedor será desativado.",
      confirmText: "Excluir",
      destructive: true,
    });
    if (!confirmed) return;

    setBusy(true);
    setErr(null);
    setOk(null);

    const delRes = await applyTenantEmpresa(supabase.from("fornecedores").delete(), tenantId, empresaId).eq(
      "id",
      row.id
    );

    if (!delRes.error) {
      setBusy(false);
      setOk("Fornecedor excluído.");
      await load();
      return;
    }

    const code = (delRes.error as SupabaseErrorLike)?.code ?? "";
    const msg = ((delRes.error as SupabaseErrorLike)?.message ?? "").toLowerCase();
    const isFk = code === "23503" || msg.includes("foreign key") || msg.includes("violates foreign key");

    // fallback: desativar
    const updRes = await applyTenantEmpresa(
      supabase.from("fornecedores").update({ ativo: false, atualizado_em: new Date().toISOString() }),
      tenantId,
      empresaId
    ).eq("id", row.id);

    setBusy(false);

    if (updRes.error) {
      return setErr(mapFornecedorError(updRes.error as SupabaseErrorLike));
    }

    setOk(
      isFk
        ? "Não foi possível excluir pois há vínculos. Fornecedor foi desativado em vez disso."
        : "Fornecedor foi desativado (exclusão falhou)."
    );
    await load();
  }

  if (tenantEmpresaError) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300 p-6">{tenantEmpresaError}</div>
    );
  }

  if (tenantEmpresaLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando contexto...
      </div>
    );
  }

  if (!tenantId || !empresaId) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando contexto...
      </div>
    );
  }

  if (!ready && permissionsLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando permissões...
      </div>
    );
  }

  if (!canView) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>
    );
  }

  return (
    <div className="space-y-5 w-full pb-10">
      {confirmDialog}

      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Fornecedores</h1>
          <p className="text-sm text-zinc-400 mt-1">Cadastro e gestão de fornecedores.</p>
        </div>

        <div className="flex items-center gap-2">
          {canEdit && (
            <button
              onClick={openCreate}
              className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-100 text-zinc-900 hover:bg-white font-medium shadow-sm"
            >
              Novo fornecedor
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
        <div className="grid grid-cols-1 md:grid-cols-[1.2fr_0.8fr_0.8fr] gap-3">
          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Busca (nome/documento)</div>
            <input
              aria-label="Buscar fornecedor"
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

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Finalidade padrão</div>
            <select
              aria-label="Filtrar por finalidade"
              className="w-full px-3 py-2"
              value={finalidade}
              onChange={(e) => setFinalidade(e.target.value as typeof finalidade)}
            >
              <option value="todos">Todas</option>
              <option value="consumo">Consumo</option>
              <option value="materia_prima">Matéria-prima</option>
              <option value="revenda">Revenda</option>
              <option value="imobilizado">Imobilizado</option>
              <option value="outros">Outros</option>
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
              setFinalidade("todos");
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
          <div className="text-sm text-zinc-300">Lista de fornecedores</div>
          <div className="text-xs text-zinc-500">Exibindo {filtered.length} registro(s)</div>
        </div>

        {loadingList ? (
          <div className="px-4 py-6 text-zinc-400">Carregando...</div>
        ) : (
          <div className="overflow-auto max-h-[70vh]">
            <table className="w-full text-sm">
              <thead className="bg-zinc-900/70">
                <tr className="text-zinc-200">
                  <th className="px-4 py-3 text-left min-w-[260px]">Nome</th>
                  <th className="px-4 py-3 text-left">Documento</th>
                  <th className="px-4 py-3 text-left">Finalidade</th>
                  <th className="px-4 py-3 text-left">Contato</th>
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
                    <td className="px-4 py-3 text-zinc-300 capitalize">{formatFinalidade(r.finalidade_padrao)}</td>
                    <td className="px-4 py-3 text-zinc-300">
                      <div>{r.email ?? "-"}</div>
                      <div className="text-xs text-zinc-500">{r.telefone ?? ""}</div>
                    </td>
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
                          {canDelete && (
                            <button
                              type="button"
                              onClick={() => void deleteFornecedor(r)}
                              className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                            >
                              Excluir
                            </button>
                          )}
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
                      Nenhum fornecedor encontrado.
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

      <FornecedorDialog
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
