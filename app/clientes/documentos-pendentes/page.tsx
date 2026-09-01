"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { applyTenantEmpresa } from "@/lib/db/scopes";

type Row = { cliente_id: number; cliente_nome: string; documento: string | null; documento_norm: string | null; pendencia: "SEM_DOCUMENTO" | "CNPJ_INVALIDO" };

export default function DocumentosPendentesPage() {
  const te = useTenantEmpresa();
  const supabase = useMemo(() => getSupabaseBrowser(), []);
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const tenantId = te.tenantId;
  const empresaId = te.empresaId;

  const load = useCallback(async () => {
    if (!tenantId || !empresaId) return;
    setLoading(true); setError(null);
    const { data, error: loadError } = await applyTenantEmpresa(
      supabase.schema("r").from("r_clientes_documento_pendencia").select("*"), tenantId, empresaId
    ).order("cliente_nome");
    if (loadError) setError(loadError.message); else setRows((data ?? []) as Row[]);
    setLoading(false);
  }, [empresaId, supabase, tenantId]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, [load]);

  return <div className="space-y-4">
    <div className="flex flex-wrap items-end justify-between gap-3"><div><h1 className="text-2xl font-semibold">CNPJ inválido ou ausente</h1><p className="mt-1 text-sm text-zinc-400">Fila de saneamento do cadastro de clientes ativos.</p></div><div className="flex gap-2"><Link href="/clientes" className="rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 hover:bg-zinc-800">Clientes</Link><button onClick={() => void load()} className="rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 hover:bg-zinc-800">Atualizar</button></div></div>
    {error && <div className="rounded-md border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-200">{error}</div>}
    <div className="overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950"><table className="w-full text-sm"><thead className="bg-zinc-900/70 text-xs uppercase text-zinc-500"><tr><th className="px-4 py-3 text-left">ID</th><th className="px-4 py-3 text-left">Cliente</th><th className="px-4 py-3 text-left">Documento</th><th className="px-4 py-3 text-left">Pendência</th></tr></thead><tbody className="divide-y divide-zinc-800">{rows.map((row) => <tr key={row.cliente_id}><td className="px-4 py-3">{row.cliente_id}</td><td className="px-4 py-3 font-medium">{row.cliente_nome}</td><td className="px-4 py-3">{row.documento ?? "—"}</td><td className="px-4 py-3"><span className="rounded-full border border-amber-500/30 bg-amber-500/10 px-2 py-1 text-xs text-amber-200">{row.pendencia === "SEM_DOCUMENTO" ? "Sem documento" : "CNPJ com DV inválido"}</span></td></tr>)}{!loading && rows.length === 0 && <tr><td colSpan={4} className="px-4 py-10 text-center text-zinc-500">Nenhuma pendência.</td></tr>}</tbody></table>{loading && <div className="p-4 text-sm text-zinc-500">Carregando...</div>}</div>
  </div>;
}
