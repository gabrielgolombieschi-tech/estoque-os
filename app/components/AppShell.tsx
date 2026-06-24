"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresaContext } from "@/lib/auth/TenantEmpresaProvider";
import { useIsAdminTenant } from "@/lib/auth/useIsAdminTenant";
import type { CapabilityKey } from "@/lib/auth/capabilities";
import AdminDebugPanel from "./AdminDebugPanel";

const isDev = process.env.NODE_ENV !== "production";
const logError = (...args: unknown[]) => {
  if (isDev) console.warn(...args);
};

export default function AppShell({ children }: { children: React.ReactNode }) {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const te = useTenantEmpresaContext();

  const router = useRouter();
  const pathname = usePathname();

  const isPublic = pathname === "/login";
  const isFullWidth =
    pathname === "/itens" || pathname === "/financeiro/contas-pagar/aprovacoes" || pathname === "/financeiro/gestao-cobranca";
  const isOsDetailPage = /^\/os\/\d+\/?$/.test(pathname ?? "");
  const hideHeader = pathname?.startsWith("/projetos") || pathname?.startsWith("/execucao");

  const tenantId = te.tenantId;
  const empresaId = te.empresaId;
  const empresas = te.empresas;

  const { isAdmin: isTenantAdmin, loading: adminLoading } = useIsAdminTenant(tenantId ?? null);
  const didAutoSelectEmpresaRef = useRef(false);

  const effectiveEmpresa = useMemo(() => {
    if (empresaId) return empresas.find((e) => e.id === empresaId) ?? null;
    if (empresas.length === 1) return empresas[0];
    return null;
  }, [empresaId, empresas]);
  const empresaRole = String(effectiveEmpresa?.papel ?? "")
    .trim()
    .toUpperCase();

  useEffect(() => {
    if (te.sessionUserId === undefined) return;
    const isAuthed = Boolean(te.sessionUserId);
    if (!isAuthed && !isPublic) router.replace("/login");
    if (isAuthed && isPublic) router.replace("/");
  }, [isPublic, router, te.sessionUserId]);

  useEffect(() => {
    if (te.sessionUserId === null) {
      didAutoSelectEmpresaRef.current = false;
    }
  }, [te.sessionUserId]);

  useEffect(() => {
    if (didAutoSelectEmpresaRef.current) return;
    if (!te.sessionUserId) return; // só quando logado
    if (!empresaId && empresas.length === 1) {
      didAutoSelectEmpresaRef.current = true;
      void te.setEmpresaId(empresas[0].id);
    }
  }, [empresaId, empresas, te.sessionUserId, te.setEmpresaId]);

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

  const can = (k: CapabilityKey) => {
    if (te.capabilities === null) return true;
    return te.has(k) ?? false;
  };

  const canAccessOs = can("os.read");
  const canExecuteOs = can("os_rpcs.execute");
  const canAccessApontamentos = can("apontamentos.read");
  const canAccessEstoque = can("estoque.read") || can("estoque.write");
  const canAccessCadastroItens = can("cad_itens.write") || can("estoque.read") || can("os.read");
  const canSeeAjusteNomeMenu = Boolean(empresaRole && ["ADMIN", "FINANCEIRO", "COORDENACAO", "FATURAMENTO"].includes(empresaRole));
  const canImportXml = can("xml_import.execute");
  const canAccessFinanceiro = can("financeiro.read");
  const canAccessAdmin = can("admin.manage_users");
  const shouldShowAdmin = isTenantAdmin && (!adminLoading ? canAccessAdmin : true);
  const adminReason = useMemo(() => {
    if (shouldShowAdmin) return "ok";
    const reasons: string[] = [];
    if (te.sessionUserId === undefined) reasons.push("sessionUserId=undefined");
    if (te.sessionUserId === null) reasons.push("not authenticated");
    if (!te.tenantId) reasons.push("tenantId missing");
    if (adminLoading) reasons.push("adminLoading");
    if (!isTenantAdmin) reasons.push("isAdminTenant=false");
    if (!adminLoading && isTenantAdmin && !canAccessAdmin) reasons.push("can(admin.manage_users)=false");
    return reasons.join(", ") || "unknown";
  }, [adminLoading, canAccessAdmin, isTenantAdmin, shouldShowAdmin, te.sessionUserId, te.tenantId]);
  const canAccessCadastros = can("admin.manage_users") || can("financeiro.read");
  const canAccessContratos = can("admin.manage_users") || can("financeiro.read") || can("apontamentos.read");
  const canAccessColaboradores = can("admin.manage_users") || can("financeiro.read");
  const canAccessClientesCad = can("admin.manage_users") || can("financeiro.read") || can("cad_clientes.write");
  const canAccessFornecedoresCad =
    can("admin.manage_users") ||
    can("financeiro.read") ||
    can("cad_fornecedores.write") ||
    can("estoque.read") ||
    can("estoque.write");

  async function logout() {
    try {
      await supabase.auth.signOut();
    } catch (e) {
      logError("Erro ao sair", e);
    } finally {
      router.replace("/login");
      if (typeof window !== "undefined") window.location.href = "/login";
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
                        {canSeeAjusteNomeMenu && (
                          <Link href="/estoque/ajuste-nome" className="block px-3 py-2 hover:bg-zinc-900">
                            Ajuste Nome
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
                        {can("estoque.read") && (
                          <Link href="/estoque/relatorios" className="block px-3 py-2 hover:bg-zinc-900">
                            Relatórios
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
                        className="absolute left-0 top-full mt-1 w-64 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                        onMouseEnter={() => openWithHover("financeiro")}
                        onMouseLeave={scheduleClose}
                      >
                        {/* item simples */}
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

                        {/* item com flyout (submenu à direita) */}
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

                        <Link href="/financeiro/configuracoes" className="block px-3 py-2 hover:bg-zinc-900 text-sm">
                          Configurações
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
                <div className="text-[11px] text-zinc-400 whitespace-nowrap">
                  Atualizando...
                </div>
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
                  <span className="text-xs text-zinc-100 font-medium opacity-70">
                    Carregando...
                  </span>
                </div>
              )}

              <div className="flex flex-col items-end gap-1">
                {te.sessionEmail && (
                  <div className="text-xs text-zinc-300 select-none whitespace-nowrap">
                    <div>{te.sessionEmail}</div>
                  </div>
                )}
                <AdminDebugPanel
                  providerBuildId={te.providerBuildId}
                  sessionUserId={te.sessionUserId}
                  email={te.sessionEmail}
                  tenantId={te.tenantId}
                  empresaId={te.empresaId}
                  empresas={te.empresas}
                  isAdminTenant={isTenantAdmin}
                  adminLoading={adminLoading}
                  capabilities={te.capabilities}
                  lastLoadPermissions={te.lastLoadPermissions}
                  lastLoadPermissionsRaw={te.lastLoadPermissionsRaw}
                  lastLoadSource={te.lastLoadSource}
                  lastLoadCount={te.lastLoadCount}
                  lastLoadError={te.lastLoadError}
                  can={can}
                  canAdminManageUsers={canAccessAdmin}
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
