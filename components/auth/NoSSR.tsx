"use client";

import { useEffect, useState, type ReactNode } from "react";

/**
 * NoSSR ensures children are never server-rendered.
 * This prevents protected UI (menus, content) from appearing in the initial HTML
 * before client-side auth verification completes.
 */
export default function NoSSR({ children }: { children: ReactNode }) {
  const [hydrated, setHydrated] = useState(false);

  useEffect(() => {
    setHydrated(true);
  }, []);

  if (!hydrated) return null;

  return <>{children}</>;
}
