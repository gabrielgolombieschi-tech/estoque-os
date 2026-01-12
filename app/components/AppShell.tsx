"use client";

import Link from "next/link";
import { useContext, useEffect, useMemo, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { supabaseBrowser } from "../../lib/supabase/client";
import { ensureCurrentTenant } from "@/lib/tenant";
import { clearPermissionCache } from "@/lib/auth/permissions";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { EmpresaContext } from "@/app/components/EmpresaProvider";

type UserInfo = { id: string; email: string };
type TenantOption = {
  tenant_id: string;
  tenants?: { name: string | null }[] | null;
};

const isDev = process.env.NODE_ENV !== "production";
const logError = (...args: unknown[]) => {
  if (isDev) {
    console.warn(...args);
  }
};

export function useTenantBoot() {
  useEffect(() => {
    const supabase = supabaseBrowser();

    (async () => {
      try {
        await ensureCurrentTenant(supabase);
      } catch (e) {
        logError("Erro ao definir tenant atual:", e);
      }
    })();
  }, []);
}


export default function AppShell({ children }: { children: React.ReactNode }) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  useTenantBoot();
  const router = useRouter();
  const pathname = usePathname();
  const empresaCtx = useContext(EmpresaContext);
  const empresaId = empresaCtx?.empresaId ?? null;
  const empresas = empresaCtx?.empresas ?? [];
  const setEmpresaId = empresaCtx?.setEmpresaId ?? (() => {});
  const empresaLoading = empresaCtx?.loading ?? false;
  const empresaError = empresaCtx?.error ?? null;

  // Seu provider deve expor pelo menos clear() e idealmente reload()
  // Se não tiver reload(), remova do destructuring e as chamadas abaixo.
  const { clear, reload, has, refreshing, permissions } = usePermissions();

  const [booting, setBooting] = useState(true);
  const [userInfo, setUserInfo] = useState<UserInfo | null>(null);
  const [userRole, setUserRole] = useState<string | null>(null);
  const [tenants, setTenants] = useState<TenantOption[]>([]);
  const [tenantId, setTenantId] = useState<string | null>(null);
  const [tenantBusy, setTenantBusy] = useState(false);

  const isPublic = pathname === "/login";
  const isEmpresaSelection = pathname === "/selecionar-empresa";
  const isFullWidth = pathname === "/itens";
  const hideHeader = pathname?.startsWith("/projetos") || pathname?.startsWith("/execucao");

  const [openMenu, setOpenMenu] = useState<"os" | "estoque" | "financeiro" | null>(null);
  const navRef = useRef<HTMLDivElement | null>(null);
  const closeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // 1) Boot: pega sessão 1x e libera a UI (não trava esperando permissões)
  useEffect(() => {
    let active = true;

    (async () => {
      try {
        const { data, error } = await supabase.auth.getSession();
        if (!active) return;

        if (error) logError("getSession error:", error);

        const session = data.session;
        const user = session?.user;

        setUserInfo(user ? { id: user.id, email: user.email ?? "" } : null);
        setUserRole(null);

        // Recarrega permissões em background (sem travar)
        if (session) {
          reload().catch((e: unknown) => logError("reload permissions error:", e));
        }
      } finally {
        if (active) setBooting(false);
      }
    })();

    return () => {
      active = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 2) Listener de auth 1x (login/logout/troca sessão)
  useEffect(() => {
    const { data: sub } = supabase.auth.onAuthStateChange((_evt, session) => {
      clearPermissionCache();
      clear();

      const user = session?.user;
      setUserInfo(user ? { id: user.id, email: user.email ?? "" } : null);
      setUserRole(null);

      if (session) {
        reload().catch((e: unknown) => logError("reload permissions error:", e));
      }
    });

    return () => sub.subscription.unsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 3) Guard de rota
  useEffect(() => {
    if (booting) return;

    const isAuthed = !!userInfo?.id;
    if (!isAuthed && !isPublic) router.replace("/login");
    if (isAuthed && isPublic) router.replace("/");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [booting, userInfo?.id, pathname]);

  useEffect(() => {
    if (booting || isPublic || isEmpresaSelection) return;
    if (!userInfo?.id) return;
    if (empresaLoading) return;
    if (!empresaId && empresas.length > 1) {
      router.replace("/selecionar-empresa");
    }
  }, [booting, isPublic, isEmpresaSelection, userInfo?.id, empresaLoading, empresaId, empresas.length, router]);

  // 4) Fecha menu ao clicar fora
  useEffect(() => {
    const handleClickOutside = (ev: MouseEvent) => {
      if (!navRef.current) return;
      if (navRef.current.contains(ev.target as Node)) return;
      setOpenMenu(null);
    };
    window.addEventListener("click", handleClickOutside);
    return () => window.removeEventListener("click", handleClickOutside);
  }, []);

  // 5) Carrega Role via RPC debug_me (nao depende de tenantId do provider)
  useEffect(() => {
    if (!userInfo?.id) {
      setUserRole(null);
      return;
    }

    let active = true;

    (async () => {
      try {
        const { data: u } = await supabase.auth.getUser();
        if (!u.user?.id) {
          if (active) setUserRole(null);
          return;
        }

        const dbg = await supabase.rpc("debug_me");
        if (dbg.error) {
          logError("Erro debug_me:", dbg.error);
          if (active) setUserRole(null);
          return;
        }

        const roles = (dbg.data as { roles?: string[] | null } | null)?.roles ?? [];
        if (active) setUserRole(roles.length ? roles.join(", ") : null);
      } catch (e) {
        logError("Erro ao carregar role:", e);
        if (active) setUserRole(null);
      }
    })();

    return () => {
      active = false;
    };
  }, [userInfo?.id, supabase]);

  useEffect(() => {
    if (!userInfo?.id) {
      setTenants([]);
      setTenantId(null);
      return;
    }

    let active = true;
    (async () => {
      try {
        const { data: ctx, error: ctxErr } = await supabase
          .from("user_tenant_context")
          .select("tenant_id")
          .maybeSingle();
        if (ctxErr) logError("Erro ao carregar tenant atual:", ctxErr);

        const { data: list, error: listErr } = await supabase
          .from("tenant_memberships")
          .select("tenant_id, tenants(name)")
          .eq("status", "active");
        if (listErr) {
          logError("Erro ao carregar empresas:", listErr);
          return;
        }

        if (!active) return;
        setTenants((list ?? []) as TenantOption[]);
        const ctxTenantId = (ctx as { tenant_id?: string | null } | null)?.tenant_id ?? null;
        setTenantId(ctxTenantId);
      } catch (e) {
        logError("Erro ao carregar empresas:", e);
      }
    })();

    return () => {
      active = false;
    };
  }, [userInfo?.id, supabase]);

  async function handleTenantChange(nextTenantId: string) {
    if (!nextTenantId || nextTenantId === tenantId || tenantBusy) return;
    setTenantBusy(true);
    try {
      const { error } = await supabase.rpc("set_current_tenant", {
        p_tenant_id: nextTenantId,
      });
      if (error) throw error;
      window.location.reload();
    } catch (e) {
      logError("Erro ao trocar empresa:", e);
      setTenantBusy(false);
    }
  }

  async function logout() {
    try {
      await supabase.auth.signOut();
    } catch (e) {
      logError("Erro ao sair", e);
    } finally {
      clearPermissionCache();
      clear();
      router.replace("/login");
      if (typeof window !== "undefined") window.location.href = "/login";
    }
  }

  const canAccessMov =
    has("movimentacoes.view") || has("fiscal.nf_entrada") || has("cadastros.fornecedores") || has("itens.create");
  const hasPermissionPrefix = (prefix: string) => permissions?.some((perm) => perm.startsWith(prefix)) ?? false;
  const canAccessEstoque = has("estoque.acessar") || hasPermissionPrefix("estoque.");
  const canAccessFinanceiro = has("financeiro.gerenciar") || hasPermissionPrefix("financeiro.");

  const toggleMenu = (key: "os" | "estoque" | "financeiro") =>
    setOpenMenu((prev) => (prev === key ? null : key));

  const openWithHover = (key: "os" | "estoque" | "financeiro") => {
    if (closeTimerRef.current) clearTimeout(closeTimerRef.current);
    setOpenMenu(key);
  };

  const scheduleClose = () => {
    if (closeTimerRef.current) clearTimeout(closeTimerRef.current);
    closeTimerRef.current = setTimeout(() => setOpenMenu(null), 150);
  };

  if (booting) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando...
      </div>
    );
  }

  if (isPublic) return <>{children}</>;

  if (!empresaLoading && userInfo?.id && empresas.length === 0) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        {empresaError ?? "Sem acesso a empresas. Fale com o admin."}
      </div>
    );
  }

  if (!empresaLoading && !empresaId && empresas.length > 1 && !isEmpresaSelection) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Redirecionando para selecao de empresa...
      </div>
    );
  }

  return (
    <div className="min-h-screen">
      {!hideHeader && (
        <header className="sticky top-0 z-50 border-b border-zinc-800 bg-zinc-950/80 backdrop-blur">
          <div
            className="mx-auto max-w-6xl px-4 py-3 flex items-center justify-between"
            ref={navRef}
          >
            <div className="flex items-center gap-4">
              <Link href="/" className="font-semibold tracking-tight text-zinc-100">
                Home
              </Link>

              <nav className="relative flex flex-wrap items-center gap-4 text-sm text-zinc-200">
                <div
                  className="relative"
                  onMouseEnter={() => openWithHover("os")}
                  onMouseLeave={scheduleClose}
                >
                  <button
                    type="button"
                    onClick={() => toggleMenu("os")}
                    className="px-3 py-1 rounded-md hover:bg-zinc-900 flex items-center gap-2"
                  >
                    OS <span className="text-[10px]">▼</span>
                  </button>

                  {openMenu === "os" && (
                    <div
                      className="absolute left-0 top-full mt-1 w-52 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                      onMouseEnter={() => openWithHover("os")}
                      onMouseLeave={scheduleClose}
                    >
                      <Link href="/os" className="block px-3 py-2 hover:bg-zinc-900">
                        OSs
                      </Link>
                      <Link href="/baixa_os" className="block px-3 py-2 hover:bg-zinc-900">
                        Baixa PC
                      </Link>
                      <Link href="/baixa_os_cel" className="block px-3 py-2 hover:bg-zinc-900">
                        Baixa Celular
                      </Link>
                      <Link href="/apontamentos" className="block px-3 py-2 hover:bg-zinc-900">
                        Apontamentos Horas
                      </Link>
                    </div>
                  )}
                </div>

                {canAccessEstoque && (
                  <div
                    className="relative"
                    onMouseEnter={() => openWithHover("estoque")}
                    onMouseLeave={scheduleClose}
                  >
                  <button
                    type="button"
                    onClick={() => toggleMenu("estoque")}
                    className="px-3 py-1 rounded-md hover:bg-zinc-900 flex items-center gap-2"
                  >
                    Estoque <span className="text-[10px]">▼</span>
                  </button>

                  {openMenu === "estoque" && (
                    <div
                      className="absolute left-0 top-full mt-1 w-52 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                      onMouseEnter={() => openWithHover("estoque")}
                      onMouseLeave={scheduleClose}
                    >
                      {(canAccessEstoque || has("estoque.view")) && (
                        <Link href="/estoque" className="block px-3 py-2 hover:bg-zinc-900">
                          Ajuste Estoque
                        </Link>
                      )}

                      {(canAccessEstoque || has("itens.view")) && (
                        <Link href="/itens" className="block px-3 py-2 hover:bg-zinc-900">
                          Cadastro
                        </Link>
                      )}

                      {(canAccessEstoque || has("fiscal.nf_entrada")) && (
                        <Link href="/estoque/importar" className="block px-3 py-2 hover:bg-zinc-900">
                          Importar XML
                        </Link>
                      )}

                      {(canAccessEstoque || canAccessMov) && (
                        <Link href="/mov" className="block px-3 py-2 hover:bg-zinc-900">
                          Movimentações
                        </Link>
                      )}
                    </div>
                  )}
                  </div>
                )}

                {canAccessFinanceiro && (
                  <div
                    className="relative"
                    onMouseEnter={() => openWithHover("financeiro")}
                    onMouseLeave={scheduleClose}
                  >
                    <button
                      type="button"
                      onClick={() => toggleMenu("financeiro")}
                      className="px-3 py-1 rounded-md hover:bg-zinc-900 flex items-center gap-2"
                    >
                      Financeiro <span className="text-[10px]">▼</span>
                    </button>

                    {openMenu === "financeiro" && (
                      <div
                        className="absolute left-0 top-full mt-1 w-56 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                        onMouseEnter={() => openWithHover("financeiro")}
                        onMouseLeave={scheduleClose}
                      >
                        <Link
                          href="/financeiro/contas_pagar_receber"
                          className="block px-3 py-2 hover:bg-zinc-900"
                        >
                          Contas a pagar/Receber
                        </Link>
                      </div>
                    )}
                  </div>
                )}

                {has("admin.users.manage") && (
                  <Link href="/usuarios" className="px-3 py-1 rounded-md hover:bg-zinc-900">
                    Usuarios
                  </Link>
                )}
              </nav>
            </div>

            <div className="flex items-center gap-3">
              {refreshing && (
                <div className="text-[11px] text-zinc-400 whitespace-nowrap">
                  Atualizando permissoes...
                </div>
              )}
              {tenants.length > 0 && (
                <div className="flex items-center gap-2">
                  <span className="text-xs text-zinc-400">Tenant</span>
                  <select
                    className="bg-zinc-900 border border-zinc-700 text-xs text-zinc-100 rounded px-2 py-1"
                    value={tenantId ?? ""}
                    onChange={(e) => handleTenantChange(e.target.value)}
                    disabled={tenantBusy}
                  >
                    <option value="" disabled>
                      Selecione
                    </option>
                    {tenants.map((t) => (
                      <option key={t.tenant_id} value={t.tenant_id}>
                        {t.tenants?.[0]?.name ?? t.tenant_id}
                      </option>
                    ))}
                  </select>
                </div>
              )}
              {empresaError && (
                <div className="text-xs text-red-400 max-w-[240px]">{empresaError}</div>
              )}
              {empresas.length > 1 && (
                <div className="flex items-center gap-2">
                  <span className="text-xs text-zinc-400">Empresa</span>
                  <select
                    className="bg-zinc-900 border border-zinc-700 text-xs text-zinc-100 rounded px-2 py-1"
                    value={empresaId ?? ""}
                    onChange={(e) => setEmpresaId(e.target.value)}
                    disabled={empresaLoading}
                  >
                    <option value="" disabled>
                      Selecione
                    </option>
                    {empresas.map((empresa) => (
                      <option key={empresa.id} value={empresa.id}>
                        {empresa.nome ?? empresa.id}
                      </option>
                    ))}
                  </select>
                </div>
              )}
              {userInfo && (
                <div className="text-xs text-zinc-300 select-none whitespace-nowrap">
                  <div>{userInfo.email}</div>
                  <div className="text-[11px] text-zinc-400">{userRole ?? "-"}</div>
                </div>
              )}
              <button
                type="button"
                onClick={logout}
                className="px-3 py-1.5 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
              >
                Sair
              </button>
            </div>
          </div>
        </header>
      )}

      <main
        className={
          hideHeader
            ? "w-full px-6 py-6"
            : isFullWidth
              ? "w-full px-4 md:px-6 py-6"
              : "mx-auto max-w-6xl px-4 py-6"
        }
      >
        {children}
      </main>
    </div>
  );
}






