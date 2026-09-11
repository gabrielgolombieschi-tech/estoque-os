"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { formatMoneyBR } from "@/lib/decimal";
import { emailPadraoCliente, emailsDoCadastro, separarEmails, type ContatoNfe } from "@/lib/nfe/emailsCliente";
import { ratearParcelas } from "@/lib/faturamento/parcelas";
import { supabaseBrowser } from "@/lib/supabase/client";
import { resolverIbsCbsTransicao2026 } from "@/supabase/functions/_shared/fiscal/ibs-cbs-transicao-2026";

type Solicitacao = {
  id: string;
  pedido_cliente: string | null;
  cliente_id: number;
  status: "RASCUNHO" | "PREVIA" | "APROVADA" | "EMITIDA" | "CANCELADA";
  natureza_operacao: string;
  finalidade_emissao: number | null;
  consumidor_final: number | null;
  presenca_comprador: number | null;
  modalidade_frete: number | null;
  valor_frete: number | string | null;
  valor_seguro: number | string | null;
  valor_outras_despesas: number | string | null;
  destinacao_mercadoria: string | null;
  pagamento_forma: string | null;
  pagamento_indicador: number | null;
  pagamento_descricao: string | null;
  pagamento_parcelas: Array<{ numero?: string | null; dias: number | string; valor: number | string | null }> | null;
  transportador_dados: {
    nome?: string | null;
    documento?: string | null;
    inscricao_estadual?: string | null;
    endereco?: string | null;
    municipio?: string | null;
    uf?: string | null;
  } | null;
  volumes_dados: Array<{
    quantidade?: number | string | null;
    especie?: string | null;
    marca?: string | null;
    numero?: string | null;
    peso_liquido?: number | string | null;
    peso_bruto?: number | string | null;
  }> | null;
  snapshot_cadastro_em: string | null;
  destino_uf_confirmada: string | null;
  created_at: string;
};

type SolicitacaoItem = {
  id: string;
  solicitacao_id: string;
  item_id: number | null;
  codigo_produto: string | null;
  descricao: string;
  ncm: string | null;
  cfop: string | null;
  cst_icms: string | null;
  csosn: string | null;
  cst_ipi: string | null;
  ipi_codigo_enquadramento_legal: string | null;
  cst_pis: string | null;
  cst_cofins: string | null;
  cst_ibs_cbs: string | null;
  cclass_trib: string | null;
  cclass_trib_versao: string | null;
  ibs_cbs_json: Record<string, unknown> | null;
  cbenef: string | null;
  origem_mercadoria: number | null;
  unidade_tributavel: string | null;
  numero_fci: string | null;
  perfil_operacao_id: string | null;
  reducao_base_icms_percentual: number | string | null;
  icms_modalidade_base_calculo: string | null;
  aliquota_icms: number | string | null;
  aliquota_ipi: number | string | null;
  aliquota_pis: number | string | null;
  aliquota_cofins: number | string | null;
  quantidade: number | string;
  unidade: string | null;
  valor_unitario: number | string;
  valor_desconto: number | string | null;
  ordem: number;
};

type Emissao = {
  documento_fiscal_id: string;
  solicitacao_id: string;
  referencia_externa: string;
  ambiente: "HOMOLOGACAO" | "PRODUCAO";
  status: "RASCUNHO" | "ENVIANDO" | "PROCESSANDO" | "AUTORIZADA" | "REJEITADA" | "CANCELADA" | "ERRO";
  chave_acesso: string | null;
  protocolo: string | null;
  numero: number | null;
  serie: number | null;
  codigo_status: number | null;
  mensagem: string | null;
  tentativa_count: number;
  payload_enviado: Record<string, unknown> | null;
  enviado_em: string | null;
  ultima_tentativa_em: string | null;
  xml_path: string | null;
  danfe_path: string | null;
  updated_at: string;
};

type Pendencia = {
  entidade?: string;
  id?: string | number | null;
  campo?: string;
  mensagem?: string;
  rota?: string;
};

type Draft = Solicitacao & { itens: SolicitacaoItem[]; emissao: Emissao | null };

type PerfilOperacao = {
  id: string;
  codigo: string;
  crt: string | null;
  cfop_interno: string | null;
  cfop_externo: string | null;
  cst_icms: string | null;
  csosn: string | null;
  cst_pis: string | null;
  cst_cofins: string | null;
  cbenef: string | null;
  cbenef_aplicacao: "NAO_CONFIRMADO" | "SEM_BENEFICIO" | "COM_BENEFICIO";
  icms_modalidade_base_calculo: string | null;
  aliquota_icms: number | string | null;
  reducao_base_icms_percentual: number | string | null;
  aliquota_pis: number | string | null;
  aliquota_cofins: number | string | null;
  finalidade_emissao: number | null;
  consumidor_final: number | null;
  cst_ibs_cbs: string | null;
  cclass_trib: string | null;
  cclass_trib_versao: string | null;
  ibs_cbs_json: Record<string, unknown> | null;
};

type ProdutoFiscalResolvido = {
  ncm: string | null;
  cest: string | null;
  unidade_tributavel: string | null;
  numero_fci: string | null;
};

type IpiOperacaoResolvido = {
  cst: string | null;
  c_enq: string | null;
  aliquota: number | string | null;
  fonte: "PERFIL_OPERACAO" | "FIXTURE_HOMOLOGACAO" | null;
};

type ItemResolvido = {
  solicitacao_item_id: string;
  item_id: number | null;
  origem_mercadoria: number | null;
  status: "RESOLVIDO" | "SEM_PERFIL" | "AMBIGUO" | "PRODUTO_INCOMPLETO" | "PERFIL_INCOMPLETO";
  motivo: string | null;
  perfil_id: string | null;
  perfil_codigo: string | null;
  perfil: PerfilOperacao | null;
  produto: ProdutoFiscalResolvido;
  ipi_operacao: IpiOperacaoResolvido;
};

type ResolucaoPerfis = {
  ok: boolean;
  bloqueio?: string;
  uf_emitente?: string;
  uf_cliente?: string;
  uf_confirmada?: string;
  ambito?: "INTERNA" | "INTERESTADUAL";
  indicador_ie?: string | null;
  rota_cliente?: string;
  itens?: ItemResolvido[];
};

type ProducaoStatus = {
  pronta: boolean;
  banco_pronto?: boolean;
  edge_configurada?: boolean;
  preflight_confirmacao_pronto?: boolean;
  resumo_confirmacao?: {
    nome_destinatario?: string;
    tipo_documento_destinatario?: "CNPJ" | "CPF";
    documento_destinatario_mascarado?: string | null;
    valor_total?: number | string;
    contexto_hash?: string;
    homologacao_documento_fiscal_id?: string;
  } | null;
  motivo?: string | null;
};

type Props = {
  tenantId: string;
  empresaId: string;
  ovId: number;
  clienteNome: string;
  podeEmitir: boolean;
  refreshKey?: number;
  onChanged?: () => void;
};

// Parcela confirmada na conferencia: dias apos a emissao + valor (vazio na
// parcela unica = total da nota). Vira duplicata na NF-e e parcela do AR.
type ParcelaForm = { dias: string; valor: string };

type OperacaoForm = {
  destino_uf_confirmada: string;
  finalidade_emissao: string;
  consumidor_final: string;
  presenca_comprador: string;
  modalidade_frete: string;
  valor_frete: string;
  valor_seguro: string;
  valor_outras_despesas: string;
  destinacao_mercadoria_confirmada: string;
  pagamento_forma: string;
  pagamento_indicador: string;
  pagamento_descricao: string;
  pagamento_parcelas: ParcelaForm[];
  transportador_nome: string;
  transportador_documento: string;
  transportador_ie: string;
  transportador_endereco: string;
  transportador_municipio: string;
  transportador_uf: string;
  volume_quantidade: string;
  volume_especie: string;
  volume_marca: string;
  volume_numero: string;
  volume_peso_liquido: string;
  volume_peso_bruto: string;
};

type ItemForm = {
  id: string;
  perfil_operacao_id: string | null;
  cfop: string;
  cst_icms: string;
  csosn: string;
  cst_ipi: string;
  ipi_codigo_enquadramento_legal: string;
  cst_pis: string;
  cst_cofins: string;
  cbenef: string;
  reducao_base_icms_percentual: string;
  icms_modalidade_base_calculo: string;
  aliquota_icms: string;
  aliquota_ipi: string;
  aliquota_pis: string;
  aliquota_cofins: string;
  cst_ibs_cbs: string;
  cclass_trib: string;
  aliquota_ibs_uf: string;
  aliquota_ibs_mun: string;
  aliquota_cbs: string;
  numero_fci: string;
};

const field = "w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500";
const label = "space-y-1 text-xs text-zinc-400";

function numero(value: unknown) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function arredondarMoeda(value: number) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function totaisItensNfe(
  itens: Array<Pick<SolicitacaoItem, "quantidade" | "valor_unitario" | "valor_desconto" | "aliquota_ipi">>,
) {
  let valorProdutos = 0;
  let valorDesconto = 0;
  let valorIpi = 0;
  for (const item of itens) {
    const bruto = arredondarMoeda(numero(item.quantidade) * numero(item.valor_unitario));
    const desconto = numero(item.valor_desconto);
    const baseIpi = arredondarMoeda(bruto - desconto);
    valorProdutos = arredondarMoeda(valorProdutos + bruto);
    valorDesconto = arredondarMoeda(valorDesconto + desconto);
    valorIpi = arredondarMoeda(valorIpi + arredondarMoeda(baseIpi * numero(item.aliquota_ipi) / 100));
  }
  return { valorLiquido: arredondarMoeda(valorProdutos - valorDesconto), valorIpi };
}

function totalNotaNfe(
  itens: Array<Pick<SolicitacaoItem, "quantidade" | "valor_unitario" | "valor_desconto" | "aliquota_ipi">>,
  frete: unknown,
  seguro: unknown,
  outrasDespesas: unknown,
) {
  const totais = totaisItensNfe(itens);
  return arredondarMoeda(
    totais.valorLiquido
      + numero(frete)
      + numero(seguro)
      + numero(outrasDespesas)
      + totais.valorIpi,
  );
}

function decimal(value: unknown) {
  if (value === null || value === undefined || String(value).trim() === "") return "";
  return String(value).replace(".", ",");
}

const PARCELA_PADRAO: ParcelaForm = { dias: "15", valor: "" };

function parcelasParaForm(parcelas: Solicitacao["pagamento_parcelas"] | undefined): ParcelaForm[] {
  if (!Array.isArray(parcelas) || parcelas.length === 0) return [{ ...PARCELA_PADRAO }];
  return parcelas.map((parcela) => ({
    dias: String(parcela.dias ?? ""),
    valor: decimal(parcela.valor),
  }));
}

function pendenciasParcelas(parcelas: ParcelaForm[]) {
  if (parcelas.length === 0) return "ao menos uma parcela";
  for (const [indice, parcela] of parcelas.entries()) {
    const dias = Number(parcela.dias.trim());
    if (!parcela.dias.trim() || !Number.isInteger(dias) || dias < 0) return `dias da parcela ${indice + 1}`;
    if (parcelas.length > 1 && (paraNumero(parcela.valor) ?? 0) <= 0) return `valor da parcela ${indice + 1}`;
  }
  return null;
}

function paraNumero(value: string) {
  const normalized = value.trim().replace(/\./g, "").replace(",", ".");
  if (!normalized) return null;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function textoErro(cause: unknown) {
  if (cause instanceof Error) return cause.message;
  if (cause && typeof cause === "object" && "message" in cause) {
    return String((cause as { message: unknown }).message);
  }
  return "Não foi possível concluir a operação.";
}

async function erroFunction(cause: unknown) {
  if (cause && typeof cause === "object" && "context" in cause) {
    const response = (cause as { context?: unknown }).context;
    if (response instanceof Response) {
      try {
        const body = await response.clone().json() as { erro?: string; codigo?: string | number };
        if (body.erro) return body.codigo ? `cStat ${body.codigo} · ${body.erro}` : body.erro;
      } catch {
        // A mensagem padrao do cliente ainda e exibida abaixo.
      }
    }
  }
  return textoErro(cause);
}

function statusLabel(status: Draft["status"], emissao: Emissao | null) {
  if (!emissao) return status === "PREVIA" ? "Conferência salva" : "Rascunho";
  if (emissao.status === "ENVIANDO" || emissao.status === "PROCESSANDO") return "Em processamento";
  if (emissao.status === "AUTORIZADA") return emissao.ambiente === "PRODUCAO" ? "Autorizada em produção" : "Autorizada em homologação";
  if (emissao.status === "REJEITADA") return "Rejeitada";
  if (emissao.status === "ERRO") return "Erro no envio";
  return emissao.status;
}

/**
 * Memoria da ultima nota ja conferida desta OV. Existe porque os campos de
 * operacao chegavam vazios em toda nota nova: quem emite a segunda nota da mesma
 * OV redigitava transportadora, volumes e pesos identicos aos da primeira.
 * Nao cobre finalidade/consumidor final (vem travados do perfil) nem o destino,
 * que continua sendo confirmado nota a nota de proposito.
 */
type MemoriaOperacao = { rotulo: string; resumo: string; campos: Partial<OperacaoForm> };

// O que o CLIENTE faz com a mercadoria — nao a natureza da operacao da empresa,
// que nesta tela e sempre venda de mercadoria de terceiros (CFOP 5102).
// Industrializacao da SEGAU sai por OS; remessa, conserto e afins tem lugar
// proprio. "Insumo" cobre o cliente que industrializa, sem repetir o termo.
//
// A aliquota ao lado e informativa, para o operador conferir contra a OC: quem
// escolhe o perfil e o servidor. Bases legais em
// docs/faturamento/regras-icms-sc-contabilidade.md — 12% para contribuinte
// (Lei 10.297/96, art. 19, III, "n" e Lei 17.878/2019) e 17% para destinatario
// final (RICMS/SC, art. 26, I).
const DESTINACOES_MERCADORIA: Array<[string, string, number]> = [
  ["REVENDA", "Vai revender", 12],
  ["INSUMO", "Vai usar como insumo de produção", 12],
  ["MANUTENCAO", "Vai usar em manutenção", 12],
  ["CONSIGNADO", "Recebe em consignação", 12],
  ["USO_CONSUMO", "Uso e consumo próprio", 17],
  ["ATIVO_IMOBILIZADO", "Vai para o ativo imobilizado", 17],
];

function rotuloDestinacao(codigo: string) {
  const encontrada = DESTINACOES_MERCADORIA.find(([valor]) => valor === codigo);
  return encontrada ? `${encontrada[1].toLowerCase()} (${encontrada[2]}%)` : codigo;
}

// tPag do grupo detPag. Só as formas que a operação usa; a tabela completa tem
// 23 códigos e oferecer todos aqui só aumentaria a chance de escolher errado.
const FORMAS_PAGAMENTO: Array<[string, string]> = [
  ["15", "15 · Boleto bancário"],
  ["16", "16 · Depósito bancário"],
  ["03", "03 · Cartão de crédito"],
  ["04", "04 · Cartão de débito"],
  ["17", "17 · PIX dinâmico"],
  ["20", "20 · PIX estático"],
  ["01", "01 · Dinheiro"],
  ["02", "02 · Cheque"],
  ["05", "05 · Crédito na loja"],
  ["90", "90 · Sem pagamento"],
  ["99", "99 · Outros"],
];

function rotuloPagamento(forma: string) {
  return FORMAS_PAGAMENTO.find(([codigo]) => codigo === forma)?.[1] ?? forma;
}

const CAMPOS_LEMBRADOS = [
  "presenca_comprador",
  // destinacao_mercadoria_confirmada NAO entra: a PORTOBELLO recusa a nota
  // quando a aliquota divergir da utilizacao informada na OC, e cada remessa
  // pode ter destinacao diferente. A memoria mostra o que a nota anterior usou,
  // como sugestao visivel, mas a escolha e explicita em cada nota.
  "pagamento_forma",
  "pagamento_indicador",
  "pagamento_descricao",
  "pagamento_parcelas",
  "modalidade_frete",
  "valor_frete",
  "valor_seguro",
  "valor_outras_despesas",
  "transportador_nome",
  "transportador_documento",
  "transportador_ie",
  "transportador_endereco",
  "transportador_municipio",
  "transportador_uf",
  "volume_quantidade",
  "volume_especie",
  "volume_marca",
  "volume_numero",
  "volume_peso_liquido",
  "volume_peso_bruto",
] as const satisfies ReadonlyArray<keyof OperacaoForm>;

function memoriaDeSolicitacao(origem: Solicitacao): MemoriaOperacao | null {
  if (origem.modalidade_frete == null) return null;
  const transportador = origem.transportador_dados ?? {};
  const volume = origem.volumes_dados?.[0] ?? {};
  // O aviso precisa dizer o que de fato veio: numa nota modalidade 9 nao ha
  // transportadora nem volume, e prometer "transportadora, volumes e pesos"
  // manda o usuario procurar dado que nunca existiu.
  const partes = [
    origem.pagamento_forma ? `pagamento ${rotuloPagamento(origem.pagamento_forma)}` : null,
    transportador.nome ? `transportadora ${transportador.nome}` : null,
    volume.quantidade != null ? `${decimal(volume.quantidade)} volume(s)` : null,
    volume.peso_bruto != null ? `peso bruto ${decimal(volume.peso_bruto)} kg` : null,
  ].filter((parte): parte is string => parte !== null);
  return {
    rotulo: new Date(origem.created_at).toLocaleDateString("pt-BR"),
    resumo: partes.length > 0
      ? partes.join(", ")
      : `modalidade do frete ${origem.modalidade_frete}${origem.modalidade_frete === 9 ? " · sem transporte" : ""}`,
    campos: {
      presenca_comprador: origem.presenca_comprador?.toString() ?? "",
      destinacao_mercadoria_confirmada: origem.destinacao_mercadoria ?? "",
      pagamento_forma: origem.pagamento_forma ?? "",
      pagamento_indicador: origem.pagamento_indicador?.toString() ?? "",
      pagamento_descricao: origem.pagamento_descricao ?? "",
      pagamento_parcelas: parcelasParaForm(origem.pagamento_parcelas),
      modalidade_frete: origem.modalidade_frete.toString(),
      valor_frete: decimal(origem.valor_frete),
      valor_seguro: decimal(origem.valor_seguro),
      valor_outras_despesas: decimal(origem.valor_outras_despesas),
      transportador_nome: transportador.nome ?? "",
      transportador_documento: transportador.documento ?? "",
      transportador_ie: transportador.inscricao_estadual ?? "",
      transportador_endereco: transportador.endereco ?? "",
      transportador_municipio: transportador.municipio ?? "",
      transportador_uf: transportador.uf ?? "",
      volume_quantidade: decimal(volume.quantidade),
      volume_especie: volume.especie ?? "",
      volume_marca: volume.marca ?? "",
      volume_numero: volume.numero ?? "",
      volume_peso_liquido: decimal(volume.peso_liquido),
      volume_peso_bruto: decimal(volume.peso_bruto),
    },
  };
}

/** true quando a nota ainda nao foi conferida e portanto aceita a memoria. */
function aceitaMemoria(draft: Draft) {
  return draft.modalidade_frete == null;
}

// Padrao do CLIENTE (public.clientes.transportador_padrao_*), diferente da memoria
// acima que e da OV: quem transporta pra este cliente nao muda venda a venda, e por
// isso sobrevive entre OVs — a memoria da OV so alcanca a nota seguinte da mesma OV.
type TransportadorPadraoCliente = {
  nome: string;
  documento: string;
  ie: string;
  endereco: string;
  municipio: string;
  uf: string;
  modalidade_frete: string;
};

// Contexto de entrega de uma nota autorizada: e-mails do cadastro, o que ja foi
// enviado e o texto em edicao. `ctx` nulo = ainda carregando ou sem contexto.
type EntregaCtx = ContatoNfe & { eventos?: Array<{ tipo: string; status: string; destinatarios: string[] | null }> };
type EntregaNota = { ctx: EntregaCtx | null; emails: string; enviadoPara: string[] | null; enviando: boolean };

function formOperacao(
  draft: Draft,
  memoria?: MemoriaOperacao | null,
  padraoCliente?: TransportadorPadraoCliente | null,
): OperacaoForm {
  const transportador = draft.transportador_dados ?? {};
  const volume = draft.volumes_dados?.[0] ?? {};
  const base: OperacaoForm = {
    destino_uf_confirmada: draft.destino_uf_confirmada ?? "",
    finalidade_emissao: draft.finalidade_emissao?.toString() ?? "",
    consumidor_final: draft.consumidor_final?.toString() ?? "",
    presenca_comprador: draft.presenca_comprador?.toString() ?? "",
    destinacao_mercadoria_confirmada: draft.destinacao_mercadoria ?? "",
    pagamento_forma: draft.pagamento_forma ?? "",
    pagamento_indicador: draft.pagamento_indicador?.toString() ?? "",
    pagamento_descricao: draft.pagamento_descricao ?? "",
    pagamento_parcelas: parcelasParaForm(draft.pagamento_parcelas),
    modalidade_frete: draft.modalidade_frete?.toString() ?? "",
    valor_frete: decimal(draft.valor_frete),
    valor_seguro: decimal(draft.valor_seguro),
    valor_outras_despesas: decimal(draft.valor_outras_despesas),
    transportador_nome: transportador.nome ?? "",
    transportador_documento: transportador.documento ?? "",
    transportador_ie: transportador.inscricao_estadual ?? "",
    transportador_endereco: transportador.endereco ?? "",
    transportador_municipio: transportador.municipio ?? "",
    transportador_uf: transportador.uf ?? "",
    volume_quantidade: decimal(volume.quantidade),
    volume_especie: volume.especie ?? "",
    volume_marca: volume.marca ?? "",
    volume_numero: volume.numero ?? "",
    volume_peso_liquido: decimal(volume.peso_liquido),
    volume_peso_bruto: decimal(volume.peso_bruto),
  };

  if (memoria && aceitaMemoria(draft)) {
    for (const campo of CAMPOS_LEMBRADOS) {
      if (campo === "pagamento_parcelas") {
        // A memoria de parcelas so vale quando o rascunho ainda esta no padrao.
        const atual = base.pagamento_parcelas;
        const lembrado = memoria.campos.pagamento_parcelas;
        if (lembrado && atual.length === 1 && atual[0].dias === PARCELA_PADRAO.dias && atual[0].valor === "") {
          base.pagamento_parcelas = lembrado.map((parcela) => ({ ...parcela }));
        }
        continue;
      }
      if (base[campo] === "") base[campo] = memoria.campos[campo] ?? "";
    }
  }

  // Padrao do cliente: so preenche o que a memoria da propria OV deixou vazio — ela e
  // mais recente e mais especifica que o padrao do cliente. Peso e volumes nao tem
  // padrao de cliente (variam por pedido) e continuam so na memoria da OV, acima.
  if (padraoCliente?.nome && aceitaMemoria(draft) && base.transportador_nome === "") {
    base.transportador_nome = padraoCliente.nome;
    base.transportador_documento = padraoCliente.documento;
    base.transportador_ie = padraoCliente.ie;
    base.transportador_endereco = padraoCliente.endereco;
    base.transportador_municipio = padraoCliente.municipio;
    base.transportador_uf = padraoCliente.uf;
  }
  if (padraoCliente?.modalidade_frete && aceitaMemoria(draft) && base.modalidade_frete === "") {
    base.modalidade_frete = padraoCliente.modalidade_frete;
  }
  return base;
}

function formItem(item: SolicitacaoItem): ItemForm {
  const ibsCbs = item.ibs_cbs_json ?? {};
  return {
    id: item.id,
    perfil_operacao_id: item.perfil_operacao_id ?? null,
    cfop: item.cfop ?? "",
    cst_icms: item.cst_icms ?? "",
    csosn: item.csosn ?? "",
    cst_ipi: item.cst_ipi ?? "",
    ipi_codigo_enquadramento_legal: item.ipi_codigo_enquadramento_legal ?? "",
    cst_pis: item.cst_pis ?? "",
    cst_cofins: item.cst_cofins ?? "",
    cbenef: item.cbenef ?? "",
    reducao_base_icms_percentual: decimal(item.reducao_base_icms_percentual),
    icms_modalidade_base_calculo: item.icms_modalidade_base_calculo ?? "",
    aliquota_icms: decimal(item.aliquota_icms),
    aliquota_ipi: decimal(item.aliquota_ipi),
    aliquota_pis: decimal(item.aliquota_pis),
    aliquota_cofins: decimal(item.aliquota_cofins),
    cst_ibs_cbs: item.cst_ibs_cbs ?? "",
    cclass_trib: item.cclass_trib ?? "",
    aliquota_ibs_uf: decimal(ibsCbs.ibs_uf_aliquota),
    aliquota_ibs_mun: decimal(ibsCbs.ibs_mun_aliquota),
    aliquota_cbs: decimal(ibsCbs.cbs_aliquota),
    numero_fci: item.numero_fci ?? "",
  };
}

function aplicarPerfilNoItem(
  atual: ItemForm,
  resolvido: ItemResolvido,
  ambito: ResolucaoPerfis["ambito"],
  naturezaOperacao: string,
): ItemForm {
  const perfil = resolvido.perfil;
  const produto = resolvido.produto ?? {} as ProdutoFiscalResolvido;
  const ipi = resolvido.ipi_operacao ?? {} as IpiOperacaoResolvido;
  const ibs = resolverIbsCbsTransicao2026(naturezaOperacao, new Date());
  return {
    ...atual,
    perfil_operacao_id: resolvido.perfil_id,
    cfop: (ambito === "INTERNA" ? perfil?.cfop_interno : perfil?.cfop_externo) ?? atual.cfop,
    cst_icms: perfil?.cst_icms ?? atual.cst_icms,
    csosn: perfil?.csosn ?? atual.csosn,
    cst_ipi: ipi.cst ?? "",
    ipi_codigo_enquadramento_legal: ipi.c_enq ?? "",
    aliquota_ipi: decimal(ipi.aliquota),
    numero_fci: produto.numero_fci ?? "",
    cst_pis: perfil?.cst_pis ?? atual.cst_pis,
    cst_cofins: perfil?.cst_cofins ?? atual.cst_cofins,
    cbenef: perfil?.cbenef_aplicacao === "SEM_BENEFICIO" ? "" : (perfil?.cbenef ?? atual.cbenef),
    reducao_base_icms_percentual: perfil?.reducao_base_icms_percentual == null
      ? atual.reducao_base_icms_percentual
      : decimal(perfil.reducao_base_icms_percentual),
    icms_modalidade_base_calculo: perfil?.icms_modalidade_base_calculo ?? atual.icms_modalidade_base_calculo,
    aliquota_icms: perfil?.aliquota_icms == null ? atual.aliquota_icms : decimal(perfil.aliquota_icms),
    aliquota_pis: perfil?.aliquota_pis == null ? atual.aliquota_pis : decimal(perfil.aliquota_pis),
    aliquota_cofins: perfil?.aliquota_cofins == null ? atual.aliquota_cofins : decimal(perfil.aliquota_cofins),
    cst_ibs_cbs: ibs.cst,
    cclass_trib: ibs.cClassTrib,
    aliquota_ibs_uf: decimal(ibs.pIBSUF),
    aliquota_ibs_mun: decimal(ibs.pIBSMun),
    aliquota_cbs: decimal(ibs.pCBS),
  };
}

type CampoPerfil = Exclude<keyof ItemForm, "id" | "perfil_operacao_id">;

function campoVemDoPerfil(resolvido: ItemResolvido | undefined, campo: CampoPerfil) {
  const perfil = resolvido?.perfil;
  if (!perfil) return false;
  const mapeamento: Partial<Record<CampoPerfil, boolean>> = {
    cfop: Boolean(perfil.cfop_interno || perfil.cfop_externo),
    cst_icms: perfil.cst_icms != null,
    csosn: perfil.csosn != null,
    cst_pis: perfil.cst_pis != null,
    cst_cofins: perfil.cst_cofins != null,
    cbenef: perfil.cbenef_aplicacao !== "NAO_CONFIRMADO",
    reducao_base_icms_percentual: perfil.reducao_base_icms_percentual != null,
    icms_modalidade_base_calculo: perfil.icms_modalidade_base_calculo != null,
    aliquota_icms: perfil.aliquota_icms != null,
    aliquota_pis: perfil.aliquota_pis != null,
    aliquota_cofins: perfil.aliquota_cofins != null,
    cst_ibs_cbs: perfil.cst_ibs_cbs != null,
    cclass_trib: perfil.cclass_trib != null,
    aliquota_ibs_uf: perfil.ibs_cbs_json?.ibs_uf_aliquota != null,
    aliquota_ibs_mun: perfil.ibs_cbs_json?.ibs_mun_aliquota != null,
    aliquota_cbs: perfil.ibs_cbs_json?.cbs_aliquota != null,
  };
  return Boolean(mapeamento[campo]);
}

function perfilCabecalhoUnico(resolucao: ResolucaoPerfis | null) {
  const perfis = (resolucao?.itens ?? []).map((item) => item.perfil).filter(Boolean) as PerfilOperacao[];
  if (perfis.length === 0) return null;
  const ids = new Set(perfis.map((perfil) => perfil.id));
  return ids.size === 1 ? perfis[0] : null;
}

function camposObrigatoriosPendentes(operacao: OperacaoForm, itens: ItemForm[]) {
  const pendentes: string[] = [];
  const camposOperacao: Array<[keyof OperacaoForm, string]> = [
    ["finalidade_emissao", "finalidade"],
    ["consumidor_final", "consumidor final"],
    ["presenca_comprador", "presença do comprador"],
    ["destinacao_mercadoria_confirmada", "destinação da mercadoria"],
    ["pagamento_forma", "forma de pagamento"],
    ["pagamento_indicador", "pagamento à vista ou a prazo"],
    ["modalidade_frete", "modalidade do frete"],
    ["valor_frete", "valor do frete"],
    ["valor_seguro", "valor do seguro"],
    ["valor_outras_despesas", "outras despesas"],
  ];
  // xPag e obrigatorio no layout quando tPag = 99.
  if (operacao.pagamento_forma === "99") {
    camposOperacao.push(["pagamento_descricao", "descrição da forma de pagamento"]);
  }
  if (operacao.pagamento_indicador === "1") {
    const pendenciaParcela = pendenciasParcelas(operacao.pagamento_parcelas);
    if (pendenciaParcela) pendentes.push(pendenciaParcela);
  }
  if (operacao.modalidade_frete !== "9") {
    // Espécie, marca e numeração NAO entram: o grupo vol e opcional no layout da
    // NF-e, e as notas de producao da propria SEGAU saem sem eles — conferido na
    // NF 3772/serie 1 (autorizada, protocolo 242260375531137), que traz apenas
    // quantidade 1 e pesos 0,20. Exigi-los impedia reproduzir uma nota real.
    // Quantidade e pesos seguem obrigatorios porque a expedicao depende deles.
    camposOperacao.push(
      ["transportador_nome", "transportadora"],
      ["volume_quantidade", "quantidade de volumes"],
      ["volume_peso_liquido", "peso líquido"],
      ["volume_peso_bruto", "peso bruto"],
    );
  }
  for (const [campo, rotulo] of camposOperacao) {
    const valor = operacao[campo];
    if (typeof valor !== "string" || !valor.trim()) pendentes.push(rotulo);
  }

  itens.forEach((item, index) => {
    const camposItem: Array<[keyof ItemForm, string]> = [
      ["cfop", "CFOP"],
      ["cst_ipi", "CST IPI do produto"],
      ["ipi_codigo_enquadramento_legal", "enquadramento legal do IPI"],
      ["cst_pis", "CST PIS"],
      ["cst_cofins", "CST COFINS"],
      ["icms_modalidade_base_calculo", "modalidade da base de ICMS"],
      ["reducao_base_icms_percentual", "redução da base de ICMS"],
      ["cst_ibs_cbs", "CST IBS/CBS"],
      ["cclass_trib", "cClassTrib"],
      ["aliquota_ibs_uf", "alíquota IBS UF"],
      ["aliquota_ibs_mun", "alíquota IBS municipal"],
      ["aliquota_cbs", "alíquota CBS"],
    ];
    for (const [campo, rotulo] of camposItem) {
      const valor = item[campo];
      if (typeof valor === "string" && !valor.trim()) pendentes.push(`linha ${index + 1}: ${rotulo}`);
    }
    if (!item.cst_icms.trim() && !item.csosn.trim()) pendentes.push(`linha ${index + 1}: CST ICMS ou CSOSN`);
    if (!item.perfil_operacao_id) pendentes.push(`linha ${index + 1}: perfil fiscal`);
  });
  return pendentes;
}

export default function OvNfeDraftsPanel({
  tenantId,
  empresaId,
  ovId,
  clienteNome,
  podeEmitir,
  refreshKey = 0,
  onChanged,
}: Props) {
  const supabase = useMemo(() => supabaseBrowser(), []);
  const [drafts, setDrafts] = useState<Draft[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [openId, setOpenId] = useState<string | null>(null);
  const [operacao, setOperacao] = useState<OperacaoForm | null>(null);
  const [memoria, setMemoria] = useState<MemoriaOperacao | null>(null);
  // Falha e sucesso compartilhavam a mesma caixa azul: "Solicitação enviada à Focus"
  // e "Solicitação incompleta: volume 1, espécie" ficavam identicas. Este mapa marca
  // quais mensagens sao erro, para pintar e anunciar como erro.
  const [feedbackErro, setFeedbackErro] = useState<Record<string, boolean>>({});

  /** Registra a mensagem de um card, dizendo se e erro. */
  const avisar = useCallback((draftId: string, mensagem: string, erro = false) => {
    setFeedback((current) => ({ ...current, [draftId]: mensagem }));
    setFeedbackErro((current) => ({ ...current, [draftId]: erro }));
  }, []);
  const [itensForm, setItensForm] = useState<ItemForm[]>([]);
  const [feedback, setFeedback] = useState<Record<string, string>>({});
  const [pendencias, setPendencias] = useState<Record<string, Pendencia[]>>({});
  const [producaoStatus, setProducaoStatus] = useState<Record<string, ProducaoStatus>>({});
  const [ambienteConferencia, setAmbienteConferencia] = useState<"HOMOLOGACAO" | "PRODUCAO">("HOMOLOGACAO");
  const [etapaConferencia, setEtapaConferencia] = useState<"DESTINO" | "FISCAL">("DESTINO");
  const [destinoTipo, setDestinoTipo] = useState<"" | "SC" | "FORA">("");
  const [ufCliente, setUfCliente] = useState<string | null>(null);
  const [padraoTransportador, setPadraoTransportador] = useState<TransportadorPadraoCliente | null>(null);
  // Entrega ao cliente (XML + DANFE pela Focus), por documento fiscal — a OV pode ter
  // mais de uma nota real. Mesmo caminho da tela da OS: fn_nfe_ciclo_contexto para os
  // e-mails do cadastro, nfe-ciclo {acao EMAIL} para enviar.
  const [entregas, setEntregas] = useState<Record<string, EntregaNota>>({});
  const [destinoUf, setDestinoUf] = useState("");
  const [resolucaoPerfis, setResolucaoPerfis] = useState<ResolucaoPerfis | null>(null);
  const [resolvendoDestino, setResolvendoDestino] = useState(false);
  const [descarteId, setDescarteId] = useState<string | null>(null);
  const [justificativaDescarte, setJustificativaDescarte] = useState("");

  const carregar = useCallback(async () => {
    if (!tenantId || !empresaId || !Number.isInteger(ovId) || ovId <= 0) return;
    setLoading(true);
    try {
      const { data: itensData, error: itensError } = await supabase
        .schema("f")
        .from("solicitacao_item")
        .select("id,solicitacao_id,item_id,codigo_produto,descricao,ncm,cfop,cst_icms,csosn,cst_ipi,ipi_codigo_enquadramento_legal,cst_pis,cst_cofins,cbenef,origem_mercadoria,unidade_tributavel,numero_fci,perfil_operacao_id,reducao_base_icms_percentual,icms_modalidade_base_calculo,aliquota_icms,aliquota_ipi,aliquota_pis,aliquota_cofins,cst_ibs_cbs,cclass_trib,cclass_trib_versao,ibs_cbs_json,quantidade,unidade,valor_unitario,valor_desconto,ordem")
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .eq("origem_tipo", "OV")
        .eq("origem_id", String(ovId))
        .order("ordem", { ascending: true });
      if (itensError) throw itensError;

      const itens = (itensData ?? []) as SolicitacaoItem[];
      const ids = [...new Set(itens.map((item) => item.solicitacao_id))];
      if (ids.length === 0) {
        setDrafts([]);
        setMemoria(null);
        return;
      }

      // A ultima nota ja conferida desta OV, inclusive cancelada: e dela que a
      // proxima herda transportadora, volumes e pesos, em vez de exigir redigitacao.
      //
      // O filtro e snapshot_cadastro_em, nao modalidade_frete: a conferencia sao
      // dois RPCs (revisao fiscal, depois transporte) e uma nota que falhou no
      // segundo fica com modalidade gravada e transporte vazio. Herdar dessa
      // trazia campos em branco enquanto o aviso dizia que os dados vieram.
      // snapshot_cadastro_em so e gravado quando o transporte passou.
      const memoriaResult = await supabase
        .schema("f")
        .from("solicitacao_faturamento")
        .select("id,cliente_id,status,natureza_operacao,finalidade_emissao,consumidor_final,presenca_comprador,modalidade_frete,valor_frete,valor_seguro,valor_outras_despesas,destinacao_mercadoria,pagamento_forma,pagamento_indicador,pagamento_descricao,pagamento_parcelas,pedido_cliente,transportador_dados,volumes_dados,snapshot_cadastro_em,destino_uf_confirmada,created_at")
        .eq("tenant_id", tenantId)
        .eq("empresa_id", empresaId)
        .in("id", ids)
        .not("modalidade_frete", "is", null)
        .not("snapshot_cadastro_em", "is", null)
        .order("created_at", { ascending: false })
        .limit(1);
      setMemoria(
        memoriaResult.error || !memoriaResult.data?.[0]
          ? null
          : memoriaDeSolicitacao(memoriaResult.data[0] as Solicitacao),
      );

      const [solicitacoesResult, emissoesResult] = await Promise.all([
        supabase
          .schema("f")
          .from("solicitacao_faturamento")
          .select("id,cliente_id,status,natureza_operacao,finalidade_emissao,consumidor_final,presenca_comprador,modalidade_frete,valor_frete,valor_seguro,valor_outras_despesas,destinacao_mercadoria,pagamento_forma,pagamento_indicador,pagamento_descricao,pagamento_parcelas,pedido_cliente,transportador_dados,volumes_dados,snapshot_cadastro_em,destino_uf_confirmada,created_at")
          .eq("tenant_id", tenantId)
          .eq("empresa_id", empresaId)
          .in("id", ids)
          .neq("status", "CANCELADA")
          .order("created_at", { ascending: false }),
        supabase
          .schema("f")
          .from("documento_fiscal_emissao")
          .select("documento_fiscal_id,solicitacao_id,referencia_externa,ambiente,status,chave_acesso,protocolo,numero,serie,codigo_status,mensagem,tentativa_count,payload_enviado,enviado_em,ultima_tentativa_em,xml_path,danfe_path,updated_at")
          .eq("tenant_id", tenantId)
          .eq("empresa_id", empresaId)
          .in("solicitacao_id", ids)
          .order("updated_at", { ascending: false }),
      ]);
      if (solicitacoesResult.error) throw solicitacoesResult.error;
      if (emissoesResult.error) throw emissoesResult.error;
      const emissoes = (emissoesResult.data ?? []) as Emissao[];
      const lista = ((solicitacoesResult.data ?? []) as Solicitacao[]).map((solicitacao) => ({
        ...solicitacao,
        itens: itens.filter((item) => item.solicitacao_id === solicitacao.id),
        emissao: emissoes.find((emissao) => emissao.solicitacao_id === solicitacao.id && emissao.ambiente === "PRODUCAO")
          ?? emissoes.find((emissao) => emissao.solicitacao_id === solicitacao.id && emissao.ambiente === "HOMOLOGACAO")
          ?? null,
      }));
      setDrafts(lista);

      // A UF do cliente so chegava em resolucaoPerfis, populado DEPOIS de confirmar
      // o destino — por isso a etapa 1 abria sem nada marcado, mesmo com a UF ja
      // cadastrada. Buscando aqui, a opcao certa ja vem selecionada; confirmar
      // continua sendo um clique seu, que e o controle fiscal que se quer preservar.
      const clienteId = lista.find((draft) => draft.cliente_id)?.cliente_id ?? null;
      if (clienteId) {
        const clienteResult = await supabase
          .from("clientes")
          .select("uf,transportador_padrao_nome,transportador_padrao_documento,transportador_padrao_ie,transportador_padrao_endereco,transportador_padrao_municipio,transportador_padrao_uf,transportador_padrao_modalidade_frete")
          .eq("tenant_id", tenantId)
          .eq("empresa_id", empresaId)
          .eq("id", clienteId)
          .maybeSingle();
        const uf = String(clienteResult.data?.uf ?? "").trim().toUpperCase();
        setUfCliente(/^[A-Z]{2}$/.test(uf) ? uf : null);
        const nomePadrao = String(clienteResult.data?.transportador_padrao_nome ?? "").trim();
        setPadraoTransportador(nomePadrao ? {
          nome: nomePadrao,
          documento: String(clienteResult.data?.transportador_padrao_documento ?? ""),
          ie: String(clienteResult.data?.transportador_padrao_ie ?? ""),
          endereco: String(clienteResult.data?.transportador_padrao_endereco ?? ""),
          municipio: String(clienteResult.data?.transportador_padrao_municipio ?? ""),
          uf: String(clienteResult.data?.transportador_padrao_uf ?? ""),
          modalidade_frete: clienteResult.data?.transportador_padrao_modalidade_frete != null
            ? String(clienteResult.data.transportador_padrao_modalidade_frete)
            : "",
        } : null);
      } else {
        setUfCliente(null);
        setPadraoTransportador(null);
      }

      const statusProducao = await Promise.all(lista.map(async (draft) => {
        const homologacaoAutorizada = emissoes.some((emissao) =>
          emissao.solicitacao_id === draft.id
          && emissao.ambiente === "HOMOLOGACAO"
          && emissao.status === "AUTORIZADA"
        );
        const existeProducao = emissoes.some((emissao) =>
          emissao.solicitacao_id === draft.id && emissao.ambiente === "PRODUCAO"
        );
        if (!homologacaoAutorizada || existeProducao) return [draft.id, null] as const;
        const { data, error } = await supabase.functions.invoke("nfe-emitir-producao", {
          body: { acao: "STATUS", solicitacao_id: draft.id },
        });
        if (error) {
          return [draft.id, { pronta: false, motivo: "Não foi possível conferir a liberação de produção." }] as const;
        }
        return [draft.id, data as ProducaoStatus] as const;
      }));
      setProducaoStatus(Object.fromEntries(
        statusProducao.filter((entry) => entry[1] !== null),
      ) as Record<string, ProducaoStatus>);
    } catch (cause) {
      setFeedback((current) => ({ ...current, geral: textoErro(cause) }));
      setDrafts([]);
    } finally {
      setLoading(false);
    }
  }, [empresaId, ovId, supabase, tenantId]);

  useEffect(() => {
    void carregar();
  }, [carregar, refreshKey]);

  useEffect(() => {
    if (!empresaId) return;
    const channel = supabase
      .channel(`ov-nfe-${empresaId}-${ovId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "f", table: "documento_fiscal_emissao", filter: `empresa_id=eq.${empresaId}` },
        () => void carregar()
      )
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [carregar, empresaId, ovId, supabase]);

  useEffect(() => {
    const processando = drafts.some((draft) => ["ENVIANDO", "PROCESSANDO"].includes(draft.emissao?.status ?? ""));
    if (!processando) return;
    const timer = window.setInterval(() => void carregar(), 5000);
    return () => window.clearInterval(timer);
  }, [carregar, drafts]);

  // Contexto de entrega das notas reais autorizadas: busca uma vez por documento,
  // quando a nota aparece. So producao — homologacao nao se manda para cliente.
  useEffect(() => {
    const pendentes = drafts
      .map((draft) => draft.emissao)
      .filter((emissao) => emissao
        && emissao.ambiente === "PRODUCAO"
        && emissao.status === "AUTORIZADA"
        && !entregas[emissao.documento_fiscal_id]);
    if (pendentes.length === 0) return;
    let ativo = true;
    for (const emissao of pendentes) {
      const documentoId = emissao!.documento_fiscal_id;
      void supabase.schema("f").rpc("fn_nfe_ciclo_contexto", { p_documento_fiscal_id: documentoId })
        .then(({ data }) => {
          if (!ativo) return;
          const ctx = (data ?? null) as EntregaCtx | null;
          const enviado = ctx?.eventos?.find((ev) => ev.tipo === "EMAIL" && !/ERRO|REJEIT|FALH/i.test(ev.status))?.destinatarios ?? null;
          setEntregas((atual) => atual[documentoId] ? atual : {
            ...atual,
            [documentoId]: { ctx, emails: emailPadraoCliente(ctx), enviadoPara: enviado, enviando: false },
          });
        });
    }
    return () => { ativo = false; };
  }, [drafts, entregas, supabase]);

  async function enviarEntrega(draft: Draft) {
    const emissao = draft.emissao;
    if (!emissao) return;
    const documentoId = emissao.documento_fiscal_id;
    const entrega = entregas[documentoId];
    const destinatarios = separarEmails(entrega?.emails ?? "");
    if (!destinatarios.length) { avisar(draft.id, "Informe ao menos um e-mail para a entrega.", true); return; }
    const rotuloNota = `${emissao.serie ?? ""}/${emissao.numero ?? ""}`;
    if (!window.confirm(
      `Enviar XML e DANFE da NF-e ${rotuloNota} para:\n\n${destinatarios.join("\n")}\n\nConfirme somente após revisar os dois arquivos.`,
    )) return;
    setEntregas((atual) => ({ ...atual, [documentoId]: { ...atual[documentoId], enviando: true } }));
    avisar(draft.id, "");
    try {
      const { data, error } = await supabase.functions.invoke("nfe-ciclo", {
        body: { acao: "EMAIL", emails: destinatarios, documento_fiscal_id: documentoId },
      });
      if (error) throw error;
      if (data?.error) throw new Error(String(data.error));
      setEntregas((atual) => ({
        ...atual,
        [documentoId]: { ...atual[documentoId], enviando: false, enviadoPara: destinatarios },
      }));
      avisar(draft.id, `XML e DANFE da NF-e ${rotuloNota} enviados para ${destinatarios.join(", ")}.`);
    } catch (cause) {
      setEntregas((atual) => ({ ...atual, [documentoId]: { ...atual[documentoId], enviando: false } }));
      avisar(draft.id, await erroFunction(cause), true);
    }
  }

  function abrirConferencia(draft: Draft, ambiente: "HOMOLOGACAO" | "PRODUCAO" = "HOMOLOGACAO") {
    setAmbienteConferencia(ambiente);
    setOpenId(draft.id);
    setOperacao(formOperacao(draft, memoria, padraoTransportador));
    setItensForm(draft.itens.map(formItem));
    setEtapaConferencia("DESTINO");
    // Ordem: o que a nota ja confirmou; senao a UF do cadastro do cliente como
    // sugestao; senao nada. Sugerir nao confirma — o clique continua obrigatorio.
    const ufBase = draft.destino_uf_confirmada || ufCliente || "";
    setDestinoTipo(ufBase ? (ufBase === "SC" ? "SC" : "FORA") : "");
    setDestinoUf(ufBase && ufBase !== "SC" ? ufBase : "");
    setResolucaoPerfis(null);
    avisar(draft.id, "");
    setPendencias((current) => ({ ...current, [draft.id]: [] }));
  }

  function atualizarItem(id: string, patch: Partial<ItemForm>) {
    setItensForm((current) => current.map((item) => item.id === id ? { ...item, ...patch } : item));
  }

  async function confirmarDestino(draft: Draft) {
    const uf = destinoTipo === "SC" ? "SC" : destinoUf.trim().toUpperCase();
    if (!destinoTipo || (destinoTipo === "FORA" && !/^[A-Z]{2}$/.test(uf))) {
      avisar(draft.id, "Selecione se o destino é Santa Catarina ou informe a UF de destino.", true);
      return;
    }
    const destinacao = operacao?.destinacao_mercadoria_confirmada?.trim() ?? "";
    if (!destinacao) {
      avisar(draft.id, "Informe a destinação da mercadoria: ela decide a alíquota interna de ICMS.", true);
      return;
    }
    setResolvendoDestino(true);
    avisar(draft.id, "");
    try {
      // A destinacao vai por parametro porque a resolucao acontece antes de
      // gravar: e ela que escolhe entre o perfil de 12% e o de 17%.
      const { data, error } = await supabase.schema("f").rpc("fn_solicitacao_nfe_resolver_perfis", {
        p_solicitacao_id: draft.id,
        p_destino_uf: uf,
        p_destinacao: destinacao,
      });
      if (error) throw error;
      const resolucao = data as ResolucaoPerfis;
      if (!resolucao?.ok) {
        setResolucaoPerfis(resolucao);
        avisar(draft.id, resolucao?.bloqueio || "Não foi possível confirmar o destino fiscal.", true);
        return;
      }
      const porId = new Map((resolucao.itens ?? []).map((item) => [item.solicitacao_item_id, item]));
      setItensForm((current) => current.map((item) => {
        const resolvido = porId.get(item.id);
        return resolvido ? aplicarPerfilNoItem(item, resolvido, resolucao.ambito, draft.natureza_operacao) : item;
      }));
      const perfilCabecalho = perfilCabecalhoUnico(resolucao);
      setOperacao((current) => current ? {
        ...current,
        destino_uf_confirmada: uf,
        finalidade_emissao: perfilCabecalho?.finalidade_emissao?.toString() ?? current.finalidade_emissao,
        consumidor_final: perfilCabecalho?.consumidor_final?.toString() ?? current.consumidor_final,
      } : current);
      setResolucaoPerfis(resolucao);
      setEtapaConferencia("FISCAL");
    } catch (cause) {
      avisar(draft.id, textoErro(cause), true);
    } finally {
      setResolvendoDestino(false);
    }
  }

  function alterarDestino(draft: Draft) {
    setEtapaConferencia("DESTINO");
    setResolucaoPerfis(null);
    setOperacao(formOperacao(draft, memoria, padraoTransportador));
    setItensForm(draft.itens.map(formItem));
    avisar(draft.id, "");
  }

  async function salvarEEmitir(draft: Draft) {
    if (!operacao) return;
    if (etapaConferencia !== "FISCAL" || !resolucaoPerfis?.ok || !operacao.destino_uf_confirmada) {
      avisar(draft.id, "Confirme primeiro o destino fiscal da NF-e.", true);
      return;
    }
    const camposPendentes = camposObrigatoriosPendentes(operacao, itensForm);
    if (camposPendentes.length > 0) {
      setFeedback((current) => ({
        ...current,
        [draft.id]: `Preencha os campos obrigatórios antes de emitir: ${camposPendentes.join("; ")}.`,
      }));
      return;
    }
    let confirmacaoContextoHash: string | null = null;
    if (ambienteConferencia === "PRODUCAO") {
      setBusyId(draft.id);
      const { data: statusData, error: statusError } = await supabase.functions.invoke("nfe-emitir-producao", {
        body: { acao: "STATUS", solicitacao_id: draft.id },
      });
      const statusAtual = statusData as ProducaoStatus | null;
      const resumo = statusAtual?.resumo_confirmacao;
      if (statusError || !statusAtual?.pronta || !statusAtual.preflight_confirmacao_pronto || !resumo) {
        const motivo = statusError ? await erroFunction(statusError) : statusAtual?.motivo;
        setFeedback((current) => ({
          ...current,
          [draft.id]: motivo || "A confirmação de produção não pôde ser montada a partir do snapshot homologado.",
        }));
        setBusyId(null);
        return;
      }
      if (typeof resumo.contexto_hash !== "string" || !/^[0-9a-f]{64}$/.test(resumo.contexto_hash)) {
        avisar(draft.id, "O preflight de produção não devolveu um hash fiscal válido.", true);
        setBusyId(null);
        return;
      }
      setProducaoStatus((current) => ({ ...current, [draft.id]: statusAtual }));
      confirmacaoContextoHash = resumo.contexto_hash;
      const documento = [resumo.tipo_documento_destinatario, resumo.documento_destinatario_mascarado]
        .filter(Boolean)
        .join(" ");
      // Sem OC a nota sai valida, mas o cliente costuma recusar no recebimento e a
      // cobranca trava — foi o que derrubou a NF-e 2/13 (11/09/2026), cancelada
      // horas depois so por isso. Nao bloqueia: pergunta antes, porque venda sem
      // pedido formal existe. O aviso vem primeiro para a pessoa poder desistir sem
      // passar pela confirmacao da emissao real.
      if (!String(draft.pedido_cliente ?? "").trim()) {
        const seguirSemOc = window.confirm(
          "Esta nota vai sair SEM PEDIDO DE COMPRA do cliente.\n\n"
          + "A NF-e é válida assim, mas o cliente costuma recusar o recebimento sem a OC e a cobrança fica travada.\n\n"
          + "Deseja continuar mesmo sem o pedido de compra?",
        );
        if (!seguirSemOc) {
          setBusyId(null);
          return;
        }
      }
      const confirmou = window.confirm(
        `CONFIRMAÇÃO DE EMISSÃO FISCAL REAL\n\nAmbiente: PRODUÇÃO\nDestinatário do snapshot homologado: ${resumo.nome_destinatario || "não informado"}\n${documento ? `${documento}\n` : ""}Total: R$ ${formatMoneyBR(numero(resumo.valor_total))}\n\nA NF-e será transmitida com validade fiscal. Deseja continuar?`,
      );
      if (!confirmou) {
        setBusyId(null);
        return;
      }
    }
    setBusyId(draft.id);
    avisar(draft.id, "");
    setPendencias((current) => ({ ...current, [draft.id]: [] }));
    try {
      const emissaoHomologacaoIntocada = draft.emissao?.ambiente === "HOMOLOGACAO"
        && draft.emissao.status === "RASCUNHO"
        && numero(draft.emissao.tentativa_count) === 0
        && !draft.emissao.payload_enviado
        && !draft.emissao.enviado_em
        && !draft.emissao.ultima_tentativa_em;
      if (ambienteConferencia === "HOMOLOGACAO" && (!draft.emissao || emissaoHomologacaoIntocada)) {
        const operacaoPayload = {
          ...operacao,
          destinacao_mercadoria: operacao.destinacao_mercadoria_confirmada,
          pagamento_parcelas: operacao.pagamento_indicador === "1"
            ? operacao.pagamento_parcelas.map((parcela, indice) => ({
                numero: String(indice + 1).padStart(3, "0"),
                dias: Number(parcela.dias.trim()),
                valor: parcela.valor.trim() ? paraNumero(parcela.valor) : null,
              }))
            : null,
          modalidade_frete: operacao.modalidade_frete === "9" ? "9" : operacao.modalidade_frete,
          valor_frete: paraNumero(operacao.valor_frete),
          valor_seguro: paraNumero(operacao.valor_seguro),
          valor_outras_despesas: paraNumero(operacao.valor_outras_despesas),
          transportador: operacao.modalidade_frete !== "9" && operacao.transportador_nome.trim() ? {
            nome: operacao.transportador_nome.trim(),
            documento: operacao.transportador_documento.trim() || null,
            inscricao_estadual: operacao.transportador_ie.trim() || null,
            endereco: operacao.transportador_endereco.trim() || null,
            municipio: operacao.transportador_municipio.trim() || null,
            uf: operacao.transportador_uf.trim().toUpperCase() || null,
          } : null,
          volumes: operacao.modalidade_frete !== "9" ? [{
              quantidade: paraNumero(operacao.volume_quantidade),
              especie: operacao.volume_especie.trim(),
              marca: operacao.volume_marca.trim(),
              numero: operacao.volume_numero.trim(),
              peso_liquido: paraNumero(operacao.volume_peso_liquido),
              peso_bruto: paraNumero(operacao.volume_peso_bruto),
            }] : [],
        };
        const itensPayload = itensForm.map((item) => ({
          ...item,
          reducao_base_icms_percentual: paraNumero(item.reducao_base_icms_percentual),
          aliquota_icms: paraNumero(item.aliquota_icms),
          aliquota_ipi: paraNumero(item.aliquota_ipi),
          aliquota_pis: paraNumero(item.aliquota_pis),
          aliquota_cofins: paraNumero(item.aliquota_cofins),
          cst_ibs_cbs: item.cst_ibs_cbs,
          cclass_trib: item.cclass_trib,
          numero_fci: item.numero_fci,
          ibs_cbs_json: {
            ibs_uf_aliquota: paraNumero(item.aliquota_ibs_uf),
            ibs_mun_aliquota: paraNumero(item.aliquota_ibs_mun),
            cbs_aliquota: paraNumero(item.aliquota_cbs),
          },
        }));
        const { error: salvarError } = await supabase.schema("f").rpc("fn_solicitacao_nfe_salvar_conferencia_2026", {
          p_solicitacao_id: draft.id,
          p_operacao: operacaoPayload,
          p_itens: itensPayload,
        });
        if (salvarError) throw salvarError;

        const { error: transporteError } = await supabase.schema("f").rpc("fn_solicitacao_nfe_salvar_transporte", {
          p_solicitacao_id: draft.id,
          p_transporte: {
            transportador: operacaoPayload.transportador,
            volumes: operacaoPayload.volumes,
          },
        });
        if (transporteError) throw transporteError;

        // Padrao do cliente: quem transporta pra ele nao muda venda a venda, entao a
        // transportadora e a modalidade confirmadas aqui passam a ser a sugestao da
        // proxima OV deste cliente (public.clientes.transportador_padrao_*). Peso e
        // volumes ficam de fora — so a memoria da propria OV cobre esses.
        // Nao bloqueia a emissao se falhar: e conveniencia, a nota ja foi conferida.
        if (draft.cliente_id && operacaoPayload.transportador) {
          const { error: padraoError } = await supabase.rpc("clientes_salvar_transportador_padrao", {
            p_cliente_id: draft.cliente_id,
            p_nome: operacaoPayload.transportador.nome,
            p_documento: operacaoPayload.transportador.documento,
            p_ie: operacaoPayload.transportador.inscricao_estadual,
            p_endereco: operacaoPayload.transportador.endereco,
            p_municipio: operacaoPayload.transportador.municipio,
            p_uf: operacaoPayload.transportador.uf,
            p_modalidade_frete: Number(operacao.modalidade_frete),
            p_empresa_id: empresaId,
          });
          if (padraoError) console.error("Nao foi possivel salvar a transportadora padrao do cliente:", padraoError);
        }

        const { data: validacao, error: validarError } = await supabase
          .schema("f")
          .rpc("fn_solicitacao_nfe_congelar_cadastro", { p_solicitacao_id: draft.id });
        if (validarError) throw validarError;
        const resultado = validacao as { ok?: boolean; pendencias?: Pendencia[] } | null;
        if (!resultado?.ok) {
          const lista = Array.isArray(resultado?.pendencias) ? resultado.pendencias : [];
          setPendencias((current) => ({ ...current, [draft.id]: lista }));
          avisar(draft.id, "A conferência foi salva, mas o cadastro ainda precisa das correções abaixo.", true);
          await carregar();
          return;
        }
      }

      const funcao = ambienteConferencia === "PRODUCAO" ? "nfe-emitir-producao" : "nfe-emitir";
      const { data, error: emitirError } = await supabase.functions.invoke(funcao, {
        body: ambienteConferencia === "PRODUCAO"
          ? { acao: "EMITIR", solicitacao_id: draft.id, confirmacao_contexto_hash: confirmacaoContextoHash }
          : { solicitacao_id: draft.id },
      });
      if (emitirError) throw emitirError;
      if (data?.erro) throw new Error(data.codigo ? `cStat ${data.codigo} · ${data.erro}` : String(data.erro));
      avisar(
        draft.id,
        ambienteConferencia === "PRODUCAO"
          ? "Solicitação enviada à Focus em ambiente de produção."
          : "Solicitação enviada à Focus em ambiente de homologação.",
      );
      setOpenId(null);
      await carregar();
      onChanged?.();
    } catch (cause) {
      const mensagem = await erroFunction(cause);
      avisar(draft.id, mensagem, true);
      await carregar();
    } finally {
      setBusyId(null);
    }
  }

  async function descartarRascunho(draft: Draft, totalNota: number) {
    const justificativa = justificativaDescarte.trim();
    if (justificativa.length < 15 || justificativa.length > 255) {
      setFeedback((current) => ({
        ...current,
        [draft.id]: "A justificativa do descarte deve ter entre 15 e 255 caracteres.",
      }));
      return;
    }
    const confirmou = window.confirm(
      `Confirmar descarte auditável do rascunho?\n\nDestinatário: ${clienteNome}\nTotal: R$ ${formatMoneyBR(totalNota)}\n\nA solicitação será cancelada e o saldo voltará a ficar disponível.`,
    );
    if (!confirmou) return;

    setBusyId(draft.id);
    avisar(draft.id, "");
    try {
      const { data, error } = await supabase.schema("f").rpc("fn_solicitacao_nfe_cancelar_rascunho", {
        p_solicitacao_id: draft.id,
        p_motivo: justificativa,
      });
      if (error) throw error;
      if (data && typeof data === "object" && "ok" in data && !(data as { ok?: boolean }).ok) {
        throw new Error(String((data as { motivo?: unknown }).motivo ?? "O rascunho não pôde ser descartado."));
      }
      setDescarteId(null);
      setJustificativaDescarte("");
      await carregar();
      onChanged?.();
    } catch (cause) {
      avisar(draft.id, textoErro(cause), true);
    } finally {
      setBusyId(null);
    }
  }

  async function abandonarHomologacao(draft: Draft, totalNota: number) {
    const justificativa = justificativaDescarte.trim();
    if (justificativa.length < 15 || justificativa.length > 255) {
      setFeedback((current) => ({
        ...current,
        [draft.id]: "A justificativa do abandono deve ter entre 15 e 255 caracteres.",
      }));
      return;
    }
    const confirmou = window.confirm(
      `Abandonar esta emissão de HOMOLOGAÇÃO e devolver o saldo?\n\nDestinatário: ${clienteNome}\nTotal: R$ ${formatMoneyBR(totalNota)}\n\nA NF-e continua autorizada na SEFAZ de homologação — ela não tem valor fiscal e nada precisa ser regularizado. O que se desfaz é a reserva da OV, liberando o saldo para uma nova solicitação.`,
    );
    if (!confirmou) return;

    setBusyId(draft.id);
    avisar(draft.id, "");
    try {
      const { data, error } = await supabase.schema("f").rpc("fn_solicitacao_nfe_abandonar_homologacao", {
        p_solicitacao_id: draft.id,
        p_motivo: justificativa,
      });
      if (error) throw error;
      if (data && typeof data === "object" && "ok" in data && !(data as { ok?: boolean }).ok) {
        throw new Error(String((data as { motivo?: unknown }).motivo ?? "A emissão não pôde ser abandonada."));
      }
      setDescarteId(null);
      setJustificativaDescarte("");
      await carregar();
      onChanged?.();
    } catch (cause) {
      avisar(draft.id, textoErro(cause), true);
    } finally {
      setBusyId(null);
    }
  }

  async function abandonarRejeitada(draft: Draft, totalNota: number) {
    if (!draft.emissao || !["REJEITADA", "ERRO"].includes(draft.emissao.status)) return;
    const justificativa = justificativaDescarte.trim();
    if (justificativa.length < 15 || justificativa.length > 255) {
      setFeedback((current) => ({
        ...current,
        [draft.id]: "A justificativa do abandono deve ter entre 15 e 255 caracteres.",
      }));
      return;
    }
    const confirmou = window.confirm(
      `Confirmar consulta e eventual abandono auditável desta NF-e?\n\nEstado local: ${draft.emissao.status}\nAmbiente: ${draft.emissao.ambiente}\nDestinatário: ${clienteNome}\nTotal reservado: R$ ${formatMoneyBR(totalNota)}\n\nO servidor consultará novamente a referência na Focus. O saldo só será liberado se a rejeição for conclusivamente confirmada.`,
    );
    if (!confirmou) return;

    setBusyId(draft.id);
    avisar(draft.id, "");
    try {
      const funcao = draft.emissao.ambiente === "PRODUCAO" ? "nfe-emitir-producao" : "nfe-emitir";
      const { data, error } = await supabase.functions.invoke(funcao, {
        body: { acao: "ABANDONAR_REJEITADA", solicitacao_id: draft.id, justificativa },
      });
      if (error) throw error;
      if (data?.erro) throw new Error(String(data.erro));
      setDescarteId(null);
      setJustificativaDescarte("");
      setFeedback((current) => ({
        ...current,
        [draft.id]: "Rejeição confirmada no provedor; tentativa encerrada com auditoria e saldo liberado.",
      }));
      await carregar();
      onChanged?.();
    } catch (cause) {
      const mensagem = await erroFunction(cause);
      avisar(draft.id, mensagem, true);
    } finally {
      setBusyId(null);
    }
  }

  async function abrirArquivo(draft: Draft, arquivo: "DANFE" | "XML") {
    if (!draft.emissao) return;
    const novaAba = window.open("about:blank", "_blank");
    if (novaAba) novaAba.opener = null;
    setBusyId(draft.id);
    avisar(draft.id, "");
    try {
      const { data, error } = await supabase.functions.invoke("nfe-ciclo", {
        body: { acao: "ARQUIVO", arquivo, documento_fiscal_id: draft.emissao.documento_fiscal_id },
      });
      if (error) throw error;
      if (!data?.url) throw new Error(`${arquivo} ainda não está disponível.`);
      if (!novaAba) throw new Error(`O navegador bloqueou a abertura do ${arquivo}. Libere pop-ups para este sistema.`);
      novaAba.location.replace(String(data.url));
    } catch (cause) {
      novaAba?.close();
      avisar(draft.id, textoErro(cause), true);
    } finally {
      setBusyId(null);
    }
  }

  if (loading && drafts.length === 0) {
    return <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 text-sm text-zinc-500">Carregando rascunhos de NF-e...</div>;
  }
  if (drafts.length === 0) return null;

  return (
    <div className="space-y-4">
      {feedback.geral ? <div role="alert" className="rounded-lg border border-red-900 bg-red-950/30 p-3 text-sm text-red-300">{feedback.geral}</div> : null}
      {drafts.map((draft) => {
        const totalNota = totalNotaNfe(
          draft.itens,
          draft.valor_frete,
          draft.valor_seguro,
          draft.valor_outras_despesas,
        );
        const rejeitada = draft.emissao?.status === "REJEITADA" || draft.emissao?.status === "ERRO";
        const autorizada = draft.emissao?.status === "AUTORIZADA";
        const processando = draft.emissao?.status === "ENVIANDO" || draft.emissao?.status === "PROCESSANDO";
        const homologacaoAutorizada = autorizada && draft.emissao?.ambiente === "HOMOLOGACAO";
        // Nota real autorizada: e a unica que se entrega ao cliente.
        const producaoAutorizada = autorizada && draft.emissao?.ambiente === "PRODUCAO";
        const entrega = draft.emissao ? entregas[draft.emissao.documento_fiscal_id] : undefined;
        const podeDescartar = podeEmitir && (
          !draft.emissao
          || (
            draft.emissao.ambiente === "HOMOLOGACAO"
            && draft.emissao.status === "RASCUNHO"
            && numero(draft.emissao.tentativa_count) === 0
            && !draft.emissao.payload_enviado
            && !draft.emissao.enviado_em
            && !draft.emissao.ultima_tentativa_em
          )
        );
        const podeAbandonarRejeitada = podeEmitir && ["REJEITADA", "ERRO"].includes(draft.emissao?.status ?? "");
        // Rejeicao em homologacao nao autorizou nada e nao consumiu numero na SEFAZ:
        // o certo e corrigir o que ela apontou e mandar de novo, nao jogar fora a
        // solicitacao. O servidor cunha uma referencia nova e descarta o payload
        // recusado quando a Focus confirma a rejeicao (f.fn_nfe_recomecar_rejeitada),
        // entao daqui basta reabrir a conferencia. Producao continua congelada.
        const podeRefazerRejeitada = podeEmitir
          && rejeitada
          && draft.emissao?.ambiente === "HOMOLOGACAO";
        // Homologacao autorizada nao tem existencia fiscal (tpAmb=2, base separada da
        // SEFAZ, sem SPED, sem ICMS) — nao ha o que regularizar. Mesmo assim ela segurava
        // o saldo da OV para sempre, porque so status CANCELADA devolve reserva. Aqui a
        // reserva de negocio e liberada sem tocar na emissao, que segue AUTORIZADA.
        const podeAbandonarHomologacao = podeEmitir && homologacaoAutorizada;
        const podeContinuarConferencia = podeEmitir
          && draft.emissao?.ambiente === "HOMOLOGACAO"
          && draft.emissao.status === "RASCUNHO"
          && numero(draft.emissao.tentativa_count) === 0
          && !draft.emissao.payload_enviado
          && !draft.emissao.enviado_em
          && !draft.emissao.ultima_tentativa_em;
        const justificativaDescarteValida = justificativaDescarte.trim().length >= 15
          && justificativaDescarte.trim().length <= 255;
        const liberacaoProducao = producaoStatus[draft.id];
        const perfisDoRascunho = [...new Set(
          draft.itens.map((item) => item.perfil_operacao_id).filter((id): id is string => Boolean(id)),
        )];
        const perfilCabecalho = openId === draft.id ? perfilCabecalhoUnico(resolucaoPerfis) : null;
        const todosPerfisResolvidos = etapaConferencia === "FISCAL"
          && Boolean(resolucaoPerfis?.ok)
          && (resolucaoPerfis?.itens?.length ?? 0) === draft.itens.length
          && (resolucaoPerfis?.itens ?? []).every((item) => item.status === "RESOLVIDO");
        const camposPendentesConferencia = openId === draft.id && operacao
          ? camposObrigatoriosPendentes(operacao, itensForm)
          : [];
        const aliquotasIpiConferencia = new Map(itensForm.map((item) => [item.id, paraNumero(item.aliquota_ipi)]));
        const totalConferencia = openId === draft.id && operacao
          ? totalNotaNfe(
              draft.itens.map((item) => ({
                ...item,
                aliquota_ipi: aliquotasIpiConferencia.get(item.id) ?? item.aliquota_ipi,
              })),
              paraNumero(operacao.valor_frete),
              paraNumero(operacao.valor_seguro),
              paraNumero(operacao.valor_outras_despesas),
            )
          : totalNota;
        return (
          <article key={draft.id} className="overflow-hidden rounded-xl border border-sky-900/70 bg-sky-950/10">
            <div className="flex flex-wrap items-start justify-between gap-3 border-b border-zinc-800 p-4">
              <div>
                <div className="text-xs font-medium uppercase tracking-wide text-sky-300">NF-e · {draft.emissao?.ambiente === "PRODUCAO" ? "produção" : "homologação"}</div>
                <h3 className="mt-1 font-semibold text-zinc-100">{clienteNome}</h3>
                <div className="mt-1 font-mono text-xs text-zinc-500">Rascunho {draft.id.slice(0, 8)}</div>
              </div>
              <span className={`rounded-full border px-3 py-1 text-xs ${autorizada ? "border-emerald-800 text-emerald-300" : rejeitada ? "border-red-800 text-red-300" : processando ? "border-amber-800 text-amber-300" : "border-zinc-700 text-zinc-300"}`}>
                {statusLabel(draft.status, draft.emissao)}
              </span>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full min-w-[720px] text-sm">
                <thead className="bg-zinc-900/60 text-left text-xs uppercase text-zinc-500">
                  <tr><th className="px-4 py-2">Item</th><th className="px-4 py-2 text-right">Quantidade</th><th className="px-4 py-2 text-right">Valor unitário</th><th className="px-4 py-2 text-right">Total</th></tr>
                </thead>
                <tbody className="divide-y divide-zinc-900">
                  {draft.itens.map((item) => (
                    <tr key={item.id}>
                      <td className="px-4 py-3"><div className="font-medium text-zinc-100">{item.item_id ? <Link href={`/itens?id=${item.item_id}&editar=1&aba=fiscal&retorno=/comercial/vendas/${ovId}`} className="hover:text-sky-300 hover:underline">{item.descricao}</Link> : item.descricao}</div><div className="text-xs text-zinc-500">{item.codigo_produto || (item.item_id ? `Item ${item.item_id}` : "Item avulso")}</div></td>
                      <td className="px-4 py-3 text-right tabular-nums">{numero(item.quantidade).toLocaleString("pt-BR", { maximumFractionDigits: 4 })} {item.unidade}</td>
                      <td className="px-4 py-3 text-right tabular-nums">R$ {formatMoneyBR(numero(item.valor_unitario))}</td>
                      <td className="px-4 py-3 text-right font-medium tabular-nums">R$ {formatMoneyBR(numero(item.quantidade) * numero(item.valor_unitario) - numero(item.valor_desconto))}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="space-y-3 border-t border-zinc-800 p-4">
              <div className="flex flex-wrap items-end justify-between gap-3">
                <div className="text-sm text-zinc-400">{draft.itens.length} item(ns) · preço definido no rascunho</div>
                <div className="text-right"><div className="text-xs uppercase text-zinc-500">Total da NF-e</div><div className="text-xl font-semibold tabular-nums">R$ {formatMoneyBR(totalNota)}</div></div>
              </div>

              {draft.emissao ? (
                <div className="grid gap-2 rounded-lg border border-zinc-800 bg-zinc-950/70 p-3 text-sm md:grid-cols-2">
                  <div><span className="text-zinc-500">Status:</span> {statusLabel(draft.status, draft.emissao)}</div>
                  <div><span className="text-zinc-500">Número:</span> {draft.emissao.numero ? `${draft.emissao.serie ?? "—"}/${draft.emissao.numero}` : "aguardando"}</div>
                  <div className="break-all md:col-span-2"><span className="text-zinc-500">Chave:</span> <span className="font-mono text-xs">{draft.emissao.chave_acesso || "aguardando"}</span></div>
                  {rejeitada ? <div role="alert" className="rounded border border-red-900 bg-red-950/30 p-3 text-red-200 md:col-span-2"><strong>cStat {draft.emissao.codigo_status ?? "não informado"}</strong><div className="mt-1">xMotivo: {draft.emissao.mensagem || "A SEFAZ não devolveu uma descrição."}</div></div> : null}
                </div>
              ) : null}

              {feedback[draft.id] ? (() => {
                // Uma emissão que falha deixa a nota em RASCUNHO, então `rejeitada` é
                // falso e o erro saía pintado igual ao sucesso. Quem manda agora é a
                // origem da mensagem, não o status da emissão.
                const ehErro = feedbackErro[draft.id] || rejeitada;
                return (
                  <div
                    role={ehErro ? "alert" : "status"}
                    className={`rounded border p-3 text-sm ${ehErro ? "border-red-900 bg-red-950/30 text-red-200" : "border-sky-900 bg-sky-950/30 text-sky-200"}`}
                  >
                    {ehErro ? <span className="mr-1 font-medium">Falha:</span> : null}
                    {feedback[draft.id]}
                  </div>
                );
              })() : null}
              {(pendencias[draft.id]?.length ?? 0) > 0 ? (
                <div className="rounded-lg border border-amber-800 bg-amber-950/20 p-3">
                  <div className="text-sm font-medium text-amber-200">Correções necessárias antes do envio</div>
                  <ul className="mt-2 space-y-1 text-sm text-amber-100/90">
                    {pendencias[draft.id].map((item, index) => <li key={`${item.campo}-${index}`}>• {item.mensagem || item.campo}{item.rota && !item.rota.startsWith("/faturamento/solicitacoes/") ? <> · <Link href={item.rota} className="underline">corrigir cadastro</Link></> : null}</li>)}
                  </ul>
                </div>
              ) : null}

              {homologacaoAutorizada && liberacaoProducao && !liberacaoProducao.pronta ? (
                <div className="rounded-lg border border-amber-900 bg-amber-950/20 p-3 text-sm text-amber-200">
                  <div>Produção ainda protegida: {liberacaoProducao.motivo || "faltam as liberações de produção."}</div>
                  {perfisDoRascunho.length > 0 ? (
                    <div className="mt-2 flex flex-wrap gap-2">
                      {perfisDoRascunho.map((perfilId, index) => (
                        <Link
                          key={perfilId}
                          href={`/faturamento/perfis?perfil=${perfilId}&solicitacao=${draft.id}&retorno=/comercial/vendas/${ovId}`}
                          className="rounded border border-amber-700 px-2 py-1 text-xs font-medium underline hover:bg-amber-950/40"
                        >
                          {perfisDoRascunho.length === 1 ? "Revisar e liberar o perfil fiscal" : `Revisar e liberar perfil ${index + 1}`}
                        </Link>
                      ))}
                    </div>
                  ) : null}
                </div>
              ) : null}

              {draft.emissao?.ambiente === "PRODUCAO" && rejeitada ? (
                <div className="rounded-lg border border-amber-900 bg-amber-950/20 p-3 text-sm text-amber-200">
                  A tentativa de produção está congelada para auditoria e não pode ser editada nesta solicitação. Abra os detalhes para reconciliar o retorno antes de decidir uma nova homologação.
                </div>
              ) : null}

              {descarteId === draft.id && (podeDescartar || podeAbandonarRejeitada || podeAbandonarHomologacao) ? (
                <div className="space-y-3 rounded-lg border border-red-900/70 bg-red-950/20 p-3">
                  <div>
                    <div className="text-sm font-medium text-red-200">{podeAbandonarRejeitada
                      ? "Reconciliar e abandonar somente com prova do provedor"
                      : podeAbandonarHomologacao
                        ? "Abandonar emissão de homologação e devolver o saldo"
                        : "Descartar rascunho com registro de auditoria"}</div>
                    <p className="mt-1 text-xs text-zinc-400">{podeAbandonarRejeitada
                      ? "A referência será consultada novamente. O saldo só volta se a Focus confirmar o estado REJEITADA; erro, 404 ou processamento mantêm o bloqueio."
                      : podeAbandonarHomologacao
                        ? "A NF-e continua autorizada na SEFAZ de homologação e o histórico é preservado — ela não tem valor fiscal e nada precisa ser regularizado. O que se desfaz é a reserva desta OV, liberando o saldo para uma nova solicitação."
                        : "Informe por que esta solicitação deve ser cancelada. O saldo reservado voltará a ficar disponível."}</p>
                  </div>
                  <label className="block text-xs text-zinc-400">
                    Justificativa
                    <textarea
                      value={justificativaDescarte}
                      onChange={(event) => setJustificativaDescarte(event.target.value)}
                      minLength={15}
                      maxLength={255}
                      rows={3}
                      className={`${field} mt-1 resize-y`}
                      placeholder="Descreva o motivo do descarte (15 a 255 caracteres)"
                    />
                  </label>
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className={`text-xs ${justificativaDescarteValida ? "text-emerald-300" : "text-zinc-500"}`}>{justificativaDescarte.trim().length}/255 caracteres</span>
                    <div className="flex gap-2">
                      <button type="button" onClick={() => { setDescarteId(null); setJustificativaDescarte(""); }} disabled={busyId === draft.id} className="rounded-md border border-zinc-700 px-3 py-2 text-sm hover:bg-zinc-900 disabled:opacity-40">Manter rascunho</button>
                      <button
                        type="button"
                        onClick={() => void (podeAbandonarRejeitada
                          ? abandonarRejeitada(draft, totalNota)
                          : podeAbandonarHomologacao
                            ? abandonarHomologacao(draft, totalNota)
                            : descartarRascunho(draft, totalNota))}
                        disabled={busyId === draft.id || !justificativaDescarteValida}
                        className="rounded-md border border-red-800 bg-red-950/40 px-3 py-2 text-sm text-red-200 hover:bg-red-950/70 disabled:opacity-40"
                      >
                        {podeAbandonarRejeitada
                          ? "Consultar, comprovar e abandonar"
                          : podeAbandonarHomologacao
                            ? "Abandonar e devolver saldo"
                            : "Confirmar descarte"}
                      </button>
                    </div>
                  </div>
                </div>
              ) : null}

              {producaoAutorizada ? (
                <div className="space-y-2 rounded-lg border border-emerald-900/60 bg-emerald-950/10 p-3">
                  <div className="text-sm font-medium text-emerald-200">Entregar ao cliente</div>
                  <p className="text-xs text-zinc-400">A Focus envia XML e DANFE anexados. Confirme depois de revisar os dois arquivos acima.</p>
                  <input
                    className="w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none focus:border-sky-500"
                    value={entrega?.emails ?? ""}
                    onChange={(event) => setEntregas((atual) => ({
                      ...atual,
                      [draft.emissao!.documento_fiscal_id]: { ...atual[draft.emissao!.documento_fiscal_id], emails: event.target.value },
                    }))}
                    placeholder="E-mails separados por vírgula"
                  />
                  <div className="flex flex-wrap items-center gap-2 text-xs text-zinc-400">
                    <span>Cadastro do cliente:</span>
                    {emailsDoCadastro(entrega?.ctx).map((contato) => contato.proprio ? (
                      <span key={contato.rotulo} className="rounded border border-rose-900/60 bg-rose-950/30 px-2 py-0.5 text-rose-200" title="Endereço do domínio da própria empresa emitente gravado no cadastro do cliente; corrija no cadastro fiscal.">{contato.rotulo}: {contato.email} · é da própria empresa</span>
                    ) : (
                      <button key={contato.rotulo} type="button" className="rounded border border-zinc-700 px-2 py-0.5 hover:bg-zinc-800" onClick={() => setEntregas((atual) => ({
                        ...atual,
                        [draft.emissao!.documento_fiscal_id]: { ...atual[draft.emissao!.documento_fiscal_id], emails: contato.email },
                      }))}>{contato.rotulo}: {contato.email}</button>
                    ))}
                    {entrega?.ctx && emailsDoCadastro(entrega.ctx).length === 0 ? <span>nenhum e-mail cadastrado</span> : null}
                  </div>
                  {entrega?.enviadoPara ? <div className="text-xs text-emerald-300">Já enviado para {entrega.enviadoPara.join(", ")}. Enviar de novo repete o e-mail.</div> : null}
                  <div className="flex flex-wrap items-center gap-2">
                    <button
                      type="button"
                      onClick={() => void enviarEntrega(draft)}
                      disabled={Boolean(entrega?.enviando) || busyId === draft.id || !(entrega?.emails ?? "").trim() || !draft.emissao?.xml_path || !draft.emissao?.danfe_path}
                      className="rounded-md bg-sky-600 px-3 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-40"
                    >
                      {entrega?.enviando ? "Enviando..." : "Revisado: enviar XML + DANFE"}
                    </button>
                    {!draft.emissao?.xml_path || !draft.emissao?.danfe_path ? <span className="text-xs text-zinc-500">Aguardando XML e DANFE arquivados.</span> : null}
                  </div>
                </div>
              ) : null}

              <div className="flex flex-wrap justify-end gap-2">
                {autorizada ? <><button type="button" disabled={busyId === draft.id || !draft.emissao?.danfe_path} onClick={() => void abrirArquivo(draft, "DANFE")} className="rounded-md border border-zinc-700 px-3 py-2 text-sm hover:bg-zinc-900 disabled:opacity-40">DANFE</button><button type="button" disabled={busyId === draft.id || !draft.emissao?.xml_path} onClick={() => void abrirArquivo(draft, "XML")} className="rounded-md border border-zinc-700 px-3 py-2 text-sm hover:bg-zinc-900 disabled:opacity-40">XML</button></> : null}
                {draft.emissao ? <Link href={`/faturamento/nfe/${draft.emissao.documento_fiscal_id}?retorno=/comercial/vendas/${ovId}`} className="rounded-md border border-zinc-700 px-3 py-2 text-sm hover:bg-zinc-900">Abrir detalhes e ciclo da NF-e</Link> : null}
                {podeDescartar && descarteId !== draft.id ? <button type="button" onClick={() => { setDescarteId(draft.id); setJustificativaDescarte(""); }} disabled={busyId === draft.id} className="rounded-md border border-red-900 px-3 py-2 text-sm text-red-300 hover:bg-red-950/40 disabled:opacity-40">Descartar rascunho</button> : null}
                {podeAbandonarRejeitada && descarteId !== draft.id ? <button type="button" onClick={() => { setDescarteId(draft.id); setJustificativaDescarte(""); }} disabled={busyId === draft.id} className="rounded-md border border-red-900 px-3 py-2 text-sm text-red-300 hover:bg-red-950/40 disabled:opacity-40">Reconciliar e, se rejeitada, recomeçar</button> : null}
                {podeAbandonarHomologacao && descarteId !== draft.id ? <button type="button" onClick={() => { setDescarteId(draft.id); setJustificativaDescarte(""); }} disabled={busyId === draft.id} className="rounded-md border border-red-900 px-3 py-2 text-sm text-red-300 hover:bg-red-950/40 disabled:opacity-40" title="A NF-e de homologação não tem valor fiscal; libera a reserva desta OV">Abandonar homologação e liberar saldo</button> : null}
                {!draft.emissao && podeEmitir ? <button type="button" onClick={() => abrirConferencia(draft)} disabled={busyId === draft.id} className="rounded-md bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50">Conferir e emitir em homologação</button> : null}
                {homologacaoAutorizada && liberacaoProducao?.pronta && podeEmitir ? <button type="button" onClick={() => abrirConferencia(draft, "PRODUCAO")} disabled={busyId === draft.id} className="rounded-md bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-500 disabled:opacity-50">Conferir e emitir em produção</button> : null}
                {podeContinuarConferencia ? <button type="button" onClick={() => abrirConferencia(draft, "HOMOLOGACAO")} disabled={busyId === draft.id} className="rounded-md bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50">Continuar conferência</button> : null}
                {podeRefazerRejeitada ? <button type="button" onClick={() => abrirConferencia(draft, "HOMOLOGACAO")} disabled={busyId === draft.id} className="rounded-md bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50" title="A rejeição não autorizou nada nem consumiu número. Reveja a conferência e emita de novo com uma referência nova.">Corrigir e emitir de novo</button> : null}
              </div>
            </div>

            {openId === draft.id && operacao ? (
              <div className="fixed inset-0 z-50 overflow-y-auto bg-black/80 p-4">
                <div className="mx-auto my-4 w-full max-w-7xl rounded-xl border border-zinc-700 bg-zinc-950 shadow-2xl">
                  <div className="sticky top-0 z-10 flex items-start justify-between gap-3 border-b border-zinc-800 bg-zinc-950 p-4">
                    <div>
                      <h2 className="text-lg font-semibold">Conferir NF-e em {ambienteConferencia === "PRODUCAO" ? "produção" : "homologação"}</h2>
                      <p className="text-sm text-zinc-400">
                        Etapa {etapaConferencia === "DESTINO" ? "1 de 2 · destino da operação" : "2 de 2 · conferência fiscal"}
                        <span className="ml-2 text-zinc-500">· venda de mercadoria de terceiros, CFOP 5102</span>
                      </p>
                    </div>
                    <button type="button" onClick={() => setOpenId(null)} disabled={busyId === draft.id} className="rounded-md border border-zinc-700 px-3 py-2 text-sm hover:bg-zinc-900">Fechar</button>
                  </div>

                  {etapaConferencia === "DESTINO" ? (
                    <div className="space-y-5 p-5">
                      <section className="rounded-xl border border-zinc-800 bg-zinc-900/20 p-5">
                        <h3 className="text-base font-semibold">Para onde vai esta mercadoria?</h3>
                        <p className="mt-1 text-sm text-zinc-400">Essa confirmação define qual perfil fiscal o servidor pode procurar. Ela não altera o endereço do cliente.</p>
                        {ufCliente && !draft.destino_uf_confirmada ? (
                          <p className="mt-3 rounded border border-sky-900/70 bg-sky-950/30 px-3 py-2 text-xs text-sky-200">
                            Sugerido <strong>{ufCliente}</strong> a partir do cadastro do cliente. Confirme abaixo — a sugestão não vale como confirmação.
                          </p>
                        ) : null}
                        <div className="mt-5 grid gap-3 sm:grid-cols-2">
                          <button type="button" onClick={() => { setDestinoTipo("SC"); setDestinoUf(""); }} className={`rounded-lg border p-4 text-left ${destinoTipo === "SC" ? "border-sky-500 bg-sky-950/40" : "border-zinc-700 hover:border-zinc-500"}`}>
                            <span className="block font-medium">Dentro de Santa Catarina</span><span className="mt-1 block text-sm text-zinc-400">Operação interna em SC</span>
                          </button>
                          <button type="button" onClick={() => setDestinoTipo("FORA")} className={`rounded-lg border p-4 text-left ${destinoTipo === "FORA" ? "border-sky-500 bg-sky-950/40" : "border-zinc-700 hover:border-zinc-500"}`}>
                            <span className="block font-medium">Fora de Santa Catarina</span><span className="mt-1 block text-sm text-zinc-400">Operação interestadual</span>
                          </button>
                        </div>
                        {destinoTipo === "FORA" ? <label className={`${label} mt-4 block max-w-xs`}>UF de destino<select className={field} value={destinoUf} onChange={(event) => setDestinoUf(event.target.value)}><option value="">Selecione...</option>{["AC","AL","AP","AM","BA","CE","DF","ES","GO","MA","MT","MS","MG","PA","PB","PR","PE","PI","RJ","RN","RS","RO","RR","SP","SE","TO"].map((uf) => <option key={uf} value={uf}>{uf}</option>)}</select></label> : null}
                      </section>

                      <section className="rounded-xl border border-zinc-800 bg-zinc-900/20 p-5">
                        <h3 className="text-base font-semibold">O que o cliente vai fazer com a mercadoria?</h3>
                        <p className="mt-1 text-sm text-zinc-400">
                          Em SC é a destinação do cliente que decide a alíquota interna, não o produto: <strong>12%</strong> quando
                          ele é contribuinte e vai revender, usar como insumo, em manutenção ou receber em consignação; <strong>17%</strong> quando
                          é destinatário final. Vem informada na OC dele e sai nas informações complementares da nota.
                        </p>
                        <label className={`${label} mt-4 block max-w-md`}>Destinação declarada
                          <select
                            aria-label="Destinação da mercadoria"
                            className={field}
                            value={operacao.destinacao_mercadoria_confirmada}
                            onChange={(event) => setOperacao({ ...operacao, destinacao_mercadoria_confirmada: event.target.value })}
                          >
                            <option value="">Confirme...</option>
                            {DESTINACOES_MERCADORIA.map(([codigo, rotulo, aliquota]) => (
                              <option key={codigo} value={codigo}>{rotulo} · {aliquota}%</option>
                            ))}
                          </select>
                        </label>
                        {memoria?.campos.destinacao_mercadoria_confirmada && aceitaMemoria(draft) ? (
                          <p className="mt-3 text-xs text-zinc-500">
                            A última nota desta OV usou {rotuloDestinacao(memoria.campos.destinacao_mercadoria_confirmada)}. Confirme
                            contra a OC desta remessa — o cliente recusa a nota se a alíquota divergir da utilização que ele informou.
                          </p>
                        ) : null}
                      </section>
                      {feedback[draft.id] ? <div role="alert" className="rounded border border-amber-800 bg-amber-950/20 p-3 text-sm text-amber-100">{feedback[draft.id]}{resolucaoPerfis?.rota_cliente ? <> · <Link href={resolucaoPerfis.rota_cliente} className="underline">corrigir cadastro do cliente</Link></> : null}</div> : null}
                      <div className="flex justify-end gap-2"><button type="button" onClick={() => setOpenId(null)} className="rounded-md border border-zinc-700 px-4 py-2 text-sm hover:bg-zinc-900">Cancelar</button><button type="button" onClick={() => void confirmarDestino(draft)} disabled={!destinoTipo || resolvendoDestino || !operacao.destinacao_mercadoria_confirmada || (destinoTipo === "FORA" && !destinoUf)} className="rounded-md bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50">{resolvendoDestino ? "Validando cadastro e perfil..." : "Continuar para conferência fiscal"}</button></div>
                    </div>
                  ) : (
                    <>
                      <div className="space-y-5 p-4">
                        <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-zinc-800 bg-zinc-900/30 p-3 text-sm"><div><span className="text-zinc-500">Destino confirmado:</span> <strong>{resolucaoPerfis?.ambito === "INTERNA" ? "SC · operação interna" : `${resolucaoPerfis?.uf_confirmada} · operação interestadual`}</strong><span className="ml-3 text-zinc-500">Cliente: {resolucaoPerfis?.uf_cliente || "UF ausente"} · indIEDest {resolucaoPerfis?.indicador_ie || "ausente"}</span></div><button type="button" onClick={() => alterarDestino(draft)} disabled={autorizada || processando} className="rounded border border-zinc-700 px-3 py-1.5 text-xs hover:bg-zinc-800 disabled:opacity-40">Alterar destino</button></div>

                        {!todosPerfisResolvidos ? <div role="alert" className="rounded-lg border border-amber-800 bg-amber-950/20 p-3 text-sm text-amber-100"><div className="font-medium">Emissão bloqueada até existir um perfil fiscal válido para cada item.</div>{(resolucaoPerfis?.itens ?? []).filter((item) => item.status !== "RESOLVIDO").map((item) => <div key={item.solicitacao_item_id} className="mt-1">• Linha {item.item_id ?? "avulsa"}: {item.motivo || item.status}</div>)}</div> : null}

                        <fieldset disabled={autorizada || processando} className="space-y-5 border-0 p-0 disabled:opacity-70">
                          <section className="space-y-3 rounded-lg border border-zinc-800 p-4">
                            <div><h3 className="font-medium">Operação e destinatário</h3><p className="text-xs text-zinc-500">Campos com cadeado vieram do perfil e não podem ser alterados nesta nota.</p></div>
                            <div className="grid gap-3 md:grid-cols-4">
                              <label className={label}>Finalidade {perfilCabecalho?.finalidade_emissao != null ? <span className="text-sky-300">🔒 perfil</span> : null}<select disabled={perfilCabecalho?.finalidade_emissao != null} className={field} value={operacao.finalidade_emissao} onChange={(event) => setOperacao({ ...operacao, finalidade_emissao: event.target.value })}><option value="">Confirme...</option><option value="1">1 · Normal</option><option value="2">2 · Complementar</option><option value="3">3 · Ajuste</option><option value="4">4 · Devolução</option></select></label>
                              <label className={label}>Consumidor final {perfilCabecalho?.consumidor_final != null ? <span className="text-sky-300">🔒 perfil</span> : null}<select disabled={perfilCabecalho?.consumidor_final != null} className={field} value={operacao.consumidor_final} onChange={(event) => setOperacao({ ...operacao, consumidor_final: event.target.value })}><option value="">Confirme...</option><option value="0">0 · Não</option><option value="1">1 · Sim</option></select></label>
                              <label className={label}>Presença do comprador <span className="text-amber-300">confirmar</span><select className={field} value={operacao.presenca_comprador} onChange={(event) => setOperacao({ ...operacao, presenca_comprador: event.target.value })}><option value="">Confirme...</option>{operacao.finalidade_emissao === "2" || operacao.finalidade_emissao === "3" ? <option value="0">0 · Não se aplica (complementar/ajuste)</option> : null}<option value="1">1 · Presencial</option><option value="2">2 · Internet</option><option value="3">3 · Teleatendimento</option><option value="5">5 · Fora do estabelecimento</option><option value="9">9 · Outros</option></select></label>
                            </div>
                          </section>

                          {/* O aviso cobre pagamento, frete e volumes, então fica acima das
                              duas seções que a memória preenche, e não dentro de uma delas. */}
                          {memoria && aceitaMemoria(draft) ? (
                            <p className="rounded border border-sky-900/70 bg-sky-950/30 px-3 py-2 text-xs text-sky-200">
                              Da última nota conferida desta OV ({memoria.rotulo}) vieram: {memoria.resumo}. Revise antes de emitir — a conferência continua sendo sua.
                            </p>
                          ) : null}

                          <section className="space-y-4 rounded-lg border border-zinc-800 p-4">
                            <div>
                              <h3 className="font-medium">Pagamento <span className="text-xs font-normal text-amber-300">confirmar em cada nota</span></h3>
                              <p className="mt-1 text-xs text-zinc-500">Grupo obrigatório da NF-e. Sem esta confirmação a nota saía declarando <strong>dinheiro</strong>, porque o provedor preenchia o default dele.</p>
                            </div>
                            <div className="grid gap-3 md:grid-cols-3">
                              <label className={label}>Forma de pagamento<select aria-label="Forma de pagamento" className={field} value={operacao.pagamento_forma} onChange={(event) => setOperacao({ ...operacao, pagamento_forma: event.target.value })}><option value="">Confirme...</option>{FORMAS_PAGAMENTO.map(([codigo, rotulo]) => <option key={codigo} value={codigo}>{rotulo}</option>)}</select></label>
                              <label className={label}>À vista ou a prazo<select aria-label="Indicador de pagamento" className={field} value={operacao.pagamento_indicador} onChange={(event) => setOperacao({ ...operacao, pagamento_indicador: event.target.value })}><option value="">Confirme...</option><option value="0">0 · À vista</option><option value="1">1 · A prazo</option></select></label>
                              {operacao.pagamento_forma === "99" ? (
                                <label className={label}>Descrição (obrigatória no 99)<input aria-label="Descrição da forma de pagamento" className={field} value={operacao.pagamento_descricao} onChange={(event) => setOperacao({ ...operacao, pagamento_descricao: event.target.value })} maxLength={60} placeholder="Ex.: compensação de crédito" /></label>
                              ) : null}
                            </div>
                            {operacao.pagamento_indicador === "1" ? (
                              <div className="mt-3 space-y-2 rounded-lg border border-zinc-800 bg-zinc-900/30 p-3">
                                <div className="flex flex-wrap items-center justify-between gap-2">
                                  <div>
                                    <h4 className="text-sm font-medium text-zinc-200">Parcelas (duplicatas da NF-e)</h4>
                                    <p className="text-xs text-zinc-500">Dias contados da data de emissão. Na parcela única, deixe o valor vazio para usar o total da nota. As mesmas parcelas geram o contas a receber.</p>
                                  </div>
                                  <button
                                    type="button"
                                    className="rounded-md border border-zinc-700 px-3 py-1.5 text-xs hover:bg-zinc-900"
                                    onClick={() => {
                                      const proximas = [...operacao.pagamento_parcelas, { dias: "", valor: "" }];
                                      const rateio = ratearParcelas(totalConferencia, proximas.length);
                                      setOperacao({
                                        ...operacao,
                                        pagamento_parcelas: proximas.map((p, i) => ({ ...p, valor: rateio[i] ?? "" })),
                                      });
                                    }}
                                  >
                                    Adicionar parcela
                                  </button>
                                </div>
                                {operacao.pagamento_parcelas.map((parcela, indice) => (
                                  <div key={indice} className="grid gap-2 md:grid-cols-[auto_1fr_1fr_auto] md:items-end">
                                    <div className="text-xs text-zinc-500 md:pb-2">{String(indice + 1).padStart(3, "0")}</div>
                                    <label className={label}>Dias após a emissão<input aria-label={`Dias da parcela ${indice + 1}`} className={field} inputMode="numeric" value={parcela.dias} onChange={(event) => setOperacao({ ...operacao, pagamento_parcelas: operacao.pagamento_parcelas.map((p, i) => i === indice ? { ...p, dias: event.target.value } : p) })} placeholder="15" /></label>
                                    <label className={label}>Valor (R$)<input aria-label={`Valor da parcela ${indice + 1}`} className={field} inputMode="decimal" value={parcela.valor} onChange={(event) => setOperacao({ ...operacao, pagamento_parcelas: operacao.pagamento_parcelas.map((p, i) => i === indice ? { ...p, valor: event.target.value } : p) })} placeholder={operacao.pagamento_parcelas.length === 1 ? "vazio = total da nota" : "obrigatório"} /></label>
                                    <button
                                      type="button"
                                      disabled={operacao.pagamento_parcelas.length === 1}
                                      className="rounded-md border border-zinc-700 px-3 py-2 text-xs hover:bg-zinc-900 disabled:opacity-40"
                                      onClick={() => {
                                        const proximas = operacao.pagamento_parcelas.filter((_, i) => i !== indice);
                                        const rateio = ratearParcelas(totalConferencia, proximas.length);
                                        setOperacao({
                                          ...operacao,
                                          pagamento_parcelas: proximas.map((p, i) => ({ ...p, valor: rateio[i] ?? "" })),
                                        });
                                      }}
                                    >
                                      Remover
                                    </button>
                                  </div>
                                ))}
                              </div>
                            ) : null}
                          </section>

                          <section className="space-y-4 rounded-lg border border-zinc-800 p-4">
                            <div><h3 className="font-medium">Frete e transportadora <span className="text-xs font-normal text-amber-300">confirmar em cada nota</span></h3><p className="mt-1 text-xs text-zinc-500">Na modalidade 9 não há ocorrência de transporte e o grupo vol não é enviado.</p></div>
                            {padraoTransportador?.nome && aceitaMemoria(draft) && !memoria?.campos.transportador_nome ? (
                              <p className="rounded border border-sky-900/70 bg-sky-950/30 px-3 py-2 text-xs text-sky-200">
                                Transportadora e modalidade vieram do cadastro de {clienteNome} ({padraoTransportador.nome}). Revise antes de emitir — a conferência continua sendo sua.
                              </p>
                            ) : null}
                            <div className="grid gap-3 md:grid-cols-4">
                              <label className={label}>Modalidade do frete<select className={field} value={operacao.modalidade_frete} onChange={(event) => setOperacao({ ...operacao, modalidade_frete: event.target.value })}><option value="">Confirme...</option><option value="0">0 · Emitente</option><option value="1">1 · Destinatário</option><option value="2">2 · Terceiros</option><option value="3">3 · Próprio emitente</option><option value="4">4 · Próprio destinatário</option><option value="9">9 · Sem frete</option></select></label>
                              <label className={label}>Frete (R$)<input required className={field} inputMode="decimal" value={operacao.valor_frete} onChange={(event) => setOperacao({ ...operacao, valor_frete: event.target.value })} placeholder="Digite 0 quando não houver" /></label>
                              <label className={label}>Seguro (R$)<input required className={field} inputMode="decimal" value={operacao.valor_seguro} onChange={(event) => setOperacao({ ...operacao, valor_seguro: event.target.value })} placeholder="Digite 0 quando não houver" /></label>
                              <label className={label}>Outras despesas (R$)<input required className={field} inputMode="decimal" value={operacao.valor_outras_despesas} onChange={(event) => setOperacao({ ...operacao, valor_outras_despesas: event.target.value })} placeholder="Digite 0 quando não houver" /></label>
                            </div>
                            {operacao.modalidade_frete !== "9" ? <><div className="grid gap-3 md:grid-cols-3 lg:grid-cols-6">
                              <label className={label}>Transportadora (opcional)<input className={field} value={operacao.transportador_nome} onChange={(event) => setOperacao({ ...operacao, transportador_nome: event.target.value })} maxLength={60} placeholder="Vazio quando não houver" /></label>
                              <label className={label}>CNPJ/CPF transportadora<input className={field} value={operacao.transportador_documento} onChange={(event) => setOperacao({ ...operacao, transportador_documento: event.target.value })} /></label>
                              <label className={label}>IE transportadora<input className={field} value={operacao.transportador_ie} onChange={(event) => setOperacao({ ...operacao, transportador_ie: event.target.value })} /></label>
                              <label className={label}>Endereço transportadora<input className={field} value={operacao.transportador_endereco} onChange={(event) => setOperacao({ ...operacao, transportador_endereco: event.target.value })} maxLength={60} /></label>
                              <label className={label}>Município transportadora<input className={field} value={operacao.transportador_municipio} onChange={(event) => setOperacao({ ...operacao, transportador_municipio: event.target.value })} maxLength={60} /></label>
                              <label className={label}>UF transportadora<input className={field} value={operacao.transportador_uf} onChange={(event) => setOperacao({ ...operacao, transportador_uf: event.target.value.toUpperCase() })} maxLength={2} /></label>
                            </div>
                            <div className="grid gap-3 md:grid-cols-3 lg:grid-cols-6">
                              <label className={label}>Quantidade de volumes<input required className={field} inputMode="numeric" value={operacao.volume_quantidade} onChange={(event) => setOperacao({ ...operacao, volume_quantidade: event.target.value })} /></label>
                              <label className={label}>Espécie <span className="text-xs font-normal text-zinc-500">opcional</span><input className={field} value={operacao.volume_especie} onChange={(event) => setOperacao({ ...operacao, volume_especie: event.target.value })} maxLength={60} placeholder="Ex.: CAIXA" /></label>
                              <label className={label}>Marca <span className="text-xs font-normal text-zinc-500">opcional</span><input className={field} value={operacao.volume_marca} onChange={(event) => setOperacao({ ...operacao, volume_marca: event.target.value })} maxLength={60} /></label>
                              <label className={label}>Numeração <span className="text-xs font-normal text-zinc-500">opcional</span><input className={field} value={operacao.volume_numero} onChange={(event) => setOperacao({ ...operacao, volume_numero: event.target.value })} maxLength={60} /></label>
                              <label className={label}>Peso líquido (kg)<input required className={field} inputMode="decimal" value={operacao.volume_peso_liquido} onChange={(event) => setOperacao({ ...operacao, volume_peso_liquido: event.target.value })} /></label>
                              <label className={label}>Peso bruto (kg)<input required className={field} inputMode="decimal" value={operacao.volume_peso_bruto} onChange={(event) => setOperacao({ ...operacao, volume_peso_bruto: event.target.value })} /></label>
                            </div></> : <div className="rounded border border-zinc-800 bg-zinc-900/30 p-3 text-sm text-zinc-400">Sem transportadora e sem volumes. Para frete real, a expedição deverá informar transportadora, espécie, numeração e pesos.</div>}
                          </section>

                          <div className="rounded-lg border border-emerald-900 bg-emerald-950/20 p-3 text-sm text-emerald-100"><div className="font-medium">IBS/CBS — regra legal do exercício de 2026</div><p className="mt-1 text-emerald-100/80">Os cinco valores abaixo são aplicados pela natureza da operação e ficam bloqueados para edição. A versão da NT é responsabilidade do provedor e não integra o payload fiscal.</p></div>

                          {draft.itens.map((item) => {
                            const form = itensForm.find((value) => value.id === item.id);
                            const resolvido = resolucaoPerfis?.itens?.find((value) => value.solicitacao_item_id === item.id);
                            const perfil = resolvido?.perfil;
                            const produto = resolvido?.produto;
                            const ipiOperacao = resolvido?.ipi_operacao;
                            if (!form) return null;
                            const bloqueado = (campo: CampoPerfil) => campoVemDoPerfil(resolvido, campo);
                            const classeCampo = (campo: CampoPerfil) => `${field} ${bloqueado(campo) ? "cursor-not-allowed border-sky-900 bg-sky-950/30 text-sky-100" : ""}`;
                            const trava = (campo: CampoPerfil) => bloqueado(campo) || resolvido?.status !== "RESOLVIDO";
                            return <section key={item.id} className="space-y-4 rounded-lg border border-zinc-800 p-4">
                              <div className="flex flex-wrap items-start justify-between gap-2"><div><div className="font-medium">{item.item_id ? <><Link href={`/itens?id=${item.item_id}&editar=1&aba=fiscal&retorno=/comercial/vendas/${ovId}`} className="text-sky-200 underline">#{item.item_id}</Link> · </> : null}{item.codigo_produto ? `[${item.codigo_produto}] ` : ""}{item.descricao}</div><div className="text-xs text-zinc-500">{numero(item.quantidade).toLocaleString("pt-BR")} {item.unidade} · R$ {formatMoneyBR(numero(item.valor_unitario))} por unidade · origem {resolvido?.origem_mercadoria ?? "ausente"}</div></div>{perfil ? <span className="rounded border border-sky-800 bg-sky-950/30 px-2 py-1 text-xs text-sky-200">Perfil {perfil.codigo} · <Link href={`/faturamento/perfis?perfil=${perfil.id}&solicitacao=${draft.id}&retorno=/comercial/vendas/${ovId}`} className="underline">abrir cadastro</Link></span> : null}</div>
                              {resolvido?.status !== "RESOLVIDO" ? <div className="rounded border border-amber-800 bg-amber-950/20 p-3 text-sm text-amber-100">{resolvido?.motivo || "Perfil fiscal não resolvido."}</div> : null}
                              <div className="space-y-2"><h4 className="text-sm font-medium text-zinc-300">ICMS</h4><div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-6">
                                <label className={label}>CFOP {bloqueado("cfop") ? <span className="text-sky-300">🔒 perfil</span> : null}<input disabled={trava("cfop")} className={classeCampo("cfop")} value={form.cfop} onChange={(event) => atualizarItem(item.id, { cfop: event.target.value })} maxLength={4} /></label>
                                {perfil?.crt === "1" ? <><label className={label}>CST ICMS<input disabled className={`${field} opacity-50`} value="Não se aplica" readOnly /></label><label className={label}>CSOSN {bloqueado("csosn") ? <span className="text-sky-300">🔒 perfil</span> : null}<input disabled={trava("csosn")} className={classeCampo("csosn")} value={form.csosn} onChange={(event) => atualizarItem(item.id, { csosn: event.target.value })} maxLength={3} /></label></> : <><label className={label}>CST ICMS {bloqueado("cst_icms") ? <span className="text-sky-300">🔒 perfil</span> : null}<input disabled={trava("cst_icms")} className={classeCampo("cst_icms")} value={form.cst_icms} onChange={(event) => atualizarItem(item.id, { cst_icms: event.target.value })} maxLength={2} /></label><label className={label}>CSOSN<input disabled className={`${field} opacity-50`} value="Não se aplica" readOnly /></label></>}
                                <label className={label}>Modalidade da base {bloqueado("icms_modalidade_base_calculo") ? <span className="text-sky-300">🔒 perfil</span> : null}<input disabled={trava("icms_modalidade_base_calculo")} className={classeCampo("icms_modalidade_base_calculo")} value={form.icms_modalidade_base_calculo} onChange={(event) => atualizarItem(item.id, { icms_modalidade_base_calculo: event.target.value })} /></label>
                                <label className={label}>Alíquota ICMS (%) {bloqueado("aliquota_icms") ? <span className="text-sky-300">🔒 perfil</span> : null}<input disabled={trava("aliquota_icms")} className={classeCampo("aliquota_icms")} value={form.aliquota_icms} onChange={(event) => atualizarItem(item.id, { aliquota_icms: event.target.value })} /></label>
                                <label className={label}>Redução da base (%) {bloqueado("reducao_base_icms_percentual") ? <span className="text-sky-300">🔒 perfil</span> : null}<input disabled={trava("reducao_base_icms_percentual")} className={classeCampo("reducao_base_icms_percentual")} value={form.reducao_base_icms_percentual} onChange={(event) => atualizarItem(item.id, { reducao_base_icms_percentual: event.target.value })} /></label>
                                <label className={label}>cBenef {bloqueado("cbenef") ? <span className="text-sky-300">🔒 perfil</span> : null}<input disabled={trava("cbenef")} className={classeCampo("cbenef")} value={form.cbenef} onChange={(event) => atualizarItem(item.id, { cbenef: event.target.value })} placeholder={perfil?.cbenef_aplicacao === "SEM_BENEFICIO" ? "Sem benefício" : ""} /></label>
                              </div></div>
                              <div className="space-y-2"><h4 className="text-sm font-medium text-zinc-300">PIS e COFINS</h4><div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                                <label className={label}>CST PIS {bloqueado("cst_pis") ? <span className="text-sky-300">🔒 perfil</span> : null}<input disabled={trava("cst_pis")} className={classeCampo("cst_pis")} value={form.cst_pis} onChange={(event) => atualizarItem(item.id, { cst_pis: event.target.value })} maxLength={2} /></label><label className={label}>Alíquota PIS (%) {bloqueado("aliquota_pis") ? <span className="text-sky-300">🔒 perfil</span> : null}<input disabled={trava("aliquota_pis")} className={classeCampo("aliquota_pis")} value={form.aliquota_pis} onChange={(event) => atualizarItem(item.id, { aliquota_pis: event.target.value })} /></label><label className={label}>CST COFINS {bloqueado("cst_cofins") ? <span className="text-sky-300">🔒 perfil</span> : null}<input disabled={trava("cst_cofins")} className={classeCampo("cst_cofins")} value={form.cst_cofins} onChange={(event) => atualizarItem(item.id, { cst_cofins: event.target.value })} maxLength={2} /></label><label className={label}>Alíquota COFINS (%) {bloqueado("aliquota_cofins") ? <span className="text-sky-300">🔒 perfil</span> : null}<input disabled={trava("aliquota_cofins")} className={classeCampo("aliquota_cofins")} value={form.aliquota_cofins} onChange={(event) => atualizarItem(item.id, { aliquota_cofins: event.target.value })} /></label>
                              </div></div>
                              <div className="space-y-2"><div className="flex items-center justify-between"><h4 className="text-sm font-medium text-zinc-300">IPI da operação e identificação do produto</h4>{ipiOperacao?.fonte ? <span className={`text-xs ${ipiOperacao.fonte === "FIXTURE_HOMOLOGACAO" ? "text-amber-300" : "text-sky-300"}`}>🔒 {ipiOperacao.fonte === "FIXTURE_HOMOLOGACAO" ? "fixture provisória · pergunta 4 ao contador" : "perfil de operação"}</span> : null}</div><div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-6">
                                <label className={label}>NCM <span className="text-sky-300">🔒 produto</span><input disabled className={`${field} opacity-70`} value={produto?.ncm ?? item.ncm ?? ""} readOnly /></label><label className={label}>CST IPI <span className="text-sky-300">🔒 operação</span><input disabled className={`${field} opacity-70`} value={form.cst_ipi} readOnly /></label><label className={label}>cEnq IPI <span className="text-sky-300">🔒 operação</span><input disabled className={`${field} opacity-70`} value={form.ipi_codigo_enquadramento_legal} readOnly /></label><label className={label}>Alíquota IPI (%) <span className="text-sky-300">🔒 operação</span><input disabled className={`${field} opacity-70`} value={form.aliquota_ipi} readOnly /></label><label className={label}>Unidade tributável <span className="text-sky-300">🔒 produto</span><input disabled className={`${field} opacity-70`} value={produto?.unidade_tributavel ?? item.unidade_tributavel ?? ""} readOnly /></label><label className={label}>FCI <span className="text-sky-300">🔒 produto</span><input disabled className={`${field} opacity-70`} value={form.numero_fci} readOnly /></label>
                              </div></div>
                              <div className="space-y-2"><h4 className="text-sm font-medium text-zinc-300">IBS/CBS</h4><div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-5">
                                {([['cst_ibs_cbs','CST IBS/CBS'],['cclass_trib','cClassTrib'],['aliquota_ibs_uf','IBS UF (%)'],['aliquota_ibs_mun','IBS municipal (%)'],['aliquota_cbs','CBS (%)']] as const).map(([campo, rotulo]) => <label key={campo} className={label}>{rotulo} <span className="text-emerald-300">🔒 lei 2026</span><input disabled readOnly className={`${field} cursor-not-allowed border-emerald-900 bg-emerald-950/30 text-emerald-100`} value={form[campo]} /></label>)}
                              </div></div>
                            </section>;
                          })}
                        </fieldset>

                        {/* Enquanto o perfil nao resolve, os campos travados ainda estao vazios e
                            o aviso de bloqueio dava a impressao de impasse. Mostra o carregamento. */}
                        {resolucaoPerfis === null && !autorizada && !processando ? (
                          <div role="status" className="rounded border border-sky-900 bg-sky-950/20 p-3 text-sm text-sky-200">
                            Carregando o perfil fiscal dos itens… os campos com cadeado são preenchidos automaticamente ao final.
                          </div>
                        ) : camposPendentesConferencia.length > 0 && !autorizada && !processando ? (
                          <div role="alert" className="rounded border border-amber-800 bg-amber-950/20 p-3 text-sm text-amber-100">
                            Emissão bloqueada: faltam {camposPendentesConferencia.length} dados obrigatórios ({camposPendentesConferencia.slice(0, 6).join(", ")}{camposPendentesConferencia.length > 6 ? "…" : ""}). Valores sugeridos não são aplicados automaticamente.
                          </div>
                        ) : null}
                        {feedback[draft.id] ? <div role="alert" className="rounded border border-amber-800 bg-amber-950/20 p-3 text-sm text-amber-100">{feedback[draft.id]}</div> : null}
                        {(pendencias[draft.id]?.length ?? 0) > 0 ? <ul className="space-y-1 rounded border border-amber-800 bg-amber-950/20 p-3 text-sm text-amber-100">{pendencias[draft.id].map((item, index) => <li key={`${item.campo}-${index}`}>• {item.mensagem || item.campo}{item.rota && !item.rota.startsWith("/faturamento/solicitacoes/") ? <> · <Link className="underline" href={item.rota}>corrigir cadastro</Link></> : null}</li>)}</ul> : null}
                      </div>
                      <div className="sticky bottom-0 flex flex-wrap items-center justify-between gap-3 border-t border-zinc-800 bg-zinc-950 p-4"><div><div className="text-xs uppercase text-zinc-500">Total conferido</div><div className="text-xl font-semibold">R$ {formatMoneyBR(totalConferencia)}</div></div><div className="flex gap-2"><button type="button" onClick={() => alterarDestino(draft)} disabled={busyId === draft.id || autorizada || processando} className="rounded-md border border-zinc-700 px-4 py-2 text-sm hover:bg-zinc-900 disabled:opacity-40">Voltar ao destino</button><button type="button" onClick={() => void salvarEEmitir(draft)} disabled={busyId === draft.id || !todosPerfisResolvidos || camposPendentesConferencia.length > 0} className={`rounded-md px-4 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50 ${ambienteConferencia === "PRODUCAO" ? "bg-emerald-600 hover:bg-emerald-500" : "bg-sky-600 hover:bg-sky-500"}`}>{busyId === draft.id ? "Enviando..." : !todosPerfisResolvidos ? "Perfil fiscal pendente" : camposPendentesConferencia.length > 0 ? "Complete os campos obrigatórios" : ambienteConferencia === "PRODUCAO" ? "Emitir NF-e real em produção" : (draft.emissao ? "Tentar emitir novamente" : "Emitir em homologação")}</button></div></div>
                    </>
                  )}
                </div>
              </div>
            ) : null}
          </article>
        );
      })}
    </div>
  );
}
