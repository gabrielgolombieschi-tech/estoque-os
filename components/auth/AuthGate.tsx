"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { getSupabaseBrowser } from "@/lib/auth/supabase";

type AuthStatus = "checking" | "authed" | "guest";

type Props = {
  children: ReactNode;
  /**
   * When true, renders a minimal loading screen during auth resolution.
   * When false, returns null while loading/redirecting (maximum anti-flicker).
   */
  showLoading?: boolean;
};

function isPublicPath(pathname: string): boolean {
  // Public routes must never be gated; they also must not show menus (AppShell handles that).
  if (pathname === "/login") return true;
  if (pathname === "/reset-password" || pathname === "/auth/reset-password") return true;
  if (pathname === "/reset-password/" || pathname === "/auth/reset-password/") return true;
  return false;
}

function buildNextParam(pathname: string, searchParams: URLSearchParams | null): string {
  const qs = searchParams ? searchParams.toString() : "";
  return qs ? `${pathname}?${qs}` : pathname;
}

export default function AuthGate({ children, showLoading = false }: Props) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const publicRoute = useMemo(() => isPublicPath(pathname), [pathname]);
  const nextUrl = useMemo(() => buildNextParam(pathname, searchParams), [pathname, searchParams]);

  const [status, setStatus] = useState<AuthStatus>("checking");
  const didRedirectRef = useRef(false);
  const verifyIdRef = useRef(0);

  const redirectToLogin = useCallback(() => {
    // Avoid loops if already on login.
    if (pathname === "/login") return;
    if (didRedirectRef.current) return;
    didRedirectRef.current = true;
    const next = encodeURIComponent(nextUrl);
    router.replace(`/login?next=${next}`);
  }, [nextUrl, pathname, router]);

  const verify = useCallback(async () => {
    const supabase = getSupabaseBrowser();
    const verifyId = ++verifyIdRef.current;
    const isStale = () => verifyIdRef.current !== verifyId;

    setStatus("checking");

    try {
      const { data: sessData, error: sessErr } = await supabase.auth.getSession();
      if (isStale()) return;

      const session = sessErr ? null : sessData.session ?? null;
      if (!session) {
        setStatus("guest");
        return;
      }

      // STRICT MODE: require a real network verification.
      const { data: userData, error: userErr } = await supabase.auth.getUser();
      if (isStale()) return;

      const user = userErr ? null : userData.user ?? null;
      if (!user) {
        // Clear any stale session from storage/cookies to prevent repeated flashes.
        try {
          await supabase.auth.signOut();
        } catch {
          // ignore
        }
        if (isStale()) return;
        setStatus("guest");
        return;
      }

      setStatus("authed");
    } catch {
      if (isStale()) return;
      try {
        await getSupabaseBrowser().auth.signOut();
      } catch {
        // ignore
      }
      if (isStale()) return;
      setStatus("guest");
    }
  }, []);

  // Resolve session eagerly; never render protected UI before this completes.
  useEffect(() => {
    if (publicRoute) return;

    let active = true;
    const supabase = getSupabaseBrowser();

    const run = async () => {
      await verify();
    };

    void run();

    const { data: sub } = supabase.auth.onAuthStateChange((event) => {
      if (!active) return;

      // IMPORTANT: don't trust event session; always re-verify with getUser().
      if (event === "SIGNED_OUT") {
        setStatus("guest");
        return;
      }

      if (event === "INITIAL_SESSION" || event === "SIGNED_IN" || event === "TOKEN_REFRESHED" || event === "USER_UPDATED") {
        void verify();
      }
    });

    return () => {
      active = false;
      sub.subscription.unsubscribe();
    };
  }, [publicRoute, verify]);

  // Redirect guests immediately (but only once).
  useEffect(() => {
    if (publicRoute) return;
    if (status !== "guest") return;
    redirectToLogin();
  }, [publicRoute, redirectToLogin, status]);

  if (publicRoute) return <>{children}</>;

  if (status !== "authed") {
    if (!showLoading) return null;
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando...</div>;
  }

  return <>{children}</>;
}
