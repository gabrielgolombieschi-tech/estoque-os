import { NextRequest } from "next/server";
import { getAuthSupabase, jsonError, resolveTenantEmpresa } from "@/app/api/compras/_lib";

export const runtime = "nodejs";

type AssistenteIAStatusPreco = "preco_atualizado" | "preco_antigo" | "preco_muito_antigo" | "sem_historico";
type AssistenteIADecisao = "aceitar" | "revisar" | "cotar_cadastrar" | "ignorar";
type AssistenteIATipoResultado = "produto_unico" | "composicao" | "equivalente" | "nao_encontrado" | "precisa_revisao";
type AssistenteIAPapelProduto =
  | "produto_principal"
  | "lateral"
  | "base_soleira"
  | "acessorio"
  | "equivalente"
  | "alternativa"
  | "outro";
type AssistenteIAGrupoDiagnostico =
  | "codigo_exato"
  | "codigo_parcial"
  | "mesma_familia"
  | "mesma_categoria"
  | "equivalente_tecnico"
  | "alternativa_fabricante"
  | "produto_principal"
  | "lateral"
  | "base_soleira"
  | "acessorio"
  | "equivalente"
  | "geral";
type CategoriaTecnicaAssistenteIA =
  | "soft_starter"
  | "rele_estado_solido"
  | "fonte_24v"
  | "armario_painel"
  | "borne"
  | "disjuntor"
  | "contator"
  | "clp"
  | "ihm"
  | "seguranca"
  | "sinalizacao"
  | "ventilacao"
  | "desconhecida";
type AssistenteIACategoriaTecnica = CategoriaTecnicaAssistenteIA;

type AssistenteIAEspecificacoesDetectadas = {
  familia?: string;
  correnteA?: number;
  correnteMotorA?: number;
  tensaoV?: number;
  tensaoMinV?: number;
  tensaoMaxV?: number;
  potenciaW?: number;
};

type AssistenteIAPlanoBuscaEspecificacoes = {
  tensaoV?: number;
  correnteA?: number;
  potenciaW?: number;
  familia?: string;
  modelo?: string;
};

type AssistenteIAPlanoBuscaPapel = "produto_principal" | "lateral" | "base_soleira" | "acessorio" | "equivalente" | "alternativa";

type AssistenteIAPlanoBuscaGrupo = {
  papel: AssistenteIAPlanoBuscaPapel;
  termosObrigatorios: string[];
  termosDesejaveis: string[];
  termosProibidos: string[];
  marcaPreferencial?: string;
  observacao: string;
};

type AssistenteIAPlanoBusca = {
  linha: number;
  categoriaTecnica: CategoriaTecnicaAssistenteIA;
  itemComposto: boolean;
  marcaPreferencial?: string;
  fabricantesAlternativos?: string[];
  dimensoes?: string[];
  especificacoes?: AssistenteIAPlanoBuscaEspecificacoes;
  gruposBusca: AssistenteIAPlanoBuscaGrupo[];
};

type AssistenteIAAnaliseTecnica = {
  categoriaTecnicaDetectada: AssistenteIACategoriaTecnica;
  especificacoesDetectadas: AssistenteIAEspecificacoesDetectadas;
  sinonimosTecnicos: string[];
};

type AssistenteIAItemPlanilha = {
  linha: number;
  itemId: number | null;
  qtd: number;
  componente: string;
  codigo: string;
  marca: string;
};

type AssistenteIACandidatoBanco = {
  produtoId: string;
  codigo: string;
  descricao: string;
  marca?: string;
  fornecedorNome?: string;
  grupo: AssistenteIAGrupoDiagnostico;
  pontuacaoBackend: number;
  scoreFinal: number;
  categoriaCandidatoDetectada: CategoriaTecnicaAssistenteIA;
  motivos: string[];
  penalidades: string[];
  ultimaCompraData?: string;
  ultimaCompraValorUnitario?: number;
  estoque?: number;
  statusPreco: AssistenteIAStatusPreco;
};

type AssistenteIAProdutoSelecionado = {
  produtoId: string;
  codigo: string;
  descricao: string;
  marca?: string;
  fornecedorNome?: string;
  qtdSugerida: number;
  papelNaComposicao: AssistenteIAPapelProduto;
  justificativa: string;
  origem?: "ia" | "planilha";
  ultimaCompraData?: string;
  ultimaCompraValorUnitario?: number;
  estoque?: number;
  statusPreco: AssistenteIAStatusPreco;
};

type AssistenteIACandidatoDiagnostico = {
  produtoId: string;
  codigo: string;
  descricao: string;
  fornecedorNome?: string;
  grupo: string;
  pontuacaoBackend: number;
  scoreFinal: number;
  categoriaCandidatoDetectada: CategoriaTecnicaAssistenteIA;
  motivos: string[];
  penalidades: string[];
};

type AssistenteIADiagnostico = {
  termosExtraidos: string[];
  dimensoesDetectadas: string[];
  codigoNormalizado?: string;
  marcaPriorizada?: string;
  categoriaTecnicaDetectada?: string;
  especificacoesDetectadas?: AssistenteIAEspecificacoesDetectadas;
  planoBusca?: AssistenteIAPlanoBusca;
  gruposDetectados: AssistenteIAGrupoDiagnostico[];
  candidatosResumo: AssistenteIACandidatoDiagnostico[];
  candidatosEnviadosParaIA: number;
  candidatosBancoAntesFiltro: number;
  candidatosAposCategoriaBase: number;
  candidatosRemovidosPorValidacao: number;
  candidatosRemovidosPorIncompatibilidade: number;
  candidatosRemovidosPorTermosProibidos: number;
  candidatosRemovidosPorScore: number;
  fallbackAcionado: boolean;
};

type AssistenteIAResultadoAnalise = {
  linha: number;
  qtdOriginal: number;
  componenteOriginal: string;
  codigoOriginal: string;
  marcaOriginal: string;
  tipoResultado: AssistenteIATipoResultado;
  produtosSelecionados: AssistenteIAProdutoSelecionado[];
  confianca: number;
  decisaoSugerida: AssistenteIADecisao;
  resumoIA: string;
  alertaTecnico?: string;
  termosBuscaUsados: string[];
  categoriaTecnicaDetectada?: string;
  especificacoesDetectadas?: AssistenteIAEspecificacoesDetectadas;
  diagnostico?: AssistenteIADiagnostico;
};

type ItemRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  descricao: string | null;
  categoria: string | null;
  subcategoria: string | null;
  fabricante: string | null;
  fornecedor_id: number | null;
  fornecedores?: { nome?: string | null } | Array<{ nome?: string | null }> | null;
};

type PedidoItemRow = {
  pedido_compra_id: string | null;
  item_id: number | null;
  valor_unitario: number | string | null;
  created_at: string | null;
};

type PedidoCompraRow = {
  id: string;
  created_at: string | null;
  status: string | null;
};

type EstoqueRow = {
  item_id: number | null;
  quantidade_atual: number | string | null;
};

type UltimaCompra = {
  data: string;
  valorUnitario: number;
};

type ScoredItem = {
  item: ItemRow;
  score: number;
  scoreBase: number;
  scoreFinal: number;
  categoriaCandidatoDetectada: CategoriaTecnicaAssistenteIA;
  motivos: string[];
  penalidades: string[];
};

type CandidateTechnicalEvaluation = {
  scoreDelta: number;
  motivos: string[];
  penalidades: string[];
  categoriaCandidatoDetectada: CategoriaTecnicaAssistenteIA;
  incompatibilidadeForte: boolean;
};

type CandidateSeed = {
  row: AssistenteIAItemPlanilha;
  planoBusca: AssistenteIAPlanoBusca;
  analiseTecnica: AssistenteIAAnaliseTecnica;
  termosBuscaUsados: string[];
  general: ScoredItem[];
  grupos: Partial<Record<AssistenteIAPapelProduto, ScoredItem[]>>;
  candidatosBancoAntesFiltro: number;
  candidatosAposCategoriaBase: number;
  candidatosRemovidosPorIncompatibilidade: number;
  candidatosRemovidosPorTermosProibidos: number;
  candidatosRemovidosPorScore: number;
  fallbackAcionado: boolean;
};

type CandidatePackage = {
  row: AssistenteIAItemPlanilha;
  planoBusca: AssistenteIAPlanoBusca;
  analiseTecnica: AssistenteIAAnaliseTecnica;
  termosBuscaUsados: string[];
  candidatosGerais: AssistenteIACandidatoBanco[];
  candidatosPorGrupo: Partial<Record<AssistenteIAPapelProduto, AssistenteIACandidatoBanco[]>>;
  diagnosticoBase: Omit<AssistenteIADiagnostico, "candidatosRemovidosPorValidacao">;
  candidatosBancoAntesFiltro: number;
  candidatosAposCategoriaBase: number;
  candidatosRemovidosPorIncompatibilidade: number;
  candidatosRemovidosPorTermosProibidos: number;
  candidatosRemovidosPorScore: number;
  fallbackAcionado: boolean;
};

type CandidateSearchResult = {
  general: ScoredItem[];
  grupos: Partial<Record<AssistenteIAPapelProduto, ScoredItem[]>>;
  candidatosBancoAntesFiltro: number;
  candidatosAposCategoriaBase: number;
  candidatosRemovidosPorIncompatibilidade: number;
  candidatosRemovidosPorTermosProibidos: number;
  candidatosRemovidosPorScore: number;
  fallbackAcionado: boolean;
};

type AuthResult = Awaited<ReturnType<typeof getAuthSupabase>>;
type AuthedSupabase = Extract<AuthResult, { supabase: unknown }>["supabase"];

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_ROWS = 200;
const MAX_GENERAL_CANDIDATES = 20;
const MAX_KNOWN_CATEGORY_CANDIDATES = 15;
const MAX_TECHNICAL_EQUIVALENTS = 5;
const MAX_GROUP_CANDIDATES = 10;
const MAX_DIAGNOSTIC_CANDIDATES = 30;

const SOFT_STARTER_SYNONYMS = [
  "soft-starter",
  "soft starter",
  "softstarter",
  "chave de partida estatica",
  "partida suave",
  "acionamento de motor",
  "regulador automatico para acionamento de motor",
  "SSW",
];
const SOFT_STARTER_FALLBACK_TERMS = ["softstarter", "soft starter", "soft-starter", "SSW", "acionamento motor", "partida", "WEG SSW", "WEG"];
const CATEGORY_LABELS: Record<AssistenteIACategoriaTecnica, string> = {
  soft_starter: "soft-starter",
  rele_estado_solido: "rele de estado solido",
  fonte_24v: "fonte 24V",
  armario_painel: "armario/painel",
  borne: "borne",
  disjuntor: "disjuntor",
  contator: "contator",
  clp: "CLP",
  ihm: "IHM",
  seguranca: "seguranca",
  sinalizacao: "sinalizacao",
  ventilacao: "ventilacao",
  desconhecida: "desconhecida",
};
const AI_NOT_CONFIGURED_MESSAGE = "IA não configurada. Configure a chave do provedor de IA no ambiente.";

const STOP_TERMS = new Set([
  "COM",
  "SEM",
  "PARA",
  "POR",
  "DOS",
  "DAS",
  "UMA",
  "UNO",
  "UND",
  "UNI",
  "UN",
  "MM",
  "CM",
  "MTS",
  "PAINEL",
  "ELETRICO",
  "ELETRICA",
  "TOTAL",
  "ALTURA",
  "LARGURA",
  "PROFUNDIDADE",
]);

const VALID_TIPOS = new Set<AssistenteIATipoResultado>([
  "produto_unico",
  "composicao",
  "equivalente",
  "nao_encontrado",
  "precisa_revisao",
]);

const VALID_DECISOES = new Set<AssistenteIADecisao>(["aceitar", "revisar", "cotar_cadastrar", "ignorar"]);
const VALID_PAPEIS = new Set<AssistenteIAPapelProduto>([
  "produto_principal",
  "lateral",
  "base_soleira",
  "acessorio",
  "equivalente",
  "alternativa",
  "outro",
]);
const VALID_PLANO_PAPEIS = new Set<AssistenteIAPlanoBuscaPapel>(["produto_principal", "lateral", "base_soleira", "acessorio", "equivalente", "alternativa"]);
const VALID_CATEGORIAS_TECNICAS = new Set<CategoriaTecnicaAssistenteIA>([
  "soft_starter",
  "rele_estado_solido",
  "fonte_24v",
  "armario_painel",
  "borne",
  "disjuntor",
  "contator",
  "clp",
  "ihm",
  "seguranca",
  "sinalizacao",
  "ventilacao",
  "desconhecida",
]);

function normalizeText(value: unknown): string {
  return String(value ?? "")
    .trim()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
}

function normalizeCompact(value: unknown): string {
  return normalizeText(value).replace(/[^A-Z0-9]+/g, "");
}

function normalizeCode(value: unknown): string {
  return normalizeCompact(value);
}

function toNumber(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : NaN;
}

function clampNumber(value: unknown, min: number, max: number): number {
  const parsed = toNumber(value);
  if (!Number.isFinite(parsed)) return min;
  return Math.min(max, Math.max(min, parsed));
}

function parsePayloadItemId(value: unknown): number | null {
  const raw = String(value ?? "").trim();
  if (!raw) return null;

  const compact = raw.replace(/\s+/g, "");
  const normalized = /^\d{1,3}(\.\d{3})+$/.test(compact) ? compact.replace(/\./g, "") : compact.replace(",", ".");
  const parsed = Number(normalized);
  if (Number.isInteger(parsed) && parsed > 0) return parsed;

  return null;
}

function hasPayloadValue(value: unknown): boolean {
  return value !== null && value !== undefined && String(value).trim() !== "";
}

function normalizeNullableText(value: unknown, maxLength = 500): string {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  return raw.slice(0, maxLength);
}

function unique(values: string[]): string[] {
  return Array.from(new Set(values.map((value) => value.trim()).filter(Boolean)));
}

function itemDescription(row: ItemRow): string {
  return String(row.nome ?? row.descricao ?? "").trim() || String(row.codigo_interno ?? "").trim() || `Item ${row.id}`;
}

function getFornecedorNome(row: ItemRow): string | null {
  const raw = row.fornecedores ?? null;
  const fornecedor = Array.isArray(raw) ? raw[0] ?? null : raw;
  const nome = String(fornecedor?.nome ?? "").trim();
  return nome || null;
}

function itemSearchText(row: ItemRow): string {
  return normalizeText(
    `${row.codigo_interno ?? ""} ${row.nome ?? ""} ${row.descricao ?? ""} ${row.categoria ?? ""} ${row.subcategoria ?? ""} ${row.fabricante ?? ""} ${
      getFornecedorNome(row) ?? ""
    }`
  );
}

function itemSearchCompact(row: ItemRow): string {
  return normalizeCompact(
    `${row.codigo_interno ?? ""} ${row.nome ?? ""} ${row.descricao ?? ""} ${row.categoria ?? ""} ${row.subcategoria ?? ""} ${row.fabricante ?? ""} ${
      getFornecedorNome(row) ?? ""
    }`
  );
}

function brandMatches(planilhaMarca: string, item: ItemRow | AssistenteIACandidatoBanco | AssistenteIAProdutoSelecionado): boolean {
  const marca = normalizeText(planilhaMarca);
  if (!marca) return false;
  const itemMarca = normalizeText("id" in item ? item.fabricante : item.marca);
  const fornecedor = "id" in item ? normalizeText(getFornecedorNome(item)) : normalizeText(item.fornecedorNome);
  return Boolean((itemMarca && itemMarca.includes(marca)) || (fornecedor && fornecedor.includes(marca)));
}

function containsTerm(text: string, compact: string, term: string): boolean {
  const normalized = normalizeText(term);
  const normalizedCompact = normalizeCompact(term);
  return Boolean((normalized && text.includes(normalized)) || (normalizedCompact && compact.includes(normalizedCompact)));
}

function hasAnyTerm(text: string, compact: string, terms: string[]): boolean {
  return terms.some((term) => containsTerm(text, compact, term));
}

function technicalSourceFromRow(row: AssistenteIAItemPlanilha): string {
  return `${row.componente} ${row.codigo} ${row.marca}`;
}

function technicalSourceFromItem(row: ItemRow | AssistenteIACandidatoBanco): string {
  if ("id" in row) {
    return `${row.codigo_interno ?? ""} ${row.nome ?? ""} ${row.descricao ?? ""} ${row.categoria ?? ""} ${row.subcategoria ?? ""} ${row.fabricante ?? ""} ${
      getFornecedorNome(row) ?? ""
    }`;
  }
  return `${row.codigo} ${row.descricao} ${row.marca ?? ""} ${row.fornecedorNome ?? ""}`;
}

function parseTechnicalNumber(value: string): number {
  const parsed = Number(value.replace(",", "."));
  return Number.isFinite(parsed) ? parsed : NaN;
}

function roundTechnicalNumber(value: number): number {
  return Math.round(value * 1000) / 1000;
}

function formatTechnicalNumber(value: number): string {
  return Number.isInteger(value) ? String(value) : String(roundTechnicalNumber(value)).replace(".", ",");
}

function detectTechnicalCategoryFromText(value: string): AssistenteIACategoriaTecnica {
  const text = normalizeText(value);
  const compact = normalizeCompact(value);
  const hasSoftStarter = hasAnyTerm(text, compact, SOFT_STARTER_SYNONYMS);
  const hasMotorDrive = text.includes("ACIONAMENTO") && text.includes("MOTOR");
  if (hasSoftStarter || hasMotorDrive || compact.includes("SSW")) return "soft_starter";

  const hasBorneBlocker = hasAnyTerm(text, compact, ["borne", "terminal", "passagem", "terra", "porta-fusivel", "porta fusivel"]);
  const hasSolidStateRelay = hasAnyTerm(text, compact, ["rele de estado solido", "estado solido", "serie 857", "857"]) || /\bSSR\b/.test(text);
  if (hasSolidStateRelay && !hasBorneBlocker) return "rele_estado_solido";

  const hasSinalizacao = hasAnyTerm(text, compact, ["campainha", "sinalizador", "botao", "botão", "torre", "sirene", "sensor"]);
  const hasFonte = hasAnyTerm(text, compact, ["fonte", "alimentacao"]);
  const hasFonteSpec = hasAnyTerm(text, compact, ["24V", "24VCC", "24VDC", "24DC", "10A", "240W"]);
  if (hasFonte && hasFonteSpec && !hasSinalizacao) return "fonte_24v";

  if (
    hasAnyTerm(text, compact, [
      "armario",
      "painel",
      "gabinete",
      "auto-portante",
      "auto portante",
      "Rittal",
      "VX",
      "TS",
      "AX",
      "base soleira",
      "soleira",
      "paredes laterais",
      "parede lateral",
    ])
  ) {
    return "armario_painel";
  }

  const hasBorne = hasAnyTerm(text, compact, ["borne", "terminal", "passagem", "terra", "porta-fusivel", "porta fusivel", "topjob", "2002", "2202", "WAGO"]);
  if (hasBorne && !hasSolidStateRelay) return "borne";
  if (hasAnyTerm(text, compact, ["disjuntor"])) return "disjuntor";
  if (hasAnyTerm(text, compact, ["contator"])) return "contator";
  if (hasAnyTerm(text, compact, ["CLP", "PLC"])) return "clp";
  if (hasAnyTerm(text, compact, ["IHM", "HMI"])) return "ihm";
  if (hasAnyTerm(text, compact, ["chave de seguranca", "intertravamento", "seguranca", "emergencia"])) return "seguranca";
  if (hasSinalizacao) return "sinalizacao";
  if (hasAnyTerm(text, compact, ["ventilador", "exaustor", "filtro ventilador", "ventilacao"])) return "ventilacao";

  return "desconhecida";
}

function extractTechnicalFamily(value: string, category?: AssistenteIACategoriaTecnica): string | undefined {
  const text = normalizeText(value);
  const compact = normalizeCompact(value);

  if (category === "soft_starter" || compact.includes("SSW")) {
    const match = compact.match(/SSW(\d{1,3})/);
    if (match?.[1]) return `SSW${match[1].length <= 2 ? match[1].padStart(2, "0") : match[1]}`;
  }

  if (category === "rele_estado_solido" || text.includes("SERIE") || compact.includes("857")) {
    const serieMatch = text.match(/\bSERIE\s*(\d{3,})\b/);
    if (serieMatch?.[1]) return serieMatch[1];
    const compactMatch = compact.match(/857\d*/);
    if (compactMatch?.[0]) return compactMatch[0].slice(0, 3);
  }

  return undefined;
}

function extractVoltageSpecs(text: string): Pick<AssistenteIAEspecificacoesDetectadas, "tensaoV" | "tensaoMinV" | "tensaoMaxV"> {
  const normalized = normalizeText(text);
  const rangeMatch = normalized.match(/\b(\d{2,4})\s*-\s*(\d{2,4})\s*V(?:CC|DC|CA|AC)?\b/);
  if (rangeMatch?.[1] && rangeMatch[2]) {
    const min = parseTechnicalNumber(rangeMatch[1]);
    const max = parseTechnicalNumber(rangeMatch[2]);
    if (Number.isFinite(min) && Number.isFinite(max)) return { tensaoMinV: Math.min(min, max), tensaoMaxV: Math.max(min, max) };
  }

  const singleMatch = normalized.match(/\b(\d{2,4})\s*V(?:CC|DC|CA|AC)?\b/);
  if (singleMatch?.[1]) {
    const tensaoV = parseTechnicalNumber(singleMatch[1]);
    if (Number.isFinite(tensaoV)) return { tensaoV };
  }

  return {};
}

function extractCurrentSpecs(text: string): Pick<AssistenteIAEspecificacoesDetectadas, "correnteA" | "correnteMotorA"> {
  const normalized = normalizeText(text);
  const result: Pick<AssistenteIAEspecificacoesDetectadas, "correnteA" | "correnteMotorA"> = {};
  const currentRe = /(\d+(?:[,.]\d+)?)\s*A\b/g;
  let match: RegExpExecArray | null;

  while ((match = currentRe.exec(normalized))) {
    const value = parseTechnicalNumber(match[1] ?? "");
    if (!Number.isFinite(value)) continue;
    const before = normalized.slice(Math.max(0, match.index - 28), match.index);
    const after = normalized.slice(match.index + match[0].length, Math.min(normalized.length, match.index + match[0].length + 10));
    if (before.includes("MOTOR") || /^\s*(?:DO|DE|PARA)?\s*MOTOR\b/.test(after)) {
      result.correnteMotorA ??= value;
      continue;
    }
    result.correnteA ??= value;
  }

  return result;
}

function extractPowerSpecs(text: string): Pick<AssistenteIAEspecificacoesDetectadas, "potenciaW"> {
  const normalized = normalizeText(text);
  const match = normalized.match(/\b(\d+(?:[,.]\d+)?)\s*(KW|W)\b/);
  if (!match?.[1] || !match[2]) return {};
  const value = parseTechnicalNumber(match[1]);
  if (!Number.isFinite(value)) return {};
  return { potenciaW: match[2] === "KW" ? roundTechnicalNumber(value * 1000) : value };
}

function analyzeTechnicalText(value: string): AssistenteIAAnaliseTecnica {
  const category = detectTechnicalCategoryFromText(value);
  const specs: AssistenteIAEspecificacoesDetectadas = {
    familia: extractTechnicalFamily(value, category),
    ...extractCurrentSpecs(value),
    ...extractVoltageSpecs(value),
    ...extractPowerSpecs(value),
  };

  return {
    categoriaTecnicaDetectada: category,
    especificacoesDetectadas: Object.fromEntries(Object.entries(specs).filter(([, specValue]) => specValue !== undefined)) as AssistenteIAEspecificacoesDetectadas,
    sinonimosTecnicos: category === "soft_starter" ? SOFT_STARTER_SYNONYMS : [],
  };
}

function analyzeTechnicalRow(row: AssistenteIAItemPlanilha): AssistenteIAAnaliseTecnica {
  return analyzeTechnicalText(technicalSourceFromRow(row));
}

function analyzeTechnicalItem(item: ItemRow | AssistenteIACandidatoBanco): AssistenteIAAnaliseTecnica {
  return analyzeTechnicalText(technicalSourceFromItem(item));
}

function detectarCategoriaDoProdutoBanco(produto: ItemRow | AssistenteIACandidatoBanco): CategoriaTecnicaAssistenteIA {
  return analyzeTechnicalItem(produto).categoriaTecnicaDetectada;
}

function defaultForbiddenTermsForCategory(category: CategoriaTecnicaAssistenteIA): string[] {
  switch (category) {
    case "soft_starter":
      return ["chave de seguranca", "intertravamento", "botao", "borne", "fonte", "campainha", "sensor", "disjuntor"];
    case "rele_estado_solido":
      return ["borne", "terminal", "conector", "terminacao", "jumper", "placa final", "disjuntor", "fonte", "campainha"];
    case "fonte_24v":
      return ["campainha", "sirene", "botao", "torre", "sinalizador", "rele", "borne", "sensor"];
    case "armario_painel":
      return ["disjuntor", "fonte", "rele", "borne", "campainha", "sensor"];
    default:
      return [];
  }
}

function sanitizeSearchTerms(value: unknown, max = 16): string[] {
  if (!Array.isArray(value)) return [];
  return unique(value.map((term) => normalizeNullableText(term, 80)).filter(Boolean)).slice(0, max);
}

function sanitizePlanCategory(value: unknown, fallback: CategoriaTecnicaAssistenteIA): CategoriaTecnicaAssistenteIA {
  const raw = String(value ?? "").trim() as CategoriaTecnicaAssistenteIA;
  return VALID_CATEGORIAS_TECNICAS.has(raw) ? raw : fallback;
}

function sanitizePlanPapel(value: unknown, fallback: AssistenteIAPlanoBuscaPapel): AssistenteIAPlanoBuscaPapel {
  const raw = String(value ?? "").trim() as AssistenteIAPlanoBuscaPapel;
  return VALID_PLANO_PAPEIS.has(raw) ? raw : fallback;
}

function planoSpecsFromAnalysis(analysis: AssistenteIAAnaliseTecnica): AssistenteIAPlanoBuscaEspecificacoes {
  const specs = analysis.especificacoesDetectadas;
  return {
    tensaoV: specs.tensaoV,
    correnteA: specs.correnteA,
    potenciaW: specs.potenciaW,
    familia: specs.familia,
    modelo: specs.familia,
  };
}

function sanitizePlanoSpecs(value: unknown, fallback: AssistenteIAPlanoBuscaEspecificacoes): AssistenteIAPlanoBuscaEspecificacoes {
  const record = getRecord(value) ?? {};
  const result: AssistenteIAPlanoBuscaEspecificacoes = { ...fallback };
  const tensaoV = toNumber(record.tensaoV);
  const correnteA = toNumber(record.correnteA);
  const potenciaW = toNumber(record.potenciaW);
  const familia = normalizeNullableText(record.familia, 80);
  const modelo = normalizeNullableText(record.modelo, 80);

  if (Number.isFinite(tensaoV) && tensaoV > 0) result.tensaoV = tensaoV;
  if (Number.isFinite(correnteA) && correnteA > 0) result.correnteA = correnteA;
  if (Number.isFinite(potenciaW) && potenciaW > 0) result.potenciaW = potenciaW;
  if (familia) result.familia = familia;
  if (modelo) result.modelo = modelo;
  return Object.fromEntries(Object.entries(result).filter(([, spec]) => spec !== undefined && spec !== "")) as AssistenteIAPlanoBuscaEspecificacoes;
}

function planoGroup(
  papel: AssistenteIAPlanoBuscaPapel,
  termosObrigatorios: string[],
  termosDesejaveis: string[],
  termosProibidos: string[],
  marcaPreferencial: string | undefined,
  observacao: string
): AssistenteIAPlanoBuscaGrupo {
  return {
    papel,
    termosObrigatorios: unique(termosObrigatorios).slice(0, 16),
    termosDesejaveis: unique(termosDesejaveis).slice(0, 20),
    termosProibidos: unique(termosProibidos).slice(0, 16),
    marcaPreferencial,
    observacao,
  };
}

function buildFallbackPlanoBusca(row: AssistenteIAItemPlanilha): AssistenteIAPlanoBusca {
  const analysis = analyzeTechnicalRow(row);
  const category = analysis.categoriaTecnicaDetectada;
  const marca = row.marca.trim() || undefined;
  const specs = planoSpecsFromAnalysis(analysis);
  const dimensoes = extractDetectedDimensions(row.componente);
  const forbidden = defaultForbiddenTermsForCategory(category);
  const text = normalizeText(`${row.componente} ${row.codigo} ${row.marca}`);
  const groups: AssistenteIAPlanoBuscaGrupo[] = [];

  if (category === "armario_painel") {
    groups.push(
      planoGroup(
        "produto_principal",
        ["armario", "gabinete", "painel"],
        unique([marca ?? "", ...dimensoes.flatMap((dimension) => [dimension, ...dimension.split("x")]), "auto portante", "metalico", "Rittal", "VX", "TS", "AX"]),
        forbidden,
        marca,
        "Buscar o corpo principal do armario/gabinete, nao acessorios isolados."
      )
    );
    groups.push(
      planoGroup("lateral", ["parede lateral", "chapa lateral", "lateral"], unique([marca ?? "", "Rittal", "VX", "TS", "AX"]), forbidden, marca, "Buscar laterais/chapas laterais quando existirem.")
    );
    if (text.includes("BASE") || text.includes("SOLEIRA") || text.includes("SOCO")) {
      groups.push(
        planoGroup("base_soleira", ["base soleira", "soleira", "soco"], unique([marca ?? "", "Rittal", "VX", "TS", "AX"]), forbidden, marca, "Buscar base soleira como item separado da composicao.")
      );
    }
  } else if (category === "soft_starter") {
    groups.push(
      planoGroup(
        "produto_principal",
        ["softstarter", "soft-starter", "SSW"],
        unique([marca ?? "", "acionamento de motor", specs.familia ?? "", specs.modelo ?? ""]),
        forbidden,
        marca,
        "Buscar soft-starter ou equivalente da mesma categoria."
      )
    );
  } else if (category === "rele_estado_solido") {
    groups.push(
      planoGroup(
        "produto_principal",
        ["estado solido", "rele estado solido", "857"],
        unique([marca ?? "", specs.familia ?? "", "24 VDC", "857-724"]),
        forbidden,
        marca,
        "Buscar rele de estado solido; bornes WAGO nao sao equivalentes."
      )
    );
  } else if (category === "fonte_24v") {
    groups.push(
      planoGroup(
        "produto_principal",
        ["fonte", "alimentacao"],
        unique([marca ?? "", "24VDC", "24VCC", "10A", "240W", "TRIO", "QUINT", "PS-EE"]),
        forbidden,
        marca,
        "Buscar fonte 24V, nao sinalizadores ou campainhas 24V."
      )
    );
  } else {
    groups.push(
      planoGroup(
        "produto_principal",
        extractTechnicalTerms(row).slice(0, 6),
        unique([marca ?? "", ...technicalSpecTerms(analysis)]),
        forbidden,
        marca,
        "Buscar produto principal tecnicamente compativel."
      )
    );
  }

  return {
    linha: row.linha,
    categoriaTecnica: category,
    itemComposto: groups.length > 1,
    marcaPreferencial: marca,
    fabricantesAlternativos: [],
    dimensoes,
    especificacoes: specs,
    gruposBusca: groups,
  };
}

function sanitizePlanoBuscaGrupo(value: unknown, fallback: AssistenteIAPlanoBuscaGrupo, planCategory: CategoriaTecnicaAssistenteIA): AssistenteIAPlanoBuscaGrupo {
  const record = getRecord(value);
  if (!record) return fallback;
  const termosProibidos = unique([...sanitizeSearchTerms(record.termosProibidos), ...defaultForbiddenTermsForCategory(planCategory)]).slice(0, 18);
  return {
    papel: sanitizePlanPapel(record.papel, fallback.papel),
    termosObrigatorios: sanitizeSearchTerms(record.termosObrigatorios).length > 0 ? sanitizeSearchTerms(record.termosObrigatorios) : fallback.termosObrigatorios,
    termosDesejaveis: sanitizeSearchTerms(record.termosDesejaveis).length > 0 ? sanitizeSearchTerms(record.termosDesejaveis, 20) : fallback.termosDesejaveis,
    termosProibidos: termosProibidos.length > 0 ? termosProibidos : fallback.termosProibidos,
    marcaPreferencial: normalizeNullableText(record.marcaPreferencial, 80) || fallback.marcaPreferencial,
    observacao: normalizeNullableText(record.observacao, 300) || fallback.observacao,
  };
}

function sanitizePlanoBusca(value: unknown, row: AssistenteIAItemPlanilha): AssistenteIAPlanoBusca {
  const fallback = buildFallbackPlanoBusca(row);
  const record = getRecord(value);
  if (!record) return fallback;

  const category = sanitizePlanCategory(record.categoriaTecnica, fallback.categoriaTecnica);
  const rawGroups = Array.isArray(record.gruposBusca) ? record.gruposBusca : [];
  const groupsFallback = fallback.gruposBusca;
  const groups =
    rawGroups.length > 0
      ? rawGroups
          .slice(0, 8)
          .map((group, index) => sanitizePlanoBuscaGrupo(group, groupsFallback[index] ?? groupsFallback[0], category))
          .filter((group) => group.termosObrigatorios.length > 0 || group.termosDesejaveis.length > 0)
      : groupsFallback;

  return {
    linha: row.linha,
    categoriaTecnica: category,
    itemComposto: typeof record.itemComposto === "boolean" ? record.itemComposto : groups.length > 1 || fallback.itemComposto,
    marcaPreferencial: normalizeNullableText(record.marcaPreferencial, 80) || fallback.marcaPreferencial,
    fabricantesAlternativos: sanitizeSearchTerms(record.fabricantesAlternativos, 8),
    dimensoes: sanitizeSearchTerms(record.dimensoes, 6).length > 0 ? sanitizeSearchTerms(record.dimensoes, 6) : fallback.dimensoes,
    especificacoes: sanitizePlanoSpecs(record.especificacoes, fallback.especificacoes ?? {}),
    gruposBusca: groups.length > 0 ? groups : groupsFallback,
  };
}

function sanitizePlanosBusca(aiPayload: Record<string, unknown>, rows: AssistenteIAItemPlanilha[]): Map<number, AssistenteIAPlanoBusca> {
  const rawPlanos = Array.isArray(aiPayload.planos) ? aiPayload.planos : [];
  const rawByLinha = new Map<number, unknown>();
  for (const rawPlan of rawPlanos) {
    const record = getRecord(rawPlan);
    const linha = Number(record?.linha ?? 0);
    if (Number.isFinite(linha) && linha > 0) rawByLinha.set(linha, rawPlan);
  }

  const planos = new Map<number, AssistenteIAPlanoBusca>();
  for (const row of rows) {
    planos.set(row.linha, sanitizePlanoBusca(rawByLinha.get(row.linha), row));
  }
  return planos;
}

function analysisFromPlanoBusca(row: AssistenteIAItemPlanilha, plano: AssistenteIAPlanoBusca): AssistenteIAAnaliseTecnica {
  const fallback = analyzeTechnicalRow(row);
  return {
    categoriaTecnicaDetectada: plano.categoriaTecnica,
    especificacoesDetectadas: {
      ...fallback.especificacoesDetectadas,
      familia: plano.especificacoes?.familia ?? plano.especificacoes?.modelo ?? fallback.especificacoesDetectadas.familia,
      correnteA: plano.especificacoes?.correnteA ?? fallback.especificacoesDetectadas.correnteA,
      tensaoV: plano.especificacoes?.tensaoV ?? fallback.especificacoesDetectadas.tensaoV,
      potenciaW: plano.especificacoes?.potenciaW ?? fallback.especificacoesDetectadas.potenciaW,
    },
    sinonimosTecnicos: plano.categoriaTecnica === "soft_starter" ? SOFT_STARTER_SYNONYMS : fallback.sinonimosTecnicos,
  };
}

function termosBuscaFromPlano(row: AssistenteIAItemPlanilha, plano: AssistenteIAPlanoBusca, analysis: AssistenteIAAnaliseTecnica): string[] {
  return unique([
    ...extractTechnicalTerms(row),
    ...(plano.marcaPreferencial ? [plano.marcaPreferencial] : []),
    ...(plano.fabricantesAlternativos ?? []),
    ...(plano.dimensoes ?? []),
    ...technicalSpecTerms(analysis),
    ...plano.gruposBusca.flatMap((grupo) => [...grupo.termosObrigatorios, ...grupo.termosDesejaveis]),
  ]).slice(0, 60);
}

function itemMatchesAnySearchTerm(item: ItemRow, terms: string[]): boolean {
  const text = itemSearchText(item);
  const compact = itemSearchCompact(item);
  return terms.some((term) => containsTerm(text, compact, term));
}

function itemMatchesForbiddenTerms(item: ItemRow, terms: string[]): boolean {
  return terms.length > 0 && itemMatchesAnySearchTerm(item, terms);
}

function hasFonteBaseTerms(text: string, compact: string): boolean {
  return hasAnyTerm(text, compact, ["fonte", "alimentacao", "power supply"]) || text.includes("PS-") || compact.includes("TRIOPS") || compact.includes("QUINTPS");
}

function hasReleEstadoSolidoBaseTerms(text: string, compact: string): boolean {
  const hasEstadoSolido = hasAnyTerm(text, compact, [
    "estado solido",
    "rele de estado solido",
    "rele estado solido",
    "relÃ© de estado sÃ³lido",
    "relÃ© estado sÃ³lido",
  ]);
  const hasSsr = /\bSSR\b/.test(text);
  const has857724 = text.includes("857-724") || compact.includes("857724");
  const has857RelayModule =
    compact.includes("857") &&
    hasAnyTerm(text, compact, ["rele", "relÃ©", "reles", "relÃ©s", "modulo de rele", "mÃ³dulo de relÃ©", "modulo reles", "modulo de reles"]);
  return hasEstadoSolido || hasSsr || has857724 || has857RelayModule;
}

function hasArmarioPrincipalTerms(text: string, compact: string): boolean {
  return hasAnyTerm(text, compact, ["armario", "armÃ¡rio", "gabinete", "painel", "TS", "VX", "AX"]);
}

function hasArmarioLateralTerms(text: string, compact: string): boolean {
  return hasAnyTerm(text, compact, ["parede lateral", "paredes laterais", "chapa lateral", "chapas laterais"]);
}

function hasArmarioBaseSoleiraTerms(text: string, compact: string): boolean {
  return hasAnyTerm(text, compact, ["base soleira", "soleira", "soco"]);
}

function candidateMatchesCategoriaBase(item: ItemRow, category: CategoriaTecnicaAssistenteIA, papel: AssistenteIAPlanoBuscaPapel): boolean {
  const text = itemSearchText(item);
  const compact = itemSearchCompact(item);

  switch (category) {
    case "soft_starter":
      return hasSoftStarterTerms(text, compact);
    case "fonte_24v":
      return hasFonteBaseTerms(text, compact);
    case "rele_estado_solido":
      return hasReleEstadoSolidoBaseTerms(text, compact);
    case "armario_painel":
      if (papel === "lateral") return hasArmarioLateralTerms(text, compact);
      if (papel === "base_soleira") return hasArmarioBaseSoleiraTerms(text, compact);
      if (papel === "produto_principal") {
        if (hasArmarioBaseSoleiraTerms(text, compact) || hasArmarioLateralTerms(text, compact)) return false;
        return hasArmarioPrincipalTerms(text, compact);
      }
      return hasArmarioPrincipalTerms(text, compact) || hasArmarioLateralTerms(text, compact) || hasArmarioBaseSoleiraTerms(text, compact);
    default:
      return true;
  }
}

function candidateMatchesCategoriaFallback(item: ItemRow, category: CategoriaTecnicaAssistenteIA, papel: AssistenteIAPlanoBuscaPapel): boolean {
  const text = itemSearchText(item);
  const compact = itemSearchCompact(item);
  switch (category) {
    case "soft_starter":
      return hasAnyTerm(text, compact, ["SSW", "softstarter", "soft starter", "soft-starter"]);
    case "fonte_24v":
      return hasAnyTerm(text, compact, ["fonte", "alimentacao"]);
    case "rele_estado_solido":
      return hasAnyTerm(text, compact, ["estado solido", "rele de estado solido"]) || text.includes("857-724") || compact.includes("857724");
    case "armario_painel":
      return candidateMatchesCategoriaBase(item, category, papel);
    default:
      return candidateMatchesCategoriaBase(item, category, papel);
  }
}

function candidateHasForbiddenForCategory(
  item: ItemRow,
  category: CategoriaTecnicaAssistenteIA,
  papel: AssistenteIAPlanoBuscaPapel,
  termosProibidos: string[]
): boolean {
  const text = itemSearchText(item);
  const compact = itemSearchCompact(item);
  const blockedByPlan = itemMatchesForbiddenTerms(item, termosProibidos);

  switch (category) {
    case "soft_starter":
      return !hasSoftStarterTerms(text, compact) && hasAnyTerm(text, compact, termosProibidos);
    case "fonte_24v":
      return !hasFonteBaseTerms(text, compact) && hasAnyTerm(text, compact, termosProibidos);
    case "rele_estado_solido":
      return hasAnyTerm(text, compact, [
        "borne",
        "terminal",
        "conector",
        "jumper",
        "placa final",
        "terminacao",
        "terminaÃ§Ã£o",
        "engate rapido",
        "engate rÃ¡pido",
        "prensa cabo",
        "disjuntor",
        "fonte",
        "campainha",
      ]);
    case "armario_painel":
      if (papel === "produto_principal" && (hasArmarioBaseSoleiraTerms(text, compact) || hasArmarioLateralTerms(text, compact))) return true;
      if (papel === "lateral" && hasArmarioBaseSoleiraTerms(text, compact) && !hasArmarioLateralTerms(text, compact)) return true;
      if (papel === "base_soleira" && hasArmarioLateralTerms(text, compact) && !hasArmarioBaseSoleiraTerms(text, compact)) return true;
      return blockedByPlan && !candidateMatchesCategoriaBase(item, category, papel);
    default:
      return blockedByPlan;
  }
}

function candidateFamilyText(item: ItemRow): string {
  const compact = itemSearchCompact(item);
  const softStarter = compact.match(/SSW\d{2,3}/);
  if (softStarter?.[0]) return softStarter[0];
  const serie857 = compact.match(/857\d{0,3}/);
  if (serie857?.[0]) return serie857[0];
  return "";
}

function textHasTenAmpHint(text: string, compact: string): boolean {
  return hasAnyTerm(text, compact, ["10A", "10 A"]) || /\/\s*10\b/.test(text);
}

function addCategoryScore(
  item: ItemRow,
  row: AssistenteIAItemPlanilha,
  plano: AssistenteIAPlanoBusca,
  grupo: AssistenteIAPlanoBuscaGrupo,
  rowAnalysis: AssistenteIAAnaliseTecnica,
  motivos: string[]
): number {
  const text = itemSearchText(item);
  const compact = itemSearchCompact(item);
  const candidateAnalysis = analyzeTechnicalItem(item);
  const candidateSpecs = candidateAnalysis.especificacoesDetectadas;
  const requestedSpecs = rowAnalysis.especificacoesDetectadas;
  let score = 0;
  const add = (value: number, motivo: string) => {
    score += value;
    motivos.push(motivo);
  };

  switch (plano.categoriaTecnica) {
    case "soft_starter": {
      if (hasAnyTerm(text, compact, ["softstarter", "soft starter", "soft-starter"])) add(100, "categoria base softstarter");
      if (containsTerm(text, compact, "SSW")) add(100, "familia SSW encontrada");
      if (brandMatches(row.marca, item) || brandMatches(plano.marcaPreferencial ?? "", item) || containsTerm(text, compact, "WEG")) add(50, "marca WEG/preferencial encontrada");
      if (candidateFamilyText(item).match(/^SSW(?:07|08|900)$/)) add(40, "familia proxima SSW07/SSW08/SSW900");
      if (currentCompatibility(requestedSpecs, candidateSpecs) === "igual_ou_superior") add(40, "corrente igual ou superior");
      if (voltageCompatibility(requestedSpecs, candidateSpecs) === "compativel") add(30, "tensao compativel");
      break;
    }
    case "fonte_24v": {
      if (containsTerm(text, compact, "fonte")) add(120, "categoria base fonte");
      if (hasAnyTerm(text, compact, ["alimentacao", "alimentaÃ§Ã£o"])) add(80, "texto contem alimentacao");
      if (hasFonte24VTerms(text, compact)) add(80, "saida 24VDC/24VCC");
      if (textHasTenAmpHint(text, compact)) add(80, "corrente 10A ou /10 encontrada");
      if (hasAnyTerm(text, compact, ["240W", "240 W"])) add(60, "potencia 240W encontrada");
      if (hasAnyTerm(text, compact, ["480W", "480 W", "20A", "20 A"])) add(40, "potencia/corrente superior para revisao");
      if (hasAnyTerm(text, compact, ["Phoenix", "TRIO", "QUINT", "PS-EE"]) || brandMatches(row.marca, item) || brandMatches(plano.marcaPreferencial ?? "", item)) {
        add(50, "fabricante/linha preferencial encontrada");
      }
      break;
    }
    case "rele_estado_solido": {
      if (hasAnyTerm(text, compact, ["estado solido", "estado sÃ³lido", "rele de estado solido", "relÃ© de estado sÃ³lido"])) {
        add(140, "categoria base rele de estado solido");
      }
      if (text.includes("857-724") || compact.includes("857724")) add(100, "codigo/familia 857-724 encontrada");
      if (brandMatches(row.marca, item) || brandMatches(plano.marcaPreferencial ?? "", item) || containsTerm(text, compact, "WAGO")) add(60, "marca WAGO/preferencial encontrada");
      if (hasFonte24VTerms(text, compact)) add(40, "tensao 24VDC encontrada");
      break;
    }
    case "armario_painel": {
      if (grupo.papel === "produto_principal" && hasArmarioPrincipalTerms(text, compact)) add(140, "produto principal armario/gabinete/painel");
      if (grupo.papel === "lateral" && hasArmarioLateralTerms(text, compact)) add(140, "lateral identificada");
      if (grupo.papel === "base_soleira" && hasArmarioBaseSoleiraTerms(text, compact)) add(140, "base soleira identificada");
      if (extractDimensionTerms(row.componente).some((dimension) => compact.includes(normalizeCompact(dimension)))) add(80, "dimensao bate parcialmente");
      if (brandMatches(row.marca, item) || brandMatches(plano.marcaPreferencial ?? "", item) || containsTerm(text, compact, "Rittal")) add(50, "marca Rittal/preferencial encontrada");
      if (hasAnyTerm(text, compact, ["TS", "VX", "AX"])) add(40, "familia TS/VX/AX");
      break;
    }
    default:
      break;
  }

  return score;
}

function scoreItemForPlanoGrupo(
  item: ItemRow,
  row: AssistenteIAItemPlanilha,
  plano: AssistenteIAPlanoBusca,
  grupo: AssistenteIAPlanoBuscaGrupo,
  termosBuscaUsados: string[],
  rowAnalysis: AssistenteIAAnaliseTecnica
): ScoredItem {
  const text = itemSearchText(item);
  const compact = itemSearchCompact(item);
  const base = buildScoredItem(item, row, termosBuscaUsados, rowAnalysis);
  const requiredMatches = grupo.termosObrigatorios.filter((term) => containsTerm(text, compact, term));
  const desiredMatches = grupo.termosDesejaveis.filter((term) => containsTerm(text, compact, term));
  let scoreFinal = base.scoreFinal + requiredMatches.length * 20 + desiredMatches.length * 10;
  const motivos = [...base.motivos];
  const penalidades = [...base.penalidades];

  if (requiredMatches.length > 0) motivos.push(`obrigatorios do plano: ${requiredMatches.slice(0, 4).join(", ")}`);
  if (desiredMatches.length > 0) motivos.push(`desejaveis do plano: ${desiredMatches.slice(0, 4).join(", ")}`);
  scoreFinal += addCategoryScore(item, row, plano, grupo, rowAnalysis, motivos);
  if (grupo.marcaPreferencial && brandMatches(grupo.marcaPreferencial, item)) {
    scoreFinal += 35;
    motivos.push(`marca preferencial ${grupo.marcaPreferencial}`);
  } else if (plano.marcaPreferencial && brandMatches(plano.marcaPreferencial, item)) {
    scoreFinal += 25;
    motivos.push(`marca preferencial ${plano.marcaPreferencial}`);
  }

  return { ...base, score: scoreFinal, scoreFinal, motivos: unique(motivos).slice(0, 10), penalidades: unique(penalidades).slice(0, 10) };
}

function groupPapelToProdutoPapel(papel: AssistenteIAPlanoBuscaPapel): AssistenteIAPapelProduto {
  return papel;
}

function technicalSpecTerms(analysis: AssistenteIAAnaliseTecnica): string[] {
  const specs = analysis.especificacoesDetectadas;
  const terms: string[] = [];
  if (specs.familia) terms.push(specs.familia);
  if (typeof specs.correnteA === "number") terms.push(`${formatTechnicalNumber(specs.correnteA)}A`, `${formatTechnicalNumber(specs.correnteA)} A`);
  if (typeof specs.correnteMotorA === "number") terms.push(`${formatTechnicalNumber(specs.correnteMotorA)}A`, `${formatTechnicalNumber(specs.correnteMotorA)} A`);
  if (typeof specs.tensaoV === "number") terms.push(`${formatTechnicalNumber(specs.tensaoV)}V`, `${formatTechnicalNumber(specs.tensaoV)} V`);
  if (typeof specs.tensaoMinV === "number" && typeof specs.tensaoMaxV === "number") {
    terms.push(`${formatTechnicalNumber(specs.tensaoMinV)}-${formatTechnicalNumber(specs.tensaoMaxV)}V`);
  }
  if (typeof specs.potenciaW === "number") terms.push(`${formatTechnicalNumber(specs.potenciaW)}W`, `${formatTechnicalNumber(specs.potenciaW)} W`);
  return unique(terms);
}

function technicalCategoryLabel(category?: string): string {
  return category && category in CATEGORY_LABELS ? CATEGORY_LABELS[category as AssistenteIACategoriaTecnica] : String(category ?? "");
}

function voltageCompatibility(
  requested: AssistenteIAEspecificacoesDetectadas,
  candidate: AssistenteIAEspecificacoesDetectadas
): "compativel" | "incompativel" | "desconhecida" {
  if (typeof requested.tensaoV !== "number") return "desconhecida";
  if (typeof candidate.tensaoMinV === "number" && typeof candidate.tensaoMaxV === "number") {
    return candidate.tensaoMinV <= requested.tensaoV && requested.tensaoV <= candidate.tensaoMaxV ? "compativel" : "incompativel";
  }
  if (typeof candidate.tensaoV === "number") {
    return Math.abs(candidate.tensaoV - requested.tensaoV) <= Math.max(5, requested.tensaoV * 0.05) ? "compativel" : "incompativel";
  }
  return "desconhecida";
}

function currentCompatibility(
  requested: AssistenteIAEspecificacoesDetectadas,
  candidate: AssistenteIAEspecificacoesDetectadas
): "igual_ou_superior" | "inferior" | "muito_inferior" | "desconhecida" {
  if (typeof requested.correnteA !== "number") return "desconhecida";
  if (typeof candidate.correnteA !== "number") return "desconhecida";
  if (candidate.correnteA >= requested.correnteA) return "igual_ou_superior";
  return candidate.correnteA < requested.correnteA * 0.8 ? "muito_inferior" : "inferior";
}

function powerCompatibility(
  requested: AssistenteIAEspecificacoesDetectadas,
  candidate: AssistenteIAEspecificacoesDetectadas
): "igual_ou_superior" | "inferior" | "desconhecida" {
  if (typeof requested.potenciaW !== "number") return "desconhecida";
  if (typeof candidate.potenciaW !== "number") return "desconhecida";
  return candidate.potenciaW >= requested.potenciaW ? "igual_ou_superior" : "inferior";
}

function extractDetectedDimensions(value: string): string[] {
  const normalized = normalizeText(value).replace(/×/g, "X");
  const dimensions = normalized.match(/\b\d{2,4}\s*X\s*\d{2,4}(?:\s*X\s*\d{2,4})?\b/g) ?? [];
  return unique(dimensions.map((dimension) => normalizeCompact(dimension).replace(/X/g, "x")));
}

function extractDimensionTerms(value: string): string[] {
  const dimensions = extractDetectedDimensions(value);
  const terms: string[] = [];

  for (const dimension of dimensions) {
    const compact = normalizeCompact(dimension);
    if (compact) terms.push(compact);
    for (const part of compact.split("X")) {
      if (part.length >= 2) terms.push(part);
    }
  }

  return unique(terms);
}

function extractCodeFragments(row: AssistenteIAItemPlanilha): string[] {
  const source = normalizeText(`${row.codigo} ${row.componente}`);
  const fragments = source.match(/[A-Z]*\d[A-Z0-9-/.]*\d[A-Z0-9-/.]*/g) ?? [];
  const terms: string[] = [];

  for (const fragment of fragments) {
    const compact = normalizeCompact(fragment);
    if (compact.length >= 3) terms.push(compact);
    for (const part of compact.split(/[^A-Z0-9]+/)) {
      if (part.length >= 3) terms.push(part);
    }
    const numericParts = compact.match(/\d{3,}/g) ?? [];
    terms.push(...numericParts);
  }

  return unique(terms);
}

function extractTechnicalTerms(row: AssistenteIAItemPlanilha): string[] {
  const text = normalizeText(`${row.componente} ${row.codigo} ${row.marca}`);
  const compact = normalizeCompact(text);
  const analysis = analyzeTechnicalRow(row);
  const words = text
    .replace(/[^A-Z0-9]+/g, " ")
    .split(/\s+/)
    .map((term) => term.trim())
    .filter((term) => term.length >= 3 && !STOP_TERMS.has(term));

  const terms = [
    ...words,
    ...extractCodeFragments(row),
    ...extractDimensionTerms(row.componente),
    ...technicalSpecTerms(analysis),
    ...analysis.sinonimosTecnicos,
  ];

  if (text.includes("ARMARIO") || text.includes("GABINETE") || text.includes("QUADRO")) {
    terms.push("ARMARIO", "GABINETE", "QUADRO", "AUTO PORTANTE", "METALICO", "VX", "TS", "AX");
  }
  if (text.includes("LATERAL") || text.includes("PAREDE")) terms.push("LATERAL", "PAREDE", "CHAPA");
  if (text.includes("BASE") || text.includes("SOLEIRA") || text.includes("SOCO")) terms.push("BASE", "SOLEIRA", "SOCO");
  if (text.includes("RELE") && text.includes("SOLIDO")) terms.push("RELE", "ESTADO SOLIDO", "SSR");
  if (text.includes("FONTE") || text.includes("ALIMENTACAO")) terms.push("FONTE", "ALIMENTACAO", "24V", "24VDC", "24VCC");
  if (compact.includes("24VCC")) terms.push("24VDC", "24 VDC", "24 VCC");
  if (compact.includes("10A")) terms.push("10A", "10 A");
  if (compact.includes("240W")) terms.push("240W", "240 W");
  if (analysis.categoriaTecnicaDetectada === "soft_starter" || text.includes("SOFT") || text.includes("STARTER")) {
    terms.push("SOFT STARTER", "SOFT-STARTER", "SOFTSTARTER", "PARTIDA SUAVE", "CHAVE PARTIDA ESTATICA", "ACIONAMENTO MOTOR", "SSW");
    if (row.marca.trim()) terms.push(`${row.marca} SSW`);
    terms.push(...SOFT_STARTER_FALLBACK_TERMS);
  }
  if (text.includes("DISJUNTOR")) terms.push("DISJUNTOR");
  if (text.includes("CONTATOR")) terms.push("CONTATOR");
  if (text.includes("INVERSOR")) terms.push("INVERSOR");
  if (text.includes("BORNE")) terms.push("BORNE");
  if (text.includes("TRILHO")) terms.push("TRILHO", "DIN");
  if (text.includes("CLP")) terms.push("CLP");
  if (text.includes("IHM")) terms.push("IHM");

  return unique(terms).slice(0, 40);
}

function diagnosticText(value: unknown): string {
  return normalizeText(value).toLowerCase().replace(/\s+/g, " ").trim();
}

function diagnosticCode(value: unknown): string {
  return normalizeCode(value).toLowerCase();
}

function diagnosticTerms(values: string[]): string[] {
  return unique(values.map((value) => diagnosticText(value))).slice(0, 40);
}

function normalizedCodeForDiagnostic(row: AssistenteIAItemPlanilha): string | undefined {
  const code = diagnosticCode(row.codigo);
  return code || undefined;
}

function itemHasExactCode(row: AssistenteIAItemPlanilha, item: ItemRow | AssistenteIACandidatoBanco): boolean {
  const rowCode = normalizeCode(row.codigo);
  const candidateCode = normalizeCode("id" in item ? item.codigo_interno : item.codigo);
  return Boolean(rowCode && candidateCode && rowCode === candidateCode);
}

function itemHasPartialCode(row: AssistenteIAItemPlanilha, item: ItemRow | AssistenteIACandidatoBanco): boolean {
  const rowCode = normalizeCode(row.codigo);
  const candidateCode = normalizeCode("id" in item ? item.codigo_interno : item.codigo);
  if (!rowCode || !candidateCode) return false;
  if (rowCode.length >= 4 && candidateCode.includes(rowCode)) return true;
  if (candidateCode.length >= 4 && rowCode.includes(candidateCode)) return true;
  return extractCodeFragments(row).some((fragment) => {
    const code = normalizeCode(fragment);
    return code.length >= 4 && (candidateCode.includes(code) || rowCode.includes(code));
  });
}

function sameTechnicalFamily(rowAnalysis: AssistenteIAAnaliseTecnica, candidateAnalysis: AssistenteIAAnaliseTecnica): boolean {
  const requestedFamily = normalizeCompact(rowAnalysis.especificacoesDetectadas.familia);
  const candidateFamily = normalizeCompact(candidateAnalysis.especificacoesDetectadas.familia);
  return Boolean(requestedFamily && candidateFamily && requestedFamily === candidateFamily);
}

function sameTechnicalCategory(rowAnalysis: AssistenteIAAnaliseTecnica, candidateAnalysis: AssistenteIAAnaliseTecnica): boolean {
  return rowAnalysis.categoriaTecnicaDetectada !== "desconhecida" && rowAnalysis.categoriaTecnicaDetectada === candidateAnalysis.categoriaTecnicaDetectada;
}

function isKnownCategory(category: CategoriaTecnicaAssistenteIA): boolean {
  return category !== "desconhecida";
}

function hasSoftStarterTerms(text: string, compact: string): boolean {
  return hasAnyTerm(text, compact, ["softstarter", "soft starter", "soft-starter", "SSW"]);
}

function hasSafetyInterlockTerms(text: string, compact: string): boolean {
  return hasAnyTerm(text, compact, ["chave de seguranca", "intertravamento"]);
}

function hasFonte24VTerms(text: string, compact: string): boolean {
  return hasAnyTerm(text, compact, ["24DC", "24VDC", "24VCC", "24 VDC", "24 VCC"]);
}

function evaluateCategoryScore(item: ItemRow, row: AssistenteIAItemPlanilha, rowAnalysis: AssistenteIAAnaliseTecnica): CandidateTechnicalEvaluation {
  const text = itemSearchText(item);
  const compact = itemSearchCompact(item);
  const candidateAnalysis = analyzeTechnicalItem(item);
  const categoriaCandidatoDetectada = detectarCategoriaDoProdutoBanco(item);
  const requestedSpecs = rowAnalysis.especificacoesDetectadas;
  const candidateSpecs = candidateAnalysis.especificacoesDetectadas;
  const motivos: string[] = [];
  const penalidades: string[] = [];
  let scoreDelta = 0;

  const add = (score: number, motivo: string) => {
    scoreDelta += score;
    motivos.push(motivo);
  };
  const penalize = (score: number, motivo: string) => {
    scoreDelta -= score;
    penalidades.push(motivo);
  };

  switch (rowAnalysis.categoriaTecnicaDetectada) {
    case "soft_starter": {
      const hasSoft = hasSoftStarterTerms(text, compact);
      if (hasAnyTerm(text, compact, ["softstarter", "soft starter", "soft-starter"])) add(100, "produto contem softstarter");
      if (containsTerm(text, compact, "SSW")) add(80, "produto contem SSW");
      if (brandMatches(row.marca, item) || containsTerm(text, compact, "WEG")) add(40, "marca/fabricante WEG compativel");
      if (currentCompatibility(requestedSpecs, candidateSpecs) === "igual_ou_superior") add(30, "corrente igual ou superior");
      if (voltageCompatibility(requestedSpecs, candidateSpecs) === "compativel") add(20, "tensao compativel");
      if (hasSafetyInterlockTerms(text, compact) && !hasSoft) penalize(200, "chave de seguranca/intertravamento sem softstarter ou SSW");
      if (hasAnyTerm(text, compact, ["botao", "botão", "borne", "fonte", "campainha", "sensor", "disjuntor"]) && !hasSoft) {
        penalize(200, "categoria eletrica incompatível com soft-starter");
      }
      if (categoriaCandidatoDetectada !== "soft_starter") penalize(200, `categoria do produto ${technicalCategoryLabel(categoriaCandidatoDetectada)} diferente de soft-starter`);
      break;
    }
    case "rele_estado_solido": {
      if (hasAnyTerm(text, compact, ["estado solido", "rele de estado solido"])) add(120, "produto contem rele de estado solido");
      if (hasAnyTerm(text, compact, ["857-724", "857"])) add(100, "produto contem serie 857");
      if (brandMatches(row.marca, item) || containsTerm(text, compact, "WAGO")) add(50, "fabricante WAGO compativel");
      if (hasFonte24VTerms(text, compact)) add(30, "produto contem 24 VDC");
      if (hasAnyTerm(text, compact, ["borne", "terminal", "conector", "jumper", "placa final"])) {
        penalize(200, "produto de borne/terminal nao e rele de estado solido");
      }
      if (hasAnyTerm(text, compact, ["disjuntor", "fonte", "campainha"])) penalize(200, "produto incompatível com rele de estado solido");
      if (categoriaCandidatoDetectada === "borne") penalize(200, "categoria do produto e borne");
      if (isKnownCategory(categoriaCandidatoDetectada) && categoriaCandidatoDetectada !== "rele_estado_solido") {
        penalize(160, `categoria do produto ${technicalCategoryLabel(categoriaCandidatoDetectada)} diferente de rele de estado solido`);
      }
      break;
    }
    case "fonte_24v": {
      if (hasAnyTerm(text, compact, ["fonte", "alimentacao"])) add(120, "produto contem fonte/alimentacao");
      if (hasFonte24VTerms(text, compact)) add(80, "produto contem saida 24VDC/24VCC");
      if (hasAnyTerm(text, compact, ["10A", "10 A", "240W", "240 W"])) add(80, "produto contem 10A ou 240W");
      if (hasAnyTerm(text, compact, ["Phoenix", "TRIO", "QUINT", "PS-EE"]) || brandMatches(row.marca, item)) {
        add(50, "fabricante/linha compativel");
      }
      if (
        powerCompatibility(requestedSpecs, candidateSpecs) === "igual_ou_superior" ||
        currentCompatibility(requestedSpecs, candidateSpecs) === "igual_ou_superior"
      ) {
        add(40, "potencia/corrente superior compativel");
      }
      if (hasAnyTerm(text, compact, ["campainha", "sinalizador", "torre", "botao", "botão", "sirene"])) {
        penalize(250, "sinalizacao/campainha nao e fonte 24V");
      }
      if (hasAnyTerm(text, compact, ["borne", "rele", "sensor"])) penalize(200, "produto incompatível com fonte 24V");
      if (categoriaCandidatoDetectada !== "fonte_24v") penalize(200, `categoria do produto ${technicalCategoryLabel(categoriaCandidatoDetectada)} diferente de fonte 24V`);
      break;
    }
    case "armario_painel": {
      if (hasAnyTerm(text, compact, ["armario", "gabinete", "painel"])) add(100, "produto principal de armario/painel");
      if (extractDimensionTerms(row.componente).some((dimension) => compact.includes(normalizeCompact(dimension)))) add(80, "dimensao bate parcialmente");
      if (containsTerm(text, compact, "Rittal")) add(50, "fabricante Rittal");
      if (hasAnyTerm(text, compact, ["TS", "VX", "AX"])) add(40, "familia TS/VX/AX");
      if (hasAnyTerm(text, compact, ["paredes laterais", "parede lateral", "chapas laterais", "chapa lateral"])) add(100, "componente lateral identificado");
      if (hasAnyTerm(text, compact, ["base soleira", "soleira", "soco"])) add(100, "base soleira identificada");
      if (isKnownCategory(categoriaCandidatoDetectada) && categoriaCandidatoDetectada !== "armario_painel") {
        penalize(160, `categoria do produto ${technicalCategoryLabel(categoriaCandidatoDetectada)} diferente de armario/painel`);
      }
      break;
    }
    case "desconhecida":
      break;
    default:
      if (isKnownCategory(categoriaCandidatoDetectada) && categoriaCandidatoDetectada !== rowAnalysis.categoriaTecnicaDetectada) {
        penalize(120, `categoria do produto ${technicalCategoryLabel(categoriaCandidatoDetectada)} diferente da solicitada`);
      }
      break;
  }

  const incompatibilidadeForte =
    isKnownCategory(rowAnalysis.categoriaTecnicaDetectada) &&
    isKnownCategory(categoriaCandidatoDetectada) &&
    categoriaCandidatoDetectada !== rowAnalysis.categoriaTecnicaDetectada;

  return { scoreDelta, motivos: unique(motivos), penalidades: unique(penalidades), categoriaCandidatoDetectada, incompatibilidadeForte };
}

function technicalScoreAdjustment(item: ItemRow, row: AssistenteIAItemPlanilha, rowAnalysis: AssistenteIAAnaliseTecnica): number {
  const candidateAnalysis = analyzeTechnicalItem(item);
  const requestedSpecs = rowAnalysis.especificacoesDetectadas;
  const candidateSpecs = candidateAnalysis.especificacoesDetectadas;
  let score = evaluateCategoryScore(item, row, rowAnalysis).scoreDelta;

  if (sameTechnicalCategory(rowAnalysis, candidateAnalysis)) score += 38;
  if (sameTechnicalFamily(rowAnalysis, candidateAnalysis)) score += 36;
  else if (requestedSpecs.familia && candidateSpecs.familia && sameTechnicalCategory(rowAnalysis, candidateAnalysis)) score += 10;

  return score;
}

function candidateDiagnosticGroup(
  row: AssistenteIAItemPlanilha,
  candidate: ItemRow | AssistenteIACandidatoBanco,
  rowAnalysis = analyzeTechnicalRow(row),
  candidateAnalysis = analyzeTechnicalItem(candidate)
): AssistenteIAGrupoDiagnostico {
  if (itemHasExactCode(row, candidate)) return "codigo_exato";
  if (itemHasPartialCode(row, candidate)) return "codigo_parcial";
  if (sameTechnicalFamily(rowAnalysis, candidateAnalysis)) return "mesma_familia";
  if (sameTechnicalCategory(rowAnalysis, candidateAnalysis)) {
    if (rowAnalysis.especificacoesDetectadas.familia && candidateAnalysis.especificacoesDetectadas.familia) return "equivalente_tecnico";
    return "mesma_categoria";
  }
  if (rowAnalysis.categoriaTecnicaDetectada && brandMatches(row.marca, candidate)) return "alternativa_fabricante";
  return "geral";
}

function scoreItemBase(item: ItemRow, row: AssistenteIAItemPlanilha, terms: string[]): number {
  const text = itemSearchText(item);
  const compact = itemSearchCompact(item);
  const itemCode = normalizeCode(item.codigo_interno);
  const rowCode = normalizeCode(row.codigo);
  let score = 0;

  if (rowCode && itemCode) {
    if (itemCode === rowCode) score += 140;
    else if (rowCode.length >= 4 && itemCode.includes(rowCode)) score += 90;
    else if (itemCode.length >= 4 && rowCode.includes(itemCode)) score += 55;
  }

  for (const fragment of extractCodeFragments(row)) {
    if (fragment.length >= 3 && (itemCode.includes(fragment) || compact.includes(fragment))) score += fragment.length >= 5 ? 32 : 22;
  }

  let termMatches = 0;
  for (const term of terms) {
    if (!containsTerm(text, compact, term)) continue;
    termMatches += 1;
    score += normalizeCompact(term).match(/^\d/) ? 10 : 6;
  }

  if (termMatches >= 2) score += 12;
  if (brandMatches(row.marca, item)) score += 24;
  else if (row.marca.trim()) score -= 4;

  const dimensionTerms = extractDimensionTerms(row.componente);
  const dimensionMatches = dimensionTerms.filter((term) => compact.includes(term)).length;
  if (dimensionMatches > 0) score += dimensionMatches * 8;

  return score;
}

function buildScoredItem(item: ItemRow, row: AssistenteIAItemPlanilha, terms: string[], rowAnalysis = analyzeTechnicalRow(row)): ScoredItem {
  const scoreBase = scoreItemBase(item, row, terms);
  const evaluation = evaluateCategoryScore(item, row, rowAnalysis);
  const scoreFinal = scoreBase + technicalScoreAdjustment(item, row, rowAnalysis);
  return {
    item,
    score: scoreFinal,
    scoreBase,
    scoreFinal,
    categoriaCandidatoDetectada: evaluation.categoriaCandidatoDetectada,
    motivos: evaluation.motivos,
    penalidades: evaluation.penalidades,
  };
}

function detectDiagnosticGroups(row: AssistenteIAItemPlanilha): AssistenteIAGrupoDiagnostico[] {
  const text = normalizeText(`${row.componente} ${row.codigo} ${row.marca}`);
  const compact = normalizeCompact(text);
  const analysis = analyzeTechnicalRow(row);
  const groups: AssistenteIAGrupoDiagnostico[] = [];
  const hasArmario = text.includes("ARMARIO") || text.includes("GABINETE") || text.includes("QUADRO");
  const hasReleSolido = text.includes("RELE") && text.includes("SOLIDO");
  const hasFonte = text.includes("FONTE") || text.includes("ALIMENTACAO");

  if (isKnownCategory(analysis.categoriaTecnicaDetectada)) groups.push("mesma_categoria", "equivalente_tecnico");
  if (analysis.especificacoesDetectadas.familia) groups.push("mesma_familia");
  if (hasArmario || hasReleSolido || hasFonte) groups.push("produto_principal");
  if (text.includes("LATERAL") || text.includes("PAREDE") || text.includes("CHAPA")) groups.push("lateral");
  if (text.includes("BASE") || text.includes("SOLEIRA") || text.includes("SOCO")) groups.push("base_soleira");
  if (text.includes("ACESSORIO") || text.includes("KIT") || text.includes("SUPORTE") || text.includes("FECHADURA")) {
    groups.push("acessorio");
  }
  if (hasFonte && (compact.includes("24V") || compact.includes("10A") || compact.includes("240W"))) groups.push("equivalente");
  if (groups.length === 0) groups.push("geral");

  return unique(groups) as AssistenteIAGrupoDiagnostico[];
}

function toDiagnosticGroup(group: AssistenteIAPapelProduto): AssistenteIAGrupoDiagnostico {
  if (group === "produto_principal") return "produto_principal";
  if (group === "lateral") return "lateral";
  if (group === "base_soleira") return "base_soleira";
  if (group === "acessorio") return "acessorio";
  if (group === "equivalente") return "equivalente";
  return "geral";
}

function isCandidateIncompatible(rowAnalysis: AssistenteIAAnaliseTecnica, candidate: ScoredItem): boolean {
  const requestedCategory = rowAnalysis.categoriaTecnicaDetectada;
  if (!isKnownCategory(requestedCategory)) return false;
  if (!isKnownCategory(candidate.categoriaCandidatoDetectada)) return true;
  return requestedCategory !== candidate.categoriaCandidatoDetectada;
}

function isCandidateRemovedByTechnicalFilter(rowAnalysis: AssistenteIAAnaliseTecnica, candidate: ScoredItem): boolean {
  return candidate.scoreFinal <= 0 || isCandidateIncompatible(rowAnalysis, candidate);
}

function shouldCountRemovedCandidate(candidate: ScoredItem): boolean {
  return candidate.scoreBase > 0 || candidate.motivos.length > 0 || candidate.penalidades.length > 0;
}

function sortScoredCandidates(candidates: ScoredItem[]): ScoredItem[] {
  return candidates.sort((a, b) => b.scoreFinal - a.scoreFinal);
}

function limitCandidatesByTechnicalCategory(row: AssistenteIAItemPlanilha, rowAnalysis: AssistenteIAAnaliseTecnica, candidates: ScoredItem[]): ScoredItem[] {
  const sorted = sortScoredCandidates(uniqueScoredItems(candidates));
  if (!isKnownCategory(rowAnalysis.categoriaTecnicaDetectada)) return sorted.slice(0, MAX_GENERAL_CANDIDATES);

  const primary: ScoredItem[] = [];
  const equivalents: ScoredItem[] = [];

  for (const candidate of sorted) {
    const group = candidateDiagnosticGroup(row, candidate.item, rowAnalysis);
    if (group === "equivalente_tecnico" || group === "mesma_categoria" || group === "alternativa_fabricante") equivalents.push(candidate);
    else primary.push(candidate);
  }

  return uniqueScoredItems([...primary.slice(0, MAX_KNOWN_CATEGORY_CANDIDATES), ...equivalents.slice(0, MAX_TECHNICAL_EQUIVALENTS)]).slice(
    0,
    MAX_GENERAL_CANDIDATES
  );
}

function emptyCandidateSearchResult(items: ItemRow[], fallbackAcionado = false): CandidateSearchResult {
  return {
    general: [],
    grupos: {},
    candidatosBancoAntesFiltro: items.length,
    candidatosAposCategoriaBase: 0,
    candidatosRemovidosPorIncompatibilidade: 0,
    candidatosRemovidosPorTermosProibidos: 0,
    candidatosRemovidosPorScore: 0,
    fallbackAcionado,
  };
}

function mergePlanoGroupsWithFallback(row: AssistenteIAItemPlanilha, planoBusca: AssistenteIAPlanoBusca): AssistenteIAPlanoBuscaGrupo[] {
  const fallbackGroups = buildFallbackPlanoBusca(row).gruposBusca;
  const byPapel = new Map<AssistenteIAPlanoBuscaPapel, AssistenteIAPlanoBuscaGrupo>();
  for (const group of planoBusca.gruposBusca) byPapel.set(group.papel, group);
  for (const fallbackGroup of fallbackGroups) {
    if (!byPapel.has(fallbackGroup.papel)) byPapel.set(fallbackGroup.papel, fallbackGroup);
  }
  return Array.from(byPapel.values());
}

function buildCandidateSearchByCategory(
  items: ItemRow[],
  row: AssistenteIAItemPlanilha,
  planoBusca: AssistenteIAPlanoBusca,
  gruposBusca: AssistenteIAPlanoBuscaGrupo[],
  useFallbackBase: boolean
): CandidateSearchResult {
  const analiseTecnica = analysisFromPlanoBusca(row, planoBusca);
  const termosBuscaUsados = termosBuscaFromPlano(row, planoBusca, analiseTecnica);
  const grupos: Partial<Record<AssistenteIAPapelProduto, ScoredItem[]>> = {};
  const generalCandidates: ScoredItem[] = [];
  const idsAposCategoriaBase = new Set<number>();
  const idsRemovidosPorTermosProibidos = new Set<number>();
  const idsRemovidosPorScore = new Set<number>();

  for (const grupoPlano of gruposBusca) {
    const papel = groupPapelToProdutoPapel(grupoPlano.papel);
    const groupCandidates: ScoredItem[] = [];

    for (const item of items) {
      const itemId = Number(item.id);
      if (!Number.isFinite(itemId) || itemId <= 0) continue;

      const matchesBase = useFallbackBase
        ? candidateMatchesCategoriaFallback(item, planoBusca.categoriaTecnica, grupoPlano.papel)
        : candidateMatchesCategoriaBase(item, planoBusca.categoriaTecnica, grupoPlano.papel);
      if (!matchesBase) continue;
      idsAposCategoriaBase.add(itemId);

      if (candidateHasForbiddenForCategory(item, planoBusca.categoriaTecnica, grupoPlano.papel, grupoPlano.termosProibidos)) {
        idsRemovidosPorTermosProibidos.add(itemId);
        continue;
      }

      const candidate = scoreItemForPlanoGrupo(item, row, planoBusca, grupoPlano, termosBuscaUsados, analiseTecnica);
      if (candidate.scoreFinal <= 0) {
        idsRemovidosPorScore.add(itemId);
        continue;
      }

      groupCandidates.push(candidate);
    }

    const limitedGroup = sortScoredCandidates(uniqueScoredItems(groupCandidates)).slice(0, MAX_GROUP_CANDIDATES);
    grupos[papel] = uniqueScoredItems([...(grupos[papel] ?? []), ...limitedGroup]).slice(0, MAX_GROUP_CANDIDATES);
    generalCandidates.push(...limitedGroup);
  }

  const general = sortScoredCandidates(uniqueScoredItems(generalCandidates)).slice(0, MAX_GENERAL_CANDIDATES);

  return {
    general,
    grupos,
    candidatosBancoAntesFiltro: items.length,
    candidatosAposCategoriaBase: idsAposCategoriaBase.size,
    candidatosRemovidosPorIncompatibilidade: 0,
    candidatosRemovidosPorTermosProibidos: idsRemovidosPorTermosProibidos.size,
    candidatosRemovidosPorScore: idsRemovidosPorScore.size,
    fallbackAcionado: useFallbackBase,
  };
}

function buscarSeedsSoftStarter(
  items: ItemRow[],
  row: AssistenteIAItemPlanilha,
  planoBusca: AssistenteIAPlanoBusca,
  useFallbackBase = false
): CandidateSearchResult {
  const groups = planoBusca.gruposBusca.length > 0 ? planoBusca.gruposBusca : buildFallbackPlanoBusca(row).gruposBusca;
  return buildCandidateSearchByCategory(items, row, planoBusca, groups, useFallbackBase);
}

function buscarSeedsFonte24v(
  items: ItemRow[],
  row: AssistenteIAItemPlanilha,
  planoBusca: AssistenteIAPlanoBusca,
  useFallbackBase = false
): CandidateSearchResult {
  const groups = planoBusca.gruposBusca.length > 0 ? planoBusca.gruposBusca : buildFallbackPlanoBusca(row).gruposBusca;
  return buildCandidateSearchByCategory(items, row, planoBusca, groups, useFallbackBase);
}

function buscarSeedsReleEstadoSolido(
  items: ItemRow[],
  row: AssistenteIAItemPlanilha,
  planoBusca: AssistenteIAPlanoBusca,
  useFallbackBase = false
): CandidateSearchResult {
  const groups = planoBusca.gruposBusca.length > 0 ? planoBusca.gruposBusca : buildFallbackPlanoBusca(row).gruposBusca;
  return buildCandidateSearchByCategory(items, row, planoBusca, groups, useFallbackBase);
}

function buscarSeedsArmarioPainel(
  items: ItemRow[],
  row: AssistenteIAItemPlanilha,
  planoBusca: AssistenteIAPlanoBusca,
  useFallbackBase = false
): CandidateSearchResult {
  return buildCandidateSearchByCategory(items, row, planoBusca, mergePlanoGroupsWithFallback(row, planoBusca), useFallbackBase);
}

function buscarSeedsGenerico(items: ItemRow[], row: AssistenteIAItemPlanilha, planoBusca: AssistenteIAPlanoBusca): CandidateSearchResult {
  const analiseTecnica = analysisFromPlanoBusca(row, planoBusca);
  const termosBuscaUsados = termosBuscaFromPlano(row, planoBusca, analiseTecnica);
  const grupos: Partial<Record<AssistenteIAPapelProduto, ScoredItem[]>> = {};
  const generalCandidates: ScoredItem[] = [];
  const idsAposCategoriaBase = new Set<number>();
  const idsRemovidosPorTermosProibidos = new Set<number>();
  const idsRemovidosPorIncompatibilidade = new Set<number>();
  const idsRemovidosPorScore = new Set<number>();

  for (const grupoPlano of planoBusca.gruposBusca) {
    const papel = groupPapelToProdutoPapel(grupoPlano.papel);
    const searchTerms = unique([...grupoPlano.termosObrigatorios, ...grupoPlano.termosDesejaveis, grupoPlano.marcaPreferencial ?? "", planoBusca.marcaPreferencial ?? ""]);
    const groupCandidates: ScoredItem[] = [];

    for (const item of items) {
      const itemId = Number(item.id);
      if (!Number.isFinite(itemId) || itemId <= 0) continue;
      const hasSearchHit = searchTerms.length === 0 || itemMatchesAnySearchTerm(item, searchTerms);
      if (!hasSearchHit) continue;
      idsAposCategoriaBase.add(itemId);

      if (itemMatchesForbiddenTerms(item, grupoPlano.termosProibidos)) {
        idsRemovidosPorTermosProibidos.add(itemId);
        continue;
      }

      const candidate = scoreItemForPlanoGrupo(item, row, planoBusca, grupoPlano, termosBuscaUsados, analiseTecnica);
      if (isCandidateRemovedByTechnicalFilter(analiseTecnica, candidate)) {
        if (shouldCountRemovedCandidate(candidate)) idsRemovidosPorIncompatibilidade.add(itemId);
        else idsRemovidosPorScore.add(itemId);
        continue;
      }

      groupCandidates.push(candidate);
    }

    const limitedGroup = sortScoredCandidates(uniqueScoredItems(groupCandidates)).slice(0, MAX_GROUP_CANDIDATES);
    grupos[papel] = uniqueScoredItems([...(grupos[papel] ?? []), ...limitedGroup]).slice(0, MAX_GROUP_CANDIDATES);
    generalCandidates.push(...limitedGroup);
  }

  return {
    general: limitCandidatesByTechnicalCategory(row, analiseTecnica, generalCandidates),
    grupos,
    candidatosBancoAntesFiltro: items.length,
    candidatosAposCategoriaBase: idsAposCategoriaBase.size,
    candidatosRemovidosPorIncompatibilidade: idsRemovidosPorIncompatibilidade.size,
    candidatosRemovidosPorTermosProibidos: idsRemovidosPorTermosProibidos.size,
    candidatosRemovidosPorScore: idsRemovidosPorScore.size,
    fallbackAcionado: false,
  };
}

function buscarSeedsPorCategoria(items: ItemRow[], row: AssistenteIAItemPlanilha, planoBusca: AssistenteIAPlanoBusca, useFallbackBase = false): CandidateSearchResult {
  switch (planoBusca.categoriaTecnica) {
    case "soft_starter":
      return buscarSeedsSoftStarter(items, row, planoBusca, useFallbackBase);
    case "fonte_24v":
      return buscarSeedsFonte24v(items, row, planoBusca, useFallbackBase);
    case "rele_estado_solido":
      return buscarSeedsReleEstadoSolido(items, row, planoBusca, useFallbackBase);
    case "armario_painel":
      return buscarSeedsArmarioPainel(items, row, planoBusca, useFallbackBase);
    default:
      return buscarSeedsGenerico(items, row, planoBusca);
  }
}

function buildCandidateSeed(items: ItemRow[], row: AssistenteIAItemPlanilha, planoBusca: AssistenteIAPlanoBusca): CandidateSeed {
  const initial = buscarSeedsPorCategoria(items, row, planoBusca, false);
  const needsFallback = isKnownCategory(planoBusca.categoriaTecnica) && initial.general.length === 0;
  const search = needsFallback ? buscarSeedsPorCategoria(items, row, buildFallbackPlanoBusca(row), true) : initial;
  const effectivePlanoBusca = needsFallback ? buildFallbackPlanoBusca(row) : planoBusca;
  const analiseTecnica = analysisFromPlanoBusca(row, effectivePlanoBusca);
  const termosBuscaUsados = termosBuscaFromPlano(row, effectivePlanoBusca, analiseTecnica);

  if (!items.length) {
    const empty = emptyCandidateSearchResult(items, needsFallback);
    return {
      row,
      planoBusca: effectivePlanoBusca,
      analiseTecnica,
      termosBuscaUsados,
      general: empty.general,
      grupos: empty.grupos,
      candidatosBancoAntesFiltro: empty.candidatosBancoAntesFiltro,
      candidatosAposCategoriaBase: empty.candidatosAposCategoriaBase,
      candidatosRemovidosPorIncompatibilidade: empty.candidatosRemovidosPorIncompatibilidade,
      candidatosRemovidosPorTermosProibidos: empty.candidatosRemovidosPorTermosProibidos,
      candidatosRemovidosPorScore: empty.candidatosRemovidosPorScore,
      fallbackAcionado: empty.fallbackAcionado,
    };
  }

  return {
    row,
    planoBusca: effectivePlanoBusca,
    analiseTecnica,
    termosBuscaUsados,
    general: search.general,
    grupos: search.grupos,
    candidatosBancoAntesFiltro: search.candidatosBancoAntesFiltro,
    candidatosAposCategoriaBase: search.candidatosAposCategoriaBase,
    candidatosRemovidosPorIncompatibilidade: search.candidatosRemovidosPorIncompatibilidade,
    candidatosRemovidosPorTermosProibidos: search.candidatosRemovidosPorTermosProibidos,
    candidatosRemovidosPorScore: search.candidatosRemovidosPorScore,
    fallbackAcionado: needsFallback || search.fallbackAcionado,
  };
}

function classifyPriceStatus(ultimaCompra: UltimaCompra | null): AssistenteIAStatusPreco {
  if (!ultimaCompra?.data) return "sem_historico";
  const time = Date.parse(ultimaCompra.data);
  if (!Number.isFinite(time)) return "sem_historico";
  const diffMs = Date.now() - time;
  const months = diffMs / (1000 * 60 * 60 * 24 * 30.4375);
  if (months <= 12) return "preco_atualizado";
  if (months <= 24) return "preco_antigo";
  return "preco_muito_antigo";
}

function buildDirectIdResult(
  row: AssistenteIAItemPlanilha,
  item: ItemRow,
  ultimasCompras: Map<number, UltimaCompra>,
  estoqueByItemId: Map<number, number>
): AssistenteIAResultadoAnalise {
  const itemId = Number(item.id);
  const ultimaCompra = ultimasCompras.get(itemId) ?? null;
  const estoque = estoqueByItemId.get(itemId);
  const statusPreco = classifyPriceStatus(ultimaCompra);
  const analiseTecnica = analyzeTechnicalRow(row);
  const codeMatches = !row.codigo.trim() || normalizeCode(row.codigo) === normalizeCode(item.codigo_interno);
  const brandMatchesInput = !row.marca.trim() || brandMatches(row.marca, item);
  const alertaParts: string[] = [];

  if (!codeMatches) alertaParts.push("ID informado na planilha encontrado, mas o código da planilha difere do cadastro.");
  if (!brandMatchesInput) alertaParts.push("ID informado na planilha encontrado, mas a marca da planilha difere do cadastro.");
  if (statusPreco !== "preco_atualizado") alertaParts.push("Produto com preço antigo ou sem histórico de compra recente.");

  return {
    linha: row.linha,
    qtdOriginal: row.qtd,
    componenteOriginal: row.componente,
    codigoOriginal: row.codigo,
    marcaOriginal: row.marca,
    tipoResultado: "produto_unico",
    produtosSelecionados: [
      {
        produtoId: String(item.id),
        codigo: String(item.codigo_interno ?? "").trim(),
        descricao: itemDescription(item).slice(0, 260),
        marca: String(item.fabricante ?? "").trim() || undefined,
        fornecedorNome: getFornecedorNome(item) ?? undefined,
        qtdSugerida: row.qtd,
        papelNaComposicao: "produto_principal",
        justificativa: "Produto vinculado diretamente pelo ID informado na planilha.",
        origem: "planilha",
        ultimaCompraData: ultimaCompra?.data,
        ultimaCompraValorUnitario: ultimaCompra?.valorUnitario,
        estoque: Number.isFinite(estoque) ? estoque : undefined,
        statusPreco,
      },
    ],
    confianca: 100,
    decisaoSugerida: "aceitar",
    resumoIA: "Produto vinculado diretamente pelo ID informado na planilha.",
    alertaTecnico: unique(alertaParts).join(" ") || undefined,
    termosBuscaUsados: unique([`ID ${item.id}`, row.codigo, ...extractTechnicalTerms(row)]).slice(0, 40),
    categoriaTecnicaDetectada: analiseTecnica.categoriaTecnicaDetectada,
    especificacoesDetectadas:
      Object.keys(analiseTecnica.especificacoesDetectadas).length > 0 ? analiseTecnica.especificacoesDetectadas : undefined,
  };
}

function enrichScore(candidate: ScoredItem, ultimasCompras: Map<number, UltimaCompra>, estoqueByItemId: Map<number, number>): number {
  const ultimaCompra = ultimasCompras.get(Number(candidate.item.id)) ?? null;
  const statusPreco = classifyPriceStatus(ultimaCompra);
  const estoque = estoqueByItemId.get(Number(candidate.item.id)) ?? 0;
  let score = candidate.score;
  if (statusPreco === "preco_atualizado") score += 20;
  else if (statusPreco === "preco_antigo") score += 8;
  if (estoque > 0) score += 10;
  return score;
}

function buildCandidateMotivos(
  candidate: ScoredItem,
  row: AssistenteIAItemPlanilha,
  terms: string[],
  ultimasCompras: Map<number, UltimaCompra>,
  estoqueByItemId: Map<number, number>
): string[] {
  const item = candidate.item;
  const text = itemSearchText(item);
  const compact = itemSearchCompact(item);
  const itemCode = normalizeCode(item.codigo_interno);
  const rowAnalysis = analyzeTechnicalRow(row);
  const candidateAnalysis = analyzeTechnicalItem(item);
  const requestedSpecs = rowAnalysis.especificacoesDetectadas;
  const candidateSpecs = candidateAnalysis.especificacoesDetectadas;
  const motivos: string[] = [...candidate.motivos];
  const dimensionTerms = extractDimensionTerms(row.componente);
  const dimensionTermSet = new Set(dimensionTerms.map((term) => normalizeCompact(term)));
  const codeFragments = extractCodeFragments(row);
  const codeTermSet = new Set(codeFragments.map((term) => normalizeCompact(term)));

  if (rowAnalysis.categoriaTecnicaDetectada && sameTechnicalCategory(rowAnalysis, candidateAnalysis)) {
    motivos.push(`mesma categoria tecnica ${technicalCategoryLabel(rowAnalysis.categoriaTecnicaDetectada)}`);
  }
  if (sameTechnicalFamily(rowAnalysis, candidateAnalysis) && requestedSpecs.familia) {
    motivos.push(`mesma familia ${requestedSpecs.familia}`);
  } else if (requestedSpecs.familia && candidateSpecs.familia && sameTechnicalCategory(rowAnalysis, candidateAnalysis)) {
    motivos.push(`familia diferente (${candidateSpecs.familia} vs ${requestedSpecs.familia})`);
  }

  const current = currentCompatibility(requestedSpecs, candidateSpecs);
  if (current === "igual_ou_superior" && typeof requestedSpecs.correnteA === "number" && typeof candidateSpecs.correnteA === "number") {
    motivos.push(`corrente ${formatTechnicalNumber(candidateSpecs.correnteA)}A >= solicitada ${formatTechnicalNumber(requestedSpecs.correnteA)}A`);
  } else if ((current === "inferior" || current === "muito_inferior") && typeof requestedSpecs.correnteA === "number" && typeof candidateSpecs.correnteA === "number") {
    motivos.push(`corrente ${formatTechnicalNumber(candidateSpecs.correnteA)}A abaixo da solicitada ${formatTechnicalNumber(requestedSpecs.correnteA)}A`);
  }

  const voltage = voltageCompatibility(requestedSpecs, candidateSpecs);
  if (voltage === "compativel" && typeof requestedSpecs.tensaoV === "number") {
    if (typeof candidateSpecs.tensaoMinV === "number" && typeof candidateSpecs.tensaoMaxV === "number") {
      motivos.push(
        `tensao ${formatTechnicalNumber(candidateSpecs.tensaoMinV)}-${formatTechnicalNumber(candidateSpecs.tensaoMaxV)}V cobre ${formatTechnicalNumber(
          requestedSpecs.tensaoV
        )}V`
      );
    } else if (typeof candidateSpecs.tensaoV === "number") {
      motivos.push(`tensao ${formatTechnicalNumber(candidateSpecs.tensaoV)}V compativel`);
    }
  } else if (voltage === "incompativel") {
    motivos.push("tensao divergente");
  }

  const power = powerCompatibility(requestedSpecs, candidateSpecs);
  if (power === "igual_ou_superior" && typeof requestedSpecs.potenciaW === "number" && typeof candidateSpecs.potenciaW === "number") {
    motivos.push(`potencia ${formatTechnicalNumber(candidateSpecs.potenciaW)}W >= solicitada ${formatTechnicalNumber(requestedSpecs.potenciaW)}W`);
  } else if (power === "inferior" && typeof requestedSpecs.potenciaW === "number" && typeof candidateSpecs.potenciaW === "number") {
    motivos.push(`potencia ${formatTechnicalNumber(candidateSpecs.potenciaW)}W abaixo da solicitada ${formatTechnicalNumber(requestedSpecs.potenciaW)}W`);
  }

  if (brandMatches(row.marca, item)) motivos.push("marca compativel");

  let termReasonCount = 0;
  for (const term of terms) {
    const key = normalizeCompact(term);
    if (!key || dimensionTermSet.has(key) || codeTermSet.has(key) || !containsTerm(text, compact, term)) continue;
    motivos.push(`termo ${diagnosticText(term)} encontrado`);
    termReasonCount += 1;
    if (termReasonCount >= 3) break;
  }

  let codeReasonCount = 0;
  for (const fragment of codeFragments) {
    const fragmentCode = normalizeCode(fragment);
    if (!fragmentCode || (!itemCode.includes(fragmentCode) && !compact.includes(fragmentCode))) continue;
    motivos.push(`codigo contem ${diagnosticCode(fragment)}`);
    codeReasonCount += 1;
    if (codeReasonCount >= 3) break;
  }

  let dimensionReasonCount = 0;
  for (const dimension of dimensionTerms) {
    const compactDimension = normalizeCompact(dimension);
    if (!compactDimension || !compact.includes(compactDimension)) continue;
    motivos.push(`dimensao ${diagnosticText(dimension)} encontrada`);
    dimensionReasonCount += 1;
    if (dimensionReasonCount >= 3) break;
  }

  const itemId = Number(item.id);
  const ultimaCompra = ultimasCompras.get(itemId) ?? null;
  if (classifyPriceStatus(ultimaCompra) === "preco_atualizado") motivos.push("compra recente");

  const estoque = estoqueByItemId.get(itemId) ?? 0;
  if (estoque > 0) motivos.push("possui estoque");
  if (candidate.penalidades.length > 0) motivos.push(`penalidades: ${candidate.penalidades.join(", ")}`);

  return unique(motivos.length > 0 ? motivos : ["pontuacao por similaridade textual"]).slice(0, 10);
}

function diagnosticGroupSummary(groups: Set<AssistenteIAGrupoDiagnostico>): string {
  const values = Array.from(groups);
  const specificGroups = values.filter((group) => group !== "geral");
  return (specificGroups.length > 0 ? specificGroups : values).join(", ");
}

function buildCandidatosResumo(
  entries: Array<{ candidate: ScoredItem; group: AssistenteIAGrupoDiagnostico }>,
  row: AssistenteIAItemPlanilha,
  terms: string[],
  ultimasCompras: Map<number, UltimaCompra>,
  estoqueByItemId: Map<number, number>
): { candidatosResumo: AssistenteIACandidatoDiagnostico[]; candidatosEnviadosParaIA: number } {
  const byId = new Map<
    number,
    {
      item: ItemRow;
      pontuacaoBackend: number;
      scoreFinal: number;
      categoriaCandidatoDetectada: CategoriaTecnicaAssistenteIA;
      grupos: Set<AssistenteIAGrupoDiagnostico>;
      motivos: string[];
      penalidades: string[];
    }
  >();

  for (const entry of entries) {
    const itemId = Number(entry.candidate.item.id);
    if (!Number.isFinite(itemId) || itemId <= 0) continue;

    const pontuacaoBackend = Math.round(enrichScore(entry.candidate, ultimasCompras, estoqueByItemId));
    const motivos = buildCandidateMotivos(entry.candidate, row, terms, ultimasCompras, estoqueByItemId);
    const current = byId.get(itemId);
    if (current) {
      current.grupos.add(entry.group);
      if (pontuacaoBackend > current.pontuacaoBackend) {
        current.pontuacaoBackend = pontuacaoBackend;
        current.scoreFinal = entry.candidate.scoreFinal;
        current.categoriaCandidatoDetectada = entry.candidate.categoriaCandidatoDetectada;
        current.motivos = motivos;
        current.penalidades = entry.candidate.penalidades;
      }
      continue;
    }

    byId.set(itemId, {
      item: entry.candidate.item,
      pontuacaoBackend,
      scoreFinal: entry.candidate.scoreFinal,
      categoriaCandidatoDetectada: entry.candidate.categoriaCandidatoDetectada,
      grupos: new Set([entry.group]),
      motivos,
      penalidades: entry.candidate.penalidades,
    });
  }

  const candidatosResumo = Array.from(byId.values())
    .sort((a, b) => b.pontuacaoBackend - a.pontuacaoBackend)
    .slice(0, MAX_DIAGNOSTIC_CANDIDATES)
    .map((draft) => ({
      produtoId: String(draft.item.id),
      codigo: String(draft.item.codigo_interno ?? "").trim(),
      descricao: itemDescription(draft.item).slice(0, 260),
      fornecedorNome: getFornecedorNome(draft.item) ?? undefined,
      grupo: diagnosticGroupSummary(draft.grupos),
      pontuacaoBackend: draft.pontuacaoBackend,
      scoreFinal: draft.scoreFinal,
      categoriaCandidatoDetectada: draft.categoriaCandidatoDetectada,
      motivos: draft.motivos,
      penalidades: draft.penalidades,
    }));

  return { candidatosResumo, candidatosEnviadosParaIA: byId.size };
}

function buildDiagnosticoBase(
  row: AssistenteIAItemPlanilha,
  planoBusca: AssistenteIAPlanoBusca,
  analiseTecnica: AssistenteIAAnaliseTecnica,
  terms: string[],
  entries: Array<{ candidate: ScoredItem; group: AssistenteIAGrupoDiagnostico }>,
  ultimasCompras: Map<number, UltimaCompra>,
  estoqueByItemId: Map<number, number>,
  candidatosBancoAntesFiltro: number,
  candidatosAposCategoriaBase: number,
  candidatosRemovidosPorIncompatibilidade: number,
  candidatosRemovidosPorTermosProibidos: number,
  candidatosRemovidosPorScore: number,
  fallbackAcionado: boolean
): Omit<AssistenteIADiagnostico, "candidatosRemovidosPorValidacao"> {
  const marcaPriorizada = row.marca.trim();
  return {
    termosExtraidos: diagnosticTerms(terms),
    dimensoesDetectadas: extractDetectedDimensions(row.componente),
    codigoNormalizado: normalizedCodeForDiagnostic(row),
    marcaPriorizada: marcaPriorizada || undefined,
    categoriaTecnicaDetectada: analiseTecnica.categoriaTecnicaDetectada,
    especificacoesDetectadas:
      Object.keys(analiseTecnica.especificacoesDetectadas).length > 0 ? analiseTecnica.especificacoesDetectadas : undefined,
    planoBusca,
    gruposDetectados: detectDiagnosticGroups(row),
    candidatosBancoAntesFiltro,
    candidatosAposCategoriaBase,
    candidatosRemovidosPorIncompatibilidade,
    candidatosRemovidosPorTermosProibidos,
    candidatosRemovidosPorScore,
    fallbackAcionado,
    ...buildCandidatosResumo(entries, row, terms, ultimasCompras, estoqueByItemId),
  };
}

function buildCandidate(
  candidate: ScoredItem,
  row: AssistenteIAItemPlanilha,
  group: AssistenteIAGrupoDiagnostico,
  ultimasCompras: Map<number, UltimaCompra>,
  estoqueByItemId: Map<number, number>
): AssistenteIACandidatoBanco {
  const item = candidate.item;
  const ultimaCompra = ultimasCompras.get(Number(item.id)) ?? null;
  const estoque = estoqueByItemId.get(Number(item.id));
  const pontuacaoBackend = Math.round(enrichScore(candidate, ultimasCompras, estoqueByItemId));

  return {
    produtoId: String(item.id),
    codigo: String(item.codigo_interno ?? "").trim(),
    descricao: itemDescription(item).slice(0, 260),
    marca: String(item.fabricante ?? "").trim() || undefined,
    fornecedorNome: getFornecedorNome(item) ?? undefined,
    grupo: group,
    pontuacaoBackend,
    scoreFinal: candidate.scoreFinal,
    categoriaCandidatoDetectada: candidate.categoriaCandidatoDetectada,
    motivos: buildCandidateMotivos(candidate, row, extractTechnicalTerms(row), ultimasCompras, estoqueByItemId),
    penalidades: candidate.penalidades,
    ultimaCompraData: ultimaCompra?.data,
    ultimaCompraValorUnitario: ultimaCompra?.valorUnitario,
    estoque: Number.isFinite(estoque) ? estoque : undefined,
    statusPreco: classifyPriceStatus(ultimaCompra),
  };
}

function uniqueScoredItems(candidates: ScoredItem[]): ScoredItem[] {
  const byId = new Map<number, ScoredItem>();
  for (const candidate of candidates) {
    const id = Number(candidate.item.id);
    const current = byId.get(id);
    if (!current || candidate.scoreFinal > current.scoreFinal) byId.set(id, candidate);
  }
  return Array.from(byId.values());
}

function buildCandidatePackage(
  seed: CandidateSeed,
  ultimasCompras: Map<number, UltimaCompra>,
  estoqueByItemId: Map<number, number>
): CandidatePackage {
  const sortByContext = (items: ScoredItem[]) =>
    uniqueScoredItems(items).sort((a, b) => enrichScore(b, ultimasCompras, estoqueByItemId) - enrichScore(a, ultimasCompras, estoqueByItemId));

  const candidatosGeraisScored = sortByContext(seed.general).slice(0, MAX_GENERAL_CANDIDATES);
  const candidatosGeraisEntries = candidatosGeraisScored.map((candidate) => ({
    candidate,
    group: candidateDiagnosticGroup(seed.row, candidate.item, seed.analiseTecnica),
  }));
  const candidatosGerais = candidatosGeraisEntries.map(({ candidate, group }) =>
    buildCandidate(candidate, seed.row, group, ultimasCompras, estoqueByItemId)
  );
  const diagnosticoEntries: Array<{ candidate: ScoredItem; group: AssistenteIAGrupoDiagnostico }> = [...candidatosGeraisEntries];

  const candidatosPorGrupo: Partial<Record<AssistenteIAPapelProduto, AssistenteIACandidatoBanco[]>> = {};
  for (const [group, candidates] of Object.entries(seed.grupos) as Array<[AssistenteIAPapelProduto, ScoredItem[]]>) {
    const candidatosGrupoScored = sortByContext(candidates).slice(0, MAX_GROUP_CANDIDATES);
    const diagnosticoGrupo = toDiagnosticGroup(group);
    candidatosPorGrupo[group] = candidatosGrupoScored.map((candidate) =>
      buildCandidate(candidate, seed.row, diagnosticoGrupo, ultimasCompras, estoqueByItemId)
    );
    for (const candidate of candidatosGrupoScored) {
      diagnosticoEntries.push({ candidate, group: diagnosticoGrupo });
    }
  }

  return {
    row: seed.row,
    planoBusca: seed.planoBusca,
    analiseTecnica: seed.analiseTecnica,
    termosBuscaUsados: seed.termosBuscaUsados,
    candidatosGerais,
    candidatosPorGrupo,
    diagnosticoBase: buildDiagnosticoBase(
      seed.row,
      seed.planoBusca,
      seed.analiseTecnica,
      seed.termosBuscaUsados,
      diagnosticoEntries,
      ultimasCompras,
      estoqueByItemId,
      seed.candidatosBancoAntesFiltro,
      seed.candidatosAposCategoriaBase,
      seed.candidatosRemovidosPorIncompatibilidade,
      seed.candidatosRemovidosPorTermosProibidos,
      seed.candidatosRemovidosPorScore,
      seed.fallbackAcionado
    ),
    candidatosBancoAntesFiltro: seed.candidatosBancoAntesFiltro,
    candidatosAposCategoriaBase: seed.candidatosAposCategoriaBase,
    candidatosRemovidosPorIncompatibilidade: seed.candidatosRemovidosPorIncompatibilidade,
    candidatosRemovidosPorTermosProibidos: seed.candidatosRemovidosPorTermosProibidos,
    candidatosRemovidosPorScore: seed.candidatosRemovidosPorScore,
    fallbackAcionado: seed.fallbackAcionado,
  };
}

function collectCandidateIds(seeds: CandidateSeed[]): number[] {
  const ids = new Set<number>();
  for (const seed of seeds) {
    for (const candidate of seed.general) ids.add(Number(candidate.item.id));
    for (const candidates of Object.values(seed.grupos)) {
      for (const candidate of candidates ?? []) ids.add(Number(candidate.item.id));
    }
  }
  return Array.from(ids).filter((id) => Number.isFinite(id) && id > 0);
}

function validatePayloadRows(value: unknown): AssistenteIAItemPlanilha[] | null {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_ROWS) return null;

  const rows: AssistenteIAItemPlanilha[] = [];
  for (const raw of value) {
    const row = raw as Record<string, unknown>;
    const linha = Number(row.linha);
    const itemIdRaw = row.itemId ?? row.id ?? row.produtoId;
    const itemId = parsePayloadItemId(itemIdRaw);
    const qtd = Number(row.qtd);
    const componente = String(row.componente ?? "").trim();
    const codigo = String(row.codigo ?? "").trim();
    const marca = String(row.marca ?? "").trim();

    if (!Number.isFinite(linha) || linha <= 0) return null;
    if (hasPayloadValue(itemIdRaw) && itemId === null) return null;
    if (!Number.isFinite(qtd) || qtd <= 0) return null;
    if (!componente) return null;

    rows.push({ linha, itemId, qtd, componente, codigo, marca });
  }
  return rows;
}

async function canReadOrcamento(supabase: AuthedSupabase) {
  const checks = await Promise.allSettled([
    supabase.rpc("can", { p_resource: "financeiro", p_action: "read" }),
    supabase.rpc("can", { p_resource: "financeiro", p_action: "write" }),
    supabase.rpc("can", { p_resource: "os", p_action: "read" }),
    supabase.rpc("can", { p_resource: "os", p_action: "write" }),
  ]);
  return checks.some((result) => result.status === "fulfilled" && Boolean(result.value.data));
}

async function ensureOrcamentoExists(
  supabase: AuthedSupabase,
  params: { tenantId: string; empresaId: string; idOrCodigo: string }
): Promise<boolean> {
  const raw = params.idOrCodigo.trim();
  if (!raw) return false;

  let query = supabase
    .schema("m")
    .from("orcamento")
    .select("id")
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId)
    .is("deleted_at", null)
    .limit(1);

  query = UUID_RE.test(raw) ? query.eq("id", raw) : query.eq("codigo", raw);

  const { data, error } = await query.maybeSingle<{ id: string }>();
  if (error) throw error;
  return Boolean(data?.id);
}

async function loadItems(supabase: AuthedSupabase, tenantId: string, empresaId: string): Promise<ItemRow[]> {
  const result: ItemRow[] = [];
  const pageSize = 1000;
  const maxItems = 10000;

  for (let from = 0; from < maxItems; from += pageSize) {
    const to = Math.min(from + pageSize - 1, maxItems - 1);
    const { data, error } = await supabase
      .from("itens")
      .select(
        "id,codigo_interno,nome,descricao,categoria,subcategoria,fabricante,fornecedor_id,fornecedores!itens_tenant_empresa_fornecedor_fk(nome)"
      )
      .eq("tenant_id", tenantId)
      .eq("empresa_id", empresaId)
      .eq("ativo", true)
      .is("mesclado_em_item_id", null)
      .order("nome", { ascending: true })
      .order("id", { ascending: true })
      .range(from, to)
      .returns<ItemRow[]>();

    if (error) throw error;
    const rows = data ?? [];
    result.push(...rows);
    if (rows.length < pageSize) break;
  }

  return result;
}

async function loadUltimasCompras(
  supabase: AuthedSupabase,
  params: { tenantId: string; empresaId: string; itemIds: number[] }
): Promise<Map<number, UltimaCompra>> {
  const itemIds = Array.from(new Set(params.itemIds.filter((id) => Number.isFinite(id) && id > 0)));
  const result = new Map<number, UltimaCompra>();
  if (itemIds.length === 0) return result;

  const { data: itemRows, error: itemErr } = await supabase
    .schema("m")
    .from("pedido_compra_item")
    .select("pedido_compra_id,item_id,valor_unitario,created_at")
    .eq("tenant_id", params.tenantId)
    .eq("empresa_id", params.empresaId)
    .is("deleted_at", null)
    .in("item_id", itemIds)
    .order("created_at", { ascending: false })
    .limit(5000)
    .returns<PedidoItemRow[]>();
  if (itemErr) throw itemErr;

  const rows = itemRows ?? [];
  const pedidoIds = Array.from(new Set(rows.map((row) => String(row.pedido_compra_id ?? "").trim()).filter(Boolean)));
  const pedidoById = new Map<string, PedidoCompraRow>();

  if (pedidoIds.length > 0) {
    const { data: pedidos, error: pedidosErr } = await supabase
      .schema("m")
      .from("pedido_compra")
      .select("id,created_at,status")
      .eq("tenant_id", params.tenantId)
      .eq("empresa_id", params.empresaId)
      .is("deleted_at", null)
      .in("id", pedidoIds)
      .returns<PedidoCompraRow[]>();
    if (pedidosErr) throw pedidosErr;
    for (const pedido of pedidos ?? []) pedidoById.set(String(pedido.id), pedido);
  }

  for (const row of rows) {
    const itemId = Number(row.item_id ?? 0);
    if (!Number.isFinite(itemId) || itemId <= 0 || result.has(itemId)) continue;

    const pedido = pedidoById.get(String(row.pedido_compra_id ?? ""));
    if (pedido && String(pedido.status ?? "").trim().toUpperCase() === "CANCELADO") continue;

    const valorUnitario = toNumber(row.valor_unitario);
    if (!Number.isFinite(valorUnitario) || valorUnitario < 0) continue;

    const data = String(pedido?.created_at ?? row.created_at ?? "").trim();
    if (!data) continue;

    result.set(itemId, { data, valorUnitario });
  }

  return result;
}

async function loadEstoqueByItemId(
  supabase: AuthedSupabase,
  params: { tenantId: string; empresaId: string; itemIds: number[] }
): Promise<Map<number, number>> {
  const itemIds = Array.from(new Set(params.itemIds.filter((id) => Number.isFinite(id) && id > 0)));
  const result = new Map<number, number>();
  if (itemIds.length === 0) return result;

  try {
    const { data, error } = await supabase
      .from("estoque")
      .select("item_id,quantidade_atual")
      .eq("tenant_id", params.tenantId)
      .eq("empresa_id", params.empresaId)
      .in("item_id", itemIds)
      .returns<EstoqueRow[]>();

    if (error) return result;
    for (const row of data ?? []) {
      const itemId = Number(row.item_id ?? 0);
      if (!Number.isFinite(itemId) || itemId <= 0) continue;
      const current = result.get(itemId) ?? 0;
      result.set(itemId, current + Math.max(0, toNumber(row.quantidade_atual)));
    }
  } catch {
    return result;
  }

  return result;
}

function buildPromptPayload(packages: CandidatePackage[]) {
  return {
    itens: packages.map((pkg) => ({
      linha: pkg.row.linha,
      qtdOriginal: pkg.row.qtd,
      componenteOriginal: pkg.row.componente,
      codigoOriginal: pkg.row.codigo,
      marcaOriginal: pkg.row.marca,
      planoBusca: pkg.planoBusca,
      categoriaTecnicaDetectada: pkg.analiseTecnica.categoriaTecnicaDetectada,
      especificacoesDetectadas: pkg.analiseTecnica.especificacoesDetectadas,
      termosBuscaUsados: pkg.termosBuscaUsados,
      candidatosGerais: pkg.candidatosGerais,
      candidatosPorGrupo: pkg.candidatosPorGrupo,
    })),
  };
}

function openAIConfig(): { apiKey: string; model: string } | null {
  const apiKey = String(process.env.OPENAI_API_KEY ?? process.env.ASSISTENTE_IA_OPENAI_API_KEY ?? "").trim();
  if (!apiKey) return null;
  const model = String(process.env.ASSISTENTE_IA_OPENAI_MODEL ?? process.env.OPENAI_MODEL ?? "gpt-4.1-mini").trim();
  return { apiKey, model };
}

function getRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function extractOpenAIText(value: unknown): string {
  const record = getRecord(value);
  if (!record) return "";

  if (typeof record.output_text === "string") return record.output_text;

  const output = Array.isArray(record.output) ? record.output : [];
  const parts: string[] = [];
  for (const outputItem of output) {
    const outputRecord = getRecord(outputItem);
    const content = Array.isArray(outputRecord?.content) ? outputRecord.content : [];
    for (const contentItem of content) {
      const contentRecord = getRecord(contentItem);
      const text = contentRecord?.text;
      if (typeof text === "string") parts.push(text);
    }
  }
  return parts.join("\n").trim();
}

function parseJsonFromText(text: string): Record<string, unknown> {
  const trimmed = text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "");
  try {
    const parsed = JSON.parse(trimmed);
    const record = getRecord(parsed);
    if (record) return record;
  } catch {
    // tenta extrair o primeiro objeto JSON abaixo
  }

  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start >= 0 && end > start) {
    const parsed = JSON.parse(trimmed.slice(start, end + 1));
    const record = getRecord(parsed);
    if (record) return record;
  }

  throw new Error("A IA retornou uma resposta em formato inválido.");
}

async function callAIPlanosBusca(rows: AssistenteIAItemPlanilha[], config: { apiKey: string; model: string }): Promise<Record<string, unknown>> {
  const systemPrompt = [
    "Voce e um assistente tecnico para orcamento de paineis eletricos.",
    "Sua tarefa nesta etapa e interpretar itens de planilha e gerar apenas um plano de busca estruturado.",
    "Nao escolha produtos, nao informe produtoId, nao invente precos e nao use produtos fora do banco.",
    "O backend fara a busca no banco usando gruposBusca; por isso os termos devem separar produto principal, laterais, base soleira, acessorios e equivalentes.",
    "Identifique quando o item e composto. Armario/painel com base soleira, laterais ou acessorios deve gerar mais de um grupo quando necessario.",
    "Use categoriaTecnica exatamente entre: armario_painel, soft_starter, rele_estado_solido, fonte_24v, borne, disjuntor, contator, clp, ihm, seguranca, sinalizacao, ventilacao, desconhecida.",
    "Use papel de grupo exatamente entre: produto_principal, lateral, base_soleira, acessorio, equivalente, alternativa.",
    "Termos obrigatorios podem ser familias de sinonimos relevantes para a busca; termos desejaveis refinam marca, dimensoes, modelo e especificacoes.",
    "Termos proibidos devem remover candidatos tecnicamente errados, como borne para rele de estado solido, sinalizador para fonte 24V e chave de seguranca para soft-starter.",
    "Retorne somente JSON valido no formato {\"planos\": [...]} sem markdown.",
  ].join(" ");

  const schemaHint = {
    linha: "number",
    categoriaTecnica:
      "armario_painel | soft_starter | rele_estado_solido | fonte_24v | borne | disjuntor | contator | clp | ihm | seguranca | sinalizacao | ventilacao | desconhecida",
    itemComposto: "boolean",
    marcaPreferencial: "string opcional",
    fabricantesAlternativos: "string[] opcional",
    dimensoes: "string[] opcional, por exemplo 1800x800x600",
    especificacoes: {
      tensaoV: "number opcional",
      correnteA: "number opcional",
      potenciaW: "number opcional",
      familia: "string opcional",
      modelo: "string opcional",
    },
    gruposBusca: [
      {
        papel: "produto_principal | lateral | base_soleira | acessorio | equivalente | alternativa",
        termosObrigatorios: "string[]",
        termosDesejaveis: "string[]",
        termosProibidos: "string[]",
        marcaPreferencial: "string opcional",
        observacao: "string curta",
      },
    ],
  };

  const body = {
    model: config.model,
    temperature: 0.1,
    input: [
      { role: "system", content: systemPrompt },
      {
        role: "user",
        content: JSON.stringify(
          {
            regras: [
              "Para armario metalico auto-portante com base soleira, use categoria armario_painel, itemComposto true, grupo produto_principal para armario/gabinete/painel, grupo lateral quando o texto pedir laterais e grupo base_soleira quando houver base/soleira/soco.",
              "Para Soft-Starter WEG SSW08 - 130A / 380V, use categoria soft_starter, familia SSW08, correnteA 130, tensaoV 380 e termos proibidos como chave de seguranca, intertravamento, botao, borne e fonte.",
              "Para Rele de Estado Solido Serie 857 WAGO, use categoria rele_estado_solido, familia 857, marca WAGO e termos proibidos como borne, terminal, conector, terminacao e jumper.",
              "Para Fonte de Alimentacao Estabilizada 24VCC / 10A (240W), use categoria fonte_24v, tensaoV 24, correnteA 10, potenciaW 240 e termos proibidos como campainha, sirene, botao, torre, sinalizador, rele e borne.",
              "Nao use produto_unico, composicao ou decisao nesta etapa; isso sera decidido na avaliacao.",
            ],
            schemaResposta: { planos: [schemaHint] },
            itens: rows.map((row) => ({
              linha: row.linha,
              qtd: row.qtd,
              componente: row.componente,
              codigo: row.codigo,
              marca: row.marca,
            })),
          },
          null,
          2
        ),
      },
    ],
  };

  const res = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const responseText = await res.text();
  let json: unknown = null;
  if (responseText) {
    try {
      json = JSON.parse(responseText);
    } catch {
      json = null;
    }
  }

  if (!res.ok) {
    const record = getRecord(json);
    const error = getRecord(record?.error);
    const message = typeof error?.message === "string" ? error.message : responseText.slice(0, 300);
    throw new Error(message || "Erro ao gerar plano de busca com IA.");
  }

  const text = extractOpenAIText(json);
  if (!text) throw new Error("A IA nao retornou texto para o plano de busca.");
  return parseJsonFromText(text);
}

async function callAI(packages: CandidatePackage[], config: { apiKey: string; model: string }): Promise<Record<string, unknown>> {
  const systemPrompt = [
    "Esta e a segunda etapa: avalie candidatos encontrados pelo backend a partir do plano de busca da IA.",
    "Use o planoBusca recebido como contexto tecnico e respeite os candidatos agrupados por papel.",
    "Você é um assistente técnico para orçamento de painéis elétricos.",
    "Sua tarefa é analisar itens de uma planilha e escolher produtos existentes no banco.",
    "Você não pode inventar produtos, produtoId, código, fornecedor ou preço.",
    "Você só pode selecionar produtoId presente nos candidatos enviados.",
    "Você só deve escolher candidatos tecnicamente compatíveis com categoriaCandidatoDetectada igual à categoriaTecnicaDetectada do item.",
    "Se o candidato tiver categoria diferente da categoria solicitada, não selecione.",
    "Use scoreFinal, motivos e penalidades como sinais fortes de compatibilidade técnica.",
    "Se o item for composto, monte uma composição apenas com candidatos disponíveis.",
    "Para fonte 24V, não selecione campainha, sinalizador, torre, botão ou sirene apenas por conter 24V.",
    "Para relé de estado sólido, não selecione borne WAGO apenas por ser WAGO ou trilho DIN.",
    "Para soft-starter, não selecione chave de segurança ou intertravamento.",
    "Para armário/painel com base soleira, não use base soleira como produto principal; use composição e papelNaComposicao correto.",
    "Não retorne nao_encontrado se houver candidatos da mesma categoria técnica que possam servir como equivalente para orçamento.",
    "Quando não houver produto exato, sugira o melhor equivalente disponível entre os candidatos, com tipoResultado equivalente ou precisa_revisao.",
    "Modelo ou família diferente, por exemplo SSW08 solicitado e SSW07 encontrado, não é match exato; pode ser equivalente somente para revisão.",
    "Se corrente ou tensão do candidato parecer compatível ou superior, explique isso no resumo; se não conseguir confirmar, coloque alerta técnico.",
    "Use nao_encontrado somente quando nenhum candidato enviado for da mesma categoria técnica ou tecnicamente aproveitável.",
    "Nunca marque equivalente como aceitar.",
    "Se não houver candidato seguro, marque como precisa_revisao ou nao_encontrado.",
    "Equivalentes, troca de fabricante, preço antigo ou sem histórico devem ficar para revisão.",
    "Retorne somente JSON válido no formato {\"resultados\": [...]} sem markdown.",
  ].join(" ");

  const schemaHint = {
    linha: "number",
    qtdOriginal: "number",
    componenteOriginal: "string",
    codigoOriginal: "string",
    marcaOriginal: "string",
    tipoResultado: "produto_unico | composicao | equivalente | nao_encontrado | precisa_revisao",
    produtosSelecionados: [
      {
        produtoId: "string, deve existir nos candidatos",
        qtdSugerida: "number",
        papelNaComposicao: "produto_principal | lateral | base_soleira | acessorio | equivalente | alternativa | outro",
        justificativa: "string curta",
      },
    ],
    confianca: "0 a 100",
    decisaoSugerida: "aceitar | revisar | cotar_cadastrar | ignorar",
    resumoIA: "string curta",
    alertaTecnico: "string opcional",
    termosBuscaUsados: "string[]",
    categoriaTecnicaDetectada: "string opcional, ecoe o valor recebido quando existir",
    especificacoesDetectadas: "objeto opcional, ecoe as especificacoes recebidas quando existirem",
  };

  const body = {
    model: config.model,
    temperature: 0.1,
    input: [
      { role: "system", content: systemPrompt },
      {
        role: "user",
        content: JSON.stringify(
          {
            regrasDeDecisao: [
              "produto_unico só pode sugerir aceitar se confiança >= 90, preço atualizado e correspondência tecnicamente clara.",
              "composicao sempre deve sugerir revisar.",
              "equivalente sempre deve sugerir revisar.",
              "equivalente nunca pode sugerir aceitar.",
              "precisa_revisao deve sugerir revisar.",
              "nao_encontrado deve sugerir cotar_cadastrar apenas quando não houver candidato de mesma categoria técnica.",
              "Se houver candidato com grupo mesma_categoria, mesma_familia, equivalente_tecnico, codigo_parcial ou alternativa_fabricante, prefira revisar em vez de nao_encontrado.",
              "Para soft-starter, SSW07 e SSW08 são famílias diferentes: use equivalente/revisar, alertando para validar corrente, tensão, modelo e aplicação.",
              "Não selecione candidato com penalidades de incompatibilidade técnica forte.",
              "Para fonte 24V, campainha/sinalizador/botão/sirene não são equivalentes.",
              "Para relé de estado sólido, borne/terminal/jumper/placa final não são equivalentes.",
              "Para armário, produto principal deve ser armário/gabinete/painel; base soleira deve ter papelNaComposicao base_soleira.",
              "Equivalente sempre deve manter decisaoSugerida revisar.",
              "Não inclua preços criados pela IA. Use somente dados dos candidatos.",
            ],
            schemaResposta: { resultados: [schemaHint] },
            dados: buildPromptPayload(packages),
          },
          null,
          2
        ),
      },
    ],
  };

  const res = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const responseText = await res.text();
  let json: unknown = null;
  if (responseText) {
    try {
      json = JSON.parse(responseText);
    } catch {
      json = null;
    }
  }

  if (!res.ok) {
    const record = getRecord(json);
    const errorRecord = getRecord(record?.error);
    const message = normalizeNullableText(errorRecord?.message, 300);
    throw new Error(message || "Erro ao consultar a IA.");
  }

  const outputText = extractOpenAIText(json);
  if (!outputText) throw new Error("A IA não retornou conteúdo para análise.");
  return parseJsonFromText(outputText);
}

function candidateMap(pkg: CandidatePackage): Map<string, AssistenteIACandidatoBanco> {
  const result = new Map<string, AssistenteIACandidatoBanco>();
  for (const candidate of pkg.candidatosGerais) result.set(candidate.produtoId, candidate);
  for (const candidates of Object.values(pkg.candidatosPorGrupo)) {
    for (const candidate of candidates ?? []) result.set(candidate.produtoId, candidate);
  }
  return result;
}

function buildDiagnostico(pkg: CandidatePackage, candidatosRemovidosPorValidacao: number): AssistenteIADiagnostico {
  return {
    ...pkg.diagnosticoBase,
    candidatosRemovidosPorValidacao,
  };
}

function parseTipo(value: unknown, selectedCount: number, candidateCount: number): AssistenteIATipoResultado {
  const raw = String(value ?? "").trim() as AssistenteIATipoResultado;
  if (VALID_TIPOS.has(raw)) return raw;
  if (selectedCount > 1) return "composicao";
  if (selectedCount === 1) return "produto_unico";
  return candidateCount > 0 ? "precisa_revisao" : "nao_encontrado";
}

function parseDecisao(value: unknown): AssistenteIADecisao {
  const raw = String(value ?? "").trim() as AssistenteIADecisao;
  return VALID_DECISOES.has(raw) ? raw : "revisar";
}

function parsePapel(value: unknown): AssistenteIAPapelProduto {
  const raw = String(value ?? "").trim() as AssistenteIAPapelProduto;
  return VALID_PAPEIS.has(raw) ? raw : "outro";
}

function hasExactCodeMatch(row: AssistenteIAItemPlanilha, candidate: AssistenteIACandidatoBanco | AssistenteIAProdutoSelecionado): boolean {
  const rowCode = normalizeCode(row.codigo);
  const candidateCode = normalizeCode(candidate.codigo);
  return Boolean(rowCode && candidateCode && rowCode === candidateCode);
}

function allPackageCandidates(pkg: CandidatePackage): AssistenteIACandidatoBanco[] {
  return Array.from(candidateMap(pkg).values()).sort((a, b) => b.pontuacaoBackend - a.pontuacaoBackend);
}

function isSameCategoryCandidate(pkg: CandidatePackage, candidate: AssistenteIACandidatoBanco): boolean {
  const candidateAnalysis = analyzeTechnicalItem(candidate);
  return sameTechnicalCategory(pkg.analiseTecnica, candidateAnalysis);
}

function hasTechnicalReviewCandidate(pkg: CandidatePackage): boolean {
  return allPackageCandidates(pkg).some((candidate) => {
    if (["codigo_exato", "codigo_parcial", "mesma_familia", "mesma_categoria", "equivalente_tecnico", "alternativa_fabricante"].includes(candidate.grupo)) {
      return true;
    }
    return isSameCategoryCandidate(pkg, candidate);
  });
}

function canAutoSuggestEquivalent(pkg: CandidatePackage, candidate: AssistenteIACandidatoBanco): boolean {
  if (!isSameCategoryCandidate(pkg, candidate) && !["codigo_parcial", "mesma_familia", "equivalente_tecnico"].includes(candidate.grupo)) return false;

  const requestedSpecs = pkg.analiseTecnica.especificacoesDetectadas;
  const candidateSpecs = analyzeTechnicalItem(candidate).especificacoesDetectadas;
  if (voltageCompatibility(requestedSpecs, candidateSpecs) === "incompativel") return false;
  if (currentCompatibility(requestedSpecs, candidateSpecs) === "muito_inferior") return false;
  if (powerCompatibility(requestedSpecs, candidateSpecs) === "inferior") return false;
  return true;
}

function bestEquivalentCandidate(pkg: CandidatePackage): AssistenteIACandidatoBanco | null {
  return allPackageCandidates(pkg).find((candidate) => !hasExactCodeMatch(pkg.row, candidate) && canAutoSuggestEquivalent(pkg, candidate)) ?? null;
}

function buildEquivalentJustification(pkg: CandidatePackage, candidate: AssistenteIACandidatoBanco): string {
  const motivos = candidate.motivos.length > 0 ? candidate.motivos.slice(0, 3).join("; ") : "mesma categoria tecnica para revisao";
  return `Equivalente sugerido para revisao: ${motivos}.`;
}

function buildEquivalentSelectedProduct(pkg: CandidatePackage, candidate: AssistenteIACandidatoBanco): AssistenteIAProdutoSelecionado {
  return {
    produtoId: candidate.produtoId,
    codigo: candidate.codigo,
    descricao: candidate.descricao,
    marca: candidate.marca,
    fornecedorNome: candidate.fornecedorNome,
    qtdSugerida: pkg.row.qtd,
    papelNaComposicao: "equivalente",
    justificativa: buildEquivalentJustification(pkg, candidate),
    ultimaCompraData: candidate.ultimaCompraData,
    ultimaCompraValorUnitario: candidate.ultimaCompraValorUnitario,
    estoque: candidate.estoque,
    statusPreco: candidate.statusPreco,
  };
}

function buildTechnicalReviewAlert(pkg: CandidatePackage, selected: AssistenteIAProdutoSelecionado[]): string {
  const parts: string[] = [];
  const specs = pkg.analiseTecnica.especificacoesDetectadas;
  const candidate = selected[0] ? candidateMap(pkg).get(selected[0].produtoId) : null;
  const candidateSpecs = candidate ? analyzeTechnicalItem(candidate).especificacoesDetectadas : {};

  if (pkg.analiseTecnica.categoriaTecnicaDetectada === "soft_starter") {
    parts.push("Equivalente de soft-starter: validar modelo/familia, corrente, tensao e aplicacao antes de usar.");
  } else if (pkg.analiseTecnica.categoriaTecnicaDetectada) {
    parts.push(`Equivalente de ${technicalCategoryLabel(pkg.analiseTecnica.categoriaTecnicaDetectada)}: validar especificacoes antes de usar.`);
  }

  if (specs.familia && candidateSpecs.familia && normalizeCompact(specs.familia) !== normalizeCompact(candidateSpecs.familia)) {
    parts.push(`Familia diferente (${candidateSpecs.familia} vs ${specs.familia}).`);
  }
  if (currentCompatibility(specs, candidateSpecs) === "desconhecida" && typeof specs.correnteA === "number") {
    parts.push("Corrente do candidato nao confirmada.");
  }
  if (voltageCompatibility(specs, candidateSpecs) === "desconhecida" && typeof specs.tensaoV === "number") {
    parts.push("Tensao do candidato nao confirmada.");
  }
  if (powerCompatibility(specs, candidateSpecs) === "desconhecida" && typeof specs.potenciaW === "number") {
    parts.push("Potencia do candidato nao confirmada.");
  }

  return parts.join(" ");
}

function enforceSafeDecision(
  row: AssistenteIAItemPlanilha,
  tipo: AssistenteIATipoResultado,
  selected: AssistenteIAProdutoSelecionado[],
  confianca: number,
  aiDecision: AssistenteIADecisao
): AssistenteIADecisao {
  if (aiDecision === "ignorar") return "ignorar";
  if (tipo === "nao_encontrado") return "cotar_cadastrar";
  if (selected.length === 0) return tipo === "precisa_revisao" ? "revisar" : "cotar_cadastrar";
  if (tipo !== "produto_unico" || selected.length !== 1) return "revisar";

  const candidate = selected[0];
  const sameBrand = !row.marca.trim() || brandMatches(row.marca, candidate);
  if (confianca >= 90 && candidate.statusPreco === "preco_atualizado" && sameBrand && hasExactCodeMatch(row, candidate)) {
    return "aceitar";
  }

  return "revisar";
}

function sanitizeSelectedProducts(
  rawProducts: unknown,
  row: AssistenteIAItemPlanilha,
  candidates: Map<string, AssistenteIACandidatoBanco>
): { selected: AssistenteIAProdutoSelecionado[]; invalidIds: string[] } {
  const selected: AssistenteIAProdutoSelecionado[] = [];
  const invalidIds: string[] = [];
  const seen = new Set<string>();
  const products = Array.isArray(rawProducts) ? rawProducts : [];

  for (const rawProduct of products) {
    const record = getRecord(rawProduct);
    const produtoId = String(record?.produtoId ?? "").trim();
    if (!produtoId || seen.has(produtoId)) continue;

    const candidate = candidates.get(produtoId);
    if (!candidate) {
      invalidIds.push(produtoId);
      continue;
    }

    seen.add(produtoId);
    selected.push({
      produtoId: candidate.produtoId,
      codigo: candidate.codigo,
      descricao: candidate.descricao,
      marca: candidate.marca,
      fornecedorNome: candidate.fornecedorNome,
      qtdSugerida: clampNumber(record?.qtdSugerida ?? row.qtd, 0.001, 999999),
      papelNaComposicao: parsePapel(record?.papelNaComposicao),
      justificativa: normalizeNullableText(record?.justificativa, 300) || "Selecionado pela IA para revisão técnica.",
      ultimaCompraData: candidate.ultimaCompraData,
      ultimaCompraValorUnitario: candidate.ultimaCompraValorUnitario,
      estoque: candidate.estoque,
      statusPreco: candidate.statusPreco,
    });
  }

  return { selected, invalidIds };
}

function sanitizeResult(rawResult: unknown, pkg: CandidatePackage): AssistenteIAResultadoAnalise {
  const record = getRecord(rawResult);
  const candidates = candidateMap(pkg);
  const { selected: selectedFromAI, invalidIds } = sanitizeSelectedProducts(record?.produtosSelecionados, pkg.row, candidates);
  let selected = selectedFromAI;
  const backendEquivalent = selected.length === 0 ? bestEquivalentCandidate(pkg) : null;
  if (backendEquivalent) selected = [buildEquivalentSelectedProduct(pkg, backendEquivalent)];
  const allCandidateCount = candidates.size;
  let tipo = parseTipo(record?.tipoResultado, selected.length, allCandidateCount);

  if (tipo === "produto_unico" && selected.length > 1) tipo = "composicao";
  if (selected.length > 0 && tipo === "nao_encontrado") tipo = "equivalente";
  if (tipo === "produto_unico" && selected.length === 1 && !hasExactCodeMatch(pkg.row, selected[0])) {
    tipo = "equivalente";
  }
  if (selected.length === 0 && tipo === "nao_encontrado" && hasTechnicalReviewCandidate(pkg)) tipo = "precisa_revisao";
  if (selected.length === 0 && allCandidateCount === 0) tipo = "nao_encontrado";
  if (selected.length === 0 && tipo !== "nao_encontrado") tipo = "precisa_revisao";

  const confianca = Math.round(clampNumber(record?.confianca, 0, 100));
  const aiDecision = parseDecisao(record?.decisaoSugerida);
  const decisaoSugerida = enforceSafeDecision(pkg.row, tipo, selected, confianca, aiDecision);
  const resumoIA =
    normalizeNullableText(record?.resumoIA, 500) ||
    (selected.length > 0
      ? "Sugestão gerada pela IA a partir dos candidatos retornados do banco."
      : "Nenhum candidato seguro foi selecionado pela IA.");

  const alertaParts: string[] = [];
  const rawAlert = normalizeNullableText(record?.alertaTecnico, 500);
  if (rawAlert) alertaParts.push(rawAlert);
  if (pkg.row.itemId) alertaParts.push(`ID ${pkg.row.itemId} informado na planilha não foi encontrado em itens ativos desta empresa; análise feita por busca.`);
  if (backendEquivalent) alertaParts.push("A IA nao selecionou produto; o backend sugeriu o melhor equivalente tecnico dos candidatos para revisao.");
  if (invalidIds.length > 0) alertaParts.push("A IA retornou produto fora dos candidatos; a seleção foi removida.");
  if (allCandidateCount === 0) alertaParts.push("Falha na geracao de candidatos: nenhum item da categoria foi enviado para IA. Ver diagnostico.");
  if (tipo === "equivalente") alertaParts.push("Sugestão equivalente: revisar fabricante, modelo e requisitos técnicos.");
  if (tipo === "equivalente" || tipo === "precisa_revisao") alertaParts.push(buildTechnicalReviewAlert(pkg, selected));
  if (selected.some((product) => product.statusPreco !== "preco_atualizado")) {
    alertaParts.push("Há produto selecionado com preço antigo ou sem histórico.");
  }

  const termos = Array.isArray(record?.termosBuscaUsados)
    ? (record.termosBuscaUsados as unknown[]).map((term) => normalizeNullableText(term, 80)).filter(Boolean)
    : pkg.termosBuscaUsados;

  return {
    linha: pkg.row.linha,
    qtdOriginal: pkg.row.qtd,
    componenteOriginal: pkg.row.componente,
    codigoOriginal: pkg.row.codigo,
    marcaOriginal: pkg.row.marca,
    tipoResultado: tipo,
    produtosSelecionados: selected,
    confianca,
    decisaoSugerida,
    resumoIA,
    alertaTecnico: unique(alertaParts).join(" "),
    termosBuscaUsados: unique(termos).slice(0, 40),
    categoriaTecnicaDetectada: pkg.analiseTecnica.categoriaTecnicaDetectada,
    especificacoesDetectadas:
      Object.keys(pkg.analiseTecnica.especificacoesDetectadas).length > 0 ? pkg.analiseTecnica.especificacoesDetectadas : undefined,
    diagnostico: buildDiagnostico(pkg, invalidIds.length),
  };
}

function fallbackResult(pkg: CandidatePackage): AssistenteIAResultadoAnalise {
  const equivalent = bestEquivalentCandidate(pkg);
  const selected = equivalent ? [buildEquivalentSelectedProduct(pkg, equivalent)] : [];
  const hasReviewCandidate = hasTechnicalReviewCandidate(pkg);
  const tipoResultado: AssistenteIATipoResultado =
    selected.length > 0 ? "equivalente" : hasReviewCandidate || pkg.candidatosGerais.length > 0 ? "precisa_revisao" : "nao_encontrado";

  return {
    linha: pkg.row.linha,
    qtdOriginal: pkg.row.qtd,
    componenteOriginal: pkg.row.componente,
    codigoOriginal: pkg.row.codigo,
    marcaOriginal: pkg.row.marca,
    tipoResultado,
    produtosSelecionados: selected,
    confianca: 0,
    decisaoSugerida: tipoResultado === "nao_encontrado" ? "cotar_cadastrar" : "revisar",
    resumoIA:
      selected.length > 0
        ? "Equivalente tecnico sugerido pelo backend a partir dos candidatos retornados do banco."
        : pkg.candidatosGerais.length > 0
        ? "Candidatos foram encontrados no banco, mas a IA não retornou seleção segura para esta linha."
        : "Nenhum candidato foi encontrado no banco para esta linha.",
    alertaTecnico:
      unique([
        pkg.row.itemId
          ? `ID ${pkg.row.itemId} informado na planilha não foi encontrado em itens ativos desta empresa; análise feita por busca.`
          : "",
        pkg.candidatosGerais.length === 0
          ? "Falha na geracao de candidatos: nenhum item da categoria foi enviado para IA. Ver diagnostico."
          : unique(["Revisar manualmente os candidatos antes de qualquer inclusão.", buildTechnicalReviewAlert(pkg, selected)]).join(" "),
      ]).join(" "),
    termosBuscaUsados: pkg.termosBuscaUsados,
    categoriaTecnicaDetectada: pkg.analiseTecnica.categoriaTecnicaDetectada,
    especificacoesDetectadas:
      Object.keys(pkg.analiseTecnica.especificacoesDetectadas).length > 0 ? pkg.analiseTecnica.especificacoesDetectadas : undefined,
    diagnostico: buildDiagnostico(pkg, 0),
  };
}

function sanitizeAIResults(aiPayload: Record<string, unknown>, packages: CandidatePackage[]): AssistenteIAResultadoAnalise[] {
  const rawResults = Array.isArray(aiPayload.resultados) ? aiPayload.resultados : [];
  const rawByLinha = new Map<number, unknown>();
  for (const rawResult of rawResults) {
    const record = getRecord(rawResult);
    const linha = Number(record?.linha ?? 0);
    if (Number.isFinite(linha) && linha > 0) rawByLinha.set(linha, rawResult);
  }

  return packages.map((pkg) => {
    const rawResult = rawByLinha.get(pkg.row.linha);
    return rawResult ? sanitizeResult(rawResult, pkg) : fallbackResult(pkg);
  });
}

function errorMessage(error: unknown, fallback: string): string {
  if (error instanceof Error && error.message) return error.message;
  if (typeof error === "object" && error !== null && "message" in error) {
    return String((error as { message?: unknown }).message ?? fallback);
  }
  return fallback;
}

export async function POST(req: NextRequest, context: { params: Promise<{ id?: string }> }) {
  try {
    const auth = await getAuthSupabase(req);
    if ("error" in auth) return auth.error;
    const { supabase } = auth;

    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const ctx = await resolveTenantEmpresa(supabase, body, req.nextUrl.searchParams);
    if (!ctx) return jsonError(400, "Tenant/empresa não carregados.");

    if (!(await canReadOrcamento(supabase))) return jsonError(403, "Sem permissão para consultar itens do orçamento.");

    const { id: rawId = "" } = await context.params;
    const idOrCodigo = decodeURIComponent(String(rawId ?? "")).trim();
    if (!idOrCodigo) return jsonError(400, "Orçamento inválido.");

    const exists = await ensureOrcamentoExists(supabase, { tenantId: ctx.tenantId, empresaId: ctx.empresaId, idOrCodigo });
    if (!exists) return jsonError(404, "Orçamento não encontrado.");

    const rows = validatePayloadRows(body.itens);
    if (!rows) return jsonError(400, "Itens da planilha inválidos.");

    const items = await loadItems(supabase, ctx.tenantId, ctx.empresaId);
    const itemById = new Map(items.map((item) => [Number(item.id), item]));
    const directMatches: Array<{ row: AssistenteIAItemPlanilha; item: ItemRow }> = [];
    const rowsParaIA: AssistenteIAItemPlanilha[] = [];

    for (const row of rows) {
      const item = row.itemId ? itemById.get(row.itemId) ?? null : null;
      if (item) {
        directMatches.push({ row, item });
      } else {
        rowsParaIA.push(row);
      }
    }

    const config = rowsParaIA.length > 0 ? openAIConfig() : null;
    if (rowsParaIA.length > 0 && !config) return jsonError(503, AI_NOT_CONFIGURED_MESSAGE);

    let seeds: CandidateSeed[] = [];
    if (rowsParaIA.length > 0 && config) {
      const planosPayload = await callAIPlanosBusca(rowsParaIA, config);
      const planosBusca = sanitizePlanosBusca(planosPayload, rowsParaIA);
      seeds = rowsParaIA.map((row) => buildCandidateSeed(items, row, planosBusca.get(row.linha) ?? buildFallbackPlanoBusca(row)));
    }

    const directItemIds = directMatches.map(({ item }) => Number(item.id));
    const candidateIds = Array.from(new Set([...directItemIds, ...collectCandidateIds(seeds)]));
    const [ultimasCompras, estoqueByItemId] = await Promise.all([
      loadUltimasCompras(supabase, { tenantId: ctx.tenantId, empresaId: ctx.empresaId, itemIds: candidateIds }),
      loadEstoqueByItemId(supabase, { tenantId: ctx.tenantId, empresaId: ctx.empresaId, itemIds: candidateIds }),
    ]);

    const directResults = directMatches.map(({ row, item }) => buildDirectIdResult(row, item, ultimasCompras, estoqueByItemId));
    let aiResults: AssistenteIAResultadoAnalise[] = [];
    if (rowsParaIA.length > 0 && config) {
      const packages = seeds.map((seed) => buildCandidatePackage(seed, ultimasCompras, estoqueByItemId));
      const aiPayload = await callAI(packages, config);
      aiResults = sanitizeAIResults(aiPayload, packages);
    }

    const resultsByLinha = new Map([...directResults, ...aiResults].map((result) => [result.linha, result]));
    const resultados = rows.map((row) => resultsByLinha.get(row.linha)).filter((result): result is AssistenteIAResultadoAnalise => Boolean(result));

    return Response.json({
      resultados,
      modelo: config?.model ?? null,
      aviso:
        directMatches.length > 0
          ? `${directMatches.length} item(ns) vinculado(s) diretamente pelo ID da planilha. Nenhum item foi adicionado ao orçamento.`
          : "Nenhum item foi adicionado ao orçamento.",
    });
  } catch (e: unknown) {
    return jsonError(500, errorMessage(e, "Erro ao analisar itens com IA."));
  }
}
