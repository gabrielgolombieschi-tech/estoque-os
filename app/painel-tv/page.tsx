"use client";

import Link from "next/link";
import { useEffect, useMemo } from "react";
import { useRouter } from "next/navigation";
import { useTenantEmpresa } from "@/lib/auth/hooks";

function normalizeRole(role: string | null | undefined) {
  return typeof role === "string" ? role.trim().toUpperCase() : "";
}

export default function PainelTvPage() {
  const te = useTenantEmpresa();
  const router = useRouter();

  const empresaRole = useMemo(() => normalizeRole(te.empresa?.papel), [te.empresa?.papel]);
  const isPainelTv = empresaRole === "PAINEL_TV";

  useEffect(() => {
    if (te.sessionUserId === undefined) return;
    if (!te.sessionUserId) return;
    if (!te.empresaId) return;
    if (te.empresa && !isPainelTv) router.replace("/");
  }, [isPainelTv, router, te.empresa, te.empresaId, te.sessionUserId]);

  return (
    <div className="min-h-[calc(100vh-0px)] bg-zinc-950 text-zinc-100">
      <div className="mx-auto max-w-6xl px-6 py-10">
        <div className="flex items-end justify-between gap-6">
          <div className="space-y-2">
            <div className="text-xs tracking-[0.18em] text-zinc-400 uppercase">
              Painel TV
            </div>
            <h1 className="text-4xl md:text-5xl font-semibold tracking-tight">
              Escolha a tela
            </h1>
            <p className="text-zinc-300 text-lg md:text-xl">
              Visualização para TV (kiosk) — somente leitura.
            </p>
          </div>

          {te.empresa && (
            <div className="hidden md:block text-right">
              <div className="text-xs text-zinc-400">Empresa</div>
              <div className="text-lg font-medium text-zinc-100">
                {te.empresa.nome_fantasia ?? te.empresa.razao_social ?? "Empresa"}
              </div>
            </div>
          )}
        </div>

        <div className="mt-10 grid grid-cols-1 md:grid-cols-2 gap-6">
          <BigCard
            title="Projetos"
            description="Status, prazos e progresso por área."
            href="/projetos"
          />
          <BigCard
            title="Execução"
            description="Acompanhe frentes elétrico e mecânico."
            href="/execucao"
          />
        </div>

        <div className="mt-10 text-sm text-zinc-500">
          {isPainelTv ? (
            <div>Conta configurada como PAINEL_TV.</div>
          ) : (
            <div className="text-red-400">
              Acesso restrito ao papel de empresa PAINEL_TV.
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function BigCard({
  title,
  description,
  href,
}: {
  title: string;
  description: string;
  href: string;
}) {
  return (
    <Link
      href={href}
      className="group rounded-2xl border border-zinc-800 bg-gradient-to-b from-zinc-900/40 to-zinc-950 p-8 shadow-sm hover:border-zinc-600 focus:outline-none focus:ring-2 focus:ring-zinc-500"
    >
      <div className="flex items-start justify-between gap-6">
        <div className="space-y-3">
          <div className="text-3xl md:text-4xl font-semibold tracking-tight">{title}</div>
          <div className="text-zinc-300 text-lg md:text-xl">{description}</div>
        </div>
        <div className="text-zinc-500 group-hover:text-zinc-200 transition-colors text-3xl md:text-4xl leading-none">
          →
        </div>
      </div>
      <div className="mt-8 h-1 w-24 rounded bg-zinc-800 group-hover:bg-zinc-600 transition-colors" />
    </Link>
  );
}

