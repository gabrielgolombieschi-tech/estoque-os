"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { formatMoneyBR } from "@/lib/decimal";

type DocumentoFiscalRow = {
  id: string;
  emissao_date: string | null;
  modelo: string | null;
  serie: string | null;
  numero: string | null;
  chave_acesso: string;
  cliente_id: number | null;
  valor_total: number | string | null;
  nfse_status: "RASCUNHO" | "EMITIDA" | "CANCELADA" | "SUBSTITUIDA" | string | null;
  created_at: string;
};

type ClienteRow = { id: number; nome: string };

const PAGE_SIZE = 50;
const NFSE_STATUSES = ["RASCUNHO", "EMITIDA", "CANCELADA", "SUBSTITUIDA"] as const;
type NfseStatusFilter = "" | (typeof NFSE_STATUSES)[number];

function n(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  return Number.isFinite(num) ? num : 0;
}

function formatDateBR(iso?: string | null): string {
  if (!iso) return "";
  const d = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleDateString("pt-BR");
}

function pillForStatus(status: string) {
  const s = String(status || "").toUpperCase();
  if (s === "RASCUNHO") return "bg-zinc-700/40 text-zinc-200 border-zinc-700";
  if (s === "EMITIDA") return "bg-emerald-500/15 text-emerald-200 border-emerald-500/30";
  if (s === "CANCELADA") return "bg-rose-500/15 text-rose-200 border-rose-500/30";
  if (s === "SUBSTITUIDA") return "bg-amber-500/15 text-amber-200 border-amber-500/30";
  return "bg-zinc-800 text-zinc-200 border-zinc-700";
}

function StatusPill({ status }: { status: string | null }) {
  const label = String(status || "").toUpperCase() || "—";
  return (
    <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-xs ${pillForStatus(label)}`}>
      {label}
    </span>
  );
}

export default function NfseList() {
  const te = useTenantEmpresa();
  const router = useRouter();

  const canFinanceiro = useMemo(() => {
    const r = te.has("financeiro.read");
    const w = te.has("financeiro.write");
    if (r === undefined || w === undefined) return undefined;
    return Boolean(r || w);
  }, [te]);

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  const [docs, setDocs] = useState<DocumentoFiscalRow[]>([]);
  const [clientesById, setClientesById] = useState<Record<string, string>>({});

  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);

  const [search, setSearch] = useState("");
  const [status, setStatus] = useState<NfseStatusFilter>("");

  const ready =
    typeof te.sessionUserId === "string" &&
    Boolean(te.tenantId) &&
    (Boolean(te.empresaId) || te.empresas.length === 1) &&
    canFinanceiro === true;

  const resolveClientes = async (rows: DocumentoFiscalRow[]) => {
    if (!te.tenantId) return;
    const ids = Array.from(
      new Set(
        rows
          .map((r) => (typeof r.cliente_id === "number" ? r.cliente_id : null))
          .filter((v): v is number => typeof v === "number")
      )
    );
    const missing = ids.filter((id) => !(String(id) in clientesById));
    if (!missing.length) return;

    const supabase = supabaseBrowser();
    const tenantId = te.tenantId;
    const empresaId = te.empresaId ?? te.empresas[0]?.id ?? "";

    const q = applyTenantEmpresa(
      supabase.from("clientes").select("id,nome").in("id", missing),
      tenantId,
      empresaId
    );

    const { data, error: cErr } = await q.returns<ClienteRow[]>();
    if (cErr) throw cErr;

    setClientesById((prev) => {
      const next = { ...prev };
      for (const c of data ?? []) {
        if (typeof c?.id === "number") next[String(c.id)] = String(c.nome ?? "");
      }
      return next;
    });
  };

  const fetchDocs = async (offset: number) => {
    if (!ready) return { rows: [] as DocumentoFiscalRow[], more: false };

    const supabase = supabaseBrowser();
    const tenantId = te.tenantId!;
    const empresaId = te.empresaId ?? te.empresas[0]!.id;

    let query = applyTenantEmpresa(
      supabase
        .schema("f")
        .from("documento_fiscal")
        .select("id,emissao_date,modelo,serie,numero,chave_acesso,cliente_id,valor_total,nfse_status,created_at")
        .eq("operacao", "SAIDA")
        .eq("natureza", "SERVICO")
        .is("deleted_at", null),
      tenantId,
      empresaId
    )
      .order("emissao_date", { ascending: false, nullsFirst: false })
      .order("created_at", { ascending: false })
      .range(offset, offset + PAGE_SIZE - 1);

    const { data, error: qErr } = await query;
    if (qErr) throw qErr;

    const rows = (data ?? []) as unknown as DocumentoFiscalRow[];
    return { rows, more: rows.length === PAGE_SIZE };
  };

  const reload = async () => {
    if (!ready) return;

    setLoading(true);
    setError(null);
    try {
      const { rows, more } = await fetchDocs(0);
      setDocs(rows);
      setHasMore(more);
      await resolveClientes(rows);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro inesperado ao carregar NFS-e.");
      setDocs([]);
      setHasMore(false);
    } finally {
      setLoading(false);
    }
  };

  const loadMore = async () => {
    if (loadingMore || loading) return;
    if (!hasMore) return;
    if (!ready) return;

    setLoadingMore(true);
    setError(null);
    try {
      const offset = docs.length;
      const { rows, more } = await fetchDocs(offset);
      setDocs((prev) => [...prev, ...rows]);
      setHasMore(more);
      await resolveClientes(rows);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro inesperado ao carregar mais NFS-e.");
    } finally {
      setLoadingMore(false);
    }
  };

  useEffect(() => {
    if (!ready) return;
    void reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, canFinanceiro, te.sessionUserId, te.tenantId, te.empresaId, te.empresas.length]);

  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();
    const statusUpper = status ? status.toUpperCase() : "";

    return docs.filter((r) => {
      if (statusUpper) {
        const rowStatus = String(r.nfse_status ?? "").toUpperCase();
        if (rowStatus !== statusUpper) return false;
      }

      if (!term) return true;
      const numero = String(r.numero ?? "").toLowerCase();
      const modelo = String(r.modelo ?? "").toLowerCase();
      const serie = String(r.serie ?? "").toLowerCase();
      const clienteNome = r.cliente_id ? String(clientesById[String(r.cliente_id)] ?? "").toLowerCase() : "";
      return (
        numero.includes(term) ||
        clienteNome.includes(term) ||
        `${modelo} ${serie} ${numero}`.replace(/\\s+/g, " ").trim().includes(term)
      );
    });
  }, [clientesById, docs, search, status]);

  const headerRight = (
    <Link
      href="/faturamento/nfse/novo"
      className="inline-flex items-center rounded-md bg-zinc-800 px-3 py-2 text-sm font-medium text-zinc-100 hover:bg-zinc-700"
    >
      Novo
    </Link>
  );

  return (
    <div className="mx-auto max-w-6xl px-4 py-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold text-zinc-100">NFS-e</h1>
          <p className="text-sm text-zinc-400">Listagem (somente leitura)</p>
        </div>
        {headerRight}
      </div>

      <div className="mt-4 grid gap-3 md:grid-cols-3">
        <div className="md:col-span-2">
          <label className="block text-xs font-medium text-zinc-400">Buscar</label>
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Número, modelo/série ou cliente"
            className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 placeholder:text-zinc-500 focus:outline-none focus:ring-2 focus:ring-zinc-700"
          />
        </div>

        <div>
          <label className="block text-xs font-medium text-zinc-400">Status</label>
          <select
            value={status}
            onChange={(e) => setStatus(e.target.value as NfseStatusFilter)}
            className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-700"
          >
            <option value="">Todos</option>
            {NFSE_STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div className="mt-4 rounded-xl border border-zinc-800 bg-zinc-950 overflow-hidden">
        <div className="px-4 py-3 border-b border-zinc-800 flex items-center justify-between">
          <div className="text-sm text-zinc-200">
            {loading ? "Carregando..." : `${filtered.length} registro(s)`}
          </div>
          <button
            type="button"
            onClick={() => void reload()}
            className="text-sm text-zinc-300 hover:text-zinc-100"
            disabled={loading || loadingMore}
          >
            Recarregar
          </button>
        </div>

        {error ? <div className="px-4 py-3 text-sm text-rose-200">{error}</div> : null}

        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-zinc-950/60 text-zinc-400">
              <tr>
                <th className="px-4 py-3 text-left font-medium">Emissão</th>
                <th className="px-4 py-3 text-left font-medium">Modelo</th>
                <th className="px-4 py-3 text-left font-medium">Série</th>
                <th className="px-4 py-3 text-left font-medium">Número</th>
                <th className="px-4 py-3 text-left font-medium">Cliente</th>
                <th className="px-4 py-3 text-right font-medium">Valor</th>
                <th className="px-4 py-3 text-left font-medium">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {!loading && filtered.length === 0 ? (
                <tr>
                  <td className="px-4 py-6 text-center text-zinc-500" colSpan={7}>
                    Nenhum registro encontrado.
                  </td>
                </tr>
              ) : null}

              {filtered.map((r) => (
                <tr
                  key={r.id}
                  className="hover:bg-zinc-900/40 cursor-pointer"
                  onClick={() => router.push(`/faturamento/nfse/${r.id}`)}
                >
                  <td className="px-4 py-3 text-zinc-200 whitespace-nowrap">{formatDateBR(r.emissao_date) || "—"}</td>
                  <td className="px-4 py-3 text-zinc-200">{r.modelo ?? "—"}</td>
                  <td className="px-4 py-3 text-zinc-200">{r.serie ?? "—"}</td>
                  <td className="px-4 py-3 text-zinc-200 tabular-nums">{r.numero ?? "—"}</td>
                  <td className="px-4 py-3 text-zinc-200">
                    {typeof r.cliente_id === "number" ? clientesById[String(r.cliente_id)] ?? `ID ${r.cliente_id}` : "—"}
                  </td>
                  <td className="px-4 py-3 text-right text-zinc-200 tabular-nums">{formatMoneyBR(n(r.valor_total))}</td>
                  <td className="px-4 py-3 text-zinc-200">
                    <StatusPill status={r.nfse_status} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="px-4 py-3 border-t border-zinc-800 flex items-center justify-between">
          <div className="text-xs text-zinc-500">{docs.length} carregado(s)</div>
          {hasMore ? (
            <button
              type="button"
              onClick={() => void loadMore()}
              disabled={loadingMore || loading}
              className="rounded-md bg-zinc-800 px-3 py-2 text-sm text-zinc-100 hover:bg-zinc-700 disabled:opacity-50"
            >
              {loadingMore ? "Carregando..." : "Carregar mais"}
            </button>
          ) : (
            <div className="text-xs text-zinc-500">Fim da lista</div>
          )}
        </div>
      </div>
    </div>
  );
}
