"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

type MaoObraData = {
  total_horas: number;
  custo_mao_obra: number;
};

export default function MaoObraCard({ osId }: { osId: number }) {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const [loading, setLoading] = useState(false);
  const [dados, setDados] = useState<MaoObraData>({
    total_horas: 0,
    custo_mao_obra: 0,
  });
  const formatMoney = (v: number) =>
    Number(v || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  async function carregar() {
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from("vw_custo_mao_obra_os")
        .select("total_horas,custo_mao_obra")
        .eq("os_id", osId)
        .maybeSingle();

      if (error) throw error;

      setDados({
        total_horas: Number(data?.total_horas ?? 0),
        custo_mao_obra: Number(data?.custo_mao_obra ?? 0),
      });
    } catch (e) {
      console.error(e);
      setDados({ total_horas: 0, custo_mao_obra: 0 });
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (Number.isFinite(osId)) carregar();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [osId]);

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
            {loading ? "..." : dados.total_horas.toFixed(2)}
          </div>
        </div>

        <div style={{ border: "1px solid #222", borderRadius: 8, padding: 10 }}>
          <div style={{ opacity: 0.8 }}>Custo mao de obra</div>
          <div style={{ fontSize: 18, fontWeight: 700 }}>
            {loading ? "..." : `R$ ${formatMoney(dados.custo_mao_obra)}`}
          </div>
        </div>
      </div>

      <div style={{ marginTop: 10, opacity: 0.85 }}>
        Dica: lance as horas em <b>/apontamentos</b> para refletir aqui.
      </div>
    </div>
  );
}
