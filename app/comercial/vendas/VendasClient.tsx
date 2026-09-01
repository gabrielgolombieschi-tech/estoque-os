"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import { formatMoneyBR } from "@/lib/decimal";

type VendaRow = {
  id: number;
  codigo: string;
  numero_doc: number | null;
  cliente_id: number | null;
  cliente_nome: string;
  descricao_servico: string | null;
  status: string | null;
  status_fluxo: string | null;
  data_abertura: string | null;
  data_conclusao: string | null;
  orcado: number | string | null;
  valor_total: number | string | null;
  vendedor: string | null;
  faturado_em: string | null;
};

type PendenciaRow = {
  pendencia_id: string;
  origem_os_id: number | null;
  status: string;
};

type DocumentoRow = {
  id: string;
  os_id_import: number | null;
  modelo: string | null;
  nfe_status: string | null;
  nfse_status: string | null;
  valor_total: number | string | null;
};

type CompraStatus = "NENHUMA" | "PENDENTE" | "EM_PEDIDO" | "RECEBIDO";

const STATUS_LABEL: Record<string, string> = {
  em_andamento: "Em andamento",
  concluida: "Concluída",
  faturada: "Faturada",
  cancelada: "Cancelada",
};

const COMPRA_LABEL: Record<CompraStatus, string> = {
  NENHUMA: "Nada pendente",
  PENDENTE: "Aguardando compra",
  EM_PEDIDO: "Em pedido",
  RECEBIDO: "Recebido",
};

function hasAny(caps: Capabilities | null, keys: CapabilityKey[]) {
  return requireAny(caps, keys);
}

function n(value: unknown) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function dateBR(value: string | null | undefined) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat("pt-BR").format(date);
}

function documentoEmitido(documento: DocumentoRow) {
  const modelo = String(documento.modelo ?? "").toUpperCase();
  if (modelo === "NFSE") return String(documento.nfse_status ?? "").toUpperCase() === "EMITIDA";
  const status = String(documento.nfe_status ?? "").toUpperCase();
  return !status || status === "EMITIDA";
}

function compraStatus(rows: PendenciaRow[]): CompraStatus {
  if (rows.some((row) => row.status === "PENDENTE")) return "PENDENTE";
  if (rows.some((row) => row.status === "EM_PEDIDO")) return "EM_PEDIDO";
  if (rows.some((row) => row.status === "CONCLUIDO")) return "RECEBIDO";
  return "NENHUMA";
}

function statusClass(status: string) {
  if (status === "faturada") return "border-emerald-800 bg-emerald-950/50 text-emerald-300";
  if (status === "concluida") return "border-sky-800 bg-sky-950/50 text-sky-300";
  if (status === "cancelada") return "border-red-900 bg-red-950/40 text-red-300";
  return "border-amber-800 bg-amber-950/40 text-amber-300";
}

function compraClass(status: CompraStatus) {
  if (status === "RECEBIDO") return "border-emerald-800 bg-emerald-950/50 text-emerald-300";
  if (status === "EM_PEDIDO") return "border-sky-800 bg-sky-950/50 text-sky-300";
  if (status === "PENDENTE") return "border-amber-800 bg-amber-950/40 text-amber-300";
  return "border-zinc-700 text-zinc-400";
}

export default function VendasClient() {
  const te = useTenantEmpresa();
  const { loading: permissionsLoading, ready, capabilities } = usePermissions();
  const canView = hasAny(capabilities, ["financeiro.read", "financeiro.write", "os.read", "os.write"]);
  const supabase = useMemo(() => supabaseBrowser(), []);
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const filterQueryRef = useRef(searchParams.toString());

  const [vendas, setVendas] = useState<VendaRow[]>([]);
  const [pendencias, setPendencias] = useState<PendenciaRow[]>([]);
  const [documentos, setDocumentos] = useState<DocumentoRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const tenantId = te.tenantId;
  const empresaId = te.empresaId;

  useEffect(() => {
    filterQueryRef.current = searchParams.toString();
  }, [searchParams]);

  const setFilter = useCallback(
    (key: string, value: string) => {
      const next = new URLSearchParams(filterQueryRef.current);
      if (value) next.set(key, value);
      else next.delete(key);
      const query = next.toString();
      filterQueryRef.current = query;
      router.replace(query ? `${pathname}?${query}` : pathname, { scroll: false });
    },
    [pathname, router]
  );

  const reload = useCallback(async () => {
    if (!tenantId || !empresaId) {
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const { data: vendaData, error: vendaError } = await supabase
        .from("ordens_servico")
        .select(
          "id,codigo,numero_doc,cliente_id,cliente_nome,descricao_servico,status,status_fluxo,data_abertura,data_conclusao,orcado,valor_total,vendedor,faturado_em"
        )
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .eq("tipo_documento", "OV")
        .order("data_abertura", { ascending: false })
        .limit(1000);
      if (vendaError) throw vendaError;

      const rows = (vendaData ?? []) as VendaRow[];
      setVendas(rows);
      if (rows.length === 0) {
        setPendencias([]);
        setDocumentos([]);
        return;
      }

      const ids = rows.map((row) => row.id);
      const [pendenciaResult, documentoResult] = await Promise.all([
        supabase.schema("m").rpc("vendas_compras_resumo"),
        supabase
          .schema("f")
          .from("documento_fiscal")
          .select("id,os_id_import,modelo,nfe_status,nfse_status,valor_total")
          .eq("tenant_id", tenantId)
          .eq("empresa_id", empresaId)
          .eq("operacao", "SAIDA")
          .is("deleted_at", null)
          .in("os_id_import", ids),
      ]);

      if (pendenciaResult.error) throw pendenciaResult.error;
      setPendencias(Array.isArray(pendenciaResult.data) ? (pendenciaResult.data as PendenciaRow[]) : []);
      setDocumentos(documentoResult.error ? [] : ((documentoResult.data ?? []) as DocumentoRow[]));
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Não foi possível carregar as vendas.");
      setVendas([]);
      setPendencias([]);
      setDocumentos([]);
    } finally {
      setLoading(false);
    }
  }, [empresaId, supabase, tenantId]);

  useEffect(() => {
    // A consulta remota é o sistema externo sincronizado por este efeito.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void reload();
  }, [reload]);

  const pendenciasByVenda = useMemo(() => {
    const map = new Map<number, PendenciaRow[]>();
    for (const row of pendencias) {
      if (!row.origem_os_id) continue;
      map.set(row.origem_os_id, [...(map.get(row.origem_os_id) ?? []), row]);
    }
    return map;
  }, [pendencias]);

  const documentosByVenda = useMemo(() => {
    const map = new Map<number, DocumentoRow[]>();
    for (const row of documentos) {
      if (!row.os_id_import) continue;
      map.set(row.os_id_import, [...(map.get(row.os_id_import) ?? []), row]);
    }
    return map;
  }, [documentos]);

  const q = String(searchParams.get("q") ?? "");
  const status = String(searchParams.get("status") ?? "");
  const cliente = String(searchParams.get("cliente") ?? "");
  const vendedor = String(searchParams.get("vendedor") ?? "");
  const from = String(searchParams.get("de") ?? "");
  const to = String(searchParams.get("ate") ?? "");
  const compra = String(searchParams.get("compra") ?? "");
  const faturado = String(searchParams.get("faturado") ?? "");

  const filtered = useMemo(() => {
    const term = q.trim().toLocaleLowerCase("pt-BR");
    return vendas.filter((row) => {
      const rowStatus = String(row.status_fluxo ?? row.status ?? "em_andamento");
      const rowCompra = compraStatus(pendenciasByVenda.get(row.id) ?? []);
      const docs = documentosByVenda.get(row.id) ?? [];
      const isFaturado = rowStatus === "faturada" || docs.some(documentoEmitido);
      const opened = String(row.data_abertura ?? "").slice(0, 10);
      if (term && !`${row.codigo} ${row.cliente_nome} ${row.descricao_servico ?? ""}`.toLocaleLowerCase("pt-BR").includes(term)) return false;
      if (status && rowStatus !== status) return false;
      if (cliente && String(row.cliente_id ?? "") !== cliente) return false;
      if (vendedor && String(row.vendedor ?? "") !== vendedor) return false;
      if (from && opened < from) return false;
      if (to && opened > to) return false;
      if (compra && rowCompra !== compra) return false;
      if (faturado === "SIM" && !isFaturado) return false;
      if (faturado === "NAO" && isFaturado) return false;
      return true;
    });
  }, [cliente, compra, documentosByVenda, faturado, from, pendenciasByVenda, q, status, to, vendas, vendedor]);

  const clientes = useMemo(
    () =>
      Array.from(new Map(vendas.filter((row) => row.cliente_id).map((row) => [row.cliente_id, row.cliente_nome])).entries()).sort((a, b) =>
        String(a[1]).localeCompare(String(b[1]), "pt-BR")
      ),
    [vendas]
  );
  const vendedores = useMemo(
    () => Array.from(new Set(vendas.map((row) => row.vendedor).filter(Boolean) as string[])).sort((a, b) => a.localeCompare(b, "pt-BR")),
    [vendas]
  );

  const indicadores = useMemo(() => {
    const emAndamento = vendas.filter((row) => String(row.status_fluxo ?? row.status) === "em_andamento").length;
    const valorAberto = vendas
      .filter((row) => !["faturada", "cancelada"].includes(String(row.status_fluxo ?? row.status)))
      .reduce((sum, row) => sum + n(row.orcado || row.valor_total), 0);
    const itensCompra = pendencias.filter((row) => row.status === "PENDENTE").length;
    const aguardandoFaturamento = vendas.filter((row) => {
      const rowStatus = String(row.status_fluxo ?? row.status);
      return rowStatus === "concluida" && !(documentosByVenda.get(row.id) ?? []).some(documentoEmitido);
    }).length;
    return { emAndamento, valorAberto, itensCompra, aguardandoFaturamento };
  }, [documentosByVenda, pendencias, vendas]);

  if (!ready && permissionsLoading) return <div className="py-12 text-center text-zinc-400">Carregando permissões...</div>;
  if (!canView) return <div className="py-12 text-center text-zinc-400">Acesso negado.</div>;

  return (
    <div className="space-y-5">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold text-zinc-100">Vendas</h1>
          <p className="mt-1 text-sm text-zinc-400">Ordens de venda de materiais, da aprovação ao faturamento.</p>
        </div>
        <button type="button" onClick={() => void reload()} className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm hover:bg-zinc-900">
          Atualizar
        </button>
      </header>

      <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {[
          ["OVs em andamento", indicadores.emAndamento],
          ["Valor em aberto", `R$ ${formatMoneyBR(indicadores.valorAberto)}`],
          ["Itens aguardando compra", indicadores.itensCompra],
          ["Aguardando faturamento", indicadores.aguardandoFaturamento],
        ].map(([label, value]) => (
          <div key={label} className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
            <div className="text-xs uppercase tracking-wide text-zinc-500">{label}</div>
            <div className="mt-2 text-2xl font-semibold tabular-nums text-zinc-100">{value}</div>
          </div>
        ))}
      </section>

      <section className="rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <div className="grid gap-2 md:grid-cols-2 xl:grid-cols-4">
          <input value={q} onChange={(event) => setFilter("q", event.target.value)} placeholder="Código, cliente ou descrição" className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm" />
          <select value={status} onChange={(event) => setFilter("status", event.target.value)} className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm">
            <option value="">Todos os status</option>
            <option value="em_andamento">Em andamento</option>
            <option value="concluida">Concluída</option>
            <option value="faturada">Faturada</option>
            <option value="cancelada">Cancelada</option>
          </select>
          <select value={cliente} onChange={(event) => setFilter("cliente", event.target.value)} className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm">
            <option value="">Todos os clientes</option>
            {clientes.map(([id, nome]) => <option key={id} value={String(id)}>{nome}</option>)}
          </select>
          <select value={vendedor} onChange={(event) => setFilter("vendedor", event.target.value)} className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm">
            <option value="">Todos os vendedores</option>
            {vendedores.map((nome) => <option key={nome} value={nome}>{nome}</option>)}
          </select>
          <label className="text-xs text-zinc-500">De<input type="date" value={from} onChange={(event) => setFilter("de", event.target.value)} className="mt-1 block w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-200" /></label>
          <label className="text-xs text-zinc-500">Até<input type="date" value={to} onChange={(event) => setFilter("ate", event.target.value)} className="mt-1 block w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-200" /></label>
          <select value={compra} onChange={(event) => setFilter("compra", event.target.value)} className="self-end rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm">
            <option value="">Toda situação de compra</option>
            {Object.entries(COMPRA_LABEL).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
          <select value={faturado} onChange={(event) => setFilter("faturado", event.target.value)} className="self-end rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm">
            <option value="">Faturada ou não</option><option value="SIM">Faturada</option><option value="NAO">Não faturada</option>
          </select>
        </div>
      </section>

      {error ? <div className="rounded-lg border border-red-900 bg-red-950/30 p-3 text-sm text-red-300">{error}</div> : null}

      <section className="overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950">
        <div className="overflow-x-auto">
          <table className="min-w-[1100px] w-full text-sm">
            <thead className="bg-zinc-900/70 text-left text-xs uppercase tracking-wide text-zinc-500">
              <tr>
                <th className="whitespace-nowrap px-3 py-3">Venda</th>
                <th className="whitespace-nowrap px-3 py-3">Cliente</th>
                <th className="px-3 py-3">Descrição</th>
                <th className="whitespace-nowrap px-3 py-3">Abertura</th>
                <th className="whitespace-nowrap px-3 py-3 text-right">Valor</th>
                <th className="whitespace-nowrap px-3 py-3">Compra</th>
                <th className="whitespace-nowrap px-3 py-3">Status</th>
                <th className="whitespace-nowrap px-3 py-3">Faturada</th>
                <th className="whitespace-nowrap px-3 py-3">Vendedor</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-900">
              {loading ? <tr><td colSpan={9} className="px-3 py-10 text-center text-zinc-500">Carregando...</td></tr> : null}
              {!loading && filtered.length === 0 ? <tr><td colSpan={9} className="px-3 py-10 text-center text-zinc-500">Nenhuma venda encontrada.</td></tr> : null}
              {!loading && filtered.map((row) => {
                const rowStatus = String(row.status_fluxo ?? row.status ?? "em_andamento");
                const purchase = compraStatus(pendenciasByVenda.get(row.id) ?? []);
                const billed = rowStatus === "faturada" || (documentosByVenda.get(row.id) ?? []).some(documentoEmitido);
                return (
                  <tr key={row.id} className="hover:bg-zinc-900/40">
                    <td className="whitespace-nowrap px-3 py-3"><Link href={`/comercial/vendas/${row.id}`} className="font-medium text-sky-300 hover:underline">{row.codigo}</Link></td>
                    <td className="whitespace-nowrap px-3 py-3">{row.cliente_nome}</td>
                    <td className="max-w-xs truncate px-3 py-3 text-zinc-300" title={row.descricao_servico ?? ""}>{row.descricao_servico || "—"}</td>
                    <td className="whitespace-nowrap px-3 py-3 text-zinc-400">{dateBR(row.data_abertura)}</td>
                    <td className="whitespace-nowrap px-3 py-3 text-right tabular-nums">R$ {formatMoneyBR(n(row.orcado || row.valor_total))}</td>
                    <td className="whitespace-nowrap px-3 py-3">
                      <span className={`inline-flex items-center whitespace-nowrap rounded-full border px-2 py-1 text-xs ${compraClass(purchase)}`}>{COMPRA_LABEL[purchase]}</span>
                    </td>
                    <td className="whitespace-nowrap px-3 py-3">
                      <span className={`inline-flex items-center whitespace-nowrap rounded-full border px-2 py-1 text-xs ${statusClass(rowStatus)}`}>{STATUS_LABEL[rowStatus] ?? rowStatus}</span>
                    </td>
                    <td className="whitespace-nowrap px-3 py-3">{billed ? <span className="text-emerald-300">Sim</span> : <span className="text-zinc-500">Não</span>}</td>
                    <td className="whitespace-nowrap px-3 py-3 text-zinc-400">{row.vendedor || "—"}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <div className="border-t border-zinc-900 px-4 py-3 text-xs text-zinc-500">{filtered.length} venda(s) exibida(s)</div>
      </section>
    </div>
  );
}
