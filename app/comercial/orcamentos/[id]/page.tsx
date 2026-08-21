"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { useParams, useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import { formatDecimalBR, formatMoneyBR, parseDecimalBR } from "@/lib/decimal";
import type {
  ClienteContatoLookupRow,
  ClienteLookupRow,
  OrcamentoItemRow,
  OrcamentoRow,
  OrcamentoStatus,
  UsuarioLookupRow,
} from "@/lib/comercial/types";
import { getOrcamentoStatusLabel, normalizeOrcamentoStatus, type OrcamentoStatusCanonical } from "@/lib/comercial/status";
import { getSuggestedOrcamentoUnitPrice, isOrcamentoReadOnly, mapOrcamentoError, n, toSupabaseErrorLike, upperTrim } from "@/lib/comercial/utils";
import {
  addItem,
  atualizarStatusOrcamento,
  createOrcamento,
  getClienteById,
  getItemByCodigo,
  getItemById,
  getOrcamento,
  getOrcamentoConfig,
  getUsuarioIdByAuthUserId,
  listCondicoesPagamentoAtivas,
  listarContatosClienteParaOrcamento,
  salvarContatoClienteDoOrcamento,
  searchClientes,
  sincronizarOrcamentoComDriveViaAppsScript,
  updateItem,
  updateOrcamento,
} from "@/lib/comercial/orcamentos.service";
import OrcamentoStatusDialog, { type OrcamentoStatusDialogPayload } from "../OrcamentoStatusDialog";
import AssistenteIAModal from "./AssistenteIAModal";

import type { ItemByIdRow } from "@/lib/comercial/orcamentos.service";

type ItemLookupBaseRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  fabricante: string | null;
  preco_unitario: number | null;
  custo_ultima_compra: number | null;
  fornecedor: string | null;
  ultima_entrada: string | null;
  estoque_atual: number | null;
};

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

type ConjuntoInsertMode = "EXPANDIR_ITENS" | "ITEM_UNICO";

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

type LookupSearchTerm = {
  raw: string;
  normalized: string;
};

const LOOKUP_FETCH_LIMIT = 150;
const LOOKUP_RESULT_LIMIT = 50;

function hasAny(caps: Capabilities | null, keys: CapabilityKey[]): boolean {
  return requireAny(caps, keys);
}

function normalizeLookupText(value: string | null | undefined): string {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
}

function parseLookupTerms(value: string | null | undefined): LookupSearchTerm[] {
  return String(value ?? "")
    .trim()
    .split(/\s+/)
    .map((raw) => raw.trim())
    .filter(Boolean)
    .map((raw) => ({
      raw,
      normalized: normalizeLookupText(raw),
    }))
    .filter((term) => term.normalized.length > 0);
}

function pickLookupSeedTerm(terms: LookupSearchTerm[]): string {
  return [...terms].sort((a, b) => b.normalized.length - a.normalized.length)[0]?.raw ?? "";
}

function matchesLookupTerms(values: Array<string | null | undefined>, terms: LookupSearchTerm[]): boolean {
  if (terms.length === 0) return true;
  const haystack = values.map((value) => normalizeLookupText(value)).join(" ");
  return terms.every((term) => haystack.includes(term.normalized));
}

type VendedoresApiResponse = {
  vendedores?: Array<{ id?: string | null; nome?: string | null; email?: string | null }>;
  error?: string;
};

async function fetchVendedores(
  supabase: ReturnType<typeof supabaseBrowser>,
  tenantId: string,
  empresaId: string
): Promise<UsuarioLookupRow[]> {
  const { data: sess } = await supabase.auth.getSession();
  const token = sess.session?.access_token ?? null;
  if (!token) throw new Error("Sessao expirada. Faca login novamente.");

  const res = await fetch(`/api/comercial/vendedores?tenantId=${tenantId}&empresaId=${empresaId}`, {
    headers: { authorization: `Bearer ${token}` },
  });

  const json = (await res.json().catch(() => null)) as VendedoresApiResponse | null;
  if (!res.ok) {
    throw new Error(typeof json?.error === "string" ? json.error : "Erro ao carregar vendedores.");
  }

  return (Array.isArray(json?.vendedores) ? json.vendedores : [])
    .map((row) => {
      const id = String(row?.id ?? "").trim();
      const nome = String(row?.nome ?? "").trim();
      const email = String(row?.email ?? "").trim();
      return {
        id,
        nome: nome || email || null,
      } satisfies UsuarioLookupRow;
    })
    .filter((row) => row.id && row.nome);
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

function truncateText(value: string, max = 90): string {
  if (value.length <= max) return value;
  return `${value.slice(0, max - 1)}...`;
}

function formatConjuntoSingleLineDescription(conjunto: ConjuntoCatalogoRow): string {
  const codigo = upperTrim(String(conjunto.codigo ?? ""));
  const nome = upperTrim(String(conjunto.nome ?? ""));
  const details = [codigo, nome].filter(Boolean).join(" - ");
  return details ? `CONJUNTO ${details}` : "CONJUNTO";
}

function formatClienteDocumento(value: string | null | undefined): string {
  const raw = String(value ?? "").trim();
  const digits = raw.replace(/\D/g, "");

  if (digits.length === 14) {
    return digits.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5");
  }
  if (digits.length === 11) {
    return digits.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, "$1.$2.$3-$4");
  }

  return raw || "Não informado";
}

function contatoField(value: string | null | undefined): string {
  return String(value ?? "").trim();
}

function uppercaseContatoField(value: string | null | undefined): string {
  return contatoField(value).toLocaleUpperCase("pt-BR");
}

function lowercaseEmailField(value: string | null | undefined): string {
  return contatoField(value).toLocaleLowerCase("pt-BR");
}

function onlyDigits(value: string | null | undefined): string {
  return String(value ?? "").replace(/\D/g, "");
}

function formatPhoneInput(value: string | null | undefined): string {
  const digits = onlyDigits(value).slice(0, 11);
  if (!digits) return "";
  if (digits.length <= 2) return `(${digits}`;
  if (digits.length <= 6) return `(${digits.slice(0, 2)}) ${digits.slice(2)}`;
  if (digits.length <= 10) return `(${digits.slice(0, 2)}) ${digits.slice(2, 6)}-${digits.slice(6)}`;
  return `(${digits.slice(0, 2)}) ${digits.slice(2, 7)}-${digits.slice(7)}`;
}

function formatContatoSuggestion(contato: ClienteContatoLookupRow): string {
  return [contato.email, contato.nome, contato.setor, contato.telefone].map(contatoField).filter(Boolean).join(" - ");
}

function statusBadgeClass(status: string): string {
  const s = normalizeOrcamentoStatus(status);
  if (s === "ANDAMENTO") return "bg-blue-500/15 text-blue-300 border-blue-500/30";
  if (s === "FECHADO") return "bg-emerald-500/15 text-emerald-300 border-emerald-500/30";
  if (s === "PERDIDO") return "bg-red-500/15 text-red-300 border-red-500/30";
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
      clienteResults: ClienteLookupRow[];
      clienteLoading: boolean;
      clienteSearchError: string | null;
      clienteId: number | null;
      contatoResults: ClienteContatoLookupRow[];
      contatoLoading: boolean;
      titulo: string;
      vendedorUsuarioId: string;
      condicaoPagamentoId: string | null;
      solicitanteNome: string;
      solicitanteSetor: string;
      solicitanteEmail: string;
      solicitanteTelefone: string;
    };

function closedNewDialog(): NewDialogState {
  return { open: false };
}

type EditClienteDialogState =
  | { open: false }
  | {
      open: true;
      busy: boolean;
      error: string | null;
      clienteTerm: string;
      clienteResults: ClienteLookupRow[];
      clienteLoading: boolean;
      clienteSearchError: string | null;
      clienteId: number | null;
      contatoResults: ClienteContatoLookupRow[];
      contatoLoading: boolean;
      titulo: string;
      vendedorUsuarioId: string;
      condicaoPagamentoId: string | null;
      solicitanteNome: string;
      solicitanteSetor: string;
      solicitanteEmail: string;
      solicitanteTelefone: string;
    };

function closedEditClienteDialog(): EditClienteDialogState {
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
  const canOpenOs = hasAny(capabilities, ["os.write"]);

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const [orc, setOrc] = useState<OrcamentoRow | null>(null);
  const [itens, setItens] = useState<OrcamentoItemRow[]>([]);
  const [form, setForm] = useState<OrcamentoForm | null>(null);
  const [clienteNome, setClienteNome] = useState<string | null>(null);

  const [cfgDescontoMax, setCfgDescontoMax] = useState<number>(0);
  const [cfgCondPadraoId, setCfgCondPadraoId] = useState<string | null>(null);
  const [cfgMargemLucroPadraoPercent, setCfgMargemLucroPadraoPercent] = useState<number>(0);
  const [condicoes, setCondicoes] = useState<Array<{ id: string; nome: string | null; acrescimo_percent: number | string | null }>>([]);
  const [vendedores, setVendedores] = useState<UsuarioLookupRow[]>([]);

  const [newDialog, setNewDialog] = useState<NewDialogState>(closedNewDialog);
  const newClienteReqRef = useRef(0);
  const driveSyncAttemptedRef = useRef<Set<string>>(new Set());
  const newDialogClienteTerm = newDialog.open ? newDialog.clienteTerm : "";
  const newDialogClienteId = newDialog.open ? newDialog.clienteId : null;

  const [editClienteDialog, setEditClienteDialog] = useState<EditClienteDialogState>(closedEditClienteDialog);
  const editClienteReqRef = useRef(0);
  const editClienteDialogClienteTerm = editClienteDialog.open ? editClienteDialog.clienteTerm : "";
  const editClienteDialogClienteId = editClienteDialog.open ? editClienteDialog.clienteId : null;

  const [itemDialog, setItemDialog] = useState<ItemDialogState>(closedItemDialog);
  const [inlineItemId, setInlineItemId] = useState<string>("");
  const [inlineItem, setInlineItem] = useState<ItemByIdRow | null>(null);
  const [inlineQuantidade, setInlineQuantidade] = useState<string>("1");
  const [inlineValorUnitario, setInlineValorUnitario] = useState<string>("0");
  const [inlineDesconto, setInlineDesconto] = useState<string>("0");
  const [inlineDescricaoLivre, setInlineDescricaoLivre] = useState<string>("");
  const [inlineBusy, setInlineBusy] = useState<boolean>(false);
  const [inlineErr, setInlineErr] = useState<string | null>(null);
  const [inlineEditingItemId, setInlineEditingItemId] = useState<string | null>(null);
  const [inlineEstoqueAtual, setInlineEstoqueAtual] = useState<number | null>(null);
  const inlineMode = inlineEditingItemId ? "edit" : "add";
  const inlineIsCodigoGenerico = useMemo(
    () => String(inlineItem?.codigo_interno ?? "").trim().toUpperCase() === "9999",
    [inlineItem?.codigo_interno]
  );
  const inlineItemIsKg = useMemo(() => upperTrim(String(inlineItem?.unidade_medida ?? "")) === "KG", [inlineItem?.unidade_medida]);
  const inlineItemPesoReferencia = useMemo(() => {
    if (!inlineItemIsKg) return null;
    const peso = n(inlineItem?.peso_liquido);
    return Number.isFinite(peso) && peso > 0 ? peso : null;
  }, [inlineItemIsKg, inlineItem?.peso_liquido]);
  const isInlineTokenGenerico = useCallback((value: string) => /^[#@$]/.test(String(value ?? "").trim()), []);
  const inlineFormRef = useRef<HTMLDivElement | null>(null);
  const inlineCodigoInputRef = useRef<HTMLInputElement | null>(null);
  const inlineQuantidadeInputRef = useRef<HTMLInputElement | null>(null);
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
  const [lookupMultiMode, setLookupMultiMode] = useState(false);
  const [lookupSelecionados, setLookupSelecionados] = useState<Map<number, string>>(new Map());
  const [lookupBulkBusy, setLookupBulkBusy] = useState(false);
  const [lookupBulkErr, setLookupBulkErr] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<SortKey>("id");
  const [sortDir, setSortDir] = useState<SortDir>("asc");

  const [addConjunto, setAddConjunto] = useState<
    | { open: false }
    | {
        open: true;
        conjunto: ConjuntoCatalogoRow;
        quantidade: string;
        modo: ConjuntoInsertMode;
        busy: boolean;
        error: string | null;
      }
  >({ open: false });
  const [statusDialog, setStatusDialog] = useState<{ open: false } | { open: true; status: OrcamentoStatusCanonical }>({
    open: false,
  });
  const [aiAssistantOpen, setAiAssistantOpen] = useState(false);

  const { confirm, dialog: confirmDialog } = useConfirmDialog();

  const statusRaw = String(orc?.status ?? "").toUpperCase() as OrcamentoStatus | string;
  const status = normalizeOrcamentoStatus(statusRaw);
  const statusLabel = getOrcamentoStatusLabel(statusRaw);
  const statusFollowup = String(orc?.observacoes ?? "").trim();
  const readOnly = isOrcamentoReadOnly(statusRaw);

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
        fetchVendedores(supabase, tenantId, empresaId),
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
      const computed = getSuggestedOrcamentoUnitPrice({
        custoUltimaCompra: item.custo_ultima_compra,
        precoUnitario: item.preco_unitario,
        margemLucroPadraoPercent: cfgMargemLucroPadraoPercent,
      });
      if (!Number.isFinite(computed) || computed < 0) return "0";
      return computed.toFixed(2);
    },
    [cfgMargemLucroPadraoPercent]
  );

  // Para itens vendidos por peso (KG, ex.: chapas), a quantidade nao e "1
  // unidade" — e o peso, em kg, da peca cadastrada. Sem isso, quem adiciona o
  // item no orcamento tende a deixar "1" e subprecificar a chapa inteira.
  const defaultQuantidadeFromItem = useCallback((item: ItemByIdRow | null): string => {
    if (!item?.id) return "1";
    const isKg = upperTrim(String(item.unidade_medida ?? "")) === "KG";
    const peso = isKg ? n(item.peso_liquido) : 0;
    return isKg && Number.isFinite(peso) && peso > 0 ? String(peso) : "1";
  }, []);

  const reload = useCallback(async () => {
    setErr(null);
    setOk(null);

    if (!supabase) return;
    if (te.loading || te.refreshing) return;

    if (!tenantId || !empresaId) {
      setLoading(false);
      setErr("Contexto (tenant/empresa) nao carregado.");
      setOrc(null);
      setItens([]);
      setForm(null);
      setClienteNome(null);
      return;
    }

    if (idParam === "novo") {
      setLoading(false);
      setOrc(null);
      setItens([]);
      setForm(null);
      setClienteNome(null);
      return;
    }

      setLoading(true);
    try {
      const { orcamento } = await getOrcamento(supabase, { tenantId, empresaId, idOrCodigo: idParam });

      const { data: itens, error: itensErr } = await supabase
        .schema("r")
        .from("r_orcamento_itens")
        .select("*")
        .eq("orcamento_id", orcamento.id)
        .order("seq", { ascending: true });

      if (itensErr) throw itensErr;

      setOrc(orcamento);

      // r.r_orcamento_itens pode não expor o código interno do item; fazemos um enrich via public.itens
      // para evitar "Codigo = -" no orçamento e no documento impresso.
      const itensRows = ((itens ?? []) as OrcamentoItemRow[]).map((it) => ({ ...it }));
      try {
        const itemIds = Array.from(
          new Set(
            itensRows
              .map((it) => Number(it.item_id))
              .filter((v) => Number.isFinite(v) && v > 0)
          )
        );
        if (itemIds.length > 0) {
          const { data: itensMeta, error: itensMetaErr } = await supabase
            .from("itens")
            .select("id,codigo_interno")
            .eq("tenant_id", tenantId)
            .eq("empresa_id", empresaId)
            .in("id", itemIds);
          if (!itensMetaErr && itensMeta) {
            const codigoById = new Map<number, string>();
            for (const row of itensMeta) {
              const id = Number((row as { id: unknown }).id);
              const codigo = String((row as { codigo_interno?: unknown }).codigo_interno ?? "").trim();
              if (Number.isFinite(id) && id > 0 && codigo) codigoById.set(id, codigo);
            }
            for (const it of itensRows) {
              const existing = String((it as { item_codigo_interno?: unknown }).item_codigo_interno ?? "").trim();
              if (existing) continue;
              const id = Number(it.item_id);
              const codigo = codigoById.get(id);
              if (codigo) (it as unknown as { item_codigo_interno?: string }).item_codigo_interno = codigo;
            }
          }
        }
      } catch {
        // best-effort: se falhar, mantém o comportamento atual.
      }

      setItens(itensRows);
      setForm(formFromRow(orcamento));

      try {
        const cli = orcamento?.cliente_id
          ? await getClienteById(supabase, { tenantId, empresaId, clienteId: orcamento.cliente_id })
          : null;
        setClienteNome(cli?.nome ?? null);
      } catch {
        setClienteNome(null);
      }

      // Prefer the human-friendly codigo in the URL.
      if (
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(idParam) &&
        orcamento?.codigo &&
        idParam !== orcamento.codigo
      ) {
        router.replace(`/comercial/orcamentos/${orcamento.codigo}`);
      }
    } catch (e: unknown) {
      setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao carregar orcamento."));
      setOrc(null);
      setItens([]);
      setForm(null);
      setClienteNome(null);
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

  useEffect(() => {
    if (!orc?.id || !supabase || !tenantId || !empresaId) return;
    if (!canWrite || readOnly) return;

    const hasDriveFolder = Boolean(String(orc.drive_folder_id ?? "").trim() || String(orc.drive_folder_url ?? "").trim());
    const driveStatus = String(orc.drive_sync_status ?? "").trim().toLowerCase();
    if (hasDriveFolder || driveStatus === "created" || driveStatus === "pending") return;

    if (driveSyncAttemptedRef.current.has(orc.id)) return;
    driveSyncAttemptedRef.current.add(orc.id);

    let active = true;
    void (async () => {
      await sincronizarOrcamentoComDriveViaAppsScript(supabase, { tenantId, empresaId, orcamentoId: orc.id });
      if (active) void reload();
    })();

    return () => {
      active = false;
    };
  }, [
    canWrite,
    empresaId,
    orc?.drive_folder_id,
    orc?.drive_folder_url,
    orc?.drive_sync_status,
    orc?.id,
    readOnly,
    reload,
    supabase,
    tenantId,
  ]);

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
        clienteLoading: false,
        clienteSearchError: null,
        clienteId: null,
        contatoResults: [],
        contatoLoading: false,
        titulo: "",
        vendedorUsuarioId: vendedorFromMe?.id ? String(vendedorFromMe.id) : "",
        condicaoPagamentoId: cfgCondPadraoId,
        solicitanteNome: "",
        solicitanteSetor: "",
        solicitanteEmail: "",
        solicitanteTelefone: "",
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

    const term = newDialogClienteTerm.trim();
    const reqId = ++newClienteReqRef.current;
    const t = setTimeout(async () => {
      try {
        if (!term) {
          if (reqId === newClienteReqRef.current) {
            setNewDialog((p) =>
              p.open ? { ...p, clienteResults: [], clienteLoading: false, clienteSearchError: null } : p
            );
          }
          return;
        }
        setNewDialog((p) =>
          p.open ? { ...p, clienteLoading: true, clienteSearchError: null } : p
        );
        const res = await searchClientes(supabase, { tenantId, empresaId, term });
        if (reqId === newClienteReqRef.current) {
          setNewDialog((p) =>
            p.open ? { ...p, clienteResults: res, clienteLoading: false, clienteSearchError: null } : p
          );
        }
      } catch {
        if (reqId === newClienteReqRef.current) {
          setNewDialog((p) =>
            p.open
              ? {
                  ...p,
                  clienteResults: [],
                  clienteLoading: false,
                  clienteSearchError: "Nao foi possivel buscar clientes. Tente novamente.",
                }
              : p
          );
        }
      }
    }, 250);

    return () => clearTimeout(t);
  }, [empresaId, newDialog.open, newDialogClienteTerm, supabase, tenantId]);

  // search contatos do cliente in new dialog
  useEffect(() => {
    if (!newDialog.open) return;

    const clienteId = newDialogClienteId;
    if (!supabase || !tenantId || !empresaId || !clienteId) {
      setNewDialog((p) => {
        if (!p.open || (p.contatoResults.length === 0 && !p.contatoLoading)) return p;
        return { ...p, contatoResults: [], contatoLoading: false };
      });
      return;
    }

    let active = true;

    setNewDialog((p) => (p.open && p.clienteId === clienteId ? { ...p, contatoResults: [], contatoLoading: true } : p));

    (async () => {
      try {
        const contatos = await listarContatosClienteParaOrcamento(supabase, { tenantId, empresaId, clienteId });
        if (!active) return;
        setNewDialog((p) => (p.open && p.clienteId === clienteId ? { ...p, contatoResults: contatos, contatoLoading: false } : p));
      } catch (error) {
        console.warn("Falha ao carregar contatos do cliente para orcamento.", error);
        if (!active) return;
        setNewDialog((p) => (p.open && p.clienteId === clienteId ? { ...p, contatoResults: [], contatoLoading: false } : p));
      }
    })();

    return () => {
      active = false;
    };
  }, [empresaId, newDialog.open, newDialogClienteId, supabase, tenantId]);

  // search clientes in edit-cliente dialog
  useEffect(() => {
    if (!editClienteDialog.open) return;
    if (!supabase || !tenantId || !empresaId) return;

    const term = editClienteDialogClienteTerm.trim();
    const reqId = ++editClienteReqRef.current;
    const t = setTimeout(async () => {
      try {
        if (!term) {
          if (reqId === editClienteReqRef.current) {
            setEditClienteDialog((p) =>
              p.open ? { ...p, clienteResults: [], clienteLoading: false, clienteSearchError: null } : p
            );
          }
          return;
        }
        setEditClienteDialog((p) =>
          p.open ? { ...p, clienteLoading: true, clienteSearchError: null } : p
        );
        const res = await searchClientes(supabase, { tenantId, empresaId, term });
        if (reqId === editClienteReqRef.current) {
          setEditClienteDialog((p) =>
            p.open ? { ...p, clienteResults: res, clienteLoading: false, clienteSearchError: null } : p
          );
        }
      } catch {
        if (reqId === editClienteReqRef.current) {
          setEditClienteDialog((p) =>
            p.open
              ? {
                  ...p,
                  clienteResults: [],
                  clienteLoading: false,
                  clienteSearchError: "Nao foi possivel buscar clientes. Tente novamente.",
                }
              : p
          );
        }
      }
    }, 250);

    return () => clearTimeout(t);
  }, [editClienteDialog.open, editClienteDialogClienteTerm, empresaId, supabase, tenantId]);

  // search contatos do cliente in edit-cliente dialog
  useEffect(() => {
    if (!editClienteDialog.open) return;

    const clienteId = editClienteDialogClienteId;
    if (!supabase || !tenantId || !empresaId || !clienteId) {
      setEditClienteDialog((p) => {
        if (!p.open || (p.contatoResults.length === 0 && !p.contatoLoading)) return p;
        return { ...p, contatoResults: [], contatoLoading: false };
      });
      return;
    }

    let active = true;

    setEditClienteDialog((p) => (p.open && p.clienteId === clienteId ? { ...p, contatoResults: [], contatoLoading: true } : p));

    (async () => {
      try {
        const contatos = await listarContatosClienteParaOrcamento(supabase, { tenantId, empresaId, clienteId });
        if (!active) return;
        setEditClienteDialog((p) => (p.open && p.clienteId === clienteId ? { ...p, contatoResults: contatos, contatoLoading: false } : p));
      } catch (error) {
        console.warn("Falha ao carregar contatos do cliente para orcamento.", error);
        if (!active) return;
        setEditClienteDialog((p) => (p.open && p.clienteId === clienteId ? { ...p, contatoResults: [], contatoLoading: false } : p));
      }
    })();

    return () => {
      active = false;
    };
  }, [editClienteDialog.open, editClienteDialogClienteId, empresaId, supabase, tenantId]);

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

  // inline: buscar item por codigo (id ou codigo interno)
  useEffect(() => {
    if (!supabase || !tenantId || !empresaId) return;

    const raw = String(inlineItemId ?? "").trim();
    const reqId = ++inlineItemReqRef.current;

    if (!raw) {
      setInlineItem(null);
      setInlineErr(null);
      return;
    }

    if (isInlineTokenGenerico(raw)) {
      setInlineItem(null);
      setInlineErr(null);
      return;
    }

    const t = setTimeout(async () => {
      try {
        const item = await resolveItemByCodigoOrId(raw);
        if (reqId !== inlineItemReqRef.current) return;
        if (!item?.id) {
          setInlineItem(null);
          setInlineErr("Item nao encontrado.");
          return;
        }
        setInlineItem(item);
        setInlineErr(null);
        if (!inlineEditingItemId) {
          const isGenerico = String(item.codigo_interno ?? "").trim().toUpperCase() === "9999";
          setInlineDescricaoLivre(isGenerico ? "" : String(item.descricao ?? item.nome ?? ""));
        }
        if (!inlineEditingItemId) setInlineValorUnitario(defaultValorUnitarioFromItem(item));
        if (!inlineEditingItemId) setInlineQuantidade(defaultQuantidadeFromItem(item));
      } catch {
        if (reqId !== inlineItemReqRef.current) return;
        setInlineItem(null);
        setInlineErr("Erro ao buscar item.");
      }
    }, 250);

    return () => clearTimeout(t);
  }, [
    defaultQuantidadeFromItem,
    defaultValorUnitarioFromItem,
    empresaId,
    inlineEditingItemId,
    inlineItemId,
    isInlineTokenGenerico,
    resolveItemByCodigoOrId,
    supabase,
    tenantId,
  ]);

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
    setLookupSelecionados(new Map());
    setLookupBulkErr(null);

    const nomeTerm = (nextNome ?? lookupNome).trim();
    const fornecedorTerm = (nextFornecedor ?? lookupFornecedor).trim();
    const nomeTerms = parseLookupTerms(nomeTerm);
    const fornecedorTerms = parseLookupTerms(fornecedorTerm);
    const nomeSeedTerm = pickLookupSeedTerm(nomeTerms);
    const fornecedorSeedTerm = pickLookupSeedTerm(fornecedorTerms);

    try {
      if (lookupBuscarConjuntos) {
        const buildConjuntoQuery = (field: "codigo" | "nome" | null) => {
          let q = supabase
            .schema("r")
            .from("r_orcamento_catalogo_busca")
            .select("*")
            .eq("origem", "CONJUNTO");

          if (field && nomeSeedTerm) q = q.ilike(field, `%${nomeSeedTerm}%`);
          return q.order("nome", { ascending: true }).limit(LOOKUP_FETCH_LIMIT);
        };

        const conjuntoResponses = nomeSeedTerm
          ? await Promise.all([buildConjuntoQuery("codigo"), buildConjuntoQuery("nome")])
          : [await buildConjuntoQuery(null)];

        const conjuntoError = conjuntoResponses.find((response) => response.error)?.error;
        if (conjuntoError) {
          setLookupErr(conjuntoError.message);
          setLookupConjuntoRows([]);
          setLookupRows([]);
          return;
        }

        const conjuntoMap = new Map<string, ConjuntoCatalogoRow>();
        conjuntoResponses.forEach((response) => {
          const rows = (response.data ?? []) as Array<Record<string, unknown>>;
          rows.forEach((r) => {
            const conjuntoId = r.conjunto_id ? String(r.conjunto_id) : "";
            if (!conjuntoId || conjuntoMap.has(conjuntoId)) return;
            const codigo = typeof r.codigo === "string" ? r.codigo : r.codigo ? String(r.codigo) : null;
            const nome = typeof r.nome === "string" ? r.nome : r.nome ? String(r.nome) : null;
            const preco = Number(r.preco_sugerido);
            conjuntoMap.set(conjuntoId, {
              conjunto_id: conjuntoId,
              codigo,
              nome,
              preco_sugerido: Number.isFinite(preco) ? preco : null,
            });
          });
        });

        const conjuntoRows = Array.from(conjuntoMap.values())
          .filter((row) => matchesLookupTerms([row.codigo, row.nome], nomeTerms))
          .sort((a, b) => String(a.nome ?? "").localeCompare(String(b.nome ?? ""), "pt-BR", { sensitivity: "base" }))
          .slice(0, LOOKUP_RESULT_LIMIT);

        setLookupConjuntoRows(conjuntoRows);
        setLookupRows([]);
        return;
      }

      setLookupConjuntoRows([]);

      const { data: itemData, error: itemError } = await supabase.rpc("search_orcamento_itens", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaId,
        p_term: nomeSeedTerm || null,
        p_fornecedor: fornecedorSeedTerm || null,
        p_limit: LOOKUP_FETCH_LIMIT,
      });
      if (itemError) {
        setLookupErr(itemError.message);
        setLookupRows([]);
        return;
      }

      const baseRows = ((itemData ?? []) as ItemLookupBaseRow[])
        .filter((row) => matchesLookupTerms([row.nome, row.codigo_interno, row.fabricante], nomeTerms))
        .filter((row) => matchesLookupTerms([row.fornecedor], fornecedorTerms))
        .sort((a, b) => String(a.nome ?? "").localeCompare(String(b.nome ?? ""), "pt-BR", { sensitivity: "base" }))
        .slice(0, LOOKUP_RESULT_LIMIT);

      setLookupRows(
        baseRows.map((r) => ({
          id: r.id,
          codigo_interno: r.codigo_interno,
          nome: r.nome,
          fornecedor: r.fornecedor,
          ultima_entrada: r.ultima_entrada,
          preco_unitario: getSuggestedOrcamentoUnitPrice({
            custoUltimaCompra: r.custo_ultima_compra,
            precoUnitario: r.preco_unitario,
            margemLucroPadraoPercent: cfgMargemLucroPadraoPercent,
          }),
          estoque_atual: r.estoque_atual === null ? null : Number(r.estoque_atual),
        }))
      );
    } catch (e: unknown) {
      setLookupErr(e instanceof Error ? e.message : "Erro ao buscar itens.");
      setLookupRows([]);
      setLookupConjuntoRows([]);
    } finally {
      setLookupBusy(false);
    }
  }

  async function handleAddConjuntoConfirm() {
    if (!supabase) return;
    if (!orc?.id) return;
    if (!tenantId || !empresaId) return;
    if (readOnly || !canWrite) return;
    if (!addConjunto.open) return;

    const qtd = parseDecimalBR(addConjunto.quantidade);
    if (!Number.isFinite(qtd) || qtd <= 0) {
      setAddConjunto((p) => (p.open ? { ...p, error: "Quantidade invalida." } : p));
      return;
    }

    setAddConjunto((p) => (p.open ? { ...p, busy: true, error: null } : p));
    try {
      if (addConjunto.modo === "ITEM_UNICO") {
        const itemGenerico = await getItemByCodigo(supabase, { tenantId, empresaId, codigo: "9999" });
        if (!itemGenerico?.id) {
          throw new Error("Nao foi possivel resolver o item generico 9999 para inserir o conjunto.");
        }

        const valorUnitario = Number(addConjunto.conjunto.preco_sugerido ?? 0);
        const valorSeguro = Number.isFinite(valorUnitario) && valorUnitario >= 0 ? Number(valorUnitario.toFixed(2)) : 0;
        const descricao = formatConjuntoSingleLineDescription(addConjunto.conjunto);

        await addItem(supabase, {
          tenantId,
          empresaId,
          orcamentoId: orc.id,
          itemId: itemGenerico.id,
          quantidade: qtd,
          valorUnitario: valorSeguro,
          descontoItemPercent: 0,
          observacoes: descricao,
        });

        const totalEstimado = Number((qtd * valorSeguro).toFixed(2));

        setAddConjunto({ open: false });
        setShowLookup(false);
        await reload();
        setOk(
          `Conjunto inserido como item unico: ${formatDecimalBR(qtd)} x R$ ${formatMoneyBR(valorSeguro)} = R$ ${formatMoneyBR(totalEstimado)}.`
        );
        return;
      }

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
        setOk(`Conjunto expandido em itens: ${itensInseridos} itens, total estimado R$ ${formatMoneyBR(totalEstimado)}.`);
      } else {
        setOk("Conjunto expandido em itens.");
      }
    } catch (e: unknown) {
      setAddConjunto((p) =>
        p.open ? { ...p, busy: false, error: mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao inserir conjunto.") } : p
      );
    } finally {
      setAddConjunto((p) => (p.open ? { ...p, busy: false } : p));
    }
  }

  async function handleAddSelecionadosConfirm() {
    if (!supabase) return;
    if (!orc?.id) return;
    if (!tenantId || !empresaId) return;
    if (readOnly || !canWrite) return;
    if (lookupSelecionados.size === 0) return;

    const entradas = Array.from(lookupSelecionados.entries());
    for (const [, qtdTexto] of entradas) {
      const qtd = parseDecimalBR(qtdTexto);
      if (!Number.isFinite(qtd) || qtd <= 0) {
        setLookupBulkErr("Informe uma quantidade valida (maior que zero) para todos os itens selecionados.");
        return;
      }
    }

    setLookupBulkBusy(true);
    setLookupBulkErr(null);
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData.session?.access_token ?? null;
      if (!token) throw new Error("Sessao expirada. Faca login novamente.");

      const itensPayload = entradas.map(([itemId, qtdTexto], idx) => ({
        linha: idx + 1,
        produtoId: String(itemId),
        qtd: parseDecimalBR(qtdTexto),
      }));

      const res = await fetch(`/api/comercial/orcamentos/${encodeURIComponent(idParam)}/assistente-ia/adicionar-itens`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ tenantId, empresaId, itens: itensPayload }),
      });

      const json = (await res.json().catch(() => ({}))) as {
        resumo?: { totalAdicionado?: number; totalIgnorado?: number; totalErro?: number };
        erros?: Array<{ erro?: string }>;
        ignorados?: Array<{ motivo?: string }>;
        error?: string;
      };

      if (!res.ok) {
        throw new Error(json.error || "Erro ao adicionar itens selecionados.");
      }

      const totalAdicionado = json.resumo?.totalAdicionado ?? 0;
      const totalIgnorado = json.resumo?.totalIgnorado ?? 0;
      const totalErro = json.resumo?.totalErro ?? 0;

      if (totalAdicionado === 0) {
        const motivo = json.erros?.[0]?.erro || json.ignorados?.[0]?.motivo || "Nenhum item foi adicionado.";
        setLookupBulkErr(motivo);
        return;
      }

      setLookupSelecionados(new Map());
      setShowLookup(false);
      await reload();

      const partes = [`${totalAdicionado} item${totalAdicionado === 1 ? "" : "s"} adicionado${totalAdicionado === 1 ? "" : "s"}`];
      if (totalIgnorado > 0) partes.push(`${totalIgnorado} ignorado${totalIgnorado === 1 ? "" : "s"} (ja no orcamento)`);
      if (totalErro > 0) partes.push(`${totalErro} com erro`);
      setOk(`${partes.join(", ")}.`);
    } catch (e: unknown) {
      setLookupBulkErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao adicionar itens selecionados."));
    } finally {
      setLookupBulkBusy(false);
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

    const triggerGenerico = isInlineTokenGenerico(raw);
    if (triggerGenerico) {
      const textoLivre = raw.slice(1).trim();
      const reqId = ++inlineItemReqRef.current;
      try {
        const item = await resolveItemByCodigoOrId("9999");
        if (reqId !== inlineItemReqRef.current) return;
        if (!item?.id) {
          setInlineItem(null);
          setInlineErr("Nao foi possivel resolver o item generico 9999.");
          return;
        }
        setInlineItemId("9999");
        setInlineItem(item);
        setInlineErr(null);
        setInlineDescricaoLivre(textoLivre);
        if (!inlineEditingItemId) setInlineValorUnitario(defaultValorUnitarioFromItem(item));
        if (!inlineEditingItemId) setInlineQuantidade(defaultQuantidadeFromItem(item));
        window.requestAnimationFrame(() => {
          inlineQuantidadeInputRef.current?.focus();
          inlineQuantidadeInputRef.current?.select();
        });
      } catch (e: unknown) {
        if (reqId !== inlineItemReqRef.current) return;
        setInlineItem(null);
        const msg = toSupabaseErrorLike(e)?.message ?? "Erro ao buscar item generico.";
        setInlineErr(msg);
      }
      return;
    }

    const reqId = ++inlineItemReqRef.current;
    try {
      const item = await resolveItemByCodigoOrId(raw);
      if (reqId !== inlineItemReqRef.current) return;
      if (!item?.id) {
        setInlineItem(null);
        setInlineErr("Item nao encontrado.");
        if (raw !== "9999") openLookupModal(raw);
        return;
      }
      setInlineItem(item);
      setInlineErr(null);
      if (!inlineEditingItemId) {
        const isGenerico = String(item.codigo_interno ?? "").trim().toUpperCase() === "9999";
        setInlineDescricaoLivre(isGenerico ? "" : String(item.descricao ?? item.nome ?? ""));
      }
      if (!inlineEditingItemId) setInlineValorUnitario(defaultValorUnitarioFromItem(item));
      if (!inlineEditingItemId) setInlineQuantidade(defaultQuantidadeFromItem(item));
      window.requestAnimationFrame(() => {
        inlineQuantidadeInputRef.current?.focus();
        inlineQuantidadeInputRef.current?.select();
      });
    } catch (e: unknown) {
      if (reqId !== inlineItemReqRef.current) return;
      setInlineItem(null);
      const msg = toSupabaseErrorLike(e)?.message ?? "Erro ao buscar item.";
      setInlineErr(msg);
      if (raw !== "9999") openLookupModal(raw);
    }
  }
  const closeNewDialog = useCallback(() => {
    setNewDialog(closedNewDialog());
    router.push("/comercial/orcamentos");
  }, [router]);

  const applyContatoSuggestion = useCallback((contato: ClienteContatoLookupRow) => {
    setNewDialog((p) =>
      p.open
        ? {
            ...p,
            solicitanteNome: uppercaseContatoField(contato.nome),
            solicitanteSetor: uppercaseContatoField(contato.setor),
            solicitanteEmail: lowercaseEmailField(contato.email),
            solicitanteTelefone: formatPhoneInput(contato.telefone),
          }
        : p
    );
  }, []);

  const applyEditContatoSuggestion = useCallback((contato: ClienteContatoLookupRow) => {
    setEditClienteDialog((p) =>
      p.open
        ? {
            ...p,
            solicitanteNome: uppercaseContatoField(contato.nome),
            solicitanteSetor: uppercaseContatoField(contato.setor),
            solicitanteEmail: lowercaseEmailField(contato.email),
            solicitanteTelefone: formatPhoneInput(contato.telefone),
          }
        : p
    );
  }, []);

  const submitNew = useCallback(async () => {
    if (!newDialog.open) return;
    if (!supabase || !tenantId || !empresaId) return;

    const clienteId = newDialog.clienteId;
    const titulo = upperTrim(newDialog.titulo);
    const vendedorUsuarioId = String(newDialog.vendedorUsuarioId ?? "").trim();
    const solicitanteNome = uppercaseContatoField(newDialog.solicitanteNome);
    const solicitanteSetor = uppercaseContatoField(newDialog.solicitanteSetor);
    const solicitanteEmail = lowercaseEmailField(newDialog.solicitanteEmail);
    const solicitanteTelefone = formatPhoneInput(newDialog.solicitanteTelefone);

    if (!clienteId) {
      setNewDialog((p) => (p.open ? { ...p, error: "Selecione um cliente." } : p));
      return;
    }
    if (!titulo) {
      setNewDialog((p) => (p.open ? { ...p, error: "Informe o titulo." } : p));
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
        solicitanteNome,
        solicitanteSetor,
        solicitanteEmail,
        solicitanteTelefone,
      });
      setNewDialog(closedNewDialog());
      router.replace(`/comercial/orcamentos/${created.codigo ?? created.id}`);
    } catch (e: unknown) {
      setNewDialog((p) =>
        p.open ? { ...p, busy: false, error: mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao criar orcamento.") } : p
      );
    }
  }, [empresaId, newDialog, router, supabase, tenantId]);

  const openEditCliente = useCallback(() => {
    if (!orc?.id || !form) return;
    if (!supabase || !tenantId || !empresaId) return;
    if (readOnly || !canWrite) return;

    setEditClienteDialog({
      open: true,
      busy: false,
      error: null,
      clienteTerm: clienteNome ?? "",
      clienteResults: [],
      clienteLoading: false,
      clienteSearchError: null,
      clienteId: form.cliente_id ?? orc.cliente_id ?? null,
      contatoResults: [],
      contatoLoading: false,
      titulo: form.titulo ?? orc.titulo ?? "",
      vendedorUsuarioId: form.vendedor_usuario_id ?? orc.vendedor_usuario_id ?? "",
      condicaoPagamentoId: form.condicao_pagamento_id ?? orc.condicao_pagamento_id ?? null,
      solicitanteNome: uppercaseContatoField(orc.solicitante_nome),
      solicitanteSetor: uppercaseContatoField(orc.solicitante_setor),
      solicitanteEmail: lowercaseEmailField(orc.solicitante_email),
      solicitanteTelefone: formatPhoneInput(orc.solicitante_telefone),
    });
  }, [canWrite, clienteNome, empresaId, form, orc, readOnly, supabase, tenantId]);

  const closeEditCliente = useCallback(() => {
    setEditClienteDialog(closedEditClienteDialog());
  }, []);

  const submitEditCliente = useCallback(async () => {
    if (!editClienteDialog.open) return;
    if (!orc?.id || !form) return;
    if (!supabase || !tenantId || !empresaId) return;
    if (readOnly || !canWrite) return;

    const clienteId = editClienteDialog.clienteId;
    const titulo = upperTrim(editClienteDialog.titulo);
    const vendedorUsuarioId = String(editClienteDialog.vendedorUsuarioId ?? "").trim();
    const condicaoPagamentoId = editClienteDialog.condicaoPagamentoId ?? null;
    const solicitanteNome = uppercaseContatoField(editClienteDialog.solicitanteNome);
    const solicitanteSetor = uppercaseContatoField(editClienteDialog.solicitanteSetor);
    const solicitanteEmail = lowercaseEmailField(editClienteDialog.solicitanteEmail);
    const solicitanteTelefone = formatPhoneInput(editClienteDialog.solicitanteTelefone);

    if (!clienteId) {
      setEditClienteDialog((p) => (p.open ? { ...p, error: "Selecione um cliente." } : p));
      return;
    }
    if (!titulo) {
      setEditClienteDialog((p) => (p.open ? { ...p, error: "Informe o titulo." } : p));
      return;
    }
    if (!vendedorUsuarioId) {
      setEditClienteDialog((p) => (p.open ? { ...p, error: "Selecione um vendedor." } : p));
      return;
    }

    setEditClienteDialog((p) => (p.open ? { ...p, busy: true, error: null } : p));
    setErr(null);
    setOk(null);
    try {
      const patch: Partial<OrcamentoRow> = {
        cliente_id: clienteId,
        titulo,
        vendedor_usuario_id: vendedorUsuarioId,
        condicao_pagamento_id: condicaoPagamentoId,
        solicitante_nome: solicitanteNome || null,
        solicitante_setor: solicitanteSetor || null,
        solicitante_email: solicitanteEmail || null,
        solicitante_telefone: solicitanteTelefone || null,
      };

      await updateOrcamento(supabase, { tenantId, empresaId, id: orc.id, patch });
      await salvarContatoClienteDoOrcamento(supabase, {
        tenantId,
        empresaId,
        clienteId,
        solicitanteNome,
        solicitanteSetor,
        solicitanteEmail,
        solicitanteTelefone,
      });

      setOrc((p) => (p ? { ...p, ...patch } : p));
      setForm((p) =>
        p
          ? {
              ...p,
              cliente_id: clienteId,
              titulo,
              vendedor_usuario_id: vendedorUsuarioId,
              condicao_pagamento_id: condicaoPagamentoId,
            }
          : p
      );

      try {
        const cli = await getClienteById(supabase, { tenantId, empresaId, clienteId });
        setClienteNome(cli?.nome ?? null);
      } catch {
        // keep previous name if lookup fails
      }

      setOk("Dados iniciais atualizados.");
      setEditClienteDialog(closedEditClienteDialog());
      await reload();
    } catch (e: unknown) {
      setEditClienteDialog((p) =>
        p.open ? { ...p, busy: false, error: mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao atualizar dados iniciais.") } : p
      );
    }
  }, [canWrite, editClienteDialog, empresaId, form, orc?.id, readOnly, reload, supabase, tenantId]);

  const saveHeader = useCallback(
    async (e?: FormEvent) => {
      e?.preventDefault();
      if (!orc?.id || !form) return;
      if (!supabase || !tenantId || !empresaId) return;
      if (readOnly || !canWrite) return;

      const desconto = n(form.desconto_global_percent);
      if (cfgDescontoMax > 0 && desconto > cfgDescontoMax) {
        setErr(`Desconto global (%) excede o maximo configurado (${cfgDescontoMax}%).`);
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
        setOk("Orcamento atualizado.");
        await reload();
      } catch (e2: unknown) {
        setErr(mapOrcamentoError(toSupabaseErrorLike(e2), "Erro ao salvar."));
      } finally {
        setBusy(false);
      }
    },
    [canWrite, cfgDescontoMax, empresaId, form, orc?.cliente_id, orc?.id, readOnly, reload, supabase, tenantId]
  );

  const openStatusDialog = useCallback(
    (nextStatus: OrcamentoStatusCanonical) => {
      if (!orc?.id) return;
      if (!canWrite || busy) return;
      setStatusDialog({ open: true, status: nextStatus });
    },
    [busy, canWrite, orc?.id]
  );

  const closeStatusDialog = useCallback(() => {
    if (busy) return;
    setStatusDialog({ open: false });
  }, [busy]);

  const saveStatusDialog = useCallback(
    async (payload: OrcamentoStatusDialogPayload) => {
      if (!orc?.id) return;
      if (!statusDialog.open) return;
      if (!supabase || !tenantId || !empresaId) return;
      if (!canWrite || busy) return;

      const prevOrc = orc;

      setBusy(true);
      setErr(null);
      setOk(null);
      setOrc((current) =>
        current
          ? {
              ...current,
              status: payload.status,
              observacoes: payload.followup,
              valor_fechado: payload.status === "FECHADO" ? payload.valorFechado : current.valor_fechado,
              updated_at: new Date().toISOString(),
            }
          : current
      );
      try {
        const result = await atualizarStatusOrcamento(supabase, {
          tenantId,
          empresaId,
          id: orc.id,
          status: payload.status,
          followup: payload.followup,
          valorFechado: payload.valorFechado,
          abrirOs: payload.abrirOs,
          importarItensOs: payload.importarItensOs,
        });
        setStatusDialog({ open: false });
        if (payload.abrirOs && result.osId) {
          router.push(`/os/${result.osId}`);
          return;
        }
        setOk(`Status atualizado para ${getOrcamentoStatusLabel(payload.status)}.`);
        await reload();
      } catch (e: unknown) {
        setOrc(prevOrc);
        setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao atualizar status do orcamento."));
      } finally {
        setBusy(false);
      }
    },
    [busy, canWrite, empresaId, orc, reload, router, statusDialog.open, supabase, tenantId]
  );

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

  const totalDespesas = useMemo(
    () =>
      itens.reduce((sum, item) => {
        return String(item.item_tipo ?? "").toUpperCase() === "DESPESA" ? sum + n(item.valor_total) : sum;
      }, 0),
    [itens]
  );

  const cancelInlineEdit = useCallback(() => {
    setInlineEditingItemId(null);
    setInlineItemId("");
    setInlineItem(null);
    setInlineQuantidade("1");
    setInlineValorUnitario("0");
    setInlineDesconto("0");
    setInlineDescricaoLivre("");
    setInlineErr(null);
    window.requestAnimationFrame(() => {
      inlineCodigoInputRef.current?.focus();
      inlineCodigoInputRef.current?.select();
    });
  }, []);

  const submitInlineItem = useCallback(async () => {
    if (!supabase || !tenantId || !empresaId) return;
    if (!orc?.id) return;
    if (readOnly || !canWrite) return;
    if (!form) return;

    if (!inlineItem?.id) {
      setInlineErr("Item nao encontrado.");
      return;
    }
    const descricaoLivre = String(inlineDescricaoLivre ?? "").trim();
    if (inlineIsCodigoGenerico && !descricaoLivre) {
      setInlineErr("Informe a descricao livre para o codigo 9999.");
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

    // Garante que a condicao de pagamento / desconto global do cabecalho estejam persistidos
    // antes de inserir/atualizar itens (triggers do banco dependem disso).
    const nextCondId = form.condicao_pagamento_id ?? null;
    const nextDescGlobal = n(form.desconto_global_percent);
    const curCondId = (orc.condicao_pagamento_id ?? null) as string | null;
    const curDescGlobal = n(orc.desconto_global_percent);

    if (cfgDescontoMax > 0 && nextDescGlobal > cfgDescontoMax) {
      setInlineErr(`Desconto global (%) excede o maximo configurado (${cfgDescontoMax}%).`);
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
            observacoes: inlineIsCodigoGenerico ? descricaoLivre : null,
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
          observacoes: inlineIsCodigoGenerico ? descricaoLivre : null,
        });
      }

      cancelInlineEdit();
      await reload();
    } catch (e: unknown) {
      setInlineErr(mapOrcamentoError(toSupabaseErrorLike(e), inlineEditingItemId ? "Erro ao atualizar item." : "Erro ao adicionar item."));
    } finally {
      setInlineBusy(false);
    }
  }, [canWrite, cancelInlineEdit, cfgDescontoMax, empresaId, form, inlineDesconto, inlineDescricaoLivre, inlineEditingItemId, inlineIsCodigoGenerico, inlineItem, inlineQuantidade, inlineValorUnitario, orc, readOnly, reload, supabase, tenantId]);

  const startInlineEdit = useCallback(
    (it: OrcamentoItemRow) => {
      if (readOnly || !canWrite) return;
      setInlineEditingItemId(it.id);
      setInlineItemId(String(it.item_id));
      setInlineQuantidade(String(it.quantidade ?? "1"));
      setInlineValorUnitario(String(it.valor_unitario ?? "0"));
      setInlineDesconto(String(it.desconto_item_percent ?? "0"));
      setInlineDescricaoLivre(String(it.observacoes ?? it.item_nome ?? ""));
      setInlineErr(null);

      // Move focus to the inline form.
      setTimeout(() => {
        inlineFormRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
        inlineQuantidadeInputRef.current?.focus();
        inlineQuantidadeInputRef.current?.select();
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
        description: "Exclusao e arquivamento (soft delete).",
        confirmText: "Excluir",
        destructive: true,
      });
      if (!ok) return;

      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        const { error } = await supabase
          .schema("m")
          .from("orcamento_item")
          .update({ deleted_at: new Date().toISOString() })
          .eq("id", it.id);

        if (error) throw error;
        setOk("Item excluido.");
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
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissoes...</div>;
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
                      ? "Busque conjuntos (kits) para inserir no orcamento."
                      : "Filtre por nome, codigo ou fabricante para localizar o ID."}
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    setShowLookup(false);
                    setLookupSelecionados(new Map());
                    setLookupBulkErr(null);
                  }}
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

              {!lookupBuscarConjuntos && (
                <label className="flex items-center gap-2 text-sm text-zinc-200">
                  <input
                    type="checkbox"
                    checked={lookupMultiMode}
                    onChange={(e) => {
                      setLookupMultiMode(e.target.checked);
                      setLookupSelecionados(new Map());
                      setLookupBulkErr(null);
                    }}
                  />
                  Selecionar varios
                </label>
              )}

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">{lookupBuscarConjuntos ? "Codigo/Nome" : "Nome/Codigo"}</div>
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
                    aria-label={lookupBuscarConjuntos ? "Buscar conjunto" : "Buscar item por nome ou codigo"}
                    title={lookupBuscarConjuntos ? "Buscar conjunto" : "Buscar item por nome ou codigo"}
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
                    setLookupSelecionados(new Map());
                    setLookupBulkErr(null);
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
                      {lookupMultiMode && <col className="w-10" />}
                      <col className="w-16" />
                      <col className="w-40" />
                      <col className="w-[40%]" />
                      <col className="w-[28%]" />
                      <col className="w-32" />
                      <col className="w-28" />
                      <col className="w-20" />
                      {lookupMultiMode && <col className="w-28" />}
                    </colgroup>
                    <thead className="bg-zinc-900/70 sticky top-0 z-10">
                      <tr className="text-left text-zinc-200">
                        {lookupMultiMode && (
                          <th className="px-4 py-3">
                            <input
                              type="checkbox"
                              aria-label="Selecionar todos"
                              checked={
                                sortedLookupRows.length > 0 && sortedLookupRows.every((it) => lookupSelecionados.has(it.id))
                              }
                              onChange={(e) => {
                                const checked = e.target.checked;
                                setLookupSelecionados((prev) => {
                                  const next = new Map(prev);
                                  sortedLookupRows.forEach((it) => {
                                    if (checked) next.set(it.id, next.get(it.id) ?? "1");
                                    else next.delete(it.id);
                                  });
                                  return next;
                                });
                              }}
                            />
                          </th>
                        )}
                        <th className="px-4 py-3 cursor-pointer whitespace-nowrap" onClick={() => handleSort("id")}>
                          ID {sortKey === "id" && (sortDir === "asc" ? "^" : "v")}
                        </th>
                        <th className="px-4 py-3 cursor-pointer whitespace-nowrap" onClick={() => handleSort("codigo")}>
                          Codigo {sortKey === "codigo" && (sortDir === "asc" ? "^" : "v")}
                        </th>
                        <th className="px-4 py-3 cursor-pointer" onClick={() => handleSort("descricao")}>
                          Descricao {sortKey === "descricao" && (sortDir === "asc" ? "^" : "v")}
                        </th>
                        <th className="px-4 py-3 cursor-pointer" onClick={() => handleSort("fornecedor")}>
                          Fornecedor {sortKey === "fornecedor" && (sortDir === "asc" ? "^" : "v")}
                        </th>
                        <th className="px-4 py-3 cursor-pointer whitespace-nowrap" onClick={() => handleSort("ultima")}>
                          Ultima entrada {sortKey === "ultima" && (sortDir === "asc" ? "^" : "v")}
                        </th>
                        <th className="px-4 py-3 text-right cursor-pointer whitespace-nowrap" onClick={() => handleSort("preco")}>
                          Preco sugerido {sortKey === "preco" && (sortDir === "asc" ? "^" : "v")}
                        </th>
                        <th className="px-4 py-3 text-right cursor-pointer whitespace-nowrap" onClick={() => handleSort("estoque")}>
                          Saldo {sortKey === "estoque" && (sortDir === "asc" ? "^" : "v")}
                        </th>
                        {lookupMultiMode && <th className="px-4 py-3 text-right whitespace-nowrap">Qtd</th>}
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-zinc-800">
                      {sortedLookupRows.map((it) => {
                        const selecionado = lookupSelecionados.has(it.id);
                        return (
                          <tr
                            key={it.id}
                            className="hover:bg-zinc-900/40 cursor-pointer"
                            onClick={() => {
                              if (lookupMultiMode) {
                                setLookupSelecionados((prev) => {
                                  const next = new Map(prev);
                                  if (next.has(it.id)) next.delete(it.id);
                                  else next.set(it.id, "1");
                                  return next;
                                });
                                return;
                              }
                              setInlineItemId(String(it.id));
                              setShowLookup(false);
                            }}
                          >
                            {lookupMultiMode && (
                              <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                                <input
                                  type="checkbox"
                                  aria-label={`Selecionar ${it.nome ?? it.id}`}
                                  checked={selecionado}
                                  onChange={() => {
                                    setLookupSelecionados((prev) => {
                                      const next = new Map(prev);
                                      if (next.has(it.id)) next.delete(it.id);
                                      else next.set(it.id, "1");
                                      return next;
                                    });
                                  }}
                                />
                              </td>
                            )}
                            <td className="px-4 py-3 tabular-nums whitespace-nowrap">{it.id}</td>
                            <td className="px-4 py-3 whitespace-nowrap">{it.codigo_interno}</td>
                            <td className="px-4 py-3 whitespace-normal break-words">{it.nome}</td>
                            <td className="px-4 py-3 text-zinc-300 whitespace-normal break-words">{it.fornecedor ?? "-"}</td>
                            <td className="px-4 py-3 text-zinc-300">
                              {it.ultima_entrada ? new Date(it.ultima_entrada).toLocaleDateString("pt-BR") : "-"}
                            </td>
                            <td className="px-4 py-3 text-right tabular-nums">R$ {formatMoneyBR(Number(it.preco_unitario ?? 0))}</td>
                            <td className="px-4 py-3 text-right tabular-nums">
                              {typeof it.estoque_atual === "number" ? formatDecimalBR(Number(it.estoque_atual), 3) : "-"}
                            </td>
                            {lookupMultiMode && (
                              <td className="px-4 py-3 text-right" onClick={(e) => e.stopPropagation()}>
                                <input
                                  value={lookupSelecionados.get(it.id) ?? ""}
                                  disabled={!selecionado}
                                  onChange={(e) => {
                                    const value = e.target.value;
                                    setLookupSelecionados((prev) => {
                                      if (!prev.has(it.id)) return prev;
                                      const next = new Map(prev);
                                      next.set(it.id, value);
                                      return next;
                                    });
                                  }}
                                  inputMode="decimal"
                                  className="w-full px-2 py-1 text-right rounded-md border border-zinc-800 bg-zinc-950 disabled:opacity-40"
                                />
                              </td>
                            )}
                          </tr>
                        );
                      })}

                      {lookupRows.length === 0 && (
                        <tr>
                          <td colSpan={lookupMultiMode ? 9 : 7} className="px-4 py-6 text-zinc-400 text-center">
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
                        <th className="px-4 py-3 whitespace-nowrap">Codigo</th>
                        <th className="px-4 py-3">Nome</th>
                        <th className="px-4 py-3 text-right whitespace-nowrap">Preco sugerido</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-zinc-800">
                      {lookupConjuntoRows.map((c) => (
                        <tr
                          key={c.conjunto_id}
                          className="hover:bg-zinc-900/40 cursor-pointer"
                          onClick={() =>
                            setAddConjunto({
                              open: true,
                              conjunto: c,
                              quantidade: "1",
                              modo: "EXPANDIR_ITENS",
                              busy: false,
                              error: null,
                            })
                          }
                        >
                          <td className="px-4 py-3 whitespace-nowrap">{c.codigo ?? "-"}</td>
                          <td className="px-4 py-3 whitespace-normal break-words">{c.nome ?? "-"}</td>
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

              {lookupMultiMode && lookupSelecionados.size > 0 && (
                <div className="flex items-center justify-between gap-3 rounded-xl border border-zinc-800 bg-zinc-900/70 px-4 py-3">
                  <div className="text-sm text-zinc-200">
                    {lookupSelecionados.size} item{lookupSelecionados.size === 1 ? "" : "s"} selecionado
                    {lookupSelecionados.size === 1 ? "" : "s"}
                    {lookupBulkErr && <span className="ml-3 text-red-400">{lookupBulkErr}</span>}
                  </div>
                  <button
                    type="button"
                    onClick={() => void handleAddSelecionadosConfirm()}
                    disabled={lookupBulkBusy}
                    className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
                  >
                    {lookupBulkBusy ? "Adicionando..." : `Adicionar ${lookupSelecionados.size} itens`}
                  </button>
                </div>
              )}

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
                        {addConjunto.conjunto.codigo ?? ""} {addConjunto.conjunto.nome ? `- ${addConjunto.conjunto.nome}` : ""}
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
                      <div className="space-y-2">
                        <div className="text-xs text-zinc-400">Modo de inclusao</div>
                        <label className="flex items-start gap-2 rounded-lg border border-zinc-800 px-3 py-2 text-sm text-zinc-200">
                          <input
                            type="radio"
                            name="modo-conjunto"
                            checked={addConjunto.modo === "EXPANDIR_ITENS"}
                            onChange={() =>
                              setAddConjunto((p) => (p.open ? { ...p, modo: "EXPANDIR_ITENS", error: null } : p))
                            }
                            disabled={addConjunto.busy}
                          />
                          <span>Adicionar todos os itens do conjunto para editar quantidades depois.</span>
                        </label>
                        <label className="flex items-start gap-2 rounded-lg border border-zinc-800 px-3 py-2 text-sm text-zinc-200">
                          <input
                            type="radio"
                            name="modo-conjunto"
                            checked={addConjunto.modo === "ITEM_UNICO"}
                            onChange={() => setAddConjunto((p) => (p.open ? { ...p, modo: "ITEM_UNICO", error: null } : p))}
                            disabled={addConjunto.busy}
                          />
                          <span>Adicionar uma unica linha no orcamento com o preco sugerido do conjunto.</span>
                        </label>
                      </div>
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

      <AssistenteIAModal
        open={aiAssistantOpen}
        idParam={idParam}
        supabase={supabase}
        tenantId={tenantId}
        empresaId={empresaId}
        onClose={() => setAiAssistantOpen(false)}
        onImported={reload}
      />

      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Orcamento</h1>
          <div className="text-sm text-zinc-400 mt-1 flex items-center gap-2 flex-wrap">
            <span>
              {orc?.codigo ? (
                <>
                  <span className="font-medium text-zinc-200">{orc.codigo}</span>
                  {orc?.versao ? <span className="text-zinc-500"> v{orc.versao}</span> : null}
                  {clienteNome ? (
                    readOnly || !canWrite ? (
                      <span className="text-zinc-400"> - {clienteNome}</span>
                    ) : (
                      <button
                        type="button"
                        onClick={openEditCliente}
                        className="text-zinc-400 hover:text-zinc-200 underline underline-offset-2"
                      >
                        {` - ${clienteNome}`}
                      </button>
                    )
                  ) : null}
                </>
              ) : (
                <span>Novo</span>
              )}
            </span>
            {orc?.status && (
              <span className={`px-2 py-0.5 rounded-full border text-xs ${statusBadgeClass(status)}`}>{statusLabel}</span>
            )}
            {orc?.emissao_date ? <span>Emissao: {formatDateBR(orc.emissao_date)}</span> : null}
            {statusFollowup ? <span className="text-zinc-400">Ultimo followup: {truncateText(statusFollowup)}</span> : null}
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
                onClick={() => {
                  if (!orc?.codigo && !orc?.id) return;
                  const idOrCodigo = encodeURIComponent(String(orc.codigo || orc.id));
                  const url = `/comercial/orcamentos/${idOrCodigo}/imprimir`;
                  const w = window.open(url, "_blank", "noopener,noreferrer");
                  if (!w) router.push(url);
                }}
                className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
              >
                Imprimir
              </button>
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
                onClick={() => openStatusDialog("FECHADO")}
                disabled={!canWrite || busy}
                className="px-3 py-2 rounded-md border border-emerald-500/30 bg-emerald-500/10 hover:bg-emerald-500/15 text-emerald-200 text-sm disabled:opacity-60"
              >
                Fechado
              </button>
              <button
                type="button"
                onClick={() => openStatusDialog("PERDIDO")}
                disabled={!canWrite || busy}
                className="px-3 py-2 rounded-md border border-red-500/30 bg-red-500/10 hover:bg-red-500/15 text-red-200 text-sm disabled:opacity-60"
              >
                Perdido
              </button>
              <button
                type="button"
                onClick={() => openStatusDialog("ANDAMENTO")}
                disabled={!canWrite || busy}
                className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm disabled:opacity-60"
              >
                Andamento
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
                Titulo
                <input
                  value={form.titulo}
                  disabled={readOnly || !canWrite}
                  onChange={(e) => setForm((p) => (p ? { ...p, titulo: e.target.value } : p))}
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                />
              </label>

              <label className="block text-xs text-zinc-400">
                Emissao
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
                Condicao de Pagamento
                <select
                  value={form.condicao_pagamento_id ?? ""}
                  disabled={readOnly || !canWrite}
                  onChange={(e) =>
                    setForm((p) => (p ? { ...p, condicao_pagamento_id: e.target.value ? e.target.value : null } : p))
                  }
                  className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                >
                  <option value="">(Sem condicao)</option>
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
                  placeholder={cfgDescontoMax ? `Max. ${cfgDescontoMax}%` : undefined}
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

            {readOnly && <div className="text-xs text-zinc-500">Edicao bloqueada (status {statusLabel}).</div>}
          </div>

          <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
            <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between gap-2">
              <div className="font-medium">Itens</div>
              <button
                type="button"
                onClick={() => setAiAssistantOpen(true)}
                disabled={readOnly || !canWrite}
                className="px-3 py-2 rounded-md border border-emerald-500/30 bg-emerald-500/10 hover:bg-emerald-500/15 text-emerald-200 text-sm disabled:opacity-60"
              >
                Assistente de IA
              </button>
            </div>

            <div ref={inlineFormRef} className="p-4 border-b border-zinc-800">
              {inlineErr && <div className="text-sm text-red-400 mb-3">{inlineErr}</div>}
              <div className="flex flex-wrap items-end gap-3">
                <label className="block text-xs text-zinc-400 w-full sm:w-36">
                  Codigo
                  <input
                    ref={inlineCodigoInputRef}
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
                    placeholder="Ex.: 109 ou #texto livre"
                  />
                </label>

                <label className="block text-xs text-zinc-400 w-20">
                  Unidade
                  <input
                    value={inlineItem?.id ? upperTrim(String(inlineItem.unidade_medida ?? "")) || "-" : "-"}
                    disabled
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>

                {inlineItemIsKg && (
                  <label className="block text-xs text-zinc-400 w-36">
                    Peso ref. (kg)
                    <input
                      value={inlineItemPesoReferencia !== null ? formatDecimalBR(inlineItemPesoReferencia) : "-"}
                      disabled
                      title={
                        inlineItemPesoReferencia !== null
                          ? `Peso cadastrado desta peca: ${formatDecimalBR(inlineItemPesoReferencia)} kg (ajuste a quantidade se for outra).`
                          : "Item sem peso de referencia cadastrado; informe o peso real em kg na quantidade."
                      }
                      className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                    />
                  </label>
                )}

                <label className="block text-xs text-zinc-400 w-28">
                  {inlineItemIsKg ? "Quantidade (kg)" : "Quantidade"}
                  <input
                    ref={inlineQuantidadeInputRef}
                    value={inlineQuantidade}
                    disabled={readOnly || !canWrite || inlineBusy}
                    onChange={(e) => setInlineQuantidade(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        if (!inlineBusy) void submitInlineItem();
                      }
                    }}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>

                <label className="block text-xs text-zinc-400 flex-1 min-w-[140px]">
                  {inlineItemIsKg ? "Valor unitario (R$/kg)" : "Valor unitario"}
                  <input
                    value={inlineValorUnitario}
                    disabled={readOnly || !canWrite || inlineBusy}
                    onChange={(e) => setInlineValorUnitario(e.target.value)}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>

                <label className="block text-xs text-zinc-400 w-24">
                  Desconto
                  <input
                    value={inlineDesconto}
                    disabled={readOnly || !canWrite || inlineBusy}
                    onChange={(e) => setInlineDesconto(e.target.value)}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>

                <label className="block text-xs text-zinc-400 w-24">
                  Estoque
                  <input
                    value={inlineItem?.id ? formatDecimalBR(inlineEstoqueAtual ?? 0) : "-"}
                    disabled
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>

                <label className="block text-xs text-zinc-400 w-28">
                  Total
                  <input
                    value={formatMoneyBR(inlineTotal)}
                    disabled
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                  />
                </label>

                <label className="block text-xs text-zinc-400 w-32">
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
                    value={
                      inlineIsCodigoGenerico
                        ? inlineDescricaoLivre
                        : inlineItem?.id
                          ? (inlineItem.descricao ?? inlineItem.nome ?? "")
                          : ""
                    }
                    onChange={(e) => setInlineDescricaoLivre(e.target.value)}
                    disabled={!inlineIsCodigoGenerico || readOnly || !canWrite || inlineBusy}
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm disabled:opacity-60"
                    placeholder={inlineIsCodigoGenerico ? "Descricao livre do item para o orcamento" : ""}
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
                    <th className="px-3 py-3 text-right whitespace-nowrap">Desc (%)</th>
                    <th className="px-3 py-3 text-right whitespace-nowrap">Vlr Unit</th>
                    <th className="px-3 py-3 text-right whitespace-nowrap">Total</th>
                    <th className="px-3 py-3 text-right whitespace-nowrap">Estoque</th>
                    <th className="px-3 py-3 text-right whitespace-nowrap">Acoes</th>
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
                      <td className="px-3 py-2 whitespace-nowrap">{it.item_codigo_interno ?? "-"}</td>
                      <td className="px-3 py-2 min-w-[280px]">{it.item_nome}</td>
                      <td className="px-3 py-2 whitespace-nowrap">{it.unidade}</td>
                      <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{n(it.quantidade)}</td>
                      <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{n(it.desconto_item_percent)}</td>
                      <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{formatMoneyBR(n(it.valor_unitario_liquido))}</td>
                      <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{formatMoneyBR(n(it.valor_total))}</td>
                      <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">
                        {Number.isFinite(estoqueByItemId[Number(it.item_id)])
                          ? formatDecimalBR(estoqueByItemId[Number(it.item_id)])
                          : "-"}
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
                <span className="text-zinc-400">Total servicos</span>
                <span className="tabular-nums">{formatMoneyBR(n(orc.total_servicos))}</span>
              </div>
              <div className="flex items-center justify-between gap-2">
                <span className="text-zinc-400">Total despesas</span>
                <span className="tabular-nums">{formatMoneyBR(totalDespesas)}</span>
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
                <span className="text-zinc-400 font-medium">Total liquido</span>
                <span className="tabular-nums font-semibold">{formatMoneyBR(n(orc.total_liquido))}</span>
              </div>
              <div className="flex items-center justify-between gap-2">
                <span className="text-zinc-400">Valor fechado</span>
                <span className="tabular-nums">
                  {orc.valor_fechado === null || orc.valor_fechado === undefined ? "-" : formatMoneyBR(n(orc.valor_fechado))}
                </span>
              </div>
              <div className="flex items-center justify-between gap-2">
                <span className="text-zinc-400">Desconto fechamento</span>
                <span className="tabular-nums">
                  {orc.valor_fechado === null || orc.valor_fechado === undefined
                    ? "-"
                    : formatMoneyBR(n(orc.total_liquido) - n(orc.valor_fechado))}
                </span>
              </div>
            </div>
          </div>

          <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
            <label className="block text-xs text-zinc-400">
              Observacoes
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
            aria-label="Novo orcamento"
            className="w-full max-w-2xl max-h-[calc(100dvh-2rem)] bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden flex flex-col"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div className="font-semibold text-zinc-100">Novo orcamento</div>
              <div className="text-xs text-zinc-400 mt-1">Informe cliente e titulo para criar o rascunho.</div>
            </div>

            <div className="p-5 space-y-4 overflow-y-auto">
              {newDialog.error && <div className="text-sm text-red-400">{newDialog.error}</div>}

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <label className="block text-xs text-zinc-400 md:col-span-2">
                  Cliente (busca)
                  <input
                    value={newDialog.clienteTerm}
                    onChange={(e) =>
                      setNewDialog((p) =>
                        p.open
                          ? { ...p, clienteTerm: e.target.value, clienteSearchError: null }
                          : p
                      )
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="Digite nome ou ID..."
                  />
                </label>

                <div className="md:col-span-2">
                  <div className="text-xs text-zinc-400 mb-1">Resultados</div>
                  <div className="max-h-48 overflow-auto border border-zinc-800 rounded-md">
                    {newDialog.clienteLoading ? (
                      <div className="px-3 py-3 text-sm text-zinc-500">Buscando clientes...</div>
                    ) : newDialog.clienteSearchError ? (
                      <div className="px-3 py-3 text-sm text-red-400">{newDialog.clienteSearchError}</div>
                    ) : newDialog.clienteResults.length === 0 ? (
                      <div className="px-3 py-3 text-sm text-zinc-500">Sem resultados.</div>
                    ) : (
                      newDialog.clienteResults.map((c) => (
                        <button
                          type="button"
                          key={c.id}
                          onClick={() =>
                            setNewDialog((p) =>
                              p.open
                                ? {
                                    ...p,
                                    clienteId: c.id,
                                    clienteTerm: c.nome ?? String(c.id),
                                    contatoResults: [],
                                    contatoLoading: false,
                                    clienteSearchError: null,
                                  }
                                : p
                            )
                          }
                          className={
                            newDialog.clienteId === c.id
                              ? "w-full text-left px-3 py-2 text-sm bg-zinc-900/60"
                              : "w-full text-left px-3 py-2 text-sm hover:bg-zinc-900/40"
                          }
                        >
                          <span className="text-zinc-200">{c.nome ?? `#${c.id}`}</span>
                          <span className="text-zinc-400"> — {formatClienteDocumento(c.documento)}</span>
                          <span className="text-zinc-600"> · #{c.id}</span>
                        </button>
                      ))
                    )}
                  </div>
                </div>

                <label className="block text-xs text-zinc-400 md:col-span-2">
                  Titulo
                  <input
                    value={newDialog.titulo}
                    onChange={(e) =>
                      setNewDialog((p) => (p.open ? { ...p, titulo: e.target.value.toLocaleUpperCase("pt-BR") } : p))
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="Ex.: Proposta de manutencao"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Solicitante
                  <input
                    value={newDialog.solicitanteNome ?? ""}
                    onChange={(e) =>
                      setNewDialog((p) => (p.open ? { ...p, solicitanteNome: e.target.value.toLocaleUpperCase("pt-BR") } : p))
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="Nome do solicitante"
                    autoComplete="name"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Setor
                  <input
                    value={newDialog.solicitanteSetor ?? ""}
                    onChange={(e) =>
                      setNewDialog((p) => (p.open ? { ...p, solicitanteSetor: e.target.value.toLocaleUpperCase("pt-BR") } : p))
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="Setor"
                    autoComplete="organization-title"
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  E-mail
                  <input
                    type="email"
                    value={newDialog.solicitanteEmail ?? ""}
                    onChange={(e) =>
                      setNewDialog((p) => (p.open ? { ...p, solicitanteEmail: e.target.value.toLocaleLowerCase("pt-BR") } : p))
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="email@cliente.com.br"
                    autoComplete="email"
                  />
                </label>

                {(newDialog.contatoLoading || newDialog.contatoResults.length > 0) && (
                  <div className="md:col-span-2">
                    {newDialog.contatoLoading ? (
                      <div className="text-xs text-zinc-500">Carregando contatos...</div>
                    ) : (
                      <>
                        <div className="text-xs text-zinc-400 mb-1">Contatos sugeridos</div>
                        <div className="max-h-36 overflow-auto rounded-md border border-zinc-800">
                          {newDialog.contatoResults.map((contato) => {
                            const label = formatContatoSuggestion(contato) || `Contato #${contato.id}`;
                            return (
                              <button
                                type="button"
                                key={String(contato.id)}
                                onClick={() => applyContatoSuggestion(contato)}
                                title={label}
                                className="w-full text-left px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-900/40"
                              >
                                {label}
                              </button>
                            );
                          })}
                        </div>
                      </>
                    )}
                  </div>
                )}

                <label className="block text-xs text-zinc-400">
                  Telefone
                  <input
                    type="tel"
                    value={newDialog.solicitanteTelefone ?? ""}
                    onChange={(e) =>
                      setNewDialog((p) => (p.open ? { ...p, solicitanteTelefone: formatPhoneInput(e.target.value) } : p))
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="(00) 00000-0000"
                    inputMode="numeric"
                    maxLength={15}
                    autoComplete="tel"
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
                  Condicao de Pagamento
                  <select
                    value={newDialog.condicaoPagamentoId ?? ""}
                    onChange={(e) =>
                      setNewDialog((p) => (p.open ? { ...p, condicaoPagamentoId: e.target.value ? e.target.value : null } : p))
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                  >
                    <option value="">(Sem condicao)</option>
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

      {editClienteDialog.open && (
        <div
          className="fixed inset-0 z-[60] bg-black/70 backdrop-blur-sm flex items-start justify-center p-4"
          onClick={(e) => e.target === e.currentTarget && closeEditCliente()}
          role="presentation"
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-label="Alterar dados iniciais"
            className="w-full max-w-2xl max-h-[calc(100dvh-2rem)] bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden flex flex-col"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div className="font-semibold text-zinc-100">Alterar dados iniciais</div>
              <div className="text-xs text-zinc-400 mt-1">Altere cliente e informacoes iniciais do orcamento.</div>
            </div>

            <div className="p-5 space-y-4 overflow-y-auto">
              {editClienteDialog.error && <div className="text-sm text-red-400">{editClienteDialog.error}</div>}

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <label className="block text-xs text-zinc-400 md:col-span-2">
                  Cliente (busca)
                  <input
                    value={editClienteDialog.clienteTerm}
                    onChange={(e) =>
                      setEditClienteDialog((p) =>
                        p.open
                          ? { ...p, clienteTerm: e.target.value, error: null, clienteSearchError: null }
                          : p
                      )
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="Digite nome ou ID..."
                    disabled={editClienteDialog.busy}
                  />
                </label>

                <div className="md:col-span-2">
                  <div className="text-xs text-zinc-400 mb-1">Resultados</div>
                  <div className="max-h-48 overflow-auto border border-zinc-800 rounded-md">
                    {editClienteDialog.clienteLoading ? (
                      <div className="px-3 py-3 text-sm text-zinc-500">Buscando clientes...</div>
                    ) : editClienteDialog.clienteSearchError ? (
                      <div className="px-3 py-3 text-sm text-red-400">{editClienteDialog.clienteSearchError}</div>
                    ) : editClienteDialog.clienteResults.length === 0 ? (
                      <div className="px-3 py-3 text-sm text-zinc-500">Sem resultados.</div>
                    ) : (
                      editClienteDialog.clienteResults.map((c) => (
                        <button
                          type="button"
                          key={c.id}
                          onClick={() =>
                            setEditClienteDialog((p) =>
                              p.open
                                ? {
                                    ...p,
                                    clienteId: c.id,
                                    clienteTerm: c.nome ?? String(c.id),
                                    contatoResults: [],
                                    contatoLoading: false,
                                    clienteSearchError: null,
                                    error: null,
                                  }
                                : p
                            )
                          }
                          disabled={editClienteDialog.busy}
                          className={
                            editClienteDialog.clienteId === c.id
                              ? "w-full text-left px-3 py-2 text-sm bg-zinc-900/60"
                              : "w-full text-left px-3 py-2 text-sm hover:bg-zinc-900/40"
                          }
                        >
                          <span className="text-zinc-200">{c.nome ?? `#${c.id}`}</span>
                          <span className="text-zinc-400"> — {formatClienteDocumento(c.documento)}</span>
                          <span className="text-zinc-600"> · #{c.id}</span>
                        </button>
                      ))
                    )}
                  </div>
                </div>

                <label className="block text-xs text-zinc-400 md:col-span-2">
                  Titulo
                  <input
                    value={editClienteDialog.titulo}
                    onChange={(e) =>
                      setEditClienteDialog((p) =>
                        p.open ? { ...p, titulo: e.target.value.toLocaleUpperCase("pt-BR"), error: null } : p
                      )
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="Ex.: Proposta de manutencao"
                    disabled={editClienteDialog.busy}
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Solicitante
                  <input
                    value={editClienteDialog.solicitanteNome ?? ""}
                    onChange={(e) =>
                      setEditClienteDialog((p) =>
                        p.open ? { ...p, solicitanteNome: e.target.value.toLocaleUpperCase("pt-BR"), error: null } : p
                      )
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="Nome do solicitante"
                    autoComplete="name"
                    disabled={editClienteDialog.busy}
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Setor
                  <input
                    value={editClienteDialog.solicitanteSetor ?? ""}
                    onChange={(e) =>
                      setEditClienteDialog((p) =>
                        p.open ? { ...p, solicitanteSetor: e.target.value.toLocaleUpperCase("pt-BR"), error: null } : p
                      )
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="Setor"
                    autoComplete="organization-title"
                    disabled={editClienteDialog.busy}
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  E-mail
                  <input
                    type="email"
                    value={editClienteDialog.solicitanteEmail ?? ""}
                    onChange={(e) =>
                      setEditClienteDialog((p) =>
                        p.open ? { ...p, solicitanteEmail: e.target.value.toLocaleLowerCase("pt-BR"), error: null } : p
                      )
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="email@cliente.com.br"
                    autoComplete="email"
                    disabled={editClienteDialog.busy}
                  />
                </label>

                {(editClienteDialog.contatoLoading || editClienteDialog.contatoResults.length > 0) && (
                  <div className="md:col-span-2">
                    {editClienteDialog.contatoLoading ? (
                      <div className="text-xs text-zinc-500">Carregando contatos...</div>
                    ) : (
                      <>
                        <div className="text-xs text-zinc-400 mb-1">Contatos sugeridos</div>
                        <div className="max-h-36 overflow-auto rounded-md border border-zinc-800">
                          {editClienteDialog.contatoResults.map((contato) => {
                            const label = formatContatoSuggestion(contato) || `Contato #${contato.id}`;
                            return (
                              <button
                                type="button"
                                key={String(contato.id)}
                                onClick={() => applyEditContatoSuggestion(contato)}
                                title={label}
                                disabled={editClienteDialog.busy}
                                className="w-full text-left px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-900/40 disabled:opacity-60"
                              >
                                {label}
                              </button>
                            );
                          })}
                        </div>
                      </>
                    )}
                  </div>
                )}

                <label className="block text-xs text-zinc-400">
                  Telefone
                  <input
                    type="tel"
                    value={editClienteDialog.solicitanteTelefone ?? ""}
                    onChange={(e) =>
                      setEditClienteDialog((p) =>
                        p.open ? { ...p, solicitanteTelefone: formatPhoneInput(e.target.value), error: null } : p
                      )
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                    placeholder="(00) 00000-0000"
                    inputMode="numeric"
                    maxLength={15}
                    autoComplete="tel"
                    disabled={editClienteDialog.busy}
                  />
                </label>

                <label className="block text-xs text-zinc-400">
                  Vendedor
                  <select
                    value={editClienteDialog.vendedorUsuarioId}
                    onChange={(e) =>
                      setEditClienteDialog((p) => (p.open ? { ...p, vendedorUsuarioId: e.target.value, error: null } : p))
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                    disabled={editClienteDialog.busy}
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
                  Condicao de Pagamento
                  <select
                    value={editClienteDialog.condicaoPagamentoId ?? ""}
                    onChange={(e) =>
                      setEditClienteDialog((p) =>
                        p.open ? { ...p, condicaoPagamentoId: e.target.value ? e.target.value : null, error: null } : p
                      )
                    }
                    className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-2 py-2 text-sm"
                    disabled={editClienteDialog.busy}
                  >
                    <option value="">(Sem condicao)</option>
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
                onClick={closeEditCliente}
                disabled={editClienteDialog.busy}
                className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-60"
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={() => void submitEditCliente()}
                disabled={editClienteDialog.busy}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
              >
                Alterar
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
                  Valor unitario (R$)
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

      {statusDialog.open && (
        <OrcamentoStatusDialog
          open={statusDialog.open}
          status={statusDialog.status}
          loading={busy}
          initialFollowup={orc?.observacoes}
          initialValorFechado={orc?.valor_fechado}
          valorOrcado={orc?.total_liquido}
          canOpenOs={canOpenOs}
          onCancel={closeStatusDialog}
          onSave={saveStatusDialog}
        />
      )}
      {confirmDialog}
      </div>
  );
}


