"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { formatMoneyBR } from "@/lib/decimal";

type SaldoItem = {
  os_item_id: number;
  item_id: number;
  descricao: string;
  quantidade_total: number | string;
  quantidade_faturada: number | string;
  saldo: number | string;
  unidade: string | null;
};

type OrigemItem = {
  id: number;
  finalidade: string | null;
  quantidade: number | string;
  valor_unitario: number | string;
  desconto_valor: number | string | null;
};

type Linha = SaldoItem & {
  finalidade: string | null;
  custoUnitario: number;
  descontoTotal: number;
};

type Props = {
  tenantId: string;
  empresaId: string;
  osId: number;
  codigo: string;
  tipo: "OS" | "OV";
  valorVenda?: number | string | null;
  descricaoSugestao?: string | null;
  podeCompor: boolean;
  onSolicitacaoCriada?: (solicitacaoId: string) => void;
};

const EPSILON = 0.0000001;

// Venda compoe a nota; componente sai do estoque e nao entra nela. Linha antiga fica
// nula ate alguem classificar — e e essa a decisao que o pop-up pede.
type Finalidade = "venda" | "componente";
const FINALIDADES: Array<[Finalidade, string, string]> = [
  ["venda", "Venda", "Entra na nota e consome o saldo a faturar."],
  ["componente", "Componente", "Sai do estoque e fica fora da nota."],
];

function numero(value: unknown) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function quantidadeBR(value: number) {
  return value.toLocaleString("pt-BR", { minimumFractionDigits: 0, maximumFractionDigits: 3 });
}

function parseQuantidade(value: string) {
  const normalized = value.trim().replace(/\./g, "").replace(",", ".");
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : Number.NaN;
}

function valorVendaInput(value: number) {
  return value.toLocaleString("pt-BR", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 4,
  });
}

function precosRateados(linhas: Linha[], valorVenda: number) {
  const elegiveis = linhas.filter(
    (linha) => linha.finalidade === "venda" && numero(linha.quantidade_total) > EPSILON
  );
  if (elegiveis.length === 0) return {} as Record<number, string>;

  const basesCusto = elegiveis.map((linha) => Math.max(
    numero(linha.quantidade_total) * linha.custoUnitario - linha.descontoTotal,
    0
  ));
  const totalCusto = basesCusto.reduce((total, valor) => total + valor, 0);
  const pesos = totalCusto > EPSILON
    ? basesCusto
    : elegiveis.map((linha) => numero(linha.quantidade_total));
  const totalPeso = pesos.reduce((total, valor) => total + valor, 0);
  const totalCentavos = Math.round(Math.max(valorVenda, 0) * 100);
  const brutos = pesos.map((peso) => totalPeso > EPSILON ? totalCentavos * peso / totalPeso : 0);
  const centavos = brutos.map(Math.floor);
  let restantes = totalCentavos - centavos.reduce((total, valor) => total + valor, 0);
  const ordemRestos = brutos
    .map((valor, indice) => ({ indice, resto: valor - Math.floor(valor) }))
    .sort((a, b) => b.resto - a.resto || a.indice - b.indice);
  for (let indice = 0; indice < ordemRestos.length && restantes > 0; indice += 1, restantes -= 1) {
    centavos[ordemRestos[indice].indice] += 1;
  }

  return Object.fromEntries(elegiveis.map((linha, indice) => [
    linha.os_item_id,
    valorVendaInput((centavos[indice] / 100) / numero(linha.quantidade_total)),
  ]));
}

function mensagemErro(cause: unknown) {
  if (cause && typeof cause === "object" && "message" in cause) {
    return String((cause as { message: unknown }).message);
  }
  return "Não foi possível preparar o faturamento.";
}

function FaturamentoOvPanel({
  tenantId,
  empresaId,
  osId,
  codigo,
  tipo,
  valorVenda,
  podeCompor,
  onSolicitacaoCriada,
}: Props) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [linhas, setLinhas] = useState<Linha[]>([]);
  const [quantidades, setQuantidades] = useState<Record<number, string>>({});
  const [precosUnitarios, setPrecosUnitarios] = useState<Record<number, string>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [open, setOpen] = useState(false);
  const [classificando, setClassificando] = useState(false);
  const [classificacoes, setClassificacoes] = useState<Record<number, Finalidade>>({});
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const carregar = useCallback(async () => {
    if (!tenantId || !empresaId || !Number.isInteger(osId) || osId <= 0) return;
    setLoading(true);
    setError(null);
    try {
      const [saldoResult, origemResult] = await Promise.all([
        supabase.schema("f").rpc("fn_os_itens_saldo_a_faturar", {
          p_tenant_id: tenantId,
          p_empresa_id: empresaId,
          p_os_id: osId,
        }),
        supabase
          .from("os_itens")
          .select("id,finalidade,quantidade,valor_unitario,desconto_valor")
          .eq("tenant_id", tenantId)
          .eq("empresa_id", empresaId)
          .eq("os_id", osId),
      ]);
      if (saldoResult.error) throw saldoResult.error;
      if (origemResult.error) throw origemResult.error;

      const origemPorId = new Map(
        ((origemResult.data ?? []) as OrigemItem[]).map((item) => [item.id, item])
      );
      const next = ((saldoResult.data ?? []) as SaldoItem[]).map((item) => {
        const origem = origemPorId.get(item.os_item_id);
        return {
          ...item,
          finalidade: origem?.finalidade ?? null,
          custoUnitario: numero(origem?.valor_unitario),
          descontoTotal: numero(origem?.desconto_valor),
        };
      });
      setLinhas(next);
      setPrecosUnitarios(precosRateados(next, numero(valorVenda)));
      setQuantidades(
        Object.fromEntries(
          next
            .filter((item) => item.finalidade === "venda" && numero(item.saldo) > EPSILON)
            .map((item) => [item.os_item_id, quantidadeBR(numero(item.saldo))])
        )
      );
    } catch (cause) {
      setError(mensagemErro(cause));
      setLinhas([]);
    } finally {
      setLoading(false);
    }
  }, [empresaId, osId, supabase, tenantId, valorVenda]);

  useEffect(() => {
    // A RPC remota é a fonte do saldo e sincroniza o estado local do painel.
    void carregar();
  }, [carregar]);

  const venda = useMemo(() => linhas.filter((item) => item.finalidade === "venda"), [linhas]);
  const legado = useMemo(() => linhas.filter((item) => item.finalidade == null), [linhas]);
  const pendentes = useMemo(() => venda.filter((item) => numero(item.saldo) > EPSILON), [venda]);

  const itensSelecionados = useMemo(
    () =>
      pendentes
        .map((item) => ({
          item,
          quantidade: parseQuantidade(quantidades[item.os_item_id] ?? ""),
          valorUnitario: parseQuantidade(precosUnitarios[item.os_item_id] ?? ""),
        }))
        .filter(({ quantidade }) => Number.isFinite(quantidade) && quantidade > EPSILON),
    [pendentes, precosUnitarios, quantidades]
  );

  const totalSolicitacao = useMemo(
    () =>
      itensSelecionados.reduce((total, { quantidade, valorUnitario }) => {
        return total + (Number.isFinite(valorUnitario) ? quantidade * valorUnitario : 0);
      }, 0),
    [itensSelecionados]
  );
  const diferencaOv = totalSolicitacao - numero(valorVenda);

  function abrirClassificacao() {
    setError(null);
    setOk(null);
    // Venda e o palpite, nao a decisao: linha em OV quase sempre e o que se vende, e
    // quem estiver classificando troca para componente com um clique quando nao for.
    setClassificacoes(Object.fromEntries(legado.map((item) => [item.os_item_id, "venda" as Finalidade])));
    setClassificando(true);
  }

  async function salvarClassificacao() {
    setError(null);
    setOk(null);
    const escolhas = legado.map((item) => ({
      os_item_id: item.os_item_id,
      finalidade: classificacoes[item.os_item_id] ?? "venda",
    }));
    if (escolhas.length === 0) {
      setClassificando(false);
      return;
    }
    setSaving(true);
    try {
      const { data, error: rpcError } = await supabase.rpc("set_os_itens_finalidade", {
        p_os_id: osId,
        p_classificacoes: escolhas,
        p_empresa_id: empresaId,
      });
      if (rpcError) throw rpcError;
      const vendas = escolhas.filter((escolha) => escolha.finalidade === "venda").length;
      const componentes = escolhas.length - vendas;
      setOk(
        `${numero(data)} linha(s) classificada(s): ${vendas} como venda, ${componentes} como componente.`
      );
      setClassificando(false);
      await carregar();
    } catch (cause) {
      setError(mensagemErro(cause));
    } finally {
      setSaving(false);
    }
  }

  async function confirmar() {
    setError(null);
    setOk(null);
    if (itensSelecionados.length === 0) {
      setError("Informe ao menos uma quantidade maior que zero.");
      return;
    }
    const invalida = itensSelecionados.find(
      ({ item, quantidade }) => quantidade > numero(item.saldo) + EPSILON
    );
    if (invalida) {
      setError(
        `A linha ${invalida.item.os_item_id} aceita no máximo ${quantidadeBR(numero(invalida.item.saldo))} ${invalida.item.unidade ?? ""}.`
      );
      return;
    }
    const precoInvalido = itensSelecionados.find(
      ({ valorUnitario }) => !Number.isFinite(valorUnitario) || valorUnitario < 0
    );
    if (precoInvalido) {
      setError(`Informe um preço unitário de venda válido para a linha ${precoInvalido.item.os_item_id}.`);
      return;
    }

    setSaving(true);
    try {
      const itens = itensSelecionados.map(({ item, quantidade, valorUnitario }) => ({
        os_item_id: item.os_item_id,
        quantidade,
        valor_unitario: valorUnitario,
      }));
      const { data, error: rpcError } = await supabase
        .schema("f")
        .rpc("fn_solicitacao_faturamento_criar_parcial", {
          p_tenant_id: tenantId,
          p_empresa_id: empresaId,
          p_os_id: osId,
          p_itens_quantidades: itens,
          p_os_item_ids: itens.map((item) => item.os_item_id),
          p_natureza_operacao: "VENDA_MERCADORIA_TERCEIROS",
        });
      if (rpcError) throw rpcError;
      const solicitacaoId = String(data ?? "");
      setOk(`Solicitação ${solicitacaoId.slice(0, 8)} criada em rascunho. Nenhuma nota foi emitida.`);
      setOpen(false);
      await carregar();
      onSolicitacaoCriada?.(solicitacaoId);
    } catch (cause) {
      setError(mensagemErro(cause));
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="space-y-3 rounded-xl border border-zinc-800 bg-zinc-950 p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="font-semibold text-zinc-100">Progresso do faturamento por item</h2>
          <p className="mt-1 text-sm text-zinc-400">
            {tipo} {codigo}: rascunhos já reservam quantidade; somente uma solicitação cancelada devolve o saldo.
          </p>
        </div>
        <div className="flex gap-2">
          <button
            type="button"
            onClick={() => void carregar()}
            disabled={loading || saving}
            className="rounded-md border border-zinc-700 px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-900 disabled:opacity-50"
          >
            Atualizar saldo
          </button>
          {podeCompor ? (
            <button
              type="button"
              onClick={() => { setError(null); setOk(null); setOpen(true); }}
              disabled={loading || saving || pendentes.length === 0}
              className="rounded-md bg-sky-600 px-3 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50"
            >
              Faturar
            </button>
          ) : null}
        </div>
      </div>

      {error && !open ? <div role="alert" className="rounded-md border border-red-900 bg-red-950/30 p-3 text-sm text-red-300">{error}</div> : null}
      {ok ? <div className="rounded-md border border-emerald-900 bg-emerald-950/30 p-3 text-sm text-emerald-300">{ok}</div> : null}

      {loading ? (
        <div className="py-5 text-sm text-zinc-500">Calculando quantidades...</div>
      ) : venda.length === 0 ? (
        <div className="py-5 text-sm text-zinc-500">Nenhuma linha classificada como venda.</div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[720px] text-sm">
            <thead className="text-left text-xs uppercase text-zinc-500">
              <tr className="border-b border-zinc-800">
                <th className="px-2 py-2">Item</th>
                <th className="px-2 py-2 text-right">Total</th>
                <th className="px-2 py-2 text-right">Reservado/faturado</th>
                <th className="px-2 py-2 text-right">Saldo</th>
                <th className="px-2 py-2">Situação</th>
              </tr>
            </thead>
            <tbody>
              {venda.map((item) => {
                const semSaldo = numero(item.saldo) <= EPSILON;
                return (
                  <tr key={item.os_item_id} className="border-b border-zinc-900">
                    <td className="px-2 py-3"><span className="text-zinc-500">#{item.os_item_id}</span> · {item.descricao}</td>
                    <td className="px-2 py-3 text-right tabular-nums">{quantidadeBR(numero(item.quantidade_total))} {item.unidade}</td>
                    <td className="px-2 py-3 text-right tabular-nums">{quantidadeBR(numero(item.quantidade_faturada))} {item.unidade}</td>
                    <td className="px-2 py-3 text-right font-medium tabular-nums">{quantidadeBR(numero(item.saldo))} {item.unidade}</td>
                    <td className={`px-2 py-3 ${semSaldo ? "text-emerald-300" : "text-amber-300"}`}>{semSaldo ? "Faturado" : "Pendente"}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {legado.length > 0 ? (
        <div className="rounded-lg border border-amber-900/70 bg-amber-950/20 p-3">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <div className="text-sm font-medium text-amber-300">{legado.length} linha(s) sem finalidade</div>
              <p className="mt-1 text-xs text-amber-200/80">Classifique como venda ou componente antes de incluir no faturamento.</p>
            </div>
            {podeCompor ? (
              <button
                type="button"
                onClick={abrirClassificacao}
                disabled={loading || saving}
                className="rounded-md border border-amber-700 bg-amber-950/40 px-3 py-2 text-sm font-medium text-amber-100 hover:bg-amber-900/40 disabled:opacity-50"
              >
                Classificar linhas
              </button>
            ) : null}
          </div>
          <div className="mt-2 space-y-1 text-sm text-zinc-300">
            {legado.map((item) => <div key={item.os_item_id}>#{item.os_item_id} · {item.descricao} · {quantidadeBR(numero(item.quantidade_total))} {item.unidade}</div>)}
          </div>
        </div>
      ) : null}

      {classificando ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4">
          <div role="dialog" aria-modal="true" aria-label={`Classificar linhas de ${tipo} ${codigo}`} className="max-h-[90vh] w-full max-w-3xl overflow-y-auto rounded-xl border border-zinc-700 bg-zinc-950 shadow-2xl">
            <div className="sticky top-0 flex items-start justify-between gap-3 border-b border-zinc-800 bg-zinc-950 p-4">
              <div>
                <h2 className="text-lg font-semibold">Classificar linhas de {tipo} {codigo}</h2>
                <p className="text-sm text-zinc-400">O que entra na nota e o que só sai do estoque. Nada é faturado agora.</p>
              </div>
              <button type="button" onClick={() => setClassificando(false)} disabled={saving} className="rounded-md border border-zinc-700 px-3 py-2 text-sm hover:bg-zinc-900">Fechar</button>
            </div>
            <div className="space-y-3 p-4">
              {error ? <div role="alert" className="rounded-md border border-red-900 bg-red-950/30 p-3 text-sm text-red-300">{error}</div> : null}
              {legado.map((item) => (
                <div key={item.os_item_id} className="rounded-lg border border-zinc-800 p-3">
                  <div className="font-medium">{item.descricao}</div>
                  <div className="mt-1 text-xs text-zinc-500">Linha #{item.os_item_id} · {quantidadeBR(numero(item.quantidade_total))} {item.unidade}</div>
                  <div className="mt-3 grid gap-2 md:grid-cols-2">
                    {FINALIDADES.map(([valor, rotulo, explicacao]) => {
                      const marcada = (classificacoes[item.os_item_id] ?? "venda") === valor;
                      return (
                        <label key={valor} className={`flex cursor-pointer gap-3 rounded-md border p-3 text-sm ${marcada ? "border-sky-600 bg-sky-950/30" : "border-zinc-800 hover:bg-zinc-900"}`}>
                          <input
                            type="radio"
                            name={`finalidade-${item.os_item_id}`}
                            value={valor}
                            checked={marcada}
                            onChange={() => { setError(null); setClassificacoes((current) => ({ ...current, [item.os_item_id]: valor })); }}
                            className="mt-1"
                          />
                          <span>
                            <span className="font-medium text-zinc-100">{rotulo}</span>
                            <span className="mt-0.5 block text-xs text-zinc-400">{explicacao}</span>
                          </span>
                        </label>
                      );
                    })}
                  </div>
                </div>
              ))}
              <p className="text-xs text-zinc-500">A classificação vale para a linha inteira e pode ser refeita enquanto não houver solicitação de faturamento em aberto para ela.</p>
            </div>
            <div className="sticky bottom-0 flex flex-wrap items-center justify-end gap-3 border-t border-zinc-800 bg-zinc-950 p-4">
              <button type="button" onClick={() => setClassificando(false)} disabled={saving} className="rounded-md border border-zinc-700 px-3 py-2 text-sm hover:bg-zinc-900">Cancelar</button>
              <button type="button" onClick={() => void salvarClassificacao()} disabled={saving} className="rounded-md bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50">
                {saving ? "Salvando..." : "Salvar classificação"}
              </button>
            </div>
          </div>
        </div>
      ) : null}

      {open ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4">
          <div role="dialog" aria-modal="true" aria-label={`Faturar ${tipo} ${codigo}`} className="max-h-[90vh] w-full max-w-4xl overflow-y-auto rounded-xl border border-zinc-700 bg-zinc-950 shadow-2xl">
            <div className="sticky top-0 flex items-start justify-between gap-3 border-b border-zinc-800 bg-zinc-950 p-4">
              <div><h2 className="text-lg font-semibold">Faturar {tipo} {codigo}</h2><p className="text-sm text-zinc-400">Defina quanto entra nesta solicitação. A nota não será emitida agora.</p></div>
              <button type="button" onClick={() => setOpen(false)} disabled={saving} className="rounded-md border border-zinc-700 px-3 py-2 text-sm hover:bg-zinc-900">Fechar</button>
            </div>
            <div className="space-y-3 p-4">
              {error ? <div role="alert" className="rounded-md border border-red-900 bg-red-950/30 p-3 text-sm text-red-300">{error}</div> : null}
              {pendentes.map((item) => (
                <div key={item.os_item_id} className="grid gap-3 rounded-lg border border-zinc-800 p-3 md:grid-cols-[minmax(240px,1fr)_100px_160px_160px] md:items-end">
                  <div><div className="font-medium">{item.descricao}</div><div className="mt-1 text-xs text-zinc-500">Linha #{item.os_item_id} · total {quantidadeBR(numero(item.quantidade_total))} · já reservado {quantidadeBR(numero(item.quantidade_faturada))}</div></div>
                  <div className="text-sm"><div className="text-xs text-zinc-500">Saldo</div><div className="mt-2 tabular-nums">{quantidadeBR(numero(item.saldo))} {item.unidade}</div></div>
                  <label className="text-xs text-zinc-500">Preço unitário de venda<input aria-label={`Preço unitário de venda — ${item.descricao}`} value={precosUnitarios[item.os_item_id] ?? ""} onChange={(event) => { setError(null); setPrecosUnitarios((current) => ({ ...current, [item.os_item_id]: event.target.value })); }} inputMode="decimal" className="mt-1 w-full rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 text-right text-sm text-zinc-100" /></label>
                  <label className="text-xs text-zinc-500">Quantidade a faturar<input aria-label={`Quantidade a faturar — ${item.descricao}`} value={quantidades[item.os_item_id] ?? ""} onChange={(event) => { setError(null); setQuantidades((current) => ({ ...current, [item.os_item_id]: event.target.value })); }} inputMode="decimal" className="mt-1 w-full rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 text-right text-sm text-zinc-100" /></label>
                </div>
              ))}
              <p className="text-xs text-zinc-500">Os preços sugeridos rateiam o valor total da OV proporcionalmente ao custo das linhas. O custo nunca é enviado para a NF-e.</p>
            </div>
            <div className="sticky bottom-0 flex flex-wrap items-center justify-between gap-3 border-t border-zinc-800 bg-zinc-950 p-4">
              <div className="space-y-1">
                <div className="text-xs uppercase text-zinc-500">Total da solicitação</div>
                <div className="text-xl font-semibold tabular-nums">R$ {formatMoneyBR(totalSolicitacao)}</div>
                <div className="text-xs text-zinc-400">Valor da OV: R$ {formatMoneyBR(numero(valorVenda))}</div>
                {Math.abs(diferencaOv) > 0.009 ? <div className="text-xs text-amber-300">Diferença: {diferencaOv > 0 ? "+" : "-"} R$ {formatMoneyBR(Math.abs(diferencaOv))}. Confira; isso não impede salvar o rascunho.</div> : <div className="text-xs text-emerald-300">A soma das linhas fecha com o valor da OV.</div>}
              </div>
              <div className="flex gap-2"><button type="button" onClick={() => setOpen(false)} disabled={saving} className="rounded-md border border-zinc-700 px-4 py-2 text-sm hover:bg-zinc-900">Cancelar</button><button type="button" onClick={() => void confirmar()} disabled={saving || itensSelecionados.length === 0} className="rounded-md bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50">{saving ? "Salvando..." : "Salvar rascunho da NF-e"}</button></div>
            </div>
          </div>
        </div>
      ) : null}
    </section>
  );
}

type NotaOs = {
  documento_fiscal_id: string;
  solicitacao_status: string | null;
  modelo: string;
  ambiente: string;
  emissao_status: string;
  nfe_status: string | null;
  serie: string | null;
  numero: string | null;
  valor_total: number | string | null;
  danfe_path: string | null;
  referencia_externa: string;
};

type SaldoOs = {
  valor_pedido: number | string;
  valor_faturado: number | string;
  valor_reservado: number | string;
  saldo: number | string;
  usa_relatorio_hh: boolean;
};

// Painel da OS: saldo a faturar e notas da OS. A nota (NF-e ou NFS-e) sai pela tela de faturar a OS
// (/os/<id>/faturar). Ate 11/09/2026 este painel tinha um segundo botao "Faturar" que abria uma composicao
// de linhas livres e criava uma solicitacao FATURAMENTO_OS em rascunho, sem emitir nada — nenhuma foi criada,
// e quem clicava achava que estava faturando. Os dois "Faturar" da pagina da OS levam agora ao mesmo lugar.
function FaturamentoOsPanel({
  tenantId,
  empresaId,
  osId,
  codigo,
  podeCompor,
}: Props) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [saldo, setSaldo] = useState<SaldoOs | null>(null);
  const [notas, setNotas] = useState<NotaOs[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const carregar = useCallback(async () => {
    if (!tenantId || !empresaId || !Number.isInteger(osId) || osId <= 0) return;
    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.schema("f").rpc("fn_os_saldo_a_faturar", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaId,
        p_os_id: osId,
      });
      if (rpcError) throw rpcError;
      const row = Array.isArray(data) ? data[0] : data;
      if (!row) throw new Error("Não foi possível calcular o saldo desta OS.");
      setSaldo(row as SaldoOs);
      // Notas da OS (emitidas pelo ERP ou importadas), abaixo dos quatro numeros.
      const { data: notasData } = await supabase.schema("f").rpc("fn_os_notas", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaId,
        p_os_id: osId,
      });
      setNotas((notasData as NotaOs[] | null) ?? []);
    } catch (cause) {
      setSaldo(null);
      setError(mensagemErro(cause));
    } finally {
      setLoading(false);
    }
  }, [empresaId, osId, supabase, tenantId]);

  useEffect(() => {
    void carregar();
  }, [carregar]);

  const valorPedido = numero(saldo?.valor_pedido);
  const temTeto = valorPedido > EPSILON;

  return (
    <section className="space-y-4 rounded-xl border border-zinc-800 bg-zinc-950 p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="font-semibold text-zinc-100">Faturamento da OS</h2>
          <p className="mt-1 text-sm text-zinc-400">
            OS {codigo}: saldo a faturar e notas desta OS. A NF-e ou a NFS-e sai pela tela Faturar.
          </p>
        </div>
        <div className="flex gap-2">
          <button type="button" onClick={() => void carregar()} disabled={loading} className="rounded-md border border-zinc-700 px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-900 disabled:opacity-50">Atualizar saldo</button>
          {podeCompor ? (
            <Link href={`/os/${osId}/faturar`} className="rounded-md bg-sky-600 px-3 py-2 text-sm font-medium text-white hover:bg-sky-500">Faturar</Link>
          ) : null}
        </div>
      </div>

      {error ? <div role="alert" className="rounded-md border border-red-900 bg-red-950/30 p-3 text-sm text-red-300">{error}</div> : null}

      {loading ? <div className="py-4 text-sm text-zinc-500">Calculando valores...</div> : saldo ? (
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <div className="rounded-lg border border-zinc-800 p-3"><div className="text-xs uppercase text-zinc-500">Orçado / HH</div><div className="mt-1 text-lg font-semibold tabular-nums">{temTeto ? `R$ ${formatMoneyBR(valorPedido)}` : "Sem teto cadastrado"}</div></div>
          <div className="rounded-lg border border-zinc-800 p-3"><div className="text-xs uppercase text-zinc-500">Já faturado</div><div className="mt-1 text-lg font-semibold tabular-nums">R$ {formatMoneyBR(numero(saldo.valor_faturado))}</div></div>
          <div className="rounded-lg border border-zinc-800 p-3"><div className="text-xs uppercase text-zinc-500">Reservado em aberto</div><div className="mt-1 text-lg font-semibold tabular-nums">R$ {formatMoneyBR(numero(saldo.valor_reservado))}</div></div>
          <div className="rounded-lg border border-zinc-800 p-3"><div className="text-xs uppercase text-zinc-500">Saldo</div><div className="mt-1 text-lg font-semibold tabular-nums">{temTeto ? `R$ ${formatMoneyBR(numero(saldo.saldo))}` : "Sem teto"}</div></div>
        </div>
      ) : null}

      {!loading && notas.length > 0 ? (
        <div className="rounded-lg border border-zinc-800">
          <div className="border-b border-zinc-800 px-3 py-2 text-xs uppercase text-zinc-500">Notas desta OS</div>
          <table className="w-full text-sm">
            <tbody>
              {notas.map((nota) => (
                <tr key={nota.documento_fiscal_id} className="border-b border-zinc-900 last:border-0">
                  <td className="px-3 py-2">{nota.serie && nota.numero ? `${nota.modelo === "NFSE" ? "NFS-e" : "NF-e"} ${nota.serie}/${nota.numero}` : nota.referencia_externa}</td>
                  <td className="px-3 py-2 text-zinc-400">{nota.ambiente}</td>
                  <td className="px-3 py-2">{nota.emissao_status}{nota.nfe_status === "EMITIDA" ? " · emitida" : nota.nfe_status === "CANCELADA" ? " · cancelada" : nota.ambiente === "HOMOLOGACAO" && nota.solicitacao_status === "CANCELADA" ? " · homologação abandonada" : ""}</td>
                  <td className="px-3 py-2 text-right tabular-nums">R$ {formatMoneyBR(numero(nota.valor_total))}</td>
                  <td className="px-3 py-2 text-right"><Link className="text-sky-300 underline" href={`/faturamento/${nota.modelo === "NFSE" ? "nfse" : "nfe"}/${nota.documento_fiscal_id}`}>{nota.danfe_path ? (nota.modelo === "NFSE" ? "DANFSe e detalhe" : "DANFE e detalhe") : "detalhe"}</Link></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}

      {!loading && !temTeto ? (
        <div className="rounded-md border border-amber-900/70 bg-amber-950/20 p-3 text-sm text-amber-200">
          Esta OS não tem orçamento/HH com valor. O sistema permite faturar, mas não consegue avisar sobre excesso.
        </div>
      ) : null}

    </section>
  );
}

export default function FaturamentoParcialPanel(props: Props) {
  return props.tipo === "OS"
    ? <FaturamentoOsPanel {...props} />
    : <FaturamentoOvPanel {...props} />;
}
