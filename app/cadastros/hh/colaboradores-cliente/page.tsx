"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { applyTenant } from "@/lib/db/scopes";

type Cliente = {
  id: number;
  nome: string;
  ativo: boolean;
  habilita_hh: boolean;
};

type Colaborador = {
  id: string;
  nome: string;
  ativo: boolean;
};

type HHServico = {
  id: number;
  nome: string;
  preco_base: number;
  preco_50: number;
  preco_100: number;
};

type Vinculo = {
  id: number;
  colaborador_id: string;
  hh_servico_id: number;
  ativo: boolean;
  criado_em: string;
  atualizado_em: string;
};

type VinculoRow = Vinculo & {
  colaborador_nome?: string;
  servico_nome?: string;
};

type VinculoForm = {
  colaborador_id: string;
  hh_servico_id: number | null;
  ativo: boolean;
};

function emptyForm(): VinculoForm {
  return {
    colaborador_id: "",
    hh_servico_id: null,
    ativo: true,
  };
}

export default function ColaboradoresClientePage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { tenantId, empresaId } = useTenantEmpresa();
  const fixedTenantId = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
  const fixedEmpresaId = "f0e74f49-a127-46b4-901b-f7b37e43c690";
  const effectiveTenantId = useMemo(() => tenantId ?? fixedTenantId, [tenantId]);
  const effectiveEmpresaId = useMemo(() => empresaId ?? fixedEmpresaId, [empresaId]);
  const { has, loading: permissionsLoading, ready } = usePermissions();
  const canRead = Boolean(has("admin.manage_users")) || Boolean(has("financeiro.read")) || Boolean(has("apontamentos.read"));
  const canWrite = Boolean(has("admin.manage_users")) || Boolean(has("financeiro.read"));

  const [clientes, setClientes] = useState<Cliente[]>([]);
  const [colaboradores, setColaboradores] = useState<Colaborador[]>([]);
  const [servicos, setServicos] = useState<HHServico[]>([]);
  const [vinculos, setVinculos] = useState<VinculoRow[]>([]);

  const [clienteId, setClienteId] = useState<number | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [showModal, setShowModal] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [form, setForm] = useState<VinculoForm>(emptyForm());

  async function loadClientes() {
    if (!tenantId) return;
    try {
      const { data, error } = await applyTenant(
        supabase
          .from("clientes")
          .select("id,nome,ativo,habilita_hh")
          .eq("ativo", true)
          .eq("habilita_hh", true)
          .order("nome", { ascending: true }),
        tenantId
      );
      if (error) throw error;
      setClientes((data ?? []) as Cliente[]);
    } catch (e: unknown) {
      console.warn("Erro ao carregar clientes:", e);
    }
  }

  async function loadColaboradores() {
    if (!tenantId) return;
    try {
      const { data, error } = await applyTenant(
        supabase.from("colaboradores").select("id,nome,ativo").eq("ativo", true).order("nome", { ascending: true }),
        tenantId
      );
      if (error) throw error;
      setColaboradores((data ?? []) as Colaborador[]);
    } catch (e: unknown) {
      console.warn("Erro ao carregar colaboradores:", e);
    }
  }

  async function loadServicos() {
    if (!tenantId || !clienteId) {
      setServicos([]);
      return;
    }
    try {
      const { data, error } = await supabase
        .from("cliente_hh_servicos")
        .select("id,nome,preco_base,preco_50,preco_100")
        .eq("tenant_id", tenantId)
        .eq("cliente_id", clienteId)
        .eq("ativo", true)
        .order("nome", { ascending: true });
      if (error) throw error;
      setServicos((data ?? []) as HHServico[]);
    } catch (e: unknown) {
      console.warn("Erro ao carregar serviços HH:", e);
    }
  }

  async function loadVinculos() {
    if (!tenantId || !clienteId) {
      setVinculos([]);
      return;
    }
    try {
      const { data, error } = await applyTenant(
        supabase
          .from("colaborador_cliente_funcao")
          .select("id,colaborador_id,hh_servico_id,ativo,criado_em,atualizado_em")
          .eq("cliente_id", clienteId)
          .order("criado_em", { ascending: false }),
        tenantId
      );
      if (error) throw error;

      const vinculosRaw = (data ?? []) as Vinculo[];

      // Enriquecer com nomes
      const colaboradorMap = new Map(colaboradores.map((c) => [c.id, c.nome]));
      const servicoMap = new Map(servicos.map((s) => [s.id, s.nome]));

      const enriched: VinculoRow[] = vinculosRaw.map((v) => ({
        ...v,
        colaborador_nome: colaboradorMap.get(v.colaborador_id) ?? `ID: ${v.colaborador_id}`,
        servico_nome: servicoMap.get(v.hh_servico_id) ?? `ID: ${v.hh_servico_id}`,
      }));

      setVinculos(enriched);
    } catch (e: unknown) {
      console.warn("Erro ao carregar vínculos:", e);
    }
  }

  function novoVinculo() {
    setEditingId(null);
    setForm(emptyForm());
    setErr(null);
    setOk(null);
    setShowModal(true);
  }

  function editarVinculo(v: VinculoRow) {
    setEditingId(v.id);
    setForm({
      colaborador_id: v.colaborador_id,
      hh_servico_id: v.hh_servico_id,
      ativo: v.ativo,
    });
    setErr(null);
    setOk(null);
    setShowModal(true);
  }

  function fecharModal() {
    setShowModal(false);
    setEditingId(null);
    setForm(emptyForm());
    setErr(null);
  }

  async function salvar() {
    if (!tenantId || !clienteId || !canWrite) {
      setErr("Sem permissão para salvar.");
      return;
    }

    if (!form.colaborador_id || form.colaborador_id.trim() === "") {
      setErr("Selecione um colaborador.");
      return;
    }

    if (!form.hh_servico_id) {
      setErr("Selecione uma função/serviço HH.");
      return;
    }

    setBusy(true);
    setErr(null);
    setOk(null);

    try {
      const { data: sess } = await supabase.auth.getSession();
      const userEmail = sess.session?.user?.email ?? null;

      // Validar que colaborador existe
      console.log("Validando colaborador_id:", form.colaborador_id);
      const { data: colabCheck, error: colabErr } = await applyTenant(
        supabase.from("colaboradores").select("id").eq("id", form.colaborador_id).maybeSingle(),
        tenantId
      );
      
      if (colabErr) {
        console.error("Erro ao validar colaborador:", colabErr);
        setErr(`Erro ao validar colaborador: ${colabErr.message}`);
        setBusy(false);
        return;
      }
      
      if (!colabCheck) {
        console.error("Colaborador não encontrado:", form.colaborador_id);
        setErr("Colaborador selecionado não existe. Recarregue a página e tente novamente.");
        setBusy(false);
        return;
      }
      
      console.log("Colaborador validado:", colabCheck);

      // NÃO passar tenant_id no payload - virá automaticamente do contexto RLS
      const payload = {
        cliente_id: clienteId,
        colaborador_id: form.colaborador_id,
        hh_servico_id: form.hh_servico_id,
        ativo: form.ativo,
        atualizado_em: new Date().toISOString(),
      };

      console.log("Payload completo:", payload);

      let error;

      if (editingId) {
        // Atualizar
        const res = await applyTenant(
          supabase.from("colaborador_cliente_funcao").update(payload).eq("id", editingId),
          tenantId
        );
        console.log("Resposta UPDATE completa:", res);
        console.log("res.data:", res.data);
        console.log("res.error:", res.error);
        error = res.error;
      } else {
        // Criar novo - tenant_id virá do contexto via trigger ou default
        const res = await applyTenant(
          supabase.from("colaborador_cliente_funcao").insert({
            ...payload,
            criado_por: userEmail,
            criado_em: new Date().toISOString(),
          }),
          tenantId
        );
        console.log("Resposta INSERT completa:", res);
        console.log("res.data:", res.data);
        console.log("res.error:", res.error);
        error = res.error;
      }

      if (error) {
        console.error("Erro Supabase completo:", error);
        console.error("Código:", error.code);
        console.error("Mensagem:", error.message);
        console.error("Detalhes:", error.details);
        console.error("Hint:", error.hint);
        
        // Se for erro de constraint unique, mensagem amigável
        if (error.code === "23505" || error.message?.toLowerCase().includes("unique")) {
          throw new Error("Este colaborador já está vinculado a este serviço neste cliente.");
        }
        // Se for erro de RLS, mensagem clara
        if (error.code === "42501" || error.message?.toLowerCase().includes("row-level security")) {
          throw new Error("Sem permissão para salvar vínculo. Verifique suas permissões (apontamentos.write).");
        }
        throw new Error(error.message || "Erro desconhecido do banco de dados");
      }

      setOk(editingId ? "Vínculo atualizado!" : "Vínculo criado!");
      fecharModal();
      await loadVinculos();
    } catch (e: unknown) {
      console.error("Erro detalhado ao salvar vínculo:", e);
      console.error("Tipo do erro:", typeof e);
      console.error("JSON do erro:", JSON.stringify(e, null, 2));
      
      let message = "Erro ao salvar vínculo.";
      if (e instanceof Error) {
        message = e.message;
      } else if (e && typeof e === "object" && "message" in e) {
        message = String((e as { message: unknown }).message);
      }
      setErr(message);
    } finally {
      setBusy(false);
    }
  }

  async function excluir(id: number) {
    const ok = confirm("Deseja realmente excluir este vínculo?");
    if (!ok) return;

    if (!tenantId || !canWrite) {
      setErr("Sem permissão para excluir.");
      return;
    }

    setBusy(true);
    setErr(null);
    setOk(null);

    try {
      // Soft delete: apenas desativa
      const { error } = await applyTenant(
        supabase
          .from("colaborador_cliente_funcao")
          .update({ ativo: false, atualizado_em: new Date().toISOString() })
          .eq("id", id),
        tenantId
      );

      if (error) throw error;

      setOk("Vínculo desativado!");
      await loadVinculos();
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "Erro ao excluir vínculo.";
      setErr(message);
    } finally {
      setBusy(false);
    }
  }

  async function toggleAtivo(id: number, novoStatus: boolean) {
    if (!tenantId || !canWrite) {
      setErr("Sem permissão para alterar status.");
      return;
    }

    setBusy(true);
    setErr(null);
    setOk(null);

    try {
      const { error } = await applyTenant(
        supabase
          .from("colaborador_cliente_funcao")
          .update({ ativo: novoStatus, atualizado_em: new Date().toISOString() })
          .eq("id", id),
        tenantId
      );

      if (error) throw error;

      setOk(novoStatus ? "Vínculo ativado!" : "Vínculo desativado!");
      await loadVinculos();
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "Erro ao alterar status.";
      setErr(message);
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    void loadClientes();
    void loadColaboradores();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, effectiveTenantId]);

  useEffect(() => {
    if (!clienteId) {
      setServicos([]);
      setVinculos([]);
      return;
    }
    void loadServicos();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clienteId, tenantId, empresaId]);

  useEffect(() => {
    if (servicos.length > 0 && clienteId) {
      void loadVinculos();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [servicos, clienteId, tenantId]);

  if (!ready && permissionsLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando permissões...
      </div>
    );
  }

  if (!canRead) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Acesso negado.
      </div>
    );
  }

  const clienteNome = clientes.find((c) => c.id === clienteId)?.nome ?? "";

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Colaboradores × Cliente × Função HH</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Gerencie os vínculos entre colaboradores e funções/serviços HH por cliente.
          </p>
        </div>
      </div>

      {err && <div className="text-sm text-red-400">{err}</div>}
      {ok && <div className="text-sm text-emerald-300">{ok}</div>}

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div className="space-y-1">
            <label className="text-xs text-zinc-400">Cliente (HH habilitado) *</label>
            <select
              aria-label="Selecionar cliente"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
              value={clienteId ?? ""}
              onChange={(e) => setClienteId(e.target.value ? Number(e.target.value) : null)}
            >
              <option value="">Selecione um cliente...</option>
              {clientes.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nome}
                </option>
              ))}
            </select>
            {clientes.length === 0 && (
              <div className="text-xs text-amber-300 mt-1">
                Nenhum cliente com HH habilitado.{" "}
                <a href="/clientes" className="underline hover:text-amber-200">
                  Habilite HH em um cliente →
                </a>
              </div>
            )}
          </div>
        </div>

        {clienteId && servicos.length === 0 && (
          <div className="mt-4 text-sm text-amber-300">
            O cliente &quot;{clienteNome}&quot; não possui serviços HH cadastrados.{" "}
            <a
              href={`/cadastros/hh/servicos-cliente?cliente_id=${clienteId}`}
              className="underline hover:text-amber-200"
            >
              Cadastre serviços primeiro →
            </a>
          </div>
        )}
      </div>

      {clienteId && servicos.length > 0 && (
        <>
          <div className="flex items-center justify-between gap-3">
            <div className="text-sm text-zinc-300">
              Vínculos de &quot;{clienteNome}&quot; ({vinculos.length})
            </div>
            {canWrite && (
              <button
                onClick={novoVinculo}
                className="px-4 py-2 rounded-md bg-emerald-300 text-emerald-950 hover:bg-emerald-200 font-medium"
              >
                + Novo Vínculo
              </button>
            )}
          </div>

          <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
            <table className="w-full text-sm">
              <thead className="bg-zinc-900/70">
                <tr className="text-left text-zinc-200">
                  <th className="px-4 py-3">Colaborador</th>
                  <th className="px-4 py-3">Função / Serviço HH</th>
                  <th className="px-4 py-3 text-center">Status</th>
                  <th className="px-4 py-3 text-center">Ações</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-800">
                {vinculos.map((v) => (
                  <tr key={v.id} className={v.ativo ? "hover:bg-zinc-900/40" : "bg-zinc-900/20 opacity-60"}>
                    <td className="px-4 py-3 font-medium text-zinc-200">{v.colaborador_nome}</td>
                    <td className="px-4 py-3 text-zinc-300">{v.servico_nome}</td>
                    <td className="px-4 py-3 text-center">
                      <span
                        className={
                          v.ativo
                            ? "inline-flex px-2 py-1 rounded-md border text-xs bg-emerald-500/15 text-emerald-300 border-emerald-500/30"
                            : "inline-flex px-2 py-1 rounded-md border text-xs bg-zinc-500/15 text-zinc-400 border-zinc-500/30"
                        }
                      >
                        {v.ativo ? "Ativo" : "Inativo"}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-center">
                      <div className="flex items-center justify-center gap-2">
                        {canWrite && (
                          <>
                            <button
                              onClick={() => editarVinculo(v)}
                              className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs"
                            >
                              Editar
                            </button>
                            <button
                              onClick={() => toggleAtivo(v.id, !v.ativo)}
                              className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs"
                            >
                              {v.ativo ? "Desativar" : "Ativar"}
                            </button>
                            <button
                              onClick={() => excluir(v.id)}
                              className="px-3 py-1.5 rounded-md border border-red-700 bg-red-900/20 hover:bg-red-900/40 text-red-300 text-xs"
                            >
                              Excluir
                            </button>
                          </>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}

                {vinculos.length === 0 && (
                  <tr>
                    <td colSpan={4} className="px-4 py-6 text-zinc-400 text-center">
                      Nenhum vínculo cadastrado para este cliente.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </>
      )}

      {/* Modal Criar/Editar Vínculo */}
      {showModal && (
        <div
          className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50"
          onClick={(e) => e.target === e.currentTarget && fecharModal()}
        >
          <div
            className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between bg-zinc-900/40">
              <div>
                <div className="text-lg font-semibold">
                  {editingId ? `Editar Vínculo #${editingId}` : "Novo Vínculo"}
                </div>
                <div className="text-sm text-zinc-400">
                  Cliente: {clienteNome}
                </div>
              </div>
              <button
                onClick={fecharModal}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Fechar
              </button>
            </div>

            <div className="px-5 py-4 space-y-4">
              <div className="grid grid-cols-1 gap-3">
                <div className="space-y-1">
                  <label className="text-xs text-zinc-400">Colaborador *</label>
                  <select
                    aria-label="Colaborador"
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                    value={form.colaborador_id}
                    onChange={(e) => setForm((prev) => ({ ...prev, colaborador_id: e.target.value }))}
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
                  <label className="text-xs text-zinc-400">Função / Serviço HH *</label>
                  <select
                    aria-label="Serviço HH"
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900"
                    value={form.hh_servico_id ?? ""}
                    onChange={(e) =>
                      setForm((prev) => ({ ...prev, hh_servico_id: e.target.value ? Number(e.target.value) : null }))
                    }
                  >
                    <option value="">Selecione...</option>
                    {servicos.map((s) => (
                      <option key={s.id} value={s.id}>
                        {s.nome} (Base: R$ {s.preco_base.toFixed(2)})
                      </option>
                    ))}
                  </select>
                </div>

                <div className="border border-zinc-800 rounded-lg px-4 py-3 bg-zinc-900/40">
                  <label className="flex items-center gap-2 text-sm text-zinc-300">
                    <input
                      type="checkbox"
                      checked={form.ativo}
                      onChange={(e) => setForm((prev) => ({ ...prev, ativo: e.target.checked }))}
                      className="h-4 w-4"
                    />
                    Ativo
                  </label>
                  <div className="text-xs text-zinc-400 mt-1">
                    Vínculos inativos não aparecem nos lançamentos de HH.
                  </div>
                </div>
              </div>

              {err && <div className="text-sm text-red-400">{err}</div>}
            </div>

            <div className="px-5 py-3 border-t border-zinc-800 bg-zinc-950 flex justify-end gap-2">
              <button
                onClick={fecharModal}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Cancelar
              </button>
              <button
                onClick={salvar}
                disabled={busy || !canWrite}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
              >
                {busy ? "Salvando..." : "Salvar"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
