"use server";

import { supabaseServer } from "../../lib/supabase/server";
import ProjetosDashboard from "../../components/projetos/ProjetosDashboard";

type DashRow = {
  os_id: number;
  item_tipo: "projeto";
  area: "eletrico" | "mecanico" | "seguranca" | "software";
  responsavel_id: string | null;
  data_prevista: string;
  progresso_percent: number;
  habilitado: boolean;
  numero_os: string;
  cliente_nome: string;
  descricao_servico: string | null;
};

export default async function ProjetosPage() {
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
        ordens_servico (id, numero_os, cliente_nome, descricao_servico)
      `
    )
    .eq("habilitado", true)
    .eq("item_tipo", "projeto");

  if (error) {
    throw new Error(error.message);
  }

  const rows: DashRow[] =
    (data ?? [])
      .map((row: any) => ({
        os_id: row.os_id,
        item_tipo: row.item_tipo,
        area: row.area,
        habilitado: !!row.habilitado,
        responsavel_id: row.responsavel_id,
        data_prevista: row.data_prevista,
        progresso_percent: Number(row.progresso_percent ?? 0),
        numero_os: row.ordens_servico?.numero_os ?? String(row.os_id),
        cliente_nome: row.ordens_servico?.cliente_nome ?? "-",
        descricao_servico: row.ordens_servico?.descricao_servico ?? null,
      }));

  return <ProjetosDashboard initialRows={rows} />;
}
