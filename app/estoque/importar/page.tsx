"use client";

import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { formatDecimalBR, formatMoneyBR } from "@/lib/decimal";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useTenantEmpresa } from "@/lib/auth/useTenantEmpresa";
import { applyTenantEmpresa } from "@/lib/db/scopes";
import { usePermissions } from "@/components/auth/PermissionsProvider";
import { Can } from "@/components/auth/Can";
import { useImportMotivos, type MotivoCompra } from "./ImportMotivosProvider";
import MotivoCompraCombobox from "./MotivoCompraCombobox";
import { parseNfeXml, type ParsedItem, type ParsedNfe } from "@/lib/nfe/parseNfeXml";
import {
  analyzeXmlImport,
  normalizeXmlItemCode,
  type XmlImportItemInterno,
  type XmlImportPedidoCandidato,
  type XmlImportPedidoItem,
} from "@/lib/nfe/xmlImportAnalyzer";
import { getImportacaoXmlParams, type ItemFinalidade as ParamItemFinalidade } from "@/src/lib/importacaoXmlParams";
import XmlImportAssistantPanel from "./XmlImportAssistantPanel";
import {
  imprimirRelatorioDestinos,
  isRelatorioDestinoImportacao,
  type RelatorioDestinoImportacao,
} from "./relatorioDestinoPrint";

type FiscalPerfil = {
  item_id: number;
  ncm: string | null;
  cst_icms: string | null;
  cst_pis: string | null;
  cst_cofins: string | null;
  aliq_icms: number | null;
  aliq_ipi: number | null;
  aliq_pis: number | null;
  aliq_cofins: number | null;
  credita_icms: boolean;
  credita_pis: boolean;
  credita_cofins: boolean;
  ipi_entra_no_custo: boolean;
};

type ImportJob = {
  id: string;
  fileName: string;
  xmlText: string;
  nfeInfo: ParsedNfe | null;
  itens: ParsedItem[];
  fornecedorCnpj: string | null;
  status: "ok" | "erro" | "importando" | "importado";
  error?: string;
  selected: boolean;
};

type ItemFinalidade = ParamItemFinalidade | "revenda";

type FornecedorRow = {
  id: number;
  nome: string | null;
  cnpj_norm?: string | null;
  finalidade_padrao?: ItemFinalidade | null;
  motivo_compra_padrao_id?: string | null;
  gerar_contas_pagar_auto?: boolean | null;
};

type ItemCodigoRow = {
  id: number;
  codigo_interno: string;
  nome?: string | null;
  fornecedor_id?: number | null;
  ativo?: boolean | null;
};

type ItemCodigoMap = Map<string, ItemCodigoRow>;

type NovoGrupoCadastroSuggestion = {
  codigo: string;
  nome: string;
  grupo_pai_id: number | null;
  justificativa: string;
};

type NormalizacaoCadastroSuggestion = {
  codigo: string;
  descricao_padronizada: string;
  grupo_id: number | null;
  novo_grupo: NovoGrupoCadastroSuggestion | null;
  grupo_nome: string | null;
  grupo_caminho: string | null;
  justificativa: string;
  dados_pendentes: string[];
  confianca: "alta" | "media" | "baixa";
};

type NormalizacaoCadastroResponse = {
  model?: string;
  sugestoes?: NormalizacaoCadastroSuggestion[];
  error?: string;
};

type OsLookupRow = {
  id: number;
  numero_os?: string | null;
  cliente_nome?: string | null;
  descricao_servico?: string | null;
  status?: string | null;
};

type DbError = {
  code?: string;
  message?: string;
};

type FiscalPayload = {
  tenant_id: string;
  empresa_id: string;
  item_id: number;
  ncm: string | null;
  cst_icms: string | null;
  cst_pis: string | null;
  cst_cofins: string | null;
  aliq_icms: number | null;
  aliq_ipi: number | null;
  aliq_pis: number | null;
  aliq_cofins: number | null;
  credita_icms: boolean;
  credita_pis: boolean;
  credita_cofins: boolean;
  ipi_entra_no_custo: boolean;
};

type UsuarioSolicitante = {
  id: string;
  nome: string;
  email: string;
};

type UsuariosSolicitantesApiResponse = { usuarios?: UsuarioSolicitante[]; error?: string };

type PedidoLookupRow = {
  id: string;
  codigo: string | null;
  status: string | null;
  fornecedor_id?: number | string | null;
  fornecedor_nome?: string | null;
  solicitante_usuario_id?: string | null;
  created_at?: string | null;
  total_geral?: number | string | null;
};

type PedidoItemLinkRequest = {
  xmlItemIndex: number;
  codigoOriginal: string;
  codigoNormalizado: string;
  descricao: string;
  pedidoId: string;
  pedidoCodigo?: string | null;
  pedidoItemId: string;
};

type VincularPedidoItemResponse = {
  ok?: boolean;
  pedidoItem?: {
    id?: string | null;
    pedido_compra_id?: string | null;
    item_id?: number | string | null;
    item_codigo?: string | null;
    item_nome?: string | null;
  };
  error?: string;
};

function toNullableString(value: unknown): string | null {
  const text = String(value ?? "").trim();
  return text ? text : null;
}

function toNullableNumber(value: unknown): number | null {
  if (value == null || String(value).trim() === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function splitPedidoCompraRefs(value: unknown): string[] {
  return String(value ?? "")
    .split(/[,;\n]+/)
    .map((ref) => ref.trim())
    .filter(Boolean);
}

function isPedidoItemManualParaVinculo(item: Pick<XmlImportPedidoItem, "item_id" | "item_codigo">): boolean {
  const codigo = String(item.item_codigo ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toUpperCase();
  const semCodigo = !codigo || codigo === "-" || codigo === "MANUAL" || codigo === "SEM CODIGO" || codigo === "SEM CODIGO INTERNO";
  return !toNullableNumber(item.item_id) && semCodigo;
}

function adaptPedidoAnalyzerCandidato(raw: unknown): XmlImportPedidoCandidato | null {
  if (!raw || typeof raw !== "object") return null;
  const row = raw as Record<string, unknown>;
  const id = toNullableString(row.id);
  if (!id) return null;

  const itensRaw = Array.isArray(row.itens) ? row.itens : [];
  const itens = itensRaw.reduce<XmlImportPedidoItem[]>((acc, rawItem) => {
    if (!rawItem || typeof rawItem !== "object") return acc;
    const item = rawItem as Record<string, unknown>;
    const itemId = toNullableString(item.id);
    if (!itemId) return acc;
    acc.push({
      id: itemId,
      seq: toNullableNumber(item.seq),
      item_id: item.item_id == null ? null : String(item.item_id),
      item_codigo: toNullableString(item.item_codigo),
      item_nome: toNullableString(item.item_nome),
      descricao: toNullableString(item.descricao),
      quantidade: item.quantidade == null ? null : String(item.quantidade),
      quantidade_recebida: item.quantidade_recebida == null ? null : String(item.quantidade_recebida),
      valor_unitario: item.valor_unitario == null ? null : String(item.valor_unitario),
      valor_total: item.valor_total == null ? null : String(item.valor_total),
      origem_os_id: toNullableNumber(item.origem_os_id),
      origem_os_numero: toNullableString(item.origem_os_numero),
      origem_os_label: toNullableString(item.origem_os_label),
    });
    return acc;
  }, []);

  return {
    id,
    codigo: toNullableString(row.codigo),
    status: toNullableString(row.status),
    fornecedor_id: toNullableNumber(row.fornecedor_id),
    fornecedor_nome: toNullableString(row.fornecedor_nome),
    solicitante_usuario_id: toNullableString(row.solicitante_usuario_id),
    total_geral: row.total_geral == null ? null : String(row.total_geral),
    total_pendente: row.total_pendente == null ? null : String(row.total_pendente),
    itens,
  };
}

function normalizeImportedItemCode(code: unknown): string {
  return normalizeXmlItemCode(code);
}

function addItemCodigoToMap(map: ItemCodigoMap, row: ItemCodigoRow): void {
  const codigo = String(row.codigo_interno ?? "").trim();
  if (!codigo) return;
  if (!map.has(codigo)) map.set(codigo, row);

  const normalized = normalizeImportedItemCode(codigo);
  if (normalized && !map.has(normalized)) map.set(normalized, row);
}

function getItemCodigoFromMap(map: ItemCodigoMap, code: unknown): ItemCodigoRow | undefined {
  const raw = String(code ?? "").trim();
  if (!raw) return undefined;
  return map.get(raw) ?? map.get(normalizeImportedItemCode(raw));
}

function hasItemCodigoInMap(map: ItemCodigoMap, code: unknown): boolean {
  return Boolean(getItemCodigoFromMap(map, code));
}

function normalizeMotivoSearchText(value: unknown): string {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^A-Za-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .toUpperCase();
}

function findMotivoAutomaticoParaPedido(
  motivos: MotivoCompra[],
  contexto: { temOs?: boolean; finalidade?: ItemFinalidade | "" | null }
): MotivoCompra | null {
  const finalidade = String(contexto.finalidade ?? "").trim().toLowerCase();
  const preferirOs = Boolean(contexto.temOs);
  const codigosPreferidos = preferirOs
    ? ["OS_MATERIAL_DIRETO", "OS", "EST_MATERIA_PRIMA"]
    : finalidade === "materia_prima"
      ? ["ESTOQUE", "EST_MATERIA_PRIMA", "CONSUMO_GERAL"]
      : ["ESTOQUE", "CONSUMO", "CONSUMO_GERAL"];

  for (const codigoPreferido of codigosPreferidos) {
    const motivo = motivos.find((row) => normalizeMotivoSearchText(row.codigo) === normalizeMotivoSearchText(codigoPreferido));
    if (motivo) return motivo;
  }

  const scored = motivos
    .filter((motivo) => normalizeMotivoSearchText(motivo.codigo) !== "NAO CLASSIFICADO")
    .map((motivo) => {
      const codigo = normalizeMotivoSearchText(motivo.codigo);
      const nome = normalizeMotivoSearchText(motivo.nome);
      const text = `${codigo} ${nome}`;
      let score = 0;

      if (text.includes("PEDIDO") && text.includes("COMPRA")) score += 60;
      if (text.includes("ORDEM") && text.includes("COMPRA")) score += 50;
      if (text.includes("COMPRA") && text.includes("OS")) score += 50;
      if (text.includes("MATERIAL") && text.includes("OS")) score += 45;
      if (text.includes("MATERIA") && text.includes("PRIMA")) score += 40;
      if (text.includes("PEDIDO")) score += 25;
      if (text.includes("COMPRA")) score += 15;
      if (preferirOs && (text.includes("OS") || text.includes("ORDEM") || text.includes("MATERIAL") || text.includes("MATERIA"))) {
        score += 20;
      }
      if (motivo.favorito) score += 5;
      score += Math.min(5, Number(motivo.qtd_usos_180d ?? 0) / 20);

      return { motivo, score };
    })
    .filter((row) => row.score > 0)
    .sort((a, b) => b.score - a.score || a.motivo.ordem - b.motivo.ordem || a.motivo.nome.localeCompare(b.motivo.nome, "pt-BR"));

  return scored[0]?.motivo ?? null;
}

type ImportItemPayload = {
  tenant_id: string;
  item_id: number | null;
  numero_item_xml?: number | null;
  codigo_fornecedor: string;
  // Compat: o importador do banco (public.import_nf_entrada) espera "codigo" e "nome".
  // Mantemos também "codigo_fornecedor"/"descricao" porque o app usa esses nomes no client.
  codigo?: string;
  nome?: string;
  descricao: string;
  unidade?: string | null;
  unidade_tributavel?: string | null;
  ean?: string | null;
  ean_tributavel?: string | null;
  ncm: string | null;
  cest?: string | null;
  cfop?: string | null;
  pedido_xml?: string | null;
  pedido_item_xml?: string | null;
  informacoes_adicionais?: string | null;
  qtd: number;
  v_unit: number;
  v_prod: number;
  v_desc?: number;
  v_frete?: number;
  v_seguro?: number;
  v_outro?: number;
  v_st?: number;
  v_icms: number;
  v_ipi: number;
  v_pis: number;
  v_cofins: number;
  aliq_icms: number | null;
  aliq_ipi: number | null;
  aliq_pis: number | null;
  aliq_cofins: number | null;
  quantidade: number;
  tipo: "entrada";
  motivo: string;
  realizado_por: string | null;
  data_movimentacao: string;
  custo_unitario_bruto: number | null;
  custo_unitario_real: number | null;
  v_frete_rateado: number;
  credito_icms: number;
  credito_pis: number;
  credito_cofins: number;
};

type NfEntradaResumoRow = {
  id: number;
  chave: string;
  numero: string | null;
  serie: string | null;
  emitente_nome: string | null;
  data_emissao: string | null;
  valor_total: number | string | null;
  criado_em: string | null;
  finalidade_contexto?: string | null;
  fornecedor_id?: number | null;
  motivo_compra_id?: string | null;
  solicitante_usuario_id?: string | null;
};

const RECENT_NFS_LIMIT = 20;

type ParcelaPayload = {
  numero: string;
  vencimento: string;
  valor: number;
  forma_pagamento?: string | null;
};

type PagamentoModoImportacao = "seguir_nota" | "cartao" | "dinheiro" | "faturado";

type PagamentoImportacaoConfig =
  | { modo: "seguir_nota" }
  | { modo: "cartao"; quantidade: number }
  | { modo: "dinheiro" }
  | { modo: "faturado"; parcelas: ParcelaPayload[] };

type FaturadoParcelaForm = {
  numero: string;
  valor: string;
  vencimento: string;
};

function getErrorMessage(err: unknown, fallback: string) {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  if (err && typeof err === "object" && "message" in err) {
    const msg = (err as { message?: string }).message;
    if (typeof msg === "string" && msg.trim() !== "") return msg;
  }
  return fallback;
}

function normalizeCnpj(doc: string | null): string | null {
  if (!doc) return null;
  const onlyDigits = doc.replace(/\D/g, "");
  if (!onlyDigits) return null;
  return onlyDigits.length === 14 ? onlyDigits : null;
}

function toDateOnly(value: string | null | undefined): string | null {
  const v = (value ?? "").trim();
  if (!v) return null;
  // aceita YYYY-MM-DD ou ISO com horário
  if (/^\d{4}-\d{2}-\d{2}/.test(v)) return v.slice(0, 10);
  return null;
}

function formatDateBR(iso?: string | null): string {
  if (!iso) return "";
  const v = String(iso);
  const d = new Date(v.includes("T") ? v : `${v}T00:00:00`);
  if (Number.isNaN(d.getTime())) return v;
  return d.toLocaleDateString("pt-BR");
}

function formatFinalidadeImportada(value: string | null | undefined): string {
  const key = String(value ?? "").trim().toLowerCase();
  if (key === "materia_prima") return "Materia-prima";
  if (key === "imobilizado") return "Imobilizado";
  if (key === "consumo") return "Consumo";
  if (key === "revenda") return "Revenda";
  return key || "-";
}

function clampParcelas(value: number): number {
  if (!Number.isFinite(value)) return 1;
  return Math.min(60, Math.max(1, Math.trunc(value)));
}

function parseIsoDateLocal(iso: string): Date {
  const [year, month, day] = iso.split("-").map((part) => Number(part));
  if (!year || !month || !day) {
    return new Date(new Date().getFullYear(), new Date().getMonth(), new Date().getDate(), 12, 0, 0, 0);
  }
  return new Date(year, month - 1, day, 12, 0, 0, 0);
}

function formatIsoDateLocal(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function addMonthsKeepingDay(base: Date, months: number, dayOverride?: number): Date {
  const targetDay = dayOverride ?? base.getDate();
  const first = new Date(base.getFullYear(), base.getMonth() + months, 1, 12, 0, 0, 0);
  const lastDay = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
  return new Date(first.getFullYear(), first.getMonth(), Math.min(targetDay, lastDay), 12, 0, 0, 0);
}

function splitAmount(total: number, parcelas: number): number[] {
  const count = clampParcelas(parcelas);
  const totalCents = Math.round(Math.max(0, total) * 100);
  const base = Math.floor(totalCents / count);
  const rest = totalCents - base * count;
  return Array.from({ length: count }, (_, idx) => (base + (idx < rest ? 1 : 0)) / 100);
}

function parseMoneyInput(raw: string): number {
  const input = String(raw ?? "").trim().replace(/\s/g, "");
  const normalized = input.includes(",") && input.includes(".")
    ? input.replace(/\./g, "").replace(",", ".")
    : input.replace(",", ".");
  const n = Number(normalized);
  return Number.isFinite(n) ? Number(n.toFixed(2)) : Number.NaN;
}

function buildParcelasDinheiro(total: number, dataEmissao: string | null | undefined): ParcelaPayload[] {
  const emissao = toDateOnly(dataEmissao) ?? toDateOnly(new Date().toISOString()) ?? formatIsoDateLocal(new Date());
  return [{ numero: "001", vencimento: emissao, valor: Number(total.toFixed(2)), forma_pagamento: "DINHEIRO" }];
}

function buildParcelasCartao(total: number, parcelas: number, dataEmissao: string | null | undefined): ParcelaPayload[] {
  const count = clampParcelas(parcelas);
  const emissao = toDateOnly(dataEmissao) ?? toDateOnly(new Date().toISOString()) ?? formatIsoDateLocal(new Date());
  const emissaoDate = parseIsoDateLocal(emissao);
  const primeiroVencimento = addMonthsKeepingDay(emissaoDate, 1, 9);
  const valores = splitAmount(total, count);

  return valores.map((valor, idx) => ({
    numero: String(idx + 1).padStart(3, "0"),
    vencimento: formatIsoDateLocal(addMonthsKeepingDay(primeiroVencimento, idx, 9)),
    valor,
    forma_pagamento: "CARTAO",
  }));
}

function buildFaturadoDrafts(
  quantidade: number,
  total: number,
  dataEmissao: string | null | undefined,
  previous: FaturadoParcelaForm[] = []
): FaturadoParcelaForm[] {
  const count = clampParcelas(quantidade);
  const emissao = toDateOnly(dataEmissao) ?? toDateOnly(new Date().toISOString()) ?? formatIsoDateLocal(new Date());
  const emissaoDate = parseIsoDateLocal(emissao);
  const valores = total > 0 ? splitAmount(total, count) : Array.from({ length: count }, () => 0);

  return Array.from({ length: count }, (_, idx) => {
    const prev = previous[idx];
    return {
      numero: String(idx + 1).padStart(3, "0"),
      valor: prev?.valor ?? (valores[idx] > 0 ? valores[idx].toFixed(2) : ""),
      vencimento: prev?.vencimento ?? formatIsoDateLocal(addMonthsKeepingDay(emissaoDate, idx + 1)),
    };
  });
}

function buildParcelasPorPagamento(
  nfe: ParsedNfe,
  config: PagamentoImportacaoConfig | null
): ParcelaPayload[] | null {
  const modo = config?.modo ?? "seguir_nota";
  if (modo === "seguir_nota") {
    const fromXml = nfe.parcelas ?? [];
    return fromXml.length > 0 ? fromXml : null;
  }

  const total = Number(nfe.valorTotal ?? 0);
  if (!Number.isFinite(total) || total <= 0) {
    throw new Error("Valor total da NF invalido para gerar parcelas.");
  }

  if (modo === "dinheiro") {
    return buildParcelasDinheiro(total, nfe.dataEmissao);
  }
  if (modo === "cartao" && config?.modo === "cartao") {
    return buildParcelasCartao(total, config.quantidade, nfe.dataEmissao);
  }
  if (modo === "faturado" && config?.modo === "faturado") {
    return config.parcelas.map((parcela) => ({ ...parcela, forma_pagamento: parcela.forma_pagamento ?? "FATURADO" }));
  }
  return null;
}

async function copyTextToClipboard(text: string): Promise<void> {
  if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      return;
    } catch {
      // Fallback abaixo para navegadores/contextos que bloqueiam Clipboard API.
    }
  }

  if (typeof document === "undefined") throw new Error("Clipboard indisponivel.");

  const textarea = document.createElement("textarea");
  textarea.value = text;
  textarea.setAttribute("readonly", "");
  textarea.style.position = "fixed";
  textarea.style.left = "-9999px";
  textarea.style.top = "0";

  document.body.appendChild(textarea);
  textarea.focus();
  textarea.select();

  try {
    const copied = document.execCommand("copy");
    if (!copied) throw new Error("Falha ao copiar.");
  } finally {
    textarea.remove();
  }
}

export default function ImportarXmlPage() {
  const router = useRouter();
  const supabase = useMemo(() => {
    if (typeof window === "undefined") return null as unknown as ReturnType<typeof supabaseBrowser>;
    return supabaseBrowser();
  }, []);

  const [xmlText, setXmlText] = useState("");
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const [isReading, setIsReading] = useState(false);
  const readReqIdRef = useRef(0);

  const [fornecedorId, setFornecedorId] = useState<number | null>(null);
  const [fornecedorNome, setFornecedorNome] = useState<string | null>(null);
  const [fornecedorFinalidadePadrao, setFornecedorFinalidadePadrao] = useState<ItemFinalidade | null>(null);
  const [fornecedorMotivoPadraoId, setFornecedorMotivoPadraoId] = useState<string | null>(null);

  const [importErr, setImportErr] = useState<string | null>(null);
  const [importOk, setImportOk] = useState<string | null>(null);
  const [importWarn, setImportWarn] = useState<string | null>(null);
  const [importBusy, setImportBusy] = useState(false);
  const [cadBusy, setCadBusy] = useState(false);

  const [itemMap, setItemMap] = useState<ItemCodigoMap>(new Map());
  const [normalizacoesCadastro, setNormalizacoesCadastro] = useState<Record<string, NormalizacaoCadastroSuggestion>>({});
  const [normalizacaoCadastroBusy, setNormalizacaoCadastroBusy] = useState(false);
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const [jobs, setJobs] = useState<ImportJob[]>([]);
  const [selectedJobId, setSelectedJobId] = useState<string | null>(null);
  const [showPagamentoModal, setShowPagamentoModal] = useState(false);
  const [pagamentoModo, setPagamentoModo] = useState<PagamentoModoImportacao>("seguir_nota");
  const [pagamentoParcelasQtd, setPagamentoParcelasQtd] = useState(1);
  const [faturadoParcelasForm, setFaturadoParcelasForm] = useState<FaturadoParcelaForm[]>([]);
  const [pagamentoModalErr, setPagamentoModalErr] = useState<string | null>(null);

  const [fornecedorCnpjBase, setFornecedorCnpjBase] = useState<string | null>(null);
  const [fornecedorIdBase, setFornecedorIdBase] = useState<number | null>(null);

  // Fonte de verdade durante parsing (evita race/stale setState ao ler múltiplos XMLs)
  const fornecedorCnpjBaseRef = useRef<string | null>(null);
  // Evita duplicidade por closure stale durante addJobFromRaw
  const chavesAddedRef = useRef<Set<string>>(new Set());

  const [fornecedorGerarContasAuto, setFornecedorGerarContasAuto] = useState(false);

  const [finalidadeLote, setFinalidadeLote] = useState<ItemFinalidade | "">("");

  const [allowedAutoCadastrarFinalidades, setAllowedAutoCadastrarFinalidades] = useState<string[]>(["materia_prima"]);
  const [allowedVincularFinalidades, setAllowedVincularFinalidades] = useState<string[]>(["materia_prima", "revenda"]);

  const allowedAutoCadastrarSet = useMemo(
    () => new Set(allowedAutoCadastrarFinalidades.map((v) => String(v).trim()).filter(Boolean)),
    [allowedAutoCadastrarFinalidades]
  );
  const allowedVincularSet = useMemo(
    () => new Set(allowedVincularFinalidades.map((v) => String(v).trim()).filter(Boolean)),
    [allowedVincularFinalidades]
  );
  const finalidadesComItemObrigatorio = useMemo(() => new Set<string>(["materia_prima", "revenda"]), []);

  const {
    motivos,
    loading: motivosLoading,
    error: motivosError,
    setFavorito: setMotivoFavorito,
  } = useImportMotivos();
  const [motivoCompraId, setMotivoCompraId] = useState<string>("");

  const [solicitanteUsuarioId, setSolicitanteUsuarioId] = useState<string>("");
  const [usuariosSolicitantes, setUsuariosSolicitantes] = useState<UsuarioSolicitante[]>([]);
  const [usuariosSolicitantesLoading, setUsuariosSolicitantesLoading] = useState(false);
  const [usuariosSolicitantesError, setUsuariosSolicitantesError] = useState<string | null>(null);
  const [pedidoCompraRef, setPedidoCompraRef] = useState("");
  const [showPedidoLookup, setShowPedidoLookup] = useState(false);
  const [pedidoLookupTerm, setPedidoLookupTerm] = useState("");
  const [pedidoLookupRows, setPedidoLookupRows] = useState<PedidoLookupRow[]>([]);
  const [pedidoAnalyzerRows, setPedidoAnalyzerRows] = useState<PedidoLookupRow[]>([]);
  const [pedidosAnalyzerComItens, setPedidosAnalyzerComItens] = useState<XmlImportPedidoCandidato[]>([]);
  const [pedidosAnalyzerLoading, setPedidosAnalyzerLoading] = useState(false);
  const [pedidosAnalyzerError, setPedidosAnalyzerError] = useState<string | null>(null);
  const [assistantCopyMessage, setAssistantCopyMessage] = useState<{ kind: "ok" | "error"; message: string } | null>(
    null
  );
  const [pedidoItemLink, setPedidoItemLink] = useState<PedidoItemLinkRequest | null>(null);
  const [pedidoItemLinkSelectedId, setPedidoItemLinkSelectedId] = useState<string>("");
  const [pedidoItemLinkBusy, setPedidoItemLinkBusy] = useState(false);
  const [pedidoItemLinkError, setPedidoItemLinkError] = useState<string | null>(null);
  const [pedidoLookupLoading, setPedidoLookupLoading] = useState(false);
  const [pedidoLookupError, setPedidoLookupError] = useState<string | null>(null);
  const pedidoLookupDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const [defaultsToast, setDefaultsToast] = useState<{ kind: "saved" | "error" | "warn"; message: string } | null>(
    null
  );
  const toastTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const fornecedorIdRef = useRef<number | null>(null);
  const finalidadeRef = useRef<ItemFinalidade | "">("");
  const motivoCompraIdRef = useRef<string>("");
  useEffect(() => {
    fornecedorIdRef.current = fornecedorId;
    finalidadeRef.current = finalidadeLote;
    motivoCompraIdRef.current = motivoCompraId;
  }, [finalidadeLote, fornecedorId, motivoCompraId]);

  const defaultsDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pendingDefaultsRef = useRef<{
    fornecedorId: number;
    finalidade: ItemFinalidade | null;
    motivoCompraId: string | null;
  } | null>(null);

  const clearToastLater = useCallback((ms = 2200) => {
    if (toastTimerRef.current) clearTimeout(toastTimerRef.current);
    toastTimerRef.current = setTimeout(() => setDefaultsToast(null), ms);
  }, []);

  const aplicarMotivoAutomatico = useCallback(
    (contexto: { temOs?: boolean; origem: "pedido" | "os" }) => {
      const motivoAtual = motivos.find((row) => row.id === motivoCompraIdRef.current) ?? null;
      const codigoAtual = normalizeMotivoSearchText(motivoAtual?.codigo);
      const motivosSubstituiveisAoDirecionarParaOs = new Set([
        "",
        "NAO CLASSIFICADO",
        "ESTOQUE",
        "EST MATERIA PRIMA",
        "CONSUMO",
        "CONSUMO GERAL",
      ]);

      if (
        motivoCompraIdRef.current &&
        (!contexto.temOs || !motivosSubstituiveisAoDirecionarParaOs.has(codigoAtual))
      ) {
        return false;
      }

      const motivo = findMotivoAutomaticoParaPedido(motivos, {
        temOs: contexto.temOs,
        finalidade: finalidadeRef.current,
      });
      if (!motivo) return false;

      setMotivoCompraId(motivo.id);
      motivoCompraIdRef.current = motivo.id;
      setDefaultsToast({
        kind: "saved",
        message:
          contexto.origem === "os"
            ? "Classificacao ajustada para material direto de OS."
            : "Classificacao/motivo preenchido automaticamente pelo pedido.",
      });
      clearToastLater(2600);
      return true;
    },
    [clearToastLater, motivos]
  );

  const normalizeFinalidade = (v: ItemFinalidade | "" | null | undefined): ItemFinalidade | null => {
    if (!v) return null;
    return v as ItemFinalidade;
  };

  const normalizeMotivoId = (v: string | null | undefined): string | null => {
    const s = String(v ?? "").trim();
    return s ? s : null;
  };

  const saveFornecedorImportDefaultsNow = useCallback(
    async (payload: { fornecedorId: number; finalidade: ItemFinalidade | null; motivoCompraId: string | null }) => {
      try {
        const { error } = await supabase.rpc("set_fornecedor_import_defaults", {
          p_fornecedor_id: payload.fornecedorId,
          p_finalidade: payload.finalidade,
          p_motivo_compra_id: payload.motivoCompraId,
        });

        if (error) {
          setDefaultsToast({ kind: "error", message: "Erro ao salvar padrão do fornecedor." });
          clearToastLater();
          return;
        }

        setDefaultsToast({ kind: "saved", message: "Padrão do fornecedor salvo." });
        setFornecedorFinalidadePadrao(payload.finalidade);
        setFornecedorMotivoPadraoId(payload.motivoCompraId);
        clearToastLater();
      } catch {
        setDefaultsToast({ kind: "error", message: "Erro ao salvar padrão do fornecedor." });
        clearToastLater();
      }
    },
    [clearToastLater, supabase]
  );

  const scheduleSaveFornecedorDefaults = useCallback(
    (next: { fornecedorId: number; finalidade: ItemFinalidade | null; motivoCompraId: string | null }) => {
      pendingDefaultsRef.current = next;
      if (defaultsDebounceRef.current) clearTimeout(defaultsDebounceRef.current);
      defaultsDebounceRef.current = setTimeout(() => {
        const p = pendingDefaultsRef.current;
        pendingDefaultsRef.current = null;
        if (!p) return;
        void saveFornecedorImportDefaultsNow(p);
      }, 650);
    },
    [saveFornecedorImportDefaultsNow]
  );

  const flushFornecedorDefaults = useCallback(
    (fornecedorIdToFlush?: number | null) => {
      const fid = fornecedorIdToFlush ?? fornecedorIdRef.current;
      if (!fid) return;

      if (defaultsDebounceRef.current) {
        clearTimeout(defaultsDebounceRef.current);
        defaultsDebounceRef.current = null;
      }

      const pending = pendingDefaultsRef.current;
      pendingDefaultsRef.current = null;

      const payload = pending?.fornecedorId === fid
        ? pending
        : {
            fornecedorId: fid,
            finalidade: normalizeFinalidade(finalidadeRef.current),
            motivoCompraId: normalizeMotivoId(motivoCompraIdRef.current),
          };

      void saveFornecedorImportDefaultsNow(payload);
    },
    [saveFornecedorImportDefaultsNow]
  );

  // Vinculo opcional de OS (somente quando finalidade do lote = materia_prima)
  const [osNumero, setOsNumero] = useState("");
  const [osId, setOsId] = useState<number | null>(null);
  const [osLabel, setOsLabel] = useState<string | null>(null);
  const [osLoading, setOsLoading] = useState(false);
  const [osError, setOsError] = useState<string | null>(null);

  const [showOsLookup, setShowOsLookup] = useState(false);
  const [osLookupTerm, setOsLookupTerm] = useState("");
  const [osLookupRows, setOsLookupRows] = useState<OsLookupRow[]>([]);
  const [osLookupLoading, setOsLookupLoading] = useState(false);
  const [osLookupError, setOsLookupError] = useState<string | null>(null);
  const osLookupDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const osResolveReqIdRef = useRef(0);

  const [loteMissing, setLoteMissing] = useState<string[]>([]);

  const clearOsSelection = useCallback(() => {
    setOsNumero("");
    setOsId(null);
    setOsLabel(null);
    setOsLoading(false);
    setOsError(null);
    setShowOsLookup(false);
    setOsLookupTerm("");
    setOsLookupRows([]);
    setOsLookupError(null);
    setOsLookupLoading(false);
  }, []);

  const te = useTenantEmpresa();
  const tenantId = te.tenantId ?? "";
  const empresaId = te.empresaId ?? te.empresas[0]?.id ?? "";

  const permiteVincularItens =
    Boolean(finalidadeLote) &&
    (allowedVincularSet.has(String(finalidadeLote)) || finalidadesComItemObrigatorio.has(String(finalidadeLote)));
  const permiteAutoCadastrarItens =
    Boolean(finalidadeLote) &&
    (allowedAutoCadastrarSet.has(String(finalidadeLote)) || finalidadesComItemObrigatorio.has(String(finalidadeLote)));

  useEffect(() => {
    let active = true;

    const load = async () => {
      if (!tenantId || !empresaId) return;
      try {
        const params = await getImportacaoXmlParams(supabase, tenantId, empresaId);
        if (!active) return;
        setAllowedAutoCadastrarFinalidades(Array.from(params.allowedAutoCadastrar));
        setAllowedVincularFinalidades(Array.from(params.allowedVincular));
      } catch {
        // fallback já é o default do state
      }
    };

    void load();
    return () => {
      active = false;
    };
  }, [supabase, tenantId, empresaId]);

  const empresaRole = useMemo(() => {
    const role = te.empresa?.papel ?? te.empresas.find((e) => e.id === te.empresaId)?.papel ?? null;
    return typeof role === "string" ? role.trim().toUpperCase() : "";
  }, [te.empresa?.papel, te.empresaId, te.empresas]);
  const isFinanceiroEmpresaRole = empresaRole === "FINANCEIRO" || empresaRole === "FATURAMENTO";
  const { has, loading: permissionsLoading, ready } = usePermissions();

  const [recentNfs, setRecentNfs] = useState<NfEntradaResumoRow[]>([]);
  const [recentNfsLoading, setRecentNfsLoading] = useState(false);
  const [recentNfsError, setRecentNfsError] = useState<string | null>(null);
  const [openingNfEntradaId, setOpeningNfEntradaId] = useState<number | null>(null);
  const [recentReloadTick, setRecentReloadTick] = useState(0);

  const [recentFilterMonth, setRecentFilterMonth] = useState<string>(() => String(new Date().getMonth() + 1));
  const [recentFilterYear, setRecentFilterYear] = useState<string>(() => String(new Date().getFullYear()));
  const [recentUseDateFilter, setRecentUseDateFilter] = useState(false);
  const [recentFilterEmitente, setRecentFilterEmitente] = useState("");
  const [recentFilterNumero, setRecentFilterNumero] = useState("");

  const canImport = has("xml_import.execute");
  const canCreateFornecedor = has("cad_fornecedores.write");
  const canCreateItem = has("cad_itens.write");
  const canAccessPage = Boolean(canImport || canCreateFornecedor || canCreateItem || isFinanceiroEmpresaRole);

  const osEnabled = finalidadeLote === "materia_prima";

  useEffect(() => {
    let active = true;

    const run = async () => {
      if (!tenantId || !empresaId) {
        if (!active) return;
        setRecentNfs([]);
        setRecentNfsError(null);
        setRecentNfsLoading(false);
        return;
      }

      setRecentNfsLoading(true);
      setRecentNfsError(null);

      try {
        const y = Number(recentFilterYear);
        const m = Number(recentFilterMonth);
        const hasMonth = recentUseDateFilter && Number.isFinite(y) && Number.isFinite(m) && y > 2000 && m >= 1 && m <= 12;
        const start = hasMonth ? new Date(Date.UTC(y, m - 1, 1)).toISOString().slice(0, 10) : null;
        const end = hasMonth ? new Date(Date.UTC(y, m, 1)).toISOString().slice(0, 10) : null;
        const emitenteTerm = recentFilterEmitente.trim();
        const numeroTerm = recentFilterNumero.trim();

        const { data, error } = await supabase.schema("public").rpc("list_imported_nfe", {
            p_tenant_id: tenantId,
            p_empresa_id: empresaId,
            p_start_date: start,
            p_end_date: end,
            p_emitente: emitenteTerm || null,
            p_numero: numeroTerm || null,
            p_limit: RECENT_NFS_LIMIT,
          });
        if (error) throw error;
        if (!active) return;

        const rowsAll = ((data ?? []) as unknown as NfEntradaResumoRow[])
          .map((r) => ({
            id: Number(r.id),
            chave: String(r.chave ?? ""),
            numero: r.numero ?? null,
            serie: r.serie ?? null,
            emitente_nome: r.emitente_nome ?? null,
            data_emissao: r.data_emissao ?? null,
            valor_total: r.valor_total ?? null,
            criado_em: r.criado_em ?? null,
            finalidade_contexto: r.finalidade_contexto ?? null,
          }))
          .filter((r) => Number.isFinite(r.id) && r.id > 0 && r.chave);

        setRecentNfs(rowsAll);
      } catch (e: unknown) {
        if (!active) return;
        setRecentNfs([]);
        setRecentNfsError(getErrorMessage(e, "Erro ao carregar notas importadas."));
      } finally {
        if (active) setRecentNfsLoading(false);
      }
    };

    void run();
    return () => {
      active = false;
    };
  }, [
    empresaId,
    importOk,
    recentFilterEmitente,
    recentFilterMonth,
    recentFilterNumero,
    recentFilterYear,
    recentReloadTick,
    recentUseDateFilter,
    supabase,
    tenantId,
  ]);

  const abrirNotaImportada = useCallback(
    async (row: NfEntradaResumoRow) => {
      if (!tenantId || !empresaId) return;
      if (!row?.id) return;

      setOpeningNfEntradaId(row.id);
      setRecentNfsError(null);

      try {
        const { data: foundId, error: findErr } = await supabase.schema("f").rpc("fn_find_documento_fiscal_from_import", {
          p_tenant_id: tenantId,
          p_empresa_id: empresaId,
          p_nf_entrada_id: row.id,
          p_chave_acesso: row.chave ?? null,
        });

        let documentoFiscalId = foundId ? String(foundId) : null;

        // Fallback: garante DF a partir da NF de entrada (caso o importador não tenha criado).
        if (!documentoFiscalId) {
          const { data: ensuredId, error: ensureErr } = await supabase
            .schema("f")
            .rpc("fn_ensure_documento_fiscal_from_nf_entrada", { p_nf_entrada_id: row.id });

          if (ensureErr || !ensuredId) throw ensureErr ?? findErr ?? new Error("Não foi possível localizar o documento fiscal.");
          documentoFiscalId = String(ensuredId);
        }

        // Best-effort: garantir impostos gravados para exibição/apuração.
        try {
          await supabase
            .schema("f")
            .rpc("nfe_gravar_impostos_do_documento", { p_documento_fiscal_id: documentoFiscalId });
        } catch {
          // ignore
        }

        router.push(`/estoque/importar/${documentoFiscalId}`);
      } catch (e: unknown) {
        setRecentNfsError(getErrorMessage(e, "Erro ao abrir a nota importada."));
      } finally {
        setOpeningNfEntradaId(null);
      }
    },
    [empresaId, router, supabase, tenantId]
  );

  useEffect(() => {
    let active = true;

    const run = async () => {
      if (!tenantId || !empresaId) {
        setUsuariosSolicitantes([]);
        setUsuariosSolicitantesError(null);
        setUsuariosSolicitantesLoading(false);
        setSolicitanteUsuarioId("");
        return;
      }

      setUsuariosSolicitantesLoading(true);
      setUsuariosSolicitantesError(null);

      try {
        const { data: sess } = await supabase.auth.getSession();
        const token = sess.session?.access_token ?? null;
        if (!token) throw new Error("Sessao expirada. Faca login novamente.");

        const res = await fetch(`/api/estoque/usuarios-solicitantes?tenantId=${tenantId}&empresaId=${empresaId}`, {
          headers: { authorization: `Bearer ${token}` },
        });

        const json = (await res.json().catch(() => null)) as UsuariosSolicitantesApiResponse | null;
        if (!active) return;

        if (!res.ok) {
          const msg = typeof json?.error === "string" ? json.error : "Erro ao carregar usuarios.";
          setUsuariosSolicitantes([]);
          setUsuariosSolicitantesError(msg);
          setUsuariosSolicitantesLoading(false);
          return;
        }

        const data = Array.isArray(json?.usuarios) ? json!.usuarios! : [];
        const next = (data ?? [])
          .map((r) => ({ id: String(r.id ?? ""), nome: String(r.nome ?? ""), email: String(r.email ?? "") }))
          .filter((r) => r.id && r.nome && r.email);

        setUsuariosSolicitantes(next);
        setUsuariosSolicitantesLoading(false);
        setSolicitanteUsuarioId((prev) => (prev && !next.some((u) => u.id === prev) ? "" : prev));
      } catch (e: unknown) {
        if (!active) return;
        setUsuariosSolicitantes([]);
        setUsuariosSolicitantesError(getErrorMessage(e, "Erro ao carregar usuarios."));
        setUsuariosSolicitantesLoading(false);
      }
    };

    void run();
    return () => {
      active = false;
    };
  }, [empresaId, supabase, tenantId]);

  const resolveOsByNumero = useCallback(
    async (numero: string) => {
      const reqId = ++osResolveReqIdRef.current;
      const normalized = numero.trim();
      if (!normalized) {
        setOsId(null);
        setOsLabel(null);
        setOsError(null);
        setOsLoading(false);
        return;
      }

      setOsLoading(true);
      setOsError(null);

      if (!tenantId || !empresaId) {
        if (reqId !== osResolveReqIdRef.current) return;
        setOsId(null);
        setOsLabel(null);
        setOsError("Tenant ou empresa nao carregados.");
        setOsLoading(false);
        return;
      }

      const { data, error } = await applyTenantEmpresa(
        supabase.schema("public").from("ordens_servico").select("id,numero_os,cliente_nome,descricao_servico,status"),
        tenantId,
        empresaId
      )
        .eq("numero_os", normalized)
        .maybeSingle();

      if (reqId !== osResolveReqIdRef.current) return;

      if (error) {
        setOsId(null);
        setOsLabel(null);
        setOsError("Erro ao buscar OS.");
        setOsLoading(false);
        return;
      }

      if (!data) {
        setOsId(null);
        setOsLabel(null);
        setOsError("OS nao encontrada.");
        setOsLoading(false);
        return;
      }

      const row = data as OsLookupRow;
      setOsId(Number(row.id));
      const numeroDb = row.numero_os ?? String(row.id);
      const cliente = row.cliente_nome ?? "-";
      setOsLabel(`OS ${numeroDb} - ${cliente}`);
      setOsError(null);
      setOsLoading(false);
      aplicarMotivoAutomatico({ origem: "os", temOs: true });
    },
    [aplicarMotivoAutomatico, supabase, tenantId, empresaId]
  );

  const loadOsLookup = useCallback(
    async (term: string) => {
      setOsLookupLoading(true);
      setOsLookupError(null);

      const trimmed = term.trim();
      if (!trimmed) {
        setOsLookupRows([]);
        setOsLookupLoading(false);
        return;
      }

      if (!tenantId || !empresaId) {
        setOsLookupRows([]);
        setOsLookupError("Tenant ou empresa nao carregados.");
        setOsLookupLoading(false);
        return;
      }

      let query = applyTenantEmpresa(
        supabase.schema("public").from("ordens_servico").select("id,numero_os,cliente_nome,descricao_servico,status"),
        tenantId,
        empresaId
      )
        .order("id", { ascending: false })
        .limit(50);

      const likeTerm = `%${trimmed}%`;
      query = query.or(`numero_os.ilike.${likeTerm},cliente_nome.ilike.${likeTerm}`);

      const { data, error } = await query;
      if (error) {
        setOsLookupRows([]);
        setOsLookupError("Erro ao buscar OS.");
        setOsLookupLoading(false);
        return;
      }

      setOsLookupRows((data ?? []) as OsLookupRow[]);
      setOsLookupLoading(false);
    },
    [supabase, tenantId, empresaId]
  );

  const openOsLookup = useCallback(() => {
    setShowOsLookup(true);
    setOsLookupTerm("");
    setOsLookupRows([]);
    setOsLookupError(null);
  }, []);

  const closeOsLookup = useCallback(() => {
    setShowOsLookup(false);
    setOsLookupRows([]);
    setOsLookupError(null);
  }, []);

  const loadPedidoLookup = useCallback(
    async (term: string) => {
      setPedidoLookupLoading(true);
      setPedidoLookupError(null);

      if (!tenantId || !empresaId) {
        setPedidoLookupRows([]);
        setPedidoAnalyzerRows([]);
        setPedidoLookupError("Tenant ou empresa nao carregados.");
        setPedidoLookupLoading(false);
        return;
      }

      try {
        const { data: sess } = await supabase.auth.getSession();
        const token = sess.session?.access_token ?? null;
        if (!token) throw new Error("Sessao expirada. Faca login novamente.");
        const fornecedorFiltroId = fornecedorIdBase ?? fornecedorId ?? null;
        const allowedPedidoStatuses = new Set(["ENVIADO", "PARCIAL_RECEBIDO"]);

        const qs = new URLSearchParams({
          tenant_id: tenantId,
          empresa_id: empresaId,
          status: "ANDAMENTO",
        });
        if (fornecedorFiltroId) qs.set("fornecedorId", String(fornecedorFiltroId));

        const res = await fetch(`/api/compras/pedidos?${qs.toString()}`, {
          headers: { authorization: `Bearer ${token}` },
        });
        const json = (await res.json().catch(() => null)) as { data?: unknown[]; error?: string } | null;
        if (!res.ok) {
          const msg = typeof json?.error === "string" ? json.error : "Erro ao buscar pedidos.";
          throw new Error(msg);
        }

        const allRows = Array.isArray(json?.data) ? json!.data! : [];
        const normalized = String(term ?? "").trim().toLowerCase();

        const rows = allRows
          .map((row) => row as Record<string, unknown>)
          .map((row) => ({
            id: String(row.id ?? ""),
            codigo: row.codigo == null ? null : String(row.codigo),
            status: row.status == null ? null : String(row.status),
            fornecedor_id:
              typeof row.fornecedor_id === "number" || typeof row.fornecedor_id === "string" ? row.fornecedor_id : null,
            fornecedor_nome: row.fornecedor_nome == null ? null : String(row.fornecedor_nome),
            solicitante_usuario_id: row.solicitante_usuario_id == null ? null : String(row.solicitante_usuario_id),
            created_at: row.created_at == null ? null : String(row.created_at),
            total_geral:
              typeof row.total_geral === "number" || typeof row.total_geral === "string" ? row.total_geral : null,
          }))
          .filter((row) => Boolean(row.id))
          .filter((row) => allowedPedidoStatuses.has(String(row.status ?? "").toUpperCase()))
          .filter((row) => {
            if (!normalized) return true;
            const code = String(row.codigo ?? "").toLowerCase();
            const supplier = String(row.fornecedor_nome ?? "").toLowerCase();
            const id = String(row.id ?? "").toLowerCase();
            return code.includes(normalized) || supplier.includes(normalized) || id.includes(normalized);
          })
          .slice(0, 80);

        setPedidoLookupRows(rows);
        setPedidoAnalyzerRows(rows);
        setPedidoLookupLoading(false);
      } catch (e: unknown) {
        setPedidoLookupRows([]);
        setPedidoAnalyzerRows([]);
        setPedidoLookupError(getErrorMessage(e, "Erro ao buscar pedidos."));
        setPedidoLookupLoading(false);
      }
    },
    [empresaId, fornecedorId, fornecedorIdBase, supabase, tenantId]
  );

  const openPedidoLookup = useCallback(
    (term?: string) => {
      const nextTerm = String(term ?? pedidoCompraRef).trim();
      setShowPedidoLookup(true);
      setPedidoLookupTerm(nextTerm);
      setPedidoLookupRows([]);
      setPedidoLookupError(null);
      void loadPedidoLookup(nextTerm);
    },
    [loadPedidoLookup, pedidoCompraRef]
  );

  const closePedidoLookup = useCallback(() => {
    setShowPedidoLookup(false);
    setPedidoLookupRows([]);
    setPedidoLookupError(null);
  }, []);

  useEffect(() => {
    if (osEnabled) return;
    clearOsSelection();
  }, [clearOsSelection, osEnabled]);

  useEffect(() => {
    if (!osEnabled) return;
    const trimmed = osNumero.trim();
    if (!trimmed) {
      setOsId(null);
      setOsLabel(null);
      setOsLoading(false);
      setOsError(null);
      return;
    }

    if (osId !== null && osLabel) return;

    const t = setTimeout(() => {
      void resolveOsByNumero(trimmed);
    }, 400);

    return () => clearTimeout(t);
  }, [osNumero, osEnabled, osId, osLabel, resolveOsByNumero]);

  function normalizeItemCodigo(code: unknown): string {
    return normalizeXmlItemCode(code);
  }

  function parseXml(raw: string): { nfe: ParsedNfe; itens: ParsedItem[] } {
    const parsed = parseNfeXml(raw);
    return {
      nfe: parsed.nfe,
      itens: (parsed.itens ?? []).map((it) => ({
        ...it,
        codigo: normalizeItemCodigo((it as unknown as { codigo?: unknown })?.codigo),
      })),
    };
  }

  function applyFornecedorFinanceDefaults(flag: boolean) {
    setFornecedorGerarContasAuto(Boolean(flag));
  }

  async function checkFornecedor(
    params: { documento: string | null; nome: string | null },
    opts?: { allowCreate?: boolean }
  ) {
    const allowCreate = opts?.allowCreate ?? true;
    // Persist last supplier choices before switching.
    if (fornecedorIdRef.current) flushFornecedorDefaults(fornecedorIdRef.current);

    setFornecedorId(null);
    setFornecedorNome(null);
    setFornecedorFinalidadePadrao(null);
    setFornecedorMotivoPadraoId(null);
    applyFornecedorFinanceDefaults(false);

    const cnpjNormalizado = normalizeCnpj(params.documento);
    if (!cnpjNormalizado) return;

    if (!tenantId || !empresaId) {
      setImportErr("Tenant ou empresa nao carregados.");
      return;
    }

    const { data, error } = await applyTenantEmpresa(
      supabase
        .schema("public")
        .from("fornecedores")
        .select("id,nome,cnpj_norm,finalidade_padrao,motivo_compra_padrao_id,gerar_contas_pagar_auto"),
      tenantId,
      empresaId
    )
      .or(`cnpj_norm.eq.${cnpjNormalizado},documento_norm.eq.${cnpjNormalizado}`)
      .order("id", { ascending: true })
      .limit(1)
      .maybeSingle();

    if (error) {
      setImportErr(error.message);
      return;
    }

    const fornecedor = (data ?? null) as FornecedorRow | null;
    if (fornecedor?.id) {
      setFornecedorId(fornecedor.id);
      setFornecedorNome(fornecedor.nome ?? null);
      setFornecedorFinalidadePadrao(fornecedor.finalidade_padrao ?? null);
      setFornecedorMotivoPadraoId(normalizeMotivoId(fornecedor.motivo_compra_padrao_id));

      applyFornecedorFinanceDefaults(Boolean(fornecedor.gerar_contas_pagar_auto));

      // Auto-preenche defaults do fornecedor
      if (fornecedor.finalidade_padrao) {
        setFinalidadeLote(fornecedor.finalidade_padrao);
      }
      setMotivoCompraId(String(fornecedor.motivo_compra_padrao_id ?? ""));

      return;
    }

    if (!allowCreate) return;

    // Não encontrado: cria automaticamente (requisito)
    if (!canCreateFornecedor) {
      setImportErr("Fornecedor nao encontrado e voce nao tem permissao para cadastrar automaticamente.");
      return;
    }

    const createdId = await criarFornecedor(
      cnpjNormalizado,
      params.nome ?? "Fornecedor NF",
      finalidadeLote ? (finalidadeLote as ItemFinalidade) : null
    );

    if (createdId && finalidadeLote) {
      await atualizarFinalidadePadraoFornecedor(createdId, finalidadeLote as ItemFinalidade);
    }
  }

  async function criarFornecedor(cnpj: string, nome: string, finalidadePadrao?: ItemFinalidade | null) {
    setImportErr(null);

    if (!canCreateFornecedor) {
      setImportErr("Sem permissao para cadastrar fornecedor.");
      return null;
    }

    const documento = normalizeCnpj(cnpj);
    if (!documento) {
      setImportErr("CNPJ do fornecedor invalido.");
      return null;
    }

    if (!tenantId || !empresaId) {
      setImportErr("Tenant ou empresa nao carregados.");
      return null;
    }

    // Regra: fornecedor nasce com finalidade_padrao = finalidade do lote quando houver (senão, null)
    const finalidadeParaSalvar = (finalidadePadrao ?? null) ?? null;

    const nomeUpper = String(nome ?? "")
      .replace(/\s+/g, " ")
      .trim()
      .toUpperCase();

    const payload: Record<string, unknown> = {
      tenant_id: tenantId,
      empresa_id: empresaId,
      nome: nomeUpper || "FORNECEDOR NF",
      cnpj: documento,
      documento,
      ativo: true,
      finalidade_padrao: finalidadeParaSalvar,
      motivo_compra_padrao_id: normalizeMotivoId(motivoCompraIdRef.current),
    };

    const { data, error } = await supabase
      .schema("public")
      .from("fornecedores")
      .insert(payload)
      .select("id,nome,cnpj_norm,finalidade_padrao,motivo_compra_padrao_id,gerar_contas_pagar_auto")
      .single();

    if (error) {
      const err = (error && typeof error === "object" ? (error as DbError) : null);

      // se já existe, tenta update (mantém robusto)
      if (err?.code === "23505") {
        const { data: existing, error: existingErr } = await applyTenantEmpresa(
          supabase.schema("public").from("fornecedores").select("id"),
          tenantId,
          empresaId
        )
          .or(`cnpj_norm.eq.${documento},documento_norm.eq.${documento}`)
          .order("id", { ascending: true })
          .limit(1)
          .maybeSingle();

        if (existingErr) {
          setImportErr(existingErr.message);
          return null;
        }

        const existingId = existing?.id ?? null;
        if (!existingId) {
          setImportErr("Fornecedor ja cadastrado para este documento.");
          return null;
        }

        const { data: updated, error: updateErr } = await applyTenantEmpresa(
          supabase
            .schema("public")
            .from("fornecedores")
            .update(payload)
            .select("id,nome,cnpj_norm,finalidade_padrao,motivo_compra_padrao_id,gerar_contas_pagar_auto"),
          tenantId,
          empresaId
        )
          .eq("id", existingId)
          .maybeSingle();

        if (updateErr) {
          setImportErr(updateErr.message);
          return null;
        }

        const updatedRow = (updated ?? null) as FornecedorRow | null;
        if (!updatedRow?.id) {
          setImportErr("Fornecedor ja cadastrado para este documento.");
          return null;
        }

        setFornecedorId(updatedRow.id);
        setFornecedorNome(updatedRow.nome ?? null);
        setFornecedorFinalidadePadrao(updatedRow.finalidade_padrao ?? null);
        setFornecedorMotivoPadraoId(normalizeMotivoId(updatedRow.motivo_compra_padrao_id));
        applyFornecedorFinanceDefaults(Boolean(updatedRow.gerar_contas_pagar_auto));

        if (updatedRow.finalidade_padrao) setFinalidadeLote(updatedRow.finalidade_padrao);
        setMotivoCompraId(String(updatedRow.motivo_compra_padrao_id ?? ""));
        return updatedRow.id;
      }

      setImportErr(error.message);
      return null;
    }

    const created = (data ?? null) as FornecedorRow | null;
    if (!created?.id) return null;

    setFornecedorId(created.id);
    setFornecedorNome(created.nome ?? null);
    setFornecedorFinalidadePadrao(created.finalidade_padrao ?? null);
    setFornecedorMotivoPadraoId(normalizeMotivoId(created.motivo_compra_padrao_id));

    applyFornecedorFinanceDefaults(Boolean(created.gerar_contas_pagar_auto));

    // garante que o padrão fica setado
    if (created.finalidade_padrao) setFinalidadeLote(created.finalidade_padrao);
    setMotivoCompraId(String(created.motivo_compra_padrao_id ?? ""));

    // Persist defaults for the newly created supplier.
    scheduleSaveFornecedorDefaults({
      fornecedorId: created.id,
      finalidade: normalizeFinalidade(created.finalidade_padrao ?? finalidadeRef.current),
      motivoCompraId: normalizeMotivoId(created.motivo_compra_padrao_id ?? motivoCompraIdRef.current),
    });

    return created.id;
  }

  async function atualizarFinalidadePadraoFornecedor(fornecedorIdToUpdate: number, finalidade: ItemFinalidade) {
    if (!tenantId || !empresaId) return;
    const { error } = await applyTenantEmpresa(
      supabase.schema("public").from("fornecedores").update({ finalidade_padrao: finalidade }),
      tenantId,
      empresaId
    ).eq("id", fornecedorIdToUpdate);

    if (error) setImportErr(error.message);
  }

  // If the currently selected motivo becomes invalid for XML_PRODUTO (e.g. it was SERVICO), clear and warn.
  useEffect(() => {
    if (motivosLoading) return;
    if (!motivoCompraId) return;
    const ok = motivos.some((m) => m.id === motivoCompraId);
    if (ok) return;
    setMotivoCompraId("");
    setDefaultsToast({
      kind: "warn",
      message: "Motivo padrao do fornecedor nao se aplica a XML de produtos (SERVICO). Selecione outro.",
    });
    clearToastLater(3500);
  }, [clearToastLater, motivoCompraId, motivos, motivosLoading]);

  const carregarItensPorCodigo = useCallback(
    async (codigos: string[], tenantIdLocal: string, empresaIdLocal: string, fornecedorIdLocal?: number | null) => {
      if (codigos.length === 0) return new Map<string, ItemCodigoRow>();

      // Consulta e mapeia usando o código normalizado (sem zeros à esquerda),
      // mas mantém compat com bancos que ainda possam ter código com zeros.
      const expanded = Array.from(
        new Set(
          codigos
            .map((c) => String(c ?? "").trim())
            .filter(Boolean)
            .flatMap((c) => {
              const n = normalizeItemCodigo(c);
              return n && n !== c ? [c, n] : [c];
            })
        )
      );

      const { data, error } = await applyTenantEmpresa(
        supabase.schema("public").from("itens").select("id,codigo_interno,nome,fornecedor_id,ativo"),
        tenantIdLocal,
        empresaIdLocal
      ).in("codigo_interno", expanded);

      if (error) {
        setImportErr(error.message);
        return new Map();
      }

      const fornecedorFiltroId = fornecedorIdLocal && Number.isFinite(Number(fornecedorIdLocal))
        ? Number(fornecedorIdLocal)
        : null;
      const map = new Map<string, ItemCodigoRow>();
      const rows = ((data ?? []) as ItemCodigoRow[])
        .filter((r) => {
          if (!fornecedorFiltroId) return true;
          if (r.fornecedor_id == null) return true;
          return Number(r.fornecedor_id) === fornecedorFiltroId;
        })
        .sort((a, b) => {
          const rank = (r: ItemCodigoRow) => (fornecedorFiltroId && Number(r.fornecedor_id) === fornecedorFiltroId ? 2 : r.fornecedor_id == null ? 1 : 0);
          return rank(b) - rank(a);
        });

      rows.forEach((r) => addItemCodigoToMap(map, r));
      return map;
    },
    [supabase]
  );

  async function carregarFiscalPorItens(itemIds: number[], tenantIdLocal: string, empresaIdLocal: string) {
    if (itemIds.length === 0) return new Map<number, FiscalPerfil>();

    const { data, error } = await applyTenantEmpresa(
      supabase
        .schema("public")
        .from("fiscal_itens")
        .select(
          "item_id,ncm,cst_icms,cst_pis,cst_cofins,aliq_icms,aliq_ipi,aliq_pis,aliq_cofins,credita_icms,credita_pis,credita_cofins,ipi_entra_no_custo"
        ),
      tenantIdLocal,
      empresaIdLocal
    ).in("item_id", itemIds);

    if (error) {
      setImportErr(error.message);
      return new Map();
    }

    const map = new Map<number, FiscalPerfil>();
    const rows = (data ?? []) as FiscalPerfil[];
    rows.forEach((r) => map.set(r.item_id, r));
    return map;
  }

  async function upsertFiscalItem(
    itemId: number,
    fiscal: Partial<FiscalPerfil>,
    tenantIdLocal: string,
    empresaIdLocal: string
  ) {
    const normCst = (v?: string | null) => {
      const t = (v ?? "").trim();
      return t.length > 0 ? t : null;
    };

    const cstIcms = normCst(fiscal.cst_icms ?? null);
    const cstPis = normCst(fiscal.cst_pis ?? null);
    const cstCofins = normCst(fiscal.cst_cofins ?? null);

    const creditaIcms =
      typeof fiscal.credita_icms === "boolean" ? fiscal.credita_icms : Boolean(cstIcms);
    const creditaPis =
      typeof fiscal.credita_pis === "boolean" ? fiscal.credita_pis : Boolean(cstPis);
    const creditaCofins =
      typeof fiscal.credita_cofins === "boolean" ? fiscal.credita_cofins : Boolean(cstCofins);

    const payload: FiscalPayload = {
      tenant_id: tenantIdLocal,
      empresa_id: empresaIdLocal,
      item_id: itemId,
      ncm: fiscal.ncm ?? null,
      cst_icms: cstIcms,
      cst_pis: cstPis,
      cst_cofins: cstCofins,
      aliq_icms: fiscal.aliq_icms ?? null,
      aliq_ipi: fiscal.aliq_ipi ?? null,
      aliq_pis: fiscal.aliq_pis ?? null,
      aliq_cofins: fiscal.aliq_cofins ?? null,
      credita_icms: creditaIcms,
      credita_pis: creditaPis,
      credita_cofins: creditaCofins,
      ipi_entra_no_custo: fiscal.ipi_entra_no_custo ?? true,
    };

    const { error } = await supabase
      .schema("public")
      .from("fiscal_itens")
      .upsert(payload, { onConflict: "tenant_id,empresa_id,item_id" });

    // Com as policies do SQL, isso deve parar de acontecer
    if (error) {
      setImportErr(error.message);
    }
  }

  async function criarItemRapido(
    it: ParsedItem,
    fornecedorIdLocal: number | null | undefined,
    dataEmissao: string | null | undefined,
    finalidade: ItemFinalidade,
    normalizacao?: NormalizacaoCadastroSuggestion | null
  ) {
    setImportErr(null);

    if (!finalidadeLote) {
      setImportErr("Selecione a finalidade antes de cadastrar itens.");
      return null;
    }

    const nomeFinal = normalizacao?.descricao_padronizada?.trim() || it.overrideNome?.trim() || it.nome || `Item ${it.codigo}`;
    const nomeUpper = String(nomeFinal).trim().toUpperCase();
    const dataCompra = dataEmissao || new Date().toISOString();
    const margem = 52;

    const valorUnitRaw = Number(it.valorUnit ?? 0);
    const valorUnit = Number.isFinite(valorUnitRaw) ? valorUnitRaw : 0;

    const aliq = (v?: number | null) => (Number.isFinite(v as number) ? Number(v) : null);

    if (!tenantId || !empresaId) {
      setImportErr("Tenant ou empresa nao carregados.");
      return null;
    }

    const { data, error } = await supabase
      .schema("public")
      .from("itens")
      .insert({
        tenant_id: tenantId,
        empresa_id: empresaId,
        codigo_interno: normalizeItemCodigo(it.codigo),
        nome: nomeUpper,
        tipo: "produto",
        controla_estoque: true,
        unidade_medida: "UN",
        custo_ultima_compra: valorUnit,
        custo_medio: valorUnit,
        preco_unitario: valorUnit,
        fornecedor_id: fornecedorIdLocal ?? null,
        grupo_id: normalizacao?.grupo_id ?? null,
        data_atualizacao_preco: dataCompra,
        data_ultima_compra: dataCompra,
        margem_lucro_percentual: margem,
        finalidade,
        ncm: it.ncm ?? null,
        aliquota_icms: aliq(it.aliquotaIcms),
        aliquota_ipi: aliq(it.aliquotaIpi),
        aliquota_pis: aliq(it.aliquotaPis),
        aliquota_cofins: aliq(it.aliquotaCofins),
      })
      .select("id")
      .single();

    if (error) {
      setImportErr(error.message);
      return null;
    }

    const createdId = data.id as number;

    // tenta gravar fiscal (se policy não existir, pode falhar — mas item já foi criado)
    await upsertFiscalItem(
      createdId,
      {
        ncm: it.ncm ?? null,
        aliq_icms: aliq(it.aliquotaIcms),
        aliq_ipi: aliq(it.aliquotaIpi),
        aliq_pis: aliq(it.aliquotaPis),
        aliq_cofins: aliq(it.aliquotaCofins),
      },
      tenantId,
      empresaId
    );

    return createdId;
  }

  function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    setImportErr(null);
    setImportOk(null);

    const files = Array.from(e.target.files ?? []);
    const file = files[0] ?? null;

    setSelectedFile(file);
    setSelectedFiles(files);
    setIsReading(false);

    if (files.length > 0) {
      setTimeout(() => {
        void parseXmlAndCheck(files);
      }, 0);
    }
  }

  function newJobId() {
    return `job-${Math.random().toString(36).slice(2)}`;
  }

  async function addJobFromRaw(xml: string, fileName: string) {
    const parsed = parseXml(xml);
    const cnpjRaw = parsed.nfe.cnpjEmitente ?? null;
    const cnpj = normalizeCnpj(cnpjRaw);

    let status: ImportJob["status"] = "ok";
    let error: string | undefined;
    let selected = true;

    if (!tenantId || !empresaId) {
      status = "erro";
      error = "Tenant ou empresa nao carregados.";
    }

    const chave = parsed.nfe.chave ?? null;

    if (chave && status === "ok" && tenantId && empresaId) {
      const { count: nfExiste } = await applyTenantEmpresa(
        supabase.schema("public").from("nf_entrada").select("id", { count: "exact" }),
        tenantId,
        empresaId
      )
        .eq("chave", chave)
        .limit(1);

      if (typeof nfExiste === "number" && nfExiste > 0) {
        status = "importado";
        selected = false;
        error = "NF ja importada";
      }
    }

    // regra do lote: todos devem ser do mesmo fornecedor
    const baseRef = fornecedorCnpjBaseRef.current;
    let setAsBase = false;
    if (!baseRef && cnpj && status !== "erro") {
      fornecedorCnpjBaseRef.current = cnpj;
      setFornecedorCnpjBase(cnpj); // state apenas para UI
      setAsBase = true;
    } else if (baseRef && cnpj && baseRef !== cnpj) {
      status = "erro";
      error = "Fornecedor diferente do lote";
      selected = false;
    }

    const job: ImportJob = {
      id: newJobId(),
      fileName,
      xmlText: xml,
      nfeInfo: parsed.nfe,
      itens: parsed.itens,
      fornecedorCnpj: cnpj,
      status,
      error,
      selected,
    };

    const chaveKey = chave ? String(chave) : null;
    const alreadyExists = Boolean(chaveKey && chavesAddedRef.current.has(chaveKey));
    if (chaveKey && !alreadyExists) chavesAddedRef.current.add(chaveKey);

    const didAdd = !alreadyExists;

    setJobs((prev) => {
      if (alreadyExists) return prev;
      if (chaveKey && prev.some((j) => j.nfeInfo?.chave === chaveKey)) return prev;
      return [...prev, job];
    });

    if (selected && didAdd) setSelectedJobId(job.id);

    if (didAdd && setAsBase && status !== "erro") {
      await checkFornecedor(
        { documento: parsed.nfe.cnpjEmitente, nome: parsed.nfe.emitente },
        { allowCreate: status === "ok" && selected }
      );
    }
  }

  async function addJobFromFile(file: File) {
    const text = await new Promise<string>((resolve, reject) => {
      const reader = new FileReader();
      reader.onerror = () => reject(new Error("Falha ao ler o arquivo."));
      reader.onload = () => resolve(String(reader.result || ""));
      reader.readAsText(file);
    });

    await addJobFromRaw(text, file.name);
  }

  async function parseXmlAndCheck(filesOverride?: File[] | null) {
    if (isReading || importBusy) return;

    setImportErr(null);
    setImportOk(null);

    setIsReading(true);
    const reqId = ++readReqIdRef.current;

    try {
      const fileList = filesOverride ?? selectedFiles;

      if ((!fileList || fileList.length === 0) && !xmlText.trim()) {
        throw new Error("Selecione um XML para ler.");
      }

      // reset do contexto do lote
      setFornecedorId(null);
      setFornecedorNome(null);
      setFornecedorFinalidadePadrao(null);
      setFornecedorMotivoPadraoId(null);
      setFornecedorIdBase(null);
      setFornecedorCnpjBase(null);

      fornecedorCnpjBaseRef.current = null;
      chavesAddedRef.current = new Set();

      setFinalidadeLote("");
      setMotivoCompraId("");
      setSolicitanteUsuarioId("");
      setPedidoCompraRef("");
      setPedidoLookupRows([]);
      setPedidoAnalyzerRows([]);
      setPedidoLookupError(null);
      setPedidosAnalyzerComItens([]);
      setPedidosAnalyzerError(null);
      setPedidosAnalyzerLoading(false);
      clearOsSelection();

      setItemMap(new Map());
      setJobs([]);
      setSelectedJobId(null);

      if (fileList && fileList.length > 0) {
        for (const file of fileList) {
          await addJobFromFile(file);
        }
      }

      if (xmlText.trim()) await addJobFromRaw(xmlText, "xml-painel");

      if (reqId === readReqIdRef.current) setImportOk("XML lido e validado.");
    } catch (e: unknown) {
      if (reqId === readReqIdRef.current) setImportErr(getErrorMessage(e, "Erro ao ler XML."));
    } finally {
      if (reqId === readReqIdRef.current) setIsReading(false);
    }
  }

  function selectJob(id: string) {
    setSelectedJobId(id);
  }

  function toggleJobSelected(id: string) {
    setJobs((prev) => prev.map((j) => (j.id === id ? { ...j, selected: !j.selected } : j)));
  }

  function removeJob(id: string) {
    setJobs((prev) => {
      const next = prev.filter((j) => j.id !== id);
      if (selectedJobId === id) {
        setSelectedJobId(next[0]?.id ?? null);
      }
      return next;
    });
  }

  function clearQueue() {
    setXmlText("");
    setSelectedFile(null);
    setSelectedFiles([]);
    if (fileInputRef.current) fileInputRef.current.value = "";
    setJobs([]);
    setSelectedJobId(null);
    setFornecedorCnpjBase(null);
    setFornecedorIdBase(null);
    setFornecedorId(null);
    setFornecedorNome(null);
    setFornecedorFinalidadePadrao(null);
    setFornecedorMotivoPadraoId(null);
    setFinalidadeLote("");
    setMotivoCompraId("");
    setSolicitanteUsuarioId("");
    setPedidoCompraRef("");
    setPedidoLookupRows([]);
    setPedidoLookupError(null);
    clearOsSelection();
    setItemMap(new Map());
    setNormalizacoesCadastro({});
    setNormalizacaoCadastroBusy(false);
    setPedidoAnalyzerRows([]);
    setPedidosAnalyzerComItens([]);
    setPedidosAnalyzerError(null);
    setPedidosAnalyzerLoading(false);
    setAssistantCopyMessage(null);
    setPedidoItemLink(null);
    setPedidoItemLinkSelectedId("");
    setPedidoItemLinkError(null);
    setPedidoItemLinkBusy(false);
    setImportErr(null);
    setImportOk(null);
    setImportWarn(null);

    fornecedorCnpjBaseRef.current = null;
    chavesAddedRef.current = new Set();
  }

  async function solicitarNormalizacoesCadastro(itens: ParsedItem[]) {
    if (!tenantId || !empresaId) throw new Error("Tenant ou empresa nao carregados.");

    const porCodigo = new Map<string, ParsedItem>();
    for (const item of itens) {
      const codigo = normalizeItemCodigo(item.codigo);
      if (codigo && !porCodigo.has(codigo)) porCodigo.set(codigo, item);
    }
    const itensUnicos = [...porCodigo.values()];
    if (itensUnicos.length === 0) return {} as Record<string, NormalizacaoCadastroSuggestion>;

    setNormalizacaoCadastroBusy(true);
    try {
      const { data: sess } = await supabase.auth.getSession();
      const token = sess.session?.access_token ?? null;
      if (!token) throw new Error("Sessao expirada. Faca login novamente.");

      const res = await fetch("/api/estoque/importar/normalizar-itens", {
        method: "POST",
        headers: { authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          tenant_id: tenantId,
          empresa_id: empresaId,
          itens: itensUnicos.map((item) => ({
            codigo: normalizeItemCodigo(item.codigo),
            descricao_nf: item.overrideNome?.trim() || item.nome,
            ncm: item.ncm ?? null,
            unidade: item.unidade ?? item.unidadeTrib ?? null,
            informacoes_adicionais: item.informacoesAdicionais ?? null,
          })),
        }),
      });

      const json = (await res.json().catch(() => null)) as NormalizacaoCadastroResponse | null;
      if (!res.ok) throw new Error(String(json?.error ?? "Erro ao solicitar sugestoes de cadastro com IA."));

      const sugestoes = Array.isArray(json?.sugestoes) ? json.sugestoes : [];
      const result = sugestoes.reduce<Record<string, NormalizacaoCadastroSuggestion>>((acc, sugestao) => {
        const codigo = normalizeItemCodigo(sugestao.codigo);
        if (codigo) acc[codigo] = { ...sugestao, codigo };
        return acc;
      }, {});

      setNormalizacoesCadastro((prev) => ({ ...prev, ...result }));
      return result;
    } finally {
      setNormalizacaoCadastroBusy(false);
    }
  }

  async function garantirGrupoDaSugestao(sugestao: NormalizacaoCadastroSuggestion) {
    if (sugestao.grupo_id) return sugestao;
    const novoGrupo = sugestao.novo_grupo;
    if (!novoGrupo) return sugestao;
    if (!tenantId || !empresaId) throw new Error("Tenant ou empresa nao carregados.");

    const encontrarGrupoPorCodigo = async () => {
      const { data, error } = await applyTenantEmpresa(
        supabase.schema("public").from("item_grupos").select("id,nome"),
        tenantId,
        empresaId
      )
        .eq("codigo", novoGrupo.codigo)
        .maybeSingle();
      if (error) throw error;
      return data as { id: number; nome: string | null } | null;
    };

    let grupo = await encontrarGrupoPorCodigo();
    if (!grupo) {
      const { data, error } = await supabase
        .schema("public")
        .from("item_grupos")
        .insert({
          tenant_id: tenantId,
          empresa_id: empresaId,
          codigo: novoGrupo.codigo,
          nome: novoGrupo.nome.toUpperCase(),
          grupo_pai_id: novoGrupo.grupo_pai_id,
          ativo: true,
          descricao: `Criado após aprovação de sugestão da IA: ${novoGrupo.justificativa}`,
        })
        .select("id,nome")
        .maybeSingle();

      if (error) {
        const dbError = error as DbError;
        if (dbError.code !== "23505") throw error;
        grupo = await encontrarGrupoPorCodigo();
      } else {
        grupo = data as { id: number; nome: string | null } | null;
      }
    }

    if (!grupo?.id) throw new Error("Nao foi possivel criar ou localizar o grupo sugerido.");

    const atualizada: NormalizacaoCadastroSuggestion = {
      ...sugestao,
      grupo_id: Number(grupo.id),
      grupo_nome: grupo.nome ?? novoGrupo.nome,
      grupo_caminho: novoGrupo.nome,
      novo_grupo: null,
    };
    setNormalizacoesCadastro((prev) => ({ ...prev, [atualizada.codigo]: atualizada }));
    return atualizada;
  }

  function validarSugestaoCadastro(sugestao: NormalizacaoCadastroSuggestion | undefined) {
    if (!sugestao?.descricao_padronizada?.trim()) {
      throw new Error("A IA nao retornou uma descricao segura. Revise o item antes de cadastrar.");
    }
    if (!sugestao.grupo_id && !sugestao.novo_grupo) {
      throw new Error("A IA nao conseguiu classificar o item com seguranca. Revise os dados pendentes antes de cadastrar.");
    }
  }

  async function cadastrarItemComIA(it: ParsedItem) {
    setImportErr(null);
    setImportOk(null);

    if (!canCreateItem) {
      setImportErr("Sem permissao para cadastrar itens.");
      return;
    }
    if (!finalidadeLote) {
      setImportErr("Selecione a finalidade antes de cadastrar itens.");
      return;
    }
    if (!permiteAutoCadastrarItens) {
      setImportErr(`Finalidade '${finalidadeLote}' nao permite cadastro automatico de itens.`);
      return;
    }

    const codigo = normalizeItemCodigo(it.codigo);
    let sugestao = normalizacoesCadastro[codigo];
    if (!sugestao) {
      try {
        const sugestoes = await solicitarNormalizacoesCadastro([it]);
        sugestao = sugestoes[codigo];
        setImportOk("Sugestao da IA gerada. Confira descricao e grupo antes de confirmar o cadastro.");
      } catch (error: unknown) {
        setImportErr(getErrorMessage(error, "Erro ao gerar sugestao de cadastro com IA."));
      }
      return;
    }

    try {
      validarSugestaoCadastro(sugestao);
      sugestao = await garantirGrupoDaSugestao(sugestao);
      validarSugestaoCadastro(sugestao);
      setCadBusy(true);
      const created = await criarItemRapido(
        it,
        fornecedorIdBase ?? fornecedorId ?? null,
        selectedJob?.nfeInfo?.dataEmissao ?? null,
        finalidadeLote as ItemFinalidade,
        sugestao
      );
      if (!created) return;

      setItemMap((prev) => {
        const next = new Map(prev);
        addItemCodigoToMap(next, {
          id: created,
          codigo_interno: codigo,
          nome: sugestao.descricao_padronizada,
          fornecedor_id: fornecedorIdBase ?? fornecedorId ?? null,
          ativo: true,
        });
        return next;
      });
      setLoteMissing((prev) => (prev.length === 0 ? prev : prev.filter((itemCodigo) => itemCodigo !== it.codigo)));
      setImportOk("Item cadastrado com a sugestao aprovada da IA.");
    } catch (error: unknown) {
      setImportErr(getErrorMessage(error, "Erro ao cadastrar item com IA."));
    } finally {
      setCadBusy(false);
    }
  }

  async function cadastrarFornecedorEItens() {
    setImportErr(null);
    setImportOk(null);
    setCadBusy(true);

    try {
      if (!finalidadeLote) throw new Error("Selecione a finalidade antes de cadastrar/importar.");

      // Se a finalidade do lote não permite auto-cadastro, não cria itens.
      // (Itens serão importados com item_id=null.)
      if (!permiteAutoCadastrarItens) {
        setLoteMissing([]);
        setImportOk(`Finalidade '${finalidadeLote}' nao permite cadastro automatico de itens. Nenhum item foi cadastrado.`);
        return;
      }

      const jobsToUse = jobs.filter((j) => j.selected && j.status === "ok" && j.itens.length > 0);
      if (jobsToUse.length === 0) throw new Error("Nenhum XML selecionado.");

      if (!tenantId || !empresaId) throw new Error("Tenant ou empresa nao carregados.");

      // resolve fornecedor do lote via CNPJ base
      const baseCnpj =
        fornecedorCnpjBaseRef.current ??
        fornecedorCnpjBase ??
        normalizeCnpj(jobsToUse.find((j) => j.nfeInfo?.cnpjEmitente)?.nfeInfo?.cnpjEmitente ?? null);

      let fornecedorFinal = fornecedorIdBase ?? fornecedorId ?? null;

        if (!fornecedorFinal && baseCnpj) {
          const { data: found, error: findErr } = await applyTenantEmpresa(
            supabase.schema("public").from("fornecedores").select("id"),
            tenantId,
            empresaId
          )
            .or(`cnpj_norm.eq.${baseCnpj},documento_norm.eq.${baseCnpj}`)
            .order("id", { ascending: true })
            .limit(1)
            .maybeSingle();

        if (findErr) throw findErr;
        fornecedorFinal = found?.id ?? null;
      }

      if (!fornecedorFinal) {
        throw new Error("Fornecedor nao cadastrado. Cadastre o fornecedor antes de cadastrar itens.");
      }

      // Recarrega config do fornecedor (fonte da verdade)
      let gerarContasAuto = false;
      {
        const { data: fornecedorCfg, error: fornecedorCfgErr } = await applyTenantEmpresa(
          supabase.schema("public").from("fornecedores").select("nome,gerar_contas_pagar_auto"),
          tenantId,
          empresaId
        )
          .eq("id", fornecedorFinal)
          .maybeSingle();

        if (fornecedorCfgErr) throw fornecedorCfgErr;

        gerarContasAuto = Boolean(fornecedorCfg?.gerar_contas_pagar_auto);
        setFornecedorGerarContasAuto(gerarContasAuto);
        if (fornecedorCfg?.nome) setFornecedorNome(String(fornecedorCfg.nome));
      }

      // Sempre persiste finalidade padrão do fornecedor (comportamento obrigatório)
      // Persist supplier defaults (finalidade + motivo) before proceeding.
      flushFornecedorDefaults(fornecedorFinal);

      // agora itens
      const todosItens = jobsToUse.flatMap((j) => j.itens);
      const codigos = Array.from(new Set(todosItens.map((i) => i.codigo)));

      const map = await carregarItensPorCodigo(codigos, tenantId, empresaId, fornecedorFinal);

      // regra: só cria item se tiver permissão
      const missing = codigos.filter((c) => !hasItemCodigoInMap(map, c));
      if (missing.length > 0 && !canCreateItem) {
        throw new Error(`Sem permissao para cadastrar itens. Faltantes: ${missing.join(", ")}`);
      }

      const itensFaltantesPorCodigo = new Map<string, ParsedItem>();
      for (const item of todosItens) {
        const codigo = normalizeItemCodigo(item.codigo);
        if (missing.includes(item.codigo) && !itensFaltantesPorCodigo.has(codigo)) itensFaltantesPorCodigo.set(codigo, item);
      }

      const faltantesSemSugestao = [...itensFaltantesPorCodigo.values()].filter(
        (item) => !normalizacoesCadastro[normalizeItemCodigo(item.codigo)]
      );
      if (faltantesSemSugestao.length > 0) {
        await solicitarNormalizacoesCadastro(faltantesSemSugestao);
        setImportOk("Sugestoes da IA geradas. Confira descricao e grupo de cada item antes de confirmar o cadastro.");
        return;
      }

      const sugestoesConfirmadas = new Map<string, NormalizacaoCadastroSuggestion>();
      for (const item of itensFaltantesPorCodigo.values()) {
        const codigo = normalizeItemCodigo(item.codigo);
        const sugestao = normalizacoesCadastro[codigo];
        validarSugestaoCadastro(sugestao);
        const sugestaoComGrupo = await garantirGrupoDaSugestao(sugestao!);
        validarSugestaoCadastro(sugestaoComGrupo);
        sugestoesConfirmadas.set(codigo, sugestaoComGrupo);
      }

      for (const job of jobsToUse) {
        const dataCompra = job.nfeInfo?.dataEmissao ?? new Date().toISOString();
        for (const it of job.itens) {
          if (!hasItemCodigoInMap(map, it.codigo)) {
            const sugestao = sugestoesConfirmadas.get(normalizeItemCodigo(it.codigo));
            const created = await criarItemRapido(
              it,
              fornecedorFinal ?? null,
              dataCompra,
              finalidadeLote as ItemFinalidade,
              sugestao
            );
            if (created) {
              addItemCodigoToMap(map, {
                id: created,
                codigo_interno: normalizeItemCodigo(it.codigo),
                nome: sugestao?.descricao_padronizada ?? it.overrideNome ?? it.nome ?? null,
                fornecedor_id: fornecedorFinal ?? null,
                ativo: true,
              });
            }
          }
        }
      }

      setItemMap(map);

      // Atualiza imediatamente os faltantes do lote para liberar a importacao sem precisar recarregar a tela.
      // (o efeito que recalcula loteMissing depende de selectedOkJobs, que pode não mudar após o cadastro)
      const nextMissing = codigos.filter((c) => !hasItemCodigoInMap(map, c));
      setLoteMissing(nextMissing);

      setFornecedorIdBase(fornecedorFinal ?? null);
      setImportOk("Itens cadastrados para os XMLs selecionados.");
    } catch (e: unknown) {
      setImportErr(getErrorMessage(e, "Erro ao cadastrar."));
    } finally {
      setCadBusy(false);
    }
  }

  async function importarNfe(paymentConfig: PagamentoImportacaoConfig | null = null) {
    if (isReading || importBusy) return;

    setImportErr(null);
    setImportOk(null);
    setImportWarn(null);
    setImportBusy(true);

    const round6 = (n: number) => (Number.isFinite(n) ? Number(n.toFixed(6)) : 0);

    try {
      if (!canImport) throw new Error("Sem permissao para importar NF.");
      if (!solicitanteUsuarioId && !pedidoCompraInformado) {
        throw new Error("Selecione o solicitante (usuario) antes de importar.");
      }
      if (!finalidadeLote && !pedidoCompraInformado) {
        throw new Error("Selecione a finalidade antes de importar.");
      }

      if (!motivosLoading && motivos.length === 0) {
        throw new Error("Nao existe nenhum motivo/classificacao ativo. Contate o admin.");
      }

      const motivo = motivos.find((m) => m.id === motivoCompraId) ?? null;
      const motivoCodigo = String(motivo?.codigo ?? "")
        .trim()
        .toUpperCase();
      if (!pedidoCompraInformado && (!motivoCompraId || !motivo || !motivoCodigo || motivoCodigo === "NAO_CLASSIFICADO")) {
        throw new Error("Selecione uma classificacao/motivo valido (nao pode ser NAO_CLASSIFICADO).");
      }

      // OS opcional, mas se o usuario preencheu, precisa ser valida.
      if (finalidadeLote === "materia_prima") {
        if (osLoading) throw new Error("Aguarde a validacao da OS.");
        if (osNumero.trim() !== "" && osId === null) throw new Error("OS invalida. Limpe o campo ou selecione uma OS valida.");
      }

      const jobsToImport = jobs.filter((j) => j.selected && j.status === "ok");
      if (jobsToImport.length === 0) throw new Error("Nenhum XML selecionado para importar.");

      if (!tenantId || !empresaId) throw new Error("Tenant ou empresa nao carregados.");

      // regra: só exige itens cadastrados se a finalidade permitir vincular item_id
      if (permiteVincularItens && loteMissing.length > 0) {
        throw new Error(`Itens nao cadastrados: ${loteMissing.join(", ")}`);
      }

      // Best-effort: if fornecedor already resolved in UI, persist defaults (doesn't block import)
      const fornecedorFinal = fornecedorIdBase ?? fornecedorId ?? null;
      let gerarContasAuto = fornecedorGerarContasAuto;
      if (fornecedorFinal) {
        try {
          await atualizarFinalidadePadraoFornecedor(fornecedorFinal, finalidadeLote as ItemFinalidade);
        } catch {
          // ignore
        }

        const { data: fornecedorCfg, error: fornecedorCfgErr } = await applyTenantEmpresa(
          supabase.schema("public").from("fornecedores").select("nome,gerar_contas_pagar_auto"),
          tenantId,
          empresaId
        )
          .eq("id", fornecedorFinal)
          .maybeSingle();

        if (fornecedorCfgErr) throw fornecedorCfgErr;

        gerarContasAuto = Boolean(fornecedorCfg?.gerar_contas_pagar_auto);
        setFornecedorGerarContasAuto(gerarContasAuto);
        if (fornecedorCfg?.nome) setFornecedorNome(String(fornecedorCfg.nome));
      }

      const { data: sess } = await supabase.auth.getSession();
      const token = sess.session?.access_token ?? null;
      const userEmail = sess.session?.user?.email ?? null;
      if (!token) throw new Error("Sessao expirada. Faca login novamente.");

      const callImportApi = async (job: ImportJob, payload: { nfJson: unknown; itensJson: unknown; gerar: boolean; parcelas: unknown }) => {
        const info = job.nfeInfo;
        const res = await fetch("/api/estoque/importar-xml", {
          method: "POST",
          headers: {
            "content-type": "application/json",
            authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({
            tenantId,
            empresaId,
            finalidade: finalidadeLote,
            osId: finalidadeLote === "materia_prima" ? osId : null,
            pedidoCompraId: pedidoCompraRef.trim() || null,
            pedidoCompraIds: splitPedidoCompraRefs(pedidoCompraRef),
            motivoCompraId,
            solicitanteUsuarioId: solicitanteUsuarioId,
            fornecedorCnpj: info?.cnpjEmitente ?? null,
            fornecedorNome: info?.emitente ?? null,
            nfJson: payload.nfJson,
            itensJson: payload.itensJson,
            xmlRaw: job.xmlText,
            gerarContasPagar: payload.gerar,
            parcelasJson: payload.gerar ? payload.parcelas : null,
          }),
        });

        const jsonUnknown: unknown = await res.json().catch(() => null);
        const jsonObj =
          jsonUnknown && typeof jsonUnknown === "object" ? (jsonUnknown as Record<string, unknown>) : null;
        if (!res.ok) {
          const msg = typeof jsonObj?.error === "string" ? String(jsonObj.error) : "Erro ao importar.";
          const err = new Error(msg) as Error & { status?: number };
          err.status = res.status;
          throw err;
        }

        const warningsRaw = Array.isArray(jsonObj?.warnings) ? jsonObj.warnings : [];
        const warnings = warningsRaw
          .map((w) => {
            if (typeof w === "string") return w.trim();
            if (!w || typeof w !== "object") return "";
            const rec = w as Record<string, unknown>;
            return typeof rec.message === "string" ? rec.message.trim() : "";
          })
          .filter((w): w is string => Boolean(w));

        return {
          status: typeof jsonObj?.status === "string" ? jsonObj.status : undefined,
          message: typeof jsonObj?.message === "string" ? jsonObj.message : undefined,
          nf_entrada_id:
            typeof jsonObj?.nf_entrada_id === "number"
              ? jsonObj.nf_entrada_id
              : jsonObj?.nf_entrada_id
                ? Number(jsonObj.nf_entrada_id) || null
                : null,
          warnings,
          relatorio_destinos: isRelatorioDestinoImportacao(jsonObj?.relatorio_destinos)
            ? jsonObj.relatorio_destinos
            : null,
        };
      };

      const results: string[] = [];
      const warningResults: string[] = [];
      const relatoriosDestino: RelatorioDestinoImportacao[] = [];

      for (const job of jobsToImport) {
        try {
          const info = job.nfeInfo;

          if (!info || job.itens.length === 0) {
            results.push(`${job.fileName}: sem dados de NF ou itens.`);
            setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "erro", error: "Sem dados" } : j)));
            continue;
          }

          if (!info.chave) {
            results.push(`${job.fileName}: chave nao encontrada.`);
            setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "erro", error: "Chave ausente" } : j)));
            continue;
          }

          setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "importando", error: undefined } : j)));

          // valida itens (tem que existir)
          const codes = Array.from(new Set(job.itens.map((i) => i.codigo)));

          // Só busca/vincula item_id quando a finalidade do lote permitir.
          const fornecedorFinalId = fornecedorIdBase ?? fornecedorId ?? null;
          const map = permiteVincularItens
            ? await carregarItensPorCodigo(codes, tenantId, empresaId, fornecedorFinalId)
            : new Map<string, ItemCodigoRow>();

          // Se não pode vincular, missing não bloqueia.
          if (permiteVincularItens) {
            const missingCodes = job.itens.filter((it) => !map.get(it.codigo)).map((it) => it.codigo);
            if (missingCodes.length > 0) {
              throw new Error(`Itens nao cadastrados: ${missingCodes.join(", ")}`);
            }
          }

          const itemIds = permiteVincularItens ? Array.from(new Set(Array.from(map.values()).map((item) => item.id))) : [];
          const fiscalMap = permiteVincularItens ? await carregarFiscalPorItens(itemIds, tenantId, empresaId) : new Map<number, FiscalPerfil>();

          const itemsToImport = job.itens;

          const totalProdutos = itemsToImport.reduce((sum, it) => sum + Number(it.valorProd ?? 0), 0);

          const totalFrete =
            Number(info.valorFrete ?? 0) > 0
              ? Number(info.valorFrete ?? 0)
              : itemsToImport.reduce((sum, it) => sum + Number(it.vFrete ?? 0), 0);

          const itensPayload: ImportItemPayload[] = [];

          for (const it of itemsToImport) {
            const itemId = permiteVincularItens ? (map.get(it.codigo)?.id ?? null) : null;
            const fiscal = itemId ? fiscalMap.get(itemId) : null;

            const qtd = Number(it.quantidade ?? 0);
            const baseProd = Number(it.valorProd ?? 0);
            const vDesc = Number(it.vDesc ?? 0);
            const baseLiquida = Math.max(0, baseProd - vDesc);
            const vUnitRaw = Number(it.valorUnit ?? 0);
            const vUnitLiquido = qtd > 0 && baseLiquida > 0 ? baseLiquida / qtd : vUnitRaw;

            const vIcms = Number(it.vIcms ?? 0);
            const vIpi = Number(it.vIpi ?? 0);
            const vPis = Number(it.vPis ?? 0);
            const vCofins = Number(it.vCofins ?? 0);
            const vSt = Number(it.vSt ?? 0);

            const creditoIcms = fiscal?.credita_icms ? vIcms : 0;
            const creditoPis = fiscal?.credita_pis ? vPis : 0;
            const creditoCofins = fiscal?.credita_cofins ? vCofins : 0;

            const freteRateado = totalProdutos > 0 ? (Number(it.valorProd ?? 0) / totalProdutos) * totalFrete : 0;

            const custoImpostos = (fiscal?.ipi_entra_no_custo ?? true) ? vIpi + vSt : 0;

            const custoTotal =
              baseLiquida + Number(it.vOutro ?? 0) + Number(it.vSeguro ?? 0) + freteRateado + custoImpostos;

            const custoUnitBruto = qtd > 0 ? custoTotal / qtd : null;
            const custoUnitReal =
              custoUnitBruto !== null ? custoUnitBruto - (creditoIcms + creditoPis + creditoCofins) / (qtd || 1) : null;

            itensPayload.push({
              tenant_id: tenantId,
              item_id: itemId,
              numero_item_xml: it.nItem ?? null,
              codigo: it.codigo,
              nome: it.overrideNome ?? it.nome,
              codigo_fornecedor: it.codigo,
              descricao: it.overrideNome ?? it.nome,
              unidade: it.unidade ?? null,
              unidade_tributavel: it.unidadeTrib ?? null,
              ean: it.ean ?? null,
              ean_tributavel: it.eanTrib ?? null,
              ncm: it.ncm ?? null,
              cest: it.cest ?? null,
              cfop: it.cfop ?? null,
              pedido_xml: it.pedidoXml ?? null,
              pedido_item_xml: it.pedidoItemXml ?? null,
              informacoes_adicionais: it.informacoesAdicionais ?? null,
              qtd: round6(qtd),
              v_unit: round6(vUnitLiquido > 0 ? vUnitLiquido : vUnitRaw),
              v_prod: round6(baseProd),
              v_desc: round6(vDesc),
              v_frete: round6(Number(it.vFrete ?? 0)),
              v_seguro: round6(Number(it.vSeguro ?? 0)),
              v_outro: round6(Number(it.vOutro ?? 0)),
              v_st: round6(vSt),
              v_icms: round6(vIcms),
              v_ipi: round6(vIpi),
              v_pis: round6(vPis),
              v_cofins: round6(vCofins),
              aliq_icms: it.aliquotaIcms ?? fiscal?.aliq_icms ?? null,
              aliq_ipi: it.aliquotaIpi ?? fiscal?.aliq_ipi ?? null,
              aliq_pis: it.aliquotaPis ?? fiscal?.aliq_pis ?? null,
              aliq_cofins: it.aliquotaCofins ?? fiscal?.aliq_cofins ?? null,
              quantidade: round6(qtd),
              tipo: "entrada",
              motivo: `NF ${info.numero ?? ""}/${info.serie ?? ""} chave ${info.chave ?? ""} emitente ${info.emitente ?? ""}`,
              realizado_por: userEmail,
              data_movimentacao: info.dataEmissao ?? new Date().toISOString(),
              custo_unitario_bruto: custoUnitBruto !== null ? round6(custoUnitBruto) : null,
              custo_unitario_real: custoUnitReal !== null ? round6(custoUnitReal) : null,
              v_frete_rateado: round6(freteRateado),
              credito_icms: round6(creditoIcms),
              credito_pis: round6(creditoPis),
              credito_cofins: round6(creditoCofins),
            });
          }

          const nfJson = {
            chave: info.chave,
            numero: info.numero,
            serie: info.serie,
            emitente_nome: info.emitente,
            emitente_cnpj: info.cnpjEmitente,
            valor_produtos: info.valorProdutos ?? 0,
            valor_frete: info.valorFrete ?? 0,
            valor_seguro: info.valorSeguro ?? 0,
            valor_outros: info.valorOutros ?? 0,
            valor_desconto: info.valorDesconto ?? 0,
            valor_total: info.valorTotal ?? 0,
            data_emissao: info.dataEmissao ?? new Date().toISOString(),
          };

          const shouldGenerateFinance = Boolean(gerarContasAuto);
          const parcelasJson = shouldGenerateFinance ? buildParcelasPorPagamento(info, paymentConfig) : null;
          const parcelasCount = Array.isArray(parcelasJson) ? parcelasJson.length : 0;

          const importRes = await callImportApi(job, {
            nfJson,
            itensJson: itensPayload,
            gerar: shouldGenerateFinance,
            parcelas: parcelasJson,
          });

          const status = String(importRes?.status ?? "ok");
          const message = importRes?.message ? String(importRes.message) : null;

          if (status === "ja_importada") {
            setJobs((prev) =>
              prev.map((j) => (j.id === job.id ? { ...j, status: "importado", error: message ?? "NF ja importada" } : j))
            );
            results.push(`${job.fileName}: NF ja importada (nada foi duplicado).`);
          } else {
            setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "importado", error: undefined } : j)));
            if (shouldGenerateFinance && parcelasCount === 0) {
              results.push(`${job.fileName}: importado com sucesso. XML sem duplicatas; gerado lançamento à vista.`);
            } else {
              results.push(`${job.fileName}: importado com sucesso.`);
            }
            if (Array.isArray(importRes.warnings) && importRes.warnings.length > 0) {
              warningResults.push(`${job.fileName}: ${importRes.warnings.join(" ")}`);
            }
            if (importRes.relatorio_destinos?.itens?.length) {
              relatoriosDestino.push({ ...importRes.relatorio_destinos, fileName: job.fileName });
            }
          }
        } catch (err: unknown) {
          const msg = getErrorMessage(err, "Erro");
          results.push(`${job.fileName}: erro - ${msg}`);
          setJobs((prev) => prev.map((j) => (j.id === job.id ? { ...j, status: "erro", error: msg } : j)));
        }
      }

      setJobs((prev) => prev.filter((j) => j.status !== "importado"));
      setImportOk(results.join(" "));
      setImportWarn(warningResults.length > 0 ? warningResults.join(" ") : null);
      if (relatoriosDestino.length > 0) imprimirRelatorioDestinos(relatoriosDestino);
    } catch (e: unknown) {
      setImportErr(getErrorMessage(e, "Erro ao importar."));
    } finally {
      setImportBusy(false);
    }
  }

  useEffect(() => {
    if (jobs.length === 0) {
      setSelectedJobId(null);
      return;
    }
    const exists = selectedJobId && jobs.some((j) => j.id === selectedJobId);
    if (!exists) {
      setSelectedJobId(jobs[0].id);
    }
  }, [jobs, selectedJobId]);

  const selectedJob = selectedJobId ? jobs.find((j) => j.id === selectedJobId) ?? jobs[0] ?? null : jobs[0] ?? null;
  const itensParaTabela = selectedJob?.itens ?? [];

  const selectedOkJobs = useMemo(() => jobs.filter((j) => j.selected && j.status === "ok"), [jobs]);
  const hasSelectedOkJobs = selectedOkJobs.length > 0;
  const pagamentoPreviewJob = selectedOkJobs[0] ?? selectedJob ?? null;
  const pagamentoPreviewDataEmissao = pagamentoPreviewJob?.nfeInfo?.dataEmissao ?? null;
  const pagamentoPreviewTotal = Number(pagamentoPreviewJob?.nfeInfo?.valorTotal ?? 0);
  const pagamentoPreviewParcelasXml = pagamentoPreviewJob?.nfeInfo?.parcelas ?? [];
  const cartaoPreviewParcelas = useMemo(() => {
    if (!Number.isFinite(pagamentoPreviewTotal) || pagamentoPreviewTotal <= 0) return [];
    return buildParcelasCartao(pagamentoPreviewTotal, pagamentoParcelasQtd, pagamentoPreviewDataEmissao);
  }, [pagamentoPreviewTotal, pagamentoParcelasQtd, pagamentoPreviewDataEmissao]);

  useEffect(() => {
    if (!showPagamentoModal || pagamentoModo !== "faturado") return;
    setFaturadoParcelasForm((prev) =>
      buildFaturadoDrafts(
        pagamentoParcelasQtd,
        pagamentoPreviewTotal,
        pagamentoPreviewDataEmissao,
        prev
      )
    );
  }, [showPagamentoModal, pagamentoModo, pagamentoParcelasQtd, pagamentoPreviewTotal, pagamentoPreviewDataEmissao]);

  useEffect(() => {
    const loadMap = async () => {
      if (!selectedJob || selectedJob.itens.length === 0) {
        setItemMap(new Map());
        return;
      }
      if (!tenantId || !empresaId) {
        setImportErr("Tenant ou empresa nao carregados.");
        return;
      }

      if (!permiteVincularItens) {
        setItemMap(new Map());
        return;
      }
      const fornecedorFinalId = fornecedorIdBase ?? fornecedorId ?? null;
      if (!fornecedorFinalId) {
        setItemMap(new Map());
        return;
      }
      try {
        const codes = Array.from(new Set(selectedJob.itens.map((i) => i.codigo)));
        const map = await carregarItensPorCodigo(codes, tenantId, empresaId, fornecedorFinalId);
        setItemMap(map);
      } catch (e: unknown) {
        setImportErr(getErrorMessage(e, "Erro ao carregar itens."));
      }
    };
    void loadMap();
  }, [selectedJob, tenantId, empresaId, carregarItensPorCodigo, permiteVincularItens, fornecedorIdBase, fornecedorId]);

  useEffect(() => {
    let active = true;

    const loadLoteMap = async () => {
      const clearMissing = () => setLoteMissing((prev) => (prev.length === 0 ? prev : []));

      if (!tenantId || !empresaId) {
        clearMissing();
        return;
      }

      if (!permiteVincularItens) {
        clearMissing();
        return;
      }

      if (selectedOkJobs.length === 0) {
        clearMissing();
        return;
      }

      const fornecedorFinalId = fornecedorIdBase ?? fornecedorId ?? null;
      if (!fornecedorFinalId) {
        clearMissing();
        return;
      }

      const codes = Array.from(new Set(selectedOkJobs.flatMap((j) => j.itens.map((it) => it.codigo))));
      if (codes.length === 0) {
        clearMissing();
        return;
      }

      try {
        const map = await carregarItensPorCodigo(codes, tenantId, empresaId, fornecedorFinalId);
        if (!active) return;

        const nextMissing = codes.filter((c) => !hasItemCodigoInMap(map, c));

        setLoteMissing((prev) => {
          if (prev.length !== nextMissing.length) return nextMissing;
          for (let i = 0; i < prev.length; i += 1) {
            if (prev[i] !== nextMissing[i]) return nextMissing;
          }
          return prev;
        });
      } catch (e: unknown) {
        if (!active) return;
        setImportErr(getErrorMessage(e, "Erro ao carregar itens."));
      }
    };

    void loadLoteMap();
    return () => {
      active = false;
    };
  }, [selectedOkJobs, tenantId, empresaId, carregarItensPorCodigo, permiteVincularItens, fornecedorIdBase, fornecedorId]);

  useEffect(() => {
    const fornecedorFinalId = fornecedorIdBase ?? fornecedorId;
    const hasXmlSelecionado = Boolean(selectedJob?.nfeInfo);

    if (!tenantId || !empresaId || !fornecedorFinalId || !hasXmlSelecionado || importBusy || isReading) {
      setPedidosAnalyzerComItens([]);
      setPedidosAnalyzerError(null);
      setPedidosAnalyzerLoading(false);
      return;
    }

    let active = true;
    const controller = new AbortController();

    const loadPedidosCandidatos = async () => {
      setPedidosAnalyzerLoading(true);
      setPedidosAnalyzerError(null);

      try {
        const { data: sess } = await supabase.auth.getSession();
        const token = sess.session?.access_token ?? null;
        if (!token) throw new Error("Sessao expirada. Faca login novamente.");

        const qs = new URLSearchParams({
          tenant_id: tenantId,
          empresa_id: empresaId,
          fornecedorId: String(fornecedorFinalId),
          limit: "20",
        });

        const res = await fetch(`/api/compras/pedidos-candidatos-importacao?${qs.toString()}`, {
          headers: { authorization: `Bearer ${token}` },
          signal: controller.signal,
        });
        const json = (await res.json().catch(() => null)) as { data?: unknown[]; error?: string } | null;
        if (!res.ok) {
          const msg = typeof json?.error === "string" ? json.error : "Erro ao buscar pedidos candidatos.";
          throw new Error(msg);
        }

        const rows = Array.isArray(json?.data) ? json.data : [];
        const next = rows.map(adaptPedidoAnalyzerCandidato).filter((row): row is XmlImportPedidoCandidato => Boolean(row));
        if (!active) return;
        setPedidosAnalyzerComItens(next);
        setPedidosAnalyzerLoading(false);
      } catch (e: unknown) {
        if (!active || controller.signal.aborted) return;
        setPedidosAnalyzerComItens([]);
        setPedidosAnalyzerError(getErrorMessage(e, "Nao foi possivel carregar pedidos candidatos para o assistente."));
        setPedidosAnalyzerLoading(false);
      }
    };

    void loadPedidosCandidatos();

    return () => {
      active = false;
      controller.abort();
    };
  }, [
    empresaId,
    fornecedorId,
    fornecedorIdBase,
    importBusy,
    isReading,
    selectedJob?.id,
    selectedJob?.nfeInfo,
    supabase,
    tenantId,
  ]);

  const fornecedorResolvido = Boolean(fornecedorIdBase ?? fornecedorId);
  const pedidoCompraInformado = Boolean(pedidoCompraRef.trim());
  const finalidadeSelecionada = pedidoCompraInformado || Boolean(finalidadeLote);
  const solicitanteSelecionado = Boolean(solicitanteUsuarioId || pedidoCompraInformado);
  const itensFaltantes = loteMissing.length > 0;

  const motivoSelecionadoRow = motivos.find((m) => m.id === motivoCompraId) ?? null;
  const motivoSelecionadoCodigo = String(motivoSelecionadoRow?.codigo ?? "")
    .trim()
    .toUpperCase();
  const motivoSelecionadoOk = pedidoCompraInformado
    ? true
    : Boolean(
        motivoCompraId && motivoSelecionadoRow && motivoSelecionadoCodigo && motivoSelecionadoCodigo !== "NAO_CLASSIFICADO"
      );

  const requisitosChecklist = {
    xml: hasSelectedOkJobs,
    finalidade: finalidadeSelecionada,
    motivo: motivoSelecionadoOk,
    solicitante: solicitanteSelecionado,
    fornecedor: fornecedorResolvido,
    itens: !permiteVincularItens || !itensFaltantes || canCreateItem,
  };

  const xmlImportAnalysis = useMemo(() => {
    if (!selectedJob?.nfeInfo) return null;

    const fornecedorFinalId = fornecedorIdBase ?? fornecedorId;
    const itensCadastradosPorCodigo: XmlImportItemInterno[] = [];
    const seenItens = new Set<string>();

    for (const [codigoInterno, item] of itemMap.entries()) {
      if (!codigoInterno || !item?.id) continue;
      const key = `${item.id}:${codigoInterno}`;
      if (seenItens.has(key)) continue;
      seenItens.add(key);
      itensCadastradosPorCodigo.push({
        id: item.id,
        codigo_interno: item.codigo_interno || codigoInterno,
        nome: item.nome ?? null,
        fornecedor_id: item.fornecedor_id ?? null,
      });
    }

    const pedidosCandidatos: XmlImportPedidoCandidato[] =
      pedidosAnalyzerComItens.length > 0
        ? pedidosAnalyzerComItens
        : pedidoAnalyzerRows.map((row) => ({
            id: row.id,
            codigo: row.codigo,
            status: row.status,
            fornecedor_id: toNullableNumber(row.fornecedor_id),
            fornecedor_nome: row.fornecedor_nome ?? null,
            solicitante_usuario_id: row.solicitante_usuario_id ?? null,
            total_geral: row.total_geral ?? null,
            total_pendente: row.total_geral ?? null,
            itens: [],
          }));

    return analyzeXmlImport({
      nfe: {
        chave: selectedJob.nfeInfo.chave,
        numero: selectedJob.nfeInfo.numero,
        serie: selectedJob.nfeInfo.serie,
        emitente: selectedJob.nfeInfo.emitente,
        cnpjEmitente: selectedJob.nfeInfo.cnpjEmitente,
        valorTotal: selectedJob.nfeInfo.valorTotal,
        valorProdutos: selectedJob.nfeInfo.valorProdutos,
        itens: selectedJob.itens,
      },
      itens: selectedJob.itens,
      fornecedor: fornecedorFinalId
        ? {
            id: fornecedorFinalId,
            nome: fornecedorNome,
            cnpj: selectedJob.nfeInfo.cnpjEmitente ?? fornecedorCnpjBase ?? null,
            finalidade_padrao: fornecedorFinalidadePadrao,
            motivo_compra_padrao_id: fornecedorMotivoPadraoId,
          }
        : null,
      itensCadastradosPorCodigo,
      pedidosCandidatos,
      finalidadeSelecionada: finalidadeLote || null,
      motivoSelecionadoId: motivoCompraId || null,
      solicitanteUsuarioId: solicitanteUsuarioId || null,
      pedidoCompraRefAtual: pedidoCompraRef || null,
      osIdAtual: osId,
      parametros: {
        finalidadesExigemItemCadastrado: Array.from(finalidadesComItemObrigatorio),
        finalidadesPermitemAutocadastro: allowedAutoCadastrarFinalidades,
        finalidadesPermitemVinculo: allowedVincularFinalidades,
      },
    });
  }, [
    allowedAutoCadastrarFinalidades,
    allowedVincularFinalidades,
    finalidadeLote,
    finalidadesComItemObrigatorio,
    fornecedorCnpjBase,
    fornecedorFinalidadePadrao,
    fornecedorId,
    fornecedorIdBase,
    fornecedorMotivoPadraoId,
    fornecedorNome,
    itemMap,
    motivoCompraId,
    osId,
    pedidoAnalyzerRows,
    pedidoCompraRef,
    pedidosAnalyzerComItens,
    selectedJob,
    solicitanteUsuarioId,
  ]);

  // regra: importar só se tudo estiver ok e itens sem faltantes
  const pedidoSugeridoPossuiItensManuais = useMemo(() => {
    const pedidoIds = new Set(
      [
        xmlImportAnalysis?.pedidoSuggestion?.pedidoId ?? null,
        ...(xmlImportAnalysis?.pedidoSuggestions ?? []).map((pedido) => pedido.pedidoId),
      ].filter((id): id is string => Boolean(id))
    );
    if (pedidoIds.size === 0) return false;

    return pedidosAnalyzerComItens.some(
      (pedido) => pedidoIds.has(pedido.id) && Boolean(pedido.itens?.some(isPedidoItemManualParaVinculo))
    );
  }, [pedidosAnalyzerComItens, xmlImportAnalysis]);

  const pedidoItemLinkData = useMemo(() => {
    if (!pedidoItemLink) return null;

    const itemSuggestion = xmlImportAnalysis?.itemSuggestions.find((item) => item.index === pedidoItemLink.xmlItemIndex) ?? null;
    const pedido = pedidosAnalyzerComItens.find((row) => row.id === pedidoItemLink.pedidoId) ?? null;
    const manualItems = (pedido?.itens ?? []).filter(isPedidoItemManualParaVinculo);
    const selectedPedidoItemId = pedidoItemLinkSelectedId || pedidoItemLink.pedidoItemId;
    const selectedPedidoItem =
      manualItems.find((item) => item.id === selectedPedidoItemId) ??
      (pedido?.itens ?? []).find((item) => item.id === selectedPedidoItemId) ??
      null;

    return {
      itemSuggestion,
      internalItem: itemSuggestion?.internalItem ?? null,
      pedido,
      manualItems,
      selectedPedidoItem,
      nfItem: selectedJob?.itens[pedidoItemLink.xmlItemIndex] ?? null,
    };
  }, [pedidoItemLink, pedidoItemLinkSelectedId, pedidosAnalyzerComItens, selectedJob?.itens, xmlImportAnalysis]);

  const pedidoItemLinkPodeCadastrar = Boolean(
    pedidoItemLink &&
      !pedidoItemLinkData?.internalItem &&
      canCreateItem &&
      permiteAutoCadastrarItens &&
      finalidadeLote &&
      fornecedorResolvido
  );
  const bloqueiaVinculoManualPedido = Boolean(
    xmlImportAnalysis?.findings.some((finding) => finding.code === "VINCULAR_ITENS_MANUAIS_PEDIDO_OBRIGATORIO")
  );
  const bloqueiaDivergenciaPedido = Boolean(
    xmlImportAnalysis?.findings.some(
      (finding) =>
        finding.severity === "error" &&
        ["DIVERGENCIA_VALOR_UNITARIO", "QUANTIDADE_EXCEDE_PEDIDO"].includes(finding.code)
    )
  );
  const hasPedidoSuggestion = Boolean(xmlImportAnalysis?.pedidoSuggestion || (xmlImportAnalysis?.pedidoSuggestions?.length ?? 0) > 0);
  const bloqueiaPedidoCompativelNaoAplicado = Boolean(hasPedidoSuggestion && !pedidoCompraInformado);

  const bloqueiaImportacao =
    !hasSelectedOkJobs ||
    !finalidadeSelecionada ||
    !motivoSelecionadoOk ||
    !solicitanteSelecionado ||
    !fornecedorResolvido ||
    (permiteVincularItens && itensFaltantes) ||
    bloqueiaPedidoCompativelNaoAplicado ||
    bloqueiaVinculoManualPedido ||
    bloqueiaDivergenciaPedido ||
    !tenantId ||
    !empresaId;

  const podeCriarItens = !permiteVincularItens || !itensFaltantes || canCreateItem;

  // regra: o botão "Cadastrar itens" só fica habilitado quando o fornecedor já estiver cadastrado
  const bloqueiaCadastroItens =
    !hasSelectedOkJobs ||
    !finalidadeSelecionada ||
    !fornecedorResolvido ||
    !tenantId ||
    !empresaId ||
    !podeCriarItens ||
    !permiteAutoCadastrarItens;
  const showBulkItemRegistrationButton = false;
  const hasAnyXmlJob = jobs.length > 0;
  const hasSelectedNfeInfo = Boolean(selectedJob?.nfeInfo);
  const selectedJobAlreadyImported = selectedJob?.status === "importado";
  const selectedJobHasError = selectedJob?.status === "erro";
  const shouldShowImportForm = hasSelectedNfeInfo && !selectedJobAlreadyImported && !selectedJobHasError;
  const shouldShowAssistant = shouldShowImportForm && Boolean(xmlImportAnalysis);
  const shouldShowItens = shouldShowImportForm && itensParaTabela.length > 0;
  const shouldShowQueue = hasAnyXmlJob;
  const shouldShowImportActions = shouldShowImportForm && hasSelectedOkJobs && itensParaTabela.length > 0;
  const hasXmlStateToClear =
    selectedFiles.length > 0 ||
    Boolean(selectedFile) ||
    Boolean(xmlText.trim()) ||
    hasAnyXmlJob ||
    Boolean(importErr) ||
    Boolean(importOk) ||
    Boolean(importWarn) ||
    isReading;

  const renderNfeResumo = (nfe: ParsedNfe, itemCount: number) => (
    <div className="grid gap-3 text-sm sm:grid-cols-2 lg:grid-cols-3">
      <div>
        <div className="text-xs text-zinc-500">Chave</div>
        <div className="font-mono text-zinc-200 break-all">{nfe.chave ?? "-"}</div>
      </div>
      <div>
        <div className="text-xs text-zinc-500">Numero/serie</div>
        <div className="text-zinc-200">
          {nfe.numero ?? "-"}/{nfe.serie ?? "-"}
        </div>
      </div>
      <div>
        <div className="text-xs text-zinc-500">Emitente</div>
        <div className="text-zinc-200">{nfe.emitente ?? "-"}</div>
      </div>
      <div>
        <div className="text-xs text-zinc-500">CNPJ</div>
        <div className="font-mono text-zinc-200">{nfe.cnpjEmitente ?? "-"}</div>
      </div>
      <div>
        <div className="text-xs text-zinc-500">Data emissao</div>
        <div className="text-zinc-200">{formatDateBR(nfe.dataEmissao) || "-"}</div>
      </div>
      <div>
        <div className="text-xs text-zinc-500">Valor total</div>
        <div className="text-right tabular-nums text-zinc-200 sm:text-left">R$ {formatMoneyBR(Number(nfe.valorTotal ?? 0))}</div>
      </div>
      <div>
        <div className="text-xs text-zinc-500">Itens</div>
        <div className="text-right tabular-nums text-zinc-200 sm:text-left">{itemCount}</div>
      </div>
    </div>
  );

  const aplicarPedidoSugerido = (pedidoRef: string) => {
    setPedidoCompraRef(pedidoRef);
    clearOsSelection();
    aplicarMotivoAutomatico({ origem: "pedido", temOs: false });
  };

  const aplicarSolicitanteSugerido = (usuarioId: string) => {
    setSolicitanteUsuarioId(usuarioId);
  };

  const aplicarOsSugerida = (nextOsId: number, osNumeroSugerido?: string | null, osLabelSugerido?: string | null) => {
    const normalizedOsId = Math.trunc(Number(nextOsId));
    if (!Number.isFinite(normalizedOsId) || normalizedOsId <= 0) return;

    const numero = String(osNumeroSugerido ?? "").trim() || String(normalizedOsId);
    const label = String(osLabelSugerido ?? "").trim() || `OS ${numero}`;

    setOsId(normalizedOsId);
    setOsNumero(numero);
    setOsLabel(label);
    setOsError(null);
    setOsLoading(false);
    aplicarMotivoAutomatico({ origem: "os", temOs: true });
  };

  const aplicarFinalidadeSugerida = (finalidade: string) => {
    const next = finalidade as ItemFinalidade;
    setFinalidadeLote(next);

    const fornecedorFinal = fornecedorIdBase ?? fornecedorIdRef.current;
    if (fornecedorFinal) {
      scheduleSaveFornecedorDefaults({
        fornecedorId: fornecedorFinal,
        finalidade: next,
        motivoCompraId: normalizeMotivoId(motivoCompraIdRef.current),
      });
    }
  };

  const aplicarMotivoSugerido = (motivoId: string) => {
    setMotivoCompraId(motivoId);

    const fornecedorFinal = fornecedorIdBase ?? fornecedorIdRef.current;
    if (fornecedorFinal) {
      scheduleSaveFornecedorDefaults({
        fornecedorId: fornecedorFinal,
        finalidade: normalizeFinalidade(finalidadeRef.current),
        motivoCompraId: normalizeMotivoId(motivoId),
      });
    }
  };

  const copiarDiagnosticoAssistente = async () => {
    if (!xmlImportAnalysis) return;

    const diagnostico = {
      geradoEm: new Date().toISOString(),
      analyzer: {
        status: xmlImportAnalysis.status,
        score: xmlImportAnalysis.score,
        fornecedorSuggestion: xmlImportAnalysis.fornecedorSuggestion,
        pedidoSuggestion: xmlImportAnalysis.pedidoSuggestion,
        pedidoSuggestions: xmlImportAnalysis.pedidoSuggestions,
        findings: xmlImportAnalysis.findings,
        warnings: xmlImportAnalysis.warnings,
        suggestions: xmlImportAnalysis.suggestions,
        itemSuggestions: xmlImportAnalysis.itemSuggestions,
        actionPlan: xmlImportAnalysis.actionPlan,
      },
      selectedJob: selectedJob
        ? {
            fileName: selectedJob.fileName,
            chave: selectedJob.nfeInfo?.chave ?? null,
            numero: selectedJob.nfeInfo?.numero ?? null,
            serie: selectedJob.nfeInfo?.serie ?? null,
            emitente: selectedJob.nfeInfo?.emitente ?? null,
            cnpjEmitente: selectedJob.nfeInfo?.cnpjEmitente ?? null,
            valorTotal: selectedJob.nfeInfo?.valorTotal ?? null,
            quantidadeItens: selectedJob.itens.length,
          }
        : null,
      camposTela: {
        finalidadeLote: finalidadeLote || null,
        motivoCompraId: motivoCompraId || null,
        solicitanteUsuarioIdPreenchido: Boolean(solicitanteUsuarioId),
        pedidoCompraRef: pedidoCompraRef || null,
        fornecedorId: fornecedorIdBase ?? fornecedorId ?? null,
        pedidosAnalyzerComItensQuantidade: pedidosAnalyzerComItens.length,
        itemMapQuantidade: itemMap.size,
        loteMissing: [...loteMissing],
      },
    };

    try {
      await copyTextToClipboard(JSON.stringify(diagnostico, null, 2));
      setAssistantCopyMessage({ kind: "ok", message: "Diagnóstico copiado." });
    } catch {
      setAssistantCopyMessage({ kind: "error", message: "Não foi possível copiar o diagnóstico." });
    }

    window.setTimeout(() => setAssistantCopyMessage(null), 2800);
  };

  const abrirVinculoItemPedido = (params: PedidoItemLinkRequest) => {
    setPedidoItemLink(params);
    setPedidoItemLinkSelectedId(params.pedidoItemId);
    setPedidoItemLinkError(null);
    setPedidoItemLinkBusy(false);
  };

  const abrirVinculoItemPedidoDaTabela = (it: ParsedItem, index: number) => {
    const suggestion = xmlImportAnalysis?.itemSuggestions.find((item) => item.index === index) ?? null;
    const pedidosSugeridos = xmlImportAnalysis?.pedidoSuggestions ?? [];
    const pedido = pedidosSugeridos.length === 1 ? pedidosSugeridos[0] : xmlImportAnalysis?.pedidoSuggestion ?? null;
    const pedidoId = suggestion?.pedidoMatchPedidoId ?? pedido?.pedidoId ?? null;
    const pedidoCodigo = suggestion?.pedidoMatchPedidoCodigo ?? pedido?.codigo ?? null;

    if (!pedidoId) {
      setImportErr("Nenhum pedido sugerido disponivel para vincular este item.");
      return;
    }

    const pedidoCompleto = pedidosAnalyzerComItens.find((row) => row.id === pedidoId) ?? null;
    const manualItems = (pedidoCompleto?.itens ?? []).filter(isPedidoItemManualParaVinculo);
    const pedidoItemId = suggestion?.pedidoMatchItemId ?? manualItems[0]?.id ?? "";

    if (!pedidoItemId) {
      setImportErr("Pedido sugerido nao possui item manual disponivel para vinculo.");
      return;
    }

    abrirVinculoItemPedido({
      xmlItemIndex: index,
      codigoOriginal: it.codigo,
      codigoNormalizado: normalizeItemCodigo(it.codigo),
      descricao: it.overrideNome ?? it.nome ?? "",
      pedidoId,
      pedidoCodigo,
      pedidoItemId,
    });
  };

  const fecharVinculoItemPedido = () => {
    if (pedidoItemLinkBusy) return;
    setPedidoItemLink(null);
    setPedidoItemLinkSelectedId("");
    setPedidoItemLinkError(null);
  };

  const confirmarVinculoItemPedido = async () => {
    if (!pedidoItemLink || !tenantId || !empresaId) return;

    let internalItem = pedidoItemLinkData?.internalItem ?? null;

    const pedidoItemId = pedidoItemLinkSelectedId || pedidoItemLink.pedidoItemId;
    if (!pedidoItemId) {
      setPedidoItemLinkError("Selecione um item manual do pedido.");
      return;
    }

    setPedidoItemLinkBusy(true);
    setPedidoItemLinkError(null);

    try {
      if (!internalItem?.id) {
        if (!canCreateItem) throw new Error("Sem permissao para cadastrar itens.");
        if (!permiteAutoCadastrarItens || !finalidadeLote) {
          throw new Error("Selecione uma finalidade que permita cadastrar item antes de vincular ao pedido.");
        }

        const nfItem = pedidoItemLinkData?.nfItem ?? null;
        if (!nfItem) throw new Error("Item da NF nao encontrado para cadastro.");

        const codigoNormalizado = normalizeItemCodigo(nfItem.codigo);
        let sugestao = normalizacoesCadastro[codigoNormalizado];
        if (!sugestao) {
          const sugestoes = await solicitarNormalizacoesCadastro([nfItem]);
          sugestao = sugestoes[codigoNormalizado];
          throw new Error("Sugestao da IA gerada. Confira descricao e grupo do item na NF antes de confirmar o vinculo.");
        }
        validarSugestaoCadastro(sugestao);
        sugestao = await garantirGrupoDaSugestao(sugestao);
        validarSugestaoCadastro(sugestao);

        const fornecedorFinal = fornecedorIdBase ?? fornecedorId ?? null;
        const createdId = await criarItemRapido(
          nfItem,
          fornecedorFinal,
          selectedJob?.nfeInfo?.dataEmissao ?? new Date().toISOString(),
          finalidadeLote as ItemFinalidade,
          sugestao
        );
        if (!createdId) throw new Error("Nao foi possivel cadastrar o item antes do vinculo.");

        const createdItem: XmlImportItemInterno = {
          id: createdId,
          codigo_interno: codigoNormalizado,
          nome: sugestao.descricao_padronizada,
          fornecedor_id: fornecedorFinal,
        };
        internalItem = createdItem;
        setItemMap((prev) => {
          const next = new Map(prev);
          addItemCodigoToMap(next, {
            id: createdItem.id,
            codigo_interno: createdItem.codigo_interno,
            nome: createdItem.nome,
            fornecedor_id: createdItem.fornecedor_id ?? null,
            ativo: true,
          });
          return next;
        });
        setLoteMissing((prev) => prev.filter((codigo) => normalizeItemCodigo(codigo) !== createdItem.codigo_interno));
      }

      const { data: sess } = await supabase.auth.getSession();
      const token = sess.session?.access_token ?? null;
      if (!token) throw new Error("Sessao expirada. Faca login novamente.");

      const res = await fetch("/api/compras/pedido-itens/vincular-item", {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          tenantId,
          empresaId,
          pedidoId: pedidoItemLink.pedidoId,
          pedidoItemId,
          itemId: internalItem.id,
        }),
      });

      const json = (await res.json().catch(() => null)) as VincularPedidoItemResponse | null;
      if (!res.ok || !json?.ok || !json.pedidoItem) {
        const message = typeof json?.error === "string" ? json.error : "Nao foi possivel vincular o item ao pedido.";
        throw new Error(message);
      }

      const updated = json.pedidoItem;
      const updatedItemId = toNullableNumber(updated.item_id);
      const updatedCodigo = toNullableString(updated.item_codigo);
      const updatedNome = toNullableString(updated.item_nome);

      setPedidosAnalyzerComItens((prev) =>
        prev.map((pedido) => {
          if (pedido.id !== pedidoItemLink.pedidoId) return pedido;
          return {
            ...pedido,
            itens: (pedido.itens ?? []).map((item) =>
              item.id === pedidoItemId
                ? {
                    ...item,
                    item_id: updatedItemId == null ? item.item_id : String(updatedItemId),
                    item_codigo: updatedCodigo,
                    item_nome: updatedNome,
                    descricao: updatedNome ?? item.descricao ?? null,
                  }
                : item
            ),
          };
        })
      );

      setAssistantCopyMessage({
        kind: "ok",
        message: pedidoItemLinkData?.internalItem
          ? "Item manual do pedido vinculado ao cadastro interno."
          : "Item cadastrado e vinculado ao item manual do pedido.",
      });
      window.setTimeout(() => setAssistantCopyMessage(null), 2800);
      setPedidoItemLink(null);
      setPedidoItemLinkSelectedId("");
    } catch (e: unknown) {
      setPedidoItemLinkError(getErrorMessage(e, "Nao foi possivel vincular o item ao pedido."));
    } finally {
      setPedidoItemLinkBusy(false);
    }
  };

  const abrirModalPagamento = () => {
    if (isReading || importBusy || bloqueiaImportacao || !canImport) return;

    const qtdPadrao = clampParcelas(pagamentoPreviewParcelasXml.length || 1);
    setPagamentoModo("seguir_nota");
    setPagamentoParcelasQtd(qtdPadrao);
    setFaturadoParcelasForm(
      buildFaturadoDrafts(
        qtdPadrao,
        pagamentoPreviewTotal,
        pagamentoPreviewDataEmissao
      )
    );
    setPagamentoModalErr(null);
    setShowPagamentoModal(true);
  };

  const fecharModalPagamento = () => {
    if (importBusy) return;
    setShowPagamentoModal(false);
    setPagamentoModalErr(null);
  };

  const confirmarPagamentoEImportar = async () => {
    if (importBusy || isReading) return;

    const jobsToImport = jobs.filter((j) => j.selected && j.status === "ok");
    if (jobsToImport.length === 0) {
      setPagamentoModalErr("Nenhum XML selecionado para importar.");
      return;
    }

    const qtd = clampParcelas(pagamentoParcelasQtd);
    let config: PagamentoImportacaoConfig = { modo: "seguir_nota" };

    if (pagamentoModo === "cartao") {
      config = { modo: "cartao", quantidade: qtd };
    } else if (pagamentoModo === "dinheiro") {
      config = { modo: "dinheiro" };
    } else if (pagamentoModo === "faturado") {
      if (jobsToImport.length > 1) {
        setPagamentoModalErr("Para faturado manual, importe um XML por vez.");
        return;
      }

      const rows = faturadoParcelasForm.slice(0, qtd);
      if (rows.length !== qtd) {
        setPagamentoModalErr("Informe todas as parcelas do faturado.");
        return;
      }

      const parcelas: ParcelaPayload[] = [];
      for (let i = 0; i < rows.length; i += 1) {
        const row = rows[i];
        const vencimento = toDateOnly(row.vencimento);
        const valor = parseMoneyInput(row.valor);

        if (!vencimento) {
          setPagamentoModalErr(`Parcela ${i + 1}: informe uma data valida.`);
          return;
        }
        if (!Number.isFinite(valor) || valor <= 0) {
          setPagamentoModalErr(`Parcela ${i + 1}: valor invalido.`);
          return;
        }

        parcelas.push({
          numero: String(i + 1).padStart(3, "0"),
          vencimento,
          valor,
        });
      }

      const totalNf = Number(jobsToImport[0]?.nfeInfo?.valorTotal ?? 0);
      if (Number.isFinite(totalNf) && totalNf > 0) {
        const soma = Number(parcelas.reduce((acc, p) => acc + p.valor, 0).toFixed(2));
        if (Math.abs(soma - totalNf) > 0.05) {
          setPagamentoModalErr(
            `A soma das parcelas (R$ ${formatMoneyBR(soma)}) difere do total da NF (R$ ${formatMoneyBR(totalNf)}).`
          );
          return;
        }
      }

      config = { modo: "faturado", parcelas };
    }

    setPagamentoModalErr(null);
    setShowPagamentoModal(false);
    await importarNfe(config);
  };

  if (!ready && permissionsLoading) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Carregando permissoes...</div>;
  }

  if (!canAccessPage) {
    return <div className="min-h-screen flex items-center justify-center text-zinc-300">Sem permissao para acessar esta pagina.</div>;
  }

  const recentControlsDisabled = !tenantId || !empresaId;
  const recentActionsDisabled = recentControlsDisabled || recentNfsLoading;
  const recentDateFieldsDisabled = recentControlsDisabled || !recentUseDateFilter;
  const hasRecentFilters =
    recentUseDateFilter || recentFilterEmitente.trim() !== "" || recentFilterNumero.trim() !== "";

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold">Importar NF-e (XML)</h1>
          <p className="mt-1 text-sm text-zinc-400">Selecione um XML de NF-e para validar e preparar a entrada no estoque.</p>
        </div>
      </div>

      {shouldShowImportForm && (
      <div className="order-3 border border-zinc-800 rounded-xl bg-zinc-950 p-4 space-y-4">
        {!canImport && (
          <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-200">
            Voce nao tem permissao para importar NF-e. Voce ainda pode ler XML e cadastrar fornecedor/itens.
          </div>
        )}

        <div className="grid gap-4 md:grid-cols-2">
          <div className="border border-zinc-800 rounded-lg p-3 space-y-3">
            <div>
              <div className="text-lg font-semibold">Finalidade e vínculo</div>
              <div className="text-sm text-zinc-400">Dados operacionais para cadastrar itens e importar a NF.</div>
            </div>

            <div className="grid gap-4">
              <label className="flex flex-col gap-1">
                <span className="text-sm text-zinc-200">Finalidade</span>
                <select
                  value={finalidadeLote}
                  onChange={(e) => {
                    const next = e.target.value as ItemFinalidade | "";
                    setFinalidadeLote(next);

                    const fornecedorFinal = fornecedorIdBase ?? fornecedorIdRef.current;
                    if (fornecedorFinal) {
                      scheduleSaveFornecedorDefaults({
                        fornecedorId: fornecedorFinal,
                        finalidade: next ? (next as ItemFinalidade) : null,
                        motivoCompraId: normalizeMotivoId(motivoCompraIdRef.current),
                      });
                    }
                  }}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                >
                  <option value="">Selecione...</option>
                  <option value="consumo">Consumo</option>
                  <option value="materia_prima">Materia-prima</option>
                  <option value="revenda">Revenda</option>
                  <option value="imobilizado">Imobilizado</option>
                  <option value="outros">Outros</option>
                </select>
              </label>

              <label className="flex flex-col gap-1">
                <span className="text-sm text-zinc-200">Classificacao / Motivo</span>
                <MotivoCompraCombobox
                  motivos={motivos}
                  value={motivoCompraId}
                  disabled={motivosLoading}
                  loading={motivosLoading}
                  error={motivosError}
                  onChange={(next) => {
                    setMotivoCompraId(next);
                    const fornecedorFinal = fornecedorIdBase ?? fornecedorIdRef.current;
                    if (fornecedorFinal) {
                      scheduleSaveFornecedorDefaults({
                        fornecedorId: fornecedorFinal,
                        finalidade: normalizeFinalidade(finalidadeRef.current),
                        motivoCompraId: normalizeMotivoId(next),
                      });
                    }
                  }}
                  onToggleFavorito={async (id, next) => {
                    await setMotivoFavorito(id, next);
                  }}
                />
                {!motivosLoading && !motivosError && !motivoSelecionadoOk && !pedidoCompraInformado && (
                  <div className="text-xs text-amber-300">Obrigatorio para importar (nao pode ser NAO_CLASSIFICADO).</div>
                )}

                {defaultsToast && (
                  <div
                    className={
                      defaultsToast.kind === "saved"
                        ? "text-xs text-emerald-300"
                        : defaultsToast.kind === "warn"
                          ? "text-xs text-amber-300"
                          : "text-xs text-red-300"
                    }
                  >
                    {defaultsToast.message}
                  </div>
                )}
              </label>

              <label className="flex flex-col gap-1">
                <span className="text-sm text-zinc-200">Solicitante (Usuario) (obrigatorio)</span>
                <select
                  value={solicitanteUsuarioId}
                  onChange={(e) => setSolicitanteUsuarioId(e.target.value)}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                  disabled={usuariosSolicitantesLoading || importBusy || isReading}
                >
                  <option value="">Selecione...</option>
                  {usuariosSolicitantes.map((u) => (
                    <option key={u.id} value={u.id}>
                      {u.nome} — {u.email}
                    </option>
                  ))}
                </select>
                {usuariosSolicitantesLoading && <div className="text-xs text-zinc-400">Carregando usuarios...</div>}
                {!usuariosSolicitantesLoading && usuariosSolicitantesError && (
                  <div className="text-xs text-red-400">{usuariosSolicitantesError}</div>
                )}
                {!usuariosSolicitantesLoading && !usuariosSolicitantesError && !solicitanteSelecionado && (
                  <div className="text-xs text-amber-300">Obrigatorio para importar (ou informe um pedido com solicitante).</div>
                )}
              </label>

              <label className="flex flex-col gap-1">
                <span className="text-sm text-zinc-200">Pedido de compra (opcional)</span>
                <div className="flex items-center gap-2">
                  <input
                    value={pedidoCompraRef}
                    onChange={(e) => {
                      const nextPedidoRef = e.target.value;
                      setPedidoCompraRef(nextPedidoRef);
                      setPedidoAnalyzerRows([]);
                      if (nextPedidoRef.trim()) clearOsSelection();
                    }}
                    onKeyDown={(e) => {
                      if (e.key !== "Enter") return;
                      e.preventDefault();
                      openPedidoLookup((e.currentTarget as HTMLInputElement).value);
                    }}
                    className="flex-1 px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                    placeholder="Codigo(s) do pedido ou UUID (Enter abre busca)"
                    disabled={importBusy || isReading}
                    autoComplete="off"
                    enterKeyHint="search"
                  />
                  <button
                    type="button"
                    onClick={() => openPedidoLookup()}
                    className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
                    disabled={importBusy || isReading}
                  >
                    Buscar
                  </button>
                </div>
                <div className="text-xs text-zinc-400">
                  Se informado, a importacao tenta vincular itens ao pedido. Para NF com itens de mais de um pedido, separe os pedidos por virgula.
                </div>
              </label>

              {osEnabled && (
                <label className="flex flex-col gap-1">
                  <span className="text-sm text-zinc-200">
                    OS (opcional)
                    <span className="text-xs text-zinc-500"> — apenas para Matéria-prima</span>
                  </span>

                  <div className="flex items-center gap-2">
                    <div className="relative flex-1">
                      <input
                        value={osNumero}
                        onChange={(e) => {
                          setOsNumero(e.target.value);
                          setOsId(null);
                          setOsLabel(null);
                          setOsError(null);
                        }}
                        onKeyDown={(e) => {
                          if (e.key === "Enter" && osNumero.trim() === "") {
                            e.preventDefault();
                            openOsLookup();
                          }
                        }}
                        placeholder="Numero da OS (Enter abre busca)"
                        className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                        disabled={importBusy || isReading}
                        autoComplete="off"
                        enterKeyHint="search"
                      />

                      {osLoading && (
                        <span className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-zinc-400">
                          buscando...
                        </span>
                      )}
                    </div>

                    <button
                      type="button"
                      onClick={openOsLookup}
                      className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
                      disabled={importBusy || isReading}
                    >
                      Buscar
                    </button>

                    <button
                      type="button"
                      onClick={() => {
                        setOsNumero("");
                        setOsId(null);
                        setOsLabel(null);
                        setOsError(null);
                      }}
                      className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
                      disabled={importBusy || isReading || (!osNumero && osId === null)}
                      title="Limpar OS"
                    >
                      Limpar
                    </button>
                  </div>

                  {osLabel && <div className="text-xs text-zinc-400">{osLabel}</div>}
                  {osError && <div className="text-xs text-red-400">{osError}</div>}
                </label>
              )}

              {fornecedorResolvido && (
                <div className="text-sm text-zinc-200">
                  <span className="text-zinc-400">Fornecedor identificado:</span>{" "}
                  <span className="font-medium">{fornecedorNome ?? "—"}</span>
                  <span className="text-zinc-500"> — contas a pagar automático: </span>
                  <span className="font-medium">{fornecedorGerarContasAuto ? "Sim" : "Não"}</span>
                </div>
              )}
            </div>
          </div>

          <div className="border border-zinc-800 rounded-lg p-3">
            <div className="text-sm font-semibold text-zinc-100">Requisitos</div>
            <div className="mt-2 space-y-1 text-sm">
              <div className={requisitosChecklist.xml ? "text-emerald-300" : "text-amber-300"}>
                {requisitosChecklist.xml ? "OK" : "Pendente"} - XML lido e validado
              </div>
              <div className={requisitosChecklist.finalidade ? "text-emerald-300" : "text-amber-300"}>
                {requisitosChecklist.finalidade ? "OK" : "Pendente"} - Finalidade selecionada
              </div>
              <div className={requisitosChecklist.motivo ? "text-emerald-300" : "text-amber-300"}>
                {requisitosChecklist.motivo ? "OK" : "Pendente"} - Classificacao/Motivo selecionado
              </div>
              <div className={requisitosChecklist.solicitante ? "text-emerald-300" : "text-amber-300"}>
                {requisitosChecklist.solicitante ? "OK" : "Pendente"} - Solicitante selecionado
              </div>
              <div className={requisitosChecklist.fornecedor ? "text-emerald-300" : "text-amber-300"}>
                {requisitosChecklist.fornecedor ? "OK" : "Pendente"} - Fornecedor encontrado/cadastrado
              </div>
              <div className={!itensFaltantes && requisitosChecklist.itens ? "text-emerald-300" : "text-amber-300"}>
                {itensFaltantes
                  ? `Pendente - ${loteMissing.length} ${loteMissing.length > 1 ? "itens sem cadastro" : "item sem cadastro"}`
                  : `${requisitosChecklist.itens ? "OK" : "Pendente"} - ${
                      finalidadeLote === "imobilizado"
                        ? "Itens vao para cadastro de imobilizado"
                        : finalidadeLote === "consumo"
                          ? "Itens vao para cadastro de consumo"
                          : "Itens cadastrados"
                    }`}
              </div>
              {bloqueiaVinculoManualPedido && (
                <div className="text-amber-300">
                  Pendente - Vincule/corrija os itens manuais do pedido antes de importar
                </div>
              )}
              {bloqueiaPedidoCompativelNaoAplicado && (
                <div className="text-red-300">
                  Pendente - Use o pedido sugerido antes de importar esta NF
                </div>
              )}
              {bloqueiaDivergenciaPedido && (
                <div className="text-red-300">
                  Pendente - Corrija divergencias de preco ou quantidade no pedido antes de importar
                </div>
              )}
            </div>
          </div>
        </div>

        {shouldShowAssistant && (
          <>
            <XmlImportAssistantPanel
              result={xmlImportAnalysis}
              currentPedidoRef={pedidoCompraRef}
              currentSolicitanteUsuarioId={solicitanteUsuarioId}
              currentFinalidade={finalidadeLote || null}
              currentMotivoId={motivoCompraId || null}
              currentOsId={osId}
              hasManualPedidoItems={pedidoSugeridoPossuiItensManuais}
              onApplyPedidoSuggestion={aplicarPedidoSugerido}
              onApplySolicitanteSuggestion={aplicarSolicitanteSugerido}
              onApplyOsSuggestion={aplicarOsSugerida}
              onApplyFinalidadeSuggestion={aplicarFinalidadeSugerida}
              onApplyMotivoSuggestion={aplicarMotivoSugerido}
              onCopyDiagnostics={copiarDiagnosticoAssistente}
              onOpenPedidoItemLink={abrirVinculoItemPedido}
            />
            {pedidosAnalyzerLoading && (
              <div className="text-xs text-zinc-500">Buscando pedidos candidatos para o assistente...</div>
            )}
            {pedidosAnalyzerError && <div className="text-xs text-amber-300">{pedidosAnalyzerError}</div>}
            {assistantCopyMessage && (
              <div className={assistantCopyMessage.kind === "ok" ? "text-xs text-emerald-300" : "text-xs text-amber-300"}>
                {assistantCopyMessage.message}
              </div>
            )}
          </>
        )}
      </div>
      )}

      <div className="order-2 border border-zinc-800 rounded-xl bg-zinc-950">
        <div className="flex items-center justify-between gap-2 px-5 py-4 border-b border-zinc-800">
          <div>
            <div className="text-lg font-semibold">Selecionar XML</div>
            <div className="text-sm text-zinc-400">Escolha um ou mais arquivos XML de NF-e para leitura.</div>
          </div>

          <div className="flex items-center gap-2">
            {hasXmlStateToClear && (
              <button
                type="button"
                onClick={clearQueue}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                disabled={isReading || importBusy}
              >
                Limpar
              </button>
            )}
          </div>
        </div>

        <div className="px-5 py-4 space-y-3">
          <div className="space-y-2">
            <div className="flex gap-2 items-center">
              <input
                ref={fileInputRef}
                type="file"
                accept=".xml"
                multiple
                aria-label="Selecionar arquivos XML"
                title="Selecionar arquivos XML"
                onChange={handleFile}
                className="text-sm text-zinc-200"
                disabled={isReading || importBusy}
              />

              <button
                onClick={() => void parseXmlAndCheck()}
                className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                disabled={isReading || ((selectedFiles.length === 0 && !selectedFile) && !xmlText) || importBusy}
              >
                {isReading ? "Lendo..." : "Ler XML"}
              </button>
            </div>
          </div>

          {selectedFiles.length > 0 && !hasAnyXmlJob && !isReading && (
            <div className="text-xs text-zinc-400">
              {selectedFiles.length === 1 ? selectedFiles[0]?.name : `${selectedFiles.length} arquivos selecionados`}
            </div>
          )}
          {isReading && <div className="text-sm text-zinc-300">Lendo XML...</div>}
          {importErr && <div className="text-sm text-red-400">{importErr}</div>}
          {importWarn && <div className="text-sm text-amber-300">{importWarn}</div>}
          {importOk && <div className="text-sm text-emerald-300">{importOk}</div>}

          {shouldShowQueue && (
          <div className="border border-zinc-800 rounded-lg p-3 space-y-2">
            <div className="flex items-center justify-between">
              <div className="font-semibold text-zinc-100">Fila de XMLs</div>
              <div className="flex items-center gap-2">
                <span className="text-xs text-zinc-400">{jobs.length} arquivos na fila</span>
                <button
                  onClick={clearQueue}
                  disabled={jobs.length === 0}
                  className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs"
                >
                  Limpar fila
                </button>
              </div>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead className="bg-zinc-900/60 text-zinc-200 sticky top-0">
                  <tr>
                    <th className="px-2 py-1 text-center">Ver</th>
                    <th className="px-2 py-1 text-center">Importar</th>
                    <th className="px-2 py-1 text-left">Chave</th>
                    <th className="px-2 py-1 text-left">Numero/Serie</th>
                    <th className="px-2 py-1 text-left">Emissao</th>
                    <th className="px-2 py-1 text-left">Emitente</th>
                    <th className="px-2 py-1 text-left">Status</th>
                    <th className="px-2 py-1 text-center">Acoes</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-800">
                  {jobs.map((j) => (
                    <tr key={j.id} className="hover:bg-zinc-900/40">
                      <td className="px-2 py-1 text-center">
                        <input
                          type="radio"
                          name="job-view"
                          aria-label={`Selecionar XML ${j.nfeInfo?.chave ?? j.id}`}
                          title={`Selecionar XML ${j.nfeInfo?.chave ?? j.id}`}
                          checked={selectedJobId === j.id}
                          onChange={() => selectJob(j.id)}
                        />
                      </td>
                      <td className="px-2 py-1 text-center">
                        <input
                          type="checkbox"
                          aria-label={`Marcar XML ${j.nfeInfo?.chave ?? j.id} para importar`}
                          title={`Marcar XML ${j.nfeInfo?.chave ?? j.id} para importar`}
                          checked={j.selected}
                          onChange={() => toggleJobSelected(j.id)}
                        />
                      </td>
                      <td className="px-2 py-1">{j.nfeInfo?.chave ?? "?"}</td>
                      <td className="px-2 py-1">
                        {j.nfeInfo?.numero ?? "?"}/{j.nfeInfo?.serie ?? "?"}
                      </td>
                      <td className="px-2 py-1">{j.nfeInfo?.dataEmissao ?? "?"}</td>
                      <td className="px-2 py-1">
                        {j.nfeInfo?.emitente ?? "?"}
                        {j.nfeInfo?.cnpjEmitente ? ` (${j.nfeInfo.cnpjEmitente})` : ""}
                      </td>
                      <td className="px-2 py-1">
                        {j.status === "ok" && <span className="text-emerald-300">OK</span>}
                        {j.status === "erro" && <span className="text-red-400">Erro {j.error ? `- ${j.error}` : ""}</span>}
                        {j.status === "importando" && <span className="text-amber-300">Importando...</span>}
                        {j.status === "importado" && (
                          <span className="text-emerald-300">{j.error ? `Importada (${j.error})` : "Importada"}</span>
                        )}
                      </td>
                      <td className="px-2 py-1 text-center">
                        <button
                          onClick={() => removeJob(j.id)}
                          className="px-2 py-1 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                        >
                          Remover
                        </button>
                      </td>
                    </tr>
                  ))}
                  {jobs.length === 0 && (
                    <tr>
                      <td colSpan={8} className="px-2 py-3 text-center text-zinc-400">
                        Nenhum XML na fila.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
          )}

          {hasSelectedNfeInfo && selectedJob?.nfeInfo && (
            <div
              className={
                selectedJobAlreadyImported
                  ? "border border-amber-500/40 rounded-lg bg-amber-500/10 p-3 space-y-3"
                  : selectedJobHasError
                    ? "border border-red-500/40 rounded-lg bg-red-500/10 p-3 space-y-3"
                    : "border border-zinc-800 rounded-lg p-3 space-y-3"
              }
            >
              <div>
                <div className="font-semibold text-zinc-100">
                  {selectedJobAlreadyImported
                    ? "Esta NF-e já foi importada."
                    : selectedJobHasError
                      ? "XML com erro"
                      : "Dados básicos da NF"}
                </div>
                {selectedJobAlreadyImported && (
                  <div className="text-sm text-amber-200">
                    NF-e já importada. Escolha outro XML ou abra a nota na lista de notas importadas.
                  </div>
                )}
                {selectedJobHasError && (
                  <div className="text-sm text-red-200">{selectedJob.error ?? "Nao foi possivel validar este XML."}</div>
                )}
              </div>
              {renderNfeResumo(selectedJob.nfeInfo, selectedJob.itens.length)}
            </div>
          )}

          {shouldShowImportForm && !fornecedorResolvido && (
            <div className="border border-zinc-800 rounded-lg p-3 text-sm text-zinc-300 space-y-2">
              <div className="flex items-center justify-between">
                <div>
                  <div className="font-semibold text-zinc-100">Fornecedor</div>
                  <div className="text-xs text-zinc-400">Valida por CNPJ</div>
                </div>

                {selectedJob?.nfeInfo?.cnpjEmitente && (
                  <Can perm="cad_fornecedores.write">
                    <button
                      onClick={() => {
                        if (!finalidadeLote) {
                          setImportErr("Selecione a finalidade antes de cadastrar fornecedor.");
                          return;
                        }
                        void criarFornecedor(
                          selectedJob.nfeInfo!.cnpjEmitente!,
                          selectedJob.nfeInfo!.emitente ?? "Fornecedor NF",
                          (finalidadeLote as ItemFinalidade)
                        );
                      }}
                      disabled={importBusy}
                      className="px-3 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
                    >
                      Cadastrar fornecedor
                    </button>
                  </Can>
                )}
              </div>

              {selectedJob?.nfeInfo?.cnpjEmitente && (
                <div className="text-sm">
                  CNPJ: {selectedJob.nfeInfo.cnpjEmitente}{" "}
                  {fornecedorNome ? `Encontrado: ${fornecedorNome}` : "Nao cadastrado"}
                </div>
              )}
            </div>
          )}

          {shouldShowItens && (
          <div className="border border-zinc-800 rounded-lg p-3 flex flex-col gap-2">
            <div className="flex items-center justify-between">
              <div className="font-semibold text-zinc-100">Itens da NF</div>
              <div className="text-xs text-zinc-400">Itens faltantes recebem sugestão do agente antes do cadastro.</div>
            </div>

            <div className="overflow-x-auto">
              <div className="max-h-[55vh] overflow-auto rounded-lg border border-zinc-800">
                <table className="w-full text-sm">
                  <thead className="bg-zinc-900/60 text-zinc-200 sticky top-0">
                    <tr>
                      <th className="px-3 py-2 text-left">Codigo</th>
                      <th className="px-3 py-2 text-left">Descricao NF</th>
                      <th className="px-3 py-2 text-right">Qtd</th>
                      <th className="px-3 py-2 text-right">V.Unit</th>
                      <th className="px-3 py-2 text-right">Total</th>
                      <th className="px-3 py-2 text-center">Status</th>
                      <th className="px-3 py-2 text-center">Acoes</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-zinc-800">
                    {itensParaTabela.map((it, idx) => {
                      const foundItem = getItemCodigoFromMap(itemMap, it.codigo);
                      const normalizacaoCadastro = normalizacoesCadastro[normalizeItemCodigo(it.codigo)] ?? null;
                      const itemAnalysis = xmlImportAnalysis?.itemSuggestions.find((item) => item.index === idx) ?? null;
                      const pedidosSugeridos = xmlImportAnalysis?.pedidoSuggestions ?? [];
                      const fallbackPedido = pedidosSugeridos.length === 1 ? pedidosSugeridos[0] : xmlImportAnalysis?.pedidoSuggestion ?? null;
                      const pedidoLinkId = itemAnalysis?.pedidoMatchPedidoId ?? fallbackPedido?.pedidoId ?? null;
                      const pedidoLink = pedidosAnalyzerComItens.find((pedido) => pedido.id === pedidoLinkId) ?? null;
                      const hasManualPedidoItems = Boolean(pedidoLink?.itens?.some(isPedidoItemManualParaVinculo));
                      const canOpenPedidoLink = Boolean(pedidoLinkId && hasManualPedidoItems);
                      return (
                        <tr key={`${it.codigo}-${idx}`} className="hover:bg-zinc-900/40">
                          <td className="px-3 py-2 font-medium">{it.codigo}</td>
                          <td className="px-3 py-2 align-top">
                            <textarea
                              className="w-full px-2 py-2 bg-zinc-900 border border-zinc-700 rounded min-h-[64px] text-sm leading-snug"
                              aria-label={`Descricao NF do item ${it.codigo}`}
                              title={`Descricao NF do item ${it.codigo}`}
                              value={it.overrideNome ?? it.nome}
                              onChange={(e) => {
                                const value = e.target.value;
                                const codigo = normalizeItemCodigo(it.codigo);
                                setNormalizacoesCadastro((prev) => {
                                  if (!prev[codigo]) return prev;
                                  const next = { ...prev };
                                  delete next[codigo];
                                  return next;
                                });
                                setJobs((prev) =>
                                  prev.map((j) =>
                                    j.id === selectedJobId
                                      ? {
                                          ...j,
                                          itens: j.itens.map((p) => (p.codigo === it.codigo ? { ...p, overrideNome: value } : p)),
                                        }
                                      : j
                                  )
                                );
                              }}
                            />
                            {!foundItem && normalizacaoCadastro && (
                              <div className="mt-2 rounded-md border border-sky-500/35 bg-sky-500/10 px-2 py-2 text-xs text-sky-100 space-y-1">
                                <div className="font-medium text-sky-200">Sugestão do agente de cadastro · confiança {normalizacaoCadastro.confianca}</div>
                                <div>
                                  <span className="text-sky-300">Nome: </span>
                                  {normalizacaoCadastro.descricao_padronizada || "Sem descrição segura"}
                                </div>
                                <div>
                                  <span className="text-sky-300">Grupo: </span>
                                  {normalizacaoCadastro.grupo_caminho ??
                                    (normalizacaoCadastro.novo_grupo
                                      ? `Novo grupo sugerido: ${normalizacaoCadastro.novo_grupo.nome}`
                                      : "Revisão necessária")}
                                </div>
                                {normalizacaoCadastro.novo_grupo && (
                                  <div className="text-sky-100/90">
                                    {normalizacaoCadastro.novo_grupo.justificativa}
                                  </div>
                                )}
                                <div className="text-sky-100/90">{normalizacaoCadastro.justificativa}</div>
                                {normalizacaoCadastro.dados_pendentes.length > 0 && (
                                  <div className="text-amber-200">
                                    Pendente: {normalizacaoCadastro.dados_pendentes.join("; ")}
                                  </div>
                                )}
                              </div>
                            )}
                          </td>
                          <td className="px-3 py-2 text-right tabular-nums">{formatDecimalBR(it.quantidade, 3)}</td>
                          <td className="px-3 py-2 text-right tabular-nums">R$ {it.valorUnit.toFixed(2)}</td>
                          <td className="px-3 py-2 text-right tabular-nums">R$ {it.total.toFixed(2)}</td>
                          <td className="px-3 py-2 text-center">
                            {!permiteVincularItens ? (
                              <span className="inline-flex items-center px-2 py-1 rounded-md border border-zinc-600/50 text-zinc-300 text-xs">
                                {finalidadeLote === "imobilizado"
                                  ? "Cadastro imobilizado"
                                  : finalidadeLote === "consumo"
                                    ? "Cadastro consumo"
                                    : `Nao cadastrado (${finalidadeLote || "sem finalidade"})`}
                              </span>
                            ) : foundItem ? (
                              <span className="inline-flex items-center px-2 py-1 rounded-md border border-emerald-500/40 text-emerald-300 text-xs">
                                Cadastrado (id {foundItem.id})
                              </span>
                            ) : (
                              <span className="inline-flex items-center px-2 py-1 rounded-md border border-amber-500/40 text-amber-300 text-xs">
                                Nao encontrado
                              </span>
                            )}
                          </td>
                          <td className="px-3 py-2 text-center">
                            {canOpenPedidoLink ? (
                              <button
                                type="button"
                                onClick={() => abrirVinculoItemPedidoDaTabela(it, idx)}
                                className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs"
                                title="Abre o vinculo entre o item do XML e um item manual do pedido."
                              >
                                Vincular
                              </button>
                            ) : (
                              permiteAutoCadastrarItens && !foundItem && (
                              <Can perm="cad_itens.write">
                                <button
                                  onClick={() => void cadastrarItemComIA(it)}
                                  disabled={
                                    cadBusy ||
                                    normalizacaoCadastroBusy ||
                                    Boolean(normalizacaoCadastro && !normalizacaoCadastro.grupo_id && !normalizacaoCadastro.novo_grupo)
                                  }
                                  className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs"
                                  title={
                                    normalizacaoCadastro && !normalizacaoCadastro.grupo_id && !normalizacaoCadastro.novo_grupo
                                      ? "A sugestão precisa de revisão antes do cadastro."
                                      : undefined
                                  }
                                >
                                  {normalizacaoCadastroBusy
                                    ? "Analisando IA..."
                                    : normalizacaoCadastro
                                      ? normalizacaoCadastro.novo_grupo
                                        ? "Criar grupo e cadastrar IA"
                                        : "Cadastrar sugestão IA"
                                      : "Sugerir com IA"}
                                </button>
                              </Can>
                              )
                            )}
                          </td>
                        </tr>
                      );
                    })}
                    {itensParaTabela.length === 0 && (
                      <tr>
                        <td colSpan={8} className="px-3 py-4 text-zinc-400 text-center">
                          Nenhum item lido ainda.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>

            {importErr && <div className="text-sm text-red-400">{importErr}</div>}
            {importWarn && <div className="text-sm text-amber-300">{importWarn}</div>}
            {importOk && <div className="text-sm text-emerald-300">{importOk}</div>}
          </div>
          )}
        </div>

        {shouldShowImportActions && (
        <div className="px-5 py-3 border-t border-zinc-800 bg-zinc-950 flex justify-end gap-2">
          {showBulkItemRegistrationButton && (
            <button
              onClick={() => void cadastrarFornecedorEItens()}
              disabled={cadBusy || normalizacaoCadastroBusy || importBusy || isReading || bloqueiaCadastroItens}
              className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-zinc-100"
              title={!fornecedorResolvido ? "Cadastre/identifique o fornecedor para cadastrar itens." : undefined}
            >
              {cadBusy
                ? "Cadastrando..."
                : normalizacaoCadastroBusy
                  ? "Analisando com IA..."
                  : loteMissing.some((codigo) => Boolean(normalizacoesCadastro[normalizeItemCodigo(codigo)]))
                    ? "Cadastrar sugestões IA"
                    : "Sugerir itens com IA"}
            </button>
          )}

          <button
            onClick={abrirModalPagamento}
            disabled={isReading || importBusy || bloqueiaImportacao || !canImport}
            className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
          >
            {importBusy ? "Importando..." : "Importar"}
          </button>
        </div>
        )}
      </div>

      <div className="order-4 border border-zinc-800 rounded-xl bg-zinc-950 p-4 space-y-3">
        <div className="flex items-end justify-between gap-3 flex-wrap">
          <div>
            <div className="text-lg font-semibold">Notas importadas</div>
            <div className="text-sm text-zinc-400">
              Exibindo as 20 últimas notas importadas. Use os filtros para consultar ou imprimir a mesma seleção.
            </div>
          </div>
          <div className="flex items-end justify-end gap-2 flex-wrap">
            <label className="h-10 px-3 rounded-md border border-zinc-700 bg-zinc-900 text-xs text-zinc-300 flex items-center gap-2">
              <input
                id="recent-notas-usar-data"
                type="checkbox"
                className="h-4 w-4 accent-emerald-500"
                checked={recentUseDateFilter}
                onChange={(e) => setRecentUseDateFilter(e.target.checked)}
                disabled={recentControlsDisabled}
              />
              Usar data
            </label>

            <div className="flex items-center gap-2">
              <label className="text-xs text-zinc-400" htmlFor="recent-notas-mes">
                Mês
              </label>
              <select
                id="recent-notas-mes"
                className="px-2 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-sm"
                value={recentFilterMonth}
                onChange={(e) => setRecentFilterMonth(e.target.value)}
                disabled={recentDateFieldsDisabled}
                title="Filtrar por mês de emissão"
              >
                {Array.from({ length: 12 }).map((_, idx) => {
                  const m = idx + 1;
                  return (
                    <option key={m} value={String(m)}>
                      {String(m).padStart(2, "0")}
                    </option>
                  );
                })}
              </select>
            </div>

            <div className="flex items-center gap-2">
              <label className="text-xs text-zinc-400" htmlFor="recent-notas-ano">
                Ano
              </label>
              <input
                id="recent-notas-ano"
                name="recent-notas-ano"
                className="w-[92px] px-2 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-sm"
                value={recentFilterYear}
                onChange={(e) => setRecentFilterYear(e.target.value.replace(/[^0-9]/g, "").slice(0, 4))}
                disabled={recentDateFieldsDisabled}
                inputMode="numeric"
                autoComplete="off"
                placeholder="YYYY"
                title="Filtrar por ano de emissão"
              />
            </div>

            <div className="flex items-center gap-2">
              <label className="text-xs text-zinc-400" htmlFor="recent-notas-emitente">
                Emitente
              </label>
              <input
                id="recent-notas-emitente"
                name="recent-notas-emitente"
                type="search"
                className="w-[240px] px-2 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-sm"
                value={recentFilterEmitente}
                onChange={(e) => setRecentFilterEmitente(e.target.value)}
                disabled={recentControlsDisabled}
                autoComplete="off"
                placeholder="Nome do emitente"
                title="Filtrar por emitente"
              />
            </div>

            <div className="flex items-center gap-2">
              <label className="text-xs text-zinc-400" htmlFor="recent-notas-numero">
                Número
              </label>
              <input
                id="recent-notas-numero"
                name="recent-notas-numero-nf"
                type="search"
                className="w-[110px] px-2 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-sm"
                value={recentFilterNumero}
                onChange={(e) => setRecentFilterNumero(e.target.value.slice(0, 20))}
                disabled={recentControlsDisabled}
                autoComplete="off"
                placeholder="NF"
                title="Filtrar por número"
              />
            </div>

            <button
              type="button"
              onClick={() => {
                setRecentUseDateFilter(false);
                setRecentFilterEmitente("");
                setRecentFilterNumero("");
              }}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm disabled:opacity-60"
              disabled={recentControlsDisabled || !hasRecentFilters}
            >
              Limpar
            </button>

            <button
              type="button"
              onClick={() => {
                const params = new URLSearchParams();
                if (recentUseDateFilter) {
                  params.set("periodo", "1");
                  params.set("mes", recentFilterMonth);
                  params.set("ano", recentFilterYear);
                }
                const emitente = recentFilterEmitente.trim();
                const numero = recentFilterNumero.trim();
                if (emitente) params.set("emitente", emitente);
                if (numero) params.set("numero", numero);
                const query = params.toString();
                window.open(`/estoque/importar/imprimir${query ? `?${query}` : ""}`, "_blank");
              }}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
              disabled={recentActionsDisabled}
            >
              Imprimir
            </button>

            <button
              type="button"
              onClick={() => setRecentReloadTick((n) => n + 1)}
              className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-sm"
              disabled={recentActionsDisabled}
            >
              {recentNfsLoading ? "Atualizando..." : "Atualizar"}
            </button>
          </div>
        </div>

        {recentNfsError ? (
          <div className="rounded-md border border-rose-900/60 bg-rose-950/30 px-3 py-2 text-sm text-rose-200">{recentNfsError}</div>
        ) : null}

        <div className="border border-zinc-800 rounded-lg overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/70">
              <tr className="text-zinc-200">
                <th className="px-3 py-2 text-left">Emissão</th>
                <th className="px-3 py-2 text-left">Série/Número</th>
                <th className="px-3 py-2 text-left">Emitente</th>
                <th className="px-3 py-2 text-left">Finalidade</th>
                <th className="px-3 py-2 text-left">Chave</th>
                <th className="px-3 py-2 text-right">Valor</th>
                <th className="px-3 py-2 text-center">Ação</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800">
              {recentNfsLoading ? (
                <tr>
                  <td colSpan={7} className="px-3 py-4 text-zinc-400 text-center">
                    Carregando...
                  </td>
                </tr>
              ) : recentNfs.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-3 py-4 text-zinc-400 text-center">
                    Nenhuma nota encontrada.
                  </td>
                </tr>
              ) : (
                recentNfs.map((nf) => {
                  const emissao = toDateOnly(nf.data_emissao ?? "") ?? "";
                  const serieNum = `${nf.serie ?? "—"} / ${nf.numero ?? "—"}`;
                  const chaveShort =
                    nf.chave && nf.chave.length > 18 ? `${nf.chave.slice(0, 8)}...${nf.chave.slice(-8)}` : nf.chave;
                  const isOpening = openingNfEntradaId === nf.id;
                  const canOpen = Boolean(tenantId && empresaId) && !isOpening;

                  return (
                    <tr
                      key={nf.id}
                      className={`hover:bg-zinc-900/40 ${canOpen ? "cursor-pointer" : "opacity-60"}`}
                      role="button"
                      tabIndex={canOpen ? 0 : -1}
                      onClick={() => {
                        if (!canOpen) return;
                        void abrirNotaImportada(nf);
                      }}
                      onKeyDown={(e) => {
                        if (!canOpen) return;
                        if (e.key === "Enter" || e.key === " ") {
                          e.preventDefault();
                          void abrirNotaImportada(nf);
                        }
                      }}
                    >
                      <td className="px-3 py-2">{formatDateBR(emissao) || "—"}</td>
                      <td className="px-3 py-2">{serieNum}</td>
                      <td className="px-3 py-2">{nf.emitente_nome ?? "—"}</td>
                      <td className="px-3 py-2">{formatFinalidadeImportada(nf.finalidade_contexto)}</td>
                      <td className="px-3 py-2 font-mono text-xs">{chaveShort || "—"}</td>
                      <td className="px-3 py-2 text-right tabular-nums">R$ {formatMoneyBR(Number(nf.valor_total ?? 0))}</td>
                      <td className="px-3 py-2 text-center">
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            void abrirNotaImportada(nf);
                          }}
                          disabled={!canOpen}
                          className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 text-xs disabled:opacity-60"
                        >
                          {isOpening ? "Abrindo..." : "Abrir"}
                        </button>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      {pedidoItemLink && (
        <div
          className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 overflow-y-auto"
          onClick={(e) => e.target === e.currentTarget && fecharVinculoItemPedido()}
        >
          <div className="min-h-full w-full flex items-start sm:items-center justify-center p-4 py-6">
            <div className="w-full max-w-4xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl max-h-[90vh] flex flex-col overflow-hidden">
              <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between gap-3">
                <div>
                  <div className="text-lg font-semibold">Vincular item manual do pedido</div>
                  <div className="text-sm text-zinc-400">
                    Corrige somente o cadastro vinculado ao item manual. Nao altera quantidade, valor, status, estoque ou NF.
                  </div>
                </div>
                <button
                  type="button"
                  onClick={fecharVinculoItemPedido}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                  disabled={pedidoItemLinkBusy}
                >
                  Fechar
                </button>
              </div>

              <div className="px-5 py-4 space-y-4 flex-1 min-h-0 overflow-auto">
                {!pedidoItemLinkData?.pedido && (
                  <div className="rounded-md border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-200">
                    Dados do pedido candidato nao estao carregados. Releia o XML ou aguarde a busca de pedidos candidatos.
                  </div>
                )}

                {!pedidoItemLinkData?.internalItem && (
                  <div className="rounded-md border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-200">
                    {pedidoItemLinkPodeCadastrar
                      ? "Este item ainda nao tem cadastro interno. Ao confirmar, o sistema vai cadastrar o item e vincular ao item manual escolhido."
                      : "Este item da NF ainda nao tem cadastro interno. Cadastre o item antes de vincular ao pedido."}
                  </div>
                )}

                <div className="grid gap-3 md:grid-cols-2">
                  <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 p-3">
                    <div className="text-sm font-semibold text-zinc-100">Item da NF</div>
                    <div className="mt-2 space-y-1 text-sm text-zinc-300">
                      <div><span className="text-zinc-500">Codigo: </span>{pedidoItemLink.codigoOriginal || "-"}</div>
                      <div><span className="text-zinc-500">Descricao: </span>{pedidoItemLink.descricao || "-"}</div>
                      <div>
                        <span className="text-zinc-500">Quantidade: </span>
                        {formatDecimalBR(Number(pedidoItemLinkData?.nfItem?.quantidade ?? pedidoItemLinkData?.itemSuggestion?.quantidade ?? 0))}
                      </div>
                      <div>
                        <span className="text-zinc-500">Valor unitario: </span>
                        R$ {formatMoneyBR(Number(pedidoItemLinkData?.nfItem?.valorUnit ?? pedidoItemLinkData?.itemSuggestion?.valorUnitario ?? 0))}
                      </div>
                    </div>
                  </div>

                  <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 p-3">
                    <div className="text-sm font-semibold text-zinc-100">Cadastro interno</div>
                    {pedidoItemLinkData?.internalItem ? (
                      <div className="mt-2 space-y-1 text-sm text-zinc-300">
                        <div><span className="text-zinc-500">ID: </span>{pedidoItemLinkData.internalItem.id}</div>
                        <div><span className="text-zinc-500">Codigo: </span>{pedidoItemLinkData.internalItem.codigo_interno || "-"}</div>
                        <div><span className="text-zinc-500">Nome: </span>{pedidoItemLinkData.internalItem.nome ?? pedidoItemLinkData.internalItem.descricao ?? "-"}</div>
                      </div>
                    ) : (
                      <div className="mt-2 text-sm text-zinc-500">
                        {pedidoItemLinkPodeCadastrar
                          ? "Sera criado a partir dos dados do XML ao confirmar."
                          : "Nenhum cadastro interno encontrado para este codigo."}
                      </div>
                    )}
                  </div>
                </div>

                <div className="rounded-lg border border-zinc-800 bg-zinc-900/30 p-3">
                  <div className="text-sm font-semibold text-zinc-100">Pedido sugerido</div>
                  <div className="mt-2 text-sm text-zinc-300">
                    {pedidoItemLink.pedidoCodigo ?? pedidoItemLinkData?.pedido?.codigo ?? pedidoItemLink.pedidoId}
                  </div>
                </div>

                <div className="rounded-lg border border-zinc-800 overflow-hidden">
                  <div className="bg-zinc-900/70 px-3 py-2 text-sm font-semibold text-zinc-100">
                    Escolha o item manual do pedido
                  </div>
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead className="bg-zinc-900/60 text-zinc-300">
                        <tr>
                          <th className="px-3 py-2 text-left">Selecionar</th>
                          <th className="px-3 py-2 text-left">Seq</th>
                          <th className="px-3 py-2 text-left">Descricao manual</th>
                          <th className="px-3 py-2 text-left">OS</th>
                          <th className="px-3 py-2 text-right">Score</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-zinc-800">
                        {(pedidoItemLinkData?.manualItems ?? []).map((item) => {
                          const osLabel = item.origem_os_label ?? (item.origem_os_numero ? `OS ${item.origem_os_numero}` : item.origem_os_id ? `OS ${item.origem_os_id}` : "-");
                          return (
                            <tr key={item.id} className="hover:bg-zinc-900/40">
                              <td className="px-3 py-2">
                                <input
                                  type="radio"
                                  name="pedido-item-manual-link"
                                  checked={(pedidoItemLinkSelectedId || pedidoItemLink.pedidoItemId) === item.id}
                                  onChange={() => setPedidoItemLinkSelectedId(item.id)}
                                />
                              </td>
                              <td className="px-3 py-2">{item.seq ?? "-"}</td>
                              <td className="px-3 py-2">{item.item_nome ?? item.descricao ?? "-"}</td>
                              <td className="px-3 py-2">{osLabel}</td>
                              <td className="px-3 py-2 text-right tabular-nums">
                                {item.id === pedidoItemLink.pedidoItemId && pedidoItemLinkData?.itemSuggestion?.pedidoMatchScore
                                  ? `${pedidoItemLinkData.itemSuggestion.pedidoMatchScore}/100`
                                  : "-"}
                              </td>
                            </tr>
                          );
                        })}
                        {(pedidoItemLinkData?.manualItems ?? []).length === 0 && (
                          <tr>
                            <td colSpan={5} className="px-3 py-4 text-zinc-400">
                              Nenhum item manual disponivel neste pedido.
                            </td>
                          </tr>
                        )}
                      </tbody>
                    </table>
                  </div>
                </div>

                {pedidoItemLinkError && (
                  <div className="rounded-md border border-red-500/40 bg-red-500/10 px-3 py-2 text-sm text-red-200">
                    {pedidoItemLinkError}
                  </div>
                )}
              </div>

              <div className="px-5 py-4 border-t border-zinc-800 flex flex-wrap items-center justify-end gap-2">
                <button
                  type="button"
                  onClick={fecharVinculoItemPedido}
                  className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                  disabled={pedidoItemLinkBusy}
                >
                  Cancelar
                </button>
                <button
                  type="button"
                  onClick={() => void confirmarVinculoItemPedido()}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium disabled:opacity-60"
                  disabled={
                    pedidoItemLinkBusy ||
                    (!pedidoItemLinkData?.internalItem && !pedidoItemLinkPodeCadastrar) ||
                    !(pedidoItemLinkSelectedId || pedidoItemLink.pedidoItemId)
                  }
                >
                  {pedidoItemLinkBusy
                    ? "Vinculando..."
                    : pedidoItemLinkData?.internalItem
                      ? "Confirmar vinculo"
                      : "Cadastrar e vincular"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {showPagamentoModal && (
        <div
          className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 overflow-y-auto"
          onClick={(e) => e.target === e.currentTarget && fecharModalPagamento()}
        >
          <div className="min-h-full w-full flex items-start sm:items-center justify-center p-4 py-6">
            <div className="w-full max-w-3xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl max-h-[90vh] flex flex-col overflow-hidden">
              <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
                <div>
                  <div className="text-lg font-semibold">Forma de pagamento</div>
                  <div className="text-sm text-zinc-400">
                    Defina como montar as parcelas antes de importar a NF para contas a pagar.
                  </div>
                </div>
                <button
                  type="button"
                  onClick={fecharModalPagamento}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                  disabled={importBusy}
                >
                  Fechar
                </button>
              </div>

              <div className="px-5 py-4 space-y-4 flex-1 min-h-0 overflow-auto">
                {!fornecedorGerarContasAuto && (
                  <div className="rounded-md border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-200">
                    Fornecedor com contas a pagar automatico = Nao. A importacao segue normal, mas as parcelas nao serao aplicadas.
                  </div>
                )}

                <fieldset className="space-y-2">
                  <legend className="text-sm text-zinc-300 mb-2">Selecione a forma</legend>

                  <label className="flex items-start gap-3 rounded-md border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                    <input
                      type="radio"
                      name="pagamento-forma"
                      checked={pagamentoModo === "seguir_nota"}
                      autoFocus
                      onChange={() => {
                        setPagamentoModo("seguir_nota");
                        setPagamentoModalErr(null);
                      }}
                      className="mt-1"
                    />
                    <div>
                      <div className="font-medium text-zinc-100">Seguir nota</div>
                      <div className="text-xs text-zinc-400">Usa as duplicatas do XML (quando existirem).</div>
                    </div>
                  </label>

                  <label className="flex items-start gap-3 rounded-md border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                    <input
                      type="radio"
                      name="pagamento-forma"
                      checked={pagamentoModo === "cartao"}
                      onChange={() => {
                        setPagamentoModo("cartao");
                        setPagamentoModalErr(null);
                      }}
                      className="mt-1"
                    />
                    <div>
                      <div className="font-medium text-zinc-100">Cartao</div>
                      <div className="text-xs text-zinc-400">
                        Informe o numero de parcelas. Primeira parcela sempre no dia 09 do mes seguinte.
                      </div>
                    </div>
                  </label>

                  <label className="flex items-start gap-3 rounded-md border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                    <input
                      type="radio"
                      name="pagamento-forma"
                      checked={pagamentoModo === "dinheiro"}
                      onChange={() => {
                        setPagamentoModo("dinheiro");
                        setPagamentoModalErr(null);
                      }}
                      className="mt-1"
                    />
                    <div>
                      <div className="font-medium text-zinc-100">Dinheiro</div>
                      <div className="text-xs text-zinc-400">Parcela unica a vista.</div>
                    </div>
                  </label>

                  <label className="flex items-start gap-3 rounded-md border border-zinc-800 bg-zinc-900/30 px-3 py-2">
                    <input
                      type="radio"
                      name="pagamento-forma"
                      checked={pagamentoModo === "faturado"}
                      onChange={() => {
                        setPagamentoModo("faturado");
                        setPagamentoModalErr(null);
                      }}
                      className="mt-1"
                    />
                    <div>
                      <div className="font-medium text-zinc-100">Faturado (entrada manual)</div>
                      <div className="text-xs text-zinc-400">
                        Defina quantidade, valores e datas de vencimento manualmente.
                      </div>
                    </div>
                  </label>
                </fieldset>

                {pagamentoModo === "seguir_nota" && (
                  <div className="rounded-md border border-zinc-800 bg-zinc-900/30 p-3 space-y-2">
                    <div className="text-sm text-zinc-300">
                      {selectedOkJobs.length > 1
                        ? "Visualizacao do primeiro XML selecionado:"
                        : "Parcelas encontradas no XML selecionado:"}
                    </div>
                    {pagamentoPreviewParcelasXml.length > 0 ? (
                      <div className="border border-zinc-800 rounded-md overflow-hidden">
                        <table className="w-full text-xs">
                          <thead className="bg-zinc-900/70 text-zinc-200">
                            <tr>
                              <th className="px-2 py-1 text-left">Parcela</th>
                              <th className="px-2 py-1 text-left">Vencimento</th>
                              <th className="px-2 py-1 text-right">Valor</th>
                            </tr>
                          </thead>
                          <tbody className="divide-y divide-zinc-800">
                            {pagamentoPreviewParcelasXml.map((parcela) => (
                              <tr key={`${parcela.numero}-${parcela.vencimento}`}>
                                <td className="px-2 py-1">{parcela.numero}</td>
                                <td className="px-2 py-1">{formatDateBR(parcela.vencimento)}</td>
                                <td className="px-2 py-1 text-right tabular-nums">R$ {formatMoneyBR(parcela.valor)}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    ) : (
                      <div className="text-xs text-zinc-400">
                        XML sem duplicatas. Se contas a pagar automatico estiver ativo, sera gerada parcela unica.
                      </div>
                    )}
                  </div>
                )}

                {pagamentoModo === "cartao" && (
                  <div className="rounded-md border border-zinc-800 bg-zinc-900/30 p-3 space-y-3">
                    <label className="flex flex-col gap-1 max-w-[240px]">
                      <span className="text-sm text-zinc-300">Quantidade de parcelas</span>
                      <input
                        type="number"
                        min={1}
                        max={60}
                        step={1}
                        value={pagamentoParcelasQtd}
                        onChange={(e) => setPagamentoParcelasQtd(clampParcelas(Number(e.target.value || 1)))}
                        className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                      />
                    </label>

                    {cartaoPreviewParcelas.length > 0 && (
                      <div className="border border-zinc-800 rounded-md overflow-hidden">
                        <table className="w-full text-xs">
                          <thead className="bg-zinc-900/70 text-zinc-200">
                            <tr>
                              <th className="px-2 py-1 text-left">Parcela</th>
                              <th className="px-2 py-1 text-left">Vencimento</th>
                              <th className="px-2 py-1 text-right">Valor</th>
                            </tr>
                          </thead>
                          <tbody className="divide-y divide-zinc-800">
                            {cartaoPreviewParcelas.map((parcela) => (
                              <tr key={`${parcela.numero}-${parcela.vencimento}`}>
                                <td className="px-2 py-1">{parcela.numero}</td>
                                <td className="px-2 py-1">{formatDateBR(parcela.vencimento)}</td>
                                <td className="px-2 py-1 text-right tabular-nums">R$ {formatMoneyBR(parcela.valor)}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    )}
                  </div>
                )}

                {pagamentoModo === "dinheiro" && (
                  <div className="rounded-md border border-zinc-800 bg-zinc-900/30 px-3 py-2 text-xs text-zinc-300">
                    Sera criada uma unica parcela (001) com o valor total da nota.
                  </div>
                )}

                {pagamentoModo === "faturado" && (
                  <div className="rounded-md border border-zinc-800 bg-zinc-900/30 p-3 space-y-3">
                    <label className="flex flex-col gap-1 max-w-[240px]">
                      <span className="text-sm text-zinc-300">Quantidade de pagamentos</span>
                      <input
                        type="number"
                        min={1}
                        max={60}
                        step={1}
                        value={pagamentoParcelasQtd}
                        onChange={(e) => setPagamentoParcelasQtd(clampParcelas(Number(e.target.value || 1)))}
                        className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                      />
                    </label>

                    {selectedOkJobs.length > 1 && (
                      <div className="text-xs text-amber-300">
                        Para faturado manual, selecione apenas um XML por importacao.
                      </div>
                    )}

                    <div className="space-y-2">
                      {faturadoParcelasForm.slice(0, clampParcelas(pagamentoParcelasQtd)).map((row, idx) => (
                        <div key={row.numero} className="grid grid-cols-1 md:grid-cols-3 gap-2">
                          <div className="px-3 py-2 rounded-md border border-zinc-800 bg-zinc-900 text-sm text-zinc-300">
                            Parcela {row.numero}
                          </div>
                          <input
                            type="text"
                            inputMode="decimal"
                            placeholder="Valor (ex: 1500,00)"
                            value={row.valor}
                            onChange={(e) =>
                              setFaturadoParcelasForm((prev) =>
                                prev.map((item, pidx) => (pidx === idx ? { ...item, valor: e.target.value } : item))
                              )
                            }
                            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                          />
                          <input
                            type="date"
                            value={row.vencimento}
                            onChange={(e) =>
                              setFaturadoParcelasForm((prev) =>
                                prev.map((item, pidx) => (pidx === idx ? { ...item, vencimento: e.target.value } : item))
                              )
                            }
                            className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                          />
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {pagamentoModalErr && <div className="text-sm text-red-400">{pagamentoModalErr}</div>}
              </div>

              <div className="px-5 py-3 border-t border-zinc-800 bg-zinc-950 flex justify-end gap-2">
                <button
                  type="button"
                  onClick={fecharModalPagamento}
                  className="px-4 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                  disabled={importBusy}
                >
                  Cancelar
                </button>
                <button
                  type="button"
                  onClick={() => void confirmarPagamentoEImportar()}
                  className="px-4 py-2 rounded-md bg-zinc-100 text-zinc-900 hover:bg-white font-medium"
                  disabled={importBusy}
                >
                  {importBusy ? "Importando..." : "Confirmar e importar"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {showOsLookup && (
        <div
          className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 overflow-y-auto"
          onClick={(e) => e.target === e.currentTarget && closeOsLookup()}
        >
          <div className="min-h-full w-full flex items-start sm:items-center justify-center p-4 py-6">
            <div className="w-full max-w-2xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl max-h-[90vh] flex flex-col overflow-hidden">
              <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
                <div>
                  <div className="text-lg font-semibold">Buscar OS</div>
                  <div className="text-sm text-zinc-400">Digite numero da OS ou cliente para buscar.</div>
                </div>
                <button
                  onClick={closeOsLookup}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                >
                  Fechar
                </button>
              </div>

              <div className="px-5 py-4 space-y-3 flex-1 min-h-0 overflow-auto">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Buscar</div>
                  <input
                    value={osLookupTerm}
                    onChange={(e) => {
                      const value = e.target.value;
                      setOsLookupTerm(value);
                      if (osLookupDebounceRef.current) clearTimeout(osLookupDebounceRef.current);
                      osLookupDebounceRef.current = setTimeout(() => {
                        void loadOsLookup(value);
                      }, 300);
                    }}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        void loadOsLookup(osLookupTerm);
                      }
                    }}
                    placeholder="Ex: 43 ou nome do cliente"
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                    autoFocus
                  />
                </div>

                {osLookupLoading && <div className="text-sm text-zinc-400">Buscando...</div>}
                {osLookupError && <div className="text-sm text-red-400">{osLookupError}</div>}

                <div className="border border-zinc-800 rounded-lg overflow-hidden">
                  <table className="w-full text-sm">
                    <thead className="bg-zinc-900/70">
                      <tr className="text-zinc-200">
                        <th className="px-3 py-2 text-left">OS</th>
                        <th className="px-3 py-2 text-left">Cliente</th>
                        <th className="px-3 py-2 text-left">Descricao</th>
                        <th className="px-3 py-2 text-center">Acao</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-zinc-800">
                      {osLookupRows.map((row) => (
                        <tr key={row.id} className="hover:bg-zinc-900/40">
                          <td className="px-3 py-2">{row.numero_os ?? row.id}</td>
                          <td className="px-3 py-2">{row.cliente_nome ?? "-"}</td>
                          <td className="px-3 py-2">{row.descricao_servico ?? "-"}</td>
                          <td className="px-3 py-2 text-center">
                            <button
                              type="button"
                              onClick={() => {
                                const numero = row.numero_os ?? String(row.id);
                                setOsNumero(numero);
                                setOsId(Number(row.id));
                                setOsLabel(`OS ${numero} - ${(row.cliente_nome ?? "-")}`);
                                setOsError(null);
                                aplicarMotivoAutomatico({ origem: "os", temOs: true });
                                closeOsLookup();
                              }}
                              className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                            >
                              Selecionar
                            </button>
                          </td>
                        </tr>
                      ))}
                      {!osLookupLoading && osLookupRows.length === 0 && osLookupTerm.trim() !== "" && (
                        <tr>
                          <td colSpan={4} className="px-3 py-4 text-zinc-400">
                            Nenhuma OS encontrada.
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {showPedidoLookup && (
        <div
          className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 overflow-y-auto"
          onClick={(e) => e.target === e.currentTarget && closePedidoLookup()}
        >
          <div className="min-h-full w-full flex items-start sm:items-center justify-center p-4 py-6">
            <div className="w-full max-w-3xl bg-zinc-950 border border-zinc-800 rounded-xl shadow-xl max-h-[90vh] flex flex-col overflow-hidden">
              <div className="px-5 py-4 border-b border-zinc-800 flex items-center justify-between">
                <div>
                  <div className="text-lg font-semibold">Buscar pedido de compra</div>
                  <div className="text-sm text-zinc-400">Digite codigo, fornecedor ou UUID do pedido.</div>
                  {fornecedorResolvido && (
                    <div className="text-xs text-zinc-500">
                      Filtrando pelo fornecedor do XML: {fornecedorNome ?? "Fornecedor identificado"}.
                    </div>
                  )}
                </div>
                <button
                  onClick={closePedidoLookup}
                  className="px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                >
                  Fechar
                </button>
              </div>

              <div className="px-5 py-4 space-y-3 flex-1 min-h-0 overflow-auto">
                <div className="space-y-1">
                  <div className="text-xs text-zinc-400">Buscar</div>
                  <input
                    value={pedidoLookupTerm}
                    onChange={(e) => {
                      const value = e.target.value;
                      setPedidoLookupTerm(value);
                      if (pedidoLookupDebounceRef.current) clearTimeout(pedidoLookupDebounceRef.current);
                      pedidoLookupDebounceRef.current = setTimeout(() => {
                        void loadPedidoLookup(value);
                      }, 300);
                    }}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        void loadPedidoLookup(pedidoLookupTerm);
                      }
                    }}
                    placeholder="Ex: PC-000123"
                    className="w-full px-3 py-2 rounded-md border border-zinc-700 bg-zinc-900 text-zinc-100"
                    autoFocus
                  />
                </div>

                {pedidoLookupLoading && <div className="text-sm text-zinc-400">Buscando...</div>}
                {pedidoLookupError && <div className="text-sm text-red-400">{pedidoLookupError}</div>}

                <div className="border border-zinc-800 rounded-lg overflow-hidden">
                  <table className="w-full text-sm">
                    <thead className="bg-zinc-900/70">
                      <tr className="text-zinc-200">
                        <th className="px-3 py-2 text-left">Codigo</th>
                        <th className="px-3 py-2 text-left">Fornecedor</th>
                        <th className="px-3 py-2 text-left">Status</th>
                        <th className="px-3 py-2 text-right">Total</th>
                        <th className="px-3 py-2 text-left">Criado em</th>
                        <th className="px-3 py-2 text-center">Acao</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-zinc-800">
                      {pedidoLookupRows.map((row) => (
                        <tr key={row.id} className="hover:bg-zinc-900/40">
                          <td className="px-3 py-2">{row.codigo ?? row.id}</td>
                          <td className="px-3 py-2">{row.fornecedor_nome ?? "-"}</td>
                          <td className="px-3 py-2">{row.status ?? "-"}</td>
                          <td className="px-3 py-2 text-right tabular-nums">R$ {formatMoneyBR(Number(row.total_geral ?? 0))}</td>
                          <td className="px-3 py-2">{formatDateBR(row.created_at)}</td>
                          <td className="px-3 py-2 text-center">
                            <button
                              type="button"
                              onClick={() => {
                                setPedidoCompraRef((row.codigo ?? row.id) || "");
                                setPedidoAnalyzerRows([row]);
                                clearOsSelection();
                                if (row.solicitante_usuario_id) setSolicitanteUsuarioId(row.solicitante_usuario_id);
                                closePedidoLookup();
                              }}
                              className="px-3 py-1.5 rounded-md border border-zinc-700 bg-zinc-900 hover:bg-zinc-800"
                            >
                              Selecionar
                            </button>
                          </td>
                        </tr>
                      ))}
                      {!pedidoLookupLoading && pedidoLookupRows.length === 0 && (
                        <tr>
                          <td colSpan={6} className="px-3 py-4 text-zinc-400">
                            Nenhum pedido encontrado.
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

