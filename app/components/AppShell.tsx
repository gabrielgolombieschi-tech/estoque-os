"use client";

import { useEffect, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { supabaseBrowser } from "../../lib/supabase/client";
import { clearPermissionCache } from "@/lib/auth/permissions";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { Can } from "@/components/auth/Can";

export default function AppShell({ children }: { children: React.ReactNode }) {
  const supabase = supabaseBrowser();
  const router = useRouter();
  const pathname = usePathname();
  const { clear, tenantId } = usePermissions();

  const [loading, setLoading] = useState(true);
  const [userInfo, setUserInfo] = useState<{ id: string; email: string } | null>(null);
  const [userRole, setUserRole] = useState<string | null>(null);
  const isPublic = pathname === "/login";
  const isFullWidth = pathname === "/itens";
  const hideHeader = pathname?.startsWith("/projetos") || pathname?.startsWith("/execucao");

  const [openMenu, setOpenMenu] = useState<"os" | "estoque" | null>(null);
  const navRef = useRef<HTMLDivElement | null>(null);
  const closeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    (async () => {
      const { data } = await supabase.auth.getSession();
      const isAuthed = !!data.session;
      const user = data.session?.user;
      setUserInfo(user ? { id: user.id, email: user.email ?? "" } : null);
      setUserRole(null);

      if (!isAuthed && !isPublic) router.replace("/login");
      if (isAuthed && isPublic) router.replace("/");

      setLoading(false);
    })();

    const { data: sub } = supabase.auth.onAuthStateChange((_evt, session) => {
      clearPermissionCache();
      clear();
      const isAuthed = !!session;
      const user = session?.user;
      setUserInfo(user ? { id: user.id, email: user.email ?? "" } : null);
      setUserRole(null);
      if (!isAuthed && !isPublic) router.replace("/login");
      if (isAuthed && isPublic) router.replace("/");
    });

    return () => sub.subscription.unsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pathname]);

  useEffect(() => {
    const handleClickOutside = (ev: MouseEvent) => {
      if (!navRef.current) return;
      if (navRef.current.contains(ev.target as Node)) return;
      setOpenMenu(null);
    };
    window.addEventListener("click", handleClickOutside);
    return () => window.removeEventListener("click", handleClickOutside);
  }, []);

  useEffect(() => {
    if (!userInfo?.id || !tenantId) {
      setUserRole(null);
      return;
    }

    let active = true;

    (async () => {
      const { data: u } = await supabase.auth.getUser();
      if (!u.user?.id) {
        if (active) setUserRole(null);
        return;
      }

      const { data, error } = await supabase.rpc("get_my_roles");
      if (error) {
        console.error("Erro get_my_roles:", error);
        if (active) setUserRole(null);
        return;
      }

      const roles = (data ?? []).map((x: any) => x.role).filter(Boolean);
      if (active) setUserRole(roles.length ? roles.join(", ") : null);
    })();

    return () => {
      active = false;
    };
  }, [userInfo?.id, tenantId]);

  async function logout() {
    try {
      await supabase.auth.signOut();
    } catch (e) {
      console.error("Erro ao sair", e);
    } finally {
      clearPermissionCache();
      clear();
      router.replace("/login");
      if (typeof window !== "undefined") {
        window.location.href = "/login";
      }
    }
  }

  const toggleMenu = (key: "os" | "estoque") => {
    setOpenMenu((prev) => (prev === key ? null : key));
  };

  const closeMenu = () => setOpenMenu(null);

  const openWithHover = (key: "os" | "estoque") => {
    if (closeTimerRef.current) clearTimeout(closeTimerRef.current);
    setOpenMenu(key);
  };

  const scheduleClose = () => {
    if (closeTimerRef.current) clearTimeout(closeTimerRef.current);
    closeTimerRef.current = setTimeout(() => setOpenMenu(null), 150);
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando...
      </div>
    );
  }

  // Tela pública (login) sem menu
  if (isPublic) return <>{children}</>;

  return (
      <div className="min-h-screen">
      {!hideHeader && (
        <header className="sticky top-0 z-50 border-b border-zinc-800 bg-zinc-950/80 backdrop-blur pointer-events-auto">
          <div
            className="mx-auto max-w-6xl px-4 py-3 flex items-center justify-between pointer-events-auto"
            ref={navRef}
          >
            <div className="flex items-center gap-4">
              <a href="/" className="font-semibold tracking-tight text-zinc-100">
                Home
              </a>

              <nav className="relative flex flex-wrap items-center gap-4 text-sm text-zinc-200">
                <div
                  className="relative"
                  onMouseEnter={() => openWithHover("os")}
                  onMouseLeave={scheduleClose}
                >
                  <button
                    type="button"
                    onClick={() => toggleMenu("os")}
                    className="px-3 py-1 rounded-md hover:bg-zinc-900 flex items-center gap-2 cursor-pointer"
                  >
                    Ordem de Serviço
                    <span className="text-[10px]">▼</span>
                  </button>
                  {openMenu === "os" && (
                    <div
                      className="absolute left-0 top-full mt-1 w-52 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                      onMouseEnter={() => openWithHover("os")}
                      onMouseLeave={scheduleClose}
                    >
                      <a href="/os" className="block px-3 py-2 hover:bg-zinc-900 cursor-pointer">
                        OS
                      </a>
                      <a href="/baixa_os" className="block px-3 py-2 hover:bg-zinc-900 cursor-pointer">
                        Apontamentos
                      </a>
                      <a href="/baixa_os_cel" className="block px-3 py-2 hover:bg-zinc-900 cursor-pointer">
                        Apontamento Celular
                      </a>
                      <a href="/execucao" className="block px-3 py-2 hover:bg-zinc-900 cursor-pointer">
                        Painel Execução
                      </a>
                      <a href="/projetos" className="block px-3 py-2 hover:bg-zinc-900 cursor-pointer">
                        Painel Projetos
                      </a>
                    </div>
                  )}
                </div>

                <div
                  className="relative"
                  onMouseEnter={() => openWithHover("estoque")}
                  onMouseLeave={scheduleClose}
                >
                  <button
                    type="button"
                    onClick={() => toggleMenu("estoque")}
                    className="px-3 py-1 rounded-md hover:bg-zinc-900 flex items-center gap-2 cursor-pointer"
                  >
                    Estoque
                    <span className="text-[10px]">▼</span>
                  </button>
                  {openMenu === "estoque" && (
                    <div
                      className="absolute left-0 top-full mt-1 w-52 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                      onMouseEnter={() => openWithHover("estoque")}
                      onMouseLeave={scheduleClose}
                    >
                      <Can perm="estoque.ajuste.create">
                        <a href="/estoque" className="block px-3 py-2 hover:bg-zinc-900 cursor-pointer">
                          Ajuste Estoque
                        </a>
                      </Can>
                      <Can perm="itens.create">
                        <a href="/itens" className="block px-3 py-2 hover:bg-zinc-900 cursor-pointer">
                          Cadastro
                        </a>
                      </Can>
                      <a href="/estoque/importar" className="block px-3 py-2 hover:bg-zinc-900 cursor-pointer">
                        Importar XML
                      </a>
                      <a href="/mov" className="block px-3 py-2 hover:bg-zinc-900 cursor-pointer">
                        Movimentação
                      </a>
                    </div>
                  )}
                </div>
                <button
                  type="button"
                  onClick={logout}
                  className="px-3 py-1.5 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
                >
                  Sair
                </button>
              </nav>
            </div>

            <div className="flex items-center gap-3 pointer-events-auto">
              {userInfo && (
                <div className="text-xs text-zinc-300 pointer-events-none select-none whitespace-nowrap">
                  <div>USER LOGADO: {userInfo.email}</div>
                  <div className="text-[11px] text-zinc-400">ROLE: {userRole ?? "-"}</div>
                </div>
              )}
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
