"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { formatMoneyBR } from "@/lib/decimal";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import type { OrcamentoListaRow, OrcamentoStatus } from "@/lib/comercial/types";
import type { OrcamentoStatusCanonical } from "@/lib/comercial/status";
import { getOrcamentoStatusLabel, normalizeOrcamentoStatus } from "@/lib/comercial/status";
import { mapOrcamentoError, n, toSupabaseErrorLike } from "@/lib/comercial/utils";
import {
  atualizarStatusOrcamento,
  getPedidoCompraOrcamento,
  listOrcamentos,
  listOrcamentosAgrupadoCliente,
  listOrcamentosDoCliente,
  type OrcamentoGrupoCliente,
} from "@/lib/comercial/orcamentos.service";
import OrcamentoStatusDialog, { type OrcamentoStatusDialogPayload } from "./OrcamentoStatusDialog";

const PAGE_SIZE = 50;
const STATUS_OPTIONS: Array<{ value: OrcamentoStatus | "TODOS"; label: string }> = [
  { value: "TODOS", label: "Todos" },
  { value: "ANDAMENTO", label: "Andamento" },
  { value: "FECHADO", label: "Fechado" },
  { value: "PERDIDO", label: "Perdido" },
];

/** Como o filtro se le no subtitulo, na mesma forma da tela de OS ("74 em andamento"). */
function rotuloSituacao(status: OrcamentoStatus | "TODOS"): string {
  if (status === "ANDAMENTO") return "em andamento";
  if (status === "FECHADO") return "fechados";
  if (status === "PERDIDO") return "perdidos";
  return "no total";
}

type StatusDialogState =
  | { open: false }
  | { open: true; row: OrcamentoListaRow; status: OrcamentoStatusCanonical };

function formatDateBR(iso?: string | null) {
  if (!iso) return "-";
  const [y, m, d] = String(iso).slice(0, 10).split("-");
  if (!y || !m || !d) return String(iso);
  return `${d}/${m}/${y}`;
}

function truncateFollowup(value: string, max = 70): string {
  if (value.length <= max) return value;
  return `${value.slice(0, max - 1)}...`;
}

function hasAny(caps: Capabilities | null, keys: CapabilityKey[]): boolean {
  return requireAny(caps, keys);
}

function statusColor(status: string): string {
  const canonical = normalizeOrcamentoStatus(status);
  if (canonical === "FECHADO") return "var(--carteira-green)";
  if (canonical === "PERDIDO") return "var(--carteira-red)";
  return "var(--carteira-amber)";
}

function ResumoCard({ titulo, valor, detalhe }: { titulo: string; valor: string; detalhe: string }) {
  return (
    <article className="carteira-surface min-h-[96px] min-w-0 rounded-xl border px-4 py-3.5">
      <div className="carteira-muted font-mono text-[9px] font-bold uppercase tracking-[0.11em]">{titulo}</div>
      <div className="carteira-text mt-3 font-mono text-[20px] font-bold leading-none tabular-nums">{valor}</div>
      <div className="carteira-muted mt-2 text-[10px]">{detalhe}</div>
    </article>
  );
}

export default function OrcamentosClient() {
  const router = useRouter();
  const te = useTenantEmpresa();
  const { loading: permissionsLoading, ready, capabilities } = usePermissions();

  const canView = hasAny(capabilities, ["financeiro.read", "financeiro.write", "os.read", "os.write"]);
  const canWrite = hasAny(capabilities, ["financeiro.write", "os.write"]);
  const canOpenOs = hasAny(capabilities, ["os.write"]);

  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

  const tenantId = te.tenantId;
  const empresaId = te.empresaId;

  const [rows, setRows] = useState<OrcamentoListaRow[]>([]);
  const [count, setCount] = useState(0);

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [ultimoFollowupById, setUltimoFollowupById] = useState<Record<string, string>>({});

  const [q, setQ] = useState("");
  const [status, setStatus] = useState<OrcamentoStatus | "TODOS">("ANDAMENTO");
  const [from, setFrom] = useState<string>("");
  const [to, setTo] = useState<string>("");
  const [page, setPage] = useState(1);

  const totalPages = Math.max(1, Math.ceil(count / PAGE_SIZE));
  const pageSafe = Math.min(Math.max(1, page), totalPages);
  const [statusDialog, setStatusDialog] = useState<StatusDialogState>({ open: false });

  // Visao "Por cliente", igual a de ordens de servico. Os totais vem do servidor
  // (m.fn_orcamento_agrupado_cliente) porque a lista pagina: somar as linhas da
  // pagina daria o total dela, nao o do cliente.
  const [vista, setVista] = useState<"lista" | "cliente">("lista");
  const [grupos, setGrupos] = useState<OrcamentoGrupoCliente[]>([]);
  const [gruposLoading, setGruposLoading] = useState(true);
  const [ordem, setOrdem] = useState("valor");
  const listaRequest = useRef(0);
  const gruposRequest = useRef(0);
  const clientesRequest = useRef(0);
  const [gruposAbertos, setGruposAbertos] = useState<Set<string>>(new Set());
  const [orcamentosPorCliente, setOrcamentosPorCliente] = useState<Record<string, OrcamentoListaRow[]>>({});
  const [clientesCarregando, setClientesCarregando] = useState<Set<string>>(new Set());

  const chaveCliente = (clienteId: number | null) => (clienteId === null ? "sem-cliente" : String(clienteId));

  const reload = useCallback(async () => {
    const request = ++listaRequest.current;
    setErr(null);
    setOk(null);

    if (!supabase) return;
    if (!tenantId || !empresaId) {
      setErr("Contexto (tenant/empresa) nao carregado.");
      setRows([]);
      setCount(0);
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const res = await listOrcamentos(supabase, {
        tenantId,
        empresaId,
        q,
        status,
        from,
        to,
        page: pageSafe,
        pageSize: PAGE_SIZE,
      });
      if (request !== listaRequest.current) return;
      setRows(res.rows);
      setCount(res.count);
    } catch (e: unknown) {
      if (request !== listaRequest.current) return;
      setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao carregar orcamentos."));
      setRows([]);
      setCount(0);
    } finally {
      if (request === listaRequest.current) setLoading(false);
    }
  }, [empresaId, from, pageSafe, q, status, supabase, tenantId, to]);

  const carregarGrupos = useCallback(async () => {
    const request = ++gruposRequest.current;
    if (!supabase || !tenantId || !empresaId) {
      setGrupos([]);
      setGruposLoading(false);
      return;
    }
    setGruposLoading(true);
    setErr(null);
    try {
      const result = await listOrcamentosAgrupadoCliente(supabase, { tenantId, empresaId, q, status, from, to });
      if (request === gruposRequest.current) setGrupos(result);
    } catch (e: unknown) {
      if (request !== gruposRequest.current) return;
      setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao agrupar orcamentos por cliente."));
      setGrupos([]);
    } finally {
      if (request === gruposRequest.current) setGruposLoading(false);
    }
  }, [empresaId, from, q, status, supabase, tenantId, to]);

  // Trocar de filtro invalida o que ja foi aberto: os orcamentos de cada cliente
  // sao os do filtro, nao todos os dele.
  useEffect(() => {
    clientesRequest.current += 1;
    setOrcamentosPorCliente({});
    setGruposAbertos(new Set());
    setClientesCarregando(new Set());
  }, [q, status, from, to, tenantId, empresaId]);

  useEffect(() => {
    void carregarGrupos();
  }, [carregarGrupos]);

  useEffect(() => {
    if (vista === "lista") void reload();
  }, [reload, vista]);

  const atualizar = useCallback(() => {
    clientesRequest.current += 1;
    setOrcamentosPorCliente({});
    setGruposAbertos(new Set());
    setClientesCarregando(new Set());
    void carregarGrupos();
    if (vista === "lista") void reload();
  }, [carregarGrupos, reload, vista]);

  const alternarCliente = useCallback(async (grupo: OrcamentoGrupoCliente) => {
    const chave = chaveCliente(grupo.cliente_id);
    const abrindo = !gruposAbertos.has(chave);
    setGruposAbertos((atual) => {
      const proximo = new Set(atual);
      if (abrindo) proximo.add(chave);
      else proximo.delete(chave);
      return proximo;
    });
    if (!abrindo || orcamentosPorCliente[chave] || !supabase || !tenantId || !empresaId) return;
    const request = clientesRequest.current;
    setClientesCarregando((atual) => new Set(atual).add(chave));
    try {
      const linhas = await listOrcamentosDoCliente(supabase, {
        tenantId,
        empresaId,
        clienteId: grupo.cliente_id,
        q,
        status,
        from,
        to,
      });
      if (request !== clientesRequest.current) return;
      setOrcamentosPorCliente((atual) => ({ ...atual, [chave]: linhas }));
    } catch (e: unknown) {
      if (request !== clientesRequest.current) return;
      setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao carregar os orcamentos do cliente."));
    } finally {
      setClientesCarregando((atual) => {
        if (request !== clientesRequest.current) return atual;
        const proximo = new Set(atual);
        proximo.delete(chave);
        return proximo;
      });
    }
  }, [empresaId, from, gruposAbertos, orcamentosPorCliente, q, status, supabase, tenantId, to]);

  useEffect(() => {
    if (page !== pageSafe) setPage(pageSafe);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pageSafe]);

  const startNew = useCallback(() => {
    router.push("/comercial/orcamentos/novo");
  }, [router]);

  const openStatusDialog = useCallback(async (row: OrcamentoListaRow, nextStatus: OrcamentoStatusCanonical) => {
    if (busy || !canWrite || !supabase || !tenantId || !empresaId) return;
    setBusy(true);
    setErr(null);
    try {
      const pedidoCompra = nextStatus === "FECHADO"
        ? await getPedidoCompraOrcamento(supabase, { tenantId, empresaId, id: row.id })
        : null;
      setStatusDialog({ open: true, row: { ...row, pedido_compra_cliente: pedidoCompra }, status: nextStatus });
    } catch (error: unknown) {
      setErr(mapOrcamentoError(toSupabaseErrorLike(error), "Erro ao carregar os dados do fechamento."));
    } finally {
      setBusy(false);
    }
  }, [busy, canWrite, supabase, tenantId, empresaId]);

  const closeStatusDialog = useCallback(() => {
    if (busy) return;
    setStatusDialog({ open: false });
  }, [busy]);

  const submitStatusDialog = useCallback(
    async (payload: OrcamentoStatusDialogPayload) => {
      if (!statusDialog.open) return;
      if (!canWrite || !supabase || !tenantId || !empresaId) return;

      const targetRowId = statusDialog.row.id;
      const prevRows = rows;
      const prevFollowup = ultimoFollowupById[targetRowId];

      setBusy(true);
      setErr(null);
      setOk(null);

      setRows((prev) =>
        prev.map((row) =>
          row.id === targetRowId
            ? {
                ...row,
                status: payload.status,
                observacoes: payload.followup,
                valor_fechado: payload.status === "FECHADO" ? payload.valorFechado : row.valor_fechado,
              }
            : row
        )
      );
      setUltimoFollowupById((prev) => ({ ...prev, [targetRowId]: payload.followup }));

      try {
        const result = await atualizarStatusOrcamento(supabase, {
          tenantId,
          empresaId,
          id: targetRowId,
          status: payload.status,
          followup: payload.followup,
          valorFechado: payload.valorFechado,
          pedidoCompraCliente: payload.pedidoCompraCliente,
          abrirOs: payload.abrirOs,
          importarItensOs: payload.importarItensOs,
          responsavelAprovacaoId: payload.responsavelAprovacaoId,
          tipoDocumento: payload.tipoDocumento,
        });
        setRows((prev) =>
          prev.map((row) =>
            row.id === targetRowId
              ? {
                  ...row,
                  status: payload.status,
                  observacoes: payload.followup,
                  valor_fechado: payload.status === "FECHADO" ? result.valorFechado : row.valor_fechado,
                  os_id: result.osId ?? row.os_id,
                  os_itens_importados_at: payload.importarItensOs ? new Date().toISOString() : row.os_itens_importados_at,
                }
              : row
          )
        );
        setStatusDialog({ open: false });
        if (payload.abrirOs && result.osId) {
          if (payload.gestao) {
            await supabase.rpc("set_current_tenant", { p_tenant_id: tenantId });
            await supabase.rpc("set_current_empresa", { p_empresa_id: empresaId });
            const gestaoRows = payload.gestao.items.map((it) => ({
              os_id: result.osId as number,
              item_tipo: it.item_tipo,
              area: it.area,
              habilitado: it.habilitado,
              responsavel_id: null as string | null,
              data_prevista: it.data_prevista ?? null,
              progresso_percent: it.progresso_percent,
            }));
            await supabase.from("os_gestao_itens").upsert(gestaoRows, { onConflict: "os_id,item_tipo,area" });
            if (payload.gestao.habilitarGestao) {
              await supabase
                .from("ordens_servico")
                .update({ tem_gestao: true, atualizado_em: new Date().toISOString() })
                .eq("id", result.osId);
            }
          }
          router.push(payload.tipoDocumento === "OV" ? `/comercial/vendas/${result.osId}` : `/os/${result.osId}`);
          return;
        }
        atualizar();
        setOk(`Status atualizado para ${getOrcamentoStatusLabel(payload.status)}.`);
      } catch (e: unknown) {
        setRows(prevRows);
        setUltimoFollowupById((prev) => {
          const next = { ...prev };
          if (prevFollowup) next[targetRowId] = prevFollowup;
          else delete next[targetRowId];
          return next;
        });
        setErr(mapOrcamentoError(toSupabaseErrorLike(e), "Erro ao atualizar status do orcamento."));
      } finally {
        setBusy(false);
      }
    },
    [atualizar, canWrite, empresaId, router, rows, statusDialog, supabase, tenantId, ultimoFollowupById]
  );

  const totalOrcamentos = grupos.reduce((total, grupo) => total + n(grupo.quantidade_orcamentos), 0);
  const totalValor = grupos.reduce((total, grupo) => total + n(grupo.valor_total), 0);
  const totalClientes = grupos.filter((grupo) => grupo.cliente_id !== null).length;
  const carregando = gruposLoading || (vista === "lista" && loading);
  const filtrosAtivos = Boolean(q.trim() || from || to || status !== "ANDAMENTO");
  const gruposOrdenados = useMemo(() => [...grupos].sort((a, b) => {
    if (ordem === "cliente") return a.cliente_nome.localeCompare(b.cliente_nome, "pt-BR");
    if (ordem === "emissao") return (b.ultima_emissao ?? "").localeCompare(a.ultima_emissao ?? "");
    return n(b.valor_total) - n(a.valor_total) || a.cliente_nome.localeCompare(b.cliente_nome, "pt-BR");
  }), [grupos, ordem]);

  const limparFiltros = () => {
    setQ("");
    setStatus("ANDAMENTO");
    setFrom("");
    setTo("");
    setPage(1);
  };

  if (!ready && permissionsLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissoes...</div>;
  }

  if (!canView) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Acesso negado.</div>;
  }

  return (
    <div className="carteira-theme mx-auto w-full max-w-[1680px] space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <div className="carteira-blue font-mono text-[10px] font-semibold uppercase tracking-[0.13em]">
            Comercial <span className="carteira-faint px-1">›</span> Orçamentos
          </div>
          <h1 className="carteira-text mt-1.5 text-[23px] font-bold tracking-[-0.02em]">Orçamentos</h1>
          <p className="carteira-muted mt-1 text-[12px]" aria-live="polite">
            {carregando ? "Carregando a carteira de orçamentos..." :
              totalOrcamentos + " " + (totalOrcamentos === 1 ? "orçamento" : "orçamentos") + " " + rotuloSituacao(status) + " · " + totalClientes + " " + (totalClientes === 1 ? "cliente" : "clientes")}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <div className="carteira-surface flex items-center rounded-lg border p-0.5" aria-label="Modo de visualização">
            {(["lista", "cliente"] as const).map((modo) => (
              <button
                key={modo}
                type="button"
                onClick={() => setVista(modo)}
                aria-pressed={vista === modo}
                className={"rounded-md px-3 py-1.5 text-[11px] font-semibold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--carteira-blue)] " + (vista === modo
                  ? "bg-[var(--carteira-elevated)] text-[var(--carteira-text)] shadow-sm"
                  : "text-[var(--carteira-muted)] hover:text-[var(--carteira-text)]")}
              >
                {modo === "lista" ? "Lista" : "Por cliente"}
              </button>
            ))}
          </div>
          <Link href="/" className="carteira-button rounded-lg px-3 py-2 text-xs font-medium">Voltar</Link>
          <button type="button" onClick={atualizar} disabled={carregando || busy}
            className="carteira-button rounded-lg px-3 py-2 text-xs font-medium disabled:opacity-50">
            {carregando ? "Atualizando..." : "Atualizar"}
          </button>
          <button type="button" onClick={startNew} disabled={!canWrite}
            className="carteira-button carteira-button-amber rounded-lg px-3.5 py-2 text-xs font-semibold disabled:opacity-50">
            Novo orçamento
          </button>
        </div>
      </div>

      <section className="grid grid-cols-1 gap-2 sm:grid-cols-2 xl:grid-cols-4" aria-label="Indicadores da carteira de orçamentos" aria-busy={gruposLoading}>
        <ResumoCard titulo={status === "TODOS" ? "Orçamentos" : rotuloSituacao(status)}
          valor={gruposLoading ? "—" : totalOrcamentos.toLocaleString("pt-BR")} detalhe="Orçamentos no filtro atual" />
        <ResumoCard titulo="Valor total" valor={gruposLoading ? "—" : "R$ " + formatMoneyBR(totalValor)}
          detalhe="Total líquido dos orçamentos" />
        <ResumoCard titulo="Clientes" valor={gruposLoading ? "—" : totalClientes.toLocaleString("pt-BR")}
          detalhe="Clientes com orçamentos no filtro" />
        <ResumoCard titulo="Valor médio" valor={gruposLoading ? "—" : "R$ " + formatMoneyBR(totalOrcamentos ? totalValor / totalOrcamentos : 0)}
          detalhe="Por orçamento no filtro atual" />
      </section>

      <div className="carteira-surface rounded-xl border p-2.5">
        <div className="grid grid-cols-1 items-end gap-2 sm:grid-cols-2 xl:grid-cols-[minmax(250px,1fr)_160px_180px_180px_auto]">
          <input value={q} onChange={(event) => { setQ(event.target.value); setPage(1); }}
            placeholder="Buscar por cliente, título ou código..." aria-label="Buscar"
            className="carteira-control min-w-0 rounded-lg px-3 py-2 text-xs sm:col-span-2 xl:col-span-1" />
          <label className="carteira-muted block text-[10px]">
            Status
            <select value={status} onChange={(event) => { setStatus(event.target.value as OrcamentoStatus | "TODOS"); setPage(1); }}
              className="carteira-control mt-1 w-full rounded-lg px-3 py-2 text-xs" aria-label="Status">
              {STATUS_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
            </select>
          </label>
          <label className="carteira-muted block text-[10px]">
            Emissão (de)
            <input type="date" value={from} onChange={(event) => { setFrom(event.target.value); setPage(1); }}
              className="carteira-control mt-1 w-full min-w-0 rounded-lg px-3 py-2 text-xs" />
          </label>
          <label className="carteira-muted block text-[10px]">
            Emissão (até)
            <input type="date" value={to} onChange={(event) => { setTo(event.target.value); setPage(1); }}
              className="carteira-control mt-1 w-full min-w-0 rounded-lg px-3 py-2 text-xs" />
          </label>
          <button type="button" onClick={atualizar} disabled={carregando}
            className="carteira-button rounded-lg px-3 py-2 text-xs font-medium disabled:opacity-50">Buscar</button>
        </div>
        <div className="mt-2 flex min-h-5 flex-wrap items-center justify-between gap-2 border-t border-[var(--carteira-border)] px-1 pt-2 text-[10px]">
          <span className="carteira-faint">{filtrosAtivos ? "Filtros aplicados à carteira de orçamentos" : "Nenhum filtro adicional ativo"}</span>
          {filtrosAtivos ? <button type="button" onClick={limparFiltros} className="carteira-blue font-semibold hover:underline">Limpar filtros</button> : null}
        </div>
      </div>

      {err && <div role="alert" className="rounded-lg border border-[var(--carteira-red)] p-3 text-xs text-[var(--carteira-red)]">{err}</div>}
      {ok && <div role="status" className="carteira-green text-xs">{ok}</div>}

      <div className="flex flex-wrap items-center justify-between gap-2 px-1">
        {vista === "cliente" ? (
          <label className="carteira-muted flex items-center gap-2 text-[10px]">
            <span className="font-mono font-semibold uppercase tracking-[0.13em]">Ordem</span>
            <select value={ordem} onChange={(event) => setOrdem(event.target.value)} aria-label="Ordenar clientes"
              className="carteira-control rounded-lg px-2.5 py-1.5 text-[11px]">
              <option value="valor">Maior valor total</option>
              <option value="cliente">Nome do cliente</option>
              <option value="emissao">Emissão mais recente</option>
            </select>
          </label>
        ) : <span className="carteira-muted font-mono text-[10px] font-semibold uppercase tracking-[0.13em]">Emissão mais recente</span>}
        <span className="carteira-muted text-[10.5px]">
          {carregando ? "Carregando..." : vista === "cliente" ? grupos.length + " grupos · " + totalOrcamentos + " orçamentos" : count + " orçamentos · página " + pageSafe + " de " + totalPages}
        </span>
      </div>

      {vista === "cliente" ? (
        <div className="space-y-2" aria-busy={gruposLoading}>
          {gruposLoading ? (
            <div className="carteira-surface carteira-muted rounded-xl border px-4 py-8 text-center text-sm">Agrupando orçamentos por cliente...</div>
          ) : grupos.length === 0 ? (
            <div className="carteira-surface carteira-muted rounded-xl border px-4 py-10 text-center text-sm">Nenhum orçamento encontrado.</div>
          ) : gruposOrdenados.map((grupo) => {
            const chave = chaveCliente(grupo.cliente_id);
            const aberto = gruposAbertos.has(chave);
            const linhas = orcamentosPorCliente[chave] ?? [];
            const vendedores = (grupo.vendedores ?? []).filter(Boolean);
            return (
              <div key={chave} className="carteira-surface overflow-hidden rounded-[10px] border">
                <button type="button" onClick={() => void alternarCliente(grupo)} aria-expanded={aberto}
                  className="grid w-full grid-cols-[16px_minmax(0,1fr)] items-center gap-x-3 gap-y-1 px-4 py-3 text-left transition hover:bg-[var(--carteira-hover)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-[var(--carteira-blue)] sm:grid-cols-[16px_minmax(0,1fr)_auto]">
                  <span aria-hidden="true" className={"carteira-faint text-[10px] transition-transform " + (aberto ? "rotate-90" : "")}>▶</span>
                  <span className="min-w-0">
                    <span className="carteira-text block truncate text-[13.5px] font-[650] leading-5 tracking-[0.01em]">{grupo.cliente_nome}</span>
                    <span className="carteira-muted mt-0.5 block truncate text-[11.5px]">
                      {grupo.quantidade_orcamentos} {n(grupo.quantidade_orcamentos) === 1 ? "orçamento" : "orçamentos"}
                      {" · "}{grupo.quantidade_itens} {n(grupo.quantidade_itens) === 1 ? "item" : "itens"}
                      {vendedores.length ? " · " + vendedores.join(", ") : ""}
                    </span>
                  </span>
                  <span className="col-start-2 whitespace-nowrap text-left sm:col-start-auto sm:text-right">
                    <span className="carteira-text block font-mono text-[15px] font-bold tabular-nums">R$ {formatMoneyBR(n(grupo.valor_total))}</span>
                    <span className="carteira-muted mt-0.5 block text-[10.5px]">Última emissão {formatDateBR(grupo.ultima_emissao)}</span>
                  </span>
                </button>
                {aberto ? (
                  <div className="overflow-x-auto border-t border-[var(--carteira-border)] bg-[var(--carteira-surface-2)]">
                    {clientesCarregando.has(chave) ? <div className="carteira-muted px-4 py-4 text-xs">Carregando orçamentos...</div> : linhas.length === 0 ?
                      <div className="carteira-muted px-4 py-4 text-xs">Nenhum orçamento deste cliente no filtro.</div> : linhas.map((linha) => (
                        <Link key={linha.id} href={"/comercial/orcamentos/" + linha.id}
                          className="grid min-w-[850px] grid-cols-[8px_110px_minmax(220px,1fr)_minmax(160px,0.7fr)_130px] items-center gap-3 border-b border-[var(--carteira-border)] py-2.5 pr-4 pl-[42px] text-left transition last:border-b-0 hover:bg-[var(--carteira-hover)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-[var(--carteira-blue)]">
                          <span aria-hidden="true" className="h-1.5 w-1.5 rounded-full" style={{ background: statusColor(linha.status) }} />
                          <span className="carteira-blue font-mono text-[12px] font-bold tabular-nums">{linha.codigo}</span>
                          <span className="carteira-text min-w-0 truncate text-[12.5px] font-medium" title={linha.titulo}>{linha.titulo}</span>
                          <span className="carteira-muted min-w-0 truncate text-[11px]">{linha.vendedor_nome ?? "Sem vendedor"} · {getOrcamentoStatusLabel(linha.status)}</span>
                          <span className="text-right">
                            <span className="carteira-text block font-mono text-[12.5px] font-semibold tabular-nums">R$ {formatMoneyBR(n(linha.total_liquido))}</span>
                            <span className="carteira-muted mt-0.5 block text-[9.5px]">{formatDateBR(linha.emissao_date)}</span>
                          </span>
                        </Link>
                      ))}
                  </div>
                ) : null}
              </div>
            );
          })}
        </div>
      ) : (
        <div className="carteira-table-shell rounded-xl" aria-busy={loading}>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[1120px] text-xs">
              <thead>
                <tr className="carteira-table-head border-b border-[var(--carteira-border)]">
                  <th scope="col" className="px-4 py-3 text-left">Código / Emissão</th>
                  <th scope="col" className="px-4 py-3 text-left">Orçamento / Cliente</th>
                  <th scope="col" className="px-4 py-3 text-left">Vendedor / Cond. Pgto</th>
                  <th scope="col" className="px-4 py-3 text-left">Status</th>
                  <th scope="col" className="px-4 py-3 text-right whitespace-nowrap">Total líquido</th>
                  <th scope="col" className="px-4 py-3 text-right">Ações</th>
                </tr>
              </thead>
              <tbody>
                {!loading && rows.length === 0 ? <tr><td colSpan={6} className="carteira-muted px-4 py-8 text-center text-sm">Nenhum orçamento encontrado.</td></tr> : null}
                {rows.map((row) => {
                  const followup = String(ultimoFollowupById[row.id] ?? row.observacoes ?? "").trim();
                  const href = "/comercial/orcamentos/" + encodeURIComponent(row.codigo ?? row.id);
                  return (
                    <tr key={row.id} className="carteira-table-row cursor-pointer" onClick={() => router.push(href)}>
                      <td className="px-4 py-3 align-middle whitespace-nowrap">
                        <Link href={href} onClick={(event) => event.stopPropagation()} className="carteira-blue font-mono text-[12.5px] font-bold hover:underline">{row.codigo}</Link>
                        <div className="carteira-muted mt-1 text-[10.5px] tabular-nums">{formatDateBR(row.emissao_date)}</div>
                      </td>
                      <td className="max-w-[420px] px-4 py-3 align-middle">
                        <div className="carteira-text text-[13px] font-[620] leading-5">{row.titulo}</div>
                        <div className="carteira-muted mt-0.5 text-[11.5px]">{row.cliente_nome ?? "Cliente não informado"}</div>
                      </td>
                      <td className="px-4 py-3 align-middle">
                        <div className="carteira-text text-xs">{row.vendedor_nome ?? "—"}</div>
                        <div className="carteira-muted mt-1 text-[10.5px]">{row.condicao_pagamento_nome ?? "—"}</div>
                      </td>
                      <td className="max-w-[230px] px-4 py-3 align-middle">
                        <div className="flex items-center gap-2 whitespace-nowrap">
                          <span aria-hidden="true" className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ background: statusColor(row.status) }} />
                          <span className="carteira-text text-xs font-medium">{getOrcamentoStatusLabel(row.status)}</span>
                        </div>
                        {followup ? <div className="carteira-muted mt-1 text-[10.5px]" title={followup}>Último follow-up: {truncateFollowup(followup)}</div> : null}
                      </td>
                      <td className="carteira-text px-4 py-3 text-right align-middle font-mono text-[13px] font-semibold whitespace-nowrap tabular-nums">R$ {formatMoneyBR(n(row.total_liquido))}</td>
                      <td className="px-4 py-3 text-right align-middle whitespace-nowrap">
                        <div className="inline-flex items-center gap-1.5">
                          {(["FECHADO", "PERDIDO", "ANDAMENTO"] as const).map((nextStatus) => (
                            <button key={nextStatus} type="button" onClick={(event) => { event.stopPropagation(); void openStatusDialog(row, nextStatus); }}
                              disabled={!canWrite || busy}
                              style={{ color: statusColor(nextStatus) }}
                              className="carteira-button rounded-md px-2 py-1.5 text-[10.5px] font-medium disabled:opacity-50">
                              {getOrcamentoStatusLabel(nextStatus)}
                            </button>
                          ))}
                        </div>
                      </td>
                    </tr>
                  );
                })}
                {loading ? <tr><td colSpan={6} className="carteira-muted px-4 py-6 text-center">Carregando...</td></tr> : null}
              </tbody>
            </table>
          </div>
          <div className="flex flex-wrap items-center justify-between gap-3 border-t border-[var(--carteira-border)] px-4 py-3">
            <span className="carteira-muted text-[10.5px]">Página {pageSafe} de {totalPages} · {count} registros</span>
            <div className="flex items-center gap-2">
              <button type="button" onClick={() => setPage((current) => Math.max(1, current - 1))} disabled={pageSafe <= 1 || loading}
                className="carteira-button rounded-lg px-3 py-2 text-xs font-medium disabled:opacity-50">Anterior</button>
              <button type="button" onClick={() => setPage((current) => Math.min(totalPages, current + 1))} disabled={pageSafe >= totalPages || loading}
                className="carteira-button rounded-lg px-3 py-2 text-xs font-medium disabled:opacity-50">Próxima</button>
            </div>
          </div>
        </div>
      )}

      {statusDialog.open && (
        <OrcamentoStatusDialog
          open={statusDialog.open}
          status={statusDialog.status}
          loading={busy}
          initialFollowup={statusDialog.row.observacoes}
          initialValorFechado={statusDialog.row.valor_fechado}
          initialPedidoCompraCliente={statusDialog.row.pedido_compra_cliente}
          valorOrcado={statusDialog.row.total_liquido}
          canOpenOs={canOpenOs}
          suggestedTipoDocumento={Number(statusDialog.row.total_servicos ?? 0) > 0 ? "OS" : "OV"}
          tenantId={tenantId}
          empresaId={empresaId}
          onCancel={closeStatusDialog}
          onSave={submitStatusDialog}
        />
      )}
    </div>
  );
}
