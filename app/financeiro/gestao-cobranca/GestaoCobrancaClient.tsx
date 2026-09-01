"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { formatMoneyBR } from "@/lib/decimal";
import PeriodoMesAnoFilter, { buildPeriodoMesAnoRange } from "@/app/faturamento/components/PeriodoMesAnoFilter";

type SupabaseBrowser = ReturnType<typeof getSupabaseBrowser>;

type DocumentoFiscalRow = {
  id: string;
  emissao_date: string | null;
  modelo: string | null;
  serie: string | null;
  numero: string | null;
  chave_acesso: string | null;
  natureza: "PRODUTO" | "SERVICO" | string | null;
  cliente_id: number | null;
  valor_total: number | string | null;
  created_at: string;
};

type TituloFinanceiroRow = {
  id: string;
  documento_fiscal_id: string;
  tipo: string | null;
  status: string | null;
  valor_total: number | string | null;
  valor_aberto: number | string | null;
};

type ParcelaFinanceiraRow = {
  id: string;
  titulo_id: string;
  vencimento_date: string | null;
  valor: number | string | null;
  valor_aberto: number | string | null;
};

type ClienteRow = {
  id: number;
  nome: string | null;
};

type PagamentoFiltro = "TODOS" | "PAGOS" | "A_PAGAR" | "ATRASADOS";

type PagamentoMeta = {
  pago: number;
  aReceber: number;
  emAtraso: number;
};

type ClienteResumo = {
  key: string;
  clienteId: number | null;
  clienteNome: string;
  pago: number;
  aReceber: number;
  emAtraso: number;
  total: number;
  searchText: string;
};

const BASE_PATH = "/financeiro/gestao-cobranca";
const FETCH_BATCH_SIZE = 1000;
const IN_BATCH_SIZE = 400;
const PAYMENT_EPSILON = 0.009;

function n(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}

function todayIsoDate(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function isPastDue(vencimentoDate?: string | null): boolean {
  const normalized = String(vencimentoDate ?? "").slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(normalized)) return false;
  return normalized < todayIsoDate();
}

function normalizePagamentoFiltro(value: string | null): PagamentoFiltro {
  const normalized = String(value ?? "")
    .trim()
    .toUpperCase()
    .replace(/-/g, "_");

  switch (normalized) {
    case "PAGOS":
    case "PAGO":
      return "PAGOS";
    case "A_PAGAR":
    case "APAGAR":
    case "EM_ABERTO":
      return "A_PAGAR";
    case "ATRASADOS":
    case "ATRASADO":
      return "ATRASADOS";
    default:
      return "TODOS";
  }
}

function buildPagamentoFallback(row: DocumentoFiscalRow): PagamentoMeta {
  const total = Math.max(0, n(row.valor_total));
  if (total <= PAYMENT_EPSILON) return { pago: 0, aReceber: 0, emAtraso: 0 };
  return { pago: 0, aReceber: total, emAtraso: 0 };
}

function computePagamentoMeta(
  row: DocumentoFiscalRow,
  titulos: TituloFinanceiroRow[],
  parcelasByTituloId: Record<string, ParcelaFinanceiraRow[]>
): PagamentoMeta {
  if (!titulos.length) return buildPagamentoFallback(row);

  const totalTitulos = titulos.reduce((sum, titulo) => sum + n(titulo.valor_total), 0);
  const totalAberto = titulos.reduce((sum, titulo) => sum + n(titulo.valor_aberto), 0);
  const parcelasEmAberto = titulos.flatMap((titulo) =>
    (parcelasByTituloId[String(titulo.id)] ?? []).filter((parcela) => n(parcela.valor_aberto) > PAYMENT_EPSILON)
  );
  const emAtraso = parcelasEmAberto.reduce(
    (sum, parcela) => (isPastDue(parcela.vencimento_date) ? sum + Math.max(0, n(parcela.valor_aberto)) : sum),
    0
  );

  return {
    pago: Math.max(0, totalTitulos - totalAberto),
    aReceber: Math.max(0, totalAberto - emAtraso),
    emAtraso: Math.max(0, emAtraso),
  };
}

function matchesPagamentoFiltro(row: ClienteResumo, filtro: PagamentoFiltro): boolean {
  if (filtro === "PAGOS") return row.pago > PAYMENT_EPSILON;
  if (filtro === "A_PAGAR") return row.aReceber > PAYMENT_EPSILON;
  if (filtro === "ATRASADOS") return row.emAtraso > PAYMENT_EPSILON;
  return true;
}

function pagamentoResumoLabel(filtro: PagamentoFiltro): string {
  if (filtro === "PAGOS") return "Total pago";
  if (filtro === "A_PAGAR") return "Total a receber";
  if (filtro === "ATRASADOS") return "Total em atraso";
  return "Valor total filtrado";
}

function pagamentoResumoValor(
  filtro: PagamentoFiltro,
  totals: { total: number; pago: number; aReceber: number; emAtraso: number }
): number {
  if (filtro === "PAGOS") return totals.pago;
  if (filtro === "A_PAGAR") return totals.aReceber;
  if (filtro === "ATRASADOS") return totals.emAtraso;
  return totals.total;
}

async function fetchAllDocumentos(
  supabase: SupabaseBrowser,
  tenantId: string,
  empresaId: string,
  periodo: { startDate: string | null; endDate: string | null }
): Promise<DocumentoFiscalRow[]> {
  const rows: DocumentoFiscalRow[] = [];
  let offset = 0;

  while (true) {
    let query = applyTenantEmpresa(
      supabase
        .schema("f")
        .from("documento_fiscal")
        .select("id,emissao_date,modelo,serie,numero,chave_acesso,natureza,cliente_id,valor_total,created_at")
        .eq("operacao", "SAIDA")
        .in("natureza", ["PRODUTO", "SERVICO"])
        .is("deleted_at", null),
      tenantId,
      empresaId
    )
      .order("emissao_date", { ascending: false, nullsFirst: false })
      .order("created_at", { ascending: false })
      .range(offset, offset + FETCH_BATCH_SIZE - 1);

    if (periodo.startDate) {
      query = query.gte("emissao_date", periodo.startDate);
    }
    if (periodo.endDate) {
      query = query.lte("emissao_date", periodo.endDate);
    }

    const { data, error } = await query.returns<DocumentoFiscalRow[]>();
    if (error) throw error;

    const batch = data ?? [];
    rows.push(...batch);
    if (batch.length < FETCH_BATCH_SIZE) break;
    offset += FETCH_BATCH_SIZE;
  }

  return rows;
}

async function fetchClientesById(
  supabase: SupabaseBrowser,
  tenantId: string,
  empresaId: string,
  clienteIds: number[]
): Promise<Record<string, string>> {
  const result: Record<string, string> = {};
  const uniqueIds = Array.from(new Set(clienteIds.filter((id) => Number.isFinite(id))));

  for (const ids of chunk(uniqueIds, IN_BATCH_SIZE)) {
    const { data, error } = await applyTenantEmpresa(
      supabase.from("clientes").select("id,nome").in("id", ids),
      tenantId,
      empresaId
    ).returns<ClienteRow[]>();
    if (error) throw error;

    for (const cliente of data ?? []) {
      if (typeof cliente.id !== "number") continue;
      const nome = String(cliente.nome ?? "").trim();
      result[String(cliente.id)] = nome || `Cliente ID ${cliente.id}`;
    }
  }

  return result;
}

async function fetchPagamentosByDocumentoId(
  supabase: SupabaseBrowser,
  tenantId: string,
  empresaId: string,
  documentos: DocumentoFiscalRow[]
): Promise<Record<string, PagamentoMeta>> {
  const documentoIds = Array.from(new Set(documentos.map((row) => String(row.id)).filter(Boolean)));
  if (!documentoIds.length) return {};

  const titulos: TituloFinanceiroRow[] = [];
  for (const ids of chunk(documentoIds, IN_BATCH_SIZE)) {
    const { data, error } = await applyTenantEmpresa(
      supabase
        .schema("f")
        .from("titulo")
        .select("id,documento_fiscal_id,tipo,status,valor_total,valor_aberto")
        .in("documento_fiscal_id", ids)
        .is("deleted_at", null),
      tenantId,
      empresaId
    ).returns<TituloFinanceiroRow[]>();
    if (error) throw error;

    titulos.push(
      ...((data ?? []).filter((titulo) => {
        const tipo = String(titulo.tipo ?? "").trim().toUpperCase();
        const status = String(titulo.status ?? "").trim().toUpperCase();
        return tipo === "AR" && status !== "CANCELADO";
      }) as TituloFinanceiroRow[])
    );
  }

  const tituloIds = titulos.map((titulo) => String(titulo.id)).filter(Boolean);
  const parcelas: ParcelaFinanceiraRow[] = [];
  for (const ids of chunk(tituloIds, IN_BATCH_SIZE)) {
    const { data, error } = await applyTenantEmpresa(
      supabase
        .schema("f")
        .from("titulo_parcela")
        .select("id,titulo_id,vencimento_date,valor,valor_aberto")
        .in("titulo_id", ids)
        .is("deleted_at", null),
      tenantId,
      empresaId
    ).returns<ParcelaFinanceiraRow[]>();
    if (error) throw error;
    parcelas.push(...(data ?? []));
  }

  const titulosByDocumentoId: Record<string, TituloFinanceiroRow[]> = {};
  for (const titulo of titulos) {
    const documentoId = String(titulo.documento_fiscal_id ?? "");
    if (!documentoId) continue;
    if (!titulosByDocumentoId[documentoId]) titulosByDocumentoId[documentoId] = [];
    titulosByDocumentoId[documentoId].push(titulo);
  }

  const parcelasByTituloId: Record<string, ParcelaFinanceiraRow[]> = {};
  for (const parcela of parcelas) {
    const tituloId = String(parcela.titulo_id ?? "");
    if (!tituloId) continue;
    if (!parcelasByTituloId[tituloId]) parcelasByTituloId[tituloId] = [];
    parcelasByTituloId[tituloId].push(parcela);
  }

  const result: Record<string, PagamentoMeta> = {};
  for (const documento of documentos) {
    result[String(documento.id)] = computePagamentoMeta(
      documento,
      titulosByDocumentoId[String(documento.id)] ?? [],
      parcelasByTituloId
    );
  }

  return result;
}

function buildClienteResumoRows(
  documentos: DocumentoFiscalRow[],
  clientesById: Record<string, string>,
  pagamentosByDocumentoId: Record<string, PagamentoMeta>
): ClienteResumo[] {
  const rowsByCliente = new Map<string, ClienteResumo>();

  for (const documento of documentos) {
    const clienteId = typeof documento.cliente_id === "number" ? documento.cliente_id : null;
    const key = clienteId === null ? "sem-cliente" : `cliente-${clienteId}`;
    const clienteNome = clienteId === null ? "Sem cliente" : clientesById[String(clienteId)] ?? `Cliente ID ${clienteId}`;
    const pagamento = pagamentosByDocumentoId[String(documento.id)] ?? buildPagamentoFallback(documento);
    const current =
      rowsByCliente.get(key) ??
      ({
        key,
        clienteId,
        clienteNome,
        pago: 0,
        aReceber: 0,
        emAtraso: 0,
        total: 0,
        searchText: clienteNome.toLowerCase(),
      } satisfies ClienteResumo);

    current.pago += pagamento.pago;
    current.aReceber += pagamento.aReceber;
    current.emAtraso += pagamento.emAtraso;
    current.total = current.pago + current.aReceber + current.emAtraso;
    current.searchText = `${current.searchText} ${documento.numero ?? ""} ${documento.chave_acesso ?? ""} ${
      documento.modelo ?? ""
    } ${documento.serie ?? ""}`.toLowerCase();

    rowsByCliente.set(key, current);
  }

  return Array.from(rowsByCliente.values()).sort((a, b) => {
    const totalDiff = b.total - a.total;
    if (Math.abs(totalDiff) > PAYMENT_EPSILON) return totalDiff;
    return a.clienteNome.localeCompare(b.clienteNome, "pt-BR");
  });
}

export default function GestaoCobrancaClient() {
  const te = useTenantEmpresa();
  const router = useRouter();
  const searchParams = useSearchParams();
  const supabase = useMemo(() => getSupabaseBrowser(), []);

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [rows, setRows] = useState<ClienteResumo[]>([]);
  const [search, setSearch] = useState("");

  const empresaRole = useMemo(() => {
    const role = te.empresa?.papel ?? te.empresas.find((e) => e.id === te.empresaId)?.papel ?? null;
    return typeof role === "string" ? role.trim().toUpperCase() : "";
  }, [te.empresa?.papel, te.empresaId, te.empresas]);
  const isFinanceiroEmpresaRole = empresaRole === "FINANCEIRO";

  const canFinanceiro = useMemo(() => {
    const r = te.has("financeiro.read");
    const w = te.has("financeiro.write");
    if (isFinanceiroEmpresaRole) return true;
    if (r === undefined || w === undefined) return undefined;
    return Boolean(r || w);
  }, [isFinanceiroEmpresaRole, te]);

  const tenantId = te.tenantId ?? null;
  const empresaId = te.empresaId ?? (te.empresas.length === 1 ? te.empresas[0]?.id ?? null : null);
  const ready =
    typeof te.sessionUserId === "string" &&
    Boolean(tenantId) &&
    Boolean(empresaId) &&
    canFinanceiro === true;

  const pagamentoFiltro = normalizePagamentoFiltro(searchParams.get("pagamento"));
  const periodo = useMemo(() => buildPeriodoMesAnoRange(searchParams), [searchParams]);

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  const setPagamentoFiltro = useCallback(
    (filtro: PagamentoFiltro) => {
      const params = new URLSearchParams(searchParams.toString());
      if (filtro === "TODOS") {
        params.delete("pagamento");
      } else {
        params.set("pagamento", filtro.toLowerCase());
      }
      const nextUrl = params.toString() ? `${BASE_PATH}?${params.toString()}` : BASE_PATH;
      router.replace(nextUrl, { scroll: false });
    },
    [router, searchParams]
  );

  const load = useCallback(async () => {
    if (!ready || !tenantId || !empresaId) return;

    setLoading(true);
    setError(null);

    try {
      const documentos = await fetchAllDocumentos(supabase, tenantId, empresaId, {
        startDate: periodo.startDate,
        endDate: periodo.endDate,
      });
      const clienteIds = documentos
        .map((documento) => documento.cliente_id)
        .filter((id): id is number => typeof id === "number");

      const [clientesById, pagamentosByDocumentoId] = await Promise.all([
        fetchClientesById(supabase, tenantId, empresaId, clienteIds),
        fetchPagamentosByDocumentoId(supabase, tenantId, empresaId, documentos),
      ]);

      setRows(buildClienteResumoRows(documentos, clientesById, pagamentosByDocumentoId));
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro ao carregar gestao de cobrancas.");
      setRows([]);
    } finally {
      setLoading(false);
    }
  }, [empresaId, periodo.endDate, periodo.startDate, ready, supabase, tenantId]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, [load]);

  const filteredRows = useMemo(() => {
    const term = search.trim().toLowerCase();
    return rows
      .filter((row) => matchesPagamentoFiltro(row, pagamentoFiltro))
      .filter((row) => (term ? row.searchText.includes(term) : true));
  }, [pagamentoFiltro, rows, search]);

  const resumoFiltro = useMemo(() => {
    const totals = filteredRows.reduce(
      (acc, row) => {
        acc.pago += row.pago;
        acc.aReceber += row.aReceber;
        acc.emAtraso += row.emAtraso;
        acc.total += row.total;
        return acc;
      },
      { total: 0, pago: 0, aReceber: 0, emAtraso: 0 }
    );

    return {
      label: pagamentoResumoLabel(pagamentoFiltro),
      value: pagamentoResumoValor(pagamentoFiltro, totals),
      ...totals,
    };
  }, [filteredRows, pagamentoFiltro]);

  return (
    <div className="w-full px-4 py-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-zinc-100">Gestao de cobrancas</h1>
          <p className="text-sm text-zinc-400">Resumo por cliente de notas de material e servico.</p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href="/financeiro/venda-a-credito"
            className="rounded-md border border-emerald-500/40 bg-emerald-500/10 px-3 py-2 text-sm text-emerald-200 hover:bg-emerald-500/20"
          >
            Venda a crédito
          </Link>
          <Link
            href="/financeiro"
            className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-900"
          >
            Financeiro
          </Link>
          <button
            type="button"
            onClick={() => void load()}
            disabled={loading || !ready}
            className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-900 disabled:opacity-50"
          >
            Atualizar
          </button>
        </div>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-[minmax(0,1fr)_auto]">
        <div>
          <label className="block text-xs font-medium text-zinc-400">Buscar</label>
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Cliente, numero, chave de acesso ou parceiro"
            className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 placeholder:text-zinc-500 focus:outline-none focus:ring-2 focus:ring-zinc-700"
          />
        </div>

        <div className="lg:min-w-[360px]">
          <label className="block text-xs font-medium text-zinc-400">Pagamento</label>
          <div className="mt-1 flex flex-wrap gap-2">
            {[
              { value: "TODOS" as const, label: "Todos" },
              { value: "PAGOS" as const, label: "Pagos" },
              { value: "A_PAGAR" as const, label: "A pagar" },
              { value: "ATRASADOS" as const, label: "Atrasados" },
            ].map((option) => {
              const active = pagamentoFiltro === option.value;
              return (
                <button
                  key={option.value}
                  type="button"
                  onClick={() => setPagamentoFiltro(option.value)}
                  className={[
                    "rounded-md border px-3 py-2 text-sm transition-colors",
                    active
                      ? "border-zinc-600 bg-zinc-800 text-zinc-100"
                      : "border-zinc-800 bg-zinc-950 text-zinc-300 hover:bg-zinc-900",
                  ].join(" ")}
                >
                  {option.label}
                </button>
              );
            })}
          </div>
        </div>
      </div>

      <PeriodoMesAnoFilter basePath={BASE_PATH} />

      <div className="mt-4 rounded-lg border border-zinc-800 bg-zinc-950 px-4 py-4">
        <div className="text-xs font-medium uppercase tracking-wide text-zinc-500">Resumo</div>
        <div className="mt-2 flex flex-wrap items-end justify-between gap-4">
          <div>
            <div className="text-sm text-zinc-400">{resumoFiltro.label}</div>
            <div className="mt-1 text-2xl font-semibold tabular-nums text-zinc-100">
              {formatMoneyBR(resumoFiltro.value)}
            </div>
          </div>
          <div className="grid gap-2 text-right sm:grid-cols-3 sm:gap-4">
            <div>
              <div className="text-xs uppercase tracking-wide text-zinc-500">Pago</div>
              <div className="text-sm font-medium tabular-nums text-emerald-300">{formatMoneyBR(resumoFiltro.pago)}</div>
            </div>
            <div>
              <div className="text-xs uppercase tracking-wide text-zinc-500">A receber</div>
              <div className="text-sm font-medium tabular-nums text-amber-200">{formatMoneyBR(resumoFiltro.aReceber)}</div>
            </div>
            <div>
              <div className="text-xs uppercase tracking-wide text-zinc-500">Em atraso</div>
              <div className="text-sm font-medium tabular-nums text-rose-300">{formatMoneyBR(resumoFiltro.emAtraso)}</div>
            </div>
          </div>
        </div>
      </div>

      <div className="mt-4 overflow-hidden rounded-lg border border-zinc-800 bg-zinc-950">
        <div className="flex items-center justify-between border-b border-zinc-800 px-4 py-3">
          <div className="text-sm text-zinc-200">{loading ? "Carregando..." : `${filteredRows.length} cliente(s)`}</div>
          <button
            type="button"
            onClick={() => void load()}
            className="text-sm text-zinc-300 hover:text-zinc-100 disabled:opacity-50"
            disabled={loading || !ready}
          >
            Recarregar
          </button>
        </div>

        {error ? <div className="px-4 py-3 text-sm text-rose-200">{error}</div> : null}

        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-zinc-950/60 text-zinc-400">
              <tr>
                <th className="px-4 py-3 text-left font-medium">Cliente</th>
                <th className="px-4 py-3 text-right font-medium">Pago</th>
                <th className="px-4 py-3 text-right font-medium">A receber</th>
                <th className="px-4 py-3 text-right font-medium">Em atraso</th>
                <th className="px-4 py-3 text-right font-medium">Total</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {!loading && filteredRows.length === 0 ? (
                <tr>
                  <td className="px-4 py-6 text-center text-zinc-500" colSpan={5}>
                    Nenhum cliente encontrado.
                  </td>
                </tr>
              ) : null}

              {filteredRows.map((row) => (
                <tr key={row.key} className="hover:bg-zinc-900/40">
                  <td className="px-4 py-3 text-left text-zinc-100">
                    <div className="font-medium">{row.clienteNome}</div>
                    {row.clienteId === null ? <div className="mt-1 text-xs text-zinc-500">Sem cliente vinculado</div> : null}
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums text-emerald-300">{formatMoneyBR(row.pago)}</td>
                  <td className="px-4 py-3 text-right tabular-nums text-amber-200">{formatMoneyBR(row.aReceber)}</td>
                  <td className="px-4 py-3 text-right tabular-nums text-rose-300">{formatMoneyBR(row.emAtraso)}</td>
                  <td className="px-4 py-3 text-right tabular-nums font-medium text-zinc-100">{formatMoneyBR(row.total)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
