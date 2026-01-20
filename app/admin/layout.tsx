"use client";

import type { ReactNode } from "react";
import RequireCap from "@/components/auth/RequireCap";

export default function AdminLayout({ children }: { children: ReactNode }) {
  return (
    <RequireCap cap={["admin.manage_users", "admin.users.manage"]} requireAdminTenant>
      {children}
    </RequireCap>
  );
}
