"use client";

import { useEffect, useMemo, useState } from "react";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { supabaseBrowser } from "@/lib/supabase/client";
import ExecucaoDashboard from "../../components/execucao/ExecucaoDashboard";

type DashRow = {
  os_id: number;
  item_tipo: "execucao";
  area: "eletrico" | "mecanico";
  habilitado: boolean;
  data_prevista: string | null;
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
  data_prevista: string | null;
  progresso_percent: number | null;
};

export default function ExecucaoPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { tenantId, empresaId } = useTenantEmpresa();
  const fixedTenantId = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
  const effectiveTenantId = useMemo(() => tenantId ?? fixedTenantId, [tenantId]);
  const [rows, setRows] = useState<DashRow[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (tenantId && !empresaId) return;

    let active = true;

    (async () => {
      setLoading(true);
      setErr(null);

      const { error: tenantErr } = await supabase.rpc("set_current_tenant", {
        p_tenant_id: effectiveTenantId,
      });
      if (tenantErr) {
        if (active) {
          setErr(tenantErr.message ?? "Erro ao definir tenant atual.");
          setRows([]);
          setLoading(false);
        }
        return;
      }

      if (empresaId) {
        const { error: empresaErr } = await supabase.rpc("set_current_empresa", {
          p_empresa_id: empresaId,
        });

        if (empresaErr) {
          console.error("Erro ao definir empresa atual:", empresaErr.message ?? empresaErr);
        }
      }

      const { data, error } = await applyTenantEmpresa(
        supabase.from("os_gestao_itens").select(
          `
            os_id,
            item_tipo,
            area,
            habilitado,
            data_prevista,
            progresso_percent
          `
        ),
        effectiveTenantId,
        empresaId ?? ""
      )
        .eq("habilitado", true)
        .eq("item_tipo", "execucao");

      if (!active) return;

      if (error) {
        console.error("Erro ao carregar execucao:", error.message ?? error);
        setErr(error.message);
        setRows([]);
        setLoading(false);
        return;
      }

      const gestaoRows = (data ?? []) as OsGestaoRow[];
      const osIds = Array.from(new Set(gestaoRows.map((row) => row.os_id)));
      const osMap = new Map<
        number,
        {
          numero_os?: string | null;
          cliente_nome?: string | null;
          descricao_servico?: string | null;
          status?: DashRow["status"] | null;
        }
      >();

      if (osIds.length > 0) {
        const { data: osData, error: osErr } = await applyTenantEmpresa(
          supabase
            .from("ordens_servico")
            .select("id,numero_os,cliente_nome,descricao_servico,status")
            .eq("tipo_documento", "OS"),
          effectiveTenantId,
          empresaId ?? ""
        ).in("id", osIds);

        if (osErr) {
          console.error("Erro ao carregar ordens_servico:", osErr.message ?? osErr);
          setErr(osErr.message);
          setRows([]);
          setLoading(false);
          return;
        }

        (osData ?? []).forEach((os) => {
          osMap.set(os.id, {
            numero_os: os.numero_os,
            cliente_nome: os.cliente_nome,
            descricao_servico: os.descricao_servico,
            status: os.status,
          });
        });
      }

      const mapped: DashRow[] = gestaoRows
        .map((row) => ({
          os_id: row.os_id,
          item_tipo: "execucao" as const,
          area: row.area,
          habilitado: Boolean(row.habilitado),
          data_prevista: row.data_prevista,
          progresso_percent: Number(row.progresso_percent ?? 0),
          numero_os: osMap.get(row.os_id)?.numero_os ?? String(row.os_id),
          cliente_nome: osMap.get(row.os_id)?.cliente_nome ?? "-",
          descricao_servico: osMap.get(row.os_id)?.descricao_servico ?? null,
          status: osMap.get(row.os_id)?.status ?? null,
        }))
        .filter((row) => row.area === "eletrico" || row.area === "mecanico");

      setRows(mapped);
      setLoading(false);
    })();

    return () => {
      active = false;
    };
  }, [supabase, tenantId, empresaId, effectiveTenantId]);

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

  return <ExecucaoDashboard initialRows={rows} emptyMessage="Nenhuma execucao habilitada encontrada." />;
}
