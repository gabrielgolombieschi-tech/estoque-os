"use client";

import { useContext, useEffect } from "react";
import { useRouter } from "next/navigation";
import { EmpresaContext } from "@/app/components/EmpresaProvider";

export default function SelecionarEmpresaPage() {
  const router = useRouter();
  const ctx = useContext(EmpresaContext);
  const empresas = ctx?.empresas ?? [];
  const empresaId = ctx?.empresaId ?? null;
  const setEmpresaId = ctx?.setEmpresaId ?? (() => {});
  const loading = ctx?.loading ?? false;
  const error = ctx?.error ?? null;

  useEffect(() => {
    if (!ctx) return;
    if (!loading && empresaId && empresas.length === 1) {
      router.replace("/");
    }
  }, [ctx, loading, empresaId, empresas.length, router]);

  if (!ctx) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        EmpresaProvider nao encontrado.
      </div>
    );
  }

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando empresas...
      </div>
    );
  }

  if (error || empresas.length === 0) {
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

        <div className="space-y-2">
          {empresas.map((empresa) => (
            <button
              key={empresa.id}
              onClick={() => {
                setEmpresaId(empresa.id);
                router.replace("/");
              }}
              className="w-full text-left px-4 py-3 rounded-lg border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
            >
              <div className="font-medium">{empresa.nome ?? empresa.id}</div>
              <div className="text-xs text-zinc-400">{empresa.id}</div>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
