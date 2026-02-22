"use client";

import { useEffect, useMemo, useState } from "react";
import type { FornecedorOption, SaldoEmEstoqueFilters, SaldoFinalidade } from "@/lib/queries/estoque-relatorios";

type Props = {
  fornecedores: FornecedorOption[];
  applied: SaldoEmEstoqueFilters;
  onApply: (next: SaldoEmEstoqueFilters) => void;
  onClear: () => void;
};

const FINALIDADES: Array<{ value: SaldoFinalidade; label: string }> = [
  { value: "materia_prima", label: "Materia-prima" },
  { value: "consumo", label: "Consumo" },
  { value: "revenda", label: "Revenda" },
  { value: "imobilizado", label: "Imobilizado" },
  { value: "outros", label: "Outros" },
];

export default function SaldoEmEstoqueFiltersPanel({ fornecedores, applied, onApply, onClear }: Props) {
  const [fornecedorPrefix, setFornecedorPrefix] = useState(applied.fornecedorPrefix);
  const [busca, setBusca] = useState(applied.busca);
  const [finalidade, setFinalidade] = useState<SaldoFinalidade>(applied.finalidade);
  const [abaixoMinimo, setAbaixoMinimo] = useState(applied.abaixoMinimo);
  const [separarPorFornecedor, setSepararPorFornecedor] = useState(applied.separarPorFornecedor);
  const [semFornecedor, setSemFornecedor] = useState(applied.semFornecedor);

  useEffect(() => {
    setFornecedorPrefix(applied.fornecedorPrefix);
    setBusca(applied.busca);
    setFinalidade(applied.finalidade);
    setAbaixoMinimo(applied.abaixoMinimo);
    setSepararPorFornecedor(applied.separarPorFornecedor);
    setSemFornecedor(applied.semFornecedor);
  }, [applied]);

  const previewMatches = useMemo(() => {
    const pref = fornecedorPrefix
      .trim()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase();
    if (!pref) return [];
    return fornecedores
      .filter((f) => {
        const nome = String(f.nome ?? "")
          .normalize("NFD")
          .replace(/[\u0300-\u036f]/g, "")
          .toLowerCase();
        return nome.startsWith(pref);
      })
      .slice(0, 5)
      .map((f) => f.nome);
  }, [fornecedorPrefix, fornecedores]);

  const applyNow = () => {
    onApply({
      fornecedorPrefix,
      fornecedorIds: [],
      semFornecedor,
      busca,
      finalidade,
      abaixoMinimo,
      separarPorFornecedor,
      localizacao: "",
    });
  };

  return (
    <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
      <div className="grid grid-cols-1 md:grid-cols-6 gap-3">
        <div className="md:col-span-2 space-y-1">
          <div className="text-xs text-zinc-400">Fornecedor</div>
          <input
            className="w-full px-3 py-2"
            value={fornecedorPrefix}
            onChange={(e) => setFornecedorPrefix(e.target.value)}
            placeholder="Digite o inicio do nome (ex.: Siem)"
            aria-label="Filtrar fornecedor por prefixo"
          />
          <label className="flex items-center gap-2 text-sm text-zinc-300 select-none mt-2">
            <input
              type="checkbox"
              checked={semFornecedor}
              onChange={(e) => setSemFornecedor(e.target.checked)}
            />
            SEM FORNECEDOR
          </label>
          <div className="text-[11px] text-zinc-500">
            {fornecedorPrefix.trim()
              ? previewMatches.length
                ? `Ex.: ${previewMatches.join(", ")}${previewMatches.length >= 5 ? "..." : ""}`
                : "Nenhum fornecedor comeca com esse texto."
              : "Digite para filtrar por nome comecando com o texto."}
          </div>
        </div>

        <div className="md:col-span-2 space-y-1">
          <div className="text-xs text-zinc-400">Busca</div>
          <input
            className="w-full px-3 py-2"
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
            placeholder="Codigo ou nome do item"
            aria-label="Buscar item"
          />
        </div>

        <div className="space-y-1">
          <div className="text-xs text-zinc-400">Finalidade</div>
          <select
            className="w-full px-3 py-2"
            value={finalidade}
            onChange={(e) => setFinalidade(e.target.value as SaldoFinalidade)}
            aria-label="Finalidade"
          >
            <option value="todas">Todas</option>
            {FINALIDADES.map((f) => (
              <option key={String(f.value)} value={f.value}>
                {f.label}
              </option>
            ))}
          </select>

          <label className="flex items-center gap-2 text-sm text-zinc-300 select-none mt-3">
            <input
              type="checkbox"
              checked={abaixoMinimo}
              onChange={(e) => setAbaixoMinimo(e.target.checked)}
            />
            Abaixo do minimo
          </label>

          <label className="flex items-center gap-2 text-sm text-zinc-300 select-none mt-2">
            <input
              type="checkbox"
              checked={separarPorFornecedor}
              onChange={(e) => setSepararPorFornecedor(e.target.checked)}
            />
            Separar por fornecedor
          </label>
        </div>

        <div className="flex items-end justify-end gap-2">
          <button
            type="button"
            onClick={applyNow}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Aplicar
          </button>
          <button
            type="button"
            onClick={onClear}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-transparent hover:bg-zinc-900 text-zinc-200"
          >
            Limpar
          </button>
        </div>
      </div>
    </div>
  );
}
