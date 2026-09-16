"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { formatMoneyBR } from "@/lib/decimal";
import { supabaseBrowser } from "@/lib/supabase/client";

/**
 * Remessa para conserto (garantia, reparo) emitida pelo pipeline de NF-e.
 *
 * O caminho e o mesmo da venda, so que a tributacao vem inteira do perfil de remessa
 * (f.fn_remessa_nfe_criar): escolher o destinatario no cadastro de clientes, os itens do
 * catalogo com quantidade e valor de compra, o transporte, e criar. Dali: emitir em
 * homologacao, liberar o perfil na tela de perfis contra essa homologacao e emitir em
 * producao. A autorizacao em producao abre sozinha o controle de retorno (180 dias).
 */

type Cliente = {
  id: number;
  nome: string;
  razao_social: string | null;
  documento: string | null;
  uf: string | null;
  cidade: string | null;
  indicador_ie: string | null;
  transportador_padrao_nome: string | null;
  transportador_padrao_documento: string | null;
  transportador_padrao_ie: string | null;
  transportador_padrao_endereco: string | null;
  transportador_padrao_municipio: string | null;
  transportador_padrao_uf: string | null;
  transportador_padrao_modalidade_frete: number | null;
};

type ItemBusca = { id: number; codigo: string; nome: string; unidade: string | null; custo_ultima_compra: number | string | null; ncm: string | null; origem: number | null; fiscal_pronto: boolean; peso_liquido: number | string | null; peso_bruto: number | string | null };
type Linha = { item: ItemBusca; quantidade: string; valor_unitario: string };
type Transportador = { nome: string; documento: string; inscricao_estadual: string; endereco: string; municipio: string; uf: string };
type Volume = { quantidade: string; especie: string; peso_liquido: string; peso_bruto: string };

type Emissao = {
  documento_fiscal_id: string;
  solicitacao_id: string;
  ambiente: "HOMOLOGACAO" | "PRODUCAO";
  status: string;
  chave_acesso: string | null;
  numero: number | null;
  serie: number | null;
  codigo_status: number | null;
  mensagem: string | null;
  xml_path: string | null;
  danfe_path: string | null;
  autorizado_em: string | null;
  updated_at: string;
};

type Remessa = {
  id: string;
  status: string;
  ambiente: string;
  finalidade: string | null;
  cfop_confirmado: string | null;
  valor_total: number | string;
  created_at: string;
  solicitacao_id: string | null;
  chave_primeira_nota: string | null;
  entrega_json: { nome?: string; documento?: string; uf?: string } | null;
  dados_json: { perfil_codigo?: string; natureza_operacao?: string } | null;
};

type ProducaoStatus = {
  pronta?: boolean;
  motivo?: string | null;
  preflight_confirmacao_pronto?: boolean;
  resumo_confirmacao?: { nome_destinatario?: string; documento_destinatario_mascarado?: string; valor_total?: number | string; contexto_hash?: string } | null;
};

const field = "rounded border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500";
const label = "space-y-1 text-xs text-zinc-400";
const button = "rounded border border-zinc-600 bg-zinc-900 px-3 py-2 text-sm hover:bg-zinc-800 disabled:cursor-not-allowed disabled:opacity-40";
const MODALIDADES_FRETE: Array<[string, string]> = [
  ["0", "0 · Por conta do remetente (SEGAU paga)"],
  ["1", "1 · Por conta do destinatário"],
  ["2", "2 · Por conta de terceiros"],
  ["9", "9 · Sem frete"],
];

function numero(valor: unknown) {
  const n = Number(String(valor ?? "").replace(",", "."));
  return Number.isFinite(n) ? n : 0;
}
function decimal(valor: unknown) {
  const n = Number(valor);
  return Number.isFinite(n) && n !== 0 ? n.toFixed(2).replace(".", ",") : "";
}
function textoErro(cause: unknown) {
  if (cause instanceof Error) return cause.message;
  if (cause && typeof cause === "object" && "message" in cause) return String((cause as { message: unknown }).message);
  return String(cause ?? "Erro inesperado.");
}
async function erroFunction(cause: unknown) {
  const contexto = (cause as { context?: Response })?.context;
  if (contexto && typeof contexto.json === "function") {
    try {
      const corpo = await contexto.json();
      if (corpo?.erro) return String(corpo.erro);
    } catch { /* corpo nao e JSON */ }
  }
  return textoErro(cause);
}
function documentoFormatado(valor: string | null | undefined) {
  const d = String(valor ?? "").replace(/\D/g, "");
  if (d.length === 14) return d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5");
  if (d.length === 11) return d.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, "$1.$2.$3-$4");
  return valor ?? "";
}
function rotuloStatus(remessa: Remessa, hom: Emissao | undefined, prod: Emissao | undefined) {
  if (remessa.status === "CANCELADA") return "Cancelada";
  if (prod?.status === "AUTORIZADA") return remessa.status === "AGUARDANDO_RETORNO" ? "Emitida · aguardando retorno" : "Emitida em produção";
  if (prod && ["ENVIANDO", "PROCESSANDO"].includes(prod.status)) return "Produção em processamento";
  if (prod?.status === "REJEITADA") return "Produção rejeitada";
  if (hom?.status === "AUTORIZADA") return "Homologada · falta liberar o perfil e emitir em produção";
  if (hom && ["ENVIANDO", "PROCESSANDO"].includes(hom.status)) return "Homologação em processamento";
  if (hom?.status === "REJEITADA" || hom?.status === "ERRO") return "Homologação rejeitada";
  return "Pronta para homologação";
}

export default function RemessaConsertoPanel({ tenantId, empresaId }: { tenantId: string; empresaId: string }) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [busy, setBusy] = useState<string | null>(null);
  const [aviso, setAviso] = useState<{ texto: string; erro: boolean } | null>(null);

  const [buscaCliente, setBuscaCliente] = useState("");
  const [clientes, setClientes] = useState<Cliente[]>([]);
  const [cliente, setCliente] = useState<Cliente | null>(null);
  const [buscaItem, setBuscaItem] = useState("");
  const [itensBusca, setItensBusca] = useState<ItemBusca[]>([]);
  const [linhas, setLinhas] = useState<Linha[]>([]);
  const [modalidade, setModalidade] = useState("0");
  const [transportador, setTransportador] = useState<Transportador>({ nome: "", documento: "", inscricao_estadual: "", endereco: "", municipio: "", uf: "" });
  const [volumes, setVolumes] = useState<Volume[]>([{ quantidade: "1", especie: "CAIXA", peso_liquido: "", peso_bruto: "" }]);
  const [presenca, setPresenca] = useState("9");
  const [observacao, setObservacao] = useState("");

  const [remessas, setRemessas] = useState<Remessa[]>([]);
  const [emissoes, setEmissoes] = useState<Emissao[]>([]);

  const avisar = useCallback((texto: string, erro = false) => setAviso(texto ? { texto, erro } : null), []);

  const carregar = useCallback(async () => {
    const { data, error } = await supabase.schema("f").from("operacao_fiscal")
      .select("id,status,ambiente,finalidade,cfop_confirmado,valor_total,created_at,solicitacao_id,chave_primeira_nota,entrega_json,dados_json")
      .eq("tipo", "REMESSA").not("solicitacao_id", "is", null).is("deleted_at", null)
      .order("created_at", { ascending: false }).limit(20);
    if (error) throw error;
    const lista = (data ?? []) as Remessa[];
    setRemessas(lista);
    const ids = lista.map((r) => r.solicitacao_id).filter((id): id is string => Boolean(id));
    if (ids.length === 0) { setEmissoes([]); return; }
    const { data: em, error: erroEm } = await supabase.schema("f").from("documento_fiscal_emissao")
      .select("documento_fiscal_id,solicitacao_id,ambiente,status,chave_acesso,numero,serie,codigo_status,mensagem,xml_path,danfe_path,autorizado_em,updated_at")
      .in("solicitacao_id", ids).order("updated_at", { ascending: false });
    if (erroEm) throw erroEm;
    setEmissoes((em ?? []) as Emissao[]);
  }, [supabase]);

  useEffect(() => { void carregar().catch((e) => avisar(textoErro(e), true)); }, [carregar, avisar]);

  // Retorno da SEFAZ chega pelo callback: atualiza sozinho, como no painel da OV.
  useEffect(() => {
    const canal = supabase.channel(`remessa-nfe-${empresaId}`)
      .on("postgres_changes", { event: "*", schema: "f", table: "documento_fiscal_emissao", filter: `empresa_id=eq.${empresaId}` }, () => void carregar().catch(() => {}))
      .subscribe();
    return () => { void supabase.removeChannel(canal); };
  }, [carregar, empresaId, supabase]);
  useEffect(() => {
    if (!emissoes.some((e) => ["ENVIANDO", "PROCESSANDO"].includes(e.status))) return;
    const timer = window.setInterval(() => void carregar().catch(() => {}), 5000);
    return () => window.clearInterval(timer);
  }, [carregar, emissoes]);

  async function buscarClientes() {
    const termo = buscaCliente.trim();
    if (termo.length < 2) return;
    setBusy("cliente");
    try {
      const digitos = termo.replace(/\D/g, "");
      let consulta = supabase.from("clientes")
        .select("id,nome,razao_social,documento,uf,cidade,indicador_ie,transportador_padrao_nome,transportador_padrao_documento,transportador_padrao_ie,transportador_padrao_endereco,transportador_padrao_municipio,transportador_padrao_uf,transportador_padrao_modalidade_frete")
        .eq("tenant_id", tenantId).eq("empresa_id", empresaId).eq("ativo", true).limit(10);
      consulta = digitos.length >= 4 && digitos.length === termo.length
        ? consulta.ilike("documento", `%${digitos}%`)
        : consulta.or(`nome.ilike.%${termo}%,razao_social.ilike.%${termo}%`);
      const { data, error } = await consulta;
      if (error) throw error;
      setClientes((data ?? []) as Cliente[]);
      if ((data ?? []).length === 0) avisar(`Nenhum cliente com "${termo}". Cadastre em Cadastros › Clientes e complete o cadastro fiscal.`, true);
      else avisar("");
    } catch (e) { avisar(textoErro(e), true); } finally { setBusy(null); }
  }

  function escolherCliente(c: Cliente) {
    setCliente(c);
    setClientes([]);
    if (c.transportador_padrao_nome) {
      setTransportador({
        nome: c.transportador_padrao_nome ?? "", documento: c.transportador_padrao_documento ?? "",
        inscricao_estadual: c.transportador_padrao_ie ?? "", endereco: c.transportador_padrao_endereco ?? "",
        municipio: c.transportador_padrao_municipio ?? "", uf: c.transportador_padrao_uf ?? "",
      });
      if (c.transportador_padrao_modalidade_frete != null) setModalidade(String(c.transportador_padrao_modalidade_frete));
    }
  }

  async function buscarItens() {
    const termo = buscaItem.trim();
    if (termo.length < 2) return;
    setBusy("item");
    try {
      // Busca propria da remessa: catalogo inteiro (a do faturamento so traz item fabricado).
      const { data, error } = await supabase.schema("f").rpc("fn_remessa_buscar_itens", { p_termo: termo, p_limite: 12 });
      if (error) throw error;
      setItensBusca((data ?? []) as ItemBusca[]);
      if ((data ?? []).length === 0) avisar(`Nenhum item com "${termo}". Cadastre em Cadastros › Itens, com NCM e origem na aba Fiscal.`, true);
      else avisar("");
    } catch (e) { avisar(textoErro(e), true); } finally { setBusy(null); }
  }

  function adicionarItem(item: ItemBusca) {
    setLinhas((atual) => atual.some((l) => l.item.id === item.id) ? atual : [...atual, { item, quantidade: "1", valor_unitario: decimal(item.custo_ultima_compra) }]);
    setItensBusca([]);
    setBuscaItem("");
    // Peso dos volumes: soma do cadastro dos itens, quando houver.
    setVolumes((atual) => {
      if (atual.length !== 1 || atual[0].peso_bruto) return atual;
      const liquido = numero(item.peso_liquido);
      const bruto = numero(item.peso_bruto);
      if (!liquido && !bruto) return atual;
      return [{ ...atual[0], peso_liquido: decimal((numero(atual[0].peso_liquido) || 0) + liquido), peso_bruto: decimal((numero(atual[0].peso_bruto) || 0) + (bruto || liquido)) }];
    });
  }

  const total = linhas.reduce((acc, l) => acc + numero(l.quantidade) * numero(l.valor_unitario), 0);
  const cfop = cliente ? (cliente.uf?.toUpperCase() === "SC" ? "5915" : "6915") : "—";

  async function criar() {
    if (!cliente) { avisar("Escolha o destinatário.", true); return; }
    if (linhas.length === 0) { avisar("Adicione ao menos um item.", true); return; }
    const semValor = linhas.find((l) => numero(l.valor_unitario) <= 0 || numero(l.quantidade) <= 0);
    if (semValor) { avisar(`Informe quantidade e valor de ${semValor.item.codigo}.`, true); return; }
    setBusy("criar");
    avisar("");
    try {
      const { data, error } = await supabase.schema("f").rpc("fn_remessa_nfe_criar", {
        p_cliente_id: cliente.id,
        p_itens: linhas.map((l) => ({ item_id: l.item.id, quantidade: numero(l.quantidade), valor_unitario: numero(l.valor_unitario) })),
        p_operacao: {
          modalidade_frete: modalidade,
          presenca_comprador: presenca,
          observacao: observacao.trim() || null,
          transportador: modalidade === "9" ? null : {
            nome: transportador.nome.trim(), documento: transportador.documento.replace(/\D/g, "") || null,
            inscricao_estadual: transportador.inscricao_estadual.trim() || null, endereco: transportador.endereco.trim() || null,
            municipio: transportador.municipio.trim() || null, uf: transportador.uf.trim().toUpperCase() || null,
          },
          volumes: modalidade === "9" ? [] : volumes.map((v) => ({ quantidade: numero(v.quantidade), especie: v.especie.trim() || null, peso_liquido: numero(v.peso_liquido), peso_bruto: numero(v.peso_bruto) })),
        },
      });
      if (error) throw error;
      const r = data as { cfop?: string; perfil?: string; valor_total?: number };
      avisar(`Remessa criada: CFOP ${r.cfop}, perfil ${r.perfil}, R$ ${formatMoneyBR(numero(r.valor_total))}. Agora emita em homologação.`);
      setLinhas([]); setObservacao(""); setCliente(null); setBuscaCliente("");
      await carregar();
    } catch (e) { avisar(textoErro(e), true); } finally { setBusy(null); }
  }

  async function emitirHomologacao(r: Remessa) {
    if (!r.solicitacao_id) return;
    setBusy(r.id); avisar("");
    try {
      const { data, error } = await supabase.functions.invoke("nfe-emitir", { body: { solicitacao_id: r.solicitacao_id } });
      if (error) throw error;
      if (data?.erro) throw new Error(data.codigo ? `cStat ${data.codigo} · ${data.erro}` : String(data.erro));
      avisar("Remessa enviada à Focus em homologação. O retorno da SEFAZ chega automaticamente.");
      await carregar();
    } catch (e) { avisar(await erroFunction(e), true); await carregar().catch(() => {}); } finally { setBusy(null); }
  }

  async function emitirProducao(r: Remessa) {
    if (!r.solicitacao_id) return;
    setBusy(r.id); avisar("");
    try {
      const { data: st, error: erroSt } = await supabase.functions.invoke("nfe-emitir-producao", { body: { acao: "STATUS", solicitacao_id: r.solicitacao_id } });
      if (erroSt) throw erroSt;
      const status = st as ProducaoStatus | null;
      const resumo = status?.resumo_confirmacao;
      if (!status?.pronta || !status.preflight_confirmacao_pronto || !resumo?.contexto_hash) {
        throw new Error(status?.motivo ?? "A produção ainda não está liberada para esta remessa.");
      }
      const ok = window.confirm(
        `EMITIR NF-e REAL DE REMESSA PARA CONSERTO (produção)\n\nDestinatário: ${resumo.nome_destinatario ?? "?"} (${resumo.documento_destinatario_mascarado ?? "?"})\n`
        + `CFOP ${r.cfop_confirmado} · sem ICMS, IPI, PIS e COFINS destacados · sem pagamento\nValor da mercadoria: R$ ${formatMoneyBR(numero(resumo.valor_total))}\n\n`
        + "A mercadoria precisa voltar em 180 dias. Deseja continuar?",
      );
      if (!ok) return;
      const { data, error } = await supabase.functions.invoke("nfe-emitir-producao", { body: { acao: "EMITIR", solicitacao_id: r.solicitacao_id, confirmacao_contexto_hash: resumo.contexto_hash } });
      if (error) throw error;
      if (data?.erro) throw new Error(data.codigo ? `cStat ${data.codigo} · ${data.erro}` : String(data.erro));
      avisar("NF-e de remessa enviada à SEFAZ em PRODUÇÃO. Quando autorizar, a remessa entra em \"Remessas em aberto\".");
      await carregar();
    } catch (e) { avisar(await erroFunction(e), true); await carregar().catch(() => {}); } finally { setBusy(null); }
  }

  async function abrirArquivo(e: Emissao, arquivo: "DANFE" | "XML") {
    const aba = window.open("about:blank", "_blank");
    if (aba) aba.opener = null;
    setBusy(e.documento_fiscal_id);
    try {
      const { data, error } = await supabase.functions.invoke("nfe-ciclo", { body: { acao: "ARQUIVO", arquivo, documento_fiscal_id: e.documento_fiscal_id } });
      if (error) throw error;
      if (!data?.url) throw new Error(`${arquivo} ainda não está disponível.`);
      if (!aba) throw new Error("O navegador bloqueou a nova aba. Libere pop-ups para este sistema.");
      aba.location.replace(String(data.url));
    } catch (err) { aba?.close(); avisar(await erroFunction(err), true); } finally { setBusy(null); }
  }

  async function cancelar(r: Remessa) {
    const motivo = window.prompt("Motivo do cancelamento da remessa (ao menos 15 caracteres):", "Remessa criada por engano");
    if (!motivo) return;
    setBusy(r.id); avisar("");
    try {
      const { error } = await supabase.schema("f").rpc("fn_remessa_nfe_cancelar", { p_operacao_id: r.id, p_motivo: motivo });
      if (error) throw error;
      avisar("Remessa cancelada.");
      await carregar();
    } catch (e) { avisar(textoErro(e), true); } finally { setBusy(null); }
  }

  return (
    <div className="space-y-5">
      <div>
        <h2 className="font-semibold">Remessa para conserto (garantia, reparo)</h2>
        <p className="mt-1 text-sm text-zinc-400">
          NF-e sem ICMS, IPI, PIS e COFINS destacados: ICMS e IPI suspensos, com retorno em 180 dias. CFOP 5915 dentro de SC, 6915 para outra UF.
          O destinatário vem do cadastro de clientes e os itens do catálogo, com o valor de compra.
        </p>
      </div>
      {aviso ? <div role={aviso.erro ? "alert" : "status"} className={`rounded border p-3 text-sm ${aviso.erro ? "border-red-900 bg-red-950/30 text-red-200" : "border-sky-800 bg-sky-950/30 text-sky-200"}`}>{aviso.texto}</div> : null}

      <section className="space-y-4 rounded-lg border border-zinc-800 p-4">
        <h3 className="font-medium">1 · Destinatário</h3>
        {cliente ? (
          <div className="flex flex-wrap items-center justify-between gap-2 rounded border border-emerald-900/60 bg-emerald-950/20 p-3 text-sm">
            <div>
              <div className="font-medium">{cliente.razao_social || cliente.nome}</div>
              <div className="text-xs text-zinc-400">{documentoFormatado(cliente.documento)} · {cliente.cidade}/{cliente.uf} · indIEDest {cliente.indicador_ie ?? "não informado"} · CFOP {cfop}</div>
            </div>
            <div className="flex gap-2">
              <Link href={`/clientes/cadastro-fiscal?cliente_id=${cliente.id}`} className={button}>Cadastro fiscal</Link>
              <button type="button" className={button} onClick={() => setCliente(null)}>Trocar</button>
            </div>
          </div>
        ) : (
          <div className="space-y-2">
            <div className="flex flex-wrap gap-2">
              <input aria-label="Buscar destinatário" className={`${field} min-w-[320px]`} value={buscaCliente} onChange={(e) => setBuscaCliente(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") void buscarClientes(); }} placeholder="Nome ou CNPJ do destinatário" />
              <button type="button" className={button} disabled={busy === "cliente" || buscaCliente.trim().length < 2} onClick={() => void buscarClientes()}>Buscar cliente</button>
              <Link href="/clientes" className={button}>Novo cliente</Link>
            </div>
            {clientes.length > 0 ? (
              <div className="divide-y divide-zinc-800 rounded border border-zinc-800">
                {clientes.map((c) => (
                  <button key={c.id} type="button" onClick={() => escolherCliente(c)} className="flex w-full flex-wrap items-center justify-between gap-2 px-3 py-2 text-left text-sm hover:bg-zinc-900">
                    <span>{c.razao_social || c.nome}</span>
                    <span className="text-xs text-zinc-500">{documentoFormatado(c.documento)} · {c.cidade ?? "?"}/{c.uf ?? "?"}</span>
                  </button>
                ))}
              </div>
            ) : null}
          </div>
        )}
      </section>

      <section className="space-y-3 rounded-lg border border-zinc-800 p-4">
        <h3 className="font-medium">2 · Itens que vão para conserto</h3>
        <div className="flex flex-wrap gap-2">
          <input aria-label="Buscar item" className={`${field} min-w-[320px]`} value={buscaItem} onChange={(e) => setBuscaItem(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") void buscarItens(); }} placeholder="Código ou nome do item (ex.: C4C-SA15010)" />
          <button type="button" className={button} disabled={busy === "item" || buscaItem.trim().length < 2} onClick={() => void buscarItens()}>Buscar item</button>
        </div>
        {itensBusca.length > 0 ? (
          <div className="divide-y divide-zinc-800 rounded border border-zinc-800">
            {itensBusca.map((i) => (
              <button key={i.id} type="button" onClick={() => adicionarItem(i)} className="flex w-full flex-wrap items-center justify-between gap-2 px-3 py-2 text-left text-sm hover:bg-zinc-900">
                <span><span className="font-mono text-xs text-zinc-500">{i.codigo}</span> {i.nome}</span>
                <span className="text-xs text-zinc-500">
                  {i.unidade ?? "UN"}{i.custo_ultima_compra ? ` · última compra R$ ${formatMoneyBR(numero(i.custo_ultima_compra))}` : ""}
                  {i.fiscal_pronto ? "" : <span className="ml-2 text-amber-300">sem NCM/origem no cadastro fiscal</span>}
                </span>
              </button>
            ))}
          </div>
        ) : null}
        {linhas.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-sm">
              <thead className="text-left text-xs uppercase text-zinc-500"><tr><th className="py-2">Item</th><th className="py-2">Quantidade</th><th className="py-2">Valor unitário (R$)</th><th className="py-2 text-right">Total</th><th /></tr></thead>
              <tbody className="divide-y divide-zinc-800">
                {linhas.map((l) => (
                  <tr key={l.item.id}>
                    <td className="py-2 pr-2"><div>{l.item.nome}</div><div className="font-mono text-xs text-zinc-500">{l.item.codigo} · NCM {l.item.ncm ?? "?"} · origem {l.item.origem ?? "?"}{l.item.fiscal_pronto ? "" : <Link href={`/itens?id=${l.item.id}&editar=1&aba=fiscal&retorno=/faturamento/operacoes`} className="ml-2 text-amber-300 underline">completar cadastro fiscal</Link>}</div></td>
                    <td className="py-2 pr-2"><input aria-label={`Quantidade de ${l.item.codigo}`} className={`${field} w-24`} inputMode="decimal" value={l.quantidade} onChange={(e) => setLinhas((a) => a.map((x) => x.item.id === l.item.id ? { ...x, quantidade: e.target.value } : x))} /></td>
                    <td className="py-2 pr-2"><input aria-label={`Valor unitário de ${l.item.codigo}`} className={`${field} w-36`} inputMode="decimal" value={l.valor_unitario} onChange={(e) => setLinhas((a) => a.map((x) => x.item.id === l.item.id ? { ...x, valor_unitario: e.target.value } : x))} placeholder="valor de compra" /></td>
                    <td className="py-2 text-right tabular-nums">R$ {formatMoneyBR(numero(l.quantidade) * numero(l.valor_unitario))}</td>
                    <td className="py-2 text-right"><button type="button" className={button} onClick={() => setLinhas((a) => a.filter((x) => x.item.id !== l.item.id))}>Remover</button></td>
                  </tr>
                ))}
              </tbody>
              <tfoot><tr><td colSpan={3} className="py-2 text-right text-xs uppercase text-zinc-500">Valor da mercadoria</td><td className="py-2 text-right font-semibold tabular-nums">R$ {formatMoneyBR(total)}</td><td /></tr></tfoot>
            </table>
            <p className="mt-1 text-xs text-zinc-500">O valor unitário é o da última compra, só para a nota; a remessa não cobra nada do destinatário.</p>
          </div>
        ) : <p className="text-sm text-zinc-500">Nenhum item ainda.</p>}
      </section>

      <section className="space-y-3 rounded-lg border border-zinc-800 p-4">
        <h3 className="font-medium">3 · Transporte</h3>
        <div className="grid gap-3 md:grid-cols-3">
          <label className={label}>Modalidade do frete<select aria-label="Modalidade do frete" className={`${field} w-full`} value={modalidade} onChange={(e) => setModalidade(e.target.value)}>{MODALIDADES_FRETE.map(([c, r]) => <option key={c} value={c}>{r}</option>)}</select></label>
          <label className={label}>Presença do comprador<select aria-label="Presença do comprador" className={`${field} w-full`} value={presenca} onChange={(e) => setPresenca(e.target.value)}><option value="9">9 · Não presencial, outros</option><option value="1">1 · Presencial</option><option value="2">2 · Internet</option><option value="3">3 · Teleatendimento</option><option value="5">5 · Fora do estabelecimento</option></select></label>
        </div>
        {modalidade !== "9" ? (
          <div className="space-y-3 rounded border border-zinc-800 bg-zinc-900/30 p-3">
            <div className="grid gap-3 md:grid-cols-3">
              <label className={label}>Transportadora<input aria-label="Transportadora" className={`${field} w-full`} value={transportador.nome} onChange={(e) => setTransportador((t) => ({ ...t, nome: e.target.value }))} maxLength={60} /></label>
              <label className={label}>CNPJ/CPF<input aria-label="CNPJ da transportadora" className={`${field} w-full`} value={transportador.documento} onChange={(e) => setTransportador((t) => ({ ...t, documento: e.target.value }))} inputMode="numeric" /></label>
              <label className={label}>Inscrição estadual<input aria-label="IE da transportadora" className={`${field} w-full`} value={transportador.inscricao_estadual} onChange={(e) => setTransportador((t) => ({ ...t, inscricao_estadual: e.target.value }))} /></label>
              <label className={label}>Endereço<input aria-label="Endereço da transportadora" className={`${field} w-full`} value={transportador.endereco} onChange={(e) => setTransportador((t) => ({ ...t, endereco: e.target.value }))} maxLength={60} /></label>
              <label className={label}>Município<input aria-label="Município da transportadora" className={`${field} w-full`} value={transportador.municipio} onChange={(e) => setTransportador((t) => ({ ...t, municipio: e.target.value }))} maxLength={60} /></label>
              <label className={label}>UF<input aria-label="UF da transportadora" className={`${field} w-full`} value={transportador.uf} onChange={(e) => setTransportador((t) => ({ ...t, uf: e.target.value.toUpperCase().slice(0, 2) }))} maxLength={2} /></label>
            </div>
            <div className="flex items-center justify-between"><div className="text-sm">Volumes</div><button type="button" className={button} onClick={() => setVolumes((v) => [...v, { quantidade: "1", especie: "CAIXA", peso_liquido: "", peso_bruto: "" }])}>Adicionar volume</button></div>
            {volumes.map((v, i) => (
              <div key={i} className="grid gap-2 md:grid-cols-[70px_1fr_1fr_1fr_1fr_auto] md:items-end">
                <div className="text-xs text-zinc-500 md:pb-2">{String(i + 1).padStart(3, "0")}</div>
                <label className={label}>Quantidade<input aria-label={`Quantidade do volume ${i + 1}`} className={`${field} w-full`} inputMode="numeric" value={v.quantidade} onChange={(e) => setVolumes((a) => a.map((x, j) => j === i ? { ...x, quantidade: e.target.value } : x))} /></label>
                <label className={label}>Espécie<input aria-label={`Espécie do volume ${i + 1}`} className={`${field} w-full`} value={v.especie} onChange={(e) => setVolumes((a) => a.map((x, j) => j === i ? { ...x, especie: e.target.value } : x))} /></label>
                <label className={label}>Peso líquido (kg)<input aria-label={`Peso líquido do volume ${i + 1}`} className={`${field} w-full`} inputMode="decimal" value={v.peso_liquido} onChange={(e) => setVolumes((a) => a.map((x, j) => j === i ? { ...x, peso_liquido: e.target.value } : x))} /></label>
                <label className={label}>Peso bruto (kg)<input aria-label={`Peso bruto do volume ${i + 1}`} className={`${field} w-full`} inputMode="decimal" value={v.peso_bruto} onChange={(e) => setVolumes((a) => a.map((x, j) => j === i ? { ...x, peso_bruto: e.target.value } : x))} /></label>
                <button type="button" className={button} disabled={volumes.length === 1} onClick={() => setVolumes((a) => a.filter((_, j) => j !== i))}>Remover</button>
              </div>
            ))}
          </div>
        ) : null}
        <label className={label}>Observação (vai nas informações complementares, depois da base legal)<textarea aria-label="Observação da remessa" className={`${field} min-h-16 w-full`} value={observacao} onChange={(e) => setObservacao(e.target.value)} maxLength={500} placeholder="Ex.: formulário de garantia SICK nº ..." /></label>
        <div className="flex justify-end">
          <button type="button" className="rounded-md bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50" disabled={busy === "criar" || !cliente || linhas.length === 0} onClick={() => void criar()}>
            {busy === "criar" ? "Criando..." : "Criar remessa e preparar a NF-e"}
          </button>
        </div>
      </section>

      <section className="space-y-3 rounded-lg border border-zinc-800 p-4">
        <h3 className="font-medium">Remessas criadas aqui</h3>
        {remessas.length === 0 ? <p className="text-sm text-zinc-500">Nenhuma remessa ainda.</p> : remessas.map((r) => {
          const hom = emissoes.find((e) => e.solicitacao_id === r.solicitacao_id && e.ambiente === "HOMOLOGACAO");
          const prod = emissoes.find((e) => e.solicitacao_id === r.solicitacao_id && e.ambiente === "PRODUCAO");
          const ocupado = busy === r.id;
          const cancelada = r.status === "CANCELADA";
          const homAutorizada = hom?.status === "AUTORIZADA";
          const prodAutorizada = prod?.status === "AUTORIZADA";
          const podeHomologar = !cancelada && !prod && (!hom || ["RASCUNHO", "REJEITADA", "ERRO"].includes(hom.status));
          const podeProduzir = !cancelada && homAutorizada && (!prod || ["RASCUNHO", "REJEITADA", "ERRO"].includes(prod.status));
          const linkPerfil = r.dados_json?.perfil_codigo && r.solicitacao_id
            ? `/faturamento/perfis?perfil=${encodeURIComponent(r.dados_json.perfil_codigo)}&solicitacao=${r.solicitacao_id}&retorno=/faturamento/operacoes`
            : null;
          return (
            <article key={r.id} className={`space-y-2 rounded border p-3 ${prodAutorizada ? "border-emerald-900/60" : "border-zinc-800"}`}>
              <div className="flex flex-wrap items-start justify-between gap-2">
                <div>
                  <div className="font-medium">{r.entrega_json?.nome ?? "Destinatário"} <span className="text-xs text-zinc-500">· {documentoFormatado(r.entrega_json?.documento)} · {r.entrega_json?.uf}</span></div>
                  <div className="text-xs text-zinc-500">CFOP {r.cfop_confirmado} · R$ {formatMoneyBR(numero(r.valor_total))} · perfil {r.dados_json?.perfil_codigo ?? "—"} · {new Date(r.created_at).toLocaleString("pt-BR")}</div>
                </div>
                <span className="rounded-full border border-zinc-700 px-3 py-1 text-xs">{rotuloStatus(r, hom, prod)}</span>
              </div>
              {[hom, prod].filter((e): e is Emissao => Boolean(e)).map((e) => (
                <div key={e.documento_fiscal_id} className="flex flex-wrap items-center gap-2 text-sm">
                  <span className="text-zinc-500">{e.ambiente === "PRODUCAO" ? "Produção" : "Homologação"}:</span>
                  <span>{e.status}{e.numero ? ` · NF-e ${e.serie}/${e.numero}` : ""}</span>
                  {e.chave_acesso ? <span className="font-mono text-xs text-zinc-500">{e.chave_acesso}</span> : null}
                  {e.status === "REJEITADA" || e.status === "ERRO" ? <span className="text-red-300">{e.codigo_status ? `cStat ${e.codigo_status} · ` : ""}{e.mensagem}</span> : null}
                  {e.status === "AUTORIZADA" ? <>
                    <button type="button" className={button} disabled={busy === e.documento_fiscal_id || !e.danfe_path} onClick={() => void abrirArquivo(e, "DANFE")}>DANFE</button>
                    <button type="button" className={button} disabled={busy === e.documento_fiscal_id || !e.xml_path} onClick={() => void abrirArquivo(e, "XML")}>XML</button>
                    <Link href={`/faturamento/nfe/${e.documento_fiscal_id}?retorno=/faturamento/operacoes`} className={button}>Ciclo de vida</Link>
                  </> : null}
                </div>
              ))}
              {!cancelada ? (
                <div className="flex flex-wrap gap-2 pt-1">
                  {podeHomologar ? <button type="button" className="rounded-md bg-sky-600 px-3 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50" disabled={ocupado} onClick={() => void emitirHomologacao(r)}>{hom ? "Tentar homologação de novo" : "Emitir em homologação"}</button> : null}
                  {homAutorizada && !prodAutorizada && linkPerfil ? <Link href={linkPerfil} className={button}>Liberar perfil para produção</Link> : null}
                  {podeProduzir ? <button type="button" className="rounded-md bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50" disabled={ocupado} onClick={() => void emitirProducao(r)}>Emitir NF-e real (produção)</button> : null}
                  {!prod ? <button type="button" className={button} disabled={ocupado} onClick={() => void cancelar(r)}>Cancelar remessa</button> : null}
                </div>
              ) : null}
            </article>
          );
        })}
      </section>
    </div>
  );
}
