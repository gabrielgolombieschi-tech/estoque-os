"use client";

import { useMemo } from "react";
import { formatDecimalBR, formatMoneyBR, parseDecimalBR, parseMoneyBR } from "@/lib/decimal";

function round2(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

function round4(n: number): number {
  return Math.round((n + Number.EPSILON) * 10000) / 10000;
}

export default function NfseIssCard({
  valorServicos,
  materialPercent,
  materialValor,
  aliquota,
  onAliquotaChange,
  onMaterialPercentChange,
  onMaterialValorChange,
  readOnly,
}: {
  valorServicos: number;
  materialPercent: number;
  materialValor: number;
  aliquota: number;
  onAliquotaChange: (n: number) => void;
  onMaterialPercentChange: (n: number) => void;
  onMaterialValorChange: (n: number) => void;
  readOnly?: boolean;
}) {
  const baseOriginal = useMemo(() => round2(valorServicos || 0), [valorServicos]);
  const deducoes = useMemo(() => Math.min(round2(materialValor || 0), baseOriginal), [baseOriginal, materialValor]);
  const baseCalculo = useMemo(() => round2(Math.max(0, baseOriginal - deducoes)), [baseOriginal, deducoes]);
  const valorIss = useMemo(() => round2((baseCalculo * (aliquota || 0)) / 100), [aliquota, baseCalculo]);

  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-950">
      <div className="px-4 py-3 border-b border-zinc-800">
        <div className="text-sm font-medium text-zinc-100">ISS</div>
        <div className="text-xs text-zinc-500">Imposto: ISS (natureza: RETENÇÃO)</div>
      </div>

      <div className="p-4 grid gap-3 md:grid-cols-3">
        <div>
          <label className="block text-xs font-medium text-zinc-400">Alíquota (%)</label>
          <input
            value={formatDecimalBR(round4(aliquota || 0), 4)}
            disabled={readOnly}
            onChange={(e) => {
              const v = parseDecimalBR(e.target.value);
              onAliquotaChange(Number.isFinite(v) ? round4(v) : 0);
            }}
            className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-700 disabled:opacity-60"
          />
        </div>

        <div>
          <label className="block text-xs font-medium text-zinc-400">Material (dedução) %</label>
          <input
            value={formatDecimalBR(round4(materialPercent || 0), 4)}
            disabled={readOnly || baseOriginal <= 0}
            onChange={(e) => {
              const v = parseDecimalBR(e.target.value);
              onMaterialPercentChange(Number.isFinite(v) ? round4(v) : 0);
            }}
            className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-700 disabled:opacity-60"
          />
        </div>

        <div>
          <label className="block text-xs font-medium text-zinc-400">Material (dedução) valor</label>
          <input
            value={formatMoneyBR(materialValor || 0)}
            disabled={readOnly}
            onChange={(e) => {
              const v = parseMoneyBR(e.target.value);
              onMaterialValorChange(Number.isFinite(v) ? round2(v) : 0);
            }}
            className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-700 disabled:opacity-60"
          />
        </div>
      </div>

      <div className="px-4 pb-4 grid gap-3 md:grid-cols-4">
        <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
          <div className="text-xs text-zinc-500">Base original</div>
          <div className="mt-1 text-sm font-medium text-zinc-100 tabular-nums">{formatMoneyBR(baseOriginal)}</div>
        </div>
        <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
          <div className="text-xs text-zinc-500">Deduções</div>
          <div className="mt-1 text-sm font-medium text-zinc-100 tabular-nums">{formatMoneyBR(deducoes)}</div>
        </div>
        <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
          <div className="text-xs text-zinc-500">Base cálculo</div>
          <div className="mt-1 text-sm font-medium text-zinc-100 tabular-nums">{formatMoneyBR(baseCalculo)}</div>
        </div>
        <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3">
          <div className="text-xs text-zinc-500">ISS calculado</div>
          <div className="mt-1 text-sm font-medium text-zinc-100 tabular-nums">{formatMoneyBR(valorIss)}</div>
        </div>
      </div>
    </div>
  );
}

