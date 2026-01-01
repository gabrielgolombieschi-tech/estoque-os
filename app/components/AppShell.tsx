"use client";

import { useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { supabaseBrowser } from "../../lib/supabase/client";

export default function AppShell({ children }: { children: React.ReactNode }) {
  const supabase = supabaseBrowser();
  const router = useRouter();
  const pathname = usePathname();

  const [loading, setLoading] = useState(true);
  const isPublic = pathname === "/login";
  const hideHeader = pathname?.startsWith("/projetos") || pathname?.startsWith("/execucao");

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

  async function logout() {
    await supabase.auth.signOut();
    router.replace("/login");
  }

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
      {!hideHeader && (<header className="sticky top-0 z-10 border-b border-zinc-800 bg-zinc-950/80 backdrop-blur">
        <div className="mx-auto max-w-6xl px-4 py-3 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <a href="/" className="font-semibold tracking-tight text-zinc-100">
              Estoque + OS
            </a>

            <nav className="flex items-center gap-2 text-sm">
              <a
                href="/os"
                className="px-3 py-1 rounded-md hover:bg-zinc-900 text-zinc-200"
              >
                Ordens de Serviço
              </a>
              <a
                href="/itens"
                className="px-3 py-1 rounded-md hover:bg-zinc-900 text-zinc-200"
              >
                Itens
              </a>
              <a
                href="/estoque"
                className="px-3 py-1 rounded-md hover:bg-zinc-900 text-zinc-200"
              >
                Estoque
              </a>
              <a
                href="/mov"
                className="px-3 py-1 rounded-md hover:bg-zinc-900 text-zinc-200"
              >
                Movimentações
              </a>
            </nav>
          </div>

          <button
            onClick={logout}
            className="px-3 py-1.5 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
          >
            Sair
          </button>
        </div>
      </header>)}

      <main className={hideHeader ? "w-full px-6 py-6" : "mx-auto max-w-6xl px-4 py-6"}>{children}</main>
    </div>
  );
}
