"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenant } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { Can } from "@/components/auth/Can";

type Cliente = { id: number; nome: string; ativo: boolean };

type Tabela = {
  id: number;
  cliente_id: number;
  ano: number;
  nome: string;
  vigencia_inicio: string;
  vigencia_fim: string;
  ativo: boolean;
  clientes?: { nome: string | null } | null;
};

type TabelaForm = {
  cliente_id: number | null;
  ano: number;
  nome: string;
  vigencia_inicio: string;
  vigencia_fim: string;
  ativo: boolean;
};

export default function TabelasHHPage() {
  const router = useRouter();
  const supabase = useMemo(() => supabaseBrowser(), []);
  const { tenantId, loading: tenantLoading } = useTenantEmpresa();
  const { has, loading: permLoading, ready } = usePermissions();
  const canView = has("os.read");
  const canEdit = has("os.write");

  const [rows, setRows] = useState<Tabela[]>([]);
  const [clientes, setClientes] = useState<Cliente[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const currentYear = new Date().getFullYear();
  const [filterCliente, setFilterCliente] = useState<string>("todos");
  const [filterAno, setFilterAno] = useState<string>("");
  const [filterAtivo, setFilterAtivo] = useState<string>("todos");

  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [form, setForm] = useState<TabelaForm>({
    cliente_id: null,
    ano: currentYear,
    nome: "",
    vigencia_inicio: `${currentYear}-01-01`,
    vigencia_fim: `${currentYear}-12-31`,
    ativo: true,
  });

  async function loadClientes() {
    if (tenantLoading) return;
    if (!tenantId) return;

    const { data } = await applyTenant(
      supabase.from("clientes").select("id,nome,ativo").eq("ativo", true).order("nome", { ascending: true }),
      tenantId
    );
    setClientes((data ?? []) as Cliente[]);
  }

  async function load() {
    setErr(null);
    if (tenantLoading) return;
    if (!tenantId) {
      setErr("Tenant não carregado.");
      return;
    }

    let query = applyTenant(
      supabase
        .from("cliente_hh_tabelas")
        .select("*,clientes:cliente_id(nome)")
        .order("ano", { ascending: false }),
      tenantId
    );

    if (filterCliente !== "todos") {
      const clienteId = Number.parseInt(filterCliente, 10);
      if (Number.isFinite(clienteId)) {
        query = query.eq("cliente_id", clienteId);
      }
    }

    if (filterAno) {
      const ano = Number.parseInt(filterAno, 10);
      if (Number.isFinite(ano)) {
        query = query.eq("ano", ano);
      }
    }

    if (filterAtivo === "ativos") query = query.eq("ativo", true);
    if (filterAtivo === "inativos") query = query.eq("ativo", false);

    const { data, error } = await query;
    if (error) return setErr(error.message);
    setRows((data ?? []) as Tabela[]);
  }

  useEffect(() => {
    loadClientes();
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, tenantLoading]);

  function startNew() {
    setOk(null);
    setErr(null);
    if (!canEdit) {
      setErr("Sem permissão para criar tabelas.");
      return;
    }
    setEditingId(null);
    const year = currentYear;
    setForm({
      cliente_id: null,
      ano: year,
      nome: "",
      vigencia_inicio: `${year}-01-01`,
      vigencia_fim: `${year}-12-31`,
      ativo: true,
    });
    setShowForm(true);
  }

  function startEdit(r: Tabela) {
    setOk(null);
    setErr(null);
    if (!canEdit) {
      setErr("Sem permissão para editar tabelas.");
      return;
    }
    setEditingId(r.id);
    setForm({
      cliente_id: r.cliente_id,
      ano: r.ano,
      nome: r.nome,
      vigencia_inicio: r.vigencia_inicio.slice(0, 10),
      vigencia_fim: r.vigencia_fim.slice(0, 10),
      ativo: r.ativo,
    });
    setShowForm(true);
  }

  function closeForm() {
    setShowForm(false);
    setEditingId(null);
    const year = currentYear;
    setForm({
      cliente_id: null,
      ano: year,
      nome: "",
      vigencia_inicio: `${year}-01-01`,
      vigencia_fim: `${year}-12-31`,
      ativo: true,
    });
  }

  async function save() {
    setOk(null);
    setErr(null);
    if (!canEdit) {
      setErr("Sem permissão para salvar tabelas.");
      return;
    }

    if (!form.cliente_id) return setErr("Cliente é obrigatório.");
    if (!form.ano) return setErr("Ano é obrigatório.");
    if (!form.nome.trim()) return setErr("Nome é obrigatório.");

    setBusy(true);

    const payload = {
      cliente_id: form.cliente_id,
      ano: form.ano,
      nome: form.nome.trim(),
      vigencia_inicio: form.vigencia_inicio,
      vigencia_fim: form.vigencia_fim,
      ativo: form.ativo,
    };

    if (!tenantId) {
      setBusy(false);
      return setErr("Tenant não carregado.");
    }

    let error: { message?: string } | null = null;

    if (editingId) {
      const res = await applyTenant(
        supabase.from("cliente_hh_tabelas").update(payload),
        tenantId
      ).eq("id", editingId);
      error = res.error;
    } else {
      const res = await supabase
        .from("cliente_hh_tabelas")
        .insert({ ...payload, tenant_id: tenantId, criado_em: new Date().toISOString() });
      error = res.error;
    }

    setBusy(false);
    if (error) return setErr(error.message ?? "Erro ao salvar.");

    setOk(editingId ? "Tabela atualizada!" : "Tabela criada!");
    closeForm();
    await load();
  }

  function formatDate(dateStr: string) {
    const d = new Date(dateStr);
    return d.toLocaleDateString("pt-BR");
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
          <h1 className="text-2xl font-semibold">Tabelas HH</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Tabelas de valores Homem-Hora por cliente e ano.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>
          <Can perm="os.write">
            <button
              onClick={startNew}
              className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
            >
              Nova Tabela HH
            </button>
          </Can>
        </div>
      </div>

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Cliente</div>
            <select
              aria-label="Filtrar por cliente"
              className="w-full px-3 py-2"
              value={filterCliente}
              onChange={(e) => setFilterCliente(e.target.value)}
            >
              <option value="todos">Todos</option>
              {clientes.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nome}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Ano</div>
            <input
              aria-label="Filtrar por ano"
              type="number"
              className="w-full px-3 py-2"
              value={filterAno}
              onChange={(e) => setFilterAno(e.target.value)}
              placeholder="Ex: 2024"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Ativo</div>
            <select
              aria-label="Filtrar por ativo"
              className="w-full px-3 py-2"
              value={filterAtivo}
              onChange={(e) => setFilterAtivo(e.target.value)}
            >
              <option value="todos">Todos</option>
              <option value="ativos">Ativos</option>
              <option value="inativos">Inativos</option>
            </select>
          </div>
        </div>

        <div className="flex items-center gap-2 mt-3">
          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Buscar
          </button>
        </div>

        {err && <div className="text-sm text-red-400 mt-3">{err}</div>}
        {ok && <div className="text-sm text-emerald-300 mt-3">{ok}</div>}
      </div>

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-4 py-3 text-left">Cliente</th>
              <th className="px-4 py-3 text-left">Ano</th>
              <th className="px-4 py-3 text-left">Nome</th>
              <th className="px-4 py-3 text-left">Vigência</th>
              <th className="px-4 py-3 text-center">Ativo</th>
              <th className="px-4 py-3 text-center">Ações</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-800">
            {rows.map((r) => (
              <tr key={r.id} className="hover:bg-zinc-900/40">
                <td className="px-4 py-3 font-medium">{r.clientes?.nome ?? `ID ${r.cliente_id}`}</td>
                <td className="px-4 py-3">{r.ano}</td>
                <td className="px-4 py-3">{r.nome}</td>
                <td className="px-4 py-3 text-sm text-zinc-300">
                  {formatDate(r.vigencia_inicio)} - {formatDate(r.vigencia_fim)}
                </td>
                <td className="px-4 py-3 text-center">
                  <span
                    className={`inline-flex items-center px-2 py-1 rounded-md border text-xs ${
                      r.ativo
                        ? "bg-emerald-500/15 text-emerald-300 border-emerald-500/30"
                        : "bg-zinc-500/15 text-zinc-300 border-zinc-500/30"
                    }`}
                  >
                    {r.ativo ? "Sim" : "Não"}
                  </span>
                </td>
                <td className="px-4 py-3 text-center">
                  <div className="flex items-center justify-center gap-2">
                    <button
                      onClick={() => router.push(`/cadastros/hh/tabelas/${r.id}`)}
                      className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                    >
                      Abrir
                    </button>
                    <Can perm="os.write">
                      <button
                        onClick={() => startEdit(r)}
                        className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                      >
                        Editar
                      </button>
                    </Can>
                  </div>
                </td>
              </tr>
            ))}

            {rows.length === 0 && (
              <tr>
                <td colSpan={6} className="px-4 py-6 text-zinc-400">
                  Nenhuma tabela HH encontrada.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {showForm && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl">
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
              <div>
                <div className="text-lg font-semibold">
                  {editingId ? "Editar Tabela HH" : "Nova Tabela HH"}
                </div>
                <div className="text-sm text-zinc-400">Preencha os campos abaixo.</div>
              </div>
              <button
                onClick={closeForm}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Cancelar
              </button>
            </div>

            <div className="px-5 py-4 space-y-3">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Cliente *</div>
                  <select
                    aria-label="Cliente"
                    className="w-full px-3 py-2"
                    value={form.cliente_id ?? ""}
                    onChange={(e) =>
                      setForm((s) => ({ ...s, cliente_id: e.target.value ? Number(e.target.value) : null }))
                    }
                  >
                    <option value="">Selecione</option>
                    {clientes.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.nome}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Ano *</div>
                  <input
                    aria-label="Ano"
                    type="number"
                    className="w-full px-3 py-2"
                    value={form.ano}
                    onChange={(e) => {
                      const ano = Number(e.target.value);
                      setForm((s) => ({
                        ...s,
                        ano,
                        vigencia_inicio: `${ano}-01-01`,
                        vigencia_fim: `${ano}-12-31`,
                      }));
                    }}
                  />
                </div>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Nome *</div>
                <input
                  aria-label="Nome"
                  className="w-full px-3 py-2"
                  value={form.nome}
                  onChange={(e) => setForm((s) => ({ ...s, nome: e.target.value }))}
                  placeholder="Ex: SEGAU 2024/2025"
                />
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Vigência início</div>
                  <input
                    aria-label="Vigência início"
                    type="date"
                    className="w-full px-3 py-2"
                    value={form.vigencia_inicio}
                    onChange={(e) => setForm((s) => ({ ...s, vigencia_inicio: e.target.value }))}
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Vigência fim</div>
                  <input
                    aria-label="Vigência fim"
                    type="date"
                    className="w-full px-3 py-2"
                    value={form.vigencia_fim}
                    onChange={(e) => setForm((s) => ({ ...s, vigencia_fim: e.target.value }))}
                  />
                </div>
              </div>

              <div className="flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={form.ativo}
                  onChange={(e) => setForm((s) => ({ ...s, ativo: e.target.checked }))}
                  id="tabela-ativo-check"
                />
                <label htmlFor="tabela-ativo-check" className="text-sm text-zinc-200">
                  Ativo
                </label>
              </div>

              {err && <div className="text-sm text-red-400">{err}</div>}
            </div>

            <div className="px-5 py-3 border-t border-zinc-800 flex justify-end gap-2">
              <button
                onClick={closeForm}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Cancelar
              </button>
              <button
                onClick={save}
                disabled={busy || !canEdit}
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
