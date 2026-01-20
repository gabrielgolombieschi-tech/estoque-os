"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { usePermissions } from "@/components/auth/PermissionsProvider";

const ADMIN_PERMISSION = "admin.manage_users";

type Role = {
  id: string;
  name: string | null;
};

type UserRow = {
  user_id: string;
  nome: string | null;
  email: string | null;
  status: string;
  roles: Role[];
};

type UsersResponse = {
  users: UserRow[];
  roles: Role[];
};

type CreateForm = {
  email: string;
  nome: string;
  roleIds: string[];
  tempPassword: string;
  sendInvite: boolean;
};

type EditForm = {
  nome: string;
  status: "active" | "inactive";
  roleIds: string[];
};

type ResetForm = {
  mode: "email" | "temp";
  tempPassword: string;
  confirmPassword: string;
};

function emptyCreateForm(): CreateForm {
  return {
    email: "",
    nome: "",
    roleIds: [],
    tempPassword: "",
    sendInvite: true,
  };
}

function emptyResetForm(): ResetForm {
  return {
    mode: "email",
    tempPassword: "",
    confirmPassword: "",
  };
}

export default function UsuariosPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { has, loading: permissionsLoading, ready } = usePermissions();

  const canManage = has(ADMIN_PERMISSION);

  const [rows, setRows] = useState<UserRow[]>([]);
  const [roles, setRoles] = useState<Role[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const [search, setSearch] = useState("");

  const [showCreate, setShowCreate] = useState(false);
  const [createForm, setCreateForm] = useState<CreateForm>(emptyCreateForm());

  const [editing, setEditing] = useState<UserRow | null>(null);
  const [editForm, setEditForm] = useState<EditForm>({
    nome: "",
    status: "active",
    roleIds: [],
  });

  const [resetting, setResetting] = useState<UserRow | null>(null);
  const [resetForm, setResetForm] = useState<ResetForm>(emptyResetForm());

  async function apiFetch<T>(url: string, init?: RequestInit): Promise<T> {
    const { data } = await supabase.auth.getSession();
    const token = data.session?.access_token;
    if (!token) {
      throw new Error("Sessao nao encontrada.");
    }

    const res = await fetch(url, {
      ...init,
      credentials: "include",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
        ...(init?.headers ?? {}),
      },
    });

    let payload: { error?: string } | null = null;
    let rawText: string | null = null;

    try {
      payload = (await res.json()) as { error?: string };
    } catch {
      rawText = await res.text().catch(() => "");
    }

    if (!res.ok) {
      const fallback = rawText?.trim()
        ? `Erro na requisicao (${res.status}): ${rawText.trim()}`
        : `Erro na requisicao (${res.status}).`;
      throw new Error(payload?.error ?? fallback);
    }

    return (payload ?? {}) as T;
  }

  async function load() {
    setErr(null);
    setOk(null);
    setLoading(true);
    try {
      const data = await apiFetch<UsersResponse>("/api/admin/users");
      setRows(data.users ?? []);
      setRoles(data.roles ?? []);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Erro ao carregar usuarios.";
      setErr(msg);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (!ready) return;
    if (!canManage) {
      setLoading(false);
      return;
    }
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, canManage]);

  function openCreate() {
    setErr(null);
    setOk(null);
    setCreateForm(emptyCreateForm());
    setShowCreate(true);
  }

  function closeCreate() {
    setShowCreate(false);
    setCreateForm(emptyCreateForm());
  }

  function openEdit(user: UserRow) {
    setErr(null);
    setOk(null);
    setEditing(user);
    setEditForm({
      nome: user.nome ?? "",
      status: user.status === "inactive" ? "inactive" : "active",
      roleIds: user.roles.map((r) => r.id),
    });
  }

  function closeEdit() {
    setEditing(null);
  }

  function openReset(user: UserRow) {
    setErr(null);
    setOk(null);
    setResetting(user);
    setResetForm(emptyResetForm());
  }

  function closeReset() {
    setResetting(null);
    setResetForm(emptyResetForm());
  }

  function toggleRole(selected: string[], roleId: string) {
    if (selected.includes(roleId)) {
      return selected.filter((id) => id !== roleId);
    }
    return [...selected, roleId];
  }

  async function handleCreate() {
    setBusy(true);
    setErr(null);
    setOk(null);

    try {
      if (!createForm.email.trim()) {
        throw new Error("Informe o email.");
      }
      if (!createForm.nome.trim()) {
        throw new Error("Informe o nome.");
      }
      if (!createForm.sendInvite && !createForm.tempPassword) {
        throw new Error("Informe senha temporaria ou envie convite.");
      }

      await apiFetch<{ ok: boolean }>("/api/admin/users", {
        method: "POST",
        body: JSON.stringify({
          email: createForm.email.trim(),
          nome: createForm.nome.trim(),
          roles: createForm.roleIds,
          tempPassword: createForm.sendInvite ? undefined : createForm.tempPassword,
          sendInvite: createForm.sendInvite,
        }),
      });

      setOk("Usuario criado.");
      closeCreate();
      await load();
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Erro ao criar usuario.";
      setErr(msg);
    } finally {
      setBusy(false);
    }
  }

  async function handleEdit() {
    if (!editing) return;
    setBusy(true);
    setErr(null);
    setOk(null);

    try {
      if (!editForm.nome.trim()) {
        throw new Error("Informe o nome.");
      }

      await apiFetch<{ ok: boolean }>(`/api/admin/users/${editing.user_id}`, {
        method: "PATCH",
        body: JSON.stringify({
          nome: editForm.nome.trim(),
          status: editForm.status,
          roles: editForm.roleIds,
        }),
      });

      setOk("Usuario atualizado.");
      closeEdit();
      await load();
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Erro ao atualizar usuario.";
      setErr(msg);
    } finally {
      setBusy(false);
    }
  }

  async function handleReset() {
    if (!resetting) return;
    setBusy(true);
    setErr(null);
    setOk(null);

    try {
      if (resetForm.mode === "temp") {
        if (!resetForm.tempPassword) {
          throw new Error("Informe a senha temporaria.");
        }
        if (resetForm.tempPassword !== resetForm.confirmPassword) {
          throw new Error("As senhas nao conferem.");
        }
      }

      await apiFetch<{ ok: boolean }>(`/api/admin/users/${resetting.user_id}/reset-password`, {
        method: "POST",
        body: JSON.stringify({
          mode: resetForm.mode,
          tempPassword: resetForm.mode === "temp" ? resetForm.tempPassword : undefined,
        }),
      });

      setOk(resetForm.mode === "email" ? "Email de redefinicao enviado." : "Senha temporaria atualizada.");
      closeReset();
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Erro ao resetar senha.";
      setErr(msg);
    } finally {
      setBusy(false);
    }
  }

  async function toggleStatus(user: UserRow, nextStatus: "active" | "inactive") {
    const confirmMsg = nextStatus === "inactive" ? "Desativar acesso deste usuario?" : "Ativar acesso deste usuario?";
    if (!confirm(confirmMsg)) return;

    setBusy(true);
    setErr(null);
    setOk(null);

    try {
      await apiFetch<{ ok: boolean }>(`/api/admin/users/${user.user_id}`, {
        method: "PATCH",
        body: JSON.stringify({ status: nextStatus }),
      });

      setOk(nextStatus === "inactive" ? "Usuario desativado." : "Usuario ativado.");
      await load();
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Erro ao atualizar status.";
      setErr(msg);
    } finally {
      setBusy(false);
    }
  }

  const filtered = rows.filter((row) => {
    const term = search.trim().toLowerCase();
    if (!term) return true;
    return (
      (row.nome ?? "").toLowerCase().includes(term) ||
      (row.email ?? "").toLowerCase().includes(term)
    );
  });

  if (!ready && permissionsLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando...
      </div>
    );
  }

  if (!canManage) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Acesso negado.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Usuarios</h1>
          <p className="text-sm text-zinc-400 mt-1">Gestao de usuarios e permissoes do tenant.</p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={openCreate}
            className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
          >
            Novo usuario
          </button>
          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>
        </div>
      </div>

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950 space-y-3">
        <div className="grid gap-3 md:grid-cols-[1fr_auto] items-end">
          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Buscar</div>
            <input
              className="w-full px-3 py-2"
              placeholder="Nome ou email"
              aria-label="Buscar usuarios"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Buscar
          </button>
        </div>

        {err && <div className="text-sm text-red-400">{err}</div>}
        {ok && <div className="text-sm text-emerald-300">{ok}</div>}
      </div>

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-4 py-3 text-left">Nome</th>
              <th className="px-4 py-3 text-left">Email</th>
              <th className="px-4 py-3 text-center">Status</th>
              <th className="px-4 py-3 text-left">Roles</th>
              <th className="px-4 py-3 text-center">Acoes</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-800">
            {loading && (
              <tr>
                <td colSpan={5} className="px-4 py-6 text-zinc-400">
                  Carregando usuarios...
                </td>
              </tr>
            )}

            {!loading &&
              filtered.map((user) => {
                const rolesLabel = user.roles.length
                  ? user.roles.map((r) => r.name ?? r.id).join(", ")
                  : "-";
                return (
                  <tr key={user.user_id} className="hover:bg-zinc-900/40">
                    <td className="px-4 py-3">
                      <div className="font-medium">{user.nome ?? "Sem nome"}</div>
                      <div className="text-xs text-zinc-500">{user.user_id}</div>
                    </td>
                    <td className="px-4 py-3 text-zinc-300">{user.email ?? "-"}</td>
                    <td className="px-4 py-3 text-center">
                      <span
                        className={`inline-flex items-center px-2 py-1 rounded-md text-xs border ${
                          user.status === "active"
                            ? "border-emerald-500/40 text-emerald-300"
                            : "border-amber-500/40 text-amber-300"
                        }`}
                      >
                        {user.status === "active" ? "Ativo" : "Inativo"}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-zinc-300">{rolesLabel}</td>
                    <td className="px-4 py-3 text-center">
                      <div className="flex items-center justify-center gap-2">
                        <button
                          onClick={() => openEdit(user)}
                          className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs"
                        >
                          Editar
                        </button>
                        <button
                          onClick={() => openReset(user)}
                          className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs"
                        >
                          Reset senha
                        </button>
                        <button
                          onClick={() => toggleStatus(user, user.status === "active" ? "inactive" : "active")}
                          disabled={busy}
                          className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs disabled:opacity-60"
                        >
                          {user.status === "active" ? "Desativar" : "Ativar"}
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}

            {!loading && filtered.length === 0 && (
              <tr>
                <td colSpan={5} className="px-4 py-6 text-zinc-400">
                  Nenhum usuario encontrado.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {showCreate && (
        <div
          className="fixed inset-0 z-40 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeCreate()}
        >
          <div
            className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden animate-[fadeIn_150ms_ease-out]"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div>
                <div className="font-semibold">Novo usuario</div>
                <div className="text-xs text-zinc-400 mt-0.5">Cadastre um usuario no tenant atual.</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={closeCreate}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                <button
                  onClick={handleCreate}
                  disabled={busy}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
                >
                  {busy ? "Salvando..." : "Salvar"}
                </button>
              </div>
            </div>

            <div className="p-5 space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Email *</div>
                  <input
                    className="w-full px-3 py-2"
                    aria-label="Email do usuario"
                    value={createForm.email}
                    onChange={(e) => setCreateForm((s) => ({ ...s, email: e.target.value }))}
                  />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Nome *</div>
                  <input
                    className="w-full px-3 py-2"
                    aria-label="Nome do usuario"
                    value={createForm.nome}
                    onChange={(e) => setCreateForm((s) => ({ ...s, nome: e.target.value }))}
                  />
                </div>
              </div>

              <div className="space-y-2">
                <div className="text-sm font-medium text-zinc-200">Roles</div>
                {roles.length === 0 ? (
                  <div className="text-xs text-zinc-500">Nenhuma role cadastrada.</div>
                ) : (
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
                    {roles.map((role) => (
                      <label key={role.id} className="flex items-center gap-2 text-sm text-zinc-200">
                        <input
                          type="checkbox"
                          checked={createForm.roleIds.includes(role.id)}
                          onChange={() =>
                            setCreateForm((s) => ({
                              ...s,
                              roleIds: toggleRole(s.roleIds, role.id),
                            }))
                          }
                        />
                        {role.name ?? role.id}
                      </label>
                    ))}
                  </div>
                )}
              </div>

              <div className="space-y-2 border border-zinc-800 rounded-lg p-3">
                <label className="flex items-center gap-2 text-sm text-zinc-200">
                  <input
                    type="checkbox"
                    checked={createForm.sendInvite}
                    onChange={(e) => setCreateForm((s) => ({ ...s, sendInvite: e.target.checked }))}
                  />
                  Enviar convite por email
                </label>

                {!createForm.sendInvite && (
                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Senha temporaria</div>
                    <input
                      type="password"
                      className="w-full px-3 py-2"
                      aria-label="Senha temporaria do usuario"
                      value={createForm.tempPassword}
                      onChange={(e) => setCreateForm((s) => ({ ...s, tempPassword: e.target.value }))}
                    />
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {editing && (
        <div
          className="fixed inset-0 z-40 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeEdit()}
        >
          <div
            className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden animate-[fadeIn_150ms_ease-out]"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div>
                <div className="font-semibold">Editar usuario</div>
                <div className="text-xs text-zinc-400 mt-0.5">Atualize dados e permissoes.</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={closeEdit}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                <button
                  onClick={handleEdit}
                  disabled={busy}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
                >
                  {busy ? "Salvando..." : "Salvar"}
                </button>
              </div>
            </div>

            <div className="p-5 space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Nome *</div>
                  <input
                    className="w-full px-3 py-2"
                    aria-label="Nome do usuario"
                    value={editForm.nome}
                    onChange={(e) => setEditForm((s) => ({ ...s, nome: e.target.value }))}
                  />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Status</div>
                  <select
                    className="w-full px-3 py-2"
                    aria-label="Status do usuario"
                    value={editForm.status}
                    onChange={(e) => setEditForm((s) => ({ ...s, status: e.target.value as EditForm["status"] }))}
                  >
                    <option value="active">Ativo</option>
                    <option value="inactive">Inativo</option>
                  </select>
                </div>
              </div>

              <div className="space-y-2">
                <div className="text-sm font-medium text-zinc-200">Roles</div>
                {roles.length === 0 ? (
                  <div className="text-xs text-zinc-500">Nenhuma role cadastrada.</div>
                ) : (
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
                    {roles.map((role) => (
                      <label key={role.id} className="flex items-center gap-2 text-sm text-zinc-200">
                        <input
                          type="checkbox"
                          checked={editForm.roleIds.includes(role.id)}
                          onChange={() =>
                            setEditForm((s) => ({
                              ...s,
                              roleIds: toggleRole(s.roleIds, role.id),
                            }))
                          }
                        />
                        {role.name ?? role.id}
                      </label>
                    ))}
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {resetting && (
        <div
          className="fixed inset-0 z-40 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeReset()}
        >
          <div
            className="w-full max-w-lg bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden animate-[fadeIn_150ms_ease-out]"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div>
                <div className="font-semibold">Reset de senha</div>
                <div className="text-xs text-zinc-400 mt-0.5">Escolha o metodo para redefinir.</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={closeReset}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                <button
                  onClick={handleReset}
                  disabled={busy}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
                >
                  {busy ? "Enviando..." : "Confirmar"}
                </button>
              </div>
            </div>

            <div className="p-5 space-y-4">
              <div className="space-y-2">
                <label className="flex items-center gap-2 text-sm text-zinc-200">
                  <input
                    type="radio"
                    name="reset-mode"
                    value="email"
                    checked={resetForm.mode === "email"}
                    onChange={() => setResetForm((s) => ({ ...s, mode: "email" }))}
                  />
                  Enviar email de redefinicao
                </label>
                <label className="flex items-center gap-2 text-sm text-zinc-200">
                  <input
                    type="radio"
                    name="reset-mode"
                    value="temp"
                    checked={resetForm.mode === "temp"}
                    onChange={() => setResetForm((s) => ({ ...s, mode: "temp" }))}
                  />
                  Definir senha temporaria
                </label>
              </div>

              {resetForm.mode === "temp" && (
                <div className="space-y-2">
                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Senha temporaria</div>
                    <input
                      type="password"
                      className="w-full px-3 py-2"
                      aria-label="Senha temporaria"
                      value={resetForm.tempPassword}
                      onChange={(e) => setResetForm((s) => ({ ...s, tempPassword: e.target.value }))}
                    />
                  </div>
                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Confirmar senha</div>
                    <input
                      type="password"
                      className="w-full px-3 py-2"
                      aria-label="Confirmar senha temporaria"
                      value={resetForm.confirmPassword}
                      onChange={(e) => setResetForm((s) => ({ ...s, confirmPassword: e.target.value }))}
                    />
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
