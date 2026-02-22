"use client";

import { useEffect, useMemo, useState } from "react";
import type { EntradasNoPeriodoFilters, EntradasToggleOs, FornecedorOption } from "@/lib/queries/estoque-relatorios";

type Props = {
  fornecedores: FornecedorOption[];
  applied: EntradasNoPeriodoFilters;
  onApply: (next: EntradasNoPeriodoFilters) => void;
  onClear: () => void;
};

export default function EntradasNoPeriodoFiltersPanel({ fornecedores, applied, onApply, onClear }: Props) {
  const [dataIni, setDataIni] = useState(applied.dataIni);
  const [dataFim, setDataFim] = useState(applied.dataFim);
  const [fornecedorPrefix, setFornecedorPrefix] = useState(applied.fornecedorPrefix);
  const [buscaItem, setBuscaItem] = useState(applied.buscaItem);
  const [osMode, setOsMode] = useState<EntradasToggleOs>(applied.osMode);
  const [comNf, setComNf] = useState(applied.comNf);
  const [destacarSaldoAlto, setDestacarSaldoAlto] = useState(applied.destacarSaldoAlto);

  useEffect(() => {
    setDataIni(applied.dataIni);
    setDataFim(applied.dataFim);
    setFornecedorPrefix(applied.fornecedorPrefix);
    setBuscaItem(applied.buscaItem);
    setOsMode(applied.osMode);
    setComNf(applied.comNf);
    setDestacarSaldoAlto(applied.destacarSaldoAlto);
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
      dataIni,
      dataFim,
      fornecedorPrefix,
      fornecedorIds: [],
      buscaItem,
      osMode,
      comNf,
      destacarSaldoAlto,
    });
  };

  return (
    <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
      <div className="grid grid-cols-1 md:grid-cols-8 gap-3">
        <div className="space-y-1">
          <div className="text-xs text-zinc-400">Data início</div>
          <input
            type="date"
            className="w-full px-3 py-2"
            value={dataIni}
            onChange={(e) => setDataIni(e.target.value)}
            aria-label="Data início"
          />
        </div>

        <div className="space-y-1">
          <div className="text-xs text-zinc-400">Data fim</div>
          <input
            type="date"
            className="w-full px-3 py-2"
            value={dataFim}
            onChange={(e) => setDataFim(e.target.value)}
            aria-label="Data fim"
          />
        </div>

        <div className="md:col-span-2 space-y-1">
          <div className="text-xs text-zinc-400">Fornecedor</div>
          <input
            className="w-full px-3 py-2"
            value={fornecedorPrefix}
            onChange={(e) => setFornecedorPrefix(e.target.value)}
            placeholder="Digite o início do nome (ex.: Siem)"
            aria-label="Filtrar fornecedor por prefixo"
          />
          <div className="text-[11px] text-zinc-500">
            {fornecedorPrefix.trim()
              ? previewMatches.length
                ? `Ex.: ${previewMatches.join(", ")}${previewMatches.length >= 5 ? "…" : ""}`
                : "Nenhum fornecedor começa com esse texto."
              : "Digite para filtrar por nome começando com o texto."}
          </div>
        </div>

        <div className="md:col-span-2 space-y-1">
          <div className="text-xs text-zinc-400">Busca item</div>
          <input
            className="w-full px-3 py-2"
            value={buscaItem}
            onChange={(e) => setBuscaItem(e.target.value)}
            placeholder="Código ou nome do item"
            aria-label="Buscar item"
          />
        </div>

        <div className="md:col-span-2 space-y-1">
          <div className="flex items-end gap-2">
            <div className="flex-1 space-y-1">
              <div className="text-xs text-zinc-400">OS</div>
              <select
                className="w-full px-3 py-2"
                value={osMode}
                onChange={(e) => setOsMode(e.target.value as EntradasToggleOs)}
                aria-label="Filtro de OS"
              >
                <option value="todos">Todos</option>
                <option value="com_os">Somente com OS</option>
                <option value="sem_os">Somente sem OS</option>
              </select>
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

          <label className="flex items-center gap-2 text-sm text-zinc-300 select-none mt-3">
            <input type="checkbox" checked={comNf} onChange={(e) => setComNf(e.target.checked)} />
            Com NF
          </label>
          <label className="flex items-center gap-2 text-sm text-zinc-300 select-none mt-2">
            <input
              type="checkbox"
              checked={destacarSaldoAlto}
              onChange={(e) => setDestacarSaldoAlto(e.target.checked)}
            />
            Destacar saldo alto
          </label>
        </div>
      </div>
    </div>
  );
}
