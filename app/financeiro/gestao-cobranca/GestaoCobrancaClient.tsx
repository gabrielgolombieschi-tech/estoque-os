"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { formatDecimalBR } from "@/lib/decimal";

type CobrancaStatus = "PENDENTE" | "FATURADO" | "RECEBIDO" | "CANCELADO";

type Row = {
  tenant_id: string;
  empresa_id: string;
  os_id: number;
  numero_os: string | null;
  os_num: number | null;
  cliente_nome: string | null;
  descricao_servico: string | null;
  data_conclusao: string | null;
  valor_total: number | string | null;
  pedido_compra_os: string | null;
  cobranca_id: string | null;
  cobranca_status: CobrancaStatus | null;
  pedido_compra_cliente: string | null;
  pedido_recebido_em: string | null;
  faturado_em: string | null;
  proximo_contato_date: string | null;
  responsavel_id: string | null;
  observacao: string | null;
  documento_fiscal_id: string | null;
  doc_modelo: string | null;
  doc_serie: string | null;
  doc_numero: string | null;
  doc_emissao_date: string | null;
  doc_status: string | null;
  titulo_ar_id: string | null;
  ar_status: string | null;
  ar_valor_total: number | string | null;
  ar_valor_aberto: number | string | null;
  dias_desde_conclusao: number | null;
};

type StatusFilter = "TODOS" | "PENDENTE" | "FATURADO";
type SortKey = "dias_desc" | "dias_asc" | "conclusao_desc" | "conclusao_asc" | "valor_desc" | "valor_asc";
type ResponsavelOption = { id: string; nome: string };

type EditState = {
  open: boolean;
  row: Row | null;
  status: CobrancaStatus;
  pedidoCompraCliente: string;
  pedidoRecebidoEm: string;
  proximoContatoDate: string;
  responsavelId: string;
  observacao: string;
  busy: boolean;
  error: string | null;
};

function toNumber(value: unknown): number {
  const n = typeof value === "number" ? value : Number(value ?? 0);
  return Number.isFinite(n) ? n : 0;
}

function fmtMoney(value: unknown): string {
  return `R$ ${formatDecimalBR(toNumber(value), 2)}`;
}

function fmtDateBR(iso: string | null | undefined): string {
  if (!iso) return "-";
  const datePart = String(iso).slice(0, 10);
  const [y, m, d] = datePart.split("-");
  if (!y || !m || !d) return String(iso);
  return `${d}/${m}/${y}`;
}

function todayISO(): string {
  const d = new Date();
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

function docLabel(row: Row): string {
  if (!row.doc_numero) return "-";
  const serie = row.doc_serie ? `/${row.doc_serie}` : "";
  const status = row.doc_status ? ` (${row.doc_status})` : "";
  return `${row.doc_numero}${serie}${status}`;
}

function effectiveStatus(row: Row): CobrancaStatus {
  if ((row.doc_status ?? "").toUpperCase() === "EMITIDA") return "FATURADO";
  return row.cobranca_status ?? "PENDENTE";
}

function statusBadge(status: CobrancaStatus) {
  if (status === "FATURADO") return "bg-blue-500/15 text-blue-300 border-blue-500/30";
  if (status === "RECEBIDO") return "bg-emerald-500/15 text-emerald-300 border-emerald-500/30";
  if (status === "CANCELADO") return "bg-red-500/15 text-red-300 border-red-500/30";
  return "bg-amber-500/15 text-amber-300 border-amber-500/30";
}

function StatCard({ title, value, subtitle }: { title: string; value: string; subtitle?: string }) {
  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
      <div className="text-xs text-zinc-400">{title}</div>
      <div className="mt-2 text-2xl font-semibold text-zinc-100 tabular-nums">{value}</div>
      {subtitle ? <div className="mt-1 text-xs text-zinc-500">{subtitle}</div> : null}
    </div>
  );
}

export default function GestaoCobrancaClient() {
  const te = useTenantEmpresa();
  const router = useRouter();
  const supabase = useMemo(() => getSupabaseBrowser(), []);

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [rows, setRows] = useState<Row[]>([]);
  const [responsaveis, setResponsaveis] = useState<ResponsavelOption[]>([]);

  const [statusFilter, setStatusFilter] = useState<StatusFilter>("TODOS");
  const [clienteQ, setClienteQ] = useState("");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [onlyContatoVencido, setOnlyContatoVencido] = useState(false);
  const [sortKey, setSortKey] = useState<SortKey>("dias_desc");

  const [edit, setEdit] = useState<EditState>({
    open: false,
    row: null,
    status: "PENDENTE",
    pedidoCompraCliente: "",
    pedidoRecebidoEm: "",
    proximoContatoDate: "",
    responsavelId: "",
    observacao: "",
    busy: false,
    error: null,
  });

  const canRead = useMemo(() => {
    const r = te.has("financeiro.read");
    const w = te.has("financeiro.write");
    if (r === undefined || w === undefined) return undefined;
    return Boolean(r || w);
  }, [te]);

  const canWrite = useMemo(() => {
    const w = te.has("financeiro.write");
    return Boolean(w);
  }, [te]);

  const tenantId = te.tenantId ?? null;
  const empresaId = te.empresaId ?? (te.empresas.length === 1 ? te.empresas[0]?.id ?? null : null);

  const ready = typeof te.sessionUserId === "string" && Boolean(tenantId) && Boolean(empresaId) && canRead === true;

  const load = useCallback(async () => {
    if (!ready || !tenantId || !empresaId) return;

    setLoading(true);
    setError(null);

    try {
      const query = applyTenantEmpresa(
        supabase.schema("r").from("r_gestao_cobranca_os").select("*"),
        tenantId,
        empresaId
      ).order("dias_desde_conclusao", { ascending: false, nullsFirst: false });

      const { data, error: qErr } = await query;
      if (qErr) throw qErr;

      setRows((data ?? []) as Row[]);
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : "Erro ao carregar gestão de cobrança.";
      setError(message);
      setRows([]);
    } finally {
      setLoading(false);
    }
  }, [ready, tenantId, empresaId, supabase]);

  const loadResponsaveis = useCallback(async () => {
    if (!ready || !empresaId) return;
    try {
      const { data, error: qErr } = await supabase
        .schema("a")
        .from("usuario_empresa")
        .select("usuario_id,papel,usuario:usuario_id(id,nome)")
        .eq("empresa_id", empresaId)
        .eq("ativo", true)
        .is("deleted_at", null);

      if (qErr) throw qErr;

      const mapped = ((data ?? []) as Array<{
        usuario_id?: string | null;
        papel?: string | null;
        usuario?: { id?: string | null; nome?: string | null } | null;
      }>)
        .map((r) => ({
          id: String(r.usuario?.id ?? r.usuario_id ?? "").trim(),
          nome: String(r.usuario?.nome ?? "").trim() || String(r.usuario_id ?? "").trim(),
          papel: String(r.papel ?? "").trim().toUpperCase(),
        }))
        .filter((r) => r.id !== "")
        .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));

      const unique = new Map<string, ResponsavelOption>();
      for (const row of mapped) {
        if (!unique.has(row.id)) unique.set(row.id, { id: row.id, nome: row.nome });
      }
      setResponsaveis(Array.from(unique.values()));
    } catch {
      setResponsaveis([]);
    }
  }, [ready, empresaId, supabase]);

  useEffect(() => {
    if (canRead === false) router.replace("/forbidden");
  }, [canRead, router]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    void loadResponsaveis();
  }, [loadResponsaveis]);

  const today = todayISO();

  const baseFilteredRows = useMemo(() => {
    const q = clienteQ.trim().toLowerCase();
    return rows.filter((row) => {
      if (q) {
        const hay = `${row.cliente_nome ?? ""} ${row.descricao_servico ?? ""} ${row.numero_os ?? ""}`.toLowerCase();
        if (!hay.includes(q)) return false;
      }

      if (dateFrom && (row.data_conclusao ? String(row.data_conclusao).slice(0, 10) < dateFrom : true)) return false;
      if (dateTo && (row.data_conclusao ? String(row.data_conclusao).slice(0, 10) > dateTo : true)) return false;

      if (onlyContatoVencido) {
        const contato = row.proximo_contato_date ? String(row.proximo_contato_date).slice(0, 10) : null;
        if (!contato || contato >= today) return false;
      }

      return true;
    });
  }, [rows, clienteQ, dateFrom, dateTo, onlyContatoVencido, today]);

  const kpis = useMemo(() => {
    let pendentes = 0;
    let faturados = 0;
    let pendentes7 = 0;
    let pendentes15 = 0;
    let totalAberto = 0;

    for (const row of baseFilteredRows) {
      const status = effectiveStatus(row);
      if (status === "PENDENTE") {
        pendentes += 1;
        const dias = Number(row.dias_desde_conclusao ?? 0);
        if (dias > 7) pendentes7 += 1;
        if (dias > 15) pendentes15 += 1;
      }
      if (status === "FATURADO") faturados += 1;

      totalAberto += toNumber(row.ar_valor_aberto ?? row.valor_total ?? 0);
    }

    return { pendentes, faturados, pendentes7, pendentes15, totalAberto };
  }, [baseFilteredRows]);

  const tableRows = useMemo(() => {
    const filtered = baseFilteredRows.filter((row) => {
      if (statusFilter === "TODOS") return true;
      return effectiveStatus(row) === statusFilter;
    });

    const sorted = [...filtered];
    sorted.sort((a, b) => {
      if (sortKey === "dias_desc") return Number(b.dias_desde_conclusao ?? -99999) - Number(a.dias_desde_conclusao ?? -99999);
      if (sortKey === "dias_asc") return Number(a.dias_desde_conclusao ?? 99999) - Number(b.dias_desde_conclusao ?? 99999);
      if (sortKey === "conclusao_desc") return String(b.data_conclusao ?? "").localeCompare(String(a.data_conclusao ?? ""));
      if (sortKey === "conclusao_asc") return String(a.data_conclusao ?? "").localeCompare(String(b.data_conclusao ?? ""));
      if (sortKey === "valor_desc") return toNumber(b.valor_total) - toNumber(a.valor_total);
      return toNumber(a.valor_total) - toNumber(b.valor_total);
    });

    return sorted;
  }, [baseFilteredRows, statusFilter, sortKey]);

  const openEdit = useCallback((row: Row) => {
    setEdit({
      open: true,
      row,
      status: row.cobranca_status ?? effectiveStatus(row),
      pedidoCompraCliente: row.pedido_compra_cliente ?? "",
      pedidoRecebidoEm: row.pedido_recebido_em ? String(row.pedido_recebido_em).slice(0, 10) : "",
      proximoContatoDate: row.proximo_contato_date ? String(row.proximo_contato_date).slice(0, 10) : "",
      responsavelId: row.responsavel_id ?? "",
      observacao: row.observacao ?? "",
      busy: false,
      error: null,
    });
  }, []);

  const closeEdit = useCallback(() => {
    setEdit((prev) => ({ ...prev, open: false, row: null, error: null, busy: false }));
  }, []);

  const saveEdit = useCallback(async () => {
    if (!edit.row || !tenantId || !empresaId) return;
    const responsavel = edit.responsavelId.trim();

    setEdit((p) => ({ ...p, busy: true, error: null }));

    const faturadoEmBase = edit.row.faturado_em ? String(edit.row.faturado_em).slice(0, 10) : "";
    const faturadoEm = edit.status === "FATURADO" ? faturadoEmBase || todayISO() : null;

    const payload = {
      tenant_id: tenantId,
      empresa_id: empresaId,
      os_id: edit.row.os_id,
      status: edit.status,
      pedido_compra_cliente: edit.pedidoCompraCliente.trim() || null,
      pedido_recebido_em: edit.pedidoRecebidoEm || null,
      faturado_em: faturadoEm,
      documento_fiscal_id: edit.row.documento_fiscal_id ?? null,
      titulo_ar_id: edit.row.titulo_ar_id ?? null,
      responsavel_id: responsavel || null,
      proximo_contato_date: edit.proximoContatoDate || null,
      observacao: edit.observacao.trim() || null,
      deleted_at: null as string | null,
    };

    const { error: upsertErr } = await supabase
      .schema("f")
      .from("gestao_cobranca_os")
      .upsert(payload, { onConflict: "tenant_id,empresa_id,os_id" });

    if (upsertErr) {
      setEdit((p) => ({ ...p, busy: false, error: upsertErr.message }));
      return;
    }

    closeEdit();
    await load();
  }, [edit, tenantId, empresaId, supabase, closeEdit, load]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <h1 className="text-2xl font-semibold">Gestão Cobrança</h1>
        <div className="ml-auto flex items-center gap-2">
          <Link href="/financeiro" className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm">
            Financeiro
          </Link>
          <button
            type="button"
            onClick={() => void load()}
            className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-950 hover:bg-zinc-900 text-sm"
          >
            Atualizar
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-5 gap-3">
        <StatCard title="Pendentes" value={String(kpis.pendentes)} />
        <StatCard title="Faturados" value={String(kpis.faturados)} />
        <StatCard title="Pendentes > 7 dias" value={String(kpis.pendentes7)} />
        <StatCard title="Pendentes > 15 dias" value={String(kpis.pendentes15)} />
        <StatCard title="Total em aberto" value={fmtMoney(kpis.totalAberto)} />
      </div>

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 space-y-3">
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-6 gap-3">
          <label className="text-xs text-zinc-400">
            Status
            <select className="mt-1 w-full px-3 py-2" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value as StatusFilter)}>
              <option value="TODOS">Todos</option>
              <option value="PENDENTE">PENDENTE</option>
              <option value="FATURADO">FATURADO</option>
            </select>
          </label>

          <label className="text-xs text-zinc-400 xl:col-span-2">
            Cliente (busca)
            <input
              className="mt-1 w-full px-3 py-2"
              value={clienteQ}
              onChange={(e) => setClienteQ(e.target.value)}
              placeholder="Nome, descrição ou OS"
            />
          </label>

          <label className="text-xs text-zinc-400">
            Conclusão de
            <input type="date" className="mt-1 w-full px-3 py-2" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
          </label>

          <label className="text-xs text-zinc-400">
            Conclusão até
            <input type="date" className="mt-1 w-full px-3 py-2" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
          </label>

          <label className="text-xs text-zinc-400">
            Ordenação
            <select className="mt-1 w-full px-3 py-2" value={sortKey} onChange={(e) => setSortKey(e.target.value as SortKey)}>
              <option value="dias_desc">Dias (maior primeiro)</option>
              <option value="dias_asc">Dias (menor primeiro)</option>
              <option value="conclusao_desc">Conclusão (mais recente)</option>
              <option value="conclusao_asc">Conclusão (mais antiga)</option>
              <option value="valor_desc">Valor (maior)</option>
              <option value="valor_asc">Valor (menor)</option>
            </select>
          </label>
        </div>

        <label className="inline-flex items-center gap-2 text-sm text-zinc-200">
          <input
            type="checkbox"
            className="h-4 w-4"
            checked={onlyContatoVencido}
            onChange={(e) => setOnlyContatoVencido(e.target.checked)}
          />
          Somente com próximo contato vencido
        </label>
      </div>

      {error ? <div className="text-sm text-red-300">{error}</div> : null}

      <div className="rounded-xl border border-zinc-800 bg-zinc-950 overflow-auto">
        <table className="w-full min-w-[1450px] text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-3 py-3 text-left">OS</th>
              <th className="px-3 py-3 text-left">Cliente</th>
              <th className="px-3 py-3 text-left">Descrição</th>
              <th className="px-3 py-3 text-left">Concluída em</th>
              <th className="px-3 py-3 text-right">Dias</th>
              <th className="px-3 py-3 text-right">Valor</th>
              <th className="px-3 py-3 text-left">Pedido</th>
              <th className="px-3 py-3 text-left">NF</th>
              <th className="px-3 py-3 text-right">A Receber</th>
              <th className="px-3 py-3 text-left">Status</th>
              <th className="px-3 py-3 text-left">Próximo contato</th>
              <th className="px-3 py-3 text-left">Responsável</th>
              <th className="px-3 py-3 text-left">Ações</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-800">
            {loading ? (
              <tr>
                <td colSpan={13} className="px-3 py-6 text-zinc-400">
                  Carregando...
                </td>
              </tr>
            ) : tableRows.length === 0 ? (
              <tr>
                <td colSpan={13} className="px-3 py-6 text-zinc-400">
                  Nenhuma OS concluída para os filtros selecionados.
                </td>
              </tr>
            ) : (
              tableRows.map((row) => {
                const status = effectiveStatus(row);
                const pedido = row.pedido_compra_cliente?.trim() ? row.pedido_compra_cliente : row.pedido_compra_os ?? "-";
                const responsavelNome =
                  responsaveis.find((u) => u.id === (row.responsavel_id ?? ""))?.nome ?? (row.responsavel_id ? row.responsavel_id : "-");
                return (
                  <tr key={`${row.tenant_id}-${row.empresa_id}-${row.os_id}`} className="hover:bg-zinc-900/40">
                    <td className="px-3 py-3 text-zinc-200">{row.numero_os ?? row.os_num ?? row.os_id}</td>
                    <td className="px-3 py-3 text-zinc-200">{row.cliente_nome ?? "-"}</td>
                    <td className="px-3 py-3 text-zinc-300">{row.descricao_servico ?? "-"}</td>
                    <td className="px-3 py-3 text-zinc-300">{fmtDateBR(row.data_conclusao)}</td>
                    <td className="px-3 py-3 text-right tabular-nums text-zinc-300">{row.dias_desde_conclusao ?? "-"}</td>
                    <td className="px-3 py-3 text-right tabular-nums text-zinc-200">{fmtMoney(row.valor_total)}</td>
                    <td className="px-3 py-3 text-zinc-300">{pedido}</td>
                    <td className="px-3 py-3 text-zinc-300">{docLabel(row)}</td>
                    <td className="px-3 py-3 text-right tabular-nums text-zinc-200">{fmtMoney(row.ar_valor_aberto ?? row.valor_total)}</td>
                    <td className="px-3 py-3">
                      <span className={["inline-flex items-center px-2 py-1 rounded-md border text-xs", statusBadge(status)].join(" ")}>{status}</span>
                    </td>
                    <td className="px-3 py-3 text-zinc-300">{fmtDateBR(row.proximo_contato_date)}</td>
                    <td className="px-3 py-3 text-zinc-300">{responsavelNome}</td>
                    <td className="px-3 py-3">
                      <button
                        type="button"
                        onClick={() => openEdit(row)}
                        disabled={!canWrite}
                        className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50"
                      >
                        Editar
                      </button>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      {edit.open && edit.row ? (
        <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4" onClick={closeEdit}>
          <div className="w-full max-w-2xl rounded-xl border border-zinc-800 bg-zinc-950 shadow-xl" onClick={(e) => e.stopPropagation()}>
            <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
              <div>
                <div className="text-lg font-semibold">Editar Cobrança - OS {edit.row.numero_os ?? edit.row.os_id}</div>
                <div className="text-sm text-zinc-400">Atualize o acompanhamento da cobrança.</div>
              </div>
              <button type="button" onClick={closeEdit} className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800">
                Fechar
              </button>
            </div>

            <div className="p-5 space-y-3">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <label className="text-xs text-zinc-400">
                  Status
                  <select
                    className="mt-1 w-full px-3 py-2"
                    value={edit.status}
                    onChange={(e) => setEdit((p) => ({ ...p, status: e.target.value as CobrancaStatus }))}
                    disabled={!canWrite || edit.busy}
                  >
                    <option value="PENDENTE">PENDENTE</option>
                    <option value="FATURADO">FATURADO</option>
                    <option value="RECEBIDO">RECEBIDO</option>
                    <option value="CANCELADO">CANCELADO</option>
                  </select>
                </label>

                <label className="text-xs text-zinc-400">
                  Pedido compra cliente
                  <input
                    className="mt-1 w-full px-3 py-2"
                    value={edit.pedidoCompraCliente}
                    onChange={(e) => setEdit((p) => ({ ...p, pedidoCompraCliente: e.target.value }))}
                    disabled={!canWrite || edit.busy}
                  />
                </label>

                <label className="text-xs text-zinc-400">
                  Pedido recebido em
                  <input
                    type="date"
                    className="mt-1 w-full px-3 py-2"
                    value={edit.pedidoRecebidoEm}
                    onChange={(e) => setEdit((p) => ({ ...p, pedidoRecebidoEm: e.target.value }))}
                    disabled={!canWrite || edit.busy}
                  />
                </label>

                <label className="text-xs text-zinc-400">
                  Próximo contato
                  <input
                    type="date"
                    className="mt-1 w-full px-3 py-2"
                    value={edit.proximoContatoDate}
                    onChange={(e) => setEdit((p) => ({ ...p, proximoContatoDate: e.target.value }))}
                    disabled={!canWrite || edit.busy}
                  />
                </label>

                <label className="text-xs text-zinc-400 md:col-span-2">
                  Responsável
                  <select
                    className="mt-1 w-full px-3 py-2"
                    value={edit.responsavelId}
                    onChange={(e) => setEdit((p) => ({ ...p, responsavelId: e.target.value }))}
                    disabled={!canWrite || edit.busy}
                  >
                    <option value="">(Não definido)</option>
                    {responsaveis.map((u) => (
                      <option key={u.id} value={u.id}>
                        {u.nome}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="text-xs text-zinc-400 md:col-span-2">
                  Observação
                  <textarea
                    className="mt-1 w-full px-3 py-2 min-h-[90px]"
                    value={edit.observacao}
                    onChange={(e) => setEdit((p) => ({ ...p, observacao: e.target.value }))}
                    disabled={!canWrite || edit.busy}
                  />
                </label>
              </div>

              {edit.error ? <div className="text-sm text-red-300">{edit.error}</div> : null}
            </div>

            <div className="px-5 py-4 border-t border-zinc-800 flex justify-end gap-2">
              <button type="button" onClick={closeEdit} className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800">
                Cancelar
              </button>
              <button
                type="button"
                onClick={() => void saveEdit()}
                disabled={!canWrite || edit.busy}
                className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white disabled:opacity-60"
              >
                {edit.busy ? "Salvando..." : "Salvar"}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
