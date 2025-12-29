"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "../../lib/supabase/client";

type Fornecedor = { id: number; nome: string; ativo: boolean };

type Item = {
  id: number;
  codigo_interno: string;
  codigo_barras: string | null;
  nome: string;
  descricao: string | null;
  tipo: "produto" | "servico" | "despesa";
  categoria: string | null;
  subcategoria: string | null;

  unidade_medida: string | null;
  controla_estoque: boolean | null;
  estoque_minimo: number | null;
  estoque_maximo: number | null;
  estoque_ideal: number | null;

  custo_ultima_compra: number | null;
  custo_medio: number | null;

  preco_unitario: number | null;

  fornecedor_id: number | null;
  fornecedores?: { nome: string | null } | null;

  ativo: boolean;
  criado_em: string;
  atualizado_em: string;
};

type ItemForm = {
  id?: number;

  codigo_interno: string;
  codigo_barras: string;

  nome: string;
  descricao: string;
  tipo: "produto" | "servico" | "despesa";
  categoria: string;
  subcategoria: string;

  unidade_medida: string;
  controla_estoque: boolean;
  estoque_minimo: number;
  estoque_maximo: number;
  estoque_ideal: number;

  custo_ultima_compra: number;
  custo_medio: number;

  preco_unitario: number;

  fornecedor_id: number | null;

  ativo: boolean;
};

function money(n: number | null | undefined) {
  const v = Number(n ?? 0);
  return `R$ ${v.toFixed(2)}`;
}

function emptyForm(): ItemForm {
  return {
    codigo_interno: "",
    codigo_barras: "",
    nome: "",
    descricao: "",
    tipo: "produto",
    categoria: "",
    subcategoria: "",
    unidade_medida: "UN",
    controla_estoque: true,
    estoque_minimo: 0,
    estoque_maximo: 0,
    estoque_ideal: 0,
    custo_ultima_compra: 0,
    custo_medio: 0,
    preco_unitario: 0,
    fornecedor_id: null,
    ativo: true,
  };
}

export default function ItensPage() {
  const supabase = useMemo(() => supabaseBrowser(), []);

  const [rows, setRows] = useState<Item[]>([]);
  const [fornecedores, setFornecedores] = useState<Fornecedor[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [showForm, setShowForm] = useState(false);

  // filtros
  const [q, setQ] = useState("");
  const [tipo, setTipo] = useState<"todos" | Item["tipo"]>("todos");
  const [ativo, setAtivo] = useState<"todos" | "ativos" | "inativos">("ativos");

  // form (criar/editar)
  const [form, setForm] = useState<ItemForm>(emptyForm());
  const [editingId, setEditingId] = useState<number | null>(null);

  async function loadFornecedores() {
    const { data, error } = await supabase
      .from("fornecedores")
      .select("id,nome,ativo")
      .eq("ativo", true)
      .order("nome", { ascending: true })
      .limit(500);

    if (!error) setFornecedores((data ?? []) as unknown as Fornecedor[]);
  }

  async function load() {
    setErr(null);

    let query = supabase
      .from("itens")
      .select(
        "id,codigo_interno,codigo_barras,nome,descricao,tipo,categoria,subcategoria,unidade_medida,controla_estoque,estoque_minimo,estoque_maximo,estoque_ideal,custo_ultima_compra,custo_medio,preco_unitario,fornecedor_id,fornecedores(nome),ativo,criado_em,atualizado_em"
      )
      .order("id", { ascending: false })
      .limit(300);

    if (tipo !== "todos") query = query.eq("tipo", tipo);
    if (ativo === "ativos") query = query.eq("ativo", true);
    if (ativo === "inativos") query = query.eq("ativo", false);

    const term = q.trim();
    if (term) {
      query = query.or(
        `nome.ilike.%${term}%,codigo_interno.ilike.%${term}%,codigo_barras.ilike.%${term}%`
      );
    }

    const { data, error } = await query;

    if (error) setErr(error.message);
    else setRows((data ?? []) as unknown as Item[]);
  }

  useEffect(() => {
    loadFornecedores();
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tipo, ativo]);

  function startNew() {
    setOk(null);
    setErr(null);
    setEditingId(null);
    setForm(emptyForm());
    setShowForm(true);
  }

  function startEdit(r: Item) {
    setOk(null);
    setErr(null);
    setEditingId(r.id);
    setShowForm(true);

    setForm({
      id: r.id,
      codigo_interno: r.codigo_interno ?? "",
      codigo_barras: r.codigo_barras ?? "",
      nome: r.nome ?? "",
      descricao: r.descricao ?? "",
      tipo: r.tipo,
      categoria: r.categoria ?? "",
      subcategoria: r.subcategoria ?? "",
      unidade_medida: r.unidade_medida ?? "UN",
      controla_estoque: !!r.controla_estoque,
      estoque_minimo: Number(r.estoque_minimo ?? 0),
      estoque_maximo: Number(r.estoque_maximo ?? 0),
      estoque_ideal: Number(r.estoque_ideal ?? 0),
      custo_ultima_compra: Number(r.custo_ultima_compra ?? 0),
      custo_medio: Number(r.custo_medio ?? 0),
      preco_unitario: Number(r.preco_unitario ?? 0),
      fornecedor_id: r.fornecedor_id ?? null,
      ativo: !!r.ativo,
    });
  }

  function closeForm() {
    setShowForm(false);
    setEditingId(null);
    setForm(emptyForm());
  }

  async function save() {
    setOk(null);
    setErr(null);

    if (!form.codigo_interno.trim()) return setErr("Codigo interno e obrigatorio.");
    if (!form.nome.trim()) return setErr("Nome e obrigatorio.");

    const isProduto = form.tipo === "produto";
    const controlaEstoque = isProduto ? form.controla_estoque : false;

    setBusy(true);

    const payload: any = {
      codigo_interno: form.codigo_interno.trim(),
      codigo_barras: form.codigo_barras.trim() || null,
      nome: form.nome.trim(),
      descricao: form.descricao.trim() || null,
      tipo: form.tipo,
      categoria: form.categoria.trim() || null,
      subcategoria: form.subcategoria.trim() || null,

      unidade_medida: (form.unidade_medida || "UN").trim().toUpperCase(),
      controla_estoque: controlaEstoque,
      estoque_minimo: controlaEstoque ? Math.trunc(form.estoque_minimo ?? 0) : 0,
      estoque_maximo: controlaEstoque ? Math.trunc(form.estoque_maximo ?? 0) : 0,
      estoque_ideal: controlaEstoque ? Math.trunc(form.estoque_ideal ?? 0) : 0,

      custo_ultima_compra: Number(form.custo_ultima_compra ?? 0),
      custo_medio: Number(form.custo_medio ?? 0),
      preco_unitario: Number(form.preco_unitario ?? 0),

      fornecedor_id: form.fornecedor_id ?? null,

      ativo: !!form.ativo,
      atualizado_em: new Date().toISOString(),
    };

    if (!isProduto) {
      payload.controla_estoque = false;
      payload.estoque_minimo = 0;
      payload.estoque_maximo = 0;
      payload.estoque_ideal = 0;
    }

    let error: any = null;

    if (editingId) {
      const res = await supabase.from("itens").update(payload).eq("id", editingId);
      error = res.error;
    } else {
      const { data: sess } = await supabase.auth.getSession();
      const userEmail = sess.session?.user?.email ?? null;

      const res = await supabase
        .from("itens")
        .insert({ ...payload, criado_por: userEmail, criado_em: new Date().toISOString() })
        .select("id")
        .single();

      error = res.error;

      if (!error && res.data?.id && isProduto) {
        await supabase.from("estoque").insert({
          item_id: res.data.id,
          quantidade_atual: 0,
          atualizado_em: new Date().toISOString(),
        });
      }
    }

    setBusy(false);

    if (error) {
      const msg = String(error.message || "");
      if (msg.toLowerCase().includes("duplicate") || msg.toLowerCase().includes("unique")) {
        return setErr("Codigo interno ou codigo de barras ja existe. Ajuste e tente novamente.");
      }
      return setErr(msg);
    }

    setOk(editingId ? "Item atualizado!" : "Item criado!");
    await load();
    closeForm();
  }

  async function toggleAtivo(id: number, to: boolean) {
    const ok = confirm(to ? "Ativar item?" : "Desativar item?");
    if (!ok) return;

    setBusy(true);
    setErr(null);
    setOk(null);

    const { error } = await supabase
      .from("itens")
      .update({ ativo: to, atualizado_em: new Date().toISOString() })
      .eq("id", id);

    setBusy(false);
    if (error) return setErr(error.message);

    setOk(to ? "Item ativado." : "Item desativado.");
    await load();
  }

  function fornecedorNome(id: number | null) {
    if (!id) return "--";
    return fornecedores.find((f) => f.id === id)?.nome ?? `#${id}`;
  }

  return (
    <div className="space-y-5 max-w-6xl mx-auto pb-10">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Itens</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Cadastro de produtos, servicos e despesas.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={startNew}
            className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-100 text-zinc-900 hover:bg-white font-medium shadow-sm"
          >
            Novo
          </button>

          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>
        </div>
      </div>

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="grid grid-cols-1 md:grid-cols-[1.2fr_0.9fr_0.7fr_0.7fr] gap-3">
          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Buscar</div>
            <div className="flex gap-2">
              <input
                className="w-full px-3 py-2"
                value={q}
                onChange={(e) => setQ(e.target.value)}
                placeholder="Nome, codigo interno ou codigo de barras"
              />
              <button
                onClick={load}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
              >
                Buscar
              </button>
            </div>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Tipo</div>
            <select className="w-full px-3 py-2" value={tipo} onChange={(e) => setTipo(e.target.value as any)}>
              <option value="todos">Todos</option>
              <option value="produto">Produto</option>
              <option value="servico">Servico</option>
              <option value="despesa">Despesa</option>
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Ativo</div>
            <select className="w-full px-3 py-2" value={ativo} onChange={(e) => setAtivo(e.target.value as any)}>
              <option value="ativos">Ativos</option>
              <option value="inativos">Inativos</option>
              <option value="todos">Todos</option>
            </select>
          </div>
        </div>

        {err && <div className="text-sm text-red-400 mt-3">{err}</div>}
        {ok && <div className="text-sm text-emerald-300 mt-3">{ok}</div>}
      </div>

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950 shadow-sm">
        <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-900/80">
          <div className="text-sm text-zinc-300">Lista de itens</div>
          <div className="text-xs text-zinc-500">Exibindo {rows.length} registro(s)</div>
        </div>
        <div className="overflow-auto max-h-[70vh]">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/70">
              <tr className="text-zinc-200">
                <th className="px-4 py-3 text-left">Codigo</th>
                <th className="px-4 py-3 text-left min-w-[220px]">Nome</th>
                <th className="px-4 py-3 text-left">Tipo</th>
                <th className="px-4 py-3 text-left">Fornecedor</th>
                <th className="px-4 py-3 text-right">Preco</th>
                <th className="px-4 py-3 text-center">Ativo</th>
                <th className="px-4 py-3 text-center">Acoes</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-zinc-800">
              {rows.map((r) => (
                <tr key={r.id} className="hover:bg-zinc-900/40">
                  <td className="px-4 py-3 font-medium whitespace-nowrap">{r.codigo_interno}</td>
                  <td className="px-4 py-3 align-top">
                    <div className="font-medium">{r.nome}</div>
                    {r.categoria && (
                      <div className="text-xs text-zinc-400">
                        {r.categoria}{r.subcategoria ? ` / ${r.subcategoria}` : ""}
                      </div>
                    )}
                  </td>
                  <td className="px-4 py-3 text-zinc-300 capitalize">{r.tipo}</td>
                  <td className="px-4 py-3 text-zinc-300">{r.fornecedores?.nome ?? fornecedorNome(r.fornecedor_id)}</td>
                  <td className="px-4 py-3 text-right tabular-nums whitespace-nowrap">{money(r.preco_unitario)}</td>
                  <td className="px-4 py-3 text-center">{r.ativo ? "Sim" : "Nao"}</td>
                  <td className="px-4 py-3 text-center">
                    <div className="flex items-center justify-center gap-2">
                      <button onClick={() => startEdit(r)} className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800">
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
                  <td colSpan={7} className="px-4 py-6 text-zinc-400">
                    Nenhum item encontrado.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {showForm && (
        <div className="fixed inset-0 z-40 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4" onClick={(e) => e.target === e.currentTarget && closeForm()}>
          <div className="w-full max-w-4xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden animate-[fadeIn_150ms_ease-out]" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div>
                <div className="font-semibold">{editingId ? `Editar item #${editingId}` : "Novo item"}</div>
                <div className="text-xs text-zinc-400 mt-0.5">Preencha os campos e salve para registrar.</div>
              </div>
              <div className="flex items-center gap-2">
                <button onClick={closeForm} className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800">
                  Cancelar
                </button>
                <button
                  onClick={save}
                  disabled={busy}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60 disabled:cursor-not-allowed"
                >
                  {busy ? "Salvando..." : "Salvar"}
                </button>
              </div>
            </div>

            <div className="p-5 space-y-4 max-h-[75vh] overflow-y-auto">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Codigo interno *</div>
                  <input className="w-full px-3 py-2" value={form.codigo_interno} onChange={(e) => setForm((s) => ({ ...s, codigo_interno: e.target.value }))} />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Codigo de barras</div>
                  <input className="w-full px-3 py-2" value={form.codigo_barras} onChange={(e) => setForm((s) => ({ ...s, codigo_barras: e.target.value }))} />
                </div>

                <div className="md:col-span-2 space-y-1">
                  <div className="text-xs text-zinc-400">Nome *</div>
                  <input className="w-full px-3 py-2" value={form.nome} onChange={(e) => setForm((s) => ({ ...s, nome: e.target.value }))} />
                </div>

                <div className="md:col-span-2 space-y-1">
                  <div className="text-xs text-zinc-400">Fornecedor</div>
                  <select
                    className="w-full px-3 py-2"
                    value={form.fornecedor_id ?? ""}
                    onChange={(e) => setForm((s) => ({ ...s, fornecedor_id: e.target.value ? Number(e.target.value) : null }))}
                  >
                    <option value="">--</option>
                    {fornecedores.map((f) => (
                      <option key={f.id} value={f.id}>
                        {f.nome}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="md:col-span-2 space-y-1">
                  <div className="text-xs text-zinc-400">Descricao</div>
                  <textarea className="w-full px-3 py-2 min-h-[70px]" value={form.descricao} onChange={(e) => setForm((s) => ({ ...s, descricao: e.target.value }))} />
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Tipo *</div>
                  <select
                    className="w-full px-3 py-2"
                    value={form.tipo}
                    onChange={(e) =>
                      setForm((s) => {
                        const t = e.target.value as ItemForm["tipo"];
                        return { ...s, tipo: t, controla_estoque: t === "produto" ? s.controla_estoque : false };
                      })
                    }
                  >
                    <option value="produto">Produto</option>
                    <option value="servico">Servico</option>
                    <option value="despesa">Despesa</option>
                  </select>
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Unidade</div>
                  <input className="w-full px-3 py-2" value={form.unidade_medida} onChange={(e) => setForm((s) => ({ ...s, unidade_medida: e.target.value }))} placeholder="UN, KG, LT..." />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Categoria</div>
                  <input className="w-full px-3 py-2" value={form.categoria} onChange={(e) => setForm((s) => ({ ...s, categoria: e.target.value }))} />
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Subcategoria</div>
                  <input className="w-full px-3 py-2" value={form.subcategoria} onChange={(e) => setForm((s) => ({ ...s, subcategoria: e.target.value }))} />
                </div>

                <div className="space-y-1 md:col-span-2">
                  <div className="text-xs text-zinc-400 flex items-center justify-between">
                    <span>Estoque</span>
                    <label className="text-xs text-zinc-300 flex items-center gap-2">
                      <input
                        type="checkbox"
                        checked={form.tipo === "produto" ? form.controla_estoque : false}
                        disabled={form.tipo !== "produto"}
                        onChange={(e) => setForm((s) => ({ ...s, controla_estoque: e.target.checked }))}
                      />
                      Controla estoque
                    </label>
                  </div>

                  <div className="grid grid-cols-3 gap-2 mt-2">
                    <div className="space-y-1">
                      <div className="text-[11px] text-zinc-400">Minimo</div>
                      <input type="number" className="w-full px-3 py-2" value={form.estoque_minimo} disabled={form.tipo !== "produto" || !form.controla_estoque} onChange={(e) => setForm((s) => ({ ...s, estoque_minimo: Number(e.target.value) }))} />
                    </div>
                    <div className="space-y-1">
                      <div className="text-[11px] text-zinc-400">Ideal</div>
                      <input type="number" className="w-full px-3 py-2" value={form.estoque_ideal} disabled={form.tipo !== "produto" || !form.controla_estoque} onChange={(e) => setForm((s) => ({ ...s, estoque_ideal: Number(e.target.value) }))} />
                    </div>
                    <div className="space-y-1">
                      <div className="text-[11px] text-zinc-400">Maximo</div>
                      <input type="number" className="w-full px-3 py-2" value={form.estoque_maximo} disabled={form.tipo !== "produto" || !form.controla_estoque} onChange={(e) => setForm((s) => ({ ...s, estoque_maximo: Number(e.target.value) }))} />
                    </div>
                  </div>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Custo ultima compra</div>
                  <input type="number" className="w-full px-3 py-2" value={form.custo_ultima_compra} onChange={(e) => setForm((s) => ({ ...s, custo_ultima_compra: Number(e.target.value) }))} />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Custo medio</div>
                  <input type="number" className="w-full px-3 py-2" value={form.custo_medio} onChange={(e) => setForm((s) => ({ ...s, custo_medio: Number(e.target.value) }))} />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Preco unitario</div>
                  <input type="number" className="w-full px-3 py-2" value={form.preco_unitario} onChange={(e) => setForm((s) => ({ ...s, preco_unitario: Number(e.target.value) }))} />
                </div>
              </div>

              <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-3 border border-zinc-800 rounded-lg p-3">
                <div className="text-sm">
                  <div className="font-medium">Status do item</div>
                  <div className="text-xs text-zinc-400">Desativar nao apaga, so oculta do uso.</div>
                </div>

                <label className="text-sm text-zinc-300 flex items-center gap-2">
                  <input type="checkbox" checked={form.ativo} onChange={(e) => setForm((s) => ({ ...s, ativo: e.target.checked }))} />
                  Ativo
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
