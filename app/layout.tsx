import "./globals.css";
import AppShell from "./components/AppShell";
import ClientProviders from "@/components/auth/ClientProviders";
import { headers } from "next/headers";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";
import { getCapabilities } from "@/lib/auth/capabilities.server";

export const dynamic = "force-dynamic";

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  // Try to read capabilities server-side to avoid client flicker. If anything fails,
  // fall back to null and let the client provider handle refresh.
  let initialCapabilities = null;
  let initialTenantId: string | null = null;
  try {
    const h = await headers();
    const authorization = h.get("authorization") ?? "";
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
        // ignore tenant read error; client will resolve later
        console.warn("Could not load server tenantId:", te);
      }
    }
  } catch (e) {
    // ignore server-side capability errors; client will fetch later
    console.warn("Could not load server capabilities:", e);
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
