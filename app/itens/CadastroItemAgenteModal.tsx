"use client";

import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

/** Dados mínimos já carregados pela tela de itens. */
export type CadastroItemAgenteFornecedor = {
  id: number;
  nome: string;
  ativo?: boolean | null;
};

export type CadastroItemAgenteNovoGrupo = {
  codigo: string;
  nome: string;
  grupo_pai_id: number | null;
  justificativa: string;
};

export type CadastroItemAgenteFonte = {
  fonte: string | null;
  fonte_url: string | null;
  /** Campos nativos das citações retornadas por web_search; são reenviados ao servidor para validação. */
  url: string | null;
  dominio: string | null;
  titulo: string | null;
  marketplace: string | null;
  preco: number | null;
  moeda: string | null;
  tipo_correspondencia: string | null;
  observacao: string | null;
};

export type CadastroItemAgentePesquisaPreco = {
  status: string | null;
  tipo_correspondencia: string | null;
  marketplace: string | null;
  fonte: string | null;
  fonte_url: string | null;
  titulo: string | null;
  moeda: string | null;
  preco_origem: number | null;
  preco_unitario_brl: number | null;
  fator_importacao: number | null;
  preco_final_brl: number | null;
  taxa_cambio_para_brl: number | null;
  fonte_cambio_url: string | null;
  data_cambio: string | null;
  regra_preco: string | null;
  observacao: string | null;
};

export type CadastroItemAgenteFiscal = {
  ncm: string | null;
  cest: string | null;
  origem: number | null;
  cfop_padrao: string | null;
  cst_icms: string | null;
  cst_pis: string | null;
  cst_cofins: string | null;
  aliq_icms: number | null;
  aliq_ipi: number | null;
  aliq_pis: number | null;
  aliq_cofins: number | null;
  credita_icms: boolean;
  ipi_entra_no_custo: boolean;
  credita_pis: boolean;
  credita_cofins: boolean;
  referencia_item_id: number | null;
  justificativa: string | null;
};

export type CadastroItemAgenteSimilarInterno = {
  id: number | null;
  codigo: string | null;
  nome: string | null;
  fornecedor: string | null;
  justificativa: string | null;
};

export type CadastroItemAgenteSugestao = {
  codigo: string;
  descricao_padronizada: string;
  fabricante: string | null;
  modelo_referencia: string | null;
  unidade_medida: string;
  finalidade: string | null;
  motivo_compra_id: string | null;
  grupo_id: number | null;
  grupo_nome: string | null;
  grupo_caminho: string | null;
  novo_grupo: CadastroItemAgenteNovoGrupo | null;
  justificativa: string;
  dados_pendentes: string[];
  confianca: "alta" | "media" | "baixa";
  pesquisa_preco: CadastroItemAgentePesquisaPreco | null;
};

export type CadastroItemAgenteDuplicidade = {
  id: number | null;
  codigo: string | null;
  nome: string | null;
  ativo: boolean | null;
  mensagem: string | null;
};

export type CadastroItemAgenteSugestaoResposta = {
  model: string | null;
  fornecedor: CadastroItemAgenteFornecedor | null;
  duplicidade: CadastroItemAgenteDuplicidade | null;
  cotacao_token: string | null;
  sugestao: CadastroItemAgenteSugestao | null;
  similar_interno: CadastroItemAgenteSimilarInterno | null;
  fiscal_sugerido: CadastroItemAgenteFiscal | null;
  pode_editar_fiscal: boolean;
  fontes: CadastroItemAgenteFonte[];
  error: string | null;
};

export type CadastroItemAgenteItemCriado = {
  id: number | null;
  codigo: string | null;
  nome: string | null;
};

export type CadastroItemAgenteConfirmarPayload = {
  fornecedor_id: number;
  codigo: string;
  quantidade_referencia: number;
  preco_unitario_confirmado: number;
  peso_referencia_kg: number | null;
  cotacao_token: string;
  model: string | null;
  sugestao: CadastroItemAgenteSugestao;
  fiscal_sugerido: CadastroItemAgenteFiscal | null;
  fontes: CadastroItemAgenteFonte[];
  similar_interno: CadastroItemAgenteSimilarInterno | null;
};

export type CadastroItemAgenteModalProps = {
  open: boolean;
  onClose: () => void;
  fornecedores: Array<{ id: number; nome: string; ativo: boolean }>;
  fornecedoresLoading?: boolean;
  fornecedoresError?: string | null;
  /** Chamado depois de o servidor confirmar a criação, para a grade se recarregar. */
  onCreated: (itemId: number, mensagem: string) => void | Promise<void>;
};

type Fase = "entrada" | "revisao" | "concluido";

type Rascunho = {
  model: string | null;
  cotacaoToken: string;
  sugestao: CadastroItemAgenteSugestao;
  similarInterno: CadastroItemAgenteSimilarInterno | null;
  fiscal: CadastroItemAgenteFiscal | null;
  podeEditarFiscal: boolean;
  fontes: CadastroItemAgenteFonte[];
};

const INPUT_CLASS = "w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-zinc-100 outline-none placeholder:text-zinc-500 focus:border-sky-500/80 focus:ring-1 focus:ring-sky-500/50";
const FIELD_LABEL_CLASS = "mb-1 block text-xs font-medium text-zinc-300";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function text(value: unknown, fallback: string | null = null): string | null {
  if (typeof value !== "string") return fallback;
  const normalized = value.trim();
  return normalized || fallback;
}

function numberOrNull(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value.replace(",", "."));
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function integerOrNull(value: unknown): number | null {
  const parsed = numberOrNull(value);
  return parsed !== null && Number.isInteger(parsed) ? parsed : null;
}

function bool(value: unknown, fallback = false): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function strings(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => text(item)).filter((item): item is string => Boolean(item));
}

function decodeFonte(value: unknown): CadastroItemAgenteFonte | null {
  if (!isRecord(value)) return null;
  return {
    fonte: text(value.fonte, text(value.marketplace)),
    fonte_url: text(value.fonte_url, text(value.url)),
    url: text(value.url, text(value.fonte_url)),
    dominio: text(value.dominio),
    titulo: text(value.titulo),
    marketplace: text(value.marketplace),
    preco: numberOrNull(value.preco),
    moeda: text(value.moeda),
    tipo_correspondencia: text(value.tipo_correspondencia),
    observacao: text(value.observacao),
  };
}

function decodePesquisaPreco(value: unknown): CadastroItemAgentePesquisaPreco | null {
  if (!isRecord(value)) return null;
  return {
    status: text(value.status),
    tipo_correspondencia: text(value.tipo_correspondencia),
    marketplace: text(value.marketplace),
    fonte: text(value.fonte),
    fonte_url: text(value.fonte_url, text(value.url)),
    titulo: text(value.titulo),
    moeda: text(value.moeda),
    preco_origem: numberOrNull(value.preco_origem),
    preco_unitario_brl: numberOrNull(value.preco_unitario_brl),
    fator_importacao: numberOrNull(value.fator_importacao),
    preco_final_brl: numberOrNull(value.preco_final_brl),
    taxa_cambio_para_brl: numberOrNull(value.taxa_cambio_para_brl),
    fonte_cambio_url: text(value.fonte_cambio_url),
    data_cambio: text(value.data_cambio),
    regra_preco: text(value.regra_preco),
    observacao: text(value.observacao),
  };
}

function decodeFiscal(value: unknown): CadastroItemAgenteFiscal | null {
  if (!isRecord(value)) return null;
  return {
    ncm: text(value.ncm),
    cest: text(value.cest),
    // O fluxo de cadastro de itens trabalha, por padrão, com origem nacional.
    // Não deixe uma referência interna sobrescrever essa convenção sem revisão fiscal.
    origem: 0,
    cfop_padrao: text(value.cfop_padrao),
    cst_icms: text(value.cst_icms),
    cst_pis: text(value.cst_pis),
    cst_cofins: text(value.cst_cofins),
    aliq_icms: numberOrNull(value.aliq_icms),
    aliq_ipi: numberOrNull(value.aliq_ipi),
    aliq_pis: numberOrNull(value.aliq_pis),
    aliq_cofins: numberOrNull(value.aliq_cofins),
    credita_icms: bool(value.credita_icms),
    ipi_entra_no_custo: bool(value.ipi_entra_no_custo, true),
    credita_pis: bool(value.credita_pis),
    credita_cofins: bool(value.credita_cofins),
    referencia_item_id: integerOrNull(value.referencia_item_id),
    justificativa: text(value.justificativa),
  };
}

function decodeNovoGrupo(value: unknown): CadastroItemAgenteNovoGrupo | null {
  if (!isRecord(value)) return null;
  const codigo = text(value.codigo);
  const nome = text(value.nome);
  if (!codigo || !nome) return null;
  return {
    codigo,
    nome,
    grupo_pai_id: integerOrNull(value.grupo_pai_id),
    justificativa: text(value.justificativa, "Grupo sugerido pelo agente para a função técnica.") ?? "",
  };
}

function decodeSugestao(value: unknown): CadastroItemAgenteSugestao | null {
  if (!isRecord(value)) return null;
  const codigo = text(value.codigo, "") ?? "";
  const descricao = text(value.descricao_padronizada, "") ?? "";
  const confiancaRaw = text(value.confianca, "baixa");
  const confianca = confiancaRaw === "alta" || confiancaRaw === "media" ? confiancaRaw : "baixa";
  return {
    codigo,
    descricao_padronizada: descricao,
    fabricante: text(value.fabricante),
    modelo_referencia: text(value.modelo_referencia),
    unidade_medida: text(value.unidade_medida, "UN") ?? "UN",
    finalidade: text(value.finalidade),
    motivo_compra_id: text(value.motivo_compra_id),
    grupo_id: integerOrNull(value.grupo_id),
    grupo_nome: text(value.grupo_nome),
    grupo_caminho: text(value.grupo_caminho),
    novo_grupo: decodeNovoGrupo(value.novo_grupo),
    justificativa: text(value.justificativa, "Revise a sugestão antes de confirmar o cadastro.") ?? "",
    dados_pendentes: strings(value.dados_pendentes),
    confianca,
    pesquisa_preco: decodePesquisaPreco(value.pesquisa_preco),
  };
}

function decodeSimilar(value: unknown): CadastroItemAgenteSimilarInterno | null {
  if (!isRecord(value)) return null;
  const id = integerOrNull(value.id);
  const codigo = text(value.codigo, text(value.codigo_interno));
  const nome = text(value.nome);
  if (!id && !codigo && !nome) return null;
  const fornecedorId = integerOrNull(value.fornecedor_id);
  return {
    id,
    codigo,
    nome,
    fornecedor: text(value.fornecedor, text(value.fornecedor_nome)) ?? (fornecedorId ? `Fornecedor #${fornecedorId}` : null),
    justificativa: text(value.justificativa, text(value.motivo)),
  };
}

function decodeDuplicidade(value: unknown): CadastroItemAgenteDuplicidade | null {
  if (!isRecord(value)) return null;
  const id = integerOrNull(value.id);
  const codigo = text(value.codigo);
  const nome = text(value.nome);
  const mensagem = text(value.mensagem);
  if (!id && !codigo && !nome && !mensagem) return null;
  return { id, codigo, nome, ativo: typeof value.ativo === "boolean" ? value.ativo : null, mensagem };
}

function decodeFornecedor(value: unknown): CadastroItemAgenteFornecedor | null {
  if (!isRecord(value)) return null;
  const id = integerOrNull(value.id);
  const nome = text(value.nome);
  if (!id || !nome) return null;
  return { id, nome, ativo: typeof value.ativo === "boolean" ? value.ativo : null };
}

/**
 * A resposta é validada no limite do browser para que uma resposta parcial ou
 * uma página de erro do provedor não preencha campos comerciais silenciosamente.
 */
export function decodeCadastroItemAgenteSugestaoResposta(value: unknown): CadastroItemAgenteSugestaoResposta {
  const raw = isRecord(value) ? value : {};
  const fontes = Array.isArray(raw.fontes)
    ? raw.fontes.map(decodeFonte).filter((fonte): fonte is CadastroItemAgenteFonte => Boolean(fonte))
    : [];
  return {
    model: text(raw.model),
    fornecedor: decodeFornecedor(raw.fornecedor),
    duplicidade: decodeDuplicidade(raw.duplicidade),
    cotacao_token: text(raw.cotacao_token),
    sugestao: decodeSugestao(raw.sugestao),
    similar_interno: decodeSimilar(raw.similar_interno),
    fiscal_sugerido: decodeFiscal(raw.fiscal_sugerido),
    pode_editar_fiscal: bool(raw.pode_editar_fiscal),
    fontes,
    error: text(raw.error),
  };
}

function decodeCreatedItem(value: unknown, fallback: CadastroItemAgenteSugestao): CadastroItemAgenteItemCriado {
  const raw = isRecord(value) ? value : {};
  const item = isRecord(raw.item) ? raw.item : isRecord(raw.criado) ? raw.criado : isRecord(raw.item_criado) ? raw.item_criado : raw;
  return {
    id: integerOrNull(item.id) ?? integerOrNull(raw.item_id),
    codigo: text(item.codigo, text(raw.codigo, fallback.codigo)),
    nome: text(item.nome, text(item.descricao_padronizada, text(raw.nome, fallback.descricao_padronizada))),
  };
}

function responseError(value: unknown, fallback: string): string {
  if (!isRecord(value)) return fallback;
  return text(value.error, text(value.message, fallback)) ?? fallback;
}

/** Zero é um valor válido: significa "não lançar estoque inicial agora". */
function parseQuantidade(value: string): number | null {
  const normalized = value.trim().replace(/\s+/g, "").replace(/\./g, "").replace(",", ".");
  const parsed = Number(normalized);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

function parseNumeroOpcional(value: string): number | null {
  const normalized = value.trim().replace(/\s+/g, "").replace(/\./g, "").replace(",", ".");
  if (!normalized) return null;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function formatMoney(value: number | null | undefined, currency = "BRL"): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return "Não informado";
  const normalizedCurrency = /^[A-Za-z]{3}$/.test(currency) ? currency.toUpperCase() : "BRL";
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: normalizedCurrency }).format(value);
}

function externalUrl(value: string | null): string | null {
  if (!value) return null;
  try {
    const parsed = new URL(value);
    return parsed.protocol === "https:" || parsed.protocol === "http:" ? parsed.href : null;
  } catch {
    return null;
  }
}

async function authenticatedJsonHeaders(): Promise<Record<string, string>> {
  const { data, error } = await supabaseBrowser().auth.getSession();
  if (error || !data.session?.access_token) {
    throw new Error("Sua sessão não está ativa. Entre novamente para usar o agente de cadastro.");
  }
  return {
    "Content-Type": "application/json",
    Authorization: `Bearer ${data.session.access_token}`,
  };
}

function confidenceClasses(confidence: CadastroItemAgenteSugestao["confianca"]) {
  if (confidence === "alta") return "border-emerald-500/45 bg-emerald-500/10 text-emerald-200";
  if (confidence === "media") return "border-amber-500/45 bg-amber-500/10 text-amber-200";
  return "border-red-500/45 bg-red-500/10 text-red-200";
}

function upcase(value: string) {
  return value.toUpperCase();
}

function normalizarCodigo(value: string) {
  // Mantém somente os separadores que fazem parte do código (por exemplo, "/").
  // Espaços, caracteres invisíveis e todas as variações usuais de hífen não
  // devem criar um código diferente do mesmo produto.
  return upcase(value).replace(/[\s\p{Cf}\-\u2010-\u2015\u2212\uFE58\uFE63\uFF0D]+/gu, "");
}

function fiscalNacional(value: CadastroItemAgenteFiscal | null): CadastroItemAgenteFiscal {
  return {
    ncm: null,
    cest: null,
    cfop_padrao: null,
    cst_icms: null,
    cst_pis: null,
    cst_cofins: null,
    aliq_icms: null,
    aliq_ipi: null,
    aliq_pis: null,
    aliq_cofins: null,
    credita_icms: false,
    ipi_entra_no_custo: true,
    credita_pis: false,
    credita_cofins: false,
    referencia_item_id: null,
    justificativa: null,
    ...(value ?? {}),
    origem: 0,
  };
}

export default function CadastroItemAgenteModal({
  open,
  onClose,
  fornecedores,
  fornecedoresLoading = false,
  fornecedoresError = null,
  onCreated,
}: CadastroItemAgenteModalProps) {
  const [fase, setFase] = useState<Fase>("entrada");
  const [fornecedorId, setFornecedorId] = useState("");
  const [codigo, setCodigo] = useState("");
  const [quantidade, setQuantidade] = useState("0");
  const [precoInput, setPrecoInput] = useState("");
  const [pesoInput, setPesoInput] = useState("");
  const [rascunho, setRascunho] = useState<Rascunho | null>(null);
  const [aceitarNovoGrupo, setAceitarNovoGrupo] = useState(false);
  const [duplicidade, setDuplicidade] = useState<CadastroItemAgenteDuplicidade | null>(null);
  const [busy, setBusy] = useState<"sugerir" | "confirmar" | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<CadastroItemAgenteItemCriado | null>(null);
  const [avisoEstoque, setAvisoEstoque] = useState<string | null>(null);

  const fornecedoresAtivos = useMemo(
    () => fornecedores.filter((fornecedor) => fornecedor.ativo !== false).sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR")),
    [fornecedores],
  );

  const quantidadeReferencia = parseQuantidade(quantidade);
  const sugestao = rascunho?.sugestao ?? null;
  const pesquisaPreco = sugestao?.pesquisa_preco ?? null;
  const precoFinal = pesquisaPreco?.preco_final_brl ?? pesquisaPreco?.preco_unitario_brl ?? null;
  const precoConfirmadoNumero = parseNumeroOpcional(precoInput);
  const totalEstimado = quantidadeReferencia !== null && precoConfirmadoNumero !== null ? quantidadeReferencia * precoConfirmadoNumero : null;
  const isUnidadeKg = (sugestao?.unidade_medida ?? "").trim().toUpperCase() === "KG";
  const pesoReferenciaNumero = parseNumeroOpcional(pesoInput);

  const limpar = useCallback(() => {
    setFase("entrada");
    setFornecedorId("");
    setCodigo("");
    setQuantidade("0");
    setPrecoInput("");
    setPesoInput("");
    setRascunho(null);
    setAceitarNovoGrupo(false);
    setDuplicidade(null);
    setBusy(null);
    setErro(null);
    setSucesso(null);
    setAvisoEstoque(null);
  }, []);

  const fechar = useCallback(() => {
    if (busy) return;
    limpar();
    onClose();
  }, [busy, limpar, onClose]);

  useEffect(() => {
    if (!open) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") fechar();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [open, fechar]);

  function atualizarSugestao(updater: (current: CadastroItemAgenteSugestao) => CadastroItemAgenteSugestao) {
    setRascunho((current) => (current ? { ...current, sugestao: updater(current.sugestao) } : current));
  }

  function atualizarFiscal(updater: (current: CadastroItemAgenteFiscal) => CadastroItemAgenteFiscal) {
    setRascunho((current) => {
      if (!current) return current;
      const fiscalBase = fiscalNacional(current.fiscal);
      return { ...current, fiscal: { ...updater(fiscalBase), origem: 0 } };
    });
  }

  async function sugerir(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setErro(null);
    setDuplicidade(null);
    const fornecedor = Number(fornecedorId);
    const codigoNormalizado = normalizarCodigo(codigo);
    if (!Number.isInteger(fornecedor) || fornecedor <= 0) {
      setErro("Selecione um fornecedor cadastrado e ativo.");
      return;
    }
    if (!codigoNormalizado) {
      setErro("Informe o código do produto.");
      return;
    }
    if (quantidadeReferencia === null) {
      setErro("Informe uma quantidade válida (0 ou mais).");
      return;
    }

    setBusy("sugerir");
    try {
      const headers = await authenticatedJsonHeaders();
      const response = await fetch("/api/itens/agente-cadastro/sugerir", {
        method: "POST",
        headers,
        body: JSON.stringify({
          fornecedor_id: fornecedor,
          codigo: codigoNormalizado,
          quantidade_referencia: quantidadeReferencia,
        }),
      });
      const payload: unknown = await response.json().catch(() => null);
      if (!response.ok) throw new Error(responseError(payload, "Não foi possível gerar a sugestão do agente."));

      const resultado = decodeCadastroItemAgenteSugestaoResposta(payload);
      if (resultado.error) throw new Error(resultado.error);
      if (resultado.duplicidade) {
        setDuplicidade(resultado.duplicidade);
        return;
      }
      if (!resultado.cotacao_token) {
        throw new Error("A cotação não foi selada pelo servidor. Gere a sugestão novamente.");
      }
      if (!resultado.sugestao?.descricao_padronizada.trim()) {
        throw new Error("O agente não retornou uma descrição segura. Revise o código e tente novamente.");
      }
      const sugestaoNormalizada: CadastroItemAgenteSugestao = {
        ...resultado.sugestao,
        codigo: normalizarCodigo(resultado.sugestao.codigo || codigoNormalizado),
        finalidade: "materia_prima",
      };
      const precoPesquisado =
        sugestaoNormalizada.pesquisa_preco?.preco_final_brl ?? sugestaoNormalizada.pesquisa_preco?.preco_unitario_brl ?? null;
      setPrecoInput(precoPesquisado !== null ? precoPesquisado.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 4 }) : "");
      setCodigo(sugestaoNormalizada.codigo);
      setRascunho({
        model: resultado.model,
        cotacaoToken: resultado.cotacao_token,
        sugestao: sugestaoNormalizada,
        similarInterno: resultado.similar_interno,
        fiscal: fiscalNacional(resultado.fiscal_sugerido),
        podeEditarFiscal: resultado.pode_editar_fiscal,
        fontes: resultado.fontes,
      });
      setAceitarNovoGrupo(false);
      setFase("revisao");
    } catch (cause) {
      setErro(cause instanceof Error ? cause.message : "Não foi possível gerar a sugestão do agente.");
    } finally {
      setBusy(null);
    }
  }

  async function confirmar() {
    if (!sugestao || !rascunho) return;
    setErro(null);
    const fornecedor = Number(fornecedorId);
    const codigoNormalizado = normalizarCodigo(codigo);
    if (!Number.isInteger(fornecedor) || fornecedor <= 0 || !codigoNormalizado || quantidadeReferencia === null) {
      setErro("Os dados iniciais estão incompletos. Volte e gere a sugestão novamente.");
      return;
    }
    if (!sugestao.descricao_padronizada.trim()) {
      setErro("A descrição padronizada é obrigatória.");
      return;
    }
    if (!sugestao.grupo_id && (!aceitarNovoGrupo || !sugestao.novo_grupo)) {
      setErro("Confirme o grupo sugerido ou revise a classificação antes de cadastrar.");
      return;
    }
    if (precoConfirmadoNumero === null || precoConfirmadoNumero <= 0) {
      setErro("Informe um preço unitário válido maior que zero antes de confirmar.");
      return;
    }

    const sugestaoConfirmada: CadastroItemAgenteSugestao = {
      ...sugestao,
      codigo: codigoNormalizado,
      descricao_padronizada: sugestao.descricao_padronizada.trim(),
      fabricante: sugestao.fabricante?.trim() || null,
      unidade_medida: sugestao.unidade_medida.trim() || "UN",
      finalidade: "materia_prima",
      novo_grupo: aceitarNovoGrupo ? sugestao.novo_grupo : null,
    };
    const body: CadastroItemAgenteConfirmarPayload = {
      fornecedor_id: fornecedor,
      codigo: codigoNormalizado,
      quantidade_referencia: quantidadeReferencia,
      preco_unitario_confirmado: precoConfirmadoNumero,
      peso_referencia_kg: isUnidadeKg ? pesoReferenciaNumero : null,
      cotacao_token: rascunho.cotacaoToken,
      model: rascunho.model,
      sugestao: sugestaoConfirmada,
      fiscal_sugerido: rascunho.fiscal,
      fontes: rascunho.fontes,
      similar_interno: rascunho.similarInterno,
    };

    setBusy("confirmar");
    try {
      const headers = await authenticatedJsonHeaders();
      const response = await fetch("/api/itens/agente-cadastro/confirmar", {
        method: "POST",
        headers,
        body: JSON.stringify(body),
      });
      const payload: unknown = await response.json().catch(() => null);
      if (!response.ok) throw new Error(responseError(payload, "Não foi possível confirmar o cadastro do item."));
      const created = decodeCreatedItem(payload, sugestaoConfirmada);
      setAvisoEstoque(isRecord(payload) ? text(payload.estoque_aviso) : null);
      setSucesso(created);
      setFase("concluido");
      try {
        await onCreated(created.id ?? 0, responseError(payload, "Item cadastrado com sucesso."));
      } catch {
        // O cadastro já foi confirmado. A tela pai poderá ser atualizada manualmente se necessário.
      }
    } catch (cause) {
      setErro(cause instanceof Error ? cause.message : "Não foi possível confirmar o cadastro do item.");
    } finally {
      setBusy(null);
    }
  }

  function voltarParaEntrada() {
    setFase("entrada");
    setRascunho(null);
    setAceitarNovoGrupo(false);
    setErro(null);
    setPrecoInput("");
    setPesoInput("");
  }

  const fontes = useMemo(() => {
    const primary = pesquisaPreco?.fonte || pesquisaPreco?.fonte_url || pesquisaPreco?.titulo
      ? [
          {
            fonte: pesquisaPreco.fonte,
            fonte_url: pesquisaPreco.fonte_url,
            url: pesquisaPreco.fonte_url,
            dominio: null,
            titulo: pesquisaPreco.titulo,
            marketplace: pesquisaPreco.marketplace ?? pesquisaPreco.fonte,
            preco: pesquisaPreco.preco_origem,
            moeda: pesquisaPreco.moeda,
            tipo_correspondencia: pesquisaPreco.tipo_correspondencia,
            observacao: pesquisaPreco.observacao,
          } satisfies CadastroItemAgenteFonte,
        ]
      : [];
    const unique = new Map<string, CadastroItemAgenteFonte>();
    for (const fonte of [...primary, ...(rascunho?.fontes ?? [])]) {
      const key = `${fonte.url ?? fonte.fonte_url ?? ""}|${fonte.titulo ?? ""}|${fonte.fonte ?? ""}`;
      if (!unique.has(key)) unique.set(key, fonte);
    }
    return [...unique.values()];
  }, [pesquisaPreco, rascunho?.fontes]);

  if (!open) return null;

  const grupoPendente = sugestao && !sugestao.grupo_id && sugestao.novo_grupo ? sugestao.novo_grupo : null;
  const fiscal = rascunho?.fiscal ?? null;

  return (
    <div
      className="fixed inset-0 z-[70] flex items-start justify-center overflow-y-auto bg-black/75 p-3 backdrop-blur-sm md:p-6"
      onClick={(event) => event.target === event.currentTarget && fechar()}
      role="presentation"
    >
      <section
        aria-label="Cadastro de item assistido por IA"
        aria-modal="true"
        role="dialog"
        className="my-auto w-full max-w-6xl overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950 shadow-2xl"
        onClick={(event) => event.stopPropagation()}
      >
        <header className="flex flex-col gap-3 border-b border-zinc-800 bg-zinc-900/45 px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 className="text-base font-semibold text-zinc-100">Novo item com agente de cadastro</h2>
            <p className="mt-0.5 text-xs text-zinc-400">
              A IA sugere a descrição, o grupo e a cotação. Nada é cadastrado antes da sua confirmação.
            </p>
          </div>
          <div className="flex items-center gap-2">
            {fase === "revisao" && (
              <button type="button" onClick={voltarParaEntrada} disabled={Boolean(busy)} className="rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-800">
                Nova consulta
              </button>
            )}
            <button type="button" onClick={fechar} disabled={Boolean(busy)} className="rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm text-zinc-200 hover:bg-zinc-800">
              {fase === "concluido" ? "Fechar" : "Cancelar"}
            </button>
          </div>
        </header>

        {fase === "entrada" && (
          <form onSubmit={sugerir} className="space-y-5 p-5">
            <div className="rounded-lg border border-sky-500/30 bg-sky-500/10 px-4 py-3 text-sm text-sky-100">
              Informe o fornecedor já cadastrado e o código. <strong>Quantidade é opcional: deixe 0 para apenas cadastrar, ou informe um valor para lançar esse estoque inicial ao confirmar.</strong>
            </div>

            {fornecedoresLoading && <div className="text-sm text-zinc-400">Carregando fornecedores...</div>}
            {fornecedoresError && <div role="alert" className="rounded-lg border border-red-500/40 bg-red-500/10 px-4 py-3 text-sm text-red-200">{fornecedoresError}</div>}

            <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
              <label>
                <span className={FIELD_LABEL_CLASS}>Fornecedor *</span>
                <select className={INPUT_CLASS} value={fornecedorId} onChange={(event) => setFornecedorId(event.target.value)} disabled={busy === "sugerir" || fornecedoresLoading}>
                  <option value="">Selecione</option>
                  {fornecedoresAtivos.map((fornecedor) => (
                    <option key={fornecedor.id} value={fornecedor.id}>
                      {fornecedor.nome}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                <span className={FIELD_LABEL_CLASS}>Código do produto *</span>
                <input
                  className={INPUT_CLASS}
                  value={codigo}
                  onChange={(event) => setCodigo(normalizarCodigo(event.target.value))}
                  placeholder="Ex.: 6XV1870-3QH20"
                  autoComplete="off"
                  disabled={busy === "sugerir"}
                />
                <span className="mt-1 block text-[11px] text-zinc-500">Espaços e hífens são removidos automaticamente.</span>
              </label>
              <label>
                <span className={FIELD_LABEL_CLASS}>Quantidade (estoque inicial)</span>
                <input
                  className={INPUT_CLASS}
                  value={quantidade}
                  onChange={(event) => setQuantidade(event.target.value)}
                  inputMode="decimal"
                  placeholder="0"
                  disabled={busy === "sugerir"}
                />
                <span className="mt-1 block text-[11px] text-zinc-500">0 = não lançar estoque agora.</span>
              </label>
            </div>

            {duplicidade && (
              <div className="rounded-lg border border-amber-500/45 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
                <div className="font-medium">Este código já possui cadastro para o fornecedor.</div>
                <div className="mt-1 text-amber-100/90">
                  {duplicidade.mensagem ??
                    [
                      duplicidade.id ? `Item #${duplicidade.id}` : null,
                      duplicidade.codigo,
                      duplicidade.nome,
                      duplicidade.ativo === false ? "inativo" : null,
                    ]
                      .filter(Boolean)
                      .join(" — ")}
                </div>
                <div className="mt-1 text-xs text-amber-200/90">Abra o item existente para revisar ou reativar; o agente não criará uma duplicidade.</div>
              </div>
            )}

            {erro && <div role="alert" className="rounded-lg border border-red-500/40 bg-red-500/10 px-4 py-3 text-sm text-red-200">{erro}</div>}

            <div className="flex flex-wrap items-center justify-end gap-2 border-t border-zinc-800 pt-4">
              <button type="submit" disabled={busy === "sugerir"} className="rounded-md bg-zinc-100 px-4 py-2 text-sm font-medium text-zinc-900 hover:bg-white">
                {busy === "sugerir" ? "Consultando agente..." : "Gerar sugestão com IA"}
              </button>
            </div>
          </form>
        )}

        {fase === "revisao" && sugestao && rascunho && (
          <div className="max-h-[78vh] space-y-5 overflow-y-auto p-5">
            <div className="flex flex-col gap-3 rounded-lg border border-zinc-800 bg-zinc-900/30 px-4 py-3 text-sm md:flex-row md:items-center md:justify-between">
              <div>
                <span className="text-zinc-400">Código:</span> <span className="font-medium text-zinc-100">{codigo}</span>
                <span className="mx-2 text-zinc-700">•</span>
                <span className="text-zinc-400">Quantidade:</span> <span className="font-medium text-zinc-100">{quantidade}</span>
                {quantidadeReferencia !== null && quantidadeReferencia > 0 && (
                  <span className="ml-2 text-xs text-emerald-300">(vai para o estoque ao confirmar)</span>
                )}
              </div>
              <span className={`w-fit rounded-full border px-2.5 py-1 text-xs font-medium ${confidenceClasses(sugestao.confianca)}`}>
                Confiança {sugestao.confianca}
              </span>
            </div>

            <section className="rounded-lg border border-zinc-800 bg-zinc-900/20 p-4">
              <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                <h3 className="font-medium text-zinc-100">Cadastro proposto</h3>
                {rascunho.model && <span className="text-xs text-zinc-500">Modelo: {rascunho.model}</span>}
              </div>
              <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                <label className="md:col-span-2">
                  <span className={FIELD_LABEL_CLASS}>Descrição padronizada *</span>
                  <input
                    className={INPUT_CLASS}
                    value={sugestao.descricao_padronizada}
                    onChange={(event) => atualizarSugestao((current) => ({ ...current, descricao_padronizada: upcase(event.target.value) }))}
                  />
                  <span className="mt-1 block text-[11px] text-zinc-500">Não repita fabricante, código ou modelo quando esses dados tiverem campo próprio.</span>
                </label>
                <label>
                  <span className={FIELD_LABEL_CLASS}>Fabricante</span>
                  <input
                    className={INPUT_CLASS}
                    value={sugestao.fabricante ?? ""}
                    onChange={(event) => atualizarSugestao((current) => ({ ...current, fabricante: upcase(event.target.value) || null }))}
                    placeholder="A confirmar"
                  />
                </label>
                <label>
                  <span className={FIELD_LABEL_CLASS}>Unidade</span>
                  <input
                    className={INPUT_CLASS}
                    value={sugestao.unidade_medida}
                    onChange={(event) => atualizarSugestao((current) => ({ ...current, unidade_medida: upcase(event.target.value) }))}
                    placeholder="UN"
                  />
                </label>
                {sugestao.modelo_referencia && (
                  <div className="md:col-span-2 rounded-md border border-zinc-800 bg-zinc-950/70 px-3 py-2 text-xs text-zinc-300">
                    <span className="font-medium text-zinc-200">Modelo/referência identificado:</span> {sugestao.modelo_referencia}
                    <span className="ml-1 text-zinc-500">(mantido fora da descrição)</span>
                  </div>
                )}
                {isUnidadeKg && (
                  <label>
                    <span className={FIELD_LABEL_CLASS}>Peso de referência (kg)</span>
                    <input
                      className={INPUT_CLASS}
                      value={pesoInput}
                      onChange={(event) => setPesoInput(event.target.value)}
                      inputMode="decimal"
                      placeholder="Ex.: 42,500"
                    />
                    <span className="mt-1 block text-[11px] text-zinc-500">Peso desta chapa/peça; sugere a quantidade em kg no orçamento.</span>
                  </label>
                )}
                <label>
                  <span className={FIELD_LABEL_CLASS}>Finalidade</span>
                  <input className={`${INPUT_CLASS} cursor-default text-zinc-300`} value="Matéria-prima" readOnly />
                </label>
                <label>
                  <span className={FIELD_LABEL_CLASS}>Preço unitário (R$) *</span>
                  <input
                    className={INPUT_CLASS}
                    value={precoInput}
                    onChange={(event) => setPrecoInput(event.target.value)}
                    inputMode="decimal"
                    placeholder="Ex.: 7145,59"
                  />
                  <span className="mt-1 block text-[11px] text-zinc-500">
                    {precoFinal !== null
                      ? "Sugerido pela pesquisa do agente; ajuste se você já tiver um preço mais atual."
                      : "O agente não encontrou um preço verificável nesta pesquisa; informe o valor antes de confirmar."}
                  </span>
                </label>
              </div>
            </section>

            <section className="rounded-lg border border-zinc-800 bg-zinc-900/20 p-4">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <h3 className="font-medium text-zinc-100">Dados fiscais</h3>
                {rascunho.similarInterno?.id && <span className="text-xs text-zinc-500">Referência interna: item #{rascunho.similarInterno.id}</span>}
              </div>
              <div className="mt-3 grid grid-cols-1 gap-3 md:grid-cols-4">
                <label>
                  <span className={FIELD_LABEL_CLASS}>NCM</span>
                  <input className={INPUT_CLASS} disabled={!rascunho.podeEditarFiscal} value={fiscal?.ncm ?? ""} onChange={(event) => atualizarFiscal((current) => ({ ...current, ncm: event.target.value || null }))} placeholder="A confirmar" />
                </label>
                <label>
                  <span className={FIELD_LABEL_CLASS}>CEST</span>
                  <input className={INPUT_CLASS} disabled={!rascunho.podeEditarFiscal} value={fiscal?.cest ?? ""} onChange={(event) => atualizarFiscal((current) => ({ ...current, cest: event.target.value || null }))} placeholder="A confirmar" />
                </label>
                <label>
                  <span className={FIELD_LABEL_CLASS}>Origem</span>
                  <select className={INPUT_CLASS} value="0" disabled>
                    <option value="0">0 — Nacional</option>
                  </select>
                </label>
                <label>
                  <span className={FIELD_LABEL_CLASS}>CFOP padrão</span>
                  <input className={INPUT_CLASS} disabled={!rascunho.podeEditarFiscal} value={fiscal?.cfop_padrao ?? ""} onChange={(event) => atualizarFiscal((current) => ({ ...current, cfop_padrao: event.target.value || null }))} placeholder="A confirmar" />
                </label>
              </div>
              <div className="mt-3 grid grid-cols-1 gap-3 md:grid-cols-3">
                <label>
                  <span className={FIELD_LABEL_CLASS}>CST ICMS</span>
                  <input className={INPUT_CLASS} disabled={!rascunho.podeEditarFiscal} value={fiscal?.cst_icms ?? ""} onChange={(event) => atualizarFiscal((current) => ({ ...current, cst_icms: event.target.value || null }))} />
                </label>
                <label>
                  <span className={FIELD_LABEL_CLASS}>CST PIS</span>
                  <input className={INPUT_CLASS} disabled={!rascunho.podeEditarFiscal} value={fiscal?.cst_pis ?? ""} onChange={(event) => atualizarFiscal((current) => ({ ...current, cst_pis: event.target.value || null }))} />
                </label>
                <label>
                  <span className={FIELD_LABEL_CLASS}>CST COFINS</span>
                  <input className={INPUT_CLASS} disabled={!rascunho.podeEditarFiscal} value={fiscal?.cst_cofins ?? ""} onChange={(event) => atualizarFiscal((current) => ({ ...current, cst_cofins: event.target.value || null }))} />
                </label>
              </div>
              <div className="mt-3 grid grid-cols-2 gap-3 md:grid-cols-4">
                {([
                  ["aliq_icms", "ICMS (%)"],
                  ["aliq_ipi", "IPI (%)"],
                  ["aliq_pis", "PIS (%)"],
                  ["aliq_cofins", "COFINS (%)"],
                ] as const).map(([field, label]) => (
                  <label key={field}>
                    <span className={FIELD_LABEL_CLASS}>{label}</span>
                    <input
                      className={INPUT_CLASS}
                      value={fiscal?.[field] ?? ""}
                      disabled={!rascunho.podeEditarFiscal}
                      onChange={(event) => atualizarFiscal((current) => ({ ...current, [field]: parseNumeroOpcional(event.target.value) }))}
                      inputMode="decimal"
                    />
                  </label>
                ))}
              </div>
              <div className="mt-3 flex flex-wrap gap-x-5 gap-y-2 text-xs text-zinc-300">
                {([
                  ["credita_icms", "Credita ICMS"],
                  ["credita_pis", "Credita PIS"],
                  ["credita_cofins", "Credita COFINS"],
                  ["ipi_entra_no_custo", "IPI entra no custo"],
                ] as const).map(([field, label]) => (
                  <label key={field} className="flex items-center gap-2">
                    <input type="checkbox" disabled={!rascunho.podeEditarFiscal} checked={fiscal?.[field] ?? (field === "ipi_entra_no_custo")} onChange={(event) => atualizarFiscal((current) => ({ ...current, [field]: event.target.checked }))} />
                    {label}
                  </label>
                ))}
              </div>
              {!rascunho.podeEditarFiscal && <p className="mt-3 text-[11px] text-amber-200/85">Seu perfil não possui permissão para gravar dados fiscais; a sugestão está disponível apenas para consulta.</p>}
            </section>

            <details className="rounded-lg border border-zinc-800 bg-zinc-900/10">
              <summary className="cursor-pointer px-4 py-3 text-sm font-medium text-zinc-300 marker:text-zinc-500">
                Grupo: {sugestao.grupo_caminho ?? sugestao.grupo_nome ?? grupoPendente?.nome ?? "a confirmar"} — ver detalhes{grupoPendente ? " e confirmar" : ""}
              </summary>
              <div className="space-y-4 border-t border-zinc-800 p-4">
                <section>
                  <h3 className="font-medium text-zinc-100">Grupo</h3>
                  {sugestao.grupo_id ? (
                    <div className="mt-3 rounded-md border border-emerald-500/30 bg-emerald-500/10 px-3 py-2 text-sm text-emerald-100">
                      <div className="font-medium">{sugestao.grupo_caminho ?? sugestao.grupo_nome ?? `Grupo #${sugestao.grupo_id}`}</div>
                      <div className="mt-1 text-xs text-emerald-200/80">Grupo existente sugerido pelo agente.</div>
                    </div>
                  ) : grupoPendente ? (
                    <div className="mt-3 rounded-md border border-sky-500/35 bg-sky-500/10 p-3 text-sm text-sky-100">
                      <label className="flex cursor-pointer items-start gap-2">
                        <input type="checkbox" checked={aceitarNovoGrupo} onChange={(event) => setAceitarNovoGrupo(event.target.checked)} className="mt-0.5" />
                        <span>
                          <span className="font-medium">Criar grupo sugerido ao confirmar</span>
                          <span className="mt-0.5 block text-xs text-sky-200/85">A criação só acontece com esta aprovação.</span>
                        </span>
                      </label>
                      <div className="mt-3 grid grid-cols-1 gap-3 md:grid-cols-2">
                        <label>
                          <span className={FIELD_LABEL_CLASS}>Nome do grupo</span>
                          <input
                            className={INPUT_CLASS}
                            value={grupoPendente.nome}
                            disabled={!aceitarNovoGrupo}
                            onChange={(event) => atualizarSugestao((current) => current.novo_grupo ? { ...current, novo_grupo: { ...current.novo_grupo, nome: event.target.value } } : current)}
                          />
                        </label>
                        <label>
                          <span className={FIELD_LABEL_CLASS}>Código do grupo</span>
                          <input
                            className={INPUT_CLASS}
                            value={grupoPendente.codigo}
                            disabled={!aceitarNovoGrupo}
                            onChange={(event) => atualizarSugestao((current) => current.novo_grupo ? { ...current, novo_grupo: { ...current.novo_grupo, codigo: upcase(event.target.value) } } : current)}
                          />
                        </label>
                      </div>
                    </div>
                  ) : (
                    <div className="mt-3 rounded-md border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-100">
                      O agente não encontrou um grupo seguro. Não confirme o cadastro sem classificar o item.
                    </div>
                  )}
                </section>

                <section>
                  <h3 className="font-medium text-zinc-100">Pesquisa de preço</h3>
                  {pesquisaPreco ? (
                    <>
                      <div className="mt-3 grid grid-cols-2 gap-3 text-sm md:grid-cols-4">
                        <div>
                          <div className="text-xs text-zinc-500">Preço de origem</div>
                          <div className="mt-0.5 font-medium text-zinc-100">{formatMoney(pesquisaPreco.preco_origem, pesquisaPreco.moeda ?? "BRL")}</div>
                        </div>
                        <div>
                          <div className="text-xs text-zinc-500">Preço confirmado</div>
                          <div className="mt-0.5 font-medium text-zinc-100">{formatMoney(precoConfirmadoNumero)}</div>
                        </div>
                        <div>
                          <div className="text-xs text-zinc-500">Correspondência</div>
                          <div className="mt-0.5 text-zinc-200">{pesquisaPreco.tipo_correspondencia ?? "A confirmar"}</div>
                        </div>
                        <div>
                          <div className="text-xs text-zinc-500">Total estimado ({quantidade})</div>
                          <div className="mt-0.5 font-medium text-zinc-100">{formatMoney(totalEstimado)}</div>
                        </div>
                      </div>
                      {pesquisaPreco.taxa_cambio_para_brl !== null && (
                        <p className="mt-3 text-xs text-zinc-400">
                          Câmbio aplicado: 1 {pesquisaPreco.moeda ?? "USD"} = {formatMoney(pesquisaPreco.taxa_cambio_para_brl)}
                          {pesquisaPreco.data_cambio ? ` em ${pesquisaPreco.data_cambio}` : ""}.
                          {externalUrl(pesquisaPreco.fonte_cambio_url) && (
                            <a href={externalUrl(pesquisaPreco.fonte_cambio_url) ?? undefined} target="_blank" rel="noreferrer" className="ml-1 text-sky-300 underline decoration-sky-500/50 underline-offset-2 hover:text-sky-200">
                              Fonte do câmbio
                            </a>
                          )}
                        </p>
                      )}
                    </>
                  ) : (
                    <p className="mt-2 text-sm text-amber-100">Nenhuma cotação verificável foi encontrada.</p>
                  )}
                  {fontes.length > 0 && (
                    <div className="mt-3 flex flex-wrap gap-2">
                      {fontes.map((fonte, index) => {
                        const url = externalUrl(fonte.url ?? fonte.fonte_url);
                        if (!url) return null;
                        return (
                          <a key={`${url}-${index}`} href={url} target="_blank" rel="noreferrer" className="rounded-md border border-zinc-700 px-2.5 py-1.5 text-xs text-sky-300 hover:bg-zinc-900 hover:text-sky-200">
                            {fonte.titulo ?? fonte.fonte ?? `Fonte ${index + 1}`}
                          </a>
                        );
                      })}
                    </div>
                  )}
                </section>

                {(sugestao.justificativa || sugestao.dados_pendentes.length > 0 || rascunho.similarInterno) && (
                  <section className="space-y-2 text-xs text-zinc-400">
                    {sugestao.justificativa && <p><span className="font-medium text-zinc-300">Justificativa:</span> {sugestao.justificativa}</p>}
                    {rascunho.similarInterno && <p><span className="font-medium text-zinc-300">Referência interna:</span> {[rascunho.similarInterno.codigo, rascunho.similarInterno.nome, rascunho.similarInterno.fornecedor].filter(Boolean).join(" — ")}</p>}
                    {sugestao.dados_pendentes.length > 0 && <p><span className="font-medium text-amber-200">Pendente:</span> {sugestao.dados_pendentes.join("; ")}</p>}
                  </section>
                )}
              </div>
            </details>

            {erro && <div role="alert" className="rounded-lg border border-red-500/40 bg-red-500/10 px-4 py-3 text-sm text-red-200">{erro}</div>}

            <div className="flex flex-wrap items-center justify-end gap-2 border-t border-zinc-800 pt-4">
              <button type="button" onClick={voltarParaEntrada} disabled={Boolean(busy)} className="mr-auto rounded-md border border-zinc-700 bg-zinc-900 px-4 py-2 text-sm text-zinc-200 hover:bg-zinc-800">
                Voltar
              </button>
              <button type="button" onClick={fechar} disabled={Boolean(busy)} className="rounded-md border border-zinc-700 bg-zinc-900 px-4 py-2 text-sm text-zinc-200 hover:bg-zinc-800">
                Cancelar
              </button>
              <button
                type="button"
                onClick={() => void confirmar()}
                disabled={
                  busy === "confirmar" ||
                  (!sugestao.grupo_id && (!aceitarNovoGrupo || !sugestao.novo_grupo)) ||
                  precoConfirmadoNumero === null ||
                  precoConfirmadoNumero <= 0
                }
                className="rounded-md bg-zinc-100 px-4 py-2 text-sm font-medium text-zinc-900 hover:bg-white"
              >
                {busy === "confirmar" ? "Confirmando cadastro..." : grupoPendente && aceitarNovoGrupo ? "Criar grupo e cadastrar" : "Confirmar cadastro"}
              </button>
            </div>
          </div>
        )}

        {fase === "concluido" && (
          <div className="space-y-5 p-5">
            <div className="rounded-lg border border-emerald-500/40 bg-emerald-500/10 px-4 py-4 text-emerald-100">
              <div className="font-medium">Item cadastrado com sucesso.</div>
              <div className="mt-1 text-sm text-emerald-100/90">{[sucesso?.id ? `Item #${sucesso.id}` : null, sucesso?.codigo, sucesso?.nome].filter(Boolean).join(" — ")}</div>
              <div className="mt-2 text-xs text-emerald-200/85">
                {quantidadeReferencia !== null && quantidadeReferencia > 0
                  ? `Estoque inicial de ${quantidade} unidade(s) lançado ao confirmar o cadastro.`
                  : "Nenhuma quantidade foi informada; o item foi cadastrado sem estoque inicial."}
              </div>
            </div>
            {avisoEstoque && (
              <div role="alert" className="rounded-lg border border-amber-500/45 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
                {avisoEstoque}
              </div>
            )}
            <div className="flex justify-end gap-2">
              <button type="button" onClick={fechar} className="rounded-md bg-zinc-100 px-4 py-2 text-sm font-medium text-zinc-900 hover:bg-white">Fechar</button>
            </div>
          </div>
        )}
      </section>
    </div>
  );
}
