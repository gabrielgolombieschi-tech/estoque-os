import type { ReactNode } from "react";
import { PermissionsProvider } from "@/components/auth/PermissionsProvider";

export default function ImportarLayout({ children }: { children: ReactNode }) {
  return <PermissionsProvider>{children}</PermissionsProvider>;
}
