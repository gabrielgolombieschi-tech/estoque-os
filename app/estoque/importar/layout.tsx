import type { ReactNode } from "react";
import { PermissionsProvider } from "@/components/auth/PermissionsProvider";
import { ImportMotivosProvider } from "./ImportMotivosProvider";

export default function ImportarLayout({ children }: { children: ReactNode }) {
  return (
    <PermissionsProvider>
      <ImportMotivosProvider>{children}</ImportMotivosProvider>
    </PermissionsProvider>
  );
}
