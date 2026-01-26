"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { formatDecimalBR } from "@/lib/decimal";

type CaixaStatus = "DISPONIVEL" | "COM_COLABORADOR" | "MANUTENCAO" | "BAIXADA";
const CAIXA_STATUS: CaixaStatus[] = ["DISPONIVEL", "COM_COLABORADOR", "MANUTENCAO", "BAIXADA"];

type CaixaRow = {
  id: string;
  codigo: string;
  nome: string;
  status: CaixaStatus;
  localizacao: string | null;
  ativo: boolean;
  updated_at: string;
};

type CaixaForm = {
  id?: string;
  codigo: string;
  nome: string;
  status: CaixaStatus;
  localizacao: string;
  ativo: boolean;
};

type VinculoRow = {
  id: string;
  caixa_id: string;
  colaborador_id: string;
  data_inicio: string;
  data_fim: string | null;
};

type ColaboradorRow = { id: string; nome: string; ativo: boolean };

type CaixaItemRow = { id: string; caixa_id: string; ferramenta_id: string; quantidade: number };
type FerramentaMini = { id: string; codigo: string; nome: string; unidade: string | null; ativo: boolean };
type CaixaCustoRow = { caixa_id: string; custo_total: number | null };

function emptyCaixaForm(): CaixaForm {
  return { codigo: "", nome: "", status: "DISPONIVEL", localizacao: "", ativo: true };
}

function upperText(value: string) {
  return value.trim().toUpperCase();
}

export default function FerramentasCaixasPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

  const { tenantId, empresaId, loading: tenantEmpresaLoading, error: tenantEmpresaError } = useTenantEmpresa();
  const { has, loading: permissionsLoading, ready } = usePermissions();
  const canView = has("estoque.read") === true || has("estoque.write") === true || has("admin.manage_users") === true;
  const canEdit = has("estoque.write") === true || has("admin.manage_users") === true;

  const [rows, setRows] = useState<CaixaRow[]>([]);
  const [activeVinculoByCaixa, setActiveVinculoByCaixa] = useState<Record<string, VinculoRow>>({});
  const [colaboradorById, setColaboradorById] = useState<Record<string, ColaboradorRow>>({});
  const [itemCountByCaixa, setItemCountByCaixa] = useState<Record<string, number>>({});
  const [custoTotalByCaixa, setCustoTotalByCaixa] = useState<Record<string, number>>({});
  const [colaboradoresList, setColaboradoresList] = useState<ColaboradorRow[]>([]);

  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const [q, setQ] = useState("");
  const [status, setStatus] = useState<CaixaStatus | "TODOS">("TODOS");
  const [colaboradorFiltro, setColaboradorFiltro] = useState<string>("TODOS"); // TODOS | SEM | <id>

  const [modal, setModal] = useState<null | "caixaForm" | "itens" | "vincular">(null);
  const [activeCaixa, setActiveCaixa] = useState<CaixaRow | null>(null);
  const [caixaForm, setCaixaForm] = useState<CaixaForm>(emptyCaixaForm());

  const [itensBusy, setItensBusy] = useState(false);
  const [itensRows, setItensRows] = useState<CaixaItemRow[]>([]);
  const [itensFerrById, setItensFerrById] = useState<Record<string, FerramentaMini>>({});
  const [addFerrBusca, setAddFerrBusca] = useState("");
  const [addFerrResultados, setAddFerrResultados] = useState<FerramentaMini[]>([]);
  const [addFerrSelecionada, setAddFerrSelecionada] = useState<FerramentaMini | null>(null);
  const [addQuantidade, setAddQuantidade] = useState<string>("1");

  const [vinculoColaboradorId, setVinculoColaboradorId] = useState<string>("");
  const [vinculoObs, setVinculoObs] = useState<string>("");

  async function loadColaboradores() {
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) return;
    const { data, error } = await applyTenantEmpresa(
      supabase.from("colaboradores").select("id,nome,ativo").eq("ativo", true).order("nome", { ascending: true }),
      tenantId,
      empresaId
    );
    if (error) return;
    setColaboradoresList((data ?? []) as unknown as ColaboradorRow[]);
  }

  async function load() {
    setErr(null);
    setOk(null);
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) return;

    setBusy(true);
    const { data: caixasData, error: caixasErr } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_caixa")
        .select("id,codigo,nome,status,localizacao,ativo,updated_at")
        .is("deleted_at", null),
      tenantId,
      empresaId
    ).order("codigo", { ascending: true });

    if (caixasErr) {
      setBusy(false);
      return setErr(caixasErr.message);
    }

    const caixas = (caixasData ?? []) as unknown as CaixaRow[];
    setRows(caixas);

    const caixaIds = caixas.map((c) => c.id);
    if (!caixaIds.length) {
      setActiveVinculoByCaixa({});
      setColaboradorById({});
      setItemCountByCaixa({});
      setCustoTotalByCaixa({});
      setBusy(false);
      return;
    }

    const { data: vinculosData, error: vinculosErr } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_caixa_vinculo")
        .select("id,caixa_id,colaborador_id,data_inicio,data_fim")
        .is("deleted_at", null)
        .is("data_fim", null)
        .in("caixa_id", caixaIds),
      tenantId,
      empresaId
    );
    if (vinculosErr) {
      setBusy(false);
      return setErr(vinculosErr.message);
    }

    const vinculos = (vinculosData ?? []) as unknown as VinculoRow[];
    const vincMap: Record<string, VinculoRow> = {};
    vinculos.forEach((v) => (vincMap[v.caixa_id] = v));
    setActiveVinculoByCaixa(vincMap);

    const colaboradorIds = Array.from(new Set(vinculos.map((v) => v.colaborador_id)));
    if (colaboradorIds.length) {
      const { data: colsData, error: colsErr } = await applyTenantEmpresa(
        supabase.from("colaboradores").select("id,nome,ativo").in("id", colaboradorIds),
        tenantId,
        empresaId
      );
      if (colsErr) {
        setBusy(false);
        return setErr(colsErr.message);
      }
      const byId: Record<string, ColaboradorRow> = {};
      ((colsData ?? []) as unknown as ColaboradorRow[]).forEach((c) => (byId[c.id] = c));
      setColaboradorById(byId);
    } else {
      setColaboradorById({});
    }

    const { data: itemsData, error: itemsErr } = await applyTenantEmpresa(
      supabase.schema("c").from("i_caixa_item").select("caixa_id").is("deleted_at", null).in("caixa_id", caixaIds),
      tenantId,
      empresaId
    );
    if (itemsErr) {
      setBusy(false);
      return setErr(itemsErr.message);
    }
    const counts: Record<string, number> = {};
    ((itemsData ?? []) as unknown as Array<{ caixa_id: string }>).forEach((r) => {
      counts[r.caixa_id] = (counts[r.caixa_id] ?? 0) + 1;
    });
    setItemCountByCaixa(counts);

    const { data: custosData, error: custosErr } = await applyTenantEmpresa(
      supabase.schema("r").from("r_i_caixa_custo").select("caixa_id,custo_total").in("caixa_id", caixaIds),
      tenantId,
      empresaId
    );
    if (custosErr) {
      setBusy(false);
      return setErr(custosErr.message);
    }
    const custoMap: Record<string, number> = {};
    ((custosData ?? []) as unknown as CaixaCustoRow[]).forEach((r) => {
      const n = typeof r.custo_total === "number" ? r.custo_total : Number(r.custo_total);
      custoMap[r.caixa_id] = Number.isFinite(n) ? n : 0;
    });
    setCustoTotalByCaixa(custoMap);
    setBusy(false);
  }

  function closeModal() {
    setModal(null);
    setActiveCaixa(null);
    setCaixaForm(emptyCaixaForm());
    setItensBusy(false);
    setItensRows([]);
    setItensFerrById({});
    setAddFerrBusca("");
    setAddFerrResultados([]);
    setAddFerrSelecionada(null);
    setAddQuantidade("1");
    setVinculoColaboradorId("");
    setVinculoObs("");
  }

  function openNewCaixa() {
    setActiveCaixa(null);
    setCaixaForm(emptyCaixaForm());
    setModal("caixaForm");
  }

  function openEditCaixa(c: CaixaRow) {
    setActiveCaixa(c);
    setCaixaForm({
      id: c.id,
      codigo: c.codigo ?? "",
      nome: c.nome ?? "",
      status: c.status ?? "DISPONIVEL",
      localizacao: c.localizacao ?? "",
      ativo: !!c.ativo,
    });
    setModal("caixaForm");
  }

  async function saveCaixa() {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para salvar.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");

    const codigo = upperText(caixaForm.codigo);
    const nome = upperText(caixaForm.nome);
    const statusUp = upperText(caixaForm.status) as CaixaStatus;
    const localizacao = caixaForm.localizacao ? upperText(caixaForm.localizacao) : "";

    if (!codigo) return setErr("Codigo e obrigatorio.");
    if (!nome) return setErr("Nome e obrigatorio.");

    setBusy(true);
    const payload = {
      tenant_id: tenantId,
      empresa_id: empresaId,
      codigo,
      nome,
      status: statusUp,
      localizacao: localizacao || null,
      ativo: !!caixaForm.ativo,
    };

    const base = supabase.schema("c").from("i_caixa");
    const { error } = caixaForm.id
      ? await applyTenantEmpresa(base.update(payload).eq("id", caixaForm.id), tenantId, empresaId)
      : await applyTenantEmpresa(base.insert(payload), tenantId, empresaId);

    setBusy(false);
    if (error) return setErr(error.message);
    setOk(caixaForm.id ? "Caixa atualizada." : "Caixa criada.");
    closeModal();
    await load();
  }

  async function softDeleteCaixa(c: CaixaRow) {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para excluir.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");
    if (!confirm(`Excluir caixa ${c.codigo}?`)) return;

    const { error } = await applyTenantEmpresa(
      supabase.schema("c").from("i_caixa").update({ deleted_at: new Date().toISOString() }).eq("id", c.id),
      tenantId,
      empresaId
    );
    if (error) return setErr(error.message);
    setOk("Caixa excluida.");
    await load();
  }

  async function loadItensForCaixa(caixaId: string) {
    if (!tenantId || !empresaId) return;
    setItensBusy(true);
    setItensRows([]);
    setItensFerrById({});

    const { data, error } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_caixa_item")
        .select("id,caixa_id,ferramenta_id,quantidade")
        .is("deleted_at", null)
        .eq("caixa_id", caixaId),
      tenantId,
      empresaId
    ).order("updated_at", { ascending: false });

    if (error) {
      setItensBusy(false);
      return setErr(error.message);
    }

    const list = (data ?? []) as unknown as CaixaItemRow[];
    setItensRows(list);

    const ferramentaIds = Array.from(new Set(list.map((i) => i.ferramenta_id)));
    if (!ferramentaIds.length) {
      setItensBusy(false);
      return;
    }

    const { data: fData, error: fErr } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta")
        .select("id,codigo,nome,unidade,ativo")
        .is("deleted_at", null)
        .in("id", ferramentaIds),
      tenantId,
      empresaId
    );
    if (fErr) {
      setItensBusy(false);
      return setErr(fErr.message);
    }

    const byId: Record<string, FerramentaMini> = {};
    ((fData ?? []) as unknown as FerramentaMini[]).forEach((f) => (byId[f.id] = f));
    setItensFerrById(byId);
    setItensBusy(false);
  }

  function openItens(c: CaixaRow) {
    setErr(null);
    setOk(null);
    setActiveCaixa(c);
    setModal("itens");
    setAddFerrBusca("");
    setAddFerrResultados([]);
    setAddFerrSelecionada(null);
    setAddQuantidade("1");
    void loadItensForCaixa(c.id);
  }

  async function buscarFerramentas(term: string) {
    if (!tenantId || !empresaId) return;
    const t = term.trim();
    if (!t) {
      setAddFerrResultados([]);
      return;
    }
    const like = `%${t}%`;
    const { data, error } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta")
        .select("id,codigo,nome,unidade,ativo")
        .is("deleted_at", null)
        .eq("ativo", true)
        .or(`codigo.ilike.${like},nome.ilike.${like}`)
        .order("codigo", { ascending: true })
        .limit(20),
      tenantId,
      empresaId
    );
    if (error) return setErr(error.message);
    setAddFerrResultados((data ?? []) as unknown as FerramentaMini[]);
  }

  async function addItemToCaixa() {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para salvar itens.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");
    if (!activeCaixa) return;
    if (!addFerrSelecionada) return setErr("Selecione uma ferramenta.");

    const qty = Number(addQuantidade);
    if (!Number.isFinite(qty) || qty <= 0) return setErr("Quantidade invalida.");

    const payload = {
      tenant_id: tenantId,
      empresa_id: empresaId,
      caixa_id: activeCaixa.id,
      ferramenta_id: addFerrSelecionada.id,
      quantidade: qty,
    };

    const { error } = await applyTenantEmpresa(
      supabase.schema("c").from("i_caixa_item").upsert(payload, { onConflict: "tenant_id,empresa_id,caixa_id,ferramenta_id" }),
      tenantId,
      empresaId
    );
    if (error) return setErr(error.message);

    setOk("Item salvo.");
    setAddFerrBusca("");
    setAddFerrResultados([]);
    setAddFerrSelecionada(null);
    setAddQuantidade("1");
    await loadItensForCaixa(activeCaixa.id);
    await load();
  }

  async function removeItem(itemId: string) {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para excluir itens.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");
    if (!activeCaixa) return;
    if (!confirm("Remover item da caixa?")) return;

    const { error } = await applyTenantEmpresa(
      supabase.schema("c").from("i_caixa_item").update({ deleted_at: new Date().toISOString() }).eq("id", itemId),
      tenantId,
      empresaId
    );
    if (error) return setErr(error.message);
    setOk("Item removido.");
    await loadItensForCaixa(activeCaixa.id);
    await load();
  }

  function openVincular(c: CaixaRow) {
    setErr(null);
    setOk(null);
    setActiveCaixa(c);
    setModal("vincular");
    setVinculoObs("");

    const v = activeVinculoByCaixa[c.id];
    setVinculoColaboradorId(v?.colaborador_id ?? "");
  }

  async function confirmarVinculo() {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para vincular.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");
    if (!activeCaixa) return;
    if (!vinculoColaboradorId) return setErr("Selecione um colaborador.");

    setBusy(true);

    const { error: closeErr } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_caixa_vinculo")
        .update({ data_fim: new Date().toISOString() })
        .eq("caixa_id", activeCaixa.id)
        .is("data_fim", null)
        .is("deleted_at", null),
      tenantId,
      empresaId
    );
    if (closeErr) {
      setBusy(false);
      return setErr(closeErr.message);
    }

    const { error: insErr } = await applyTenantEmpresa(
      supabase.schema("c").from("i_caixa_vinculo").insert({
        tenant_id: tenantId,
        empresa_id: empresaId,
        caixa_id: activeCaixa.id,
        colaborador_id: vinculoColaboradorId,
        data_inicio: new Date().toISOString(),
        observacao: vinculoObs.trim() || null,
      }),
      tenantId,
      empresaId
    );
    if (insErr) {
      setBusy(false);
      return setErr(insErr.message);
    }

    const { error: caixaErr } = await applyTenantEmpresa(
      supabase.schema("c").from("i_caixa").update({ status: "COM_COLABORADOR", updated_at: new Date().toISOString() }).eq("id", activeCaixa.id),
      tenantId,
      empresaId
    );

    setBusy(false);
    if (caixaErr) return setErr(caixaErr.message);

    setOk("Vinculo registrado.");
    closeModal();
    await load();
  }

  async function devolver(c: CaixaRow) {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para devolver.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");
    const vinculo = activeVinculoByCaixa[c.id];
    if (!vinculo) return;
    if (!confirm(`Devolver caixa ${c.codigo}?`)) return;

    setBusy(true);
    const { error: closeErr } = await applyTenantEmpresa(
      supabase.schema("c").from("i_caixa_vinculo").update({ data_fim: new Date().toISOString() }).eq("id", vinculo.id),
      tenantId,
      empresaId
    );
    if (closeErr) {
      setBusy(false);
      return setErr(closeErr.message);
    }

    const { error: caixaErr } = await applyTenantEmpresa(
      supabase.schema("c").from("i_caixa").update({ status: "DISPONIVEL", updated_at: new Date().toISOString() }).eq("id", c.id),
      tenantId,
      empresaId
    );
    setBusy(false);
    if (caixaErr) return setErr(caixaErr.message);
    setOk("Caixa devolvida.");
    await load();
  }

  const filtered = rows.filter((c) => {
    const term = q.trim().toLowerCase();
    if (term) {
      const hit = `${c.codigo ?? ""} ${c.nome ?? ""}`.toLowerCase().includes(term);
      if (!hit) return false;
    }
    if (status !== "TODOS" && c.status !== status) return false;
    if (colaboradorFiltro !== "TODOS") {
      const v = activeVinculoByCaixa[c.id];
      if (colaboradorFiltro === "SEM") {
        if (v) return false;
      } else {
        if (!v || v.colaborador_id !== colaboradorFiltro) return false;
      }
    }
    return true;
  });

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, empresaId, tenantEmpresaLoading]);

  useEffect(() => {
    void loadColaboradores();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, empresaId, tenantEmpresaLoading]);

  useEffect(() => {
    if (modal !== "itens") return;
    const handle = setTimeout(() => void buscarFerramentas(addFerrBusca), 250);
    return () => clearTimeout(handle);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [addFerrBusca, modal]);

  if (tenantEmpresaError) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300 p-6">
        {tenantEmpresaError}
      </div>
    );
  }

  if (tenantEmpresaLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando contexto...</div>;
  }

  if (!tenantId || !empresaId) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando contexto...</div>;
  }

  if (!ready && permissionsLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissoes...</div>;
  }

  if (!canView) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;
  }

  const colaboradoresAtivosNoVinculo = Array.from(
    new Map(
      Object.values(activeVinculoByCaixa)
        .map((v) => v.colaborador_id)
        .filter(Boolean)
        .map((id) => [id, colaboradorById[id]])
    ).values()
  ).filter(Boolean) as ColaboradorRow[];

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Ferramentas - Caixas</h1>
          <p className="text-sm text-zinc-400 mt-1">Cards por caixa, itens e vinculo com colaborador.</p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>
          <button
            onClick={openNewCaixa}
            disabled={!canEdit}
            className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60 disabled:cursor-not-allowed"
          >
            Nova Caixa
          </button>
        </div>
      </div>

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="grid grid-cols-1 md:grid-cols-5 gap-3">
          <div className="md:col-span-2 space-y-1">
            <div className="text-xs text-zinc-400">Codigo/Nome</div>
            <input
              className="w-full px-3 py-2"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Buscar por codigo ou nome"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Status</div>
            <select
              aria-label="Status"
              className="w-full px-3 py-2"
              value={status}
              onChange={(e) => setStatus(e.target.value as typeof status)}
            >
              <option value="TODOS">TODOS</option>
              {CAIXA_STATUS.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Colaborador</div>
            <select
              aria-label="Colaborador"
              className="w-full px-3 py-2"
              value={colaboradorFiltro}
              onChange={(e) => setColaboradorFiltro(e.target.value)}
            >
              <option value="TODOS">TODOS</option>
              <option value="SEM">SEM COLABORADOR</option>
              {colaboradoresAtivosNoVinculo.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nome}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Registros</div>
            <div className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 text-zinc-200">
              {filtered.length}
            </div>
          </div>
        </div>
      </div>

      {err && (
        <div className="text-sm text-red-400 border border-red-900/50 bg-red-950/30 px-4 py-3 rounded-lg">{err}</div>
      )}
      {ok && (
        <div className="text-sm text-emerald-300 border border-emerald-900/50 bg-emerald-950/20 px-4 py-3 rounded-lg">
          {ok}
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {filtered.map((c) => {
          const vinc = activeVinculoByCaixa[c.id];
          const col = vinc ? colaboradorById[vinc.colaborador_id] : null;
          const itemsCount = itemCountByCaixa[c.id] ?? 0;

          return (
            <div key={c.id} className="border border-zinc-800 rounded-xl bg-zinc-950 p-4 flex flex-col gap-3">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="font-mono text-xs text-zinc-400">CAIXA</div>
                  <div className="text-lg font-semibold">{c.codigo}</div>
                  <div className="text-sm text-zinc-400">{c.nome}</div>
                </div>

                <div className="text-right">
                  <div className="inline-flex items-center rounded-full border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs font-mono">
                    {c.status}
                  </div>
                  {!c.ativo && <div className="mt-1 text-xs text-red-300">INATIVA</div>}
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3 text-sm">
                <div>
                  <div className="text-xs text-zinc-500">Localizacao</div>
                  <div className="text-zinc-200">{c.localizacao ?? "-"}</div>
                </div>
                <div>
                  <div className="text-xs text-zinc-500">Itens</div>
                  <div className="text-zinc-200">{itemsCount}</div>
                </div>
                <div className="col-span-2">
                  <div className="text-xs text-zinc-500">Responsavel atual</div>
                  <div className="text-zinc-200">{col?.nome ?? "-"}</div>
                </div>
                <div className="col-span-2">
                  <div className="text-xs text-zinc-500">Custo total</div>
                  <div className="text-zinc-200 tabular-nums">
                    R$ {formatDecimalBR(Number(custoTotalByCaixa[c.id] ?? 0), 2)}
                  </div>
                </div>
              </div>

              <div className="flex flex-wrap gap-2 pt-2">
                <button
                  onClick={() => openEditCaixa(c)}
                  disabled={!canEdit}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 text-sm disabled:opacity-60 disabled:cursor-not-allowed"
                >
                  Editar
                </button>
                <button
                  onClick={() => openItens(c)}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 text-sm"
                >
                  Itens
                </button>
                <button
                  onClick={() => openVincular(c)}
                  disabled={!canEdit}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 text-sm disabled:opacity-60 disabled:cursor-not-allowed"
                >
                  Vincular/Transferir
                </button>
                {vinc ? (
                  <button
                    onClick={() => devolver(c)}
                    disabled={!canEdit}
                    className="px-3 py-2 rounded-md border border-amber-900/60 bg-amber-950/30 hover:bg-amber-950/50 text-amber-200 text-sm disabled:opacity-60 disabled:cursor-not-allowed"
                  >
                    Devolver
                  </button>
                ) : null}
                <button
                  onClick={() => softDeleteCaixa(c)}
                  disabled={!canEdit}
                  className="px-3 py-2 rounded-md border border-red-900/60 bg-red-950/40 hover:bg-red-950/70 text-red-200 text-sm disabled:opacity-60 disabled:cursor-not-allowed"
                >
                  Excluir
                </button>
              </div>
            </div>
          );
        })}

        {filtered.length === 0 && (
          <div className="border border-zinc-800 rounded-xl bg-zinc-950 p-8 text-zinc-400 text-center md:col-span-2 lg:col-span-3">
            Nenhuma caixa encontrada.
          </div>
        )}
      </div>

      {modal === "caixaForm" && (
        <div
          className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeModal()}
        >
          <div
            className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div>
                <div className="font-semibold">{caixaForm.id ? "Editar caixa" : "Nova caixa"}</div>
                <div className="text-xs text-zinc-400 mt-0.5">Campos marcados com * sao obrigatorios.</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={closeModal}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                <button
                  onClick={saveCaixa}
                  disabled={busy || !canEdit}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60 disabled:cursor-not-allowed"
                >
                  {busy ? "Salvando..." : "Salvar"}
                </button>
              </div>
            </div>

            <div className="p-5 space-y-4 max-h-[75vh] overflow-y-auto">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Codigo *</div>
                  <input
                    className="w-full px-3 py-2"
                    value={caixaForm.codigo}
                    onChange={(e) => setCaixaForm((s) => ({ ...s, codigo: e.target.value }))}
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Status</div>
                  <select
                    aria-label="Status"
                    className="w-full px-3 py-2"
                    value={caixaForm.status}
                    onChange={(e) => setCaixaForm((s) => ({ ...s, status: e.target.value as CaixaStatus }))}
                  >
                    {CAIXA_STATUS.map((s) => (
                      <option key={s} value={s}>
                        {s}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="md:col-span-2 space-y-1">
                  <div className="text-xs text-zinc-400">Nome *</div>
                  <input
                    className="w-full px-3 py-2"
                    value={caixaForm.nome}
                    onChange={(e) => setCaixaForm((s) => ({ ...s, nome: e.target.value }))}
                  />
                </div>

                <div className="md:col-span-2 space-y-1">
                  <div className="text-xs text-zinc-400">Localizacao</div>
                  <input
                    className="w-full px-3 py-2"
                    value={caixaForm.localizacao}
                    onChange={(e) => setCaixaForm((s) => ({ ...s, localizacao: e.target.value }))}
                    placeholder="Ex: ALMOXARIFADO"
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Ativo</div>
                  <select
                    aria-label="Ativo"
                    className="w-full px-3 py-2"
                    value={caixaForm.ativo ? "sim" : "nao"}
                    onChange={(e) => setCaixaForm((s) => ({ ...s, ativo: e.target.value === "sim" }))}
                  >
                    <option value="sim">SIM</option>
                    <option value="nao">NAO</option>
                  </select>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {modal === "itens" && activeCaixa && (
        <div
          className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeModal()}
        >
          <div
            className="w-full max-w-5xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div>
                <div className="font-semibold">Itens da caixa {activeCaixa.codigo}</div>
                <div className="text-xs text-zinc-400 mt-0.5">{activeCaixa.nome}</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={closeModal}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                >
                  Fechar
                </button>
              </div>
            </div>

            <div className="p-5 space-y-4 max-h-[75vh] overflow-y-auto">
              <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
                <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
                  <div className="md:col-span-2 space-y-1">
                    <div className="text-xs text-zinc-400">Adicionar ferramenta</div>
                    <input
                      className="w-full px-3 py-2"
                      value={addFerrBusca}
                      onChange={(e) => setAddFerrBusca(e.target.value)}
                      placeholder="Buscar por codigo ou nome (somente ativas)"
                    />
                  </div>

                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Quantidade</div>
                    <input
                      className="w-full px-3 py-2"
                      value={addQuantidade}
                      onChange={(e) => setAddQuantidade(e.target.value)}
                      placeholder="1"
                    />
                  </div>

                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Selecionada</div>
                    <div className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 text-zinc-200 text-sm">
                      {addFerrSelecionada ? `${addFerrSelecionada.codigo} - ${addFerrSelecionada.nome}` : "-"}
                    </div>
                  </div>
                </div>

                {addFerrResultados.length > 0 && (
                  <div className="mt-3 border border-zinc-800 rounded-lg overflow-hidden">
                    <table className="min-w-full text-sm">
                      <thead className="bg-zinc-900/40 text-zinc-200">
                        <tr>
                          <th className="text-left px-4 py-3">Codigo</th>
                          <th className="text-left px-4 py-3">Nome</th>
                          <th className="text-left px-4 py-3">Unid</th>
                          <th className="text-right px-4 py-3">Selecionar</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-zinc-900/80">
                        {addFerrResultados.map((f) => (
                          <tr key={f.id} className="hover:bg-zinc-900/40">
                            <td className="px-4 py-3 font-mono text-xs">{f.codigo}</td>
                            <td className="px-4 py-3">{f.nome}</td>
                            <td className="px-4 py-3">{f.unidade ?? "-"}</td>
                            <td className="px-4 py-3 text-right">
                              <button
                                onClick={() => setAddFerrSelecionada(f)}
                                className={
                                  addFerrSelecionada?.id === f.id
                                    ? "px-3 py-1.5 rounded-md bg-zinc-100 text-zinc-900 font-medium"
                                    : "px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                                }
                              >
                                {addFerrSelecionada?.id === f.id ? "Selecionada" : "Selecionar"}
                              </button>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}

                <div className="mt-3 flex justify-end">
                  <button
                    onClick={addItemToCaixa}
                    disabled={!canEdit || !addFerrSelecionada}
                    className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60 disabled:cursor-not-allowed"
                  >
                    Adicionar/Atualizar
                  </button>
                </div>
              </div>

              <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
                <div className="overflow-x-auto">
                  <table className="min-w-full text-sm">
                    <thead className="bg-zinc-900/40 text-zinc-200">
                      <tr>
                        <th className="text-left px-4 py-3">Codigo</th>
                        <th className="text-left px-4 py-3">Nome</th>
                        <th className="text-left px-4 py-3">Qtd</th>
                        <th className="text-right px-4 py-3">Acoes</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-zinc-900/80">
                      {itensRows.map((i) => {
                        const f = itensFerrById[i.ferramenta_id];
                        return (
                          <tr key={i.id} className="hover:bg-zinc-900/40">
                            <td className="px-4 py-3 font-mono text-xs">{f?.codigo ?? i.ferramenta_id}</td>
                            <td className="px-4 py-3">{f?.nome ?? "-"}</td>
                            <td className="px-4 py-3">{i.quantidade}</td>
                            <td className="px-4 py-3 text-right">
                              <button
                                onClick={() => removeItem(i.id)}
                                disabled={!canEdit}
                                className="px-3 py-1.5 rounded-md border border-red-900/60 bg-red-950/40 hover:bg-red-950/70 text-red-200 disabled:opacity-60 disabled:cursor-not-allowed"
                              >
                                Remover
                              </button>
                            </td>
                          </tr>
                        );
                      })}

                      {!itensBusy && itensRows.length === 0 && (
                        <tr>
                          <td colSpan={4} className="px-4 py-10 text-zinc-400 text-center">
                            Nenhum item nesta caixa.
                          </td>
                        </tr>
                      )}

                      {itensBusy && (
                        <tr>
                          <td colSpan={4} className="px-4 py-10 text-zinc-400 text-center">
                            Carregando...
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {modal === "vincular" && activeCaixa && (
        <div
          className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeModal()}
        >
          <div
            className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div>
                <div className="font-semibold">Vincular/Transferir caixa</div>
                <div className="text-xs text-zinc-400 mt-0.5">
                  {activeCaixa.codigo} - {activeCaixa.nome}
                </div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={closeModal}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                <button
                  onClick={confirmarVinculo}
                  disabled={busy || !canEdit}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60 disabled:cursor-not-allowed"
                >
                  {busy ? "Salvando..." : "Salvar"}
                </button>
              </div>
            </div>

            <div className="p-5 space-y-4 max-h-[75vh] overflow-y-auto">
              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Colaborador (ativo)</div>
                <select
                  aria-label="Colaborador"
                  className="w-full px-3 py-2"
                  value={vinculoColaboradorId}
                  onChange={(e) => setVinculoColaboradorId(e.target.value)}
                >
                  <option value="">Selecione...</option>
                  {colaboradoresList.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.nome}
                    </option>
                  ))}
                </select>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Observacao</div>
                <textarea
                  className="w-full px-3 py-2 min-h-24"
                  value={vinculoObs}
                  onChange={(e) => setVinculoObs(e.target.value)}
                  placeholder="Opcional"
                />
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
