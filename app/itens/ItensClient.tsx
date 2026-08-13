"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { supabaseBrowser } from "../../lib/supabase/client";
import { parseDecimalBR } from "../../lib/decimal";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenant, applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { Can } from "@/components/auth/Can";
import { requireAny } from "@/lib/auth/capabilities";

type Fornecedor = { id: number; nome: string; ativo: boolean };

type ItemFinalidade = "consumo" | "materia_prima" | "revenda" | "imobilizado" | "outros";
const ITEM_FINALIDADES: ItemFinalidade[] = ["consumo", "materia_prima", "revenda", "imobilizado", "outros"];
const PAGE_SIZE = 100;

type Item = {
  id: number;
  codigo_interno: string;
  codigo_barras: string | null;
  nome: string;
  descricao: string | null;
  tipo: "produto" | "servico" | "despesa";
  categoria: string | null;
  subcategoria: string | null;

  fabricante: string | null;
  finalidade: string | null;
  motivo_compra_id: string | null;

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
  criado_por: string | null;
  atualizado_em: string;
  atualizado_por: string | null;
  auditoria?: ItemAudit | null;
};

type ItemAudit = {
  item_id: number;
  acao: "criacao" | "alteracao";
  data_acao: string;
  autor_nome: string;
  autor_identificador: string | null;
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

  fabricante: string;
  finalidade: string; // public.item_finalidade ("" = null)
  motivo_compra_id: string; // f.motivo_compra ("" = null)

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

type ItemBase = Omit<Item, "fiscal_itens">;
// When the DB schema hasn't been migrated yet, `motivo_compra_id` won't be returned by Supabase.
// This keeps runtime resilient without using `any`.
type ItemBaseMaybeMotivo = Omit<ItemBase, "motivo_compra_id"> & { motivo_compra_id?: string | null };
type ItemPayload = {
  codigo_interno: string;
  codigo_barras: string | null;
  nome: string;
  descricao: string | null;
  tipo: Item["tipo"];
  categoria: string | null;
  subcategoria: string | null;
  fabricante: string | null;
  finalidade: string | null;
  motivo_compra_id: string | null;
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
  atualizado_em: string;
  atualizado_por?: string | null;
};

type FiscalPayload = {
  tenant_id: string;
  empresa_id: string;
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
  atualizado_em: string;
};

type DbError = { message?: string; code?: string } | null;

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

function upper(value: string | null | undefined) {
  return String(value ?? "").toUpperCase();
}

function formatAuditDate(value: string | null | undefined) {
  if (!value) return "Data não disponível";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return "Data não disponível";
  return parsed.toLocaleString("pt-BR");
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

    fabricante: "",
    finalidade: "",
    motivo_compra_id: "",

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

function buildFormFromItem(r: Item): ItemForm {
  return {
    id: r.id,
    codigo_interno: upper(r.codigo_interno),
    codigo_barras: upper(r.codigo_barras),
    nome: upper(r.nome),
    descricao: upper(r.descricao),
    tipo: r.tipo,
    categoria: upper(r.categoria),
    subcategoria: upper(r.subcategoria),
    fabricante: upper(r.fabricante),
    finalidade: r.finalidade ? String(r.finalidade) : "",
    motivo_compra_id: r.motivo_compra_id ? String(r.motivo_compra_id) : "",
    unidade_medida: upper(r.unidade_medida || "UN"),
    controla_estoque: !!r.controla_estoque,
    estoque_minimo: Number(r.estoque_minimo ?? 0),
    estoque_maximo: Number(r.estoque_maximo ?? 0),
    estoque_ideal: Number(r.estoque_ideal ?? 0),
    custo_ultima_compra: Number(r.custo_ultima_compra ?? 0),
    custo_medio: Number(r.custo_medio ?? 0),
    preco_unitario: Number(r.preco_unitario ?? 0),
    fornecedor_id: r.fornecedor_id ?? null,
    ativo: !!r.ativo,
  };
}

function buildFiscalFormFromItem(r: Item): FiscalForm {
  const fiscal = r.fiscal_itens;
  return {
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
  };
}

function normalizeFiscalForm(value: FiscalForm) {
  const numOrNull = (input: number | null | undefined) => (Number.isFinite(input as number) ? Number(input) : null);
  return {
    ncm: value.ncm.trim(),
    cst_icms: value.cst_icms.trim(),
    cst_pis: value.cst_pis.trim(),
    cst_cofins: value.cst_cofins.trim(),
    aliq_icms: numOrNull(value.aliq_icms),
    aliq_ipi: numOrNull(value.aliq_ipi),
    aliq_pis: numOrNull(value.aliq_pis),
    aliq_cofins: numOrNull(value.aliq_cofins),
    credita_icms: !!value.credita_icms,
    ipi_entra_no_custo: !!value.ipi_entra_no_custo,
    credita_pis: !!value.credita_pis,
    credita_cofins: !!value.credita_cofins,
  };
}

function serializeFiscalForm(value: FiscalForm) {
  return JSON.stringify(normalizeFiscalForm(value));
}

type ItensClientProps = {
  fixedFinalidade?: ItemFinalidade;
  title?: string;
  description?: string;
  tableTitle?: string;
};

export default function ItensClient({
  fixedFinalidade,
  title = "Itens",
  description = "Cadastro de produtos, servicos e despesas.",
  tableTitle = "Itens",
}: ItensClientProps = {}) {
  const lockedFinalidade: "" | ItemFinalidade = fixedFinalidade ?? "";
  const isFinalidadeLocked = Boolean(lockedFinalidade);

  const emptyFormForContext = () => {
    const next = emptyForm();
    if (lockedFinalidade) next.finalidade = lockedFinalidade;
    return next;
  };

  const buildFormForContext = (item: Item) => {
    const next = buildFormFromItem(item);
    if (lockedFinalidade) next.finalidade = lockedFinalidade;
    return next;
  };

  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const te = useTenantEmpresa();
  const tenantId = te.tenantId;
  const empresaId = te.empresaId;
  const tenantEmpresaLoading = te.loading;
  const { has, loading: permissionsLoading, ready, capabilities } = usePermissions();
  const empresaPapel = String(te.empresa?.papel ?? "")
    .trim()
    .toUpperCase();
  const canViewByEmpresaPapel = Boolean(
    empresaPapel && ["ADMIN", "DIRETOR", "COORDENACAO", "ALMOXARIFADO", "FINANCEIRO", "COMPRAS", "FATURAMENTO"].includes(empresaPapel)
  );
  const canViewImobilizadoItens =
    lockedFinalidade === "imobilizado" && (has("imobilizado.read") === true || has("imobilizado.write") === true);
  const canView = requireAny(capabilities, ["estoque.read", "os.read", "cad_itens.write"]) || canViewByEmpresaPapel || canViewImobilizadoItens;
  const canEdit =
    requireAny(capabilities, ["estoque.write", "cad_itens.write"]) ||
    (lockedFinalidade === "imobilizado" && has("imobilizado.write") === true);
  const canUseItemActions =
    has("cad_itens.write") === true || (lockedFinalidade === "imobilizado" && has("imobilizado.write") === true);
  const canEditFiscal = has("fiscal_itens.write");

  const [rows, setRows] = useState<Item[]>([]);
  const [fornecedores, setFornecedores] = useState<Fornecedor[]>([]);
  const [motivos, setMotivos] = useState<Array<{ id: string; codigo: string; nome: string }>>([]);
  const [motivosLoading, setMotivosLoading] = useState(false);
  const [supportsMotivoCompra, setSupportsMotivoCompra] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [showForm, setShowForm] = useState(false);
  const [activeTab, setActiveTab] = useState<"geral" | "fiscal">("geral");

  // filtros
  const [listLoading, setListLoading] = useState(false);
  const filtrosFormRef = useRef<HTMLFormElement | null>(null);

  const [draftFilterId, setDraftFilterId] = useState("");
  const [draftFilterCodigo, setDraftFilterCodigo] = useState("");
  const [draftFilterProduto, setDraftFilterProduto] = useState("");
  const [draftFilterFornecedor, setDraftFilterFornecedor] = useState("");
  const [draftFilterTipo, setDraftFilterTipo] = useState<"" | Item["tipo"]>("");
  const [draftFilterFinalidade, setDraftFilterFinalidade] = useState<"" | ItemFinalidade>(lockedFinalidade);
  const [draftFilterAtivo, setDraftFilterAtivo] = useState<"todos" | "ativos">("todos");

  const [filterId, setFilterId] = useState("");
  const [filterCodigo, setFilterCodigo] = useState("");
  const [filterProduto, setFilterProduto] = useState("");
  const [filterFornecedor, setFilterFornecedor] = useState("");
  const [filterTipo, setFilterTipo] = useState<"" | Item["tipo"]>("");
  const [filterFinalidade, setFilterFinalidade] = useState<"" | ItemFinalidade>(lockedFinalidade);
  const [filterAtivo, setFilterAtivo] = useState<"todos" | "ativos">("todos");

  type SortKey = "id" | "codigo_interno" | "nome" | "tipo" | "finalidade" | "fornecedor" | "ativo";
  const [sort, setSort] = useState<{ key: SortKey; dir: "desc" | "asc" }>({ key: "nome", dir: "asc" });
  const [page, setPage] = useState(1);
  const [totalCount, setTotalCount] = useState(0);

  // form (criar/editar)
  const [form, setForm] = useState<ItemForm>(emptyFormForContext);
  const [fiscalForm, setFiscalForm] = useState<FiscalForm>(emptyFiscalForm());
  const [initialFiscalSnapshot, setInitialFiscalSnapshot] = useState(() => serializeFiscalForm(emptyFiscalForm()));
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editingAudit, setEditingAudit] = useState<ItemAudit | null>(null);

  useEffect(() => {
    if (!isFinalidadeLocked) return;
    setDraftFilterFinalidade(lockedFinalidade);
    setFilterFinalidade(lockedFinalidade);
    setForm((prev) => (prev.finalidade === lockedFinalidade ? prev : { ...prev, finalidade: lockedFinalidade }));
  }, [isFinalidadeLocked, lockedFinalidade]);

  useEffect(() => {
    const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));
    if (page > totalPages) setPage(totalPages);
  }, [page, totalCount]);

  function openPrint() {
    const params = new URLSearchParams();

    const id = filterId.trim();
    const codigo = filterCodigo.trim();
    const produto = filterProduto.trim();

    if (id) params.set("id", id);
    if (codigo) params.set("codigo", codigo);
    if (produto) params.set("produto", produto);

    const qCompat = [codigo, produto].filter(Boolean).join(" ").trim();
    if (qCompat) params.set("q", qCompat);
    if (filterFornecedor.trim()) params.set("fornecedor", filterFornecedor.trim());
    if (filterTipo) params.set("tipo", filterTipo);
    if (filterFinalidade) params.set("finalidade", filterFinalidade);
    if (filterAtivo !== "todos") params.set("ativo", filterAtivo);

    const url = params.toString() ? `/itens/imprimir?${params.toString()}` : "/itens/imprimir";
    window.open(url, "_blank", "noopener,noreferrer");
  }

  async function loadFornecedores() {
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) return;
    const { data, error } = await supabase
      .from("fornecedores")
      .select("id,nome,ativo")
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .eq("ativo", true)
      .order("nome", { ascending: true })
      .limit(500);

    if (!error) setFornecedores((data ?? []) as unknown as Fornecedor[]);
  }

  async function loadMotivos() {
    if (tenantEmpresaLoading) return;
    if (!tenantId) return;
    setMotivosLoading(true);
    try {
      const { data: sess } = await supabase.auth.getSession();
      const token = sess.session?.access_token ?? null;
      if (!token) {
        setMotivos([]);
        return;
      }

      const res = await fetch("/api/estoque/motivos-compra", {
        headers: { authorization: `Bearer ${token}` },
      });

      const jsonUnknown: unknown = await res.json().catch(() => null);
      const json = jsonUnknown && typeof jsonUnknown === "object" ? (jsonUnknown as Record<string, unknown>) : null;
      const list = Array.isArray(json?.motivos) ? (json!.motivos as unknown[]) : [];
      const parsed = list
        .map((r) => (r && typeof r === "object" ? (r as Record<string, unknown>) : null))
        .filter(Boolean)
        .map((r) => ({
          id: String(r!.id ?? ""),
          codigo: String(r!.codigo ?? ""),
          nome: String(r!.nome ?? ""),
        }))
        .filter((m) => m.id && m.codigo && m.nome);

      setMotivos(parsed);
    } catch {
      setMotivos([]);
    } finally {
      setMotivosLoading(false);
    }
  }

  async function load() {
    setErr(null);
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) {
      setErr("Tenant/empresa nao carregados.");
      return;
    }

    setListLoading(true);

    const isMissingMotivoCompraColumn = (message: string) =>
      message.toLowerCase().includes("motivo_compra_id") && message.toLowerCase().includes("does not exist");

    const selectBase =
      "id,codigo_interno,codigo_barras,nome,descricao,tipo,categoria,subcategoria,fabricante,finalidade,unidade_medida,controla_estoque,estoque_minimo,estoque_maximo,estoque_ideal,custo_ultima_compra,custo_medio,preco_unitario,fornecedor_id,fornecedores!itens_tenant_empresa_fornecedor_fk(nome),ativo,criado_em,criado_por,atualizado_em,atualizado_por" as const;
    const selectWithMotivo =
      "id,codigo_interno,codigo_barras,nome,descricao,tipo,categoria,subcategoria,fabricante,finalidade,motivo_compra_id,unidade_medida,controla_estoque,estoque_minimo,estoque_maximo,estoque_ideal,custo_ultima_compra,custo_medio,preco_unitario,fornecedor_id,fornecedores!itens_tenant_empresa_fornecedor_fk(nome),ativo,criado_em,criado_por,atualizado_em,atualizado_por" as const;

    try {
      const from = (page - 1) * PAGE_SIZE;
      const to = from + PAGE_SIZE - 1;

      let query = supabase
        .from("itens")
        .select(
          (supportsMotivoCompra ? selectWithMotivo : selectBase) as string,
          { count: "exact" }
        )
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId);

      const idRaw = filterId.trim();
      if (idRaw) {
        const parsed = Number.parseInt(idRaw, 10);
        if (!Number.isFinite(parsed)) {
          setErr("ID invalido.");
          setRows([]);
          setTotalCount(0);
          return;
        }
        query = query.eq("id", parsed);
      }

      const codigo = filterCodigo.trim().replace(/,/g, " ").replace(/\s+/g, " ").trim();
      if (codigo) {
        query = /^\d+$/.test(codigo)
          ? query.or(`codigo_interno.eq.${codigo},codigo_barras.eq.${codigo}`)
          : query.or(`codigo_interno.ilike.%${codigo}%,codigo_barras.ilike.%${codigo}%`);
      }

      const produto = filterProduto.trim();
      if (produto) {
        query = query.ilike("nome", `%${produto}%`);
      }

      const fornecedorTerm = filterFornecedor.trim();
      if (fornecedorTerm) {
        const norm = (s: string) =>
          s
            .normalize("NFD")
            // eslint-disable-next-line no-control-regex
            .replace(/[\u0300-\u036f]/g, "")
            .toLowerCase();

        // Use the cached fornecedores list when available; otherwise, fetch it to avoid
        // returning empty results just because the page hasn't loaded fornecedores yet.
        let baseFornecedores = fornecedores;
        if (baseFornecedores.length === 0) {
          const { data } = await supabase
            .from("fornecedores")
            .select("id,nome,ativo")
            .eq("tenant_id", tenantId)
            .eq("empresa_id", empresaId)
            .eq("ativo", true)
            .order("nome", { ascending: true })
            .limit(1000);
          baseFornecedores = (data ?? []) as unknown as Fornecedor[];
        }

        const term = norm(fornecedorTerm);
        const ids = baseFornecedores
          .filter((f) => norm(String(f.nome ?? "")).includes(term))
          .map((f) => f.id)
          .filter((v) => Number.isFinite(v));

        if (ids.length === 0) {
          setRows([]);
          setTotalCount(0);
          return;
        }

        query = query.in("fornecedor_id", ids);
      }

      if (filterTipo) query = query.eq("tipo", filterTipo);
      if (filterFinalidade) query = query.eq("finalidade", filterFinalidade);
      if (filterAtivo === "ativos") query = query.eq("ativo", true);

      const ascending = sort.dir === "asc";
      if (sort.key === "fornecedor") {
        query = query.order("nome", { foreignTable: "fornecedores", ascending });
      } else {
        query = query.order(sort.key, { ascending });
      }
      if (sort.key !== "id") query = query.order("id", { ascending: false });

      let { data, error, count } = await query.range(from, to);

      if (error) {
        if (supportsMotivoCompra && isMissingMotivoCompraColumn(error.message ?? "")) {
          setSupportsMotivoCompra(false);
          // Retry without motivo_compra_id so the page still loads.
          const retry = await supabase
            .from("itens")
            .select(selectBase as string, { count: "exact" })
            .eq("tenant_id", tenantId)
            .eq("empresa_id", empresaId)
            .order("nome", { ascending: true })
            .range(from, to);
          data = retry.data;
          error = retry.error;
          count = retry.count;
        }

        if (error) {
          setErr(error.message);
          setRows([]);
          setTotalCount(0);
          return;
        }
      }

      setTotalCount(count ?? 0);

      const baseRows = (data ?? []) as unknown as ItemBaseMaybeMotivo[];
      const itemIds = Array.from(new Set(baseRows.map((row) => row.id).filter(Number.isFinite)));
      const fiscalMap = new Map<number, FiscalItem>();
      const auditMap = new Map<number, ItemAudit>();

      if (itemIds.length > 0 && empresaId) {
        const { data: fiscalData, error: fiscalErr } = await applyTenantEmpresa(
          supabase
            .from("fiscal_itens")
            .select(
              "item_id,ncm,cst_icms,cst_pis,cst_cofins,aliq_icms,aliq_ipi,aliq_pis,aliq_cofins,credita_icms,ipi_entra_no_custo,credita_pis,credita_cofins"
            ),
          tenantId,
          empresaId
        ).in("item_id", itemIds);

        if (fiscalErr) {
          setErr(fiscalErr.message);
        } else {
          const fiscalRows = (fiscalData ?? []) as FiscalItem[];
          fiscalRows.forEach((row) => {
            fiscalMap.set(Number(row.item_id), row);
          });
        }
      }

      if (itemIds.length > 0 && empresaId) {
        const { data: auditData, error: auditError } = await supabase.rpc("list_itens_auditoria", {
          p_tenant_id: tenantId,
          p_empresa_id: empresaId,
          p_item_ids: itemIds,
        });

        if (auditError) {
          console.warn("[Itens] auditoria indisponível", auditError);
        } else {
          ((auditData ?? []) as ItemAudit[]).forEach((audit) => {
            auditMap.set(Number(audit.item_id), audit);
          });
        }
      }

      const merged = baseRows.map((row) => ({
        ...row,
        // In environments without the column, Supabase won't return it; normalize to null.
        motivo_compra_id: supportsMotivoCompra ? row.motivo_compra_id ?? null : null,
        fiscal_itens: fiscalMap.get(row.id) ?? null,
        auditoria:
          auditMap.get(row.id) ?? {
            item_id: row.id,
            acao: row.atualizado_por?.trim() ? "alteracao" : "criacao",
            data_acao: row.atualizado_por?.trim() ? row.atualizado_em : row.criado_em,
            autor_nome: row.atualizado_por?.trim() || row.criado_por?.trim() || "Não identificado",
            autor_identificador: row.atualizado_por?.trim() || row.criado_por?.trim() || null,
          },
      }));

      setRows(merged as Item[]);
    } finally {
      setListLoading(false);
    }
  }

  async function checkMotivoCompraSupport() {
    if (tenantEmpresaLoading) return;
    if (!tenantId) return;

    // Lightweight probe: if column exists, this succeeds (even with 0/1 rows).
    const { error } = await applyTenant(supabase.from("itens").select("id,motivo_compra_id").limit(1), tenantId);
    if (!error) {
      if (!supportsMotivoCompra) setSupportsMotivoCompra(true);
      return;
    }

    const msg = String(error.message ?? "");
    if (msg.toLowerCase().includes("motivo_compra_id") && msg.toLowerCase().includes("does not exist")) {
      if (supportsMotivoCompra) setSupportsMotivoCompra(false);
    }
  }

  useEffect(() => {
    void loadFornecedores();
    if (supportsMotivoCompra) void loadMotivos();
  }, [tenantId, tenantEmpresaLoading]);

  // If the page previously fell back due to missing column, keep rechecking periodically.
  // This lets the UI recover automatically after the migration is applied.
  useEffect(() => {
    if (tenantEmpresaLoading) return;
    if (!tenantId) return;
    if (supportsMotivoCompra) return;

    const handle = setTimeout(() => {
      void checkMotivoCompraSupport();
    }, 1500);

    return () => clearTimeout(handle);
  }, [supportsMotivoCompra, tenantEmpresaLoading, tenantId]);

  // When support toggles back on, fetch motivos and refresh the list.
  useEffect(() => {
    if (!supportsMotivoCompra) return;
    if (tenantEmpresaLoading) return;
    if (!tenantId) return;
    void loadMotivos();
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [supportsMotivoCompra]);

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    tenantId,
    empresaId,
    tenantEmpresaLoading,
    page,
    filterId,
    filterCodigo,
    filterProduto,
    filterFornecedor,
    filterTipo,
    filterFinalidade,
    filterAtivo,
    sort,
  ]);

  function resetFiltros() {
    setDraftFilterId("");
    setDraftFilterCodigo("");
    setDraftFilterProduto("");
    setDraftFilterFornecedor("");
    setDraftFilterTipo("");
    setDraftFilterFinalidade(lockedFinalidade);
    setDraftFilterAtivo("todos");

    setFilterId("");
    setFilterCodigo("");
    setFilterProduto("");
    setFilterFornecedor("");
    setFilterTipo("");
    setFilterFinalidade(lockedFinalidade);
    setFilterAtivo("todos");

    setSort({ key: "nome", dir: "asc" });
    setPage(1);
  }

  function toggleSort(key: SortKey) {
    setPage(1);
    setSort((prev) =>
      prev.key === key ? { key, dir: prev.dir === "desc" ? "asc" : "desc" } : { key, dir: "desc" }
    );
  }

  function sortIcon(key: SortKey) {
    if (sort.key !== key) return "";
    return sort.dir === "desc" ? "▼" : "▲";
  }

  function startNew() {
    setOk(null);
    setErr(null);
    if (!canEdit) {
      setErr("Sem permissao para criar itens.");
      return;
    }
    setEditingId(null);
    setEditingAudit(null);
    setForm(emptyFormForContext());
    {
      const emptyFiscal = emptyFiscalForm();
      setFiscalForm(emptyFiscal);
      setInitialFiscalSnapshot(serializeFiscalForm(emptyFiscal));
    }
    setActiveTab("geral");
    setShowForm(true);
  }

  function openEditorForItem(r: Item, nextEditingId: number) {
    setEditingId(nextEditingId);
    setEditingAudit(r.auditoria ?? null);
    setShowForm(true);
    setForm(buildFormForContext({ ...r, id: nextEditingId }));

    const nextFiscalForm = buildFiscalFormFromItem(r);
    setFiscalForm(nextFiscalForm);
    setInitialFiscalSnapshot(serializeFiscalForm(nextFiscalForm));
    setActiveTab("geral");
  }

  function startEdit(r: Item) {
    setOk(null);
    setErr(null);
    if (!canEdit) {
      setErr("Sem permissao para editar itens.");
      return;
    }
    openEditorForItem(r, r.id);
  }

  function closeForm() {
    setShowForm(false);
    setEditingId(null);
    setEditingAudit(null);
    setForm(emptyFormForContext());
    {
      const emptyFiscal = emptyFiscalForm();
      setFiscalForm(emptyFiscal);
      setInitialFiscalSnapshot(serializeFiscalForm(emptyFiscal));
    }
    setActiveTab("geral");
  }

  async function saveFiscal(itemId: number) {
    if (!tenantId || !empresaId) {
      return new Error("Tenant ou empresa nao carregados.");
    }
    const numOrNull = (v: number | null | undefined) => (Number.isFinite(v as number) ? Number(v) : null);
    const payload: FiscalPayload = {
      tenant_id: tenantId,
      empresa_id: empresaId,
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
      atualizado_em: new Date().toISOString(),
    };
    const { error } = await applyTenantEmpresa(
      supabase.from("fiscal_itens").upsert(payload, { onConflict: "tenant_id,empresa_id,item_id" }),
      tenantId,
      empresaId
    );
    return error;
  }

  async function generateCopyCodigo(baseCodigo: string) {
    if (!tenantId) throw new Error("Tenant nao carregado.");

    const normalizedBase = upper(baseCodigo).trim() || "ITEM";
    for (let copyIndex = 1; copyIndex <= 999; copyIndex += 1) {
      const suffix = copyIndex === 1 ? "-COPIA" : `-COPIA-${copyIndex}`;
      const baseMaxLength = Math.max(1, 50 - suffix.length);
      const candidateBase = normalizedBase.slice(0, baseMaxLength).trim() || normalizedBase.slice(0, baseMaxLength);
      const candidate = `${candidateBase}${suffix}`;

      const { data, error } = await applyTenant(
        supabase.from("itens").select("id").eq("codigo_interno", candidate).limit(1),
        tenantId
      );

      if (error) throw error;
      if (!Array.isArray(data) || data.length === 0) return candidate;
    }

    throw new Error("Nao foi possivel gerar um codigo interno unico para a copia.");
  }

  async function duplicateItem(r: Item) {
    setOk(null);
    setErr(null);

    if (!canEdit) {
      setErr("Sem permissao para copiar itens.");
      return;
    }

    if (!tenantId || !empresaId) {
      setErr("Contexto de tenant/empresa nao carregado.");
      return;
    }

    setBusy(true);

    try {
      const copiedCodigoInterno = await generateCopyCodigo(r.codigo_interno);
      const copiedAt = new Date().toISOString();
      const { data: sess } = await supabase.auth.getSession();
      const userEmail = sess.session?.user?.email ?? null;
      const isProduto = r.tipo === "produto";
      const controlaEstoque = isProduto ? !!r.controla_estoque : false;
      const copiedFinalidade = lockedFinalidade || (r.finalidade ? String(r.finalidade) : null);

      const payload = {
        tenant_id: tenantId,
        empresa_id: empresaId,
        codigo_interno: copiedCodigoInterno,
        codigo_barras: null,
        nome: upper(r.nome).trim(),
        descricao: upper(r.descricao).trim() || null,
        tipo: r.tipo,
        categoria: upper(r.categoria).trim() || null,
        subcategoria: upper(r.subcategoria).trim() || null,
        fabricante: upper(r.fabricante).trim() || null,
        finalidade: copiedFinalidade,
        motivo_compra_id: supportsMotivoCompra ? r.motivo_compra_id ?? null : null,
        unidade_medida: upper(r.unidade_medida || "UN").trim(),
        controla_estoque: controlaEstoque,
        estoque_minimo: controlaEstoque ? Number(r.estoque_minimo ?? 0) : 0,
        estoque_maximo: controlaEstoque ? Number(r.estoque_maximo ?? 0) : 0,
        estoque_ideal: controlaEstoque ? Number(r.estoque_ideal ?? 0) : 0,
        custo_ultima_compra: Number(r.custo_ultima_compra ?? 0),
        custo_medio: Number(r.custo_medio ?? 0),
        preco_unitario: Number(r.preco_unitario ?? 0),
        fornecedor_id: r.fornecedor_id ?? null,
        ativo: !!r.ativo,
        criado_por: userEmail,
        criado_em: copiedAt,
        atualizado_em: copiedAt,
      };

      const { data: insertedItem, error: insertError } = await supabase.from("itens").insert(payload).select("id").single();

      if (insertError) throw insertError;

      const newItemId = Number(insertedItem?.id ?? 0);
      if (!Number.isFinite(newItemId) || newItemId <= 0) {
        throw new Error("Falha ao copiar item: id nao retornado.");
      }

      let fiscalCopyError: string | null = null;
      let copiedFiscal: FiscalItem | null = null;

      if (canEditFiscal && r.fiscal_itens) {
        const fiscalPayload: FiscalPayload = {
          tenant_id: tenantId,
          empresa_id: empresaId,
          item_id: newItemId,
          ncm: r.fiscal_itens.ncm ?? null,
          cst_icms: r.fiscal_itens.cst_icms ?? null,
          cst_pis: r.fiscal_itens.cst_pis ?? null,
          cst_cofins: r.fiscal_itens.cst_cofins ?? null,
          aliq_icms: r.fiscal_itens.aliq_icms ?? null,
          aliq_ipi: r.fiscal_itens.aliq_ipi ?? null,
          aliq_pis: r.fiscal_itens.aliq_pis ?? null,
          aliq_cofins: r.fiscal_itens.aliq_cofins ?? null,
          credita_icms: !!r.fiscal_itens.credita_icms,
          ipi_entra_no_custo: !!r.fiscal_itens.ipi_entra_no_custo,
          credita_pis: !!r.fiscal_itens.credita_pis,
          credita_cofins: !!r.fiscal_itens.credita_cofins,
          atualizado_em: copiedAt,
        };

        const { error: fiscalError } = await applyTenantEmpresa(
          supabase.from("fiscal_itens").upsert(fiscalPayload, { onConflict: "tenant_id,empresa_id,item_id" }),
          tenantId,
          empresaId
        );

        if (fiscalError) {
          fiscalCopyError = fiscalError.message ?? "Erro ao copiar os dados fiscais.";
        } else {
          copiedFiscal = { ...r.fiscal_itens, item_id: newItemId };
        }
      }

      openEditorForItem(
        {
          ...r,
          id: newItemId,
          codigo_interno: copiedCodigoInterno,
          codigo_barras: null,
          finalidade: copiedFinalidade,
          fiscal_itens: copiedFiscal,
          criado_em: copiedAt,
          criado_por: userEmail,
          atualizado_em: copiedAt,
          atualizado_por: null,
          auditoria: {
            item_id: newItemId,
            acao: "criacao",
            data_acao: copiedAt,
            autor_nome: userEmail?.trim() || "Não identificado",
            autor_identificador: userEmail,
          },
        },
        newItemId
      );

      await load();

      if (fiscalCopyError) {
        setErr(`Item copiado para o ID ${newItemId}, mas os dados fiscais nao foram copiados: ${fiscalCopyError}`);
      } else {
        setOk(`Item copiado para o ID ${newItemId}. Codigo de barras limpo para evitar duplicidade.`);
      }
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Erro ao copiar item.";
      setErr(msg);
    } finally {
      setBusy(false);
    }
  }

  async function save() {
    setOk(null);
    setErr(null);
    if (!canEdit) {
      setErr("Sem permissao para salvar itens.");
      return;
    }

    if (!form.codigo_interno.trim()) return setErr("Código interno é obrigatório.");
    if (!form.nome.trim()) return setErr("Nome é obrigatório.");

    const isProduto = form.tipo === "produto";
    const controlaEstoque = isProduto ? form.controla_estoque : false;
    const finalidadeParaSalvar = lockedFinalidade || form.finalidade.trim();

    setBusy(true);

    const { data: sess } = await supabase.auth.getSession();
    const userEmail = sess.session?.user?.email ?? null;

    const payload: ItemPayload = {
      codigo_interno: upper(form.codigo_interno).trim(),
      codigo_barras: upper(form.codigo_barras).trim() || null,
      nome: upper(form.nome).trim(),
      descricao: upper(form.descricao).trim() || null,
      tipo: form.tipo,
      categoria: upper(form.categoria).trim() || null,
      subcategoria: upper(form.subcategoria).trim() || null,

      fabricante: upper(form.fabricante).trim() || null,
      finalidade: finalidadeParaSalvar || null,
      motivo_compra_id: supportsMotivoCompra ? form.motivo_compra_id.trim() || null : null,

      unidade_medida: upper(form.unidade_medida || "UN").trim(),
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

    let error: DbError = null;
    let itemId: number | null = editingId ?? null;

    if (editingId) {
      if (!tenantId) {
        setBusy(false);
        setErr("Tenant nao carregado.");
        return;
      }
      const res = await applyTenant(
        supabase.from("itens").update({ ...payload, atualizado_por: userEmail }),
        tenantId
      ).eq("id", editingId);
      error = res.error ?? null;
    } else {
      if (!tenantId) {
        setBusy(false);
        setErr("Tenant nao carregado.");
        return;
      }

      const res = await supabase
        .from("itens")
        .insert({ ...payload, tenant_id: tenantId, criado_por: userEmail, criado_em: new Date().toISOString() })
        .select("id")
        .single();

      error = res.error ?? null;
      itemId = res.data?.id ?? null;

    }

    setBusy(false);

    if (error) {
      const msg = String(error.message || "");
      if (msg.toLowerCase().includes("duplicate") || msg.toLowerCase().includes("unique")) {
        setBusy(false);
        return setErr("Código interno ou código de barras já existe. Ajuste e tente novamente.");
      }
      setBusy(false);
      return setErr(msg);
    }

    if (!itemId) {
      setBusy(false);
      return setErr("Falha ao salvar: id do item nao retornado.");
    }

    const fiscalChanged = serializeFiscalForm(fiscalForm) !== initialFiscalSnapshot;
    if (canEditFiscal && fiscalChanged) {
      const fiscalError = await saveFiscal(itemId);
      if (fiscalError) {
        setBusy(false);
        return setErr(fiscalError.message);
      }
    }

    setBusy(false);
    setOk(editingId ? "Item atualizado!" : "Item criado!");
    closeForm();
    await load();
  }

  async function toggleAtivo(id: number, to: boolean) {
    const ok = confirm(to ? "Ativar item?" : "Desativar item?");
    if (!ok) return;
    if (!canEdit) {
      setErr("Sem permissao para editar itens.");
      return;
    }

    setBusy(true);
    setErr(null);
    setOk(null);

    if (!tenantId) {
      setBusy(false);
      return setErr("Tenant nao carregado.");
    }
    const { data: sess } = await supabase.auth.getSession();
    const userEmail = sess.session?.user?.email ?? null;
    const { error } = await applyTenant(
      supabase
        .from("itens")
        .update({ ativo: to, atualizado_em: new Date().toISOString(), atualizado_por: userEmail }),
      tenantId
    ).eq("id", id);

    setBusy(false);
    if (error) return setErr(error.message);

    setOk(to ? "Item ativado." : "Item desativado.");
    await load();
  }

  function fornecedorNome(id: number | null) {
    if (!id) return "--";
    return fornecedores.find((f) => f.id === id)?.nome ?? `#${id}`;
  }

  function motivoCompraLabel(id: string | null) {
    if (!id) return "—";
    const m = motivos.find((x) => x.id === id);
    return m ? `${m.codigo} — ${m.nome}` : id;
  }

  if (!ready && permissionsLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-zinc-300">
        Carregando permissoes...
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

  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));
  const showingFrom = totalCount === 0 ? 0 : (page - 1) * PAGE_SIZE + 1;
  const showingTo = Math.min(page * PAGE_SIZE, totalCount);

  return (
    <div className="space-y-5 w-full pb-10">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">{title}</h1>
          <p className="text-sm text-zinc-400 mt-1">
            {description}
          </p>
        </div>

        <div className="flex items-center gap-2">
          {canUseItemActions && (
            <button
              onClick={startNew}
              className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-100 text-zinc-900 hover:bg-white font-medium shadow-sm"
            >
              Novo
            </button>
          )}

          <button
            onClick={load}
            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
          >
            Atualizar
          </button>
        </div>
      </div>

      <form
        ref={filtrosFormRef}
        onSubmit={(e) => {
          e.preventDefault();
          setErr(null);
          setOk(null);
          setPage(1);
          setFilterId(draftFilterId);
          setFilterCodigo(draftFilterCodigo);
          setFilterProduto(draftFilterProduto);
          setFilterFornecedor(draftFilterFornecedor);
          setFilterTipo(draftFilterTipo);
          setFilterFinalidade(lockedFinalidade || draftFilterFinalidade);
          setFilterAtivo(draftFilterAtivo);
        }}
        className="border border-zinc-800 rounded-xl p-4 bg-zinc-950"
      >
        <div className="grid grid-cols-1 md:grid-cols-8 gap-3">
          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Id</div>
            <input
              aria-label="Filtrar por id"
              type="number"
              inputMode="numeric"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftFilterId}
              onChange={(e) => setDraftFilterId(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  filtrosFormRef.current?.requestSubmit();
                }
              }}
              placeholder="Ex: 123"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Código</div>
            <input
              aria-label="Filtrar por código"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftFilterCodigo}
              onChange={(e) => setDraftFilterCodigo(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  filtrosFormRef.current?.requestSubmit();
                }
              }}
              placeholder="Código interno ou barras"
            />
          </div>

          <div className="space-y-1 md:col-span-2">
            <div className="text-xs text-zinc-400">Produto</div>
            <input
              aria-label="Filtrar por produto"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftFilterProduto}
              onChange={(e) => setDraftFilterProduto(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  filtrosFormRef.current?.requestSubmit();
                }
              }}
              placeholder="Nome do produto"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Fornecedor</div>
            <input
              aria-label="Filtrar por fornecedor (digite para buscar)"
              list="fornecedor-options"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftFilterFornecedor}
              onChange={(e) => setDraftFilterFornecedor(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  filtrosFormRef.current?.requestSubmit();
                }
              }}
              placeholder='Ex: "siemens"'
            />
            <datalist id="fornecedor-options">
              {fornecedores.map((f) => (
                <option key={f.id} value={String(f.nome ?? "").trim()} />
              ))}
            </datalist>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Tipo</div>
            <select
              aria-label="Filtrar por tipo"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftFilterTipo}
              onChange={(e) => setDraftFilterTipo(e.target.value as "" | Item["tipo"])}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  filtrosFormRef.current?.requestSubmit();
                }
              }}
            >
              <option value="">Todos</option>
              <option value="produto">Produto</option>
              <option value="servico">Serviço</option>
              <option value="despesa">Despesa</option>
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Finalidade</div>
            <select
              aria-label="Filtrar por finalidade"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40 disabled:opacity-80 disabled:cursor-not-allowed"
              value={lockedFinalidade || draftFilterFinalidade}
              onChange={(e) => {
                if (!isFinalidadeLocked) setDraftFilterFinalidade(e.target.value as "" | ItemFinalidade);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  filtrosFormRef.current?.requestSubmit();
                }
              }}
              disabled={isFinalidadeLocked}
            >
              <option value="">Todos</option>
              {ITEM_FINALIDADES.map((f) => (
                <option key={f} value={f}>
                  {String(f).replace(/_/g, " ")}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Ativo</div>
            <select
              aria-label="Filtrar por ativo"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftFilterAtivo}
              onChange={(e) => setDraftFilterAtivo(e.target.value as "todos" | "ativos")}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  filtrosFormRef.current?.requestSubmit();
                }
              }}
            >
              <option value="ativos">Ativo</option>
              <option value="todos">Ativo + inativo</option>
            </select>
          </div>
        </div>

        <div className="mt-3 flex items-center justify-between gap-3 flex-wrap">
          <div className="flex items-center gap-2">
            <button
              type="submit"
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
            >
              Aplicar filtros
            </button>
            <button
              type="button"
              onClick={() => void load()}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
            >
              Atualizar
            </button>
            <button
              type="button"
              onClick={openPrint}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
            >
              Imprimir
            </button>
            <button
              type="button"
              onClick={resetFiltros}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
            >
              Limpar
            </button>
            {listLoading && <div className="text-xs text-zinc-400">Carregando...</div>}
          </div>

          <div className="text-xs text-zinc-500">
            Página {page} de {totalPages} • {showingFrom}-{showingTo} de {totalCount}
          </div>
        </div>

        {err && <div className="text-sm text-red-400 mt-3">{err}</div>}
        {ok && <div className="text-sm text-emerald-300 mt-3">{ok}</div>}
      </form>

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950 shadow-sm">
        <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-900/80">
          <div className="text-sm text-zinc-300">{tableTitle}</div>
          <div className="text-xs text-zinc-500">
            {showingFrom}-{showingTo} de {totalCount}
          </div>
        </div>
        <div className="overflow-auto max-h-[70vh]">
          <table className="w-full text-sm">
            <thead className="sticky top-0 bg-zinc-950/90 backdrop-blur border-b border-zinc-800">
              <tr className="text-zinc-200">
                <th className="px-4 py-3 text-left w-20">
                  <button
                    type="button"
                    onClick={() => toggleSort("id")}
                    className="hover:underline inline-flex items-center gap-1"
                  >
                    <span>Id</span>
                    {sortIcon("id") ? <span className="text-xs text-zinc-400">{sortIcon("id")}</span> : null}
                  </button>
                </th>
                <th className="px-4 py-3 text-left min-w-[160px]">
                  <button
                    type="button"
                    onClick={() => toggleSort("codigo_interno")}
                    className="hover:underline inline-flex items-center gap-1"
                  >
                    <span>Código</span>
                    {sortIcon("codigo_interno") ? (
                      <span className="text-xs text-zinc-400">{sortIcon("codigo_interno")}</span>
                    ) : null}
                  </button>
                </th>
                <th className="px-4 py-3 text-left min-w-[280px]">
                  <button
                    type="button"
                    onClick={() => toggleSort("nome")}
                    className="hover:underline inline-flex items-center gap-1"
                  >
                    <span>Nome</span>
                    {sortIcon("nome") ? <span className="text-xs text-zinc-400">{sortIcon("nome")}</span> : null}
                  </button>
                </th>
                <th className="px-4 py-3 text-left">
                  <button
                    type="button"
                    onClick={() => toggleSort("tipo")}
                    className="hover:underline inline-flex items-center gap-1"
                  >
                    <span>Tipo</span>
                    {sortIcon("tipo") ? <span className="text-xs text-zinc-400">{sortIcon("tipo")}</span> : null}
                  </button>
                </th>
                <th className="px-4 py-3 text-left">
                  <button
                    type="button"
                    onClick={() => toggleSort("finalidade")}
                    className="hover:underline inline-flex items-center gap-1"
                  >
                    <span>Finalidade</span>
                    {sortIcon("finalidade") ? (
                      <span className="text-xs text-zinc-400">{sortIcon("finalidade")}</span>
                    ) : null}
                  </button>
                </th>
                {supportsMotivoCompra && (
                  <th className="px-4 py-3 text-left min-w-[220px]">Motivo</th>
                )}
                <th className="px-4 py-3 text-left min-w-[200px]">
                  <button
                    type="button"
                    onClick={() => toggleSort("fornecedor")}
                    className="hover:underline inline-flex items-center gap-1"
                  >
                    <span>Fornecedor</span>
                    {sortIcon("fornecedor") ? (
                      <span className="text-xs text-zinc-400">{sortIcon("fornecedor")}</span>
                    ) : null}
                  </button>
                </th>
                <th className="px-4 py-3 text-center">
                  <button
                    type="button"
                    onClick={() => toggleSort("ativo")}
                    className="hover:underline inline-flex items-center gap-1 justify-center w-full"
                  >
                    <span>Ativo</span>
                    {sortIcon("ativo") ? <span className="text-xs text-zinc-400">{sortIcon("ativo")}</span> : null}
                  </button>
                </th>
                <th className="px-4 py-3 text-center">Ações</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-zinc-800">
              {listLoading &&
                Array.from({ length: 8 }).map((_, idx) => (
                  <tr key={`sk-${idx}`} className="animate-pulse">
                    <td className="px-4 py-3">
                      <div className="h-4 w-12 bg-zinc-800 rounded" />
                    </td>
                    <td className="px-4 py-3">
                      <div className="h-4 w-24 bg-zinc-800 rounded" />
                    </td>
                    <td className="px-4 py-3">
                      <div className="h-4 w-56 bg-zinc-800 rounded" />
                    </td>
                    <td className="px-4 py-3">
                      <div className="h-4 w-20 bg-zinc-800 rounded" />
                    </td>
                    <td className="px-4 py-3">
                      <div className="h-4 w-24 bg-zinc-800 rounded" />
                    </td>
                    <td className="px-4 py-3">
                      <div className="h-4 w-40 bg-zinc-800 rounded" />
                    </td>
                    <td className="px-4 py-3">
                      <div className="h-4 w-32 bg-zinc-800 rounded" />
                    </td>
                    <td className="px-4 py-3">
                      <div className="h-6 w-16 bg-zinc-800 rounded-full mx-auto" />
                    </td>
                    <td className="px-4 py-3">
                      <div className="h-8 w-28 bg-zinc-800 rounded mx-auto" />
                    </td>
                  </tr>
                ))}

              {!listLoading &&
                rows.map((r) => (
                  <tr key={r.id} className="hover:bg-zinc-900/40">
                    <td className="px-4 py-3 font-medium whitespace-nowrap text-zinc-400 tabular-nums">{r.id}</td>
                    <td className="px-4 py-3 font-medium whitespace-nowrap">
                      <div>{r.codigo_interno}</div>
                      {r.codigo_barras ? <div className="text-xs text-zinc-500">{r.codigo_barras}</div> : null}
                    </td>
                    <td className="px-4 py-3 align-top">
                      <div className="font-medium">{r.nome}</div>
                      {r.categoria && (
                        <div className="text-xs text-zinc-400">
                          {r.categoria}
                          {r.subcategoria ? ` / ${r.subcategoria}` : ""}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3 text-zinc-300 capitalize">{r.tipo}</td>
                    <td className="px-4 py-3 text-zinc-300">{r.finalidade ? String(r.finalidade).replace(/_/g, " ") : "-"}</td>
                    {supportsMotivoCompra && (
                      <td className="px-4 py-3 text-zinc-300">{motivoCompraLabel(r.motivo_compra_id)}</td>
                    )}
                    <td className="px-4 py-3 text-zinc-300">{r.fornecedores?.nome ?? fornecedorNome(r.fornecedor_id)}</td>
                    <td className="px-4 py-3 text-center">
                      <span
                        className={
                          r.ativo
                            ? "inline-flex items-center rounded-full bg-emerald-950/40 text-emerald-300 border border-emerald-900/40 px-2 py-0.5 text-xs"
                            : "inline-flex items-center rounded-full bg-zinc-900/60 text-zinc-300 border border-zinc-800 px-2 py-0.5 text-xs"
                        }
                      >
                        {r.ativo ? "Ativo" : "Inativo"}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-center">
                      <div className="flex items-center justify-center gap-2">
                        {canUseItemActions && (
                          <button
                            onClick={() => startEdit(r)}
                            className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                          >
                            Editar
                          </button>
                        )}
                        {canUseItemActions && (
                          <button
                            onClick={() => void duplicateItem(r)}
                            disabled={busy}
                            className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60"
                          >
                            Copiar
                          </button>
                        )}
                        {canUseItemActions && (
                          <button
                            onClick={() => toggleAtivo(r.id, !r.ativo)}
                            className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                          >
                            {r.ativo ? "Desativar" : "Ativar"}
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}

              {!listLoading && rows.length === 0 && (
                <tr>
                  <td colSpan={supportsMotivoCompra ? 9 : 8} className="px-4 py-10 text-zinc-400 text-center">
                    Nenhum item encontrado.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        <div className="px-4 py-3 border-t border-zinc-900/80 bg-zinc-950">
          <Pagination page={page} totalPages={totalPages} onChange={setPage} />
        </div>
      </div>

      {showForm && (
        <div className="fixed inset-0 z-[60] bg-black/70 backdrop-blur-sm flex items-start justify-center p-4" onClick={(e) => e.target === e.currentTarget && closeForm()}>
          <div className="w-full max-w-4xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden animate-[fadeIn_150ms_ease-out]" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div>
                <div className="font-semibold">{editingId ? `Editar item #${editingId}` : "Novo item"}</div>
                <div className="text-xs text-zinc-400 mt-0.5">Preencha os campos e salve para registrar.</div>
                {editingId && editingAudit ? (
                  <div className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-zinc-300">
                    <span className="text-zinc-500">
                      {editingAudit.acao === "alteracao" ? "Última alteração por:" : "Cadastro criado por:"}
                    </span>
                    <span className="font-medium text-amber-300">{editingAudit.autor_nome}</span>
                    <span className="text-zinc-600">•</span>
                    <span className="tabular-nums text-zinc-400">{formatAuditDate(editingAudit.data_acao)}</span>
                  </div>
                ) : null}
              </div>
              <div className="flex items-center gap-2">
                <button onClick={closeForm} className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800">
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
              <div className="flex items-center gap-2 border-b border-zinc-800 pb-2">
                <button
                  className={`px-3 py-1.5 rounded-md text-sm ${activeTab === "geral" ? "bg-zinc-800 text-zinc-100" : "text-zinc-400 hover:text-zinc-100"}`}
                  onClick={() => setActiveTab("geral")}
                >
                  Dados gerais
                </button>
                <Can perm="fiscal_itens.write">
                  <button
                    className={`px-3 py-1.5 rounded-md text-sm ${activeTab === "fiscal" ? "bg-zinc-800 text-zinc-100" : "text-zinc-400 hover:text-zinc-100"}`}
                    onClick={() => setActiveTab("fiscal")}
                  >
                    Fiscal
                  </button>
                </Can>
              </div>

              {activeTab === "geral" ? (
                <>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Código interno *</div>
                      <input
                        aria-label="Código interno"
                        className="w-full px-3 py-2"
                        value={form.codigo_interno}
                        onChange={(e) => setForm((s) => ({ ...s, codigo_interno: upper(e.target.value) }))}
                      />
                    </div>

                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Código de barras</div>
                      <input
                        aria-label="Código de barras"
                        className="w-full px-3 py-2"
                        value={form.codigo_barras}
                        onChange={(e) => setForm((s) => ({ ...s, codigo_barras: upper(e.target.value) }))}
                      />
                    </div>

                    <div className="md:col-span-2 space-y-1">
                      <div className="text-xs text-zinc-400">Nome *</div>
                      <input
                        aria-label="Nome"
                        className="w-full px-3 py-2"
                        value={form.nome}
                        onChange={(e) => setForm((s) => ({ ...s, nome: upper(e.target.value) }))}
                      />
                    </div>

                    <div className="md:col-span-2 space-y-1">
                      <div className="text-xs text-zinc-400">Fornecedor</div>
                      <select
                        aria-label="Fornecedor"
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
                      <div className="text-xs text-zinc-400">Descrição</div>
                      <textarea
                        aria-label="Descrição"
                        className="w-full px-3 py-2 min-h-[70px]"
                        value={form.descricao}
                        onChange={(e) => setForm((s) => ({ ...s, descricao: upper(e.target.value) }))}
                      />
                    </div>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Tipo *</div>
                      <select
                        aria-label="Tipo"
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
                        <option value="servico">Serviço</option>
                        <option value="despesa">Despesa</option>
                      </select>
                    </div>

                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Finalidade</div>
                      <select
                        aria-label="Finalidade"
                        className="w-full px-3 py-2 disabled:opacity-80 disabled:cursor-not-allowed"
                        value={form.finalidade}
                        onChange={(e) => {
                          if (!isFinalidadeLocked) setForm((s) => ({ ...s, finalidade: e.target.value }));
                        }}
                        disabled={isFinalidadeLocked}
                      >
                        <option value="">(Sem)</option>
                        <option value="consumo">Consumo</option>
                        <option value="materia_prima">Matéria-prima</option>
                        <option value="revenda">Revenda</option>
                        <option value="imobilizado">Imobilizado</option>
                        <option value="outros">Outros</option>
                      </select>
                    </div>

                    {supportsMotivoCompra && (
                      <div className="space-y-1">
                        <div className="text-xs text-zinc-400">Classificação / Motivo</div>
                        <select
                          aria-label="Classificação / Motivo"
                          className="w-full px-3 py-2"
                          value={form.motivo_compra_id}
                          onChange={(e) => setForm((s) => ({ ...s, motivo_compra_id: e.target.value }))}
                          disabled={motivosLoading}
                        >
                          <option value="">(Sem)</option>
                          {motivos.map((m) => (
                            <option key={m.id} value={m.id}>
                              {m.codigo} — {m.nome}
                            </option>
                          ))}
                        </select>
                      </div>
                    )}

                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Unidade</div>
                      <input className="w-full px-3 py-2" value={form.unidade_medida} onChange={(e) => setForm((s) => ({ ...s, unidade_medida: upper(e.target.value) }))} placeholder="UN, KG, LT..." />
                    </div>

                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Categoria</div>
                      <input
                        aria-label="Categoria"
                        className="w-full px-3 py-2"
                        value={form.categoria}
                        onChange={(e) => setForm((s) => ({ ...s, categoria: upper(e.target.value) }))}
                      />
                    </div>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                    <div className="space-y-1 md:col-span-2">
                      <div className="text-xs text-zinc-400">Fabricante</div>
                      <input
                        aria-label="Fabricante"
                        className="w-full px-3 py-2"
                        value={form.fabricante}
                        onChange={(e) => setForm((s) => ({ ...s, fabricante: upper(e.target.value) }))}
                        placeholder="Ex: WEG, Siemens..."
                      />
                    </div>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Subcategoria</div>
                      <input
                        aria-label="Subcategoria"
                        className="w-full px-3 py-2"
                        value={form.subcategoria}
                        onChange={(e) => setForm((s) => ({ ...s, subcategoria: upper(e.target.value) }))}
                      />
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
                            aria-label="Estoque mínimo"
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
                            aria-label="Estoque ideal"
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
                            aria-label="Estoque máximo"
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
                      <input
                        aria-label="Custo última compra"
                        type="number"
                        className="w-full px-3 py-2"
                        value={form.custo_ultima_compra}
                        onChange={(e) => setForm((s) => ({ ...s, custo_ultima_compra: Number(e.target.value) }))}
                      />
                    </div>
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Custo medio</div>
                      <input
                        aria-label="Custo médio"
                        type="number"
                        className="w-full px-3 py-2"
                        value={form.custo_medio}
                        onChange={(e) => setForm((s) => ({ ...s, custo_medio: Number(e.target.value) }))}
                      />
                    </div>
                    <div className="space-y-1">
                      <div className="text-xs text-zinc-400">Preço unitário</div>
                      <input
                        aria-label="Preço unitário"
                        type="number"
                        className="w-full px-3 py-2"
                        value={form.preco_unitario}
                        onChange={(e) => setForm((s) => ({ ...s, preco_unitario: Number(e.target.value) }))}
                      />
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
                        aria-label="Aliquota ICMS (%)"
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
                        aria-label="Aliquota IPI (%)"
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
                        aria-label="Aliquota PIS (%)"
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
                        aria-label="Aliquota COFINS (%)"
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

function buildPaginationModel(currentPage: number, totalPages: number): Array<number | "..."> {
  const total = Math.max(1, totalPages);
  const current = Math.min(Math.max(1, currentPage), total);

  if (total <= 9) return Array.from({ length: total }, (_, i) => i + 1);

  const candidates = new Set<number>([1, 2, total - 1, total, current - 1, current, current + 1]);
  const pages = Array.from(candidates)
    .filter((p) => p >= 1 && p <= total)
    .sort((a, b) => a - b);

  const out: Array<number | "..."> = [];
  let prev: number | null = null;
  for (const p of pages) {
    if (prev !== null && p - prev > 1) out.push("...");
    out.push(p);
    prev = p;
  }
  return out;
}

function Pagination({
  page,
  totalPages,
  onChange,
}: {
  page: number;
  totalPages: number;
  onChange: (page: number) => void;
}) {
  const total = Math.max(1, totalPages);
  const current = Math.min(Math.max(1, page), total);
  const model = buildPaginationModel(current, total);

  return (
    <div className="flex items-center justify-between gap-3 flex-wrap">
      <div className="text-xs text-zinc-500">
        Página {current} de {total}
      </div>

      <div className="flex items-center gap-1">
        <button
          type="button"
          aria-label="Página anterior"
          disabled={current <= 1}
          onClick={() => onChange(Math.max(1, current - 1))}
          className="h-9 w-9 inline-flex items-center justify-center rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
        >
          ‹
        </button>

        {model.map((p, idx) => {
          if (p === "...") {
            return (
              <div key={`dots-${idx}`} className="px-2 text-zinc-500 select-none">
                ...
              </div>
            );
          }

          const isActive = p === current;
          return (
            <button
              key={p}
              type="button"
              aria-current={isActive ? "page" : undefined}
              onClick={() => onChange(p)}
              className={
                isActive
                  ? "h-9 min-w-9 px-3 rounded-md bg-zinc-100 text-zinc-900 font-medium"
                  : "h-9 min-w-9 px-3 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-200"
              }
            >
              {p}
            </button>
          );
        })}

        <button
          type="button"
          aria-label="Próxima página"
          disabled={current >= total}
          onClick={() => onChange(Math.min(total, current + 1))}
          className="h-9 w-9 inline-flex items-center justify-center rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
        >
          ›
        </button>
      </div>
    </div>
  );
}
