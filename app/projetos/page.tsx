"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenant } from "@/lib/db/scopes";
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

      const { error: tenantErr } = await supabase.rpc("set_current_tenant", {
        p_tenant_id: tenantId,
      });

      if (tenantErr) {
        console.error("Erro ao definir tenant atual:", tenantErr.message ?? tenantErr);
        setErr(tenantErr.message ?? "Erro ao definir tenant atual.");
        setRows([]);
        setLoading(false);
        return;
      }

      const { data: dbgData, error: dbgErr } = await supabase.rpc("debug_tenant");
      console.log("[projetos] tenant debug:", { tenantId, dbgData, dbgErr });

      const { data, error } = await applyTenant(
        supabase.from("os_gestao_itens").select(
          `
            os_id,
            item_tipo,
            area,
            habilitado,
            responsavel_id,
            data_prevista,
            progresso_percent
          `
        ),
        tenantId
      )
        .eq("habilitado", true)
        .eq("item_tipo", "projeto");

      if (!active) return;

      console.log("[projetos] rows:", data?.length ?? 0, "error:", error);

      if (error) {
        console.error("Erro ao carregar os_gestao_itens:", error.message ?? error);
        setErr(error.message);
        setRows([]);
        setLoading(false);
        return;
      }

      const gestaoRows = (data ?? []) as OsGestaoRow[];

      const osIds = Array.from(new Set(gestaoRows.map((row) => row.os_id)));
      const osMap = new Map<number, { numero_os?: string | null; cliente_nome?: string | null; descricao_servico?: string | null; status?: DashRow["status"] | null }>();

      if (osIds.length > 0) {
        const { data: osData, error: osErr } = await applyTenant(
          supabase.from("ordens_servico").select("id,numero_os,cliente_nome,descricao_servico,status"),
          tenantId
        )
          .in("id", osIds);

        if (osErr) {
          console.error("Erro ao carregar ordens_servico:", osErr.message ?? osErr);
          setErr(osErr.message);
          setRows([]);
          setLoading(false);
          return;
        } else {
          (osData ?? []).forEach((os) => {
            osMap.set(os.id, {
              numero_os: os.numero_os,
              cliente_nome: os.cliente_nome,
              descricao_servico: os.descricao_servico,
              status: os.status,
            });
          });
        }
      }

      const mapped: DashRow[] = gestaoRows.map((row) => ({
        os_id: row.os_id,
        item_tipo: row.item_tipo,
        area: row.area,
        habilitado: !!row.habilitado,
        responsavel_id: row.responsavel_id,
        data_prevista: row.data_prevista,
        progresso_percent: Number(row.progresso_percent ?? 0),
        numero_os: osMap.get(row.os_id)?.numero_os ?? String(row.os_id),
        cliente_nome: osMap.get(row.os_id)?.cliente_nome ?? "-",
        descricao_servico: osMap.get(row.os_id)?.descricao_servico ?? null,
        status: osMap.get(row.os_id)?.status ?? null,
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
    return <div className="p-6 text-sm text-red-400">{err}</div>;
  }

  return <ProjetosDashboard initialRows={rows} emptyMessage="Nenhum projeto habilitado encontrado." />;
}
