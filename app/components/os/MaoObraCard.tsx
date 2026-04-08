"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { applyTenantEmpresa } from "@/lib/db/scopes";

type MaoObraData = {
  total_horas: number;
  custo_mao_obra: number;
  por_cargo: Array<{
    cargo: string;
    total_horas: number;
    custo_mao_obra: number;
  }>;
};

type ApontamentoBaseRow = {
  id: string;
  colaborador_id: string | null;
};

type ApontamentoCustoRow = {
  apontamento_id: string;
  colaborador_id: string | null;
  horas: number | null;
  custo_lancamento: number | null;
};

type ColaboradorCargoRow = {
  id: string;
  cargo: string | null;
};

export default function MaoObraCard({
  osId,
  effectiveTenantId,
  effectiveEmpresaId,
}: {
  osId: number;
  effectiveTenantId: string;
  effectiveEmpresaId: string;
}) {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const [loading, setLoading] = useState(false);
  const [dados, setDados] = useState<MaoObraData>({
    total_horas: 0,
    custo_mao_obra: 0,
    por_cargo: [],
  });
  const formatMoney = (v: number) =>
    Number(v || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const formatHours = (v: number) =>
    Number(v || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  const carregar = useCallback(async () => {
    if (!supabase || !effectiveTenantId || !effectiveEmpresaId || !Number.isFinite(osId)) {
      setDados({ total_horas: 0, custo_mao_obra: 0, por_cargo: [] });
      return;
    }

    setLoading(true);
    try {
      const apontamentosResult = await applyTenantEmpresa(
        supabase.from("apontamentos_horas").select("id,colaborador_id").eq("os_id", osId),
        effectiveTenantId,
        effectiveEmpresaId
      );

      if (apontamentosResult.error) throw apontamentosResult.error;

      const apontamentos = Array.isArray(apontamentosResult.data)
        ? (apontamentosResult.data as ApontamentoBaseRow[])
        : [];

      if (apontamentos.length === 0) {
        setDados({ total_horas: 0, custo_mao_obra: 0, por_cargo: [] });
        return;
      }

      const apontamentoIds = apontamentos.map((row) => String(row.id));
      const colaboradorIds = Array.from(
        new Set(apontamentos.map((row) => String(row.colaborador_id ?? "").trim()).filter(Boolean))
      );

      const [custosResult, colaboradoresResult] = await Promise.all([
        supabase
          .from("vw_apontamentos_horas_custo")
          .select("apontamento_id,colaborador_id,horas,custo_lancamento")
          .in("apontamento_id", apontamentoIds),
        colaboradorIds.length > 0
          ? applyTenantEmpresa(
              supabase.from("colaboradores").select("id,cargo").in("id", colaboradorIds),
              effectiveTenantId,
              effectiveEmpresaId
            )
          : Promise.resolve({ data: [], error: null }),
      ]);

      if (custosResult.error) throw custosResult.error;
      if (colaboradoresResult.error) throw colaboradoresResult.error;

      const custos = Array.isArray(custosResult.data) ? (custosResult.data as ApontamentoCustoRow[]) : [];
      const cargosByColaborador = new Map<string, string>();
      (Array.isArray(colaboradoresResult.data) ? (colaboradoresResult.data as ColaboradorCargoRow[]) : []).forEach(
        (row) => {
          cargosByColaborador.set(String(row.id), String(row.cargo ?? "").trim());
        }
      );

      const agrupado = new Map<string, { total_horas: number; custo_mao_obra: number }>();
      let totalHoras = 0;
      let custoMaoObra = 0;

      custos.forEach((row) => {
        const horas = Number(row.horas ?? 0) || 0;
        const custo = Number(row.custo_lancamento ?? 0) || 0;
        const cargoRaw = cargosByColaborador.get(String(row.colaborador_id ?? "").trim()) ?? "";
        const cargo = cargoRaw || "Sem cargo";
        const atual = agrupado.get(cargo) ?? { total_horas: 0, custo_mao_obra: 0 };

        atual.total_horas += horas;
        atual.custo_mao_obra += custo;
        agrupado.set(cargo, atual);

        totalHoras += horas;
        custoMaoObra += custo;
      });

      const porCargo = Array.from(agrupado.entries())
        .map(([cargo, resumo]) => ({
          cargo,
          total_horas: resumo.total_horas,
          custo_mao_obra: resumo.custo_mao_obra,
        }))
        .sort((a, b) => {
          if (b.custo_mao_obra !== a.custo_mao_obra) return b.custo_mao_obra - a.custo_mao_obra;
          return a.cargo.localeCompare(b.cargo, "pt-BR");
        });

      setDados({
        total_horas: totalHoras,
        custo_mao_obra: custoMaoObra,
        por_cargo: porCargo,
      });
    } catch (e) {
      console.error(e);
      setDados({ total_horas: 0, custo_mao_obra: 0, por_cargo: [] });
    } finally {
      setLoading(false);
    }
  }, [effectiveEmpresaId, effectiveTenantId, osId, supabase]);

  useEffect(() => {
    void carregar();
  }, [carregar]);

  return (
    <div style={{ marginTop: 12, border: "1px solid #333", borderRadius: 10, padding: 12 }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
        <div style={{ fontWeight: 700 }}>Mao de obra</div>
        <div className="flex items-center gap-2">
          <Link
            href={`/apontamentos?os=${osId}`}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm text-zinc-100"
          >
            Apontamentos
          </Link>
          <button
            onClick={carregar}
            disabled={loading}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm text-zinc-100 disabled:opacity-60"
          >
            {loading ? "Atualizando..." : "Atualizar"}
          </button>
        </div>
      </div>

      <div style={{ marginTop: 10, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
        <div style={{ border: "1px solid #222", borderRadius: 8, padding: 10 }}>
          <div style={{ opacity: 0.8 }}>Total de horas</div>
          <div style={{ fontSize: 18, fontWeight: 700 }}>
            {loading ? "..." : formatHours(dados.total_horas)}
          </div>
        </div>

        <div style={{ border: "1px solid #222", borderRadius: 8, padding: 10 }}>
          <div style={{ opacity: 0.8 }}>Custo mao de obra</div>
          <div style={{ fontSize: 18, fontWeight: 700 }}>
            {loading ? "..." : `R$ ${formatMoney(dados.custo_mao_obra)}`}
          </div>
        </div>
      </div>

      <div style={{ marginTop: 10, borderTop: "1px solid #222", paddingTop: 10 }}>
        <div className="mb-2 text-sm font-semibold text-zinc-100">Distribuicao por cargo</div>

        {loading ? (
          <div className="text-xs text-zinc-400">Carregando distribuicao...</div>
        ) : dados.por_cargo.length === 0 ? (
          <div className="text-xs text-zinc-400">Sem apontamentos com custo calculado para distribuir por cargo.</div>
        ) : (
          <div className="grid grid-cols-1 gap-2 md:grid-cols-2">
            {dados.por_cargo.map((row) => (
              <div
                key={row.cargo}
                className="rounded-md border border-zinc-800 bg-zinc-950/60 px-2.5 py-2"
              >
                <div className="grid grid-cols-[minmax(0,1fr)_auto_auto] items-center gap-x-2 text-xs leading-4">
                  <span className="min-w-0 break-words font-medium text-zinc-100">{row.cargo}</span>
                  <span className="whitespace-nowrap text-zinc-400 tabular-nums">{formatHours(row.total_horas)} h</span>
                  <span className="min-w-[104px] whitespace-nowrap text-right font-semibold text-zinc-100 tabular-nums">
                    R$ {formatMoney(row.custo_mao_obra)}
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      <div style={{ marginTop: 10, opacity: 0.85 }}>
        Dica: lance as horas em <b>/apontamentos</b> para refletir aqui.
      </div>
    </div>
  );
}
