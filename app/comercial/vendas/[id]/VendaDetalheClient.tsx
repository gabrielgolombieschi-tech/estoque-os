"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { requireAny, type Capabilities, type CapabilityKey } from "@/lib/auth/capabilities";
import { formatMoneyBR } from "@/lib/decimal";

type Tab = "itens" | "compras" | "faturamento" | "historico";

type Venda = {
  id: number;
  tenant_id: string;
  empresa_id: string;
  codigo: string;
  numero_doc: number | null;
  numero_os: string;
  os_num: number;
  cliente_id: number | null;
  cliente_nome: string;
  descricao_servico: string | null;
  status: string | null;
  status_fluxo: string | null;
  data_abertura: string | null;
  data_conclusao: string | null;
  orcado: number | string | null;
  valor_total: number | string | null;
  observacoes: string | null;
  vendedor: string | null;
  faturado_em: string | null;
  pedido_compra: string | null;
};

type ItemMeta = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  descricao: string | null;
  unidade_medida: string | null;
  tipo: string | null;
  preco_unitario: number | string | null;
};

type VendaItem = {
  id: number;
  item_id: number;
  quantidade: number | string;
  quantidade_baixada: number | string | null;
  valor_unitario: number | string | null;
  valor_total: number | string | null;
  baixa_estoque: boolean | null;
  criado_em: string | null;
  registrado_por_nome: string | null;
};

type Pendencia = {
  pendencia_id: string;
  status: string;
  item_id: number | null;
  item_codigo: string | null;
  item_nome: string | null;
  unidade: string | null;
  quantidade: number | string;
  prioridade: string | null;
  necessario_em: string | null;
  fornecedor_nome: string | null;
};

type PedidoItem = {
  id: string;
  pedido_compra_id: string;
  item_nome: string;
  unidade: string;
  quantidade: number | string;
  quantidade_recebida: number | string;
  origem_os_id: number | null;
};

type Pedido = { id: string; codigo: string; status: string; previsao_entrega_date: string | null };

type ComprasResumo = {
  pendencias?: Pendencia[];
  pedido_itens?: PedidoItem[];
  pedidos?: Pedido[];
};

type Documento = {
  id: string;
  modelo: string | null;
  serie: string | null;
  numero: string | null;
  emissao_date: string | null;
  valor_total: number | string;
  nfse_status: string | null;
  nfe_status: string | null;
  os_id_import: number | null;
};

type Evento = {
  id: string;
  evento: string;
  status_origem: string | null;
  status_destino: string | null;
  motivo: string | null;
  criado_em: string;
};

type Saldo = { valor_pedido: number | string; valor_faturado: number | string; saldo: number | string };

const STATUS_LABEL: Record<string, string> = {
  em_andamento: "Em andamento",
  concluida: "Concluída",
  faturada: "Faturada",
  cancelada: "Cancelada",
};

const EVENTO_LABEL: Record<string, string> = {
  concluir: "Venda concluída",
  faturar: "Venda faturada",
  cancelar_venda: "Venda cancelada",
  converter_ov_em_os: "Convertida em OS",
  vincular_documento_fiscal: "Nota fiscal vinculada",
  sincronizar_compras: "Compras sincronizadas",
  registrar_oc_cliente: "Ordem de compra do cliente registrada",
};

function hasAny(caps: Capabilities | null, keys: CapabilityKey[]) {
  return requireAny(caps, keys);
}

function n(value: unknown) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function dateBR(value: string | null | undefined, withTime = false) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat("pt-BR", withTime ? { dateStyle: "short", timeStyle: "short" } : undefined).format(date);
}

function errorMessage(cause: unknown) {
  if (cause && typeof cause === "object" && "message" in cause) return String((cause as { message: unknown }).message);
  return "Não foi possível concluir a operação.";
}

export default function VendaDetalheClient() {
  const params = useParams<{ id: string }>();
  const vendaId = Number(params.id);
  const router = useRouter();
  const te = useTenantEmpresa();
  const { loading: permissionsLoading, ready, capabilities } = usePermissions();
  const canView = hasAny(capabilities, ["financeiro.read", "financeiro.write", "os.read", "os.write"]);
  const canWrite = hasAny(capabilities, ["financeiro.write", "os.write"]);
  const supabase = useMemo(() => supabaseBrowser(), []);
  const tenantId = te.tenantId;
  const empresaId = te.empresaId;

  const [tab, setTab] = useState<Tab>("itens");
  const [venda, setVenda] = useState<Venda | null>(null);
  const [itens, setItens] = useState<VendaItem[]>([]);
  const [catalogo, setCatalogo] = useState<ItemMeta[]>([]);
  const [pendencias, setPendencias] = useState<Pendencia[]>([]);
  const [pedidoItens, setPedidoItens] = useState<PedidoItem[]>([]);
  const [pedidos, setPedidos] = useState<Pedido[]>([]);
  const [documentos, setDocumentos] = useState<Documento[]>([]);
  const [documentosDisponiveis, setDocumentosDisponiveis] = useState<Documento[]>([]);
  const [eventos, setEventos] = useState<Evento[]>([]);
  const [saldo, setSaldo] = useState<Saldo | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [novoItemId, setNovoItemId] = useState("");
  const [novaQuantidade, setNovaQuantidade] = useState("1");
  const [novoValor, setNovoValor] = useState("0");
  const [baixarEstoque, setBaixarEstoque] = useState(true);
  const [documentoSelecionado, setDocumentoSelecionado] = useState("");

  const itemById = useMemo(() => new Map(catalogo.map((item) => [item.id, item])), [catalogo]);
  const pedidoById = useMemo(() => new Map(pedidos.map((pedido) => [pedido.id, pedido])), [pedidos]);
  const status = String(venda?.status_fluxo ?? venda?.status ?? "em_andamento");

  const reload = useCallback(async () => {
    if (!Number.isInteger(vendaId) || vendaId <= 0 || !tenantId || !empresaId) {
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const { data: vendaData, error: vendaError } = await supabase
        .from("ordens_servico")
        .select("*")
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .eq("id", vendaId)
        .eq("tipo_documento", "OV")
        .maybeSingle<Venda>();
      if (vendaError) throw vendaError;
      if (!vendaData) throw new Error("Venda não encontrada ou já convertida em OS.");
      setVenda(vendaData);

      const [itensResult, catalogoResult, comprasResult, documentosResult, eventosResult, saldoResult] =
        await Promise.all([
          supabase
            .from("os_itens")
            .select("id,item_id,quantidade,quantidade_baixada,valor_unitario,valor_total,baixa_estoque,criado_em,registrado_por_nome")
            .eq("tenant_id", tenantId)
            .eq("empresa_id", empresaId)
            .eq("os_id", vendaId)
            .order("id", { ascending: false }),
          supabase
            .from("itens")
            .select("id,codigo_interno,nome,descricao,unidade_medida,tipo,preco_unitario")
            .eq("tenant_id", tenantId)
            .eq("empresa_id", empresaId)
            .eq("ativo", true)
            .order("nome")
            .limit(1000),
          supabase.schema("m").rpc("venda_compras_resumo", { p_venda_id: vendaId }),
          supabase
            .schema("f")
            .from("documento_fiscal")
            .select("id,modelo,serie,numero,emissao_date,valor_total,nfse_status,nfe_status,os_id_import")
            .eq("tenant_id", tenantId)
            .eq("empresa_id", empresaId)
            .eq("operacao", "SAIDA")
            .eq("os_id_import", vendaId)
            .is("deleted_at", null)
            .order("emissao_date", { ascending: false }),
          supabase
            .from("ordens_servico_fluxo_eventos")
            .select("id,evento,status_origem,status_destino,motivo,criado_em")
            .eq("tenant_id", tenantId)
            .eq("empresa_id", empresaId)
            .eq("os_id", vendaId)
            .order("criado_em", { ascending: false }),
          supabase.schema("f").rpc("fn_os_saldo_a_faturar", {
            p_tenant_id: tenantId,
            p_empresa_id: empresaId,
            p_os_id: vendaId,
          }),
        ]);

      if (itensResult.error) throw itensResult.error;
      setItens((itensResult.data ?? []) as VendaItem[]);
      setCatalogo(catalogoResult.error ? [] : ((catalogoResult.data ?? []) as ItemMeta[]));
      if (comprasResult.error) throw comprasResult.error;
      const compras = (comprasResult.data ?? {}) as ComprasResumo;
      setPendencias(Array.isArray(compras.pendencias) ? compras.pendencias : []);
      const loadedPedidoItens = Array.isArray(compras.pedido_itens) ? compras.pedido_itens : [];
      setPedidoItens(loadedPedidoItens);
      setPedidos(Array.isArray(compras.pedidos) ? compras.pedidos : []);
      setDocumentos(documentosResult.error ? [] : ((documentosResult.data ?? []) as Documento[]));
      setEventos(eventosResult.error ? [] : ((eventosResult.data ?? []) as Evento[]));
      const saldoRow = (Array.isArray(saldoResult.data) ? saldoResult.data[0] : saldoResult.data) as Saldo | null;
      setSaldo(saldoResult.error ? null : saldoRow);

      let docsQuery = supabase
        .schema("f")
        .from("documento_fiscal")
        .select("id,modelo,serie,numero,emissao_date,valor_total,nfse_status,nfe_status,os_id_import")
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .eq("operacao", "SAIDA")
        .is("os_id_import", null)
        .is("deleted_at", null)
        .order("emissao_date", { ascending: false })
        .limit(100);
      if (vendaData.cliente_id) docsQuery = docsQuery.eq("cliente_id", vendaData.cliente_id);
      const { data: disponiveis, error: disponiveisError } = await docsQuery;
      setDocumentosDisponiveis(disponiveisError ? [] : ((disponiveis ?? []) as Documento[]));
    } catch (cause) {
      setError(errorMessage(cause));
      setVenda(null);
    } finally {
      setLoading(false);
    }
  }, [empresaId, supabase, tenantId, vendaId]);

  useEffect(() => {
    // A consulta remota é o sistema externo sincronizado por este efeito.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void reload();
  }, [reload]);

  const run = useCallback(
    async (action: () => Promise<void>, success: string) => {
      if (busy) return;
      setBusy(true);
      setError(null);
      setOk(null);
      try {
        await action();
        setOk(success);
        await reload();
      } catch (cause) {
        setError(errorMessage(cause));
      } finally {
        setBusy(false);
      }
    },
    [busy, reload]
  );

  const adicionarItem = useCallback(async () => {
    const itemId = Number(novoItemId);
    const quantidade = Number(novaQuantidade.replace(",", "."));
    const valor = Number(novoValor.replace(",", "."));
    if (!itemId || quantidade <= 0 || valor < 0 || !empresaId) {
      setError("Selecione o item e informe quantidade e custo válidos.");
      return;
    }
    await run(async () => {
      const { error: rpcError } = await supabase.rpc("add_os_item_baixa_imediata", {
        p_os_id: vendaId,
        p_item_id: itemId,
        p_quantidade: quantidade,
        p_valor_unitario: valor,
        p_desconto_percentual: 0,
        p_desconto_valor: 0,
        p_baixa_estoque: baixarEstoque,
        p_realizado_por: null,
        p_motivo: `Item lançado na venda ${venda?.codigo ?? vendaId}`,
        p_empresa_id: empresaId,
      });
      if (rpcError) throw rpcError;
      setNovoItemId("");
      setNovaQuantidade("1");
      setNovoValor("0");
    }, "Item adicionado à venda.");
  }, [baixarEstoque, empresaId, novaQuantidade, novoItemId, novoValor, run, supabase, venda?.codigo, vendaId]);

  const baixarItem = useCallback(
    async (item: VendaItem) => {
      if (!empresaId) return;
      await run(async () => {
        const { error: rpcError } = await supabase.rpc("set_os_item_quantidade_baixada", {
          p_os_item_id: item.id,
          p_quantidade_baixada: n(item.quantidade),
          p_realizado_por: null,
          p_motivo: `Baixa de estoque da venda ${venda?.codigo ?? vendaId}`,
          p_empresa_id: empresaId,
        });
        if (rpcError) throw rpcError;
      }, "Baixa de estoque atualizada.");
    },
    [empresaId, run, supabase, venda?.codigo, vendaId]
  );

  const removerItem = useCallback(
    async (item: VendaItem) => {
      if (!empresaId || !window.confirm("Remover este item e reverter a baixa de estoque vinculada?")) return;
      await run(async () => {
        const { error: rpcError } = await supabase.rpc("remove_os_item_reverte_estoque", {
          p_os_item_id: item.id,
          p_realizado_por: null,
          p_motivo: `Item removido da venda ${venda?.codigo ?? vendaId}`,
          p_empresa_id: empresaId,
        });
        if (rpcError) throw rpcError;
      }, "Item removido e estoque reconciliado.");
    },
    [empresaId, run, supabase, venda?.codigo, vendaId]
  );

  const gerarPendencia = useCallback(
    async (item: VendaItem) => {
      const suggested = Math.max(0, n(item.quantidade) - n(item.quantidade_baixada));
      const raw = window.prompt("Quantidade a comprar", String(suggested || item.quantidade));
      if (raw === null) return;
      const quantidade = Number(raw.replace(",", "."));
      if (!Number.isFinite(quantidade) || quantidade <= 0) {
        setError("Informe uma quantidade de compra válida.");
        return;
      }
      await run(async () => {
        const { error: rpcError } = await supabase.schema("m").rpc("venda_sincronizar_compras", {
          p_venda_id: vendaId,
          p_item_id: item.item_id,
          p_quantidade: quantidade,
        });
        if (rpcError) throw rpcError;
      }, "Pendência enviada para Compras.");
    },
    [run, supabase, vendaId]
  );

  const sincronizarCompras = useCallback(async () => {
    let semFornecedor = 0;
    await run(async () => {
      const { data, error: rpcError } = await supabase.schema("m").rpc("venda_sincronizar_compras", {
        p_venda_id: vendaId,
        p_item_id: null,
        p_quantidade: null,
      });
      if (rpcError) throw rpcError;
      const result = (data ?? {}) as { sem_fornecedor?: number };
      semFornecedor = n(result.sem_fornecedor);
    }, "Itens pendentes sincronizados com Compras.");
    if (semFornecedor > 0) setError(`${semFornecedor} item(ns) foram enviados sem fornecedor definido no cadastro.`);
  }, [run, supabase, vendaId]);

  const registrarOc = useCallback(async () => {
    const numero = window.prompt("Número da ordem de compra do cliente", venda?.pedido_compra ?? "");
    if (!numero?.trim()) return;
    const data = window.prompt("Data de recebimento da OC (AAAA-MM-DD)", new Date().toISOString().slice(0, 10));
    if (data === null) return;
    await run(async () => {
      const { error: rpcError } = await supabase.schema("m").rpc("venda_registrar_oc", {
        p_venda_id: vendaId,
        p_numero: numero.trim(),
        p_data: data || null,
      });
      if (rpcError) throw rpcError;
    }, "Ordem de compra do cliente registrada.");
  }, [run, supabase, venda?.pedido_compra, vendaId]);

  const concluir = useCallback(async () => {
    if (!window.confirm("Concluir esta venda? Depois disso os itens deixam de ficar em edição operacional.")) return;
    await run(async () => {
      const { error: rpcError } = await supabase.rpc("os_concluir", { p_os_id: vendaId });
      if (rpcError) throw rpcError;
    }, "Venda concluída.");
  }, [run, supabase, vendaId]);

  const cancelar = useCallback(async () => {
    const motivo = window.prompt("Motivo do cancelamento");
    if (!motivo?.trim()) return;
    await run(async () => {
      const { error: rpcError } = await supabase.schema("m").rpc("venda_cancelar", {
        p_venda_id: vendaId,
        p_motivo: motivo.trim(),
      });
      if (rpcError) throw rpcError;
    }, "Venda cancelada.");
  }, [run, supabase, vendaId]);

  const converter = useCallback(async () => {
    if (!window.confirm("Converter esta OV em OS? O número técnico e todos os vínculos serão preservados.")) return;
    setBusy(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.schema("m").rpc("venda_converter_em_os", {
        p_venda_id: vendaId,
        p_motivo: "Conversão solicitada na tela de Vendas",
      });
      if (rpcError) throw rpcError;
      router.push(`/os/${vendaId}`);
    } catch (cause) {
      setError(errorMessage(cause));
      setBusy(false);
    }
  }, [router, supabase, vendaId]);

  const faturar = useCallback(async () => {
    if (!window.confirm("Marcar esta venda como faturada? É necessário ter NF-e ou NFS-e emitida vinculada.")) return;
    await run(async () => {
      const { error: rpcError } = await supabase.rpc("os_faturar", { p_os_id: vendaId });
      if (rpcError) throw rpcError;
    }, "Venda marcada como faturada.");
  }, [run, supabase, vendaId]);

  const vincularDocumento = useCallback(async () => {
    if (!documentoSelecionado) {
      setError("Selecione uma nota fiscal para vincular.");
      return;
    }
    await run(async () => {
      const { error: rpcError } = await supabase.schema("m").rpc("venda_vincular_documento_fiscal", {
        p_venda_id: vendaId,
        p_documento_fiscal_id: documentoSelecionado,
      });
      if (rpcError) throw rpcError;
      setDocumentoSelecionado("");
    }, "Nota fiscal vinculada à venda.");
  }, [documentoSelecionado, run, supabase, vendaId]);

  if (!ready && permissionsLoading) return <div className="py-12 text-center text-zinc-400">Carregando permissões...</div>;
  if (!canView) return <div className="py-12 text-center text-zinc-400">Acesso negado.</div>;
  if (loading) return <div className="py-12 text-center text-zinc-400">Carregando venda...</div>;
  if (!venda) return <div className="space-y-3"><div className="rounded-lg border border-red-900 bg-red-950/30 p-3 text-red-300">{error ?? "Venda não encontrada."}</div><Link href="/comercial/vendas" className="text-sky-300 hover:underline">Voltar para Vendas</Link></div>;

  return (
    <div className="space-y-5">
      <header className="space-y-4 rounded-xl border border-zinc-800 bg-zinc-950 p-5">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="text-2xl font-semibold text-zinc-100">{venda.codigo}</h1>
              <span className="rounded-full border border-violet-800 bg-violet-950/50 px-2 py-1 text-xs font-medium text-violet-300">OV</span>
              <span className="rounded-full border border-zinc-700 px-2 py-1 text-xs text-zinc-300">{STATUS_LABEL[status] ?? status}</span>
            </div>
            <div className="mt-2 text-lg text-zinc-200">{venda.cliente_nome}</div>
            <div className="mt-1 text-sm text-zinc-400">{venda.descricao_servico || "Venda de materiais"}</div>
          </div>
          <div className="text-right">
            <div className="text-xs uppercase tracking-wide text-zinc-500">Valor da venda</div>
            <div className="mt-1 text-2xl font-semibold tabular-nums">R$ {formatMoneyBR(n(venda.orcado || venda.valor_total))}</div>
          </div>
        </div>

        <div className="grid gap-3 text-sm sm:grid-cols-2 lg:grid-cols-5">
          <div><div className="text-xs text-zinc-500">Abertura</div>{dateBR(venda.data_abertura)}</div>
          <div><div className="text-xs text-zinc-500">Vendedor</div>{venda.vendedor || "—"}</div>
          <div><div className="text-xs text-zinc-500">Número técnico</div>{venda.numero_os}</div>
          <div><div className="text-xs text-zinc-500">OC do cliente</div>{venda.pedido_compra || "Pendente"}</div>
          <div><div className="text-xs text-zinc-500">Faturamento</div>{venda.faturado_em ? dateBR(venda.faturado_em) : "Pendente"}</div>
        </div>

        <div className="flex flex-wrap gap-2">
          <Link href="/comercial/vendas" className="rounded-md border border-zinc-800 px-3 py-2 text-sm hover:bg-zinc-900">Voltar</Link>
          <button type="button" onClick={() => void reload()} disabled={busy} className="rounded-md border border-zinc-800 px-3 py-2 text-sm hover:bg-zinc-900 disabled:opacity-50">Atualizar</button>
          {canWrite && status !== "cancelada" ? <button type="button" onClick={() => void registrarOc()} disabled={busy} className="rounded-md border border-sky-800 px-3 py-2 text-sm text-sky-300 hover:bg-sky-950/40 disabled:opacity-50">{venda.pedido_compra ? "Editar OC" : "Registrar OC"}</button> : null}
          {canWrite && status === "em_andamento" ? <button type="button" onClick={() => void sincronizarCompras()} disabled={busy || itens.length === 0} className="rounded-md border border-violet-800 px-3 py-2 text-sm text-violet-300 hover:bg-violet-950/40 disabled:opacity-50">Enviar para Compras</button> : null}
          {canWrite && status === "em_andamento" ? <Link href={`/estoque/importar?documento=${vendaId}&numero=${encodeURIComponent(venda.numero_os)}`} className="rounded-md border border-zinc-800 px-3 py-2 text-sm hover:bg-zinc-900">Importar NF/XML</Link> : null}
          {canWrite && status === "em_andamento" ? <button type="button" onClick={() => void concluir()} disabled={busy} className="rounded-md bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50">Concluir</button> : null}
          {canWrite && status === "concluida" ? <button type="button" onClick={() => void faturar()} disabled={busy} className="rounded-md bg-sky-600 px-3 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50">Marcar faturada</button> : null}
          {canWrite && status === "em_andamento" ? <button type="button" onClick={() => void converter()} disabled={busy} className="rounded-md border border-amber-800 px-3 py-2 text-sm text-amber-300 hover:bg-amber-950/40 disabled:opacity-50">Converter em OS</button> : null}
          {canWrite && !["faturada", "cancelada"].includes(status) ? <button type="button" onClick={() => void cancelar()} disabled={busy} className="rounded-md border border-red-900 px-3 py-2 text-sm text-red-300 hover:bg-red-950/40 disabled:opacity-50">Cancelar venda</button> : null}
        </div>
      </header>

      {error ? <div className="rounded-lg border border-red-900 bg-red-950/30 p-3 text-sm text-red-300">{error}</div> : null}
      {ok ? <div className="rounded-lg border border-emerald-900 bg-emerald-950/30 p-3 text-sm text-emerald-300">{ok}</div> : null}

      <nav className="flex gap-1 overflow-x-auto border-b border-zinc-800">
        {([
          ["itens", `Itens (${itens.length})`],
          ["compras", `Compras (${pendencias.length + pedidoItens.length})`],
          ["faturamento", `Faturamento (${documentos.length})`],
          ["historico", `Histórico (${eventos.length})`],
        ] as Array<[Tab, string]>).map(([value, label]) => (
          <button key={value} type="button" onClick={() => setTab(value)} className={`border-b-2 px-4 py-3 text-sm ${tab === value ? "border-sky-500 text-sky-300" : "border-transparent text-zinc-400 hover:text-zinc-200"}`}>{label}</button>
        ))}
      </nav>

      {tab === "itens" ? (
        <section className="space-y-4">
          {canWrite && status === "em_andamento" ? (
            <div className="grid gap-2 rounded-xl border border-zinc-800 bg-zinc-950 p-4 md:grid-cols-[minmax(240px,1fr)_120px_140px_auto_auto] md:items-end">
              <label className="text-xs text-zinc-500">Item<select value={novoItemId} onChange={(event) => { const value = event.target.value; setNovoItemId(value); const meta = itemById.get(Number(value)); if (meta) setNovoValor(String(n(meta.preco_unitario))); }} className="mt-1 block w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-200"><option value="">Selecione...</option>{catalogo.map((item) => <option key={item.id} value={item.id}>{item.codigo_interno ? `${item.codigo_interno} · ` : ""}{item.nome ?? item.descricao ?? `Item ${item.id}`}</option>)}</select></label>
              <label className="text-xs text-zinc-500">Quantidade<input value={novaQuantidade} onChange={(event) => setNovaQuantidade(event.target.value)} inputMode="decimal" className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-200" /></label>
              <label className="text-xs text-zinc-500">Custo unitário<input value={novoValor} onChange={(event) => setNovoValor(event.target.value)} inputMode="decimal" className="mt-1 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-200" /></label>
              <label className="flex items-center gap-2 pb-2 text-sm text-zinc-300"><input type="checkbox" checked={baixarEstoque} onChange={(event) => setBaixarEstoque(event.target.checked)} />Baixar estoque</label>
              <button type="button" onClick={() => void adicionarItem()} disabled={busy} className="rounded-md bg-zinc-100 px-3 py-2 text-sm font-medium text-zinc-900 disabled:opacity-50">Adicionar</button>
            </div>
          ) : null}

          <div className="overflow-x-auto rounded-xl border border-zinc-800 bg-zinc-950">
            <table className="min-w-[900px] w-full text-sm"><thead className="bg-zinc-900/70 text-left text-xs uppercase text-zinc-500"><tr><th className="px-3 py-3">Item</th><th className="px-3 py-3 text-right">Quantidade</th><th className="px-3 py-3 text-right">Baixada</th><th className="px-3 py-3 text-right">Custo unitário</th><th className="px-3 py-3 text-right">Total</th><th className="px-3 py-3">Ações</th></tr></thead><tbody className="divide-y divide-zinc-900">
              {itens.length === 0 ? <tr><td colSpan={6} className="px-3 py-10 text-center text-zinc-500">Nenhum item lançado.</td></tr> : null}
              {itens.map((item) => { const meta = itemById.get(item.item_id); const restante = Math.max(0, n(item.quantidade) - n(item.quantidade_baixada)); return <tr key={item.id}><td className="px-3 py-3"><div className="font-medium">{meta?.nome ?? meta?.descricao ?? `Item ${item.item_id}`}</div><div className="text-xs text-zinc-500">{meta?.codigo_interno || "Sem código"} · {meta?.unidade_medida || "UN"}</div></td><td className="px-3 py-3 text-right tabular-nums">{n(item.quantidade).toLocaleString("pt-BR")}</td><td className="px-3 py-3 text-right tabular-nums">{n(item.quantidade_baixada).toLocaleString("pt-BR")}{restante > 0 ? <div className="text-xs text-amber-400">Falta {restante.toLocaleString("pt-BR")}</div> : <div className="text-xs text-emerald-400">Completa</div>}</td><td className="px-3 py-3 text-right tabular-nums">R$ {formatMoneyBR(n(item.valor_unitario))}</td><td className="px-3 py-3 text-right tabular-nums">R$ {formatMoneyBR(n(item.valor_total))}</td><td className="px-3 py-3"><div className="flex flex-wrap gap-1">{canWrite && status === "em_andamento" && restante > 0 ? <button type="button" onClick={() => void baixarItem(item)} disabled={busy} className="rounded border border-zinc-700 px-2 py-1 text-xs hover:bg-zinc-900">Baixar restante</button> : null}{canWrite ? <button type="button" onClick={() => void gerarPendencia(item)} disabled={busy} className="rounded border border-zinc-700 px-2 py-1 text-xs hover:bg-zinc-900">Gerar compra</button> : null}{canWrite && status === "em_andamento" ? <button type="button" onClick={() => void removerItem(item)} disabled={busy} className="rounded border border-red-900 px-2 py-1 text-xs text-red-300 hover:bg-red-950/40">Remover</button> : null}</div></td></tr>; })}
            </tbody></table>
          </div>
        </section>
      ) : null}

      {tab === "compras" ? (
        <section className="space-y-4">
          <div className="flex flex-wrap gap-2">
            {canWrite && status === "em_andamento" ? <button type="button" onClick={() => void sincronizarCompras()} disabled={busy || itens.length === 0} className="rounded-md bg-violet-600 px-3 py-2 text-sm font-medium text-white hover:bg-violet-500 disabled:opacity-50">Sincronizar todos os itens</button> : null}
            <Link href={`/compras/pedidos?origem=OV&documentoId=${vendaId}`} className="rounded-md border border-zinc-800 px-3 py-2 text-sm hover:bg-zinc-900">Abrir central de Compras</Link>
          </div>
          <div className="grid gap-4 xl:grid-cols-2">
          <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4"><h2 className="font-semibold">Pendências</h2><div className="mt-3 space-y-2">{pendencias.length === 0 ? <div className="text-sm text-zinc-500">Nenhuma pendência vinculada.</div> : pendencias.map((row) => <div key={row.pendencia_id} className="rounded-lg border border-zinc-800 p-3 text-sm"><div className="flex justify-between gap-3"><span className="font-medium">{row.item_nome || `Item ${row.item_id}`}</span><span className="text-xs text-zinc-400">{row.status}</span></div><div className="mt-1 text-zinc-500">{n(row.quantidade).toLocaleString("pt-BR")} {row.unidade || "UN"} · {row.fornecedor_nome || "Sem fornecedor"}</div></div>)}</div></div>
          <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4"><h2 className="font-semibold">Pedidos de compra</h2><div className="mt-3 space-y-2">{pedidoItens.length === 0 ? <div className="text-sm text-zinc-500">Nenhum pedido gerado para esta venda.</div> : pedidoItens.map((row) => { const pedido = pedidoById.get(row.pedido_compra_id); return <Link href={`/compras/pedidos?tab=pedidos&pedidoId=${row.pedido_compra_id}`} key={row.id} className="block rounded-lg border border-zinc-800 p-3 text-sm hover:bg-zinc-900/60"><div className="flex justify-between gap-3"><span className="font-medium">{pedido?.codigo ?? "Pedido"} · {row.item_nome}</span><span className="text-xs text-zinc-400">{pedido?.status ?? "—"}</span></div><div className="mt-1 text-zinc-500">Pedido {n(row.quantidade).toLocaleString("pt-BR")} · recebido {n(row.quantidade_recebida).toLocaleString("pt-BR")} {row.unidade}</div></Link>; })}</div></div>
          </div>
        </section>
      ) : null}

      {tab === "faturamento" ? (
        <section className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-3">{[["Valor do pedido", saldo?.valor_pedido], ["Valor faturado", saldo?.valor_faturado], ["Saldo a faturar", saldo?.saldo]].map(([label, value]) => <div key={String(label)} className="rounded-xl border border-zinc-800 bg-zinc-950 p-4"><div className="text-xs uppercase text-zinc-500">{label}</div><div className="mt-2 text-xl font-semibold tabular-nums">R$ {formatMoneyBR(n(value))}</div></div>)}</div>
          {canWrite ? <div className="flex flex-wrap items-end gap-2 rounded-xl border border-zinc-800 bg-zinc-950 p-4"><label className="min-w-[280px] flex-1 text-xs text-zinc-500">Nota fiscal de saída disponível<select value={documentoSelecionado} onChange={(event) => setDocumentoSelecionado(event.target.value)} className="mt-1 block w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-200"><option value="">Selecione...</option>{documentosDisponiveis.map((doc) => <option key={doc.id} value={doc.id}>{doc.modelo || "NF"} {doc.numero || "sem número"} · {dateBR(doc.emissao_date)} · R$ {formatMoneyBR(n(doc.valor_total))}</option>)}</select></label><button type="button" onClick={() => void vincularDocumento()} disabled={busy || !documentoSelecionado} className="rounded-md bg-zinc-100 px-3 py-2 text-sm font-medium text-zinc-900 disabled:opacity-50">Vincular NF</button><Link href="/faturamento/nfe" className="rounded-md border border-zinc-800 px-3 py-2 text-sm hover:bg-zinc-900">Abrir faturamento</Link></div> : null}
          <div className="overflow-x-auto rounded-xl border border-zinc-800 bg-zinc-950"><table className="min-w-[700px] w-full text-sm"><thead className="bg-zinc-900/70 text-left text-xs uppercase text-zinc-500"><tr><th className="px-3 py-3">Documento</th><th className="px-3 py-3">Emissão</th><th className="px-3 py-3">Status</th><th className="px-3 py-3 text-right">Valor</th></tr></thead><tbody className="divide-y divide-zinc-900">{documentos.length === 0 ? <tr><td colSpan={4} className="px-3 py-10 text-center text-zinc-500">Nenhuma nota fiscal vinculada.</td></tr> : documentos.map((doc) => <tr key={doc.id}><td className="px-3 py-3">{doc.modelo || "NF"} {doc.serie ? `${doc.serie}/` : ""}{doc.numero || "—"}</td><td className="px-3 py-3">{dateBR(doc.emissao_date)}</td><td className="px-3 py-3">{doc.nfse_status || doc.nfe_status || "EMITIDA"}</td><td className="px-3 py-3 text-right tabular-nums">R$ {formatMoneyBR(n(doc.valor_total))}</td></tr>)}</tbody></table></div>
        </section>
      ) : null}

      {tab === "historico" ? (
        <section className="rounded-xl border border-zinc-800 bg-zinc-950 p-4"><div className="space-y-3"><div className="rounded-lg border border-zinc-800 p-3"><div className="text-sm font-medium">Venda criada</div><div className="mt-1 text-xs text-zinc-500">{dateBR(venda.data_abertura, true)} · {venda.observacoes || "Origem não informada"}</div></div>{eventos.map((evento) => <div key={evento.id} className="rounded-lg border border-zinc-800 p-3"><div className="flex flex-wrap justify-between gap-2"><div className="text-sm font-medium">{EVENTO_LABEL[evento.evento] ?? evento.evento}</div><div className="text-xs text-zinc-500">{dateBR(evento.criado_em, true)}</div></div><div className="mt-1 text-xs text-zinc-500">{evento.status_origem && evento.status_destino ? `${evento.status_origem} → ${evento.status_destino}` : ""}{evento.motivo ? ` · ${evento.motivo}` : ""}</div></div>)}</div></section>
      ) : null}
    </div>
  );
}
