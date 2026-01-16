"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState, type ChangeEvent } from "react";
import { usePathname, useRouter } from "next/navigation";
import { supabaseBrowser } from "../../lib/supabase/client";
import { useTenantEmpresaContext } from "@/lib/auth/TenantEmpresaProvider";

type UserInfo = { id: string; email: string };
type TenantOption = {
  tenant_id: string;
  tenants?: { nome: string | null }[] | null;
};


const isDev = process.env.NODE_ENV !== "production";
const logError = (...args: unknown[]) => {
  if (isDev) console.warn(...args);
};

// Debounce para evitar múltiplos logouts rápidos
let authChangeDebounceRef: ReturnType<typeof setTimeout> | null = null;
let lastAuthChangeTime = 0;

export default function AppShell({ children }: { children: React.ReactNode }) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const te = useTenantEmpresaContext();

  const router = useRouter();
  const pathname = usePathname();

  const currentTenantId = te.tenantId;
  const empresaId = te.empresaId;
  const empresas = te.empresas;

  // IMPORTANT: Never treat undefined permissions as false (prevents flicker).
  const has = te.has as unknown as (k: string) => boolean | undefined;
  const clear = te.clear;
  const reload = te.reload;
  const refreshing = te.refreshing;

  const bootingTenantEmpresa = te.loading || !currentTenantId || !empresaId;
  const loadingInitial = bootingTenantEmpresa && te.capabilities === null;
  const permissionsFailed = !loadingInitial && te.capabilities === null;
  const permissionsReady = te.capabilities !== null;

  const [booting, setBooting] = useState(true);
  const [userInfo, setUserInfo] = useState<UserInfo | null>(null);
  const [tenants, setTenants] = useState<TenantOption[]>([]);
  const [tenantId, setTenantId] = useState<string | null>(null);
  const [tenantBusy, setTenantBusy] = useState(false);

  const isPublic = pathname === "/login";
  const isFullWidth = pathname === "/itens";
  const hideHeader = pathname?.startsWith("/projetos") || pathname?.startsWith("/execucao");

  const [openMenu, setOpenMenu] = useState<"os" | "estoque" | "financeiro" | "cadastro" | null>(null);
  const navRef = useRef<HTMLDivElement | null>(null);
  const closeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Helper único para checar capability (nunca use has() direto no JSX)
  // Se capabilities ainda não carregaram, libera menu para evitar header vazio
  const can = (k: string) => has(k) ?? true;

  const canAccessOs = can("os.read");
  const canExecuteOs = can("os_rpcs.execute");
  const canAccessApontamentos = can("apontamentos.read");
  const canAccessEstoque = can("estoque.read") || can("estoque.write");
  const canAccessCadastroItens = can("cad_itens.write") || can("estoque.read") || can("os.read");
  const canImportXml = can("xml_import.execute");
  const canAccessFinanceiro = can("financeiro.read");
  const canAccessAdmin = can("admin.manage_users");
  const canAccessCadastros = can("admin.manage_users") || can("financeiro.read");
  const canAccessContratos = can("admin.manage_users") || can("financeiro.read") || can("apontamentos.read"); // Contratos HH - Admin, Financeiro ou Apontador
  const canAccessColaboradores = can("admin.manage_users") || can("financeiro.read"); // Colaboradores - Admin ou Financeiro
  const canAccessClientesCad = can("admin.manage_users") || can("financeiro.read") || can("cad_clientes.write"); // Clientes - Admin, Financeiro, Coordenação
  const canAccessFornecedoresCad = can("admin.manage_users") || can("financeiro.read") || can("cad_fornecedores.write") || can("estoque.read") || can("estoque.write"); // Fornecedores - Admin, Financeiro, Coordenação, Estoque

  const toggleMenu = (key: "os" | "estoque" | "financeiro" | "cadastro" | null) =>
    setOpenMenu((prev) => (prev === key ? null : key));

  const openWithHover = (key: "os" | "estoque" | "financeiro" | "cadastro") => {
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

        // PermissionsProvider já carrega permissões automaticamente ao iniciar
        // Não chamamos reload() aqui para evitar reavaliações desnecessárias
      } finally {
        if (active) setBooting(false);
      }
    })();

    return () => {
      active = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 2) Listener de auth 1x (login/logout/troca sessão) com debounce
  useEffect(() => {
    const { data: sub } = supabase.auth.onAuthStateChange((_evt, session) => {
      // Debounce: evita múltiplos dispatchs em <1s
      const now = Date.now();
      if (now - lastAuthChangeTime < 1000) {
        if (authChangeDebounceRef) clearTimeout(authChangeDebounceRef);
        authChangeDebounceRef = setTimeout(() => {
          lastAuthChangeTime = now;
          clear();

          const user = session?.user;
          setUserInfo(user ? { id: user.id, email: user.email ?? "" } : null);

          // PermissionsProvider já recarrega permissões ao detectar mudança de sessão
        }, 500);
        return;
      }

      lastAuthChangeTime = now;
      clear();

      const user = session?.user;
      setUserInfo(user ? { id: user.id, email: user.email ?? "" } : null);

      // PermissionsProvider já recarrega permissões ao detectar mudança de sessão
    });

    return () => {
      if (authChangeDebounceRef) clearTimeout(authChangeDebounceRef);
      sub.subscription.unsubscribe();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 2.5) Refresh periódico de sessão (a cada 15 min)
  useEffect(() => {
    if (booting) return;

    let sessionRefreshInterval: ReturnType<typeof setInterval> | null = null;

    const refreshSession = async () => {
      try {
        const { data: sessionData } = await supabase.auth.getSession();
        if (!sessionData.session) return; // Sem sessão, não precisa renovar

        // Tentar renovar sessão (idempotente, não causa logout se falhar)
        const { error } = await supabase.auth.refreshSession();
        if (error && error.message?.toLowerCase().includes("invalid_grant")) {
          // Sessão expirada e não pode renovar: deixa fazer logout natural
          logError("Sessão expirada e não pôde renovar. Logout na próxima ação.");
        }
      } catch (e) {
        logError("Erro ao renovar sessão periodicamente:", e);
      }
    };

    // Refresh a cada 15 minutos (900s)
    sessionRefreshInterval = setInterval(refreshSession, 15 * 60 * 1000);

    return () => {
      if (sessionRefreshInterval) clearInterval(sessionRefreshInterval);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [booting]);

  // 3) Guard de rota (login)
  useEffect(() => {
    if (booting) return;

    const isAuthed = !!userInfo?.id;
    if (!isAuthed && !isPublic) router.replace("/login");
    if (isAuthed && isPublic) router.replace("/");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [booting, userInfo?.id, pathname]);

  // 3.5) Guard de empresa - REMOVIDO: sempre usa Elétrica Segau automaticamente
  // Não há mais necessidade de redirecionar para /selecionar-empresa

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

  // 6) Carrega tenants - SIMPLIFICADO: sempre usa tenant fixo
  useEffect(() => {
    if (!userInfo?.id || !currentTenantId) {
      setTenants([]);
      setTenantId(null);
      return;
    }

    // Usar tenant do contexto TenantEmpresaProvider
    setTenantId(currentTenantId);
    setTenants([
      {
        tenant_id: currentTenantId,
        tenants: [{ nome: "Elétrica Segau" }],
      },
    ]);
  }, [userInfo?.id, currentTenantId]);

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

  // REMOVIDO: Verificação de empresas.length === 0
  // Como tudo está hardcoded para Elétrica Segau, não precisamos dessa verificação
  // que estava bloqueando o acesso

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

                {canAccessOs && (
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

                      </div>
                    )}
                  </div>
                )}

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

                {canAccessCadastros && (
                  <div
                    className="relative"
                    onMouseEnter={() => openWithHover("cadastro")}
                    onMouseLeave={scheduleClose}
                  >
                    <button
                      type="button"
                      onClick={() => toggleMenu("cadastro")}
                      className="px-3 py-1 rounded-md hover:bg-zinc-900 flex items-center gap-2"
                    >
                      Cadastros
                    </button>

                    {openMenu === "cadastro" && (
                      <div
                        className="absolute left-0 top-full mt-1 w-56 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                        onMouseEnter={() => openWithHover("cadastro")}
                        onMouseLeave={scheduleClose}
                      >
                        {canAccessContratos && (
                          <>
                            <div className="px-3 py-2 text-xs font-semibold text-zinc-400">Contratos HH</div>
                            <Link
                              href="/cadastros/hh/tabelas"
                              className="block px-5 py-2 hover:bg-zinc-900 text-sm"
                            >
                              Tabelas
                            </Link>
                            <Link
                              href="/cadastros/hh/servicos-cliente"
                              className="block px-5 py-2 hover:bg-zinc-900 text-sm"
                            >
                              Especialidades
                            </Link>
                            <Link
                              href="/cadastros/hh/colaboradores-cliente"
                              className="block px-5 py-2 hover:bg-zinc-900 text-sm"
                            >
                              Colaboradores × Cliente
                            </Link>
                            <div className="border-t border-zinc-800 my-2"></div>
                          </>
                        )}
                        {canAccessColaboradores && (
                          <>
                            <Link
                              href="/colaboradores"
                              className="block px-3 py-2 hover:bg-zinc-900"
                            >
                              Colaboradores
                            </Link>
                            <div className="border-t border-zinc-800 my-2"></div>
                          </>
                        )}
                        {canAccessClientesCad && (
                          <>
                            <Link
                              href="/clientes"
                              className="block px-3 py-2 hover:bg-zinc-900"
                            >
                              Clientes
                            </Link>
                            <div className="border-t border-zinc-800 my-2"></div>
                          </>
                        )}
                        {canAccessFornecedoresCad && (
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

                {canAccessAdmin && (
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
                        {t.tenants?.[0]?.nome ?? t.tenant_id}
                      </option>
                    ))}
                  </select>
                </div>
              )}

              {te.error && (
                <div className="text-xs text-red-400 max-w-[240px]">{te.error}</div>
              )}

              {/* Seletor de empresa REMOVIDO - sempre usa Elétrica Segau */}
              {empresaId && (
                <div className="flex items-center gap-2">
                  <span className="text-xs text-zinc-400">Empresa:</span>
                  <span className="text-xs text-zinc-100 font-medium">
                    {empresas.find((e) => e.id === empresaId)?.nome_fantasia ?? "Elétrica Segau"}
                  </span>
                </div>
              )}

              {userInfo && (
                <div className="text-xs text-zinc-300 select-none whitespace-nowrap">
                  <div>{userInfo.email}</div>
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
