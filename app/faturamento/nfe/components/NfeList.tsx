"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { formatMoneyBR } from "@/lib/decimal";
import NfeImportModal from "./NfeImportModal";

type DocumentoFiscalRow = {
  id: string;
  operacao: "ENTRADA" | "SAIDA" | string;
  emissao_date: string | null;
  modelo: string | null;
  serie: string | null;
  numero: string | null;
  chave_acesso: string;
  cliente_id: number | null;
  fornecedor_id: number | null;
  valor_total: number | string | null;
  nfe_status?: string | null;
  created_at: string;
};

type ClienteRow = { id: number; nome: string };
type FornecedorRow = { id: number; nome: string | null };

const PAGE_SIZE = 50;

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

function shortKey(key: string): string {
  const k = String(key || "");
  if (k.length <= 12) return k;
  return `${k.slice(0, 4)}…${k.slice(-6)}`;
}

export default function NfeList() {
  const te = useTenantEmpresa();
  const router = useRouter();
  const searchParams = useSearchParams();

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

  useEffect(() => {
    if (canFinanceiro === false) router.replace("/forbidden");
  }, [canFinanceiro, router]);

  const [docs, setDocs] = useState<DocumentoFiscalRow[]>([]);
  const [clientesById, setClientesById] = useState<Record<string, string>>({});
  const [fornecedoresById, setFornecedoresById] = useState<Record<string, string>>({});

  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);

  const [search, setSearch] = useState("");
  const [importOpen, setImportOpen] = useState(false);

  const canImportXmlFaturamento = useMemo(() => {
    const can = te.has("xml_import_faturamento.execute");
    if (can === undefined) return undefined;
    return Boolean(can);
  }, [te]);

  useEffect(() => {
    const wantsImport = searchParams.get("import");
    if (!wantsImport) return;
    if (wantsImport !== "1" && wantsImport.toLowerCase() !== "true") return;
    if (canImportXmlFaturamento !== true) return;
    setImportOpen(true);
  }, [canImportXmlFaturamento, searchParams]);

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

  const resolveFornecedores = async (rows: DocumentoFiscalRow[]) => {
    if (!te.tenantId) return;
    const ids = Array.from(
      new Set(
        rows
          .map((r) => (typeof r.fornecedor_id === "number" ? r.fornecedor_id : null))
          .filter((v): v is number => typeof v === "number")
      )
    );
    const missing = ids.filter((id) => !(String(id) in fornecedoresById));
    if (!missing.length) return;

    const supabase = supabaseBrowser();
    const tenantId = te.tenantId;
    const empresaId = te.empresaId ?? te.empresas[0]?.id ?? "";

    const { data, error: fErr } = await applyTenantEmpresa(
      supabase.from("fornecedores").select("id,nome").in("id", missing),
      tenantId,
      empresaId
    ).returns<FornecedorRow[]>();
    if (fErr) throw fErr;

    setFornecedoresById((prev) => {
      const next = { ...prev };
      for (const f of data ?? []) {
        if (typeof f?.id === "number") next[String(f.id)] = String(f.nome ?? "");
      }
      return next;
    });
  };

  const fetchDocs = async (offset: number) => {
    if (!ready) return { rows: [] as DocumentoFiscalRow[], more: false };

    const supabase = supabaseBrowser();
    const tenantId = te.tenantId!;
    const empresaId = te.empresaId ?? te.empresas[0]!.id;

    const query = applyTenantEmpresa(
      supabase
        .schema("f")
        .from("documento_fiscal")
        .select("id,operacao,emissao_date,modelo,serie,numero,chave_acesso,cliente_id,fornecedor_id,valor_total,nfe_status,created_at")
        .eq("operacao", "SAIDA")
        .eq("natureza", "PRODUTO")
        .or("modelo.is.null,modelo.neq.NFSE")
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
      await resolveFornecedores(rows);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro inesperado ao carregar NF-e.");
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
      await resolveFornecedores(rows);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erro inesperado ao carregar mais NF-e.");
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
    if (!term) return docs;

    return docs.filter((r) => {
      const numero = String(r.numero ?? "").toLowerCase();
      const modelo = String(r.modelo ?? "").toLowerCase();
      const serie = String(r.serie ?? "").toLowerCase();
      const chave = String(r.chave_acesso ?? "").toLowerCase();
      const clienteNome = r.cliente_id ? String(clientesById[String(r.cliente_id)] ?? "").toLowerCase() : "";
      const fornecedorNome = r.fornecedor_id ? String(fornecedoresById[String(r.fornecedor_id)] ?? "").toLowerCase() : "";
      return (
        numero.includes(term) ||
        clienteNome.includes(term) ||
        fornecedorNome.includes(term) ||
        chave.includes(term) ||
        `${modelo} ${serie} ${numero}`.replace(/\\s+/g, " ").trim().includes(term)
      );
    });
  }, [clientesById, docs, fornecedoresById, search]);

  const headerRight = canImportXmlFaturamento ? (
    <button
      type="button"
      onClick={() => setImportOpen(true)}
      className="inline-flex items-center rounded-md bg-zinc-800 px-3 py-2 text-sm font-medium text-zinc-100 hover:bg-zinc-700"
    >
      Importar XML
    </button>
  ) : null;

  return (
    <div className="mx-auto max-w-6xl px-4 py-6">
      <NfeImportModal
        open={importOpen}
        onClose={() => {
          setImportOpen(false);
          if (searchParams.get("import")) router.replace("/faturamento/nfe");
        }}
      />
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold text-zinc-100">NF-e</h1>
          <p className="text-sm text-zinc-400">Listagem (somente leitura)</p>
        </div>
        {headerRight}
      </div>

      <div className="mt-4">
        <label className="block text-xs font-medium text-zinc-400">Buscar</label>
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Número, chave de acesso ou parceiro"
          className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 placeholder:text-zinc-500 focus:outline-none focus:ring-2 focus:ring-zinc-700"
        />
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
                <th className="px-4 py-3 text-left font-medium">Operação</th>
                <th className="px-4 py-3 text-left font-medium">Emissão</th>
                <th className="px-4 py-3 text-left font-medium">Modelo</th>
                <th className="px-4 py-3 text-left font-medium">Série</th>
                <th className="px-4 py-3 text-left font-medium">Número</th>
                <th className="px-4 py-3 text-left font-medium">Parceiro</th>
                <th className="px-4 py-3 text-left font-medium">Chave</th>
                <th className="px-4 py-3 text-left font-medium">Status</th>
                <th className="px-4 py-3 text-right font-medium">Valor</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {!loading && filtered.length === 0 ? (
                <tr>
                  <td className="px-4 py-6 text-center text-zinc-500" colSpan={9}>
                    Nenhum registro encontrado.
                  </td>
                </tr>
              ) : null}

              {filtered.map((r) => (
                <tr
                  key={r.id}
                  className="hover:bg-zinc-900/40 cursor-pointer"
                  onClick={() => router.push(`/faturamento/nfe/${r.id}`)}
                >
                  <td className="px-4 py-3 text-zinc-200">{String(r.operacao ?? "").toUpperCase() || "—"}</td>
                  <td className="px-4 py-3 text-zinc-200 whitespace-nowrap">{formatDateBR(r.emissao_date) || "—"}</td>
                  <td className="px-4 py-3 text-zinc-200">{r.modelo ?? "—"}</td>
                  <td className="px-4 py-3 text-zinc-200">{r.serie ?? "—"}</td>
                  <td className="px-4 py-3 text-zinc-200 tabular-nums">{r.numero ?? "—"}</td>
                  <td className="px-4 py-3 text-zinc-200">
                    {typeof r.cliente_id === "number" ? clientesById[String(r.cliente_id)] ?? `ID ${r.cliente_id}` : "—"}
                  </td>
                  <td className="px-4 py-3 text-zinc-200 font-mono text-xs" title={r.chave_acesso}>
                    {shortKey(r.chave_acesso)}
                  </td>
                  <td className="px-4 py-3 text-zinc-200">{r.nfe_status ? String(r.nfe_status) : "—"}</td>
                  <td className="px-4 py-3 text-right text-zinc-200 tabular-nums">{formatMoneyBR(n(r.valor_total))}</td>
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
