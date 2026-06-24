
"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa, useIsAdminTenant } from "@/lib/auth/hooks";
import type { Capabilities, CapabilityKey } from "@/lib/auth/capabilities";
import AdminDebugPanel from "./AdminDebugPanel";
import SessionKeepAlive from "@/components/auth/SessionKeepAlive";
import { useTheme } from "@/components/ThemeProvider";

const isDev = process.env.NODE_ENV !== "production";
const logError = (...args: unknown[]) => {
  if (isDev) console.warn(...args);
};

export default function AppShellClient({ children }: { children: React.ReactNode }) {
  const te = useTenantEmpresa();
  const { theme, toggle: toggleTheme } = useTheme();

  const router = useRouter();
  const pathname = usePathname();

  const isLoginPage = pathname === "/login";
  const isResetPasswordPage =
    pathname === "/reset-password" ||
    pathname === "/auth/reset-password" ||
    pathname === "/reset-password/" ||
    pathname === "/auth/reset-password/";
  const isPublic = isLoginPage || isResetPasswordPage;
  const isFullWidth =
    pathname === "/itens" ||
    pathname === "/itens/imprimir" ||
    pathname === "/faturamento/nfe" ||
    pathname === "/faturamento/nfse" ||
    pathname === "/os/analitico" ||
    pathname === "/compras/pedidos" ||
    pathname === "/estoque/pedidos" ||
    pathname?.startsWith("/compras/pedidos/") && pathname?.endsWith("/imprimir") ||
    pathname === "/estoque/relatorios" ||
    pathname === "/comercial/analitico" ||
    pathname === "/comercial/orcamentos" ||
    pathname?.startsWith("/comercial/orcamentos/") && pathname?.endsWith("/imprimir") ||
    pathname === "/financeiro/contas-pagar/aprovacoes" ||
    pathname === "/financeiro/impostos" ||
    pathname === "/financeiro/contas_pagar_receber" ||
    pathname === "/financeiro/gestao-cobranca" ||
    pathname?.startsWith("/financeiro/contas_pagar_receber/");
  const isOsDetailPage = /^\/os\/\d+\/?$/.test(pathname ?? "");

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
    pathname === "/estoque/importar/imprimir" ||
    pathname?.startsWith("/compras/pedidos/") && pathname?.endsWith("/imprimir") ||
    pathname?.startsWith("/comercial/orcamentos/") && pathname?.endsWith("/imprimir") ||
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

  const [openMenu, setOpenMenu] = useState<
    "os" | "estoque" | "imobilizado" | "financeiro" | "compras" | "comercial" | "faturamento" | "cadastro" | "admin" | null
  >(null);
  const navRef = useRef<HTMLDivElement | null>(null);
  const closeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const toggleMenu = (
    key: "os" | "estoque" | "imobilizado" | "financeiro" | "compras" | "comercial" | "faturamento" | "cadastro" | "admin" | null
  ) =>
    setOpenMenu((prev) => (prev === key ? null : key));

  const openWithHover = (
    key: "os" | "estoque" | "imobilizado" | "financeiro" | "compras" | "comercial" | "faturamento" | "cadastro" | "admin"
  ) => {
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
    return false;
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
    empresaRole && ["ADMIN", "FINANCEIRO", "COORDENACAO", "COMPRAS", "FATURAMENTO"].includes(empresaRole)
  );
  const canAccessCadastrosFullByEmpresaPapel = Boolean(
    empresaRole && ["ADMIN", "FINANCEIRO", "COORDENACAO", "FATURAMENTO"].includes(empresaRole)
  );

  const canAccessCadastros =
    can("admin.manage_users") ||
    can("financeiro.read") ||
    can("cad_clientes.write") ||
    can("cad_fornecedores.write") ||
    canAccessCadastrosByEmpresaPapel;
  const canAccessContratos =
    can("admin.manage_users") ||
    can("financeiro.read") ||
    can("apontamentos.read") ||
    canAccessCadastrosFullByEmpresaPapel;
  const canAccessColaboradores =
    can("admin.manage_users") || can("financeiro.read") || canAccessCadastrosFullByEmpresaPapel;
  const canAccessApontamentos = can("apontamentos.read") || can("apontamentos.write");
  const canAccessClientesCad =
    can("admin.manage_users") || can("financeiro.read") || can("cad_clientes.write") || canAccessCadastrosByEmpresaPapel;
  const isFinanceiroEmpresaRole = empresaRole === "FINANCEIRO";
  const isFaturamentoEmpresaRole = empresaRole === "FATURAMENTO";

  const canAccessFinanceiro = can("financeiro.read") || can("financeiro.write") || isFinanceiroEmpresaRole;
  const canAccessFinanceiroMenu = canAccessFinanceiro && !isFaturamentoEmpresaRole;
  const canAccessCompras =
    can("compras.read") ||
    can("compras.write") ||
    can("compras.approve") ||
    can("compras.receive") ||
    Boolean(empresaRole && ["ADMIN", "FINANCEIRO", "COORDENACAO", "COMPRAS", "FATURAMENTO"].includes(empresaRole));
  const canAccessComercial = canAccessFinanceiro || canAccessOs;
  const canImportXml = can("xml_import.execute");
  const canImportXmlFaturamento =
    canStrict("xml_import_faturamento.execute") ||
    canStrict("faturamento.nfe.import_xml") ||
    canStrict("faturamento.write") ||
    canStrict("financeiro.read") ||
    canStrict("financeiro.write") ||
    isFinanceiroEmpresaRole ||
    isFaturamentoEmpresaRole;
  const canAccessFaturamento =
    can("faturamento.read") ||
    can("faturamento.write") ||
    canImportXmlFaturamento ||
    canAccessFinanceiro ||
    isFaturamentoEmpresaRole;
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
  const canSeeEstoquePedidosMenuByEmpresaPapel = Boolean(
    empresaPapel &&
      ["ADMIN", "COORDENACAO", "ALMOXARIFADO", "FINANCEIRO", "COMPRAS", "APONTAMENTO_RH", "FATURAMENTO"].includes(empresaPapel)
  );
  const canSeeEstoqueMenuByEmpresaPapel = Boolean(
    empresaPapel &&
      ["ADMIN", "COORDENACAO", "ALMOXARIFADO", "FINANCEIRO", "COMPRAS", "APONTAMENTO_RH", "FATURAMENTO"].includes(empresaPapel)
  );
  const canSeeEstoqueMenu = canAccessEstoque || canSeeEstoqueMenuByEmpresaPapel;
  const canSeeEstoquePedidosMenu = canSeeEstoqueMenu || canSeeEstoquePedidosMenuByEmpresaPapel;
  const canSeeCadastroItensMenu = canAccessCadastroItens || canSeeEstoqueMenuByEmpresaPapel;
  const canSeeAjusteEstoqueMenu = can("estoque.read") || can("estoque.write") || canSeeEstoqueMenuByEmpresaPapel;
  const canSeeAjusteNomeMenu = Boolean(empresaPapel && ["ADMIN", "FINANCEIRO", "COORDENACAO", "FATURAMENTO"].includes(empresaPapel));
  const canSeeImobilizadoMenu = can("imobilizado.read") === true;

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

  // Anti-flicker: never render menus or protected content before we know auth + tenant/empresa.
  // AuthGate ensures a Supabase session exists; this ensures tenant/empresa context is ready.
  const hasSession = typeof te.sessionUserId === "string";
  const hasTenant = Boolean(te.tenantId);
  const hasEmpresa = Boolean(te.empresaId) || te.empresas.length === 1;
  if (!hasSession || !hasTenant || !hasEmpresa) {
    return null;
  }

  // Páginas de impressão: não renderizar chrome/layout do app (menu/topbar/etc).
  const isBlankPrint =
    pathname?.startsWith("/compras/pedidos/") && pathname?.endsWith("/imprimir") ||
    pathname?.startsWith("/comercial/orcamentos/") && pathname?.endsWith("/imprimir");
  if (isBlankPrint) return <>{children}</>;

  return (
    <div className="min-h-screen">
      {!hideHeader && (
        <header className="sticky top-0 z-50 border-b border-zinc-800 bg-zinc-950/80 backdrop-blur">
          <div
            className={"w-full px-4 md:px-6 py-3 flex items-center justify-between"}
            ref={navRef}
          >
            <div className="flex items-center gap-4 min-w-0 flex-1">
              <Link href="/" className="font-semibold tracking-tight text-zinc-100">
                Home
              </Link>

              <nav className="relative flex flex-nowrap items-center gap-2 md:gap-4 text-sm text-zinc-200 whitespace-nowrap">
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
                          <Link href="/os/analitico" className="block px-3 py-2 hover:bg-zinc-900">
                            Analitico
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
                        {canAccessApontamentos && (
                          <Link href="/apontamentos/resumo-mensal" className="block px-3 py-2 hover:bg-zinc-900">
                            Resumo Horas (Mês)
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
                        {canSeeAjusteNomeMenu && (
                          <Link href="/estoque/ajuste-nome" className="block px-3 py-2 hover:bg-zinc-900">
                            Ajuste Nome
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
                        {canSeeEstoquePedidosMenu && (
                          <Link href="/estoque/pedidos" className="block px-3 py-2 hover:bg-zinc-900">
                            Pedidos
                          </Link>
                        )}
                        {can("estoque.read") && (
                          <Link href="/estoque/relatorios" className="block px-3 py-2 hover:bg-zinc-900">
                            Relatórios
                          </Link>
                        )}
                      </div>
                    )}
                  </div>
                )}

                {canSeeImobilizadoMenu && (
                  <div
                    className="relative"
                    onMouseEnter={() => openWithHover("imobilizado")}
                    onMouseLeave={scheduleClose}
                  >
                    <button
                      type="button"
                      onClick={() => toggleMenu("imobilizado")}
                      className="px-3 py-1 rounded-md hover:bg-zinc-900 flex items-center gap-2"
                    >
                      Imobilizado
                    </button>

                    {openMenu === "imobilizado" && (
                      <div
                        className="absolute left-0 top-full mt-1 w-64 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                        onMouseEnter={() => openWithHover("imobilizado")}
                        onMouseLeave={scheduleClose}
                      >
                        <Link href="/imobilizado/itens" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                          Itens
                        </Link>
                        <div className="relative group/imo">
                          <div className="px-3 py-2 hover:bg-zinc-900 text-sm flex items-center justify-between cursor-default select-none">
                            <span>Ferramentas</span>
                            <span className="text-zinc-500">{">"}</span>
                          </div>
                          <div className="hidden group-hover/imo:block absolute left-full top-0 ml-1 w-72 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-30">
                            <Link href="/imobilizado/ferramentas/catalogo" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Catálogo
                            </Link>
                            <Link href="/imobilizado/ferramentas/caixas" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Caixas
                            </Link>
                            <Link href="/imobilizado/ferramentas/sugestoes-xml" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Sugestões do XML
                            </Link>
                          </div>
                        </div>
                      </div>
                    )}
                  </div>
                )}

                {canAccessFinanceiroMenu && (
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
                        className="absolute left-0 top-full mt-1 w-64 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                        onMouseEnter={() => openWithHover("financeiro")}
                        onMouseLeave={scheduleClose}
                      >
                        <Link href="/financeiro" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                          Dashboard
                        </Link>
                        <Link href="/financeiro/contas_pagar_receber" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                          Fluxo Caixa
                        </Link>
                        <Link href="/financeiro/gestao-cobranca" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                          Gestão Cobrança
                        </Link>

                        <div className="border-t border-zinc-800 my-2" />

                        <div className="relative group/fin">
                          <div className="px-3 py-2 hover:bg-zinc-900 text-sm flex items-center justify-between cursor-default select-none">
                            <span>Contas a Pagar</span>
                            <span className="text-zinc-500">{">"}</span>
                          </div>
                          <div className="hidden group-hover/fin:block absolute left-full top-0 ml-1 w-72 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-30">
                            <Link href="/financeiro/contas-pagar/lancamentos" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Lançamentos
                            </Link>
                            <Link href="/financeiro/contas-pagar/aprovacoes" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Aprovações
                            </Link>
                            <Link href="/financeiro/contas-pagar/pagamentos" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Pagamentos
                            </Link>
                          </div>
                        </div>

                        <div className="relative group/fin">
                          <div className="px-3 py-2 hover:bg-zinc-900 text-sm flex items-center justify-between cursor-default select-none">
                            <span>Contas a Receber</span>
                            <span className="text-zinc-500">{">"}</span>
                          </div>
                          <div className="hidden group-hover/fin:block absolute left-full top-0 ml-1 w-72 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-30">
                            <Link href="/financeiro/contas-receber/lancamentos" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Lançamentos
                            </Link>
                            <Link href="/financeiro/contas-receber/recebimentos" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Recebimentos
                            </Link>
                          </div>
                        </div>

                        <div className="relative group/fin">
                          <div className="px-3 py-2 hover:bg-zinc-900 text-sm flex items-center justify-between cursor-default select-none">
                            <span>Caixa &amp; Bancos</span>
                            <span className="text-zinc-500">{">"}</span>
                          </div>
                          <div className="hidden group-hover/fin:block absolute left-full top-0 ml-1 w-72 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-30">
                            <Link href="/financeiro/extratos" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Extratos Bancários
                            </Link>
                            <Link href="/financeiro/conciliacao" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Conciliação Bancária
                            </Link>
                            <Link href="/financeiro/transferencias" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Transferências
                            </Link>
                          </div>
                        </div>

                        <div className="border-t border-zinc-800 my-2" />

                        <div className="relative group/fin">
                          <div className="px-3 py-2 hover:bg-zinc-900 text-sm flex items-center justify-between cursor-default select-none">
                            <span>Cadastros</span>
                            <span className="text-zinc-500">{">"}</span>
                          </div>
                          <div className="hidden group-hover/fin:block absolute left-full top-0 ml-1 w-72 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-30">
                            <div className="px-3 py-2 text-xs font-semibold text-zinc-400">Estrutura</div>
                            <Link href="/financeiro/cadastros/plano-contas" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Plano de Contas
                            </Link>
                            <Link href="/financeiro/cadastros/centro-custo" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Centros de Custo
                            </Link>

                            <div className="border-t border-zinc-800 my-2" />
                            <div className="px-3 py-2 text-xs font-semibold text-zinc-400">Bancos</div>
                            <Link href="/financeiro/cadastros/contas-bancarias" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Contas Bancárias
                            </Link>

                            <div className="border-t border-zinc-800 my-2" />
                            <div className="px-3 py-2 text-xs font-semibold text-zinc-400">Classificações</div>
                            <Link href="/financeiro/cadastros/motivos-compra" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Motivos / Classificação de Compra
                            </Link>
                          </div>
                        </div>

                        <div className="relative group/fin">
                          <div className="px-3 py-2 hover:bg-zinc-900 text-sm flex items-center justify-between cursor-default select-none">
                            <span>Relatórios</span>
                            <span className="text-zinc-500">{">"}</span>
                          </div>
                          <div className="hidden group-hover/fin:block absolute left-full top-0 ml-1 w-72 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-30">
                            <div className="px-3 py-2 text-xs font-semibold text-zinc-400">Fluxo de Caixa</div>
                            <Link href="/financeiro/relatorios/fluxo-caixa/previsto" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Previsto
                            </Link>
                            <Link href="/financeiro/relatorios/fluxo-caixa/realizado" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Realizado
                            </Link>
                            <Link href="/financeiro/relatorios/fluxo-caixa/diario" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Diário
                            </Link>
                            <div className="border-t border-zinc-800 my-2" />
                            <div className="px-3 py-2 text-xs font-semibold text-zinc-400">Aging</div>
                            <Link href="/financeiro/relatorios/ap-aging" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Aging (Contas a Pagar)
                            </Link>
                            <Link href="/financeiro/relatorios/ar-aging" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                              Aging (Contas a Receber)
                            </Link>
                          </div>
                        </div>

                        <Link href="/financeiro/impostos" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                          Impostos
                        </Link>

                        <Link href="/financeiro/configuracoes" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                          Configurações
                        </Link>

                      </div>
                    )}
                  </div>
                )}

                {canAccessCompras && (
                  <div
                    className="relative"
                    onMouseEnter={() => openWithHover("compras")}
                    onMouseLeave={scheduleClose}
                  >
                    <button
                      type="button"
                      onClick={() => toggleMenu("compras")}
                      className="px-3 py-1 rounded-md hover:bg-zinc-900 flex items-center gap-2"
                    >
                      Compras
                    </button>

                    {openMenu === "compras" && (
                      <div
                        className="absolute left-0 top-full mt-1 w-56 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                        onMouseEnter={() => openWithHover("compras")}
                        onMouseLeave={scheduleClose}
                      >
                        <Link href="/compras/pedidos" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                          Pedidos
                        </Link>
                        <Link href="/compras/configuracao" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                          Configuração
                        </Link>
                      </div>
                    )}
                  </div>
                )}

                {canAccessComercial && (
                  <div
                    className="relative"
                    onMouseEnter={() => openWithHover("comercial")}
                    onMouseLeave={scheduleClose}
                  >
                    <button
                      type="button"
                      onClick={() => toggleMenu("comercial")}
                      className="px-3 py-1 rounded-md hover:bg-zinc-900 flex items-center gap-2"
                    >
                      Comercial
                    </button>

                    {openMenu === "comercial" && (
                      <div
                        className="absolute left-0 top-full mt-1 w-64 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                        onMouseEnter={() => openWithHover("comercial")}
                        onMouseLeave={scheduleClose}
                      >
                        <Link href="/comercial/orcamentos" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                          Orçamentos
                        </Link>

                        <div className="border-t border-zinc-800 my-2" />
                        <div className="px-3 py-2 text-xs font-semibold text-zinc-400">Configurações</div>
                        <Link href="/comercial/analitico" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                          Analitico
                        </Link>
                        <Link
                          href="/configuracoes/comercial/orcamentos"
                          className="block px-5 py-2 hover:bg-zinc-900 text-sm"
                        >
                          Configuração Orçamentos
                        </Link>
                        <Link
                          href="/configuracoes/comercial/condicoes-pagamento"
                          className="block px-5 py-2 hover:bg-zinc-900 text-sm"
                        >
                          Condições de Pagamento
                        </Link>
                        <Link
                          href="/configuracoes/comercial/conjuntos"
                          className="block px-5 py-2 hover:bg-zinc-900 text-sm"
                        >
                          Conjuntos
                        </Link>
                      </div>
                    )}
                  </div>
                )}

                {canAccessFaturamento && (
                  <div
                    className="relative"
                    onMouseEnter={() => openWithHover("faturamento")}
                    onMouseLeave={scheduleClose}
                  >
                    <button
                      type="button"
                      onClick={() => toggleMenu("faturamento")}
                      className="px-3 py-1 rounded-md hover:bg-zinc-900 flex items-center gap-2"
                    >
                      Faturamento
                    </button>

                    {openMenu === "faturamento" && (
                      <div
                        className="absolute left-0 top-full mt-1 w-56 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                        onMouseEnter={() => openWithHover("faturamento")}
                        onMouseLeave={scheduleClose}
                      >
                        <Link href="/faturamento/nfse" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                          NFS-e
                        </Link>
                        <Link href="/faturamento/nfe" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                          NF-e
                        </Link>
                        <Link href="/faturamento/analitico" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                          Analitico
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
                            <Link href="/cadastros/cargos" className="block px-5 py-2 hover:bg-zinc-900 text-sm">
                              Cargos
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
                onClick={toggleTheme}
                title={theme === "dark" ? "Mudar para tema claro" : "Mudar para tema escuro"}
                className="px-2 py-1.5 rounded-md border border-zinc-700 hover:bg-zinc-800 text-sm"
              >
                {theme === "dark" ? (
                  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M12 3a9 9 0 1 0 9 9c0-.46-.04-.92-.1-1.36a5.389 5.389 0 0 1-4.4 2.26 5.403 5.403 0 0 1-3.14-9.8c-.44-.06-.9-.1-1.36-.1z"/>
                  </svg>
                ) : (
                  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M12 7a5 5 0 1 0 0 10A5 5 0 0 0 12 7zm0-5a1 1 0 0 1 1 1v1a1 1 0 1 1-2 0V3a1 1 0 0 1 1-1zm0 17a1 1 0 0 1 1 1v1a1 1 0 1 1-2 0v-1a1 1 0 0 1 1-1zM4.22 4.22a1 1 0 0 1 1.41 0l.71.71a1 1 0 0 1-1.41 1.41l-.71-.71a1 1 0 0 1 0-1.41zm13.44 13.44a1 1 0 0 1 1.41 0l.71.71a1 1 0 1 1-1.41 1.41l-.71-.71a1 1 0 0 1 0-1.41zM3 12a1 1 0 0 1 1-1h1a1 1 0 1 1 0 2H4a1 1 0 0 1-1-1zm17 0a1 1 0 0 1 1-1h1a1 1 0 1 1 0 2h-1a1 1 0 0 1-1-1zM4.93 18.36a1 1 0 0 1 0-1.41l.71-.71a1 1 0 1 1 1.41 1.41l-.71.71a1 1 0 0 1-1.41 0zm13.44-13.44a1 1 0 0 1 0-1.41l.71-.71a1 1 0 1 1 1.41 1.41l-.71.71a1 1 0 0 1-1.41 0z"/>
                  </svg>
                )}
              </button>

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
              : isOsDetailPage
                ? "mx-auto max-w-[86.4rem] px-4 py-6"
                : "mx-auto max-w-6xl px-4 py-6"
        }
      >
        {children}
      </main>
    </div>
  );
}
