
"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa, useIsAdminTenant } from "@/lib/auth/hooks";
import type { Capabilities, CapabilityKey } from "@/lib/auth/capabilities";
import AdminDebugPanel from "./AdminDebugPanel";
import SessionKeepAlive from "@/components/auth/SessionKeepAlive";

const isDev = process.env.NODE_ENV !== "production";
const logError = (...args: unknown[]) => {
  if (isDev) console.warn(...args);
};

export default function AppShellClient({ children }: { children: React.ReactNode }) {
  const te = useTenantEmpresa();

  const router = useRouter();
  const pathname = usePathname();

  const isLoginPage = pathname === "/login";
  const isResetPasswordPage =
    pathname === "/reset-password" ||
    pathname === "/auth/reset-password" ||
    pathname === "/reset-password/" ||
    pathname === "/auth/reset-password/";
  const isPublic = isLoginPage || isResetPasswordPage;
  const isFullWidth = pathname === "/itens" || pathname === "/itens/imprimir";

  const { isAdmin: isAdminTenant, loading: adminLoading } = useIsAdminTenant();
  const lastKnownCapsRef = useRef<Capabilities | null>(null);
  const didAutoSelectEmpresaRef = useRef(false);
  const lastUserIdRef = useRef<string | null>(null);

  const empresaId = te.empresaId;
  const empresas = te.empresas;

  const effectiveEmpresa = useMemo(() => {
    if (empresaId) return empresas.find((e) => e.id === empresaId) ?? null;
    if (empresas.length === 1) return empresas[0];
    return null;
  }, [empresaId, empresas]);

  const empresaRole = useMemo(() => {
    const role = effectiveEmpresa?.papel;
    return typeof role === "string" ? role.trim().toUpperCase() : "";
  }, [effectiveEmpresa?.papel]);
  const isPainelTv = empresaRole === "PAINEL_TV";

  const hideHeader =
    isPainelTv ||
    pathname === "/itens/imprimir" ||
    pathname === "/painel-tv" ||
    pathname?.startsWith("/projetos") ||
    pathname?.startsWith("/execucao");

  useEffect(() => {
    if (te.capabilities) lastKnownCapsRef.current = te.capabilities;
  }, [te.capabilities]);

  useEffect(() => {
    const userId = te.sessionUserId;
    if (userId === undefined) return;

    if (userId === null) {
      lastUserIdRef.current = null;
      lastKnownCapsRef.current = null;
      didAutoSelectEmpresaRef.current = false;
      return;
    }

    if (userId !== lastUserIdRef.current) {
      lastUserIdRef.current = userId;
      lastKnownCapsRef.current = null;
      didAutoSelectEmpresaRef.current = false;
    }
  }, [te.sessionUserId]);

  useEffect(() => {
    if (didAutoSelectEmpresaRef.current) return;
    if (!te.sessionUserId) return;
    if (!empresaId && empresas.length === 1) {
      didAutoSelectEmpresaRef.current = true;
      void te.setEmpresaId(empresas[0].id);
    }
  }, [empresaId, empresas, te.sessionUserId, te.setEmpresaId]);

  useEffect(() => {
    const sessionUserId = te.sessionUserId;
    if (sessionUserId === undefined) return;
    const isAuthed = Boolean(sessionUserId);
    if (!isAuthed && !isPublic) router.replace("/login");
    // Only redirect authed users away from the login page.
    // Password reset links often establish a session; keep user on reset screen.
    if (isAuthed && isLoginPage) router.replace("/");
  }, [isLoginPage, isPublic, router, te.sessionUserId]);

  useEffect(() => {
    if (te.sessionUserId === undefined) return;
    if (!te.sessionUserId) return;
    if (!isPainelTv) return;
    if (!effectiveEmpresa) return;

    const allowed =
      pathname === "/painel" ||
      pathname === "/painel-tv" ||
      pathname.startsWith("/painel-tv/") ||
      pathname === "/projetos" ||
      pathname.startsWith("/projetos/") ||
      pathname === "/execucao" ||
      pathname.startsWith("/execucao/");

    if (!allowed) router.replace("/painel-tv");
  }, [effectiveEmpresa, isPainelTv, pathname, router, te.sessionUserId]);

  const [openMenu, setOpenMenu] = useState<"os" | "estoque" | "financeiro" | "cadastro" | "admin" | null>(null);
  const navRef = useRef<HTMLDivElement | null>(null);
  const closeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const toggleMenu = (key: "os" | "estoque" | "financeiro" | "cadastro" | "admin" | null) =>
    setOpenMenu((prev) => (prev === key ? null : key));

  const openWithHover = (key: "os" | "estoque" | "financeiro" | "cadastro" | "admin") => {
    if (closeTimerRef.current) clearTimeout(closeTimerRef.current);
    setOpenMenu(key);
  };

  const scheduleClose = () => {
    if (closeTimerRef.current) clearTimeout(closeTimerRef.current);
    closeTimerRef.current = setTimeout(() => setOpenMenu(null), 150);
  };

  const has = te.has;
  const can = (k: CapabilityKey) => {
    const v = has(k);
    if (v !== undefined) return v;
    if (lastKnownCapsRef.current) return lastKnownCapsRef.current[k] ?? false;
    // Capabilities still unknown (boot): keep header stable, but never show Admin optimistically.
    if (k === "admin.manage_users") return false;
    return true;
  };

  const canStrict = (k: CapabilityKey) => {
    const v = has(k);
    if (v !== undefined) return v;
    if (lastKnownCapsRef.current) return lastKnownCapsRef.current[k] ?? false;
    return false;
  };

  const sessionUserId = te ? te.sessionUserId : undefined;
  const tenantIdVal = te ? te.tenantId : undefined;

  const canAccessOs = can("os.read") || can("os.write");
  const canExecuteOs = can("os_rpcs.execute");
  const canAccessEstoque = can("estoque.read") || can("estoque.write");
  const canAccessCadastroItens = can("cad_itens.write");

  const canAccessCadastrosByEmpresaPapel = Boolean(
    empresaRole && ["ADMIN", "FINANCEIRO", "COORDENACAO", "COMPRAS"].includes(empresaRole)
  );

  const canAccessCadastros =
    can("admin.manage_users") ||
    can("financeiro.read") ||
    can("cad_clientes.write") ||
    can("cad_fornecedores.write") ||
    canAccessCadastrosByEmpresaPapel;
  const canAccessContratos = can("admin.manage_users") || can("financeiro.read") || can("apontamentos.read");
  const canAccessColaboradores = can("admin.manage_users") || can("financeiro.read");
  const canAccessApontamentos = can("apontamentos.read") || can("apontamentos.write");
  const canAccessClientesCad =
    can("admin.manage_users") || can("financeiro.read") || can("cad_clientes.write") || canAccessCadastrosByEmpresaPapel;
  const canAccessFinanceiro = can("financeiro.read") || can("financeiro.write");
  const canImportXml = can("xml_import.execute");
  const canAdminManageUsers = can("admin.manage_users");
  const shouldShowAdmin = canAdminManageUsers || isAdminTenant;
  const adminReason = "";
  const canAccessFornecedoresCad =
    can("admin.manage_users") ||
    can("financeiro.read") ||
    can("cad_fornecedores.write") ||
    can("estoque.read") ||
    can("estoque.write") ||
    canAccessCadastrosByEmpresaPapel;

  const empresaPapel = String(effectiveEmpresa?.papel ?? "")
    .trim()
    .toUpperCase();
  const canSeeEstoqueMenuByEmpresaPapel = Boolean(
    empresaPapel && ["ADMIN", "COORDENACAO", "ALMOXARIFADO", "FINANCEIRO", "COMPRAS"].includes(empresaPapel)
  );
  const canSeeEstoqueMenu = canAccessEstoque || canSeeEstoqueMenuByEmpresaPapel;
  const canSeeCadastroItensMenu = canAccessCadastroItens || canSeeEstoqueMenuByEmpresaPapel;
  const canSeeAjusteEstoqueMenu = can("estoque.read") || can("estoque.write") || canSeeEstoqueMenuByEmpresaPapel;

  useEffect(() => {
    if (!isDev) return;
    console.log("[AppShell] admin", {
      isAdminTenant,
      adminLoading,
      teLoading: te.loading,
      teRefreshing: te.refreshing,
      canAdmin: can("admin.manage_users"),
      userId: te.sessionUserId ?? null,
    });
  }, [adminLoading, isAdminTenant, te.loading, te.refreshing, te.sessionUserId]);

  async function logout() {
    try {
      const supabase = getSupabaseBrowser();
      await supabase.auth.signOut();
    } catch (e) {
      logError("Erro ao sair", e);
    } finally {
      router.replace("/login");
    }
  }

  if (isPublic) return <>{children}</>;

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
                  <div className="relative" onMouseEnter={() => openWithHover("os")} onMouseLeave={scheduleClose}>
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

                {canSeeEstoqueMenu && (
                  <div className="relative" onMouseEnter={() => openWithHover("estoque")} onMouseLeave={scheduleClose}>
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
                        {canSeeAjusteEstoqueMenu && (
                          <Link href="/estoque" className="block px-3 py-2 hover:bg-zinc-900">
                            Ajuste Estoque
                          </Link>
                        )}
                        {canSeeCadastroItensMenu && (
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
                            <Link href="/cadastros/hh/tabelas" className="block px-5 py-2 hover:bg-zinc-900 text-sm">
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
                              Colaboradores - Cliente
                            </Link>
                            <div className="border-t border-zinc-800 my-2"></div>
                          </>
                        )}
                        {canAccessColaboradores && (
                          <>
                            <Link href="/colaboradores" className="block px-3 py-2 hover:bg-zinc-900">
                              Colaboradores
                            </Link>
                            <div className="border-t border-zinc-800 my-2"></div>
                          </>
                        )}
                        {canAccessClientesCad && (
                          <>
                            <Link href="/clientes" className="block px-3 py-2 hover:bg-zinc-900">
                              Clientes
                            </Link>
                            <div className="border-t border-zinc-800 my-2"></div>
                          </>
                        )}
                        {canAccessFornecedoresCad && (
                          <Link href="/estoque/fornecedores" className="block px-3 py-2 hover:bg-zinc-900">
                            Fornecedores
                          </Link>
                        )}
                      </div>
                    )}
                  </div>
                )}

                {shouldShowAdmin && (
                  <div className="relative" onMouseEnter={() => openWithHover("admin")} onMouseLeave={scheduleClose}>
                    <button
                      type="button"
                      onClick={() => toggleMenu("admin")}
                      className="px-3 py-1 rounded-md hover:bg-zinc-900 flex items-center gap-2"
                    >
                      Admin
                    </button>

                    {openMenu === "admin" && (
                      <div
                        className="absolute left-0 top-full mt-1 w-52 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                        onMouseEnter={() => openWithHover("admin")}
                        onMouseLeave={scheduleClose}
                      >
                        <Link href="/admin/usuarios" className="block px-3 py-2 hover:bg-zinc-900">
                          Usuarios
                        </Link>
                        <Link href="/admin/empresas" className="block px-3 py-2 hover:bg-zinc-900">
                          Empresas
                        </Link>
                      </div>
                    )}
                  </div>
                )}
              </nav>
            </div>

            <div className="flex items-center gap-3">
              {te.refreshing && (
                <div className="text-[11px] text-zinc-400 whitespace-nowrap">Atualizando permissões...</div>
              )}

              {te.error && <div className="text-xs text-red-400 max-w-[240px]">{te.error}</div>}

              {effectiveEmpresa && (
                <div className="flex items-center gap-2">
                  <span className="text-xs text-zinc-400">Empresa:</span>
                  <span className="text-xs text-zinc-100 font-medium">
                    {effectiveEmpresa.nome_fantasia ?? effectiveEmpresa.razao_social ?? "Empresa"}
                  </span>
                </div>
              )}
              {!effectiveEmpresa && te.sessionUserId && (
                <div className="flex items-center gap-2">
                  <span className="text-xs text-zinc-400">Empresa:</span>
                  <span className="text-xs text-zinc-100 font-medium opacity-70">Carregando...</span>
                </div>
              )}

              <div className="flex flex-col items-end gap-1">
                {te.email && (
                  <div className="text-xs text-zinc-300 select-none whitespace-nowrap">
                    <div>{te.email}</div>
                  </div>
                )}
                <AdminDebugPanel
                  providerBuildId={te.providerBuildId}
                  sessionUserId={te.sessionUserId}
                  email={te.email}
                  tenantId={te.tenantId}
                  empresaId={te.empresaId}
                  empresas={te.empresas}
                  isAdminTenant={isAdminTenant}
                  adminLoading={adminLoading}
                  capabilities={te.capabilities}
                  lastLoadPermissions={te.lastLoadPermissions}
                  lastLoadPermissionsRaw={te.lastLoadPermissionsRaw}
                  lastLoadSource={te.lastLoadSource}
                  lastLoadCount={te.lastLoadCount}
                  lastLoadError={te.lastLoadError}
                  can={can}
                  canAdminManageUsers={canAdminManageUsers}
                  shouldShowAdmin={shouldShowAdmin}
                  reason={adminReason}
                  onRefreshCapabilities={te.refreshCapabilities}
                />
              </div>

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
          hideHeader ? "w-full px-6 py-6" : isFullWidth ? "w-full px-4 md:px-6 py-6" : "mx-auto max-w-6xl px-4 py-6"
        }
      >
        {children}
      </main>
    </div>
  );
}
