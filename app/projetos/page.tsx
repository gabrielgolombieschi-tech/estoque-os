"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
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
  status: "aberta" | "em_andamento" | "concluida" | "cancelada" | null;
};

type OsGestaoRow = {
  os_id: number;
  item_tipo: "projeto";
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

export default function ProjetosPage() {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const { tenantId, loading: tenantLoading } = useTenantEmpresa();
  const [rows, setRows] = useState<DashRow[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;

    (async () => {
      if (tenantLoading) return;
      if (!tenantId) {
        if (active) {
          setErr("Tenant nao carregado.");
          setLoading(false);
        }
        return;
      }

      setLoading(true);
      setErr(null);

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
        .eq("item_tipo", "projeto");

      if (!active) return;

      if (error) {
        setErr(error.message);
        setRows([]);
        setLoading(false);
        return;
      }

      const mapped: DashRow[] = ((data ?? []) as OsGestaoRow[]).map((row) => ({
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
        status: row.ordens_servico?.status ?? null,
      }));

      setRows(mapped);
      setLoading(false);
    })();

    return () => {
      active = false;
    };
  }, [supabase, tenantId, tenantLoading]);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando...
      </div>
    );
  }

  if (err) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        {err}
      </div>
    );
  }

  return <ProjetosDashboard initialRows={rows} />;
}
