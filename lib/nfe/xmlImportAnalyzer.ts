export type XmlImportAnalyzerStatus = "OK" | "ATENCAO" | "BLOQUEADO";
export type XmlImportAnalyzerSeverity = "info" | "warning" | "error";

export type XmlImportDiagnostic = {
  code: string;
  severity: XmlImportAnalyzerSeverity;
  message: string;
  details?: Record<string, unknown>;
};

type NumberLike = number | string | null | undefined;

export type XmlImportNfeItem = {
  codigo?: string | null;
  codigo_fornecedor?: string | null;
  nome?: string | null;
  descricao?: string | null;
  quantidade?: NumberLike;
  qtd?: NumberLike;
  valorUnit?: NumberLike;
  valor_unitario?: NumberLike;
  v_unit?: NumberLike;
  valorProd?: NumberLike;
  total?: NumberLike;
  v_prod?: NumberLike;
  item_id?: NumberLike;
  ncm?: string | null;
  cfop?: string | null;
  unidade?: string | null;
  unidade_medida?: string | null;
  uCom?: string | null;
};

export type XmlImportNfeBasic = {
  chave?: string | null;
  numero?: string | null;
  serie?: string | null;
  emitente?: string | null;
  emitente_nome?: string | null;
  cnpjEmitente?: string | null;
  emitente_cnpj?: string | null;
  valorTotal?: NumberLike;
  valor_total?: NumberLike;
  valorProdutos?: NumberLike;
  valor_produtos?: NumberLike;
  itens?: XmlImportNfeItem[];
};

export type XmlImportFornecedor = {
  id: number;
  nome?: string | null;
  cnpj?: string | null;
  documento?: string | null;
  finalidade_padrao?: string | null;
  motivo_compra_padrao_id?: string | null;
  gerar_contas_pagar_auto?: boolean | null;
};

export type XmlImportItemInterno = {
  id: number;
  codigo_interno: string;
  nome?: string | null;
  descricao?: string | null;
  unidade_medida?: string | null;
  fornecedor_id?: number | null;
  finalidade?: string | null;
};

export type XmlImportItensCadastrados =
  | Map<string, XmlImportItemInterno>
  | XmlImportItemInterno[]
  | Record<string, XmlImportItemInterno | null | undefined>;

export type XmlImportPedidoItem = {
  id: string;
  seq?: number | null;
  item_id?: NumberLike;
  item_codigo?: string | null;
  item_nome?: string | null;
  descricao?: string | null;
  quantidade?: NumberLike;
  quantidade_recebida?: NumberLike;
  valor_unitario?: NumberLike;
  valor_total?: NumberLike;
  origem_os_id?: number | null;
  origem_os_numero?: string | null;
  origem_os_label?: string | null;
};

export type XmlImportPedidoCandidato = {
  id: string;
  codigo?: string | null;
  status?: string | null;
  fornecedor_id?: number | null;
  fornecedor_nome?: string | null;
  solicitante_usuario_id?: string | null;
  total_geral?: NumberLike;
  total_pendente?: NumberLike;
  itens?: XmlImportPedidoItem[];
};

export type XmlImportAnalyzerParams = {
  finalidadesExigemItemCadastrado?: string[];
  finalidadesPermitemAutocadastro?: string[];
  finalidadesPermitemVinculo?: string[];
  pedidoScoreMinimo?: number;
  valorUnitarioToleranciaAbsoluta?: number;
  valorUnitarioToleranciaPercentual?: number;
  totalToleranciaAbsoluta?: number;
  totalToleranciaPercentual?: number;
};

export type XmlImportAnalyzerInput = {
  nfe: XmlImportNfeBasic;
  itens?: XmlImportNfeItem[];
  fornecedor: XmlImportFornecedor | null;
  itensCadastradosPorCodigo: XmlImportItensCadastrados;
  pedidosCandidatos?: XmlImportPedidoCandidato[];
  finalidadeSelecionada: string | null;
  motivoSelecionadoId: string | null;
  solicitanteUsuarioId: string | null;
  pedidoCompraRefAtual?: string | null;
  osIdAtual?: number | null;
  parametros?: XmlImportAnalyzerParams;
};

export type XmlImportFornecedorSuggestion = {
  status: "IDENTIFICADO" | "NAO_ENCONTRADO" | "SEM_CNPJ_XML";
  fornecedorId?: number;
  nome?: string | null;
  cnpj?: string | null;
  finalidadePadraoSugerida?: string | null;
  motivoPadraoSugeridoId?: string | null;
};

export type XmlImportPedidoItemMatch = {
  nfItemIndex: number;
  pedidoItemId: string;
  pedidoId: string;
  score: number;
  matchedBy: string[];
  manualItem?: boolean;
  descricaoSimilarity?: number;
  pedidoItemDescricao?: string | null;
  origemOsId?: number | null;
  origemOsNumero?: string | null;
  origemOsLabel?: string | null;
  quantityStatus: "OK" | "PARCIAL" | "EXCESSO" | "DESCONHECIDA";
  quantidadeNf: number;
  saldoPedido: number;
  valorUnitarioNf: number;
  valorUnitarioPedido: number;
  valorUnitarioDiff: number;
};

export type XmlImportPedidoSuggestion = {
  pedidoId: string;
  codigo?: string | null;
  status?: string | null;
  score: number;
  motivos: string[];
  solicitanteUsuarioId?: string | null;
  itemMatches: XmlImportPedidoItemMatch[];
  divergencias: XmlImportDiagnostic[];
};

export type XmlImportItemSuggestion = {
  index: number;
  codigoOriginal: string;
  codigoNormalizado: string;
  descricao: string;
  quantidade: number;
  valorUnitario: number;
  status: "CADASTRADO" | "NAO_CADASTRADO";
  severity: XmlImportAnalyzerSeverity;
  internalItem?: XmlImportItemInterno;
  pedidoMatchPedidoId?: string | null;
  pedidoMatchPedidoCodigo?: string | null;
  pedidoMatchItemId?: string | null;
  pedidoMatchDescricao?: string | null;
  pedidoMatchTipo?: "ITEM_ID" | "CODIGO" | "DESCRICAO_MANUAL" | null;
  pedidoMatchOsId?: number | null;
  pedidoMatchOsNumero?: string | null;
  pedidoMatchOsLabel?: string | null;
  pedidoMatchScore?: number | null;
  recommendedAction?: string | null;
  findings: XmlImportDiagnostic[];
  suggestions: XmlImportDiagnostic[];
  warnings: XmlImportDiagnostic[];
};

export type XmlImportActionPlanItem = {
  code: string;
  severity: XmlImportAnalyzerSeverity;
  message: string;
  actionType?:
    | "APPLY_PEDIDO"
    | "APPLY_SOLICITANTE"
    | "APPLY_OS"
    | "CADASTRAR_ITEM"
    | "VINCULAR_ITEM_MANUAL_PEDIDO"
    | "CONFERIR_DIVERGENCIA"
    | "SELECIONAR_MOTIVO";
  payload?: Record<string, unknown>;
};

export type XmlImportAnalyzerResult = {
  status: XmlImportAnalyzerStatus;
  score: number;
  findings: XmlImportDiagnostic[];
  suggestions: XmlImportDiagnostic[];
  warnings: XmlImportDiagnostic[];
  fornecedorSuggestion: XmlImportFornecedorSuggestion;
  pedidoSuggestion: XmlImportPedidoSuggestion | null;
  pedidoSuggestions: XmlImportPedidoSuggestion[];
  itemSuggestions: XmlImportItemSuggestion[];
  actionPlan: XmlImportActionPlanItem[];
};

type NormalizedNfItem = {
  index: number;
  raw: XmlImportNfeItem;
  codigoOriginal: string;
  codigoNormalizado: string;
  descricao: string;
  descricaoNorm: string;
  quantidade: number;
  valorUnitario: number;
  valorTotal: number;
  itemId: number | null;
  unidade: string | null;
};

type PedidoScore = {
  pedido: XmlImportPedidoCandidato;
  score: number;
  motivos: string[];
  matches: XmlImportPedidoItemMatch[];
  divergencias: XmlImportDiagnostic[];
  matchedCount: number;
};

type PredominantOsSuggestion = {
  osId: number;
  osNumero: string | null;
  osLabel: string;
};

const DEFAULT_REQUIRED_ITEM_FINALIDADES = ["materia_prima", "revenda"];
const DEFAULT_AUTO_CREATE_FINALIDADES = ["materia_prima", "revenda"];
const DEFAULT_PEDIDO_SCORE_MINIMO = 60;
const PEDIDO_ITEM_MATCH_MIN_SCORE = 35;
const PEDIDO_ITEM_MANUAL_MATCH_MIN_SCORE = 45;
const VALOR_UNITARIO_DIVERGENCIA_BLOQUEIO_PERCENT = 15;

const DESCRIPTION_STOP_TOKENS = new Set([
  "A",
  "AS",
  "C",
  "COM",
  "DA",
  "DAS",
  "DE",
  "DO",
  "DOS",
  "E",
  "IMP",
  "IMPORT",
  "IMPORTADO",
  "LASER",
  "O",
  "OS",
  "PARA",
  "PVC",
  "SEM",
  "X",
]);

const DESCRIPTION_FAMILY_TOKENS = new Set(["BARRA", "CHAPA", "TUBO"]);
const DESCRIPTION_MATERIAL_TOKENS = new Set(["ACO", "AISI", "INOX"]);
const DESCRIPTION_LIGA_TOKENS = new Set(["304", "316", "316L", "430"]);
const DESCRIPTION_TECHNICAL_TOKENS = new Set(["RED", "REDONDO", "RET", "RETANGULAR"]);

export function normalizeXmlItemCode(value: unknown): string {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  if (/^\d+$/.test(raw)) return raw.replace(/^0+(?!$)/, "");
  return raw;
}

function normalizePedidoItemCode(value: unknown): string {
  const normalized = normalizeXmlItemCode(value);
  const key = normalizeKey(normalized);
  if (!key || key === "-" || key === "MANUAL" || key === "SEM CODIGO" || key === "SEM CODIGO INTERNO") return "";
  return normalized;
}

function normalizeKey(value: unknown): string {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .toUpperCase();
}

function normalizeFinalidade(value: unknown): string {
  return String(value ?? "").trim().toLowerCase();
}

function normalizeDoc(value: unknown): string {
  return String(value ?? "").replace(/\D/g, "");
}

function toNumber(value: NumberLike): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const text = String(value ?? "").trim();
  if (!text) return 0;
  const normalized = text.includes(",") && text.includes(".")
    ? text.replace(/\./g, "").replace(",", ".")
    : text.replace(",", ".");
  const num = Number(normalized);
  return Number.isFinite(num) ? num : 0;
}

function roundScore(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(100, Math.round(value)));
}

function formatDecimal(value: number, maximumFractionDigits = 4): string {
  if (!Number.isFinite(value)) return "0";
  return value.toLocaleString("pt-BR", {
    minimumFractionDigits: 0,
    maximumFractionDigits,
  });
}

function formatCurrency(value: number): string {
  if (!Number.isFinite(value)) return "R$ 0,00";
  return value.toLocaleString("pt-BR", {
    style: "currency",
    currency: "BRL",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function formatPercent(value: number): string {
  if (!Number.isFinite(value)) return "0%";
  return `${formatDecimal(value, 2)}%`;
}

function percentDiff(value: number, base: number): number | null {
  if (!Number.isFinite(value) || !Number.isFinite(base) || base <= 0) return null;
  return (value / base) * 100;
}

function diagnostic(
  code: string,
  severity: XmlImportAnalyzerSeverity,
  message: string,
  details?: Record<string, unknown>
): XmlImportDiagnostic {
  return details ? { code, severity, message, details } : { code, severity, message };
}

function hasText(value: unknown): boolean {
  return String(value ?? "").trim().length > 0;
}

function getEmitenteNome(nfe: XmlImportNfeBasic): string | null {
  const value = String(nfe.emitente ?? nfe.emitente_nome ?? "").trim();
  return value || null;
}

function getEmitenteCnpj(nfe: XmlImportNfeBasic): string | null {
  const value = normalizeDoc(nfe.cnpjEmitente ?? nfe.emitente_cnpj);
  return value.length === 14 ? value : null;
}

function getNfeTotal(nfe: XmlImportNfeBasic, itens: NormalizedNfItem[]): number {
  const total = toNumber(nfe.valorTotal ?? nfe.valor_total);
  if (total > 0) return total;
  const produtos = toNumber(nfe.valorProdutos ?? nfe.valor_produtos);
  if (produtos > 0) return produtos;
  return itens.reduce((sum, item) => sum + item.valorTotal, 0);
}

function getItemCodigo(item: XmlImportNfeItem): string {
  return String(item.codigo ?? item.codigo_fornecedor ?? "").trim();
}

function getItemDescricao(item: XmlImportNfeItem): string {
  return String(item.descricao ?? item.nome ?? "").replace(/\s+/g, " ").trim();
}

function getItemQuantidade(item: XmlImportNfeItem): number {
  return toNumber(item.quantidade ?? item.qtd);
}

function getItemValorUnitario(item: XmlImportNfeItem): number {
  const direct = toNumber(item.valorUnit ?? item.v_unit ?? item.valor_unitario);
  if (direct > 0) return direct;
  const qtd = getItemQuantidade(item);
  const total = toNumber(item.valorProd ?? item.v_prod ?? item.total);
  return qtd > 0 && total > 0 ? total / qtd : 0;
}

function getItemValorTotal(item: XmlImportNfeItem): number {
  const direct = toNumber(item.valorProd ?? item.v_prod ?? item.total);
  if (direct > 0) return direct;
  return getItemQuantidade(item) * getItemValorUnitario(item);
}

function getItemId(value: NumberLike): number | null {
  const id = toNumber(value);
  return Number.isFinite(id) && id > 0 ? Math.trunc(id) : null;
}

function getItemUnidade(item: XmlImportNfeItem): string | null {
  const unidade = String(item.unidade ?? item.unidade_medida ?? item.uCom ?? "").trim();
  return unidade || null;
}

function normalizeNfItems(input: XmlImportAnalyzerInput): NormalizedNfItem[] {
  const source = input.itens ?? input.nfe.itens ?? [];
  return source.map((item, index) => {
    const codigoOriginal = getItemCodigo(item);
    const descricao = getItemDescricao(item);
    return {
      index,
      raw: item,
      codigoOriginal,
      codigoNormalizado: normalizeXmlItemCode(codigoOriginal),
      descricao,
      descricaoNorm: normalizeKey(descricao),
      quantidade: getItemQuantidade(item),
      valorUnitario: getItemValorUnitario(item),
      valorTotal: getItemValorTotal(item),
      itemId: getItemId(item.item_id),
      unidade: getItemUnidade(item),
    };
  });
}

function addItemToMap(map: Map<string, XmlImportItemInterno>, key: string, item: XmlImportItemInterno): void {
  const normalized = normalizeXmlItemCode(key);
  if (normalized && !map.has(normalized)) map.set(normalized, item);
  const raw = String(key ?? "").trim();
  if (raw && !map.has(raw)) map.set(raw, item);
}

function buildItemMap(source: XmlImportItensCadastrados): Map<string, XmlImportItemInterno> {
  const map = new Map<string, XmlImportItemInterno>();

  if (source instanceof Map) {
    for (const [key, item] of source.entries()) {
      addItemToMap(map, key, item);
      addItemToMap(map, item.codigo_interno, item);
    }
    return map;
  }

  if (Array.isArray(source)) {
    for (const item of source) addItemToMap(map, item.codigo_interno, item);
    return map;
  }

  for (const [key, item] of Object.entries(source)) {
    if (!item) continue;
    addItemToMap(map, key, item);
    addItemToMap(map, item.codigo_interno, item);
  }

  return map;
}

function buildStringSet(values: string[] | undefined, fallback: string[]): Set<string> {
  const source = values && values.length > 0 ? values : fallback;
  return new Set(source.map(normalizeFinalidade).filter(Boolean));
}

function normalizeDecimalText(_match: string, integerPart: string, decimalPart: string): string {
  const cleanedDecimal = decimalPart.replace(/0+$/g, "");
  return cleanedDecimal ? `${integerPart}.${cleanedDecimal}` : integerPart;
}

function normalizeDescriptionText(value: unknown): string {
  return normalizeKey(value)
    .replace(/\bTB\.?/g, " TUBO ")
    .replace(/\bTUB\.?/g, " TUBO ")
    .replace(/\bRED\.?/g, " RED ")
    .replace(/(\d+)[,.](\d+)/g, normalizeDecimalText)
    .replace(/(\d+(?:\.\d+)?)\s*(MM|CM|M)\b/g, "$1$2")
    .replace(/(\d+(?:\.\d+)?(?:MM|CM|M)?)\s*X\s*(?=\d)/g, "$1 X ")
    .replace(/[^A-Z0-9.]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeNumericToken(value: string): string {
  return value.replace(/\.0+$/g, "").replace(/(\.\d*?)0+$/g, "$1");
}

function isNumericDescriptionToken(token: string): boolean {
  return /^\d+(?:\.\d+)?(?:MM|CM|M)?$/.test(token);
}

function getDescriptionTokenNumber(token: string): string | null {
  const match = token.match(/^(\d+(?:\.\d+)?)(?:MM|CM|M)?$/);
  return match ? normalizeNumericToken(match[1]) : null;
}

function descriptionTokens(value: unknown): Set<string> {
  const normalized = normalizeDescriptionText(value);
  const rawTokens = normalized.match(/[A-Z]+|\d+(?:\.\d+)?(?:MM|CM|M)?/g) ?? [];
  const tokens = new Set<string>();

  for (const rawToken of rawTokens) {
    const token = rawToken.trim();
    if (!token || DESCRIPTION_STOP_TOKENS.has(token)) continue;

    if (isNumericDescriptionToken(token)) {
      const number = getDescriptionTokenNumber(token);
      if (number) tokens.add(number);
      if (/[A-Z]/.test(token)) tokens.add(token);
      continue;
    }

    if (
      token.length >= 3 ||
      DESCRIPTION_FAMILY_TOKENS.has(token) ||
      DESCRIPTION_MATERIAL_TOKENS.has(token) ||
      DESCRIPTION_LIGA_TOKENS.has(token) ||
      DESCRIPTION_TECHNICAL_TOKENS.has(token)
    ) {
      tokens.add(token);
    }
  }

  return tokens;
}

function descriptionTokenWeight(token: string): number {
  if (DESCRIPTION_LIGA_TOKENS.has(token)) return 16;
  if (DESCRIPTION_MATERIAL_TOKENS.has(token)) return 14;
  if (DESCRIPTION_FAMILY_TOKENS.has(token)) return 14;
  if (isNumericDescriptionToken(token)) return 13;
  if (DESCRIPTION_TECHNICAL_TOKENS.has(token)) return 8;
  return token.length >= 4 ? 4 : 2;
}

function tokenWeightSum(tokens: Set<string>): number {
  let sum = 0;
  for (const token of tokens) sum += descriptionTokenWeight(token);
  return sum;
}

function intersectTokenWeight(left: Set<string>, right: Set<string>): number {
  let sum = 0;
  for (const token of left) {
    if (right.has(token)) sum += descriptionTokenWeight(token);
  }
  return sum;
}

function getTokenGroupIntersection(left: Set<string>, right: Set<string>, group: Set<string>): number {
  let count = 0;
  for (const token of group) {
    if (left.has(token) && right.has(token)) count += 1;
  }
  return count;
}

function getDescriptionNumbers(tokens: Set<string>): Set<string> {
  const numbers = new Set<string>();
  for (const token of tokens) {
    const number = getDescriptionTokenNumber(token);
    if (number) numbers.add(number);
  }
  return numbers;
}

function hasAnyIntersection(left: Set<string>, right: Set<string>): boolean {
  for (const token of left) {
    if (right.has(token)) return true;
  }
  return false;
}

function descriptionSimilarity(a: string, b: string): number {
  const left = descriptionTokens(a);
  const right = descriptionTokens(b);
  if (!left.size || !right.size) return 0;

  const intersection = intersectTokenWeight(left, right);
  if (intersection <= 0) return 0;

  const leftWeight = tokenWeightSum(left);
  const rightWeight = tokenWeightSum(right);
  const coverage = intersection / Math.max(Math.min(leftWeight, rightWeight), 1);
  const balance = intersection / Math.max(leftWeight, rightWeight, 1);
  let score = (coverage * 0.7 + balance * 0.3) * 100;

  const leftNumbers = getDescriptionNumbers(left);
  const rightNumbers = getDescriptionNumbers(right);
  if (leftNumbers.size > 0 && rightNumbers.size > 0 && !hasAnyIntersection(leftNumbers, rightNumbers)) {
    score = Math.min(score, 58);
  }

  const leftFamily = new Set(Array.from(left).filter((token) => DESCRIPTION_FAMILY_TOKENS.has(token)));
  const rightFamily = new Set(Array.from(right).filter((token) => DESCRIPTION_FAMILY_TOKENS.has(token)));
  if (leftFamily.size > 0 && rightFamily.size > 0 && !hasAnyIntersection(leftFamily, rightFamily)) {
    score = Math.min(score, 64);
  }

  const hasMaterialOrLiga =
    getTokenGroupIntersection(left, right, DESCRIPTION_MATERIAL_TOKENS) > 0 ||
    getTokenGroupIntersection(left, right, DESCRIPTION_LIGA_TOKENS) > 0;

  if (!hasMaterialOrLiga && (left.has("INOX") || right.has("INOX"))) {
    score = Math.min(score, 68);
  }

  return roundScore(score);
}

function valuesClose(a: number, b: number, absoluteTolerance: number, percentTolerance: number): boolean {
  if (a <= 0 || b <= 0) return false;
  const diff = Math.abs(a - b);
  if (diff <= absoluteTolerance) return true;
  return diff / Math.max(Math.abs(b), 1) <= percentTolerance;
}

function pedidoItemSaldo(item: XmlImportPedidoItem): number {
  return Math.max(0, toNumber(item.quantidade) - toNumber(item.quantidade_recebida));
}

function isPedidoItemManual(item: XmlImportPedidoItem): boolean {
  return !getItemId(item.item_id) && !normalizePedidoItemCode(item.item_codigo);
}

function pushUnique(values: string[], value: string): void {
  if (!values.includes(value)) values.push(value);
}

function pedidoTotalPendente(pedido: XmlImportPedidoCandidato): number {
  const explicit = toNumber(pedido.total_pendente);
  if (explicit > 0) return explicit;
  const itens = pedido.itens ?? [];
  const total = itens.reduce((sum, item) => sum + pedidoItemSaldo(item) * toNumber(item.valor_unitario), 0);
  return total > 0 ? total : toNumber(pedido.total_geral);
}

function scorePedidoItem(
  nfItem: NormalizedNfItem,
  pedido: XmlImportPedidoCandidato,
  pedidoItem: XmlImportPedidoItem,
  itemInterno: XmlImportItemInterno | undefined,
  params: Required<Pick<
    XmlImportAnalyzerParams,
    "valorUnitarioToleranciaAbsoluta" | "valorUnitarioToleranciaPercentual"
  >>
): XmlImportPedidoItemMatch {
  const matchedBy: string[] = [];
  let score = 0;
  const manualItem = isPedidoItemManual(pedidoItem);
  const origemOsId = pedidoItem.origem_os_id && Number.isFinite(Number(pedidoItem.origem_os_id))
    ? Number(pedidoItem.origem_os_id)
    : null;
  const origemOsNumero = String(pedidoItem.origem_os_numero ?? "").trim() || null;
  const origemOsLabel =
    String(pedidoItem.origem_os_label ?? "").trim() ||
    (origemOsNumero ? `OS ${origemOsNumero}` : origemOsId ? `OS ${origemOsId}` : null);

  const pedidoItemId = getItemId(pedidoItem.item_id);
  if (nfItem.itemId && pedidoItemId && nfItem.itemId === pedidoItemId) {
    score += 42;
    matchedBy.push("item_id_xml");
  } else if (itemInterno?.id && pedidoItemId && itemInterno.id === pedidoItemId) {
    score += 42;
    matchedBy.push("item_id_resolvido");
  }

  const pedidoCodigo = normalizePedidoItemCode(pedidoItem.item_codigo);
  if (nfItem.codigoNormalizado && pedidoCodigo && nfItem.codigoNormalizado === pedidoCodigo) {
    score += 28;
    matchedBy.push("codigo");
  }

  const pedidoDescricao = String(pedidoItem.item_nome ?? pedidoItem.descricao ?? "").trim();
  const descSimilarity = descriptionSimilarity(nfItem.descricao, pedidoDescricao);
  if (
    nfItem.descricaoNorm &&
    normalizeDescriptionText(pedidoDescricao) &&
    normalizeDescriptionText(nfItem.descricao) === normalizeDescriptionText(pedidoDescricao)
  ) {
    score += manualItem ? 52 : 18;
    matchedBy.push(manualItem ? "descricao_manual_exata" : "descricao_exata");
  } else if (manualItem) {
    if (descSimilarity >= 80) {
      score += 48;
      matchedBy.push("descricao_manual_forte");
    } else if (descSimilarity >= 65) {
      score += 38;
      matchedBy.push("descricao_manual_compativel");
    } else if (descSimilarity >= 50) {
      score += 24;
      matchedBy.push("descricao_manual_parcial");
    } else if (descSimilarity >= 35) {
      score += 12;
      matchedBy.push("descricao_manual_fraca");
    }
  } else if (descSimilarity >= 70) {
    score += 12;
    matchedBy.push("descricao_parecida");
  } else if (descSimilarity >= 50) {
    score += 6;
    matchedBy.push("descricao_parcial");
  } else if (descSimilarity >= 35) {
    score += 3;
    matchedBy.push("descricao_fraca");
  }

  if (manualItem && origemOsId) {
    score += 5;
    matchedBy.push("origem_os");
  }

  const valorPedido = toNumber(pedidoItem.valor_unitario);
  const valorDiff = Math.abs(nfItem.valorUnitario - valorPedido);
  if (
    valuesClose(
      nfItem.valorUnitario,
      valorPedido,
      params.valorUnitarioToleranciaAbsoluta,
      params.valorUnitarioToleranciaPercentual
    )
  ) {
    score += 14;
    matchedBy.push("valor_unitario");
  } else if (nfItem.valorUnitario > 0 && valorPedido > 0) {
    const diffPct = valorDiff / Math.max(valorPedido, 1);
    if (diffPct <= 0.1) score += 6;
  }

  const saldo = pedidoItemSaldo(pedidoItem);
  let quantityStatus: XmlImportPedidoItemMatch["quantityStatus"] = "DESCONHECIDA";
  if (nfItem.quantidade > 0 && saldo > 0) {
    if (nfItem.quantidade > saldo + 0.000001) {
      quantityStatus = "EXCESSO";
      score -= 10;
    } else if (nfItem.quantidade < saldo - 0.000001) {
      quantityStatus = "PARCIAL";
      score += 6;
      matchedBy.push("quantidade_parcial");
    } else {
      quantityStatus = "OK";
      score += 10;
      matchedBy.push("quantidade");
    }
  }

  return {
    nfItemIndex: nfItem.index,
    pedidoItemId: pedidoItem.id,
    pedidoId: pedido.id,
    score: roundScore(score),
    matchedBy,
    manualItem,
    descricaoSimilarity: descSimilarity,
    pedidoItemDescricao: pedidoDescricao || null,
    origemOsId,
    origemOsNumero,
    origemOsLabel,
    quantityStatus,
    quantidadeNf: nfItem.quantidade,
    saldoPedido: saldo,
    valorUnitarioNf: nfItem.valorUnitario,
    valorUnitarioPedido: valorPedido,
    valorUnitarioDiff: valorDiff,
  };
}

function bestMatchForItem(
  nfItem: NormalizedNfItem,
  pedido: XmlImportPedidoCandidato,
  itemInterno: XmlImportItemInterno | undefined,
  params: Required<Pick<
    XmlImportAnalyzerParams,
    "valorUnitarioToleranciaAbsoluta" | "valorUnitarioToleranciaPercentual"
  >>
): XmlImportPedidoItemMatch | null {
  let best: XmlImportPedidoItemMatch | null = null;
  for (const pedidoItem of pedido.itens ?? []) {
    const current = scorePedidoItem(nfItem, pedido, pedidoItem, itemInterno, params);
    if (!best || current.score > best.score) best = current;
  }
  return best;
}

function isPedidoItemMatchConfiavel(match: XmlImportPedidoItemMatch): boolean {
  const hasIdentityMatch = match.matchedBy.includes("item_id_xml") ||
    match.matchedBy.includes("item_id_resolvido") ||
    match.matchedBy.includes("codigo");

  if (hasIdentityMatch) return match.score >= PEDIDO_ITEM_MATCH_MIN_SCORE;

  if (match.manualItem) {
    return match.score >= PEDIDO_ITEM_MANUAL_MATCH_MIN_SCORE && (match.descricaoSimilarity ?? 0) >= 50;
  }

  return match.score >= PEDIDO_ITEM_MANUAL_MATCH_MIN_SCORE && (match.descricaoSimilarity ?? 0) >= 50;
}

function scorePedido(
  pedido: XmlImportPedidoCandidato,
  nfItems: NormalizedNfItem[],
  itemMap: Map<string, XmlImportItemInterno>,
  fornecedor: XmlImportFornecedor | null,
  nfeTotal: number,
  params: Required<Pick<
    XmlImportAnalyzerParams,
    | "valorUnitarioToleranciaAbsoluta"
    | "valorUnitarioToleranciaPercentual"
    | "totalToleranciaAbsoluta"
    | "totalToleranciaPercentual"
  >>
): PedidoScore {
  const motivos: string[] = [];
  const divergencias: XmlImportDiagnostic[] = [];
  let score = 0;

  if (fornecedor?.id && pedido.fornecedor_id) {
    if (Number(fornecedor.id) === Number(pedido.fornecedor_id)) {
      score += 20;
      motivos.push("Fornecedor do pedido compativel com a nota.");
    } else {
      score -= 15;
      divergencias.push(
        diagnostic("PEDIDO_FORNECEDOR_DIFERENTE", "warning", "O fornecedor do pedido e diferente do fornecedor da nota.")
      );
    }
  }

  const status = String(pedido.status ?? "").trim().toUpperCase();
  if (status === "ENVIADO" || status === "PARCIAL_RECEBIDO") {
    score += 5;
    motivos.push(`Pedido em status ${status}.`);
  } else if (status === "CANCELADO" || status === "RECEBIDO") {
    score -= 20;
    divergencias.push(diagnostic("PEDIDO_STATUS_INADEQUADO", "warning", `Este pedido esta com status ${status}.`));
  }

  const pedidoItens = pedido.itens ?? [];
  const manualItens = pedidoItens.filter(isPedidoItemManual);
  if (manualItens.length > 0) {
    divergencias.push(
      diagnostic(
        "PEDIDO_COM_ITENS_MANUAIS",
        "warning",
        "O pedido possui itens manuais sem cadastro interno. A importacao pode exigir cadastro e vinculo antes de concluir.",
        {
          pedido_id: pedido.id,
          itens_manuais: manualItens.length,
        }
      )
    );
  }

  const matches: XmlImportPedidoItemMatch[] = [];
  let matchScoreSum = 0;
  let matchedCount = 0;
  let matchedManualCount = 0;
  let matchedWithOsCount = 0;
  let matchedQuantityCompatibleCount = 0;
  let matchedValueCompatibleCount = 0;

  for (const nfItem of nfItems) {
    const itemInterno = itemMap.get(nfItem.codigoNormalizado);
    const match = bestMatchForItem(nfItem, pedido, itemInterno, params);
    if (!match || !isPedidoItemMatchConfiavel(match)) {
      divergencias.push(
        diagnostic("ITEM_SEM_CORRESPONDENTE_PEDIDO", "warning", "Item da NF sem correspondente claro neste pedido.", {
          codigo: nfItem.codigoOriginal,
          descricao: nfItem.descricao,
          pedido_id: pedido.id,
        })
      );
      continue;
    }

    matches.push(match);
    matchedCount += 1;
    matchScoreSum += match.score;
    if (match.manualItem) matchedManualCount += 1;
    if (match.origemOsId) matchedWithOsCount += 1;
    if (match.quantityStatus === "OK" || match.quantityStatus === "PARCIAL") matchedQuantityCompatibleCount += 1;
    if (match.matchedBy.includes("valor_unitario")) matchedValueCompatibleCount += 1;

    if (
      match.valorUnitarioNf > 0 &&
      match.valorUnitarioPedido > 0 &&
      !valuesClose(
        match.valorUnitarioNf,
        match.valorUnitarioPedido,
        params.valorUnitarioToleranciaAbsoluta,
        params.valorUnitarioToleranciaPercentual
      )
    ) {
      const diffPercent = percentDiff(match.valorUnitarioDiff, match.valorUnitarioPedido);
      const blocksImport = diffPercent != null && diffPercent >= VALOR_UNITARIO_DIVERGENCIA_BLOQUEIO_PERCENT;
      divergencias.push(
        diagnostic("DIVERGENCIA_VALOR_UNITARIO", blocksImport ? "error" : "warning", `Valor unitario divergente no item ${nfItem.codigoOriginal || "-"}: NF ${formatCurrency(match.valorUnitarioNf)}, pedido ${formatCurrency(match.valorUnitarioPedido)}, diferenca ${formatCurrency(match.valorUnitarioDiff)}${diffPercent == null ? "" : ` (${formatPercent(diffPercent)})`}.${blocksImport ? " Diferenca acima de 15%; corrija o pedido antes de importar." : ""}`, {
          codigo: nfItem.codigoOriginal,
          descricao: nfItem.descricao,
          pedido_item_id: match.pedidoItemId,
          valor_nf: match.valorUnitarioNf,
          valor_pedido: match.valorUnitarioPedido,
          diferenca: match.valorUnitarioDiff,
          diferenca_percentual: diffPercent,
          limite_bloqueio_percentual: VALOR_UNITARIO_DIVERGENCIA_BLOQUEIO_PERCENT,
        })
      );
    }

    if (match.quantityStatus === "PARCIAL") {
      const restante = Math.max(0, match.saldoPedido - match.quantidadeNf);
      divergencias.push(
        diagnostic("QUANTIDADE_PARCIAL_PEDIDO", "error", `Quantidade parcial no item ${nfItem.codigoOriginal || "-"}: NF ${formatDecimal(match.quantidadeNf)}, saldo do pedido ${formatDecimal(match.saldoPedido)}, restante ${formatDecimal(restante)}. Ajuste a quantidade do pedido antes de importar.`, {
          codigo: nfItem.codigoOriginal,
          descricao: nfItem.descricao,
          pedido_item_id: match.pedidoItemId,
          quantidade_nf: match.quantidadeNf,
          saldo_pedido: match.saldoPedido,
          restante,
        })
      );
    }

    if (match.quantityStatus === "EXCESSO") {
      const excesso = Math.max(0, match.quantidadeNf - match.saldoPedido);
      divergencias.push(
        diagnostic("QUANTIDADE_EXCEDE_PEDIDO", "error", `Quantidade excedente no item ${nfItem.codigoOriginal || "-"}: NF ${formatDecimal(match.quantidadeNf)}, saldo do pedido ${formatDecimal(match.saldoPedido)}, excesso ${formatDecimal(excesso)}. Ajuste a quantidade do pedido antes de importar.`, {
          codigo: nfItem.codigoOriginal,
          descricao: nfItem.descricao,
          pedido_item_id: match.pedidoItemId,
          quantidade_nf: match.quantidadeNf,
          saldo_pedido: match.saldoPedido,
          excesso,
        })
      );
    }
  }

  if (nfItems.length > 0) {
    score += (matchedCount / nfItems.length) * 35;
    score += (matchScoreSum / Math.max(nfItems.length * 100, 1)) * 20;
    if (matchedCount > 0) motivos.push(`${matchedCount}/${nfItems.length} itens da nota combinam com itens do pedido.`);
  }

  if (matchedManualCount > 0) {
    pushUnique(motivos, "Itens manuais do pedido tem descricao compativel com itens da NF.");
  }

  if (matchedWithOsCount > 0) {
    pushUnique(motivos, "Pedido possui OS vinculada nos itens.");
  }

  if (matchedQuantityCompatibleCount > 0) {
    pushUnique(motivos, "Quantidade compativel com saldo pendente.");
  }

  if (matchedValueCompatibleCount > 0) {
    pushUnique(motivos, "Valor unitario compativel.");
  }

  const totalPedido = pedidoTotalPendente(pedido);
  if (nfeTotal > 0 && totalPedido > 0) {
    if (valuesClose(nfeTotal, totalPedido, params.totalToleranciaAbsoluta, params.totalToleranciaPercentual)) {
      score += 15;
      motivos.push("Total da nota proximo do total pendente do pedido.");
    } else {
      const diff = nfeTotal - totalPedido;
      divergencias.push(
        diagnostic("DIVERGENCIA_TOTAL_PEDIDO_NF", "warning", "O total da NF diverge do total pendente do pedido.", {
          total_nf: nfeTotal,
          total_pedido_pendente: totalPedido,
          diferenca: diff,
        })
      );
      score += Math.max(0, 10 - Math.abs(diff / Math.max(totalPedido, 1)) * 50);
    }
  }

  if (pedido.solicitante_usuario_id) {
    score += 5;
    motivos.push("Pedido possui solicitante vinculado.");
  }

  return {
    pedido,
    score: roundScore(score),
    motivos,
    matches,
    divergencias,
    matchedCount,
  };
}

function detectMultiplePedidoCandidates(
  pedidos: PedidoScore[],
  nfItems: NormalizedNfItem[]
): XmlImportDiagnostic | null {
  if (pedidos.length < 2 || nfItems.length < 2) return null;

  const bestPedidoByItem = new Map<number, string>();
  for (const nfItem of nfItems) {
    let best: { pedidoId: string; score: number } | null = null;
    for (const pedido of pedidos) {
      const match = pedido.matches.find((item) => item.nfItemIndex === nfItem.index);
      if (!match || match.score < 50) continue;
      if (!best || match.score > best.score) best = { pedidoId: pedido.pedido.id, score: match.score };
    }
    if (best) bestPedidoByItem.set(nfItem.index, best.pedidoId);
  }

  const pedidoIds = Array.from(new Set(bestPedidoByItem.values()));
  if (pedidoIds.length < 2) return null;

  return diagnostic("NF_POSSIVEL_MULTIPLOS_PEDIDOS", "warning", "Esta NF pode estar relacionada a mais de um pedido de compra.", {
    pedidos: pedidoIds,
    itens_analisados: bestPedidoByItem.size,
  });
}

function buildPedidoMatchDivergencias(
  match: XmlImportPedidoItemMatch,
  nfItem: NormalizedNfItem,
  params: Required<Pick<
    XmlImportAnalyzerParams,
    "valorUnitarioToleranciaAbsoluta" | "valorUnitarioToleranciaPercentual"
  >>
): XmlImportDiagnostic[] {
  const divergencias: XmlImportDiagnostic[] = [];

  if (
    match.valorUnitarioNf > 0 &&
    match.valorUnitarioPedido > 0 &&
    !valuesClose(
      match.valorUnitarioNf,
      match.valorUnitarioPedido,
      params.valorUnitarioToleranciaAbsoluta,
      params.valorUnitarioToleranciaPercentual
    )
  ) {
    const diffPercent = percentDiff(match.valorUnitarioDiff, match.valorUnitarioPedido);
    const blocksImport = diffPercent != null && diffPercent >= VALOR_UNITARIO_DIVERGENCIA_BLOQUEIO_PERCENT;
    divergencias.push(
      diagnostic("DIVERGENCIA_VALOR_UNITARIO", blocksImport ? "error" : "warning", `Valor unitario divergente no item ${nfItem.codigoOriginal || "-"}: NF ${formatCurrency(match.valorUnitarioNf)}, pedido ${formatCurrency(match.valorUnitarioPedido)}, diferenca ${formatCurrency(match.valorUnitarioDiff)}${diffPercent == null ? "" : ` (${formatPercent(diffPercent)})`}.${blocksImport ? " Diferenca acima de 15%; corrija o pedido antes de importar." : ""}`, {
        codigo: nfItem.codigoOriginal,
        descricao: nfItem.descricao,
        pedido_item_id: match.pedidoItemId,
        pedido_id: match.pedidoId,
        valor_nf: match.valorUnitarioNf,
        valor_pedido: match.valorUnitarioPedido,
        diferenca: match.valorUnitarioDiff,
        diferenca_percentual: diffPercent,
        limite_bloqueio_percentual: VALOR_UNITARIO_DIVERGENCIA_BLOQUEIO_PERCENT,
      })
    );
  }

  if (match.quantityStatus === "PARCIAL") {
    const restante = Math.max(0, match.saldoPedido - match.quantidadeNf);
    divergencias.push(
      diagnostic("QUANTIDADE_PARCIAL_PEDIDO", "error", `Quantidade parcial no item ${nfItem.codigoOriginal || "-"}: NF ${formatDecimal(match.quantidadeNf)}, saldo do pedido ${formatDecimal(match.saldoPedido)}, restante ${formatDecimal(restante)}. Ajuste a quantidade do pedido antes de importar.`, {
        codigo: nfItem.codigoOriginal,
        descricao: nfItem.descricao,
        pedido_item_id: match.pedidoItemId,
        pedido_id: match.pedidoId,
        quantidade_nf: match.quantidadeNf,
        saldo_pedido: match.saldoPedido,
        restante,
      })
    );
  }

  if (match.quantityStatus === "EXCESSO") {
    const excesso = Math.max(0, match.quantidadeNf - match.saldoPedido);
    divergencias.push(
      diagnostic("QUANTIDADE_EXCEDE_PEDIDO", "error", `Quantidade excedente no item ${nfItem.codigoOriginal || "-"}: NF ${formatDecimal(match.quantidadeNf)}, saldo do pedido ${formatDecimal(match.saldoPedido)}, excesso ${formatDecimal(excesso)}. Ajuste a quantidade do pedido antes de importar.`, {
        codigo: nfItem.codigoOriginal,
        descricao: nfItem.descricao,
        pedido_item_id: match.pedidoItemId,
        pedido_id: match.pedidoId,
        quantidade_nf: match.quantidadeNf,
        saldo_pedido: match.saldoPedido,
        excesso,
      })
    );
  }

  return divergencias;
}

function buildMultiPedidoSuggestions(opts: {
  scores: PedidoScore[];
  nfItems: NormalizedNfItem[];
  params: Required<Pick<
    XmlImportAnalyzerParams,
    "valorUnitarioToleranciaAbsoluta" | "valorUnitarioToleranciaPercentual"
  >>;
}): XmlImportPedidoSuggestion[] {
  if (opts.scores.length < 2 || opts.nfItems.length < 2) return [];

  const nfItemByIndex = new Map(opts.nfItems.map((item) => [item.index, item]));
  const selectedMatches: XmlImportPedidoItemMatch[] = [];
  const usedPedidoItems = new Set<string>();

  for (const nfItem of opts.nfItems) {
    let best: XmlImportPedidoItemMatch | null = null;
    for (const score of opts.scores) {
      const match = score.matches.find((item) => item.nfItemIndex === nfItem.index) ?? null;
      if (!match || match.score < 50 || usedPedidoItems.has(match.pedidoItemId)) continue;
      if (!best || match.score > best.score) best = match;
    }
    if (!best) continue;
    selectedMatches.push(best);
    usedPedidoItems.add(best.pedidoItemId);
  }

  const pedidoIds = Array.from(new Set(selectedMatches.map((match) => match.pedidoId)));
  if (pedidoIds.length < 2) return [];

  const scoreByPedidoId = new Map(opts.scores.map((score) => [score.pedido.id, score]));
  const suggestions: XmlImportPedidoSuggestion[] = [];

  for (const pedidoId of pedidoIds) {
    const pedidoScore = scoreByPedidoId.get(pedidoId);
    if (!pedidoScore) continue;

    const matches = selectedMatches.filter((match) => match.pedidoId === pedidoId);
    if (matches.length === 0) continue;

    const divergencias = matches.flatMap((match) => {
      const nfItem = nfItemByIndex.get(match.nfItemIndex);
      return nfItem ? buildPedidoMatchDivergencias(match, nfItem, opts.params) : [];
    });
    const avgMatchScore = matches.reduce((sum, match) => sum + match.score, 0) / Math.max(matches.length, 1);

    suggestions.push({
      pedidoId: pedidoScore.pedido.id,
      codigo: pedidoScore.pedido.codigo ?? null,
      status: pedidoScore.pedido.status ?? null,
      score: roundScore(avgMatchScore),
      motivos: [
        `${matches.length}/${opts.nfItems.length} itens da nota combinam com este pedido.`,
        ...pedidoScore.motivos.filter((motivo) => !motivo.includes("Total da nota")),
      ],
      solicitanteUsuarioId: pedidoScore.pedido.solicitante_usuario_id ?? null,
      itemMatches: matches,
      divergencias,
    });
  }

  return suggestions.sort((a, b) => String(a.codigo ?? a.pedidoId).localeCompare(String(b.codigo ?? b.pedidoId)));
}

function analyzeFornecedor(input: XmlImportAnalyzerInput): {
  fornecedorSuggestion: XmlImportFornecedorSuggestion;
  findings: XmlImportDiagnostic[];
  suggestions: XmlImportDiagnostic[];
  warnings: XmlImportDiagnostic[];
} {
  const findings: XmlImportDiagnostic[] = [];
  const suggestions: XmlImportDiagnostic[] = [];
  const warnings: XmlImportDiagnostic[] = [];
  const cnpj = getEmitenteCnpj(input.nfe);
  const emitente = getEmitenteNome(input.nfe);

  if (!cnpj) {
    warnings.push(diagnostic("XML_EMITENTE_CNPJ_AUSENTE", "warning", "O XML nao trouxe um CNPJ valido do emitente para conferir o fornecedor."));
    return {
      fornecedorSuggestion: {
        status: "SEM_CNPJ_XML",
        nome: emitente,
        cnpj: null,
      },
      findings,
      suggestions,
      warnings,
    };
  }

  if (!input.fornecedor) {
    findings.push(
      diagnostic("FORNECEDOR_NAO_ENCONTRADO", "error", "Fornecedor nao encontrado para o CNPJ da NF. Cadastre ou selecione o fornecedor antes de importar.", {
        cnpj,
        emitente,
      })
    );
    return {
      fornecedorSuggestion: {
        status: "NAO_ENCONTRADO",
        nome: emitente,
        cnpj,
      },
      findings,
      suggestions,
      warnings,
    };
  }

  suggestions.push(
    diagnostic("FORNECEDOR_IDENTIFICADO", "info", "Fornecedor identificado para esta NF.", {
      fornecedor_id: input.fornecedor.id,
      nome: input.fornecedor.nome ?? emitente,
      cnpj,
    })
  );

  if (hasText(input.fornecedor.finalidade_padrao)) {
    suggestions.push(
      diagnostic("FORNECEDOR_FINALIDADE_PADRAO", "info", "Este fornecedor possui uma finalidade padrao que pode preencher o campo.", {
        fornecedor_id: input.fornecedor.id,
        finalidade_padrao: input.fornecedor.finalidade_padrao,
      })
    );
  }

  if (hasText(input.fornecedor.motivo_compra_padrao_id)) {
    suggestions.push(
      diagnostic("FORNECEDOR_MOTIVO_PADRAO", "info", "Este fornecedor possui uma classificacao/motivo padrao que pode preencher o campo.", {
        fornecedor_id: input.fornecedor.id,
        motivo_compra_padrao_id: input.fornecedor.motivo_compra_padrao_id,
      })
    );
  }

  return {
    fornecedorSuggestion: {
      status: "IDENTIFICADO",
      fornecedorId: input.fornecedor.id,
      nome: input.fornecedor.nome ?? emitente,
      cnpj,
      finalidadePadraoSugerida: input.fornecedor.finalidade_padrao ?? null,
      motivoPadraoSugeridoId: input.fornecedor.motivo_compra_padrao_id ?? null,
    },
    findings,
    suggestions,
    warnings,
  };
}

function analyzeItens(opts: {
  nfItems: NormalizedNfItem[];
  itemMap: Map<string, XmlImportItemInterno>;
  finalidadeKey: string;
  requiredItemFinalidades: Set<string>;
  autoCreateFinalidades: Set<string>;
}): {
  itemSuggestions: XmlImportItemSuggestion[];
  findings: XmlImportDiagnostic[];
  suggestions: XmlImportDiagnostic[];
  warnings: XmlImportDiagnostic[];
} {
  const findings: XmlImportDiagnostic[] = [];
  const suggestions: XmlImportDiagnostic[] = [];
  const warnings: XmlImportDiagnostic[] = [];
  const itemSuggestions: XmlImportItemSuggestion[] = [];
  const exigeCadastro = opts.requiredItemFinalidades.has(opts.finalidadeKey);
  const permiteAutocadastro = opts.autoCreateFinalidades.has(opts.finalidadeKey);

  if (opts.nfItems.length === 0) {
    findings.push(diagnostic("XML_SEM_ITENS", "error", "A NF nao possui itens para importar."));
    return { itemSuggestions, findings, suggestions, warnings };
  }

  let hasMissingWithoutUnit = false;

  for (const nfItem of opts.nfItems) {
    const internalItem = opts.itemMap.get(nfItem.codigoNormalizado);
    const itemFindings: XmlImportDiagnostic[] = [];
    const itemWarnings: XmlImportDiagnostic[] = [];
    const itemSuggestionDiagnostics: XmlImportDiagnostic[] = [];

    if (internalItem) {
      const diag = diagnostic("ITEM_INTERNO_ENCONTRADO", "info", "Item encontrado no cadastro interno.", {
        codigo_xml: nfItem.codigoOriginal,
        codigo_normalizado: nfItem.codigoNormalizado,
        item_id: internalItem.id,
        codigo_interno: internalItem.codigo_interno,
      });
      itemSuggestionDiagnostics.push(diag);
      suggestions.push(diag);
      itemSuggestions.push({
        index: nfItem.index,
        codigoOriginal: nfItem.codigoOriginal,
        codigoNormalizado: nfItem.codigoNormalizado,
        descricao: nfItem.descricao,
        quantidade: nfItem.quantidade,
        valorUnitario: nfItem.valorUnitario,
        status: "CADASTRADO",
        severity: "info",
        internalItem,
        findings: itemFindings,
        suggestions: itemSuggestionDiagnostics,
        warnings: itemWarnings,
      });
      continue;
    }

    hasMissingWithoutUnit = hasMissingWithoutUnit || !nfItem.unidade;

    if (exigeCadastro) {
      const diag = diagnostic("ITEM_NAO_CADASTRADO", "error", "Este item nao esta cadastrado. Cadastre ou vincule antes de importar.", {
        codigo_xml: nfItem.codigoOriginal,
        codigo_normalizado: nfItem.codigoNormalizado,
        descricao: nfItem.descricao,
        finalidade: opts.finalidadeKey,
      });
      itemFindings.push(diag);
      findings.push(diag);
    }

    if (permiteAutocadastro) {
      const diag = diagnostic("SUGERIR_CADASTRO_ITEM", "info", "Este item pode ser usado para preencher um cadastro novo.", {
        codigo_xml: nfItem.codigoOriginal,
        codigo_normalizado: nfItem.codigoNormalizado,
        descricao: nfItem.descricao,
      });
      itemSuggestionDiagnostics.push(diag);
      suggestions.push(diag);
    }

    if (!exigeCadastro && !permiteAutocadastro) {
      const diag = diagnostic("ITEM_NAO_CADASTRADO_SEM_BLOQUEIO", "warning", "Item ainda nao encontrado no cadastro interno para esta finalidade.", {
        codigo_xml: nfItem.codigoOriginal,
        codigo_normalizado: nfItem.codigoNormalizado,
        descricao: nfItem.descricao,
        finalidade: opts.finalidadeKey,
      });
      itemWarnings.push(diag);
      warnings.push(diag);
    }

    itemSuggestions.push({
      index: nfItem.index,
      codigoOriginal: nfItem.codigoOriginal,
      codigoNormalizado: nfItem.codigoNormalizado,
      descricao: nfItem.descricao,
      quantidade: nfItem.quantidade,
      valorUnitario: nfItem.valorUnitario,
      status: "NAO_CADASTRADO",
      severity: exigeCadastro ? "error" : permiteAutocadastro ? "info" : "warning",
      findings: itemFindings,
      suggestions: itemSuggestionDiagnostics,
      warnings: itemWarnings,
    });
  }

  if (hasMissingWithoutUnit) {
    warnings.push(
      diagnostic(
        "XML_UNIDADE_NAO_EXTRAIDA",
        "warning",
        "A unidade comercial do XML ainda nao esta disponivel para o assistente; novos itens podem aparecer como UN."
      )
    );
  }

  return { itemSuggestions, findings, suggestions, warnings };
}

function analyzePedidos(opts: {
  input: XmlImportAnalyzerInput;
  nfItems: NormalizedNfItem[];
  itemMap: Map<string, XmlImportItemInterno>;
  nfeTotal: number;
  params: Required<Pick<
    XmlImportAnalyzerParams,
    | "pedidoScoreMinimo"
    | "valorUnitarioToleranciaAbsoluta"
    | "valorUnitarioToleranciaPercentual"
    | "totalToleranciaAbsoluta"
    | "totalToleranciaPercentual"
  >>;
}): {
  pedidoSuggestion: XmlImportPedidoSuggestion | null;
  pedidoSuggestions: XmlImportPedidoSuggestion[];
  findings: XmlImportDiagnostic[];
  suggestions: XmlImportDiagnostic[];
  warnings: XmlImportDiagnostic[];
} {
  const findings: XmlImportDiagnostic[] = [];
  const suggestions: XmlImportDiagnostic[] = [];
  const warnings: XmlImportDiagnostic[] = [];
  const pedidos = opts.input.pedidosCandidatos ?? [];

  if (pedidos.length === 0) {
    return { pedidoSuggestion: null, pedidoSuggestions: [], findings, suggestions, warnings };
  }

  const scores = pedidos
    .map((pedido) => scorePedido(pedido, opts.nfItems, opts.itemMap, opts.input.fornecedor, opts.nfeTotal, opts.params))
    .sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return String(a.pedido.codigo ?? a.pedido.id).localeCompare(String(b.pedido.codigo ?? b.pedido.id));
    });

  const multiPedidoWarning = detectMultiplePedidoCandidates(scores, opts.nfItems);
  if (multiPedidoWarning) warnings.push(multiPedidoWarning);
  const multiPedidoSuggestions = buildMultiPedidoSuggestions({
    scores,
    nfItems: opts.nfItems,
    params: opts.params,
  });

  if (multiPedidoSuggestions.length > 1) {
    const pedidoRefs = multiPedidoSuggestions.map((pedido) => pedido.codigo ?? pedido.pedidoId);
    suggestions.push(
      diagnostic("PEDIDOS_CANDIDATOS_MULTIPLOS", "info", "A NF pode ser importada usando mais de um pedido de compra.", {
        pedidos: pedidoRefs,
        pedido_ids: multiPedidoSuggestions.map((pedido) => pedido.pedidoId),
        itens_combinados: multiPedidoSuggestions.reduce((sum, pedido) => sum + pedido.itemMatches.length, 0),
      })
    );
    const multiDivergencias = multiPedidoSuggestions.flatMap((pedido) => pedido.divergencias);
    findings.push(...multiDivergencias.filter((diag) => diag.severity === "error"));
    warnings.push(...multiDivergencias.filter((diag) => diag.severity === "warning"));
    return { pedidoSuggestion: null, pedidoSuggestions: multiPedidoSuggestions, findings, suggestions, warnings };
  }

  const best = scores[0] ?? null;
  if (!best || best.matchedCount === 0) {
    warnings.push(
      diagnostic("PEDIDO_SEM_ITENS_COMPATIVEIS", "warning", "Nenhum pedido aberto teve itens claramente compativeis com esta NF.", {
        melhor_score: best?.score ?? 0,
        pedidos_analisados: pedidos.length,
      })
    );
    return { pedidoSuggestion: null, pedidoSuggestions: [], findings, suggestions, warnings };
  }

  if (best.score < opts.params.pedidoScoreMinimo) {
    warnings.push(
      diagnostic("PEDIDO_CANDIDATO_FRACO", "warning", "Nenhum pedido aberto ficou compativel o suficiente para sugestao segura.", {
        score_minimo: opts.params.pedidoScoreMinimo,
        melhor_score: best?.score ?? 0,
        pedidos_analisados: pedidos.length,
      })
    );
    return { pedidoSuggestion: null, pedidoSuggestions: [], findings, suggestions, warnings };
  }

  const pedidoSuggestion: XmlImportPedidoSuggestion = {
    pedidoId: best.pedido.id,
    codigo: best.pedido.codigo ?? null,
    status: best.pedido.status ?? null,
    score: best.score,
    motivos: best.motivos,
    solicitanteUsuarioId: best.pedido.solicitante_usuario_id ?? null,
    itemMatches: best.matches,
    divergencias: best.divergencias,
  };

  suggestions.push(
    diagnostic("PEDIDO_CANDIDATO_PROVAVEL", "info", "Este pedido parece compativel com a nota.", {
      pedido_id: best.pedido.id,
      codigo: best.pedido.codigo ?? null,
      score: best.score,
    })
  );

  if (best.pedido.solicitante_usuario_id) {
    suggestions.push(
      diagnostic("SUGERIR_SOLICITANTE_DO_PEDIDO", "info", "O solicitante do pedido pode preencher o campo solicitante.", {
        pedido_id: best.pedido.id,
        solicitante_usuario_id: best.pedido.solicitante_usuario_id,
        solicitante_ja_selecionado: hasText(opts.input.solicitanteUsuarioId),
      })
    );
  }

  findings.push(...best.divergencias.filter((diag) => diag.severity === "error"));
  warnings.push(...best.divergencias.filter((diag) => diag.severity === "warning"));

  return { pedidoSuggestion, pedidoSuggestions: [pedidoSuggestion], findings, suggestions, warnings };
}

function addManualPedidoItemGuidance(opts: {
  pedidoSuggestion: XmlImportPedidoSuggestion | null;
  pedidoSuggestions?: XmlImportPedidoSuggestion[];
  itemSuggestions: XmlImportItemSuggestion[];
}): XmlImportDiagnostic[] {
  const suggestions: XmlImportDiagnostic[] = [];
  const pedidos = opts.pedidoSuggestions?.length
    ? opts.pedidoSuggestions
    : opts.pedidoSuggestion
      ? [opts.pedidoSuggestion]
      : [];
  if (pedidos.length === 0) return suggestions;

  for (const pedido of pedidos) {
    for (const match of pedido.itemMatches) {
      if (!match.manualItem) continue;

      const itemSuggestion = opts.itemSuggestions.find((item) => item.index === match.nfItemIndex);
      if (!itemSuggestion) continue;

      const details = {
        pedido_id: match.pedidoId,
        pedido_item_id: match.pedidoItemId,
        descricao_pedido: match.pedidoItemDescricao,
        origem_os_id: match.origemOsId,
        origem_os_numero: match.origemOsNumero,
        origem_os_label: match.origemOsLabel,
        codigo_xml: itemSuggestion.codigoOriginal,
        descricao_xml: itemSuggestion.descricao,
        similaridade_descricao: match.descricaoSimilarity,
      };

      const diag = itemSuggestion.status === "CADASTRADO"
        ? diagnostic(
            "VINCULAR_ITEM_INTERNO_A_ITEM_MANUAL_PEDIDO",
            "info",
            "Item interno encontrado. Considere vincular este cadastro ao item manual do pedido.",
            details
          )
        : diagnostic(
            "ITEM_NF_PARECE_ITEM_MANUAL_PEDIDO",
            "info",
            "Este item da NF parece corresponder a um item manual do pedido. Cadastre o item e depois vincule/corrija o item do pedido.",
            details
          );

      itemSuggestion.pedidoMatchPedidoId = pedido.pedidoId;
      itemSuggestion.pedidoMatchPedidoCodigo = pedido.codigo ?? null;
      itemSuggestion.pedidoMatchItemId = match.pedidoItemId;
      itemSuggestion.pedidoMatchDescricao = match.pedidoItemDescricao ?? null;
      itemSuggestion.pedidoMatchTipo = "DESCRICAO_MANUAL";
      itemSuggestion.pedidoMatchOsId = match.origemOsId ?? null;
      itemSuggestion.pedidoMatchOsNumero = match.origemOsNumero ?? null;
      itemSuggestion.pedidoMatchOsLabel = match.origemOsLabel ?? null;
      itemSuggestion.pedidoMatchScore = match.score;
      itemSuggestion.recommendedAction = itemSuggestion.status === "CADASTRADO"
        ? "Vincular cadastro existente ao item manual do pedido."
        : "Cadastrar item e vincular ao item manual do pedido.";
      itemSuggestion.suggestions.push(diag);
      suggestions.push(diag);
    }
  }

  return suggestions;
}

function addManualPedidoLinkBlockingFindings(opts: {
  pedidoSuggestion: XmlImportPedidoSuggestion | null;
  pedidoSuggestions?: XmlImportPedidoSuggestion[];
  itemSuggestions: XmlImportItemSuggestion[];
}): XmlImportDiagnostic[] {
  const pedidos = opts.pedidoSuggestions?.length
    ? opts.pedidoSuggestions
    : opts.pedidoSuggestion
      ? [opts.pedidoSuggestion]
      : [];
  if (pedidos.length === 0) return [];

  const pending = opts.itemSuggestions.filter(
    (item) => item.status === "CADASTRADO" && item.pedidoMatchTipo === "DESCRICAO_MANUAL" && item.pedidoMatchItemId
  );
  if (pending.length === 0) return [];

  const details = {
    pedidos: pedidos.map((pedido) => ({
      pedido_id: pedido.pedidoId,
      pedido_codigo: pedido.codigo ?? null,
    })),
    quantidade: pending.length,
    itens: pending.map((item) => ({
      codigo_xml: item.codigoOriginal,
      descricao_xml: item.descricao,
      pedido_item_id: item.pedidoMatchItemId ?? null,
      descricao_pedido: item.pedidoMatchDescricao ?? null,
      os_id: item.pedidoMatchOsId ?? null,
      os_label: item.pedidoMatchOsLabel ?? null,
    })),
  };

  const message =
    pending.length === 1
      ? "Vincule o item cadastrado ao item manual do pedido antes de importar."
      : `Vincule os ${pending.length} itens cadastrados aos itens manuais do pedido antes de importar.`;

  const globalFinding = diagnostic("VINCULAR_ITENS_MANUAIS_PEDIDO_OBRIGATORIO", "error", message, details);

  for (const item of pending) {
    item.severity = "error";
    item.findings.push(
      diagnostic(
        "VINCULAR_ITEM_MANUAL_PEDIDO_OBRIGATORIO",
        "error",
        "Este item ja esta cadastrado, mas o item manual correspondente no pedido ainda precisa ser vinculado.",
        {
          pedido_id: item.pedidoMatchPedidoId ?? pedidos[0]?.pedidoId ?? null,
          pedido_item_id: item.pedidoMatchItemId ?? null,
          codigo_xml: item.codigoOriginal,
          descricao_pedido: item.pedidoMatchDescricao ?? null,
        }
      )
    );
  }

  return [globalFinding];
}

function getPedidoMatchTipo(match: XmlImportPedidoItemMatch): XmlImportItemSuggestion["pedidoMatchTipo"] {
  if (match.manualItem) return "DESCRICAO_MANUAL";
  if (match.matchedBy.includes("item_id_xml") || match.matchedBy.includes("item_id_resolvido")) return "ITEM_ID";
  if (match.matchedBy.includes("codigo")) return "CODIGO";
  return null;
}

function enrichItemSuggestionsWithPedidoMatches(opts: {
  pedidoSuggestion: XmlImportPedidoSuggestion | null;
  pedidoSuggestions?: XmlImportPedidoSuggestion[];
  itemSuggestions: XmlImportItemSuggestion[];
}): void {
  const pedidos = opts.pedidoSuggestions?.length
    ? opts.pedidoSuggestions
    : opts.pedidoSuggestion
      ? [opts.pedidoSuggestion]
      : [];
  if (pedidos.length === 0) return;

  for (const pedido of pedidos) {
    for (const match of pedido.itemMatches) {
      const itemSuggestion = opts.itemSuggestions.find((item) => item.index === match.nfItemIndex);
      if (!itemSuggestion) continue;

      itemSuggestion.pedidoMatchPedidoId = match.pedidoId ?? itemSuggestion.pedidoMatchPedidoId ?? null;
      itemSuggestion.pedidoMatchPedidoCodigo = pedido.codigo ?? itemSuggestion.pedidoMatchPedidoCodigo ?? null;
      itemSuggestion.pedidoMatchItemId = match.pedidoItemId ?? itemSuggestion.pedidoMatchItemId ?? null;
      itemSuggestion.pedidoMatchDescricao = match.pedidoItemDescricao ?? itemSuggestion.pedidoMatchDescricao ?? null;
      itemSuggestion.pedidoMatchTipo = getPedidoMatchTipo(match) ?? itemSuggestion.pedidoMatchTipo ?? null;
      itemSuggestion.pedidoMatchOsId = match.origemOsId ?? itemSuggestion.pedidoMatchOsId ?? null;
      itemSuggestion.pedidoMatchOsNumero = match.origemOsNumero ?? itemSuggestion.pedidoMatchOsNumero ?? null;
      itemSuggestion.pedidoMatchOsLabel = match.origemOsLabel ?? itemSuggestion.pedidoMatchOsLabel ?? null;
      itemSuggestion.pedidoMatchScore = match.score ?? itemSuggestion.pedidoMatchScore ?? null;
    }
  }
}

function enrichUnmatchedItemSuggestionsWithManualPedidoItems(opts: {
  input: XmlImportAnalyzerInput;
  nfItems: NormalizedNfItem[];
  itemMap: Map<string, XmlImportItemInterno>;
  pedidoSuggestion: XmlImportPedidoSuggestion | null;
  itemSuggestions: XmlImportItemSuggestion[];
  params: Required<Pick<
    XmlImportAnalyzerParams,
    "valorUnitarioToleranciaAbsoluta" | "valorUnitarioToleranciaPercentual"
  >>;
}): void {
  if (!opts.pedidoSuggestion) return;

  const pedido = (opts.input.pedidosCandidatos ?? []).find((row) => row.id === opts.pedidoSuggestion?.pedidoId) ?? null;
  if (!pedido) return;

  const usedPedidoItemIds = new Set(
    opts.itemSuggestions
      .map((item) => String(item.pedidoMatchItemId ?? "").trim())
      .filter(Boolean)
  );
  const manualItems = (pedido.itens ?? []).filter((item) => isPedidoItemManual(item) && !usedPedidoItemIds.has(item.id));
  if (manualItems.length === 0) return;

  for (const itemSuggestion of opts.itemSuggestions) {
    if (itemSuggestion.pedidoMatchItemId) continue;

    const nfItem = opts.nfItems.find((item) => item.index === itemSuggestion.index);
    if (!nfItem) continue;

    const itemInterno = opts.itemMap.get(nfItem.codigoNormalizado);
    let best: XmlImportPedidoItemMatch | null = null;

    for (const pedidoItem of manualItems) {
      const current = scorePedidoItem(nfItem, pedido, pedidoItem, itemInterno, opts.params);
      if (!isPedidoItemMatchConfiavel(current)) continue;
      if (!best || current.score > best.score) best = current;
    }

    if (!best) continue;

    usedPedidoItemIds.add(best.pedidoItemId);
    const usedIndex = manualItems.findIndex((item) => item.id === best?.pedidoItemId);
    if (usedIndex >= 0) manualItems.splice(usedIndex, 1);

    itemSuggestion.pedidoMatchPedidoId = best.pedidoId;
    itemSuggestion.pedidoMatchPedidoCodigo = opts.pedidoSuggestion.codigo ?? null;
    itemSuggestion.pedidoMatchItemId = best.pedidoItemId;
    itemSuggestion.pedidoMatchDescricao = best.pedidoItemDescricao ?? null;
    itemSuggestion.pedidoMatchTipo = "DESCRICAO_MANUAL";
    itemSuggestion.pedidoMatchOsId = best.origemOsId ?? null;
    itemSuggestion.pedidoMatchOsNumero = best.origemOsNumero ?? null;
    itemSuggestion.pedidoMatchOsLabel = best.origemOsLabel ?? null;
    itemSuggestion.pedidoMatchScore = best.score;
    itemSuggestion.recommendedAction = itemSuggestion.status === "CADASTRADO"
      ? "Vincular cadastro existente ao item manual do pedido."
      : "Cadastrar item e vincular ao item manual do pedido.";

    if (manualItems.length === 0) return;
  }
}

function getPredominantOsSuggestion(pedidoSuggestion: XmlImportPedidoSuggestion | null): PredominantOsSuggestion | null {
  if (!pedidoSuggestion) return null;
  const counts = new Map<number, number>();
  const numeros = new Map<number, string | null>();
  const labels = new Map<number, string>();
  const matches = pedidoSuggestion.itemMatches;
  const matchesWithOs = matches.filter((match) => match.origemOsId && match.origemOsId > 0);
  if (matches.length === 0 || matchesWithOs.length !== matches.length) return null;

  for (const match of matchesWithOs) {
    const osId = Number(match.origemOsId);
    if (!Number.isFinite(osId) || osId <= 0) continue;
    counts.set(osId, (counts.get(osId) ?? 0) + 1);
    if (!numeros.has(osId)) numeros.set(osId, match.origemOsNumero ?? null);
    if (!labels.has(osId)) {
      labels.set(osId, match.origemOsLabel ?? (match.origemOsNumero ? `OS ${match.origemOsNumero}` : `OS ${osId}`));
    }
  }

  if (counts.size === 0 || matchesWithOs.length === 0) return null;

  const ranked = Array.from(counts.entries()).sort((a, b) => b[1] - a[1]);
  const [osId, count] = ranked[0] ?? [];
  if (!osId || !count) return null;

  if (count !== matches.length) return null;

  return {
    osId,
    osNumero: numeros.get(osId) ?? null,
    osLabel: labels.get(osId) ?? `OS ${osId}`,
  };
}

function getPedidoDestinoMistoSummary(pedidoSuggestion: XmlImportPedidoSuggestion | null): {
  itensOs: number;
  itensEstoque: number;
  osLabels: string[];
} | null {
  if (!pedidoSuggestion) return null;
  const matches = pedidoSuggestion.itemMatches;
  if (matches.length === 0) return null;

  const osLabels = new Set<string>();
  let itensOs = 0;
  let itensEstoque = 0;
  for (const match of matches) {
    const osId = Number(match.origemOsId ?? 0);
    if (Number.isFinite(osId) && osId > 0) {
      itensOs += 1;
      osLabels.add(match.origemOsLabel ?? (match.origemOsNumero ? `OS ${match.origemOsNumero}` : `OS ${osId}`));
    } else {
      itensEstoque += 1;
    }
  }

  if (itensOs === 0 || itensEstoque === 0) return null;
  return { itensOs, itensEstoque, osLabels: Array.from(osLabels) };
}

function previewDiagnosticMessages(items: XmlImportDiagnostic[], limit = 2): string {
  const messages = items.map((item) => item.message).filter(Boolean);
  if (messages.length === 0) return "";
  const preview = messages.slice(0, limit).join(" ");
  return messages.length > limit ? `${preview} Mais ${messages.length - limit} ocorrencia(s).` : preview;
}

function buildActionPlan(opts: {
  input: XmlImportAnalyzerInput;
  itemSuggestions: XmlImportItemSuggestion[];
  pedidoSuggestion: XmlImportPedidoSuggestion | null;
  pedidoSuggestions?: XmlImportPedidoSuggestion[];
}): XmlImportActionPlanItem[] {
  const actionPlan: XmlImportActionPlanItem[] = [];
  const pedido = opts.pedidoSuggestion;
  const pedidos = opts.pedidoSuggestions?.length
    ? opts.pedidoSuggestions
    : pedido
      ? [pedido]
      : [];

  if (pedidos.length > 1) {
    const pedidoRefs = pedidos.map((row) => String(row.codigo ?? row.pedidoId).trim()).filter(Boolean);
    const currentRefs = new Set(
      String(opts.input.pedidoCompraRefAtual ?? "")
        .split(/[,;\n]+/)
        .map((ref) => ref.trim())
        .filter(Boolean)
    );
    const pedidosJaAplicados = pedidoRefs.length > 0 && pedidoRefs.every((ref) => currentRefs.has(ref));

    if (pedidoRefs.length > 0 && !pedidosJaAplicados) {
      actionPlan.push({
        code: "APPLY_PEDIDOS_SUGERIDOS",
        severity: "info",
        message: `Use os pedidos sugeridos ${pedidoRefs.join(", ")} para vincular esta NF aos pedidos de compra.`,
        actionType: "APPLY_PEDIDO",
        payload: {
          pedidoRef: pedidoRefs.join(", "),
          pedidoRefs,
          pedidoIds: pedidos.map((row) => row.pedidoId),
          codigos: pedidos.map((row) => row.codigo ?? null),
        },
      });
    }

    const solicitantes = Array.from(
      new Set(pedidos.map((row) => String(row.solicitanteUsuarioId ?? "").trim()).filter(Boolean))
    );
    if (solicitantes.length === 1 && solicitantes[0] !== opts.input.solicitanteUsuarioId) {
      actionPlan.push({
        code: "APPLY_SOLICITANTE_PEDIDOS",
        severity: "info",
        message: "Use o solicitante dos pedidos para preencher o campo solicitante.",
        actionType: "APPLY_SOLICITANTE",
        payload: { usuarioId: solicitantes[0], pedidoIds: pedidos.map((row) => row.pedidoId) },
      });
    }
  } else if (pedido) {
    const pedidoRef = String(pedido.codigo ?? pedido.pedidoId ?? "").trim();
    const currentPedido = String(opts.input.pedidoCompraRefAtual ?? "").trim();
    const pedidoJaAplicado = Boolean(pedidoRef) &&
      [String(pedido.codigo ?? "").trim(), String(pedido.pedidoId ?? "").trim()].filter(Boolean).includes(currentPedido);

    if (pedidoRef && !pedidoJaAplicado) {
      actionPlan.push({
        code: "APPLY_PEDIDO_SUGERIDO",
        severity: "info",
        message: `Use o pedido sugerido ${pedido.codigo ?? pedido.pedidoId} para vincular esta NF ao pedido de compra.`,
        actionType: "APPLY_PEDIDO",
        payload: { pedidoRef, pedidoId: pedido.pedidoId, codigo: pedido.codigo ?? null },
      });
    }

    if (pedido.solicitanteUsuarioId && pedido.solicitanteUsuarioId !== opts.input.solicitanteUsuarioId) {
      actionPlan.push({
        code: "APPLY_SOLICITANTE_PEDIDO",
        severity: "info",
        message: "Use o solicitante do pedido para preencher o campo solicitante.",
        actionType: "APPLY_SOLICITANTE",
        payload: { usuarioId: pedido.solicitanteUsuarioId, pedidoId: pedido.pedidoId },
      });
    }

    const osSuggestion = getPredominantOsSuggestion(pedido);
    if (osSuggestion && Number(opts.input.osIdAtual ?? 0) !== osSuggestion.osId) {
      actionPlan.push({
        code: "APPLY_OS_PEDIDO",
        severity: "info",
        message: `Use a ${osSuggestion.osLabel} encontrada nos itens do pedido.`,
        actionType: "APPLY_OS",
        payload: {
          osId: osSuggestion.osId,
          osNumero: osSuggestion.osNumero,
          osLabel: osSuggestion.osLabel,
          pedidoId: pedido.pedidoId,
        },
      });
    }

    const destinoMisto = getPedidoDestinoMistoSummary(pedido);
    if (destinoMisto) {
      actionPlan.push({
        code: "PEDIDO_DESTINO_MISTO",
        severity: "info",
        message: `Pedido com destino misto: ${destinoMisto.itensOs} item(ns) seguem para ${destinoMisto.osLabels.join(", ")} e ${destinoMisto.itensEstoque} item(ns) ficam em estoque. A importacao seguira a origem de cada item do pedido.`,
        payload: {
          pedidoId: pedido.pedidoId,
          itensOs: destinoMisto.itensOs,
          itensEstoque: destinoMisto.itensEstoque,
          osLabels: destinoMisto.osLabels,
        },
      });
    }
  }

  if (!hasText(opts.input.motivoSelecionadoId)) {
    actionPlan.push({
      code: "SELECIONAR_MOTIVO",
      severity: "error",
      message: "Selecione a classificacao/motivo antes de importar.",
      actionType: "SELECIONAR_MOTIVO",
    });
  }

  const missingItems = opts.itemSuggestions.filter((item) => item.status === "NAO_CADASTRADO");
  if (missingItems.length > 0) {
    actionPlan.push({
      code: "CADASTRAR_ITENS_FALTANTES",
      severity: missingItems.some((item) => item.severity === "error") ? "error" : "warning",
      message: `Cadastre ${missingItems.length === 1 ? "o item faltante" : `os ${missingItems.length} itens faltantes`} antes de importar.`,
      actionType: "CADASTRAR_ITEM",
      payload: {
        quantidade: missingItems.length,
        codigos: missingItems.map((item) => item.codigoOriginal),
      },
    });
  }

  const manualMatches = opts.itemSuggestions.filter((item) => item.pedidoMatchTipo === "DESCRICAO_MANUAL");
  const manualMatchesCadastrados = manualMatches.filter((item) => item.status === "CADASTRADO");
  if (manualMatches.length > 0) {
    actionPlan.push({
      code: "VINCULAR_ITENS_MANUAIS_PEDIDO",
      severity: manualMatchesCadastrados.length > 0 ? "error" : missingItems.length > 0 ? "warning" : "info",
      message: manualMatchesCadastrados.length > 0
        ? "Vincule/corrija os itens manuais do pedido antes de importar."
        : missingItems.length > 0
        ? "Apos cadastrar os itens, vincule/corrija os itens manuais do pedido."
        : "Vincule/corrija os itens manuais do pedido com os cadastros internos encontrados.",
      actionType: "VINCULAR_ITEM_MANUAL_PEDIDO",
      payload: {
        quantidade: manualMatches.length,
        pedidoItens: manualMatches.map((item) => ({
          codigoXml: item.codigoOriginal,
          descricaoPedido: item.pedidoMatchDescricao ?? null,
          osId: item.pedidoMatchOsId ?? null,
          osNumero: item.pedidoMatchOsNumero ?? null,
          osLabel: item.pedidoMatchOsLabel ?? null,
        })),
      },
    });
  }

  const divergencias = pedidos.flatMap((row) => row.divergencias);
  const divergenciasValor = divergencias.filter((diag) => diag.code === "DIVERGENCIA_VALOR_UNITARIO");
  if (divergenciasValor.length > 0) {
    const hasValorBloqueante = divergenciasValor.some((diag) => diag.severity === "error");
    actionPlan.push({
      code: "CONFERIR_VALOR_UNITARIO",
      severity: hasValorBloqueante ? "error" : "warning",
      message: `Confira ${divergenciasValor.length === 1 ? "a divergencia" : `as ${divergenciasValor.length} divergencias`} de valor unitario entre NF e pedido. ${previewDiagnosticMessages(divergenciasValor)}`,
      actionType: "CONFERIR_DIVERGENCIA",
      payload: { tipo: "valor_unitario", divergencias: divergenciasValor.map((diag) => diag.details ?? {}) },
    });
  }

  const divergenciasQuantidadeParcial = divergencias.filter((diag) => diag.code === "QUANTIDADE_PARCIAL_PEDIDO");
  if (divergenciasQuantidadeParcial.length > 0) {
    actionPlan.push({
      code: "CONFERIR_QUANTIDADE_PARCIAL",
      severity: "error",
      message: `A NF atende parcialmente o saldo do pedido em ${divergenciasQuantidadeParcial.length} item(ns). Ajuste a quantidade do pedido antes de importar. ${previewDiagnosticMessages(divergenciasQuantidadeParcial)}`,
      actionType: "CONFERIR_DIVERGENCIA",
      payload: { tipo: "quantidade_parcial", divergencias: divergenciasQuantidadeParcial.map((diag) => diag.details ?? {}) },
    });
  }

  const divergenciasQuantidadeExcesso = divergencias.filter((diag) => diag.code === "QUANTIDADE_EXCEDE_PEDIDO");
  if (divergenciasQuantidadeExcesso.length > 0) {
    actionPlan.push({
      code: "CONFERIR_QUANTIDADE_EXCESSO",
      severity: "error",
      message: `A quantidade da NF excede o saldo do pedido em ${divergenciasQuantidadeExcesso.length} item(ns). Ajuste a quantidade do pedido antes de importar. ${previewDiagnosticMessages(divergenciasQuantidadeExcesso)}`,
      actionType: "CONFERIR_DIVERGENCIA",
      payload: { tipo: "quantidade_excesso", divergencias: divergenciasQuantidadeExcesso.map((diag) => diag.details ?? {}) },
    });
  }

  return actionPlan;
}

function calculateOverallScore(opts: {
  input: XmlImportAnalyzerInput;
  nfItems: NormalizedNfItem[];
  itemSuggestions: XmlImportItemSuggestion[];
  pedidoSuggestion: XmlImportPedidoSuggestion | null;
  pedidoSuggestions?: XmlImportPedidoSuggestion[];
  findings: XmlImportDiagnostic[];
  warnings: XmlImportDiagnostic[];
  requiredItemFinalidades: Set<string>;
  finalidadeKey: string;
  pedidosCount: number;
}): number {
  let score = 0;

  score += opts.input.fornecedor ? 20 : getEmitenteCnpj(opts.input.nfe) ? 0 : 5;

  score += hasText(opts.input.finalidadeSelecionada) ? 10 : 0;
  score += hasText(opts.input.motivoSelecionadoId) ? 10 : 0;
  score += hasText(opts.input.solicitanteUsuarioId) ? 10 : 0;

  if (opts.nfItems.length === 0) {
    score += 0;
  } else {
    const cadastrados = opts.itemSuggestions.filter((item) => item.status === "CADASTRADO").length;
    const exigeCadastro = opts.requiredItemFinalidades.has(opts.finalidadeKey);
    if (exigeCadastro) {
      score += (cadastrados / opts.nfItems.length) * 35;
    } else {
      score += 28 + (cadastrados / opts.nfItems.length) * 7;
    }
  }

  if (opts.pedidosCount === 0) {
    score += 15;
  } else {
    const pedidos = opts.pedidoSuggestions?.length
      ? opts.pedidoSuggestions
      : opts.pedidoSuggestion
        ? [opts.pedidoSuggestion]
        : [];
    const pedidoScore = pedidos.length > 0
      ? pedidos.reduce((sum, pedido) => sum + pedido.score, 0) / pedidos.length
      : 0;
    score += (pedidoScore / 100) * 15;
  }

  const hasError = opts.findings.some((finding) => finding.severity === "error");
  const warningPenalty = Math.min(12, opts.warnings.length * 3);
  const adjustedScore = score - warningPenalty;

  if (hasError) return Math.min(roundScore(adjustedScore), 64);
  if (opts.warnings.length > 0) return Math.min(roundScore(adjustedScore), 84);
  return roundScore(score);
}

export function analyzeXmlImport(input: XmlImportAnalyzerInput): XmlImportAnalyzerResult {
  const params = {
    pedidoScoreMinimo: input.parametros?.pedidoScoreMinimo ?? DEFAULT_PEDIDO_SCORE_MINIMO,
    valorUnitarioToleranciaAbsoluta: input.parametros?.valorUnitarioToleranciaAbsoluta ?? 0.05,
    valorUnitarioToleranciaPercentual: input.parametros?.valorUnitarioToleranciaPercentual ?? 0.03,
    totalToleranciaAbsoluta: input.parametros?.totalToleranciaAbsoluta ?? 1,
    totalToleranciaPercentual: input.parametros?.totalToleranciaPercentual ?? 0.08,
  };

  const requiredItemFinalidades = buildStringSet(
    input.parametros?.finalidadesExigemItemCadastrado,
    DEFAULT_REQUIRED_ITEM_FINALIDADES
  );
  const autoCreateFinalidades = buildStringSet(
    input.parametros?.finalidadesPermitemAutocadastro,
    DEFAULT_AUTO_CREATE_FINALIDADES
  );

  const nfItems = normalizeNfItems(input);
  const itemMap = buildItemMap(input.itensCadastradosPorCodigo);
  const finalidadeKey = normalizeFinalidade(input.finalidadeSelecionada);
  const nfeTotal = getNfeTotal(input.nfe, nfItems);

  const findings: XmlImportDiagnostic[] = [];
  const suggestions: XmlImportDiagnostic[] = [];
  const warnings: XmlImportDiagnostic[] = [];

  const fornecedorAnalysis = analyzeFornecedor(input);
  findings.push(...fornecedorAnalysis.findings);
  suggestions.push(...fornecedorAnalysis.suggestions);
  warnings.push(...fornecedorAnalysis.warnings);

  if (!finalidadeKey) {
    findings.push(diagnostic("FINALIDADE_OBRIGATORIA", "error", "Selecione a finalidade antes de importar."));
  }

  if (!hasText(input.motivoSelecionadoId)) {
    findings.push(diagnostic("MOTIVO_OBRIGATORIO", "error", "Selecione a classificacao/motivo antes de importar."));
  }

  if (!hasText(input.solicitanteUsuarioId)) {
    findings.push(diagnostic("SOLICITANTE_OBRIGATORIO", "error", "Selecione o solicitante antes de importar."));
  }

  const itemAnalysis = analyzeItens({
    nfItems,
    itemMap,
    finalidadeKey,
    requiredItemFinalidades,
    autoCreateFinalidades,
  });
  findings.push(...itemAnalysis.findings);
  suggestions.push(...itemAnalysis.suggestions);
  warnings.push(...itemAnalysis.warnings);

  const pedidoAnalysis = analyzePedidos({
    input,
    nfItems,
    itemMap,
    nfeTotal,
    params,
  });
  findings.push(...pedidoAnalysis.findings);
  suggestions.push(...pedidoAnalysis.suggestions);
  warnings.push(...pedidoAnalysis.warnings);

  enrichItemSuggestionsWithPedidoMatches({
    pedidoSuggestion: pedidoAnalysis.pedidoSuggestion,
    pedidoSuggestions: pedidoAnalysis.pedidoSuggestions,
    itemSuggestions: itemAnalysis.itemSuggestions,
  });

  enrichUnmatchedItemSuggestionsWithManualPedidoItems({
    input,
    nfItems,
    itemMap,
    pedidoSuggestion: pedidoAnalysis.pedidoSuggestion,
    itemSuggestions: itemAnalysis.itemSuggestions,
    params,
  });

  const manualPedidoGuidance = addManualPedidoItemGuidance({
    pedidoSuggestion: pedidoAnalysis.pedidoSuggestion,
    pedidoSuggestions: pedidoAnalysis.pedidoSuggestions,
    itemSuggestions: itemAnalysis.itemSuggestions,
  });
  suggestions.push(...manualPedidoGuidance);

  const manualPedidoBlockingFindings = addManualPedidoLinkBlockingFindings({
    pedidoSuggestion: pedidoAnalysis.pedidoSuggestion,
    pedidoSuggestions: pedidoAnalysis.pedidoSuggestions,
    itemSuggestions: itemAnalysis.itemSuggestions,
  });
  findings.push(...manualPedidoBlockingFindings);

  const actionPlan = buildActionPlan({
    input,
    itemSuggestions: itemAnalysis.itemSuggestions,
    pedidoSuggestion: pedidoAnalysis.pedidoSuggestion,
    pedidoSuggestions: pedidoAnalysis.pedidoSuggestions,
  });

  const status: XmlImportAnalyzerStatus = findings.some((finding) => finding.severity === "error")
    ? "BLOQUEADO"
    : warnings.length > 0
      ? "ATENCAO"
      : "OK";

  const score = calculateOverallScore({
    input,
    nfItems,
    itemSuggestions: itemAnalysis.itemSuggestions,
    pedidoSuggestion: pedidoAnalysis.pedidoSuggestion,
    pedidoSuggestions: pedidoAnalysis.pedidoSuggestions,
    findings,
    warnings,
    requiredItemFinalidades,
    finalidadeKey,
    pedidosCount: input.pedidosCandidatos?.length ?? 0,
  });

  return {
    status,
    score,
    findings,
    suggestions,
    warnings,
    fornecedorSuggestion: fornecedorAnalysis.fornecedorSuggestion,
    pedidoSuggestion: pedidoAnalysis.pedidoSuggestion,
    pedidoSuggestions: pedidoAnalysis.pedidoSuggestions,
    itemSuggestions: itemAnalysis.itemSuggestions,
    actionPlan,
  };
}
