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

type OsGestaoRow = {
  os_id: number;
  item_tipo: "execucao";
  area: DashRow["area"];
  habilitado: boolean | null;
  responsavel_id: string | null;
  data_prevista: string;
  progresso_percent: number | null;
  ordens_servico?: {
    numero_os?: string | null;
    cliente_nome?: string | null;
    descricao_servico?: string | null;
    status?: DashRow["status"] | null;
  } | null;
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
    console.error("Erro ao carregar execucao:", error.message);
  }

  const rows: DashRow[] = ((data ?? []) as OsGestaoRow[])
    .map((row) => ({
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
      status: row.ordens_servico?.status ?? null,
    }))
    .filter((r) => !!r.data_prevista && (r.area === "eletrico" || r.area === "mecanico"));

  return <ExecucaoDashboard initialRows={rows} />;
}
