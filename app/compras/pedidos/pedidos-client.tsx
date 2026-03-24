"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { supabaseBrowser } from "@/lib/supabase/client";

type FornPend = {
  fornecedor_id: number | null;
  fornecedor_nome: string;
  qtd_pendencias_abertas: number;
  qtd_total_pendente: number;
};

type FornecedorBase = {
  id: number;
  nome: string | null;
  ativo: boolean | null;
};

type PendDet = {
  pendencia_id: string;
  item_id?: number | null;
  fornecedor_nome: string;
  item_nome: string;
  unidade: string;
  quantidade: number;
  origem_tipo: string;
  numero_os?: string | null;
  os_num?: number | null;
  status: string;
};

type DetNewRowDraft = {
  item_nome: string;
  unidade: string;
  quantidade: string;
  valor_unitario: string;
  os_numero: string;
};

type AgrRow = {
  fornecedor_id: number | null;
  item_id: number | null;
  item_nome: string;
  unidade: string | null;
  pendencia_ids: string[] | null;
  qtd_os_total: number;
  qtd_em_compra_aberto: number;
  sugestao_min: number;
  sugestao_ideal: number;
  sugestao_max: number;
  estoque_pendencia_id: string | null;
  estoque_meta_atual: "MIN" | "IDEAL" | "MAX" | null;
  qtd_estoque_pendencia: number;
};

type Pedido = {
  id: string;
  codigo: string;
  status: string;
  fornecedor_id: number | null;
  fornecedor_nome?: string | null;
  solicitante_usuario_id?: string | null;
  solicitante_nome?: string | null;
  created_at: string;
  total_geral: number;
};

type PedidoItem = {
  id: string;
  item_id: number | null;
  item_codigo?: string | null;
  origem_resumo?: string | null;
  origem_os_id?: number | null;
  documento_ref_resumo?: string | null;
  item_nome: string;
  unidade: string;
  quantidade: number;
  quantidade_recebida: number;
  valor_unitario: number;
  valor_total: number;
};

type UsuarioSolicitante = {
  id: string;
  nome: string;
  email: string;
};

type LookupItemRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  unidade: string;
  fornecedor: string | null;
  ultima_entrada: string | null;
  preco_unitario: number;
  estoque_atual: number | null;
};

type LookupSortKey = "id" | "codigo" | "descricao" | "fornecedor" | "ultima" | "preco" | "saldo";
type LookupSortDir = "asc" | "desc";
type LookupSortValue = string | number | null;

async function authedFetch(path: string, init?: RequestInit) {
  const supabase = supabaseBrowser();
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error("Sessao expirada.");
  const res = await fetch(path, {
    ...init,
    cache: init?.cache ?? "no-store",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
  const raw = await res.text();
  const json = raw
    ? ((() => {
        try {
          return JSON.parse(raw) as Record<string, unknown>;
        } catch {
          return {};
        }
      })())
    : {};
  if (!res.ok) {
    const htmlLike = raw.trim().startsWith("<");
    const fallback = htmlLike ? `Erro de requisicao (${res.status}).` : raw.trim();
    const message = (json as { error?: string }).error ?? fallback ?? `Erro de requisicao (${res.status}).`;
    throw new Error(String(message));
  }
  return json as Record<string, unknown>;
}

function parseNum(v: unknown, def = 0) {
  const n = parseLocaleNumber(v);
  return n ?? def;
}

function parseQtyInput(v: string) {
  return parseLocaleNumber(v);
}

function parseMoneyInput(v: string) {
  return parseLocaleNumber(v);
}

function parseLocaleNumber(value: unknown): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  const raw = String(value ?? "").trim();
  if (!raw) return null;

  const compact = raw.replace(/\s+/g, "");
  const hasComma = compact.includes(",");
  const hasDot = compact.includes(".");
  let normalized = compact;

  if (hasComma && hasDot) {
    normalized =
      compact.lastIndexOf(",") > compact.lastIndexOf(".")
        ? compact.replace(/\./g, "").replace(",", ".")
        : compact.replace(/,/g, "");
  } else if (hasComma) {
    normalized = compact.replace(/\./g, "").replace(",", ".");
  }

  const n = Number(normalized);
  return Number.isFinite(n) ? n : null;
}

function formatEditableNumber(v: unknown, maxFractionDigits = 4): string {
  const n = Number(v ?? 0);
  if (!Number.isFinite(n)) return "0";
  return n.toLocaleString("pt-BR", { useGrouping: false, maximumFractionDigits: maxFractionDigits });
}

function fmtMoney(v: number) {
  return Number(v ?? 0).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
}

function fmtDate(v: string) {
  const d = new Date(v);
  if (!Number.isFinite(d.getTime())) return "-";
  return d.toLocaleDateString("pt-BR");
}

function fmtLookupSaldo(v: number | null) {
  if (typeof v !== "number" || !Number.isFinite(v)) return "-";
  return Number(v).toLocaleString("pt-BR", { minimumFractionDigits: 3, maximumFractionDigits: 3 });
}

function normalizeFilterText(value: unknown) {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}

function sortLookupRows(rows: LookupItemRow[], key: LookupSortKey, dir: LookupSortDir) {
  const factor = dir === "asc" ? 1 : -1;
  return [...rows].sort((a, b) => {
    const getValue = (row: LookupItemRow): LookupSortValue => {
      switch (key) {
        case "id":
          return row.id;
        case "codigo":
          return row.codigo_interno?.toLowerCase() ?? "";
        case "descricao":
          return row.nome?.toLowerCase() ?? "";
        case "fornecedor":
          return row.fornecedor?.toLowerCase() ?? "";
        case "ultima":
          return row.ultima_entrada ? new Date(row.ultima_entrada).getTime() : null;
        case "preco":
          return typeof row.preco_unitario === "number" ? row.preco_unitario : null;
        case "saldo":
          return typeof row.estoque_atual === "number" ? row.estoque_atual : null;
      }
    };

    const aValue = getValue(a);
    const bValue = getValue(b);
    const aNull = aValue === null || aValue === undefined || aValue === "";
    const bNull = bValue === null || bValue === undefined || bValue === "";

    if (aNull && bNull) return 0;
    if (aNull) return 1;
    if (bNull) return -1;
    if (aValue < bValue) return -1 * factor;
    if (aValue > bValue) return 1 * factor;
    return 0;
  });
}

function extractOsNumeroFromItem(it: Pick<PedidoItem, "origem_resumo" | "origem_os_id">): string {
  const resumo = String(it.origem_resumo ?? "").trim();
  const m = /^OS\s+(.+)$/i.exec(resumo);
  if (m?.[1]) return String(m[1]).trim();
  const osId = Number(it.origem_os_id ?? 0);
  return Number.isFinite(osId) && osId > 0 ? String(osId) : "";
}

function statusBadgeClass(statusRaw: string) {
  const status = String(statusRaw ?? "").toUpperCase();
  if (status === "RECEBIDO") return "bg-emerald-900/40 text-emerald-200 border border-emerald-700";
  if (status === "CANCELADO" || status === "REPROVADO") return "bg-red-900/40 text-red-200 border border-red-700";
  if (status === "APROVADO" || status === "ENVIADO" || status === "PARCIAL_RECEBIDO") {
    return "bg-sky-900/40 text-sky-200 border border-sky-700";
  }
  if (status === "AGUARDANDO_APROVACAO") return "bg-amber-900/40 text-amber-200 border border-amber-700";
  return "bg-zinc-900 text-zinc-200 border border-zinc-700";
}

function statusLabel(statusRaw: string) {
  const status = String(statusRaw ?? "").toUpperCase();
  if (status === "PARCIAL_RECEBIDO") return "RECEBIDO PARCIAL";
  return status || "-";
}

function itemRecebimentoLabel(item: Pick<PedidoItem, "quantidade" | "quantidade_recebida">) {
  const qtd = Math.max(0, Number(item.quantidade ?? 0));
  const qtdRec = Math.max(0, Number(item.quantidade_recebida ?? 0));
  if (qtdRec <= 0) return { label: "PENDENTE", cls: "text-amber-300" };
  if (qtdRec + 1e-9 >= qtd) return { label: "RECEBIDO", cls: "text-emerald-300" };
  return { label: "RECEBIDO PARCIAL", cls: "text-sky-300" };
}

function getSaldoReceberItem(item: Pick<PedidoItem, "quantidade" | "quantidade_recebida">) {
  return Math.max(0, Number(item.quantidade ?? 0) - Number(item.quantidade_recebida ?? 0));
}

type ComprasPedidosClientProps = {
  readOnly?: boolean;
};

export default function ComprasPedidosClient({ readOnly = false }: ComprasPedidosClientProps) {
  const te = useTenantEmpresa();
  const tenantId = te.tenantId ?? "";
  const empresaId = te.empresaId ?? te.empresas[0]?.id ?? "";

  const [tab, setTab] = useState<"comprar" | "pedidos" | "avulso">(readOnly ? "pedidos" : "comprar");
  const [modo, setModo] = useState<"DETALHADO" | "AGRUPADO">("AGRUPADO");
  const [fornecedores, setFornecedores] = useState<FornPend[]>([]);
  const [fornecedorId, setFornecedorId] = useState<number | null>(null);
  const [avulsoFornecedores, setAvulsoFornecedores] = useState<FornecedorBase[]>([]);
  const [avulsoFornecedorId, setAvulsoFornecedorId] = useState<number | null>(null);
  const [avulsoOsReferencia, setAvulsoOsReferencia] = useState("");
  const [avulsoObservacoes, setAvulsoObservacoes] = useState("");
  const [detRows, setDetRows] = useState<PendDet[]>([]);
  const [detQtdDraftById, setDetQtdDraftById] = useState<Record<string, string>>({});
  const [detQtdConfirmById, setDetQtdConfirmById] = useState<Record<string, number>>({});
  const [detVlrDraftById, setDetVlrDraftById] = useState<Record<string, string>>({});
  const [detVlrConfirmById, setDetVlrConfirmById] = useState<Record<string, number>>({});
  const [detNewRow, setDetNewRow] = useState<DetNewRowDraft | null>(null);
  const [agrRows, setAgrRows] = useState<AgrRow[]>([]);
  const [selPendencias, setSelPendencias] = useState<string[]>([]);
  const [metaByRowKey, setMetaByRowKey] = useState<Record<string, "MIN" | "IDEAL" | "MAX">>({});

  const [pedidos, setPedidos] = useState<Pedido[]>([]);
  const [statusFiltro, setStatusFiltro] = useState("ANDAMENTO");
  const [fornecedorFiltro, setFornecedorFiltro] = useState("");
  const [manualPedidoId, setManualPedidoId] = useState<string>("");
  const [manualCodigo, setManualCodigo] = useState("");
  const [manualNome, setManualNome] = useState("");
  const [manualUnidade, setManualUnidade] = useState("UN");
  const [manualQtd, setManualQtd] = useState("1");
  const [manualValor, setManualValor] = useState("0");
  const [manualOsNumero, setManualOsNumero] = useState("");
  const [manualCodigoLookupBusy, setManualCodigoLookupBusy] = useState(false);
  const [showLookup, setShowLookup] = useState(false);
  const [lookupNome, setLookupNome] = useState("");
  const [lookupFornecedor, setLookupFornecedor] = useState("");
  const [lookupRows, setLookupRows] = useState<LookupItemRow[]>([]);
  const [lookupBusy, setLookupBusy] = useState(false);
  const [lookupErr, setLookupErr] = useState<string | null>(null);
  const [lookupSortKey, setLookupSortKey] = useState<LookupSortKey>("id");
  const [lookupSortDir, setLookupSortDir] = useState<LookupSortDir>("asc");
  const [pedidoEditMode, setPedidoEditMode] = useState(false);
  const [pedidoItens, setPedidoItens] = useState<PedidoItem[]>([]);
  const [itemDrafts, setItemDrafts] = useState<Record<string, { item_nome: string; unidade: string; quantidade: string; valor_unitario: string; os_numero: string }>>({});
  const [deleteTarget, setDeleteTarget] = useState<{ id: string; nome: string } | null>(null);
  const [recebimentoTarget, setRecebimentoTarget] = useState<{ id: string; nome: string; saldo: number } | null>(null);
  const [recebimentoDate, setRecebimentoDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [recebimentoDocumentoRef, setRecebimentoDocumentoRef] = useState("");
  const [recebimentoQuantidade, setRecebimentoQuantidade] = useState("");
  const [recebimentoObservacoes, setRecebimentoObservacoes] = useState("");
  const [autoScanTried, setAutoScanTried] = useState(false);
  const [usuariosSolicitantes, setUsuariosSolicitantes] = useState<UsuarioSolicitante[]>([]);
  const [pedidoSolicitanteId, setPedidoSolicitanteId] = useState("");
  const manualQtdInputRef = useRef<HTMLInputElement | null>(null);

  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const ctxQuery = useMemo(
    () => `tenant_id=${encodeURIComponent(tenantId)}&empresa_id=${encodeURIComponent(empresaId)}`,
    [empresaId, tenantId]
  );

  const effectiveEmpresa = useMemo(() => {
    if (te.empresaId) return te.empresas.find((e) => e.id === te.empresaId) ?? null;
    if (te.empresas.length === 1) return te.empresas[0];
    return null;
  }, [te.empresaId, te.empresas]);
  const empresaRole = useMemo(() => String(effectiveEmpresa?.papel ?? "").trim().toUpperCase(), [effectiveEmpresa?.papel]);

  const canReadByRole = ["ADMIN", "FINANCEIRO", "COORDENACAO", "COMPRAS"].includes(empresaRole);
  const canWriteByRole = ["ADMIN", "FINANCEIRO", "COORDENACAO", "COMPRAS"].includes(empresaRole);
  const canReadOnlyPedidosByRole = ["ADMIN", "FINANCEIRO", "COORDENACAO", "COMPRAS", "ALMOXARIFADO", "APONTAMENTO_RH"].includes(empresaRole);

  const canRead =
    te.has("compras.read") || te.has("compras.write") || te.has("compras.approve") || te.has("compras.receive") || canReadByRole;
  const canReadOnlyPedidos =
    readOnly &&
    (te.has("estoque.read") ||
      te.has("estoque.write") ||
      te.has("os.read") ||
      te.has("os.write") ||
      canReadOnlyPedidosByRole);
  const effectiveCanRead = canRead || canReadOnlyPedidos;
  const canWrite = !readOnly && (te.has("compras.write") || canWriteByRole);
  const canReconcileRecebimento = readOnly && (te.has("compras.receive") || te.has("estoque.write"));

  const rowKey = useCallback((r: AgrRow) => `${String(r.fornecedor_id ?? "null")}:${String(r.item_id ?? "null")}`, []);

  const rowPendencias = useCallback((r: AgrRow) => {
    if (!Array.isArray(r.pendencia_ids)) return [];
    return r.pendencia_ids.filter((x): x is string => typeof x === "string" && x.length > 0);
  }, []);

  const loadUltimosValoresDetalhado = useCallback(
    async (rows: PendDet[]) => {
      const aplicarZerados = () => {
        const zeradosDraft: Record<string, string> = {};
        const zeradosConfirm: Record<string, number> = {};
        for (const r of rows) {
          zeradosDraft[r.pendencia_id] = Number(0).toFixed(2);
          zeradosConfirm[r.pendencia_id] = 0;
        }
        setDetVlrDraftById(zeradosDraft);
        setDetVlrConfirmById(zeradosConfirm);
      };

      if (!tenantId || !empresaId || !effectiveCanRead || fornecedorId == null) {
        aplicarZerados();
        return;
      }

      const payloadRows = rows.map((r) => ({
        pendencia_id: r.pendencia_id,
        item_id: r.item_id ?? null,
        item_nome: r.item_nome ?? "",
        unidade: r.unidade ?? "UN",
      }));

      try {
        const json = await authedFetch("/api/compras/pedidos/ultimos-valores", {
          method: "POST",
          body: JSON.stringify({
            tenant_id: tenantId,
            empresa_id: empresaId,
            fornecedorId,
            rows: payloadRows,
          }),
        });

        const data = ((json.data ?? {}) as Record<string, unknown>);
        const draftMap: Record<string, string> = {};
        const confirmMap: Record<string, number> = {};
        for (const r of rows) {
          const v = Number((data[r.pendencia_id] as number | string | null | undefined) ?? 0);
          const valor = Number.isFinite(v) && v >= 0 ? v : 0;
          draftMap[r.pendencia_id] = valor.toFixed(2);
          confirmMap[r.pendencia_id] = valor;
        }
        setDetVlrDraftById(draftMap);
        setDetVlrConfirmById(confirmMap);
      } catch {
        aplicarZerados();
      }
    },
    [effectiveCanRead, empresaId, fornecedorId, tenantId]
  );

  const loadFornecedores = useCallback(async () => {
    if (readOnly) return;
    if (!tenantId || !empresaId || !effectiveCanRead) return;
    const json = await authedFetch(`/api/compras/fornecedores-pendentes?${ctxQuery}`);
    const rows = (json.data as FornPend[]) ?? [];
    setFornecedores(rows);
    if (rows.length && fornecedorId == null) setFornecedorId(rows[0].fornecedor_id);
  }, [ctxQuery, effectiveCanRead, empresaId, fornecedorId, readOnly, tenantId]);

  const loadFornecedoresAvulso = useCallback(async () => {
    if (readOnly) return;
    if (!tenantId || !empresaId || !effectiveCanRead) return;
    const json = await authedFetch(`/api/compras/fornecedores?${ctxQuery}`);
    const rows = ((json.data as FornecedorBase[]) ?? []).filter((f) => Number.isFinite(Number(f.id)));
    setAvulsoFornecedores(rows);
    if (avulsoFornecedorId == null && rows.length > 0) setAvulsoFornecedorId(Number(rows[0].id));
  }, [avulsoFornecedorId, ctxQuery, effectiveCanRead, empresaId, readOnly, tenantId]);

  const loadUsuariosSolicitantes = useCallback(async () => {
    if (readOnly) return;
    if (!tenantId || !empresaId || !effectiveCanRead) return;
    const qp = `tenantId=${encodeURIComponent(tenantId)}&empresaId=${encodeURIComponent(empresaId)}`;
    const json = await authedFetch(`/api/estoque/usuarios-solicitantes?${qp}`);
    const rows = ((json.usuarios as UsuarioSolicitante[]) ?? []).filter((u) => u?.id);
    setUsuariosSolicitantes(rows);
  }, [effectiveCanRead, empresaId, readOnly, tenantId]);

  const loadPendencias = useCallback(async () => {
    if (!tenantId || !empresaId || !effectiveCanRead || fornecedorId == null) return;
    const base = `/api/compras/pendencias?${ctxQuery}&modo=${modo}&fornecedorId=${fornecedorId}`;
    const json = await authedFetch(base);
    if (modo === "DETALHADO") {
      const rows = ((json.data as PendDet[]) ?? []).filter((r) => r.status === "PENDENTE");
      setDetRows(rows);
      const draftInit: Record<string, string> = {};
      for (const r of rows) draftInit[r.pendencia_id] = Number(r.quantidade ?? 0).toFixed(3);
      setDetQtdDraftById(draftInit);
      setDetQtdConfirmById({});
      await loadUltimosValoresDetalhado(rows);
      setDetNewRow(null);
      setAgrRows([]);
    } else {
      const rows = (json.data as AgrRow[]) ?? [];
      setAgrRows(rows);
      const init: Record<string, "MIN" | "IDEAL" | "MAX"> = {};
      for (const r of rows) {
        const k = rowKey(r);
        init[k] = r.estoque_meta_atual ?? "IDEAL";
      }
      setMetaByRowKey(init);
      setDetRows([]);
    }
  }, [ctxQuery, effectiveCanRead, empresaId, fornecedorId, loadUltimosValoresDetalhado, modo, rowKey, tenantId]);

  const loadPedidos = useCallback(async () => {
    if (!tenantId || !empresaId || !effectiveCanRead) return;
    const statusQ = statusFiltro ? `&status=${encodeURIComponent(statusFiltro)}` : "";
    const json = await authedFetch(`/api/compras/pedidos?${ctxQuery}${statusQ}&_ts=${Date.now()}`);
    const rows = (json.data as Pedido[]) ?? [];
    setPedidos(rows);
    if (!manualPedidoId && rows[0]?.id) setManualPedidoId(rows[0].id);
  }, [ctxQuery, effectiveCanRead, empresaId, manualPedidoId, statusFiltro, tenantId]);

  const loadPedidoItens = useCallback(async () => {
    if (!tenantId || !empresaId || !effectiveCanRead || !manualPedidoId) {
      setPedidoItens([]);
      setItemDrafts({});
      setManualOsNumero("");
      return;
    }
    const json = await authedFetch(`/api/compras/pedidos/${manualPedidoId}?${ctxQuery}&_ts=${Date.now()}`);
    const itens = ((json.data as { itens?: PedidoItem[] })?.itens ?? []) as PedidoItem[];
    setPedidoItens(itens);
    const nextDrafts: Record<string, { item_nome: string; unidade: string; quantidade: string; valor_unitario: string; os_numero: string }> = {};
    let lastOsNumero = "";
    for (const it of itens) {
      const osNumero = extractOsNumeroFromItem(it);
      nextDrafts[it.id] = {
        item_nome: String(it.item_nome ?? ""),
        unidade: String(it.unidade ?? "UN"),
        quantidade: String(it.quantidade ?? 0),
        valor_unitario: formatEditableNumber(it.valor_unitario, 4),
        os_numero: osNumero,
      };
      if (osNumero) lastOsNumero = osNumero;
    }
    setItemDrafts(nextDrafts);
    setManualOsNumero(lastOsNumero);
  }, [ctxQuery, effectiveCanRead, empresaId, manualPedidoId, tenantId]);

  const pedidosFiltrados = useMemo(() => {
    const termoFornecedor = normalizeFilterText(fornecedorFiltro);
    if (!termoFornecedor) return pedidos;

    return pedidos.filter((pedido) =>
      normalizeFilterText(String(pedido.fornecedor_nome ?? "").trim() || "SEM FORNECEDOR").includes(termoFornecedor)
    );
  }, [fornecedorFiltro, pedidos]);

  const selectedPedido = useMemo(
    () => pedidosFiltrados.find((p) => p.id === manualPedidoId) ?? null,
    [manualPedidoId, pedidosFiltrados]
  );
  const canEditManualItems = useMemo(() => {
    const st = String(selectedPedido?.status ?? "").toUpperCase();
    return ["RASCUNHO", "AGUARDANDO_APROVACAO", "REPROVADO"].includes(st);
  }, [selectedPedido?.status]);
  const canEditPedidoItems = !readOnly && canWrite && canEditManualItems && pedidoEditMode;
  const sortedLookupRows = useMemo(
    () => sortLookupRows(lookupRows, lookupSortKey, lookupSortDir),
    [lookupRows, lookupSortDir, lookupSortKey]
  );

  const buscarItensLookup = useCallback(
    async (nextNome?: string, nextFornecedor?: string) => {
      const nomeTerm = (nextNome ?? lookupNome).trim();
      const fornecedorTerm = (nextFornecedor ?? lookupFornecedor).trim();

      if (!nomeTerm && !fornecedorTerm) {
        setLookupRows([]);
        setLookupErr(null);
        return;
      }

      const q = new URLSearchParams({
        tenant_id: tenantId,
        empresa_id: empresaId,
      });
      if (nomeTerm) q.set("nome", nomeTerm);
      if (fornecedorTerm) q.set("fornecedor", fornecedorTerm);

      setLookupBusy(true);
      setLookupErr(null);

      try {
        const json = await authedFetch(`/api/compras/pedidos/item-lookup?${q.toString()}`);
        const rows = Array.isArray(json.data) ? (json.data as LookupItemRow[]) : [];
        setLookupRows(rows);
      } catch (e: unknown) {
        setLookupRows([]);
        setLookupErr(e instanceof Error ? e.message : "Erro ao buscar itens.");
      } finally {
        setLookupBusy(false);
      }
    },
    [empresaId, lookupFornecedor, lookupNome, tenantId]
  );

  const abrirLookupCodigo = useCallback(() => {
    const nomeInicial = manualCodigo.trim();
    const fornecedorInicial = String(selectedPedido?.fornecedor_nome ?? "").trim();

    setLookupNome(nomeInicial);
    setLookupFornecedor(fornecedorInicial);
    setLookupErr(null);
    setLookupRows([]);
    setShowLookup(true);

    if (nomeInicial || fornecedorInicial) {
      void buscarItensLookup(nomeInicial, fornecedorInicial);
    }
  }, [buscarItensLookup, manualCodigo, selectedPedido?.fornecedor_nome]);

  async function selecionarItemLookup(row: LookupItemRow) {
    const codigoSelecionado = String(row.codigo_interno ?? "").trim() || String(row.id);
    setManualCodigo(codigoSelecionado);
    setShowLookup(false);
    setLookupErr(null);
    await buscarCodigoExistente(codigoSelecionado);
  }

  const handleLookupSort = useCallback((key: LookupSortKey) => {
    if (lookupSortKey === key) {
      setLookupSortDir((prev) => (prev === "asc" ? "desc" : "asc"));
      return;
    }
    setLookupSortKey(key);
    setLookupSortDir("asc");
  }, [lookupSortKey]);

  useEffect(() => {
    setPedidoEditMode(false);
  }, [manualPedidoId]);

  useEffect(() => {
    void loadFornecedores();
  }, [loadFornecedores]);

  useEffect(() => {
    void loadFornecedoresAvulso();
  }, [loadFornecedoresAvulso]);

  useEffect(() => {
    void loadUsuariosSolicitantes();
  }, [loadUsuariosSolicitantes]);

  useEffect(() => {
    setPedidoSolicitanteId(String(selectedPedido?.solicitante_usuario_id ?? ""));
  }, [selectedPedido?.solicitante_usuario_id]);

  useEffect(() => {
    if (tab !== "pedidos") return;
    if (!pedidosFiltrados.length) {
      if (manualPedidoId) setManualPedidoId("");
      return;
    }
    if (!pedidosFiltrados.some((pedido) => pedido.id === manualPedidoId)) {
      setManualPedidoId(pedidosFiltrados[0].id);
    }
  }, [manualPedidoId, pedidosFiltrados, tab]);

  useEffect(() => {
    if (tab === "comprar") void loadPendencias();
  }, [tab, loadPendencias]);

  useEffect(() => {
    if (tab !== "comprar") return;
    if (!canWrite) return;
    if (busy) return;
    if (autoScanTried) return;
    if (fornecedores.length > 0) return;
    if (!tenantId || !empresaId) return;

    setAutoScanTried(true);
    void (async () => {
      try {
        await authedFetch("/api/compras/pendencias/varredura", {
          method: "POST",
          body: JSON.stringify({
            tenant_id: tenantId,
            empresa_id: empresaId,
            incluir_os: true,
            incluir_estoque: true,
          }),
        });
        await loadFornecedores();
        await loadPendencias();
      } catch {
        // mensagem principal já é tratada nos fluxos manuais
      }
    })();
  }, [autoScanTried, busy, canWrite, empresaId, fornecedores.length, loadFornecedores, loadPendencias, tab, tenantId]);

  useEffect(() => {
    if (tab === "pedidos") void loadPedidos();
  }, [tab, loadPedidos]);

  useEffect(() => {
    if (tab === "pedidos") void loadPedidoItens();
  }, [tab, loadPedidoItens]);

  const onGerarPedido = useCallback(async () => {
    if (!selPendencias.length || fornecedorId == null) return;
    const quantidadeOverrides = selPendencias
      .map((id) => {
        const qtd = detQtdConfirmById[id];
        if (!Number.isFinite(qtd) || qtd <= 0) return null;
        return { id, quantidade: qtd };
      })
      .filter((x): x is { id: string; quantidade: number } => Boolean(x));
    const valorUnitOverrides = selPendencias
      .map((id) => {
        const valor = detVlrConfirmById[id];
        if (!Number.isFinite(valor) || valor < 0) return null;
        return { id, valor_unitario: valor };
      })
      .filter((x): x is { id: string; valor_unitario: number } => Boolean(x));

    setBusy(true);
    setErr(null);
    setOk(null);
    try {
      const json = await authedFetch("/api/compras/pedidos/gerar", {
        method: "POST",
        body: JSON.stringify({
          tenant_id: tenantId,
          empresa_id: empresaId,
          fornecedorId,
          pendenciaIds: selPendencias,
          quantidadeOverrides,
          valorUnitOverrides,
        }),
      });
      setOk(`Pedido gerado: ${String(json.pedido_id ?? "")}`);
      setSelPendencias([]);
      await loadPendencias();
      await loadPedidos();
      setTab("pedidos");
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : "Erro ao gerar pedido.");
    } finally {
      setBusy(false);
    }
  }, [detQtdConfirmById, detVlrConfirmById, empresaId, fornecedorId, loadPendencias, loadPedidos, selPendencias, tenantId]);

  const adicionarLinhaDetalhada = useCallback(() => {
    if (modo !== "DETALHADO") return;
    setDetNewRow({
      item_nome: "",
      unidade: "UN",
      quantidade: "1",
      valor_unitario: "0",
      os_numero: "",
    });
  }, [modo]);

  const salvarLinhaDetalhada = useCallback(async () => {
    if (!canWrite) return;
    if (!detNewRow) return;
    if (fornecedorId == null) {
      setErr("Selecione um fornecedor para incluir item livre.");
      return;
    }

    const itemNome = String(detNewRow.item_nome ?? "").trim();
    const unidade = String(detNewRow.unidade ?? "UN").trim() || "UN";
    const osNumero = String(detNewRow.os_numero ?? "").trim();
    const qtd = parseQtyInput(detNewRow.quantidade);
    const valorUnit = parseMoneyInput(detNewRow.valor_unitario);

    if (!itemNome) return setErr("Informe a descricao do item livre.");
    if (qtd == null || qtd <= 0) return setErr("Quantidade invalida.");
    if (valorUnit == null || valorUnit < 0) return setErr("Valor unitario invalido.");

    setBusy(true);
    setErr(null);
    setOk(null);
    try {
      const json = await authedFetch("/api/compras/pendencias", {
        method: "POST",
        body: JSON.stringify({
          tenant_id: tenantId,
          empresa_id: empresaId,
          fornecedor_id: fornecedorId,
          origem_tipo: osNumero ? "OS" : "OUTROS",
          origem_os_numero: osNumero || null,
          item_id: null,
          item_nome: itemNome,
          unidade,
          quantidade: qtd,
          prioridade: "MEDIA",
          observacoes: osNumero
            ? "ITEM LIVRE (CODIGO GENERICO 9999) | VINCULADO A OS"
            : "ITEM LIVRE (CODIGO GENERICO 9999) | SEM VINCULO DE OS",
        }),
      });

      const created = (json.data ?? {}) as Record<string, unknown>;
      const createdId = String(created.id ?? "");
      if (!createdId) throw new Error("Nao foi possivel criar pendencia do item livre.");

      const novaLinha: PendDet = {
        pendencia_id: createdId,
        fornecedor_nome: "",
        item_nome: itemNome.toUpperCase(),
        unidade,
        quantidade: qtd,
        origem_tipo: osNumero ? "OS" : "OUTROS",
        numero_os: osNumero || null,
        os_num: null,
        status: "PENDENTE",
      };

      setDetRows((prev) => [novaLinha, ...prev]);
      setSelPendencias((prev) => Array.from(new Set([...prev, createdId])));
      setDetQtdDraftById((prev) => ({ ...prev, [createdId]: qtd.toFixed(3) }));
      setDetQtdConfirmById((prev) => ({ ...prev, [createdId]: qtd }));
      setDetVlrDraftById((prev) => ({ ...prev, [createdId]: valorUnit.toFixed(2) }));
      setDetVlrConfirmById((prev) => ({ ...prev, [createdId]: valorUnit }));
      setDetNewRow(null);
      setOk(osNumero ? `Item livre incluido e vinculado a OS ${osNumero}.` : "Item livre incluido sem vinculo de OS.");
      await loadFornecedores();
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : "Erro ao incluir item livre.");
    } finally {
      setBusy(false);
    }
  }, [canWrite, detNewRow, empresaId, fornecedorId, loadFornecedores, tenantId]);

  const totalCompraSelecionada = useMemo(() => {
    if (modo !== "DETALHADO") return 0;
    const rowById = new Map(detRows.map((r) => [r.pendencia_id, r]));
    let total = 0;
    for (const id of selPendencias) {
      const r = rowById.get(id);
      if (!r) continue;
      const qtd = Number.isFinite(detQtdConfirmById[id]) ? detQtdConfirmById[id] : parseNum(r.quantidade, 0);
      const vlr = Number.isFinite(detVlrConfirmById[id]) ? detVlrConfirmById[id] : 0;
      total += qtd * vlr;
    }
    return total;
  }, [detQtdConfirmById, detRows, detVlrConfirmById, modo, selPendencias]);

  const executarVarredura = useCallback(async () => {
    if (!canWrite) return;
    setBusy(true);
    setErr(null);
    setOk(null);
    try {
      const json = await authedFetch("/api/compras/pendencias/varredura", {
        method: "POST",
        body: JSON.stringify({
          tenant_id: tenantId,
          empresa_id: empresaId,
          incluir_os: true,
          incluir_estoque: true,
        }),
      });
      const r = (json.data ?? {}) as Record<string, unknown>;
      setOk(
        `Varredura concluida | OS novas: ${Number(r.os_inseridas ?? 0)} | OS canceladas: ${Number(
          r.os_canceladas ?? 0
        )} | Estoque novas: ${Number(
          r.estoque_inseridas ?? 0
        )} | Estoque atualizadas: ${Number(r.estoque_atualizadas ?? 0)}`
      );
      await loadFornecedores();
      await loadPendencias();
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : "Erro na varredura.");
    } finally {
      setBusy(false);
    }
  }, [canWrite, empresaId, loadFornecedores, loadPendencias, tenantId]);

  const applyEstoqueMeta = useCallback(
    async (r: AgrRow) => {
      if (!canWrite) return;
      if (!r.item_id || !Number.isFinite(r.item_id)) {
        setErr("Item invalido para pendencia de estoque.");
        return;
      }
      const k = rowKey(r);
      const meta = metaByRowKey[k] ?? "IDEAL";
      const sugestao =
        meta === "MIN" ? parseNum(r.sugestao_min) :
        meta === "IDEAL" ? parseNum(r.sugestao_ideal) :
        parseNum(r.sugestao_max);

      if (sugestao <= 0) {
        setErr("Sugestao calculada zerada para a meta selecionada.");
        return;
      }

      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        if (r.estoque_pendencia_id) {
          await authedFetch(`/api/compras/pendencias/${r.estoque_pendencia_id}`, {
            method: "PATCH",
            body: JSON.stringify({
              tenant_id: tenantId,
              empresa_id: empresaId,
              estoque_meta: meta,
              quantidade: sugestao,
              item_id: r.item_id,
              fornecedor_id: r.fornecedor_id,
            }),
          });
        } else {
          await authedFetch("/api/compras/pendencias", {
            method: "POST",
            body: JSON.stringify({
              tenant_id: tenantId,
              empresa_id: empresaId,
              fornecedor_id: r.fornecedor_id,
              origem_tipo: "ESTOQUE",
              item_id: r.item_id,
              quantidade: sugestao,
              prioridade: "MEDIA",
              estoque_meta: meta,
              observacoes: "Reposicao sugerida (modo agrupado)",
            }),
          });
        }
        setOk(`Pendencia de estoque atualizada (${meta}) para ${r.item_nome}.`);
        await loadPendencias();
        await loadFornecedores();
      } catch (e: unknown) {
        setErr(e instanceof Error ? e.message : "Erro ao aplicar meta de estoque.");
      } finally {
        setBusy(false);
      }
    },
    [canWrite, empresaId, loadFornecedores, loadPendencias, metaByRowKey, rowKey, tenantId]
  );

  const transicionarPedido = useCallback(
    async (id: string, action: string, body?: Record<string, unknown>) => {
      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        await authedFetch(`/api/compras/pedidos/${id}/${action}`, {
          method: "POST",
          body: JSON.stringify({ tenant_id: tenantId, empresa_id: empresaId, ...(body ?? {}) }),
        });
        setOk(`Pedido atualizado: ${action}`);
        await loadPedidos();
      } catch (e: unknown) {
        setErr(e instanceof Error ? e.message : "Erro ao atualizar pedido.");
      } finally {
        setBusy(false);
      }
    },
    [empresaId, loadPedidos, tenantId]
  );

  const receberTotal = useCallback(
    async (pedidoId: string) => {
      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        const det = await authedFetch(`/api/compras/pedidos/${pedidoId}?${ctxQuery}`);
        const itens = ((det.data as { itens?: Array<{ id: string; quantidade: number; quantidade_recebida: number }> })?.itens ?? [])
          .map((i) => ({
            pedidoItemId: i.id,
            quantidade: Math.max(0, Number(i.quantidade ?? 0) - Number(i.quantidade_recebida ?? 0)),
          }))
          .filter((i) => i.quantidade > 0);
        if (!itens.length) throw new Error("Pedido sem saldo para receber.");
        await authedFetch(`/api/compras/pedidos/${pedidoId}/receber`, {
          method: "POST",
          body: JSON.stringify({
            tenant_id: tenantId,
            empresa_id: empresaId,
            recebimentoDate: new Date().toISOString().slice(0, 10),
            itens,
          }),
        });
        setOk("Recebimento registrado.");
        await loadPedidos();
      } catch (e: unknown) {
        setErr(e instanceof Error ? e.message : "Erro ao receber pedido.");
      } finally {
        setBusy(false);
      }
    },
    [ctxQuery, empresaId, loadPedidos, tenantId]
  );

  const abrirRecebimentoItem = useCallback((item: PedidoItem) => {
    const saldo = getSaldoReceberItem(item);
    setRecebimentoTarget({ id: item.id, nome: item.item_nome, saldo });
    setRecebimentoDate(new Date().toISOString().slice(0, 10));
    setRecebimentoDocumentoRef("");
    setRecebimentoQuantidade(formatEditableNumber(saldo, 3));
    setRecebimentoObservacoes("");
  }, []);

  const registrarRecebimentoItem = useCallback(async () => {
    if (!recebimentoTarget) return;
    if (!manualPedidoId) {
      setErr("Selecione um pedido.");
      return;
    }

    const qtd = parseNum(recebimentoQuantidade, 0);
    const documentoRef = recebimentoDocumentoRef.trim();
    if (!documentoRef) {
      setErr("Informe a NF/documento do recebimento.");
      return;
    }
    if (qtd <= 0) {
      setErr("Quantidade de recebimento invalida.");
      return;
    }
    if (qtd - recebimentoTarget.saldo > 1e-9) {
      setErr("Quantidade informada excede o saldo pendente do item.");
      return;
    }

    setBusy(true);
    setErr(null);
    setOk(null);
    try {
      await authedFetch(`/api/compras/pedidos/${manualPedidoId}/receber`, {
        method: "POST",
        body: JSON.stringify({
          tenant_id: tenantId,
          empresa_id: empresaId,
          recebimentoDate,
          documentoRef,
          observacoes: recebimentoObservacoes.trim() || null,
          skipStockMovement: true,
          itens: [{ pedidoItemId: recebimentoTarget.id, quantidade: qtd }],
        }),
      });
      setRecebimentoTarget(null);
      setOk(`Recebimento conciliado para ${recebimentoTarget.nome}.`);
      await Promise.all([loadPedidos(), loadPedidoItens()]);
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : "Erro ao conciliar recebimento do item.");
    } finally {
      setBusy(false);
    }
  }, [
    empresaId,
    loadPedidoItens,
    loadPedidos,
    manualPedidoId,
    recebimentoDate,
    recebimentoDocumentoRef,
    recebimentoObservacoes,
    recebimentoQuantidade,
    recebimentoTarget,
    tenantId,
  ]);

  const addManualItem = useCallback(async () => {
    if (!manualPedidoId) {
      setErr("Selecione um pedido.");
      return;
    }
    const codigo = manualCodigo.trim();
    const nome = manualNome.trim();
    const qtd = parseNum(manualQtd, 0);
    const vlr = parseNum(manualValor, 0);
    if (!codigo && !nome) {
      setErr("Informe o codigo existente ou a descricao do item.");
      return;
    }
    if (qtd <= 0) {
      setErr("Quantidade invalida.");
      return;
    }
    if (vlr < 0) {
      setErr("Valor unitario invalido.");
      return;
    }

    setBusy(true);
    setErr(null);
    setOk(null);
    try {
      await authedFetch(`/api/compras/pedidos/${manualPedidoId}/itens`, {
        method: "POST",
        body: JSON.stringify({
          tenant_id: tenantId,
          empresa_id: empresaId,
          item_codigo: codigo || null,
          item_nome: nome,
          unidade: manualUnidade || "UN",
          quantidade: qtd,
          valor_unitario: vlr,
          origem_os_numero: manualOsNumero.trim() || null,
        }),
      });
      setOk(codigo ? "Item vinculado por codigo adicionado ao pedido." : "Item manual adicionado ao pedido.");
      setManualCodigo("");
      setManualNome("");
      setManualUnidade("UN");
      setManualQtd("1");
      setManualValor("0");
      await loadPedidos();
      await loadPedidoItens();
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : "Erro ao adicionar item manual.");
    } finally {
      setBusy(false);
    }
  }, [empresaId, loadPedidoItens, loadPedidos, manualCodigo, manualNome, manualOsNumero, manualPedidoId, manualQtd, manualUnidade, manualValor, tenantId]);

  async function buscarCodigoExistente(codigoParam?: string) {
    const codigo = String(codigoParam ?? manualCodigo).trim();
    if (!codigo) return;
    if (!tenantId || !empresaId) return;

    const fornecedorIdLookup = Number(selectedPedido?.fornecedor_id ?? 0);
    const q = new URLSearchParams({
      tenant_id: tenantId,
      empresa_id: empresaId,
      codigo,
    });
    if (Number.isFinite(fornecedorIdLookup) && fornecedorIdLookup > 0) {
      q.set("fornecedorId", String(fornecedorIdLookup));
    }

    setManualCodigoLookupBusy(true);
    setErr(null);
    setOk(null);
    try {
      const json = await authedFetch(`/api/compras/pedidos/item-lookup?${q.toString()}`);
      const row = (json.data ?? {}) as Record<string, unknown>;
      const nome = String(row.item_nome ?? "").trim();
      const unidade = String(row.unidade ?? "").trim();
      const valor = Number(row.valor_unitario_sugerido ?? row.valor_unitario_cadastro ?? 0);

      if (nome) setManualNome(nome);
      if (unidade) setManualUnidade(unidade);
      if (Number.isFinite(valor) && valor >= 0) {
        setManualValor(formatEditableNumber(valor, 4));
      }
      setOk(nome ? `Item localizado: ${nome}` : "Item localizado.");
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : "Nao foi possivel localizar o item pelo codigo.");
    } finally {
      setManualCodigoLookupBusy(false);
    }
  }

  const salvarItemPedido = useCallback(
    async (itemId: string) => {
      if (!manualPedidoId) return;
      const draft = itemDrafts[itemId];
      if (!draft) return;
      const row = pedidoItens.find((it) => it.id === itemId);
      const isManual = row ? row.item_id == null : true;
      const qtd = parseNum(draft.quantidade, 0);
      const vlr = parseNum(draft.valor_unitario, 0);
      if (isManual && !draft.item_nome.trim()) return setErr("Descricao do item manual obrigatoria.");
      if (qtd <= 0) return setErr("Quantidade invalida.");
      if (vlr < 0) return setErr("Valor unitario invalido.");

      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        await authedFetch(`/api/compras/pedidos/${manualPedidoId}/itens/${itemId}`, {
          method: "PATCH",
          body: JSON.stringify({
            tenant_id: tenantId,
            empresa_id: empresaId,
            item_nome: draft.item_nome,
            unidade: draft.unidade || "UN",
            quantidade: qtd,
            valor_unitario: vlr,
            origem_os_numero: draft.os_numero?.trim() || null,
          }),
        });
        setOk("Item atualizado.");
        await loadPedidoItens();
        await loadPedidos();
      } catch (e: unknown) {
        setErr(e instanceof Error ? e.message : "Erro ao atualizar item.");
      } finally {
        setBusy(false);
      }
    },
    [empresaId, itemDrafts, loadPedidoItens, loadPedidos, manualPedidoId, pedidoItens, tenantId]
  );

  const excluirItemPedido = useCallback(
    async (itemId: string) => {
      if (!manualPedidoId) return;
      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        await authedFetch(`/api/compras/pedidos/${manualPedidoId}/itens/${itemId}?${ctxQuery}`, {
          method: "DELETE",
        });
        setPedidoItens((prev) => prev.filter((it) => it.id !== itemId));
        setItemDrafts((prev) => {
          const next = { ...prev };
          delete next[itemId];
          return next;
        });
        setOk("Item excluido.");
        await loadPedidoItens();
        await loadPedidos();
      } catch (e: unknown) {
        setErr(e instanceof Error ? e.message : "Erro ao excluir item.");
      } finally {
        setBusy(false);
      }
    },
    [ctxQuery, loadPedidoItens, loadPedidos, manualPedidoId]
  );

  const criarPedidoAvulso = useCallback(async () => {
    if (!canWrite) return;
    if (!avulsoFornecedorId || !Number.isFinite(avulsoFornecedorId)) {
      setErr("Selecione um fornecedor para criar a compra avulsa.");
      return;
    }

    setBusy(true);
    setErr(null);
    setOk(null);
    try {
      const json = await authedFetch("/api/compras/pedidos/criar", {
        method: "POST",
        body: JSON.stringify({
          tenant_id: tenantId,
          empresa_id: empresaId,
          fornecedorId: avulsoFornecedorId,
          solicitanteUsuarioId: pedidoSolicitanteId || null,
          osReferencia: avulsoOsReferencia.trim() || null,
          observacoes: avulsoObservacoes.trim() || null,
        }),
      });

      const pedidoId = String(json.pedido_id ?? "");
      if (!pedidoId) throw new Error("Nao foi possivel criar o pedido avulso.");

      setManualPedidoId(pedidoId);
      setManualCodigo("");
      setManualNome("");
      setManualUnidade("UN");
      setManualQtd("1");
      setManualValor("0");
      setManualOsNumero("");

      await loadPedidos();
      setTab("pedidos");
      setOk("Pedido avulso criado. Agora adicione os itens livremente na aba Pedidos.");
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : "Erro ao criar pedido avulso.");
    } finally {
      setBusy(false);
    }
  }, [
    avulsoFornecedorId,
    avulsoObservacoes,
    avulsoOsReferencia,
    canWrite,
    empresaId,
    loadPedidos,
    tenantId,
    pedidoSolicitanteId,
  ]);

  const salvarSolicitantePedido = useCallback(async () => {
    if (!manualPedidoId) return;
    setBusy(true);
    setErr(null);
    setOk(null);
    try {
      await authedFetch(`/api/compras/pedidos/${manualPedidoId}`, {
        method: "PATCH",
        body: JSON.stringify({
          tenant_id: tenantId,
          empresa_id: empresaId,
          solicitanteUsuarioId: pedidoSolicitanteId || null,
        }),
      });
      setOk("Solicitante do pedido atualizado.");
      await loadPedidos();
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : "Erro ao atualizar solicitante.");
    } finally {
      setBusy(false);
    }
  }, [empresaId, loadPedidos, manualPedidoId, pedidoSolicitanteId, tenantId]);

  const imprimirPedido = useCallback((pedidoId: string) => {
    const id = String(pedidoId ?? "").trim();
    if (!id) return;
    const params = new URLSearchParams();
    if (tenantId) params.set("tenant_id", tenantId);
    if (empresaId) params.set("empresa_id", empresaId);
    params.set("auto", "1");
    window.open(`/compras/pedidos/${encodeURIComponent(id)}/imprimir?${params.toString()}`, "_blank", "noopener,noreferrer");
  }, [empresaId, tenantId]);

  if (!tenantId || !empresaId) return <div className="text-zinc-400">Carregando contexto...</div>;
  if (!effectiveCanRead) return <div className="text-zinc-400">Sem permissao para visualizar pedidos.</div>;

  return (
    <div className="space-y-4">
      {readOnly ? (
        <div className="flex items-center gap-2">
          <div className="px-3 py-2 rounded bg-zinc-100 text-zinc-900">Pedidos</div>
        </div>
      ) : (
        <div className="flex items-center gap-2">
          <button className={tab === "comprar" ? "px-3 py-2 rounded bg-zinc-100 text-zinc-900" : "px-3 py-2 rounded border border-zinc-800"} onClick={() => setTab("comprar")}>Comprar por Fornecedor</button>
          <button className={tab === "avulso" ? "px-3 py-2 rounded bg-zinc-100 text-zinc-900" : "px-3 py-2 rounded border border-zinc-800"} onClick={() => setTab("avulso")}>Compra Avulsa</button>
          <button className={tab === "pedidos" ? "px-3 py-2 rounded bg-zinc-100 text-zinc-900" : "px-3 py-2 rounded border border-zinc-800"} onClick={() => setTab("pedidos")}>Pedidos</button>
        </div>
      )}

      {err && <div className="text-red-400 text-sm">{err}</div>}
      {ok && <div className="text-emerald-400 text-sm">{ok}</div>}

      {tab === "comprar" && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3 md:col-span-1 space-y-2">
            <div className="text-sm font-medium">Fornecedores Pendentes</div>
            {fornecedores.map((f) => (
              <button
                key={`${f.fornecedor_id ?? "null"}-${f.fornecedor_nome}`}
                onClick={() => {
                  setFornecedorId(f.fornecedor_id);
                  setSelPendencias([]);
                }}
                className={
                  "w-full text-left p-2 rounded border " +
                  (fornecedorId === f.fornecedor_id ? "border-zinc-300" : "border-zinc-800 hover:border-zinc-600")
                }
              >
                <div className="text-sm">{f.fornecedor_nome}</div>
                <div className="text-xs text-zinc-400">{f.qtd_pendencias_abertas} pendencias | {Number(f.qtd_total_pendente).toFixed(3)}</div>
              </button>
            ))}
          </div>

          <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3 md:col-span-3 space-y-3">
            <div className="flex items-center gap-2">
              <button className={modo === "AGRUPADO" ? "px-2 py-1 rounded bg-zinc-100 text-zinc-900" : "px-2 py-1 rounded border border-zinc-800"} onClick={() => { setModo("AGRUPADO"); setSelPendencias([]); }}>AGRUPADO</button>
              <button className={modo === "DETALHADO" ? "px-2 py-1 rounded bg-zinc-100 text-zinc-900" : "px-2 py-1 rounded border border-zinc-800"} onClick={() => { setModo("DETALHADO"); setSelPendencias([]); }}>DETALHADO</button>
              <button className="px-3 py-1 rounded border border-zinc-800" onClick={() => void executarVarredura()} disabled={busy || !canWrite}>
                Varrer OS + Estoque MIN
              </button>
              <button className="ml-auto px-3 py-1 rounded border border-zinc-800" onClick={() => void loadPendencias()}>Atualizar</button>
            </div>

            {modo === "AGRUPADO" ? (
              <div className="overflow-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-zinc-300">
                      <th className="py-2">Sel</th>
                      <th>Item</th>
                      <th>Unid</th>
                      <th className="text-right">Qtd OS</th>
                      <th className="text-right">Em compra</th>
                      <th className="text-right">Sug. MIN</th>
                      <th className="text-right">Sug. IDEAL</th>
                      <th className="text-right">Sug. MAX</th>
                      <th className="text-center">Meta estoque</th>
                      <th className="text-right pr-4">Acao</th>
                    </tr>
                  </thead>
                  <tbody>
                    {agrRows.map((r, idx) => {
                      const k = rowKey(r);
                      const ids = rowPendencias(r);
                      const checked = ids.length > 0 && ids.every((id) => selPendencias.includes(id));
                      const metaSel = metaByRowKey[k] ?? "IDEAL";
                      return (
                        <tr key={`${k}:${idx}`} className="border-t border-zinc-900">
                          <td className="py-2">
                            <input
                              type="checkbox"
                              checked={checked}
                              onChange={(e) => {
                                setSelPendencias((prev) => {
                                  const set = new Set(prev);
                                  if (e.target.checked) ids.forEach((id) => set.add(id));
                                  else ids.forEach((id) => set.delete(id));
                                  return Array.from(set);
                                });
                              }}
                            />
                          </td>
                          <td className="py-2">{String(r.item_nome ?? "-")}</td>
                          <td>{String(r.unidade ?? "-")}</td>
                          <td className="text-right">{parseNum(r.qtd_os_total).toFixed(3)}</td>
                          <td className="text-right">{parseNum(r.qtd_em_compra_aberto).toFixed(3)}</td>
                          <td className="text-right">{parseNum(r.sugestao_min).toFixed(3)}</td>
                          <td className="text-right">{parseNum(r.sugestao_ideal).toFixed(3)}</td>
                          <td className="text-right">{parseNum(r.sugestao_max).toFixed(3)}</td>
                          <td className="text-center">
                            <select
                              className="px-2 py-1 rounded border border-zinc-800 bg-zinc-950"
                              value={metaSel}
                              onChange={(e) => setMetaByRowKey((prev) => ({ ...prev, [k]: e.target.value as "MIN" | "IDEAL" | "MAX" }))}
                            >
                              <option value="MIN">MIN</option>
                              <option value="IDEAL">IDEAL</option>
                              <option value="MAX">MAX</option>
                            </select>
                          </td>
                          <td className="pr-4 text-right">
                            <button
                              className="px-2 py-1 rounded border border-zinc-800"
                              onClick={() => void applyEstoqueMeta(r)}
                              disabled={busy || !canWrite || !r.item_id}
                            >
                              Aplicar
                            </button>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            ) : (
              <div className="space-y-2">
                <div className="overflow-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="text-left text-zinc-300">
                        <th className="py-2">Sel</th>
                        <th>Origem</th>
                        <th>Item</th>
                        <th>Qtd</th>
                        <th>Valor uni</th>
                        <th className="text-right pr-4 min-w-[110px]">Total</th>
                        <th className="text-center px-4 min-w-[110px]">OS</th>
                        <th className="text-center pl-4 min-w-[130px]">Acoes</th>
                      </tr>
                    </thead>
                    <tbody>
                      {detNewRow && (
                        <tr className="border-t border-zinc-900">
                          <td className="py-2 text-zinc-500">-</td>
                          <td>{detNewRow.os_numero.trim() ? "OS" : "OUTROS"}</td>
                          <td>
                            <input
                              className="px-2 py-1 rounded border border-zinc-700 bg-zinc-950 w-full"
                              placeholder="Descricao do item (codigo generico 9999)"
                              value={detNewRow.item_nome}
                              onChange={(e) => setDetNewRow((prev) => (prev ? { ...prev, item_nome: e.target.value } : prev))}
                            />
                          </td>
                          <td>
                            <input
                              className="px-2 py-1 rounded border border-zinc-700 bg-zinc-950 w-28 text-right"
                              value={detNewRow.quantidade}
                              onChange={(e) => setDetNewRow((prev) => (prev ? { ...prev, quantidade: e.target.value } : prev))}
                              onKeyDown={(e) => {
                                if (e.key !== "Enter") return;
                                e.preventDefault();
                                void salvarLinhaDetalhada();
                              }}
                            />
                          </td>
                          <td>
                            <input
                              className="px-2 py-1 rounded border border-zinc-700 bg-zinc-950 w-28 text-right"
                              value={detNewRow.valor_unitario}
                              onChange={(e) => setDetNewRow((prev) => (prev ? { ...prev, valor_unitario: e.target.value } : prev))}
                              onKeyDown={(e) => {
                                if (e.key !== "Enter") return;
                                e.preventDefault();
                                void salvarLinhaDetalhada();
                              }}
                            />
                          </td>
                          <td className="text-right pr-4">
                            {(() => {
                              const qtd = parseQtyInput(detNewRow.quantidade) ?? 0;
                              const vlr = parseMoneyInput(detNewRow.valor_unitario) ?? 0;
                              return (qtd * vlr).toFixed(2);
                            })()}
                          </td>
                          <td className="px-4">
                            <input
                              className="px-2 py-1 rounded border border-zinc-700 bg-zinc-950 w-28"
                              placeholder="Numero OS (opcional)"
                              value={detNewRow.os_numero}
                              onChange={(e) => setDetNewRow((prev) => (prev ? { ...prev, os_numero: e.target.value } : prev))}
                              onKeyDown={(e) => {
                                if (e.key !== "Enter") return;
                                e.preventDefault();
                                void salvarLinhaDetalhada();
                              }}
                            />
                          </td>
                          <td className="pl-4 space-x-1 text-center">
                            <button className="px-2 py-1 rounded border border-zinc-800" disabled={busy} onClick={() => void salvarLinhaDetalhada()}>
                              Salvar
                            </button>
                            <button className="px-2 py-1 rounded border border-zinc-800" disabled={busy} onClick={() => setDetNewRow(null)}>
                              Cancelar
                            </button>
                          </td>
                        </tr>
                      )}
                      {detRows.map((r) => {
                        const checked = selPendencias.includes(r.pendencia_id);
                        const qtdEfetiva = Number.isFinite(detQtdConfirmById[r.pendencia_id])
                          ? detQtdConfirmById[r.pendencia_id]
                          : parseNum(r.quantidade, 0);
                        const vlrEfetivo = Number.isFinite(detVlrConfirmById[r.pendencia_id]) ? detVlrConfirmById[r.pendencia_id] : 0;
                        return (
                          <tr key={r.pendencia_id} className="border-t border-zinc-900">
                            <td className="py-2">
                              <input
                                type="checkbox"
                                checked={checked}
                                onChange={(e) =>
                                  setSelPendencias((prev) =>
                                    e.target.checked ? [...prev, r.pendencia_id] : prev.filter((x) => x !== r.pendencia_id)
                                  )
                                }
                              />
                            </td>
                            <td>{r.origem_tipo}</td>
                            <td>{r.item_nome}</td>
                            <td>
                            <input
                              className="px-2 py-1 rounded border border-zinc-800 bg-zinc-950 w-28 text-right"
                              value={detQtdDraftById[r.pendencia_id] ?? Number(r.quantidade ?? 0).toFixed(3)}
                              disabled={!canWrite}
                              onChange={(e) =>
                                setDetQtdDraftById((prev) => ({ ...prev, [r.pendencia_id]: e.target.value }))
                              }
                                onBlur={() => {
                                  const confirmed = detQtdConfirmById[r.pendencia_id];
                                  const base = Number.isFinite(confirmed) ? confirmed : parseNum(r.quantidade, 0);
                                  setDetQtdDraftById((prev) => ({ ...prev, [r.pendencia_id]: base.toFixed(3) }));
                                }}
                              onKeyDown={(e) => {
                                if (e.key !== "Enter") return;
                                e.preventDefault();
                                const parsed = parseQtyInput(detQtdDraftById[r.pendencia_id] ?? "");
                                if (parsed == null || parsed <= 0) {
                                  setErr(`Quantidade invalida para ${r.item_nome}.`);
                                  return;
                                }
                                setErr(null);
                                setDetQtdConfirmById((prev) => ({ ...prev, [r.pendencia_id]: parsed }));
                                setDetQtdDraftById((prev) => ({ ...prev, [r.pendencia_id]: parsed.toFixed(3) }));
                                setOk(`Quantidade confirmada para ${r.item_nome}.`);
                              }}
                            />
                          </td>
                          <td>
                            <input
                              className="px-2 py-1 rounded border border-zinc-800 bg-zinc-950 w-28 text-right"
                              value={detVlrDraftById[r.pendencia_id] ?? "0.00"}
                              disabled={!canWrite}
                              onChange={(e) =>
                                setDetVlrDraftById((prev) => ({ ...prev, [r.pendencia_id]: e.target.value }))
                              }
                              onBlur={() => {
                                const confirmed = detVlrConfirmById[r.pendencia_id];
                                const base = Number.isFinite(confirmed) ? confirmed : 0;
                                setDetVlrDraftById((prev) => ({ ...prev, [r.pendencia_id]: base.toFixed(2) }));
                              }}
                              onKeyDown={(e) => {
                                if (e.key !== "Enter") return;
                                e.preventDefault();
                                const parsed = parseMoneyInput(detVlrDraftById[r.pendencia_id] ?? "");
                                if (parsed == null || parsed < 0) {
                                  setErr(`Valor unitario invalido para ${r.item_nome}.`);
                                  return;
                                }
                                setErr(null);
                                setDetVlrConfirmById((prev) => ({ ...prev, [r.pendencia_id]: parsed }));
                                setDetVlrDraftById((prev) => ({ ...prev, [r.pendencia_id]: parsed.toFixed(2) }));
                                setOk(`Valor unitario confirmado para ${r.item_nome}.`);
                              }}
                            />
                          </td>
                          <td className="text-right pr-4">{(qtdEfetiva * vlrEfetivo).toFixed(2)}</td>
                          <td className="text-center px-4">{r.numero_os ?? r.os_num ?? "-"}</td>
                          <td className="text-zinc-500 text-center pl-4">-</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
                </div>
              </div>
            )}
            <div className="mt-3 border-t border-zinc-900 pt-3 flex items-center justify-between">
              <div className="text-sm text-zinc-300">Total da compra: {totalCompraSelecionada.toFixed(2)}</div>
              <div className="flex items-center gap-2">
                {modo === "DETALHADO" && (
                  <button
                    className="px-3 py-2 rounded border border-zinc-800"
                    onClick={() => adicionarLinhaDetalhada()}
                    disabled={busy || !canWrite || detNewRow != null}
                  >
                    Novo item livre
                  </button>
                )}
                <button
                  onClick={() => void onGerarPedido()}
                  disabled={busy || !selPendencias.length || !canWrite}
                  className="px-3 py-2 rounded bg-zinc-100 text-zinc-900 disabled:opacity-50"
                >
                  Gerar Pedido ({selPendencias.length})
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {tab === "avulso" && (
        <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-4 space-y-4">
          <div>
            <div className="text-sm font-medium">Compra Avulsa (sem estoque e sem OS obrigatoria)</div>
            <div className="text-xs text-zinc-400">
              Crie um pedido em rascunho sem pendencias. O vinculo com OS e opcional e fica registrado nas observacoes.
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
            <label className="text-sm space-y-1">
              <div className="text-zinc-300">Fornecedor</div>
              <select
                className="w-full px-2 py-2 rounded border border-zinc-800 bg-zinc-950"
                value={avulsoFornecedorId ?? ""}
                onChange={(e) => setAvulsoFornecedorId(e.target.value ? Number(e.target.value) : null)}
              >
                <option value="">Selecione...</option>
                {avulsoFornecedores.map((f) => (
                  <option key={f.id} value={f.id}>
                    {String(f.nome ?? `Fornecedor #${f.id}`)}
                  </option>
                ))}
              </select>
            </label>

            <label className="text-sm space-y-1">
              <div className="text-zinc-300">Solicitante (opcional)</div>
              <select
                className="w-full px-2 py-2 rounded border border-zinc-800 bg-zinc-950"
                value={pedidoSolicitanteId}
                onChange={(e) => setPedidoSolicitanteId(e.target.value)}
              >
                <option value="">Selecione...</option>
                {usuariosSolicitantes.map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.nome} - {u.email}
                  </option>
                ))}
              </select>
            </label>

            <label className="text-sm space-y-1">
              <div className="text-zinc-300">OS vinculada (opcional)</div>
              <input
                className="w-full px-2 py-2 rounded border border-zinc-800 bg-zinc-950"
                placeholder="Ex.: 1234"
                value={avulsoOsReferencia}
                onChange={(e) => setAvulsoOsReferencia(e.target.value)}
              />
            </label>

            <label className="text-sm space-y-1">
              <div className="text-zinc-300">Observacoes (opcional)</div>
              <input
                className="w-full px-2 py-2 rounded border border-zinc-800 bg-zinc-950"
                placeholder="Informacoes adicionais"
                value={avulsoObservacoes}
                onChange={(e) => setAvulsoObservacoes(e.target.value)}
              />
            </label>
          </div>

          <div className="flex items-center gap-2">
            <button
              className="px-3 py-2 rounded bg-zinc-100 text-zinc-900 disabled:opacity-60"
              onClick={() => void criarPedidoAvulso()}
              disabled={busy || !canWrite}
            >
              Criar Pedido Avulso
            </button>
            <span className="text-xs text-zinc-500">
              Depois de criar, use a aba Pedidos para incluir, editar e remover itens livres.
            </span>
          </div>
        </div>
      )}

      {tab === "pedidos" && (
        <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3 space-y-3">
          <div className="flex flex-wrap items-center gap-2">
            <select
              className="px-2 py-1 rounded border border-zinc-800 bg-zinc-950"
              value={statusFiltro}
              onChange={(e) => setStatusFiltro(e.target.value)}
            >
              <option value="">Todos status</option>
              <option value="ANDAMENTO">Andamento</option>
              <option>RASCUNHO</option>
              <option>AGUARDANDO_APROVACAO</option>
              <option>APROVADO</option>
              <option>REPROVADO</option>
              <option>ENVIADO</option>
              <option>PARCIAL_RECEBIDO</option>
              <option>RECEBIDO</option>
              <option>CANCELADO</option>
            </select>
            <input
              className="min-w-[16rem] flex-1 px-2 py-1 rounded border border-zinc-800 bg-zinc-950"
              placeholder="Filtrar por fornecedor"
              value={fornecedorFiltro}
              onChange={(e) => setFornecedorFiltro(e.target.value)}
            />
            <button className="px-3 py-1 rounded border border-zinc-800" onClick={() => void loadPedidos()}>
              Atualizar
            </button>
            <div className="ml-auto text-xs text-zinc-400">
              {fornecedorFiltro.trim() ? `${pedidosFiltrados.length} de ${pedidos.length}` : pedidos.length} pedido(s)
            </div>
          </div>

          <div className="space-y-3">
            <div className="rounded border border-zinc-800 overflow-hidden">
              <div className="px-3 py-2 border-b border-zinc-800">
                <div className="text-sm font-medium">Selecao de pedido</div>
                <div className="text-xs text-zinc-500">Mostrando lista com rolagem (aprox. 10 pedidos visiveis).</div>
              </div>
              <div className="overflow-auto max-h-[34rem]">
                <table className="w-full text-sm">
                  <thead className="sticky top-0 bg-zinc-950 z-10">
                    <tr className="text-left text-zinc-300 border-b border-zinc-800">
                      <th className="py-2 px-3">Codigo</th>
                      <th className="py-2 px-3">Fornecedor</th>
                      <th className="py-2 px-3">Status</th>
                      <th className="py-2 px-3 text-right">Valor</th>
                    </tr>
                  </thead>
                  <tbody>
                    {pedidosFiltrados.map((p) => {
                      const selected = manualPedidoId === p.id;
                      return (
                        <tr
                          key={p.id}
                          className={`border-b border-zinc-900 cursor-pointer ${
                            selected ? "bg-zinc-900/70" : "hover:bg-zinc-900/40"
                          }`}
                          onClick={() => setManualPedidoId(p.id)}
                        >
                          <td className="py-2 px-3">
                            <div className="font-medium text-zinc-100">{p.codigo}</div>
                            <div className="text-xs text-zinc-500">{fmtDate(String(p.created_at ?? ""))}</div>
                          </td>
                          <td className="py-2 px-3 text-zinc-200">
                            {String(p.fornecedor_nome ?? "").trim() || "SEM FORNECEDOR"}
                          </td>
                          <td className="py-2 px-3">
                            <span className={`inline-flex rounded px-2 py-0.5 text-xs ${statusBadgeClass(String(p.status ?? ""))}`}>
                              {statusLabel(String(p.status ?? ""))}
                            </span>
                          </td>
                          <td className="py-2 px-3 text-right tabular-nums">{fmtMoney(Number(p.total_geral ?? 0))}</td>
                        </tr>
                      );
                    })}
                    {!pedidosFiltrados.length && (
                      <tr>
                        <td className="py-6 px-3 text-zinc-500 text-center" colSpan={4}>
                          Nenhum pedido encontrado.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>

            <div className="rounded border border-zinc-800 p-3 space-y-3">
              {!selectedPedido ? (
                <div className="text-sm text-zinc-400">Selecione um pedido na lista para ver os detalhes.</div>
              ) : (
                <>
                  <div className="flex items-center gap-2 flex-wrap">
                    <div className="text-sm font-semibold">{selectedPedido.codigo}</div>
                    <span className={`inline-flex rounded px-2 py-0.5 text-xs ${statusBadgeClass(String(selectedPedido.status ?? ""))}`}>
                      {statusLabel(String(selectedPedido.status ?? ""))}
                    </span>
                    <div className="text-xs text-zinc-500">
                      {String(selectedPedido.fornecedor_nome ?? "").trim() || "SEM FORNECEDOR"}
                    </div>
                    <div className="ml-auto text-sm font-medium">{fmtMoney(Number(selectedPedido.total_geral ?? 0))}</div>
                  </div>

                  {readOnly ? (
                    selectedPedido.solicitante_nome ? (
                      <div className="text-xs text-zinc-500">Solicitante: {selectedPedido.solicitante_nome}</div>
                    ) : null
                  ) : (
                    <div className="flex items-center gap-2 flex-wrap">
                      <label className="text-xs text-zinc-400">Solicitante</label>
                      <select
                        className="px-2 py-1 rounded border border-zinc-800 bg-zinc-950 text-sm min-w-[280px]"
                        value={pedidoSolicitanteId}
                        onChange={(e) => setPedidoSolicitanteId(e.target.value)}
                        disabled={busy || !canWrite}
                      >
                        <option value="">Selecione...</option>
                        {usuariosSolicitantes.map((u) => (
                          <option key={u.id} value={u.id}>
                            {u.nome} - {u.email}
                          </option>
                        ))}
                      </select>
                      <button
                        className="px-2 py-1 rounded border border-zinc-800 disabled:opacity-50"
                        onClick={() => void salvarSolicitantePedido()}
                        disabled={busy || !canWrite}
                      >
                        Salvar solicitante
                      </button>
                      {selectedPedido.solicitante_nome ? (
                        <span className="text-xs text-zinc-500">Atual: {selectedPedido.solicitante_nome}</span>
                      ) : null}
                    </div>
                  )}

                  <div className="flex items-center gap-1 flex-wrap">
                    {!readOnly && (
                      <>
                    <button
                      className="px-2 py-1 rounded border border-zinc-800 disabled:opacity-50"
                      onClick={() => setPedidoEditMode((prev) => !prev)}
                      disabled={!canWrite || !canEditManualItems}
                    >
                      {pedidoEditMode ? "Fechar edição" : "Editar"}
                    </button>
                    <button className="px-2 py-1 rounded border border-zinc-800" onClick={() => void transicionarPedido(selectedPedido.id, "enviar-aprovacao")}>Solic. Aprov.</button>
                    <button className="px-2 py-1 rounded border border-zinc-800" onClick={() => void transicionarPedido(selectedPedido.id, "aprovar")}>Aprovar</button>
                    <button className="px-2 py-1 rounded border border-zinc-800" onClick={() => void transicionarPedido(selectedPedido.id, "reprovar", { motivo: "Reprovado via tela" })}>Reprovar</button>
                    <button className="px-2 py-1 rounded border border-zinc-800" onClick={() => void transicionarPedido(selectedPedido.id, "enviar")}>Enviar</button>
                    <button className="px-2 py-1 rounded border border-zinc-800" onClick={() => void receberTotal(selectedPedido.id)}>Receber</button>
                    <button className="px-2 py-1 rounded border border-zinc-800" onClick={() => void transicionarPedido(selectedPedido.id, "cancelar", { motivo: "Cancelado via tela" })}>Cancelar</button>
                      </>
                    )}
                    <button className="px-2 py-1 rounded border border-zinc-800" onClick={() => imprimirPedido(selectedPedido.id)}>Imprimir PDF</button>
                  </div>

                  {!readOnly && (
                    <div className="rounded border border-zinc-800 p-3 space-y-2">
                    <div className="text-sm font-medium">Adicionar item no pedido</div>
                    <div className="grid grid-cols-1 md:grid-cols-7 gap-2">
                      <label className="space-y-1">
                        <div className="text-[11px] text-zinc-400">Codigo existente</div>
                        <input
                          className="w-full px-2 py-2 rounded border border-zinc-800 bg-zinc-950 disabled:opacity-50"
                          placeholder="Codigo existente"
                          value={manualCodigo}
                          disabled={!canEditPedidoItems || manualCodigoLookupBusy}
                          onChange={(e) => setManualCodigo(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key !== "Enter") return;
                            e.preventDefault();
                            abrirLookupCodigo();
                          }}
                        />
                      </label>
                      <label className="space-y-1 md:col-span-2">
                        <div className="text-[11px] text-zinc-400">Descricao do item (manual)</div>
                        <input
                          className="w-full px-2 py-2 rounded border border-zinc-800 bg-zinc-950 disabled:opacity-50"
                          placeholder="Descricao do item (manual)"
                          value={manualNome}
                          disabled={!canEditPedidoItems}
                          onChange={(e) => setManualNome(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key !== "Enter") return;
                            e.preventDefault();
                            manualQtdInputRef.current?.focus();
                            manualQtdInputRef.current?.select();
                          }}
                        />
                      </label>
                      <label className="space-y-1">
                        <div className="text-[11px] text-zinc-400">Unidade</div>
                        <input className="w-full px-2 py-2 rounded border border-zinc-800 bg-zinc-950 disabled:opacity-50" placeholder="UN" value={manualUnidade} disabled={!canEditPedidoItems} onChange={(e) => setManualUnidade(e.target.value)} />
                      </label>
                      <label className="space-y-1">
                        <div className="text-[11px] text-zinc-400">Qtd</div>
                        <input
                          ref={manualQtdInputRef}
                          className="w-full px-2 py-2 rounded border border-zinc-800 bg-zinc-950 disabled:opacity-50"
                          placeholder="Qtd"
                          value={manualQtd}
                          disabled={!canEditPedidoItems}
                          onChange={(e) => setManualQtd(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key !== "Enter") return;
                            e.preventDefault();
                            if (!busy && canEditPedidoItems) {
                              void addManualItem();
                            }
                          }}
                        />
                      </label>
                      <label className="space-y-1">
                        <div className="text-[11px] text-zinc-400">Vlr unit</div>
                        <input className="w-full px-2 py-2 rounded border border-zinc-800 bg-zinc-950 disabled:opacity-50" placeholder="0,00" value={manualValor} disabled={!canEditPedidoItems} onChange={(e) => setManualValor(e.target.value)} />
                      </label>
                      <label className="space-y-1">
                        <div className="text-[11px] text-zinc-400">OS (numero/id)</div>
                        <input className="w-full px-2 py-2 rounded border border-zinc-800 bg-zinc-950 disabled:opacity-50" placeholder="OS (numero/id)" value={manualOsNumero} disabled={!canEditPedidoItems} onChange={(e) => setManualOsNumero(e.target.value)} />
                      </label>
                    </div>
                    <div className="text-xs text-zinc-500">
                      No campo codigo, pode informar o codigo interno (ex.: 199.19240) ou o ID do item (ex.: 1733).
                    </div>
                    <button className="px-3 py-2 rounded border border-zinc-800 disabled:opacity-50" onClick={() => void addManualItem()} disabled={busy || !canEditPedidoItems}>
                      Adicionar item
                    </button>
                    {!canEditManualItems ? (
                      <div className="text-xs text-amber-300">
                        Pedido em status {statusLabel(String(selectedPedido.status ?? ""))} nao permite edicao.
                      </div>
                    ) : !pedidoEditMode ? (
                      <div className="text-xs text-zinc-400">
                        Clique em <strong>Editar</strong> para alterar ou excluir itens.
                      </div>
                    ) : null}
                    </div>
                  )}

                  {showLookup && (
                    <div className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 overflow-y-auto">
                      <div className="min-h-full w-full flex items-start justify-center p-4 md:items-center">
                        <div className="w-full max-w-5xl bg-zinc-950 border border-zinc-800 rounded-xl p-5 shadow-xl flex flex-col gap-4 max-h-[90dvh] h-[90dvh] min-h-0 overflow-hidden">
                          <div className="flex items-center justify-between gap-3">
                            <div>
                              <div className="text-lg font-semibold">Localizar item</div>
                              <div className="text-sm text-zinc-400">Filtre por nome, codigo ou fornecedor para localizar o item.</div>
                            </div>
                            <button
                              onClick={() => setShowLookup(false)}
                              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                            >
                              Fechar
                            </button>
                          </div>

                          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                            <div className="space-y-1">
                              <div className="text-xs text-zinc-400">Nome</div>
                              <input
                                className="w-full px-3 py-2 rounded border border-zinc-800 bg-zinc-950"
                                value={lookupNome}
                                onChange={(e) => setLookupNome(e.target.value)}
                                onKeyDown={(e) => {
                                  if (e.key !== "Enter") return;
                                  e.preventDefault();
                                  void buscarItensLookup(e.currentTarget.value, lookupFornecedor);
                                }}
                                aria-label="Buscar item por nome"
                                title="Buscar item por nome"
                              />
                            </div>

                            <div className="space-y-1">
                              <div className="text-xs text-zinc-400">Fornecedor</div>
                              <input
                                className="w-full px-3 py-2 rounded border border-zinc-800 bg-zinc-950"
                                value={lookupFornecedor}
                                onChange={(e) => setLookupFornecedor(e.target.value)}
                                onKeyDown={(e) => {
                                  if (e.key !== "Enter") return;
                                  e.preventDefault();
                                  void buscarItensLookup(lookupNome, e.currentTarget.value);
                                }}
                                aria-label="Buscar item por fornecedor"
                                title="Buscar item por fornecedor"
                              />
                            </div>
                          </div>

                          <div className="flex items-center gap-2">
                            <button
                              onClick={() => void buscarItensLookup()}
                              disabled={lookupBusy}
                              className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
                            >
                              {lookupBusy ? "Buscando..." : "Buscar"}
                            </button>
                            <button
                              onClick={() => {
                                setLookupNome("");
                                setLookupFornecedor("");
                                setLookupRows([]);
                                setLookupErr(null);
                              }}
                              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                            >
                              Limpar
                            </button>
                          </div>

                          {lookupErr && <div className="text-sm text-red-400">{lookupErr}</div>}

                          <div className="border border-zinc-800 rounded-xl bg-zinc-950 flex-1 min-h-0 overflow-auto overscroll-contain">
                            <table className="w-full text-sm min-w-[980px]">
                              <thead className="bg-zinc-900/70 sticky top-0 z-10">
                                <tr className="text-left text-zinc-200">
                                  <th className="px-4 py-3 cursor-pointer" onClick={() => handleLookupSort("id")}>
                                    ID {lookupSortKey === "id" && (lookupSortDir === "asc" ? "^" : "v")}
                                  </th>
                                  <th className="px-4 py-3 cursor-pointer" onClick={() => handleLookupSort("codigo")}>
                                    Codigo {lookupSortKey === "codigo" && (lookupSortDir === "asc" ? "^" : "v")}
                                  </th>
                                  <th className="px-4 py-3 cursor-pointer" onClick={() => handleLookupSort("descricao")}>
                                    Descricao {lookupSortKey === "descricao" && (lookupSortDir === "asc" ? "^" : "v")}
                                  </th>
                                  <th className="px-4 py-3 cursor-pointer" onClick={() => handleLookupSort("fornecedor")}>
                                    Fornecedor {lookupSortKey === "fornecedor" && (lookupSortDir === "asc" ? "^" : "v")}
                                  </th>
                                  <th className="px-4 py-3 cursor-pointer" onClick={() => handleLookupSort("ultima")}>
                                    Ultima entrada {lookupSortKey === "ultima" && (lookupSortDir === "asc" ? "^" : "v")}
                                  </th>
                                  <th className="px-4 py-3 text-right cursor-pointer" onClick={() => handleLookupSort("preco")}>
                                    Preco {lookupSortKey === "preco" && (lookupSortDir === "asc" ? "^" : "v")}
                                  </th>
                                  <th className="px-4 py-3 text-right cursor-pointer" onClick={() => handleLookupSort("saldo")}>
                                    Saldo {lookupSortKey === "saldo" && (lookupSortDir === "asc" ? "^" : "v")}
                                  </th>
                                </tr>
                              </thead>
                              <tbody className="divide-y divide-zinc-800">
                                {sortedLookupRows.map((it) => (
                                  <tr
                                    key={`${it.id}-${it.codigo_interno ?? ""}`}
                                    className="hover:bg-zinc-900/40 cursor-pointer"
                                    onClick={() => void selecionarItemLookup(it)}
                                  >
                                    <td className="px-4 py-3 tabular-nums">{it.id}</td>
                                    <td className="px-4 py-3">{it.codigo_interno ?? "-"}</td>
                                    <td className="px-4 py-3">{it.nome ?? "-"}</td>
                                    <td className="px-4 py-3 text-zinc-300">{it.fornecedor ?? "-"}</td>
                                    <td className="px-4 py-3 text-zinc-300">
                                      {it.ultima_entrada ? new Date(it.ultima_entrada).toLocaleDateString("pt-BR") : "-"}
                                    </td>
                                    <td className="px-4 py-3 text-right tabular-nums">{fmtMoney(Number(it.preco_unitario ?? 0))}</td>
                                    <td className="px-4 py-3 text-right tabular-nums">{fmtLookupSaldo(it.estoque_atual)}</td>
                                  </tr>
                                ))}

                                {!lookupBusy && sortedLookupRows.length === 0 && (
                                  <tr>
                                    <td colSpan={7} className="px-4 py-6 text-zinc-400 text-center">
                                      Nenhum resultado ainda. Informe filtros e busque.
                                    </td>
                                  </tr>
                                )}

                                {lookupBusy && (
                                  <tr>
                                    <td colSpan={7} className="px-4 py-6 text-zinc-400 text-center">
                                      Buscando itens...
                                    </td>
                                  </tr>
                                )}
                              </tbody>
                            </table>
                          </div>
                        </div>
                      </div>
                    </div>
                  )}

                  <div className="rounded border border-zinc-800 p-3 space-y-2">
                    <div className="text-sm font-medium">Itens do pedido selecionado</div>
                    <div className="overflow-x-auto">
                      <table className="w-full text-sm min-w-[1100px]">
                        <thead>
                          <tr className="text-left text-zinc-300">
                            <th className="py-2">Tipo</th>
                            <th>ID</th>
                            <th>Codigo</th>
                            <th>Descricao</th>
                            <th>Origem</th>
                            <th>Unid</th>
                            <th>OS</th>
                            <th>Qtd</th>
                            <th>Receb.</th>
                            <th>NF</th>
                            <th>Status item</th>
                            <th>Vlr unit</th>
                            <th className="text-center min-w-[130px] px-3">Total</th>
                            <th className="text-center min-w-[170px] px-3">Acoes</th>
                          </tr>
                        </thead>
                        <tbody>
                          {pedidoItens.map((it) => {
                            const isManual = it.item_id == null;
                            const saldoReceber = getSaldoReceberItem(it);
                            const draft = itemDrafts[it.id] ?? {
                              item_nome: it.item_nome,
                              unidade: it.unidade,
                              os_numero: extractOsNumeroFromItem(it),
                              quantidade: String(it.quantidade),
                              valor_unitario: formatEditableNumber(it.valor_unitario, 4),
                            };
                            return (
                              <tr key={it.id} className="border-t border-zinc-900">
                                <td className="py-2">{isManual ? "MANUAL" : "VINCULADO"}</td>
                                <td className="tabular-nums">{it.item_id ?? "-"}</td>
                                <td className="tabular-nums">{it.item_codigo ?? "-"}</td>
                                <td>
                                  <input
                                    className="px-2 py-1 rounded border border-zinc-800 bg-zinc-950 w-full"
                                    value={draft.item_nome}
                                    disabled={!isManual || !canEditPedidoItems}
                                    onChange={(e) =>
                                      setItemDrafts((prev) => ({ ...prev, [it.id]: { ...draft, item_nome: e.target.value } }))
                                    }
                                  />
                                </td>
                                <td className="text-xs text-zinc-300 whitespace-nowrap">
                                  {String(it.origem_resumo ?? (isManual ? "MANUAL" : "-"))}
                                </td>
                                <td>
                                  <input
                                    className="px-2 py-1 rounded border border-zinc-800 bg-zinc-950 w-20"
                                    value={draft.unidade}
                                    disabled={!isManual || !canEditPedidoItems}
                                    onChange={(e) =>
                                      setItemDrafts((prev) => ({ ...prev, [it.id]: { ...draft, unidade: e.target.value } }))
                                    }
                                  />
                                </td>
                                <td>
                                  <input
                                    className="px-2 py-1 rounded border border-zinc-800 bg-zinc-950 w-24"
                                    value={draft.os_numero}
                                    disabled={!canEditPedidoItems}
                                    placeholder="OS"
                                    onChange={(e) =>
                                      setItemDrafts((prev) => ({ ...prev, [it.id]: { ...draft, os_numero: e.target.value } }))
                                    }
                                  />
                                </td>
                                <td>
                                  <input
                                    className="px-2 py-1 rounded border border-zinc-800 bg-zinc-950 w-24"
                                    value={draft.quantidade}
                                    disabled={!canEditPedidoItems}
                                    onChange={(e) =>
                                      setItemDrafts((prev) => ({ ...prev, [it.id]: { ...draft, quantidade: e.target.value } }))
                                    }
                                  />
                                </td>
                                <td className="tabular-nums">
                                  {Number(it.quantidade_recebida ?? 0).toLocaleString("pt-BR", { maximumFractionDigits: 3 })}
                                </td>
                                <td className="text-xs text-zinc-300 whitespace-nowrap">
                                  {String(it.documento_ref_resumo ?? "").trim() || "-"}
                                </td>
                                <td>
                                  {(() => {
                                    const st = itemRecebimentoLabel(it);
                                    return <span className={`text-xs font-medium ${st.cls}`}>{st.label}</span>;
                                  })()}
                                </td>
                                <td>
                                  <input
                                    className="px-2 py-1 rounded border border-zinc-800 bg-zinc-950 w-28"
                                    value={draft.valor_unitario}
                                    disabled={!canEditPedidoItems}
                                    onChange={(e) =>
                                      setItemDrafts((prev) => ({ ...prev, [it.id]: { ...draft, valor_unitario: e.target.value } }))
                                    }
                                  />
                                </td>
                                <td className="text-center tabular-nums whitespace-nowrap px-3">{fmtMoney(Number(it.valor_total ?? 0))}</td>
                                <td className="px-3">
                                  {canEditPedidoItems ? (
                                    <div className="flex items-center justify-center gap-1">
                                      <button className="px-2 py-1 rounded border border-zinc-800 disabled:opacity-50" disabled={busy || !canEditPedidoItems} onClick={() => void salvarItemPedido(it.id)}>Salvar</button>
                                      <button
                                        className="px-2 py-1 rounded border border-red-900 text-red-300 disabled:opacity-50"
                                        disabled={busy || !canEditPedidoItems}
                                        onClick={() => setDeleteTarget({ id: it.id, nome: draft.item_nome || "ITEM MANUAL" })}
                                      >
                                        Excluir
                                      </button>
                                    </div>
                                  ) : (
                                    <div className="flex items-center justify-center gap-2">
                                      {canReconcileRecebimento ? (
                                        <button
                                          className="px-2 py-1 rounded border border-zinc-800 disabled:opacity-50"
                                          disabled={busy || saldoReceber <= 0}
                                          onClick={() => abrirRecebimentoItem(it)}
                                        >
                                          Editar
                                        </button>
                                      ) : null}
                                      <span className="text-xs text-zinc-500">{isManual ? "Item manual" : "Item de pendencia"}</span>
                                    </div>
                                  )}
                                </td>
                              </tr>
                            );
                          })}
                          {!pedidoItens.length && (
                            <tr>
                              <td className="py-3 text-zinc-500" colSpan={14}>Nenhum item no pedido selecionado.</td>
                            </tr>
                          )}
                        </tbody>
                      </table>
                    </div>
                  </div>
                </>
              )}
            </div>
          </div>
        </div>
      )}

      {deleteTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
          <div className="w-full max-w-md rounded-lg border border-zinc-800 bg-zinc-950 p-4 space-y-3">
            <div className="text-sm font-semibold">Confirmar exclusao</div>
            <div className="text-sm text-zinc-300">
              Excluir item <span className="font-medium">{deleteTarget.nome}</span>?
            </div>
            <div className="flex justify-end gap-2">
              <button
                className="px-3 py-2 rounded border border-zinc-800"
                onClick={() => setDeleteTarget(null)}
                disabled={busy}
              >
                Cancelar
              </button>
              <button
                className="px-3 py-2 rounded border border-red-900 text-red-300"
                onClick={async () => {
                  const target = deleteTarget;
                  setDeleteTarget(null);
                  if (target) await excluirItemPedido(target.id);
                }}
                disabled={busy}
              >
                Confirmar exclusao
              </button>
            </div>
          </div>
        </div>
      )}

      {recebimentoTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
          <div className="w-full max-w-lg rounded-lg border border-zinc-800 bg-zinc-950 p-4 space-y-4">
            <div className="space-y-1">
              <div className="text-sm font-semibold">Editar recebimento do item</div>
              <div className="text-sm text-zinc-300">{recebimentoTarget.nome}</div>
              <div className="text-xs text-zinc-500">
                Esta acao concilia o item com uma NF ja recebida, sem gerar nova entrada no estoque. Saldo pendente:{" "}
                {recebimentoTarget.saldo.toLocaleString("pt-BR", { maximumFractionDigits: 3 })}
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <label className="space-y-1">
                <div className="text-xs text-zinc-400">Data do recebimento</div>
                <input
                  type="date"
                  className="w-full px-3 py-2 rounded border border-zinc-800 bg-zinc-950"
                  value={recebimentoDate}
                  onChange={(e) => setRecebimentoDate(e.target.value)}
                  disabled={busy}
                />
              </label>
              <label className="space-y-1">
                <div className="text-xs text-zinc-400">Quantidade</div>
                <input
                  className="w-full px-3 py-2 rounded border border-zinc-800 bg-zinc-950"
                  value={recebimentoQuantidade}
                  onChange={(e) => setRecebimentoQuantidade(e.target.value)}
                  disabled={busy}
                />
              </label>
            </div>

            <label className="space-y-1 block">
              <div className="text-xs text-zinc-400">NF / documento</div>
              <input
                className="w-full px-3 py-2 rounded border border-zinc-800 bg-zinc-950"
                placeholder="Ex.: NF 1056 ou chave de acesso"
                value={recebimentoDocumentoRef}
                onChange={(e) => setRecebimentoDocumentoRef(e.target.value)}
                disabled={busy}
              />
            </label>

            <label className="space-y-1 block">
              <div className="text-xs text-zinc-400">Observacoes</div>
              <textarea
                className="w-full px-3 py-2 rounded border border-zinc-800 bg-zinc-950 min-h-[96px]"
                placeholder="Detalhe opcional sobre a conciliacao do recebimento"
                value={recebimentoObservacoes}
                onChange={(e) => setRecebimentoObservacoes(e.target.value)}
                disabled={busy}
              />
            </label>

            <div className="flex justify-end gap-2">
              <button
                className="px-3 py-2 rounded border border-zinc-800"
                onClick={() => setRecebimentoTarget(null)}
                disabled={busy}
              >
                Cancelar
              </button>
              <button
                className="px-3 py-2 rounded border border-zinc-800 disabled:opacity-50"
                onClick={() => void registrarRecebimentoItem()}
                disabled={busy}
              >
                Salvar recebimento
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
