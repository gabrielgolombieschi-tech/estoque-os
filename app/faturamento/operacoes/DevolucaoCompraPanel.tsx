"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { formatMoneyBR } from "@/lib/decimal";
import { parseNfeXml } from "@/lib/nfe/parseNfeXml";
import { supabaseBrowser } from "@/lib/supabase/client";

/**
 * Devolucao de compra ao fornecedor.
 *
 * A mercadoria entrou por NF-e (XML importado em Estoque › Importar) e parte dela volta ao
 * fornecedor: NF-e de devolucao (finNFe 4, CFOP 5201/6201), espelho proporcional da linha de
 * origem com os impostos da nota de entrada (ICMS, IPI, PIS e COFINS), NFref com a chave e sem
 * cobranca. f.fn_devolucao_compra_nfe_criar monta a operacao e a solicitacao; nfe-emitir manda
 * para a Focus em homologacao; a liberacao do perfil e pela tela de perfis; nfe-emitir-producao
 * emite a nota real, que da baixa no estoque.
 *
 * Orientacao da contadora (17/09/2026, NF-e 121481/3 da Acos America): CFOP 5201, saida
 * tributada com o CST da origem, IPI fora da base do ICMS, transporte com volumes e peso.
 */

type Entrada = { id: number; numero: string | null; serie: string | null; emitente_nome: string | null; emitente_cnpj: string | null; data_emissao: string | null; valor_total: number | string | null; chave: string | null };
type ItemXml = {
  nitem: number; codigo: string; descricao: string; ncm: string | null; unidade: string | null; quantidade_original: number | string; valor_unitario: number | string; valor_total: number | string;
  cfop_original: string | null; cst_icms: string | null; csosn: string | null; aliquota_icms: number | string | null; cst_ipi: string | null; aliquota_ipi: number | string | null;
  cst_pis: string | null; aliquota_pis: number | string | null; cst_cofins: string | null; aliquota_cofins: number | string | null; origem: number | null;
};
type Preparo = { nf_entrada_id: number; chave: string; numero: string; fornecedor: string; valor_total: number | string; itens: ItemXml[] };
type Emitente = { nome: string | null; documento: string | null; ie: string | null; uf: string | null; cidade: string | null; endereco: string | null };
type Operacao = {
  id: string; solicitacao_id: string | null; status: string; cfop_confirmado: string | null; valor_total: number | string; created_at: string; nf_entrada_origem_id: number | null;
  dados_json: { perfil_codigo?: string | null; origem_numero?: string | null; origem_serie?: string | null; origem_emitente?: string | null; origem_data_emissao?: string | null; estoque_pendencias?: Array<{ codigo?: string; quantidade?: number; saldo?: number; motivo?: string }>; estoque_movimentacoes?: unknown[] } | null;
};
type OperacaoItem = { operacao_id: string; ordem: number; codigo: string; descricao: string; quantidade: number | string; quantidade_original: number | string; unidade: string | null; valor_total: number | string; valor_ipi: number | string | null };
type Emissao = {
  documento_fiscal_id: string; solicitacao_id: string; ambiente: "HOMOLOGACAO" | "PRODUCAO"; status: string; chave_acesso: string | null; numero: number | null; serie: number | null;
  codigo_status: number | null; mensagem: string | null; xml_path: string | null; danfe_path: string | null; autorizado_em: string | null; updated_at: string;
};
type ProducaoStatus = {
  pronta?: boolean; motivo?: string | null; preflight_confirmacao_pronto?: boolean;
  resumo_confirmacao?: { nome_destinatario?: string; documento_destinatario_mascarado?: string; valor_total?: number | string; contexto_hash?: string } | null;
};

const CFOP_DESCRICAO: Record<string, string> = {
  "5201": "Devolução de compra para industrialização (dentro de SC)",
  "5553": "Devolução de compra de bem para o ativo imobilizado (dentro de SC)",
  "6201": "Devolução de compra para industrialização (fora de SC)",
  "6556": "Devolução de compra de material de uso ou consumo (fora de SC)",
};
const MODALIDADES_FRETE: Array<[string, string]> = [
  ["0", "0 · Por conta do remetente (SEGAU paga)"],
  ["1", "1 · Por conta do destinatário (fornecedor paga)"],
  ["2", "2 · Por conta de terceiros"],
  ["3", "3 · Transporte próprio, por conta do remetente"],
  ["4", "4 · Transporte próprio, por conta do destinatário"],
  ["9", "9 · Sem frete"],
];
const field = "rounded border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500";
const label = "space-y-1 text-xs text-zinc-400";
const button = "rounded border border-zinc-600 bg-zinc-900 px-3 py-2 text-sm hover:bg-zinc-800 disabled:cursor-not-allowed disabled:opacity-40";
const primario = "rounded-md bg-sky-600 px-3 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50";

function numero(valor: unknown) {
  const n = Number(String(valor ?? "").replace(",", "."));
  return Number.isFinite(n) ? n : 0;
}
function qtd(valor: unknown, casas = 4) {
  return numero(valor).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: casas });
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
function cnpjFormatado(valor: string | null | undefined) {
  const d = String(valor ?? "").replace(/\D/g, "");
  return d.length === 14 ? d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5") : (valor ?? "");
}
function dataBR(valor: string | null | undefined) {
  if (!valor) return "—";
  const d = valor.length === 10 ? new Date(`${valor}T00:00:00`) : new Date(valor);
  return Number.isNaN(d.getTime()) ? valor : d.toLocaleDateString("pt-BR");
}
function statusRotulo(status: string) {
  if (status === "PRONTO_HOMOLOGACAO") return "Em homologação";
  if (status === "CONCLUIDA") return "Concluída";
  if (status === "CANCELADA") return "Cancelada";
  return status;
}
/** Emitente da entrada (destinatario da devolucao) lido do XML so para mostrar; quem grava e o banco. */
function lerEmitente(xml: string | null): Emitente | null {
  if (!xml) return null;
  try {
    const { nfe } = parseNfeXml(xml);
    const endereco = [nfe.endEmitLogradouro, nfe.endEmitNumero, nfe.endEmitBairro].filter(Boolean).join(", ");
    return {
      nome: nfe.emitente, documento: nfe.cnpjEmitente, ie: nfe.inscricaoEstadualEmitente ?? null, uf: nfe.endEmitUf?.toUpperCase() ?? null,
      cidade: nfe.endEmitCidade ?? null, endereco: endereco || null,
    };
  } catch {
    return null;
  }
}

export default function DevolucaoCompraPanel({ empresaId }: { tenantId: string; empresaId: string }) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [busy, setBusy] = useState<string | null>(null);
  const [aviso, setAviso] = useState<{ texto: string; erro: boolean } | null>(null);
  const [empresaUf, setEmpresaUf] = useState<string | null>(null);

  // 1 · nota de entrada
  const [busca, setBusca] = useState("");
  const [entradas, setEntradas] = useState<Entrada[]>([]);
  const [buscou, setBuscou] = useState(false);
  const [selecionada, setSelecionada] = useState<Entrada | null>(null);
  const [preparo, setPreparo] = useState<Preparo | null>(null);
  const [emitente, setEmitente] = useState<Emitente | null>(null);

  // 2 · itens e transporte
  const [quantidades, setQuantidades] = useState<Record<number, string>>({});
  const [cfop, setCfop] = useState("");
  const [modalidade, setModalidade] = useState("0");
  const [qVol, setQVol] = useState("1");
  const [especie, setEspecie] = useState("");
  const [pesoLiquido, setPesoLiquido] = useState("");
  const [pesoBruto, setPesoBruto] = useState("");
  const [transp, setTransp] = useState({ nome: "", documento: "", inscricao_estadual: "", uf: "", municipio: "" });
  const [observacao, setObservacao] = useState("");

  // 3 · devolucoes
  const [operacoes, setOperacoes] = useState<Operacao[]>([]);
  const [opItens, setOpItens] = useState<OperacaoItem[]>([]);
  const [emissoes, setEmissoes] = useState<Emissao[]>([]);
  const [perfisLiberados, setPerfisLiberados] = useState<string[]>([]);
  const [filtro, setFiltro] = useState<"ATIVAS" | "TODAS">("ATIVAS");

  const avisar = useCallback((texto: string, erro = false) => setAviso(texto ? { texto, erro } : null), []);

  const carregar = useCallback(async () => {
    const { data, error } = await supabase.schema("f").from("operacao_fiscal")
      .select("id,solicitacao_id,status,cfop_confirmado,valor_total,created_at,nf_entrada_origem_id,dados_json")
      .eq("tipo", "DEVOLUCAO_COMPRA").is("deleted_at", null).order("created_at", { ascending: false }).limit(100);
    if (error) throw error;
    const lista = (data ?? []) as Operacao[];
    setOperacoes(lista);
    const ids = lista.map((o) => o.id);
    const sols = lista.map((o) => o.solicitacao_id).filter((id): id is string => Boolean(id));
    const [it, em, perfis] = await Promise.all([
      ids.length ? supabase.schema("f").from("operacao_fiscal_item").select("operacao_id,ordem,codigo,descricao,quantidade,quantidade_original,unidade,valor_total,valor_ipi").in("operacao_id", ids).order("ordem") : Promise.resolve({ data: [], error: null }),
      sols.length ? supabase.schema("f").from("documento_fiscal_emissao").select("documento_fiscal_id,solicitacao_id,ambiente,status,chave_acesso,numero,serie,codigo_status,mensagem,xml_path,danfe_path,autorizado_em,updated_at").in("solicitacao_id", sols).order("updated_at", { ascending: false }) : Promise.resolve({ data: [], error: null }),
      // Perfil liberado PARA ESTA solicitacao: o link "Liberar perfil" some da linha.
      supabase.schema("f").from("perfil_operacao").select("codigo,habilitado_producao,producao_homologacao_solicitacao_id").eq("modelo", "NFE").eq("natureza_operacao", "DEVOLUCAO_COMPRA"),
    ]);
    if (it.error) throw it.error;
    if (em.error) throw em.error;
    if (perfis.error) throw perfis.error;
    setOpItens((it.data ?? []) as OperacaoItem[]);
    setEmissoes((em.data ?? []) as Emissao[]);
    setPerfisLiberados(((perfis.data ?? []) as Array<{ codigo: string; habilitado_producao: boolean; producao_homologacao_solicitacao_id: string | null }>)
      .filter((p) => p.habilitado_producao && p.producao_homologacao_solicitacao_id)
      .map((p) => `${p.codigo}|${p.producao_homologacao_solicitacao_id}`));
  }, [supabase]);

  useEffect(() => { void carregar().catch((e) => avisar(textoErro(e), true)); }, [carregar, avisar]);
  useEffect(() => {
    void supabase.from("empresas").select("uf").eq("id", empresaId).maybeSingle().then(({ data }) => {
      const e = data as { uf?: string | null } | null;
      setEmpresaUf(e?.uf ? String(e.uf).toUpperCase() : null);
    });
  }, [empresaId, supabase]);
  // Retorno da SEFAZ chega pelo callback: atualiza sozinho.
  useEffect(() => {
    const canal = supabase.channel(`devolucao-compra-${empresaId}`)
      .on("postgres_changes", { event: "*", schema: "f", table: "documento_fiscal_emissao", filter: `empresa_id=eq.${empresaId}` }, () => void carregar().catch(() => {}))
      .on("postgres_changes", { event: "*", schema: "f", table: "operacao_fiscal", filter: `empresa_id=eq.${empresaId}` }, () => void carregar().catch(() => {}))
      .subscribe();
    return () => { void supabase.removeChannel(canal); };
  }, [carregar, empresaId, supabase]);
  useEffect(() => {
    if (!emissoes.some((e) => ["ENVIANDO", "PROCESSANDO"].includes(e.status))) return;
    const timer = window.setInterval(() => void carregar().catch(() => {}), 5000);
    return () => window.clearInterval(timer);
  }, [carregar, emissoes]);

  // ---------------------------------------------------------------- 1 · buscar e ler a entrada
  async function buscar() {
    setBusy("buscar"); avisar("");
    try {
      const termo = busca.trim();
      let q = supabase.from("nf_entrada").select("id,numero,serie,emitente_nome,emitente_cnpj,data_emissao,valor_total,chave")
        .eq("empresa_id", empresaId).is("deleted_at", null).not("xml_raw", "is", null).order("data_emissao", { ascending: false }).limit(20);
      if (termo) {
        const d = termo.replace(/\D/g, "");
        q = d.length === 44 ? q.eq("chave", d) : q.or(`numero.ilike.%${termo.replace(/[%,()]/g, "")}%,emitente_nome.ilike.%${termo.replace(/[%,()]/g, "")}%`);
      }
      const { data, error } = await q;
      if (error) throw error;
      setEntradas((data ?? []) as Entrada[]);
      setBuscou(true);
    } catch (e) { avisar(textoErro(e), true); } finally { setBusy(null); }
  }

  async function selecionar(entrada: Entrada) {
    setBusy(`ler-${entrada.id}`); avisar("");
    try {
      const [{ data, error }, xml] = await Promise.all([
        supabase.schema("f").rpc("fn_devolucao_compra_preparar", { p_nf_entrada_id: entrada.id }),
        supabase.from("nf_entrada").select("xml_raw").eq("id", entrada.id).maybeSingle(),
      ]);
      if (error) throw error;
      const p = data as Preparo;
      const emit = lerEmitente((xml.data as { xml_raw?: string | null } | null)?.xml_raw ?? null);
      setSelecionada(entrada);
      setPreparo(p);
      setEmitente(emit);
      setQuantidades(Object.fromEntries(p.itens.map((i) => [i.nitem, ""])));
      const interestadual = Boolean(empresaUf) && Boolean(emit?.uf) && emit?.uf !== empresaUf;
      setCfop(interestadual ? "6201" : "5201");
      setModalidade("0"); setQVol("1"); setEspecie(""); setPesoLiquido(""); setPesoBruto("");
      setTransp({ nome: "", documento: "", inscricao_estadual: "", uf: "", municipio: "" });
      setObservacao("");
      avisar(`XML validado: NF-e ${p.numero} de ${p.fornecedor}, ${p.itens.length} item(ns). Informe a quantidade a devolver de cada item.`);
    } catch (e) { avisar(textoErro(e), true); } finally { setBusy(null); }
  }

  const cfopsDisponiveis = useMemo(() => {
    const interestadual = Boolean(empresaUf) && Boolean(emitente?.uf) && emitente?.uf !== empresaUf;
    return interestadual ? ["6201", "6556"] : ["5201", "5553"];
  }, [emitente?.uf, empresaUf]);

  const itensEscolhidos = useMemo(() => (preparo?.itens ?? []).flatMap((i) => {
    const q = numero(quantidades[i.nitem]);
    return q > 0 ? [{ nitem: i.nitem, quantidade: q, item: i }] : [];
  }), [preparo, quantidades]);
  const totalDevolver = itensEscolhidos.reduce((acc, e) => acc + numero(e.item.valor_unitario) * e.quantidade, 0);
  const pesoTotal = itensEscolhidos.filter((e) => String(e.item.unidade ?? "").toUpperCase() === "KG").reduce((acc, e) => acc + e.quantidade, 0);

  // ---------------------------------------------------------------- 2 · gerar e homologar
  async function gerarEHomologar() {
    if (!selecionada || !preparo) return;
    if (itensEscolhidos.length === 0) return avisar("Informe a quantidade a devolver de ao menos um item.", true);
    const acima = itensEscolhidos.find((e) => e.quantidade > numero(e.item.quantidade_original));
    if (acima) return avisar(`Item ${acima.nitem}: a quantidade a devolver (${qtd(acima.quantidade)}) passa da nota (${qtd(acima.item.quantidade_original)}).`, true);
    setBusy("gerar"); avisar("");
    try {
      const volumes = modalidade !== "9"
        ? [{ quantidade: Math.max(1, Math.round(numero(qVol))), especie: especie.trim() || null, peso_liquido: numero(pesoLiquido), peso_bruto: numero(pesoBruto || pesoLiquido) }]
        : null;
      const transportador = modalidade !== "9" && transp.nome.trim()
        ? { nome: transp.nome.trim(), documento: transp.documento.replace(/\D/g, "") || null, inscricao_estadual: transp.inscricao_estadual.trim() || null, uf: transp.uf.trim().toUpperCase() || null, municipio: transp.municipio.trim() || null }
        : null;
      const { data, error } = await supabase.schema("f").rpc("fn_devolucao_compra_nfe_criar", {
        p_nf_entrada_id: selecionada.id,
        p_itens: itensEscolhidos.map((e) => ({ nitem: e.nitem, quantidade: e.quantidade })),
        p_modalidade_frete: Number(modalidade),
        p_volumes: volumes,
        p_observacao: observacao.trim() || null,
        p_transportador: transportador,
        p_cfop: cfop,
      });
      if (error) throw error;
      const r = data as { solicitacao_id: string; cfop: string; valor_total: number; destinatario: string };
      const { data: env, error: erroEnv } = await supabase.functions.invoke("nfe-emitir", { body: { solicitacao_id: r.solicitacao_id } });
      if (erroEnv) throw erroEnv;
      if (env?.erro) throw new Error(env.codigo ? `cStat ${env.codigo} · ${env.erro}` : String(env.erro));
      setSelecionada(null); setPreparo(null); setEmitente(null);
      avisar(`Devolução CFOP ${r.cfop} para ${r.destinatario} (R$ ${formatMoneyBR(numero(r.valor_total))}) enviada à Focus em homologação. O retorno da SEFAZ chega automaticamente.`);
    } catch (e) {
      avisar(await erroFunction(e), true);
    } finally {
      setBusy(null);
      await carregar().catch(() => {});
    }
  }

  async function emitirHomologacao(op: Operacao) {
    if (!op.solicitacao_id) return;
    setBusy(op.id); avisar("");
    try {
      const { data, error } = await supabase.functions.invoke("nfe-emitir", { body: { solicitacao_id: op.solicitacao_id } });
      if (error) throw error;
      if (data?.erro) throw new Error(data.codigo ? `cStat ${data.codigo} · ${data.erro}` : String(data.erro));
      avisar("Devolução enviada à Focus em homologação. O retorno da SEFAZ chega automaticamente.");
    } catch (e) { avisar(await erroFunction(e), true); } finally { setBusy(null); await carregar().catch(() => {}); }
  }

  async function emitirProducao(op: Operacao) {
    if (!op.solicitacao_id) return;
    setBusy(op.id); avisar("");
    try {
      const { data: st, error: erroSt } = await supabase.functions.invoke("nfe-emitir-producao", { body: { acao: "STATUS", solicitacao_id: op.solicitacao_id } });
      if (erroSt) throw erroSt;
      const status = st as ProducaoStatus | null;
      const resumo = status?.resumo_confirmacao;
      if (!status?.pronta || !status.preflight_confirmacao_pronto || !resumo?.contexto_hash) {
        throw new Error(status?.motivo ?? "A produção ainda não está liberada para esta devolução.");
      }
      const ok = window.confirm(
        `EMITIR NF-e REAL DE DEVOLUÇÃO DE COMPRA (produção)\n\nDestinatário: ${resumo.nome_destinatario ?? "?"} (${resumo.documento_destinatario_mascarado ?? "?"})\n`
        + `Origem: NF-e ${op.dados_json?.origem_numero ?? "?"}/${op.dados_json?.origem_serie ?? "?"} de ${op.dados_json?.origem_data_emissao ?? "?"} · CFOP ${op.cfop_confirmado}\n`
        + `Valor da nota: R$ ${formatMoneyBR(numero(resumo.valor_total))} · impostos destacados como na origem · sem cobrança\n\nQuando autorizar, a mercadoria sai do estoque. Deseja continuar?`,
      );
      if (!ok) return;
      const { data, error } = await supabase.functions.invoke("nfe-emitir-producao", { body: { acao: "EMITIR", solicitacao_id: op.solicitacao_id, confirmacao_contexto_hash: resumo.contexto_hash } });
      if (error) throw error;
      if (data?.erro) throw new Error(data.codigo ? `cStat ${data.codigo} · ${data.erro}` : String(data.erro));
      avisar("NF-e de devolução enviada à SEFAZ em PRODUÇÃO.");
    } catch (e) { avisar(await erroFunction(e), true); } finally { setBusy(null); await carregar().catch(() => {}); }
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

  const listadas = operacoes.filter((o) => filtro === "TODAS" || o.status !== "CANCELADA");
  const itensDa = (id: string) => opItens.filter((i) => i.operacao_id === id);

  return (
    <div className="space-y-5">
      <div>
        <h2 className="font-semibold">Devolução de compra ao fornecedor</h2>
        <p className="mt-1 text-sm text-zinc-400">
          Parte (ou o todo) de uma mercadoria que entrou por NF-e volta ao fornecedor. A NF-e de devolução (finalidade 4, CFOP 5201 dentro de SC ou 6201 fora)
          espelha a linha da nota de entrada na quantidade devolvida, com ICMS, IPI, PIS e COFINS como vieram, referencia a chave da entrada e sai sem cobrança.
          A nota real dá baixa no estoque.
        </p>
      </div>
      {aviso ? <div role={aviso.erro ? "alert" : "status"} className={`rounded border p-3 text-sm ${aviso.erro ? "border-red-900 bg-red-950/30 text-red-200" : "border-sky-800 bg-sky-950/30 text-sky-200"}`}>{aviso.texto}</div> : null}

      <section className="space-y-3 rounded-lg border border-zinc-800 p-4">
        <h3 className="font-medium">1 · Nota de entrada de origem</h3>
        <p className="text-sm text-zinc-400">Só entra nota importada com o XML (Estoque › Importar). Busque pelo número, pelo fornecedor ou pela chave.</p>
        <div className="flex flex-wrap gap-2">
          <input aria-label="Buscar nota de entrada" className={`${field} min-w-72 flex-1`} value={busca} onChange={(e) => setBusca(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") void buscar(); }} placeholder="Número da NF, fornecedor ou chave de acesso" />
          <button type="button" className={button} disabled={busy === "buscar"} onClick={() => void buscar()}>{busy === "buscar" ? "Buscando..." : "Buscar"}</button>
        </div>
        {buscou ? (
          entradas.length === 0 ? <p className="text-sm text-zinc-500">Nenhuma nota de entrada com XML encontrada.</p> : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[720px] text-sm">
                <thead className="text-left text-xs uppercase text-zinc-500"><tr><th className="py-2 pr-3">NF-e</th><th className="py-2 pr-3">Fornecedor</th><th className="py-2 pr-3">Emissão</th><th className="py-2 pr-3 text-right">Valor</th><th className="py-2 pr-3">Chave</th><th className="py-2 text-right"></th></tr></thead>
                <tbody className="divide-y divide-zinc-800">
                  {entradas.map((n) => (
                    <tr key={n.id} className={selecionada?.id === n.id ? "bg-sky-950/30" : ""}>
                      <td className="py-2 pr-3 whitespace-nowrap">{n.numero}/{n.serie}</td>
                      <td className="py-2 pr-3"><div>{n.emitente_nome}</div><div className="text-xs text-zinc-500">{cnpjFormatado(n.emitente_cnpj)}</div></td>
                      <td className="py-2 pr-3 whitespace-nowrap">{dataBR(n.data_emissao)}</td>
                      <td className="py-2 pr-3 text-right tabular-nums whitespace-nowrap">R$ {formatMoneyBR(numero(n.valor_total))}</td>
                      <td className="py-2 pr-3 font-mono text-xs" title={n.chave ?? ""}>{n.chave ? `${n.chave.slice(0, 8)}…${n.chave.slice(-6)}` : "—"}</td>
                      <td className="py-2 text-right"><button type="button" className={primario} disabled={busy === `ler-${n.id}`} onClick={() => void selecionar(n)}>{busy === `ler-${n.id}` ? "Lendo XML..." : "Ler XML e devolver"}</button></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )
        ) : null}
      </section>

      {selecionada && preparo ? (
        <section className="space-y-4 rounded-lg border border-zinc-800 p-4">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div>
              <h3 className="font-medium">2 · Itens a devolver da NF-e {preparo.numero}/{selecionada.serie}</h3>
              <p className="text-sm text-zinc-400">Chave <span className="font-mono text-xs">{preparo.chave}</span></p>
            </div>
            <button type="button" className={button} onClick={() => { setSelecionada(null); setPreparo(null); setEmitente(null); }}>Trocar nota</button>
          </div>

          <div className="rounded border border-zinc-800 bg-zinc-900/40 p-3 text-sm">
            <div className="text-xs uppercase text-zinc-500">Destinatário (emitente da entrada, do XML)</div>
            <div className="font-medium">{emitente?.nome ?? preparo.fornecedor}</div>
            <div className="text-xs text-zinc-400">CNPJ {cnpjFormatado(emitente?.documento ?? selecionada.emitente_cnpj)} · IE {emitente?.ie ?? "não informada"}</div>
            {emitente?.endereco || emitente?.cidade ? <div className="text-xs text-zinc-400">{emitente?.endereco}{emitente?.endereco && emitente?.cidade ? " · " : ""}{emitente?.cidade}{emitente?.uf ? `/${emitente.uf}` : ""}</div> : null}
          </div>

          <div className="overflow-x-auto">
            <table className="w-full min-w-[900px] text-sm">
              <thead className="text-left text-xs uppercase text-zinc-500"><tr><th className="py-1">#</th><th className="py-1">Código</th><th className="py-1">Descrição</th><th className="py-1">NCM</th><th className="py-1">Un.</th><th className="py-1 text-right">Qtd. na nota</th><th className="py-1 text-right">Vl. unit.</th><th className="py-1">ICMS</th><th className="py-1">IPI</th><th className="py-1">PIS/COFINS</th><th className="py-1 text-right">Qtd. a devolver</th></tr></thead>
              <tbody className="divide-y divide-zinc-800">
                {preparo.itens.map((i) => (
                  <tr key={i.nitem}>
                    <td className="py-1 pr-2">{i.nitem}</td>
                    <td className="py-1 pr-2 font-mono text-xs">{i.codigo}</td>
                    <td className="py-1 pr-2">{i.descricao}</td>
                    <td className="py-1 pr-2">{i.ncm ?? "?"}</td>
                    <td className="py-1 pr-2">{i.unidade}</td>
                    <td className="py-1 pr-2 text-right tabular-nums">{qtd(i.quantidade_original)}</td>
                    <td className="py-1 pr-2 text-right tabular-nums">{numero(i.valor_unitario).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 10 })}</td>
                    <td className="py-1 pr-2 text-xs">{i.csosn ? `CSOSN ${i.csosn}` : `CST ${i.cst_icms ?? "?"}`}{i.aliquota_icms != null ? ` · ${qtd(i.aliquota_icms, 2)}%` : ""}</td>
                    <td className="py-1 pr-2 text-xs">{i.cst_ipi ? `CST ${i.cst_ipi}` : "—"}{i.aliquota_ipi != null ? ` · ${qtd(i.aliquota_ipi, 2)}%` : ""}</td>
                    <td className="py-1 pr-2 text-xs">{i.cst_pis ?? "?"}/{i.cst_cofins ?? "?"}</td>
                    <td className="py-1 text-right"><input aria-label={`Quantidade a devolver do item ${i.nitem}`} className={`${field} w-28 text-right`} inputMode="decimal" value={quantidades[i.nitem] ?? ""} onChange={(e) => setQuantidades((q) => ({ ...q, [i.nitem]: e.target.value }))} placeholder="0" /></td>
                  </tr>
                ))}
              </tbody>
              <tfoot><tr><td colSpan={10} className="py-1 text-right text-xs uppercase text-zinc-500">Valor da mercadoria devolvida (sem o IPI)</td><td className="py-1 text-right font-semibold tabular-nums">R$ {formatMoneyBR(totalDevolver)}</td></tr></tfoot>
            </table>
            <p className="mt-1 text-xs text-zinc-500">Cada item devolvido espelha a linha da nota: mesmo código, descrição, NCM, unidade e valor unitário; ICMS, IPI, PIS e COFINS com os CST e alíquotas do XML, proporcionais à quantidade. IPI fora da base do ICMS, como na entrada. Sem cobrança (tPag 90).</p>
          </div>

          <div className="grid gap-3 md:grid-cols-2">
            <label className={label}>CFOP da devolução<select aria-label="CFOP da devolução" className={`${field} w-full`} value={cfop} onChange={(e) => setCfop(e.target.value)}>{cfopsDisponiveis.map((c) => <option key={c} value={c}>{c} · {CFOP_DESCRICAO[c] ?? c}</option>)}</select></label>
            <label className={label}>Modalidade do frete<select aria-label="Modalidade do frete da devolução" className={`${field} w-full`} value={modalidade} onChange={(e) => setModalidade(e.target.value)}>{MODALIDADES_FRETE.map(([c, r]) => <option key={c} value={c}>{r}</option>)}</select></label>
          </div>
          {modalidade !== "9" ? (
            <>
              <div className="grid gap-3 md:grid-cols-4">
                <label className={label}>Quantidade de volumes<input aria-label="Quantidade de volumes" className={`${field} w-full`} inputMode="numeric" value={qVol} onChange={(e) => setQVol(e.target.value)} /></label>
                <label className={label}>Espécie (opcional)<input aria-label="Espécie dos volumes" className={`${field} w-full`} value={especie} onChange={(e) => setEspecie(e.target.value)} maxLength={60} placeholder="Ex.: FEIXE" /></label>
                <label className={label}>Peso líquido (kg)<input aria-label="Peso líquido" className={`${field} w-full`} inputMode="decimal" value={pesoLiquido} onChange={(e) => setPesoLiquido(e.target.value)} placeholder={pesoTotal > 0 ? qtd(pesoTotal, 3) : "0,000"} /></label>
                <label className={label}>Peso bruto (kg)<input aria-label="Peso bruto" className={`${field} w-full`} inputMode="decimal" value={pesoBruto} onChange={(e) => setPesoBruto(e.target.value)} placeholder="= líquido" /></label>
              </div>
              {pesoTotal > 0 && !pesoLiquido ? <button type="button" className="text-xs text-sky-300 underline" onClick={() => { setPesoLiquido(pesoTotal.toFixed(3).replace(".", ",")); setPesoBruto(pesoTotal.toFixed(3).replace(".", ",")); }}>Usar a quantidade em kg como peso ({qtd(pesoTotal, 3)} kg)</button> : null}
              <details className="rounded border border-zinc-800 p-3 text-sm">
                <summary className="cursor-pointer text-zinc-300">Transportadora (opcional)</summary>
                <div className="mt-3 grid gap-3 md:grid-cols-3">
                  <label className={label}>Nome<input aria-label="Nome da transportadora" className={`${field} w-full`} value={transp.nome} onChange={(e) => setTransp((t) => ({ ...t, nome: e.target.value }))} maxLength={60} /></label>
                  <label className={label}>CNPJ/CPF<input aria-label="CNPJ da transportadora" className={`${field} w-full`} value={transp.documento} onChange={(e) => setTransp((t) => ({ ...t, documento: e.target.value }))} /></label>
                  <label className={label}>IE<input aria-label="IE da transportadora" className={`${field} w-full`} value={transp.inscricao_estadual} onChange={(e) => setTransp((t) => ({ ...t, inscricao_estadual: e.target.value }))} /></label>
                  <label className={label}>Município<input aria-label="Município da transportadora" className={`${field} w-full`} value={transp.municipio} onChange={(e) => setTransp((t) => ({ ...t, municipio: e.target.value }))} /></label>
                  <label className={label}>UF<input aria-label="UF da transportadora" className={`${field} w-full`} value={transp.uf} onChange={(e) => setTransp((t) => ({ ...t, uf: e.target.value }))} maxLength={2} /></label>
                </div>
              </details>
            </>
          ) : null}
          <label className={label}>Observação (vai nas informações complementares, depois do texto da devolução)<textarea aria-label="Observação da devolução" className={`${field} min-h-16 w-full`} value={observacao} onChange={(e) => setObservacao(e.target.value)} maxLength={500} /></label>
          <div className="flex flex-wrap justify-end gap-2">
            <button type="button" className={primario} disabled={busy === "gerar" || itensEscolhidos.length === 0 || (modalidade !== "9" && numero(pesoLiquido) <= 0)} onClick={() => void gerarEHomologar()}>{busy === "gerar" ? "Gerando..." : "Gerar devolução e emitir em homologação"}</button>
          </div>
        </section>
      ) : null}

      <section className="space-y-3 rounded-lg border border-zinc-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="font-medium">3 · Devoluções</h3>
          <label className={label}>Mostrar<select aria-label="Filtrar devoluções" className={`${field} w-full`} value={filtro} onChange={(e) => setFiltro(e.target.value as typeof filtro)}><option value="ATIVAS">Em andamento e concluídas</option><option value="TODAS">Todas, com canceladas</option></select></label>
        </div>
        {listadas.length === 0 ? <p className="text-sm text-zinc-500">Nenhuma devolução gerada.</p> : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[960px] text-sm">
              <thead className="text-left text-xs uppercase text-zinc-500"><tr><th className="py-2 pr-3">Nota de origem</th><th className="py-2 pr-3">Itens devolvidos</th><th className="py-2 pr-3">CFOP</th><th className="py-2 pr-3 text-right">Valor</th><th className="py-2 pr-3">Status</th><th className="py-2 pr-3">NF-e de devolução</th><th className="py-2 text-right">Ações</th></tr></thead>
              <tbody className="divide-y divide-zinc-800">
                {listadas.map((op) => {
                  const hom = emissoes.find((e) => e.solicitacao_id === op.solicitacao_id && e.ambiente === "HOMOLOGACAO");
                  const prod = emissoes.find((e) => e.solicitacao_id === op.solicitacao_id && e.ambiente === "PRODUCAO");
                  const ocupado = busy === op.id;
                  const ativa = op.status !== "CANCELADA" && op.status !== "CONCLUIDA";
                  const homAutorizada = hom?.status === "AUTORIZADA";
                  const podeHomologar = ativa && Boolean(op.solicitacao_id) && !prod && (!hom || ["RASCUNHO", "REJEITADA", "ERRO"].includes(hom.status));
                  const podeProduzir = ativa && homAutorizada && (!prod || ["RASCUNHO", "REJEITADA", "ERRO"].includes(prod.status));
                  const perfilCodigo = op.dados_json?.perfil_codigo ?? null;
                  const linkPerfil = perfilCodigo && op.solicitacao_id && !perfisLiberados.includes(`${perfilCodigo}|${op.solicitacao_id}`)
                    ? `/faturamento/perfis?perfil=${encodeURIComponent(perfilCodigo)}&solicitacao=${op.solicitacao_id}&retorno=/faturamento/operacoes?aba=DEVOLUCAO`
                    : null;
                  const pendencias = op.dados_json?.estoque_pendencias ?? [];
                  return (
                    <tr key={op.id} className="align-top">
                      <td className="py-2 pr-2"><div>NF-e {op.dados_json?.origem_numero ?? "?"}/{op.dados_json?.origem_serie ?? "?"} de {op.dados_json?.origem_data_emissao ?? "?"}</div><div className="text-xs text-zinc-500">{op.dados_json?.origem_emitente ?? ""}</div></td>
                      <td className="py-2 pr-2 text-xs">{itensDa(op.id).map((i) => <div key={`${op.id}-${i.ordem}`}>{i.codigo} · {qtd(i.quantidade)} de {qtd(i.quantidade_original)} {i.unidade}</div>)}</td>
                      <td className="py-2 pr-2">{op.cfop_confirmado}</td>
                      <td className="py-2 pr-2 text-right tabular-nums whitespace-nowrap">R$ {formatMoneyBR(numero(op.valor_total))}</td>
                      <td className="py-2 pr-2">
                        <div>{statusRotulo(op.status)}</div>
                        {op.status === "CONCLUIDA" && (op.dados_json?.estoque_movimentacoes?.length ?? 0) > 0 ? <span className="mt-1 inline-block rounded-full border border-emerald-800 px-2 py-0.5 text-xs text-emerald-300">estoque baixado</span> : null}
                        {pendencias.length > 0 ? <div className="mt-1 text-xs text-amber-300" title={pendencias.map((p) => `${p.codigo ?? "?"}: ${p.motivo ?? ""} (saldo ${qtd(p.saldo ?? 0)})`).join("; ")}>estoque pendente: {pendencias.map((p) => p.codigo).join(", ")}</div> : null}
                      </td>
                      <td className="py-2 pr-2 text-xs">
                        {[hom, prod].filter((e): e is Emissao => Boolean(e)).map((e) => (
                          <div key={e.documento_fiscal_id} className="flex flex-wrap items-center gap-1">
                            <span className="text-zinc-500">{e.ambiente === "PRODUCAO" ? "Prod." : "Hom."}:</span>
                            <span>{e.status}{e.numero ? ` · NF-e ${e.serie}/${e.numero}` : ""}</span>
                            {e.status === "REJEITADA" || e.status === "ERRO" ? <span className="text-red-300">{e.codigo_status ? `cStat ${e.codigo_status} · ` : ""}{e.mensagem}</span> : null}
                            {e.status === "AUTORIZADA" ? <>
                              <button type="button" className="underline" disabled={busy === e.documento_fiscal_id || !e.danfe_path} onClick={() => void abrirArquivo(e, "DANFE")}>DANFE</button>
                              <button type="button" className="underline" disabled={busy === e.documento_fiscal_id || !e.xml_path} onClick={() => void abrirArquivo(e, "XML")}>XML</button>
                              <Link href={`/faturamento/nfe/${e.documento_fiscal_id}?retorno=/faturamento/operacoes?aba=DEVOLUCAO`} className="underline">Ciclo de vida</Link>
                            </> : null}
                          </div>
                        ))}
                        {!hom && !prod ? <span className="text-zinc-500">—</span> : null}
                      </td>
                      <td className="py-2 text-right">
                        <div className="flex flex-col items-end gap-1">
                          {podeHomologar ? <button type="button" className={button} disabled={ocupado} onClick={() => void emitirHomologacao(op)}>{hom ? "Tentar homologação de novo" : "Emitir em homologação"}</button> : null}
                          {ativa && homAutorizada && linkPerfil ? <Link href={linkPerfil} className={button}>Liberar perfil para produção</Link> : null}
                          {podeProduzir ? <button type="button" className="rounded-md bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50" disabled={ocupado} onClick={() => void emitirProducao(op)}>Emitir NF-e real (produção)</button> : null}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
