"use client";

import Link from "next/link";
import { useEffect, useMemo } from "react";
import { useRouter } from "next/navigation";
import { useTenantEmpresa } from "@/lib/auth/hooks";

function Card({ title, desc, href }: { title: string; desc: string; href: string }) {
  return (
    <Link
      href={href}
      className="block rounded-xl border border-zinc-800 bg-zinc-950 p-4 hover:bg-zinc-900/50 transition"
    >
      <div className="text-lg font-semibold text-zinc-100">{title}</div>
      <div className="mt-1 text-sm text-zinc-400">{desc}</div>
      <div className="mt-3 text-xs text-zinc-500">Abrir →</div>
    </Link>
  );
}

export default function FluxoCaixaIndexClient() {
  const te = useTenantEmpresa();
  const router = useRouter();

  const canFinanceiro = useMemo(() => {
    const r = te.has("financeiro.read");
    const w = te.has("financeiro.write");
    if (r === undefined || w === undefined) return undefined;
    return Boolean(r || w);
  }, [te]);

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  if (canFinanceiro !== true) return null;

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Fluxo de Caixa</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Previsto (agenda/vencimentos), Realizado (baixas/pagamentos) e Diário (comparativo).
          </p>
        </div>
        <Link
          href="/financeiro"
          className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
        >
          Voltar
        </Link>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <Card
          title="Previsto"
          desc="Planejamento de caixa por data (antes da baixa)."
          href="/financeiro/relatorios/fluxo-caixa/previsto"
        />
        <Card
          title="Realizado"
          desc="Caixa efetivo por data de movimentação/baixa."
          href="/financeiro/relatorios/fluxo-caixa/realizado"
        />
        <Card
          title="Diário"
          desc="Comparativo previsto vs realizado (por conta/motivo/fornecedor/OS)."
          href="/financeiro/relatorios/fluxo-caixa/diario"
        />
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 text-sm text-zinc-300">
        <div className="font-semibold text-zinc-100">Notas (Lucro Real)</div>
        <ul className="mt-2 list-disc list-inside space-y-1 text-zinc-300">
          <li>
            <span className="font-medium">Previsto</span> vem de títulos/parcelas/agendamentos (competência não é o
            extrato).
          </li>
          <li>
            <span className="font-medium">Realizado</span> vem de pagamentos/recebimentos (base caixa).
          </li>
          <li>
            O <span className="font-medium">Diário</span> ajuda a enxergar desvios (saldo do dia) e a rastrear
            classificações (motivo/OS/fornecedor) quando disponíveis.
          </li>
        </ul>
      </div>
    </div>
  );
}
