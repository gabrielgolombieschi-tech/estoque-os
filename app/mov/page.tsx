"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "../../lib/supabase/client";
import { formatDecimalBR } from "../../lib/decimal";

type MovTipo = "entrada" | "saida" | "ajuste";

type MovRow = {
  id: number;
  item_id: number;
  tipo: MovTipo;
  quantidade: number;
  motivo: string | null;
  realizado_por: string | null;
  data_movimentacao: string;
  itens: {
    codigo_interno: string;
    nome: string;
    unidade_medida: string | null;
  } | null;
};

const tipoBadge: Record<MovTipo, string> = {
  entrada: "bg-emerald-500/15 text-emerald-300 border border-emerald-500/30",
  saida: "bg-red-500/15 text-red-300 border border-red-500/30",
  ajuste: "bg-amber-500/15 text-amber-300 border border-amber-500/30",
};

export default function MovimentacoesPage() {
  const supabase = useMemo(() => supabaseBrowser(), []);

  const [rows, setRows] = useState<MovRow[]>([]);
  const [err, setErr] = useState<string | null>(null);

  // filtros
  const [q, setQ] = useState("");
  const [tipo, setTipo] = useState<"todos" | MovTipo>("todos");

  async function load() {
    setErr(null);

    const { data, error } = await supabase
      .from("movimentacoes")
      .select(
        "id,item_id,tipo,quantidade,motivo,realizado_por,data_movimentacao,itens(codigo_interno,nome,unidade_medida)"
      )
      .order("id", { ascending: false })
      .limit(500);

    if (error) return setErr(error.message);

    let list = (data ?? []) as unknown as MovRow[];

    const term = q.trim().toLowerCase();
    if (term) {
      list = list.filter((r) => {
        const cod = (r.itens?.codigo_interno ?? "").toLowerCase();
        const nome = (r.itens?.nome ?? "").toLowerCase();
        const mot = (r.motivo ?? "").toLowerCase();
        return cod.includes(term) || nome.includes(term) || mot.includes(term);
      });
    }

    if (tipo !== "todos") list = list.filter((r) => r.tipo === tipo);

    setRows(list);
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tipo]);

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Movimentações</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Histórico completo de entradas, saídas e ajustes.
          </p>
        </div>

        <button
          onClick={load}
          className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
        >
          Atualizar
        </button>
      </div>

      {/* Filtros */}
      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="grid grid-cols-1 md:grid-cols-5 gap-3">
          <div className="md:col-span-3 space-y-1">
            <div className="text-xs text-zinc-400">Buscar</div>
            <input
              className="w-full px-3 py-2"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Código, nome ou motivo"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Tipo</div>
            <select
              className="w-full px-3 py-2"
              value={tipo}
              onChange={(e) => setTipo(e.target.value as "todos" | MovTipo)}
            >
              <option value="todos">Todos</option>
              <option value="entrada">Entrada</option>
              <option value="saida">Saída</option>
              <option value="ajuste">Ajuste</option>
            </select>
          </div>

          <div className="flex items-end">
            <button
              onClick={load}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 w-full"
            >
              Aplicar
            </button>
          </div>
        </div>

        {err && <div className="text-sm text-red-400 mt-3">{err}</div>}
      </div>

      {/* Tabela */}
      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-4 py-3 text-left">Data</th>
              <th className="px-4 py-3 text-left">Item</th>
              <th className="px-4 py-3 text-center">Tipo</th>
              <th className="px-4 py-3 text-right">Qtd</th>
              <th className="px-4 py-3 text-left">Motivo</th>
              <th className="px-4 py-3 text-left">Usuário</th>
            </tr>
          </thead>

          <tbody className="divide-y divide-zinc-800">
            {rows.map((r) => (
              <tr key={r.id} className="hover:bg-zinc-900/40">
                <td className="px-4 py-3 text-zinc-300">
                  {new Date(r.data_movimentacao).toLocaleString("pt-BR")}
                </td>

                <td className="px-4 py-3">
                  {r.itens ? (
                    <>
                      <div className="font-medium">
                        [{r.itens.codigo_interno}] {r.itens.nome}
                      </div>
                      <div className="text-xs text-zinc-400">
                        {r.itens.unidade_medida ?? "UN"}
                      </div>
                    </>
                  ) : (
                    <span className="text-zinc-400">Item {r.item_id}</span>
                  )}
                </td>

                <td className="px-4 py-3 text-center">
                  <span className={`inline-flex items-center px-2 py-1 rounded-md text-xs ${tipoBadge[r.tipo]}`}>
                    {r.tipo}
                  </span>
                </td>

                <td className="px-4 py-3 text-right tabular-nums">
                  {r.tipo === "saida" ? "-" : "+"}
                  {formatDecimalBR(Number(r.quantidade ?? 0), 3)}
                </td>

                <td className="px-4 py-3 text-zinc-300">
                  {r.motivo ?? "—"}
                </td>

                <td className="px-4 py-3 text-zinc-400">
                  {r.realizado_por ?? "—"}
                </td>
              </tr>
            ))}

            {rows.length === 0 && (
              <tr>
                <td colSpan={6} className="px-4 py-6 text-zinc-400">
                  Nenhuma movimentação encontrada.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
