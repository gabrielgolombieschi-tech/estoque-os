"use client";

import type { ReactNode } from "react";
import { PermissionsProvider } from "@/components/auth/PermissionsProvider";

export default function ClientProviders({ children }: { children: ReactNode }) {
  return <PermissionsProvider>{children}</PermissionsProvider>;
}
