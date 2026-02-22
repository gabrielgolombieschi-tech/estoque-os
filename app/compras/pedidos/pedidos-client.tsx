"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { supabaseBrowser } from "@/lib/supabase/client";

type FornPend = {
  fornecedor_id: number | null;
  fornecedor_nome: string;
  qtd_pendencias_abertas: number;
  qtd_total_pendente: number;
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
  created_at: string;
  total_geral: number;
};

type PedidoItem = {
  id: string;
  item_id: number | null;
  item_codigo?: string | null;
  item_nome: string;
  unidade: string;
  quantidade: number;
  quantidade_recebida: number;
  valor_unitario: number;
  valor_total: number;
};

async function authedFetch(path: string, init?: RequestInit) {
  const supabase = supabaseBrowser();
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error("Sessao expirada.");
  const res = await fetch(path, {
    ...init,
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(String((json as { error?: string }).error ?? "Erro de requisicao."));
  return json as Record<string, unknown>;
}

function parseNum(v: unknown, def = 0) {
  const n = Number(v ?? def);
  return Number.isFinite(n) ? n : def;
}

function parseQtyInput(v: string) {
  const n = Number(String(v ?? "").replace(",", ".").trim());
  return Number.isFinite(n) ? n : null;
}

function parseMoneyInput(v: string) {
  const n = Number(String(v ?? "").replace(",", ".").trim());
  return Number.isFinite(n) ? n : null;
}

function fmtMoney(v: number) {
  return Number(v ?? 0).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
}

function fmtDate(v: string) {
  const d = new Date(v);
  if (!Number.isFinite(d.getTime())) return "-";
  return d.toLocaleDateString("pt-BR");
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

export default function ComprasPedidosClient() {
  const te = useTenantEmpresa();
  const tenantId = te.tenantId ?? "";
  const empresaId = te.empresaId ?? te.empresas[0]?.id ?? "";

  const [tab, setTab] = useState<"comprar" | "pedidos">("comprar");
  const [modo, setModo] = useState<"DETALHADO" | "AGRUPADO">("AGRUPADO");
  const [fornecedores, setFornecedores] = useState<FornPend[]>([]);
  const [fornecedorId, setFornecedorId] = useState<number | null>(null);
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
  const [statusFiltro, setStatusFiltro] = useState("");
  const [manualPedidoId, setManualPedidoId] = useState<string>("");
  const [manualNome, setManualNome] = useState("");
  const [manualUnidade, setManualUnidade] = useState("UN");
  const [manualQtd, setManualQtd] = useState("1");
  const [manualValor, setManualValor] = useState("0");
  const [pedidoItens, setPedidoItens] = useState<PedidoItem[]>([]);
  const [itemDrafts, setItemDrafts] = useState<Record<string, { item_nome: string; unidade: string; quantidade: string; valor_unitario: string }>>({});
  const [deleteTarget, setDeleteTarget] = useState<{ id: string; nome: string } | null>(null);
  const [autoScanTried, setAutoScanTried] = useState(false);

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
  const canWriteByRole = ["ADMIN", "COORDENACAO", "COMPRAS"].includes(empresaRole);

  const canRead =
    te.has("compras.read") || te.has("compras.write") || te.has("compras.approve") || te.has("compras.receive") || canReadByRole;
  const canWrite = te.has("compras.write") || canWriteByRole;

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

      if (!tenantId || !empresaId || !canRead || fornecedorId == null) {
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
    [canRead, empresaId, fornecedorId, tenantId]
  );

  const loadFornecedores = useCallback(async () => {
    if (!tenantId || !empresaId || !canRead) return;
    const json = await authedFetch(`/api/compras/fornecedores-pendentes?${ctxQuery}`);
    const rows = (json.data as FornPend[]) ?? [];
    setFornecedores(rows);
    if (rows.length && fornecedorId == null) setFornecedorId(rows[0].fornecedor_id);
  }, [canRead, ctxQuery, empresaId, fornecedorId, tenantId]);

  const loadPendencias = useCallback(async () => {
    if (!tenantId || !empresaId || !canRead || fornecedorId == null) return;
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
  }, [canRead, ctxQuery, empresaId, fornecedorId, loadUltimosValoresDetalhado, modo, rowKey, tenantId]);

  const loadPedidos = useCallback(async () => {
    if (!tenantId || !empresaId || !canRead) return;
    const statusQ = statusFiltro ? `&status=${encodeURIComponent(statusFiltro)}` : "";
    const json = await authedFetch(`/api/compras/pedidos?${ctxQuery}${statusQ}`);
    const rows = (json.data as Pedido[]) ?? [];
    setPedidos(rows);
    if (!manualPedidoId && rows[0]?.id) setManualPedidoId(rows[0].id);
  }, [canRead, ctxQuery, empresaId, manualPedidoId, statusFiltro, tenantId]);

  const loadPedidoItens = useCallback(async () => {
    if (!tenantId || !empresaId || !canRead || !manualPedidoId) {
      setPedidoItens([]);
      setItemDrafts({});
      return;
    }
    const json = await authedFetch(`/api/compras/pedidos/${manualPedidoId}?${ctxQuery}`);
    const itens = ((json.data as { itens?: PedidoItem[] })?.itens ?? []) as PedidoItem[];
    setPedidoItens(itens);
    const nextDrafts: Record<string, { item_nome: string; unidade: string; quantidade: string; valor_unitario: string }> = {};
    for (const it of itens) {
      nextDrafts[it.id] = {
        item_nome: String(it.item_nome ?? ""),
        unidade: String(it.unidade ?? "UN"),
        quantidade: String(it.quantidade ?? 0),
        valor_unitario: String(it.valor_unitario ?? 0),
      };
    }
    setItemDrafts(nextDrafts);
  }, [canRead, ctxQuery, empresaId, manualPedidoId, tenantId]);

  const selectedPedido = useMemo(
    () => pedidos.find((p) => p.id === manualPedidoId) ?? null,
    [manualPedidoId, pedidos]
  );
  const canEditManualItems = useMemo(() => {
    const st = String(selectedPedido?.status ?? "").toUpperCase();
    return ["RASCUNHO", "AGUARDANDO_APROVACAO", "REPROVADO"].includes(st);
  }, [selectedPedido?.status]);

  useEffect(() => {
    void loadFornecedores();
  }, [loadFornecedores]);

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
    if (!osNumero) return setErr("Informe a OS para vincular o item livre.");
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
          origem_tipo: "OS",
          origem_os_numero: osNumero,
          item_id: null,
          item_nome: itemNome,
          unidade,
          quantidade: qtd,
          prioridade: "MEDIA",
          observacoes: "ITEM LIVRE (CODIGO GENERICO 9999)",
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
        origem_tipo: "OS",
        numero_os: osNumero,
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
      setOk(`Item livre incluido e vinculado a OS ${osNumero}.`);
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

  const addManualItem = useCallback(async () => {
    if (!manualPedidoId) {
      setErr("Selecione um pedido.");
      return;
    }
    const qtd = parseNum(manualQtd, 0);
    const vlr = parseNum(manualValor, 0);
    if (!manualNome.trim()) {
      setErr("Informe o nome do item manual.");
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
          item_nome: manualNome,
          unidade: manualUnidade || "UN",
          quantidade: qtd,
          valor_unitario: vlr,
        }),
      });
      setOk("Item manual adicionado ao pedido.");
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
  }, [empresaId, loadPedidoItens, loadPedidos, manualNome, manualPedidoId, manualQtd, manualUnidade, manualValor, tenantId]);

  const salvarItemManual = useCallback(
    async (itemId: string) => {
      if (!manualPedidoId) return;
      const draft = itemDrafts[itemId];
      if (!draft) return;
      const qtd = parseNum(draft.quantidade, 0);
      const vlr = parseNum(draft.valor_unitario, 0);
      if (!draft.item_nome.trim()) return setErr("Descricao do item manual obrigatoria.");
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
          }),
        });
        setOk("Item manual atualizado.");
        await loadPedidoItens();
        await loadPedidos();
      } catch (e: unknown) {
        setErr(e instanceof Error ? e.message : "Erro ao atualizar item manual.");
      } finally {
        setBusy(false);
      }
    },
    [empresaId, itemDrafts, loadPedidoItens, loadPedidos, manualPedidoId, tenantId]
  );

  const excluirItemManual = useCallback(
    async (itemId: string) => {
      if (!manualPedidoId) return;
      setBusy(true);
      setErr(null);
      setOk(null);
      try {
        await authedFetch(`/api/compras/pedidos/${manualPedidoId}/itens/${itemId}?${ctxQuery}`, {
          method: "DELETE",
        });
        setOk("Item manual excluido.");
        await loadPedidoItens();
        await loadPedidos();
      } catch (e: unknown) {
        setErr(e instanceof Error ? e.message : "Erro ao excluir item manual.");
      } finally {
        setBusy(false);
      }
    },
    [ctxQuery, loadPedidoItens, loadPedidos, manualPedidoId]
  );

  if (!tenantId || !empresaId) return <div className="text-zinc-400">Carregando contexto...</div>;
  if (!canRead) return <div className="text-zinc-400">Sem permissao para Compras.</div>;

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <button className={tab === "comprar" ? "px-3 py-2 rounded bg-zinc-100 text-zinc-900" : "px-3 py-2 rounded border border-zinc-800"} onClick={() => setTab("comprar")}>Comprar por Fornecedor</button>
        <button className={tab === "pedidos" ? "px-3 py-2 rounded bg-zinc-100 text-zinc-900" : "px-3 py-2 rounded border border-zinc-800"} onClick={() => setTab("pedidos")}>Pedidos</button>
      </div>

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
                          <td>OS</td>
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
                              placeholder="Numero OS"
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

      {tab === "pedidos" && (
        <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-3 space-y-3">
          <div className="flex items-center gap-2">
            <select
              className="px-2 py-1 rounded border border-zinc-800 bg-zinc-950"
              value={statusFiltro}
              onChange={(e) => setStatusFiltro(e.target.value)}
            >
              <option value="">Todos status</option>
              <option>RASCUNHO</option>
              <option>AGUARDANDO_APROVACAO</option>
              <option>APROVADO</option>
              <option>REPROVADO</option>
              <option>ENVIADO</option>
              <option>PARCIAL_RECEBIDO</option>
              <option>RECEBIDO</option>
              <option>CANCELADO</option>
            </select>
            <button className="px-3 py-1 rounded border border-zinc-800" onClick={() => void loadPedidos()}>
              Atualizar
            </button>
            <div className="ml-auto text-xs text-zinc-400">{pedidos.length} pedido(s)</div>
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
                    {pedidos.map((p) => {
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
                              {String(p.status ?? "-")}
                            </span>
                          </td>
                          <td className="py-2 px-3 text-right tabular-nums">{fmtMoney(Number(p.total_geral ?? 0))}</td>
                        </tr>
                      );
                    })}
                    {!pedidos.length && (
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
                      {String(selectedPedido.status ?? "-")}
                    </span>
                    <div className="text-xs text-zinc-500">
                      {String(selectedPedido.fornecedor_nome ?? "").trim() || "SEM FORNECEDOR"}
                    </div>
                    <div className="ml-auto text-sm font-medium">{fmtMoney(Number(selectedPedido.total_geral ?? 0))}</div>
                  </div>

                  <div className="flex items-center gap-1 flex-wrap">
                    <button className="px-2 py-1 rounded border border-zinc-800" onClick={() => void transicionarPedido(selectedPedido.id, "enviar-aprovacao")}>Solic. Aprov.</button>
                    <button className="px-2 py-1 rounded border border-zinc-800" onClick={() => void transicionarPedido(selectedPedido.id, "aprovar")}>Aprovar</button>
                    <button className="px-2 py-1 rounded border border-zinc-800" onClick={() => void transicionarPedido(selectedPedido.id, "reprovar", { motivo: "Reprovado via tela" })}>Reprovar</button>
                    <button className="px-2 py-1 rounded border border-zinc-800" onClick={() => void transicionarPedido(selectedPedido.id, "enviar")}>Enviar</button>
                    <button className="px-2 py-1 rounded border border-zinc-800" onClick={() => void receberTotal(selectedPedido.id)}>Receber</button>
                    <button className="px-2 py-1 rounded border border-zinc-800" onClick={() => void transicionarPedido(selectedPedido.id, "cancelar", { motivo: "Cancelado via tela" })}>Cancelar</button>
                  </div>

                  <div className="rounded border border-zinc-800 p-3 space-y-2">
                    <div className="text-sm font-medium">Adicionar item manual no pedido</div>
                    <div className="grid grid-cols-1 md:grid-cols-5 gap-2">
                      <input className="px-2 py-2 rounded border border-zinc-800 bg-zinc-950 md:col-span-2 disabled:opacity-50" placeholder="Descricao do item" value={manualNome} disabled={!canEditManualItems || !canWrite} onChange={(e) => setManualNome(e.target.value)} />
                      <input className="px-2 py-2 rounded border border-zinc-800 bg-zinc-950 disabled:opacity-50" placeholder="UN" value={manualUnidade} disabled={!canEditManualItems || !canWrite} onChange={(e) => setManualUnidade(e.target.value)} />
                      <input className="px-2 py-2 rounded border border-zinc-800 bg-zinc-950 disabled:opacity-50" placeholder="Qtd" value={manualQtd} disabled={!canEditManualItems || !canWrite} onChange={(e) => setManualQtd(e.target.value)} />
                      <input className="px-2 py-2 rounded border border-zinc-800 bg-zinc-950 disabled:opacity-50" placeholder="Valor unitario" value={manualValor} disabled={!canEditManualItems || !canWrite} onChange={(e) => setManualValor(e.target.value)} />
                    </div>
                    <button className="px-3 py-2 rounded border border-zinc-800 disabled:opacity-50" onClick={() => void addManualItem()} disabled={busy || !canWrite || !canEditManualItems}>
                      Adicionar item
                    </button>
                    {!canEditManualItems ? (
                      <div className="text-xs text-amber-300">
                        Pedido em status {String(selectedPedido.status ?? "-")} nao permite incluir/editar/excluir item manual.
                      </div>
                    ) : null}
                  </div>

                  <div className="rounded border border-zinc-800 p-3 space-y-2">
                    <div className="text-sm font-medium">Itens do pedido selecionado</div>
                    <div className="overflow-x-auto">
                      <table className="w-full text-sm min-w-[860px]">
                        <thead>
                          <tr className="text-left text-zinc-300">
                            <th className="py-2">Tipo</th>
                            <th>ID</th>
                            <th>Codigo</th>
                            <th>Descricao</th>
                            <th>Unid</th>
                            <th>Qtd</th>
                            <th>Vlr unit</th>
                            <th className="text-center min-w-[130px] px-3">Total</th>
                            <th className="text-center min-w-[170px] px-3">Acoes</th>
                          </tr>
                        </thead>
                        <tbody>
                          {pedidoItens.map((it) => {
                            const isManual = it.item_id == null;
                            const draft = itemDrafts[it.id] ?? {
                              item_nome: it.item_nome,
                              unidade: it.unidade,
                              quantidade: String(it.quantidade),
                              valor_unitario: String(it.valor_unitario),
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
                                    disabled={!isManual || !canWrite || !canEditManualItems}
                                    onChange={(e) =>
                                      setItemDrafts((prev) => ({ ...prev, [it.id]: { ...draft, item_nome: e.target.value } }))
                                    }
                                  />
                                </td>
                                <td>
                                  <input
                                    className="px-2 py-1 rounded border border-zinc-800 bg-zinc-950 w-20"
                                    value={draft.unidade}
                                    disabled={!isManual || !canWrite || !canEditManualItems}
                                    onChange={(e) =>
                                      setItemDrafts((prev) => ({ ...prev, [it.id]: { ...draft, unidade: e.target.value } }))
                                    }
                                  />
                                </td>
                                <td>
                                  <input
                                    className="px-2 py-1 rounded border border-zinc-800 bg-zinc-950 w-24"
                                    value={draft.quantidade}
                                    disabled={!isManual || !canWrite || !canEditManualItems}
                                    onChange={(e) =>
                                      setItemDrafts((prev) => ({ ...prev, [it.id]: { ...draft, quantidade: e.target.value } }))
                                    }
                                  />
                                </td>
                                <td>
                                  <input
                                    className="px-2 py-1 rounded border border-zinc-800 bg-zinc-950 w-28"
                                    value={draft.valor_unitario}
                                    disabled={!isManual || !canWrite || !canEditManualItems}
                                    onChange={(e) =>
                                      setItemDrafts((prev) => ({ ...prev, [it.id]: { ...draft, valor_unitario: e.target.value } }))
                                    }
                                  />
                                </td>
                                <td className="text-center tabular-nums whitespace-nowrap px-3">{fmtMoney(Number(it.valor_total ?? 0))}</td>
                                <td className="px-3">
                                  {isManual ? (
                                    <div className="flex items-center justify-center gap-1">
                                      <button className="px-2 py-1 rounded border border-zinc-800 disabled:opacity-50" disabled={busy || !canWrite || !canEditManualItems} onClick={() => void salvarItemManual(it.id)}>Salvar</button>
                                      <button
                                        className="px-2 py-1 rounded border border-red-900 text-red-300 disabled:opacity-50"
                                        disabled={busy || !canWrite || !canEditManualItems}
                                        onClick={() => setDeleteTarget({ id: it.id, nome: draft.item_nome || "ITEM MANUAL" })}
                                      >
                                        Excluir
                                      </button>
                                    </div>
                                  ) : (
                                    <div className="text-center">
                                      <span className="text-xs text-zinc-500">Item de pendencia</span>
                                    </div>
                                  )}
                                </td>
                              </tr>
                            );
                          })}
                          {!pedidoItens.length && (
                            <tr>
                              <td className="py-3 text-zinc-500" colSpan={9}>Nenhum item no pedido selecionado.</td>
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
              Excluir item manual <span className="font-medium">{deleteTarget.nome}</span>?
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
                  if (target) await excluirItemManual(target.id);
                }}
                disabled={busy}
              >
                Confirmar exclusao
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
