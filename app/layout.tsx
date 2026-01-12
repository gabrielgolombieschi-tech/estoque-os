import "./globals.css";
import AppShell from "./components/AppShell";
import ClientProviders from "@/components/auth/ClientProviders";
import { EmpresaProvider } from "./components/EmpresaProvider";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR">
      <head>
        <meta charSet="utf-8" />
      </head>
      <body>
        <ClientProviders>
          <EmpresaProvider>
            <AppShell>{children}</AppShell>
          </EmpresaProvider>
        </ClientProviders>
      </body>
    </html>
  );
}
