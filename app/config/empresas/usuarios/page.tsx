"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresaContext } from "@/lib/auth/TenantEmpresaProvider";
import { usePermissions } from "@/components/auth/PermissionsProvider";

type Profile = {
  id: string;
  email: string | null;
  nome: string | null;
};

type EmpresaRole =
  | "ADMIN"
  | "FINANCEIRO"
  | "FATURAMENTO"
  | "COORDENACAO"
  | "COMPRAS"
  | "ALMOXARIFADO"
  | "TECNICO"
  | "APONTAMENTO_RH"
  | "PAINEL_TV";

type UsuarioEmpresaRow = {
  id: string;
  usuario_id: string;
  empresa_id: string;
  papel: EmpresaRole;
  ativo: boolean;
};

type TenantMembershipRow = {
  usuario_id: string | null;
};

const roleOptions: EmpresaRole[] = [
  "ADMIN",
  "FINANCEIRO",
  "FATURAMENTO",
  "COORDENACAO",
  "COMPRAS",
  "ALMOXARIFADO",
  "TECNICO",
  "APONTAMENTO_RH",
  "PAINEL_TV",
];

function getErrorMessage(err: unknown, fallback: string) {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  if (err && typeof err === "object" && "message" in err) {
    const msg = (err as { message?: string }).message;
    if (typeof msg === "string" && msg.trim() !== "") return msg;
  }
  return fallback;
}

export default function EmpresaUsuariosPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const te = useTenantEmpresaContext();
  const tenantId = te.tenantId;
  const empresaId = te.empresaId;
  const empresas = te.empresas;
  const setEmpresaId = te.setEmpresaId;
  const tenantLoading = te.loading || !tenantId || !empresaId;
  const { has, loading: permLoading } = usePermissions();

  const [switchingEmpresa, setSwitchingEmpresa] = useState(false);
  const [users, setUsers] = useState<Profile[]>([]);
  const [memberships, setMemberships] = useState<UsuarioEmpresaRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [busyUserId, setBusyUserId] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  const isAdmin = has("admin.manage_users");

  useEffect(() => {
    let active = true;

    (async () => {
      if (!tenantId || !empresaId || permLoading || !isAdmin) {
        if (active) setLoading(false);
        return;
      }
      setLoading(true);
      setErr(null);

      try {
        const { data: tenantUsers, error: tenantUsersErr } = await supabase
          .schema("a")
          .from("usuario_tenant")
          .select("usuario_id")
          .eq("tenant_id", tenantId)
          .eq("ativo", true)
          .is("deleted_at", null);
        if (tenantUsersErr) throw tenantUsersErr;

        const tenantRows = (tenantUsers ?? []) as TenantMembershipRow[];
        const usuarioIds = Array.from(new Set(tenantRows.map((r) => r.usuario_id).filter(Boolean)));
        if (usuarioIds.length === 0) {
          if (active) {
            setUsers([]);
            setMemberships([]);
          }
          return;
        }

        const { data: profiles, error: profilesErr } = await supabase
          .schema("a")
          .from("usuario")
          .select("id,email,nome")
          .in("id", usuarioIds)
          .is("deleted_at", null)
          .order("email", { ascending: true });
        if (profilesErr) throw profilesErr;

        const { data: empresaUsers, error: empresaErr } = await supabase
          .schema("a")
          .from("usuario_empresa")
          .select("id,usuario_id,empresa_id,papel,ativo")
          .eq("empresa_id", empresaId)
          .is("deleted_at", null)
          .order("created_at", { ascending: true });
        if (empresaErr) throw empresaErr;

        if (active) {
          setUsers((profiles ?? []) as Profile[]);
          setMemberships((empresaUsers ?? []) as UsuarioEmpresaRow[]);
        }
      } catch (e: unknown) {
        if (active) setErr(getErrorMessage(e, "Erro ao carregar usuarios."));
      } finally {
        if (active) setLoading(false);
      }
    })();

    return () => {
      active = false;
    };
  }, [supabase, tenantId, empresaId, permLoading, isAdmin, reloadKey]);

  async function addMembership(userId: string) {
    if (!tenantId || !empresaId) return;
    setBusyUserId(userId);
    setErr(null);

    const existing = memberships.find((m) => m.usuario_id === userId && m.empresa_id === empresaId) ?? null;
    const payload = { usuario_id: userId, empresa_id: empresaId, papel: "TECNICO" as EmpresaRole, ativo: true };

    const { error } = existing?.id
      ? await supabase.schema("a").from("usuario_empresa").update(payload).eq("id", existing.id).is("deleted_at", null)
      : await supabase.schema("a").from("usuario_empresa").insert(payload);
    setBusyUserId(null);
    if (error) {
      setErr(error.message);
      return;
    }
    setReloadKey((prev) => prev + 1);
  }

  async function removeMembership(userId: string) {
    if (!tenantId || !empresaId) return;
    setBusyUserId(userId);
    setErr(null);
    const existing = memberships.find((m) => m.usuario_id === userId && m.empresa_id === empresaId) ?? null;
    if (!existing?.id) {
      setBusyUserId(null);
      return;
    }

    const { error } = await supabase
      .schema("a")
      .from("usuario_empresa")
      .update({ ativo: false })
      .eq("id", existing.id)
      .is("deleted_at", null);
    setBusyUserId(null);
    if (error) {
      setErr(error.message);
      return;
    }
    setReloadKey((prev) => prev + 1);
  }

  async function updateRole(membershipId: string, role: EmpresaRole) {
    if (!tenantId || !empresaId) return;
    setErr(null);
    const { error } = await supabase
      .schema("a")
      .from("usuario_empresa")
      .update({ papel: role })
      .eq("id", membershipId)
      .is("deleted_at", null);
    if (error) {
      setErr(error.message);
      return;
    }
    setReloadKey((prev) => prev + 1);
  }

  if (tenantLoading || permLoading || switchingEmpresa || loading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando...
      </div>
    );
  }

  if (!tenantId) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Tenant nao carregado.
      </div>
    );
  }

  if (!empresaId) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Empresa nao carregada.
      </div>
    );
  }

  if (!isAdmin) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Sem permissao para administrar usuarios de empresa.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Usuarios por empresa</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Vincule usuarios as empresas permitidas.
          </p>
        </div>
      </div>

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950 space-y-3">
        <div className="space-y-1">
          <div className="text-xs text-zinc-400">Empresa</div>
          <select
            aria-label="Selecionar empresa"
            className="w-full px-3 py-2"
            value={empresaId ?? ""}
            onChange={async (e) => {
              const next = e.target.value;
              if (!next || next === empresaId) return;
              setSwitchingEmpresa(true);
              try {
                await setEmpresaId(next);
                setReloadKey((prev) => prev + 1);
              } catch (e: unknown) {
                setErr(getErrorMessage(e, "Nao foi possivel trocar de empresa."));
              } finally {
                setSwitchingEmpresa(false);
              }
            }}
          >
            <option value="" disabled>
              Selecione
            </option>
            {empresas.map((empresa) => (
              <option key={empresa.id} value={empresa.id}>
                {empresa.nome_fantasia ?? empresa.razao_social ?? empresa.id}
              </option>
            ))}
          </select>
        </div>

        {err && <div className="text-sm text-red-400">{err}</div>}
      </div>

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-4 py-3 text-left">Usuario</th>
              <th className="px-4 py-3 text-left">Email</th>
              <th className="px-4 py-3 text-left">Role</th>
              <th className="px-4 py-3 text-center">Status</th>
              <th className="px-4 py-3 text-center">Acao</th>
            </tr>
          </thead>
            <tbody className="divide-y divide-zinc-800">
              {users.map((user) => {
              const membership = memberships.find((m) => m.usuario_id === user.id) ?? null;
              const isActive = Boolean(membership?.ativo);
              return (
                <tr key={user.id} className="hover:bg-zinc-900/40">
                  <td className="px-4 py-3">
                    {user.nome ?? user.id}
                  </td>
                  <td className="px-4 py-3 text-zinc-300">{user.email ?? "-"}</td>
                  <td className="px-4 py-3">
                    {isActive ? (
                      <select
                        aria-label="Selecionar role"
                        className="px-2 py-1 bg-zinc-900 border border-zinc-700 text-xs rounded"
                        value={membership?.papel ?? "TECNICO"}
                        onChange={(e) => updateRole(membership!.id, e.target.value as EmpresaRole)}
                      >
                        {roleOptions.map((role) => (
                          <option key={role} value={role}>
                            {role}
                          </option>
                        ))}
                      </select>
                    ) : (
                      <span className="text-xs text-zinc-500">-</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {isActive ? "Vinculado" : "Sem vinculo"}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {isActive ? (
                      <button
                        onClick={() => removeMembership(user.id)}
                        disabled={busyUserId === user.id}
                        className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs disabled:opacity-60"
                      >
                        Remover
                      </button>
                    ) : (
                      <button
                        onClick={() => addMembership(user.id)}
                        disabled={busyUserId === user.id}
                        className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs disabled:opacity-60"
                      >
                        Adicionar
                      </button>
                    )}
                  </td>
                </tr>
              );
            })}

            {users.length === 0 && (
              <tr>
                <td colSpan={5} className="px-4 py-6 text-zinc-400">
                  Nenhum usuario encontrado.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
