"use client";

import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { formatDecimalBR, formatMoneyBR, parseMoneyBR } from "@/lib/decimal";

type FerramentaRow = {
  id: string;
  categoria_id: string | null;
  categoria: { prefixo: string | null; nome: string | null } | null;
  codigo: string;
  nome: string;
  ncm: string | null;
  unidade: string | null;
  ativo: boolean;
  custo_unit: number | null;
  updated_at: string;
};

type FerramentaForm = {
  id?: string;
  codigo: string;
  categoria_id: string;
  nome: string;
  ncm: string;
  unidade: string;
  ativo: boolean;
  custo_unit: number;
};

type FerramentaUnidadeStatus = "DISPONIVEL" | "COM_COLABORADOR" | "MANUTENCAO" | "BAIXADA";

type FerramentaUnidadeRow = {
  id: string;
  ferramenta_id: string;
  patrimonio_codigo: string;
  status: FerramentaUnidadeStatus;
  localizacao: string | null;
  custo_aquisicao: number | null;
  adquirido_em: string | null;
};

type FerramentaUnidadeVinculoRow = {
  id: string;
  ferramenta_unidade_id: string;
  colaborador_id: string;
  data_inicio: string;
  data_fim: string | null;
  observacao: string | null;
};

type ColaboradorRow = { id: string; nome: string; ativo: boolean };

function emptyForm(): FerramentaForm {
  return { codigo: "", categoria_id: "", nome: "", ncm: "", unidade: "UN", ativo: true, custo_unit: 0 };
}

function upperText(value: string) {
  return value.trim().toUpperCase();
}

function asNumberOrZero(value: unknown) {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : 0;
}

function escapeRegex(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export default function FerramentasCatalogoPage() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

  const { tenantId, empresaId, loading: tenantEmpresaLoading, error: tenantEmpresaError } = useTenantEmpresa();
  const { has, loading: permissionsLoading, ready } = usePermissions();
  const canView = has("imobilizado.read") === true || has("imobilizado.write") === true;
  const canEdit = has("imobilizado.write") === true;

  const [rows, setRows] = useState<FerramentaRow[]>([]);
  const [categorias, setCategorias] = useState<Array<{ id: string; prefixo: string | null; nome: string | null }>>([]);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const [q, setQ] = useState("");
  const [ativos, setAtivos] = useState<"todos" | "ativos" | "inativos">("ativos");

  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState<FerramentaForm>(emptyForm());
  const [custoUnitInput, setCustoUnitInput] = useState<string>("0,00");
  const [showAddUnidades, setShowAddUnidades] = useState(false);

  const [unidadesCounts, setUnidadesCounts] = useState<{
    total: number;
    DISPONIVEL: number;
    COM_COLABORADOR: number;
    MANUTENCAO: number;
    BAIXADA: number;
  } | null>(null);

  const [showUnidades, setShowUnidades] = useState(false);
  const [activeFerramenta, setActiveFerramenta] = useState<FerramentaRow | null>(null);
  const [unidades, setUnidades] = useState<FerramentaUnidadeRow[]>([]);
  const [vinculoAtivoByUnidade, setVinculoAtivoByUnidade] = useState<Record<string, FerramentaUnidadeVinculoRow>>({});
  const [colaboradorById, setColaboradorById] = useState<Record<string, ColaboradorRow>>({});
  const [unidadesBusy, setUnidadesBusy] = useState(false);

  const [showGerarUnidades, setShowGerarUnidades] = useState(false);
  const [gerarQtd, setGerarQtd] = useState("1");
  const [gerarCusto, setGerarCusto] = useState<number>(0);
  const [gerarAdquiridoEm, setGerarAdquiridoEm] = useState<string>("");
  const [gerarPrefixo, setGerarPrefixo] = useState<string>("");
  const [gerarLocalizacao, setGerarLocalizacao] = useState<string>("");
  const [gerarBusy, setGerarBusy] = useState(false);

  const [colaboradores, setColaboradores] = useState<ColaboradorRow[]>([]);
  const [showVincular, setShowVincular] = useState(false);
  const [activeUnidade, setActiveUnidade] = useState<FerramentaUnidadeRow | null>(null);
  const [vinculoColaboradorId, setVinculoColaboradorId] = useState<string>("");
  const [vinculoObs, setVinculoObs] = useState<string>("");
  const [vincularBusy, setVincularBusy] = useState(false);

  async function loadCategorias() {
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) return;

    const { data, error } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta_categoria")
        .select("id,prefixo,nome")
        .eq("ativo", true)
        .is("deleted_at", null)
        .order("prefixo", { ascending: true }),
      tenantId,
      empresaId
    );
    if (error) return setErr(error.message);
    setCategorias((data ?? []) as unknown as Array<{ id: string; prefixo: string | null; nome: string | null }>);
  }

  async function load() {
    setErr(null);
    setOk(null);
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) return;

    let query = applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta")
        .select("id,categoria_id,categoria:i_ferramenta_categoria(prefixo,nome),codigo,nome,ncm,unidade,ativo,custo_unit,updated_at")
        .is("deleted_at", null),
      tenantId,
      empresaId
    ).order("codigo", { ascending: true });

    const term = q.trim();
    if (term) {
      const like = `%${term}%`;
      query = query.or(`codigo.ilike.${like},nome.ilike.${like}`);
    }

    if (ativos === "ativos") query = query.eq("ativo", true);
    if (ativos === "inativos") query = query.eq("ativo", false);

    const { data, error } = await query;
    if (error) return setErr(error.message);
    setRows((data ?? []) as unknown as FerramentaRow[]);
  }

  async function loadUnidadesCounts(ferramentaId: string) {
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) return;

    const countStatus = async (status?: FerramentaUnidadeStatus) => {
      let q = applyTenantEmpresa(
        supabase
          .schema("c")
          .from("i_ferramenta_unidade")
          .select("id", { count: "exact", head: true })
          .is("deleted_at", null)
          .eq("ferramenta_id", ferramentaId),
        tenantId,
        empresaId
      );
      if (status) q = q.eq("status", status);
      const { count, error } = await q;
      if (error) throw error;
      return typeof count === "number" ? count : 0;
    };

    try {
      const [total, DISPONIVEL, COM_COLABORADOR, MANUTENCAO, BAIXADA] = await Promise.all([
        countStatus(),
        countStatus("DISPONIVEL"),
        countStatus("COM_COLABORADOR"),
        countStatus("MANUTENCAO"),
        countStatus("BAIXADA"),
      ]);
      setUnidadesCounts({ total, DISPONIVEL, COM_COLABORADOR, MANUTENCAO, BAIXADA });
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Erro ao carregar contadores de unidades.";
      setErr(msg);
      setUnidadesCounts(null);
    }
  }

  async function loadColaboradores() {
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) return;

    const { data, error } = await applyTenantEmpresa(
      supabase.from("colaboradores").select("id,nome,ativo").eq("ativo", true).order("nome", { ascending: true }),
      tenantId,
      empresaId
    );
    if (error) return setErr(error.message);
    setColaboradores((data ?? []) as unknown as ColaboradorRow[]);
  }

  async function loadUnidades(ferramentaId: string) {
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) return;
    setUnidadesBusy(true);

    const { data: unidadesData, error: unidadesErr } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta_unidade")
        .select("id,ferramenta_id,patrimonio_codigo,status,localizacao,custo_aquisicao,adquirido_em")
        .is("deleted_at", null)
        .eq("ferramenta_id", ferramentaId),
      tenantId,
      empresaId
    ).order("patrimonio_codigo", { ascending: true });

    if (unidadesErr) {
      setUnidadesBusy(false);
      return setErr(unidadesErr.message);
    }

    const list = (unidadesData ?? []) as unknown as FerramentaUnidadeRow[];
    setUnidades(list);

    const unidadeIds = list.map((u) => u.id);
    if (unidadeIds.length === 0) {
      setVinculoAtivoByUnidade({});
      setColaboradorById({});
      setUnidadesBusy(false);
      return;
    }

    const { data: vinculosData, error: vinculosErr } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta_unidade_vinculo")
        .select("id,ferramenta_unidade_id,colaborador_id,data_inicio,data_fim,observacao")
        .is("deleted_at", null)
        .is("data_fim", null)
        .in("ferramenta_unidade_id", unidadeIds),
      tenantId,
      empresaId
    );

    if (vinculosErr) {
      setUnidadesBusy(false);
      return setErr(vinculosErr.message);
    }

    const vinculos = (vinculosData ?? []) as unknown as FerramentaUnidadeVinculoRow[];
    const vincMap: Record<string, FerramentaUnidadeVinculoRow> = {};
    vinculos.forEach((v) => {
      vincMap[v.ferramenta_unidade_id] = v;
    });
    setVinculoAtivoByUnidade(vincMap);

    const colaboradorIds = Array.from(new Set(vinculos.map((v) => v.colaborador_id)));
    if (colaboradorIds.length > 0) {
      const { data: colsData, error: colsErr } = await applyTenantEmpresa(
        supabase.from("colaboradores").select("id,nome,ativo").in("id", colaboradorIds),
        tenantId,
        empresaId
      );
      if (colsErr) {
        setUnidadesBusy(false);
        return setErr(colsErr.message);
      }
      const byId: Record<string, ColaboradorRow> = {};
      ((colsData ?? []) as unknown as ColaboradorRow[]).forEach((c) => {
        byId[c.id] = c;
      });
      setColaboradorById(byId);
    } else {
      setColaboradorById({});
    }

    setUnidadesBusy(false);
  }

  function openUnidadesModal(f: FerramentaRow) {
    setErr(null);
    setOk(null);
    setActiveFerramenta(f);
    setShowUnidades(true);
    setShowGerarUnidades(false);
    setShowVincular(false);
    setActiveUnidade(null);
    setVinculoColaboradorId("");
    setVinculoObs("");
    setGerarQtd("1");
    setGerarCusto(asNumberOrZero(f.custo_unit));
    setGerarAdquiridoEm("");
    setGerarPrefixo(f.codigo ?? "");
    setGerarLocalizacao("");
    void loadUnidades(f.id);
    void loadColaboradores();
  }

  function closeUnidadesModal() {
    setShowUnidades(false);
    setActiveFerramenta(null);
    setUnidades([]);
    setVinculoAtivoByUnidade({});
    setColaboradorById({});
    setShowGerarUnidades(false);
    setShowVincular(false);
    setActiveUnidade(null);
  }

  function openGerarUnidades() {
    if (!activeFerramenta) return;
    setGerarQtd("1");
    setGerarCusto(asNumberOrZero(activeFerramenta.custo_unit));
    setGerarAdquiridoEm("");
    setGerarPrefixo(activeFerramenta.codigo ?? "");
    setGerarLocalizacao("");
    setShowGerarUnidades(true);
  }

  function openVincularModal(u: FerramentaUnidadeRow) {
    setActiveUnidade(u);
    setVinculoObs("");
    const vinc = vinculoAtivoByUnidade[u.id];
    setVinculoColaboradorId(vinc?.colaborador_id ?? "");
    setShowVincular(true);
  }

  function openNew() {
    setForm(emptyForm());
    setCustoUnitInput(formatMoneyBR(0));
    setShowForm(true);
    setUnidadesCounts(null);
    setShowAddUnidades(false);
  }

  function openEdit(r: FerramentaRow) {
    const custo = Number.isFinite(Number(r.custo_unit)) ? Number(r.custo_unit) : 0;
    setForm({
      id: r.id,
      codigo: r.codigo ?? "",
      categoria_id: r.categoria_id ?? "",
      nome: r.nome ?? "",
      ncm: r.ncm ?? "",
      unidade: r.unidade ?? "UN",
      ativo: !!r.ativo,
      custo_unit: custo,
    });
    setCustoUnitInput(formatMoneyBR(custo));
    setShowForm(true);
    setShowAddUnidades(false);
    void loadUnidadesCounts(r.id);
  }

  function closeForm() {
    setShowForm(false);
    setForm(emptyForm());
    setCustoUnitInput(formatMoneyBR(0));
    setUnidadesCounts(null);
    setShowAddUnidades(false);
  }

  async function save() {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para salvar.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");

    const categoriaId = String(form.categoria_id ?? "").trim();
    const nome = upperText(form.nome);
    const ncm = form.ncm ? upperText(form.ncm) : "";
    const unidade = form.unidade ? upperText(form.unidade) : "";
    const custoParsed = parseMoneyBR(custoUnitInput);
    const custoUnit = Number.isFinite(custoParsed) ? Number(custoParsed) : 0;

    if (!categoriaId) return setErr("Categoria e obrigatoria.");
    if (!nome) return setErr("Nome e obrigatorio.");

    setBusy(true);
    const insertPayload = {
      tenant_id: tenantId,
      empresa_id: empresaId,
      categoria_id: categoriaId,
      nome,
      ncm: ncm || null,
      unidade: unidade || null,
      ativo: !!form.ativo,
      custo_unit: custoUnit,
      custo_moeda: "BRL",
      custo_atualizado_em: new Date().toISOString(),
    };
    const updatePayload = {
      nome,
      ncm: ncm || null,
      unidade: unidade || null,
      ativo: !!form.ativo,
      custo_unit: custoUnit,
      custo_moeda: "BRL",
      custo_atualizado_em: new Date().toISOString(),
    };

    const base = supabase.schema("c").from("i_ferramenta");
    const query = form.id
      ? applyTenantEmpresa(base.update(updatePayload).eq("id", form.id).select("id,codigo"), tenantId, empresaId)
      : applyTenantEmpresa(base.insert(insertPayload).select("id,codigo"), tenantId, empresaId);
    const { data, error } = await query.maybeSingle();

    setBusy(false);
    if (error) return setErr(error.message);
    const codigoGerado = (data as unknown as { codigo?: string | null } | null)?.codigo ?? null;
    setOk(form.id ? "Ferramenta atualizada." : `Ferramenta criada. Codigo gerado: ${codigoGerado ?? "-"}.`);
    closeForm();
    await load();
  }

  async function softDelete(id: string) {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para excluir.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");
    if (!confirm("Excluir ferramenta?")) return;

    const { error } = await applyTenantEmpresa(
      supabase.schema("c").from("i_ferramenta").update({ deleted_at: new Date().toISOString() }).eq("id", id),
      tenantId,
      empresaId
    );
    if (error) return setErr(error.message);
    setOk("Ferramenta excluida.");
    await load();
  }

  function computeNextUnidadeSeq(prefix: string, existing: FerramentaUnidadeRow[]): number {
    const base = upperText(prefix);
    if (!base) return 1;
    const re = new RegExp(`^${escapeRegex(base)}-U(\\d+)$`);
    let max = 0;
    existing.forEach((u) => {
      const code = upperText(u.patrimonio_codigo ?? "");
      const m = re.exec(code);
      if (!m) return;
      const n = Number.parseInt(m[1] ?? "", 10);
      if (Number.isFinite(n) && n > max) max = n;
    });
    return max + 1;
  }

  async function gerarUnidades() {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para alterar.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");
    if (!activeFerramenta) return;

    const qtd = Number.parseInt(String(gerarQtd ?? "").trim(), 10);
    if (!Number.isFinite(qtd) || qtd <= 0) return setErr("Quantidade invalida.");
    if (qtd > 500) return setErr("Quantidade muito alta (max 500 por vez).");

    const prefix = upperText(gerarPrefixo || activeFerramenta.codigo || "");
    if (!prefix) return setErr("Prefixo de patrimonio invalido.");

    const custoAquisicao = Number.isFinite(Number(gerarCusto)) ? Number(gerarCusto) : 0;
    const localizacao = gerarLocalizacao ? upperText(gerarLocalizacao) : "";
    const adquiridoEm = gerarAdquiridoEm.trim() ? gerarAdquiridoEm.trim() : "";

    const startSeq = computeNextUnidadeSeq(prefix, unidades);
    const items = Array.from({ length: qtd }).map((_, idx) => {
      const seq = startSeq + idx;
      const patrimonio = `${prefix}-U${String(seq).padStart(4, "0")}`;
      return {
        tenant_id: tenantId,
        empresa_id: empresaId,
        ferramenta_id: activeFerramenta.id,
        patrimonio_codigo: patrimonio,
        status: "DISPONIVEL" as FerramentaUnidadeStatus,
        localizacao: localizacao || null,
        custo_aquisicao: custoAquisicao,
        adquirido_em: adquiridoEm || null,
      };
    });

    setGerarBusy(true);
    const { error } = await applyTenantEmpresa(
      supabase.schema("c").from("i_ferramenta_unidade").insert(items),
      tenantId,
      empresaId
    );
    setGerarBusy(false);
    if (error) return setErr(error.message);
    setOk(`Unidades geradas: ${qtd}.`);
    setShowGerarUnidades(false);
    await loadUnidades(activeFerramenta.id);
  }

  async function getNextUnidadeSeqFromDb(ferramentaId: string, codigoFerramenta: string): Promise<number> {
    if (!tenantId || !empresaId) return 1;
    const prefix = upperText(codigoFerramenta);
    if (!prefix) return 1;
    const like = `${prefix}-U%`;

    const { data, error } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta_unidade")
        .select("patrimonio_codigo")
        .is("deleted_at", null)
        .eq("ferramenta_id", ferramentaId)
        .ilike("patrimonio_codigo", like)
        .order("patrimonio_codigo", { ascending: false })
        .limit(1),
      tenantId,
      empresaId
    );
    if (error) throw error;
    const first = Array.isArray(data) && data.length ? (data[0] as { patrimonio_codigo?: unknown } | null) : null;
    const code = first?.patrimonio_codigo ? upperText(String(first.patrimonio_codigo)) : "";
    const m = new RegExp(`^${escapeRegex(prefix)}-U(\\d+)$`).exec(code);
    if (!m) return 1;
    const n = Number.parseInt(m[1] ?? "", 10);
    return Number.isFinite(n) ? n + 1 : 1;
  }

  function openAddUnidadesFromForm() {
    if (!form.id) {
      setErr("Salve a ferramenta antes de adicionar unidades.");
      return;
    }
    setGerarQtd("1");
    setGerarCusto(Number.isFinite(Number(form.custo_unit)) ? Number(form.custo_unit) : 0);
    setGerarAdquiridoEm("");
    setGerarLocalizacao("");
    setShowAddUnidades(true);
  }

  async function adicionarUnidadesPeloCadastro() {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para alterar.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");
    if (!form.id) return setErr("Salve a ferramenta antes de adicionar unidades.");
    if (!form.codigo) return setErr("Codigo da ferramenta nao carregado.");

    const qtd = Number.parseInt(String(gerarQtd ?? "").trim(), 10);
    if (!Number.isFinite(qtd) || qtd <= 0) return setErr("Quantidade invalida.");
    if (qtd > 500) return setErr("Quantidade muito alta (max 500 por vez).");

    const custoAquisicao = Number.isFinite(Number(gerarCusto)) ? Number(gerarCusto) : 0;
    const localizacao = gerarLocalizacao ? upperText(gerarLocalizacao) : "";
    const adquiridoEm = gerarAdquiridoEm.trim() ? gerarAdquiridoEm.trim() : "";

    setGerarBusy(true);
    try {
      const nextSeq = await getNextUnidadeSeqFromDb(form.id, form.codigo);
      const prefix = upperText(form.codigo);
      const items = Array.from({ length: qtd }).map((_, idx) => {
        const seq = nextSeq + idx;
        const patrimonio = `${prefix}-U${String(seq).padStart(4, "0")}`;
        return {
          tenant_id: tenantId,
          empresa_id: empresaId,
          ferramenta_id: form.id!,
          patrimonio_codigo: patrimonio,
          status: "DISPONIVEL" as FerramentaUnidadeStatus,
          localizacao: localizacao || null,
          custo_aquisicao: custoAquisicao,
          adquirido_em: adquiridoEm || null,
        };
      });

      const { error } = await applyTenantEmpresa(
        supabase.schema("c").from("i_ferramenta_unidade").insert(items),
        tenantId,
        empresaId
      );
      if (error) throw error;
      setOk(`Unidades adicionadas: ${qtd}.`);
      setShowAddUnidades(false);
      await loadUnidadesCounts(form.id);
      if (showUnidades && activeFerramenta?.id === form.id) {
        await loadUnidades(form.id);
      }
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Erro ao adicionar unidades.";
      setErr(msg);
    } finally {
      setGerarBusy(false);
    }
  }

  async function setUnidadeStatus(unidadeId: string, status: FerramentaUnidadeStatus) {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para alterar.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");
    if (!activeFerramenta) return;

    const { error } = await applyTenantEmpresa(
      supabase.schema("c").from("i_ferramenta_unidade").update({ status, updated_at: new Date().toISOString() }).eq("id", unidadeId),
      tenantId,
      empresaId
    );
    if (error) return setErr(error.message);
    setOk("Status atualizado.");
    await loadUnidades(activeFerramenta.id);
  }

  async function confirmarVinculoUnidade() {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para vincular.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");
    if (!activeFerramenta) return;
    if (!activeUnidade) return;
    if (!vinculoColaboradorId) return setErr("Selecione um colaborador.");

    setVincularBusy(true);

    const { error: closeErr } = await applyTenantEmpresa(
      supabase
        .schema("c")
        .from("i_ferramenta_unidade_vinculo")
        .update({ data_fim: new Date().toISOString() })
        .eq("ferramenta_unidade_id", activeUnidade.id)
        .is("data_fim", null)
        .is("deleted_at", null),
      tenantId,
      empresaId
    );
    if (closeErr) {
      setVincularBusy(false);
      return setErr(closeErr.message);
    }

    const { error: insErr } = await applyTenantEmpresa(
      supabase.schema("c").from("i_ferramenta_unidade_vinculo").insert({
        tenant_id: tenantId,
        empresa_id: empresaId,
        ferramenta_unidade_id: activeUnidade.id,
        colaborador_id: vinculoColaboradorId,
        data_inicio: new Date().toISOString(),
        observacao: vinculoObs.trim() || null,
      }),
      tenantId,
      empresaId
    );
    if (insErr) {
      setVincularBusy(false);
      return setErr(insErr.message);
    }

    const { error: unitErr } = await applyTenantEmpresa(
      supabase.schema("c").from("i_ferramenta_unidade").update({ status: "COM_COLABORADOR", updated_at: new Date().toISOString() }).eq("id", activeUnidade.id),
      tenantId,
      empresaId
    );
    setVincularBusy(false);
    if (unitErr) return setErr(unitErr.message);

    setOk("Vinculo registrado.");
    setShowVincular(false);
    setActiveUnidade(null);
    await loadUnidades(activeFerramenta.id);
  }

  async function devolverUnidade(unidade: FerramentaUnidadeRow) {
    setErr(null);
    setOk(null);
    if (!canEdit) return setErr("Sem permissao para devolver.");
    if (!tenantId || !empresaId) return setErr("Contexto nao carregado.");
    if (!activeFerramenta) return;

    const vinc = vinculoAtivoByUnidade[unidade.id];
    if (!vinc) return;
    if (!confirm(`Devolver ${unidade.patrimonio_codigo}?`)) return;

    const { error: closeErr } = await applyTenantEmpresa(
      supabase.schema("c").from("i_ferramenta_unidade_vinculo").update({ data_fim: new Date().toISOString() }).eq("id", vinc.id),
      tenantId,
      empresaId
    );
    if (closeErr) return setErr(closeErr.message);

    const { error: unitErr } = await applyTenantEmpresa(
      supabase.schema("c").from("i_ferramenta_unidade").update({ status: "DISPONIVEL", updated_at: new Date().toISOString() }).eq("id", unidade.id),
      tenantId,
      empresaId
    );
    if (unitErr) return setErr(unitErr.message);

    setOk("Unidade devolvida.");
    await loadUnidades(activeFerramenta.id);
  }

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, empresaId, tenantEmpresaLoading, q, ativos]);

  useEffect(() => {
    void loadCategorias();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, empresaId, tenantEmpresaLoading]);

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

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Ferramentas - Catalogo</h1>
          <p className="text-sm text-zinc-400 mt-1">Cadastro de ferramentas do imobilizado.</p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>
          <button
            onClick={openNew}
            disabled={!canEdit}
            className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60 disabled:cursor-not-allowed"
          >
            Nova Ferramenta
          </button>
        </div>
      </div>

      <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
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
            <div className="text-xs text-zinc-400">Ativo</div>
            <select
              aria-label="Ativo"
              className="w-full px-3 py-2"
              value={ativos}
              onChange={(e) => setAtivos(e.target.value as typeof ativos)}
            >
              <option value="todos">Todos</option>
              <option value="ativos">Ativos</option>
              <option value="inativos">Inativos</option>
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Registros</div>
            <div className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 text-zinc-200">
              {rows.length}
            </div>
          </div>
        </div>
      </div>

      {err && <div className="text-sm text-red-400 border border-red-900/50 bg-red-950/30 px-4 py-3 rounded-lg">{err}</div>}
      {ok && <div className="text-sm text-emerald-300 border border-emerald-900/50 bg-emerald-950/20 px-4 py-3 rounded-lg">{ok}</div>}

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-zinc-900/40 text-zinc-200">
              <tr>
                <th className="text-left px-4 py-3">Categoria</th>
                <th className="text-left px-4 py-3">Codigo</th>
                <th className="text-left px-4 py-3">Nome</th>
                <th className="text-right px-4 py-3">Custo (R$)</th>
                <th className="text-left px-4 py-3">Unidade</th>
                <th className="text-left px-4 py-3">NCM</th>
                <th className="text-left px-4 py-3">Ativo</th>
                <th className="text-right px-4 py-3">Acoes</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-900/80">
              {rows.map((r) => (
                <tr key={r.id} className="hover:bg-zinc-900/40">
                  <td className="px-4 py-3">
                    <div className="text-xs text-zinc-200">
                      {r.categoria?.prefixo ?? "-"}
                      {r.categoria?.nome ? ` - ${r.categoria.nome}` : ""}
                    </div>
                  </td>
                  <td className="px-4 py-3 font-mono text-xs text-zinc-200">{r.codigo}</td>
                  <td className="px-4 py-3">{r.nome}</td>
                  <td className="px-4 py-3 text-right tabular-nums">R$ {formatDecimalBR(Number(r.custo_unit ?? 0), 2)}</td>
                  <td className="px-4 py-3">{r.unidade ?? "-"}</td>
                  <td className="px-4 py-3">{r.ncm ?? "-"}</td>
                  <td className="px-4 py-3">{r.ativo ? "SIM" : "NAO"}</td>
                  <td className="px-4 py-3 text-right">
                    <div className="flex items-center justify-end gap-2">
                      <button
                        onClick={() => openUnidadesModal(r)}
                        className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                      >
                        Unidades
                      </button>
                      <button
                        onClick={() => openEdit(r)}
                        disabled={!canEdit}
                        className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60 disabled:cursor-not-allowed"
                      >
                        Editar
                      </button>
                      <button
                        onClick={() => softDelete(r.id)}
                        disabled={!canEdit}
                        className="px-3 py-1.5 rounded-md border border-red-900/60 bg-red-950/40 hover:bg-red-950/70 text-red-200 disabled:opacity-60 disabled:cursor-not-allowed"
                      >
                        Excluir
                      </button>
                    </div>
                  </td>
                </tr>
              ))}

              {!busy && rows.length === 0 && (
                <tr>
                  <td colSpan={8} className="px-4 py-10 text-zinc-400 text-center">
                    Nenhuma ferramenta encontrada.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {showUnidades && activeFerramenta && (
        <div
          className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeUnidadesModal()}
        >
          <div
            className="w-full max-w-6xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div>
                <div className="font-semibold">Unidades - {activeFerramenta.codigo}</div>
                <div className="text-xs text-zinc-400 mt-0.5">{activeFerramenta.nome}</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => loadUnidades(activeFerramenta.id)}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                >
                  Atualizar
                </button>
                <button
                  onClick={openGerarUnidades}
                  disabled={!canEdit}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60 disabled:cursor-not-allowed"
                >
                  Gerar Unidades
                </button>
                <button
                  onClick={closeUnidadesModal}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                >
                  Fechar
                </button>
              </div>
            </div>

            <div className="p-5 space-y-4 max-h-[78vh] overflow-y-auto">
              {unidadesBusy && <div className="text-xs text-zinc-400">Carregando unidades...</div>}

              {!unidadesBusy && unidades.length === 0 && (
                <div className="border border-zinc-800 rounded-xl bg-zinc-950 p-8 text-zinc-400 text-center">
                  Nenhuma unidade cadastrada.
                </div>
              )}

              {!unidadesBusy && unidades.length > 0 && (
                <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
                  <div className="overflow-x-auto">
                    <table className="min-w-full text-sm">
                      <thead className="bg-zinc-900/40 text-zinc-200">
                        <tr>
                          <th className="text-left px-4 py-3">Patrimonio</th>
                          <th className="text-left px-4 py-3">Status</th>
                          <th className="text-left px-4 py-3">Colaborador atual</th>
                          <th className="text-left px-4 py-3">Localizacao</th>
                          <th className="text-right px-4 py-3">Custo aquisicao</th>
                          <th className="text-left px-4 py-3">Adquirido em</th>
                          <th className="text-right px-4 py-3">Acoes</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-zinc-900/80">
                        {unidades.map((u) => {
                          const vinc = vinculoAtivoByUnidade[u.id];
                          const col = vinc ? colaboradorById[vinc.colaborador_id] : null;
                          const canDevolver = Boolean(vinc);
                          return (
                            <tr key={u.id} className="hover:bg-zinc-900/40">
                              <td className="px-4 py-3 font-mono text-xs text-zinc-200">{u.patrimonio_codigo}</td>
                              <td className="px-4 py-3 font-mono text-xs">{u.status}</td>
                              <td className="px-4 py-3">{col?.nome ?? "-"}</td>
                              <td className="px-4 py-3">{u.localizacao ?? "-"}</td>
                              <td className="px-4 py-3 text-right tabular-nums">R$ {formatDecimalBR(asNumberOrZero(u.custo_aquisicao), 2)}</td>
                              <td className="px-4 py-3">{u.adquirido_em ? String(u.adquirido_em).slice(0, 10) : "-"}</td>
                              <td className="px-4 py-3 text-right">
                                <div className="flex items-center justify-end gap-2 flex-wrap">
                                  <button
                                    onClick={() => openVincularModal(u)}
                                    disabled={!canEdit}
                                    className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60 disabled:cursor-not-allowed"
                                  >
                                    Vincular/Transferir
                                  </button>
                                  <button
                                    onClick={() => devolverUnidade(u)}
                                    disabled={!canEdit || !canDevolver}
                                    className="px-3 py-1.5 rounded-md border border-amber-900/60 bg-amber-950/30 hover:bg-amber-950/50 text-amber-200 disabled:opacity-60 disabled:cursor-not-allowed"
                                  >
                                    Devolver
                                  </button>
                                  <button
                                    onClick={() => setUnidadeStatus(u.id, "MANUTENCAO")}
                                    disabled={!canEdit}
                                    className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60 disabled:cursor-not-allowed"
                                  >
                                    Manutencao
                                  </button>
                                  <button
                                    onClick={() => confirm(`Baixar ${u.patrimonio_codigo}?`) && setUnidadeStatus(u.id, "BAIXADA")}
                                    disabled={!canEdit}
                                    className="px-3 py-1.5 rounded-md border border-red-900/60 bg-red-950/40 hover:bg-red-950/70 text-red-200 disabled:opacity-60 disabled:cursor-not-allowed"
                                  >
                                    Baixar
                                  </button>
                                </div>
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                </div>
              )}

              {showGerarUnidades && (
                <div className="border border-zinc-800 rounded-xl bg-zinc-950 p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <div className="font-semibold">Gerar unidades</div>
                      <div className="text-xs text-zinc-400 mt-0.5">
                        Padrao: <span className="font-mono">{upperText(gerarPrefixo || activeFerramenta.codigo)}-U0001</span>
                      </div>
                    </div>
                    <button
                      onClick={() => setShowGerarUnidades(false)}
                      className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                    >
                      Fechar
                    </button>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-4 gap-3 mt-4">
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Quantidade *</div>
                      <input className="w-full px-3 py-2" value={gerarQtd} onChange={(e) => setGerarQtd(e.target.value)} />
                    </div>
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Custo aquisicao (R$)</div>
                      <input
                        className="w-full px-3 py-2 tabular-nums"
                        value={formatMoneyBR(gerarCusto)}
                        onChange={(e) => setGerarCusto(parseMoneyBR(e.target.value))}
                        placeholder="0,00"
                      />
                    </div>
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Adquirido em</div>
                      <input
                        type="date"
                        className="w-full px-3 py-2"
                        value={gerarAdquiridoEm}
                        onChange={(e) => setGerarAdquiridoEm(e.target.value)}
                      />
                    </div>
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Prefixo patrimonio</div>
                      <input
                        className="w-full px-3 py-2 font-mono text-xs"
                        value={gerarPrefixo}
                        onChange={(e) => setGerarPrefixo(e.target.value)}
                        placeholder={activeFerramenta.codigo}
                      />
                    </div>
                    <div className="md:col-span-2 space-y-1">
                      <div className="text-xs text-zinc-400">Localizacao</div>
                      <input
                        className="w-full px-3 py-2"
                        value={gerarLocalizacao}
                        onChange={(e) => setGerarLocalizacao(e.target.value)}
                        placeholder="Ex: ALMOXARIFADO"
                      />
                    </div>
                    <div className="md:col-span-2 flex items-end justify-end">
                      <button
                        onClick={gerarUnidades}
                        disabled={gerarBusy || !canEdit}
                        className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60 disabled:cursor-not-allowed"
                      >
                        {gerarBusy ? "Gerando..." : "Confirmar"}
                      </button>
                    </div>
                  </div>
                </div>
              )}

              {showVincular && activeUnidade && (
                <div className="border border-zinc-800 rounded-xl bg-zinc-950 p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <div className="font-semibold">Vincular/Transferir</div>
                      <div className="text-xs text-zinc-400 mt-0.5 font-mono">{activeUnidade.patrimonio_codigo}</div>
                    </div>
                    <button
                      onClick={() => setShowVincular(false)}
                      className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                    >
                      Fechar
                    </button>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-3 gap-3 mt-4">
                    <div className="md:col-span-2 space-y-1">
                      <div className="text-xs text-zinc-400">Colaborador (ativo) *</div>
                      <select
                        aria-label="Colaborador"
                        className="w-full px-3 py-2"
                        value={vinculoColaboradorId}
                        onChange={(e) => setVinculoColaboradorId(e.target.value)}
                      >
                        <option value="">Selecione...</option>
                        {colaboradores.map((c) => (
                          <option key={c.id} value={c.id}>
                            {c.nome}
                          </option>
                        ))}
                      </select>
                    </div>
                    <div className="md:col-span-3 space-y-1">
                      <div className="text-xs text-zinc-400">Observacao</div>
                      <textarea
                        className="w-full px-3 py-2 min-h-24"
                        value={vinculoObs}
                        onChange={(e) => setVinculoObs(e.target.value)}
                        placeholder="Opcional"
                      />
                    </div>
                    <div className="md:col-span-3 flex justify-end">
                      <button
                        onClick={confirmarVinculoUnidade}
                        disabled={vincularBusy || !canEdit}
                        className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60 disabled:cursor-not-allowed"
                      >
                        {vincularBusy ? "Salvando..." : "Salvar"}
                      </button>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {showForm && (
        <div
          className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeForm()}
        >
          <div
            className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div>
                <div className="font-semibold">{form.id ? "Editar ferramenta" : "Nova ferramenta"}</div>
                <div className="text-xs text-zinc-400 mt-0.5">Campos marcados com * sao obrigatorios.</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={closeForm}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                <button
                  onClick={save}
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
                  <div className="text-xs text-zinc-400">Categoria *</div>
                  <select
                    aria-label="Categoria"
                    className="w-full px-3 py-2"
                    value={form.categoria_id}
                    onChange={(e) => setForm((s) => ({ ...s, categoria_id: e.target.value }))}
                    disabled={Boolean(form.id)}
                  >
                    <option value="">Selecione...</option>
                    {categorias.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.prefixo ?? "-"} {c.nome ? `- ${c.nome}` : ""}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Codigo</div>
                  {form.id ? (
                    <input className="w-full px-3 py-2 font-mono text-xs" value={form.codigo} readOnly />
                  ) : (
                    <div className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 text-zinc-300 text-sm">
                      Codigo sera gerado automaticamente (ex: MEC-000001)
                    </div>
                  )}
                </div>

                <div className="md:col-span-2 space-y-1">
                  <div className="text-xs text-zinc-400">Nome *</div>
                  <input
                    className="w-full px-3 py-2"
                    value={form.nome}
                    onChange={(e) => setForm((s) => ({ ...s, nome: e.target.value }))}
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Unidade</div>
                  <input
                    className="w-full px-3 py-2"
                    value={form.unidade}
                    onChange={(e) => setForm((s) => ({ ...s, unidade: e.target.value }))}
                    placeholder="UN"
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">NCM</div>
                  <input
                    className="w-full px-3 py-2"
                    value={form.ncm}
                    onChange={(e) => setForm((s) => ({ ...s, ncm: e.target.value }))}
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Custo unitario (R$)</div>
                  <input
                    className="w-full px-3 py-2 tabular-nums"
                    value={custoUnitInput}
                    onChange={(e) => setCustoUnitInput(e.target.value)}
                    onBlur={() => {
                      const n = parseMoneyBR(custoUnitInput);
                      const next = Number.isFinite(n) ? Number(n) : 0;
                      setForm((s) => ({ ...s, custo_unit: next }));
                      setCustoUnitInput(formatMoneyBR(next));
                    }}
                    placeholder="0,00"
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Ativo</div>
                  <select
                    aria-label="Ativo"
                    className="w-full px-3 py-2"
                    value={form.ativo ? "sim" : "nao"}
                    onChange={(e) => setForm((s) => ({ ...s, ativo: e.target.value === "sim" }))}
                  >
                    <option value="sim">SIM</option>
                    <option value="nao">NAO</option>
                  </select>
                </div>
              </div>

              <div className="border border-zinc-800 rounded-xl p-4 bg-zinc-950">
                <div className="flex items-start justify-between gap-3 flex-wrap">
                  <div>
                    <div className="font-semibold">Unidades (Quantidade)</div>
                    <div className="text-xs text-zinc-400 mt-0.5">Contadores calculados por status das unidades fisicas.</div>
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => form.id && loadUnidadesCounts(form.id)}
                      disabled={!form.id}
                      className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60 disabled:cursor-not-allowed"
                    >
                      Atualizar
                    </button>
                    <button
                      onClick={openAddUnidadesFromForm}
                      disabled={!canEdit || !form.id}
                      className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60 disabled:cursor-not-allowed"
                    >
                      Adicionar unidades
                    </button>
                  </div>
                </div>

                {!form.id && (
                  <div className="mt-3 text-xs text-zinc-400">Salve a ferramenta para habilitar contadores e adicionar unidades.</div>
                )}

                <div className="mt-4 grid grid-cols-2 md:grid-cols-5 gap-3">
                  <div className="rounded-lg border border-zinc-800 bg-zinc-900/40 px-3 py-2">
                    <div className="text-[11px] text-zinc-400">Total</div>
                    <div className="text-zinc-100 font-semibold tabular-nums">{unidadesCounts?.total ?? 0}</div>
                  </div>
                  <div className="rounded-lg border border-zinc-800 bg-zinc-900/40 px-3 py-2">
                    <div className="text-[11px] text-zinc-400">Disponivel</div>
                    <div className="text-zinc-100 font-semibold tabular-nums">{unidadesCounts?.DISPONIVEL ?? 0}</div>
                  </div>
                  <div className="rounded-lg border border-zinc-800 bg-zinc-900/40 px-3 py-2">
                    <div className="text-[11px] text-zinc-400">Com colaborador</div>
                    <div className="text-zinc-100 font-semibold tabular-nums">{unidadesCounts?.COM_COLABORADOR ?? 0}</div>
                  </div>
                  <div className="rounded-lg border border-zinc-800 bg-zinc-900/40 px-3 py-2">
                    <div className="text-[11px] text-zinc-400">Manutencao</div>
                    <div className="text-zinc-100 font-semibold tabular-nums">{unidadesCounts?.MANUTENCAO ?? 0}</div>
                  </div>
                  <div className="rounded-lg border border-zinc-800 bg-zinc-900/40 px-3 py-2">
                    <div className="text-[11px] text-zinc-400">Baixada</div>
                    <div className="text-zinc-100 font-semibold tabular-nums">{unidadesCounts?.BAIXADA ?? 0}</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {showForm && showAddUnidades && form.id && (
        <div
          className="fixed inset-0 z-[60] bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && setShowAddUnidades(false)}
        >
          <div
            className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div>
                <div className="font-semibold">Adicionar unidades</div>
                <div className="text-xs text-zinc-400 mt-0.5 font-mono">{form.codigo}</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setShowAddUnidades(false)}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                <button
                  onClick={adicionarUnidadesPeloCadastro}
                  disabled={gerarBusy || !canEdit}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60 disabled:cursor-not-allowed"
                >
                  {gerarBusy ? "Salvando..." : "Confirmar"}
                </button>
              </div>
            </div>

            <div className="p-5 space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Quantidade *</div>
                  <input className="w-full px-3 py-2" value={gerarQtd} onChange={(e) => setGerarQtd(e.target.value)} />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Custo aquisicao (R$)</div>
                  <input
                    className="w-full px-3 py-2 tabular-nums"
                    value={formatMoneyBR(gerarCusto)}
                    onChange={(e) => setGerarCusto(parseMoneyBR(e.target.value))}
                    placeholder="0,00"
                  />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Adquirido em</div>
                  <input
                    type="date"
                    className="w-full px-3 py-2"
                    value={gerarAdquiridoEm}
                    onChange={(e) => setGerarAdquiridoEm(e.target.value)}
                  />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Localizacao</div>
                  <input
                    className="w-full px-3 py-2"
                    value={gerarLocalizacao}
                    onChange={(e) => setGerarLocalizacao(e.target.value)}
                    placeholder="Opcional"
                  />
                </div>
              </div>

              <div className="text-xs text-zinc-400">
                Patrimonio sera gerado como <span className="font-mono">{upperText(form.codigo)}-U0001</span>...
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
