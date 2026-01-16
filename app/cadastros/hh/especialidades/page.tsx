"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { Can } from "@/components/auth/Can";
import { parseDecimalBR } from "@/lib/decimal";

type HHPreco = {
  id: number;
  descricao: string;
  nivel: string;
  categoria: string;
  preco_base: number;
  preco_50: number;
  preco_100: number;
  ativo: boolean;
  criado_em: string;
  atualizado_em: string;
};

type HHPrecoForm = {
  descricao: string;
  nivel: string;
  categoria: string;
  preco_base: number;
  preco_50: number;
  preco_100: number;
  ativo: boolean;
};

export default function EspecialidadesPage() {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const { has, loading: permLoading, ready } = usePermissions();
  const canView = has("os.read") || has("admin.manage_users") || has("financeiro.read");
  const canEdit = has("os.write") || has("admin.manage_users") || has("financeiro.read");
  const canDelete = has("os.delete") || has("admin.manage_users");

  const [rows, setRows] = useState<HHPreco[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [q, setQ] = useState("");
  const [filterCategoria, setFilterCategoria] = useState<string>("todas");
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [form, setForm] = useState<HHPrecoForm>({
    descricao: "",
    nivel: "I",
    categoria: "montador",
    preco_base: 0,
    preco_50: 0,
    preco_100: 0,
    ativo: true,
  });

  async function load() {
    setErr(null);

    // hh_tabela_precos é global (sem tenant_id)
    let query = supabase.from("hh_tabela_precos").select("*").order("categoria", { ascending: true }).order("nivel", { ascending: true });

    const term = q.trim().toLowerCase();
    if (term) {
      query = query.ilike("descricao", `%${term}%`);
    }

    if (filterCategoria !== "todas") {
      query = query.eq("categoria", filterCategoria);
    }

    const { data, error } = await query;
    if (error) return setErr(error.message);
    setRows((data ?? []) as HHPreco[]);
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q, filterCategoria]);

  function startNew() {
    setOk(null);
    setErr(null);
    if (!canEdit) {
      setErr("Sem permissão para criar especialidades.");
      return;
    }
    setEditingId(null);
    setForm({
      descricao: "",
      nivel: "I",
      categoria: "montador",
      preco_base: 0,
      preco_50: 0,
      preco_100: 0,
      ativo: true,
    });
    setShowForm(true);
  }

  function startEdit(r: HHPreco) {
    setOk(null);
    setErr(null);
    if (!canEdit) {
      setErr("Sem permissão para editar especialidades.");
      return;
    }
    setEditingId(r.id);
    setForm({
      descricao: r.descricao,
      nivel: r.nivel,
      categoria: r.categoria,
      preco_base: Number(r.preco_base),
      preco_50: Number(r.preco_50),
      preco_100: Number(r.preco_100),
      ativo: r.ativo,
    });
    setShowForm(true);
  }

  function closeForm() {
    setShowForm(false);
    setEditingId(null);
    setForm({
      descricao: "",
      nivel: "I",
      categoria: "montador",
      preco_base: 0,
      preco_50: 0,
      preco_100: 0,
      ativo: true,
    });
  }

  async function save() {
    setOk(null);
    setErr(null);
    if (!canEdit) {
      setErr("Sem permissão para salvar especialidades.");
      return;
    }

    if (!form.descricao.trim()) return setErr("Descrição é obrigatória.");
    if (form.preco_base <= 0) return setErr("Preço base deve ser maior que zero.");

    setBusy(true);

    const payload = {
      descricao: form.descricao.trim(),
      nivel: form.nivel,
      categoria: form.categoria,
      preco_base: Number(form.preco_base),
      preco_50: Number(form.preco_50),
      preco_100: Number(form.preco_100),
      ativo: form.ativo,
      atualizado_em: new Date().toISOString(),
    };

    let error: { message?: string } | null = null;

    if (editingId) {
      const res = await supabase.from("hh_tabela_precos").update(payload).eq("id", editingId);
      error = res.error;
    } else {
      const res = await supabase.from("hh_tabela_precos").insert({ ...payload, criado_em: new Date().toISOString() });
      error = res.error;
    }

    setBusy(false);
    if (error) return setErr(error.message ?? "Erro ao salvar.");

    setOk(editingId ? "Especialidade atualizada!" : "Especialidade criada!");
    closeForm();
    await load();
  }

  async function handleDelete(id: number) {
    if (!canDelete) {
      setErr("Sem permissão para excluir especialidades.");
      return;
    }

    const ok = confirm("Tem certeza que deseja excluir esta especialidade?");
    if (!ok) return;

    setBusy(true);
    setErr(null);
    setOk(null);

    const { error } = await supabase.from("hh_tabela_precos").delete().eq("id", id);

    setBusy(false);
    if (error) return setErr(error.message);

    setOk("Especialidade excluída.");
    await load();
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
          <h1 className="text-2xl font-semibold">Tabela de Preços HH (Global)</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Cadastro de especialidades e preços-base para Homem-Hora. Estes valores serão copiados para cada cliente.
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
              Nova Especialidade
            </button>
          </Can>
        </div>
      </div>

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Buscar por descrição</div>
            <input
              aria-label="Buscar especialidade"
              className="w-full px-3 py-2"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Digite parte da descrição..."
            />
          </div>
          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Categoria</div>
            <select
              aria-label="Filtrar por categoria"
              className="w-full px-3 py-2"
              value={filterCategoria}
              onChange={(e) => setFilterCategoria(e.target.value)}
            >
              <option value="todas">Todas</option>
              <option value="montador">Montador</option>
              <option value="comando">Comando</option>
              <option value="automacao">Automação</option>
              <option value="mecanica">Mecânica</option>
            </select>
          </div>
        </div>

        {err && <div className="text-sm text-red-400 mt-3">{err}</div>}
        {ok && <div className="text-sm text-emerald-300 mt-3">{ok}</div>}
      </div>

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <div className="overflow-auto">
          <table className="w-full text-sm min-w-[900px]">
            <thead className="bg-zinc-900/70">
              <tr className="text-zinc-200">
                <th className="px-4 py-3 text-left">Descrição</th>
                <th className="px-4 py-3 text-center">Nível</th>
                <th className="px-4 py-3 text-center">Categoria</th>
                <th className="px-4 py-3 text-right">Preço Base</th>
                <th className="px-4 py-3 text-right">50%</th>
                <th className="px-4 py-3 text-right">100%</th>
                <th className="px-4 py-3 text-center">Ativo</th>
                <th className="px-4 py-3 text-center">Ações</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {rows.map((r) => (
                <tr key={r.id} className="hover:bg-zinc-900/40">
                  <td className="px-4 py-3 font-medium">{r.descricao}</td>
                  <td className="px-4 py-3 text-center">
                    <span className="inline-flex items-center px-2 py-1 rounded-md border border-zinc-700 bg-zinc-900 text-xs">
                      {r.nivel}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-center capitalize text-zinc-300">{r.categoria}</td>
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-200">
                    R$ {Number(r.preco_base).toFixed(2)}
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-200">
                    R$ {Number(r.preco_50).toFixed(2)}
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums text-zinc-200">
                    R$ {Number(r.preco_100).toFixed(2)}
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
                      <Can perm="os.write">
                        <button
                          onClick={() => startEdit(r)}
                          className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                        >
                          Editar
                        </button>
                      </Can>
                      <Can perm="os.delete">
                        <button
                          onClick={() => handleDelete(r.id)}
                          disabled={busy}
                          className="px-3 py-1.5 rounded-md border border-red-700 bg-red-900/30 hover:bg-red-900/50 text-red-300 disabled:opacity-60"
                        >
                          Excluir
                        </button>
                      </Can>
                    </div>
                  </td>
                </tr>
              ))}

              {rows.length === 0 && (
                <tr>
                  <td colSpan={8} className="px-4 py-6 text-zinc-400">
                    Nenhuma especialidade encontrada.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {showForm && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl">
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
              <div>
                <div className="text-lg font-semibold">
                  {editingId ? "Editar Especialidade" : "Nova Especialidade"}
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
              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Descrição *</div>
                <input
                  aria-label="Descrição"
                  className="w-full px-3 py-2"
                  value={form.descricao}
                  onChange={(e) => setForm((s) => ({ ...s, descricao: e.target.value }))}
                  placeholder="Ex: MAO-DE-OBRA ELETRICISTA MONTADOR HH (NIVEL I)"
                />
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Nível *</div>
                  <select
                    aria-label="Nível"
                    className="w-full px-3 py-2"
                    value={form.nivel}
                    onChange={(e) => setForm((s) => ({ ...s, nivel: e.target.value }))}
                  >
                    <option value="I">Nível I</option>
                    <option value="II">Nível II</option>
                    <option value="III">Nível III</option>
                  </select>
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Categoria *</div>
                  <select
                    aria-label="Categoria"
                    className="w-full px-3 py-2"
                    value={form.categoria}
                    onChange={(e) => setForm((s) => ({ ...s, categoria: e.target.value }))}
                  >
                    <option value="montador">Montador</option>
                    <option value="comando">Comando</option>
                    <option value="automacao">Automação</option>
                    <option value="mecanica">Mecânica</option>
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Preço Base (R$) *</div>
                  <input
                    type="text"
                    inputMode="decimal"
                    aria-label="Preço base"
                    className="w-full px-3 py-2"
                    value={form.preco_base}
                    onChange={(e) => setForm((s) => ({ ...s, preco_base: parseDecimalBR(e.target.value) || 0 }))}
                    placeholder="0,00"
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Preço 50% (R$) *</div>
                  <input
                    type="text"
                    inputMode="decimal"
                    aria-label="Preço 50%"
                    className="w-full px-3 py-2"
                    value={form.preco_50}
                    onChange={(e) => setForm((s) => ({ ...s, preco_50: parseDecimalBR(e.target.value) || 0 }))}
                    placeholder="0,00"
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Preço 100% (R$) *</div>
                  <input
                    type="text"
                    inputMode="decimal"
                    aria-label="Preço 100%"
                    className="w-full px-3 py-2"
                    value={form.preco_100}
                    onChange={(e) => setForm((s) => ({ ...s, preco_100: parseDecimalBR(e.target.value) || 0 }))}
                    placeholder="0,00"
                  />
                </div>
              </div>

              <div className="flex items-center gap-2 pt-2">
                <input
                  type="checkbox"
                  checked={form.ativo}
                  onChange={(e) => setForm((s) => ({ ...s, ativo: e.target.checked }))}
                  id="ativo-check"
                />
                <label htmlFor="ativo-check" className="text-sm text-zinc-200">
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
