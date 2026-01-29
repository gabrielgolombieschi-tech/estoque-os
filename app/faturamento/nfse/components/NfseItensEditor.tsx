"use client";

import { useMemo } from "react";
import { formatDecimalBR, formatMoneyBR, parseDecimalBR, parseMoneyBR } from "@/lib/decimal";

export type NfseServicoForm = {
  descricao: string;
  codigo_servico: string;
  quantidade: number;
  valor_unitario: number;
};

function round2(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

function round4(n: number): number {
  return Math.round((n + Number.EPSILON) * 10000) / 10000;
}

export default function NfseItensEditor({
  servico,
  onChange,
  readOnly,
}: {
  servico: NfseServicoForm;
  onChange: (next: NfseServicoForm) => void;
  readOnly?: boolean;
}) {
  const total = useMemo(
    () => round2((servico.quantidade || 0) * (servico.valor_unitario || 0)),
    [servico.quantidade, servico.valor_unitario]
  );

  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-950">
      <div className="px-4 py-3 border-b border-zinc-800">
        <div className="text-sm font-medium text-zinc-100">Itens</div>
        <div className="text-xs text-zinc-500">MVP: 1 linha de serviço + material (dedução) no card de ISS</div>
      </div>

      <div className="p-4 grid gap-3">
        <div className="grid gap-3 md:grid-cols-6">
          <div className="md:col-span-4">
            <label className="block text-xs font-medium text-zinc-400">Descrição do serviço</label>
            <input
              value={servico.descricao}
              disabled={readOnly}
              onChange={(e) => onChange({ ...servico, descricao: e.target.value })}
              placeholder="Ex.: Prestação de serviço"
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 placeholder:text-zinc-500 focus:outline-none focus:ring-2 focus:ring-zinc-700 disabled:opacity-60"
            />
          </div>

          <div className="md:col-span-2">
            <label className="block text-xs font-medium text-zinc-400">Código do serviço (opcional)</label>
            <input
              value={servico.codigo_servico}
              disabled={readOnly}
              onChange={(e) => onChange({ ...servico, codigo_servico: e.target.value })}
              placeholder="Ex.: 14.01"
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 placeholder:text-zinc-500 focus:outline-none focus:ring-2 focus:ring-zinc-700 disabled:opacity-60"
            />
          </div>
        </div>

        <div className="grid gap-3 md:grid-cols-6">
          <div className="md:col-span-2">
            <label className="block text-xs font-medium text-zinc-400">Quantidade</label>
            <input
              value={formatDecimalBR(round4(servico.quantidade || 0), 4)}
              disabled={readOnly}
              onChange={(e) => {
                const v = parseDecimalBR(e.target.value);
                onChange({ ...servico, quantidade: Number.isFinite(v) ? round4(v) : 0 });
              }}
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-700 disabled:opacity-60"
            />
          </div>

          <div className="md:col-span-2">
            <label className="block text-xs font-medium text-zinc-400">Valor unitário</label>
            <input
              value={formatMoneyBR(servico.valor_unitario || 0)}
              disabled={readOnly}
              onChange={(e) => {
                const v = parseMoneyBR(e.target.value);
                onChange({ ...servico, valor_unitario: Number.isFinite(v) ? round2(v) : 0 });
              }}
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-700 disabled:opacity-60"
            />
          </div>

          <div className="md:col-span-2">
            <label className="block text-xs font-medium text-zinc-400">Total</label>
            <input
              value={formatMoneyBR(total)}
              disabled
              className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 opacity-70"
            />
          </div>
        </div>
      </div>
    </div>
  );
}

