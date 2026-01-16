"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { Can } from "@/components/auth/Can";

type Cliente = { id: number; nome: string; ativo: boolean };
type Colaborador = { id: string; nome: string; ativo: boolean };
type ServicoHH = { id: number; nome: string; preco_base: number; ativo: boolean };

type ColaboradorFuncao = {
  id: number;
  colaborador_id: string;
  servico_hh_id: number;
  ativo: boolean;
  colaboradores?: { nome: string | null } | null;
  cliente_hh_servicos?: { nome: string | null } | null;
};

export default function ColaboradorFuncaoPage() {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const { tenantId, empresaId } = useTenantEmpresa();
  const fixedTenantId = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
  const fixedEmpresaId = "f0e74f49-a127-46b4-901b-f7b37e43c690";
  const effectiveTenantId = useMemo(() => tenantId ?? fixedTenantId, [tenantId]);
  const effectiveEmpresaId = useMemo(() => empresaId ?? fixedEmpresaId, [empresaId]);
  const { has, loading: permLoading, ready } = usePermissions();
  const canView = has("apontamentos.read");

  const [clientes, setClientes] = useState<Cliente[]>([]);
  const [colaboradores, setColaboradores] = useState<Colaborador[]>([]);
  const [servicos, setServicos] = useState<ServicoHH[]>([]);
  const [vinculos, setVinculos] = useState<ColaboradorFuncao[]>([]);

  const [clienteId, setClienteId] = useState<number | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [showForm, setShowForm] = useState(false);
  const [formColabId, setFormColabId] = useState<string | null>(null);
  const [formServicoId, setFormServicoId] = useState<number | null>(null);

  const loadClientes = useCallback(async () => {
    if (!tenantId || !empresaId) return;
    const { data } = await applyTenantEmpresa(
      supabase.from("clientes").select("id,nome,ativo").eq("ativo", true).order("nome", { ascending: true }),
      tenantId,
      empresaId
    );
    setClientes((data ?? []) as Cliente[]);
  }, [empresaId, supabase, tenantId]);

  const loadColaboradores = useCallback(async () => {
    if (!tenantId) return;
    const { data } = await supabase
      .from("colaboradores")
      .select("id,nome,ativo")
      .eq("ativo", true)
      .order("nome", { ascending: true });
    setColaboradores((data ?? []) as Colaborador[]);
  }, [supabase, tenantId]);

  const loadServicos = useCallback(async () => {
    if (!tenantId || !empresaId || !clienteId) {
      setServicos([]);
      return;
    }
    const { data } = await applyTenantEmpresa(
      supabase
        .from("cliente_hh_servicos")
        .select("id,nome,preco_base,ativo")
        .eq("cliente_id", clienteId)
        .eq("ativo", true)
        .order("nome", { ascending: true }),
      tenantId,
      empresaId
    );
    setServicos((data ?? []) as ServicoHH[]);
  }, [clienteId, empresaId, supabase, tenantId]);

  const loadVinculos = useCallback(async () => {
    if (!tenantId || !clienteId) {
      setVinculos([]);
      return;
    }
    const { data } = await supabase
      .from("colaborador_funcao_hh")
      .select("id,colaborador_id,servico_hh_id,ativo,colaboradores(nome),cliente_hh_servicos(nome)")
      .eq("tenant_id", tenantId)
      .eq("cliente_id", clienteId)
      .order("colaborador_id", { ascending: true });

    const mapped = (data ?? []).map((row) => {
      const r = row as Record<string, unknown>;
      const colaboradores = r.colaboradores;
      const cliente_hh_servicos = r.cliente_hh_servicos;
      return {
        id: r.id,
        colaborador_id: r.colaborador_id,
        servico_hh_id: r.servico_hh_id,
        ativo: r.ativo,
        colaboradores:
          Array.isArray(colaboradores) && colaboradores.length > 0
            ? (colaboradores[0] as unknown as ColaboradorFuncao["colaboradores"])
            : null,
        cliente_hh_servicos:
          Array.isArray(cliente_hh_servicos) && cliente_hh_servicos.length > 0
            ? (cliente_hh_servicos[0] as unknown as ColaboradorFuncao["cliente_hh_servicos"])
            : null,
      };
    });

    setVinculos(mapped as ColaboradorFuncao[]);
  }, [clienteId, supabase, tenantId]);

  useEffect(() => {
    const t = setTimeout(() => {
      void loadClientes();
      void loadColaboradores();
    }, 0);
    return () => clearTimeout(t);
  }, [loadClientes, loadColaboradores, tenantId, effectiveTenantId]);

  useEffect(() => {
    if (!clienteId) return;
    const t = setTimeout(() => {
      void loadServicos();
      void loadVinculos();
    }, 0);
    return () => clearTimeout(t);
  }, [clienteId, loadServicos, loadVinculos]);

  async function adicionarVinculo() {
    if (!tenantId || !clienteId || !formColabId || !formServicoId) {
      setErr("Preencha todos os campos.");
      return;
    }

    setBusy(true);
    setErr(null);

    const { error } = await supabase.from("colaborador_funcao_hh").insert({
      tenant_id: tenantId,
      cliente_id: clienteId,
      colaborador_id: formColabId,
      servico_hh_id: formServicoId,
      ativo: true,
    });

    setBusy(false);

    if (error) {
      if (error.message?.includes("unique")) {
        setErr("Este colaborador já tem esta função vinculada.");
      } else {
        setErr(error.message);
      }
      return;
    }

    setOk("Vínculo adicionado com sucesso!");
    setFormColabId(null);
    setFormServicoId(null);
    setShowForm(false);
    await loadVinculos();
  }

  async function removerVinculo(id: number) {
    const ok = confirm("Remover este vínculo?");
    if (!ok) return;

    setBusy(true);
    setErr(null);

    const { error } = await supabase.from("colaborador_funcao_hh").delete().eq("id", id);

    setBusy(false);

    if (error) {
      setErr(error.message);
      return;
    }

    setOk("Vínculo removido.");
    await loadVinculos();
  }

  if (!ready && permLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando permissões...
      </div>
    );
  }

  if (!canView) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Acesso negado.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Colaboradores - Funções HH</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Vincule colaboradores às funções (especialidades) por cliente.
          </p>
        </div>

        <Can perm="apontamentos.write">
          <button
            onClick={() => {
              if (!clienteId) {
                alert("Selecione um cliente primeiro.");
                return;
              }
              setShowForm(true);
              setFormColabId(null);
              setFormServicoId(null);
            }}
            disabled={!clienteId}
            className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-50"
          >
            Adicionar Vínculo
          </button>
        </Can>
      </div>

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="space-y-1">
          <div className="text-xs text-zinc-400">Cliente *</div>
          <select
            aria-label="Cliente"
            className="w-full md:w-96 px-3 py-2"
            value={clienteId ?? ""}
            onChange={(e) => setClienteId(e.target.value ? Number(e.target.value) : null)}
          >
            <option value="">Selecione um cliente</option>
            {clientes.map((c) => (
              <option key={c.id} value={c.id}>
                {c.nome}
              </option>
            ))}
          </select>
        </div>
      </div>

      {err && <div className="text-sm text-red-400">{err}</div>}
      {ok && <div className="text-sm text-emerald-300">{ok}</div>}

      {clienteId && (
        <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/70">
              <tr className="text-zinc-200">
                <th className="px-4 py-3 text-left">Colaborador</th>
                <th className="px-4 py-3 text-left">Função (Serviço HH)</th>
                <th className="px-4 py-3 text-center">Ativo</th>
                <th className="px-4 py-3 text-center">Ações</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-zinc-800">
              {vinculos.map((v) => (
                <tr key={v.id} className="hover:bg-zinc-900/40">
                  <td className="px-4 py-3 font-medium">
                    {v.colaboradores?.nome ?? `ID: ${v.colaborador_id}`}
                  </td>
                  <td className="px-4 py-3 text-zinc-300">
                    {v.cliente_hh_servicos?.nome ?? `ID: ${v.servico_hh_id}`}
                  </td>
                  <td className="px-4 py-3 text-center">
                    <span
                      className={`inline-flex items-center px-2 py-1 rounded-md border text-xs ${
                        v.ativo
                          ? "bg-emerald-500/15 text-emerald-300 border-emerald-500/30"
                          : "bg-zinc-500/15 text-zinc-300 border-zinc-500/30"
                      }`}
                    >
                      {v.ativo ? "Sim" : "Não"}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-center">
                    <Can perm="apontamentos.write">
                      <button
                        onClick={() => removerVinculo(v.id)}
                        disabled={busy}
                        className="px-3 py-1.5 rounded-md border border-red-600/50 bg-red-900/20 hover:bg-red-900/30 text-red-300 text-sm"
                      >
                        Remover
                      </button>
                    </Can>
                  </td>
                </tr>
              ))}

              {vinculos.length === 0 && (
                <tr>
                  <td colSpan={4} className="px-4 py-6 text-zinc-400">
                    Nenhum vínculo cadastrado para este cliente.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      {showForm && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="w-full max-w-lg bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl">
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
              <div>
                <div className="text-lg font-semibold">Adicionar Vínculo</div>
                <div className="text-sm text-zinc-400">Vincule um colaborador a uma função de HH.</div>
              </div>
              <button
                onClick={() => setShowForm(false)}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Cancelar
              </button>
            </div>

            <div className="px-5 py-4 space-y-3">
              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Colaborador *</div>
                <select
                  aria-label="Colaborador"
                  className="w-full px-3 py-2"
                  value={formColabId ?? ""}
                  onChange={(e) => setFormColabId(e.target.value || null)}
                >
                  <option value="">Selecione...</option>
                  {colaboradores.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.nome}
                    </option>
                  ))}
                </select>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Função (Serviço HH) *</div>
                <select
                  aria-label="Serviço HH"
                  className="w-full px-3 py-2"
                  value={formServicoId ?? ""}
                  onChange={(e) => setFormServicoId(e.target.value ? Number(e.target.value) : null)}
                >
                  <option value="">Selecione...</option>
                  {servicos.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.nome}
                    </option>
                  ))}
                </select>
              </div>

              {err && <div className="text-sm text-red-400">{err}</div>}
            </div>

            <div className="px-5 py-3 border-t border-zinc-800 flex justify-end gap-2">
              <button
                onClick={() => setShowForm(false)}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Cancelar
              </button>
              <button
                onClick={adicionarVinculo}
                disabled={busy || !formColabId || !formServicoId}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
              >
                {busy ? "Adicionando..." : "Adicionar"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
