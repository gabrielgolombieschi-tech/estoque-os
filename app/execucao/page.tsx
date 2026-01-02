"use server";

import { supabaseServer } from "../../lib/supabase/server";
import ExecucaoDashboard from "../../components/execucao/ExecucaoDashboard";

type DashRow = {
  os_id: number;
  item_tipo: "execucao";
  area: "eletrico" | "mecanico";
  habilitado: boolean;
  responsavel_id: string | null;
  data_prevista: string;
  progresso_percent: number;
  numero_os: string;
  cliente_nome: string;
  descricao_servico: string | null;
  status: "aberta" | "em_andamento" | "concluida" | "cancelada" | null;
};

export default async function ExecucaoPage() {
  const supabase = supabaseServer();

  const { data, error } = await supabase
    .from("os_gestao_itens")
    .select(
      `
        os_id,
        item_tipo,
        area,
        habilitado,
        responsavel_id,
        data_prevista,
        progresso_percent,
        ordens_servico (id, numero_os, cliente_nome, descricao_servico, status)
      `
    )
    .eq("habilitado", true)
    .eq("item_tipo", "execucao");

  if (error) {
    throw new Error(error.message);
  }

  const rows: DashRow[] =
    (data ?? [])
      .map((row: any) => ({
        os_id: row.os_id,
        item_tipo: "execucao" as const,
        area: row.area,
        habilitado: !!row.habilitado,
        responsavel_id: row.responsavel_id,
        data_prevista: row.data_prevista,
        progresso_percent: Number(row.progresso_percent ?? 0),
        numero_os: row.ordens_servico?.numero_os ?? String(row.os_id),
        cliente_nome: row.ordens_servico?.cliente_nome ?? "-",
        descricao_servico: row.ordens_servico?.descricao_servico ?? null,
        status: (row.ordens_servico?.status as any) ?? null,
      }))
      .filter((r) => !!r.data_prevista && (r.area === "eletrico" || r.area === "mecanico"));

  return <ExecucaoDashboard initialRows={rows} />;
}
