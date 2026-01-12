"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "../../lib/supabase/client";

type Cliente = {
  id: number;
  nome: string;
  documento: string | null;
  email: string | null;
  telefone: string | null;
  endereco: string | null;
  observacoes: string | null;
  ativo: boolean;
};

type Form = {
  nome: string;
  documento: string;
  email: string;
  telefone: string;
  endereco: string;
  observacoes: string;
  ativo: boolean;
};

type ClientePayload = {
  nome: string;
  documento: string | null;
  email: string | null;
  telefone: string | null;
  endereco: string | null;
  observacoes: string | null;
  ativo: boolean;
  atualizado_em: string;
};

type DbError = { message?: string } | null;

function emptyForm(): Form {
  return {
    nome: "",
    documento: "",
    email: "",
    telefone: "",
    endereco: "",
    observacoes: "",
    ativo: true,
  };
}

export default function ClientesPage() {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [rows, setRows] = useState<Cliente[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [q, setQ] = useState("");
  const [ativo, setAtivo] = useState<"ativos" | "inativos" | "todos">("ativos");

  const [editingId, setEditingId] = useState<number | null>(null);
  const [form, setForm] = useState<Form>(emptyForm());

  async function load() {
    setErr(null);

    const { data, error } = await supabase
      .from("clientes")
      .select("id,nome,documento,email,telefone,endereco,observacoes,ativo")
      .order("id", { ascending: false })
      .limit(500);

    if (error) return setErr(error.message);

    let list = (data ?? []) as unknown as Cliente[];

    const term = q.trim().toLowerCase();
    if (term) {
      list = list.filter((r) => {
        const nome = (r.nome ?? "").toLowerCase();
        const doc = (r.documento ?? "").toLowerCase();
        return nome.includes(term) || doc.includes(term);
      });
    }

    if (ativo === "ativos") list = list.filter((r) => r.ativo);
    if (ativo === "inativos") list = list.filter((r) => !r.ativo);

    setRows(list);
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ativo]);

  function novo() {
    setEditingId(null);
    setForm(emptyForm());
    setErr(null);
    setOk(null);
  }

  function editar(r: Cliente) {
    setEditingId(r.id);
    setForm({
      nome: r.nome ?? "",
      documento: r.documento ?? "",
      email: r.email ?? "",
      telefone: r.telefone ?? "",
      endereco: r.endereco ?? "",
      observacoes: r.observacoes ?? "",
      ativo: !!r.ativo,
    });
    setErr(null);
    setOk(null);
  }

  async function salvar() {
    setErr(null);
    setOk(null);

    if (!form.nome.trim()) return setErr("Nome obrigatorio.");

    setBusy(true);

    const payload: ClientePayload = {
      nome: form.nome.trim(),
      documento: form.documento.trim() || null,
      email: form.email.trim() || null,
      telefone: form.telefone.trim() || null,
      endereco: form.endereco.trim() || null,
      observacoes: form.observacoes.trim() || null,
      ativo: !!form.ativo,
      atualizado_em: new Date().toISOString(),
    };

    let error: DbError = null;

    if (editingId) {
      const res = await supabase.from("clientes").update(payload).eq("id", editingId);
      error = res.error ?? null;
    } else {
      const res = await supabase.from("clientes").insert(payload);
      error = res.error ?? null;
    }

    setBusy(false);

    if (error) return setErr(error.message ?? "Erro ao salvar cliente.");

    setOk(editingId ? "Cliente atualizado!" : "Cliente criado!");
    await load();
    if (!editingId) novo();
  }

  async function toggleAtivo(id: number, to: boolean) {
    const ok = confirm(to ? "Ativar cliente?" : "Desativar cliente?");
    if (!ok) return;

    setBusy(true);
    setErr(null);
    setOk(null);

    const { error } = await supabase
      .from("clientes")
      .update({ ativo: to, atualizado_em: new Date().toISOString() })
      .eq("id", id);

    setBusy(false);
    if (error) return setErr(error.message);

    setOk(to ? "Cliente ativado." : "Cliente desativado.");
    await load();
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Clientes</h1>
          <p className="text-sm text-zinc-400 mt-1">Cadastro e gerenciamento de clientes.</p>
        </div>
        <div className="flex gap-2">
          <button onClick={novo} className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800">
            Novo
          </button>
          <button onClick={load} className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800">
            Atualizar
          </button>
        </div>
      </div>

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="grid grid-cols-1 md:grid-cols-5 gap-3">
          <div className="md:col-span-3 space-y-1">
            <div className="text-xs text-zinc-400">Buscar</div>
            <input className="w-full px-3 py-2" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Nome ou CPF/CNPJ" />
          </div>
          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Status</div>
            <select
              className="w-full px-3 py-2"
              value={ativo}
              onChange={(e) => setAtivo(e.target.value as "ativos" | "inativos" | "todos")}
            >
              <option value="ativos">Ativos</option>
              <option value="inativos">Inativos</option>
              <option value="todos">Todos</option>
            </select>
          </div>
          <div className="flex items-end">
            <button onClick={load} className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 w-full">
              Aplicar
            </button>
          </div>
        </div>

        {err && <div className="text-sm text-red-400 mt-3">{err}</div>}
        {ok && <div className="text-sm text-emerald-300 mt-3">{ok}</div>}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-5 gap-4">
        <div className="lg:col-span-2 border border-zinc-800 rounded-xl p-4 bg-zinc-950">
          <div className="flex items-center justify-between">
            <div className="font-medium">{editingId ? `Editar cliente #${editingId}` : "Novo cliente"}</div>
            <button
              onClick={salvar}
              disabled={busy}
              className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
            >
              {busy ? "Salvando..." : "Salvar"}
            </button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3 mt-4">
            <div className="md:col-span-2 space-y-1">
              <div className="text-xs text-zinc-400">Nome *</div>
              <input className="w-full px-3 py-2" value={form.nome} onChange={(e) => setForm((s) => ({ ...s, nome: e.target.value }))} />
            </div>
            <div className="space-y-1">
              <div className="text-xs text-zinc-400">CPF/CNPJ</div>
              <input className="w-full px-3 py-2" value={form.documento} onChange={(e) => setForm((s) => ({ ...s, documento: e.target.value }))} />
            </div>
            <div className="space-y-1">
              <div className="text-xs text-zinc-400">Telefone</div>
              <input className="w-full px-3 py-2" value={form.telefone} onChange={(e) => setForm((s) => ({ ...s, telefone: e.target.value }))} />
            </div>
            <div className="md:col-span-2 space-y-1">
              <div className="text-xs text-zinc-400">Email</div>
              <input className="w-full px-3 py-2" value={form.email} onChange={(e) => setForm((s) => ({ ...s, email: e.target.value }))} />
            </div>
            <div className="md:col-span-2 space-y-1">
              <div className="text-xs text-zinc-400">Endereço</div>
              <input className="w-full px-3 py-2" value={form.endereco} onChange={(e) => setForm((s) => ({ ...s, endereco: e.target.value }))} />
            </div>
            <div className="md:col-span-2 space-y-1">
              <div className="text-xs text-zinc-400">Observações</div>
              <textarea className="w-full px-3 py-2 min-h-[70px]" value={form.observacoes} onChange={(e) => setForm((s) => ({ ...s, observacoes: e.target.value }))} />
            </div>

            <div className="md:col-span-2 flex items-center justify-between border border-zinc-800 rounded-lg p-3">
              <div className="text-sm">
                <div className="font-medium">Status</div>
                <div className="text-xs text-zinc-400">Desativar não apaga, só oculta.</div>
              </div>
              <label className="text-sm text-zinc-300 flex items-center gap-2">
                <input type="checkbox" checked={form.ativo} onChange={(e) => setForm((s) => ({ ...s, ativo: e.target.checked }))} />
                Ativo
              </label>
            </div>
          </div>
        </div>

        <div className="lg:col-span-3 border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/70">
              <tr className="text-zinc-200">
                <th className="px-4 py-3 text-left">Nome</th>
                <th className="px-4 py-3 text-left">Doc</th>
                <th className="px-4 py-3 text-left">Contato</th>
                <th className="px-4 py-3 text-center">Ativo</th>
                <th className="px-4 py-3 text-center">Ações</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {rows.map((r) => (
                <tr key={r.id} className="hover:bg-zinc-900/40">
                  <td className="px-4 py-3 font-medium">{r.nome}</td>
                  <td className="px-4 py-3 text-zinc-300">{r.documento ?? "—"}</td>
                  <td className="px-4 py-3 text-zinc-300">
                    <div>{r.telefone ?? "—"}</div>
                    <div className="text-xs text-zinc-400">{r.email ?? ""}</div>
                  </td>
                  <td className="px-4 py-3 text-center">{r.ativo ? "✅" : "—"}</td>
                  <td className="px-4 py-3 text-center">
                    <div className="flex items-center justify-center gap-2">
                      <button onClick={() => editar(r)} className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800">
                        Editar
                      </button>
                      <button onClick={() => toggleAtivo(r.id, !r.ativo)} className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800">
                        {r.ativo ? "Desativar" : "Ativar"}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}

              {rows.length === 0 && (
                <tr>
                  <td colSpan={5} className="px-4 py-6 text-zinc-400">
                    Nenhum cliente encontrado.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
