"use client";

import { useEffect, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { supabaseBrowser } from "../../lib/supabase/client";

export default function AppShell({ children }: { children: React.ReactNode }) {
  const supabase = supabaseBrowser();
  const router = useRouter();
  const pathname = usePathname();

  const [loading, setLoading] = useState(true);
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

      if (!isAuthed && !isPublic) router.replace("/login");
      if (isAuthed && isPublic) router.replace("/");

      setLoading(false);
    })();

    const { data: sub } = supabase.auth.onAuthStateChange((_evt, session) => {
      const isAuthed = !!session;
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

  async function logout() {
    await supabase.auth.signOut();
    router.replace("/login");
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
        <header className="sticky top-0 z-10 border-b border-zinc-800 bg-zinc-950/80 backdrop-blur">
          <div className="mx-auto max-w-6xl px-4 py-3 flex items-center justify-between" ref={navRef}>
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
                      <a href="/estoque" className="block px-3 py-2 hover:bg-zinc-900 cursor-pointer">
                        Ajuste Estoque
                      </a>
                      <a href="/itens" className="block px-3 py-2 hover:bg-zinc-900 cursor-pointer">
                        Cadastro
                      </a>
                      <a href="/mov" className="block px-3 py-2 hover:bg-zinc-900 cursor-pointer">
                        Movimentação
                      </a>
                    </div>
                  )}
                </div>
              </nav>
            </div>

            <button
              onClick={logout}
              className="px-3 py-1.5 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
            >
              Sair
            </button>
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
