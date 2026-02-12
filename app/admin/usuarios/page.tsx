"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { useIsAdminTenant } from "@/lib/auth/useIsAdminTenant";

type RpcEmpresaLink = {
  empresa_id: string | null;
  empresa_nome: string | null;
  papel: string | null;
  ativo: boolean | null;
  deleted_at: string | null;
};

type RpcAdminUserRow = {
  usuario_id: string;
  auth_user_id: string | null;
  nome: string | null;
  email: string | null;
  telefone: string | null;
  usuario_ativo: boolean | null;
  tenant_papel: string | null;
  tenant_ativo: boolean | null;
  tenant_deleted_at: string | null;
  empresas: RpcEmpresaLink[] | null;
  usuario_created_at: string | null;
  usuario_updated_at: string | null;
};

type TenantRole = "OWNER" | "ADMIN" | "CONTADOR" | "GESTOR";
type EmpresaRole =
  | "ADMIN"
  | "FINANCEIRO"
  | "COORDENACAO"
  | "COMPRAS"
  | "ALMOXARIFADO"
  | "TECNICO"
  | "APONTAMENTO_RH"
  | "PAINEL_TV";

type EditUserForm = {
  nome: string;
  telefoneDigits: string;
  ativo: boolean;
};

type EditTenantForm = {
  papel: TenantRole;
  ativo: boolean;
};

type EditEmpresaItem = {
  ativo: boolean;
  papel: EmpresaRole;
};

const TENANT_ROLES: TenantRole[] = ["OWNER", "ADMIN", "CONTADOR", "GESTOR"];
const EMPRESA_ROLES: EmpresaRole[] = [
  "ADMIN",
  "FINANCEIRO",
  "COORDENACAO",
  "COMPRAS",
  "ALMOXARIFADO",
  "TECNICO",
  "APONTAMENTO_RH",
  "PAINEL_TV",
];

const FOCUSABLE_SELECTOR =
  "button, [href], input, select, textarea, [tabindex]:not([tabindex='-1'])";

function getFocusable(container: HTMLElement | null): HTMLElement[] {
  if (!container) return [];
  return Array.from(container.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)).filter(
    (el) => !el.hasAttribute("disabled") && el.getAttribute("aria-hidden") !== "true"
  );
}

function formatPhone(v: string | null) {
  const digits = (v ?? "").replace(/\D/g, "");
  if (!digits) return "-";
  if (digits.length === 10) return `(${digits.slice(0, 2)}) ${digits.slice(2, 6)}-${digits.slice(6)}`;
  if (digits.length === 11) return `(${digits.slice(0, 2)}) ${digits.slice(2, 7)}-${digits.slice(7)}`;
  return v ?? "-";
}

function onlyDigits(v: string) {
  return v.replace(/\D/g, "");
}

function safeTenantRole(v: unknown): TenantRole {
  const s = typeof v === "string" ? v.toUpperCase() : "";
  return (TENANT_ROLES.includes(s as TenantRole) ? s : "GESTOR") as TenantRole;
}

function safeEmpresaRole(v: unknown): EmpresaRole {
  const s = typeof v === "string" ? v.toUpperCase() : "";
  return (EMPRESA_ROLES.includes(s as EmpresaRole) ? s : "TECNICO") as EmpresaRole;
}

function getErrorText(err: unknown) {
  if (!err) return "";
  if (typeof err === "string") return err;
  if (typeof err === "object") {
    const e = err as { message?: unknown; details?: unknown; hint?: unknown; code?: unknown };
    return [e.message, e.details, e.hint, e.code].filter(Boolean).join(" ");
  }
  return String(err);
}

function getFriendlyRoleError(err: unknown): string | null {
  const t = getErrorText(err).toLowerCase();
  if (t.includes("invalid_tenant_role")) {
    return "Papel do tenant inválido. Use: OWNER, ADMIN, CONTADOR, GESTOR.";
  }
  if (t.includes("invalid_empresa_role")) {
    return "Papel da empresa inválido. Use: ADMIN, FINANCEIRO, COORDENACAO, COMPRAS, ALMOXARIFADO, TECNICO, APONTAMENTO_RH, PAINEL_TV.";
  }
  return null;
}

export default function AdminUsuariosPage() {
  const te = useTenantEmpresa();
  const tenantId = te.tenantId;
  const { isAdmin: isAdminTenant, loading: adminLoading, error: adminError } = useIsAdminTenant();

  const canManageUsers = Boolean(te.capabilities?.["admin.manage_users"] || te.capabilities?.["admin.users.manage"]);

  const [rows, setRows] = useState<RpcAdminUserRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const [search, setSearch] = useState("");
  const [debouncedSearch, setDebouncedSearch] = useState("");

  const [createOpen, setCreateOpen] = useState(false);
  const [createForm, setCreateForm] = useState<{ email: string; nome: string; telefoneDigits: string }>({
    email: "",
    nome: "",
    telefoneDigits: "",
  });
  const [createTenantPapel, setCreateTenantPapel] = useState<TenantRole>("GESTOR");
  const [createEmpresaForm, setCreateEmpresaForm] = useState<Record<string, EditEmpresaItem>>({});
  const [creating, setCreating] = useState(false);
  const [createErr, setCreateErr] = useState<string | null>(null);

  const [editOpen, setEditOpen] = useState(false);
  const [editRow, setEditRow] = useState<RpcAdminUserRow | null>(null);
  const [userForm, setUserForm] = useState<EditUserForm>({ nome: "", telefoneDigits: "", ativo: true });
  const [tenantForm, setTenantForm] = useState<EditTenantForm>({ papel: "GESTOR", ativo: true });
  const [empresaForm, setEmpresaForm] = useState<Record<string, EditEmpresaItem>>({});
  const [saving, setSaving] = useState(false);
  const [editErr, setEditErr] = useState<string | null>(null);

  const [passwordOpen, setPasswordOpen] = useState(false);
  const [passwordValue, setPasswordValue] = useState("");
  const [passwordBusy, setPasswordBusy] = useState(false);
  const [passwordErr, setPasswordErr] = useState<string | null>(null);

  const modalRef = useRef<HTMLDivElement | null>(null);
  const firstInputRef = useRef<HTMLInputElement | null>(null);

  const createModalRef = useRef<HTMLDivElement | null>(null);
  const createFirstInputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    const handle = setTimeout(() => setDebouncedSearch(search.trim().toLowerCase()), 250);
    return () => clearTimeout(handle);
  }, [search]);

  const filtered = useMemo(() => {
    if (!debouncedSearch) return rows;
    return rows.filter((r) => {
      const hay = `${r.nome ?? ""} ${r.email ?? ""} ${r.telefone ?? ""}`.toLowerCase();
      return hay.includes(debouncedSearch);
    });
  }, [debouncedSearch, rows]);

  const load = useCallback(async () => {
    setErr(null);
    setOk(null);
    if (!tenantId) {
      setRows([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    const supabase = getSupabaseBrowser();
    const { data, error } = await supabase.rpc("admin_list_users", { p_tenant_id: tenantId });

    if (error) {
      setErr(error.message ?? "Erro ao carregar usuários.");
      setRows([]);
      setLoading(false);
      return;
    }

    setRows((data ?? []) as unknown as RpcAdminUserRow[]);
    setLoading(false);
  }, [tenantId]);

  useEffect(() => {
    if (te.loading) return;
    if (adminLoading) return;
    if (!tenantId) return;
    if (!isAdminTenant) return;
    if (!canManageUsers) return;
    const t = setTimeout(() => {
      void load();
    }, 0);
    return () => clearTimeout(t);
  }, [adminLoading, canManageUsers, isAdminTenant, load, te.loading, tenantId]);

  const closeEdit = useCallback(() => {
    setEditOpen(false);
    setEditRow(null);
    setUserForm({ nome: "", telefoneDigits: "", ativo: true });
    setTenantForm({ papel: "GESTOR", ativo: true });
    setEmpresaForm({});
    setEditErr(null);
    setPasswordOpen(false);
    setPasswordValue("");
    setPasswordBusy(false);
    setPasswordErr(null);
  }, []);

  const resetPasswordByEmail = useCallback(async () => {
    if (!editRow?.auth_user_id) {
      setEditErr("Este usuário não possui auth_user_id.");
      return;
    }

    const okConfirm = confirm(
      "Enviar email de recuperação de senha para este usuário? (Ele receberá um link para redefinir a senha.)"
    );
    if (!okConfirm) return;

    setPasswordBusy(true);
    setPasswordErr(null);
    setOk(null);

    try {
      const supabase = getSupabaseBrowser();
      const { data: sess, error: sessErr } = await supabase.auth.getSession();
      const token = sess?.session?.access_token ?? null;
      if (sessErr || !token) {
        setPasswordErr("Sessão não encontrada. Faça login novamente.");
        setPasswordBusy(false);
        return;
      }

      const res = await fetch(`/api/admin/usuarios/${encodeURIComponent(editRow.auth_user_id)}/password`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ mode: "reset_email" }),
      });

      const payload = (await res.json().catch(() => null)) as { ok?: boolean; error?: string } | null;
      if (!res.ok) {
        setPasswordErr(payload?.error ?? "Erro ao enviar email de reset.");
        setPasswordBusy(false);
        return;
      }

      setOk("Email de recuperação enviado.");
      setPasswordBusy(false);
    } catch (e: unknown) {
      setPasswordErr(getErrorText(e) || "Erro ao enviar email de reset.");
      setPasswordBusy(false);
    }
  }, [editRow]);

  const setUserPassword = useCallback(async () => {
    if (!editRow?.auth_user_id) {
      setPasswordErr("Este usuário não possui auth_user_id.");
      return;
    }

    const nextPass = passwordValue;
    if (nextPass.length < 8) {
      setPasswordErr("Senha deve ter pelo menos 8 caracteres.");
      return;
    }

    setPasswordBusy(true);
    setPasswordErr(null);
    setOk(null);

    try {
      const supabase = getSupabaseBrowser();
      const { data: sess, error: sessErr } = await supabase.auth.getSession();
      const token = sess?.session?.access_token ?? null;
      if (sessErr || !token) {
        setPasswordErr("Sessão não encontrada. Faça login novamente.");
        setPasswordBusy(false);
        return;
      }

      const res = await fetch(`/api/admin/usuarios/${encodeURIComponent(editRow.auth_user_id)}/password`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ mode: "set_password", password: nextPass }),
      });

      const payload = (await res.json().catch(() => null)) as { ok?: boolean; error?: string } | null;
      if (!res.ok) {
        setPasswordErr(payload?.error ?? "Erro ao alterar senha.");
        setPasswordBusy(false);
        return;
      }

      setOk("Senha alterada com sucesso.");
      setPasswordValue("");
      setPasswordOpen(false);
      setPasswordBusy(false);
    } catch (e: unknown) {
      setPasswordErr(getErrorText(e) || "Erro ao alterar senha.");
      setPasswordBusy(false);
    }
  }, [editRow, passwordValue]);

  const closeCreate = useCallback(() => {
    setCreateOpen(false);
    setCreateForm({ email: "", nome: "", telefoneDigits: "" });
    setCreateTenantPapel("GESTOR");
    setCreateEmpresaForm({});
    setCreating(false);
    setCreateErr(null);
  }, []);

  const openCreate = useCallback(() => {
    if (!canManageUsers) return;
    setOk(null);
    setCreateErr(null);
    setCreateOpen(true);
    setCreateForm({ email: "", nome: "", telefoneDigits: "" });
    setCreateTenantPapel("GESTOR");

    const empresaMap: Record<string, EditEmpresaItem> = {};
    for (const e of te.empresas ?? []) {
      empresaMap[e.id] = { ativo: false, papel: "TECNICO" };
    }
    setCreateEmpresaForm(empresaMap);
  }, [canManageUsers, te.empresas]);

  const openEdit = useCallback(
    (row: RpcAdminUserRow) => {
      if (!canManageUsers) return;
      setEditRow(row);
      setEditOpen(true);
      setEditErr(null);
      setOk(null);
      setUserForm({
        nome: row.nome ?? "",
        telefoneDigits: onlyDigits(row.telefone ?? "").slice(0, 11),
        ativo: row.usuario_ativo ?? true,
      });
      setTenantForm({
        papel: safeTenantRole(row.tenant_papel),
        ativo: row.tenant_ativo ?? true,
      });

      const empresaMap: Record<string, EditEmpresaItem> = {};
      const links = Array.isArray(row.empresas) ? row.empresas : [];
      const linksByEmpresaId = new Map<string, RpcEmpresaLink>();
      for (const link of links) {
        if (!link?.empresa_id) continue;
        linksByEmpresaId.set(String(link.empresa_id), link);
      }

      for (const e of te.empresas ?? []) {
        const existing = linksByEmpresaId.get(e.id) ?? null;
        empresaMap[e.id] = {
          ativo: existing?.ativo ?? false,
          papel: safeEmpresaRole(existing?.papel),
        };
      }
      setEmpresaForm(empresaMap);
    },
    [canManageUsers, te.empresas]
  );

  useEffect(() => {
    if (!createOpen) return;

    const previousFocus = document.activeElement as HTMLElement | null;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        closeCreate();
        return;
      }
      if (e.key !== "Tab") return;
      const focusable = getFocusable(createModalRef.current);
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    };

    document.addEventListener("keydown", handleKeyDown);
    requestAnimationFrame(() => createFirstInputRef.current?.focus());

    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      previousFocus?.focus?.();
    };
  }, [closeCreate, createOpen]);

  useEffect(() => {
    if (!editOpen) return;

    const previousFocus = document.activeElement as HTMLElement | null;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        closeEdit();
        return;
      }
      if (e.key !== "Tab") return;
      const focusable = getFocusable(modalRef.current);
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    };

    document.addEventListener("keydown", handleKeyDown);
    requestAnimationFrame(() => firstInputRef.current?.focus());

    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      previousFocus?.focus?.();
    };
  }, [closeEdit, editOpen]);

  const inviteUser = useCallback(async () => {
    if (!tenantId) return;
    setCreating(true);
    setCreateErr(null);
    setOk(null);

    const email = createForm.email.trim().toLowerCase();
    const nome = createForm.nome.trim();
    if (!email) {
      setCreateErr("Email é obrigatório.");
      setCreating(false);
      return;
    }
    if (!nome) {
      setCreateErr("Nome é obrigatório.");
      setCreating(false);
      return;
    }

    const telefone = onlyDigits(createForm.telefoneDigits).slice(0, 20);
    const supabase = getSupabaseBrowser();
    const { data: sess, error: sessErr } = await supabase.auth.getSession();
    const token = sess?.session?.access_token ?? null;
    if (sessErr || !token) {
      setCreateErr("Sessão não encontrada. Faça login novamente.");
      setCreating(false);
      return;
    }

    const empresas = te.empresas ?? [];
    const empresaVinculos = empresas.map((e) => {
      const item = createEmpresaForm[e.id] ?? { ativo: false, papel: "TECNICO" as EmpresaRole };
      return { empresa_id: e.id, papel: item.papel, ativo: item.ativo };
    });

    try {
      const res = await fetch("/api/admin/invite-user", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          tenantId,
          email,
          nome,
          telefone: telefone ? telefone : null,
          tenantPapel: createTenantPapel,
          empresaVinculos,
        }),
      });

      const payload = (await res.json().catch(() => null)) as { ok?: boolean; error?: string } | null;
      if (!res.ok) {
        const msg = payload?.error ?? "Erro ao criar usuário.";
        setCreateErr(getFriendlyRoleError(msg) ?? msg);
        setCreating(false);
        return;
      }

      setOk("Usuário criado/convidado com sucesso.");
      setCreating(false);
      closeCreate();
      await load();
    } catch (e: unknown) {
      setCreateErr(getErrorText(e) || "Erro ao criar usuário.");
      setCreating(false);
    }
  }, [
    closeCreate,
    createEmpresaForm,
    createForm.email,
    createForm.nome,
    createForm.telefoneDigits,
    createTenantPapel,
    load,
    te.empresas,
    tenantId,
  ]);

  const save = useCallback(async () => {
    if (!tenantId || !editRow) return;
    setSaving(true);
    setEditErr(null);
    setOk(null);

    const supabase = getSupabaseBrowser();

    const nome = userForm.nome.trim();
    if (!nome) {
      setEditErr("Nome é obrigatório.");
      setSaving(false);
      return;
    }

    const telefone = onlyDigits(userForm.telefoneDigits).slice(0, 20);
    const { error: userErr } = await supabase.rpc("admin_update_user", {
      p_tenant_id: tenantId,
      p_usuario_id: editRow.usuario_id,
      p_nome: nome,
      p_telefone: telefone ? telefone : null,
      p_ativo: userForm.ativo,
    });

    if (userErr) {
      setEditErr(userErr.message ?? "Erro ao salvar usuário.");
      setSaving(false);
      return;
    }

    const { error: tenantErr } = await supabase.rpc("admin_set_user_tenant_role", {
      p_tenant_id: tenantId,
      p_usuario_id: editRow.usuario_id,
      p_papel: tenantForm.papel,
      p_ativo: tenantForm.ativo,
    });

    if (tenantErr) {
      setEditErr(getFriendlyRoleError(tenantErr) ?? tenantErr.message ?? "Erro ao salvar papel do tenant.");
      setSaving(false);
      return;
    }

    const empresas = te.empresas ?? [];
    for (const e of empresas) {
      const item = empresaForm[e.id] ?? { ativo: false, papel: "TECNICO" as EmpresaRole };
      const { error: empErr } = await supabase.rpc("admin_set_user_empresa", {
        p_tenant_id: tenantId,
        p_empresa_id: e.id,
        p_usuario_id: editRow.usuario_id,
        p_papel: item.papel,
        p_ativo: item.ativo,
      });
      if (empErr) {
        setEditErr(getFriendlyRoleError(empErr) ?? empErr.message ?? `Erro ao salvar empresa ${e.nome_fantasia ?? e.id}.`);
        setSaving(false);
        return;
      }
    }

    setOk("Usuário atualizado.");
    setSaving(false);
    closeEdit();
    await load();
    await te.refreshCapabilities?.();
  }, [closeEdit, editRow, empresaForm, load, te, tenantForm, tenantId, userForm]);

  if (te.loading || adminLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando...</div>;
  }

  if (!tenantId) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Tenant não encontrado.</div>;
  }

  if (!isAdminTenant) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Acesso negado.
        {adminError ? <span className="ml-2 text-zinc-500">({adminError})</span> : null}
      </div>
    );
  }

  if (!canManageUsers) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;
  }

  return (
    <div className="mx-auto max-w-6xl px-4 py-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold text-zinc-100">Usuários</h1>
          <p className="text-sm text-zinc-400">Administração de usuários e acessos por tenant/empresa.</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={openCreate}
            className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
          >
            Novo usuário
          </button>
          <button
            type="button"
            onClick={() => void load()}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm text-zinc-200"
          >
            Recarregar lista
          </button>
        </div>
      </div>

      <div className="mt-4 flex items-center gap-3">
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Buscar por nome, email ou telefone..."
          className="w-full max-w-md px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 text-zinc-100 placeholder:text-zinc-600"
        />
        {loading && <div className="text-sm text-zinc-400">Carregando...</div>}
      </div>

      {err && <div className="mt-3 text-sm text-red-400">{err}</div>}
      {ok && <div className="mt-3 text-sm text-emerald-400">{ok}</div>}

      <div className="mt-4 overflow-x-auto rounded-md border border-zinc-800">
        <table className="w-full text-sm">
          <thead className="bg-zinc-950/60 text-zinc-400">
            <tr>
              <th className="text-left p-3 font-medium">Nome</th>
              <th className="text-left p-3 font-medium">Email</th>
              <th className="text-left p-3 font-medium">Telefone</th>
              <th className="text-left p-3 font-medium">Papel (Tenant)</th>
              <th className="text-left p-3 font-medium">Ativo (Tenant)</th>
              <th className="text-left p-3 font-medium">Empresas</th>
              <th className="text-right p-3 font-medium">Ações</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-800">
            {filtered.map((r) => {
              const links = Array.isArray(r.empresas) ? r.empresas : [];
              const activeCount = links.filter((l) => l?.ativo && !l?.deleted_at).length;
              const empresasLabel = activeCount ? `${activeCount} ativas` : "—";
              return (
                <tr key={r.usuario_id} className="text-zinc-200">
                  <td className="p-3">{r.nome ?? "—"}</td>
                  <td className="p-3">{r.email ?? "—"}</td>
                  <td className="p-3">{formatPhone(r.telefone)}</td>
                  <td className="p-3">{r.tenant_papel ?? "—"}</td>
                  <td className="p-3">
                    <span className={r.tenant_ativo ? "text-emerald-300" : "text-zinc-500"}>
                      {r.tenant_ativo ? "Sim" : "Não"}
                    </span>
                  </td>
                  <td className="p-3 text-zinc-400">{empresasLabel}</td>
                  <td className="p-3 text-right">
                    <button
                      type="button"
                      onClick={() => openEdit(r)}
                      className="px-2 py-1 rounded border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-200"
                    >
                      Editar
                    </button>
                  </td>
                </tr>
              );
            })}
            {!loading && filtered.length === 0 && (
              <tr>
                <td colSpan={7} className="p-6 text-center text-zinc-500">
                  Nenhum usuário encontrado.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {createOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-black/60" onClick={closeCreate} />
          <div
            ref={createModalRef}
            role="dialog"
            aria-modal="true"
            className="relative w-full max-w-3xl rounded-lg border border-zinc-800 bg-zinc-950 p-4 shadow-xl"
          >
            <div className="flex items-start justify-between gap-4">
              <div>
                <div className="text-sm text-zinc-400">Novo usuário</div>
                <div className="text-sm text-zinc-500">Cria/convida no Auth e finaliza no banco.</div>
              </div>
              <button
                type="button"
                onClick={closeCreate}
                className="px-2 py-1 rounded border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-200"
              >
                Fechar
              </button>
            </div>

            {createErr && <div className="mt-3 text-sm text-red-400">{createErr}</div>}

            <div className="mt-4 grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-4">
                <div className="rounded-md border border-zinc-800 p-3">
                  <div className="text-sm font-medium text-zinc-200 mb-2">Usuário</div>

                  <label className="block text-xs text-zinc-400 mb-1">Email *</label>
                  <input
                    ref={createFirstInputRef}
                    value={createForm.email}
                    onChange={(e) => setCreateForm((prev) => ({ ...prev, email: e.target.value }))}
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 text-zinc-100"
                    inputMode="email"
                    placeholder="email@exemplo.com"
                  />

                  <label className="mt-3 block text-xs text-zinc-400 mb-1">Nome *</label>
                  <input
                    value={createForm.nome}
                    onChange={(e) => setCreateForm((prev) => ({ ...prev, nome: e.target.value }))}
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 text-zinc-100"
                    placeholder="Nome do usuário"
                  />

                  <label className="mt-3 block text-xs text-zinc-400 mb-1">Telefone</label>
                  <input
                    inputMode="tel"
                    value={createForm.telefoneDigits ? formatPhone(createForm.telefoneDigits) : ""}
                    onChange={(e) => {
                      const digits = onlyDigits(e.target.value).slice(0, 11);
                      setCreateForm((prev) => ({ ...prev, telefoneDigits: digits }));
                    }}
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 text-zinc-100"
                    placeholder="(00) 00000-0000"
                  />
                  <div className="mt-1 text-[11px] text-zinc-500">Ao salvar, envia somente números.</div>
                </div>

                <div className="rounded-md border border-zinc-800 p-3">
                  <div className="text-sm font-medium text-zinc-200 mb-2">Tenant</div>
                  <label className="block text-xs text-zinc-400 mb-1">Papel</label>
                  <select
                    title="Papel (tenant)"
                    aria-label="Papel (tenant)"
                    value={createTenantPapel}
                    onChange={(e) => setCreateTenantPapel(safeTenantRole(e.target.value))}
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 text-zinc-100"
                  >
                    {TENANT_ROLES.map((r) => (
                      <option key={r} value={r}>
                        {r}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="rounded-md border border-zinc-800 p-3">
                <div className="text-sm font-medium text-zinc-200 mb-2">Vínculos (Empresas)</div>
                <div className="max-h-[50vh] overflow-auto pr-1 space-y-2">
                  {(te.empresas ?? []).map((e) => {
                    const item = createEmpresaForm[e.id] ?? { ativo: false, papel: "TECNICO" as EmpresaRole };
                    return (
                      <div key={e.id} className="rounded border border-zinc-800 p-2">
                        <div className="flex items-start justify-between gap-3">
                          <div>
                            <div className="text-sm text-zinc-200">{e.nome_fantasia ?? e.razao_social ?? e.id}</div>
                            <div className="text-xs text-zinc-500">{e.id}</div>
                          </div>
                          <label className="flex items-center gap-2 text-sm text-zinc-200">
                            <input
                              type="checkbox"
                              checked={item.ativo}
                              onChange={(ev) =>
                                setCreateEmpresaForm((prev) => ({
                                  ...prev,
                                  [e.id]: { ...item, ativo: ev.target.checked },
                                }))
                              }
                            />
                            Ativo
                          </label>
                        </div>
                        <div className="mt-2">
                          <label className="block text-xs text-zinc-400 mb-1">Papel</label>
                          <select
                            title={`Papel empresa ${e.nome_fantasia ?? e.razao_social ?? e.id}`}
                            aria-label={`Papel empresa ${e.nome_fantasia ?? e.razao_social ?? e.id}`}
                            value={item.papel}
                            onChange={(ev) =>
                              setCreateEmpresaForm((prev) => ({
                                ...prev,
                                [e.id]: { ...item, papel: safeEmpresaRole(ev.target.value) },
                              }))
                            }
                            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 text-zinc-100 disabled:opacity-60"
                            disabled={!item.ativo}
                          >
                            {EMPRESA_ROLES.map((r) => (
                              <option key={r} value={r}>
                                {r}
                              </option>
                            ))}
                          </select>
                        </div>
                      </div>
                    );
                  })}
                  {(te.empresas ?? []).length === 0 && (
                    <div className="text-sm text-zinc-500">Nenhuma empresa disponível no contexto.</div>
                  )}
                </div>
              </div>
            </div>

            <div className="mt-4 flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={closeCreate}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm text-zinc-200"
                disabled={creating}
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={() => void inviteUser()}
                className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
                disabled={creating}
              >
                {creating ? "Salvando..." : "Salvar"}
              </button>
            </div>
          </div>
        </div>
      )}

      {editOpen && editRow && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-black/60" onClick={closeEdit} />
          <div
            ref={modalRef}
            role="dialog"
            aria-modal="true"
            className="relative w-full max-w-3xl rounded-lg border border-zinc-800 bg-zinc-950 p-4 shadow-xl"
          >
            <div className="flex items-start justify-between gap-4">
              <div>
                <div className="text-sm text-zinc-400">Editar usuário</div>
                <div className="text-lg font-semibold text-zinc-100">{editRow.nome ?? editRow.email ?? "Usuário"}</div>
                <div className="text-sm text-zinc-500">{editRow.email ?? "-"}</div>
              </div>
              <button
                type="button"
                onClick={closeEdit}
                className="px-2 py-1 rounded border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-200"
              >
                Fechar
              </button>
            </div>

            {editErr && <div className="mt-3 text-sm text-red-400">{editErr}</div>}

            <div className="mt-4 grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-4">
                <div className="rounded-md border border-zinc-800 p-3">
                  <div className="text-sm font-medium text-zinc-200 mb-2">Usuário</div>

                  <label className="block text-xs text-zinc-400 mb-1">Nome</label>
                  <input
                    ref={firstInputRef}
                    aria-label="Nome"
                    title="Nome"
                    value={userForm.nome}
                    onChange={(e) => setUserForm((prev) => ({ ...prev, nome: e.target.value }))}
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 text-zinc-100"
                  />

                  <label className="mt-3 block text-xs text-zinc-400 mb-1">Email</label>
                  <div className="w-full px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 text-zinc-400 break-all">
                    {editRow.email ?? "-"}
                  </div>

                  <label className="mt-3 block text-xs text-zinc-400 mb-1">Telefone</label>
                  <input
                    inputMode="tel"
                    value={userForm.telefoneDigits ? formatPhone(userForm.telefoneDigits) : ""}
                    onChange={(e) => {
                      const digits = onlyDigits(e.target.value).slice(0, 11);
                      setUserForm((prev) => ({ ...prev, telefoneDigits: digits }));
                    }}
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 text-zinc-100"
                    placeholder="(00) 00000-0000"
                  />
                  <div className="mt-1 text-[11px] text-zinc-500">Ao salvar, envia somente números.</div>

                  <label className="mt-3 flex items-center gap-2 text-sm text-zinc-200">
                    <input
                      type="checkbox"
                      checked={userForm.ativo}
                      onChange={(e) => setUserForm((prev) => ({ ...prev, ativo: e.target.checked }))}
                    />
                    Ativo
                  </label>

                  <div className="mt-3 text-[11px] text-zinc-500">
                    <div className="font-mono break-all">usuario_id: {editRow.usuario_id}</div>
                    <div className="font-mono break-all">auth_user_id: {editRow.auth_user_id ?? "-"}</div>
                  </div>
                </div>

                <div className="rounded-md border border-zinc-800 p-3">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <div className="text-sm font-medium text-zinc-200">Senha</div>
                      <div className="text-xs text-zinc-500">Apenas TENANT OWNER (validado no server).</div>
                    </div>
                    <button
                      type="button"
                      onClick={() => setPasswordOpen((v) => !v)}
                      className="px-2 py-1 rounded border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-200 text-xs disabled:opacity-60"
                      disabled={passwordBusy}
                      title=""
                    >
                      {passwordOpen ? "Fechar" : "Ações"}
                    </button>
                  </div>

                  {passwordErr && <div className="mt-2 text-sm text-red-400">{passwordErr}</div>}

                  {passwordOpen && (
                    <div className="mt-3 space-y-3">
                      <button
                        type="button"
                        onClick={() => void resetPasswordByEmail()}
                        className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm text-zinc-200 disabled:opacity-60"
                        disabled={passwordBusy || !editRow.auth_user_id}
                      >
                        Reset password (enviar email)
                      </button>

                      <div className="space-y-2">
                        <div className="text-xs text-zinc-400">Alterar senha (definir manualmente)</div>
                        <input
                          type="password"
                          value={passwordValue}
                          onChange={(e) => setPasswordValue(e.target.value)}
                          className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 text-zinc-100"
                          placeholder="Nova senha (mín. 8 caracteres)"
                          title="Nova senha"
                          aria-label="Nova senha"
                          disabled={passwordBusy}
                        />
                        <button
                          type="button"
                          onClick={() => void setUserPassword()}
                          className="w-full px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
                          disabled={passwordBusy || passwordValue.length < 8 || !editRow.auth_user_id}
                        >
                          {passwordBusy ? "Salvando..." : "Salvar nova senha"}
                        </button>
                      </div>
                    </div>
                  )}
                </div>

                <div className="rounded-md border border-zinc-800 p-3">
                  <div className="text-sm font-medium text-zinc-200 mb-2">Tenant</div>
                  <label className="block text-xs text-zinc-400 mb-1">Papel</label>
                  <select
                    title="Papel (tenant)"
                    aria-label="Papel (tenant)"
                    value={tenantForm.papel}
                    onChange={(e) => setTenantForm((prev) => ({ ...prev, papel: safeTenantRole(e.target.value) }))}
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 text-zinc-100"
                  >
                    {TENANT_ROLES.map((r) => (
                      <option key={r} value={r}>
                        {r}
                      </option>
                    ))}
                  </select>

                  <label className="mt-3 flex items-center gap-2 text-sm text-zinc-200">
                    <input
                      type="checkbox"
                      checked={tenantForm.ativo}
                      onChange={(e) => setTenantForm((prev) => ({ ...prev, ativo: e.target.checked }))}
                    />
                    Ativo no tenant
                  </label>
                </div>
              </div>

              <div className="rounded-md border border-zinc-800 p-3">
                <div className="text-sm font-medium text-zinc-200 mb-2">Empresas</div>
                <div className="max-h-[50vh] overflow-auto pr-1 space-y-2">
                  {(te.empresas ?? []).map((e) => {
                    const item = empresaForm[e.id] ?? { ativo: false, papel: "TECNICO" as EmpresaRole };
                    return (
                      <div key={e.id} className="rounded border border-zinc-800 p-2">
                        <div className="flex items-start justify-between gap-3">
                          <div>
                            <div className="text-sm text-zinc-200">{e.nome_fantasia ?? e.razao_social ?? e.id}</div>
                            <div className="text-xs text-zinc-500">{e.id}</div>
                          </div>
                          <label className="flex items-center gap-2 text-sm text-zinc-200">
                            <input
                              type="checkbox"
                              checked={item.ativo}
                              onChange={(ev) =>
                                setEmpresaForm((prev) => ({
                                  ...prev,
                                  [e.id]: { ...item, ativo: ev.target.checked },
                                }))
                              }
                            />
                            Ativo
                          </label>
                        </div>
                        <div className="mt-2">
                          <label className="block text-xs text-zinc-400 mb-1">Papel</label>
                          <select
                            title={`Papel empresa ${e.nome_fantasia ?? e.razao_social ?? e.id}`}
                            aria-label={`Papel empresa ${e.nome_fantasia ?? e.razao_social ?? e.id}`}
                            value={item.papel}
                            onChange={(ev) =>
                              setEmpresaForm((prev) => ({
                                ...prev,
                                [e.id]: { ...item, papel: safeEmpresaRole(ev.target.value) },
                              }))
                            }
                            className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-950 text-zinc-100 disabled:opacity-60"
                            disabled={!item.ativo}
                          >
                            {EMPRESA_ROLES.map((r) => (
                              <option key={r} value={r}>
                                {r}
                              </option>
                            ))}
                          </select>
                        </div>
                      </div>
                    );
                  })}
                  {(te.empresas ?? []).length === 0 && (
                    <div className="text-sm text-zinc-500">Nenhuma empresa disponível no contexto.</div>
                  )}
                </div>
              </div>
            </div>

            <div className="mt-4 flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={closeEdit}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm text-zinc-200"
                disabled={saving}
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={() => void save()}
                className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
                disabled={saving}
              >
                {saving ? "Salvando..." : "Salvar"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
