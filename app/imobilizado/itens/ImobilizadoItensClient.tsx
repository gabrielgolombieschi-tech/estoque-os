"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { formatDecimalBR, formatMoneyBR, parseMoneyBR } from "@/lib/decimal";

type NumericLike = number | string | null;

type Fornecedor = {
  id: number;
  nome: string | null;
  ativo: boolean | null;
};

type ImobilizadoStatus = "IMPORTADO" | "EM_USO" | "MANUTENCAO" | "BAIXADO" | "CANCELADO";

type ImobilizadoItemDb = {
  id: number;
  tenant_id: string;
  empresa_id: string;
  status: ImobilizadoStatus | string;
  origem: string | null;
  nf_entrada_id: number;
  nf_entrada_item_id: number;
  fornecedor_id: number | null;
  documento_chave: string | null;
  documento_numero: string | null;
  documento_serie: string | null;
  data_emissao: string | null;
  data_entrada: string | null;
  codigo_xml: string | null;
  codigo_fornecedor: string | null;
  codigo_normalizado: string | null;
  descricao: string;
  unidade: string | null;
  ncm: string | null;
  cfop: string | null;
  quantidade: NumericLike;
  valor_unitario: NumericLike;
  valor_total: NumericLike;
  patrimonio_codigo: string | null;
  categoria: string | null;
  subcategoria: string | null;
  marca: string | null;
  modelo: string | null;
  numero_serie: string | null;
  localizacao: string | null;
  data_inicio_uso: string | null;
  depreciavel: boolean | null;
  vida_util_meses: number | null;
  valor_residual: NumericLike;
  centro_custo: string | null;
  conta_contabil: string | null;
  observacoes: string | null;
  created_at: string | null;
  updated_at: string | null;
};

type ImobilizadoItem = Omit<
  ImobilizadoItemDb,
  "quantidade" | "valor_unitario" | "valor_total" | "valor_residual"
> & {
  quantidade: number;
  valor_unitario: number;
  valor_total: number;
  valor_residual: number;
};

type EditForm = {
  status: ImobilizadoStatus;
  patrimonio_codigo: string;
  categoria: string;
  subcategoria: string;
  marca: string;
  modelo: string;
  numero_serie: string;
  localizacao: string;
  data_inicio_uso: string;
  depreciavel: boolean;
  vida_util_meses: string;
  valor_residual: string;
  centro_custo: string;
  conta_contabil: string;
  observacoes: string;
};

type SortKey = "id" | "descricao" | "status" | "data_emissao" | "quantidade" | "valor_total" | "documento_numero";

const PAGE_SIZE = 100;

const STATUS_OPTIONS: ImobilizadoStatus[] = ["IMPORTADO", "EM_USO", "MANUTENCAO", "BAIXADO", "CANCELADO"];

const STATUS_LABELS: Record<ImobilizadoStatus, string> = {
  IMPORTADO: "Importado",
  EM_USO: "Em uso",
  MANUTENCAO: "Manutencao",
  BAIXADO: "Baixado",
  CANCELADO: "Cancelado",
};

const SELECT_FIELDS = [
  "id",
  "tenant_id",
  "empresa_id",
  "status",
  "origem",
  "nf_entrada_id",
  "nf_entrada_item_id",
  "fornecedor_id",
  "documento_chave",
  "documento_numero",
  "documento_serie",
  "data_emissao",
  "data_entrada",
  "codigo_xml",
  "codigo_fornecedor",
  "codigo_normalizado",
  "descricao",
  "unidade",
  "ncm",
  "cfop",
  "quantidade",
  "valor_unitario",
  "valor_total",
  "patrimonio_codigo",
  "categoria",
  "subcategoria",
  "marca",
  "modelo",
  "numero_serie",
  "localizacao",
  "data_inicio_uso",
  "depreciavel",
  "vida_util_meses",
  "valor_residual",
  "centro_custo",
  "conta_contabil",
  "observacoes",
  "created_at",
  "updated_at",
].join(",");

function toNumber(value: NumericLike | undefined) {
  const n = typeof value === "number" ? value : Number(value ?? 0);
  return Number.isFinite(n) ? n : 0;
}

function normalizeRow(row: ImobilizadoItemDb): ImobilizadoItem {
  return {
    ...row,
    quantidade: toNumber(row.quantidade),
    valor_unitario: toNumber(row.valor_unitario),
    valor_total: toNumber(row.valor_total),
    valor_residual: toNumber(row.valor_residual),
  };
}

function normalizeText(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toLowerCase();
}

function nullableText(value: string) {
  const text = value.trim();
  return text ? text : null;
}

function upperOrNull(value: string) {
  const text = value.trim().toUpperCase();
  return text ? text : null;
}

function formatDateBR(value: string | null | undefined) {
  if (!value) return "-";
  const date = new Date(`${String(value).slice(0, 10)}T00:00:00`);
  if (Number.isNaN(date.getTime())) return String(value).slice(0, 10);
  return date.toLocaleDateString("pt-BR");
}

function statusLabel(value: string | null | undefined) {
  const key = String(value ?? "") as ImobilizadoStatus;
  return STATUS_LABELS[key] ?? String(value ?? "-");
}

function buildForm(row: ImobilizadoItem): EditForm {
  return {
    status: STATUS_OPTIONS.includes(row.status as ImobilizadoStatus) ? (row.status as ImobilizadoStatus) : "IMPORTADO",
    patrimonio_codigo: row.patrimonio_codigo ?? "",
    categoria: row.categoria ?? "",
    subcategoria: row.subcategoria ?? "",
    marca: row.marca ?? "",
    modelo: row.modelo ?? "",
    numero_serie: row.numero_serie ?? "",
    localizacao: row.localizacao ?? "",
    data_inicio_uso: row.data_inicio_uso ? String(row.data_inicio_uso).slice(0, 10) : "",
    depreciavel: row.depreciavel !== false,
    vida_util_meses: row.vida_util_meses == null ? "" : String(row.vida_util_meses),
    valor_residual: formatMoneyBR(row.valor_residual),
    centro_custo: row.centro_custo ?? "",
    conta_contabil: row.conta_contabil ?? "",
    observacoes: row.observacoes ?? "",
  };
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
        Pagina {current} de {total}
      </div>

      <div className="flex items-center gap-1">
        <button
          type="button"
          aria-label="Pagina anterior"
          disabled={current <= 1}
          onClick={() => onChange(Math.max(1, current - 1))}
          className="h-9 w-9 inline-flex items-center justify-center rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
        >
          {"<"}
        </button>

        {model.map((p, idx) =>
          p === "..." ? (
            <div key={`dots-${idx}`} className="px-2 text-zinc-500 select-none">
              ...
            </div>
          ) : (
            <button
              key={p}
              type="button"
              aria-current={p === current ? "page" : undefined}
              onClick={() => onChange(p)}
              className={
                p === current
                  ? "h-9 min-w-9 px-3 rounded-md bg-zinc-100 text-zinc-900 font-medium"
                  : "h-9 min-w-9 px-3 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-200"
              }
            >
              {p}
            </button>
          )
        )}

        <button
          type="button"
          aria-label="Proxima pagina"
          disabled={current >= total}
          onClick={() => onChange(Math.min(total, current + 1))}
          className="h-9 w-9 inline-flex items-center justify-center rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
        >
          {">"}
        </button>
      </div>
    </div>
  );
}

export default function ImobilizadoItensClient() {
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

  const { tenantId, empresaId, loading: tenantEmpresaLoading, error: tenantEmpresaError } = useTenantEmpresa();
  const { has, loading: permissionsLoading, ready } = usePermissions();
  const canView = has("imobilizado.read") === true || has("imobilizado.write") === true;
  const canEdit = has("imobilizado.write") === true;

  const filtrosFormRef = useRef<HTMLFormElement | null>(null);

  const [rows, setRows] = useState<ImobilizadoItem[]>([]);
  const [fornecedores, setFornecedores] = useState<Fornecedor[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [listLoading, setListLoading] = useState(false);
  const [busy, setBusy] = useState(false);

  const [draftId, setDraftId] = useState("");
  const [draftCodigo, setDraftCodigo] = useState("");
  const [draftDescricao, setDraftDescricao] = useState("");
  const [draftFornecedor, setDraftFornecedor] = useState("");
  const [draftDocumento, setDraftDocumento] = useState("");
  const [draftStatus, setDraftStatus] = useState<"" | ImobilizadoStatus>("");

  const [filterId, setFilterId] = useState("");
  const [filterCodigo, setFilterCodigo] = useState("");
  const [filterDescricao, setFilterDescricao] = useState("");
  const [filterFornecedor, setFilterFornecedor] = useState("");
  const [filterDocumento, setFilterDocumento] = useState("");
  const [filterStatus, setFilterStatus] = useState<"" | ImobilizadoStatus>("");

  const [sort, setSort] = useState<{ key: SortKey; dir: "desc" | "asc" }>({ key: "id", dir: "desc" });
  const [page, setPage] = useState(1);
  const [totalCount, setTotalCount] = useState(0);

  const [editing, setEditing] = useState<ImobilizadoItem | null>(null);
  const [form, setForm] = useState<EditForm | null>(null);

  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));
  const showingFrom = totalCount === 0 ? 0 : (page - 1) * PAGE_SIZE + 1;
  const showingTo = Math.min(page * PAGE_SIZE, totalCount);
  const pageTotal = rows.reduce((sum, row) => sum + row.valor_total, 0);

  async function fetchFornecedores() {
    if (tenantEmpresaLoading || !tenantId || !empresaId) return [];

    const { data, error } = await supabase
      .from("fornecedores")
      .select("id,nome,ativo")
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .order("nome", { ascending: true })
      .limit(1000)
      .returns<Fornecedor[]>();

    if (error) {
      setErr(error.message);
      return [];
    }

    const next = data ?? [];
    setFornecedores(next);
    return next;
  }

  function fornecedorNome(id: number | null) {
    if (!id) return "-";
    return fornecedores.find((f) => f.id === id)?.nome ?? `#${id}`;
  }

  async function load() {
    setErr(null);
    if (tenantEmpresaLoading) return;
    if (!tenantId || !empresaId) {
      setErr("Tenant ou empresa nao carregados.");
      return;
    }

    setListLoading(true);

    try {
      const from = (page - 1) * PAGE_SIZE;
      const to = from + PAGE_SIZE - 1;

      let query = supabase
        .from("imobilizado_itens")
        .select(SELECT_FIELDS, { count: "exact" })
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .is("deleted_at", null);

      const idRaw = filterId.trim();
      if (idRaw) {
        const parsed = Number.parseInt(idRaw, 10);
        if (!Number.isFinite(parsed)) {
          setRows([]);
          setTotalCount(0);
          setErr("ID invalido.");
          return;
        }
        query = query.eq("id", parsed);
      }

      const codigo = filterCodigo.trim().replace(/,/g, " ").replace(/\s+/g, " ").trim();
      if (codigo) {
        query = query.or(
          `codigo_normalizado.ilike.%${codigo}%,codigo_fornecedor.ilike.%${codigo}%,codigo_xml.ilike.%${codigo}%,ean.ilike.%${codigo}%`
        );
      }

      const descricao = filterDescricao.trim();
      if (descricao) query = query.ilike("descricao", `%${descricao}%`);

      const documento = filterDocumento.trim().replace(/,/g, " ").replace(/\s+/g, " ").trim();
      if (documento) {
        query = query.or(`documento_numero.ilike.%${documento}%,documento_chave.ilike.%${documento}%`);
      }

      if (filterStatus) query = query.eq("status", filterStatus);

      const fornecedorTerm = filterFornecedor.trim();
      if (fornecedorTerm) {
        const baseFornecedores = fornecedores.length > 0 ? fornecedores : await fetchFornecedores();
        const term = normalizeText(fornecedorTerm);
        const ids = baseFornecedores
          .filter((f) => normalizeText(String(f.nome ?? "")).includes(term))
          .map((f) => f.id)
          .filter((v) => Number.isFinite(v));

        if (ids.length === 0) {
          setRows([]);
          setTotalCount(0);
          return;
        }

        query = query.in("fornecedor_id", ids);
      }

      query = query.order(sort.key, { ascending: sort.dir === "asc" });
      if (sort.key !== "id") query = query.order("id", { ascending: false });

      const { data, error, count } = await query.range(from, to).returns<ImobilizadoItemDb[]>();

      if (error) {
        setRows([]);
        setTotalCount(0);
        setErr(error.message);
        return;
      }

      setRows((data ?? []).map(normalizeRow));
      setTotalCount(count ?? 0);
    } finally {
      setListLoading(false);
    }
  }

  useEffect(() => {
    void fetchFornecedores();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, empresaId, tenantEmpresaLoading]);

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
    filterDescricao,
    filterFornecedor,
    filterDocumento,
    filterStatus,
    sort,
  ]);

  useEffect(() => {
    const nextTotal = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));
    if (page > nextTotal) setPage(nextTotal);
  }, [page, totalCount]);

  function resetFiltros() {
    setDraftId("");
    setDraftCodigo("");
    setDraftDescricao("");
    setDraftFornecedor("");
    setDraftDocumento("");
    setDraftStatus("");
    setFilterId("");
    setFilterCodigo("");
    setFilterDescricao("");
    setFilterFornecedor("");
    setFilterDocumento("");
    setFilterStatus("");
    setSort({ key: "id", dir: "desc" });
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
    return sort.dir === "desc" ? "v" : "^";
  }

  function startEdit(row: ImobilizadoItem) {
    setErr(null);
    setOk(null);
    setEditing(row);
    setForm(buildForm(row));
  }

  function closeEdit() {
    setEditing(null);
    setForm(null);
  }

  async function saveEdit() {
    if (!canEdit) {
      setErr("Sem permissao para editar itens do imobilizado.");
      return;
    }
    if (!tenantId || !empresaId || !editing || !form) {
      setErr("Contexto de tenant/empresa nao carregado.");
      return;
    }

    const vidaUtilText = form.vida_util_meses.trim();
    const vidaUtil = vidaUtilText ? Number.parseInt(vidaUtilText, 10) : null;
    if (vidaUtilText && (!Number.isFinite(vidaUtil) || Number(vidaUtil) < 0)) {
      setErr("Vida util deve ser um numero inteiro positivo.");
      return;
    }

    const valorResidual = parseMoneyBR(form.valor_residual);
    if (!Number.isFinite(valorResidual) || valorResidual < 0) {
      setErr("Valor residual invalido.");
      return;
    }

    setBusy(true);
    setErr(null);
    setOk(null);

    const { data: sessionData } = await supabase.auth.getSession();
    const userId = sessionData.session?.user?.id ?? null;

    const { error } = await supabase
      .from("imobilizado_itens")
      .update({
        status: form.status,
        patrimonio_codigo: upperOrNull(form.patrimonio_codigo),
        categoria: upperOrNull(form.categoria),
        subcategoria: upperOrNull(form.subcategoria),
        marca: upperOrNull(form.marca),
        modelo: upperOrNull(form.modelo),
        numero_serie: upperOrNull(form.numero_serie),
        localizacao: upperOrNull(form.localizacao),
        data_inicio_uso: form.data_inicio_uso || null,
        depreciavel: form.depreciavel,
        vida_util_meses: vidaUtil,
        valor_residual: valorResidual,
        centro_custo: upperOrNull(form.centro_custo),
        conta_contabil: upperOrNull(form.conta_contabil),
        observacoes: nullableText(form.observacoes),
        updated_by: userId,
      })
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .eq("id", editing.id);

    setBusy(false);
    if (error) {
      setErr(error.message);
      return;
    }

    setOk("Item do imobilizado atualizado.");
    closeEdit();
    await load();
  }

  if (tenantEmpresaError) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300 p-6">{tenantEmpresaError}</div>;
  }

  if (tenantEmpresaLoading || (!ready && permissionsLoading)) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando...</div>;
  }

  if (!canView) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;
  }

  return (
    <div className="space-y-5 w-full pb-10">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Itens do Imobilizado</h1>
          <p className="text-sm text-zinc-400 mt-1">
            Itens importados como imobilizado, vindos da tabela documental do XML.
          </p>
        </div>

        <button
          type="button"
          onClick={() => void load()}
          className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
        >
          Atualizar
        </button>
      </div>

      <form
        ref={filtrosFormRef}
        onSubmit={(e) => {
          e.preventDefault();
          setErr(null);
          setOk(null);
          setPage(1);
          setFilterId(draftId);
          setFilterCodigo(draftCodigo);
          setFilterDescricao(draftDescricao);
          setFilterFornecedor(draftFornecedor);
          setFilterDocumento(draftDocumento);
          setFilterStatus(draftStatus);
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
              value={draftId}
              onChange={(e) => setDraftId(e.target.value)}
              placeholder="Ex: 123"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Codigo</div>
            <input
              aria-label="Filtrar por codigo"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftCodigo}
              onChange={(e) => setDraftCodigo(e.target.value)}
              placeholder="XML / fornecedor"
            />
          </div>

          <div className="space-y-1 md:col-span-2">
            <div className="text-xs text-zinc-400">Descricao</div>
            <input
              aria-label="Filtrar por descricao"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftDescricao}
              onChange={(e) => setDraftDescricao(e.target.value)}
              placeholder="Nome do item"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Fornecedor</div>
            <input
              aria-label="Filtrar por fornecedor"
              list="fornecedor-imobilizado-options"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftFornecedor}
              onChange={(e) => setDraftFornecedor(e.target.value)}
              placeholder="Nome"
            />
            <datalist id="fornecedor-imobilizado-options">
              {fornecedores.map((f) => (
                <option key={f.id} value={String(f.nome ?? "").trim()} />
              ))}
            </datalist>
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">NF</div>
            <input
              aria-label="Filtrar por NF"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftDocumento}
              onChange={(e) => setDraftDocumento(e.target.value)}
              placeholder="Numero/chave"
            />
          </div>

          <div className="space-y-1">
            <div className="text-xs text-zinc-400">Status</div>
            <select
              aria-label="Filtrar por status"
              className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40"
              value={draftStatus}
              onChange={(e) => setDraftStatus(e.target.value as "" | ImobilizadoStatus)}
            >
              <option value="">Todos</option>
              {STATUS_OPTIONS.map((status) => (
                <option key={status} value={status}>
                  {STATUS_LABELS[status]}
                </option>
              ))}
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
              onClick={resetFiltros}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
            >
              Limpar
            </button>
            {listLoading && <div className="text-xs text-zinc-400">Carregando...</div>}
          </div>

          <div className="text-xs text-zinc-500">
            Pagina {page} de {totalPages} - {showingFrom}-{showingTo} de {totalCount} - Total da pagina: R${" "}
            {formatMoneyBR(pageTotal)}
          </div>
        </div>

        {err && <div className="text-sm text-red-400 mt-3">{err}</div>}
        {ok && <div className="text-sm text-emerald-300 mt-3">{ok}</div>}
      </form>

      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950 shadow-sm">
        <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-900/80">
          <div className="text-sm text-zinc-300">Itens importados como imobilizado</div>
          <div className="text-xs text-zinc-500">
            {showingFrom}-{showingTo} de {totalCount}
          </div>
        </div>

        <div className="overflow-auto max-h-[70vh]">
          <table className="w-full text-sm">
            <thead className="sticky top-0 bg-zinc-950/90 backdrop-blur border-b border-zinc-800">
              <tr className="text-zinc-400">
                <th className="px-4 py-3 text-left">
                  <button type="button" onClick={() => toggleSort("id")} className="hover:underline inline-flex gap-1">
                    <span>Id</span>
                    {sortIcon("id") && <span className="text-xs">{sortIcon("id")}</span>}
                  </button>
                </th>
                <th className="px-4 py-3 text-left">Codigo</th>
                <th className="px-4 py-3 text-left min-w-[280px]">
                  <button
                    type="button"
                    onClick={() => toggleSort("descricao")}
                    className="hover:underline inline-flex gap-1"
                  >
                    <span>Descricao</span>
                    {sortIcon("descricao") && <span className="text-xs">{sortIcon("descricao")}</span>}
                  </button>
                </th>
                <th className="px-4 py-3 text-left">
                  <button
                    type="button"
                    onClick={() => toggleSort("documento_numero")}
                    className="hover:underline inline-flex gap-1"
                  >
                    <span>NF</span>
                    {sortIcon("documento_numero") && <span className="text-xs">{sortIcon("documento_numero")}</span>}
                  </button>
                </th>
                <th className="px-4 py-3 text-left">
                  <button
                    type="button"
                    onClick={() => toggleSort("data_emissao")}
                    className="hover:underline inline-flex gap-1"
                  >
                    <span>Emissao</span>
                    {sortIcon("data_emissao") && <span className="text-xs">{sortIcon("data_emissao")}</span>}
                  </button>
                </th>
                <th className="px-4 py-3 text-left min-w-[180px]">Fornecedor</th>
                <th className="px-4 py-3 text-right">
                  <button
                    type="button"
                    onClick={() => toggleSort("quantidade")}
                    className="hover:underline inline-flex gap-1"
                  >
                    <span>Qtd</span>
                    {sortIcon("quantidade") && <span className="text-xs">{sortIcon("quantidade")}</span>}
                  </button>
                </th>
                <th className="px-4 py-3 text-right">
                  <button
                    type="button"
                    onClick={() => toggleSort("valor_total")}
                    className="hover:underline inline-flex gap-1"
                  >
                    <span>Valor</span>
                    {sortIcon("valor_total") && <span className="text-xs">{sortIcon("valor_total")}</span>}
                  </button>
                </th>
                <th className="px-4 py-3 text-left">Patrimonio</th>
                <th className="px-4 py-3 text-center">
                  <button
                    type="button"
                    onClick={() => toggleSort("status")}
                    className="hover:underline inline-flex gap-1 justify-center w-full"
                  >
                    <span>Status</span>
                    {sortIcon("status") && <span className="text-xs">{sortIcon("status")}</span>}
                  </button>
                </th>
                <th className="px-4 py-3 text-center">Acoes</th>
              </tr>
            </thead>

            <tbody className="divide-y divide-zinc-800">
              {listLoading &&
                Array.from({ length: 8 }).map((_, idx) => (
                  <tr key={`sk-${idx}`} className="animate-pulse">
                    {Array.from({ length: 11 }).map((__, colIdx) => (
                      <td key={colIdx} className="px-4 py-3">
                        <div className="h-4 bg-zinc-800 rounded" />
                      </td>
                    ))}
                  </tr>
                ))}

              {!listLoading &&
                rows.map((row) => (
                  <tr key={row.id} className="hover:bg-zinc-900/40">
                    <td className="px-4 py-3 font-medium whitespace-nowrap text-zinc-400 tabular-nums">{row.id}</td>
                    <td className="px-4 py-3 whitespace-nowrap">
                      <div className="font-medium">{row.codigo_normalizado || row.codigo_fornecedor || row.codigo_xml || "-"}</div>
                      {row.ncm ? <div className="text-xs text-zinc-500">NCM {row.ncm}</div> : null}
                    </td>
                    <td className="px-4 py-3 align-top">
                      <div className="font-medium">{row.descricao}</div>
                      <div className="text-xs text-zinc-500">
                        {[row.categoria, row.subcategoria, row.marca, row.modelo].filter(Boolean).join(" / ") || "-"}
                      </div>
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap">
                      <div>{row.documento_numero || "-"}</div>
                      {row.documento_serie ? <div className="text-xs text-zinc-500">Serie {row.documento_serie}</div> : null}
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-zinc-300">{formatDateBR(row.data_emissao)}</td>
                    <td className="px-4 py-3 text-zinc-300">{fornecedorNome(row.fornecedor_id)}</td>
                    <td className="px-4 py-3 text-right tabular-nums">
                      {formatDecimalBR(row.quantidade, 3)} {row.unidade ?? ""}
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums">R$ {formatMoneyBR(row.valor_total)}</td>
                    <td className="px-4 py-3">
                      <div>{row.patrimonio_codigo || "-"}</div>
                      {row.localizacao ? <div className="text-xs text-zinc-500">{row.localizacao}</div> : null}
                    </td>
                    <td className="px-4 py-3 text-center">
                      <span className="inline-flex items-center rounded-full bg-zinc-900/70 text-zinc-200 border border-zinc-800 px-2 py-0.5 text-xs">
                        {statusLabel(row.status)}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-center">
                      {canEdit ? (
                        <button
                          type="button"
                          onClick={() => startEdit(row)}
                          className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                        >
                          Editar
                        </button>
                      ) : (
                        <span className="text-xs text-zinc-500">-</span>
                      )}
                    </td>
                  </tr>
                ))}

              {!listLoading && rows.length === 0 && (
                <tr>
                  <td colSpan={11} className="px-4 py-10 text-zinc-400 text-center">
                    Nenhum item do imobilizado encontrado.
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

      {editing && form && (
        <div
          className="fixed inset-0 z-[60] bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeEdit()}
        >
          <div
            className="w-full max-w-4xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div>
                <div className="font-semibold">Editar item #{editing.id}</div>
                <div className="text-xs text-zinc-400 mt-0.5">{editing.descricao}</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={closeEdit}
                  className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                <button
                  type="button"
                  onClick={() => void saveEdit()}
                  disabled={busy}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
                >
                  {busy ? "Salvando..." : "Salvar"}
                </button>
              </div>
            </div>

            <div className="p-5 space-y-4 max-h-[75vh] overflow-y-auto">
              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Status</div>
                  <select
                    className="w-full px-3 py-2"
                    value={form.status}
                    onChange={(e) => setForm((s) => (s ? { ...s, status: e.target.value as ImobilizadoStatus } : s))}
                  >
                    {STATUS_OPTIONS.map((status) => (
                      <option key={status} value={status}>
                        {STATUS_LABELS[status]}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Patrimonio</div>
                  <input
                    className="w-full px-3 py-2"
                    value={form.patrimonio_codigo}
                    onChange={(e) => setForm((s) => (s ? { ...s, patrimonio_codigo: e.target.value } : s))}
                  />
                </div>

                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Data inicio uso</div>
                  <input
                    type="date"
                    className="w-full px-3 py-2"
                    value={form.data_inicio_uso}
                    onChange={(e) => setForm((s) => (s ? { ...s, data_inicio_uso: e.target.value } : s))}
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Categoria</div>
                  <input
                    className="w-full px-3 py-2"
                    value={form.categoria}
                    onChange={(e) => setForm((s) => (s ? { ...s, categoria: e.target.value } : s))}
                  />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Subcategoria</div>
                  <input
                    className="w-full px-3 py-2"
                    value={form.subcategoria}
                    onChange={(e) => setForm((s) => (s ? { ...s, subcategoria: e.target.value } : s))}
                  />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Localizacao</div>
                  <input
                    className="w-full px-3 py-2"
                    value={form.localizacao}
                    onChange={(e) => setForm((s) => (s ? { ...s, localizacao: e.target.value } : s))}
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Marca</div>
                  <input
                    className="w-full px-3 py-2"
                    value={form.marca}
                    onChange={(e) => setForm((s) => (s ? { ...s, marca: e.target.value } : s))}
                  />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Modelo</div>
                  <input
                    className="w-full px-3 py-2"
                    value={form.modelo}
                    onChange={(e) => setForm((s) => (s ? { ...s, modelo: e.target.value } : s))}
                  />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Numero de serie</div>
                  <input
                    className="w-full px-3 py-2"
                    value={form.numero_serie}
                    onChange={(e) => setForm((s) => (s ? { ...s, numero_serie: e.target.value } : s))}
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Depreciavel</div>
                  <label className="h-10 px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900/40 flex items-center gap-2">
                    <input
                      type="checkbox"
                      checked={form.depreciavel}
                      onChange={(e) => setForm((s) => (s ? { ...s, depreciavel: e.target.checked } : s))}
                    />
                    <span className="text-sm">Sim</span>
                  </label>
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Vida util (meses)</div>
                  <input
                    inputMode="numeric"
                    className="w-full px-3 py-2"
                    value={form.vida_util_meses}
                    onChange={(e) => setForm((s) => (s ? { ...s, vida_util_meses: e.target.value } : s))}
                  />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Valor residual</div>
                  <input
                    inputMode="decimal"
                    className="w-full px-3 py-2"
                    value={form.valor_residual}
                    onChange={(e) => setForm((s) => (s ? { ...s, valor_residual: e.target.value } : s))}
                  />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Centro de custo</div>
                  <input
                    className="w-full px-3 py-2"
                    value={form.centro_custo}
                    onChange={(e) => setForm((s) => (s ? { ...s, centro_custo: e.target.value } : s))}
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Conta contabil</div>
                  <input
                    className="w-full px-3 py-2"
                    value={form.conta_contabil}
                    onChange={(e) => setForm((s) => (s ? { ...s, conta_contabil: e.target.value } : s))}
                  />
                </div>
                <div className="md:col-span-2 space-y-1">
                  <div className="text-xs text-zinc-400">Observacoes</div>
                  <textarea
                    className="w-full px-3 py-2 min-h-[80px]"
                    value={form.observacoes}
                    onChange={(e) => setForm((s) => (s ? { ...s, observacoes: e.target.value } : s))}
                  />
                </div>
              </div>

              {err && <div className="text-sm text-red-400">{err}</div>}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
