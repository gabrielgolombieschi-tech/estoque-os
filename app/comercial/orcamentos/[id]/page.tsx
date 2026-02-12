"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { useParams, useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import { formatMoneyBR } from "@/lib/decimal";
import type { ItemLookupRow, OrcamentoItemRow, OrcamentoRow, OrcamentoStatus, UsuarioLookupRow } from "@/lib/comercial/types";
import { isOrcamentoReadOnly, mapOrcamentoError, n, toSupabaseErrorLike, upperTrim } from "@/lib/comercial/utils";
import {
  addItem,
  cancelarOrcamento,
  createOrcamento,
  deleteItem,
  finalizarOrcamento,
  getOrcamento,
  getOrcamentoConfig,
  getUsuarioIdByAuthUserId,
  listCondicoesPagamentoAtivas,
  listVendedores,
  searchClientes,
  searchItens,
  updateItem,
  updateOrcamento,
} from "@/lib/comercial/orcamentos.service";

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
      mode: "add" | "edit";
      itemTerm: string;
      itemResults: ItemLookupRow[];
      selectedItem: ItemLookupRow | null;
      quantidade: string;
      valorUnitario: string;
      descontoItemPercent: string;
      editingId: string | null;
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
  const [condicoes, setCondicoes] = useState<Array<{ id: string; nome: string | null }>>([]);
  const [vendedores, setVendedores] = useState<UsuarioLookupRow[]>([]);

  const [newDialog, setNewDialog] = useState<NewDialogState>(closedNewDialog);
  const newClienteReqRef = useRef(0);

  const [itemDialog, setItemDialog] = useState<ItemDialogState>(closedItemDialog);
  const itemReqRef = useRef(0);

  const { confirm, dialog: confirmDialog } = useConfirmDialog();

  const status = String(orc?.status ?? "").toUpperCase() as OrcamentoStatus | string;
  const readOnly = isOrcamentoReadOnly(status);

  const loadLookups = useCallback(async () => {
    if (!supabase || !tenantId || !empresaId) return;

    try {
      const [cfg, cps, vends] = await Promise.all([
        getOrcamentoConfig(supabase, { tenantId, empresaId }),
        listCondicoesPagamentoAtivas(supabase, { tenantId, empresaId }),
        listVendedores(supabase),
      ]);
      setCfgDescontoMax(n(cfg.desconto_max_percent));
      setCfgCondPadraoId(cfg.condicao_pagamento_padrao_id ?? null);
      setCondicoes(cps.map((c) => ({ id: c.id, nome: c.nome ?? null })));
      setVendedores(vends);
    } catch {
      setCfgDescontoMax(0);
      setCfgCondPadraoId(null);
      setCondicoes([]);
      setVendedores([]);
    }
  }, [empresaId, supabase, tenantId]);

  const reload = useCallback(async () => {
    setErr(null);
    setOk(null);

    if (!supabase) return;
    if (te.loading) return;

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
      const { orcamento, itens } = await getOrcamento(supabase, { tenantId, empresaId, id: idParam });
      setOrc(orcamento);
      setItens(itens);
      setForm(formFromRow(orcamento));
    } catch (e: unknown) {
      setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao carregar orçamento."));
      setOrc(null);
      setItens([]);
      setForm(null);
    } finally {
      setLoading(false);
    }
  }, [empresaId, idParam, supabase, te.loading, tenantId]);

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

  // search itens
  useEffect(() => {
    if (!itemDialog.open) return;
    if (!supabase || !tenantId || !empresaId) return;

    const term = itemDialog.itemTerm.trim();
    const reqId = ++itemReqRef.current;
    const t = setTimeout(async () => {
      try {
        if (!term) {
          if (reqId === itemReqRef.current) {
            setItemDialog((p) => (p.open ? { ...p, itemResults: [] } : p));
          }
          return;
        }
        const res = await searchItens(supabase, { tenantId, empresaId, term });
        if (reqId === itemReqRef.current) {
          setItemDialog((p) => (p.open ? { ...p, itemResults: res } : p));
        }
      } catch {
        if (reqId === itemReqRef.current) {
          setItemDialog((p) => (p.open ? { ...p, itemResults: [] } : p));
        }
      }
    }, 250);

    return () => clearTimeout(t);
  }, [empresaId, itemDialog, supabase, tenantId]);

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
      const id = await createOrcamento(supabase, {
        tenantId,
        empresaId,
        titulo,
        clienteId,
        vendedorUsuarioId,
        condicaoPagamentoId: newDialog.condicaoPagamentoId ?? null,
      });
      setNewDialog(closedNewDialog());
      router.replace(`/comercial/orcamentos/${id}`);
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

  const openAddItem = useCallback(() => {
    if (readOnly || !canWrite) return;
    setItemDialog({
      open: true,
      mode: "add",
      itemTerm: "",
      itemResults: [],
      selectedItem: null,
      quantidade: "1",
      valorUnitario: "0",
      descontoItemPercent: "0",
      editingId: null,
      busy: false,
      error: null,
    });
  }, [canWrite, readOnly]);

  const openEditItem = useCallback(
    (it: OrcamentoItemRow) => {
      if (readOnly || !canWrite) return;
      setItemDialog({
        open: true,
        mode: "edit",
        itemTerm: "",
        itemResults: [],
        selectedItem: {
          id: it.item_id,
          nome: it.item_nome,
          tipo: String(it.item_tipo ?? "").toLowerCase(),
          unidade_medida: it.unidade,
          preco_unitario: it.valor_unitario,
          ativo: true,
        },
        quantidade: String(it.quantidade ?? "1"),
        valorUnitario: String(it.valor_unitario ?? "0"),
        descontoItemPercent: String(it.desconto_item_percent ?? "0"),
        editingId: it.id,
        busy: false,
        error: null,
      });
    },
    [canWrite, readOnly]
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

    if (itemDialog.mode === "add") {
      if (!itemDialog.selectedItem?.id) {
        setItemDialog((p) => (p.open ? { ...p, error: "Selecione um item." } : p));
        return;
      }

      setItemDialog((p) => (p.open ? { ...p, busy: true, error: null } : p));
      try {
        await addItem(supabase, {
          tenantId,
          empresaId,
          orcamentoId: orc.id,
          itemId: itemDialog.selectedItem.id,
          quantidade: qty,
          valorUnitario: vu,
          descontoItemPercent: desc,
        });
        setItemDialog(closedItemDialog());
        await reload();
      } catch (e: unknown) {
        setItemDialog((p) =>
          p.open
            ? { ...p, busy: false, error: mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao adicionar item.") }
            : p
        );
      }
      return;
    }

    // edit
    if (!itemDialog.editingId) return;
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

            <label className="block text-xs text-zinc-400">
              Observações
              <textarea
                value={form.observacoes}
                disabled={readOnly || !canWrite}
                onChange={(e) => setForm((p) => (p ? { ...p, observacoes: e.target.value } : p))}
                className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm min-h-24 disabled:opacity-60"
              />
            </label>

            <div className="flex items-center gap-2">
              <button
                type="submit"
                disabled={readOnly || !canWrite || busy}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium text-sm disabled:opacity-60"
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
              {readOnly && <span className="text-xs text-zinc-500">Edição bloqueada (status {status}).</span>}
            </div>
          </div>

          <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
            <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between gap-2">
              <div className="font-medium">Itens</div>
              <button
                type="button"
                onClick={openAddItem}
                disabled={readOnly || !canWrite}
                className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white text-sm font-medium disabled:opacity-60"
              >
                Adicionar item
              </button>
            </div>

            <div className="overflow-auto">
              <table className="w-full text-sm">
                <thead className="bg-zinc-900/70">
                  <tr className="text-zinc-200">
                    <th className="px-3 py-3 text-left whitespace-nowrap">Seq</th>
                    <th className="px-3 py-3 text-left whitespace-nowrap">Item</th>
                    <th className="px-3 py-3 text-left whitespace-nowrap">Tipo</th>
                    <th className="px-3 py-3 text-left whitespace-nowrap">Unid</th>
                    <th className="px-3 py-3 text-right whitespace-nowrap">Qtd</th>
                    <th className="px-3 py-3 text-right whitespace-nowrap">Vlr Unit</th>
                    <th className="px-3 py-3 text-right whitespace-nowrap">Desc (%)</th>
                    <th className="px-3 py-3 text-right whitespace-nowrap">Total</th>
                    <th className="px-3 py-3 text-right whitespace-nowrap">Ações</th>
                  </tr>
                </thead>
                <tbody>
                  {itens.length === 0 && (
                    <tr>
                      <td colSpan={9} className="px-3 py-6 text-zinc-400">
                        Nenhum item.
                      </td>
                    </tr>
                  )}
                  {itens.map((it) => (
                    <tr key={it.id} className="border-t border-zinc-900/60 hover:bg-zinc-900/30">
                      <td className="px-3 py-2 whitespace-nowrap">{it.seq}</td>
                      <td className="px-3 py-2 min-w-[280px]">{it.item_nome}</td>
                      <td className="px-3 py-2 whitespace-nowrap">{String(it.item_tipo ?? "").toUpperCase()}</td>
                      <td className="px-3 py-2 whitespace-nowrap">{it.unidade}</td>
                      <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{n(it.quantidade)}</td>
                      <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{formatMoneyBR(n(it.valor_unitario))}</td>
                      <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{n(it.desconto_item_percent)}</td>
                      <td className="px-3 py-2 text-right tabular-nums whitespace-nowrap">{formatMoneyBR(n(it.valor_total))}</td>
                      <td className="px-3 py-2 text-right whitespace-nowrap">
                        <div className="inline-flex items-center gap-2">
                          <button
                            type="button"
                            onClick={() => openEditItem(it)}
                            disabled={readOnly || !canWrite}
                            className="px-3 py-1.5 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 disabled:opacity-60"
                          >
                            Editar
                          </button>
                          <button
                            type="button"
                            onClick={() => void doDeleteItem(it)}
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
            aria-label={itemDialog.mode === "add" ? "Adicionar item" : "Editar item"}
            className="w-full max-w-3xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="px-5 py-4 border-b border-zinc-900/80 bg-zinc-900/40">
              <div className="font-semibold text-zinc-100">{itemDialog.mode === "add" ? "Adicionar item" : "Editar item"}</div>
              <div className="text-xs text-zinc-400 mt-1">Produtos e serviços ativos.</div>
            </div>

            <div className="p-5 space-y-4">
              {itemDialog.error && <div className="text-sm text-red-400">{itemDialog.error}</div>}

              {itemDialog.mode === "add" && (
                <>
                  <label className="block text-xs text-zinc-400">
                    Item (busca)
                    <input
                      value={itemDialog.itemTerm}
                      onChange={(e) => setItemDialog((p) => (p.open ? { ...p, itemTerm: e.target.value } : p))}
                      className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm"
                      placeholder="Digite nome ou ID..."
                    />
                  </label>

                  <div>
                    <div className="text-xs text-zinc-400 mb-1">Resultados</div>
                    <div className="max-h-56 overflow-auto border border-zinc-800 rounded-md">
                      {itemDialog.itemResults.length === 0 ? (
                        <div className="px-3 py-3 text-sm text-zinc-500">Sem resultados.</div>
                      ) : (
                        itemDialog.itemResults.map((it) => (
                          <button
                            type="button"
                            key={it.id}
                            onClick={() =>
                              setItemDialog((p) =>
                                p.open
                                  ? {
                                      ...p,
                                      selectedItem: it,
                                      valorUnitario: String(it.preco_unitario ?? "0"),
                                    }
                                  : p
                              )
                            }
                            className={
                              itemDialog.selectedItem?.id === it.id
                                ? "w-full text-left px-3 py-2 text-sm bg-zinc-900/60"
                                : "w-full text-left px-3 py-2 text-sm hover:bg-zinc-900/40"
                            }
                          >
                            <span className="text-zinc-200">{it.nome ?? `#${it.id}`}</span>
                            <span className="text-zinc-500"> — #{it.id}</span>
                            {it.tipo ? <span className="text-zinc-500"> — {String(it.tipo).toUpperCase()}</span> : null}
                          </button>
                        ))
                      )}
                    </div>
                  </div>
                </>
              )}

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
