"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { formatMoneyBR } from "@/lib/decimal";
import { parseNfeXml } from "@/lib/nfe/parseNfeXml";
import { supabaseBrowser } from "@/lib/supabase/client";

/**
 * Retorno de mercadoria de terceiros.
 *
 * A WEG (e outros) manda pecas para a Segau industrializar ou consertar (NF-e 5901/6901 ou
 * 5915/6915). As pecas sao deles: nao entram no estoque, nao geram compra nem financeiro.
 * Aqui a nota recebida e importada do XML (f.fn_remessa_terceiros_importar), fica listada
 * enquanto a mercadoria esta em nosso poder e, na hora de devolver, gera a NF-e de RETORNO
 * (5902/5903 ou 5916) pelo mesmo pipeline da venda: f.fn_remessa_terceiros_retorno_criar
 * monta a solicitacao espelhando o XML, nfe-emitir manda para a Focus em homologacao e
 * nfe-emitir-producao em producao. A autorizacao em producao baixa a remessa (RETORNADA);
 * a de homologacao so carimba "homologada em".
 *
 * Producao desligada por padrao (f.retorno_terceiros_config); so o ADMIN da empresa liga.
 */

type Endereco = { logradouro?: string; numero?: string; complemento?: string; bairro?: string; cidade?: string; uf?: string; cep?: string; codigo_ibge_municipio?: string; telefone?: string };
type VolumeOrigem = { qVol?: number | null; esp?: string | null; pesoL?: number | null; pesoB?: number | null };
type Remessa = {
  id: string;
  chave: string;
  numero: string | null;
  serie: string | null;
  emitente_cnpj: string;
  emitente_nome: string;
  emitente_ie: string | null;
  emitente_endereco: Endereco | null;
  cfop_origem: string;
  nat_op: string | null;
  dh_emi: string;
  data_entrada: string;
  prazo_retorno: string;
  tipo: "INDUSTRIALIZACAO" | "CONSERTO" | "OUTRO";
  valor_total: number | string;
  status: "ABERTA" | "RETORNADA" | "CANCELADA";
  transporte_origem: { modFrete?: string | null; volumes?: VolumeOrigem[] } | null;
  solicitacao_retorno_id: string | null;
  nfe_homologacao_id: string | null;
  homologada_em: string | null;
  nfe_retorno_id: string | null;
  cfop_retorno: string | null;
  retornada_em: string | null;
  obs: string | null;
  is_teste: boolean;
};
type Item = { id: string; remessa_id: string; n_item: number; c_prod: string; x_prod: string; ncm: string | null; cfop_origem: string; u_com: string; q_com: number | string; v_un_com: number | string; v_prod: number | string; orig: number | null };
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
type Operacao = { id: string; solicitacao_id: string | null; status: string; dados_json: { perfil_codigo?: string | null; remessa_terceiros_id?: string } | null };
type ResultadoArquivo = { nome: string; ok: boolean; texto: string };
type ProducaoStatus = {
  pronta?: boolean;
  motivo?: string | null;
  preflight_confirmacao_pronto?: boolean;
  resumo_confirmacao?: { nome_destinatario?: string; documento_destinatario_mascarado?: string; valor_total?: number | string; contexto_hash?: string } | null;
};

const CFOPS_ORIGEM = ["5901", "6901", "5915", "6915"];
const CFOP_DESCRICAO: Record<string, string> = {
  "5902": "Retorno de mercadoria utilizada na industrialização por encomenda",
  "5903": "Retorno de mercadoria recebida para industrialização e não aplicada",
  "5916": "Retorno de mercadoria recebida para conserto ou reparo",
};
// Padrao 0, como a Segau ja emitia no Vertex (NF 3427, 23/09/2025).
const MODALIDADES_FRETE: Array<[string, string]> = [
  ["0", "0 · Por conta do remetente (SEGAU paga)"],
  ["1", "1 · Por conta do destinatário"],
  ["3", "3 · Por conta do destinatário, transporte próprio"],
  ["4", "4 · Por conta do remetente, transporte próprio"],
  ["9", "9 · Sem frete"],
];
const MODALIDADE_FRETE_PADRAO = "0";
const field = "rounded border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500";
const label = "space-y-1 text-xs text-zinc-400";
const button = "rounded border border-zinc-600 bg-zinc-900 px-3 py-2 text-sm hover:bg-zinc-800 disabled:cursor-not-allowed disabled:opacity-40";
const primario = "rounded-md bg-sky-600 px-3 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50";

function numero(valor: unknown) {
  const n = Number(String(valor ?? "").replace(",", "."));
  return Number.isFinite(n) ? n : 0;
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
function diasDesde(iso: string) {
  const inicio = new Date(iso);
  const hoje = new Date();
  return Math.max(0, Math.floor((Date.UTC(hoje.getFullYear(), hoje.getMonth(), hoje.getDate()) - Date.UTC(inicio.getFullYear(), inicio.getMonth(), inicio.getDate())) / 86400000));
}
/** Verde ate 149 dias, amarelo de 150 a 180, vermelho depois do prazo (Anexo 2, Art. 27). */
function corPrazo(dias: number) {
  if (dias > 180) return "border-rose-800 bg-rose-950/40 text-rose-200";
  if (dias >= 150) return "border-amber-700 bg-amber-950/40 text-amber-200";
  return "border-emerald-800 bg-emerald-950/40 text-emerald-200";
}
function tipoRotulo(tipo: Remessa["tipo"]) {
  return tipo === "INDUSTRIALIZACAO" ? "Industrialização" : tipo === "CONSERTO" ? "Conserto" : "Outro";
}
/** CFOPs de retorno possiveis: 5902/5903 (industrializacao), 5916/5903 (conserto); 6xxx fora da UF do remetente. */
function cfopsRetorno(remessa: Remessa, ufEmpresa: string | null) {
  const base = remessa.tipo === "CONSERTO" ? ["5916", "5903"] : remessa.tipo === "INDUSTRIALIZACAO" ? ["5902", "5903"] : ["5903"];
  const ufRemetente = (remessa.emitente_endereco?.uf ?? "").toUpperCase();
  const interestadual = Boolean(ufEmpresa) && Boolean(ufRemetente) && ufRemetente !== ufEmpresa;
  return base.map((c) => ({ cfop: interestadual ? `6${c.slice(1)}` : c, descricao: CFOP_DESCRICAO[c] ?? c }));
}

export default function RetornoTerceirosPanel({ empresaId }: { tenantId: string; empresaId: string }) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [busy, setBusy] = useState<string | null>(null);
  const [aviso, setAviso] = useState<{ texto: string; erro: boolean } | null>(null);
  const [resultados, setResultados] = useState<ResultadoArquivo[]>([]);
  const [remessas, setRemessas] = useState<Remessa[]>([]);
  const [itens, setItens] = useState<Item[]>([]);
  const [emissoes, setEmissoes] = useState<Emissao[]>([]);
  const [operacoes, setOperacoes] = useState<Operacao[]>([]);
  const [filtroStatus, setFiltroStatus] = useState<"ABERTA" | "RETORNADA" | "CANCELADA" | "TODAS">("ABERTA");
  const [empresa, setEmpresa] = useState<{ uf: string | null; cnpj: string | null }>({ uf: null, cnpj: null });
  const [producaoLigada, setProducaoLigada] = useState(false);
  const [perfisLiberados, setPerfisLiberados] = useState<string[]>([]);
  const [papel, setPapel] = useState<string | null>(null);
  // Teste de homologacao: importa a remessa em linha propria (is_teste), mesmo com a chave ja usada;
  // so homologa (producao bloqueada no banco), nao conta prazo e fica na secao "Testes".
  const [teste, setTeste] = useState(false);

  // Modal "Gerar NF-e de retorno"
  const [modal, setModal] = useState<Remessa | null>(null);
  const [cfop, setCfop] = useState("");
  const [modalidade, setModalidade] = useState(MODALIDADE_FRETE_PADRAO);
  const [observacao, setObservacao] = useState("");
  const [qVol, setQVol] = useState("");
  const [especie, setEspecie] = useState("");

  const avisar = useCallback((texto: string, erro = false) => setAviso(texto ? { texto, erro } : null), []);

  const carregar = useCallback(async () => {
    const { data, error } = await supabase.schema("f").from("remessas_terceiros")
      .select("id,chave,numero,serie,emitente_cnpj,emitente_nome,emitente_ie,emitente_endereco,cfop_origem,nat_op,dh_emi,data_entrada,prazo_retorno,tipo,valor_total,status,transporte_origem,solicitacao_retorno_id,nfe_homologacao_id,homologada_em,nfe_retorno_id,cfop_retorno,retornada_em,obs,is_teste")
      .order("dh_emi", { ascending: true }).limit(200);
    if (error) throw error;
    const lista = (data ?? []) as Remessa[];
    setRemessas(lista);
    const ids = lista.map((r) => r.id);
    const sols = lista.map((r) => r.solicitacao_retorno_id).filter((id): id is string => Boolean(id));
    const [it, em, ops, cfg, perfis] = await Promise.all([
      ids.length ? supabase.schema("f").from("remessas_terceiros_itens").select("id,remessa_id,n_item,c_prod,x_prod,ncm,cfop_origem,u_com,q_com,v_un_com,v_prod,orig").in("remessa_id", ids).order("n_item") : Promise.resolve({ data: [], error: null }),
      sols.length ? supabase.schema("f").from("documento_fiscal_emissao").select("documento_fiscal_id,solicitacao_id,ambiente,status,chave_acesso,numero,serie,codigo_status,mensagem,xml_path,danfe_path,autorizado_em,updated_at").in("solicitacao_id", sols).order("updated_at", { ascending: false }) : Promise.resolve({ data: [], error: null }),
      sols.length ? supabase.schema("f").from("operacao_fiscal").select("id,solicitacao_id,status,dados_json").eq("tipo", "RETORNO").in("solicitacao_id", sols).is("deleted_at", null) : Promise.resolve({ data: [], error: null }),
      supabase.schema("f").from("retorno_terceiros_config").select("producao_ligada").eq("empresa_id", empresaId).maybeSingle(),
      // Perfil liberado PARA ESTA solicitacao: o link "Liberar perfil" some da linha. Liberado
      // para outra homologacao (retorno gerado de novo), o link volta.
      supabase.schema("f").from("perfil_operacao").select("codigo,habilitado_producao,producao_homologacao_solicitacao_id").eq("modelo", "NFE").like("natureza_operacao", "RETORNO_REMESSA_TERCEIROS%"),
    ]);
    if (it.error) throw it.error;
    if (em.error) throw em.error;
    if (ops.error) throw ops.error;
    if (cfg.error) throw cfg.error;
    if (perfis.error) throw perfis.error;
    setItens((it.data ?? []) as Item[]);
    setEmissoes((em.data ?? []) as Emissao[]);
    setOperacoes((ops.data ?? []) as Operacao[]);
    setProducaoLigada(Boolean((cfg.data as { producao_ligada?: boolean } | null)?.producao_ligada));
    setPerfisLiberados(((perfis.data ?? []) as Array<{ codigo: string; habilitado_producao: boolean; producao_homologacao_solicitacao_id: string | null }>)
      .filter((p) => p.habilitado_producao && p.producao_homologacao_solicitacao_id)
      .map((p) => `${p.codigo}|${p.producao_homologacao_solicitacao_id}`));
  }, [empresaId, supabase]);

  useEffect(() => { void carregar().catch((e) => avisar(textoErro(e), true)); }, [carregar, avisar]);
  useEffect(() => {
    void (async () => {
      const [emp, pap] = await Promise.all([
        supabase.from("empresas").select("uf,cnpj").eq("id", empresaId).maybeSingle(),
        supabase.rpc("app_meu_papel_empresa"),
      ]);
      const e = emp.data as { uf?: string | null; cnpj?: string | null } | null;
      setEmpresa({ uf: e?.uf ? String(e.uf).toUpperCase() : null, cnpj: e?.cnpj ? String(e.cnpj).replace(/\D/g, "") : null });
      if (!pap.error && typeof pap.data === "string") setPapel(pap.data.toUpperCase());
    })().catch(() => {});
  }, [empresaId, supabase]);
  // Retorno da SEFAZ chega pelo callback: atualiza sozinho, como nos outros paineis.
  useEffect(() => {
    const canal = supabase.channel(`retorno-terceiros-${empresaId}`)
      .on("postgres_changes", { event: "*", schema: "f", table: "documento_fiscal_emissao", filter: `empresa_id=eq.${empresaId}` }, () => void carregar().catch(() => {}))
      .on("postgres_changes", { event: "*", schema: "f", table: "remessas_terceiros", filter: `empresa_id=eq.${empresaId}` }, () => void carregar().catch(() => {}))
      .subscribe();
    return () => { void supabase.removeChannel(canal); };
  }, [carregar, empresaId, supabase]);
  useEffect(() => {
    if (!emissoes.some((e) => ["ENVIANDO", "PROCESSANDO"].includes(e.status))) return;
    const timer = window.setInterval(() => void carregar().catch(() => {}), 5000);
    return () => window.clearInterval(timer);
  }, [carregar, emissoes]);

  // ---------------------------------------------------------------- 1 · importar
  async function importarArquivos(lista: FileList | null) {
    if (!lista || lista.length === 0) return;
    setBusy("importar");
    avisar("");
    const saida: ResultadoArquivo[] = [];
    for (const arquivo of Array.from(lista)) {
      try {
        const xml = await arquivo.text();
        // Previa no navegador so para o texto do resultado; quem valida e grava e o banco.
        let previa = "";
        try {
          const { nfe, itens: its } = parseNfeXml(xml);
          const cfops = Array.from(new Set(its.map((i) => (i.cfop ?? "").trim()).filter(Boolean)));
          previa = `${nfe.emitente ?? "?"} · NF-e ${nfe.numero ?? "?"}/${nfe.serie ?? "?"} · CFOP ${cfops.join(", ") || "?"}`;
          if (cfops.length > 0 && !cfops.every((c) => CFOPS_ORIGEM.includes(c))) {
            saida.push({ nome: arquivo.name, ok: false, texto: `${previa} — não é remessa de terceiros (só 5901/6901 e 5915/6915).` });
            continue;
          }
          if (empresa.cnpj && (nfe.documentoDestinatario ?? "").replace(/\D/g, "") !== empresa.cnpj) {
            saida.push({ nome: arquivo.name, ok: false, texto: `${previa} — o destinatário (${cnpjFormatado(nfe.documentoDestinatario)}) não é a empresa ativa.` });
            continue;
          }
        } catch (e) {
          saida.push({ nome: arquivo.name, ok: false, texto: textoErro(e) });
          continue;
        }
        const { data, error } = await supabase.schema("f").rpc("fn_remessa_terceiros_importar", { p_xml: xml, p_teste: teste });
        if (error) throw error;
        const r = data as { emitente?: string; numero?: string; serie?: string; tipo?: string; itens?: number; valor_total?: number; prazo_retorno?: string; teste?: boolean };
        saida.push({ nome: arquivo.name, ok: true, texto: `${r.teste ? "TESTE DE HOMOLOGAÇÃO · " : ""}${r.emitente} · NF-e ${r.numero}/${r.serie} · ${tipoRotulo((r.tipo ?? "OUTRO") as Remessa["tipo"])} · ${r.itens} item(ns) · R$ ${formatMoneyBR(numero(r.valor_total))} · retorno até ${dataBR(r.prazo_retorno)}` });
      } catch (e) {
        saida.push({ nome: arquivo.name, ok: false, texto: textoErro(e) });
      }
    }
    setResultados(saida);
    setBusy(null);
    await carregar().catch((e) => avisar(textoErro(e), true));
  }

  // ---------------------------------------------------------------- 3 · gerar retorno
  function abrirModal(r: Remessa) {
    const opcoes = cfopsRetorno(r, empresa.uf);
    setModal(r);
    setCfop(opcoes[0]?.cfop ?? "");
    setModalidade(MODALIDADE_FRETE_PADRAO);
    setObservacao(r.obs ?? "");
    setQVol("");
    setEspecie("");
  }

  async function gerarEHomologar() {
    if (!modal) return;
    setBusy("gerar");
    avisar("");
    try {
      const volumesOrigem = modal.transporte_origem?.volumes ?? [];
      const volumesTela = modalidade !== "9" && volumesOrigem.length === 0 && numero(qVol) > 0
        ? [{ quantidade: Math.round(numero(qVol)), especie: especie.trim() || null, peso_liquido: 0, peso_bruto: 0 }]
        : null;
      const { data, error } = await supabase.schema("f").rpc("fn_remessa_terceiros_retorno_criar", {
        p_remessa_id: modal.id,
        p_cfop: cfop,
        p_modalidade_frete: Number(modalidade),
        p_observacao: observacao.trim() || null,
        p_volumes: volumesTela,
      });
      if (error) throw error;
      const r = data as { solicitacao_id: string; cfop: string; valor_total: number };
      setModal(null);
      const { data: env, error: erroEnv } = await supabase.functions.invoke("nfe-emitir", { body: { solicitacao_id: r.solicitacao_id } });
      if (erroEnv) throw erroEnv;
      if (env?.erro) throw new Error(env.codigo ? `cStat ${env.codigo} · ${env.erro}` : String(env.erro));
      avisar(`Retorno CFOP ${r.cfop} (R$ ${formatMoneyBR(numero(r.valor_total))}) enviado à Focus em homologação. O retorno da SEFAZ chega automaticamente.`);
    } catch (e) {
      avisar(await erroFunction(e), true);
    } finally {
      setBusy(null);
      await carregar().catch(() => {});
    }
  }

  async function emitirHomologacao(r: Remessa) {
    if (!r.solicitacao_retorno_id) return;
    setBusy(r.id); avisar("");
    try {
      const { data, error } = await supabase.functions.invoke("nfe-emitir", { body: { solicitacao_id: r.solicitacao_retorno_id } });
      if (error) throw error;
      if (data?.erro) throw new Error(data.codigo ? `cStat ${data.codigo} · ${data.erro}` : String(data.erro));
      avisar("Retorno enviado à Focus em homologação. O retorno da SEFAZ chega automaticamente.");
    } catch (e) { avisar(await erroFunction(e), true); } finally { setBusy(null); await carregar().catch(() => {}); }
  }

  async function emitirProducao(r: Remessa) {
    if (!r.solicitacao_retorno_id) return;
    setBusy(r.id); avisar("");
    try {
      const { data: st, error: erroSt } = await supabase.functions.invoke("nfe-emitir-producao", { body: { acao: "STATUS", solicitacao_id: r.solicitacao_retorno_id } });
      if (erroSt) throw erroSt;
      const status = st as ProducaoStatus | null;
      const resumo = status?.resumo_confirmacao;
      if (!status?.pronta || !status.preflight_confirmacao_pronto || !resumo?.contexto_hash) {
        throw new Error(status?.motivo ?? "A produção ainda não está liberada para este retorno.");
      }
      const ok = window.confirm(
        `EMITIR NF-e REAL DE RETORNO DE MERCADORIA DE TERCEIROS (produção)\n\nDestinatário: ${resumo.nome_destinatario ?? "?"} (${resumo.documento_destinatario_mascarado ?? "?"})\n`
        + `Origem: NF-e ${r.numero}/${r.serie} de ${dataBR(r.dh_emi)} · CFOP de retorno ${r.cfop_retorno}\n`
        + `Valor da mercadoria: R$ ${formatMoneyBR(numero(resumo.valor_total))} · sem ICMS, IPI, PIS e COFINS · sem cobrança\n\nQuando autorizar, a remessa sai da lista (RETORNADA). Deseja continuar?`,
      );
      if (!ok) return;
      const { data, error } = await supabase.functions.invoke("nfe-emitir-producao", { body: { acao: "EMITIR", solicitacao_id: r.solicitacao_retorno_id, confirmacao_contexto_hash: resumo.contexto_hash } });
      if (error) throw error;
      if (data?.erro) throw new Error(data.codigo ? `cStat ${data.codigo} · ${data.erro}` : String(data.erro));
      avisar("NF-e de retorno enviada à SEFAZ em PRODUÇÃO.");
    } catch (e) { avisar(await erroFunction(e), true); } finally { setBusy(null); await carregar().catch(() => {}); }
  }

  async function excluirTeste(r: Remessa) {
    if (!window.confirm(`Excluir o teste de homologação da NF-e ${r.numero}/${r.serie} (${r.emitente_nome})? A solicitação e a homologação do teste são canceladas; a remessa real de mesma chave não muda.`)) return;
    setBusy(r.id); avisar("");
    try {
      const { error } = await supabase.schema("f").rpc("fn_remessa_terceiros_teste_excluir", { p_remessa_id: r.id });
      if (error) throw error;
      avisar("Teste de homologação excluído.");
    } catch (e) { avisar(textoErro(e), true); } finally { setBusy(null); await carregar().catch(() => {}); }
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

  async function ligarProducao(ligar: boolean) {
    const ok = ligar
      ? window.confirm("Ligar a emissão em PRODUÇÃO dos retornos de terceiros? As notas passam a ter valor fiscal.")
      : true;
    if (!ok) return;
    setBusy("producao"); avisar("");
    try {
      const { error } = await supabase.schema("f").rpc("fn_retorno_terceiros_producao_ligar", { p_ligar: ligar });
      if (error) throw error;
      avisar(ligar ? "Produção do retorno de terceiros LIGADA." : "Produção do retorno de terceiros desligada.");
    } catch (e) { avisar(textoErro(e), true); } finally { setBusy(null); await carregar().catch(() => {}); }
  }

  const listadas = remessas.filter((r) => !r.is_teste && (filtroStatus === "TODAS" || r.status === filtroStatus));
  const testes = remessas.filter((r) => r.is_teste);
  const itensDe = (id: string) => itens.filter((i) => i.remessa_id === id);
  const volumesOrigemModal = modal?.transporte_origem?.volumes ?? [];

  function linhaRemessa(r: Remessa) {
                const dias = diasDesde(r.dh_emi);
                const hom = emissoes.find((e) => e.solicitacao_id === r.solicitacao_retorno_id && e.ambiente === "HOMOLOGACAO");
                const prod = emissoes.find((e) => e.solicitacao_id === r.solicitacao_retorno_id && e.ambiente === "PRODUCAO");
                const op = operacoes.find((o) => o.solicitacao_id === r.solicitacao_retorno_id);
                const ocupado = busy === r.id;
                const aberta = r.status === "ABERTA";
                const homAutorizada = hom?.status === "AUTORIZADA";
                const podeHomologar = aberta && Boolean(r.solicitacao_retorno_id) && !prod && (!hom || ["RASCUNHO", "REJEITADA", "ERRO"].includes(hom.status));
                const podeProduzir = aberta && !r.is_teste && producaoLigada && homAutorizada && (!prod || ["RASCUNHO", "REJEITADA", "ERRO"].includes(prod.status));
                const perfilCodigo = op?.dados_json?.perfil_codigo ?? null;
                const linkPerfil = perfilCodigo && r.solicitacao_retorno_id && !perfisLiberados.includes(`${perfilCodigo}|${r.solicitacao_retorno_id}`)
                  ? `/faturamento/perfis?perfil=${encodeURIComponent(perfilCodigo)}&solicitacao=${r.solicitacao_retorno_id}&retorno=/faturamento/operacoes?aba=RETORNO`
                  : null;
                return (
                  <tr key={r.id} className="align-top">
                    <td className="py-2 pr-2 font-mono text-xs" title={r.chave}>{r.chave.slice(0, 8)}…{r.chave.slice(-6)}</td>
                    <td className="py-2 pr-2"><div>{r.emitente_nome}</div><div className="text-xs text-zinc-500">{cnpjFormatado(r.emitente_cnpj)}<br />{r.emitente_endereco?.cidade ?? "?"}/{r.emitente_endereco?.uf ?? "?"}</div></td>
                    <td className="py-2 pr-2 whitespace-nowrap">{r.numero}/{r.serie}</td>
                    <td className="py-2 pr-2 whitespace-nowrap">{dataBR(r.dh_emi)}</td>
                    <td className="py-2 pr-2 tabular-nums">{dias}</td>
                    <td className="py-2 pr-2"><span className={`inline-block whitespace-nowrap rounded-full border px-2 py-0.5 text-xs ${corPrazo(dias)}`}>{dataBR(r.prazo_retorno)}{dias > 180 ? " · vencido" : ""}</span></td>
                    <td className="py-2 pr-2 text-right tabular-nums whitespace-nowrap">R$ {formatMoneyBR(numero(r.valor_total))}</td>
                    <td className="py-2 pr-2">{r.cfop_origem}<div className="text-xs text-zinc-500">{tipoRotulo(r.tipo)}</div></td>
                    <td className="py-2 pr-2">
                      <div>{r.status === "ABERTA" ? "Aberta" : r.status === "RETORNADA" ? "Retornada" : "Cancelada"}</div>
                      {r.is_teste ? <span className="mt-1 inline-block rounded-full border border-violet-800 px-2 py-0.5 text-xs text-violet-300">TESTE de homologação</span> : null}
                      {r.homologada_em ? <span className="mt-1 inline-block rounded-full border border-sky-800 px-2 py-0.5 text-xs text-sky-300">homologada em {dataBR(r.homologada_em)}</span> : null}
                      {r.retornada_em ? <div className="text-xs text-zinc-500">retorno {r.cfop_retorno} em {dataBR(r.retornada_em)}</div> : null}
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
                            <Link href={`/faturamento/nfe/${e.documento_fiscal_id}?retorno=/faturamento/operacoes?aba=RETORNO`} className="underline">Ciclo de vida</Link>
                          </> : null}
                        </div>
                      ))}
                      {!hom && !prod ? <span className="text-zinc-500">—</span> : null}
                    </td>
                    <td className="py-2 text-right">
                      <div className="flex flex-col items-end gap-1">
                        {aberta ? <button type="button" className={primario} disabled={ocupado || busy === "gerar"} onClick={() => abrirModal(r)}>Gerar retorno</button> : null}
                        {podeHomologar ? <button type="button" className={button} disabled={ocupado} onClick={() => void emitirHomologacao(r)}>{hom ? "Tentar homologação de novo" : "Emitir em homologação"}</button> : null}
                        {aberta && homAutorizada && linkPerfil && (!producaoLigada || r.is_teste) ? <Link href={linkPerfil} className={button}>Liberar perfil</Link> : null}
                        {aberta && homAutorizada && linkPerfil && producaoLigada && !r.is_teste ? <Link href={linkPerfil} className={button}>Liberar perfil para produção</Link> : null}
                        {r.is_teste ? <button type="button" className="text-xs text-red-300 underline" disabled={ocupado} onClick={() => void excluirTeste(r)}>Excluir teste</button> : null}
                        {podeProduzir ? <button type="button" className="rounded-md bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50" disabled={ocupado} onClick={() => void emitirProducao(r)}>Emitir NF-e real (produção)</button> : null}
                      </div>
                    </td>
                  </tr>
                );
  }

  return (
    <div className="space-y-5">
      <div>
        <h2 className="font-semibold">Retorno de mercadoria de terceiros</h2>
        <p className="mt-1 text-sm text-zinc-400">
          Notas de remessa para industrialização por encomenda (5901/6901) ou conserto (5915/6915) recebidas de terceiros. A mercadoria é do remetente:
          não entra no estoque nem gera cobrança. Quando voltar, a NF-e de retorno (5902/5903, 5916) espelha a nota recebida e referencia a chave dela.
        </p>
      </div>
      {aviso ? <div role={aviso.erro ? "alert" : "status"} className={`rounded border p-3 text-sm ${aviso.erro ? "border-red-900 bg-red-950/30 text-red-200" : "border-sky-800 bg-sky-950/30 text-sky-200"}`}>{aviso.texto}</div> : null}

      <section className="space-y-3 rounded-lg border border-zinc-800 p-4">
        <h3 className="font-medium">1 · Importar remessa recebida (XML)</h3>
        <p className="text-sm text-zinc-400">XML autorizado (nfeProc) com a SEGAU como destinatária e todos os itens em 5901/6901/5915/6915. Pode enviar vários de uma vez.</p>
        <input aria-label="Arquivos XML" type="file" accept=".xml,text/xml,application/xml" multiple disabled={busy === "importar"} className="block text-sm text-zinc-300 file:mr-3 file:rounded file:border file:border-zinc-600 file:bg-zinc-900 file:px-3 file:py-2 file:text-sm file:text-zinc-100 hover:file:bg-zinc-800" onChange={(e) => { void importarArquivos(e.target.files); e.target.value = ""; }} />
        <label className="flex items-center gap-2 text-sm text-zinc-300"><input aria-label="Teste de homologação" type="checkbox" checked={teste} onChange={(e) => setTeste(e.target.checked)} /> Teste de homologação: aceita XML de chave já importada, grava em linha própria (não entra na lista nem no prazo) e só emite em homologação</label>
        {busy === "importar" ? <p className="text-sm text-zinc-400">Importando...</p> : null}
        {resultados.length > 0 ? (
          <ul className="divide-y divide-zinc-800 rounded border border-zinc-800 text-sm">
            {resultados.map((r, i) => (
              <li key={`${r.nome}-${i}`} className="flex flex-wrap items-start gap-2 px-3 py-2">
                <span className={`rounded-full border px-2 py-0.5 text-xs ${r.ok ? "border-emerald-800 text-emerald-300" : "border-red-900 text-red-300"}`}>{r.ok ? "importado" : "recusado"}</span>
                <span className="font-mono text-xs text-zinc-500">{r.nome}</span>
                <span className={r.ok ? "" : "text-red-200"}>{r.texto}</span>
              </li>
            ))}
          </ul>
        ) : null}
      </section>

      <section className="space-y-3 rounded-lg border border-zinc-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="font-medium">2 · Mercadorias de terceiros em nosso poder</h3>
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <label className={label}>Status<select aria-label="Filtrar por status" className={`${field} w-full`} value={filtroStatus} onChange={(e) => setFiltroStatus(e.target.value as typeof filtroStatus)}><option value="ABERTA">Abertas</option><option value="RETORNADA">Retornadas</option><option value="CANCELADA">Canceladas</option><option value="TODAS">Todas</option></select></label>
            <span className={`rounded-full border px-3 py-1 text-xs ${producaoLigada ? "border-emerald-800 text-emerald-300" : "border-zinc-700 text-zinc-400"}`}>Produção {producaoLigada ? "ligada" : "desligada"}</span>
            {papel === "ADMIN" ? <button type="button" className={button} disabled={busy === "producao"} onClick={() => void ligarProducao(!producaoLigada)}>{producaoLigada ? "Desligar produção" : "Ligar produção"}</button> : null}
          </div>
        </div>
        {listadas.length === 0 ? <p className="text-sm text-zinc-500">Nenhuma remessa {filtroStatus === "TODAS" ? "" : filtroStatus.toLowerCase()} importada.</p> : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[960px] text-sm">
              <thead className="text-left text-xs uppercase text-zinc-500"><tr><th className="py-2 pr-3">Chave</th><th className="py-2 pr-3">Remetente</th><th className="py-2 pr-3">Nº/Série</th><th className="py-2 pr-3">Emissão</th><th className="py-2 pr-3">Dias</th><th className="py-2 pr-3">Prazo</th><th className="py-2 pr-3 text-right">Valor</th><th className="py-2 pr-3">CFOP</th><th className="py-2 pr-3">Status</th><th className="py-2 pr-3">NF-e de retorno</th><th className="py-2 text-right">Ações</th></tr></thead>
              <tbody className="divide-y divide-zinc-800">
                {listadas.map(linhaRemessa)}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="space-y-3 rounded-lg border border-violet-900 p-4">
        <h3 className="font-medium">Testes de homologação</h3>
        <p className="text-sm text-zinc-400">Remessas importadas com a caixa &quot;Teste de homologação&quot;: servem para homologar e liberar o perfil (por exemplo depois de uma mudança fiscal) sem tocar na remessa real de mesma chave. Não entram na lista acima, não contam prazo e não emitem em produção: o banco recusa a emissão real de um teste.</p>
        {testes.length === 0 ? <p className="text-sm text-zinc-500">Nenhum teste.</p> : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[960px] text-sm">
              <thead className="text-left text-xs uppercase text-zinc-500"><tr><th className="py-2 pr-3">Chave</th><th className="py-2 pr-3">Remetente</th><th className="py-2 pr-3">Nº/Série</th><th className="py-2 pr-3">Emissão</th><th className="py-2 pr-3">Dias</th><th className="py-2 pr-3">Prazo</th><th className="py-2 pr-3 text-right">Valor</th><th className="py-2 pr-3">CFOP</th><th className="py-2 pr-3">Status</th><th className="py-2 pr-3">NF-e de retorno</th><th className="py-2 text-right">Ações</th></tr></thead>
              <tbody className="divide-y divide-zinc-800">
                {testes.map(linhaRemessa)}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {modal ? (
        <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/70 p-4" role="dialog" aria-modal="true" aria-label="Gerar NF-e de retorno">
          <div className="my-6 w-full max-w-4xl space-y-4 rounded-lg border border-zinc-700 bg-zinc-950 p-5">
            <div className="flex items-start justify-between gap-2">
              <div>
                <h3 className="font-semibold">3 · Gerar NF-e de retorno</h3>
                <p className="text-sm text-zinc-400">Retorno integral da NF-e {modal.numero}/{modal.serie} de {dataBR(modal.dh_emi)} · chave <span className="font-mono text-xs">{modal.chave}</span></p>
              </div>
              <button type="button" className={button} onClick={() => setModal(null)}>Fechar</button>
            </div>

            <div className="rounded border border-zinc-800 bg-zinc-900/40 p-3 text-sm">
              <div className="text-xs uppercase text-zinc-500">Destinatário (remetente da origem, do XML)</div>
              <div className="font-medium">{modal.emitente_nome}</div>
              <div className="text-xs text-zinc-400">CNPJ {cnpjFormatado(modal.emitente_cnpj)} · IE {modal.emitente_ie ?? "não informada"}</div>
              <div className="text-xs text-zinc-400">{[modal.emitente_endereco?.logradouro, modal.emitente_endereco?.numero, modal.emitente_endereco?.complemento, modal.emitente_endereco?.bairro].filter(Boolean).join(", ")} · {modal.emitente_endereco?.cidade}/{modal.emitente_endereco?.uf} · CEP {modal.emitente_endereco?.cep}</div>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full min-w-[640px] text-sm">
                <thead className="text-left text-xs uppercase text-zinc-500"><tr><th className="py-1">#</th><th className="py-1">Código</th><th className="py-1">Descrição</th><th className="py-1">NCM</th><th className="py-1">Un.</th><th className="py-1 text-right">Qtd.</th><th className="py-1 text-right">Vl. unit.</th><th className="py-1 text-right">Total</th></tr></thead>
                <tbody className="divide-y divide-zinc-800">
                  {itensDe(modal.id).map((i) => (
                    <tr key={i.id}><td className="py-1 pr-2">{i.n_item}</td><td className="py-1 pr-2 font-mono text-xs">{i.c_prod}</td><td className="py-1 pr-2">{i.x_prod}</td><td className="py-1 pr-2">{i.ncm ?? "?"}</td><td className="py-1 pr-2">{i.u_com}</td><td className="py-1 pr-2 text-right tabular-nums">{numero(i.q_com).toLocaleString("pt-BR", { maximumFractionDigits: 4 })}</td><td className="py-1 pr-2 text-right tabular-nums">{numero(i.v_un_com).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 10 })}</td><td className="py-1 text-right tabular-nums">R$ {formatMoneyBR(numero(i.v_prod))}</td></tr>
                  ))}
                </tbody>
                <tfoot><tr><td colSpan={7} className="py-1 text-right text-xs uppercase text-zinc-500">Valor da nota (= vProd, sem impostos)</td><td className="py-1 text-right font-semibold tabular-nums">R$ {formatMoneyBR(numero(modal.valor_total))}</td></tr></tfoot>
              </table>
              <p className="mt-1 text-xs text-zinc-500">Itens espelham a origem: mesmo código, descrição, NCM, unidade, quantidade e valor. ICMS CST 50 (suspenso), IPI CST 55, PIS/COFINS 08, IBS/CBS 410 · sem cobrança (tPag 90).</p>
            </div>

            <div className="grid gap-3 md:grid-cols-2">
              <label className={label}>CFOP do retorno<select aria-label="CFOP do retorno" className={`${field} w-full`} value={cfop} onChange={(e) => setCfop(e.target.value)}>{cfopsRetorno(modal, empresa.uf).map((o) => <option key={o.cfop} value={o.cfop}>{o.cfop} · {o.descricao}</option>)}</select></label>
              <label className={label}>Modalidade do frete<select aria-label="Modalidade do frete do retorno" className={`${field} w-full`} value={modalidade} onChange={(e) => setModalidade(e.target.value)}>{MODALIDADES_FRETE.map(([c, r]) => <option key={c} value={c}>{r}</option>)}</select></label>
            </div>
            {modalidade !== "9" ? (
              volumesOrigemModal.length > 0 ? (
                <p className="text-sm text-zinc-400">Volumes copiados da origem: {volumesOrigemModal.map((v) => `${v.qVol ?? "?"} ${v.esp ?? ""} (${numero(v.pesoB ?? v.pesoL).toLocaleString("pt-BR", { minimumFractionDigits: 3 })} kg)`).join("; ")}</p>
              ) : (
                <div className="grid gap-3 md:grid-cols-2">
                  <label className={label}>Quantidade de volumes (opcional)<input aria-label="Quantidade de volumes" className={`${field} w-full`} inputMode="numeric" value={qVol} onChange={(e) => setQVol(e.target.value)} /></label>
                  <label className={label}>Espécie (opcional)<input aria-label="Espécie dos volumes" className={`${field} w-full`} value={especie} onChange={(e) => setEspecie(e.target.value)} maxLength={60} placeholder="Ex.: VOLUMES" /></label>
                </div>
              )
            ) : null}
            <label className={label}>Observação (vai nas informações complementares, depois do texto do retorno)<textarea aria-label="Observação do retorno" className={`${field} min-h-16 w-full`} value={observacao} onChange={(e) => setObservacao(e.target.value)} maxLength={500} /></label>
            <div className="flex flex-wrap justify-end gap-2">
              <button type="button" className={button} onClick={() => setModal(null)}>Cancelar</button>
              <button type="button" className={primario} disabled={busy === "gerar" || !cfop} onClick={() => void gerarEHomologar()}>{busy === "gerar" ? "Gerando..." : "Emitir em homologação"}</button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
