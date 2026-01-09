"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { supabaseBrowser } from "../../lib/supabase/client";
import { clearPermissionCache } from "@/lib/auth/permissions";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { Can } from "@/components/auth/Can";

type UserInfo = { id: string; email: string };

export default function AppShell({ children }: { children: React.ReactNode }) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const router = useRouter();
  const pathname = usePathname();

  // Seu provider deve expor pelo menos clear() e idealmente reload()
  // Se não tiver reload(), remova do destructuring e as chamadas abaixo.
  const { clear, reload } = usePermissions();

  const [booting, setBooting] = useState(true);
  const [userInfo, setUserInfo] = useState<UserInfo | null>(null);
  const [userRole, setUserRole] = useState<string | null>(null);

  const isPublic = pathname === "/login";
  const isFullWidth = pathname === "/itens";
  const hideHeader = pathname?.startsWith("/projetos") || pathname?.startsWith("/execucao");

  const [openMenu, setOpenMenu] = useState<"os" | "estoque" | null>(null);
  const navRef = useRef<HTMLDivElement | null>(null);
  const closeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // 1) Boot: pega sessão 1x e libera a UI (não trava esperando permissões)
  useEffect(() => {
    let active = true;

    (async () => {
      try {
        const { data, error } = await supabase.auth.getSession();
        if (!active) return;

        if (error) console.error("getSession error:", error);

        const session = data.session;
        const user = session?.user;

        setUserInfo(user ? { id: user.id, email: user.email ?? "" } : null);
        setUserRole(null);

        // Recarrega permissões em background (sem travar)
        if (session) {
          reload().catch((e: any) => console.error("reload permissions error:", e));
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
        reload().catch((e: any) => console.error("reload permissions error:", e));
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
          console.error("Erro debug_me:", dbg.error);
          if (active) setUserRole(null);
          return;
        }

        const roles = (dbg.data as any)?.roles ?? [];
        if (active) setUserRole(roles.length ? roles.join(", ") : null);
      } catch (e) {
        console.error("Erro ao carregar role:", e);
        if (active) setUserRole(null);
      }
    })();

    return () => {
      active = false;
    };
  }, [userInfo?.id, supabase]);

  async function logout() {
    try {
      await supabase.auth.signOut();
    } catch (e) {
      console.error("Erro ao sair", e);
    } finally {
      clearPermissionCache();
      clear();
      router.replace("/login");
      if (typeof window !== "undefined") window.location.href = "/login";
    }
  }

  const toggleMenu = (key: "os" | "estoque") => setOpenMenu((prev) => (prev === key ? null : key));

  const openWithHover = (key: "os" | "estoque") => {
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
                    Ordem de Serviço <span className="text-[10px]">▼</span>
                  </button>

                  {openMenu === "os" && (
                    <div
                      className="absolute left-0 top-full mt-1 w-52 rounded-md border border-zinc-800 bg-zinc-950 shadow-lg py-2 z-20"
                      onMouseEnter={() => openWithHover("os")}
                      onMouseLeave={scheduleClose}
                    >
                      <Link href="/os" className="block px-3 py-2 hover:bg-zinc-900">
                        OS
                      </Link>
                      <Link href="/baixa_os" className="block px-3 py-2 hover:bg-zinc-900">
                        Apontamentos
                      </Link>
                      <Link href="/baixa_os_cel" className="block px-3 py-2 hover:bg-zinc-900">
                        Apontamento Celular
                      </Link>
                      <Link href="/execucao" className="block px-3 py-2 hover:bg-zinc-900">
                        Painel Execução
                      </Link>
                      <Link href="/projetos" className="block px-3 py-2 hover:bg-zinc-900">
                        Painel Projetos
                      </Link>
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
                      <Can perm="estoque.ajuste.create">
                        <Link href="/estoque" className="block px-3 py-2 hover:bg-zinc-900">
                          Ajuste Estoque
                        </Link>
                      </Can>

                      <Can perm="itens.create">
                        <Link href="/itens" className="block px-3 py-2 hover:bg-zinc-900">
                          Cadastro
                        </Link>
                      </Can>

                      <Link href="/estoque/importar" className="block px-3 py-2 hover:bg-zinc-900">
                        Importar XML
                      </Link>

                      <Link href="/mov" className="block px-3 py-2 hover:bg-zinc-900">
                        Movimentação
                      </Link>
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

            <div className="flex items-center gap-3">
              {userInfo && (
                <div className="text-xs text-zinc-300 select-none whitespace-nowrap">
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

