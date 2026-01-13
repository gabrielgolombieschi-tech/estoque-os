"use client";

import Link from "next/link";
import { useContext, useEffect, useMemo, useRef, useState, type ChangeEvent } from "react";
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
  if (isDev) console.warn(...args);
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

  /**
   * ✅ Robustez: não assume que o provider expõe reload/ready/loadingInitial/etc.
   * Assim não quebra o header/menu em runtime.
   */
  const perms = usePermissions();

  const clear: () => void = perms?.clear ?? (() => {});
  const _rawHas = perms?.has ?? (() => false);
  const has: (k: string) => boolean | undefined = (_rawHas as unknown) as (k: string) => boolean | undefined;
  const reload: () => Promise<void> = perms?.reload ?? (async () => {});
  const refreshing: boolean = perms?.refreshing ?? false;
  const loadingInitial: boolean = perms?.loadingInitial ?? false;
  const permsCapabilities = (perms as unknown as { capabilities?: unknown } | null)?.capabilities;
  const permissionsFailed: boolean = !loadingInitial && permsCapabilities === null;

  // ready pode não existir; se não existir, consideramos "ready" quando não está no loadingInitial
  const permissionsReady: boolean = perms?.ready ?? !loadingInitial;

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

  // Helper único para checar capability (nunca use has() direto no JSX)
  const can = (k: string) => Boolean(has(k));

  const canAccessOs = can("os.read");
  const canExecuteOs = can("os_rpcs.execute");
  const canAccessApontamentos = can("apontamentos.read");
  const canAccessClientes = can("os.read") || can("cad_clientes.write");
  const canAccessEstoque = can("estoque.read") || can("estoque.write");
  const canAccessCadastroItens = can("cad_itens.write") || can("estoque.read") || can("os.read");
  const canImportXml = can("xml_import.execute");
  const canAccessFornecedores = can("estoque.read") || can("estoque.write") || can("cad_fornecedores.write");
  const canAccessFinanceiro = can("financeiro.read");
  const canAccessAdmin = can("admin.manage_users");

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

  // 3) Guard de rota (login)
  useEffect(() => {
    if (booting) return;

    const isAuthed = !!userInfo?.id;
    if (!isAuthed && !isPublic) router.replace("/login");
    if (isAuthed && isPublic) router.replace("/");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [booting, userInfo?.id, pathname]);

  // 3.5) Guard de empresa (se tiver mais de 1)
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

  // 6) Carrega tenants (para selector)
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
          logError("Erro ao carregar tenants:", listErr);
          return;
        }

        if (!active) return;
        setTenants((list ?? []) as TenantOption[]);
        const ctxTenantId = (ctx as { tenant_id?: string | null } | null)?.tenant_id ?? null;
        setTenantId(ctxTenantId);
      } catch (e) {
        logError("Erro ao carregar tenants:", e);
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
      logError("Erro ao trocar tenant:", e);
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
          <div className="mx-auto max-w-6xl px-4 py-3 flex items-center justify-between" ref={navRef}>
            <div className="flex items-center gap-4">
              <Link href="/" className="font-semibold tracking-tight text-zinc-100">
                Home
              </Link>

              <nav className="relative flex flex-wrap items-center gap-4 text-sm text-zinc-200">
                {loadingInitial && (
                  <div className="text-xs text-zinc-500">Carregando menus...</div>
                )}

                {permissionsFailed && (
                  <div className="text-xs text-amber-400">
                    Permissões não carregaram. Se este banco é novo, aplique migrations (inclui
                    <span className="font-mono"> 20260206_can_many.sql</span>) e clique em{" "}
                    <button type="button" className="underline" onClick={() => reload()}>
                      recarregar
                    </button>
                    .
                  </div>
                )}

                {permissionsReady && canAccessOs && (
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
                      OS
                    </button>

                    {openMenu === "os" && (
                      <div
                        className="absolute left-0 top-full mt-1 w-56 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                        onMouseEnter={() => openWithHover("os")}
                        onMouseLeave={scheduleClose}
                      >
                        {can("os.read") && (
                          <Link href="/os" className="block px-3 py-2 hover:bg-zinc-900">
                            OSs
                          </Link>
                        )}
                        {can("os.read") && (
                          <Link href="/projetos" className="block px-3 py-2 hover:bg-zinc-900">
                            Projetos
                          </Link>
                        )}
                        {canExecuteOs && (
                          <Link href="/execucao" className="block px-3 py-2 hover:bg-zinc-900">
                            Execucao
                          </Link>
                        )}
                        {canExecuteOs && (
                          <Link href="/baixa_os" className="block px-3 py-2 hover:bg-zinc-900">
                            Baixa PC
                          </Link>
                        )}
                        {canExecuteOs && (
                          <Link href="/baixa_os_cel" className="block px-3 py-2 hover:bg-zinc-900">
                            Baixa Celular
                          </Link>
                        )}
                        {canAccessApontamentos && (
                          <Link href="/apontamentos" className="block px-3 py-2 hover:bg-zinc-900">
                            Apontamentos Horas
                          </Link>
                        )}
                        {canAccessClientes && (
                          <Link href="/os/clientes" className="block px-3 py-2 hover:bg-zinc-900">
                            Clientes
                          </Link>
                        )}
                      </div>
                    )}
                  </div>
                )}

                {permissionsReady && canAccessEstoque && (
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
                      Estoque
                    </button>

                    {openMenu === "estoque" && (
                      <div
                        className="absolute left-0 top-full mt-1 w-52 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                        onMouseEnter={() => openWithHover("estoque")}
                        onMouseLeave={scheduleClose}
                      >
                        {can("estoque.read") && (
                          <Link href="/estoque" className="block px-3 py-2 hover:bg-zinc-900">
                            Ajuste Estoque
                          </Link>
                        )}
                        {canAccessCadastroItens && (
                          <Link href="/itens" className="block px-3 py-2 hover:bg-zinc-900">
                            Cadastro
                          </Link>
                        )}
                        {canImportXml && (
                          <Link href="/estoque/importar" className="block px-3 py-2 hover:bg-zinc-900">
                            Importar XML
                          </Link>
                        )}
                        {can("estoque.read") && (
                          <Link href="/mov" className="block px-3 py-2 hover:bg-zinc-900">
                            Movimentacoes
                          </Link>
                        )}
                        {canAccessFornecedores && (
                          <Link
                            href="/estoque/fornecedores"
                            className="block px-3 py-2 hover:bg-zinc-900"
                          >
                            Fornecedores
                          </Link>
                        )}
                      </div>
                    )}
                  </div>
                )}

                {permissionsReady && canAccessFinanceiro && (
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
                      Financeiro
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

                {permissionsReady && canAccessAdmin && (
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
                    aria-label="Selecionar tenant"
                    className="bg-zinc-900 border border-zinc-700 text-xs text-zinc-100 rounded px-2 py-1"
                    value={tenantId ?? ""}
                    onChange={(e: ChangeEvent<HTMLSelectElement>) => handleTenantChange(e.currentTarget.value)}
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
                    aria-label="Selecionar empresa"
                    className="bg-zinc-900 border border-zinc-700 text-xs text-zinc-100 rounded px-2 py-1"
                    value={empresaId ?? ""}
                    onChange={(e: ChangeEvent<HTMLSelectElement>) => setEmpresaId(e.currentTarget.value)}
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
