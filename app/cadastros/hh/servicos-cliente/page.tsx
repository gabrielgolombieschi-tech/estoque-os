"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { parseDecimalBR, formatDecimalBR } from "@/lib/decimal";
import { upper, upperOrNull, upperTrim } from "@/lib/text";

type Cliente = { id: number; nome: string };
type ServicoHH = {
  id: number;
  empresa_id: string;
  cliente_id: number;
  nome: string;
  descricao: string | null;
  preco_base: number;
  preco_50: number;
  preco_100: number;
  ativo: boolean;
  criado_em: string;
};

type ServicoForm = {
  id?: number;
  cliente_id: number | null;
  nome: string;
  descricao: string;
  preco_base: number;
  preco_50: number;
  preco_100: number;
  ativo: boolean;
};

function emptyForm(): ServicoForm {
  return {
    cliente_id: null,
    nome: "",
    descricao: "",
    preco_base: 0,
    preco_50: 0,
    preco_100: 0,
    ativo: true,
  };
}

export default function ServicosClientePage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const { tenantId, empresaId, loading: tenantLoading } = useTenantEmpresa();
  const { has, loading: permLoading } = usePermissions();
  const isAdmin = Boolean(has("admin.manage_users")) || Boolean(has("admin.users.manage"));
  const canView = isAdmin || Boolean(has("financeiro.read")) || Boolean(has("apontamentos.read"));
  const canEdit = isAdmin || Boolean(has("financeiro.read")) || Boolean(has("apontamentos.write"));

  const [clientes, setClientes] = useState<Cliente[]>([]);
  const [servicos, setServicos] = useState<ServicoHH[]>([]);
  const [clienteIdFiltro, setClienteIdFiltro] = useState<number | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [form, setForm] = useState<ServicoForm>(emptyForm());

  async function loadClientes() {
    if (tenantLoading || !tenantId || !empresaId) return;
    const { data, error } = await applyTenantEmpresa(
      supabase
        .from("clientes")
        .select("id,nome")
        .eq("empresa_id", empresaId)
        .eq("ativo", true)
        .eq("habilita_hh", true)
        .order("nome", { ascending: true }),
      tenantId,
      empresaId
    );
    if (!error) setClientes((data ?? []) as Cliente[]);
  }

  async function loadServicos() {
    setErr(null);
    if (tenantLoading || !tenantId || !empresaId) return;
    if (!clienteIdFiltro) {
      setServicos([]);
      return;
    }

    const { data, error } = await applyTenantEmpresa(
      supabase
        .from("cliente_hh_servicos")
        .select("*")
        .eq("empresa_id", empresaId)
        .eq("cliente_id", clienteIdFiltro)
        .order("criado_em", { ascending: false }),
      tenantId,
      empresaId
    );

    if (error) return setErr(error.message);
    setServicos((data ?? []) as ServicoHH[]);
  }

  useEffect(() => {
    loadClientes();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, empresaId, tenantLoading]);

  useEffect(() => {
    loadServicos();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clienteIdFiltro, tenantId, empresaId, tenantLoading]);

  function startNew() {
    if (!canEdit) return setErr("Sem permissão para criar serviços.");
    if (!clienteIdFiltro) return setErr("Selecione um cliente antes de criar um serviço.");
    setEditingId(null);
    setForm({ ...emptyForm(), cliente_id: clienteIdFiltro });
    setErr(null);
    setOk(null);
    setShowForm(true);
  }

  function startEdit(s: ServicoHH) {
    if (!canEdit) return setErr("Sem permissão para editar serviços.");
    setEditingId(s.id);
    setForm({
      id: s.id,
      cliente_id: s.cliente_id,
      nome: upper(s.nome),
      descricao: upper(s.descricao ?? ""),
      preco_base: s.preco_base,
      preco_50: s.preco_50,
      preco_100: s.preco_100,
      ativo: s.ativo,
    });
    setErr(null);
    setOk(null);
    setShowForm(true);
  }

  async function save() {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissão para salvar.");
    if (!tenantId || !empresaId) return setErr("Empresa não carregada.");
    if (!form.cliente_id) return setErr("Cliente não selecionado.");
    if (!form.nome.trim()) return setErr("Nome é obrigatório.");
    if (form.preco_base < 0 || form.preco_50 < 0 || form.preco_100 < 0)
      return setErr("Preços não podem ser negativos.");

    setBusy(true);

    const payload = {
      cliente_id: form.cliente_id,
      nome: upperTrim(form.nome),
      descricao: upperOrNull(form.descricao),
      preco_base: form.preco_base,
      preco_50: form.preco_50,
      preco_100: form.preco_100,
      ativo: form.ativo,
      atualizado_em: new Date().toISOString(),
    };

    if (editingId) {
      const { error } = await applyTenantEmpresa(
        supabase.from("cliente_hh_servicos").update(payload).eq("id", editingId).eq("empresa_id", empresaId),
        tenantId,
        empresaId
      );
      setBusy(false);
      if (error) return setErr(error.message);
      setOk("Serviço atualizado!");
    } else {
      const { data: sess } = await supabase.auth.getSession();
      const userEmail = sess.session?.user?.email ?? null;

      const { error } = await supabase.from("cliente_hh_servicos").insert({
        ...payload,
        tenant_id: tenantId,
        empresa_id: empresaId,
        criado_por: userEmail,
        criado_em: new Date().toISOString(),
      });
      setBusy(false);
      if (error) return setErr(error.message);
      setOk("Serviço criado!");
    }

    setShowForm(false);
    setForm(emptyForm());
    setEditingId(null);
    await loadServicos();
  }

  async function toggleAtivo(id: number, to: boolean) {
    if (!canEdit) return setErr("Sem permissão.");
    if (!tenantId || !empresaId) return setErr("Empresa não carregada.");
    const ok = confirm(to ? "Ativar serviço?" : "Desativar serviço?");
    if (!ok) return;

    setBusy(true);
    const { error } = await applyTenantEmpresa(
      supabase
        .from("cliente_hh_servicos")
        .update({ ativo: to, atualizado_em: new Date().toISOString() })
        .eq("id", id)
        .eq("empresa_id", empresaId),
      tenantId,
      empresaId
    );
    setBusy(false);
    if (error) return setErr(error.message);
    setOk(to ? "Serviço ativado." : "Serviço desativado.");
    await loadServicos();
  }

  function calcular50() {
    setForm((f) => ({ ...f, preco_50: f.preco_base * 1.5 }));
  }

  function calcular100() {
    setForm((f) => ({ ...f, preco_100: f.preco_base * 2 }));
  }

  if (!canView && !permLoading) {
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
          <h1 className="text-2xl font-semibold">Serviços HH por Cliente</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Cadastre os serviços de Hora-Homem com 3 níveis de preço (base, 50%, 100%).
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button onClick={loadServicos} className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800">
            Atualizar
          </button>
          {canEdit && (
            <button
              onClick={startNew}
              disabled={!clienteIdFiltro}
              className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-50"
            >
              Novo Serviço
            </button>
          )}
        </div>
      </div>

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="space-y-1">
          <div className="text-xs text-zinc-400">Cliente *</div>
          <select
            aria-label="Cliente"
            className="w-full md:w-96 px-3 py-2"
            value={clienteIdFiltro ?? ""}
            onChange={(e) => setClienteIdFiltro(e.target.value ? Number(e.target.value) : null)}
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

      {clienteIdFiltro && (
        <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/70">
              <tr className="text-zinc-200">
                <th className="px-4 py-3 text-left">ID</th>
                <th className="px-4 py-3 text-left">Nome</th>
                <th className="px-4 py-3 text-left">Descrição</th>
                <th className="px-4 py-3 text-right">Preço Base</th>
                <th className="px-4 py-3 text-right">Preço 50%</th>
                <th className="px-4 py-3 text-right">Preço 100%</th>
                <th className="px-4 py-3 text-center">Ativo</th>
                <th className="px-4 py-3 text-center">Ações</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-zinc-800">
              {servicos.map((s) => (
                <tr key={s.id} className="hover:bg-zinc-900/40">
                  <td className="px-4 py-3 text-zinc-400 tabular-nums">{s.id}</td>
                  <td className="px-4 py-3 font-medium">{s.nome}</td>
                  <td className="px-4 py-3 text-zinc-300">{s.descricao || "—"}</td>
                  <td className="px-4 py-3 text-right tabular-nums">R$ {formatDecimalBR(s.preco_base, 2)}</td>
                  <td className="px-4 py-3 text-right tabular-nums">R$ {formatDecimalBR(s.preco_50, 2)}</td>
                  <td className="px-4 py-3 text-right tabular-nums">R$ {formatDecimalBR(s.preco_100, 2)}</td>
                  <td className="px-4 py-3 text-center">{s.ativo ? "Sim" : "Não"}</td>
                  <td className="px-4 py-3 text-center">
                    <div className="flex items-center justify-center gap-2">
                      {canEdit && (
                        <>
                          <button
                            onClick={() => startEdit(s)}
                            className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                          >
                            Editar
                          </button>
                          <button
                            onClick={() => toggleAtivo(s.id, !s.ativo)}
                            className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                          >
                            {s.ativo ? "Desativar" : "Ativar"}
                          </button>
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              ))}

              {servicos.length === 0 && (
                <tr>
                  <td colSpan={8} className="px-4 py-6 text-zinc-400">
                    Nenhum serviço cadastrado para este cliente.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      {showForm && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl">
            <div className="px-5 py-4 border-b border-zinc-900/80 flex items-center justify-between">
              <div>
                <div className="font-semibold">{editingId ? "Editar Serviço HH" : "Novo Serviço HH"}</div>
                <div className="text-xs text-zinc-400 mt-0.5">
                  Cliente: {clientes.find((c) => c.id === form.cliente_id)?.nome ?? "—"}
                </div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setShowForm(false)}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                <button
                  onClick={save}
                  disabled={busy}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
                >
                  {busy ? "Salvando..." : "Salvar"}
                </button>
              </div>
            </div>

            <div className="px-5 py-4 space-y-4 max-h-[70vh] overflow-y-auto">
              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Nome do Serviço *</div>
                <input
                  aria-label="Nome do Serviço"
                  className="w-full px-3 py-2"
                  value={form.nome}
                  onChange={(e) => setForm((f) => ({ ...f, nome: upper(e.target.value) }))}
                  placeholder="Ex: MAO-DE-OBRA ELETRICISTA HH NIVEL I"
                />
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Descrição</div>
                <textarea
                  aria-label="Descrição"
                  className="w-full px-3 py-2 min-h-[60px]"
                  value={form.descricao}
                  onChange={(e) => setForm((f) => ({ ...f, descricao: upper(e.target.value) }))}
                />
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Preço Base (R$) *</div>
                  <input
                    type="text"
                    inputMode="decimal"
                    aria-label="Preço Base"
                    className="w-full px-3 py-2"
                    value={formatDecimalBR(form.preco_base, 2)}
                    onChange={(e) => setForm((f) => ({ ...f, preco_base: parseDecimalBR(e.target.value) || 0 }))}
                    onBlur={() => {
                      calcular50();
                      calcular100();
                    }}
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">
                    Preço 50% (R$)
                    <button
                      type="button"
                      onClick={calcular50}
                      className="ml-2 text-[11px] text-blue-400 hover:underline"
                    >
                      Auto
                    </button>
                  </div>
                  <input
                    type="text"
                    inputMode="decimal"
                    aria-label="Preço 50%"
                    className="w-full px-3 py-2"
                    value={formatDecimalBR(form.preco_50, 2)}
                    onChange={(e) => setForm((f) => ({ ...f, preco_50: parseDecimalBR(e.target.value) || 0 }))}
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">
                    Preço 100% (R$)
                    <button
                      type="button"
                      onClick={calcular100}
                      className="ml-2 text-[11px] text-blue-400 hover:underline"
                    >
                      Auto
                    </button>
                  </div>
                  <input
                    type="text"
                    inputMode="decimal"
                    aria-label="Preço 100%"
                    className="w-full px-3 py-2"
                    value={formatDecimalBR(form.preco_100, 2)}
                    onChange={(e) => setForm((f) => ({ ...f, preco_100: parseDecimalBR(e.target.value) || 0 }))}
                  />
                </div>
              </div>

              <div className="border border-zinc-800 rounded-lg p-3">
                <label className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={form.ativo}
                    onChange={(e) => setForm((f) => ({ ...f, ativo: e.target.checked }))}
                  />
                  Serviço ativo
                </label>
              </div>

              {err && <div className="text-sm text-red-400">{err}</div>}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
