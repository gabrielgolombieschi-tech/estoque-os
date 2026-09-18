"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { formatMoneyBR } from "@/lib/decimal";
import {
  bloqueiosDaDir,
  calcularImportacao,
  CFOPS_IMPORTACAO,
  custoImportacao,
  DirInvalida,
  formatarBrl,
  lerDirRemessa,
  PAIS_SISCOMEX_PARA_BACEN,
  PAISES_BACEN,
  round2,
  UNIDADES_RFB,
  VIAS_TRANSPORTE,
  type DirRemessa,
} from "@/lib/importacao/dir-remessa";
import { supabaseBrowser } from "@/lib/supabase/client";
import { aplicarBuscaItem } from "@/lib/itens/busca";
import { FORMAS_PAGAMENTO_AP, textoOpcao } from "@/lib/fiscal/rotulos";

/**
 * Importacao por remessa expressa (courier): NF-e de ENTRADA emitida pela Segau para a
 * mercadoria desembaracada pela DIR do Siscomex Remessa.
 *
 * Passo 1: XML da DIR (raiz xml1702). Passo 2: exportador, itens (NCM, item do catalogo,
 * fabricante), CFOP, aliquota do ICMS, GNRE, despesas e nota de debito do courier, anexos.
 * Passo 3: a conta (vProd = valor aduaneiro; II da DIR; BC ICMS = (vProd + II) / (1 - aliquota);
 * ICMS = BC x aliquota conferido com a GNRE; vOutro = ICMS; vNF = vProd + II + vOutro).
 * Passo 4: previa de todos os campos da nota e o botao de emitir em homologacao.
 * Passo 5: importacoes (homologacao, liberacao do perfil, producao, DANFE/XML, anexos, estoque, AP).
 *
 * Quem grava e o banco (f.fn_importacao_remessa_criar), que le a DIR de novo e repete a conta;
 * nfe-emitir manda para a Focus em homologacao; a liberacao do perfil e pela tela de perfis e
 * nfe-emitir-producao emite a nota real, que da entrada no estoque e lanca a nota de debito.
 */

type Conta = { id: string; nome: string };
type Motivo = { id: string; codigo: string; nome: string; favorito: boolean };
type ItemCatalogo = { id: number; codigo_interno: string | null; nome: string; unidade_medida: string | null; ncm: string | null; fabricante: string | null };
type ItemForm = { sequencia: string; descricao_dir: string; valor_usd: number; quantidade: string; item_id: number | null; codigo: string; descricao: string; unidade: string; ncm: string; fabricante: string; busca: string; sugestoes: ItemCatalogo[] };
type Importacao = {
  id: string; status: string; awb: string; dir_numero: string; dir_data_registro: string; cfop: string; natureza_operacao: string;
  valor_aduaneiro_brl: number | string; ii_valor: number | string; bc_icms: number | string; icms_valor: number | string; valor_nota: number | string;
  gnre_valor: number | string; exportador_nome: string; courier_nome: string | null; nota_debito_numero: string | null; nota_debito_valor: number | string | null;
  solicitacao_id: string | null; chave_nfe: string | null; nfe_numero: number | null; nfe_serie: number | null; created_at: string; credito_icms: boolean; teste: boolean;
  dados_json: {
    perfil_codigo?: string | null; uso_proprio?: string | null;
    estoque_movimentacoes?: Array<{ item_id: number; quantidade: number; custo_unitario: number }>; estoque_pendencias?: Array<{ codigo?: string; motivo?: string }>;
    ap?: {
      titulo_id?: string | null; pagamento_id?: string | null; erro?: string | null; criado?: boolean; titulo_status?: string | null;
      reembolso?: { titulo_id?: string; fornecedor_id?: number; valor?: number | string; status?: string } | null;
    };
    icms_credito?: { valor?: number | string; status?: string; motivo?: string } | null;
    fiscal_itens?: Array<{ item_id: number; erro?: string; depois?: { equiparado_industrial?: boolean } }>;
    cancelamento?: { motivo?: string };
  } | null;
};
type ImportacaoItem = { importacao_id: string; ordem: number; codigo: string; descricao: string; ncm: string; quantidade: number | string; unidade: string; valor_aduaneiro_brl: number | string; ii_valor: number | string; icms_valor: number | string; custo_unitario: number | string | null };
type Anexo = { id: string; importacao_id: string; tipo: string; nome_arquivo: string; created_at: string };
type Emissao = {
  documento_fiscal_id: string; solicitacao_id: string; ambiente: "HOMOLOGACAO" | "PRODUCAO"; status: string; chave_acesso: string | null; numero: number | null; serie: number | null;
  codigo_status: number | null; mensagem: string | null; xml_path: string | null; danfe_path: string | null; autorizado_em: string | null; updated_at: string;
};
type ProducaoStatus = {
  pronta?: boolean; motivo?: string | null; preflight_confirmacao_pronto?: boolean;
  resumo_confirmacao?: { nome_destinatario?: string; valor_total?: number | string; contexto_hash?: string } | null;
};
type LeituraBanco = { bloqueios: string[]; em_uso: { importacao_id: string; status: string; nfe_numero?: number | null; nfe_serie?: number | null } | null; dir: { local_desembaraco?: string | null; uf_desembaraco?: string | null } };

const field = "rounded border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500";
const label = "space-y-1 text-xs text-zinc-400";
const button = "rounded border border-zinc-600 bg-zinc-900 px-3 py-2 text-sm hover:bg-zinc-800 disabled:cursor-not-allowed disabled:opacity-40";
const primario = "rounded-md bg-sky-600 px-3 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50";
// Formas de pagamento do contas a pagar: lib/fiscal/rotulos.ts (FORMAS_PAGAMENTO_AP).
const TIPOS_ANEXO: Array<[string, string]> = [["GNRE", "GNRE"], ["NOTA_DEBITO", "Nota de débito"], ["INVOICE", "Invoice"], ["OUTRO", "Outro"]];

/** Valor vindo do banco ou da Edge: numero, ou texto com ponto decimal ("844.28"); "844,28" tambem entra. */
function numero(valor: unknown) {
  if (typeof valor === "number") return Number.isFinite(valor) ? valor : 0;
  const s = String(valor ?? "").trim();
  const n = Number(s.includes(",") ? s.replace(/\./g, "").replace(",", ".") : s);
  return Number.isFinite(n) ? n : 0;
}
function numeroDecimal(valor: unknown) {
  // Campo digitado: aceita "143,53" e "143.53".
  const s = String(valor ?? "").trim();
  if (!s) return 0;
  const n = Number(s.includes(",") ? s.replace(/\./g, "").replace(",", ".") : s);
  return Number.isFinite(n) ? n : 0;
}
function qtd(valor: unknown, casas = 4) {
  return Number(valor ?? 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: casas });
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
      if (corpo?.error) return String(corpo.error);
    } catch { /* corpo nao e JSON */ }
  }
  return textoErro(cause);
}
function dataBR(valor: string | null | undefined) {
  if (!valor) return "—";
  const d = valor.length === 10 ? new Date(`${valor}T00:00:00`) : new Date(valor);
  return Number.isNaN(d.getTime()) ? valor : d.toLocaleDateString("pt-BR");
}
function dataHoraBR(valor: string | null | undefined) {
  if (!valor) return "—";
  const d = new Date(valor);
  return Number.isNaN(d.getTime()) ? valor : d.toLocaleString("pt-BR");
}
function statusRotulo(status: string) {
  if (status === "RASCUNHO") return "Rascunho";
  if (status === "HOMOLOGACAO") return "Em homologação";
  if (status === "HOMOLOGADA") return "Homologada";
  if (status === "CONCLUIDA") return "Concluída (NF-e real)";
  if (status === "CANCELADA") return "Cancelada";
  return status;
}
function cnpjFormatado(valor: string | null | undefined) {
  const d = String(valor ?? "").replace(/\D/g, "");
  return d.length === 14 ? d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5") : (valor ?? "");
}
/** Mesma regra de f.fn_importacao_remessa_uso_proprio: indicio de uso proprio na observacao ou no motivo de compra. */
function indicioUsoProprio(observacao: string, motivoCodigo: string | null, motivoNome: string | null): string | null {
  const obs = observacao.normalize("NFD").replace(/[̀-ͯ]/g, "");
  const reObs = /(uso|consumo)\s+(propri[oa]|intern[oa])|uso\s+e\s+consumo|ativo\s+imobilizado|imobilizado|bancada(?!\s+(do|da|de|para\s+[oa])\s+cliente)|manutencao\s+(propria|interna|da\s+(fabrica|empresa|sede))|almoxarifado\s+intern|ferramental\s+(propri|intern)|para\s+(a\s+)?(nossa|nosso|nos|a\s+segau)\b|escritorio|laboratorio|\bsede\b/i;
  if (obs.trim() && reObs.test(obs)) return `observação: "${observacao.trim().slice(0, 80)}"`;
  const codigo = (motivoCodigo ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "");
  const nome = (motivoNome ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "");
  if (/^(CONSUMO|MANUTENCAO|INVESTIMENTO|OPEX)/i.test(codigo) || /CONSUMO|USO\s+(E|OU)\s+CONSUMO|IMOBILIZADO|INVESTIMENTO|MANUTEN/i.test(nome)) return `motivo de compra: ${motivoNome ?? motivoCodigo}`;
  return null;
}

export default function ImportacaoRemessaPanel({ tenantId, empresaId }: { tenantId: string; empresaId: string }) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [busy, setBusy] = useState<string | null>(null);
  const [aviso, setAviso] = useState<{ texto: string; erro: boolean } | null>(null);
  const [empresa, setEmpresa] = useState<{ cnpj: string; razao_social: string; uf: string } | null>(null);
  const [contas, setContas] = useState<Conta[]>([]);
  const [motivos, setMotivos] = useState<Motivo[]>([]);

  // 1 · DIR
  const [nomeArquivoDir, setNomeArquivoDir] = useState("");
  const [xmlDir, setXmlDir] = useState("");
  const [dir, setDir] = useState<DirRemessa | null>(null);
  const [leitura, setLeitura] = useState<LeituraBanco | null>(null);
  const [bloqueiosTela, setBloqueiosTela] = useState<string[]>([]);

  // 2 · dados
  const [exp, setExp] = useState({ nome: "", logradouro: "", numero: "", complemento: "", bairro: "", pais_codigo: "1600", pais_nome: "CHINA", codigo: "", id_estrangeiro: "" });
  const [itens, setItens] = useState<ItemForm[]>([]);
  const [cfop, setCfop] = useState("3101");
  const [aliquota, setAliquota] = useState("17");
  const [gnre, setGnre] = useState({ numero: "", receita: "10005-6", uf: "SC", valor: "" });
  const [courier, setCourier] = useState({ servicos: "", armazenagem: "" });
  const [nd, setNd] = useState({ numero: "", valor: "", emissao: "", pago_em: "", conta_bancaria_id: "", forma_pagamento: "BOLETO", motivo_compra_id: "" });
  const [desemb, setDesemb] = useState({ local: "", uf: "", data: "" });
  const [via, setVia] = useState("11");
  const [intermedio, setIntermedio] = useState("1");
  const [observacao, setObservacao] = useState("");
  const [anexosNovos, setAnexosNovos] = useState<Array<{ tipo: string; file: File }>>([]);
  const [anexoTipo, setAnexoTipo] = useState("GNRE");
  const [substituir, setSubstituir] = useState(false);
  // Teste de homologacao: convive com a DIR ja usada, nunca vai para producao (coluna f.importacao_remessa.teste).
  const [teste, setTeste] = useState(false);

  // 5 · importacoes
  const [importacoes, setImportacoes] = useState<Importacao[]>([]);
  const [impItens, setImpItens] = useState<ImportacaoItem[]>([]);
  const [anexos, setAnexos] = useState<Anexo[]>([]);
  const [emissoes, setEmissoes] = useState<Emissao[]>([]);
  const [perfisLiberados, setPerfisLiberados] = useState<string[]>([]);
  const [filtro, setFiltro] = useState<"ATIVAS" | "TODAS">("ATIVAS");
  const [anexoLista, setAnexoLista] = useState<Record<string, string>>({});

  const avisar = useCallback((texto: string, erro = false) => setAviso(texto ? { texto, erro } : null), []);

  const carregar = useCallback(async () => {
    const { data, error } = await supabase.schema("f").from("importacao_remessa")
      .select("id,status,awb,dir_numero,dir_data_registro,cfop,natureza_operacao,valor_aduaneiro_brl,ii_valor,bc_icms,icms_valor,valor_nota,gnre_valor,exportador_nome,courier_nome,nota_debito_numero,nota_debito_valor,solicitacao_id,chave_nfe,nfe_numero,nfe_serie,created_at,credito_icms,teste,dados_json")
      .eq("empresa_id", empresaId).is("deleted_at", null).order("created_at", { ascending: false }).limit(100);
    if (error) throw error;
    const lista = (data ?? []) as Importacao[];
    setImportacoes(lista);
    const ids = lista.map((i) => i.id);
    const sols = lista.map((i) => i.solicitacao_id).filter((id): id is string => Boolean(id));
    const [it, an, em, perfis] = await Promise.all([
      ids.length ? supabase.schema("f").from("importacao_remessa_item").select("importacao_id,ordem,codigo,descricao,ncm,quantidade,unidade,valor_aduaneiro_brl,ii_valor,icms_valor,custo_unitario").in("importacao_id", ids).order("ordem") : Promise.resolve({ data: [], error: null }),
      ids.length ? supabase.schema("f").from("importacao_remessa_anexo").select("id,importacao_id,tipo,nome_arquivo,created_at").in("importacao_id", ids).is("deleted_at", null).order("created_at") : Promise.resolve({ data: [], error: null }),
      sols.length ? supabase.schema("f").from("documento_fiscal_emissao").select("documento_fiscal_id,solicitacao_id,ambiente,status,chave_acesso,numero,serie,codigo_status,mensagem,xml_path,danfe_path,autorizado_em,updated_at").in("solicitacao_id", sols).order("updated_at", { ascending: false }) : Promise.resolve({ data: [], error: null }),
      supabase.schema("f").from("perfil_operacao").select("codigo,habilitado_producao,producao_homologacao_solicitacao_id").eq("modelo", "NFE").like("natureza_operacao", "IMPORTACAO_%"),
    ]);
    if (it.error) throw it.error;
    if (an.error) throw an.error;
    if (em.error) throw em.error;
    if (perfis.error) throw perfis.error;
    setImpItens((it.data ?? []) as ImportacaoItem[]);
    setAnexos((an.data ?? []) as Anexo[]);
    setEmissoes((em.data ?? []) as Emissao[]);
    setPerfisLiberados(((perfis.data ?? []) as Array<{ codigo: string; habilitado_producao: boolean; producao_homologacao_solicitacao_id: string | null }>)
      .filter((p) => p.habilitado_producao && p.producao_homologacao_solicitacao_id)
      .map((p) => `${p.codigo}|${p.producao_homologacao_solicitacao_id}`));
  }, [empresaId, supabase]);

  useEffect(() => { void carregar().catch((e) => avisar(textoErro(e), true)); }, [carregar, avisar]);
  useEffect(() => {
    void (async () => {
      const [emp, cb, mc] = await Promise.all([
        supabase.from("empresas").select("cnpj,razao_social,uf").eq("id", empresaId).maybeSingle(),
        supabase.schema("f").from("conta_bancaria").select("id,nome").eq("empresa_id", empresaId).eq("ativo", true).is("deleted_at", null).order("nome"),
        supabase.schema("f").from("motivo_compra").select("id,codigo,nome,favorito").eq("ativo", true).is("deleted_at", null).order("favorito", { ascending: false }).order("ordem").order("nome").limit(60),
      ]);
      const e = emp.data as { cnpj?: string | null; razao_social?: string | null; uf?: string | null } | null;
      if (e) setEmpresa({ cnpj: String(e.cnpj ?? "").replace(/\D/g, ""), razao_social: e.razao_social ?? "", uf: String(e.uf ?? "").toUpperCase() });
      setContas((cb.data ?? []) as Conta[]);
      const lista = (mc.data ?? []) as Motivo[];
      setMotivos(lista);
      const estoque = lista.find((m) => m.codigo === "ESTOQUE") ?? lista[0];
      if (estoque) setNd((s) => (s.motivo_compra_id ? s : { ...s, motivo_compra_id: estoque.id }));
    })().catch((e) => avisar(textoErro(e), true));
  }, [empresaId, supabase, avisar]);
  // Retorno da SEFAZ chega pelo callback: atualiza sozinho.
  useEffect(() => {
    const canal = supabase.channel(`importacao-remessa-${empresaId}`)
      .on("postgres_changes", { event: "*", schema: "f", table: "documento_fiscal_emissao", filter: `empresa_id=eq.${empresaId}` }, () => void carregar().catch(() => {}))
      .on("postgres_changes", { event: "*", schema: "f", table: "importacao_remessa", filter: `empresa_id=eq.${empresaId}` }, () => void carregar().catch(() => {}))
      .subscribe();
    return () => { void supabase.removeChannel(canal); };
  }, [carregar, empresaId, supabase]);
  useEffect(() => {
    if (!emissoes.some((e) => ["ENVIANDO", "PROCESSANDO"].includes(e.status))) return;
    const timer = window.setInterval(() => void carregar().catch(() => {}), 5000);
    return () => window.clearInterval(timer);
  }, [carregar, emissoes]);

  // ---------------------------------------------------------------- 1 · DIR
  async function lerArquivoDir(file: File | null) {
    if (!file) return;
    setBusy("dir"); avisar("");
    try {
      const texto = await file.text();
      const lida = lerDirRemessa(texto);
      const { data, error } = await supabase.schema("f").rpc("fn_importacao_remessa_ler_dir", { p_xml: texto });
      if (error) throw error;
      const banco = data as LeituraBanco;
      setNomeArquivoDir(file.name);
      setXmlDir(texto);
      setDir(lida);
      setLeitura(banco);
      setBloqueiosTela(empresa ? bloqueiosDaDir(lida, empresa.cnpj) : []);
      // Pre-preenche o que a DIR traz; o resto (NCM, item, fabricante, GNRE, courier) e da tela.
      const ua = UNIDADES_RFB[lida.manifesto.uaEntrada];
      setDesemb({ local: banco.dir?.local_desembaraco ?? ua?.local ?? "", uf: banco.dir?.uf_desembaraco ?? ua?.uf ?? "", data: (lida.dir.dataRegistro ?? "").slice(0, 10) });
      const paisBacen = PAIS_SISCOMEX_PARA_BACEN[lida.remetente.paisCodigo ?? ""] ?? "1600";
      setExp({
        nome: lida.remetente.nome ?? "", logradouro: lida.remetente.logradouro ?? "", numero: "", complemento: lida.remetente.complemento ?? "", bairro: "",
        pais_codigo: paisBacen, pais_nome: PAISES_BACEN.find(([c]) => c === paisBacen)?.[1] ?? "", codigo: "", id_estrangeiro: "",
      });
      setItens(lida.mercadorias.map((m) => ({
        sequencia: m.sequencia, descricao_dir: m.descricao, valor_usd: m.valorUsd, quantidade: String(m.quantidade), item_id: null,
        codigo: "", descricao: m.descricao, unidade: "UN", ncm: "", fabricante: "", busca: "", sugestoes: [],
      })));
      setSubstituir(false);
      if (banco.bloqueios?.length) avisar(`DIR lida, mas bloqueada: ${banco.bloqueios.join(" ")}`, true);
      else if (banco.em_uso) avisar(`DIR ${lida.dir.numero} já está em uso na importação em ${statusRotulo(banco.em_uso.status).toLowerCase()}${banco.em_uso.nfe_numero ? ` (NF-e ${banco.em_uso.nfe_serie}/${banco.em_uso.nfe_numero})` : ""}. Uma DIR só gera uma nota.`, true);
      else avisar(`DIR ${lida.dir.numero} lida: AWB ${lida.awb}, ${lida.mercadorias.length} mercadoria(s), valor aduaneiro R$ ${formatarBrl(lida.tributavelBrl)}, II R$ ${formatarBrl(lida.ii.devido ?? 0)}. Complete os dados do passo 2.`);
    } catch (e) {
      setDir(null); setLeitura(null); setXmlDir("");
      avisar(e instanceof DirInvalida ? e.message : textoErro(e), true);
    } finally { setBusy(null); }
  }

  // ---------------------------------------------------------------- 2 · itens do catalogo
  async function buscarItem(indice: number, termo: string) {
    setItens((lista) => lista.map((i, k) => (k === indice ? { ...i, busca: termo } : i)));
    const t = termo.trim();
    if (t.length < 2) {
      setItens((lista) => lista.map((i, k) => (k === indice ? { ...i, sugestoes: [] } : i)));
      return;
    }
    const consulta = aplicarBuscaItem(
      supabase.from("itens").select("id,codigo_interno,nome,unidade_medida,ncm,fabricante")
        .eq("tenant_id", tenantId).eq("empresa_id", empresaId).eq("ativo", true),
      t,
    );
    const { data, error } = await consulta.order("nome").limit(8);
    if (error) avisar(error.message, true);
    setItens((lista) => lista.map((i, k) => (k === indice && i.busca === termo ? { ...i, sugestoes: (data ?? []) as ItemCatalogo[] } : i)));
  }
  function escolherItem(indice: number, item: ItemCatalogo) {
    setItens((lista) => lista.map((i, k) => (k === indice ? {
      ...i, item_id: item.id, codigo: item.codigo_interno ?? String(item.id), descricao: item.nome, unidade: (item.unidade_medida ?? "UN").toUpperCase(),
      ncm: i.ncm || String(item.ncm ?? "").replace(/\D/g, ""), fabricante: i.fabricante || (item.fabricante ?? ""), busca: `${item.codigo_interno ?? item.id} · ${item.nome}`, sugestoes: [],
    } : i)));
  }

  // ---------------------------------------------------------------- 3 · conta
  const cfopEscolhido = CFOPS_IMPORTACAO.find((c) => c.cfop === cfop) ?? CFOPS_IMPORTACAO[0];
  const conta = useMemo(() => {
    if (!dir) return null;
    try {
      return calcularImportacao({ valorAduaneiro: dir.tributavelBrl, ii: dir.ii.devido ?? 0, aliquotaIcms: numeroDecimal(aliquota), gnre: gnre.valor.trim() ? numeroDecimal(gnre.valor) : null });
    } catch { return null; }
  }, [dir, aliquota, gnre.valor]);
  const courierTotal = round2(numeroDecimal(courier.servicos) + numeroDecimal(courier.armazenagem));
  const custo = conta ? custoImportacao({ valorAduaneiro: conta.valorAduaneiro, ii: conta.ii, icms: conta.icms, courier: courierTotal, creditoIcms: cfopEscolhido.creditoIcms, quantidade: itens.reduce((acc, i) => acc + numeroDecimal(i.quantidade), 0) || 1 }) : null;
  // IBS/CBS: base do II acrescida dos tributos do caput, sem o ICMS (LC 214/2025, art. 69, caput e §§ 1º e 2º).
  const ibsBase = conta ? round2(conta.valorAduaneiro + conta.ii) : 0;
  const ibsUf = round2(ibsBase * 0.001);
  const cbs = round2(ibsBase * 0.009);
  // O plano do titulo segue o destino (mesma regra de f.fn_importacao_remessa_motivo_por_cfop):
  // 3556 consumo, 3551 investimento, 3101/3102 estoque. Trocar o CFOP troca o motivo sugerido.
  useEffect(() => {
    if (!motivos.length) return;
    const atual = motivos.find((m) => m.id === nd.motivo_compra_id) ?? null;
    const escolher = (pred: (m: Motivo) => boolean, preferido?: string) => motivos.find((m) => m.codigo === preferido) ?? motivos.find(pred) ?? null;
    let alvo: Motivo | null = null;
    if (cfop === "3556") { if (!atual || !/^CONSUMO/i.test(atual.codigo)) alvo = escolher((m) => /^CONSUMO/i.test(m.codigo), "CONSUMO_PRODUCAO"); }
    else if (cfop === "3551") { if (!atual || !/^INVESTIMENTO/i.test(atual.codigo)) alvo = escolher((m) => /^INVESTIMENTO/i.test(m.codigo)); }
    else if (!atual || /^(CONSUMO|INVESTIMENTO)/i.test(atual.codigo)) alvo = escolher((m) => m.codigo === "ESTOQUE") ?? motivos[0];
    if (alvo && alvo.id !== nd.motivo_compra_id) setNd((s) => ({ ...s, motivo_compra_id: alvo!.id }));
  }, [cfop, motivos, nd.motivo_compra_id]);
  // Trava de destino (o banco repete a mesma regra): uso proprio nao entra em 3101/3102.
  const motivoEscolhido = motivos.find((m) => m.id === nd.motivo_compra_id) ?? null;
  const usoProprio = useMemo(() => indicioUsoProprio(observacao, motivoEscolhido?.codigo ?? null, motivoEscolhido?.nome ?? null), [observacao, motivoEscolhido]);
  // Bloqueios: os do banco (quem decide); os da tela so quando o banco nao respondeu.
  const bloqueios = useMemo(() => (leitura ? leitura.bloqueios ?? [] : bloqueiosTela), [leitura, bloqueiosTela]);
  const pendenciasForm = useMemo(() => {
    const p: string[] = [];
    if (!dir) return p;
    if (bloqueios.length) p.push("A DIR está bloqueada (veja o passo 1).");
    if (leitura?.em_uso && !substituir && !teste) p.push("A DIR já está em uso. Marque \"gerar de novo\" para cancelar a anterior (só sem nota real) ou \"teste de homologação\".");
    if (!exp.nome.trim() || !exp.logradouro.trim()) p.push("Exportador: nome e endereço (conforme a invoice).");
    if (!/^\d{2,4}$/.test(exp.pais_codigo) || !exp.pais_nome.trim()) p.push("Exportador: país (código BACEN e nome).");
    itens.forEach((i, k) => {
      if (!/^\d{8}$/.test(i.ncm.replace(/\D/g, ""))) p.push(`Mercadoria ${k + 1}: NCM com 8 dígitos.`);
      if (!i.fabricante.trim()) p.push(`Mercadoria ${k + 1}: fabricante.`);
      if (!i.item_id && (!i.codigo.trim() || !i.descricao.trim())) p.push(`Mercadoria ${k + 1}: item do catálogo (ou código e descrição).`);
      if (!(numeroDecimal(i.quantidade) > 0)) p.push(`Mercadoria ${k + 1}: quantidade.`);
    });
    if (usoProprio && cfopEscolhido.creditoIcms) p.push(`Uso próprio indicado (${usoProprio}) não combina com o CFOP ${cfop} (${cfop === "3101" ? "industrialização" : "revenda"}). Use 3556 (uso e consumo) ou 3551 (ativo imobilizado), ou corrija a observação e o motivo de compra.`);
    if (!conta) p.push("Alíquota do ICMS entre 0 e 100.");
    else if (!gnre.valor.trim()) p.push("Valor da GNRE paga.");
    else if (!conta.gnreConfere) p.push(`ICMS calculado R$ ${formatarBrl(conta.icms)} difere da GNRE R$ ${formatarBrl(conta.gnre ?? 0)} em R$ ${formatarBrl(conta.diferencaGnre ?? 0)} (limite R$ 0,05).`);
    if (!desemb.local.trim() || !/^[A-Z]{2}$/.test(desemb.uf.trim().toUpperCase()) || !desemb.data) p.push("Local, UF e data do desembaraço.");
    if (nd.numero.trim() && !(numeroDecimal(nd.valor) > 0)) p.push("Valor da nota de débito do courier.");
    if (nd.numero.trim() && nd.pago_em && !nd.conta_bancaria_id) p.push("Nota de débito já paga: informe a conta bancária (ou deixe a data em branco para baixar depois).");
    return p;
  }, [dir, bloqueios, leitura, substituir, teste, exp, itens, conta, gnre.valor, desemb, nd, usoProprio, cfopEscolhido.creditoIcms, cfop]);

  // ---------------------------------------------------------------- 4 · gerar e homologar
  async function enviarAnexo(importacaoId: string, tipo: string, file: File) {
    const { data: sess } = await supabase.auth.getSession();
    const token = sess.session?.access_token;
    if (!token) throw new Error("Sessão ausente. Recarregue a página.");
    const form = new FormData();
    form.set("importacao_id", importacaoId); form.set("tenant_id", tenantId); form.set("empresa_id", empresaId); form.set("tipo", tipo); form.set("arquivo", file);
    const res = await fetch("/api/faturamento/importacao/anexos", { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: form });
    const corpo = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(corpo?.error ?? `Falha ao anexar ${file.name}.`);
  }

  async function gerarEHomologar() {
    if (!dir || !conta || pendenciasForm.length) return;
    setBusy("gerar"); avisar("");
    try {
      const dados = {
        xml: xmlDir, cfop, aliquota_icms: numeroDecimal(aliquota), substituir, teste,
        gnre: { numero: gnre.numero.trim() || null, receita: gnre.receita.trim() || null, uf: gnre.uf.trim().toUpperCase() || null, valor: numeroDecimal(gnre.valor) },
        courier: { servicos: numeroDecimal(courier.servicos), armazenagem: numeroDecimal(courier.armazenagem) },
        nota_debito: nd.numero.trim() ? {
          numero: nd.numero.trim(), valor: numeroDecimal(nd.valor), emissao: nd.emissao || null, pago_em: nd.pago_em || null,
          conta_bancaria_id: nd.pago_em ? nd.conta_bancaria_id || null : null, forma_pagamento: nd.pago_em ? nd.forma_pagamento : null, motivo_compra_id: nd.motivo_compra_id || null,
        } : { numero: null },
        exportador: { nome: exp.nome.trim(), logradouro: exp.logradouro.trim(), numero: exp.numero.trim() || null, complemento: exp.complemento.trim() || null, bairro: exp.bairro.trim() || null, pais_codigo: exp.pais_codigo, pais_nome: exp.pais_nome.trim(), codigo: exp.codigo.trim() || null, id_estrangeiro: exp.id_estrangeiro.trim() || null },
        itens: itens.map((i) => ({ item_id: i.item_id, codigo: i.codigo.trim() || null, descricao: i.descricao.trim() || null, unidade: i.unidade.trim() || null, quantidade: numeroDecimal(i.quantidade), ncm: i.ncm.replace(/\D/g, ""), fabricante: i.fabricante.trim() })),
        local_desembaraco: desemb.local.trim(), uf_desembaraco: desemb.uf.trim().toUpperCase(), data_desembaraco: desemb.data, via_transporte: Number(via), forma_intermedio: Number(intermedio),
        observacao: observacao.trim() || null,
      };
      const { data, error } = await supabase.schema("f").rpc("fn_importacao_remessa_criar", { p_dados: dados });
      if (error) throw error;
      const r = data as { importacao_id: string; solicitacao_id: string; cfop: string; valor_nota: number; destinatario: string };
      // Anexos: a DIR sempre; os demais os que a tela recebeu. Falha de anexo nao derruba a importacao.
      const falhas: string[] = [];
      try { await enviarAnexo(r.importacao_id, "DIR_XML", new File([xmlDir], nomeArquivoDir || `DIR_${dir.dir.numero}.xml`, { type: "application/xml" })); } catch (e) { falhas.push(textoErro(e)); }
      for (const a of anexosNovos) {
        try { await enviarAnexo(r.importacao_id, a.tipo, a.file); } catch (e) { falhas.push(textoErro(e)); }
      }
      const { data: env, error: erroEnv } = await supabase.functions.invoke("nfe-emitir", { body: { solicitacao_id: r.solicitacao_id } });
      if (erroEnv) throw erroEnv;
      if (env?.erro) throw new Error(env.codigo ? `cStat ${env.codigo} · ${env.erro}` : String(env.erro));
      setDir(null); setLeitura(null); setXmlDir(""); setNomeArquivoDir(""); setItens([]); setAnexosNovos([]); setSubstituir(false);
      avisar(`Importação CFOP ${r.cfop} (${r.destinatario}, R$ ${formatMoneyBR(numero(r.valor_nota))}) enviada à Focus em homologação. O retorno da SEFAZ chega automaticamente.${falhas.length ? ` Anexos com falha: ${falhas.join("; ")}` : ""}`, falhas.length > 0);
    } catch (e) {
      avisar(await erroFunction(e), true);
    } finally {
      setBusy(null);
      await carregar().catch(() => {});
    }
  }

  // ---------------------------------------------------------------- 5 · acoes
  async function emitirHomologacao(imp: Importacao) {
    if (!imp.solicitacao_id) return;
    setBusy(imp.id); avisar("");
    try {
      const { data, error } = await supabase.functions.invoke("nfe-emitir", { body: { solicitacao_id: imp.solicitacao_id } });
      if (error) throw error;
      if (data?.erro) throw new Error(data.codigo ? `cStat ${data.codigo} · ${data.erro}` : String(data.erro));
      avisar("Importação enviada à Focus em homologação. O retorno da SEFAZ chega automaticamente.");
    } catch (e) { avisar(await erroFunction(e), true); } finally { setBusy(null); await carregar().catch(() => {}); }
  }
  async function emitirProducao(imp: Importacao) {
    if (!imp.solicitacao_id) return;
    setBusy(imp.id); avisar("");
    try {
      const { data: st, error: erroSt } = await supabase.functions.invoke("nfe-emitir-producao", { body: { acao: "STATUS", solicitacao_id: imp.solicitacao_id } });
      if (erroSt) throw erroSt;
      const status = st as ProducaoStatus | null;
      const resumo = status?.resumo_confirmacao;
      if (!status?.pronta || !status.preflight_confirmacao_pronto || !resumo?.contexto_hash) {
        throw new Error(status?.motivo ?? "A produção ainda não está liberada para esta importação.");
      }
      const ok = window.confirm(
        `EMITIR NF-e REAL DE ENTRADA DE IMPORTAÇÃO (produção)\n\nExportador: ${resumo.nome_destinatario ?? "?"} (exterior, sem CNPJ)\n`
        + `AWB ${imp.awb} · DIR ${imp.dir_numero} · CFOP ${imp.cfop}\n`
        + `Valor da nota: R$ ${formatMoneyBR(numero(resumo.valor_total))} (vProd + II + ICMS) · sem cobrança\n\nQuando autorizar, a mercadoria entra no estoque e a nota de débito do courier vai para o contas a pagar. Deseja continuar?`,
      );
      if (!ok) return;
      const { data, error } = await supabase.functions.invoke("nfe-emitir-producao", { body: { acao: "EMITIR", solicitacao_id: imp.solicitacao_id, confirmacao_contexto_hash: resumo.contexto_hash } });
      if (error) throw error;
      if (data?.erro) throw new Error(data.codigo ? `cStat ${data.codigo} · ${data.erro}` : String(data.erro));
      avisar("NF-e de entrada de importação enviada à SEFAZ em PRODUÇÃO.");
    } catch (e) { avisar(await erroFunction(e), true); } finally { setBusy(null); await carregar().catch(() => {}); }
  }
  async function cancelar(imp: Importacao) {
    const motivo = window.prompt("Motivo do cancelamento da importação (15 a 255 caracteres):", "Importacao cancelada pela tela de operacoes");
    if (!motivo) return;
    setBusy(imp.id); avisar("");
    try {
      const { error } = await supabase.schema("f").rpc("fn_importacao_remessa_cancelar", { p_importacao_id: imp.id, p_motivo: motivo });
      if (error) throw error;
      avisar(`Importação da DIR ${imp.dir_numero} cancelada; a DIR fica livre para uma nova importação.`);
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
  async function abrirAnexo(anexo: Anexo) {
    const aba = window.open("about:blank", "_blank");
    if (aba) aba.opener = null;
    setBusy(anexo.id);
    try {
      const { data: sess } = await supabase.auth.getSession();
      const token = sess.session?.access_token;
      if (!token) throw new Error("Sessão ausente. Recarregue a página.");
      const res = await fetch(`/api/faturamento/importacao/anexos?anexo_id=${encodeURIComponent(anexo.id)}`, { headers: { Authorization: `Bearer ${token}` } });
      const corpo = await res.json().catch(() => ({}));
      if (!res.ok || !corpo?.url) throw new Error(corpo?.error ?? "Não foi possível abrir o anexo.");
      if (!aba) throw new Error("O navegador bloqueou a nova aba. Libere pop-ups para este sistema.");
      aba.location.replace(String(corpo.url));
    } catch (err) { aba?.close(); avisar(textoErro(err), true); } finally { setBusy(null); }
  }
  async function anexarNaLista(imp: Importacao, file: File | null) {
    if (!file) return;
    setBusy(imp.id); avisar("");
    try {
      await enviarAnexo(imp.id, anexoLista[imp.id] ?? "OUTRO", file);
      avisar(`Anexo ${file.name} guardado na importação da DIR ${imp.dir_numero}.`);
    } catch (e) { avisar(textoErro(e), true); } finally { setBusy(null); await carregar().catch(() => {}); }
  }

  const listadas = importacoes.filter((i) => filtro === "TODAS" || i.status !== "CANCELADA");
  const itensDa = (id: string) => impItens.filter((i) => i.importacao_id === id);
  const anexosDa = (id: string) => anexos.filter((a) => a.importacao_id === id);
  const quantidadeTotal = itens.reduce((acc, i) => acc + numeroDecimal(i.quantidade), 0);

  return (
    <div className="space-y-5">
      <div>
        <h2 className="font-semibold">Importação por remessa expressa (courier)</h2>
        <p className="mt-1 text-sm text-zinc-400">
          A mercadoria chegou por courier e foi desembaraçada pela DIR do Siscomex Remessa (regime de tributação simplificada). A Segau emite a NF-e de entrada
          (CFOP 3101/3102/3556/3551) com o exportador no exterior como destinatário: vProd = valor aduaneiro, II da DIR, ICMS por dentro conferido com a GNRE, sem IPI,
          PIS e COFINS, sem cobrança. A nota real dá entrada no estoque e lança a nota de débito do courier no contas a pagar.
        </p>
      </div>
      {aviso ? <div role={aviso.erro ? "alert" : "status"} className={`rounded border p-3 text-sm ${aviso.erro ? "border-red-900 bg-red-950/30 text-red-200" : "border-sky-800 bg-sky-950/30 text-sky-200"}`}>{aviso.texto}</div> : null}

      <section className="space-y-3 rounded-lg border border-zinc-800 p-4">
        <h3 className="font-medium">1 · DIR (XML do Siscomex Remessa)</h3>
        <p className="text-sm text-zinc-400">Arquivo com raiz <span className="font-mono text-xs">xml1702</span> de uma remessa só. O destinatário da DIR tem de ser a empresa emitente, a situação 25 e o II recolhido.</p>
        <div className="flex flex-wrap items-center gap-2">
          <input aria-label="XML da DIR" type="file" accept=".xml,text/xml,application/xml" className="text-sm text-zinc-300 file:mr-3 file:rounded file:border file:border-zinc-600 file:bg-zinc-900 file:px-3 file:py-2 file:text-sm file:text-zinc-100" disabled={busy === "dir"} onChange={(e) => void lerArquivoDir(e.target.files?.[0] ?? null)} />
          {busy === "dir" ? <span className="text-sm text-zinc-400">Lendo a DIR...</span> : null}
          {dir ? <button type="button" className={button} onClick={() => { setDir(null); setLeitura(null); setXmlDir(""); setNomeArquivoDir(""); setItens([]); setBloqueiosTela([]); avisar(""); }}>Trocar DIR</button> : null}
        </div>
        {dir ? (
          <div className="grid gap-3 text-sm md:grid-cols-3">
            <div className="rounded border border-zinc-800 bg-zinc-900/40 p-3"><div className="text-xs uppercase text-zinc-500">Remessa</div><div>AWB <span className="font-mono">{dir.awb}</span></div><div className="text-xs text-zinc-400">{dir.courier.nome ?? "courier"} · CNPJ {cnpjFormatado(dir.courier.cnpj)}</div><div className="text-xs text-zinc-400">{dir.volumes ?? "?"} volume(s) · {qtd(dir.peso ?? 0, 3)} kg · {dir.descricao}</div></div>
            <div className="rounded border border-zinc-800 bg-zinc-900/40 p-3"><div className="text-xs uppercase text-zinc-500">DIR</div><div>Nº <span className="font-mono">{dir.dir.numero}</span> · situação {dir.situacao}</div><div className="text-xs text-zinc-400">Registro {dataHoraBR(dir.dir.dataRegistro)} · UA {dir.manifesto.uaEntrada} · lote {dir.dir.lote ?? "—"}</div><div className="text-xs text-zinc-400">Destinatário {dir.destinatario.nome} · CNPJ {cnpjFormatado(dir.destinatario.documento)}</div></div>
            <div className="rounded border border-zinc-800 bg-zinc-900/40 p-3"><div className="text-xs uppercase text-zinc-500">Valores</div><div>Mercadoria USD {qtd(dir.valorUsd, 2)} · frete USD {qtd(dir.freteUsd, 2)} ({dir.freteModo ?? "—"})</div><div className="text-xs text-zinc-400">Câmbio {dir.cambio.toLocaleString("pt-BR", { minimumFractionDigits: 4 })} · valor aduaneiro R$ {formatarBrl(dir.tributavelBrl)}</div><div className="text-xs text-zinc-400">II R$ {formatarBrl(dir.ii.devido ?? 0)} (recolhido R$ {formatarBrl(dir.ii.recolhido ?? 0)}, pendente R$ {formatarBrl(dir.ii.pendente)})</div><div className="text-xs text-zinc-400">Remetente na DIR: {dir.remetente.nome ?? "—"}</div></div>
          </div>
        ) : null}
        {bloqueios.length ? <ul className="list-disc space-y-1 rounded border border-red-900 bg-red-950/30 p-3 pl-7 text-sm text-red-200">{bloqueios.map((b) => <li key={b}>{b}</li>)}</ul> : null}
        {dir && leitura?.em_uso ? (
          <label className="flex items-center gap-2 text-sm text-amber-200"><input type="checkbox" checked={substituir} onChange={(e) => setSubstituir(e.target.checked)} /> Gerar de novo: cancelar a importação anterior desta DIR (só possível sem NF-e real) e criar outra.</label>
        ) : null}
        {dir ? (
          <label className="flex items-center gap-2 text-sm text-zinc-300"><input aria-label="Teste de homologação" type="checkbox" checked={teste} onChange={(e) => setTeste(e.target.checked)} /> Teste de homologação: só emite em homologação, convive com a DIR já usada e não gera estoque nem contas a pagar</label>
        ) : null}
      </section>

      {dir && conta ? (
        <section className="space-y-4 rounded-lg border border-zinc-800 p-4">
          <h3 className="font-medium">2 · Dados da nota</h3>
          <div className="space-y-2">
            <div className="text-xs uppercase text-zinc-500">Exportador (destinatário da nota de entrada, conforme a invoice)</div>
            <div className="grid gap-3 md:grid-cols-3">
              <label className={`${label} md:col-span-2`}>Nome<input aria-label="Nome do exportador" className={`${field} w-full`} value={exp.nome} maxLength={60} onChange={(e) => setExp((s) => ({ ...s, nome: e.target.value }))} /></label>
              <label className={label}>Identificação (idEstrangeiro, opcional)<input aria-label="Identificação do exportador" className={`${field} w-full`} value={exp.id_estrangeiro} maxLength={20} onChange={(e) => setExp((s) => ({ ...s, id_estrangeiro: e.target.value }))} /></label>
              <label className={`${label} md:col-span-2`}>Logradouro<input aria-label="Logradouro do exportador" className={`${field} w-full`} value={exp.logradouro} maxLength={60} onChange={(e) => setExp((s) => ({ ...s, logradouro: e.target.value }))} /></label>
              <label className={label}>Número<input aria-label="Número do exportador" className={`${field} w-full`} value={exp.numero} maxLength={60} placeholder="S/N" onChange={(e) => setExp((s) => ({ ...s, numero: e.target.value }))} /></label>
              <label className={label}>Complemento<input aria-label="Complemento do exportador" className={`${field} w-full`} value={exp.complemento} maxLength={60} onChange={(e) => setExp((s) => ({ ...s, complemento: e.target.value }))} /></label>
              <label className={label}>Bairro / distrito<input aria-label="Bairro do exportador" className={`${field} w-full`} value={exp.bairro} maxLength={60} placeholder="EXTERIOR" onChange={(e) => setExp((s) => ({ ...s, bairro: e.target.value }))} /></label>
              <label className={label}>País (BACEN)<select aria-label="País do exportador" className={`${field} w-full`} value={PAISES_BACEN.some(([c]) => c === exp.pais_codigo) ? exp.pais_codigo : ""} onChange={(e) => { const c = e.target.value; setExp((s) => ({ ...s, pais_codigo: c, pais_nome: PAISES_BACEN.find(([k]) => k === c)?.[1] ?? s.pais_nome })); }}><option value="">Outro (informe abaixo)</option>{PAISES_BACEN.map(([c, n]) => <option key={c} value={c}>{c} · {n}</option>)}</select></label>
              <label className={label}>Código BACEN<input aria-label="Código BACEN do país" className={`${field} w-full`} value={exp.pais_codigo} maxLength={4} onChange={(e) => setExp((s) => ({ ...s, pais_codigo: e.target.value.replace(/\D/g, "") }))} /></label>
              <label className={label}>Nome do país<input aria-label="Nome do país" className={`${field} w-full`} value={exp.pais_nome} maxLength={60} onChange={(e) => setExp((s) => ({ ...s, pais_nome: e.target.value }))} /></label>
              <label className={label}>Código do exportador (cExportador)<input aria-label="Código do exportador" className={`${field} w-full`} value={exp.codigo} maxLength={60} placeholder="= nome, se vazio" onChange={(e) => setExp((s) => ({ ...s, codigo: e.target.value }))} /></label>
            </div>
            <p className="text-xs text-zinc-500">Município da nota: EXTERIOR (9999999), UF EX, sem CNPJ e sem IE (indicador 9). O remetente que consta na DIR ({dir.remetente.nome ?? "—"}) vai citado nas informações complementares.</p>
          </div>

          <div className="space-y-2">
            <div className="text-xs uppercase text-zinc-500">Mercadorias da DIR ({itens.length})</div>
            {itens.map((i, k) => (
              <div key={i.sequencia || k} className="grid gap-3 rounded border border-zinc-800 p-3 md:grid-cols-6">
                <div className="text-sm md:col-span-6"><span className="text-zinc-500">#{i.sequencia || k + 1}</span> {i.descricao_dir} <span className="text-xs text-zinc-500">· USD {qtd(i.valor_usd, 2)}</span></div>
                <label className={`${label} relative md:col-span-2`}>Item do catálogo
                  <input aria-label={`Item do catálogo da mercadoria ${k + 1}`} className={`${field} w-full`} value={i.busca} placeholder="Código ou nome do item" onChange={(e) => void buscarItem(k, e.target.value)} />
                  {i.sugestoes.length ? <div className="absolute left-0 right-0 top-full z-10 mt-1 rounded border border-zinc-700 bg-zinc-900 shadow">{i.sugestoes.map((s) => <button type="button" key={s.id} className="block w-full px-3 py-2 text-left text-sm hover:bg-zinc-800" onClick={() => escolherItem(k, s)}>{s.codigo_interno ?? s.id} · {s.nome}{s.ncm ? <span className="text-xs text-zinc-500"> · NCM {s.ncm}</span> : null}</button>)}</div> : null}
                  {i.item_id ? <span className="text-xs text-emerald-300">item {i.item_id} · entra no estoque</span> : <span className="text-xs text-amber-300">sem item do catálogo a mercadoria não entra no estoque</span>}
                </label>
                <label className={label}>Código (cProd)<input aria-label={`Código da mercadoria ${k + 1}`} className={`${field} w-full`} value={i.codigo} maxLength={60} onChange={(e) => setItens((l) => l.map((x, j) => (j === k ? { ...x, codigo: e.target.value } : x)))} /></label>
                <label className={`${label} md:col-span-3`}>Descrição (xProd)<input aria-label={`Descrição da mercadoria ${k + 1}`} className={`${field} w-full`} value={i.descricao} maxLength={120} onChange={(e) => setItens((l) => l.map((x, j) => (j === k ? { ...x, descricao: e.target.value } : x)))} /></label>
                <label className={label}>NCM<input aria-label={`NCM da mercadoria ${k + 1}`} className={`${field} w-full`} value={i.ncm} placeholder="8537.10.20" onChange={(e) => setItens((l) => l.map((x, j) => (j === k ? { ...x, ncm: e.target.value } : x)))} /></label>
                <label className={label}>Unidade<input aria-label={`Unidade da mercadoria ${k + 1}`} className={`${field} w-full`} value={i.unidade} maxLength={6} onChange={(e) => setItens((l) => l.map((x, j) => (j === k ? { ...x, unidade: e.target.value.toUpperCase() } : x)))} /></label>
                <label className={label}>Quantidade<input aria-label={`Quantidade da mercadoria ${k + 1}`} className={`${field} w-full text-right`} inputMode="decimal" value={i.quantidade} onChange={(e) => setItens((l) => l.map((x, j) => (j === k ? { ...x, quantidade: e.target.value } : x)))} /></label>
                <label className={`${label} md:col-span-3`}>Fabricante (cFabricante da adição)<input aria-label={`Fabricante da mercadoria ${k + 1}`} className={`${field} w-full`} value={i.fabricante} maxLength={60} placeholder="OMRON" onChange={(e) => setItens((l) => l.map((x, j) => (j === k ? { ...x, fabricante: e.target.value } : x)))} /></label>
              </div>
            ))}
          </div>

          <div className="grid gap-3 md:grid-cols-4">
            <label className={`${label} md:col-span-2`}>CFOP / perfil<select aria-label="CFOP da importação" className={`${field} w-full`} value={cfop} onChange={(e) => setCfop(e.target.value)}>{CFOPS_IMPORTACAO.map((c) => <option key={c.cfop} value={c.cfop}>{c.rotulo}</option>)}</select></label>
            <label className={label}>Alíquota do ICMS (%)<input aria-label="Alíquota do ICMS" className={`${field} w-full text-right`} inputMode="decimal" value={aliquota} onChange={(e) => setAliquota(e.target.value)} /></label>
            <label className={label}>Via de transporte (DI)<select aria-label="Via de transporte" className={`${field} w-full`} value={via} onChange={(e) => setVia(e.target.value)}>{VIAS_TRANSPORTE.map(([v, r]) => <option key={v} value={String(v)}>{r}</option>)}</select></label>
            <label className={label}>Nº da GNRE<input aria-label="Número da GNRE" className={`${field} w-full`} value={gnre.numero} onChange={(e) => setGnre((s) => ({ ...s, numero: e.target.value }))} /></label>
            <label className={label}>Receita<input aria-label="Receita da GNRE" className={`${field} w-full`} value={gnre.receita} onChange={(e) => setGnre((s) => ({ ...s, receita: e.target.value }))} /></label>
            <label className={label}>UF favorecida<input aria-label="UF da GNRE" className={`${field} w-full`} value={gnre.uf} maxLength={2} onChange={(e) => setGnre((s) => ({ ...s, uf: e.target.value.toUpperCase() }))} /></label>
            <label className={label}>Valor da GNRE paga (R$)<input aria-label="Valor da GNRE" className={`${field} w-full text-right`} inputMode="decimal" value={gnre.valor} placeholder={formatarBrl(conta.icms)} onChange={(e) => setGnre((s) => ({ ...s, valor: e.target.value }))} /></label>
            <label className={label}>Local do desembaraço<input aria-label="Local do desembaraço" className={`${field} w-full`} value={desemb.local} maxLength={60} onChange={(e) => setDesemb((s) => ({ ...s, local: e.target.value.toUpperCase() }))} /></label>
            <label className={label}>UF do desembaraço<input aria-label="UF do desembaraço" className={`${field} w-full`} value={desemb.uf} maxLength={2} onChange={(e) => setDesemb((s) => ({ ...s, uf: e.target.value.toUpperCase() }))} /></label>
            <label className={label}>Data do desembaraço<input aria-label="Data do desembaraço" type="date" className={`${field} w-full`} value={desemb.data} onChange={(e) => setDesemb((s) => ({ ...s, data: e.target.value }))} /></label>
            <label className={label}>Intermediação<select aria-label="Forma de intermediação" className={`${field} w-full`} value={intermedio} onChange={(e) => setIntermedio(e.target.value)}><option value="1">1 · Por conta própria</option><option value="2">2 · Por conta e ordem</option><option value="3">3 · Por encomenda</option></select></label>
          </div>

          <div className="space-y-2">
            <div className="text-xs uppercase text-zinc-500">Courier: despesas e nota de débito (fora da nota; despesa da importação)</div>
            <div className="grid gap-3 md:grid-cols-4">
              <label className={label}>Serviços (R$)<input aria-label="Despesas de serviços do courier" className={`${field} w-full text-right`} inputMode="decimal" value={courier.servicos} onChange={(e) => setCourier((s) => ({ ...s, servicos: e.target.value }))} /></label>
              <label className={label}>Armazenagem (R$)<input aria-label="Armazenagem do courier" className={`${field} w-full text-right`} inputMode="decimal" value={courier.armazenagem} onChange={(e) => setCourier((s) => ({ ...s, armazenagem: e.target.value }))} /></label>
              <label className={label}>Nº da nota de débito<input aria-label="Número da nota de débito" className={`${field} w-full`} value={nd.numero} onChange={(e) => setNd((s) => ({ ...s, numero: e.target.value }))} /></label>
              <label className={label}>Valor da nota de débito (R$)<input aria-label="Valor da nota de débito" className={`${field} w-full text-right`} inputMode="decimal" value={nd.valor} placeholder={formatarBrl(round2(conta.ii + conta.icms + courierTotal))} onChange={(e) => setNd((s) => ({ ...s, valor: e.target.value }))} /></label>
              <label className={label}>Emissão<input aria-label="Emissão da nota de débito" type="date" className={`${field} w-full`} value={nd.emissao} onChange={(e) => setNd((s) => ({ ...s, emissao: e.target.value }))} /></label>
              <label className={label}>Paga em (vazio = pagar depois)<input aria-label="Data de pagamento da nota de débito" type="date" className={`${field} w-full`} value={nd.pago_em} onChange={(e) => setNd((s) => ({ ...s, pago_em: e.target.value }))} /></label>
              <label className={label}>Conta bancária que pagou<select aria-label="Conta bancária" className={`${field} w-full`} value={nd.conta_bancaria_id} onChange={(e) => setNd((s) => ({ ...s, conta_bancaria_id: e.target.value }))}><option value="">—</option>{contas.map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}</select></label>
              <label className={label}>Forma<select aria-label="Forma de pagamento" className={`${field} w-full`} value={nd.forma_pagamento} onChange={(e) => setNd((s) => ({ ...s, forma_pagamento: e.target.value }))}>{FORMAS_PAGAMENTO_AP.map((f) => <option key={f.codigo} value={f.codigo}>{textoOpcao(f)}</option>)}</select></label>
              <label className={`${label} md:col-span-2`}>Motivo de compra do título<select aria-label="Motivo de compra" className={`${field} w-full`} value={nd.motivo_compra_id} onChange={(e) => setNd((s) => ({ ...s, motivo_compra_id: e.target.value }))}><option value="">—</option>{motivos.map((m) => <option key={m.id} value={m.id}>{m.codigo} · {m.nome}</option>)}</select></label>
            </div>
            <p className="text-xs text-zinc-500">A nota de débito ({dir.courier.nome ?? "courier"}) normalmente soma II + ICMS/GNRE + serviços + armazenagem. Com a data de pagamento e a conta, o título já nasce baixado quando a nota real for autorizada; sem elas, fica aprovado para baixa no financeiro. Nunca duplica um título já lançado com o mesmo número. O rateio do título segue o destino: 3556 no plano de consumo, 3551 em investimento, 3101/3102 em estoque (o motivo sugerido muda com o CFOP).</p>
          </div>

          <div className="space-y-2">
            <div className="text-xs uppercase text-zinc-500">Anexos (a DIR é anexada sozinha)</div>
            <div className="flex flex-wrap items-center gap-2">
              <select aria-label="Tipo do anexo" className={field} value={anexoTipo} onChange={(e) => setAnexoTipo(e.target.value)}>{TIPOS_ANEXO.map(([v, r]) => <option key={v} value={v}>{r}</option>)}</select>
              <input aria-label="Arquivo do anexo" type="file" className="text-sm text-zinc-300 file:mr-3 file:rounded file:border file:border-zinc-600 file:bg-zinc-900 file:px-3 file:py-2 file:text-sm file:text-zinc-100" onChange={(e) => { const f = e.target.files?.[0]; if (f) setAnexosNovos((l) => [...l, { tipo: anexoTipo, file: f }]); e.target.value = ""; }} />
            </div>
            {anexosNovos.length ? <ul className="text-sm text-zinc-300">{anexosNovos.map((a, k) => <li key={`${a.file.name}-${k}`} className="flex items-center gap-2"><span className="rounded-full border border-zinc-700 px-2 text-xs">{TIPOS_ANEXO.find(([v]) => v === a.tipo)?.[1] ?? a.tipo}</span>{a.file.name}<button type="button" className="text-xs text-red-300 underline" onClick={() => setAnexosNovos((l) => l.filter((_, j) => j !== k))}>tirar</button></li>)}</ul> : null}
          </div>
          <label className={label}>Observação (vai nas informações complementares, depois do texto da importação)<textarea aria-label="Observação da importação" className={`${field} min-h-16 w-full`} value={observacao} onChange={(e) => setObservacao(e.target.value)} maxLength={500} /></label>
        </section>
      ) : null}

      {dir && conta ? (
        <section className="space-y-3 rounded-lg border border-zinc-800 p-4">
          <h3 className="font-medium">3 · Cálculo e conferência</h3>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[640px] text-sm">
              <tbody className="divide-y divide-zinc-800">
                <tr><td className="py-1 pr-3 text-zinc-400">vProd = valor aduaneiro (mercadoria + frete internacional, da DIR)</td><td className="py-1 text-right tabular-nums">R$ {formatarBrl(conta.valorAduaneiro)}</td></tr>
                <tr><td className="py-1 pr-3 text-zinc-400">II (da DIR, regime {dir.mercadorias[0]?.regimeTributacao ?? "?"})</td><td className="py-1 text-right tabular-nums">R$ {formatarBrl(conta.ii)}</td></tr>
                <tr><td className="py-1 pr-3 text-zinc-400">BC ICMS = (vProd + II) ÷ (1 − {qtd(conta.aliquotaIcms, 2)}%)</td><td className="py-1 text-right tabular-nums">R$ {formatarBrl(conta.bcIcms)}</td></tr>
                <tr><td className="py-1 pr-3 text-zinc-400">ICMS = BC × {qtd(conta.aliquotaIcms, 2)}%</td><td className="py-1 text-right tabular-nums">R$ {formatarBrl(conta.icms)}</td></tr>
                <tr><td className="py-1 pr-3 text-zinc-400">GNRE paga</td><td className={`py-1 text-right tabular-nums ${conta.gnre === null ? "text-amber-300" : conta.gnreConfere ? "text-emerald-300" : "text-red-300"}`}>{conta.gnre === null ? "informe o valor" : `R$ ${formatarBrl(conta.gnre)} · diferença R$ ${formatarBrl(conta.diferencaGnre ?? 0)} ${conta.gnreConfere ? "· confere" : "· acima de R$ 0,05, bloqueia"}`}</td></tr>
                <tr><td className="py-1 pr-3 text-zinc-400">IPI, PIS e COFINS (RTS)</td><td className="py-1 text-right tabular-nums">R$ 0,00 · CST IPI 02 (cEnq 319, RTS) · CST PIS/COFINS 71</td></tr>
                <tr><td className="py-1 pr-3 text-zinc-400">vOutro = ICMS</td><td className="py-1 text-right tabular-nums">R$ {formatarBrl(conta.outrasDespesas)}</td></tr>
                <tr className="font-semibold"><td className="py-1 pr-3">vNF = vProd + II + vOutro</td><td className="py-1 text-right tabular-nums">R$ {formatarBrl(conta.valorNota)}</td></tr>
                <tr><td className="py-1 pr-3 text-zinc-400">IBS/CBS (2026, teste): base vProd + II = R$ {formatarBrl(ibsBase)} (sem ICMS e sem IPI, LC 214 art. 69) · IBS UF 0,1% · CBS 0,9%</td><td className="py-1 text-right tabular-nums">R$ {formatarBrl(ibsUf)} · R$ {formatarBrl(cbs)}</td></tr>
                <tr><td className="py-1 pr-3 text-zinc-400">Custo de estoque = vProd + II + courier (R$ {formatarBrl(courierTotal)}){cfopEscolhido.creditoIcms ? " · ICMS fora do custo (crédito pendente da contadora)" : " + ICMS (sem crédito)"}</td><td className="py-1 text-right tabular-nums">R$ {formatarBrl(custo?.total ?? 0)}{quantidadeTotal > 1 ? ` · R$ ${qtd(custo?.unitario ?? 0, 6)} por unidade` : ""}</td></tr>
                <tr><td className="py-1 pr-3 text-zinc-400">Depois da nota real</td><td className="py-1 text-right text-xs text-zinc-300">{cfopEscolhido.creditoIcms ? "item marcado como importado pela Segau (origem 1, equiparado a industrial: IPI na saída); crédito de ICMS fica pendente de aprovação da contadora (GNRE em nome do courier)" : "sem equiparação a industrial e sem crédito de ICMS (uso próprio)"}</td></tr>
              </tbody>
            </table>
          </div>
          {pendenciasForm.length ? <ul className="list-disc space-y-1 rounded border border-amber-900 bg-amber-950/20 p-3 pl-7 text-sm text-amber-200">{pendenciasForm.map((p) => <li key={p}>{p}</li>)}</ul> : <p className="text-sm text-emerald-300">Tudo conferido. Revise a prévia e emita em homologação.</p>}
        </section>
      ) : null}

      {dir && conta && pendenciasForm.length === 0 ? (
        <section className="space-y-3 rounded-lg border border-zinc-800 p-4">
          <h3 className="font-medium">4 · Prévia da NF-e de entrada</h3>
          <div className="grid gap-3 text-sm md:grid-cols-2">
            <div className="rounded border border-zinc-800 bg-zinc-900/40 p-3 space-y-1">
              <div className="text-xs uppercase text-zinc-500">Identificação</div>
              <div>natOp: {cfopEscolhido.natureza.replace("IMPORTACAO_", "COMPRA PARA ").replace("INDUSTRIALIZACAO", "INDUSTRIALIZACAO - IMPORTACAO").replace("COMERCIALIZACAO", "COMERCIALIZACAO - IMPORTACAO").replace("COMPRA PARA CONSUMO", "COMPRA DE MATERIAL PARA USO OU CONSUMO - IMPORTACAO").replace("COMPRA PARA ATIVO", "COMPRA DE BEM PARA O ATIVO IMOBILIZADO - IMPORTACAO")}</div>
              <div>tpNF 0 (entrada) · idDest 3 (exterior) · finNFe 1 · indFinal {cfopEscolhido.consumidorFinal} · indPres 9 · série {empresa ? "da empresa" : "?"}</div>
              <div>Emitente: {empresa?.razao_social ?? "?"} · CNPJ {cnpjFormatado(empresa?.cnpj)}</div>
              <div>Transporte: modFrete 9 (sem frete na nota) · Pagamento: tPag 90 (sem pagamento), vPag 0</div>
            </div>
            <div className="rounded border border-zinc-800 bg-zinc-900/40 p-3 space-y-1">
              <div className="text-xs uppercase text-zinc-500">Destinatário (exportador)</div>
              <div className="font-medium">{exp.nome.toUpperCase()}</div>
              <div>{exp.logradouro.toUpperCase()}, {exp.numero || "S/N"}{exp.complemento ? ` · ${exp.complemento.toUpperCase()}` : ""} · {(exp.bairro || "EXTERIOR").toUpperCase()}</div>
              <div>EXTERIOR (9999999) · UF EX · país {exp.pais_codigo} {exp.pais_nome.toUpperCase()} · indIEDest 9 · sem CNPJ{exp.id_estrangeiro ? ` · idEstrangeiro ${exp.id_estrangeiro}` : ""}</div>
              <div className="text-xs text-zinc-500">Em homologação o nome sai como “NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL”.</div>
            </div>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[1100px] text-sm">
              <thead className="text-left text-xs uppercase text-zinc-500"><tr><th className="py-1 pr-2">#</th><th className="py-1 pr-2">cProd</th><th className="py-1 pr-2">xProd</th><th className="py-1 pr-2">NCM</th><th className="py-1 pr-2">CFOP</th><th className="py-1 pr-2">Un / qtd</th><th className="py-1 pr-2 text-right">vUnCom = vProd</th><th className="py-1 pr-2">ICMS</th><th className="py-1 pr-2">II</th><th className="py-1 pr-2">IPI · PIS/COFINS · IBS/CBS</th><th className="py-1 pr-2 text-right">vOutro</th><th className="py-1 pr-2">DI / adição</th></tr></thead>
              <tbody className="divide-y divide-zinc-800">
                {itens.map((i, k) => {
                  const share = i.valor_usd / (itens.reduce((acc, x) => acc + x.valor_usd, 0) || 1);
                  const vProd = round2(conta.valorAduaneiro * share);
                  const bc = round2(conta.bcIcms * share);
                  const icms = round2(bc * conta.aliquotaIcms / 100);
                  const ii = round2(conta.ii * share);
                  return (
                    <tr key={k} className="align-top">
                      <td className="py-1 pr-2">{k + 1}</td>
                      <td className="py-1 pr-2 font-mono text-xs">{i.codigo}</td>
                      <td className="py-1 pr-2">{i.descricao}</td>
                      <td className="py-1 pr-2">{i.ncm.replace(/\D/g, "")}</td>
                      <td className="py-1 pr-2">{cfop}</td>
                      <td className="py-1 pr-2">{i.unidade} · {qtd(numeroDecimal(i.quantidade))}</td>
                      <td className="py-1 pr-2 text-right tabular-nums">R$ {formatarBrl(vProd)}</td>
                      <td className="py-1 pr-2 text-xs">orig 1 · CST 00 · modBC 3<br />BC {formatarBrl(bc)} · {qtd(conta.aliquotaIcms, 2)}% · {formatarBrl(icms)}</td>
                      <td className="py-1 pr-2 text-xs">vBC {formatarBrl(vProd)} · vDespAdu 0,00<br />vII {formatarBrl(ii)} · vIOF 0,00</td>
                      <td className="py-1 pr-2 text-xs">IPI 03/999 · PIS 98 · COFINS 98<br />IBS/CBS 000/000001 · base {formatarBrl(round2(vProd + ii))}</td>
                      <td className="py-1 pr-2 text-right tabular-nums">R$ {formatarBrl(icms)}</td>
                      <td className="py-1 pr-2 text-xs">nDI {dir.dir.numero} · dDI {dataBR(desemb.data)}<br />{desemb.local} / {desemb.uf} · dDesemb {dataBR(desemb.data)}<br />via {via} · intermédio {intermedio} · cExportador {(exp.codigo || exp.nome).toUpperCase().slice(0, 30)}…<br />adição 1 · seq {k + 1} · cFabricante {i.fabricante.toUpperCase()}</td>
                    </tr>
                  );
                })}
              </tbody>
              <tfoot><tr className="text-xs text-zinc-400"><td colSpan={12} className="py-2">Totais: vProd R$ {formatarBrl(conta.valorAduaneiro)} · vII R$ {formatarBrl(conta.ii)} · vBC ICMS R$ {formatarBrl(conta.bcIcms)} · vICMS R$ {formatarBrl(conta.icms)} · vOutro R$ {formatarBrl(conta.outrasDespesas)} · vFrete/vSeg/vDesc/vIPI/vPIS/vCOFINS 0,00 · <span className="font-semibold text-zinc-200">vNF R$ {formatarBrl(conta.valorNota)}</span>. Com mais de uma mercadoria o banco calcula o ICMS item a item; o total pode andar centavos.</td></tr></tfoot>
            </table>
          </div>
          <div className="rounded border border-zinc-800 bg-zinc-900/40 p-3 text-xs text-zinc-300 space-y-1">
            <div><span className="text-zinc-500">infAdFisco:</span> NF-E DE ENTRADA DE IMPORTACAO POR REMESSA EXPRESSA (RTS, REGIME DE TRIBUTACAO SIMPLIFICADA). DIR {dir.dir.numero} DE {dataBR((dir.dir.dataRegistro ?? "").slice(0, 10))}. II RECOLHIDO NA DIR. ICMS RECOLHIDO POR GNRE{gnre.receita.trim() ? ` RECEITA ${gnre.receita.trim()}` : ""}.</div>
            <div><span className="text-zinc-500">infCpl:</span> IMPORTACAO POR REMESSA EXPRESSA. AWB {dir.awb}{dir.courier.nome ? ` ${dir.courier.nome}` : ""}. DIR {dir.dir.numero} REGISTRADA EM {dataBR((dir.dir.dataRegistro ?? "").slice(0, 10))}, UA {dir.manifesto.uaEntrada} ({desemb.local}/{desemb.uf}). CAMBIO {dir.cambio.toLocaleString("pt-BR", { minimumFractionDigits: 4 })}. MERCADORIA USD {formatarBrl(dir.valorUsd)}; FRETE USD {formatarBrl(dir.freteUsd)}; VALOR ADUANEIRO R$ {formatarBrl(conta.valorAduaneiro)}. II R$ {formatarBrl(conta.ii)}. ICMS R$ {formatarBrl(conta.icms)} (BC R$ {formatarBrl(conta.bcIcms)} A {qtd(conta.aliquotaIcms, 2)}%), GNRE{gnre.receita.trim() ? ` RECEITA ${gnre.receita.trim()}` : ""} R$ {formatarBrl(conta.gnre ?? 0)}. NOTA DE DEBITO {(dir.courier.nome ?? "DO COURIER").toUpperCase()} {nd.numero.trim() || "NAO INFORMADA"}. REMETENTE CONFORME DIR: {dir.remetente.nome ?? "?"}. EXPORTADOR CONFORME INVOICE: {exp.nome.toUpperCase()}. DESPESAS DO COURIER (SERVICOS R$ {formatarBrl(numeroDecimal(courier.servicos))}, ARMAZENAGEM R$ {formatarBrl(numeroDecimal(courier.armazenagem))}) FORA DA NOTA. SEM COBRANCA.{observacao.trim() ? ` | ${observacao.trim()}` : ""}</div>
          </div>
          <div className="flex flex-wrap items-center justify-end gap-2">
            <span className="text-xs text-zinc-500">A produção só depois da homologação autorizada, do perfil liberado e da sua confirmação.</span>
            <button type="button" className={primario} disabled={busy === "gerar"} onClick={() => void gerarEHomologar()}>{busy === "gerar" ? "Gerando..." : "Gerar importação e emitir em homologação"}</button>
          </div>
        </section>
      ) : null}

      <section className="space-y-3 rounded-lg border border-zinc-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="font-medium">5 · Importações</h3>
          <label className={label}>Mostrar<select aria-label="Filtrar importações" className={`${field} w-full`} value={filtro} onChange={(e) => setFiltro(e.target.value as typeof filtro)}><option value="ATIVAS">Em andamento e concluídas</option><option value="TODAS">Todas, com canceladas</option></select></label>
        </div>
        {listadas.length === 0 ? <p className="text-sm text-zinc-500">Nenhuma importação gerada.</p> : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[1100px] text-sm">
              <thead className="text-left text-xs uppercase text-zinc-500"><tr><th className="py-2 pr-3">Remessa / DIR</th><th className="py-2 pr-3">Mercadorias</th><th className="py-2 pr-3">CFOP</th><th className="py-2 pr-3 text-right">vNF</th><th className="py-2 pr-3">Status</th><th className="py-2 pr-3">NF-e de entrada</th><th className="py-2 pr-3">Anexos</th><th className="py-2 text-right">Ações</th></tr></thead>
              <tbody className="divide-y divide-zinc-800">
                {listadas.map((imp) => {
                  const hom = emissoes.find((e) => e.solicitacao_id === imp.solicitacao_id && e.ambiente === "HOMOLOGACAO");
                  const prod = emissoes.find((e) => e.solicitacao_id === imp.solicitacao_id && e.ambiente === "PRODUCAO");
                  const ocupado = busy === imp.id;
                  const ativa = imp.status !== "CANCELADA" && imp.status !== "CONCLUIDA";
                  const homAutorizada = hom?.status === "AUTORIZADA";
                  const podeHomologar = ativa && Boolean(imp.solicitacao_id) && !prod && (!hom || ["RASCUNHO", "REJEITADA", "ERRO"].includes(hom.status));
                  const podeProduzir = ativa && homAutorizada && !imp.teste && (!prod || ["RASCUNHO", "REJEITADA", "ERRO"].includes(prod.status));
                  const podeCancelar = ativa && (!prod || ["REJEITADA", "ERRO"].includes(prod.status));
                  const perfilCodigo = imp.dados_json?.perfil_codigo ?? null;
                  const linkPerfil = perfilCodigo && imp.solicitacao_id && !perfisLiberados.includes(`${perfilCodigo}|${imp.solicitacao_id}`)
                    ? `/faturamento/perfis?perfil=${encodeURIComponent(perfilCodigo)}&solicitacao=${imp.solicitacao_id}&retorno=/faturamento/operacoes?aba=IMPORTACAO`
                    : null;
                  const pendencias = imp.dados_json?.estoque_pendencias ?? [];
                  const ap = imp.dados_json?.ap;
                  return (
                    <tr key={imp.id} className="align-top">
                      <td className="py-2 pr-2"><div>AWB <span className="font-mono text-xs">{imp.awb}</span></div><div className="text-xs text-zinc-500">DIR {imp.dir_numero} de {dataBR(imp.dir_data_registro)} · {imp.courier_nome ?? "courier"}</div><div className="text-xs text-zinc-500">{imp.exportador_nome}</div></td>
                      <td className="py-2 pr-2 text-xs">{itensDa(imp.id).map((i) => <div key={`${imp.id}-${i.ordem}`}>{i.codigo} · {qtd(i.quantidade)} {i.unidade} · NCM {i.ncm}{i.custo_unitario != null ? ` · custo R$ ${qtd(i.custo_unitario, 2)}` : ""}</div>)}</td>
                      <td className="py-2 pr-2">{imp.cfop}</td>
                      <td className="py-2 pr-2 text-right tabular-nums whitespace-nowrap"><div>R$ {formatMoneyBR(numero(imp.valor_nota))}</div><div className="text-xs text-zinc-500">II {formatMoneyBR(numero(imp.ii_valor))} · ICMS {formatMoneyBR(numero(imp.icms_valor))}</div></td>
                      <td className="py-2 pr-2">
                        <div>{statusRotulo(imp.status)}</div>
                        {imp.teste ? <span className="mt-1 inline-block rounded-full border border-sky-800 px-2 py-0.5 text-xs text-sky-300">TESTE de homologação</span> : null}
                        {imp.status === "CONCLUIDA" && (imp.dados_json?.estoque_movimentacoes?.length ?? 0) > 0 ? <span className="mt-1 inline-block rounded-full border border-emerald-800 px-2 py-0.5 text-xs text-emerald-300">estoque lançado</span> : null}
                        {pendencias.length > 0 ? <div className="mt-1 text-xs text-amber-300" title={pendencias.map((p) => `${p.codigo ?? "?"}: ${p.motivo ?? ""}`).join("; ")}>estoque pendente: {pendencias.map((p) => p.codigo).join(", ")}</div> : null}
                        {ap?.reembolso?.titulo_id ? (
                          <div className="mt-1 text-xs text-sky-300" title={`Título do reembolso ${ap.reembolso.titulo_id}`}>nota de débito {imp.nota_debito_numero ?? ""} paga pelo sócio: título da UPS cancelado, reembolso de R$ {formatMoneyBR(numero(ap.reembolso.valor))} no contas a pagar{ap.reembolso.status ? ` (${ap.reembolso.status.toLowerCase()})` : ""}</div>
                        ) : ap?.titulo_id ? <div className="mt-1 text-xs text-emerald-300">nota de débito {imp.nota_debito_numero ?? ""} no contas a pagar{ap.pagamento_id ? " (baixada)" : ap.titulo_status === "CANCELADO" ? " (cancelada)" : " (aprovada)"}{ap.criado === false ? " · já existia" : ""}</div> : null}
                        {ap?.erro ? <div className="mt-1 text-xs text-red-300" title={ap.erro}>contas a pagar pendente: {ap.erro}</div> : null}
                        {imp.dados_json?.icms_credito?.status === "PENDENTE_CONTADORA" ? <div className="mt-1 text-xs text-amber-300" title={imp.dados_json.icms_credito.motivo ?? ""}>crédito de ICMS R$ {formatMoneyBR(numero(imp.dados_json.icms_credito.valor))} pendente de aprovação da contadora</div> : null}
                        {(imp.dados_json?.fiscal_itens?.length ?? 0) > 0 ? <div className="mt-1 text-xs text-zinc-400">{imp.dados_json?.fiscal_itens?.some((f) => f.erro) ? `equiparação a industrial com erro: ${imp.dados_json?.fiscal_itens?.map((f) => f.erro).filter(Boolean).join("; ")}` : "item marcado como importado pela Segau (origem 1, equiparado a industrial)"}</div> : null}
                        {imp.dados_json?.uso_proprio ? <div className="mt-1 text-xs text-zinc-500">uso próprio ({imp.dados_json.uso_proprio})</div> : null}
                        {imp.status === "CANCELADA" && imp.dados_json?.cancelamento?.motivo ? <div className="mt-1 text-xs text-zinc-500">{imp.dados_json.cancelamento.motivo}</div> : null}
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
                              <Link href={`/faturamento/nfe/${e.documento_fiscal_id}?retorno=/faturamento/operacoes?aba=IMPORTACAO`} className="underline">Ciclo de vida</Link>
                            </> : null}
                          </div>
                        ))}
                        {!hom && !prod ? <span className="text-zinc-500">—</span> : null}
                      </td>
                      <td className="py-2 pr-2 text-xs">
                        {anexosDa(imp.id).map((a) => <div key={a.id}><button type="button" className="underline" disabled={busy === a.id} onClick={() => void abrirAnexo(a)}>{TIPOS_ANEXO.find(([v]) => v === a.tipo)?.[1] ?? a.tipo.replace("_", " ")}: {a.nome_arquivo}</button></div>)}
                        {ativa || imp.status === "CONCLUIDA" ? (
                          <div className="mt-1 flex flex-wrap items-center gap-1">
                            <select aria-label={`Tipo do anexo da importação ${imp.dir_numero}`} className={`${field} px-2 py-1 text-xs`} value={anexoLista[imp.id] ?? "OUTRO"} onChange={(e) => setAnexoLista((s) => ({ ...s, [imp.id]: e.target.value }))}>{TIPOS_ANEXO.map(([v, r]) => <option key={v} value={v}>{r}</option>)}</select>
                            <input aria-label={`Anexar arquivo à importação ${imp.dir_numero}`} type="file" className="max-w-[160px] text-xs text-zinc-400" disabled={ocupado} onChange={(e) => { const f = e.target.files?.[0] ?? null; e.target.value = ""; void anexarNaLista(imp, f); }} />
                          </div>
                        ) : null}
                      </td>
                      <td className="py-2 text-right">
                        <div className="flex flex-col items-end gap-1">
                          {podeHomologar ? <button type="button" className={button} disabled={ocupado} onClick={() => void emitirHomologacao(imp)}>{hom ? "Tentar homologação de novo" : "Emitir em homologação"}</button> : null}
                          {ativa && homAutorizada && linkPerfil ? <Link href={linkPerfil} className={button}>Liberar perfil para produção</Link> : null}
                          {podeProduzir ? <button type="button" className="rounded-md bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50" disabled={ocupado} onClick={() => void emitirProducao(imp)}>Emitir NF-e real (produção)</button> : null}
                          {podeCancelar ? <button type="button" className="text-xs text-red-300 underline" disabled={ocupado} onClick={() => void cancelar(imp)}>Cancelar importação</button> : null}
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
