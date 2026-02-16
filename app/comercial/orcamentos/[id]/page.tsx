"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { useParams, useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import { formatDecimalBR, formatMoneyBR, parseDecimalBR } from "@/lib/decimal";
import type { OrcamentoItemRow, OrcamentoRow, OrcamentoStatus, UsuarioLookupRow } from "@/lib/comercial/types";
import { isOrcamentoReadOnly, mapOrcamentoError, n, toSupabaseErrorLike, upperTrim } from "@/lib/comercial/utils";
import {
  addItem,
  cancelarOrcamento,
  createOrcamento,
  deleteItem,
  finalizarOrcamento,
  getItemById,
  getOrcamento,
  getOrcamentoConfig,
  getUsuarioIdByAuthUserId,
  listCondicoesPagamentoAtivas,
  listVendedores,
  searchClientes,
  updateItem,
  updateOrcamento,
} from "@/lib/comercial/orcamentos.service";

import type { ItemByIdRow } from "@/lib/comercial/orcamentos.service";

type ItemLookupBaseRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  preco_unitario: number | null;
  fornecedores?: { nome?: string | null } | null;
};

type MovRow = { item_id: number; data_movimentacao: string };
type EstoqueRow = { item_id: number; quantidade_atual: number | null };

type ItemLookupRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  fornecedor: string | null;
  ultima_entrada: string | null;
  preco_unitario: number | null;
  estoque_atual: number | null;
};

type ConjuntoCatalogoRow = {
  conjunto_id: string;
  codigo: string | null;
  nome: string | null;
  preco_sugerido: number | null;
};

type SortKey = "id" | "codigo" | "descricao" | "fornecedor" | "ultima" | "preco" | "estoque";
type SortDir = "asc" | "desc";
type SortValue = string | number | null;

type ConfirmOptions = {
  title: string;
  description?: string;
  confirmText?: string;
  cancelText?: string;
  destructive?: boolean;
};

function hasAny(caps: Capabilities | null, keys: CapabilityKey[]): boolean {
  return requireAny(caps, keys);
}

function useConfirmDialog() {
  const [opts, setOpts] = useState<ConfirmOptions | null>(null);
  const resolverRef = useRef<((v: boolean) => void) | null>(null);

  const confirm = useCallback((next: ConfirmOptions) => {
    return new Promise<boolean>((resolve) => {
      resolverRef.current = resolve;
      setOpts(next);
    });
  }, []);

  const close = useCallback((value: boolean) => {
    const resolve = resolverRef.current;
    resolverRef.current = null;
    setOpts(null);
    resolve?.(value);
  }, []);

  const dialog = opts ? (
    <div
      className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
      onClick={(e) => e.target === e.currentTarget && close(false)}
      role="presentation"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={opts.title}
        className="w-full max-w-lg bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
          <div className="font-semibold text-zinc-100">{opts.title}</div>
          {opts.description && <div className="text-xs text-zinc-400 mt-1">{opts.description}</div>}
        </div>
        <div className="px-5 py-4 flex items-center justify-end gap-2">
          <button
            type="button"
            onClick={() => close(false)}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
          >
            {opts.cancelText ?? "Cancelar"}
          </button>
          <button
            type="button"
            onClick={() => close(true)}
            className={
              opts.destructive
                ? "px-4 py-2 rounded-md bg-red-600 text-white hover:bg-red-500 font-medium"
                : "px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
            }
          >
            {opts.confirmText ?? "Confirmar"}
          </button>
        </div>
      </div>
    </div>
  ) : null;

  return { confirm, dialog };
}

function formatDateBR(iso?: string | null) {
  if (!iso) return "-";
  const [y, m, d] = String(iso).slice(0, 10).split("-");
  if (!y || !m || !d) return String(iso);
  return `${d}/${m}/${y}`;
}

function statusBadgeClass(status: string): string {
  const s = String(status ?? "").toUpperCase();
  if (s === "RASCUNHO") return "bg-blue-500/15 text-blue-300 border-blue-500/30";
  if (s === "FINALIZADO") return "bg-emerald-500/15 text-emerald-300 border-emerald-500/30";
  if (s === "CANCELADO") return "bg-red-500/15 text-red-300 border-red-500/30";
  return "bg-zinc-500/10 text-zinc-300 border-zinc-500/30";
}

type OrcamentoForm = {
  titulo: string;
  emissao_date: string;
  cliente_id: number | null;
  vendedor_usuario_id: string;
  condicao_pagamento_id: string | null;
  desconto_global_percent: string;
  valor_frete: string;
  observacoes: string;
};

function formFromRow(row: OrcamentoRow): OrcamentoForm {
  return {
    titulo: row.titulo ?? "",
    emissao_date: String(row.emissao_date ?? "").slice(0, 10),
    cliente_id: row.cliente_id ?? null,
    vendedor_usuario_id: String(row.vendedor_usuario_id ?? ""),
    condicao_pagamento_id: row.condicao_pagamento_id ?? null,
    desconto_global_percent: String(row.desconto_global_percent ?? "0"),
    valor_frete: String(row.valor_frete ?? "0"),
    observacoes: row.observacoes ?? "",
  };
}

type ItemDialogState =
  | {
      open: false;
    }
  | {
      open: true;
      quantidade: string;
      valorUnitario: string;
      descontoItemPercent: string;
      editingId: string;
      itemNome: string;
      busy: boolean;
      error: string | null;
    };

function closedItemDialog(): ItemDialogState {
  return { open: false };
}

type NewDialogState =
  | { open: false }
  | {
      open: true;
      busy: boolean;
      error: string | null;
      clienteTerm: string;
      clienteResults: Array<{ id: number; nome: string | null }>;
      clienteId: number | null;
      titulo: string;
      vendedorUsuarioId: string;
      condicaoPagamentoId: string | null;
    };

function closedNewDialog(): NewDialogState {
  return { open: false };
}

export default function OrcamentoPage() {
  const params = useParams();
  const rawId = (params as Record<string, string | string[] | undefined>)?.id;
  const idParam = String(Array.isArray(rawId) ? rawId[0] : rawId ?? "");
  const router = useRouter();

  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

  const te = useTenantEmpresa();
  const tenantId = te.tenantId;
  const empresaId = te.empresaId;
  const authUserId = te.sessionUserId ?? null;

  const { loading: permissionsLoading, ready, capabilities } = usePermissions();

  const canView = hasAny(capabilities, ["financeiro.read", "financeiro.write", "os.read", "os.write"]);
  const canWrite = hasAny(capabilities, ["financeiro.write", "os.write"]);

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const [orc, setOrc] = useState<OrcamentoRow | null>(null);
  const [itens, setItens] = useState<OrcamentoItemRow[]>([]);
  const [form, setForm] = useState<OrcamentoForm | null>(null);

  const [cfgDescontoMax, setCfgDescontoMax] = useState<number>(0);
  const [cfgCondPadraoId, setCfgCondPadraoId] = useState<string | null>(null);
  const [cfgMargemLucroPadraoPercent, setCfgMargemLucroPadraoPercent] = useState<number>(0);
  const [condicoes, setCondicoes] = useState<Array<{ id: string; nome: string | null; acrescimo_percent: number | string | null }>>([]);
  const [vendedores, setVendedores] = useState<UsuarioLookupRow[]>([]);

  const [newDialog, setNewDialog] = useState<NewDialogState>(closedNewDialog);
  const newClienteReqRef = useRef(0);

  const [itemDialog, setItemDialog] = useState<ItemDialogState>(closedItemDialog);
  const [inlineItemId, setInlineItemId] = useState<string>("");
  const [inlineItem, setInlineItem] = useState<ItemByIdRow | null>(null);
  const [inlineQuantidade, setInlineQuantidade] = useState<string>("1");
  const [inlineValorUnitario, setInlineValorUnitario] = useState<string>("0");
  const [inlineDesconto, setInlineDesconto] = useState<string>("0");
  const [inlineBusy, setInlineBusy] = useState<boolean>(false);
  const [inlineErr, setInlineErr] = useState<string | null>(null);
  const [inlineEditingItemId, setInlineEditingItemId] = useState<string | null>(null);
  const [inlineEstoqueAtual, setInlineEstoqueAtual] = useState<number | null>(null);
  const inlineMode = inlineEditingItemId ? "edit" : "add";
  const inlineFormRef = useRef<HTMLDivElement | null>(null);
  const inlineItemReqRef = useRef(0);

  const [estoqueByItemId, setEstoqueByItemId] = useState<Record<number, number>>({});

  const [showLookup, setShowLookup] = useState(false);
  const [lookupBuscarConjuntos, setLookupBuscarConjuntos] = useState(false);
  const [lookupNome, setLookupNome] = useState("");
  const [lookupFornecedor, setLookupFornecedor] = useState("");
  const [lookupRows, setLookupRows] = useState<ItemLookupRow[]>([]);
  const [lookupConjuntoRows, setLookupConjuntoRows] = useState<ConjuntoCatalogoRow[]>([]);
  const [lookupBusy, setLookupBusy] = useState(false);
  const [lookupErr, setLookupErr] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<SortKey>("id");
  const [sortDir, setSortDir] = useState<SortDir>("asc");

  const [addConjunto, setAddConjunto] = useState<
    | { open: false }
    | { open: true; conjunto: ConjuntoCatalogoRow; quantidade: string; busy: boolean; error: string | null }
  >({ open: false });

  const { confirm, dialog: confirmDialog } = useConfirmDialog();

  const status = String(orc?.status ?? "").toUpperCase() as OrcamentoStatus | string;
  const readOnly = isOrcamentoReadOnly(status);

  const inlineAcrescimoCondPagPercent = useMemo(() => {
    const id = form?.condicao_pagamento_id ?? null;
    if (!id) return 0;
    const found = condicoes.find((c) => c.id === id);
    const acresc = n(found?.acrescimo_percent);
    return Number.isFinite(acresc) ? acresc : 0;
  }, [condicoes, form?.condicao_pagamento_id]);

  const loadLookups = useCallback(async () => {
    if (!supabase || !tenantId || !empresaId) return;
    if (te.loading || te.refreshing) return;

    try {
      const [cfg, cps, vends] = await Promise.all([
        getOrcamentoConfig(supabase, { tenantId, empresaId }),
        listCondicoesPagamentoAtivas(supabase, { tenantId, empresaId }),
        listVendedores(supabase),
      ]);
      setCfgDescontoMax(n(cfg.desconto_max_percent));
      setCfgCondPadraoId(cfg.condicao_pagamento_padrao_id ?? null);
      setCfgMargemLucroPadraoPercent(n(cfg.margem_lucro_padrao_percent));
      setCondicoes(cps.map((c) => ({ id: c.id, nome: c.nome ?? null, acrescimo_percent: c.acrescimo_percent ?? 0 })));
      setVendedores(vends);
    } catch {
      setCfgDescontoMax(0);
      setCfgCondPadraoId(null);
      setCfgMargemLucroPadraoPercent(0);
      setCondicoes([]);
      setVendedores([]);
    }
  }, [empresaId, supabase, te.loading, te.refreshing, tenantId]);

  const defaultValorUnitarioFromItem = useCallback(
    (item: ItemByIdRow | null): string => {
      if (!item?.id) return "0";
      const margem = Math.max(0, n(cfgMargemLucroPadraoPercent));
      const custo = n(item.custo_ultima_compra);
      const hasCusto = Number.isFinite(custo) && custo > 0;
      const base = hasCusto ? custo : n(item.preco_unitario);
      const computed = hasCusto ? base * (1 + margem / 100) : base;
      if (!Number.isFinite(computed) || computed < 0) return "0";
      return computed.toFixed(2);
    },
    [cfgMargemLucroPadraoPercent]
  );

  const reload = useCallback(async () => {
    setErr(null);
    setOk(null);

    if (!supabase) return;
    if (te.loading || te.refreshing) return;

    if (!tenantId || !empresaId) {
      setLoading(false);
      setErr("Contexto (tenant/empresa) não carregado.");
      setOrc(null);
      setItens([]);
      setForm(null);
      return;
    }

    if (idParam === "novo") {
      setLoading(false);
      setOrc(null);
      setItens([]);
      setForm(null);
      return;
    }

    setLoading(true);
    try {
      const { orcamento, itens } = await getOrcamento(supabase, { tenantId, empresaId, idOrCodigo: idParam });
      setOrc(orcamento);
      setItens(itens);
      setForm(formFromRow(orcamento));

      // Prefer the human-friendly codigo in the URL.
      if (
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(idParam) &&
        orcamento?.codigo &&
        idParam !== orcamento.codigo
      ) {
        router.replace(`/comercial/orcamentos/${orcamento.codigo}`);
      }
    } catch (e: unknown) {
      setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao carregar orçamento."));
      setOrc(null);
      setItens([]);
      setForm(null);
    } finally {
      setLoading(false);
    }
  }, [empresaId, idParam, router, supabase, te.loading, te.refreshing, tenantId]);

  useEffect(() => {
    void loadLookups();
  }, [loadLookups]);

  useEffect(() => {
    void reload();
  }, [reload]);

  // auto-open create dialog when /novo
  useEffect(() => {
    if (idParam !== "novo") return;
    if (!supabase || !tenantId || !empresaId) return;

    let active = true;

    (async () => {
      const vendedorFromMe = authUserId ? await getUsuarioIdByAuthUserId(supabase, { authUserId }) : null;
      if (!active) return;

      setNewDialog({
        open: true,
        busy: false,
        error: null,
        clienteTerm: "",
        clienteResults: [],
        clienteId: null,
        titulo: "",
        vendedorUsuarioId: vendedorFromMe?.id ? String(vendedorFromMe.id) : "",
        condicaoPagamentoId: cfgCondPadraoId,
      });
    })();

    return () => {
      active = false;
    };
  }, [authUserId, cfgCondPadraoId, empresaId, idParam, supabase, tenantId]);

  // search clientes in new dialog
  useEffect(() => {
    if (!newDialog.open) return;
    if (!supabase || !tenantId || !empresaId) return;

    const term = newDialog.clienteTerm.trim();
    const reqId = ++newClienteReqRef.current;
    const t = setTimeout(async () => {
      try {
        if (!term) {
          if (reqId === newClienteReqRef.current) {
            setNewDialog((p) => (p.open ? { ...p, clienteResults: [] } : p));
          }
          return;
        }
        const res = await searchClientes(supabase, { tenantId, empresaId, term });
        if (reqId === newClienteReqRef.current) {
          setNewDialog((p) => (p.open ? { ...p, clienteResults: res } : p));
        }
      } catch {
        if (reqId === newClienteReqRef.current) {
          setNewDialog((p) => (p.open ? { ...p, clienteResults: [] } : p));
        }
      }
    }, 250);

    return () => clearTimeout(t);
  }, [empresaId, newDialog, supabase, tenantId]);

  // inline: buscar item por código (id)
  useEffect(() => {
    if (!supabase || !tenantId || !empresaId) return;

    const raw = String(inlineItemId ?? "").trim();
    const parsed = Number(raw);
    const reqId = ++inlineItemReqRef.current;

    if (!raw) {
      setInlineItem(null);
      setInlineErr(null);
      return;
    }

    if (!Number.isFinite(parsed) || parsed <= 0) {
      setInlineItem(null);
      setInlineErr("Código inválido.");
      return;
    }

    const t = setTimeout(async () => {
      try {
        const item = await getItemById(supabase, { tenantId, empresaId, id: parsed });
        if (reqId !== inlineItemReqRef.current) return;
        if (!item?.id) {
          setInlineItem(null);
          setInlineErr("Item não encontrado.");
          return;
        }
        setInlineItem(item);
        setInlineErr(null);
        if (!inlineEditingItemId) setInlineValorUnitario(defaultValorUnitarioFromItem(item));
      } catch {
        if (reqId !== inlineItemReqRef.current) return;
        setInlineItem(null);
        setInlineErr("Erro ao buscar item.");
      }
    }, 250);

    return () => clearTimeout(t);
  }, [defaultValorUnitarioFromItem, empresaId, inlineEditingItemId, inlineItemId, supabase, tenantId]);

  useEffect(() => {
    if (!supabase || !inlineItem?.id) {
      setInlineEstoqueAtual(null);
      return;
    }

    let cancelled = false;
    void (async () => {
      try {
        const { data } = await supabase.from("estoque").select("quantidade_atual").eq("item_id", inlineItem.id).maybeSingle();
        if (cancelled) return;
        setInlineEstoqueAtual(Number(data?.quantidade_atual ?? 0));
      } catch {
        if (cancelled) return;
        setInlineEstoqueAtual(null);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [inlineItem?.id, supabase]);

  useEffect(() => {
    if (!supabase) return;

    const ids = Array.from(
      new Set(itens.map((it) => Number(it.item_id)).filter((v) => Number.isFinite(v) && v > 0))
    );

    if (ids.length === 0) {
      setEstoqueByItemId({});
      return;
    }

    let cancelled = false;
    void (async () => {
      try {
        const { data } = await supabase.from("estoque").select("item_id,quantidade_atual").in("item_id", ids);
        if (cancelled) return;

        const next: Record<number, number> = {};
        const rows = (data ?? []) as EstoqueRow[];
        rows.forEach((row) => {
          const id = Number(row.item_id);
          if (!Number.isFinite(id) || id <= 0) return;
          next[id] = Number(row.quantidade_atual ?? 0);
        });
        setEstoqueByItemId(next);
      } catch {
        if (cancelled) return;
        setEstoqueByItemId({});
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [itens, supabase]);

  async function handleLookupSearch(nextNome?: string, nextFornecedor?: string) {
    if (!supabase) return;

    setLookupErr(null);
    setLookupBusy(true);

    const nomeTerm = (nextNome ?? lookupNome).trim();
    const fornecedorTerm = (nextFornecedor ?? lookupFornecedor).trim();

    if (lookupBuscarConjuntos) {
      try {
        let q = supabase
          .schema("r")
          .from("r_orcamento_catalogo_busca")
          .select("*")
          .eq("origem", "CONJUNTO");

        if (nomeTerm) {
          const like = `%${nomeTerm}%`;
          q = q.or(`codigo.ilike.${like},nome.ilike.${like}`);
        }

        const { data, error } = await q.order("nome", { ascending: true }).limit(50);
        if (error) {
          setLookupErr(error.message);
          setLookupConjuntoRows([]);
          setLookupRows([]);
          setLookupBusy(false);
          return;
        }

        const rows = (data ?? []) as Array<Record<string, unknown>>;
        setLookupConjuntoRows(
          rows
            .map((r) => {
              const conjuntoId = r.conjunto_id ? String(r.conjunto_id) : "";
              if (!conjuntoId) return null;
              const codigo = typeof r.codigo === "string" ? r.codigo : r.codigo ? String(r.codigo) : null;
              const nome = typeof r.nome === "string" ? r.nome : r.nome ? String(r.nome) : null;
              const preco = Number(r.preco_sugerido);
              return {
                conjunto_id: conjuntoId,
                codigo,
                nome,
                preco_sugerido: Number.isFinite(preco) ? preco : null,
              } satisfies ConjuntoCatalogoRow;
            })
            .filter(Boolean) as ConjuntoCatalogoRow[]
        );

        setLookupRows([]);
        setLookupBusy(false);
        return;
      } catch (e: unknown) {
        setLookupErr(e instanceof Error ? e.message : "Erro ao buscar conjuntos.");
        setLookupConjuntoRows([]);
        setLookupRows([]);
        setLookupBusy(false);
        return;
      }
    }

    setLookupConjuntoRows([]);

    const baseSelect = fornecedorTerm
      ? "id,codigo_interno,nome,preco_unitario,fornecedores!itens_tenant_empresa_fornecedor_fk!inner(nome)"
      : "id,codigo_interno,nome,preco_unitario,fornecedores!itens_tenant_empresa_fornecedor_fk(nome)";

    let query = supabase.from("itens").select(baseSelect).eq("ativo", true);

    if (nomeTerm) query = query.ilike("nome", `%${nomeTerm}%`);
    if (fornecedorTerm) query = query.ilike("fornecedores.nome", `%${fornecedorTerm}%`);

    const { data, error } = await query.order("nome", { ascending: true }).limit(50);

    if (error) {
      setLookupErr(error.message);
      setLookupRows([]);
      setLookupBusy(false);
      return;
    }

    const baseRows = (data ?? []) as ItemLookupBaseRow[];
    const ids = baseRows.map((r) => r.id);
    const ultimaMap = new Map<number, string>();
    const stockMap = new Map<number, number>();

    if (ids.length > 0) {
      const { data: movData, error: movErr } = await supabase
        .from("movimentacoes")
        .select("item_id,data_movimentacao")
        .eq("tipo", "entrada")
        .in("item_id", ids)
        .order("data_movimentacao", { ascending: false });

      if (!movErr) {
        const movRows = (movData ?? []) as MovRow[];
        movRows.forEach((m) => {
          if (!ultimaMap.has(m.item_id)) ultimaMap.set(m.item_id, m.data_movimentacao);
        });
      }

      const { data: estData } = await supabase.from("estoque").select("item_id,quantidade_atual").in("item_id", ids);
      const estoqueRows = (estData ?? []) as EstoqueRow[];
      estoqueRows.forEach((e) => {
        stockMap.set(e.item_id, Number(e.quantidade_atual ?? 0));
      });
    }

    setLookupRows(
      baseRows.map((r) => ({
        id: r.id,
        codigo_interno: r.codigo_interno,
        nome: r.nome,
        fornecedor: r.fornecedores?.nome ?? null,
        ultima_entrada: ultimaMap.get(r.id) ?? null,
        preco_unitario: r.preco_unitario,
        estoque_atual: stockMap.has(r.id) ? stockMap.get(r.id)! : null,
      }))
    );

    setLookupBusy(false);
  }

  async function handleAddConjuntoConfirm() {
    if (!supabase) return;
    if (!orc?.id) return;
    if (!tenantId || !empresaId) return;
    if (readOnly || !canWrite) return;
    if (!addConjunto.open) return;

    const qtd = parseDecimalBR(addConjunto.quantidade);
    if (!Number.isFinite(qtd) || qtd <= 0) {
      setAddConjunto((p) => (p.open ? { ...p, error: "Quantidade inválida." } : p));
      return;
    }

    setAddConjunto((p) => (p.open ? { ...p, busy: true, error: null } : p));
    try {
      const { data, error } = await supabase.schema("m").rpc("fn_orcamento_adicionar_conjunto", {
        p_orcamento_id: orc.id,
        p_conjunto_id: addConjunto.conjunto.conjunto_id,
        p_quantidade: qtd,
      });
      if (error) throw error;

      const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
      const firstValue = (obj: Record<string, unknown>, keys: string[]): unknown => {
        for (const k of keys) {
          const v = obj[k];
          if (v !== null && v !== undefined) return v;
        }
        return 0;
      };

      const itensInseridos = row ? n(firstValue(row, ["itens_inseridos", "qtd_itens", "itens"])) : 0;
      const totalEstimado = row ? n(firstValue(row, ["total_estimado", "valor_total", "total"])) : 0;

      setAddConjunto({ open: false });
      setShowLookup(false);
      await reload();

      if (itensInseridos > 0 || totalEstimado > 0) {
        setOk(`Conjunto inserido: ${itensInseridos} itens, total estimado R$ ${formatMoneyBR(totalEstimado)}.`);
      } else {
        setOk("Conjunto inserido.");
      }
    } catch (e: unknown) {
      setAddConjunto((p) =>
        p.open ? { ...p, busy: false, error: mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao inserir conjunto.") } : p
      );
    } finally {
      setAddConjunto((p) => (p.open ? { ...p, busy: false } : p));
    }
  }

  function sortRows(rows: ItemLookupRow[], key: SortKey, dir: SortDir): ItemLookupRow[] {
    const factor = dir === "asc" ? 1 : -1;
    return [...rows].sort((a, b) => {
      const val = (row: ItemLookupRow, k: SortKey): SortValue => {
        switch (k) {
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
          case "estoque":
            return typeof row.estoque_atual === "number" ? row.estoque_atual : null;
        }
      };

      const va = val(a, key);
      const vb = val(b, key);

      const aNull = va === null || va === undefined || va === "";
      const bNull = vb === null || vb === undefined || vb === "";
      if (aNull && bNull) return 0;
      if (aNull) return 1;
      if (bNull) return -1;

      if (va < vb) return -1 * factor;
      if (va > vb) return 1 * factor;
      return 0;
    });
  }

  function handleSort(key: SortKey) {
    if (sortKey === key) {
      setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setSortKey(key);
      setSortDir("asc");
    }
  }

  const sortedLookupRows = useMemo(() => sortRows(lookupRows, sortKey, sortDir), [lookupRows, sortKey, sortDir]);

  function openLookupModal(initialNome?: string) {
    const nome = (initialNome ?? "").trim();
    setShowLookup(true);
    setLookupErr(null);
    setLookupRows([]);
    setLookupConjuntoRows([]);
    setLookupNome(nome);
    setLookupFornecedor("");
    void handleLookupSearch(nome, "");
  }

  async function handleCodigoEnter(value: string) {
    if (!supabase || !tenantId || !empresaId) return;

    const raw = String(value ?? "").trim();
    if (!raw) {
      openLookupModal("");
      return;
    }

    const parsed = Number(raw);
    if (!Number.isFinite(parsed) || parsed <= 0) {
      openLookupModal(raw);
      return;
    }

    const reqId = ++inlineItemReqRef.current;
    try {
      const item = await getItemById(supabase, { tenantId, empresaId, id: parsed });
      if (reqId !== inlineItemReqRef.current) return;
      if (!item?.id) {
        setInlineItem(null);
        setInlineErr("Item não encontrado.");
        openLookupModal("");
        return;
      }
      setInlineItem(item);
      setInlineErr(null);
      if (!inlineEditingItemId) setInlineValorUnitario(defaultValorUnitarioFromItem(item));
    } catch {
      if (reqId !== inlineItemReqRef.current) return;
      setInlineItem(null);
      setInlineErr("Erro ao buscar item.");
      openLookupModal("");
    }
  }

  const closeNewDialog = useCallback(() => {
    setNewDialog(closedNewDialog());
    router.push("/comercial/orcamentos");
  }, [router]);

  const submitNew = useCallback(async () => {
    if (!newDialog.open) return;
    if (!supabase || !tenantId || !empresaId) return;

    const clienteId = newDialog.clienteId;
    const titulo = upperTrim(newDialog.titulo);
    const vendedorUsuarioId = String(newDialog.vendedorUsuarioId ?? "").trim();

    if (!clienteId) {
      setNewDialog((p) => (p.open ? { ...p, error: "Selecione um cliente." } : p));
      return;
    }
    if (!titulo) {
      setNewDialog((p) => (p.open ? { ...p, error: "Informe o título." } : p));
      return;
    }
    if (!vendedorUsuarioId) {
      setNewDialog((p) => (p.open ? { ...p, error: "Selecione um vendedor." } : p));
      return;
    }

    setNewDialog((p) => (p.open ? { ...p, busy: true, error: null } : p));
    try {
      const created = await createOrcamento(supabase, {
        tenantId,
        empresaId,
        titulo,
        clienteId,
        vendedorUsuarioId,
        condicaoPagamentoId: newDialog.condicaoPagamentoId ?? null,
      });
      setNewDialog(closedNewDialog());
      router.replace(`/comercial/orcamentos/${created.codigo ?? created.id}`);
    } catch (e: unknown) {
      setNewDialog((p) =>
        p.open ? { ...p, busy: false, error: mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao criar orçamento.") } : p
      );
    }
  }, [empresaId, newDialog, router, supabase, tenantId]);

  const saveHeader = useCallback(
    async (e?: FormEvent) => {
      e?.preventDefault();
      if (!orc?.id || !form) return;
      if (!supabase || !tenantId || !empresaId) return;
      if (readOnly || !canWrite) return;

      const desconto = n(form.desconto_global_percent);
      if (cfgDescontoMax > 0 && desconto > cfgDescontoMax) {
        setErr(`Desconto global (%) excede o máximo configurado (${cfgDescontoMax}%).`);
        return;
      }

      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        const patch: Partial<OrcamentoRow> = {
          titulo: upperTrim(form.titulo),
          emissao_date: form.emissao_date,
          cliente_id: form.cliente_id ?? orc.cliente_id,
          vendedor_usuario_id: form.vendedor_usuario_id,
          condicao_pagamento_id: form.condicao_pagamento_id ?? null,
          desconto_global_percent: desconto,
          valor_frete: n(form.valor_frete),
          observacoes: form.observacoes,
        };

        await updateOrcamento(supabase, {
          tenantId,
          empresaId,
          id: orc.id,
          patch,
        });
        setOk("Orçamento atualizado.");
        await reload();
      } catch (e2: unknown) {
        setErr(mapOrcamentoError(toSupabaseErrorLike(e2), "Erro ao salvar."));
      } finally {
        setBusy(false);
      }
    },
    [canWrite, cfgDescontoMax, empresaId, form, orc?.cliente_id, orc?.id, readOnly, reload, supabase, tenantId]
  );

  const doFinalizar = useCallback(async () => {
    if (!orc?.id) return;
    if (!supabase || !tenantId || !empresaId) return;
    if (!canWrite || readOnly) return;

    const ok = await confirm({
      title: `Finalizar orçamento ${orc.codigo}?`,
      description: "Após finalizar, a edição fica bloqueada.",
      confirmText: "Finalizar",
    });
    if (!ok) return;

    setBusy(true);
    setErr(null);
    setOk(null);
    try {
      await finalizarOrcamento(supabase, { tenantId, empresaId, id: orc.id });
      setOk("Orçamento finalizado.");
      await reload();
    } catch (e: unknown) {
      setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao finalizar."));
    } finally {
      setBusy(false);
    }
  }, [canWrite, confirm, empresaId, orc, readOnly, reload, supabase, tenantId]);

  const doCancelar = useCallback(async () => {
    if (!orc?.id) return;
    if (!supabase || !tenantId || !empresaId) return;
    if (!canWrite || readOnly) return;

    const ok = await confirm({
      title: `Cancelar orçamento ${orc.codigo}?`,
      description: "A edição ficará bloqueada.",
      confirmText: "Cancelar",
      destructive: true,
    });
    if (!ok) return;

    setBusy(true);
    setErr(null);
    setOk(null);
    try {
      await cancelarOrcamento(supabase, { tenantId, empresaId, id: orc.id });
      setOk("Orçamento cancelado.");
      await reload();
    } catch (e: unknown) {
      setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao cancelar."));
    } finally {
      setBusy(false);
    }
  }, [canWrite, confirm, empresaId, orc, readOnly, reload, supabase, tenantId]);

  const closeItemDialog = useCallback(() => setItemDialog(closedItemDialog()), []);

  const submitItem = useCallback(async () => {
    if (!itemDialog.open) return;
    if (!supabase || !tenantId || !empresaId) return;
    if (!orc?.id) return;
    if (readOnly || !canWrite) return;

    const qty = n(itemDialog.quantidade);
    const vu = n(itemDialog.valorUnitario);
    const desc = n(itemDialog.descontoItemPercent);

    if (qty <= 0) {
      setItemDialog((p) => (p.open ? { ...p, error: "Quantidade deve ser maior que zero." } : p));
      return;
    }

    setItemDialog((p) => (p.open ? { ...p, busy: true, error: null } : p));
    try {
      await updateItem(supabase, {
        tenantId,
        empresaId,
        id: itemDialog.editingId,
        patch: {
          quantidade: qty,
          valor_unitario: vu,
          desconto_item_percent: desc,
        },
      });
      setItemDialog(closedItemDialog());
      await reload();
    } catch (e: unknown) {
      setItemDialog((p) =>
        p.open ? { ...p, busy: false, error: mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao atualizar item.") } : p
      );
    }
  }, [canWrite, empresaId, itemDialog, orc?.id, readOnly, reload, supabase, tenantId]);

  const inlineTotal = useMemo(() => {
    const qty = n(inlineQuantidade);
    const vu = n(inlineValorUnitario);
    const desc = n(inlineDesconto);
    const descGlobal = n(form?.desconto_global_percent);
    const acrescCond = Math.max(0, n(inlineAcrescimoCondPagPercent));
    const gross = qty * vu;
    const net = gross * (1 - desc / 100) * (1 + acrescCond / 100) * (1 - descGlobal / 100);
    return Number.isFinite(net) ? net : 0;
  }, [form?.desconto_global_percent, inlineAcrescimoCondPagPercent, inlineDesconto, inlineQuantidade, inlineValorUnitario]);

  const cancelInlineEdit = useCallback(() => {
    setInlineEditingItemId(null);
    setInlineItemId("");
    setInlineItem(null);
    setInlineQuantidade("1");
    setInlineValorUnitario("0");
    setInlineDesconto("0");
    setInlineErr(null);
  }, []);

  const submitInlineItem = useCallback(async () => {
    if (!supabase || !tenantId || !empresaId) return;
    if (!orc?.id) return;
    if (readOnly || !canWrite) return;
    if (!form) return;

    const parsedId = Number(String(inlineItemId ?? "").trim());
    if (!Number.isFinite(parsedId) || parsedId <= 0) {
      setInlineErr("Informe o código do item.");
      return;
    }
    if (!inlineItem?.id) {
      setInlineErr("Item não encontrado.");
      return;
    }

    const qty = n(inlineQuantidade);
    const vu = n(inlineValorUnitario);
    const desc = n(inlineDesconto);

    if (qty <= 0) {
      setInlineErr("Quantidade deve ser maior que zero.");
      return;
    }
    if (desc < 0 || desc > 100) {
      setInlineErr("Desconto deve estar entre 0 e 100.");
      return;
    }

    // Garante que a condição de pagamento / desconto global do cabeçalho estejam persistidos
    // antes de inserir/atualizar itens (triggers do banco dependem disso).
    const nextCondId = form.condicao_pagamento_id ?? null;
    const nextDescGlobal = n(form.desconto_global_percent);
    const curCondId = (orc.condicao_pagamento_id ?? null) as string | null;
    const curDescGlobal = n(orc.desconto_global_percent);

    if (cfgDescontoMax > 0 && nextDescGlobal > cfgDescontoMax) {
      setInlineErr(`Desconto global (%) excede o máximo configurado (${cfgDescontoMax}%).`);
      return;
    }

    const needHeaderSync = nextCondId !== curCondId || nextDescGlobal !== curDescGlobal;

    setInlineBusy(true);
    setInlineErr(null);
    try {
      if (needHeaderSync) {
        await updateOrcamento(supabase, {
          tenantId,
          empresaId,
          id: orc.id,
          patch: {
            condicao_pagamento_id: nextCondId,
            desconto_global_percent: nextDescGlobal,
          },
        });
      }

      if (inlineEditingItemId) {
        await updateItem(supabase, {
          tenantId,
          empresaId,
          id: inlineEditingItemId,
          patch: {
            quantidade: qty,
            valor_unitario: vu,
            desconto_item_percent: desc,
          },
        });
      } else {
        await addItem(supabase, {
          tenantId,
          empresaId,
          orcamentoId: orc.id,
          itemId: inlineItem.id,
          quantidade: qty,
          valorUnitario: vu,
          descontoItemPercent: desc,
        });
      }

      cancelInlineEdit();
      await reload();
    } catch (e: unknown) {
      setInlineErr(mapOrcamentoError(toSupabaseErrorLike(e), inlineEditingItemId ? "Erro ao atualizar item." : "Erro ao adicionar item."));
    } finally {
      setInlineBusy(false);
    }
  }, [canWrite, cancelInlineEdit, cfgDescontoMax, empresaId, form, inlineDesconto, inlineEditingItemId, inlineItem, inlineItemId, inlineQuantidade, inlineValorUnitario, orc, readOnly, reload, supabase, tenantId]);

  const startInlineEdit = useCallback(
    (it: OrcamentoItemRow) => {
      if (readOnly || !canWrite) return;
      setInlineEditingItemId(it.id);
      setInlineItemId(String(it.item_id));
      setInlineQuantidade(String(it.quantidade ?? "1"));
      setInlineValorUnitario(String(it.valor_unitario ?? "0"));
      setInlineDesconto(String(it.desconto_item_percent ?? "0"));
      setInlineErr(null);

      // Move focus to the inline form.
      setTimeout(() => {
        inlineFormRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
      }, 0);
    },
    [canWrite, readOnly]
  );

  const doDeleteItem = useCallback(
    async (it: OrcamentoItemRow) => {
      if (!supabase || !tenantId || !empresaId) return;
      if (readOnly || !canWrite) return;

      const ok = await confirm({
        title: `Excluir item ${it.item_nome}?`,
        description: "Exclusão é arquivamento (soft delete).",
        confirmText: "Excluir",
        destructive: true,
      });
      if (!ok) return;

      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        await deleteItem(supabase, { tenantId, empresaId, id: it.id });
        setOk("Item excluído.");
        await reload();
      } catch (e: unknown) {
        setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao excluir item."));
      } finally {
        setBusy(false);
      }
    },
    [canWrite, confirm, empresaId, readOnly, reload, supabase, tenantId]
  );

  if (!ready && permissionsLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissões...</div>;
  }

  if (!canView) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;
  }

  return (
    <div className="space-y-4">
      {showLookup && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 overflow-y-auto">
          <div className="min-h-full w-full flex items-start justify-center p-4 md:items-center">
            <div className="w-full max-w-7xl bg-zinc-950 border border-zinc-800 rounded-xl p-5 shadow-xl flex flex-col gap-4 max-h-[90dvh] h-[90dvh] min-h-0 overflow-hidden">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <div className="text-lg font-semibold">Localizar {lookupBuscarConjuntos ? "conjunto" : "item"}</div>
                  <div className="text-sm text-zinc-400">
                    {lookupBuscarConjuntos
                      ? "Busque conjuntos (kits) para inserir no orçamento."
                      : "Filtre por nome ou fabricante para localizar o ID."}
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setShowLookup(false)}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                >
                  Fechar
                </button>
              </div>

              <label className="flex items-center gap-2 text-sm text-zinc-200">
                <input
                  type="checkbox"
                  checked={lookupBuscarConjuntos}
                  onChange={(e) => {
                    const next = e.target.checked;
                    setLookupBuscarConjuntos(next);
                    setLookupErr(null);
                    setLookupRows([]);
                    setLookupConjuntoRows([]);
                    void handleLookupSearch(lookupNome, lookupFornecedor);
                  }}
                />
                Buscar Conjuntos
              </label>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">{lookupBuscarConjuntos ? "Código/Nome" : "Nome"}</div>
                  <input
                    className="w-full px-3 py-2"
                    value={lookupNome}
                    onChange={(e) => setLookupNome(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        void handleLookupSearch(e.currentTarget.value, lookupFornecedor);
                      }
                    }}
                    aria-label={lookupBuscarConjuntos ? "Buscar conjunto" : "Buscar item por nome"}
                    title={lookupBuscarConjuntos ? "Buscar conjunto" : "Buscar item por nome"}
                  />
                </div>

                {!lookupBuscarConjuntos && (
                  <div className="space-y-1">
                    <div className="text-xs text-zinc-400">Fornecedor</div>
                    <input
                      className="w-full px-3 py-2"
                      value={lookupFornecedor}
                      onChange={(e) => setLookupFornecedor(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") {
                          e.preventDefault();
                          void handleLookupSearch(lookupNome, e.currentTarget.value);
                        }
                      }}
                      aria-label="Buscar item por fornecedor"
                      title="Buscar item por fornecedor"
                    />
                  </div>
                )}
              </div>

              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => void handleLookupSearch()}
                  disabled={lookupBusy}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
                >
                  {lookupBusy ? "Buscando..." : "Buscar"}
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setLookupNome("");
                    setLookupFornecedor("");
                    setLookupRows([]);
                    setLookupConjuntoRows([]);
                    setLookupErr(null);
                    void handleLookupSearch("", "");
                  }}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                >
                  Limpar
                </button>
              </div>

              {lookupErr && <div className="text-sm text-red-400">{lookupErr}</div>}

              <div className="border border-zinc-800 rounded-xl bg-zinc-950 flex-1 min-h-0 overflow-y-auto overflow-x-hidden overscroll-contain">
                {!lookupBuscarConjuntos ? (
                  <table className="w-full text-sm table-fixed">
                    <colgroup>
                      <col className="w-16" />
                      <col className="w-40" />
                      <col className="w-[40%]" />
                      <col className="w-[28%]" />
                      <col className="w-32" />
                      <col className="w-28" />
                      <col className="w-20" />
                    </colgroup>
                    <thead className="bg-zinc-900/70 sticky top-0 z-10">
                      <tr className="text-left text-zinc-200">
                        <th className="px-4 py-3 cursor-pointer whitespace-nowrap" onClick={() => handleSort("id")}>
                          ID {sortKey === "id" && (sortDir === "asc" ? "▲" : "▼")}
                        </th>
                        <th className="px-4 py-3 cursor-pointer whitespace-nowrap" onClick={() => handleSort("codigo")}>
                          Codigo {sortKey === "codigo" && (sortDir === "asc" ? "▲" : "▼")}
                        </th>
                        <th className="px-4 py-3 cursor-pointer" onClick={() => handleSort("descricao")}>
                          Descricao {sortKey === "descricao" && (sortDir === "asc" ? "▲" : "▼")}
                        </th>
                        <th className="px-4 py-3 cursor-pointer" onClick={() => handleSort("fornecedor")}>
                          Fornecedor {sortKey === "fornecedor" && (sortDir === "asc" ? "▲" : "▼")}
                        </th>
                        <th className="px-4 py-3 cursor-pointer whitespace-nowrap" onClick={() => handleSort("ultima")}>
                          Ultima entrada {sortKey === "ultima" && (sortDir === "asc" ? "▲" : "▼")}
                        </th>
                        <th className="px-4 py-3 text-right cursor-pointer whitespace-nowrap" onClick={() => handleSort("preco")}>
                          Preco {sortKey === "preco" && (sortDir === "asc" ? "▲" : "▼")}
                        </th>
                        <th className="px-4 py-3 text-right cursor-pointer whitespace-nowrap" onClick={() => handleSort("estoque")}>
                          Saldo {sortKey === "estoque" && (sortDir === "asc" ? "▲" : "▼")}
                        </th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-zinc-800">
                      {sortedLookupRows.map((it) => (
                        <tr
                          key={it.id}
                          className="hover:bg-zinc-900/40 cursor-pointer"
                          onClick={() => {
                            setInlineItemId(String(it.id));
                            setShowLookup(false);
                          }}
                        >
                          <td className="px-4 py-3 tabular-nums whitespace-nowrap">{it.id}</td>
                          <td className="px-4 py-3 whitespace-nowrap">{it.codigo_interno}</td>
                          <td className="px-4 py-3 whitespace-normal break-words">{it.nome}</td>
                          <td className="px-4 py-3 text-zinc-300 whitespace-normal break-words">{it.fornecedor ?? "—"}</td>
                          <td className="px-4 py-3 text-zinc-300">
                            {it.ultima_entrada ? new Date(it.ultima_entrada).toLocaleDateString("pt-BR") : "—"}
                          </td>
                          <td className="px-4 py-3 text-right tabular-nums">R$ {formatMoneyBR(Number(it.preco_unitario ?? 0))}</td>
                          <td className="px-4 py-3 text-right tabular-nums">
                            {typeof it.estoque_atual === "number" ? formatDecimalBR(Number(it.estoque_atual), 3) : "—"}
                          </td>
                        </tr>
                      ))}

                      {lookupRows.length === 0 && (
                        <tr>
                          <td colSpan={7} className="px-4 py-6 text-zinc-400 text-center">
                            Nenhum resultado ainda. Informe filtros e busque.
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                ) : (
                  <table className="w-full text-sm table-fixed">
                    <colgroup>
                      <col className="w-56" />
                      <col className="w-[55%]" />
                      <col className="w-40" />
                    </colgroup>
                    <thead className="bg-zinc-900/70 sticky top-0 z-10">
                      <tr className="text-left text-zinc-200">
                        <th className="px-4 py-3 whitespace-nowrap">Código</th>
                        <th className="px-4 py-3">Nome</th>
                        <th className="px-4 py-3 text-right whitespace-nowrap">Preço sugerido</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-zinc-800">
                      {lookupConjuntoRows.map((c) => (
                        <tr
                          key={c.conjunto_id}
                          className="hover:bg-zinc-900/40 cursor-pointer"
                          onClick={() => setAddConjunto({ open: true, conjunto: c, quantidade: "1", busy: false, error: null })}
                        >
                          <td className="px-4 py-3 whitespace-nowrap">{c.codigo ?? "—"}</td>
                          <td className="px-4 py-3 whitespace-normal break-words">{c.nome ?? "—"}</td>
                          <td className="px-4 py-3 text-right tabular-nums whitespace-nowrap">R$ {formatMoneyBR(Number(c.preco_sugerido ?? 0))}</td>
                        </tr>
                      ))}

                      {lookupConjuntoRows.length === 0 && (
                        <tr>
                          <td colSpan={3} className="px-4 py-6 text-zinc-400 text-center">
                            Nenhum resultado ainda. Informe filtros e busque.
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                )}
              </div>

              {addConjunto.open && (
                <div
                  className="fixed inset-0 z-[60] bg-black/70 backdrop-blur-sm flex items-start justify-center p-4 md:items-center"
                  onClick={(e) => e.target === e.currentTarget && setAddConjunto({ open: false })}
                  role="presentation"
                >
                  <div
                    role="dialog"
                    aria-modal="true"
                    aria-label="Quantidade do conjunto"
                    className="w-full max-w-lg bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
                    onClick={(e) => e.stopPropagation()}
                  >
                    <div className="px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
                      <div className="font-semibold text-zinc-100">Adicionar conjunto</div>
                      <div className="text-xs text-zinc-400 mt-1">
                        {addConjunto.conjunto.codigo ?? ""} {addConjunto.conjunto.nome ? `— ${addConjunto.conjunto.nome}` : ""}
                      </div>
                    </div>
                    <div className="px-5 py-4 space-y-3">
                      <label className="block text-xs text-zinc-400">
                        Quantidade
                        <input
                          value={addConjunto.quantidade}
                          onChange={(e) => setAddConjunto((p) => (p.open ? { ...p, quantidade: e.target.value, error: null } : p))}
                          className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                        />
                      </label>
                      {addConjunto.error && <div className="text-sm text-red-400">{addConjunto.error}</div>}
                      <div className="flex items-center justify-end gap-2">
                        <button
                          type="button"
                          onClick={() => setAddConjunto({ open: false })}
                          className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
                          disabled={addConjunto.busy}
                        >
                          Cancelar
                        </button>
                        <button
                          type="button"
                          onClick={() => void handleAddConjuntoConfirm()}
                          className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
                          disabled={addConjunto.busy}
                        >
                          {addConjunto.busy ? "Inserindo..." : "Inserir"}
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Orçamento</h1>
          <div className="text-sm text-zinc-400 mt-1 flex items-center gap-2 flex-wrap">
            <span>
              {orc?.codigo ? (
                <>
                  <span className="font-medium text-zinc-200">{orc.codigo}</span>
                  {orc?.versao ? <span className="text-zinc-500"> v{orc.versao}</span> : null}
                </>
              ) : (
                <span>Novo</span>
              )}
            </span>
            {orc?.status && (
              <span className={`px-2 py-0.5 rounded-full border text-xs ${statusBadgeClass(status)}`}>{status}</span>
            )}
            {orc?.emissao_date ? <span>Emissão: {formatDateBR(orc.emissao_date)}</span> : null}
          </div>
        </div>

        <div className="flex items-center gap-2 flex-wrap">
          <Link
            href="/comercial/orcamentos"
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Voltar
          </Link>
          {orc?.id && (
            <>
              <button
                type="button"
                onClick={() => void saveHeader()}
                disabled={readOnly || !canWrite || busy}
                className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium text-sm disabled:opacity-60"
              >
                Salvar
              </button>
              <button
                type="button"
                onClick={() => void reload()}
                className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
              >
                Recarregar
              </button>
              <button
                type="button"
                onClick={() => void doFinalizar()}
                disabled={!canWrite || readOnly || busy || status !== "RASCUNHO"}
                className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
              >
                Finalizar
              </button>
              <button
                type="button"
                onClick={() => void doCancelar()}
                disabled={!canWrite || readOnly || busy || status !== "RASCUNHO"}
                className="px-3 py-2 rounded-md border border-amber-500/30 bg-amber-500/10 hover:bg-amber-500/15 text-amber-200 text-sm disabled:opacity-60"
              >
                Cancelar
              </button>
            </>
          )}
        </div>
      </div>

      {err && <div className="text-sm text-red-400">{err}</div>}
      {ok && <div className="text-sm text-emerald-300">{ok}</div>}

      {loading && <div className="text-sm text-zinc-400">Carregando...</div>}

      {!loading && idParam !== "novo" && orc && form && (
        <form onSubmit={(e) => void saveHeader(e)} className="space-y-4">
          <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-3">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <label className="block text-xs text-zinc-400">
                Título
                <input
                  value={form.titulo}
                  disabled={readOnly || !canWrite}
                  onChange={(e) => setForm((p) => (p ? { ...p, titulo: e.target.value } : p))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                />
              </label>

              <label className="block text-xs text-zinc-400">
                Emissão
                <input
                  type="date"
                  value={form.emissao_date}
                  disabled={readOnly || !canWrite}
                  onChange={(e) => setForm((p) => (p ? { ...p, emissao_date: e.target.value } : p))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                />
              </label>

              <label className="block text-xs text-zinc-400">
                Vendedor
                <select
                  value={form.vendedor_usuario_id}
                  disabled={readOnly || !canWrite}
                  onChange={(e) => setForm((p) => (p ? { ...p, vendedor_usuario_id: e.target.value } : p))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                >
                  <option value="">Selecione</option>
                  {vendedores.map((v) => (
                    <option key={v.id} value={v.id}>
                      {v.nome ?? v.id}
                    </option>
                  ))}
                </select>
              </label>

              <label className="block text-xs text-zinc-400">
                Condição de Pagamento
                <select
                  value={form.condicao_pagamento_id ?? ""}
                  disabled={readOnly || !canWrite}
                  onChange={(e) =>
                    setForm((p) => (p ? { ...p, condicao_pagamento_id: e.target.value ? e.target.value : null } : p))
                  }
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                >
                  <option value="">(Sem condição)</option>
                  {condicoes.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.nome ?? c.id}
                    </option>
                  ))}
                </select>
              </label>

              <label className="block text-xs text-zinc-400">
                Desconto global (%)
                <input
                  value={form.desconto_global_percent}
                  disabled={readOnly || !canWrite}
                  onChange={(e) => setForm((p) => (p ? { ...p, desconto_global_percent: e.target.value } : p))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  placeholder={cfgDescontoMax ? `Máx. ${cfgDescontoMax}%` : undefined}
                />
              </label>

              <label className="block text-xs text-zinc-400">
                Frete (R$)
                <input
                  value={form.valor_frete}
                  disabled={readOnly || !canWrite}
                  onChange={(e) => setForm((p) => (p ? { ...p, valor_frete: e.target.value } : p))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                />
              </label>
            </div>

            {readOnly && <div className="text-xs text-zinc-500">Edição bloqueada (status {status}).</div>}
          </div>

          <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
            <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between gap-2">
              <div className="font-medium">Itens</div>
            </div>

            <div ref={inlineFormRef} className="p-4 border-b border-zinc-800">
              {inlineErr && <div className="text-sm text-red-400 mb-3">{inlineErr}</div>}
              <div className="grid grid-cols-1 md:grid-cols-7 gap-3 items-end">
                <label className="block text-xs text-zinc-400">
                  Codigo
                  <input
                    value={inlineItemId}
                    disabled={readOnly || !canWrite || inlineBusy || inlineMode === "edit"}
                    onChange={(e) => setInlineItemId(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        void handleCodigoEnter(e.currentTarget.value);
                      }
                    }}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                    placeholder="Ex.: 109"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Quantidade
                  <input
                    value={inlineQuantidade}
                    disabled={readOnly || !canWrite || inlineBusy}
                    onChange={(e) => setInlineQuantidade(e.target.value)}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Valor unitario
                  <input
                    value={inlineValorUnitario}
                    disabled={readOnly || !canWrite || inlineBusy}
                    onChange={(e) => setInlineValorUnitario(e.target.value)}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Desconto
                  <input
                    value={inlineDesconto}
                    disabled={readOnly || !canWrite || inlineBusy}
                    onChange={(e) => setInlineDesconto(e.target.value)}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Estoque
                  <input
                    value={inlineItem?.id ? formatDecimalBR(inlineEstoqueAtual ?? 0) : "-"}
                    disabled
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Total
                  <input
                    value={formatMoneyBR(inlineTotal)}
                    disabled
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Valor Ultima compra
                  <input
                    value={inlineItem?.id ? formatMoneyBR(n(inlineItem.custo_ultima_compra)) : "-"}
                    disabled
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>
              </div>

              <div className="mt-3 grid grid-cols-1 md:grid-cols-6 gap-3">
                <label className="block text-xs text-zinc-400 md:col-span-2">
                  Fornecedor
                  <input
                    value={inlineItem?.id ? (inlineItem.fornecedores?.nome ?? "-") : "-"}
                    disabled
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>

                <label className="block text-xs text-zinc-400 md:col-span-4">
                  Item
                  <input
                    value={inlineItem?.id ? (inlineItem.descricao ?? inlineItem.nome ?? "") : ""}
                    disabled
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>
              </div>

              <div className="mt-3 flex items-center justify-end gap-2">
                {inlineMode === "edit" && (
                  <button
                    type="button"
                    onClick={cancelInlineEdit}
                    disabled={inlineBusy}
                    className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
                  >
                    Cancelar
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => void submitInlineItem()}
                  disabled={readOnly || !canWrite || inlineBusy}
                  className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
                >
                  {inlineMode === "edit" ? "Salvar" : "Adicionar"}
                </button>
              </div>
            </div>

            <div className="overflow-auto">
              <table className="w-full text-sm">
                <thead className="bg-zinc-900/70">
                  <tr className="text-zinc-200">
                    <th className="px-3 py-3 text-left whitespace-nowrap">Seq</th>
                    <th className="px-3 py-3 text-left whitespace-nowrap">ID</th>
                    <th className="px-3 py-3 text-left whitespace-nowrap">Codigo</th>
                    <th className="px-3 py-3 text-left whitespace-nowrap">Item</th>
                    <th className="px-3 py-3 text-left whitespace-nowrap">Unid</th>
                    <th className="px-3 py-3 text-right whitespace-nowrap">Qtd</th>
                    <th className="px-3 py-3 text-right whitespace-nowrap">Vlr Unit</th>
                    <th className="px-3 py-3 text-right whitespace-nowrap">Desc (%)</th>
                    <th className="px-3 py-3 text-right whitespace-nowrap">Total</th>
                    <th className="px-3 py-3 text-right whitespace-nowrap">Estoque</th>
                    <th className="px-3 py-3 text-right whitespace-nowrap">Ações</th>
                  </tr>
                </thead>
                <tbody>
                  {itens.length === 0 && (
                    <tr>
                      <td colSpan={11} className="px-3 py-6 text-zinc-400">
                        Nenhum item.
                      </td>
                    </tr>
                  )}
                  {itens.map((it) => (
                    <tr
                      key={it.id}
                      onClick={() => {
                        if (readOnly || !canWrite) return;
                        startInlineEdit(it);
                      }}
                      className={
                        "border-t border-zinc-900/60 hover:bg-zinc-900/30" + (readOnly || !canWrite ? "" : " cursor-pointer")
                      }
                    >
                      <td className="px-3 py-2 whitespace-nowrap">{it.seq}</td>
                      <td className="px-3 py-2 whitespace-nowrap">{it.item_id}</td>
                      <td className="px-3 py-2 whitespace-nowrap">{it.item_codigo_interno ?? "—"}</td>
                      <td className="px-3 py-2 min-w-[280px]">{it.item_nome}</td>
                      <td className="px-3 py-2 whitespace-nowrap">{it.unidade}</td>
                      <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{n(it.quantidade)}</td>
                      <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{formatMoneyBR(n(it.valor_unitario))}</td>
                      <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{n(it.desconto_item_percent)}</td>
                      <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{formatMoneyBR(n(it.valor_total))}</td>
                      <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">
                        {Number.isFinite(estoqueByItemId[Number(it.item_id)])
                          ? formatDecimalBR(estoqueByItemId[Number(it.item_id)])
                          : "—"}
                      </td>
                      <td className="px-3 py-2 text-right whitespace-nowrap">
                        <div className="inline-flex items-center gap-2">
                          <button
                            type="button"
                            onClick={(e) => {
                              e.stopPropagation();
                              void doDeleteItem(it);
                            }}
                            disabled={readOnly || !canWrite}
                            className="px-3 py-1.5 rounded-md border border-red-900/60 bg-red-950/40 hover:bg-red-950/70 text-red-200 disabled:opacity-60"
                          >
                            Excluir
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
              <div className="flex items-center justify-between gap-2">
                <span className="text-zinc-400">Total produtos</span>
                <span className="tabular-nums">{formatMoneyBR(n(orc.total_produtos))}</span>
              </div>
              <div className="flex items-center justify-between gap-2">
                <span className="text-zinc-400">Total serviços</span>
                <span className="tabular-nums">{formatMoneyBR(n(orc.total_servicos))}</span>
              </div>
              <div className="flex items-center justify-between gap-2">
                <span className="text-zinc-400">Total bruto</span>
                <span className="tabular-nums">{formatMoneyBR(n(orc.total_bruto))}</span>
              </div>
              <div className="flex items-center justify-between gap-2">
                <span className="text-zinc-400">Desconto global</span>
                <span className="tabular-nums">{formatMoneyBR(n(orc.total_desconto_global))}</span>
              </div>
              <div className="flex items-center justify-between gap-2">
                <span className="text-zinc-400">Frete</span>
                <span className="tabular-nums">{formatMoneyBR(n(orc.valor_frete))}</span>
              </div>
              <div className="flex items-center justify-between gap-2">
                <span className="text-zinc-400 font-medium">Total líquido</span>
                <span className="tabular-nums font-semibold">{formatMoneyBR(n(orc.total_liquido))}</span>
              </div>
            </div>
          </div>

          <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
            <label className="block text-xs text-zinc-400">
              Observações
              <textarea
                value={form.observacoes}
                disabled={readOnly || !canWrite}
                onChange={(e) => setForm((p) => (p ? { ...p, observacoes: e.target.value } : p))}
                className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm min-h-24 disabled:opacity-60"
              />
            </label>
          </div>
        </form>
      )}

      {newDialog.open && (
        <div
          className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeNewDialog()}
          role="presentation"
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-label="Novo orçamento"
            className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div className="font-semibold text-zinc-100">Novo orçamento</div>
              <div className="text-xs text-zinc-400 mt-1">Informe cliente e título para criar o rascunho.</div>
            </div>

            <div className="p-5 space-y-4">
              {newDialog.error && <div className="text-sm text-red-400">{newDialog.error}</div>}

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <label className="block text-xs text-zinc-400 md:col-span-2">
                  Cliente (busca)
                  <input
                    value={newDialog.clienteTerm}
                    onChange={(e) => setNewDialog((p) => (p.open ? { ...p, clienteTerm: e.target.value } : p))}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="Digite nome ou ID..."
                  />
                </label>

                <div className="md:col-span-2">
                  <div className="text-xs text-zinc-400 mb-1">Resultados</div>
                  <div className="max-h-48 overflow-auto border border-zinc-800 rounded-md">
                    {newDialog.clienteResults.length === 0 ? (
                      <div className="px-3 py-3 text-sm text-zinc-500">Sem resultados.</div>
                    ) : (
                      newDialog.clienteResults.map((c) => (
                        <button
                          type="button"
                          key={c.id}
                          onClick={() =>
                            setNewDialog((p) => (p.open ? { ...p, clienteId: c.id, clienteTerm: c.nome ?? String(c.id) } : p))
                          }
                          className={
                            newDialog.clienteId === c.id
                              ? "w-full text-left px-3 py-2 text-sm bg-zinc-900/60"
                              : "w-full text-left px-3 py-2 text-sm hover:bg-zinc-900/40"
                          }
                        >
                          <span className="text-zinc-200">{c.nome ?? `#${c.id}`}</span>
                          <span className="text-zinc-500"> — #{c.id}</span>
                        </button>
                      ))
                    )}
                  </div>
                </div>

                <label className="block text-xs text-zinc-400 md:col-span-2">
                  Título
                  <input
                    value={newDialog.titulo}
                    onChange={(e) => setNewDialog((p) => (p.open ? { ...p, titulo: e.target.value } : p))}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="Ex.: Proposta de manutenção"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Vendedor
                  <select
                    value={newDialog.vendedorUsuarioId}
                    onChange={(e) => setNewDialog((p) => (p.open ? { ...p, vendedorUsuarioId: e.target.value } : p))}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                  >
                    <option value="">Selecione</option>
                    {vendedores.map((v) => (
                      <option key={v.id} value={v.id}>
                        {v.nome ?? v.id}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="block text-xs text-zinc-400">
                  Condição de Pagamento
                  <select
                    value={newDialog.condicaoPagamentoId ?? ""}
                    onChange={(e) =>
                      setNewDialog((p) => (p.open ? { ...p, condicaoPagamentoId: e.target.value ? e.target.value : null } : p))
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                  >
                    <option value="">(Sem condição)</option>
                    {condicoes.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.nome ?? c.id}
                      </option>
                    ))}
                  </select>
                </label>
              </div>
            </div>

            <div className="px-5 py-4 border-t border-zinc-900/80 flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={closeNewDialog}
                disabled={newDialog.busy}
                className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60"
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={() => void submitNew()}
                disabled={newDialog.busy}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
              >
                Criar
              </button>
            </div>
          </div>
        </div>
      )}

      {itemDialog.open && (
        <div
          className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeItemDialog()}
          role="presentation"
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-label="Editar item"
            className="w-full max-w-3xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div className="font-semibold text-zinc-100">Editar item</div>
              <div className="text-xs text-zinc-400 mt-1">{itemDialog.itemNome}</div>
            </div>

            <div className="p-5 space-y-4">
              {itemDialog.error && <div className="text-sm text-red-400">{itemDialog.error}</div>}

              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                <label className="block text-xs text-zinc-400">
                  Quantidade
                  <input
                    value={itemDialog.quantidade}
                    onChange={(e) => setItemDialog((p) => (p.open ? { ...p, quantidade: e.target.value } : p))}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  />
                </label>
                <label className="block text-xs text-zinc-400">
                  Valor unitário (R$)
                  <input
                    value={itemDialog.valorUnitario}
                    onChange={(e) => setItemDialog((p) => (p.open ? { ...p, valorUnitario: e.target.value } : p))}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  />
                </label>
                <label className="block text-xs text-zinc-400">
                  Desconto item (%)
                  <input
                    value={itemDialog.descontoItemPercent}
                    onChange={(e) => setItemDialog((p) => (p.open ? { ...p, descontoItemPercent: e.target.value } : p))}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                  />
                </label>
              </div>
            </div>

            <div className="px-5 py-4 border-t border-zinc-900/80 flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={closeItemDialog}
                disabled={itemDialog.busy}
                className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60"
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={() => void submitItem()}
                disabled={itemDialog.busy}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
              >
                Salvar
              </button>
            </div>
          </div>
        </div>
      )}

      {confirmDialog}
    </div>
  );
}
