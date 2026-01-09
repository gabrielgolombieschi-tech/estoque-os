"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "../../lib/supabase/client";
import { parseDecimalBR } from "../../lib/decimal";
import { getCurrentTenantId } from "@/lib/auth/tenant";

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
  fiscal_itens?: FiscalItem | null;

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

type FiscalItem = {
  item_id: number;
  ncm: string | null;
  cst_icms: string | null;
  cst_pis: string | null;
  cst_cofins: string | null;
  aliq_icms: number | null;
  aliq_ipi: number | null;
  aliq_pis: number | null;
  aliq_cofins: number | null;
  credita_icms: boolean;
  ipi_entra_no_custo: boolean;
  credita_pis: boolean;
  credita_cofins: boolean;
};

type FiscalForm = {
  ncm: string;
  cst_icms: string;
  cst_pis: string;
  cst_cofins: string;
  aliq_icms: number | null;
  aliq_ipi: number | null;
  aliq_pis: number | null;
  aliq_cofins: number | null;
  credita_icms: boolean;
  ipi_entra_no_custo: boolean;
  credita_pis: boolean;
  credita_cofins: boolean;
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

function emptyFiscalForm(): FiscalForm {
  return {
    ncm: "",
    cst_icms: "",
    cst_pis: "",
    cst_cofins: "",
    aliq_icms: null,
    aliq_ipi: null,
    aliq_pis: null,
    aliq_cofins: null,
    credita_icms: false,
    ipi_entra_no_custo: true,
    credita_pis: false,
    credita_cofins: false,
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
  const [activeTab, setActiveTab] = useState<"geral" | "fiscal">("geral");

  // filtros
  const [q, setQ] = useState("");
  const [tipo, setTipo] = useState<"todos" | Item["tipo"]>("todos");
  const [ativo, setAtivo] = useState<"todos" | "ativos" | "inativos">("ativos");

  // form (criar/editar)
  const [form, setForm] = useState<ItemForm>(emptyForm());
  const [fiscalForm, setFiscalForm] = useState<FiscalForm>(emptyFiscalForm());
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
        "id,codigo_interno,codigo_barras,nome,descricao,tipo,categoria,subcategoria,unidade_medida,controla_estoque,estoque_minimo,estoque_maximo,estoque_ideal,custo_ultima_compra,custo_medio,preco_unitario,fornecedor_id,fornecedores(nome),fiscal_itens(ncm,cst_icms,cst_pis,cst_cofins,aliq_icms,aliq_ipi,aliq_pis,aliq_cofins,credita_icms,ipi_entra_no_custo,credita_pis,credita_cofins),ativo,criado_em,atualizado_em"
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
    setFiscalForm(emptyFiscalForm());
    setActiveTab("geral");
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
    const fiscal = r.fiscal_itens;
    setFiscalForm({
      ncm: fiscal?.ncm ?? "",
      cst_icms: fiscal?.cst_icms ?? "",
      cst_pis: fiscal?.cst_pis ?? "",
      cst_cofins: fiscal?.cst_cofins ?? "",
      aliq_icms: fiscal?.aliq_icms ?? null,
      aliq_ipi: fiscal?.aliq_ipi ?? null,
      aliq_pis: fiscal?.aliq_pis ?? null,
      aliq_cofins: fiscal?.aliq_cofins ?? null,
      credita_icms: !!fiscal?.credita_icms,
      ipi_entra_no_custo: fiscal?.ipi_entra_no_custo ?? true,
      credita_pis: !!fiscal?.credita_pis,
      credita_cofins: !!fiscal?.credita_cofins,
    });
    setActiveTab("geral");
  }

  function closeForm() {
    setShowForm(false);
    setEditingId(null);
    setForm(emptyForm());
    setFiscalForm(emptyFiscalForm());
    setActiveTab("geral");
  }

  async function saveFiscal(itemId: number) {
    const numOrNull = (v: number | null | undefined) => (Number.isFinite(v as number) ? Number(v) : null);
    const payload: any = {
      item_id: itemId,
      ncm: fiscalForm.ncm.trim() || null,
      cst_icms: fiscalForm.cst_icms.trim() || null,
      cst_pis: fiscalForm.cst_pis.trim() || null,
      cst_cofins: fiscalForm.cst_cofins.trim() || null,
      aliq_icms: numOrNull(fiscalForm.aliq_icms),
      aliq_ipi: numOrNull(fiscalForm.aliq_ipi),
      aliq_pis: numOrNull(fiscalForm.aliq_pis),
      aliq_cofins: numOrNull(fiscalForm.aliq_cofins),
      credita_icms: !!fiscalForm.credita_icms,
      ipi_entra_no_custo: fiscalForm.ipi_entra_no_custo,
      credita_pis: !!fiscalForm.credita_pis,
      credita_cofins: !!fiscalForm.credita_cofins,
      updated_at: new Date().toISOString(),
    };
    const { error } = await supabase.from("fiscal_itens").upsert(payload, { onConflict: "item_id" });
    return error;
  }

  async function save() {
    setOk(null);
    setErr(null);

    if (!form.codigo_interno.trim()) return setErr("C?digo interno e obrigatorio.");
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
      estoque_minimo: controlaEstoque ? Number(form.estoque_minimo ?? 0) : 0,
      estoque_maximo: controlaEstoque ? Number(form.estoque_maximo ?? 0) : 0,
      estoque_ideal: controlaEstoque ? Number(form.estoque_ideal ?? 0) : 0,

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
    let itemId: number | null = editingId ?? null;

    if (editingId) {
      const res = await supabase.from("itens").update(payload).eq("id", editingId);
      error = res.error;
    } else {
      let tenant_id = "";
      try {
        tenant_id = await getCurrentTenantId();
      } catch (e: any) {
        setBusy(false);
        setErr(e?.message ?? "Erro ao identificar tenant.");
        return;
      }

      const { data: sess } = await supabase.auth.getSession();
      const userEmail = sess.session?.user?.email ?? null;

      const res = await supabase
        .from("itens")
        .insert({ ...payload, tenant_id, criado_por: userEmail, criado_em: new Date().toISOString() })
        .select("id")
        .single();

      error = res.error;
      itemId = res.data?.id ?? null;

      if (!error && res.data?.id && isProduto) {
        const { error: estoqueErr } = await supabase.rpc("ensure_estoque_rows", {
          p_tenant_id: tenant_id,
          p_item_ids: [res.data.id],
        });
        if (estoqueErr) {
          setBusy(false);
          return setErr(estoqueErr.message);
        }
      }
    }

    setBusy(false);

    if (error) {
      const msg = String(error.message || "");
      if (msg.toLowerCase().includes("duplicate") || msg.toLowerCase().includes("unique")) {
        setBusy(false);
        return setErr("C?digo interno ou codigo de barras ja existe. Ajuste e tente novamente.");
      }
      setBusy(false);
      return setErr(msg);
    }

    if (!itemId) {
      setBusy(false);
      return setErr("Falha ao salvar: id do item nao retornado.");
    }

    const fiscalError = await saveFiscal(itemId);
    if (fiscalError) {
      setBusy(false);
      return setErr(fiscalError.message);
    }

    setBusy(false);
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
    <div className="space-y-5 w-full pb-10">
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
                placeholder="Nome, c?digo interno ou c?digo de barras"
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
              <option value="servico">Serviço</option>
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
                <th className="px-4 py-3 text-left w-16">ID</th>
                <th className="px-4 py-3 text-left">Código</th>
                <th className="px-4 py-3 text-left min-w-[220px]">Nome</th>
                <th className="px-4 py-3 text-left">Tipo</th>
                <th className="px-4 py-3 text-left">Fornecedor</th>
                <th className="px-4 py-3 text-right">Pre?o</th>
                <th className="px-4 py-3 text-center">Ativo</th>
                <th className="px-4 py-3 text-center">A??es</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-zinc-800">
              {rows.map((r) => (
                <tr key={r.id} className="hover:bg-zinc-900/40">
                  <td className="px-4 py-3 font-medium whitespace-nowrap text-zinc-400 tabular-nums">{r.id}</td>
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
                  <td className="px-4 py-3 text-center">{r.ativo ? "Sim" : "N?o"}</td>
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
              <div className="flex items-center gap-2 border-b border-zinc-800 pb-2">
                <button
                  className={`px-3 py-1.5 rounded-md text-sm ${activeTab === "geral" ? "bg-zinc-800 text-zinc-100" : "text-zinc-400 hover:text-zinc-100"}`}
                  onClick={() => setActiveTab("geral")}
                >
                  Dados gerais
                </button>
                <button
                  className={`px-3 py-1.5 rounded-md text-sm ${activeTab === "fiscal" ? "bg-zinc-800 text-zinc-100" : "text-zinc-400 hover:text-zinc-100"}`}
                  onClick={() => setActiveTab("fiscal")}
                >
                  Fiscal
                </button>
              </div>

              {activeTab === "geral" ? (
                <>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">C?digo interno *</div>
                      <input className="w-full px-3 py-2" value={form.codigo_interno} onChange={(e) => setForm((s) => ({ ...s, codigo_interno: e.target.value }))} />
                    </div>

                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">C?digo de barras</div>
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
                      <div className="text-xs text-zinc-400">Descri??o</div>
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
                        <option value="servico">Servi?oo</option>
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
                          <input
                            type="text"
                            inputMode="decimal"
                            className="w-full px-3 py-2"
                            value={form.estoque_minimo}
                            disabled={form.tipo !== "produto" || !form.controla_estoque}
                            onChange={(e) => setForm((s) => ({ ...s, estoque_minimo: parseDecimalBR(e.target.value) || 0 }))}
                          />
                        </div>
                        <div className="space-y-1">
                          <div className="text-[11px] text-zinc-400">Ideal</div>
                          <input
                            type="text"
                            inputMode="decimal"
                            className="w-full px-3 py-2"
                            value={form.estoque_ideal}
                            disabled={form.tipo !== "produto" || !form.controla_estoque}
                            onChange={(e) => setForm((s) => ({ ...s, estoque_ideal: parseDecimalBR(e.target.value) || 0 }))}
                          />
                        </div>
                        <div className="space-y-1">
                          <div className="text-[11px] text-zinc-400">Maximo</div>
                          <input
                            type="text"
                            inputMode="decimal"
                            className="w-full px-3 py-2"
                            value={form.estoque_maximo}
                            disabled={form.tipo !== "produto" || !form.controla_estoque}
                            onChange={(e) =>
                              setForm((s) => ({ ...s, estoque_maximo: parseDecimalBR(e.target.value) || 0 }))
                            }
                          />
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
                      <div className="text-xs text-zinc-400">Pre?o unit?rio</div>
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
                </>
              ) : (
                <div className="space-y-4">
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">NCM</div>
                      <input className="w-full px-3 py-2" value={fiscalForm.ncm} onChange={(e) => setFiscalForm((s) => ({ ...s, ncm: e.target.value }))} placeholder="Ex: 12345678" />
                    </div>
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">CST ICMS</div>
                      <input className="w-full px-3 py-2" value={fiscalForm.cst_icms} onChange={(e) => setFiscalForm((s) => ({ ...s, cst_icms: e.target.value }))} placeholder="00, 20, 40..." />
                    </div>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">CST PIS</div>
                      <input className="w-full px-3 py-2" value={fiscalForm.cst_pis} onChange={(e) => setFiscalForm((s) => ({ ...s, cst_pis: e.target.value }))} placeholder="01, 99..." />
                    </div>
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">CST COFINS</div>
                      <input className="w-full px-3 py-2" value={fiscalForm.cst_cofins} onChange={(e) => setFiscalForm((s) => ({ ...s, cst_cofins: e.target.value }))} placeholder="01, 99..." />
                    </div>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Aliquota ICMS (%)</div>
                      <input
                        className="w-full px-3 py-2"
                        inputMode="decimal"
                        value={fiscalForm.aliq_icms ?? ""}
                        onChange={(e) => {
                          const v = parseDecimalBR(e.target.value);
                          setFiscalForm((s) => ({ ...s, aliq_icms: Number.isFinite(v) ? v : null }));
                        }}
                      />
                    </div>
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Aliquota IPI (%)</div>
                      <input
                        className="w-full px-3 py-2"
                        inputMode="decimal"
                        value={fiscalForm.aliq_ipi ?? ""}
                        onChange={(e) => {
                          const v = parseDecimalBR(e.target.value);
                          setFiscalForm((s) => ({ ...s, aliq_ipi: Number.isFinite(v) ? v : null }));
                        }}
                      />
                    </div>
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Aliquota PIS (%)</div>
                      <input
                        className="w-full px-3 py-2"
                        inputMode="decimal"
                        value={fiscalForm.aliq_pis ?? ""}
                        onChange={(e) => {
                          const v = parseDecimalBR(e.target.value);
                          setFiscalForm((s) => ({ ...s, aliq_pis: Number.isFinite(v) ? v : null }));
                        }}
                      />
                    </div>
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Aliquota COFINS (%)</div>
                      <input
                        className="w-full px-3 py-2"
                        inputMode="decimal"
                        value={fiscalForm.aliq_cofins ?? ""}
                        onChange={(e) => {
                          const v = parseDecimalBR(e.target.value);
                          setFiscalForm((s) => ({ ...s, aliq_cofins: Number.isFinite(v) ? v : null }));
                        }}
                      />
                    </div>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3 border border-zinc-800 rounded-lg p-3">
                    <div className="space-y-2">
                      <div className="text-sm font-medium text-zinc-200">Credita impostos</div>
                      <label className="flex items-center gap-2 text-sm">
                        <input type="checkbox" checked={fiscalForm.credita_icms} onChange={(e) => setFiscalForm((s) => ({ ...s, credita_icms: e.target.checked }))} />
                        ICMS
                      </label>
                      <label className="flex items-center gap-2 text-sm">
                        <input type="checkbox" checked={fiscalForm.credita_pis} onChange={(e) => setFiscalForm((s) => ({ ...s, credita_pis: e.target.checked }))} />
                        PIS
                      </label>
                      <label className="flex items-center gap-2 text-sm">
                        <input type="checkbox" checked={fiscalForm.credita_cofins} onChange={(e) => setFiscalForm((s) => ({ ...s, credita_cofins: e.target.checked }))} />
                        COFINS
                      </label>
                    </div>
                    <div className="space-y-2">
                      <div className="text-sm font-medium text-zinc-200">Custo</div>
                      <label className="flex items-center gap-2 text-sm">
                        <input type="checkbox" checked={fiscalForm.ipi_entra_no_custo} onChange={(e) => setFiscalForm((s) => ({ ...s, ipi_entra_no_custo: e.target.checked }))} />
                        IPI entra no custo
                      </label>
                    </div>
                  </div>
                </div>
              )}

              {err && <div className="text-sm text-red-400">{err}</div>}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
