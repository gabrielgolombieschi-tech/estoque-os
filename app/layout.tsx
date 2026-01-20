import "./globals.css";
import AppShell from "./components/AppShellClient";
import ClientProviders from "@/components/auth/ClientProviders";
import { headers } from "next/headers";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";
import { getCapabilities } from "@/lib/auth/capabilities.server";

export const dynamic = "force-dynamic";
const isDev = process.env.NODE_ENV !== "production";

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  // Try to read capabilities server-side to avoid client flicker. If anything fails,
  // fall back to null and let the client provider handle refresh.
  let initialCapabilities = null;
  let initialTenantId: string | null = null;
  try {
    const h = await headers();
    const authorization = h.get("authorization") ?? "";
    // In most Next.js App Router SSR requests, auth is in cookies (not in an Authorization header).
    // Only attempt server prefetch when an explicit bearer token exists.
    if (authorization) {
      const req = new Request("http://localhost", { headers: { authorization } });
      const supabase = supabaseFromAuthHeader(req);
      const capsRes = await getCapabilities(supabase);
      initialCapabilities = capsRes.capabilities;
      if (capsRes.tenantId) initialTenantId = capsRes.tenantId;
      // If tenant not present from getCapabilities, try reading it explicitly
      if (!initialTenantId) {
        try {
          const { data: tenantData, error: tenantErr } = await supabase.rpc("current_tenant_id");
          if (!tenantErr && tenantData) {
            initialTenantId = String(tenantData);
          }
        } catch (te) {
          if (isDev) console.debug("[layout] Could not load server tenantId:", te);
        }
      }
    }
  } catch (e) {
    if (isDev) console.debug("[layout] Could not load server capabilities:", e);
  }

  return (
    <html lang="pt-BR">
      <head>
        <meta charSet="utf-8" />
      </head>
      <body>
        <ClientProviders initialCapabilities={initialCapabilities} initialTenantId={initialTenantId}>
          <AppShell>{children}</AppShell>
        </ClientProviders>
      </body>
    </html>
  );
}
