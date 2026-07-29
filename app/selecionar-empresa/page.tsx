"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useTenantEmpresaContext } from "@/lib/auth/TenantEmpresaProvider";

export default function SelecionarEmpresaPage() {
  const router = useRouter();
  const ctx = useTenantEmpresaContext();
  const empresas = ctx.empresas;
  const empresaId = ctx.empresaId;
  const setEmpresaId = ctx.setEmpresaId;
  const loading = ctx.loading || !ctx.tenantId;
  const error = ctx.error;
  const [switchingId, setSwitchingId] = useState<string | null>(null);

  useEffect(() => {
    if (!loading && empresaId && empresas.length === 1) {
      router.replace("/");
    }
  }, [loading, empresaId, empresas.length, router]);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando empresas...
      </div>
    );
  }

  if (empresas.length === 0) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        {error || "Sem acesso a empresas. Fale com o admin."}
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center px-4">
      <div className="w-full max-w-lg border border-zinc-800 rounded-xl bg-zinc-950 p-5 space-y-4">
        <div>
          <h1 className="text-xl font-semibold">Selecionar empresa</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Escolha a empresa para continuar.
          </p>
        </div>

        {error && (
          <div className="rounded-lg border border-red-900/70 bg-red-950/40 px-3 py-2 text-sm text-red-300">
            {error}
          </div>
        )}

        <div className="space-y-2">
          {empresas.map((empresa) => (
            <button
              key={empresa.id}
              onClick={async () => {
                if (switchingId) return;
                setSwitchingId(empresa.id);
                try {
                  await setEmpresaId(empresa.id);
                  router.replace("/");
                } catch {
                  // O provider mantem a empresa anterior e apresenta o erro.
                } finally {
                  setSwitchingId(null);
                }
              }}
              disabled={switchingId !== null}
              className="w-full text-left px-4 py-3 rounded-lg border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 disabled:cursor-wait disabled:opacity-60"
            >
              <div className="font-medium">
                {switchingId === empresa.id
                  ? "Confirmando empresa..."
                  : empresa.nome_fantasia ?? empresa.razao_social ?? empresa.id}
              </div>
              <div className="text-xs text-zinc-400">{empresa.id}</div>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
