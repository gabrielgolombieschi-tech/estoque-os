"use client";

import { useEffect, useMemo, useState } from "react";
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
  const { tenantId, empresaId, loading: tenantLoading } = useTenantEmpresa();
  const { has, loading: permLoading, ready } = usePermissions();
  const canView = has("apontamentos.read");
  const canEdit = has("apontamentos.write");

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

  async function loadClientes() {
    if (!tenantId || !empresaId) return;
    const { data } = await applyTenantEmpresa(
      supabase.from("clientes").select("id,nome,ativo").eq("ativo", true).order("nome", { ascending: true }),
      tenantId,
      empresaId
    );
    setClientes((data ?? []) as Cliente[]);
  }

  async function loadColaboradores() {
    if (!tenantId) return;
    const { data } = await supabase
      .from("colaboradores")
      .select("id,nome,ativo")
      .eq("ativo", true)
      .order("nome", { ascending: true });
    setColaboradores((data ?? []) as Colaborador[]);
  }

  async function loadServicos() {
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
  }

  async function loadVinculos() {
    if (!tenantId || !clienteId) {
      setVinculos([]);
      return;
    }
    const { data } = await supabase
      .from("colaborador_funcao_hh")
      .select(
        "id,colaborador_id,servico_hh_id,ativo,colaboradores(nome),cliente_hh_servicos(nome)"
      )
      .eq("tenant_id", tenantId)
      .eq("cliente_id", clienteId)
      .order("colaborador_id", { ascending: true });
    
    const mapped = (data ?? []).map((row: any) => ({
      id: row.id,
      colaborador_id: row.colaborador_id,
      servico_hh_id: row.servico_hh_id,
      ativo: row.ativo,
      colaboradores: Array.isArray(row.colaboradores) && row.colaboradores.length > 0 ? row.colaboradores[0] : null,
      cliente_hh_servicos: Array.isArray(row.cliente_hh_servicos) && row.cliente_hh_servicos.length > 0 ? row.cliente_hh_servicos[0] : null,
    }));
    
    setVinculos(mapped as ColaboradorFuncao[]);
  }

  useEffect(() => {
    if (tenantLoading) return;
    loadClientes();
    loadColaboradores();
  }, [tenantId, tenantLoading]);

  useEffect(() => {
    if (!clienteId) return;
    loadServicos();
    loadVinculos();
  }, [clienteId, tenantId, empresaId]);

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
