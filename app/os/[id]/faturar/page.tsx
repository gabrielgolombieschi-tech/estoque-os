"use client";

import { ratearParcelas } from "@/lib/faturamento/parcelas";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { formatMoneyBR } from "@/lib/decimal";
import { emailPadraoCliente, emailsDoCadastro, separarEmails, type ContatoNfe } from "@/lib/nfe/emailsCliente";
import FaturarNfseOs, { type PerfilServico } from "./FaturarNfseOs";

const R$ = (value: number) => `R$ ${formatMoneyBR(value)}`;

/**
 * Faturar OS: NF-e de industrializacao (5101/6101) em HOMOLOGACAO.
 *
 * Ordem da tela = ordem de execucao: cabecalho -> linhas -> operacao ->
 * pagamento/entrega -> previa -> emissao. Nada aqui grava CFOP, CST, IPI ou
 * origem por deducao: os campos fiscais vem de f.fn_os_nfe_conferir_homologacao
 * (fixture provisoria + cadastro fiscal do produto) e qualquer lacuna volta
 * como bloqueio nomeando linha e campo.
 */

type Os = {
  id: number;
  numero_os: string | null;
  cliente_id: number | null;
  cliente_nome: string | null;
  descricao_servico: string | null;
  status_fluxo: string | null;
  status?: string | null;
  orcado: number | string | null;
  pedido_compra?: string | null;
  tipo_pedido?: string | null;
  usa_relatorio_hh?: boolean | null;
};
type Cliente = {
  id: number; nome: string; razao_social: string | null; documento: string | null; inscricao_estadual: string | null;
  indicador_ie: string | null; cidade: string | null; uf: string | null; codigo_ibge_municipio: string | null;
  // Transportadora que este cliente costuma usar, gravada na ultima nota dele
  // (public.clientes.transportador_padrao_*). O painel da OV ja sugeria; aqui a
  // pessoa redigitava tudo a cada OS.
  transportador_padrao_nome: string | null; transportador_padrao_documento: string | null;
  transportador_padrao_ie: string | null; transportador_padrao_endereco: string | null;
  transportador_padrao_municipio: string | null; transportador_padrao_uf: string | null;
  transportador_padrao_modalidade_frete: number | null;
};
type Saldo = { valor_pedido: number | string; valor_faturado: number | string; valor_reservado: number | string; saldo: number | string; usa_relatorio_hh: boolean };
// cst_ipi/aliquota_ipi vem do cadastro fiscal do item (f.fn_faturamento_buscar_itens):
// e o que deixa a composicao ja somar o IPI, antes de conferir.
type Produto = { id: number; codigo: string; nome: string; unidade: string | null; valor_unitario: number | string | null; cst_ipi?: string | null; aliquota_ipi?: number | string | null; peso_liquido?: number | string | null; peso_bruto?: number | string | null };
// Grupo vol (X26) da NF-e. Espécie, marca e numeração são opcionais; peso, não.
type Volume = { quantidade: string; especie: string; marca: string; numeracao: string; peso_liquido: string; peso_bruto: string };
type Transportador = { nome: string; documento: string; inscricao_estadual: string; endereco: string; municipio: string; uf: string };
const MODALIDADES_FRETE: Array<[string, string]> = [
  ["9", "9 · Sem frete"],
  ["0", "0 · Por conta do emitente (CIF)"],
  ["1", "1 · Por conta do destinatário (FOB)"],
  ["2", "2 · Por conta de terceiros"],
  ["3", "3 · Transporte próprio, por conta do remetente"],
  ["4", "4 · Transporte próprio, por conta do destinatário"],
];
type Linha = { chave: number; produto: Produto | null; busca: string; resultados: Produto[]; buscou: string | null; descricao: string; quantidade: string; valor_unitario: string };
type Parcela = { dias: string; valor: string };
type Perfil = {
  id: string; codigo: string; nome: string; modelo: string; item_servico: string | null; cfop_interno: string | null; cfop_externo: string | null; faixa_automacao: string; habilitado_producao: boolean; vigencia_inicio: string | null; vigencia_fim: string | null; justificativa_faixa: string | null; natureza_operacao: string;
  revisao_fiscal_em: string | null; codigo_tributacao_nacional: string | null; codigo_nbs: string | null; aliquota_iss: number | string | null; local_prestacao_regra: string | null; incidencia_iss_regra: string | null;
  iss_retido_regra: string | null; retencao_pcc_regra: string | null; retencao_irrf_regra: string | null; retencao_inss_regra: string | null;
  codigo_indicador_operacao: string | null; excecao_conserto_isolado: boolean | null; campos_conferir: Array<{ campo: string; motivo: string; prazo?: string }> | null;
  permite_deducao_material: boolean | null; destinacoes_mercadoria: string[] | null; aliquota_icms: number | string | null;
};
type Nota = { documento_fiscal_id: string; solicitacao_id: string | null; solicitacao_status: string | null; modelo: string; ambiente: string; emissao_status: string; nfe_status: string | null; serie: string | null; numero: string | null; chave_acesso: string | null; valor_total: number | string | null; autorizado_em: string | null; danfe_path: string | null; xml_path: string | null; referencia_externa: string; created_at: string };
type Solicitacao = {
  id: string; status: string; natureza_operacao: string; observacao: string | null; created_at: string;
  destinacao_mercadoria: string | null; presenca_comprador: number | null; modalidade_frete: number | null;
  pagamento_forma: string | null; pagamento_indicador: number | null; pagamento_descricao: string | null;
  pagamento_parcelas: Array<{ dias: number | string; valor: number | string | null }> | null; pedido_cliente: string | null;
};
type Emissao = { solicitacao_id: string; documento_fiscal_id: string; status: string; ambiente: string; chave_acesso: string | null; numero: number | null; serie: number | null; mensagem: string | null; codigo_status: number | null; danfe_path: string | null; xml_path: string | null };
type ProducaoStatus = { pronta?: boolean; motivo?: string | null; preflight_confirmacao_pronto?: boolean; resumo_confirmacao?: { nome_destinatario?: string; documento_destinatario_mascarado?: string | null; valor_total?: number | string; contexto_hash?: string } | null };
type ItemConferido = { ordem: number; descricao: string; quantidade: number | string; valor_unitario: number | string; cfop: string | null; aliquota_icms: number | string | null; aliquota_ipi: number | string | null; cst_ipi: string | null; aliquota_pis: number | string | null; aliquota_cofins: number | string | null; ncm: string | null; origem_mercadoria: number | null; tributacao_fonte: string | null };
type Pendencia = { entidade?: string; id?: unknown; campo?: string; mensagem?: string; rota?: string };

const DESTINACOES: Array<[string, string, number]> = [
  ["USO_CONSUMO", "Uso e consumo próprio", 17],
  ["ATIVO_IMOBILIZADO", "Vai para o ativo imobilizado", 17],
  ["REVENDA", "Vai revender", 12],
  ["INSUMO", "Vai usar como insumo de produção", 12],
  ["MANUTENCAO", "Vai usar em manutenção", 12],
  ["CONSIGNADO", "Recebe em consignação", 12],
];
const FORMAS_PAGAMENTO: Array<[string, string]> = [
  ["15", "15 · Boleto bancário"], ["01", "01 · Dinheiro"], ["03", "03 · Cartão de crédito"], ["04", "04 · Cartão de débito"],
  ["17", "17 · PIX"], ["18", "18 · Transferência bancária"], ["05", "05 · Crédito loja"], ["99", "99 · Outros"],
];
const PAPEIS_FATURAR = ["FATURAMENTO", "FINANCEIRO", "ADMIN", "DIRETOR"];

const field = "w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500 disabled:opacity-60";
const label = "block text-xs text-zinc-400";
const botao = "rounded-md border border-zinc-700 px-3 py-2 text-sm hover:bg-zinc-900 disabled:cursor-not-allowed disabled:opacity-40";

function num(value: unknown) {
  if (value === null || value === undefined || value === "") return 0;
  const n = typeof value === "number" ? value : Number(String(value).replace(/\./g, "").replace(",", "."));
  return Number.isFinite(n) ? n : 0;
}
function paraNumero(value: string) {
  const s = value.trim().replace(/\./g, "").replace(",", ".");
  if (!s) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}
function decimal(value: unknown) {
  if (value === null || value === undefined || String(value).trim() === "") return "";
  return String(value).replace(".", ",");
}
function textoErro(cause: unknown) {
  if (cause instanceof Error) return cause.message;
  if (cause && typeof cause === "object" && "message" in cause) return String((cause as { message: unknown }).message);
  return String(cause);
}
async function erroFunction(cause: unknown) {
  if (cause && typeof cause === "object" && "context" in cause) {
    const response = (cause as { context?: unknown }).context;
    if (response instanceof Response) {
      try {
        const body = await response.clone().json() as { erro?: string; error?: string; codigo?: string | number };
        const msg = body.erro ?? body.error;
        if (msg) return body.codigo ? `cStat ${body.codigo} · ${msg}` : msg;
      } catch { /* mensagem padrao abaixo */ }
    }
  }
  return textoErro(cause);
}

export default function FaturarOsPage() {
  const params = useParams<{ id: string }>();
  const osId = Number(params?.id);
  const supabase = useMemo(() => supabaseBrowser(), []);
  const te = useTenantEmpresa();
  const tenantId = te.tenantId ?? null;
  const empresaId = te.empresa?.id ?? null;
  const papel = useMemo(() => {
    const byId = (te.empresas ?? []).find((e) => e.id === empresaId) ?? null;
    return String(byId?.papel ?? te.empresa?.papel ?? "").trim().toUpperCase();
  }, [empresaId, te.empresa, te.empresas]);
  const podeFaturar = PAPEIS_FATURAR.includes(papel);

  const [os, setOs] = useState<Os | null>(null);
  const [cliente, setCliente] = useState<Cliente | null>(null);
  const [saldo, setSaldo] = useState<Saldo | null>(null);
  const [custoReal, setCustoReal] = useState<{ materiais: number; despesas: number; maoObra: number; impostos: number; total: number } | null>(null);
  const [perfis, setPerfis] = useState<Perfil[]>([]);
  const [fixturePendencia, setFixturePendencia] = useState<string | null>(null);
  const [notas, setNotas] = useState<Nota[]>([]);
  const [solicitacao, setSolicitacao] = useState<Solicitacao | null>(null);
  const [emissao, setEmissao] = useState<Emissao | null>(null);
  const [itensConferidos, setItensConferidos] = useState<ItemConferido[]>([]);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [bloqueios, setBloqueios] = useState<Array<{ texto: string; rota?: string }>>([]);
  const [ocupado, setOcupado] = useState(false);

  const [linhas, setLinhas] = useState<Linha[]>([]);
  const [proximaChave, setProximaChave] = useState(2);
  const [pedidoCliente, setPedidoCliente] = useState("");
  const [destinacao, setDestinacao] = useState("");
  const [presenca, setPresenca] = useState("9");
  const [modalidadeFrete, setModalidadeFrete] = useState("9");
  const [transportador, setTransportador] = useState<Transportador>({ nome: "", documento: "", inscricao_estadual: "", endereco: "", municipio: "", uf: "" });
  const [volumes, setVolumes] = useState<Volume[]>([]);
  const [pagamentoForma, setPagamentoForma] = useState("15");
  const [pagamentoIndicador, setPagamentoIndicador] = useState("1");
  const [pagamentoDescricao, setPagamentoDescricao] = useState("");
  const [parcelas, setParcelas] = useState<Parcela[]>([{ dias: "30", valor: "" }]);
  const [observacao, setObservacao] = useState("");
  const [conferida, setConferida] = useState(false);

  const [criandoProduto, setCriandoProduto] = useState<number | null>(null);
  const [novoProduto, setNovoProduto] = useState({ nome: "", ncm: "", origem: "", unidade: "UN", cst_ipi: "", aliquota_ipi: "" });
  // Modelo da nota: NF-e (industrializacao) ou NFS-e (servico, perfil escolhido no cabecalho).
  const [operacaoSel, setOperacaoSel] = useState("NFE");
  const [versao, setVersao] = useState(0);
  const [temRascunhoNfse, setTemRascunhoNfse] = useState(false);
  const [empresaIbge, setEmpresaIbge] = useState<string | null>(null);
  const modelo = operacaoSel.startsWith("NFSE:") ? "NFSE" : "NFE";
  const perfisServico = useMemo<PerfilServico[]>(() => perfis.filter((p) => p.modelo === "NFSE").map((p) => ({
    id: p.id, codigo: p.codigo, nome: p.nome, item_servico: p.item_servico, faixa_automacao: p.faixa_automacao, habilitado_producao: p.habilitado_producao, justificativa_faixa: p.justificativa_faixa, vigencia_inicio: p.vigencia_inicio, vigencia_fim: p.vigencia_fim,
    revisao_fiscal_em: p.revisao_fiscal_em, codigo_tributacao_nacional: p.codigo_tributacao_nacional, codigo_nbs: p.codigo_nbs, aliquota_iss: p.aliquota_iss, local_prestacao_regra: p.local_prestacao_regra, incidencia_iss_regra: p.incidencia_iss_regra,
    iss_retido_regra: p.iss_retido_regra, retencao_pcc_regra: p.retencao_pcc_regra, retencao_irrf_regra: p.retencao_irrf_regra, retencao_inss_regra: p.retencao_inss_regra,
    codigo_indicador_operacao: p.codigo_indicador_operacao, excecao_conserto_isolado: p.excecao_conserto_isolado, campos_conferir: p.campos_conferir,
    permite_deducao_material: p.permite_deducao_material,
  })), [perfis]);
  const perfilServico = useMemo(() => perfisServico.find((p) => `NFSE:${p.id}` === operacaoSel) ?? null, [operacaoSel, perfisServico]);
  // Props do componente de NFS-e memoizadas: referencia nova a cada render dispararia o carregamento em loop.
  const osNfse = useMemo(() => os ? { id: os.id, numero_os: os.numero_os, cliente_id: os.cliente_id, descricao_servico: os.descricao_servico, status_fluxo: os.status_fluxo, pedido_compra: os.pedido_compra } : null, [os]);
  const clienteNfse = useMemo(() => cliente ? { id: cliente.id, uf: cliente.uf, codigo_ibge_municipio: cliente.codigo_ibge_municipio } : null, [cliente]);

  const totalLinhas = useMemo(() => linhas.reduce((acc, l) => acc + (paraNumero(l.quantidade) ?? 0) * (paraNumero(l.valor_unitario) ?? 0), 0), [linhas]);
  // IPI previsto ja na composicao, pelo cadastro fiscal do produto vinculado. A nota
  // vai para a SEFAZ com o imposto por fora, entao a linha precisa mostrar o total
  // que sera emitido — nao so a mercadoria — para bater com o saldo da OS, que
  // conta o IPI desde a migration 20260909120000. Mesmo arredondamento do builder:
  // por item, duas casas.
  const ipiLinhas = useMemo(() => linhas.reduce((acc, l) => {
    // Number direto, e nao num(): a aliquota chega do banco como decimal com ponto
    // ("9.7500") e num() trata ponto como separador de milhar.
    const aliquota = Number(l.produto?.aliquota_ipi ?? 0);
    if (!["00", "49", "50", "99"].includes(String(l.produto?.cst_ipi ?? "")) || !Number.isFinite(aliquota) || aliquota <= 0) return acc;
    const base = Math.round((paraNumero(l.quantidade) ?? 0) * (paraNumero(l.valor_unitario) ?? 0) * 100) / 100;
    return acc + Math.round(base * aliquota) / 100;
  }, 0), [linhas]);
  const saldoDisponivel = num(saldo?.saldo);
  const ambito = cliente?.uf && cliente.uf.toUpperCase() === "SC" ? "INTERNA" : "INTERESTADUAL";
  const cfop = ambito === "INTERNA" ? "5101" : "6101";
  // A conferencia escolhe o perfil tambem pela destinacao declarada (17% consumidor final,
  // 12% contribuinte que revende/usa como insumo/manutencao). Sem esse filtro o quadro
  // mostraria os dois perfis 5101 como se qualquer um valesse para a nota em curso.
  const hoje = new Date().toISOString().slice(0, 10);
  const perfisDoCfop = perfis.filter((p) => p.modelo !== "NFSE" && (ambito === "INTERNA" ? p.cfop_interno === "5101" : p.cfop_externo === "6101"));
  const perfisDaDestinacao = perfisDoCfop.filter((p) => p.faixa_automacao !== "BLOQUEADO" && (!destinacao || !p.destinacoes_mercadoria?.length || p.destinacoes_mercadoria.includes(destinacao)));
  // Mesma regra da conferencia (fn_os_nfe_conferir_homologacao): so entra perfil com revisao
  // fiscal salva e dentro da vigencia. Um perfil em REVISAO sem revisao salva existe, mas a
  // nota ainda cai na fixture — por isso ele aparece como pendente, com o caminho para liberar.
  const perfisVigentes = perfisDaDestinacao.filter((p) => Boolean(p.revisao_fiscal_em) && (!p.vigencia_inicio || p.vigencia_inicio <= hoje) && (!p.vigencia_fim || p.vigencia_fim >= hoje));
  const perfisPendentes = perfisDaDestinacao.filter((p) => !perfisVigentes.includes(p));
  const perfisBloqueados = perfisDoCfop.filter((p) => !perfisDaDestinacao.includes(p));
  const retornoFaturar = `/os/${osId}/faturar`;
  // A liberacao de producao e por solicitacao: f.fn_nfe_producao_pronta so abre o portao
  // quando o perfil aponta para ESTA solicitacao e para o documento dela em homologacao.
  // Sem levar o id daqui, a tela de perfis abria com o campo "solicitacao homologada"
  // vazio e o operador tinha de achar o UUID na mao — quando errava, liberava para outra
  // solicitacao e a producao continuava barrada sem dizer por que.
  const linkPerfil = (codigo?: string) => {
    const partes = [
      ...(codigo ? [`perfil=${encodeURIComponent(codigo)}`] : []),
      ...(solicitacao?.id ? [`solicitacao=${encodeURIComponent(solicitacao.id)}`] : []),
      `retorno=${encodeURIComponent(retornoFaturar)}`,
    ];
    return `/faturamento/perfis?${partes.join("&")}`;
  };
  const motivoPendente = (p: Perfil) => !p.revisao_fiscal_em ? "sem revisão fiscal salva" : p.vigencia_inicio && p.vigencia_inicio > hoje ? `vigência a partir de ${p.vigencia_inicio}` : "vigência encerrada";
  const osInterna = useMemo(() => /segau/i.test(cliente?.razao_social ?? cliente?.nome ?? "") && /el[eé]trica/i.test(cliente?.razao_social ?? cliente?.nome ?? ""), [cliente]);
  const osCancelada = String(os?.status_fluxo ?? os?.status ?? "").toLowerCase() === "cancelada";
  const osFaturada = String(os?.status_fluxo ?? "").toLowerCase() === "faturada";
  const motivoBloqueioOs = !podeFaturar ? "Seu papel não fatura OS." : osCancelada ? "OS cancelada." : osInterna ? "OS interna (cliente Elétrica Segau) não emite NF-e por este fluxo." : osFaturada ? "OS já faturada." : saldo && saldoDisponivel <= 0 && !solicitacao && !temRascunhoNfse ? "Saldo a faturar zerado." : null;

  const carregar = useCallback(async () => {
    if (!tenantId || !empresaId || !Number.isInteger(osId) || osId <= 0) return;
    setCarregando(true);
    setErro(null);
    try {
      const { data: detalhe, error: erroDetalhe } = await supabase.rpc("get_os_detail_operacional", { p_tenant_id: tenantId, p_empresa_id: empresaId, p_os_id: osId });
      if (erroDetalhe) throw erroDetalhe;
      const payload = (detalhe ?? {}) as Record<string, unknown>;
      const osRow = payload.os as Os | undefined;
      if (!osRow?.id) throw new Error("Ordem de serviço não encontrada para a empresa ativa.");
      setOs(osRow);
      setPedidoCliente((atual) => atual || (osRow.pedido_compra ?? ""));
      const rows = Array.isArray(payload.itens) ? payload.itens as Array<{ valor_total?: unknown; itens?: { tipo?: string } | null }> : [];
      const materiais = rows.filter((r) => r.itens?.tipo === "produto").reduce((s, r) => s + num(r.valor_total), 0);
      const despesas = rows.filter((r) => r.itens?.tipo === "despesa").reduce((s, r) => s + num(r.valor_total), 0);
      const maoObra = num(payload.custo_mao_obra);
      const orcado = num(osRow.orcado);
      const impostos = osRow.usa_relatorio_hh ? num(payload.total_hh) * 0.15 : osRow.tipo_pedido === "material" ? orcado * 0.27 : orcado * 0.15;
      setCustoReal({ materiais, despesas, maoObra, impostos, total: materiais + despesas + maoObra + impostos });

      let clienteRow: Cliente | null = null;
      if (osRow.cliente_id) {
        const { data: cli } = await supabase.from("clientes").select("id,nome,razao_social,documento,inscricao_estadual,indicador_ie,cidade,uf,codigo_ibge_municipio,transportador_padrao_nome,transportador_padrao_documento,transportador_padrao_ie,transportador_padrao_endereco,transportador_padrao_municipio,transportador_padrao_uf,transportador_padrao_modalidade_frete").eq("id", osRow.cliente_id).maybeSingle();
        clienteRow = (cli as Cliente | null) ?? null;
        setCliente(clienteRow);
      }
      const { data: saldoData, error: erroSaldo } = await supabase.schema("f").rpc("fn_os_saldo_a_faturar", { p_tenant_id: tenantId, p_empresa_id: empresaId, p_os_id: osId });
      if (erroSaldo) throw erroSaldo;
      const saldoRow = (Array.isArray(saldoData) ? saldoData[0] : saldoData) as Saldo | null;
      setSaldo(saldoRow);
      const { data: notasData } = await supabase.schema("f").rpc("fn_os_notas", { p_tenant_id: tenantId, p_empresa_id: empresaId, p_os_id: osId });
      setNotas((notasData as Nota[] | null) ?? []);
      const { data: perfisData } = await supabase.schema("f").from("perfil_operacao").select("id,codigo,nome,modelo,item_servico,cfop_interno,cfop_externo,faixa_automacao,habilitado_producao,vigencia_inicio,vigencia_fim,justificativa_faixa,natureza_operacao,revisao_fiscal_em,codigo_tributacao_nacional,codigo_nbs,aliquota_iss,local_prestacao_regra,incidencia_iss_regra,iss_retido_regra,retencao_pcc_regra,retencao_irrf_regra,retencao_inss_regra,codigo_indicador_operacao,excecao_conserto_isolado,campos_conferir,permite_deducao_material,destinacoes_mercadoria,aliquota_icms").or("cfop_interno.eq.5101,cfop_externo.eq.6101,modelo.eq.NFSE").order("codigo");
      setPerfis((perfisData as Perfil[] | null) ?? []);
      const { data: ctxEmpresa } = await supabase.schema("f").rpc("fn_nfse_contexto_empresa", { p_empresa_id: empresaId });
      setEmpresaIbge((ctxEmpresa as { codigo_municipio_ibge?: string | null } | null)?.codigo_municipio_ibge ?? null);
      const { data: fixtureData } = await supabase.schema("f").from("tributacao_provisoria_homologacao").select("cfop,pendencia_contador,fonte").in("cfop", ["5101", "6101"]);
      const fx = (fixtureData as Array<{ cfop: string; pendencia_contador: string | null; fonte: string | null }> | null)?.[0];
      setFixturePendencia(fx?.pendencia_contador ?? null);

      // Rascunho ativo desta OS (nao cancelado), com a emissao mais recente.
      const { data: itensSol } = await supabase.schema("f").from("solicitacao_item").select("solicitacao_id,modelo,perfil_operacao_id").eq("origem_tipo", "OS").eq("origem_id", String(osId));
      const itensRows = (itensSol as Array<{ solicitacao_id: string; modelo: string | null; perfil_operacao_id: string | null }> | null) ?? [];
      const ids = Array.from(new Set(itensRows.filter((r) => (r.modelo ?? "NFE") !== "NFSE").map((r) => r.solicitacao_id)));
      // Rascunho de NFS-e em andamento: a tela abre no modelo de servico com o perfil dele.
      const idsNfse = Array.from(new Set(itensRows.filter((r) => r.modelo === "NFSE").map((r) => r.solicitacao_id)));
      setTemRascunhoNfse(false);
      if (idsNfse.length > 0) {
        const { data: solsNfse } = await supabase.schema("f").from("solicitacao_faturamento").select("id,status,perfil_operacao_id,created_at").in("id", idsNfse).neq("status", "CANCELADA").order("created_at", { ascending: false }).limit(5);
        const candNfse = (solsNfse as Array<{ id: string; status: string; perfil_operacao_id: string | null }> | null) ?? [];
        if (candNfse.length > 0) {
          const { data: emsNfse } = await supabase.schema("f").from("documento_fiscal_emissao").select("solicitacao_id,status").in("solicitacao_id", candNfse.map((c) => c.id));
          const emNfse = (emsNfse as Array<{ solicitacao_id: string; status: string }> | null) ?? [];
          const rascunhoNfse = candNfse.find((c) => { const e = emNfse.find((x) => x.solicitacao_id === c.id); return !e || !["CANCELADA"].includes(e.status); });
          if (rascunhoNfse?.perfil_operacao_id) setOperacaoSel((atual) => atual === "NFE" ? `NFSE:${rascunhoNfse.perfil_operacao_id}` : atual);
          setTemRascunhoNfse(Boolean(rascunhoNfse));
        }
      }
      // Retoma so o rascunho que ainda nao chegou a AUTORIZADA: nota autorizada
      // (parcial) fica na lista de notas e a tela abre uma nova composicao.
      let ativa: Solicitacao | null = null;
      let emissaoAtiva: Emissao | null = null;
      if (ids.length > 0) {
        const { data: sols } = await supabase.schema("f").from("solicitacao_faturamento").select("id,status,natureza_operacao,observacao,created_at,destinacao_mercadoria,presenca_comprador,modalidade_frete,pagamento_forma,pagamento_indicador,pagamento_descricao,pagamento_parcelas,pedido_cliente").in("id", ids).neq("status", "CANCELADA").order("created_at", { ascending: false }).limit(5);
        const candidatas = (sols as Solicitacao[] | null) ?? [];
        if (candidatas.length > 0) {
          const { data: ems } = await supabase.schema("f").from("documento_fiscal_emissao").select("solicitacao_id,documento_fiscal_id,status,ambiente,chave_acesso,numero,serie,mensagem,codigo_status,danfe_path,xml_path").in("solicitacao_id", candidatas.map((c) => c.id)).order("created_at", { ascending: false });
          const emissoes = (ems as Emissao[] | null) ?? [];
          for (const candidata of candidatas) {
            const em = emissoes.find((e) => e.solicitacao_id === candidata.id) ?? null;
            if (!em || !["AUTORIZADA", "CANCELADA"].includes(em.status)) { ativa = candidata; emissaoAtiva = em; break; }
          }
          // Sem rascunho aberto: a homologacao AUTORIZADA que ainda nao virou nota real volta como ativa,
          // para a emissao em producao (perfil liberado) ou o abandono. Com nota real, abre composicao nova.
          if (!ativa) {
            for (const candidata of candidatas) {
              const emsCand = emissoes.filter((e) => e.solicitacao_id === candidata.id);
              const hom = emsCand.find((e) => e.ambiente === "HOMOLOGACAO" && e.status === "AUTORIZADA");
              const prod = emsCand.find((e) => e.ambiente === "PRODUCAO");
              if (hom && !prod && candidata.status !== "CANCELADA") { ativa = candidata; emissaoAtiva = hom; break; }
            }
          }
        }
      }
      setSolicitacao(ativa);
      if (ativa) {
        setEmissao(emissaoAtiva);
        // O rascunho ja conferido volta para a tela com o que foi confirmado.
        if (ativa.destinacao_mercadoria) setDestinacao(ativa.destinacao_mercadoria);
        if (ativa.presenca_comprador != null) setPresenca(String(ativa.presenca_comprador));
        if (ativa.modalidade_frete != null) setModalidadeFrete(String(ativa.modalidade_frete));
        if (ativa.pagamento_forma) setPagamentoForma(ativa.pagamento_forma);
        if (ativa.pagamento_indicador != null) setPagamentoIndicador(String(ativa.pagamento_indicador));
        setPagamentoDescricao(ativa.pagamento_descricao ?? "");
        if (Array.isArray(ativa.pagamento_parcelas) && ativa.pagamento_parcelas.length > 0) {
          setParcelas(ativa.pagamento_parcelas.map((p) => ({ dias: String(p.dias ?? ""), valor: decimal(p.valor) })));
        }
        if (ativa.observacao && !/^Emissao da OS|^Composi[cç][aã]o (parcial|livre)/i.test(ativa.observacao)) setObservacao(ativa.observacao);
        if (ativa.pedido_cliente) setPedidoCliente(ativa.pedido_cliente);
        const { data: its } = await supabase.schema("f").from("solicitacao_item").select("ordem,descricao,quantidade,valor_unitario,cfop,aliquota_icms,aliquota_ipi,cst_ipi,aliquota_pis,aliquota_cofins,ncm,origem_mercadoria,tributacao_fonte").eq("solicitacao_id", ativa.id).order("ordem");
        setItensConferidos((its as ItemConferido[] | null) ?? []);
        setConferida(Boolean(((its as ItemConferido[] | null) ?? [])[0]?.cfop));
      } else {
        setEmissao(null);
        setItensConferidos([]);
        setConferida(false);
        // Rascunho novo: a transportadora do cliente entra como sugestao, igual ao
        // painel da OV. Sugerir nao e confirmar — os campos seguem editaveis e a
        // conferencia continua sendo de quem fatura.
        const padraoNome = String(clienteRow?.transportador_padrao_nome ?? "").trim();
        if (padraoNome) {
          setTransportador({
            nome: padraoNome,
            documento: String(clienteRow?.transportador_padrao_documento ?? ""),
            inscricao_estadual: String(clienteRow?.transportador_padrao_ie ?? ""),
            endereco: String(clienteRow?.transportador_padrao_endereco ?? ""),
            municipio: String(clienteRow?.transportador_padrao_municipio ?? ""),
            uf: String(clienteRow?.transportador_padrao_uf ?? ""),
          });
          if (clienteRow?.transportador_padrao_modalidade_frete != null) {
            setModalidadeFrete(String(clienteRow.transportador_padrao_modalidade_frete));
          }
        }
        setLinhas((atuais) => atuais.length > 0 ? atuais : [{
          chave: 1, produto: null, busca: "", resultados: [], buscou: null,
          descricao: osRow.descricao_servico ?? `OS ${osRow.numero_os ?? osRow.id}`,
          quantidade: "1", valor_unitario: decimal(num(saldoRow?.saldo).toFixed(2)),
        }]);
      }
    } catch (cause) {
      setErro(textoErro(cause));
    } finally {
      setCarregando(false);
      setVersao((v) => v + 1);
    }
  }, [empresaId, osId, supabase, tenantId]);

  useEffect(() => { void carregar(); }, [carregar]);

  // Realtime: a emissao muda de estado sem recarregar a pagina.
  useEffect(() => {
    if (!empresaId) return;
    const channel = supabase.channel(`os-nfe-${empresaId}-${osId}`)
      .on("postgres_changes", { event: "*", schema: "f", table: "documento_fiscal_emissao", filter: `empresa_id=eq.${empresaId}` }, () => void carregar())
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [carregar, empresaId, osId, supabase]);
  useEffect(() => {
    if (!emissao || !["ENVIANDO", "PROCESSANDO"].includes(emissao.status)) return;
    const timer = window.setInterval(() => void carregar(), 5000);
    return () => window.clearInterval(timer);
  }, [carregar, emissao]);

  function atualizarLinha(chave: number, patch: Partial<Linha>) {
    setLinhas((atuais) => atuais.map((l) => (l.chave === chave ? { ...l, ...patch } : l)));
  }
  async function buscarProduto(chave: number) {
    const linha = linhas.find((l) => l.chave === chave);
    if (!linha || !tenantId || !empresaId) return;
    const { data, error } = await supabase.schema("f").rpc("fn_faturamento_buscar_itens", { p_tenant_id: tenantId, p_empresa_id: empresaId, p_termo: linha.busca, p_limite: 12 });
    if (error) { setErro(error.message); return; }
    // Guarda o termo pesquisado: sem isso a busca sem resultado nao renderiza nada
    // e a tela fica muda, como se o botao nao tivesse funcionado.
    atualizarLinha(chave, { resultados: (data as Produto[] | null) ?? [], buscou: linha.busca });
  }
  async function criarProdutoDaOs(chave: number) {
    if (!os) return;
    setOcupado(true); setErro(null);
    try {
      const { data, error } = await supabase.rpc("criar_item_fabricado_da_os", {
        p_os_id: os.id, p_nome: novoProduto.nome, p_ncm: novoProduto.ncm, p_origem: novoProduto.origem === "" ? null : Number(novoProduto.origem),
        p_unidade: novoProduto.unidade, p_cst_ipi: novoProduto.cst_ipi, p_aliquota_ipi: paraNumero(novoProduto.aliquota_ipi), p_cenq: null,
      });
      if (error) throw error;
      const id = Number(data);
      atualizarLinha(chave, { produto: { id, codigo: `FAB-OS${os.numero_os ?? os.id}`, nome: novoProduto.nome.toUpperCase(), unidade: novoProduto.unidade, valor_unitario: null, cst_ipi: novoProduto.cst_ipi, aliquota_ipi: paraNumero(novoProduto.aliquota_ipi) }, resultados: [], buscou: null });
      setCriandoProduto(null);
      setAviso(`Produto fabricado ${id} criado com o cadastro fiscal completo e vinculado à linha.`);
    } catch (cause) { setErro(textoErro(cause)); } finally { setOcupado(false); }
  }

  function operacaoPayload() {
    return {
      destino_uf_confirmada: cliente?.uf ?? "",
      destinacao_mercadoria: destinacao,
      presenca_comprador: Number(presenca),
      modalidade_frete: Number(modalidadeFrete),
      // O builder só respeita a modalidade quando há transportador; sem ele a nota sai
      // como 9. Volumes com peso são exigidos por ele sempre que a modalidade não for 9.
      ...(modalidadeFrete !== "9" && transportador.nome.trim() ? {
        transportador: {
          nome: transportador.nome.trim(),
          documento: transportador.documento.replace(/\D/g, "") || null,
          inscricao_estadual: transportador.inscricao_estadual.trim() || null,
          endereco: transportador.endereco.trim() || null,
          municipio: transportador.municipio.trim() || null,
          uf: transportador.uf.trim().toUpperCase() || null,
        },
      } : {}),
      ...(modalidadeFrete !== "9" ? {
        volumes: volumes.map((v) => ({
          quantidade: paraNumero(v.quantidade),
          especie: v.especie.trim() || null,
          marca: v.marca.trim() || null,
          numeracao: v.numeracao.trim() || null,
          peso_liquido: paraNumero(v.peso_liquido),
          peso_bruto: paraNumero(v.peso_bruto),
        })),
      } : {}),
      valor_frete: 0, valor_seguro: 0, valor_outras_despesas: 0,
      pagamento_forma: pagamentoForma,
      pagamento_indicador: Number(pagamentoIndicador),
      pagamento_descricao: pagamentoDescricao || null,
      pagamento_parcelas: pagamentoIndicador === "1" ? parcelas.map((p, i) => ({ numero: String(i + 1).padStart(3, "0"), dias: Number(p.dias.trim()), valor: p.valor.trim() ? paraNumero(p.valor) : null })) : null,
      pedido_cliente: pedidoCliente.trim() || null,
      observacao: observacao.trim() || null,
    };
  }

  async function conferir() {
    if (!tenantId || !empresaId || !os) return;
    setOcupado(true); setErro(null); setAviso(null); setBloqueios([]);
    try {
      let solId = solicitacao?.id ?? null;
      if (!solId) {
        const invalida = linhas.findIndex((l) => !l.descricao.trim() || (paraNumero(l.quantidade) ?? 0) <= 0 || (paraNumero(l.valor_unitario) ?? 0) <= 0);
        if (invalida >= 0) throw new Error(`Linha ${invalida + 1}: descrição, quantidade e valor precisam estar preenchidos.`);
        const semProduto = linhas.findIndex((l) => !l.produto);
        if (semProduto >= 0) throw new Error(`Linha ${semProduto + 1}: vincule um produto fabricado ou crie um a partir da OS.`);
        // Compara o total que vai para a nota (mercadoria + IPI do cadastro), porque
        // e ele que o saldo da OS consome.
        if (totalLinhas + ipiLinhas > saldoDisponivel + 0.005) throw new Error(`Total da nota ${R$(totalLinhas + ipiLinhas)}${ipiLinhas > 0.005 ? ` (mercadoria ${R$(totalLinhas)} + IPI ${R$(ipiLinhas)})` : ""} acima do saldo da OS ${R$(saldoDisponivel)}.`);
        const { data, error } = await supabase.schema("f").rpc("fn_solicitacao_faturamento_criar_os_livre", {
          p_tenant_id: tenantId, p_empresa_id: empresaId, p_os_id: os.id,
          p_linhas: linhas.map((l) => ({ descricao: l.descricao.trim(), quantidade: paraNumero(l.quantidade), unidade: l.produto?.unidade || "UN", valor_unitario: paraNumero(l.valor_unitario), item_id: l.produto?.id ?? null })),
          p_natureza_operacao: ambito === "INTERNA" ? "VENDA_INDUSTRIALIZACAO_INTERNA" : "VENDA_INDUSTRIALIZACAO_INTERESTADUAL",
        });
        if (error) throw error;
        solId = String(data);
      }
      const { data: resultado, error: erroConferir } = await supabase.schema("f").rpc("fn_os_nfe_conferir_homologacao", { p_solicitacao_id: solId, p_operacao: operacaoPayload() });
      if (erroConferir) throw erroConferir;
      const r = resultado as { ok?: boolean; pendencias?: Pendencia[] } | null;
      if (!r?.ok) {
        setBloqueios((r?.pendencias ?? []).map((p) => ({ texto: `${p.entidade ?? "cadastro"} · ${p.campo ?? ""}: ${p.mensagem ?? ""}`, rota: p.rota })));
        setAviso("A conferência foi salva, mas o cadastro tem pendências. Corrija onde indicado e confira de novo.");
      } else {
        setAviso("Conferência salva: campos fiscais preenchidos pela fixture de homologação e pelo cadastro do produto. Revise a prévia e emita.");
      }
      await carregar();
    } catch (cause) {
      const msg = textoErro(cause);
      setBloqueios([{ texto: msg }]);
      setErro(msg);
    } finally { setOcupado(false); }
  }

  async function emitir() {
    if (!solicitacao) return;
    if (!window.confirm(`Emitir NF-e em HOMOLOGAÇÃO (sem valor fiscal) para a OS ${os?.numero_os ?? os?.id}?\n\nCFOP ${cfop} · total ${R$(itensConferidos.reduce((s, i) => s + num(i.quantidade) * num(i.valor_unitario), 0))}`)) return;
    setOcupado(true); setErro(null); setAviso(null);
    try {
      const { data, error } = await supabase.functions.invoke("nfe-emitir", { body: { solicitacao_id: solicitacao.id } });
      if (error) throw error;
      if (data?.erro) throw new Error(data.codigo ? `cStat ${data.codigo} · ${data.erro}` : String(data.erro));
      setAviso("Solicitação enviada à Focus em homologação. O saldo já está reservado; o retorno chega automaticamente.");
      await carregar();
    } catch (cause) { setErro(await erroFunction(cause)); await carregar(); } finally { setOcupado(false); }
  }

  // Producao (mesma disciplina da OV): a Edge Function confere a liberacao do perfil e monta o resumo
  // de confirmacao a partir do snapshot homologado; a emissao real exige o hash desse contexto.
  async function emitirProducao() {
    if (!solicitacao || !emissao) return;
    setOcupado(true); setErro(null); setAviso(null);
    try {
      const { data: statusData, error: statusError } = await supabase.functions.invoke("nfe-emitir-producao", { body: { acao: "STATUS", solicitacao_id: solicitacao.id } });
      if (statusError) throw statusError;
      const st = statusData as ProducaoStatus | null;
      const resumo = st?.resumo_confirmacao;
      if (!st?.pronta || !st.preflight_confirmacao_pronto || !resumo?.contexto_hash) throw new Error(st?.motivo ?? "A confirmação de produção não pôde ser montada a partir do snapshot homologado.");
      // Sem OC a nota e valida, mas o cliente costuma recusar o recebimento e a
      // cobranca trava — foi o que derrubou a NF-e 2/13 em 11/09/2026. Pergunta
      // antes da confirmacao da emissao real, para dar chance de desistir; nao
      // bloqueia, porque venda sem pedido formal existe.
      if (!(solicitacao.pedido_cliente ?? pedidoCliente ?? "").trim() && !window.confirm(
        "Esta nota vai sair SEM PEDIDO DE COMPRA do cliente.\n\n"
        + "A NF-e é válida assim, mas o cliente costuma recusar o recebimento sem a OC e a cobrança fica travada.\n\n"
        + "Deseja continuar mesmo sem o pedido de compra?",
      )) return;
      if (!window.confirm(`EMITIR NF-e REAL (produção) para a OS ${os?.numero_os ?? os?.id}?\n\nDestinatário: ${resumo.nome_destinatario ?? "?"} (${resumo.documento_destinatario_mascarado ?? "?"})\nTotal da nota: ${R$(num(resumo.valor_total))}\n\nGera documento fiscal válido e título a receber.`)) return;
      const { data, error } = await supabase.functions.invoke("nfe-emitir-producao", { body: { acao: "EMITIR", solicitacao_id: solicitacao.id, confirmacao_contexto_hash: resumo.contexto_hash } });
      if (error) throw error;
      if (data?.erro) throw new Error(data.codigo ? `cStat ${data.codigo} · ${data.erro}` : String(data.erro));
      setAviso("NF-e enviada à SEFAZ em PRODUÇÃO. O retorno chega automaticamente; a nota real aparece em \"Notas desta OS\".");
      await carregar();
    } catch (cause) { setErro(await erroFunction(cause)); await carregar(); } finally { setOcupado(false); }
  }

  async function descartarRascunho() {
    if (!solicitacao) return;
    const motivo = window.prompt("Motivo do descarte do rascunho (15 a 255 caracteres):", "Rascunho refeito pela tela de faturar a OS");
    if (!motivo) return;
    setOcupado(true); setErro(null);
    try {
      const rpc = emissao?.status === "AUTORIZADA" && emissao.ambiente === "HOMOLOGACAO" ? "fn_solicitacao_nfe_abandonar_homologacao" : "fn_solicitacao_nfe_cancelar_rascunho";
      const { error } = await supabase.schema("f").rpc(rpc, { p_solicitacao_id: solicitacao.id, p_motivo: motivo });
      if (error) throw error;
      setSolicitacao(null); setEmissao(null); setItensConferidos([]); setConferida(false); setLinhas([]);
      await carregar();
    } catch (cause) { setErro(textoErro(cause)); } finally { setOcupado(false); }
  }

  async function abandonarNota(nota: Nota) {
    const motivo = window.prompt("Motivo do abandono da homologação (15 a 255 caracteres). A NF-e de teste continua autorizada na SEFAZ; só o saldo da OS volta.", "Homologacao concluida; saldo devolvido a OS");
    if (!motivo) return;
    setOcupado(true); setErro(null);
    try {
      const { error } = await supabase.schema("f").rpc(nota.modelo === "NFSE" ? "fn_nfse_abandonar_homologacao" : "fn_solicitacao_nfe_abandonar_homologacao", { p_solicitacao_id: nota.solicitacao_id, p_motivo: motivo });
      if (error) throw error;
      setAviso(`Homologação ${nota.modelo === "NFSE" ? "NFS-e" : "NF-e"} ${nota.serie}/${nota.numero} abandonada; saldo devolvido à OS.`);
      await carregar();
    } catch (cause) { setErro(textoErro(cause)); } finally { setOcupado(false); }
  }

  async function abrirArquivoDoc(documentoFiscalId: string, arquivo: "XML" | "DANFE") {
    const { data, error } = await supabase.functions.invoke("nfe-ciclo", { body: { acao: "ARQUIVO", arquivo, documento_fiscal_id: documentoFiscalId, download: true } });
    if (error || data?.error) { setErro(data?.error ?? (await erroFunction(error))); return; }
    if (data?.url) window.location.assign(String(data.url));
  }
  async function abrirArquivo(nota: Nota, arquivo: "XML" | "DANFE") {
    await abrirArquivoDoc(nota.documento_fiscal_id, arquivo);
  }

  async function marcarFaturada() {
    if (!os) return;
    if (!window.confirm("Marcar a OS como Faturada? Só é aceito com nota emitida vinculada e saldo zero.")) return;
    setOcupado(true); setErro(null);
    try {
      const { error } = await supabase.rpc("os_faturar", { p_os_id: os.id });
      if (error) throw error;
      setAviso("OS marcada como faturada.");
      await carregar();
    } catch (cause) { setErro(textoErro(cause)); } finally { setOcupado(false); }
  }

  const totalConferido = itensConferidos.reduce((s, i) => s + num(i.quantidade) * num(i.valor_unitario), 0);
  // Consumidor final (uso/consumo ou ativo): o IPI entra na base do ICMS, como o
  // builder ja faz em supabase/functions/_shared/nfe-payload.ts. Sem isso a previa
  // mostrava um ICMS menor que o do XML e assustava quem conferia a nota.
  const consumidorFinal = destinacao === "USO_CONSUMO" || destinacao === "ATIVO_IMOBILIZADO";
  const impostosPrevia = useMemo(() => {
    // Arredonda em centavos a cada etapa, item a item, como o builder faz em
    // supabase/functions/_shared/nfe-payload.ts. Somar sem arredondar deixava a previa
    // um centavo longe do XML — e um centavo basta para a contabilidade parar a nota.
    const cent = (v: number) => Math.round(v * 100) / 100;
    const base = (i: ItemConferido) => cent(num(i.quantidade) * num(i.valor_unitario));
    const ipiDoItem = (i: ItemConferido) => cent(base(i) * num(i.aliquota_ipi) / 100);
    const icmsDoItem = (i: ItemConferido) => cent((base(i) + (consumidorFinal ? ipiDoItem(i) : 0)) * num(i.aliquota_icms) / 100);
    // PIS/COFINS sobre a mercadoria menos o ICMS destacado (STF, Tema 69), igual ao
    // builder da NF-e em supabase/functions/_shared/nfe-payload.ts.
    const basePisCofins = (i: ItemConferido) => cent(Math.max(base(i) - icmsDoItem(i), 0));
    const pisDoItem = (i: ItemConferido) => cent(basePisCofins(i) * num(i.aliquota_pis) / 100);
    const cofinsDoItem = (i: ItemConferido) => cent(basePisCofins(i) * num(i.aliquota_cofins) / 100);
    // Base do IBS/CBS: valor da operacao menos ICMS, ISS, PIS e COFINS (LC 214/2025,
    // art. 12, §1º e §2º, II e V), como o builder passou a calcular em 09/09. Enquanto
    // aqui era a mercadoria cheia, a previa prometia IBS 18,17 e CBS 163,50 numa nota
    // que saiu com 14,51 e 130,57 (NF-e 2/37, homologacao da OS 319).
    const baseIbsCbs = (i: ItemConferido) => cent(Math.max(basePisCofins(i) - pisDoItem(i) - cofinsDoItem(i), 0));
    const somar = (calculo: (i: ItemConferido) => number) => cent(itensConferidos.reduce((s, i) => s + calculo(i), 0));
    const ipi = somar(ipiDoItem);
    return {
      icms: somar(icmsDoItem),
      ipi,
      pis: somar(pisDoItem),
      cofins: somar(cofinsDoItem),
      ibs: somar((i) => cent(baseIbsCbs(i) * 0.001)),
      cbs: somar((i) => cent(baseIbsCbs(i) * 0.009)),
      totalNota: cent(totalConferido + ipi),
    };
  }, [itensConferidos, totalConferido, consumidorFinal]);
  // O saldo da OS conta o IPI (migration 20260909120000), entao a comparacao daqui
  // tambem: antes de conferir so temos a mercadoria, depois vale o total da nota. E
  // a reserva que a propria solicitacao ja fez volta para a base, senao a nota
  // conferida pareceria estourar o saldo que ela mesma segurou.
  // Peso do cadastro dos produtos vinculados, somado pela quantidade da linha. Item sem
  // peso entra como zero e o campo fica em branco para quem estiver montando a nota.
  const pesoSugerido = useMemo(() => linhas.reduce((acc, l) => {
    const qtd = paraNumero(l.quantidade) ?? 0;
    return {
      liquido: acc.liquido + qtd * (Number(l.produto?.peso_liquido ?? 0) || 0),
      bruto: acc.bruto + qtd * (Number(l.produto?.peso_bruto ?? l.produto?.peso_liquido ?? 0) || 0),
    };
  }, { liquido: 0, bruto: 0 }), [linhas]);
  const totalNotaPrevisto = conferida ? impostosPrevia.totalNota : totalLinhas + ipiLinhas;
  const ipiPrevisto = conferida ? impostosPrevia.ipi : ipiLinhas;
  const mercadoriaPrevista = conferida ? totalConferido : totalLinhas;
  const saldoParaComposicao = saldoDisponivel + (conferida ? impostosPrevia.totalNota : 0);
  const acimaDoSaldo = totalNotaPrevisto > saldoParaComposicao + 0.005;
  // A conferencia so consegue comparar mercadoria contra saldo, porque a aliquota de
  // IPI ainda nao existe quando as linhas sao montadas. Com a nota ja conferida da
  // para fechar a conta, e ai o estouro vira bloqueio de emissao.
  const bloqueiosNota = useMemo(() => (conferida && acimaDoSaldo
    ? [...bloqueios, { texto: `Total da nota ${R$(totalNotaPrevisto)} acima do saldo da OS ${R$(saldoParaComposicao)}; com o IPI a nota passa do pedido.` }]
    : bloqueios), [bloqueios, conferida, acimaDoSaldo, totalNotaPrevisto, saldoParaComposicao]);
  const autorizada = emissao?.status === "AUTORIZADA";
  const emProcessamento = emissao ? ["ENVIANDO", "PROCESSANDO"].includes(emissao.status) : false;
  const notaAtual = notas.find((n) => n.solicitacao_id === solicitacao?.id) ?? null;
  const notaProducao = notas.find((n) => n.solicitacao_id === solicitacao?.id && n.ambiente === "PRODUCAO") ?? null;
  // Margem da OS, nao da parcela: o custo real e o da OS inteira, entao entra o que ja foi faturado. Comparar so
  // esta nota com o custo todo mostrava prejuizo em todo faturamento parcial (OS 139: -23.099,07 numa OS que fecha
  // positiva). Depois da producao a nota ja esta no faturado e nao soma de novo.
  const faturadoOs = num(saldo?.valor_faturado);
  const margem = custoReal ? faturadoOs + (notaProducao?.emissao_status === "AUTORIZADA" ? 0 : (conferida ? totalConferido : totalLinhas)) - custoReal.total : null;
  const [producaoPronta, setProducaoPronta] = useState<ProducaoStatus | null>(null);
  useEffect(() => {
    if (!solicitacao || !autorizada || emissao?.ambiente !== "HOMOLOGACAO" || notaProducao) { setProducaoPronta(null); return; }
    let ativo = true;
    void supabase.functions.invoke("nfe-emitir-producao", { body: { acao: "STATUS", solicitacao_id: solicitacao.id } }).then(({ data, error }) => {
      if (!ativo) return;
      setProducaoPronta(error ? { pronta: false, motivo: "Não foi possível conferir a liberação de produção." } : ((data as ProducaoStatus | null) ?? null));
    });
    return () => { ativo = false; };
  }, [solicitacao, autorizada, emissao, notaProducao, supabase]);

  // Entrega ao cliente direto daqui: com a nota real autorizada, a tela carrega o contexto do
  // ciclo de vida (e-mails do cadastro, e-mail fiscal da empresa, eventos ja registrados) e
  // oferece o envio de XML + DANFE sem sair da OS. Depois do envio, pergunta se conclui a OS.
  //
  // A nota real vem das notas da OS, nao da solicitacao em edicao: depois da producao
  // AUTORIZADA o carregar() deixa de eleger aquela solicitacao como ativa, e ate 09/09/2026
  // isso levava junto a entrega e o "Marcar OS como Faturada" no primeiro recarregamento da
  // tela. Foi o que travou a OS 288 — concluida, NF-e 2/6 real autorizada, saldo zero e sem
  // ninguem conseguindo marca-la como faturada por aqui.
  const notaProducaoAutorizada = useMemo(() => {
    if (notaProducao?.emissao_status === "AUTORIZADA") return notaProducao;
    return notas
      .filter((n) => n.modelo !== "NFSE" && n.ambiente === "PRODUCAO" && n.emissao_status === "AUTORIZADA" && String(n.nfe_status ?? "").toUpperCase() !== "CANCELADA")
      .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))[0] ?? null;
  }, [notaProducao, notas]);
  type EntregaCtx = ContatoNfe & { eventos?: Array<{ tipo: string; status: string; destinatarios: string[] | null }> };
  const [entrega, setEntrega] = useState<{ documentoId: string | null; ctx: EntregaCtx | null; emails: string; enviadoPara: string[] | null; enviando: boolean }>({ documentoId: null, ctx: null, emails: "", enviadoPara: null, enviando: false });
  const [dialogoConcluir, setDialogoConcluir] = useState(false);
  useEffect(() => {
    const docId = notaProducaoAutorizada?.documento_fiscal_id ?? null;
    if (!docId) { setEntrega((atual) => atual.documentoId ? { documentoId: null, ctx: null, emails: "", enviadoPara: null, enviando: false } : atual); return; }
    if (entrega.documentoId === docId) return;
    let ativo = true;
    void supabase.schema("f").rpc("fn_nfe_ciclo_contexto", { p_documento_fiscal_id: docId }).then(({ data }) => {
      if (!ativo) return;
      const ctx = (data ?? null) as EntregaCtx | null;
      const enviado = ctx?.eventos?.find((ev) => ev.tipo === "EMAIL" && !/ERRO|REJEIT|FALH/i.test(ev.status))?.destinatarios ?? null;
      setEntrega({ documentoId: docId, ctx, emails: emailPadraoCliente(ctx), enviadoPara: enviado, enviando: false });
    });
    return () => { ativo = false; };
  }, [notaProducaoAutorizada, entrega.documentoId, supabase]);

  async function enviarEntrega() {
    if (!notaProducaoAutorizada) return;
    const destinatarios = separarEmails(entrega.emails);
    if (!destinatarios.length) { setErro("Informe ao menos um e-mail para a entrega."); return; }
    if (!window.confirm(`Enviar XML e DANFE da NF-e ${notaProducaoAutorizada.serie}/${notaProducaoAutorizada.numero} para:\n\n${destinatarios.join("\n")}\n\nConfirme somente após revisar os dois arquivos.`)) return;
    setEntrega((atual) => ({ ...atual, enviando: true })); setErro(null); setAviso(null);
    try {
      const { data, error } = await supabase.functions.invoke("nfe-ciclo", { body: { acao: "EMAIL", emails: destinatarios, documento_fiscal_id: notaProducaoAutorizada.documento_fiscal_id } });
      if (error) throw error;
      if (data?.error) throw new Error(String(data.error));
      setEntrega((atual) => ({ ...atual, enviando: false, enviadoPara: destinatarios }));
      setAviso(`XML e DANFE da NF-e ${notaProducaoAutorizada.serie}/${notaProducaoAutorizada.numero} enviados para ${destinatarios.join(", ")}.`);
      setDialogoConcluir(true);
    } catch (cause) { setEntrega((atual) => ({ ...atual, enviando: false })); setErro(await erroFunction(cause)); }
  }

  async function concluirEFaturar() {
    if (!os) return;
    setOcupado(true); setErro(null);
    try {
      if (String(os.status_fluxo).toLowerCase() !== "concluida") {
        const { error } = await supabase.rpc("os_concluir", { p_os_id: os.id });
        if (error) throw error;
      }
      const { error } = await supabase.rpc("os_faturar", { p_os_id: os.id });
      if (error) throw error;
      setDialogoConcluir(false);
      setAviso("OS concluída e marcada como faturada.");
      await carregar();
    } catch (cause) { setErro(textoErro(cause)); } finally { setOcupado(false); }
  }

  if (!Number.isInteger(osId) || osId <= 0) return <div className="p-6 text-sm text-red-300">OS inválida.</div>;

  return (
    <div className="mx-auto max-w-6xl space-y-5 px-4 py-6 text-zinc-100">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="text-xs uppercase text-zinc-500">Faturar OS · {modelo === "NFSE" ? "NFS-e Padrão Nacional" : "NF-e de industrialização"} · HOMOLOGAÇÃO</div>
          <h1 className="text-xl font-semibold">OS {os?.numero_os ?? osId} · {os?.cliente_nome ?? ""}</h1>
          <p className="text-sm text-zinc-400">{os?.descricao_servico}</p>
        </div>
        <Link href={`/os/${osId}`} className={botao}>Voltar para a OS</Link>
      </div>

      {erro ? <div role="alert" className="rounded-md border border-red-900 bg-red-950/30 p-3 text-sm text-red-200">{erro}</div> : null}
      {aviso ? <div role="status" className="rounded-md border border-sky-900 bg-sky-950/30 p-3 text-sm text-sky-200">{aviso}</div> : null}
      {motivoBloqueioOs ? <div className="rounded-md border border-amber-900/70 bg-amber-950/20 p-3 text-sm text-amber-200">Faturar indisponível: {motivoBloqueioOs}</div> : null}
      {carregando ? <div className="text-sm text-zinc-500">Carregando OS, cliente e saldo...</div> : null}

      {/* 1 · Cabeçalho */}
      <section className="grid gap-3 rounded-xl border border-zinc-800 bg-zinc-950 p-4 md:grid-cols-4">
        <div><div className="text-xs uppercase text-zinc-500">Destinatário</div><div className="text-sm">{cliente?.razao_social ?? cliente?.nome ?? "—"}</div><div className="text-xs text-zinc-400">CNPJ {cliente?.documento ?? "—"} · IE {cliente?.inscricao_estadual ?? "—"} · indIEDest {cliente?.indicador_ie ?? <span className="text-amber-300">vazio</span>}</div><div className="text-xs text-zinc-400">{cliente?.cidade ?? "—"}/{cliente?.uf ?? "—"} · IBGE {cliente?.codigo_ibge_municipio ?? "—"}</div>{cliente && !cliente.indicador_ie ? <Link className="text-xs text-sky-300 underline" href={`/clientes/cadastro-fiscal?cliente_id=${cliente.id}`}>Confirmar indicador de IE no cadastro fiscal</Link> : null}</div>
        <div><label className={label}>Pedido de compra do cliente (grava na OS)</label><input className={field} value={pedidoCliente} onChange={(e) => setPedidoCliente(e.target.value)} placeholder="OC do cliente" disabled={Boolean(solicitacao)} />{!pedidoCliente.trim() ? <div className="mt-1 text-xs text-amber-300">Sem OC informada. Não bloqueia; a Venda a Crédito cuida da exposição.</div> : null}</div>
        <div><div className="text-xs uppercase text-zinc-500">Saldo a faturar</div><div className="text-lg font-semibold">{R$(saldoDisponivel)}</div><div className="text-xs text-zinc-400">Orçado/HH {R$(num(saldo?.valor_pedido))} · faturado {R$(num(saldo?.valor_faturado))} · reservado {R$(num(saldo?.valor_reservado))}</div></div>
        <div>
          <label className={label}>Operação (perfil da nota)
            <select className={field} value={operacaoSel} disabled={Boolean(solicitacao)} onChange={(e) => setOperacaoSel(e.target.value)}>
              <optgroup label="NF-e · produto fabricado (industrialização)">
                <option value="NFE">{ambito === "INTERNA" ? "Dentro de SC" : `Fora de SC (${cliente?.uf ?? "?"})`} · CFOP {cfop} · {perfisVigentes[0]?.codigo ?? "fixture de homologação"}</option>
              </optgroup>
              <optgroup label="NFS-e · serviço (Padrão Nacional)">
                {perfisServico.map((p) => <option key={p.id} value={`NFSE:${p.id}`} disabled={p.faixa_automacao === "BLOQUEADO"}>{p.item_servico} · {p.nome}{p.faixa_automacao === "BLOQUEADO" ? " · bloqueado" : ""}</option>)}
              </optgroup>
            </select>
          </label>
          <div className="text-xs text-zinc-400">Custo real {custoReal ? R$(custoReal.total) : "—"}</div>
        </div>
      </section>

      {modelo === "NFSE" ? (
        <FaturarNfseOs
          tenantId={tenantId} empresaId={empresaId} osId={osId}
          os={osNfse}
          cliente={clienteNfse}
          saldo={saldoDisponivel} empresaIbge={empresaIbge}
          perfil={perfilServico} perfis={perfisServico}
          custoReal={custoReal?.total ?? null} faturadoOs={faturadoOs} motivoBloqueioOs={motivoBloqueioOs} versao={versao}
          onAtualizar={carregar} abrirArquivo={abrirArquivoDoc}
        />
      ) : (<>

      {/* 2 · Linhas */}
      <section className="space-y-3 rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <div className="flex items-center justify-between"><h2 className="font-semibold">Linhas da nota</h2>{!solicitacao ? <button type="button" className={botao} onClick={() => { setLinhas((a) => [...a, { chave: proximaChave, produto: null, busca: "", resultados: [], buscou: null, descricao: "", quantidade: "1", valor_unitario: "" }]); setProximaChave((k) => k + 1); }}>Adicionar linha</button> : null}</div>
        {solicitacao ? (
          <table className="w-full text-sm"><thead className="text-xs uppercase text-zinc-500"><tr><th className="text-left">Descrição</th><th className="text-right">Qtd</th><th className="text-right">Unitário</th><th className="text-right">Total</th><th className="text-left">CFOP</th><th className="text-right">ICMS</th><th className="text-right">IPI</th><th className="text-left">NCM / origem</th></tr></thead>
            <tbody>{itensConferidos.map((i) => <tr key={i.ordem} className="border-t border-zinc-800"><td>{i.descricao}</td><td className="text-right">{decimal(i.quantidade)}</td><td className="text-right">{R$(num(i.valor_unitario))}</td><td className="text-right">{R$(num(i.quantidade) * num(i.valor_unitario))}</td><td>{i.cfop ?? "—"}</td><td className="text-right">{i.aliquota_icms != null ? `${decimal(i.aliquota_icms)}%` : "—"}</td><td className="text-right">{i.cst_ipi ?? "—"}{i.aliquota_ipi != null ? ` · ${decimal(i.aliquota_ipi)}%` : ""}</td><td>{i.ncm ?? "—"} / {i.origem_mercadoria ?? "—"}</td></tr>)}</tbody></table>
        ) : linhas.map((linha, index) => (
          <div key={linha.chave} className="space-y-2 rounded-lg border border-zinc-800 p-3">
            <div className="flex items-center justify-between text-sm"><span className="font-medium">Linha {index + 1}</span>{linhas.length > 1 ? <button type="button" className="text-xs text-zinc-400 hover:text-zinc-200" onClick={() => setLinhas((a) => a.filter((l) => l.chave !== linha.chave))}>Remover</button> : null}</div>
            <div className="grid gap-2 md:grid-cols-[1fr_auto_auto]">
              <input className={field} value={linha.busca} onChange={(e) => atualizarLinha(linha.chave, { busca: e.target.value })} onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); void buscarProduto(linha.chave); } }} placeholder="Buscar produto fabricado no cadastro (código ou nome)" />
              <button type="button" className={botao} onClick={() => void buscarProduto(linha.chave)}>Buscar</button>
              <button type="button" className={botao} onClick={() => { setCriandoProduto(linha.chave); setNovoProduto({ nome: linha.descricao || os?.descricao_servico || "", ncm: "", origem: "", unidade: "UN", cst_ipi: "", aliquota_ipi: "" }); }}>Criar da OS</button>
            </div>
            {linha.produto ? <div className="rounded-md bg-zinc-900 px-3 py-2 text-xs text-zinc-300">Produto: <strong>{linha.produto.codigo}</strong> · {linha.produto.nome} <button type="button" className="ml-2 text-zinc-500 hover:text-zinc-200" onClick={() => atualizarLinha(linha.chave, { produto: null })}>desvincular</button></div> : <div className="text-xs text-amber-300">Sem produto vinculado. A NF-e exige produto com NCM, origem e unidade tributável.</div>}
            {linha.resultados.length > 0 ? <div className="max-h-40 overflow-y-auto rounded-md border border-zinc-700 bg-zinc-900">{linha.resultados.map((p) => <button key={p.id} type="button" className="block w-full px-3 py-1.5 text-left text-xs hover:bg-zinc-800" onClick={() => atualizarLinha(linha.chave, { produto: p, resultados: [], buscou: null, busca: "" })}>{p.codigo} · {p.nome}</button>)}</div> : linha.buscou !== null ? (
              <div className="rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 text-xs text-zinc-400">Nenhum produto fabricado encontrado para <strong className="text-zinc-200">{linha.buscou.trim() === "" ? "(busca vazia)" : linha.buscou}</strong>. Só entram aqui itens com finalidade &ldquo;Fabricado (produção própria)&rdquo;, casando por código, código de barras ou nome — a descrição da OS costuma não bater com o nome cadastrado. Tente <strong className="text-zinc-200">FAB-OS{os?.numero_os ?? os?.id}</strong> para os produtos já fabricados nesta OS, ou use &ldquo;Criar da OS&rdquo;.</div>
            ) : null}
            <div className="grid gap-2 md:grid-cols-[1fr_120px_160px_160px]">
              <label className={label}>Descrição impressa<input className={field} value={linha.descricao} onChange={(e) => atualizarLinha(linha.chave, { descricao: e.target.value })} /></label>
              <label className={label}>Quantidade<input className={field} inputMode="decimal" value={linha.quantidade} onChange={(e) => atualizarLinha(linha.chave, { quantidade: e.target.value })} /></label>
              <label className={label}>Valor unitário<input className={field} inputMode="decimal" value={linha.valor_unitario} onChange={(e) => atualizarLinha(linha.chave, { valor_unitario: e.target.value })} /></label>
              <div className={label}>Total<div className="py-2 text-sm text-zinc-100">{R$((paraNumero(linha.quantidade) ?? 0) * (paraNumero(linha.valor_unitario) ?? 0))}</div></div>
            </div>
            {criandoProduto === linha.chave ? (
              <div className="space-y-2 rounded-md border border-sky-900/60 bg-sky-950/10 p-3">
                <div className="text-sm font-medium">Criar produto fabricado a partir da OS</div>
                <p className="text-xs text-zinc-400">O produto nasce com fabricado = sim e origem na OS {os?.numero_os}. NCM, origem e unidade tributável são obrigatórios e não são deduzidos. Reaproveitável em outras OS.</p>
                <div className="grid gap-2 md:grid-cols-3">
                  <label className={label}>Descrição<input className={field} value={novoProduto.nome} onChange={(e) => setNovoProduto({ ...novoProduto, nome: e.target.value })} /></label>
                  <label className={label}>NCM (8 dígitos)<input className={field} value={novoProduto.ncm} onChange={(e) => setNovoProduto({ ...novoProduto, ncm: e.target.value })} placeholder="8537.10.19" /></label>
                  <label className={label}>Origem da mercadoria<select className={field} value={novoProduto.origem} onChange={(e) => setNovoProduto({ ...novoProduto, origem: e.target.value })}><option value="">Confirme...</option><option value="0">0 · Nacional</option><option value="1">1 · Estrangeira, importação direta</option><option value="2">2 · Estrangeira, mercado interno</option><option value="3">3 · Nacional, conteúdo importado 40 a 70%</option><option value="5">5 · Nacional, conteúdo importado até 40%</option><option value="8">8 · Nacional, conteúdo importado acima de 70%</option></select></label>
                  <label className={label}>Unidade tributável<input className={field} value={novoProduto.unidade} onChange={(e) => setNovoProduto({ ...novoProduto, unidade: e.target.value })} /></label>
                  <label className={label}>CST IPI<select className={field} value={novoProduto.cst_ipi} onChange={(e) => setNovoProduto({ ...novoProduto, cst_ipi: e.target.value })}><option value="">Confirme...</option><option value="50">50 · Saída tributada</option><option value="51">51 · Saída tributável com alíquota zero</option><option value="52">52 · Saída isenta</option><option value="53">53 · Saída não tributada</option><option value="54">54 · Saída imune</option><option value="55">55 · Saída com suspensão</option><option value="99">99 · Outras saídas</option></select></label>
                  <label className={label}>Alíquota IPI (%){novoProduto.cst_ipi === "50" || novoProduto.cst_ipi === "99" ? " · obrigatória" : ""}<input className={field} inputMode="decimal" value={novoProduto.aliquota_ipi} onChange={(e) => setNovoProduto({ ...novoProduto, aliquota_ipi: e.target.value })} placeholder="9,75" /></label>
                  {/* cEnq nao entra no cadastro do item: e do perfil de operacao (fixture 5101 usa 999) e o
                      trigger tg_fiscal_item_bloquear_cenq_produto recusa qualquer valor em fiscal_itens. */}
                </div>
                <div className="flex gap-2"><button type="button" className="rounded-md bg-sky-600 px-3 py-2 text-sm text-white hover:bg-sky-500 disabled:opacity-40" disabled={ocupado} onClick={() => void criarProdutoDaOs(linha.chave)}>Criar e vincular</button><button type="button" className={botao} onClick={() => setCriandoProduto(null)}>Cancelar</button></div>
              </div>
            ) : null}
          </div>
        ))}
        <div className="grid gap-2 rounded-lg border border-zinc-800 p-3 text-sm md:grid-cols-3">
          <div>Total da nota <strong>{R$(totalNotaPrevisto)}</strong>{ipiPrevisto > 0.005 ? <span className="text-xs text-zinc-500"> (mercadoria {R$(mercadoriaPrevista)} + IPI {R$(ipiPrevisto)})</span> : null} × saldo {R$(saldoParaComposicao)}{acimaDoSaldo ? <span className="ml-2 text-red-300">acima do saldo</span> : null}</div>
          <div>Custo real da OS <strong>{custoReal ? R$(custoReal.total) : "—"}</strong>{custoReal ? <span className="text-xs text-zinc-500"> (material {R$(custoReal.materiais)} · mão de obra {R$(custoReal.maoObra)} · despesas {R$(custoReal.despesas)} · impostos {R$(custoReal.impostos)})</span> : null}</div>
          <div>Margem da OS <strong className={margem !== null && margem < 0 ? "text-red-300" : "text-emerald-300"}>{margem !== null ? R$(margem) : "—"}</strong>{faturadoOs > 0.005 ? <span className="text-xs text-zinc-500"> (já faturado {R$(faturadoOs)} + esta nota − custo real)</span> : null}{margem !== null && margem < 0 ? <span className="ml-2 text-xs text-amber-300">abaixo do custo; a decisão é do gestor</span> : null}</div>
        </div>
      </section>

      {/* 3 · Operação */}
      <section className="space-y-3 rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <h2 className="font-semibold">Operação</h2>
        <div className="grid gap-3 md:grid-cols-2">
          <div>
            <div className={label}>Perfil de NF-e vigente (industrialização, {ambito === "INTERNA" ? "dentro de SC" : "outra UF"}{destinacao ? `, ${DESTINACOES.find(([c]) => c === destinacao)?.[1] ?? destinacao}` : ""})</div>
            {perfisVigentes.length > 0 ? perfisVigentes.map((p) => (
              <div key={p.id} className="mt-1 flex items-center justify-between gap-2 rounded-md border border-emerald-900/60 bg-emerald-950/20 p-2 text-sm">
                <span>{p.codigo} · {p.nome} · ICMS {p.aliquota_icms ?? "?"}% {p.habilitado_producao ? <span className="text-xs text-emerald-300">produção</span> : <span className="text-xs text-amber-300">só homologação · falta liberar produção</span>}</span>
                <Link href={linkPerfil(p.codigo)} className="shrink-0 rounded-md border border-emerald-800 px-2 py-1 text-xs text-emerald-100 hover:bg-emerald-950/60">{p.habilitado_producao ? "Abrir perfil" : "Liberar produção"}</Link>
              </div>
            )) : (
              <div className="mt-1 space-y-1 rounded-md border border-amber-900/60 bg-amber-950/20 p-2 text-sm text-amber-100">
                <div><strong>Nenhum perfil {cfop} vigente{destinacao ? " para esta destinação" : ""}.</strong> A emissão em homologação usa a fixture provisória (NF-e 3527–3553 e 3766 de agosto/2026); produção continua bloqueada.</div>
                {perfisPendentes.map((p) => (
                  <div key={p.id} className="flex items-center justify-between gap-2 text-xs">
                    <span>{p.codigo} · {p.faixa_automacao} · ICMS {p.aliquota_icms ?? "?"}% · <strong>{motivoPendente(p)}</strong></span>
                    <Link href={linkPerfil(p.codigo)} className="shrink-0 rounded-md border border-amber-700 bg-amber-950/40 px-2 py-1 text-xs text-amber-50 hover:bg-amber-900/60">Configurar e liberar</Link>
                  </div>
                ))}
                {perfisPendentes.length === 0 ? perfisBloqueados.slice(0, 3).map((p) => <div key={p.id} className="text-xs">{p.codigo} · {p.faixa_automacao} · {p.justificativa_faixa}</div>) : null}
                {fixturePendencia ? <div className="text-xs">Falta do contador: {fixturePendencia}</div> : null}
                <div className="pt-1"><Link href={linkPerfil()} className="rounded-md border border-amber-700 px-2 py-1 text-xs text-amber-100 hover:bg-amber-950/60">Todos os perfis fiscais</Link></div>
              </div>
            )}
          </div>
          <label className={label}>Destinação declarada pelo cliente (decide a alíquota interna)<select className={field} value={destinacao} onChange={(e) => setDestinacao(e.target.value)} disabled={Boolean(emissao && emissao.status !== "RASCUNHO")}><option value="">Confirme...</option>{DESTINACOES.map(([c, r, a]) => <option key={c} value={c}>{r} · {a}%</option>)}</select></label>
          <label className={label}>Presença do comprador<select className={field} value={presenca} onChange={(e) => setPresenca(e.target.value)}><option value="1">1 · Presencial</option><option value="2">2 · Internet</option><option value="3">3 · Teleatendimento</option><option value="5">5 · Fora do estabelecimento</option><option value="9">9 · Outros</option></select></label>
          <label className={label}>Modalidade do frete<select className={field} value={modalidadeFrete} onChange={(e) => {
            const proxima = e.target.value;
            setModalidadeFrete(proxima);
            // Ao abrir o transporte, já sugere um volume com o peso somado do cadastro
            // dos produtos das linhas. Peso ausente no cadastro fica em branco para
            // digitar — nesta fase nada é obrigatório no produto.
            if (proxima !== "9" && volumes.length === 0) setVolumes([{ quantidade: "1", especie: "", marca: "", numeracao: "", peso_liquido: decimal(pesoSugerido.liquido || ""), peso_bruto: decimal(pesoSugerido.bruto || "") }]);
          }}>{MODALIDADES_FRETE.map(([codigo, rotulo]) => <option key={codigo} value={codigo}>{rotulo}</option>)}</select><span className="text-xs text-zinc-500">Fora do 9, a nota exige transportador e ao menos um volume com peso.</span></label>
        </div>

        {modalidadeFrete !== "9" ? (
          <div className="space-y-3 rounded-md border border-zinc-800 bg-zinc-900/30 p-3">
            <div className="text-sm font-medium">Transporte</div>
            <div className="grid gap-3 md:grid-cols-3">
              <label className={label}>Transportador<input className={field} value={transportador.nome} onChange={(e) => setTransportador((t) => ({ ...t, nome: e.target.value }))} maxLength={60} /></label>
              <label className={label}>CNPJ/CPF<input className={field} value={transportador.documento} onChange={(e) => setTransportador((t) => ({ ...t, documento: e.target.value }))} inputMode="numeric" /></label>
              <label className={label}>Inscrição estadual<input className={field} value={transportador.inscricao_estadual} onChange={(e) => setTransportador((t) => ({ ...t, inscricao_estadual: e.target.value }))} /></label>
              <label className={label}>Endereço<input className={field} value={transportador.endereco} onChange={(e) => setTransportador((t) => ({ ...t, endereco: e.target.value }))} maxLength={60} /></label>
              <label className={label}>Município<input className={field} value={transportador.municipio} onChange={(e) => setTransportador((t) => ({ ...t, municipio: e.target.value }))} maxLength={60} /></label>
              <label className={label}>UF<input className={field} value={transportador.uf} onChange={(e) => setTransportador((t) => ({ ...t, uf: e.target.value.toUpperCase().slice(0, 2) }))} maxLength={2} /></label>
            </div>
            {!transportador.nome.trim() ? <div className="text-xs text-amber-300">Sem transportador a nota sai como &quot;9 · sem frete&quot;, qualquer que seja a modalidade escolhida.</div> : null}

            <div className="flex items-center justify-between gap-2">
              <div className="text-sm">Volumes <span className="text-xs text-zinc-500">(grupo vol da NF-e; espécie, marca e numeração são opcionais)</span></div>
              <button type="button" className={botao} onClick={() => setVolumes((v) => [...v, { quantidade: "1", especie: "", marca: "", numeracao: "", peso_liquido: "", peso_bruto: "" }])}>Adicionar volume</button>
            </div>
            {pesoSugerido.liquido > 0 || pesoSugerido.bruto > 0 ? (
              <div className="text-xs text-zinc-400">Cadastro dos produtos desta nota soma {formatMoneyBR(pesoSugerido.liquido)} kg líquidos e {formatMoneyBR(pesoSugerido.bruto)} kg brutos.</div>
            ) : (
              <div className="text-xs text-amber-300">Nenhum produto desta nota tem peso cadastrado; informe o peso do volume à mão ou preencha em <Link className="underline" href="/itens">Cadastros &rsaquo; Itens</Link>.</div>
            )}
            {volumes.length === 0 ? <div className="text-sm text-zinc-500">Nenhum volume. A emissão exige ao menos um.</div> : volumes.map((v, i) => (
              <div key={i} className="grid gap-2 md:grid-cols-[70px_1fr_1fr_1fr_1fr_1fr_auto] md:items-end">
                <div className="text-xs text-zinc-500 md:pb-2">{String(i + 1).padStart(3, "0")}</div>
                <label className={label}>Quantidade<input className={field} inputMode="numeric" value={v.quantidade} onChange={(e) => setVolumes((a) => a.map((x, j) => j === i ? { ...x, quantidade: e.target.value } : x))} /></label>
                <label className={label}>Espécie<input className={field} value={v.especie} onChange={(e) => setVolumes((a) => a.map((x, j) => j === i ? { ...x, especie: e.target.value } : x))} placeholder="caixa, pallet..." /></label>
                <label className={label}>Marca<input className={field} value={v.marca} onChange={(e) => setVolumes((a) => a.map((x, j) => j === i ? { ...x, marca: e.target.value } : x))} /></label>
                <label className={label}>Peso líquido (kg)<input className={field} inputMode="decimal" value={v.peso_liquido} onChange={(e) => setVolumes((a) => a.map((x, j) => j === i ? { ...x, peso_liquido: e.target.value } : x))} /></label>
                <label className={label}>Peso bruto (kg)<input className={field} inputMode="decimal" value={v.peso_bruto} onChange={(e) => setVolumes((a) => a.map((x, j) => j === i ? { ...x, peso_bruto: e.target.value } : x))} /></label>
                <button type="button" className={botao} onClick={() => setVolumes((a) => a.filter((_, j) => j !== i))}>Remover</button>
              </div>
            ))}
          </div>
        ) : null}
      </section>

      {/* 4 · Pagamento e entrega */}
      <section className="space-y-3 rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <h2 className="font-semibold">Pagamento e informações complementares</h2>
        <div className="grid gap-3 md:grid-cols-3">
          <label className={label}>Forma de pagamento<select className={field} value={pagamentoForma} onChange={(e) => setPagamentoForma(e.target.value)}>{FORMAS_PAGAMENTO.map(([c, r]) => <option key={c} value={c}>{r}</option>)}</select></label>
          <label className={label}>À vista ou a prazo<select className={field} value={pagamentoIndicador} onChange={(e) => setPagamentoIndicador(e.target.value)}><option value="0">0 · À vista</option><option value="1">1 · A prazo</option></select></label>
          {pagamentoForma === "99" ? <label className={label}>Descrição (obrigatória no 99)<input className={field} value={pagamentoDescricao} onChange={(e) => setPagamentoDescricao(e.target.value)} maxLength={60} /></label> : null}
        </div>
        {pagamentoIndicador === "1" ? (
          <div className="space-y-2 rounded-md border border-zinc-800 bg-zinc-900/30 p-3">
            <div className="flex items-center justify-between"><div className="text-sm">Parcelas (duplicatas da NF-e e parcelas do contas a receber) · dias após a emissão</div><button type="button" className={botao} onClick={() => setParcelas((p) => { const proximas = [...p, { dias: "", valor: "" }]; const rateio = ratearParcelas(totalNotaPrevisto, proximas.length); return proximas.map((x, j) => ({ ...x, valor: rateio[j] ?? "" })); })}>Adicionar parcela</button></div>
            {parcelas.map((p, i) => <div key={i} className="grid gap-2 md:grid-cols-[auto_1fr_1fr_auto] md:items-end"><div className="text-xs text-zinc-500 md:pb-2">{String(i + 1).padStart(3, "0")}</div><label className={label}>Dias<input className={field} inputMode="numeric" value={p.dias} onChange={(e) => setParcelas((a) => a.map((x, j) => j === i ? { ...x, dias: e.target.value } : x))} /></label><label className={label}>Valor (R$)<input className={field} inputMode="decimal" value={p.valor} onChange={(e) => setParcelas((a) => a.map((x, j) => j === i ? { ...x, valor: e.target.value } : x))} placeholder={parcelas.length === 1 ? "vazio = total" : "obrigatório"} /></label><button type="button" className={botao} disabled={parcelas.length === 1} onClick={() => setParcelas((a) => { const proximas = a.filter((_, j) => j !== i); const rateio = ratearParcelas(totalNotaPrevisto, proximas.length); return proximas.map((x, j) => ({ ...x, valor: rateio[j] ?? "" })); })}>Remover</button></div>)}
          </div>
        ) : null}
        <label className={label}>Observação livre (soma às informações complementares montadas: pedido, OS e destinação)<textarea className={`${field} min-h-16`} value={observacao} onChange={(e) => setObservacao(e.target.value)} maxLength={1000} /></label>
      </section>

      {/* 5 · Prévia e emissão */}
      <section className="space-y-3 rounded-xl border border-sky-900/60 bg-sky-950/10 p-4">
        <h2 className="font-semibold">Prévia e emissão</h2>
        {bloqueiosNota.length > 0 ? <div className="rounded-md border border-red-900 bg-red-950/30 p-3 text-sm"><div className="font-medium text-red-200">Bloqueios</div><ul className="mt-1 list-disc pl-5 text-red-100">{bloqueiosNota.map((b, i) => <li key={i}>{b.texto}{b.rota ? <> · <Link className="underline" href={b.rota}>corrigir</Link></> : null}</li>)}</ul></div> : null}
        {conferida ? (
          <div className="grid gap-2 text-sm md:grid-cols-4">
            <div>Produtos <strong>{R$(totalConferido)}</strong></div>
            <div>ICMS {R$(impostosPrevia.icms)} · IPI {R$(impostosPrevia.ipi)}</div>
            <div>PIS {R$(impostosPrevia.pis)} · COFINS {R$(impostosPrevia.cofins)} · IBS {R$(impostosPrevia.ibs)} · CBS {R$(impostosPrevia.cbs)}</div>
            <div>Total da nota <strong>{R$(impostosPrevia.totalNota)}</strong></div>
            {itensConferidos[0]?.tributacao_fonte === "FIXTURE_HOMOLOGACAO" ? <div className="md:col-span-4 text-xs text-amber-300">Valores da fixture provisória de homologação. Nenhum perfil 5101/6101 recebeu valor fiscal.</div> : null}
          </div>
        ) : <div className="text-sm text-zinc-400">Salve a conferência para ver os impostos calculados e os bloqueios.</div>}
        <div className="flex flex-wrap items-center gap-2">
          {!emissao || emissao.status === "RASCUNHO" || emissao.status === "REJEITADA" || emissao.status === "ERRO" ? (
            <button type="button" className={botao} disabled={ocupado || Boolean(motivoBloqueioOs) || !destinacao} onClick={() => void conferir()}>{solicitacao ? "Reconferir" : "Salvar rascunho e conferir"}</button>
          ) : null}
          {solicitacao && conferida && (!emissao || ["RASCUNHO", "REJEITADA", "ERRO"].includes(emissao.status)) ? (
            <button type="button" className="rounded-md bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-40" disabled={ocupado || bloqueiosNota.length > 0 || Boolean(motivoBloqueioOs)} onClick={() => void emitir()}>{emissao ? "Tentar emitir novamente" : "Emitir em homologação"}</button>
          ) : null}
          {solicitacao && (!emissao || ["RASCUNHO", "REJEITADA", "ERRO", "AUTORIZADA"].includes(emissao.status)) ? <button type="button" className={botao} disabled={ocupado} onClick={() => void descartarRascunho()}>{autorizada ? "Abandonar homologação e liberar saldo" : "Descartar rascunho"}</button> : null}
        </div>
        {emissao ? (
          <div className="rounded-md border border-zinc-800 p-3 text-sm">
            <div>Status: <strong>{emProcessamento ? "Em processamento" : autorizada ? "Autorizada em homologação" : emissao.status}</strong>{emissao.mensagem ? <span className="text-zinc-400"> · {emissao.codigo_status ? `${emissao.codigo_status} · ` : ""}{emissao.mensagem}</span> : null}</div>
            {emProcessamento ? <div className="text-xs text-zinc-400">Saldo reservado. A tela atualiza sozinha quando a SEFAZ responder.</div> : null}
            {autorizada && notaAtual ? <div className="mt-2 flex flex-wrap items-center gap-2"><span>NF-e {notaAtual.serie}/{notaAtual.numero} · chave <code className="text-xs">{notaAtual.chave_acesso}</code></span><button type="button" className={botao} onClick={() => void abrirArquivo(notaAtual, "DANFE")}>DANFE</button><button type="button" className={botao} onClick={() => void abrirArquivo(notaAtual, "XML")}>XML</button><Link className={botao} href={`/faturamento/nfe/${notaAtual.documento_fiscal_id}`}>Ciclo de vida</Link>
              {emissao.ambiente === "HOMOLOGACAO" && !notaProducao && producaoPronta?.pronta ? <button type="button" className="rounded-md bg-emerald-700 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-600 disabled:opacity-40" disabled={ocupado} onClick={() => void emitirProducao()}>Emitir NF-e real (produção)</button> : null}
            </div> : null}
            {autorizada && emissao.ambiente === "HOMOLOGACAO" && !notaProducao && producaoPronta && !producaoPronta.pronta ? (
              <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-zinc-500">
                <span>Produção: {producaoPronta.motivo}</span>
                {/* O motivo dizia o que falta e parava ali. Como a liberacao e por
                    solicitacao, o link ja leva o perfil e esta solicitacao prontos. */}
                {perfisVigentes.map((p) => (
                  <Link key={p.id} href={linkPerfil(p.codigo)} className="rounded-md border border-emerald-800 px-2 py-1 text-emerald-100 hover:bg-emerald-950/60">Liberar {p.codigo} para esta nota</Link>
                ))}
              </div>
            ) : null}
            {notaProducao ? <div className="mt-2 flex flex-wrap items-center gap-2 text-sm"><span className="font-medium text-emerald-300">NF-e REAL · {notaProducao.emissao_status}</span>{notaProducao.serie && notaProducao.numero ? <span>NF-e {notaProducao.serie}/{notaProducao.numero}</span> : null}{notaProducao.chave_acesso ? <code className="text-xs">{notaProducao.chave_acesso}</code> : null}<Link className={botao} href={`/faturamento/nfe/${notaProducao.documento_fiscal_id}`}>Ciclo de vida (cancelar, carta de correção)</Link></div> : null}
            {autorizada && emissao.ambiente === "HOMOLOGACAO" ? <div className="mt-2 text-xs text-zinc-400">Homologação não gera título a receber nem consome o saldo definitivo; o saldo fica reservado até o abandono. A nota real gera o contas a receber.</div> : null}
          </div>
        ) : null}
      </section>

      {/* 6 · Nota real: entrega ao cliente e fechamento da OS.
          Seção própria, fora do bloco da emissão em curso: com a produção autorizada a
          solicitação sai de cena no recarregamento, e a entrega e o fechamento precisam
          continuar ao alcance de quem fatura. */}
      {notaProducaoAutorizada ? (
        <section className="space-y-2 rounded-xl border border-emerald-900/60 bg-emerald-950/10 p-4">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h2 className="font-semibold">Entregar ao cliente · NF-e REAL {notaProducaoAutorizada.serie}/{notaProducaoAutorizada.numero}</h2>
            <span className="flex flex-wrap gap-2"><button type="button" className={botao} disabled={!notaProducaoAutorizada.danfe_path} onClick={() => void abrirArquivo(notaProducaoAutorizada, "DANFE")}>DANFE</button><button type="button" className={botao} disabled={!notaProducaoAutorizada.xml_path} onClick={() => void abrirArquivo(notaProducaoAutorizada, "XML")}>XML</button><Link className={botao} href={`/faturamento/nfe/${notaProducaoAutorizada.documento_fiscal_id}`}>Ciclo de vida</Link></span>
          </div>
          {notaProducaoAutorizada.chave_acesso ? <div className="text-xs text-zinc-400">Chave <code>{notaProducaoAutorizada.chave_acesso}</code></div> : null}
          <input className={field} value={entrega.emails} onChange={(e) => setEntrega((atual) => ({ ...atual, emails: e.target.value }))} placeholder="E-mails separados por vírgula" />
          <div className="flex flex-wrap items-center gap-2 text-xs text-zinc-400">
            <span>Cadastro do cliente:</span>
            {emailsDoCadastro(entrega.ctx).map((c) => c.proprio ? (
              <span key={c.rotulo} className="rounded border border-rose-900/60 bg-rose-950/30 px-2 py-0.5 text-rose-200" title="Endereço do domínio da própria empresa emitente gravado no cadastro do cliente; corrija no cadastro fiscal.">{c.rotulo}: {c.email} · é da própria empresa</span>
            ) : (
              <button key={c.rotulo} type="button" className="rounded border border-zinc-700 px-2 py-0.5 hover:bg-zinc-800" onClick={() => setEntrega((atual) => ({ ...atual, emails: c.email }))}>{c.rotulo}: {c.email}</button>
            ))}
            {entrega.ctx && emailsDoCadastro(entrega.ctx).length === 0 ? <span>nenhum e-mail cadastrado</span> : null}
          </div>
          {entrega.enviadoPara ? <div className="text-xs text-emerald-300">Já enviado para {entrega.enviadoPara.join(", ")}. Enviar de novo repete o e-mail.</div> : null}
          <div className="flex flex-wrap items-center gap-2">
            <button type="button" className="rounded-md bg-sky-600 px-3 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-40" disabled={entrega.enviando || ocupado || !entrega.emails.trim() || !notaProducaoAutorizada.xml_path || !notaProducaoAutorizada.danfe_path} onClick={() => void enviarEntrega()}>{entrega.enviando ? "Enviando..." : "Revisado: enviar XML + DANFE"}</button>
            {!notaProducaoAutorizada.xml_path || !notaProducaoAutorizada.danfe_path ? <span className="text-xs text-zinc-500">Aguardando XML e DANFE da SEFAZ.</span> : null}
            <button type="button" className={botao} disabled={ocupado} onClick={() => setDialogoConcluir(true)}>Concluir a OS...</button>
          </div>
          {osFaturada ? (
            <div className="text-sm text-emerald-300">OS já marcada como faturada.</div>
          ) : saldoDisponivel <= 0.005 ? (
            <div className="flex flex-wrap items-center gap-2 text-sm"><span>Saldo zerado.</span><button type="button" className={botao} disabled={ocupado || String(os?.status_fluxo).toLowerCase() !== "concluida"} onClick={() => void marcarFaturada()}>Marcar OS como Faturada</button>{String(os?.status_fluxo).toLowerCase() !== "concluida" ? <span className="text-xs text-zinc-500">exige OS concluída e nota emitida</span> : null}</div>
          ) : (
            <div className="text-sm text-amber-200">Ainda restam {R$(saldoDisponivel)} a faturar; a OS só é marcada como faturada com saldo zero.</div>
          )}
        </section>
      ) : null}
      </>)}

      {/* Notas da OS */}
      <section className="space-y-2 rounded-xl border border-zinc-800 bg-zinc-950 p-4">
        <h2 className="font-semibold">Notas desta OS</h2>
        {notas.length === 0 ? <div className="text-sm text-zinc-500">Nenhuma nota emitida ou vinculada.</div> : (
          <table className="w-full text-sm"><thead className="text-xs uppercase text-zinc-500"><tr><th className="px-2 py-1 text-left">Nota</th><th className="px-2 py-1 text-left">Modelo</th><th className="px-2 py-1 text-left">Ambiente</th><th className="px-2 py-1 text-left">Status</th><th className="px-2 py-1 text-right">Valor</th><th className="px-2 py-1 text-left">Arquivos</th></tr></thead>
            <tbody>{notas.map((n) => <tr key={n.documento_fiscal_id} className="border-t border-zinc-800"><td className="px-2 py-1">{n.serie && n.numero ? `${n.serie}/${n.numero}` : n.referencia_externa}</td><td className="px-2 py-1">{n.modelo === "NFSE" ? "NFS-e" : "NF-e"}</td><td className="px-2 py-1">{n.ambiente}</td><td className="px-2 py-1">{n.emissao_status}{n.nfe_status === "EMITIDA" ? " · documento emitido" : n.nfe_status === "SUBSTITUIDA" ? " · substituída" : ""}</td><td className="px-2 py-1 text-right whitespace-nowrap">{R$(num(n.valor_total))}</td><td className="space-x-2 px-2 py-1">{n.danfe_path ? <button type="button" className="text-sky-300 underline" onClick={() => void abrirArquivo(n, "DANFE")}>{n.modelo === "NFSE" ? "DANFSe" : "DANFE"}</button> : null}{n.xml_path ? <button type="button" className="text-sky-300 underline" onClick={() => void abrirArquivo(n, "XML")}>XML</button> : null}<Link className="text-sky-300 underline" href={`/faturamento/${n.modelo === "NFSE" ? "nfse" : "nfe"}/${n.documento_fiscal_id}`}>detalhe</Link>{n.ambiente === "HOMOLOGACAO" && n.emissao_status === "AUTORIZADA" && n.nfe_status !== "EMITIDA" ? (n.solicitacao_status === "CANCELADA" ? <span className="text-zinc-500">homologação abandonada (saldo devolvido)</span> : <button type="button" className="text-amber-300 underline" disabled={ocupado} onClick={() => void abandonarNota(n)}>abandonar homologação</button>) : null}</td></tr>)}</tbody></table>
        )}
      </section>

      {dialogoConcluir && os ? (
        <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/70 p-4" onClick={(e) => { if (e.target === e.currentTarget) setDialogoConcluir(false); }}>
          <div className="w-full max-w-lg space-y-4 rounded-xl border border-zinc-800 bg-zinc-950 p-5 shadow-2xl" role="dialog" aria-modal="true" aria-labelledby="dialogo-concluir-titulo">
            <div>
              <h2 id="dialogo-concluir-titulo" className="text-lg font-semibold">Concluir a OS {os.numero_os ?? os.id}?</h2>
              {entrega.enviadoPara ? <p className="mt-1 text-sm text-zinc-400">NF-e {notaProducaoAutorizada?.serie}/{notaProducaoAutorizada?.numero} enviada para {entrega.enviadoPara.join(", ")}.</p> : null}
            </div>
            <div className="grid grid-cols-3 gap-3 rounded-md border border-zinc-800 p-3 text-sm">
              <div><div className="text-xs uppercase text-zinc-500">Orçado/HH</div><div className="font-semibold">{R$(num(saldo?.valor_pedido))}</div></div>
              <div><div className="text-xs uppercase text-zinc-500">Faturado</div><div className="font-semibold text-emerald-300">{R$(num(saldo?.valor_faturado))}</div></div>
              <div><div className="text-xs uppercase text-zinc-500">Saldo</div><div className={`font-semibold ${saldoDisponivel <= 0.005 ? "text-emerald-300" : "text-amber-300"}`}>{R$(saldoDisponivel)}</div></div>
            </div>
            {saldoDisponivel > 0.005 ? (
              <p className="text-sm text-amber-200">Ainda restam {R$(saldoDisponivel)} a faturar. A OS só pode ser marcada como faturada com saldo zero — feche e emita o restante quando for a hora.</p>
            ) : (
              <p className="text-sm text-zinc-300">{String(os.status_fluxo).toLowerCase() === "concluida" ? "A OS já está concluída. Marcar como faturada encerra o ciclo dela." : "A OS ainda não está concluída. Confirmar conclui a OS e a marca como faturada num só passo."}</p>
            )}
            <div className="flex flex-wrap justify-end gap-2">
              <button type="button" className={botao} disabled={ocupado} onClick={() => setDialogoConcluir(false)}>{saldoDisponivel > 0.005 ? "Fechar" : "Agora não"}</button>
              {saldoDisponivel <= 0.005 ? <button type="button" className="rounded-md bg-emerald-700 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-600 disabled:opacity-40" disabled={ocupado} onClick={() => void concluirEFaturar()}>{String(os.status_fluxo).toLowerCase() === "concluida" ? "Marcar OS como Faturada" : "Concluir e marcar como Faturada"}</button> : null}
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
