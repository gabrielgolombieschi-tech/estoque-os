"use client";
/* eslint-disable react-hooks/refs */

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import { getItemByCodigo, getItemById } from "@/lib/comercial/orcamentos.service";
import { getSuggestedOrcamentoUnitPrice, mapOrcamentoError, toSupabaseErrorLike, upperTrim } from "@/lib/comercial/utils";
import { formatMoneyBR, parseMoneyBR, parseDecimalBR } from "@/lib/decimal";
import { ensureConfig, getConfig, getConjuntoCategorias } from "@/src/services/configOrcamento";
import type { ConjuntoItemRow, ConjuntoRow } from "@/src/services/conjunto";
import {
  createConjunto,
  getNextConjuntoCodigo,
  getConjunto,
  insertConjuntoItem,
  listConjuntoItens,
  softDeleteConjuntoItens,
  updateConjunto,
  updateConjuntoItem,
} from "@/src/services/conjunto";

function hasAny(caps: Capabilities | null, keys: CapabilityKey[]): boolean {
  return requireAny(caps, keys);
}

type FormState = {
  codigo: string;
  nome: string;
  categoria: string;
  precificacao: string;
  preco_fixo: string;
  ativo: boolean;
  descricao: string;
  observacoes: string;
};

type ItemSuggest = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  preco_unitario?: number | string | null;
  custo_ultima_compra?: number | string | null;
  preco_sugerido?: number | null;
  fornecedor?: string | null;
  ultima_entrada?: string | null;
  estoque_atual?: number | null;
};

type ItemLookupBaseRow = ItemSuggest & {
  fornecedores?: { nome?: string | null } | null;
};

type MovRow = {
  item_id: number;
  data_movimentacao: string;
};

type EstoqueRow = {
  item_id: number;
  quantidade_atual: number | null;
};

type SortValue = string | number | null;
type SortKey = "id" | "codigo" | "descricao" | "fornecedor" | "ultima" | "preco" | "estoque";
type SortDir = "asc" | "desc";

type ItemFormRow = {
  localKey: string;
  id?: string;
  ordem: string;
  item_id: string;
  item_codigo: string;
  item_nome: string;
  item_label: string;
  item_preco_unitario: number | null;
  quantidade: string;
};

const INLINE_LOOKUP_KEY = "__inline_lookup__";

function emptyForm(): FormState {
  return {
    codigo: "",
    nome: "",
    categoria: "",
    precificacao: "PRECO_FIXO",
    preco_fixo: "0,00",
    ativo: true,
    descricao: "",
    observacoes: "",
  };
}

function rowKey(): string {
  return `${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

function nextItemOrder(rows: ItemFormRow[]): string {
  const maxOrdem = rows.reduce((acc, row) => {
    const ordem = Number(String(row.ordem ?? "").trim());
    if (!Number.isInteger(ordem) || ordem < 0) return acc;
    return Math.max(acc, ordem);
  }, 0);
  return String(maxOrdem + 1);
}

function buildItemLabel(codigo: string, nome: string, id: number): string {
  return [codigo, nome].filter(Boolean).join(" - ") || String(id);
}

function toFiniteNumber(v: unknown): number | null {
  const parsed = typeof v === "number" ? v : Number(v);
  return Number.isFinite(parsed) ? parsed : null;
}

function formatDateBR(value?: string | null): string {
  const raw = String(value ?? "").trim();
  if (!raw) return "-";
  const iso = raw.slice(0, 10);
  if (/^\d{4}-\d{2}-\d{2}$/.test(iso)) {
    const [year, month, day] = iso.split("-");
    return `${day}/${month}/${year}`;
  }
  return raw;
}

function formatNumberBR(value?: number | string | null): string {
  const parsed = Number(value ?? 0);
  if (!Number.isFinite(parsed)) return "0";
  return parsed.toLocaleString("pt-BR", { minimumFractionDigits: 0, maximumFractionDigits: 3 });
}

function up(v: string): string {
  return String(v ?? "").toUpperCase();
}

function normalizePrecificacao(v: string): string {
  const normalized = String(v ?? "").trim().toUpperCase();
  if (normalized === "PRECO_FIXO") return "PRECO_FIXO";
  if (normalized === "SOMA_COMPONENTES") return "SOMA_COMPONENTES";
  if (normalized === "SOMA_ITENS") return "SOMA_ITENS";
  return normalized;
}

function mergeCategoriaOptions(options: string[], currentValue: string): string[] {
  const current = upperTrim(currentValue);
  if (!current) return options;
  return options.includes(current) ? options : [...options, current];
}

export default function ConjuntoEditPage() {
  const params = useParams();
  const rawId = (params as Record<string, string | string[] | undefined>)?.id;
  const idParam = String(Array.isArray(rawId) ? rawId[0] : rawId ?? "");
  const isNew = idParam === "novo";
  const router = useRouter();

  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);
  const te = useTenantEmpresa();
  const tenantId = te.tenantId;
  const empresaId = te.empresaId;

  const { loading: permissionsLoading, ready, capabilities } = usePermissions();
  const canView = hasAny(capabilities, ["financeiro.config", "financeiro.write", "os.write"]);

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const [conjunto, setConjunto] = useState<ConjuntoRow | null>(null);
  const [categoriaOptions, setCategoriaOptions] = useState<string[]>([]);
  const [form, setForm] = useState<FormState>(emptyForm());
  const [itens, setItens] = useState<ItemFormRow[]>([]);
  const removedItemIdsRef = useRef<Set<string>>(new Set());
  const [inlineMode, setInlineMode] = useState<"add" | "edit">("add");
  const [inlineEditingKey, setInlineEditingKey] = useState<string | null>(null);
  const [inlineOrdem, setInlineOrdem] = useState("1");
  const [inlineItemToken, setInlineItemToken] = useState("");
  const [inlineItemId, setInlineItemId] = useState("");
  const [inlineItemCodigo, setInlineItemCodigo] = useState("");
  const [inlineItemNome, setInlineItemNome] = useState("");
  const [inlineItemLabel, setInlineItemLabel] = useState("");
  const [inlineItemPrecoUnitario, setInlineItemPrecoUnitario] = useState<number | null>(null);
  const [inlineQuantidade, setInlineQuantidade] = useState("1");
  const [inlineErr, setInlineErr] = useState<string | null>(null);
  const inlineCodigoInputRef = useRef<HTMLInputElement | null>(null);
  const inlineQuantidadeInputRef = useRef<HTMLInputElement | null>(null);
  const [suggestKey, setSuggestKey] = useState<string | null>(null);
  const [suggestTerm, setSuggestTerm] = useState("");
  const [suggestRows, setSuggestRows] = useState<ItemSuggest[]>([]);
  const suggestBusyKey: string | null = null;
  const [showLookup, setShowLookup] = useState(false);
  const [lookupTargetKey, setLookupTargetKey] = useState<string | null>(null);
  const [lookupBusy, setLookupBusy] = useState(false);
  const [lookupErr, setLookupErr] = useState<string | null>(null);
  const [lookupTerm, setLookupTerm] = useState("");
  const [lookupFornecedor, setLookupFornecedor] = useState("");
  const [lookupRows, setLookupRows] = useState<ItemSuggest[]>([]);
  const [sortKey, setSortKey] = useState<SortKey>("id");
  const [sortDir, setSortDir] = useState<SortDir>("asc");

  const load = useCallback(async () => {
    setErr(null);
    setOk(null);

    if (!supabase) return;
    if (te.loading) return;

    if (!tenantId || !empresaId) {
      setLoading(false);
      setErr("Contexto (tenant/empresa) não carregado.");
      return;
    }

    if (!idParam) {
      setLoading(false);
      setErr("Identificador do conjunto nao informado.");
      setConjunto(null);
      setItens([]);
      return;
    }

    let categorias = ["PAINEIS AUTOPORTANTE", "PAINEIS DE COMANDO"];
    try {
      let cfg = await getConfig(supabase, { tenantId, empresaId });
      if (!cfg) {
        cfg = await ensureConfig(supabase, { tenantId, empresaId });
      }
      categorias = getConjuntoCategorias(cfg);
    } catch {
      // Se a configuracao falhar, usa o fallback padrao para nao bloquear a tela.
    }
    setCategoriaOptions(categorias);

    if (isNew) {
      setLoading(true);
      setConjunto(null);
      try {
        const nextCodigo = await getNextConjuntoCodigo(supabase, { tenantId, empresaId });
        setForm({ ...emptyForm(), codigo: nextCodigo, categoria: categorias[0] ?? "" });
        setItens([]);
        setInlineMode("add");
        setInlineEditingKey(null);
        setInlineOrdem("1");
        setInlineItemToken("");
        setInlineItemId("");
        setInlineItemCodigo("");
        setInlineItemNome("");
        setInlineItemLabel("");
        setInlineItemPrecoUnitario(null);
        setInlineQuantidade("1");
        setInlineErr(null);
        removedItemIdsRef.current = new Set();
      } catch (e: unknown) {
        setForm(emptyForm());
        setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao gerar codigo automatico do conjunto."));
      } finally {
        setLoading(false);
      }
      return;
    }

    setLoading(true);
    try {
      const c = await getConjunto(supabase, { tenantId, empresaId, id: idParam });
      setConjunto(c);
      setCategoriaOptions(mergeCategoriaOptions(categorias, c?.categoria ?? ""));
      setForm({
        codigo: c?.codigo ?? "",
        nome: c?.nome ?? "",
        categoria: c?.categoria ?? "",
        precificacao: String(c?.precificacao ?? "PRECO_FIXO"),
        preco_fixo: formatMoneyBR(Number(c?.preco_fixo ?? 0)),
        ativo: Boolean(c?.ativo ?? true),
        descricao: c?.descricao ?? "",
        observacoes: c?.observacoes ?? "",
      });

      const its = await listConjuntoItens(supabase, { tenantId, empresaId, conjuntoId: idParam });
      const ids = its.map((r) => Number(r.item_id)).filter((n) => Number.isFinite(n) && n > 0);
      const itemMap = new Map<number, ItemSuggest>();
      if (ids.length > 0) {
        const { data: itemRows } = await supabase
          .from("itens")
          .select("id,codigo_interno,nome,preco_unitario,custo_ultima_compra")
          .eq("tenant_id", tenantId)
          .eq("empresa_id", empresaId)
          .in("id", ids)
          .limit(5000);
        const typedRows = (itemRows ?? []) as ItemSuggest[];
        typedRows.forEach((it) => {
          const id = Number(it.id);
          if (!Number.isFinite(id) || id <= 0) return;
          itemMap.set(id, it);
        });
      }

      const loadedItems = await Promise.all(its.map(async (r) => {
        const itemIdNum = Number(r.item_id);
        const item = itemMap.get(itemIdNum);
        const itemCodigo = String(item?.codigo_interno ?? "").trim();
        const itemNome = String(item?.nome ?? "").trim();
        const itemLabel = item ? buildItemLabel(itemCodigo, itemNome, itemIdNum) : "";
        return {
          localKey: rowKey(),
          id: r.id,
          ordem: r.ordem === null || r.ordem === undefined ? "" : String(r.ordem),
          item_id: String(r.item_id ?? ""),
          item_codigo: itemCodigo,
          item_nome: itemNome,
          item_label: itemLabel,
          item_preco_unitario: item?.id
            ? await getSuggestedOrcamentoUnitPrice(supabase, { tenantId, empresaId, itemId: Number(item.id) })
            : null,
          quantidade: r.quantidade === null || r.quantidade === undefined ? "" : String(r.quantidade),
        } satisfies ItemFormRow;
      }));

      setItens(loadedItems);
      setInlineMode("add");
      setInlineEditingKey(null);
      setInlineOrdem(nextItemOrder(loadedItems));
      setInlineItemToken("");
      setInlineItemId("");
      setInlineItemCodigo("");
      setInlineItemNome("");
      setInlineItemLabel("");
      setInlineItemPrecoUnitario(null);
      setInlineQuantidade("1");
      setInlineErr(null);
      removedItemIdsRef.current = new Set();
    } catch (e: unknown) {
      setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao carregar conjunto."));
      setConjunto(null);
      setItens([]);
    } finally {
      setLoading(false);
    }
  }, [empresaId, idParam, isNew, supabase, te.loading, tenantId]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, [load]);

  const resolveItemByCodigoOrId = useCallback(
    async (rawValue: string) => {
      const raw = String(rawValue ?? "").trim();
      if (!supabase || !tenantId || !empresaId || !raw) return null;

      const parsed = Number(raw);
      if (Number.isFinite(parsed) && parsed > 0) {
        const byId = await getItemById(supabase, { tenantId, empresaId, id: parsed });
        if (byId?.id) return byId;
      }

      return getItemByCodigo(supabase, { tenantId, empresaId, codigo: raw });
    },
    [empresaId, supabase, tenantId]
  );


  function closeLookupModal() {
    setShowLookup(false);
    setLookupTargetKey(null);
    setLookupBusy(false);
    setLookupErr(null);
    setLookupFornecedor("");
    setLookupRows([]);
  }

  async function handleLookupSearch(nextTerm?: string, nextFornecedor?: string) {
    if (!supabase || !tenantId || !empresaId) return;

    const term = String(nextTerm ?? lookupTerm).trim();
    const fornecedorTerm = String(nextFornecedor ?? lookupFornecedor).trim();
    setLookupBusy(true);
    setLookupErr(null);

    try {
      const baseSelect = fornecedorTerm
        ? "id,codigo_interno,nome,preco_unitario,custo_ultima_compra,fornecedores!itens_tenant_empresa_fornecedor_fk!inner(nome)"
        : "id,codigo_interno,nome,preco_unitario,custo_ultima_compra,fornecedores!itens_tenant_empresa_fornecedor_fk(nome)";

      let q = supabase
        .from("itens")
        .select(baseSelect)
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .eq("ativo", true)
        .in("tipo", ["produto", "servico"]);

      if (term) {
        const parsed = Number(term);
        const like = `%${term}%`;
        q =
          Number.isFinite(parsed) && parsed > 0
            ? q.or(`id.eq.${parsed},codigo_interno.ilike.${like},nome.ilike.${like}`)
            : q.or(`codigo_interno.ilike.${like},nome.ilike.${like}`);
      }
      if (fornecedorTerm) q = q.ilike("fornecedores.nome", `%${fornecedorTerm}%`);

      const { data, error } = await q.order("nome", { ascending: true }).limit(50);
      if (error) throw error;

      const baseRows = (data ?? []) as ItemLookupBaseRow[];
      const ids = baseRows.map((row) => row.id);
      const ultimaMap = new Map<number, string>();
      const stockMap = new Map<number, number>();

      if (ids.length > 0) {
        const { data: movData, error: movErr } = await supabase
          .from("movimentacoes")
          .select("item_id,data_movimentacao")
          .eq("tenant_id", tenantId)
          .eq("empresa_id", empresaId)
          .eq("tipo", "entrada")
          .in("item_id", ids)
          .order("data_movimentacao", { ascending: false });

        if (!movErr) {
          const movRows = (movData ?? []) as MovRow[];
          movRows.forEach((row) => {
            if (!ultimaMap.has(row.item_id)) ultimaMap.set(row.item_id, row.data_movimentacao);
          });
        }

        const { data: estData } = await supabase
          .from("estoque")
          .select("item_id,quantidade_atual")
          .eq("tenant_id", tenantId)
          .eq("empresa_id", empresaId)
          .in("item_id", ids);

        const estoqueRows = (estData ?? []) as EstoqueRow[];
        estoqueRows.forEach((row) => {
          stockMap.set(row.item_id, Number(row.quantidade_atual ?? 0));
        });
      }

      setLookupRows(
        await Promise.all(baseRows.map(async (row) => ({
          ...row,
          fornecedor: row.fornecedores?.nome ?? null,
          ultima_entrada: ultimaMap.get(row.id) ?? null,
          estoque_atual: stockMap.has(row.id) ? stockMap.get(row.id)! : null,
          preco_sugerido: await getSuggestedOrcamentoUnitPrice(supabase, { tenantId, empresaId, itemId: row.id }),
        })))
      );
    } catch (e: unknown) {
      setLookupRows([]);
      setLookupErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao buscar itens."));
    } finally {
      setLookupBusy(false);
    }
  }

  function openLookupModal(localKey: string, initialTerm = "") {
    const nextTerm = String(initialTerm ?? "").trim();
    setLookupTargetKey(localKey);
    setLookupTerm(nextTerm);
    setLookupFornecedor("");
    setShowLookup(true);
    setLookupErr(null);
    setLookupRows([]);
    setSortKey("id");
    setSortDir("asc");
    void handleLookupSearch(nextTerm, "");
  }

  function handleSort(nextKey: SortKey) {
    if (sortKey === nextKey) {
      setSortDir((prev) => (prev === "asc" ? "desc" : "asc"));
      return;
    }
    setSortKey(nextKey);
    setSortDir("asc");
  }

  const sortedLookupRows = useMemo(() => {
    const rows = [...lookupRows];
    const getValue = (row: ItemSuggest): SortValue => {
      switch (sortKey) {
        case "id":
          return Number(row.id ?? 0);
        case "codigo":
          return row.codigo_interno ?? "";
        case "descricao":
          return row.nome ?? "";
        case "fornecedor":
          return row.fornecedor ?? "";
        case "ultima":
          return row.ultima_entrada ?? "";
        case "preco":
          return Number(row.preco_sugerido ?? 0);
        case "estoque":
          return Number(row.estoque_atual ?? 0);
        default:
          return "";
      }
    };

    rows.sort((a, b) => {
      const av = getValue(a);
      const bv = getValue(b);
      let result = 0;

      if (typeof av === "number" && typeof bv === "number") {
        result = av - bv;
      } else {
        result = String(av ?? "").localeCompare(String(bv ?? ""), "pt-BR", { numeric: true, sensitivity: "base" });
      }

      return sortDir === "asc" ? result : -result;
    });

    return rows;
  }, [lookupRows, sortDir, sortKey]);

  const resetInlineForm = useCallback(
    (rows: ItemFormRow[] = itens) => {
      setInlineMode("add");
      setInlineEditingKey(null);
      setInlineOrdem(nextItemOrder(rows));
      setInlineItemToken("");
      setInlineItemId("");
      setInlineItemCodigo("");
      setInlineItemNome("");
      setInlineItemLabel("");
      setInlineItemPrecoUnitario(null);
      setInlineQuantidade("1");
      setInlineErr(null);
      window.requestAnimationFrame(() => {
        inlineCodigoInputRef.current?.focus();
        inlineCodigoInputRef.current?.select();
      });
    },
    [itens]
  );

  const addItemRow = useCallback(() => {
    // Mantido apenas para compatibilidade com o bloco legado escondido.
  }, []);

  const startInlineEdit = useCallback(
    (localKey: string) => {
      const row = itens.find((it) => it.localKey === localKey);
      if (!row) return;

      setInlineMode("edit");
      setInlineEditingKey(localKey);
      setInlineOrdem(row.ordem || "");
      setInlineItemToken(row.item_codigo || row.item_id);
      setInlineItemId(row.item_id);
      setInlineItemCodigo(row.item_codigo);
      setInlineItemNome(row.item_nome);
      setInlineItemLabel(row.item_label);
      setInlineItemPrecoUnitario(row.item_preco_unitario);
      setInlineQuantidade(row.quantidade || "1");
      setInlineErr(null);
      window.requestAnimationFrame(() => {
        inlineCodigoInputRef.current?.focus();
        inlineCodigoInputRef.current?.select();
      });
    },
    [itens]
  );

  const applyPickedItem = useCallback(async (localKey: string, it: ItemSuggest) => {
    const id = Number(it.id);
    const codigo = String(it.codigo_interno ?? "").trim();
    const nome = String(it.nome ?? "").trim();
    const label = [codigo, nome].filter(Boolean).join(" â€” ") || String(id);
    const precoUnitario = !supabase || !tenantId || !empresaId
      ? null
      : await getSuggestedOrcamentoUnitPrice(supabase, { tenantId, empresaId, itemId: id });
    setItens((p) =>
      p.map((r) =>
        r.localKey === localKey
          ? { ...r, item_id: String(id), item_codigo: codigo, item_nome: nome, item_label: label, item_preco_unitario: precoUnitario }
          : r
      )
    );
    setSuggestKey(null);
    setSuggestTerm("");
    setSuggestRows([]);
    setShowLookup(false);
    setLookupTargetKey(null);
    setLookupErr(null);
    setLookupRows([]);
  }, [empresaId, supabase, tenantId]);

  const pickSuggestion = useCallback(async (localKey: string, it: ItemSuggest) => {
    const id = Number(it.id);
    const codigo = String(it.codigo_interno ?? "").trim();
    const nome = String(it.nome ?? "").trim();
    const label = [codigo, nome].filter(Boolean).join(" — ") || String(id);
    const precoUnitario = !supabase || !tenantId || !empresaId
      ? null
      : await getSuggestedOrcamentoUnitPrice(supabase, { tenantId, empresaId, itemId: id });
    setItens((p) =>
      p.map((r) =>
        r.localKey === localKey
          ? { ...r, item_id: String(id), item_codigo: codigo, item_nome: nome, item_label: label, item_preco_unitario: precoUnitario }
          : r
      )
    );
    setSuggestKey(null);
    setSuggestTerm("");
    setSuggestRows([]);
  }, [empresaId, supabase, tenantId]);

  async function handleItemTokenEnter(localKey: string, rawValue: string) {
    const raw = String(rawValue ?? "").trim();
    if (!raw) {
      openLookupModal(localKey, "");
      return;
    }

    try {
      const item = await resolveItemByCodigoOrId(raw);
      if (item?.id) {
        await applyPickedItem(localKey, {
          id: item.id,
          codigo_interno: item.codigo_interno ?? null,
          nome: item.nome ?? null,
          custo_ultima_compra: item.custo_ultima_compra ?? null,
          preco_unitario: item.preco_unitario ?? null,
        });
        return;
      }
    } catch {
      // Se a resolucao direta falhar, segue para a busca modal.
    }

    openLookupModal(localKey, raw);
  }

  const applyInlinePickedItem = useCallback(async (it: ItemSuggest) => {
    const id = Number(it.id);
    const codigo = String(it.codigo_interno ?? "").trim();
    const nome = String(it.nome ?? "").trim();
    const label = buildItemLabel(codigo, nome, id);
    setInlineItemToken(codigo || String(id));
    setInlineItemId(String(id));
    setInlineItemCodigo(codigo);
    setInlineItemNome(nome);
    setInlineItemLabel(label);
    setInlineItemPrecoUnitario(!supabase || !tenantId || !empresaId
      ? null
      : await getSuggestedOrcamentoUnitPrice(supabase, { tenantId, empresaId, itemId: id }));
    setInlineErr(null);
    window.requestAnimationFrame(() => {
      inlineQuantidadeInputRef.current?.focus();
      inlineQuantidadeInputRef.current?.select();
    });
  }, [empresaId, supabase, tenantId]);

  const applyLookupSelection = useCallback(
    async (it: ItemSuggest) => {
      if (!lookupTargetKey) return;
      if (lookupTargetKey === INLINE_LOOKUP_KEY) {
        await applyInlinePickedItem(it);
      } else {
        await applyPickedItem(lookupTargetKey, it);
      }
      setShowLookup(false);
      setLookupTargetKey(null);
      setLookupErr(null);
      setLookupRows([]);
    },
    [applyInlinePickedItem, applyPickedItem, lookupTargetKey]
  );

  const cancelInlineEdit = useCallback(() => {
    resetInlineForm();
  }, [resetInlineForm]);

  const removeInlineItemRow = useCallback(
    (localKey: string) => {
      const row = itens.find((it) => it.localKey === localKey);
      if (row?.id) removedItemIdsRef.current.add(row.id);

      const nextRows = itens.filter((it) => it.localKey !== localKey);
      setItens(nextRows);

      if (inlineMode === "edit" && inlineEditingKey === localKey) {
        resetInlineForm(nextRows);
        return;
      }

      if (inlineMode === "add") {
        setInlineOrdem(nextItemOrder(nextRows));
      }
    },
    [inlineEditingKey, inlineMode, itens, resetInlineForm]
  );

  const removeItemRow = useCallback(
    (localKey?: string) => {
      if (!localKey) return;
      removeInlineItemRow(localKey);
    },
    [removeInlineItemRow]
  );

  const submitInlineItem = useCallback(() => {
    const itemIdNum = Number(String(inlineItemId ?? "").trim());
    if (!Number.isFinite(itemIdNum) || itemIdNum <= 0) {
      setInlineErr("Informe um item valido.");
      window.requestAnimationFrame(() => {
        inlineCodigoInputRef.current?.focus();
        inlineCodigoInputRef.current?.select();
      });
      return;
    }

    const qtd = parseDecimalBR(String(inlineQuantidade ?? "").trim());
    if (!Number.isFinite(qtd) || qtd <= 0) {
      setInlineErr("Quantidade deve ser maior que 0.");
      window.requestAnimationFrame(() => {
        inlineQuantidadeInputRef.current?.focus();
        inlineQuantidadeInputRef.current?.select();
      });
      return;
    }

    const ordem = String(inlineOrdem ?? "").trim();
    const ordemNum = ordem ? Number(ordem) : null;
    if (ordem && (!Number.isInteger(ordemNum) || (ordemNum as number) < 0)) {
      setInlineErr("Ordem deve ser um inteiro maior ou igual a 0.");
      return;
    }

    const existingId = inlineMode === "edit" ? itens.find((it) => it.localKey === inlineEditingKey)?.id : undefined;
    const nextRow = {
      localKey: inlineEditingKey ?? rowKey(),
      id: existingId,
      ordem: ordemNum === null ? "" : String(ordemNum),
      item_id: String(itemIdNum),
      item_codigo: inlineItemCodigo,
      item_nome: inlineItemNome,
      item_label: inlineItemLabel || buildItemLabel(inlineItemCodigo, inlineItemNome, itemIdNum),
      item_preco_unitario: inlineItemPrecoUnitario,
      quantidade: String(inlineQuantidade ?? "").trim(),
    } satisfies ItemFormRow;

    const nextRows =
      inlineMode === "edit" && inlineEditingKey
        ? itens.map((it) => (it.localKey === inlineEditingKey ? nextRow : it))
        : [...itens, nextRow];

    setItens(nextRows);
    resetInlineForm(nextRows);
  }, [inlineEditingKey, inlineItemCodigo, inlineItemId, inlineItemLabel, inlineItemNome, inlineItemPrecoUnitario, inlineMode, inlineOrdem, inlineQuantidade, itens, resetInlineForm]);

  async function handleInlineItemTokenEnter(rawValue: string) {
    const raw = String(rawValue ?? "").trim();
    if (!raw) {
      openLookupModal(INLINE_LOOKUP_KEY, "");
      return;
    }

    try {
      const item = await resolveItemByCodigoOrId(raw);
      if (item?.id) {
        await applyInlinePickedItem({
          id: item.id,
          codigo_interno: item.codigo_interno ?? null,
          nome: item.nome ?? null,
          custo_ultima_compra: item.custo_ultima_compra ?? null,
          preco_unitario: item.preco_unitario ?? null,
        });
        return;
      }
    } catch {
      // Se a resolucao direta falhar, segue para a busca modal.
    }

    openLookupModal(INLINE_LOOKUP_KEY, raw);
  }

  const totalComponentes = useMemo(() => {
    return itens.reduce((acc, row) => {
      const quantidade = parseDecimalBR(String(row.quantidade ?? "").trim());
      const precoUnitario = toFiniteNumber(row.item_preco_unitario);
      if (!Number.isFinite(quantidade) || quantidade <= 0 || precoUnitario === null) return acc;
      return acc + quantidade * precoUnitario;
    }, 0);
  }, [itens]);

  const itensSemPreco = useMemo(() => {
    return itens.reduce((acc, row) => {
      const itemId = Number(String(row.item_id ?? "").trim());
      if (!Number.isFinite(itemId) || itemId <= 0) return acc;
      return row.item_preco_unitario === null ? acc + 1 : acc;
    }, 0);
  }, [itens]);

  const precoAplicadoConjunto = useMemo(() => {
    const precificacao = normalizePrecificacao(form.precificacao);
    if (precificacao === "PRECO_FIXO") {
      const precoFixo = parseMoneyBR(form.preco_fixo);
      return Number.isFinite(precoFixo) ? precoFixo : 0;
    }
    return totalComponentes;
  }, [form.preco_fixo, form.precificacao, totalComponentes]);

  const save = useCallback(
    async (e: FormEvent) => {
      e.preventDefault();
      if (!supabase || !tenantId || !empresaId) return;

      const codigo = upperTrim(form.codigo);
      const nome = String(form.nome ?? "").trim();
      if (!codigo && !isNew) {
        setErr("Informe o código.");
        return;
      }
      if (!nome) {
        setErr("Informe o nome.");
        return;
      }

      const precificacao = normalizePrecificacao(form.precificacao);
      const precoFixo = parseMoneyBR(form.preco_fixo);
      if (precificacao === "PRECO_FIXO" && (!Number.isFinite(precoFixo) || precoFixo < 0)) {
        setErr("Preço fixo inválido.");
        return;
      }

      // validate itens
      for (const r of itens) {
        const itemIdNum = Number(String(r.item_id ?? "").trim());
        if (!Number.isFinite(itemIdNum) || itemIdNum <= 0) {
          setErr("Informe um item válido em todos os componentes.");
          return;
        }
        const qtd = parseDecimalBR(String(r.quantidade ?? "").trim());
        if (!Number.isFinite(qtd) || qtd <= 0) {
          setErr("Quantidade deve ser maior que 0 em todos os componentes.");
          return;
        }
        const ordem = r.ordem.trim() ? Number(r.ordem) : null;
        if (r.ordem.trim() && (!Number.isFinite(ordem as number) || !Number.isInteger(ordem as number) || (ordem as number) < 0)) {
          setErr("Ordem deve ser um inteiro maior ou igual a 0.");
          return;
        }
      }

      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        let currentId = conjunto?.id ?? null;
        if (isNew) {
          const created = await createConjunto(supabase, {
            tenantId,
            empresaId,
            payload: {
              codigo: codigo || null,
              nome,
              categoria: form.categoria.trim() ? upperTrim(form.categoria) : null,
              precificacao,
              preco_fixo: precificacao === "PRECO_FIXO" ? precoFixo : null,
              ativo: Boolean(form.ativo),
              descricao: form.descricao.trim() ? upperTrim(form.descricao) : null,
              observacoes: form.observacoes.trim() ? upperTrim(form.observacoes) : null,
            },
          });
          currentId = created.id;
          setConjunto(created);
        } else if (conjunto?.id) {
          await updateConjunto(supabase, {
            tenantId,
            empresaId,
            id: conjunto.id,
            patch: {
              codigo,
              nome,
              categoria: form.categoria.trim() ? upperTrim(form.categoria) : null,
              precificacao,
              preco_fixo: precificacao === "PRECO_FIXO" ? precoFixo : null,
              ativo: Boolean(form.ativo),
              descricao: form.descricao.trim() ? upperTrim(form.descricao) : null,
              observacoes: form.observacoes.trim() ? upperTrim(form.observacoes) : null,
            },
          });
        }

        if (!currentId) throw new Error("ID do conjunto não disponível.");

        // Soft delete removed rows
        const removedIds = Array.from(removedItemIdsRef.current);
        await softDeleteConjuntoItens(supabase, { tenantId, empresaId, ids: removedIds });
        removedItemIdsRef.current = new Set();

        // Upsert remaining rows
        for (const r of itens) {
          const ordem = r.ordem.trim() ? Number(r.ordem) : null;
          const itemIdNum = Number(String(r.item_id ?? "").trim());
          const qtd = parseDecimalBR(String(r.quantidade ?? "").trim());

          const payload = {
            ordem: ordem === null ? null : (ordem as number),
            item_id: itemIdNum,
            quantidade: qtd,
          } satisfies Pick<ConjuntoItemRow, "ordem" | "item_id" | "quantidade">;

          if (r.id) {
            await updateConjuntoItem(supabase, { tenantId, empresaId, id: r.id, patch: payload });
          } else {
            await insertConjuntoItem(supabase, { tenantId, empresaId, conjuntoId: currentId, payload });
          }
        }

        setOk("Conjunto salvo.");
        if (isNew && currentId) {
          router.replace(`/configuracoes/comercial/conjuntos/${currentId}`);
        } else {
          await load();
        }
      } catch (e2: unknown) {
        setErr(mapOrcamentoError(toSupabaseErrorLike(e2), "Erro ao salvar."));
      } finally {
        setBusy(false);
      }
    },
    [conjunto, empresaId, form, isNew, itens, load, router, supabase, tenantId]
  );

  if (!ready && permissionsLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissões...</div>;
  }

  if (!canView) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">{isNew ? "Novo Conjunto" : "Editar Conjunto"}</h1>
          <p className="text-sm text-zinc-400 mt-1">Defina os dados e os itens componentes do kit.</p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href="/configuracoes/comercial/conjuntos"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Voltar
          </Link>
          <button
            type="button"
            onClick={() => void load()}
            disabled={busy}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
          >
            Atualizar
          </button>
        </div>
      </div>

      {err && <div className="text-sm text-red-400">{err}</div>}
      {ok && <div className="text-sm text-emerald-300">{ok}</div>}
      {loading && <div className="text-sm text-zinc-400">Carregando...</div>}

      {!loading && (
        <form onSubmit={save} className="space-y-4">
          <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <label className="block text-xs text-zinc-400">
                Código
                <input
                  value={form.codigo}
                  onChange={(e) => setForm((p) => ({ ...p, codigo: up(e.target.value) }))}
                  disabled={isNew}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                />
                {isNew && <div className="mt-1 text-[11px] text-zinc-500">Gerado automaticamente no padrao C1.</div>}
              </label>

              <label className="block text-xs text-zinc-400 md:col-span-2">
                Nome
                <input
                  value={form.nome}
                  onChange={(e) => setForm((p) => ({ ...p, nome: up(e.target.value) }))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                />
              </label>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-3">
                <div className="text-[11px] uppercase tracking-wide text-zinc-500">Total dos componentes</div>
                <div className="mt-1 text-lg font-semibold text-zinc-100 tabular-nums">R$ {formatMoneyBR(totalComponentes)}</div>
              </div>
              <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-3">
                <div className="text-[11px] uppercase tracking-wide text-zinc-500">Preco do conjunto</div>
                <div className="mt-1 text-lg font-semibold text-zinc-100 tabular-nums">R$ {formatMoneyBR(precoAplicadoConjunto)}</div>
                <div className="mt-1 text-[11px] text-zinc-500">{normalizePrecificacao(form.precificacao) === "PRECO_FIXO" ? "Origem: preco fixo" : "Origem: soma dos componentes"}</div>
              </div>
              <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 px-3 py-3">
                <div className="text-[11px] uppercase tracking-wide text-zinc-500">Itens sem preco</div>
                <div className="mt-1 text-lg font-semibold text-zinc-100 tabular-nums">{itensSemPreco}</div>
                <div className="mt-1 text-[11px] text-zinc-500">Componentes sem `preco_unitario` nao entram na soma.</div>
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <label className="block text-xs text-zinc-400">
                Categoria
                <select
                  value={form.categoria}
                  onChange={(e) => setForm((p) => ({ ...p, categoria: e.target.value }))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                >
                  {categoriaOptions.map((categoria) => (
                    <option key={categoria} value={categoria}>
                      {categoria}
                    </option>
                  ))}
                </select>
              </label>

              <label className="block text-xs text-zinc-400">
                Precificação
                <select
                  value={form.precificacao}
                  onChange={(e) => setForm((p) => ({ ...p, precificacao: e.target.value }))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                >
                  <option value="PRECO_FIXO">PRECO_FIXO</option>
                  <option value="SOMA_COMPONENTES">SOMA_COMPONENTES</option>
                </select>
              </label>

              <label className="block text-xs text-zinc-400">
                Preço fixo
                <input
                  value={form.preco_fixo}
                  onChange={(e) => setForm((p) => ({ ...p, preco_fixo: e.target.value }))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  disabled={normalizePrecificacao(form.precificacao) !== "PRECO_FIXO"}
                />
                <div className="text-[11px] text-zinc-500 mt-1">
                  {normalizePrecificacao(form.precificacao) === "PRECO_FIXO"
                    ? `Preco aplicado ao conjunto: R$ ${formatMoneyBR(precoAplicadoConjunto)}`
                    : `Total calculado pelos componentes: R$ ${formatMoneyBR(totalComponentes)}`}
                </div>
                {false && normalizePrecificacao(form.precificacao) === "PRECO_FIXO" && (
                  <div className="text-[11px] text-zinc-500 mt-1">Sugestão: {formatMoneyBR(parseMoneyBR(form.preco_fixo) || 0)}</div>
                )}
              </label>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <label className="flex items-center gap-2 text-sm text-zinc-200">
                <input
                  type="checkbox"
                  checked={form.ativo}
                  onChange={(e) => setForm((p) => ({ ...p, ativo: e.target.checked }))}
                />
                Ativo
              </label>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <label className="block text-xs text-zinc-400">
                Descrição
                <textarea
                  value={form.descricao}
                  onChange={(e) => setForm((p) => ({ ...p, descricao: up(e.target.value) }))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm min-h-[96px]"
                />
              </label>

              <label className="block text-xs text-zinc-400">
                Observações
                <textarea
                  value={form.observacoes}
                  onChange={(e) => setForm((p) => ({ ...p, observacoes: up(e.target.value) }))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm min-h-[96px]"
                />
              </label>
            </div>
          </div>

          <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
            <div className="px-4 py-3 border-b border-zinc-800">
              <div className="font-medium">Itens do Conjunto</div>
              <div className="text-sm text-zinc-400 mt-1">Informe codigo ou ID, pressione Enter e adicione o componente.</div>
            </div>

            <div className="p-4 border-b border-zinc-800">
              {inlineErr && <div className="text-sm text-red-400 mb-3">{inlineErr}</div>}

              <div className="grid grid-cols-1 md:grid-cols-3 gap-3 items-end">
                <label className="block text-xs text-zinc-400">
                  Codigo
                  <input
                    ref={inlineCodigoInputRef}
                    value={inlineItemToken}
                    onChange={(e) => {
                      setInlineItemToken(e.target.value);
                      setInlineItemId("");
                      setInlineItemCodigo("");
                      setInlineItemNome("");
                      setInlineItemLabel("");
                      setInlineItemPrecoUnitario(null);
                      setInlineErr(null);
                    }}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        void handleInlineItemTokenEnter(e.currentTarget.value);
                      }
                    }}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="Ex.: 109 ou 162"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Quantidade
                  <input
                    ref={inlineQuantidadeInputRef}
                    value={inlineQuantidade}
                    onChange={(e) => setInlineQuantidade(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        submitInlineItem();
                      }
                    }}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Ordem
                  <input
                    value={inlineOrdem}
                    onChange={(e) => setInlineOrdem(e.target.value)}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  />
                </label>
              </div>

              <div className="mt-3 grid grid-cols-1 md:grid-cols-3 gap-3">
                <label className="block text-xs text-zinc-400">
                  ID
                  <input
                    value={inlineItemId || "-"}
                    disabled
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Item
                  <input
                    value={inlineItemLabel}
                    disabled
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                    placeholder="Pressione Enter para localizar o item"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Preco unitario
                  <input
                    value={inlineItemPrecoUnitario === null ? "-" : `R$ ${formatMoneyBR(inlineItemPrecoUnitario)}`}
                    disabled
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-right tabular-nums disabled:opacity-60"
                  />
                </label>
              </div>

              <div className="mt-3 flex items-center justify-end gap-2">
                {inlineMode === "edit" && (
                  <button
                    type="button"
                    onClick={cancelInlineEdit}
                    className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
                  >
                    Cancelar
                  </button>
                )}
                <button
                  type="button"
                  onClick={submitInlineItem}
                  className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
                >
                  {inlineMode === "edit" ? "Salvar" : "Adicionar"}
                </button>
              </div>
            </div>

            <table className="w-full text-sm">
              <thead className="bg-zinc-900/70">
                <tr className="text-zinc-200">
                  <th className="px-3 py-3 text-left whitespace-nowrap">Ordem</th>
                  <th className="px-3 py-3 text-left whitespace-nowrap">ID</th>
                  <th className="px-3 py-3 text-left whitespace-nowrap">Codigo</th>
                  <th className="px-3 py-3 text-left">Item</th>
                  <th className="px-3 py-3 text-right whitespace-nowrap">Quantidade</th>
                  <th className="px-3 py-3 text-right whitespace-nowrap">Preco unitario</th>
                  <th className="px-3 py-3 text-right whitespace-nowrap">Total</th>
                  <th className="px-3 py-3 text-right whitespace-nowrap">Acoes</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-800">
                {itens.length === 0 && (
                  <tr>
                    <td colSpan={8} className="px-3 py-6 text-zinc-400">
                      Nenhum componente adicionado.
                    </td>
                  </tr>
                )}

                {itens.map((r) => (
                  <tr key={r.localKey}>
                    <td className="px-3 py-3 whitespace-nowrap">{r.ordem || "-"}</td>
                    <td className="px-3 py-3 whitespace-nowrap">{r.item_id || "-"}</td>
                    <td className="px-3 py-3 whitespace-nowrap">{r.item_codigo || "-"}</td>
                    <td className="px-3 py-3">{r.item_nome || r.item_label || "-"}</td>
                    <td className="px-3 py-3 text-right whitespace-nowrap">{r.quantidade || "-"}</td>
                    <td className="px-3 py-3 text-right whitespace-nowrap tabular-nums">
                      {r.item_preco_unitario === null ? "-" : `R$ ${formatMoneyBR(r.item_preco_unitario)}`}
                    </td>
                    <td className="px-3 py-3 text-right whitespace-nowrap tabular-nums">
                      {(() => {
                        const quantidade = parseDecimalBR(String(r.quantidade ?? "").trim());
                        if (!Number.isFinite(quantidade) || quantidade <= 0 || r.item_preco_unitario === null) return "-";
                        return `R$ ${formatMoneyBR(quantidade * r.item_preco_unitario)}`;
                      })()}
                    </td>
                    <td className="px-3 py-3">
                      <div className="flex items-center justify-end gap-2">
                        <button
                          type="button"
                          onClick={() => startInlineEdit(r.localKey)}
                          className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
                        >
                          Editar
                        </button>
                        <button
                          type="button"
                          onClick={() => removeInlineItemRow(r.localKey)}
                          className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
                        >
                          Remover
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {false && (
          <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-3">
            <div className="flex items-center justify-between gap-2 flex-wrap">
              <div>
                <div className="text-lg font-semibold">Itens do Conjunto</div>
                <div className="text-sm text-zinc-400">Ordem, item e quantidade. Remoção é soft delete.</div>
              </div>
              <button
                type="button"
                onClick={addItemRow}
                className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
              >
                Adicionar item
              </button>
            </div>

            <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
              <div className="overflow-auto">
                <table className="w-full text-sm">
                  <thead className="bg-zinc-900/70">
                    <tr className="text-zinc-200">
                      <th className="px-3 py-3 text-left whitespace-nowrap w-24">Ordem</th>
                      <th className="px-3 py-3 text-left whitespace-nowrap">Item</th>
                      <th className="px-3 py-3 text-left whitespace-nowrap w-36">Quantidade</th>
                      <th className="px-3 py-3 text-right whitespace-nowrap w-24">Ações</th>
                    </tr>
                  </thead>
                  <tbody>
                    {itens.length === 0 && (
                      <tr>
                        <td colSpan={4} className="px-3 py-6 text-zinc-400">
                          Nenhum componente. Clique em “Adicionar item”.
                        </td>
                      </tr>
                    )}

                    {itens.map((r) => (
                      <tr key={r.localKey} className="border-t border-zinc-900/60 align-top">
                        <td className="px-3 py-2">
                          <input
                            value={r.ordem}
                            onChange={(e) => setItens((p) => p.map((x) => (x.localKey === r.localKey ? { ...x, ordem: e.target.value } : x)))}
                            className="w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2"
                          />
                        </td>
                        <td className="px-3 py-2">
                          <div className="space-y-1 relative">
                            <div className="grid grid-cols-1 md:grid-cols-[160px_1fr_auto] gap-2">
                              <input
                                value={r.item_id}
                                onChange={(e) =>
                                  setItens((p) =>
                                    p.map((x) =>
                                      x.localKey === r.localKey ? { ...x, item_id: e.target.value, item_label: x.item_label } : x
                                    )
                                  )
                                }
                                onKeyDown={(e) => {
                                  if (e.key === "Enter") {
                                    e.preventDefault();
                                    void handleItemTokenEnter(r.localKey, e.currentTarget.value);
                                  }
                                }}
                                className="w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2"
                                placeholder="ID ou codigo"
                              />
                              <input
                                value={suggestKey === r.localKey ? suggestTerm : ""}
                                onChange={(e) => {
                                  setSuggestKey(r.localKey);
                                  setSuggestTerm(e.target.value);
                                }}
                                onFocus={() => {
                                  setSuggestKey(r.localKey);
                                  setSuggestTerm("");
                                  setSuggestRows([]);
                                }}
                                onKeyDown={(e) => {
                                  if (e.key === "Enter") {
                                    e.preventDefault();
                                    void handleItemTokenEnter(r.localKey, e.currentTarget.value);
                                  }
                                }}
                                className="w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2"
                                placeholder="Buscar item por código/nome"
                              />
                            </div>

                            {r.item_label && <div className="text-xs text-zinc-400">Selecionado: {r.item_label}</div>}

                            {suggestKey === r.localKey && (
                              <div className="absolute z-20 mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 shadow-lg overflow-hidden">
                                <div className="px-3 py-2 text-xs text-zinc-400 border-b border-zinc-900/60">
                                  {suggestBusyKey === r.localKey ? "Buscando..." : "Sugestões"}
                                </div>
                                <div className="max-h-56 overflow-auto">
                                  {suggestRows.length === 0 && (
                                    <div className="px-3 py-2 text-sm text-zinc-500">Sem resultados.</div>
                                  )}
                                  {suggestRows.map((it) => (
                                    <button
                                      type="button"
                                      key={it.id}
                                      onClick={() => pickSuggestion(r.localKey, it)}
                                      className="w-full text-left px-3 py-2 hover:bg-zinc-900/40"
                                    >
                                      <div className="text-sm text-zinc-100">
                                        {it.codigo_interno ?? ""} {it.nome ? `— ${it.nome}` : ""}
                                      </div>
                                      <div className="text-xs text-zinc-500">ID: {it.id}</div>
                                    </button>
                                  ))}
                                </div>
                              </div>
                            )}
                          </div>
                        </td>
                        <td className="px-3 py-2">
                          <input
                            value={r.quantidade}
                            onChange={(e) => setItens((p) => p.map((x) => (x.localKey === r.localKey ? { ...x, quantidade: e.target.value } : x)))}
                            className="w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2"
                          />
                        </td>
                        <td className="px-3 py-2 text-right">
                          <button
                            type="button"
                            onClick={() => removeItemRow(r.localKey)}
                            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
                          >
                            Remover
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
          )}

          <div className="flex items-center gap-2">
            <button
              type="submit"
              disabled={busy}
              className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium text-sm disabled:opacity-60"
            >
              {busy ? "Salvando..." : "Salvar"}
            </button>
            <Link
              href="/configuracoes/comercial/conjuntos"
              className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
            >
              Cancelar
            </Link>
          </div>
        </form>
      )}

      {showLookup && (
        <div
          className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4 md:items-center"
          onClick={(e) => e.target === e.currentTarget && closeLookupModal()}
          role="presentation"
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-label="Localizar item"
            className="w-full max-w-7xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40 flex items-center justify-between gap-3">
              <div>
                <div className="font-semibold text-zinc-100">Localizar item</div>
                <div className="text-xs text-zinc-400 mt-1">Filtre por nome, codigo ou fabricante para localizar o ID.</div>
              </div>
              <button
                type="button"
                onClick={closeLookupModal}
                className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 text-sm"
              >
                Fechar
              </button>
            </div>

            <div className="p-5 space-y-4">
              <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Nome/Codigo</div>
                  <input
                    value={lookupTerm}
                    onChange={(e) => setLookupTerm(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        void handleLookupSearch(e.currentTarget.value, lookupFornecedor);
                      }
                    }}
                    className="w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    aria-label="Buscar item por nome ou codigo"
                    title="Buscar item por nome ou codigo"
                  />
                </div>
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Fornecedor</div>
                  <input
                    value={lookupFornecedor}
                    onChange={(e) => setLookupFornecedor(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        void handleLookupSearch(lookupTerm, e.currentTarget.value);
                      }
                    }}
                    className="w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    aria-label="Buscar item por fornecedor"
                    title="Buscar item por fornecedor"
                  />
                </div>
              </div>

              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => void handleLookupSearch()}
                  className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium"
                  disabled={lookupBusy}
                >
                  Buscar
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setLookupTerm("");
                    setLookupFornecedor("");
                    setLookupRows([]);
                    setLookupErr(null);
                    void handleLookupSearch("", "");
                  }}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
                >
                  Limpar
                </button>
              </div>

              {lookupErr && <div className="text-sm text-red-400">{lookupErr}</div>}

              <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
                <div className="overflow-auto max-h-[60dvh]">
                  <table className="w-full text-sm table-fixed">
                    <colgroup>
                      <col className="w-16" />
                      <col className="w-36" />
                      <col className="w-[34%]" />
                      <col className="w-[22%]" />
                      <col className="w-32" />
                      <col className="w-28" />
                      <col className="w-20" />
                    </colgroup>
                    <thead className="bg-zinc-900/70 sticky top-0 z-10">
                      <tr className="text-zinc-200">
                        <th className="px-4 py-3 text-left cursor-pointer whitespace-nowrap" onClick={() => handleSort("id")}>
                          ID {sortKey === "id" && (sortDir === "asc" ? "^" : "v")}
                        </th>
                        <th className="px-4 py-3 text-left cursor-pointer whitespace-nowrap" onClick={() => handleSort("codigo")}>
                          Codigo {sortKey === "codigo" && (sortDir === "asc" ? "^" : "v")}
                        </th>
                        <th className="px-4 py-3 text-left cursor-pointer" onClick={() => handleSort("descricao")}>
                          Descricao {sortKey === "descricao" && (sortDir === "asc" ? "^" : "v")}
                        </th>
                        <th className="px-4 py-3 text-left cursor-pointer" onClick={() => handleSort("fornecedor")}>
                          Fornecedor {sortKey === "fornecedor" && (sortDir === "asc" ? "^" : "v")}
                        </th>
                        <th className="px-4 py-3 text-left cursor-pointer whitespace-nowrap" onClick={() => handleSort("ultima")}>
                          Ultima entrada {sortKey === "ultima" && (sortDir === "asc" ? "^" : "v")}
                        </th>
                        <th className="px-4 py-3 text-right cursor-pointer whitespace-nowrap" onClick={() => handleSort("preco")}>
                          Preco sugerido {sortKey === "preco" && (sortDir === "asc" ? "^" : "v")}
                        </th>
                        <th className="px-4 py-3 text-right cursor-pointer whitespace-nowrap" onClick={() => handleSort("estoque")}>
                          Saldo {sortKey === "estoque" && (sortDir === "asc" ? "^" : "v")}
                        </th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-zinc-800">
                      {lookupBusy && (
                        <tr>
                          <td colSpan={7} className="px-4 py-6 text-zinc-400 text-center">
                            Buscando...
                          </td>
                        </tr>
                      )}

                      {!lookupBusy &&
                        sortedLookupRows.map((it) => (
                          <tr
                            key={it.id}
                            className="hover:bg-zinc-900/40 cursor-pointer"
                            onClick={() => {
                              applyLookupSelection(it);
                            }}
                          >
                            <td className="px-4 py-3 whitespace-nowrap">{it.id}</td>
                            <td className="px-4 py-3 whitespace-nowrap">{it.codigo_interno ?? "-"}</td>
                            <td className="px-4 py-3 break-words">{it.nome ?? "-"}</td>
                            <td className="px-4 py-3 break-words">{it.fornecedor ?? "-"}</td>
                            <td className="px-4 py-3 whitespace-nowrap">{formatDateBR(it.ultima_entrada)}</td>
                            <td className="px-4 py-3 text-right whitespace-nowrap tabular-nums">
                              {formatMoneyBR(Number(it.preco_sugerido ?? 0))}
                            </td>
                            <td className="px-4 py-3 text-right whitespace-nowrap tabular-nums">
                              {formatNumberBR(it.estoque_atual)}
                            </td>
                          </tr>
                        ))}

                      {!lookupBusy && lookupRows.length === 0 && (
                        <tr>
                          <td colSpan={7} className="px-4 py-6 text-zinc-400 text-center">
                            Nenhum item encontrado.
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
    </div>
  );
}
