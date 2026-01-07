"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "../../lib/supabase/client";

type Cliente = { id: number; nome: string; ativo: boolean };

type OS = {
  id: number;
  numero_os: string;
  cliente_nome: string;
  cliente_id: number | null;
  status: string;
  descricao_servico: string | null;
  data_abertura: string;
  valor_total: number;
  orcado: number | null;
  custo: number | null;
  tipo_pedido?: string | null;
};

const statusBadge: Record<string, string> = {
  aberta: "bg-blue-500/15 text-blue-300 border-blue-500/30",
  em_andamento: "bg-amber-500/15 text-amber-300 border-amber-500/30",
  concluida: "bg-emerald-500/15 text-emerald-300 border-emerald-500/30",
  cancelada: "bg-red-500/15 text-red-300 border-red-500/30",
};

export default function OsListPage() {
  const router = useRouter();
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [clientes, setClientes] = useState<Cliente[]>([]);
  const [rows, setRows] = useState<OS[]>([]);
  const [status, setStatus] = useState("em_andamento");
  const [err, setErr] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);
  const [itensTotalPorOs, setItensTotalPorOs] = useState<Record<number, number>>({});
  const [maoObraPorOs, setMaoObraPorOs] = useState<Record<number, number>>({});

  // criacao
  const [creating, setCreating] = useState(false);
  const [showCreate, setShowCreate] = useState(false);
  const [clienteId, setClienteId] = useState<number | null>(null);
  const [clienteNomeLivre, setClienteNomeLivre] = useState("");
  const [descricao, setDescricao] = useState("");
  const [pedidoCompra, setPedidoCompra] = useState("");
  const [tipoPedido, setTipoPedido] = useState<"servico" | "material">("servico");
  const [vendedor, setVendedor] = useState("");
  const [orcado, setOrcado] = useState("");

  const formatMoney = (value: number) =>
    Number(value || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  async function loadClientes() {
    const { data, error } = await supabase
      .from("clientes")
      .select("id,nome,ativo")
      .eq("ativo", true)
      .order("nome", { ascending: true })
      .limit(500);

    if (!error) setClientes((data ?? []) as unknown as Cliente[]);
  }

  async function load() {
    setErr(null);
    setItensTotalPorOs({});
    setMaoObraPorOs({});

    let q = supabase
      .from("ordens_servico")
      .select("id,numero_os,cliente_nome,cliente_id,status,descricao_servico,data_abertura,valor_total,orcado,custo,tipo_pedido")
      .order("id", { ascending: false });

    if (status !== "todas") q = q.eq("status", status);

    const { data, error } = await q;
    if (error) {
      setErr(error.message);
      return;
    }

    const osList = (data ?? []) as unknown as OS[];
    setRows(osList);

    const osIds = osList.map((r) => r.id);
    if (osIds.length > 0) {
      const { data: itensData } = await supabase
        .from("os_itens")
        .select("os_id,valor_total")
        .in("os_id", osIds);

      const totals: Record<number, number> = {};
      (itensData ?? []).forEach((row: any) => {
        const osId = Number(row.os_id);
        if (!Number.isFinite(osId)) return;
        const prev = totals[osId] ?? 0;
        totals[osId] = prev + Number(row.valor_total ?? 0);
      });
      setItensTotalPorOs(totals);

      const { data: maoData } = await supabase
        .from("vw_custo_mao_obra_os")
        .select("os_id,custo_mao_obra")
        .in("os_id", osIds);

      const maoTotals: Record<number, number> = {};
      (maoData ?? []).forEach((row: any) => {
        const osId = Number(row.os_id);
        if (!Number.isFinite(osId)) return;
        maoTotals[osId] = Number(row.custo_mao_obra ?? 0);
      });
      setMaoObraPorOs(maoTotals);
    }
  }

  useEffect(() => {
    loadClientes();
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status]);

  async function gerarNumeroOs(): Promise<string> {
    const { data } = await supabase
      .from("ordens_servico")
      .select("numero_os")
      .order("id", { ascending: false })
      .limit(1)
      .maybeSingle();

    const last = Number(data?.numero_os ?? 0);
    const proximo = Number.isFinite(last) && last > 0 ? last + 1 : 1;
    return String(proximo);
  }

  async function createOS() {
    setErr(null);
    setOkMsg(null);

    if (!clienteId && !clienteNomeLivre.trim()) return setErr("Selecione um cliente ou informe um nome.");

    const orcadoValor = Number(orcado || 0);
    if (!Number.isFinite(orcadoValor) || orcadoValor < 0) return setErr("Informe um valor orcado valido.");

    setCreating(true);

    const { data: sess } = await supabase.auth.getSession();
    const userEmail = sess.session?.user?.email ?? null;

    const clienteNomeFinal =
      clienteId ? (clientes.find((c) => c.id === clienteId)?.nome ?? clienteNomeLivre.trim()) : clienteNomeLivre.trim();

    const numeroGerado = await gerarNumeroOs();

    const { data, error } = await supabase
      .from("ordens_servico")
      .insert({
        numero_os: numeroGerado,
        cliente_id: clienteId,
        cliente_nome: clienteNomeFinal,
        descricao_servico: descricao.trim() || null,
        pedido_compra: pedidoCompra.trim() || null,
        tipo_pedido: tipoPedido,
        vendedor: vendedor.trim() || null,
        orcado: orcadoValor,
        status: "aberta",
        criado_por: userEmail,
      })
      .select("id")
      .single();

    setCreating(false);

    if (error) return setErr(error.message);

    setOkMsg("OS criada!");
    setClienteId(null);
    setClienteNomeLivre("");
    setDescricao("");
    setPedidoCompra("");
    setTipoPedido("servico");
    setVendedor("");
    setOrcado("");
    setShowCreate(false);

    await load();

    if (data?.id) window.location.href = `/os/${data.id}`;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Ordens de Servico</h1>
          <p className="text-sm text-zinc-400 mt-1">Criar, filtrar e acessar OS.</p>
        </div>

        <div className="flex items-center gap-2">
          <select value={status} onChange={(e) => setStatus(e.target.value)} className="px-3 py-2">
            <option value="todas">Todas</option>
            <option value="aberta">Aberta</option>
            <option value="em_andamento">Em andamento</option>
            <option value="concluida">Concluida</option>
            <option value="cancelada">Cancelada</option>
          </select>

          <button onClick={load} className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800">
            Atualizar
          </button>

          <button
            onClick={() => {
              setShowCreate(true);
              setErr(null);
              setOkMsg(null);
            }}
            className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
          >
            Nova OS
          </button>
        </div>
      </div>

      {err && !showCreate && <div className="text-sm text-red-400">{err}</div>}
      {okMsg && !showCreate && <div className="text-sm text-emerald-300">{okMsg}</div>}

      {/* Lista */}
      <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-950">
        <table className="w-full text-sm">
          <thead className="bg-zinc-900/70">
            <tr className="text-zinc-200">
              <th className="px-4 py-3 text-left">OS</th>
              <th className="px-4 py-3 text-left">Cliente</th>
              <th className="px-4 py-3 text-left">Status</th>
              <th className="px-4 py-3 text-left">Descrição</th>
              <th className="px-4 py-3 text-right">Custo</th>
              <th className="px-4 py-3 text-right">Valor pedido</th>
            </tr>
          </thead>

          <tbody className="divide-y divide-zinc-800">
            {rows.map((r) => (
              <tr
                key={r.id}
                className="hover:bg-zinc-900/40 cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-amber-400/60"
                tabIndex={0}
                role="button"
                onClick={() => router.push(`/os/${r.id}`)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    router.push(`/os/${r.id}`);
                  }
                }}
              >
                <td className="px-4 py-3">
                  <span className="underline decoration-zinc-600 hover:decoration-zinc-300">{r.numero_os}</span>
                </td>

                <td className="px-4 py-3">
                  <div className="font-medium">{r.cliente_nome}</div>
                  {r.cliente_id && <div className="text-xs text-zinc-400">cliente_id={r.cliente_id}</div>}
                </td>

                <td className="px-4 py-3">
                  <span className={["inline-flex items-center px-2 py-1 rounded-md border text-xs", statusBadge[r.status] ?? ""].join(" ")}>
                    {r.status}
                  </span>
                </td>

                <td className="px-4 py-3 text-zinc-300">
                  {r.descricao_servico ? r.descricao_servico : "Sem descrição"}
                </td>

                {(() => {
                  const pedido = Number(r.orcado ?? 0);
                  const imposto = pedido * 0.22; // mesma regra usada no detalhe
                  const itensTotal = itensTotalPorOs[r.id] ?? 0;
                  const maoObraExtra = maoObraPorOs[r.id] ?? 0;
                  const custoBanco = Number(r.custo ?? NaN);
                  const custoCalculado = itensTotal + maoObraExtra + imposto;
                  const custo = Number.isFinite(custoBanco) && custoBanco > 0 ? custoBanco : custoCalculado;
                  const alerta = pedido > 0 && custo >= pedido * 0.9;
                  const custoClass = alerta
                    ? "text-red-300 border-red-500/40"
                    : "text-emerald-300 border-emerald-500/40";
                  return (
                    <>
                      <td className="px-4 py-3 text-right tabular-nums">
                        <span className={`inline-flex items-center px-2 py-1 rounded-md border text-xs ${custoClass}`}>
                          R$ {formatMoney(custo)}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-right tabular-nums text-zinc-200">R$ {formatMoney(pedido)}</td>
                    </>
                  );
                })()}
              </tr>
            ))}

            {rows.length === 0 && (
              <tr>
                <td colSpan={6} className="px-4 py-6 text-zinc-400">
                  Nenhuma OS encontrada.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {showCreate && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
          <div className="w-full max-w-4xl bg-zinc-950 border border-zinc-800 rounded-xl p-5 shadow-xl space-y-4">
            <div className="flex items-center justify-between gap-3">
              <div>
                <div className="text-lg font-semibold">Nova OS</div>
                <div className="text-sm text-zinc-400">Informe os dados iniciais da ordem</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setShowCreate(false)}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                >
                  Cancelar
                </button>
                <button
                  onClick={createOS}
                  disabled={creating}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
                >
                  {creating ? "Criando..." : "Criar OS"}
                </button>
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Pedido de compra</div>
                <input
                  className="w-full px-3 py-2"
                  value={pedidoCompra}
                  onChange={(e) => setPedidoCompra(e.target.value)}
                  placeholder="Alfanumerico conforme cliente"
                />
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Tipo de pedido</div>
                <select className="w-full px-3 py-2" value={tipoPedido} onChange={(e) => setTipoPedido(e.target.value as any)}>
                  <option value="servico">Servico</option>
                  <option value="material">Material</option>
                </select>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Cliente (cadastro)</div>
                <select
                  className="w-full px-3 py-2"
                  value={clienteId ?? ""}
                  onChange={(e) => setClienteId(e.target.value ? Number(e.target.value) : null)}
                >
                  <option value="">-</option>
                  {clientes.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.nome}
                    </option>
                  ))}
                </select>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Cliente (nome livre)</div>
                <input
                  className="w-full px-3 py-2"
                  value={clienteNomeLivre}
                  onChange={(e) => setClienteNomeLivre(e.target.value)}
                  placeholder="Se nao estiver cadastrado"
                />
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Vendedor</div>
                <input className="w-full px-3 py-2" value={vendedor} onChange={(e) => setVendedor(e.target.value)} />
              </div>

              <div className="space-y-1">
                <div className="text-xs text-zinc-400">Valor pedido</div>
                <input
                  type="number"
                  className="w-full px-3 py-2"
                  value={orcado}
                  onChange={(e) => setOrcado(e.target.value)}
                  placeholder="0.00"
                />
              </div>

              <div className="space-y-1 md:col-span-3">
                <div className="text-xs text-zinc-400">Descricao (opcional)</div>
                <textarea className="w-full px-3 py-2 min-h-[80px]" value={descricao} onChange={(e) => setDescricao(e.target.value)} />
              </div>
            </div>

            {err && <div className="text-sm text-red-400">{err}</div>}
            {okMsg && <div className="text-sm text-emerald-300">{okMsg}</div>}
          </div>
        </div>
      )}
    </div>
  );
}
