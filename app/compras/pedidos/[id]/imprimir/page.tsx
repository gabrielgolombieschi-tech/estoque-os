"use client";

import Image from "next/image";
import { useEffect, useMemo, useState } from "react";
import { useParams, useSearchParams } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/hooks";

type Pedido = {
  id: string;
  codigo: string;
  status: string;
  fornecedor_nome?: string | null;
  created_at?: string | null;
  total_geral?: number | null;
  observacoes?: string | null;
};

type PedidoItem = {
  id: string;
  item_codigo?: string | null;
  item_nome: string;
  unidade: string;
  quantidade: number;
  valor_unitario: number;
  valor_total: number;
  origem_resumo?: string | null;
};

type PedidoDetalheResponse = {
  pedido: Pedido;
  itens: PedidoItem[];
};

function fmtMoney(v: number) {
  return Number(v ?? 0).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
}

function fmtDate(v?: string | null) {
  const d = new Date(String(v ?? ""));
  if (!Number.isFinite(d.getTime())) return "-";
  return d.toLocaleDateString("pt-BR");
}

export default function ComprasPedidoImprimirPage() {
  const params = useParams<{ id: string }>();
  const sp = useSearchParams();
  const te = useTenantEmpresa();

  const pedidoId = String(params?.id ?? "").trim();
  const tenantId = sp.get("tenant_id") ?? te.tenantId ?? "";
  const empresaId = sp.get("empresa_id") ?? te.empresaId ?? te.empresas[0]?.id ?? "";
  const autoPrint = sp.get("auto") === "1";

  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [data, setData] = useState<PedidoDetalheResponse | null>(null);

  useEffect(() => {
    let active = true;

    async function run() {
      if (!pedidoId || !tenantId || !empresaId) {
        if (!active) return;
        setErr("Pedido/tenant/empresa nao informados.");
        setLoading(false);
        return;
      }

      setLoading(true);
      setErr(null);
      try {
        const supabase = supabaseBrowser();
        const { data: sessionData } = await supabase.auth.getSession();
        const token = sessionData.session?.access_token;
        if (!token) throw new Error("Sessao expirada.");

        const q = new URLSearchParams({
          tenant_id: tenantId,
          empresa_id: empresaId,
        });
        const res = await fetch(`/api/compras/pedidos/${encodeURIComponent(pedidoId)}?${q.toString()}`, {
          headers: {
            authorization: `Bearer ${token}`,
          },
        });
        const json = (await res.json().catch(() => ({}))) as { data?: PedidoDetalheResponse; error?: string };
        if (!res.ok) throw new Error(String(json.error ?? "Erro ao carregar pedido."));

        if (!active) return;
        setData(json.data ?? null);
      } catch (e: unknown) {
        if (!active) return;
        setData(null);
        setErr(e instanceof Error ? e.message : "Erro ao carregar pedido.");
      } finally {
        if (!active) return;
        setLoading(false);
      }
    }

    void run();
    return () => {
      active = false;
    };
  }, [empresaId, pedidoId, tenantId]);

  useEffect(() => {
    if (!autoPrint || loading || err || !data) return;
    const t = setTimeout(() => window.print(), 250);
    return () => clearTimeout(t);
  }, [autoPrint, data, err, loading]);

  const totalItens = useMemo(() => {
    if (!data?.itens?.length) return 0;
    return data.itens.reduce((acc, it) => acc + Number(it.valor_total ?? 0), 0);
  }, [data?.itens]);

  return (
    <div className="min-h-screen bg-white text-zinc-900">
      <style>{`
        @page { size: A4 landscape; margin: 10mm; }
        :root { color-scheme: light; }
        * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        .pedido-print-table th,
        .pedido-print-table td {
          border-color: #71717a !important;
          color: #18181b !important;
        }
        .pedido-print-table thead tr {
          background: #e4e4e7 !important;
        }
        @media print {
          .print-hidden { display: none !important; }
          html, body { background: #fff !important; margin: 0 !important; }
        }
      `}</style>

      <div className="print-hidden border-b border-zinc-200 px-6 py-3 flex items-center justify-between gap-3">
        <div className="text-[12px]">Visualizacao de impressao do pedido</div>
        <button type="button" onClick={() => window.print()} className="px-3 py-2 rounded-md border border-zinc-300">
          Imprimir
        </button>
      </div>

      <div className="p-8">
        {loading ? (
          <div className="text-zinc-600">Carregando...</div>
        ) : err ? (
          <div className="text-rose-700">{err}</div>
        ) : !data ? (
          <div className="text-zinc-600">Pedido nao encontrado.</div>
        ) : (
          <>
            <div className="flex items-start justify-between gap-4 border-b border-zinc-300 pb-4">
              <div className="flex items-center gap-4">
                <Image src="/Segau2.png" alt="Logo Segau" width={150} height={56} priority />
                <div>
                  <div className="text-xl font-bold">Pedido de Compra</div>
                  <div className="text-sm text-zinc-600">
                    Codigo: <strong>{data.pedido.codigo}</strong>
                  </div>
                </div>
              </div>
              <div className="text-right text-sm">
                <div>Data: <strong>{fmtDate(data.pedido.created_at)}</strong></div>
                <div>Status: <strong>{String(data.pedido.status ?? "-")}</strong></div>
                <div className="mt-1">Total: <strong>{fmtMoney(Number(data.pedido.total_geral ?? totalItens))}</strong></div>
              </div>
            </div>

            <div className="mt-4 grid grid-cols-2 gap-3 text-sm">
              <div>
                <span className="text-zinc-600">Fornecedor:</span>{" "}
                <strong>{String(data.pedido.fornecedor_nome ?? "").trim() || "SEM FORNECEDOR"}</strong>
              </div>
              <div>
                <span className="text-zinc-600">Pedido ID:</span> <span className="font-mono">{data.pedido.id}</span>
              </div>
              {String(data.pedido.observacoes ?? "").trim() ? (
                <div className="col-span-2">
                  <span className="text-zinc-600">Observacoes:</span> {String(data.pedido.observacoes)}
                </div>
              ) : null}
            </div>

            <div className="mt-4 border border-zinc-300">
              <table className="pedido-print-table w-full border-collapse text-sm">
                <thead>
                  <tr className="bg-zinc-100">
                    <th className="border border-zinc-300 px-2 py-1 text-left">Codigo</th>
                    <th className="border border-zinc-300 px-2 py-1 text-left">Descricao</th>
                    <th className="border border-zinc-300 px-2 py-1 text-left">Origem</th>
                    <th className="border border-zinc-300 px-2 py-1 text-center">Unid</th>
                    <th className="border border-zinc-300 px-2 py-1 text-right">Qtd</th>
                    <th className="border border-zinc-300 px-2 py-1 text-right">Vlr Unit</th>
                    <th className="border border-zinc-300 px-2 py-1 text-right">Total</th>
                  </tr>
                </thead>
                <tbody>
                  {data.itens.map((it) => (
                    <tr key={it.id}>
                      <td className="border border-zinc-300 px-2 py-1">{it.item_codigo ?? "-"}</td>
                      <td className="border border-zinc-300 px-2 py-1">{it.item_nome}</td>
                      <td className="border border-zinc-300 px-2 py-1">{it.origem_resumo ?? "MANUAL"}</td>
                      <td className="border border-zinc-300 px-2 py-1 text-center">{it.unidade}</td>
                      <td className="border border-zinc-300 px-2 py-1 text-right">{Number(it.quantidade ?? 0).toLocaleString("pt-BR")}</td>
                      <td className="border border-zinc-300 px-2 py-1 text-right">{fmtMoney(Number(it.valor_unitario ?? 0))}</td>
                      <td className="border border-zinc-300 px-2 py-1 text-right">{fmtMoney(Number(it.valor_total ?? 0))}</td>
                    </tr>
                  ))}
                  {!data.itens.length ? (
                    <tr>
                      <td className="border border-zinc-300 px-2 py-2 text-zinc-500" colSpan={7}>
                        Nenhum item no pedido.
                      </td>
                    </tr>
                  ) : null}
                </tbody>
              </table>
            </div>

            <div className="mt-3 text-right text-sm">
              Total de itens: <strong>{fmtMoney(totalItens)}</strong>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
