import { readFile } from "node:fs/promises";
import path from "node:path";
import { createHmac, timingSafeEqual } from "node:crypto";
import { normalizarNomeCadastro } from "@/lib/itens/normalizacaoNome";
import { origemFiscalConfirmada } from "@/lib/itens/cadastroNormalizacao";
import { pendenciasDescricaoTecnica, REGRAS_SENSORES_SEGURANCA } from "@/lib/itens/qualidadeDescricao";

export type ItemFinalidade = "consumo" | "materia_prima" | "revenda" | "imobilizado" | "outros";
export type Confianca = "alta" | "media" | "baixa";
export type TipoCorrespondenciaPreco = "exato" | "similar" | "nao_encontrado";

export type GrupoRow = {
  id: number;
  codigo: string | null;
  nome: string | null;
  grupo_pai_id: number | null;
  ativo?: boolean | null;
};

export type FornecedorRow = {
  id: number;
  nome: string | null;
  ativo: boolean | null;
  finalidade_padrao: ItemFinalidade | null;
  motivo_compra_padrao_id: string | null;
};

export type FonteWeb = {
  titulo: string;
  url: string;
  dominio: string;
};

/** Cotação oficial da PTAX, obtida diretamente da API pública do Banco Central. */
export type CotacaoCambioPtax = {
  moeda: string;
  /** Quantos BRL correspondem a uma unidade da moeda de origem. */
  taxa_cambio_brl: number;
  fonte: FonteWeb;
  /** Dia da cotação retornada pela própria PTAX, no formato YYYY-MM-DD. */
  data_cambio: string;
};

export type NovoGrupo = {
  codigo: string;
  nome: string;
  grupo_pai_id: number | null;
  justificativa: string;
};

export type PesquisaPreco = {
  status: "encontrado" | "pendente";
  tipo_correspondencia: TipoCorrespondenciaPreco;
  marketplace: string | null;
  fonte: string | null;
  fonte_url: string | null;
  titulo: string | null;
  moeda: string | null;
  preco_origem: number | null;
  /** Quantos BRL correspondem a uma unidade da moeda de origem. */
  taxa_cambio_para_brl: number | null;
  /** URL de uma fonte de cÃ¢mbio que tambÃ©m tenha sido devolvida pela web_search. */
  fonte_cambio_url: string | null;
  /** Data de referÃªncia da taxa de cÃ¢mbio, no formato YYYY-MM-DD. */
  data_cambio: string | null;
  fator_importacao: number;
  preco_final_brl: number | null;
  regra_preco: string;
  observacao: string | null;
};

/** Conteúdo selado entre a sugestão e a confirmação de cadastro. */
export type CotacaoAssinada = {
  versao: 1;
  expira_em: number;
  tenant_id: string;
  empresa_id: string;
  usuario_id: string;
  fornecedor_id: number;
  codigo: string;
  quantidade_referencia: number;
  pesquisa_preco: PesquisaPreco;
  /** Somente as fontes que fundamentam a cotação, para manter o token pequeno. */
  fontes: FonteWeb[];
};

export type FiscalValores = {
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
};

/**
 * Procedência da linha de nota fiscal de entrada que embasou a sugestão.
 *
 * Campos novos e opcionais no contrato: a tela web e o aplicativo podem
 * escrever "NCM e impostos copiados da NF 1234 de 10/03/2026 (item ABC)" sem
 * precisar de outra chamada.
 */
export type NotaFiscalReferencia = {
  nf_entrada_id: number | null;
  nf_entrada_item_id: number | null;
  numero: string | null;
  serie: string | null;
  /** AAAA-MM-DD, já recortada do timestamp da emissão. */
  data_emissao: string | null;
  emitente_nome: string | null;
  fornecedor_id: number | null;
  /** Código do produto como o emitente escreveu na nota. */
  codigo_fornecedor: string | null;
  descricao: string | null;
  item_id: number | null;
};

/**
 * De onde veio cada correspondência interna encontrada pelo agente.
 *
 * "codigo_cadastrado" é o próprio item já cadastrado com o mesmo código em
 * outro fornecedor; "codigo_nota_fiscal" é o código que entrou por nota; e
 * "descricao" é o item do mesmo tipo achado pelas palavras da descrição.
 */
export type OrigemCorrespondenciaSimilar = "codigo_cadastrado" | "codigo_nota_fiscal" | "descricao";

/**
 * Concordância de NCM entre os itens do mesmo tipo. Quando vários candidatos
 * bons usam o mesmo NCM, isso é prova — e é o que a pessoa quer copiar.
 */
export type ConsensoNcm = {
  ncm: string;
  /** Quantos itens do mesmo tipo usam esse NCM. */
  itens: number;
  /** Quantos candidatos aprovados tinham algum NCM cadastrado. */
  candidatos_com_ncm: number;
};

/** De onde vieram os valores fiscais sugeridos. */
export type OrigemDadosFiscais = "item_interno" | "nota_fiscal" | "item_interno_e_nota";

export type SimilarInterno = {
  id: number;
  codigo_interno: string;
  nome: string;
  fornecedor_id: number | null;
  grupo_id: number | null;
  finalidade: ItemFinalidade | null;
  motivo_compra_id: string | null;
  preco_unitario: number | null;
  margem_lucro_percentual: number | null;
  similaridade: number;
  justificativa: string;
  /** Campo novo: como o item foi encontrado. Sem nota, continua "descricao". */
  origem_correspondencia: OrigemCorrespondenciaSimilar;
  /** Campo novo: a nota de entrada que trouxe o mesmo código, quando houver. */
  nota_fiscal: NotaFiscalReferencia | null;
  /** Campo novo: NCM que os itens do mesmo tipo concordam em usar. */
  consenso_ncm: ConsensoNcm | null;
};

export type FiscalSugerido = FiscalValores & {
  /**
   * Item interno que embasou os dados. Passa a aceitar null porque a nota
   * fiscal pode ser a única origem, quando a linha nunca foi vinculada a item.
   */
  referencia_item_id: number | null;
  justificativa: string;
  /** Campo novo: item interno, nota fiscal ou item completado pela nota. */
  origem_dados: OrigemDadosFiscais;
  /** Campo novo: quais campos vieram da linha da nota (ex.: ["ncm","aliq_ipi"]). */
  campos_da_nota: string[];
  /** Campo novo: a nota de origem, quando algum campo veio dela. */
  nota_fiscal: NotaFiscalReferencia | null;
  /** Campo novo: frase pronta de procedência para a tela web e o aplicativo. */
  procedencia_resumo: string;
  /** Campo novo: concordância de NCM entre os itens do mesmo tipo, se houver. */
  consenso_ncm: ConsensoNcm | null;
};

type RecordValue = Record<string, unknown>;
type RespostaPrecoModelo = {
  tipo_correspondencia: TipoCorrespondenciaPreco;
  fonte: string | null;
  titulo: string | null;
  fonte_url: string | null;
  moeda: string | null;
  preco_origem: number | null;
  /** Campo bruto do agente: BRL por uma unidade da moeda de origem. */
  taxa_cambio_brl: number | null;
  /** Alias aceito apenas para sugestoes emitidas antes do contrato atual. */
  taxa_cambio_para_brl?: number | null;
  fonte_cambio_url: string | null;
  data_cambio: string | null;
  observacao: string | null;
};

type SugestaoModelo = {
  descricao_padronizada: string;
  fabricante_sugerido: string | null;
  modelo_referencia: string | null;
  unidade_medida: string | null;
  unidade_compra: string | null;
  fator_conversao_estoque: number | null;
  finalidade_sugerida: ItemFinalidade | null;
  grupo_id: number | null;
  novo_grupo: NovoGrupo | null;
  justificativa: string;
  dados_pendentes: string[];
  confianca: Confianca;
  pesquisa_preco: RespostaPrecoModelo;
};

let catalogoCache: string | null = null;

const FINALIDADES: ItemFinalidade[] = ["consumo", "materia_prima", "revenda", "imobilizado", "outros"];
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const URL_PROTOCOLS = new Set(["http:", "https:"]);
const DURACAO_COTACAO_ASSINADA_MS = 2 * 60 * 60 * 1000;
const SEPARADORES_VISUAIS_CODIGO_RE =
  /[\s\u200B-\u200D\u2060\uFEFF\u002D\u058A\u05BE\u1400\u1806\u2010-\u2015\u2212\u2E17\u2E1A\u2E3A-\u2E3B\u2E40\u2E5D\u301C\u3030\u30A0\uFE31-\uFE32\uFE58\uFE63\uFF0D]+/gu;
const CODIGO_COM_ALFANUMERICO_RE = /[\p{L}\p{N}]/u;
const STOP_WORDS = new Set([
  "A",
  "AS",
  "COM",
  "DA",
  "DAS",
  "DE",
  "DO",
  "DOS",
  "E",
  "EM",
  "NA",
  "NAS",
  "NO",
  "NOS",
  "OU",
  "PARA",
  "POR",
  "SEM",
  "UM",
  "UMA",
]);

export function asRecord(value: unknown): RecordValue | null {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as RecordValue) : null;
}

export function texto(value: unknown, max = 800): string | null {
  const normalized = String(value ?? "")
    .trim()
    .replace(/\s+/g, " ");
  return normalized ? normalized.slice(0, max) : null;
}

/**
 * Prepara o código de catálogo para comparação e gravação.
 *
 * Exemplos: " 6ES7 132-6BH01-0BA0 " -> "6ES71326BH010BA0" e
 * "W4S1-05B" -> "W4S105B". Espaços e variações Unicode de hífen são apenas
 * visuais. Caracteres técnicos, como "/", são preservados; um resultado sem
 * letras ou números continua sendo "" para que o chamador o trate como
 * código obrigatório.
 */
export function normalizarCodigo(value: unknown): string {
  const raw =
    typeof value === "string" || typeof value === "number" || typeof value === "bigint" ? String(value) : "";

  const normalized = raw
    .normalize("NFKC")
    .toUpperCase()
    .replace(SEPARADORES_VISUAIS_CODIGO_RE, "");

  return CODIGO_COM_ALFANUMERICO_RE.test(normalized) ? normalized.slice(0, 50) : "";
}

/** Indica se o valor contém ao menos uma letra ou número após a normalização. */
export function codigoNormalizadoValido(value: unknown): boolean {
  return normalizarCodigo(value).length > 0;
}

/**
 * Chave de comparação entre o código digitado e o código que o emitente
 * escreveu na nota fiscal. Parte de normalizarCodigo e ainda descarta os
 * separadores técnicos e os zeros à esquerda, porque o mesmo produto aparece
 * na nota como "000000000012240801" e no cadastro como "12240801", ou como
 * "UR-2005A-14" e "UR2005A14".
 */
export function chaveCodigoCatalogo(value: unknown): string {
  return normalizarCodigo(value)
    .replace(/[^A-Z0-9]/g, "")
    .replace(/^0+(?=.)/, "");
}

/**
 * Expressão regular (dialeto do PostgreSQL) que reencontra a chave dentro do
 * texto cru gravado na nota, tolerando zeros à esquerda e qualquer separador
 * entre os caracteres. A chave só tem letras e números, então não há
 * metacaractere para escapar.
 */
function padraoRegexChave(chave: string): string {
  return chave.split("").join("[^[:alnum:]]*");
}

/** Padrão ancorado, para comparar com o código do produto na nota. */
export function padraoCodigoNotaFiscal(chave: string): string | null {
  if (!chave) return null;
  return `^[^[:alnum:]]*0*${padraoRegexChave(chave)}[^[:alnum:]]*$`;
}

/**
 * Padrão livre, para achar o código dentro da descrição da nota. Só vale para
 * código longo: sequência curta apareceria dentro de qualquer medida.
 */
export function padraoCodigoEmDescricaoNota(chave: string): string | null {
  return chave.length >= 6 ? padraoRegexChave(chave) : null;
}

function segredoCotacaoAssinada(): string | null {
  const segredo = String(
    process.env.ITEM_CADASTRO_AGENTE_TOKEN_SECRET ??
      process.env.OPENAI_API_KEY ??
      process.env.ASSISTENTE_IA_OPENAI_API_KEY ??
      ""
  ).trim();
  return segredo || null;
}

function codificarBase64Url(value: string): string {
  return Buffer.from(value, "utf8").toString("base64url");
}

function decodificarBase64Url(value: string): string | null {
  try {
    return Buffer.from(value, "base64url").toString("utf8");
  } catch {
    return null;
  }
}

function assinarTextoCotacao(value: string, segredo: string): string {
  return createHmac("sha256", segredo).update(value).digest("base64url");
}

/**
 * Sela o resultado de preço retornado pelo servidor. A UI pode continuar
 * permitindo a revisão dos campos de cadastro, mas não consegue trocar a
 * origem, a moeda ou o valor da cotação antes de confirmar.
 */
export function criarTokenCotacaoAssinada(input: Omit<CotacaoAssinada, "versao" | "expira_em">): string | null {
  const segredo = segredoCotacaoAssinada();
  if (!segredo) return null;
  const payload: CotacaoAssinada = {
    versao: 1,
    expira_em: Date.now() + DURACAO_COTACAO_ASSINADA_MS,
    ...input,
  };
  const codificado = codificarBase64Url(JSON.stringify(payload));
  return `${codificado}.${assinarTextoCotacao(codificado, segredo)}`;
}

function fonteAssinada(value: unknown): FonteWeb | null {
  const fonte = fonteDeRegistro(value);
  return fonte ? { titulo: fonte.titulo, url: fonte.url, dominio: fonte.dominio } : null;
}

/** Verifica assinatura, prazo e formato mínimo de uma cotação emitida pelo servidor. */
export function verificarTokenCotacaoAssinada(token: unknown): CotacaoAssinada | null {
  const segredo = segredoCotacaoAssinada();
  const raw = texto(token, 50_000);
  if (!segredo || !raw) return null;
  const [codificado, assinatura, ...resto] = raw.split(".");
  if (!codificado || !assinatura || resto.length) return null;
  const assinaturaEsperada = assinarTextoCotacao(codificado, segredo);
  const assinaturaRecebidaBuffer = Buffer.from(assinatura, "utf8");
  const assinaturaEsperadaBuffer = Buffer.from(assinaturaEsperada, "utf8");
  if (
    assinaturaRecebidaBuffer.length !== assinaturaEsperadaBuffer.length ||
    !timingSafeEqual(assinaturaRecebidaBuffer, assinaturaEsperadaBuffer)
  ) {
    return null;
  }
  const textoPayload = decodificarBase64Url(codificado);
  if (!textoPayload) return null;
  let payload: RecordValue | null = null;
  try {
    payload = asRecord(JSON.parse(textoPayload));
  } catch {
    payload = null;
  }
  if (!payload || Number(payload.versao) !== 1) return null;
  const expiraEm = Number(payload.expira_em);
  const fornecedorId = inteiro(payload.fornecedor_id);
  const codigo = normalizarCodigo(payload.codigo);
  const quantidade = normalizarQuantidade(payload.quantidade_referencia);
  const tenantId = texto(payload.tenant_id, 100);
  const empresaId = texto(payload.empresa_id, 100);
  const usuarioId = texto(payload.usuario_id, 100);
  const pesquisa = pesquisaDeBody(payload.pesquisa_preco, fontesDeBody(payload.fontes));
  const fontes = Array.isArray(payload.fontes)
    ? payload.fontes.map(fonteAssinada).filter((fonte): fonte is FonteWeb => fonte !== null).slice(0, 3)
    : [];
  if (
    !Number.isFinite(expiraEm) ||
    expiraEm <= Date.now() ||
    expiraEm > Date.now() + DURACAO_COTACAO_ASSINADA_MS + 60_000 ||
    !fornecedorId ||
    !codigo ||
    quantidade === null ||
    !tenantId ||
    !empresaId ||
    !usuarioId
  ) {
    return null;
  }
  return {
    versao: 1,
    expira_em: expiraEm,
    tenant_id: tenantId,
    empresa_id: empresaId,
    usuario_id: usuarioId,
    fornecedor_id: fornecedorId,
    codigo,
    quantidade_referencia: quantidade,
    pesquisa_preco: pesquisa,
    fontes,
  };
}

export function normalizarCodigoGrupo(value: unknown): string {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 80);
}

/** Zero é um valor válido: significa "sem estoque inicial informado". */
export function normalizarQuantidade(value: unknown): number | null {
  const raw = typeof value === "number" ? String(value) : String(value ?? "").trim();
  if (!raw) return null;
  const normalized = raw.includes(",") && raw.includes(".") ? raw.replace(/\./g, "").replace(",", ".") : raw.replace(",", ".");
  const parsed = Number(normalized);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 999999999) return null;
  return Math.round(parsed * 1000) / 1000;
}

export function numero(value: unknown, min = 0, max = Number.MAX_SAFE_INTEGER): number | null {
  if (value === null || value === undefined) return null;
  const raw = typeof value === "string" ? value.trim() : String(value).trim();
  if (!raw) return null;
  const parsed = typeof value === "number" ? value : Number(raw.replace(",", "."));
  if (!Number.isFinite(parsed) || parsed < min || parsed > max) return null;
  return Math.round(parsed * 10000) / 10000;
}

export function inteiro(value: unknown): number | null {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

export function finalidade(value: unknown): ItemFinalidade | null {
  const raw = String(value ?? "").trim();
  return FINALIDADES.includes(raw as ItemFinalidade) ? (raw as ItemFinalidade) : null;
}

export function normalizarUnidade(value: unknown): string {
  const candidate = String(value ?? "")
    .trim()
    .toUpperCase()
    .replace(/\s+/g, "")
    .slice(0, 10);
  return candidate && /^[A-Z0-9%º°/.-]+$/.test(candidate) ? candidate : "UN";
}

export function caminhoGrupo(grupo: GrupoRow, gruposPorId: Map<number, GrupoRow>): string {
  const nomes: string[] = [];
  const visitados = new Set<number>();
  let atual: GrupoRow | undefined = grupo;
  while (atual && !visitados.has(atual.id)) {
    visitados.add(atual.id);
    if (atual.nome) nomes.unshift(atual.nome);
    atual = atual.grupo_pai_id ? gruposPorId.get(Number(atual.grupo_pai_id)) : undefined;
  }
  return nomes.join(" > ");
}

export async function catalogoNormalizacao(): Promise<string> {
  if (catalogoCache) return catalogoCache;
  const arquivo = path.join(process.cwd(), "docs", "padroes-cadastro", "catalogo-paineis-eletricos.yaml");
  const yaml = await readFile(arquivo, "utf8");
  const inicioHistorico = yaml.indexOf("\nhistorico_decisoes:");
  catalogoCache = inicioHistorico >= 0 ? yaml.slice(0, inicioHistorico) : yaml;
  return catalogoCache;
}

export function extrairTextoResposta(value: unknown): string {
  const body = asRecord(value);
  if (!body) return "";
  if (typeof body.output_text === "string") return body.output_text;

  const partes: string[] = [];
  for (const output of Array.isArray(body.output) ? body.output : []) {
    const outputRecord = asRecord(output);
    for (const content of Array.isArray(outputRecord?.content) ? outputRecord.content : []) {
      const contentRecord = asRecord(content);
      if (typeof contentRecord?.text === "string") partes.push(contentRecord.text);
    }
  }
  return partes.join("\n").trim();
}

function urlSegura(value: unknown): string | null {
  const raw = texto(value, 2000);
  if (!raw) return null;
  try {
    const parsed = new URL(raw);
    return URL_PROTOCOLS.has(parsed.protocol) ? parsed.toString() : null;
  } catch {
    return null;
  }
}

function chaveUrl(value: string): string {
  try {
    const parsed = new URL(value);
    parsed.hash = "";
    if (parsed.pathname !== "/") parsed.pathname = parsed.pathname.replace(/\/$/, "");
    return parsed.toString();
  } catch {
    return value;
  }
}

function fonteDeRegistro(value: unknown): FonteWeb | null {
  const source = asRecord(value);
  const url = urlSegura(source?.url);
  if (!url) return null;
  let dominio = "";
  try {
    dominio = new URL(url).hostname.replace(/^www\./i, "");
  } catch {
    return null;
  }
  return {
    titulo: texto(source?.title, 240) ?? dominio,
    url,
    dominio,
  };
}

/** Extrai somente fontes retornadas de fato pela ferramenta web_search/citações da Responses API. */
export function extrairFontesWeb(value: unknown): FonteWeb[] {
  const fontes = new Map<string, FonteWeb>();
  const adicionar = (candidate: unknown) => {
    const fonte = fonteDeRegistro(candidate);
    if (fonte) fontes.set(chaveUrl(fonte.url), fonte);
  };

  const body = asRecord(value);
  for (const output of Array.isArray(body?.output) ? body.output : []) {
    const outputRecord = asRecord(output);
    const action = asRecord(outputRecord?.action);
    for (const source of Array.isArray(action?.sources) ? action.sources : []) adicionar(source);
    for (const content of Array.isArray(outputRecord?.content) ? outputRecord.content : []) {
      const contentRecord = asRecord(content);
      for (const annotation of Array.isArray(contentRecord?.annotations) ? contentRecord.annotations : []) {
        adicionar(annotation);
      }
    }
  }
  // A Responses API pode devolver mais de vinte fontes. Manter somente as
  // primeiras faria uma URL escolhida legitimamente pelo agente parecer não
  // verificada, especialmente em buscas de marketplace com muitos anúncios.
  return [...fontes.values()].slice(0, 100);
}

function fonteCorrespondente(url: string | null, fontes: FonteWeb[]): FonteWeb | null {
  if (!url) return null;
  const key = chaveUrl(url);
  const direta = fontes.find((fonte) => chaveUrl(fonte.url) === key);
  if (direta) return direta;
  try {
    const alvo = new URL(url);
    return (
      fontes.find((fonte) => {
        try {
          const fonteUrl = new URL(fonte.url);
          return fonteUrl.hostname === alvo.hostname && fonteUrl.pathname === alvo.pathname;
        } catch {
          return false;
        }
      }) ?? null
    );
  } catch {
    return null;
  }
}

function marketplaceDaFonte(url: string | null, nome: string | null): string | null {
  const candidate = `${url ?? ""} ${nome ?? ""}`.toLowerCase();
  if (candidate.includes("ebay.")) return "eBay";
  if (candidate.includes("mercadolivre") || candidate.includes("mercadolibre")) return "Mercado Livre";
  if (candidate.includes("amazon.")) return "Amazon";
  if (candidate.includes("rs-online") || candidate.includes("radwell")) return texto(nome, 100) ?? "Loja técnica";
  return texto(nome, 100);
}

function moeda(value: unknown): string | null {
  const raw = String(value ?? "").trim().toUpperCase();
  return /^[A-Z]{3}$/.test(raw) ? raw : null;
}

/** Taxa em BRL por uma unidade da moeda de origem. */
function taxaCambioParaBrl(value: unknown): number | null {
  const parsed = typeof value === "number" ? value : Number(String(value ?? "").trim().replace(",", "."));
  if (!Number.isFinite(parsed) || parsed <= 0 || parsed > 1_000_000) return null;
  // Seis casas atendem tambem moedas cujo valor unitario e pequeno frente ao real.
  return Math.round(parsed * 1_000_000) / 1_000_000;
}

function dataCambio(value: unknown): string | null {
  const raw = texto(value, 10);
  if (!raw || !/^\d{4}-\d{2}-\d{2}$/.test(raw)) return null;
  const parsed = new Date(`${raw}T00:00:00.000Z`);
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== raw) return null;
  // Nao e seguro aplicar uma cotacao futura a um cadastro atual.
  if (raw > new Date().toISOString().slice(0, 10)) return null;
  return raw;
}

function arredondarPreco(value: number): number | null {
  if (!Number.isFinite(value) || value < 0 || value > 999_999_999) return null;
  return Math.round((value + Number.EPSILON) * 10000) / 10000;
}

function dataPtax(date: Date): string {
  const mes = String(date.getUTCMonth() + 1).padStart(2, "0");
  const dia = String(date.getUTCDate()).padStart(2, "0");
  return `${mes}-${dia}-${date.getUTCFullYear()}`;
}

function urlCotacaoPtax(moedaOrigem: string, data: Date): URL {
  const url = new URL(
    "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/CotacaoMoedaDia(moeda=@moeda,dataCotacao=@dataCotacao)"
  );
  url.searchParams.set("@moeda", `'${moedaOrigem}'`);
  url.searchParams.set("@dataCotacao", `'${dataPtax(data)}'`);
  url.searchParams.set("$format", "json");
  return url;
}

/**
 * Obtém uma taxa oficial de câmbio diretamente da PTAX do Banco Central.
 *
 * A pesquisa de preço deve continuar restrita aos marketplaces: pedir preço e
 * câmbio ao mesmo agente aumenta a chance de ele descartar um anúncio válido
 * por não ter encontrado a taxa na mesma busca. Esta consulta é independente,
 * auditável pela URL retornada e tenta dias anteriores para cobrir fins de
 * semana e feriados. Em qualquer dúvida ou indisponibilidade, retorna nulo —
 * nunca estima uma taxa.
 */
export async function buscarCotacaoCambioPtax(moedaOrigem: unknown): Promise<CotacaoCambioPtax | null> {
  const moeda = moedaOrigem instanceof String ? moedaOrigem.toString().trim().toUpperCase() : String(moedaOrigem ?? "").trim().toUpperCase();
  if (!/^[A-Z]{3}$/.test(moeda) || moeda === "BRL") return null;

  const hoje = new Date();
  for (let atraso = 0; atraso <= 7; atraso += 1) {
    const dataConsulta = new Date(hoje);
    dataConsulta.setUTCDate(dataConsulta.getUTCDate() - atraso);
    const url = urlCotacaoPtax(moeda, dataConsulta);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5_000);
    try {
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        cache: "no-store",
        signal: controller.signal,
      });
      if (!response.ok) continue;
      const body = asRecord(await response.json());
      const registros = (Array.isArray(body?.value) ? body.value : [])
        .map(asRecord)
        .filter((registro): registro is RecordValue => registro !== null)
        .filter((registro) => taxaCambioParaBrl(registro.cotacaoVenda) !== null);
      if (!registros.length) continue;

      // Preferimos o fechamento PTAX; no pregão em curso, usamos o último
      // boletim publicado pela fonte oficial em vez de inventar uma taxa.
      const candidatosFechamento = registros.filter(
        (registro) => texto(registro.tipoBoletim, 60)?.toLowerCase() === "fechamento ptax"
      );
      const candidato = (candidatosFechamento.length ? candidatosFechamento : registros)
        .slice()
        .sort((a, b) => String(a.dataHoraCotacao ?? "").localeCompare(String(b.dataHoraCotacao ?? "")))
        .at(-1);
      const taxa = taxaCambioParaBrl(candidato?.cotacaoVenda);
      const dataHora = texto(candidato?.dataHoraCotacao, 40);
      const dataCambio = dataHora?.match(/^\d{4}-\d{2}-\d{2}/)?.[0] ?? null;
      if (taxa === null || !dataCambio) continue;

      const boletim = texto(candidato?.tipoBoletim, 60) ?? "PTAX";
      return {
        moeda,
        taxa_cambio_brl: taxa,
        fonte: {
          titulo: `Banco Central do Brasil — PTAX ${moeda}/BRL (${boletim})`,
          url: url.toString(),
          dominio: "olinda.bcb.gov.br",
        },
        data_cambio: dataCambio,
      };
    } catch {
      // Uma indisponibilidade temporária da PTAX não invalida a proposta de
      // cadastro; o preço permanece pendente para validação humana.
    } finally {
      clearTimeout(timeout);
    }
  }
  return null;
}

export function calcularPesquisaPreco(input: {
  pesquisa: RespostaPrecoModelo | RecordValue | null | undefined;
  fontes: FonteWeb[];
}): PesquisaPreco {
  const pesquisa = input.pesquisa ?? {};
  const tipoRaw = String(pesquisa.tipo_correspondencia ?? "nao_encontrado");
  const tipo: TipoCorrespondenciaPreco =
    tipoRaw === "exato" || tipoRaw === "similar" || tipoRaw === "nao_encontrado" ? tipoRaw : "nao_encontrado";
  const fonteUrlSolicitada = urlSegura(pesquisa.fonte_url);
  const fonte = fonteCorrespondente(fonteUrlSolicitada, input.fontes);
  const precoOrigem = numero(pesquisa.preco_origem, 0.0001, 999999999);
  const moedaOrigem = moeda(pesquisa.moeda);
  const nomeFonte = texto(pesquisa.fonte, 100);
  const titulo = fonte?.titulo ?? texto(pesquisa.titulo, 240);
  const url = fonte?.url ?? null;
  const marketplace = marketplaceDaFonte(url, nomeFonte ?? fonte?.dominio ?? null);
  // `taxa_cambio_brl` e o contrato do agente. Aceitamos o nome normalizado
  // apenas para confirmaÃ§Ãµes de sugestÃµes geradas por versÃµes anteriores.
  const taxaCambio = taxaCambioParaBrl(pesquisa.taxa_cambio_brl ?? pesquisa.taxa_cambio_para_brl);
  const fonteCambioSolicitada = urlSegura(pesquisa.fonte_cambio_url);
  const fonteCambio = fonteCorrespondente(fonteCambioSolicitada, input.fontes);
  const dataTaxaCambio = dataCambio(pesquisa.data_cambio);
  const fonteCambioDiferenteDaFontePreco =
    fonte !== null && fonteCambio !== null && chaveUrl(fonte.url) !== chaveUrl(fonteCambio.url);
  const cambioVerificado =
    moedaOrigem !== null &&
    moedaOrigem !== "BRL" &&
    taxaCambio !== null &&
    fonteCambio !== null &&
    fonteCambioDiferenteDaFontePreco &&
    dataTaxaCambio !== null;
  const dadosCambio = cambioVerificado && taxaCambio !== null && fonteCambio !== null && dataTaxaCambio !== null
    ? {
        taxa_cambio_para_brl: taxaCambio,
        fonte_cambio_url: fonteCambio.url,
        data_cambio: dataTaxaCambio,
      }
    : {
        taxa_cambio_para_brl: null,
        fonte_cambio_url: null,
        data_cambio: null,
      };

  if (!fonte || precoOrigem === null || !moedaOrigem || tipo === "nao_encontrado") {
    return {
      status: "pendente",
      tipo_correspondencia: tipo,
      marketplace,
      fonte: nomeFonte ?? fonte?.dominio ?? null,
      fonte_url: url,
      titulo,
      moeda: moedaOrigem,
      preco_origem: null,
      ...dadosCambio,
      fator_importacao: 1,
      preco_final_brl: null,
      regra_preco: "Sem preço verificável em fonte retornada pela pesquisa; revisar antes de definir preço.",
      observacao:
        texto(pesquisa.observacao, 500) ??
        "A pesquisa não encontrou uma referência de preço verificável para este cadastro.",
    };
  }

  if (moedaOrigem !== "BRL") {
    if (cambioVerificado && taxaCambio !== null && fonteCambio !== null && dataTaxaCambio !== null) {
      const fatorImportacao = marketplace === "eBay" ? 1.8 : 1;
      const precoFinal = arredondarPreco(precoOrigem * taxaCambio * fatorImportacao);
      if (precoFinal !== null) {
        return {
          status: "encontrado",
          tipo_correspondencia: tipo,
          marketplace,
          fonte: nomeFonte ?? fonte.dominio,
          fonte_url: fonte.url,
          titulo,
          moeda: moedaOrigem,
          preco_origem: precoOrigem,
          ...dadosCambio,
          fator_importacao: fatorImportacao,
          preco_final_brl: precoFinal,
          regra_preco:
            marketplace === "eBay"
              ? `Pre\u00e7o em ${moedaOrigem} convertido para BRL pela taxa de ${taxaCambio.toLocaleString("pt-BR")} BRL/${moedaOrigem} em ${dataTaxaCambio}, com acr\u00e9scimo de 80% para importa\u00e7\u00e3o (fator 1,80).`
              : `Pre\u00e7o em ${moedaOrigem} convertido para BRL pela taxa de ${taxaCambio.toLocaleString("pt-BR")} BRL/${moedaOrigem} em ${dataTaxaCambio}.`,
          observacao: texto(pesquisa.observacao, 500),
        };
      }
    }
    return {
      status: "pendente",
      tipo_correspondencia: tipo,
      marketplace,
      fonte: nomeFonte ?? fonte.dominio,
      fonte_url: fonte.url,
      titulo,
      moeda: moedaOrigem,
      preco_origem: precoOrigem,
      ...dadosCambio,
      fator_importacao: 1,
      preco_final_brl: null,
      regra_preco: "Preço encontrado em moeda estrangeira. A conversão para BRL deve ser validada manualmente.",
      observacao: texto(pesquisa.observacao, 500),
    };
  }

  const fatorImportacao = marketplace === "eBay" ? 1.8 : 1;
  const precoFinal = Math.round(precoOrigem * fatorImportacao * 10000) / 10000;
  return {
    status: "encontrado",
    tipo_correspondencia: tipo,
    marketplace,
    fonte: nomeFonte ?? fonte.dominio,
    fonte_url: fonte.url,
    titulo,
    moeda: "BRL",
    preco_origem: precoOrigem,
    ...dadosCambio,
    fator_importacao: fatorImportacao,
    preco_final_brl: precoFinal,
    regra_preco:
      marketplace === "eBay"
        ? "Preço em BRL do eBay acrescido de 80% para taxas de importação (fator 1,80)."
        : "Preço em BRL da fonte pesquisada, sem acréscimo automático.",
    observacao: texto(pesquisa.observacao, 500),
  };
}

function schemaNovoGrupo() {
  return {
    anyOf: [
      { type: "null" },
      {
        type: "object",
        additionalProperties: false,
        required: ["codigo", "nome", "grupo_pai_id", "justificativa"],
        properties: {
          codigo: { type: "string" },
          nome: { type: "string" },
          grupo_pai_id: { type: ["integer", "null"] },
          justificativa: { type: "string" },
        },
      },
    ],
  };
}

export function schemaRespostaAgente() {
  return {
    type: "object",
    additionalProperties: false,
    required: [
      "descricao_padronizada",
      "fabricante_sugerido",
      "modelo_referencia",
      "unidade_medida",
      "unidade_compra",
      "fator_conversao_estoque",
      "finalidade_sugerida",
      "grupo_id",
      "novo_grupo",
      "justificativa",
      "dados_pendentes",
      "confianca",
      "pesquisa_preco",
    ],
    properties: {
      descricao_padronizada: { type: "string" },
      fabricante_sugerido: { type: ["string", "null"] },
      modelo_referencia: { type: ["string", "null"] },
      unidade_medida: { type: ["string", "null"] },
      unidade_compra: { type: ["string", "null"] },
      fator_conversao_estoque: { type: ["number", "null"] },
      finalidade_sugerida: { type: ["string", "null"], enum: [...FINALIDADES, null] },
      grupo_id: { type: ["integer", "null"] },
      novo_grupo: schemaNovoGrupo(),
      justificativa: { type: "string" },
      dados_pendentes: { type: "array", items: { type: "string" } },
      confianca: { type: "string", enum: ["alta", "media", "baixa"] },
      pesquisa_preco: {
        type: "object",
        additionalProperties: false,
        required: [
          "tipo_correspondencia",
          "fonte",
          "titulo",
          "fonte_url",
          "moeda",
          "preco_origem",
          "taxa_cambio_brl",
          "fonte_cambio_url",
          "data_cambio",
          "observacao",
        ],
        properties: {
          tipo_correspondencia: { type: "string", enum: ["exato", "similar", "nao_encontrado"] },
          fonte: { type: ["string", "null"] },
          titulo: { type: ["string", "null"] },
          fonte_url: { type: ["string", "null"] },
          moeda: { type: ["string", "null"] },
          preco_origem: { type: ["number", "null"] },
          // BRL por uma unidade da moeda de origem; nulo quando o preco ja esta em BRL ou nao foi verificado.
          taxa_cambio_brl: { type: ["number", "null"] },
          fonte_cambio_url: { type: ["string", "null"] },
          data_cambio: { type: ["string", "null"] },
          observacao: { type: ["string", "null"] },
        },
      },
    },
  };
}

export function promptSistemaAgenteCadastro(): string {
  return [
    REGRAS_SENSORES_SEGURANCA,
    "Você é o Agente de Cadastro Assistido do ERP. Gere uma proposta para revisão humana; você nunca grava dados no banco.",
    "A pessoa informa fornecedor, código e quantidade de referência para cotação. Quantidade não é estoque e não gera movimentação.",
    "Use a pesquisa web obrigatória para investigar primeiro o código exato e a marca/fabricante verificáveis. Se não houver referência exata, pesquise um item tecnicamente similar e declare tipo_correspondencia=similar. Se a pesquisa for insuficiente, use nao_encontrado e não invente preço, especificação ou fonte.",
    "A descrição padronizada precisa identificar tecnicamente o material e não deve repetir fabricante, marca nem o código de origem. Quando o código de origem for exclusivamente numérico, inclua a família e a referência alfanumérica oficial do fabricante confirmadas pela fonte; não repita o número. Nos demais casos, uma família técnica só aparece quando indispensável à compatibilidade. Não copie automaticamente a descrição encontrada.",
    "Nunca inclua no nome dados transacionais como número de pedido de compra, NF-e, OS, data da compra ou observação comercial. Esses dados permanecem nos documentos e relacionamentos próprios do ERP.",
    "Nunca invente especificações. Registre toda lacuna em dados_pendentes e reduza a confiança. Número, faixa ou razão e sua unidade devem ficar sempre juntos, sem espaço: 115A, 110-127VCA/CC, 50/60Hz, 24VCC, 6kA e 17,5mm. Para switches, a quantidade de portas é obrigatória; sem confirmação, registre a pendência e não finalize com descrição genérica.",
    "Para cabos elétricos, de controle, sinal ou sensor/atuador, a descrição só está tecnicamente completa quando a fonte confirmar e ela informar: família ou tipo, formação e seção nominal, classe de tensão, material da isolação dos condutores, material da capa externa e presença ou ausência de blindagem. Preserve a notação técnica G ou x e interprete-a corretamente: G indica condutor de proteção verde/amarelo e x indica ausência desse condutor. Não confunda isolação com capa; por exemplo, isolação PVC e capa PUR são atributos diferentes. Se qualquer dado obrigatório não for confirmado, registre-o em dados_pendentes e reduza a confiança.",
    "Para cabos sem terminação, declare UNIPOLAR para uma via ou MULTIPOLAR para duas ou mais vias quando a formação estiver confirmada. Cabo PP é uma família construtiva e não significa isolação de polipropileno; na construção convencional confirmada, descreva ISOLAÇÃO PVC e CAPA PVC. Cabos montados, cordões, chicotes ou cabos com conector, plugue, terminal ou adaptador nas pontas são outra classe de produto e não devem ser tratados como cabo nu deste padrão.",
    "Para cabos sem terminação, unidade_medida é sempre M, pois o saldo do ERP é controlado em metros. Se a fonte confirmar venda em KM, RL, BOB ou outra unidade comercial, informe unidade_compra e fator_conversao_estoque, onde 1 unidade de compra vezes o fator resulta em metros. Exemplo: 1RL de 100m usa unidade_compra=RL e fator=100. Nunca presuma o comprimento de rolo ou bobina: se não estiver confirmado, retorne fator null e registre a pendência.",
    "Escolha grupo_id somente da lista de grupos ativos enviada. Não trate como equivalentes produtos de funções distintas. Sem grupo adequado, proponha um novo grupo simples e reutilizável; ele será criado somente após aprovação humana.",
    "O ERP tem campos próprios para fornecedor, código e fabricante. fabricante_sugerido não deve ser repetido na descrição. modelo_referencia só entra na descrição na exceção aprovada para código de origem exclusivamente numérico ou quando for indispensável à compatibilidade.",
    "Pesquise preço de uma página concreta. Retorne o preço original exatamente na moeda vista, uma única URL da fonte e não faça conversão. O servidor calcula qualquer regra de importação. Não sugira NCM, IPI ou demais tributos pela internet.",
    "Se o preco estiver em moeda estrangeira, pesquise tambem uma fonte concreta de cambio. Informe taxa_cambio_brl como BRL por uma unidade da moeda de origem, fonte_cambio_url e data_cambio no formato YYYY-MM-DD. Preencha esses tres campos somente quando a fonte da taxa estiver entre os resultados da pesquisa; caso contrario, use null. Nao calcule o valor final em BRL: o servidor aplica a conversao e, quando a fonte for eBay, o fator de importacao.",
    "Retorne exclusivamente o JSON estruturado solicitado.",
  ].join(" ");
}

function sanitizarNovoGrupo(raw: unknown, gruposPorId: Map<number, GrupoRow>): NovoGrupo | null {
  const grupo = asRecord(raw);
  const codigo = normalizarCodigoGrupo(grupo?.codigo);
  const nome = texto(grupo?.nome, 120);
  if (!codigo || !nome) return null;
  const paiId = grupo?.grupo_pai_id == null ? null : inteiro(grupo.grupo_pai_id);
  const pai = paiId ? gruposPorId.get(paiId) : null;
  return {
    codigo,
    nome,
    grupo_pai_id: pai?.id ?? null,
    justificativa: texto(grupo?.justificativa, 500) ?? "Grupo sugerido pelo agente para esta função técnica.",
  };
}

export function sanitizarSugestaoModelo(input: {
  resposta: unknown;
  codigo: string;
  gruposPorId: Map<number, GrupoRow>;
  fontes: FonteWeb[];
}): SugestaoModelo {
  const raw = asRecord(input.resposta);
  const grupoId = raw?.grupo_id == null ? null : inteiro(raw.grupo_id);
  const grupo = grupoId ? input.gruposPorId.get(grupoId) : null;
  const novoGrupo = grupo ? null : sanitizarNovoGrupo(raw?.novo_grupo, input.gruposPorId);
  const pesquisa = asRecord(raw?.pesquisa_preco);
  const confiancaRaw = String(raw?.confianca ?? "baixa");
  const confianca: Confianca =
    confiancaRaw === "alta" || confiancaRaw === "media" || confiancaRaw === "baixa" ? confiancaRaw : "baixa";
  const dadosPendentes = Array.isArray(raw?.dados_pendentes)
    ? raw.dados_pendentes.map((value) => texto(value, 180)).filter((value): value is string => Boolean(value)).slice(0, 20)
    : [];
  const descricao = normalizarNomeCadastro(texto(raw?.descricao_padronizada, 255) ?? "");
  const pendenciasTecnicas = pendenciasDescricaoTecnica({ descricao, codigo: input.codigo, modeloReferencia: texto(raw?.modelo_referencia, 150), grupoCodigo: grupo?.codigo });
  dadosPendentes.push(...pendenciasTecnicas);
  const codigoAlfanumerico = input.codigo.replace(/[^A-Z0-9]/g, "");
  if (codigoAlfanumerico.length >= 5 && descricao.toUpperCase().replace(/[^A-Z0-9]/g, "").includes(codigoAlfanumerico)) {
    dadosPendentes.push("A descrição sugerida ainda contém o código do produto; remova-o antes de confirmar o cadastro.");
  }
  return {
    descricao_padronizada: descricao,
    fabricante_sugerido: texto(raw?.fabricante_sugerido, 150),
    modelo_referencia: texto(raw?.modelo_referencia, 150),
    unidade_medida: texto(raw?.unidade_medida, 10),
    unidade_compra: texto(raw?.unidade_compra, 10),
    fator_conversao_estoque: numero(raw?.fator_conversao_estoque, 0.000001, 999999999),
    finalidade_sugerida: finalidade(raw?.finalidade_sugerida),
    grupo_id: grupo?.id ?? null,
    novo_grupo: novoGrupo,
    justificativa: texto(raw?.justificativa, 600) ?? "Revise a classificação e as fontes antes de confirmar.",
    dados_pendentes: dadosPendentes,
    confianca: pendenciasTecnicas.length ? "baixa" : confianca,
    pesquisa_preco: {
      tipo_correspondencia:
        pesquisa?.tipo_correspondencia === "exato" || pesquisa?.tipo_correspondencia === "similar"
          ? pesquisa.tipo_correspondencia
          : "nao_encontrado",
      fonte: texto(pesquisa?.fonte, 100),
      titulo: texto(pesquisa?.titulo, 240),
      fonte_url: urlSegura(pesquisa?.fonte_url),
      moeda: moeda(pesquisa?.moeda),
      preco_origem: numero(pesquisa?.preco_origem, 0.0001, 999999999),
      taxa_cambio_brl: taxaCambioParaBrl(pesquisa?.taxa_cambio_brl ?? pesquisa?.taxa_cambio_para_brl),
      fonte_cambio_url: urlSegura(pesquisa?.fonte_cambio_url),
      data_cambio: dataCambio(pesquisa?.data_cambio),
      observacao: texto(pesquisa?.observacao, 500),
    },
  };
}

function tokens(value: unknown): string[] {
  const normalized = String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, " ");
  return [...new Set(normalized.split(" ").filter((token) => token.length >= 2 && !STOP_WORDS.has(token)))];
}

type SimilarRow = {
  id: number;
  codigo_interno: string | null;
  nome: string | null;
  descricao: string | null;
  fornecedor_id: number | null;
  grupo_id: number | null;
  finalidade: ItemFinalidade | null;
  motivo_compra_id: string | null;
  preco_unitario: number | null;
  margem_lucro_percentual: number | null;
};

/**
 * Palavras que valem a pena levar ao SQL para reduzir o catálogo antes de
 * pontuar. A descrição padronizada do ERP começa pelo tipo do produto
 * ("CLP ...", "DISJUNTOR MINI ..."), então a ordem de aparição já é a ordem de
 * importância. Ficam de fora medidas e referências curtas como "2P", "40" e
 * "1211C", que são específicas demais do item e atrapalham a busca por tipo.
 */
export function tokensFortesDescricao(descricao: unknown, max = 3): string[] {
  const fortes = tokens(descricao).filter(
    (token) => token.length >= 3 && (token.match(/[A-Z]/g) ?? []).length >= 2
  );
  return fortes.slice(0, Math.max(0, max));
}

type EntradaSelecaoSimilar = {
  descricao: string;
  grupoId: number | null;
  fornecedorId: number;
  candidatos: SimilarRow[];
  /** Fabricante proposto pelo agente; item de automação repete o nome da família. */
  fabricante?: string | null;
  /** Ids de itens que já entraram por nota fiscal de entrada. */
  itensComNota?: ReadonlySet<number>;
  /** NCM já cadastrado de cada candidato, para reforço e para o consenso. */
  ncmPorItem?: ReadonlyMap<number, string>;
};

type CandidatoPontuado = {
  row: SimilarRow;
  base: number;
  total: number;
  compartilhados: string[];
  reforcos: string[];
};

/**
 * Pontua os candidatos do mesmo tipo de produto.
 *
 * A regra original — cobertura de palavras, mesmo grupo e mesmo fornecedor —
 * continua sendo a única que decide se um candidato é aceitável. Os critérios
 * novos (fabricante em comum, item que já entrou por nota fiscal, item com NCM
 * cadastrado e NCM concordante com os demais do mesmo tipo) só desempatam
 * entre os candidatos que já passariam antes, para que a mudança nunca aprove
 * um similar que a regra anterior recusava.
 *
 * O mesmo fornecedor continua valendo ponto, mas deixou de ser condição: um
 * CLP Omron novo precisa poder copiar o NCM de um CLP Siemens.
 */
function pontuarCandidatos(input: EntradaSelecaoSimilar): {
  aprovados: CandidatoPontuado[];
  doMesmoTipo: CandidatoPontuado[];
  consenso: ConsensoNcm | null;
} {
  const alvo = tokens(input.descricao);
  if (alvo.length === 0) return { aprovados: [], doMesmoTipo: [], consenso: null };
  const tokensFabricante = new Set(tokens(input.fabricante));
  // Palavra que nomeia o tipo do produto ("CLP", "DISJUNTOR"): a descrição
  // padronizada do ERP começa por ela.
  const familia = tokensFortesDescricao(input.descricao, 1)[0] ?? null;

  const aprovados: CandidatoPontuado[] = [];
  const doMesmoTipo: CandidatoPontuado[] = [];
  for (const row of input.candidatos) {
    const palavras = new Set(tokens(`${row.nome ?? ""} ${row.descricao ?? ""}`));
    const compartilhados = alvo.filter((token) => palavras.has(token));
    if (compartilhados.length === 0) continue;
    const cobertura = compartilhados.length / alvo.length;
    const mesmaFuncao = input.grupoId !== null && Number(row.grupo_id) === input.grupoId;
    const mesmoFornecedor = Number(row.fornecedor_id) === input.fornecedorId;
    const base = cobertura * 0.7 + (mesmaFuncao ? 0.18 : 0) + (mesmoFornecedor ? 0.12 : 0);

    const id = Number(row.id);
    const mesmoFabricante = [...tokensFabricante].some((token) => palavras.has(token));
    const entrouPorNota = Boolean(input.itensComNota?.has(id));
    const temNcm = Boolean(input.ncmPorItem?.get(id));
    const reforcos: string[] = [];
    if (mesmoFabricante) reforcos.push("mesmo fabricante");
    if (entrouPorNota) reforcos.push("já entrou por nota fiscal");
    if (temNcm) reforcos.push("já tem NCM cadastrado");
    const total = base + (mesmoFabricante ? 0.08 : 0) + (entrouPorNota ? 0.06 : 0) + (temNcm ? 0.06 : 0);
    const pontuado = { row, base, total, compartilhados, reforcos };

    // Duas réguas com finalidades diferentes. A antiga (0,42) segue decidindo o
    // similar comercial, que leva preço e margem para o cadastro novo — errar
    // ali custa caro. Para o NCM basta ser do mesmo tipo de produto, porque a
    // prova não é um item só: é a concordância entre vários.
    if (base >= 0.42) aprovados.push(pontuado);
    if (mesmaFuncao || (familia !== null && palavras.has(familia))) doMesmoTipo.push(pontuado);
  }

  // Consenso: o NCM mais repetido entre os itens do mesmo tipo. Só conta como
  // prova a partir de dois itens concordando.
  const porNcm = new Map<string, number>();
  const vistos = new Set<number>();
  let comNcm = 0;
  for (const candidato of [...aprovados, ...doMesmoTipo]) {
    const id = Number(candidato.row.id);
    if (vistos.has(id)) continue;
    vistos.add(id);
    const ncm = input.ncmPorItem?.get(id);
    if (!ncm) continue;
    comNcm += 1;
    porNcm.set(ncm, (porNcm.get(ncm) ?? 0) + 1);
  }
  let consenso: ConsensoNcm | null = null;
  for (const [ncm, itens] of porNcm) {
    if (itens >= 2 && (!consenso || itens > consenso.itens)) {
      consenso = { ncm, itens, candidatos_com_ncm: comNcm };
    }
  }

  // Concordar com o NCM do tipo é o que a pessoa quer copiar: vale o maior peso
  // entre os reforços, ainda sem poder aprovar quem a regra base recusou.
  if (consenso) {
    for (const candidato of new Set([...aprovados, ...doMesmoTipo])) {
      if (input.ncmPorItem?.get(Number(candidato.row.id)) === consenso.ncm) {
        candidato.total += 0.1;
        candidato.reforcos.push(`NCM ${consenso.ncm} usado por ${consenso.itens} itens do mesmo tipo`);
      }
    }
  }

  aprovados.sort((a, b) => b.total - a.total);
  doMesmoTipo.sort((a, b) => b.total - a.total);
  return { aprovados, doMesmoTipo, consenso };
}

function similarPontuado(melhor: CandidatoPontuado, consenso: ConsensoNcm | null): SimilarInterno {
  const similaridade = Math.round(melhor.base * 100);
  const reforco = melhor.reforcos.length > 0 ? ` Reforçado por: ${melhor.reforcos.join(", ")}.` : "";
  return {
    id: Number(melhor.row.id),
    codigo_interno: String(melhor.row.codigo_interno ?? ""),
    nome: String(melhor.row.nome ?? ""),
    fornecedor_id: melhor.row.fornecedor_id == null ? null : Number(melhor.row.fornecedor_id),
    grupo_id: melhor.row.grupo_id == null ? null : Number(melhor.row.grupo_id),
    finalidade: finalidade(melhor.row.finalidade),
    motivo_compra_id: texto(melhor.row.motivo_compra_id, 80),
    preco_unitario: numero(melhor.row.preco_unitario, 0, 999999999),
    margem_lucro_percentual: numero(melhor.row.margem_lucro_percentual, 0, 100),
    similaridade,
    justificativa: `Item interno do mesmo tipo, com termos em comum: ${melhor.compartilhados.slice(0, 6).join(", ")}. Similaridade ${similaridade}%.${reforco}`,
    origem_correspondencia: "descricao",
    nota_fiscal: null,
    consenso_ncm: consenso,
  };
}

/**
 * Item do mesmo tipo, o NCM em que esses itens concordam e, quando nenhum
 * candidato é bom o bastante para virar similar comercial, o item que sustenta
 * esse NCM — porque copiar o NCM é o que a pessoa precisa ao recadastrar.
 */
export function selecionarSimilarComConsenso(input: EntradaSelecaoSimilar): {
  similar: SimilarInterno | null;
  consenso: ConsensoNcm | null;
  referenciaNcm: { id: number; codigo_interno: string } | null;
} {
  const { aprovados, doMesmoTipo, consenso } = pontuarCandidatos(input);
  const similar = aprovados[0] ? similarPontuado(aprovados[0], consenso) : null;
  const sustenta = consenso
    ? [...aprovados, ...doMesmoTipo].find((c) => input.ncmPorItem?.get(Number(c.row.id)) === consenso.ncm) ?? null
    : null;
  return {
    similar,
    consenso,
    referenciaNcm: sustenta
      ? { id: Number(sustenta.row.id), codigo_interno: String(sustenta.row.codigo_interno ?? "") }
      : null,
  };
}

/** Compatibilidade: só o item do mesmo tipo, sem o consenso de NCM. */
export function selecionarSimilar(input: EntradaSelecaoSimilar): SimilarInterno | null {
  return selecionarSimilarComConsenso(input).similar;
}

/**
 * Item interno que é o próprio produto: mesmo código já cadastrado em outro
 * fornecedor, ou mesmo código já recebido por nota de entrada.
 *
 * É a correspondência mais forte que o agente consegue — o NCM e os impostos
 * daquele cadastro são os do produto, não uma aproximação por palavras.
 */
export function similarDoMesmoCodigo(
  row: SimilarRow,
  input: { origem: OrigemCorrespondenciaSimilar; nota?: NotaFiscalReferencia | null; fornecedorNome?: string | null }
): SimilarInterno {
  const nota = input.nota ?? null;
  const itemNaNota = nota?.codigo_fornecedor ? ` (item ${nota.codigo_fornecedor})` : "";
  const motivo =
    input.origem === "codigo_cadastrado"
      ? `Mesmo código já cadastrado${input.fornecedorNome ? ` no fornecedor ${input.fornecedorNome}` : " em outro fornecedor"}`
      : nota
        ? `Mesmo código do fabricante já recebido na ${identificacaoNota(nota)}${itemNaNota}`
        : "Mesmo código do fabricante já recebido por nota de entrada";
  return {
    id: Number(row.id),
    codigo_interno: String(row.codigo_interno ?? ""),
    nome: String(row.nome ?? ""),
    fornecedor_id: row.fornecedor_id == null ? null : Number(row.fornecedor_id),
    grupo_id: row.grupo_id == null ? null : Number(row.grupo_id),
    finalidade: finalidade(row.finalidade),
    motivo_compra_id: texto(row.motivo_compra_id, 80),
    preco_unitario: numero(row.preco_unitario, 0, 999999999),
    margem_lucro_percentual: numero(row.margem_lucro_percentual, 0, 100),
    similaridade: 100,
    justificativa: `${motivo.replace(/\.+$/, "")}.`,
    origem_correspondencia: input.origem,
    nota_fiscal: nota,
    consenso_ncm: null,
  };
}

/** Compatibilidade com a assinatura anterior, só para a origem de nota. */
export function similarDoCodigoDaNota(row: SimilarRow, nota: NotaFiscalReferencia): SimilarInterno {
  return similarDoMesmoCodigo(row, { origem: "codigo_nota_fiscal", nota });
}

export function sanitizarFiscal(value: unknown): FiscalValores | null {
  const raw = asRecord(value);
  if (!raw) return null;
  const onlyDigits = (candidate: unknown, max: number) => {
    const normalized = String(candidate ?? "").replace(/\D/g, "").slice(0, max);
    return normalized || null;
  };
  const optionalCode = (candidate: unknown, max: number) => texto(candidate, max)?.toUpperCase() ?? null;
  const fiscal: FiscalValores = {
    ncm: onlyDigits(raw.ncm, 12),
    cest: onlyDigits(raw.cest, 12),
    // O padrão inicial não pode sobrescrever uma escolha humana na confirmação.
    origem: origemFiscalConfirmada(raw.origem),
    cfop_padrao: onlyDigits(raw.cfop_padrao, 10),
    cst_icms: optionalCode(raw.cst_icms, 5),
    cst_pis: optionalCode(raw.cst_pis, 5),
    cst_cofins: optionalCode(raw.cst_cofins, 5),
    aliq_icms: numero(raw.aliq_icms, 0, 100),
    aliq_ipi: numero(raw.aliq_ipi, 0, 100),
    aliq_pis: numero(raw.aliq_pis, 0, 100),
    aliq_cofins: numero(raw.aliq_cofins, 0, 100),
    credita_icms: Boolean(raw.credita_icms),
    ipi_entra_no_custo: raw.ipi_entra_no_custo !== false,
    credita_pis: Boolean(raw.credita_pis),
    credita_cofins: Boolean(raw.credita_cofins),
  };
  if (!fiscal.cst_icms) fiscal.credita_icms = false;
  if (!fiscal.cst_pis) fiscal.credita_pis = false;
  if (!fiscal.cst_cofins) fiscal.credita_cofins = false;
  const hasValue = Object.entries(fiscal).some(([key, candidate]) =>
    ["credita_icms", "ipi_entra_no_custo", "credita_pis", "credita_cofins"].includes(key)
      ? false
      : key === "origem" ? raw.origem != null && candidate !== null : candidate !== null
  );
  return hasValue ? fiscal : null;
}

/** Campos de fiscal_itens que a linha da nota fiscal de entrada consegue preencher. */
const CAMPOS_FISCAIS_DA_NOTA = [
  "ncm",
  "cfop_padrao",
  "aliq_icms",
  "aliq_ipi",
  "aliq_pis",
  "aliq_cofins",
] as const satisfies readonly (keyof FiscalValores)[];

/** Nome de tela de cada campo, para a frase de procedência ficar legível. */
const ROTULO_CAMPO_FISCAL: Record<string, string> = {
  ncm: "NCM",
  cfop_padrao: "CFOP padrão",
  aliq_icms: "ICMS",
  aliq_ipi: "IPI",
  aliq_pis: "PIS",
  aliq_cofins: "COFINS",
};

/** Recorta AAAA-MM-DD de um timestamp, sem depender do fuso do servidor. */
export function dataEmissaoNota(value: unknown): string | null {
  const bruto = texto(value, 40);
  if (!bruto) return null;
  const match = bruto.match(/^(\d{4})-(\d{2})-(\d{2})/);
  return match ? `${match[1]}-${match[2]}-${match[3]}` : null;
}

function dataBrasileira(value: string | null): string | null {
  if (!value) return null;
  const [ano, mes, dia] = value.split("-");
  return ano && mes && dia ? `${dia}/${mes}/${ano}` : null;
}

function identificacaoNota(nota: NotaFiscalReferencia): string {
  const numero = nota.numero ? `NF ${nota.numero}` : "nota de entrada";
  const serie = nota.serie ? ` série ${nota.serie}` : "";
  const data = dataBrasileira(nota.data_emissao);
  return `${numero}${serie}${data ? ` de ${data}` : ""}${nota.emitente_nome ? `, de ${nota.emitente_nome}` : ""}`;
}

export function notaFiscalReferencia(input: {
  nfEntradaId: unknown;
  nfEntradaItemId: unknown;
  numero: unknown;
  serie: unknown;
  dataEmissao: unknown;
  emitenteNome: unknown;
  fornecedorId: unknown;
  codigoFornecedor: unknown;
  descricao: unknown;
  itemId: unknown;
}): NotaFiscalReferencia {
  return {
    nf_entrada_id: inteiro(input.nfEntradaId),
    nf_entrada_item_id: inteiro(input.nfEntradaItemId),
    numero: texto(input.numero, 60),
    serie: texto(input.serie, 20),
    data_emissao: dataEmissaoNota(input.dataEmissao),
    emitente_nome: texto(input.emitenteNome, 160),
    fornecedor_id: inteiro(input.fornecedorId),
    codigo_fornecedor: texto(input.codigoFornecedor, 60),
    descricao: texto(input.descricao, 240),
    item_id: inteiro(input.itemId),
  };
}

/**
 * Traduz a linha da nota de entrada para o formato de fiscal_itens. O CFOP da
 * nota é o da operação do emitente e vira apenas sugestão de cfop_padrao, que
 * a pessoa confere na tela antes de confirmar.
 */
export function fiscalDaLinhaDeNota(linha: {
  ncm?: unknown;
  cfop?: unknown;
  aliq_icms?: unknown;
  aliq_ipi?: unknown;
  aliq_pis?: unknown;
  aliq_cofins?: unknown;
}): Record<string, unknown> {
  return {
    ncm: linha.ncm,
    cfop_padrao: linha.cfop,
    aliq_icms: linha.aliq_icms,
    aliq_ipi: linha.aliq_ipi,
    aliq_pis: linha.aliq_pis,
    aliq_cofins: linha.aliq_cofins,
  };
}

/**
 * Monta a sugestão fiscal a partir do item interno e, quando o mesmo código já
 * entrou por nota fiscal, completa o que faltar com a linha dessa nota.
 *
 * O item interno continua tendo precedência campo a campo: a nota só preenche
 * o que fiscal_itens não tem. A procedência sai junto, em campos novos, para a
 * tela web e o aplicativo mostrarem de onde cada valor veio.
 */
export function fiscalDeItemENota(input: {
  fiscalItem: unknown;
  referenciaItemId: number | null;
  referenciaItemCodigo?: string | null;
  linhaNota?: unknown;
  nota?: NotaFiscalReferencia | null;
  /** Concordância de NCM entre os itens do mesmo tipo, quando houver. */
  consensoNcm?: ConsensoNcm | null;
  /**
   * Nenhum candidato chegou a similar comercial: só o NCM do consenso foi
   * aproveitado. A frase muda para deixar isso explícito na tela.
   */
  apenasNcmDoConsenso?: boolean;
}): FiscalSugerido | null {
  const doItem = sanitizarFiscal(input.fiscalItem);
  const daNota = input.nota ? sanitizarFiscal(input.linhaNota) : null;
  const base: FiscalValores | null = doItem ?? (daNota ? { ...daNota } : null);
  if (!base) return null;

  const camposDaNota: string[] = [];
  const fiscal: FiscalValores = { ...base };
  if (daNota && doItem) {
    for (const campo of CAMPOS_FISCAIS_DA_NOTA) {
      if (fiscal[campo] === null && daNota[campo] !== null) {
        // O cast é necessário porque o campo percorrido é uma união de chaves.
        (fiscal as Record<string, unknown>)[campo] = daNota[campo];
        camposDaNota.push(campo);
      }
    }
  } else if (daNota && !doItem) {
    for (const campo of CAMPOS_FISCAIS_DA_NOTA) {
      if (daNota[campo] !== null) camposDaNota.push(campo);
    }
  }

  const origemDados: OrigemDadosFiscais = !doItem
    ? "nota_fiscal"
    : camposDaNota.length > 0
      ? "item_interno_e_nota"
      : "item_interno";
  const notaUsada = camposDaNota.length > 0 ? input.nota ?? null : null;
  const itemDescrito = input.referenciaItemCodigo ?? (input.referenciaItemId ? `#${input.referenciaItemId}` : null);
  const itemNaNota = notaUsada?.codigo_fornecedor ? ` (item ${notaUsada.codigo_fornecedor})` : "";

  // Nome de emitente costuma terminar em "Ltda."; sem isso a frase fica com ponto duplo.
  const encerrar = (frase: string) => `${frase.replace(/\.+$/, "")}.`;
  const procedencia = encerrar(
    origemDados === "nota_fiscal" && notaUsada
      ? `NCM e impostos copiados da ${identificacaoNota(notaUsada)}${itemNaNota}`
      : origemDados === "item_interno_e_nota" && notaUsada
        ? `Dados fiscais do item interno ${itemDescrito ?? "de referência"}, completados (${camposDaNota.map((campo) => ROTULO_CAMPO_FISCAL[campo] ?? campo).join(", ")}) pela ${identificacaoNota(notaUsada)}${itemNaNota}`
        : `Dados fiscais copiados do item interno ${itemDescrito ?? "de referência"}`
  );

  // O consenso só é anunciado quando confirma o NCM que está sendo sugerido;
  // nenhum NCM é inventado a partir dele.
  const consenso = input.consensoNcm ?? null;
  const consensoConfirma = Boolean(consenso && fiscal.ncm && consenso.ncm === fiscal.ncm);
  const resumo =
    consensoConfirma && consenso && input.apenasNcmDoConsenso
      ? encerrar(
          `NCM ${consenso.ncm} copiado da concordância de ${consenso.itens} itens do mesmo tipo${itemDescrito ? `, entre eles ${itemDescrito}` : ""}`
        )
      : consensoConfirma && consenso
        ? `${procedencia} ${consenso.itens} itens do mesmo tipo usam este NCM (${consenso.ncm}).`
        : procedencia;

  return {
    ...fiscal,
    // Sugestão começa nacional; confirmação pode escolher outra origem.
    origem: 0,
    referencia_item_id: input.referenciaItemId,
    justificativa: `${resumo} Validar antes da confirmação.`,
    origem_dados: origemDados,
    campos_da_nota: camposDaNota,
    nota_fiscal: notaUsada,
    procedencia_resumo: resumo,
    consenso_ncm: consensoConfirma ? consenso : null,
  };
}

/** Compatibilidade: sugestão fiscal vinda somente de um item interno. */
export function fiscalComReferencia(value: unknown, referenciaItemId: number | null): FiscalSugerido | null {
  if (!referenciaItemId) return null;
  return fiscalDeItemENota({ fiscalItem: value, referenciaItemId });
}

export function uuidOuNulo(value: unknown): string | null {
  const candidate = String(value ?? "").trim();
  return UUID_RE.test(candidate) ? candidate : null;
}

export function normalizarNome(value: unknown): string | null {
  const candidate = texto(value, 255);
  return candidate ? normalizarNomeCadastro(candidate.toUpperCase()) : null;
}

export function usuarioIdentificador(user: { id?: string | null; email?: string | null }): string {
  return texto(user.email, 100) ?? texto(user.id, 100) ?? "usuario-autenticado";
}

export function eCodigoComProdutoNaDescricao(codigo: string, descricao: string): boolean {
  const codigoAlfanumerico = normalizarCodigo(codigo).replace(/[^A-Z0-9]/g, "");
  if (codigoAlfanumerico.length < 5) return false;
  const descricaoAlfanumerica = String(descricao ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  return descricaoAlfanumerica.includes(codigoAlfanumerico);
}

export function pesquisaDeBody(value: unknown, fontes: FonteWeb[]): PesquisaPreco {
  const raw = asRecord(value);
  const calculada = calcularPesquisaPreco({
    pesquisa: {
      tipo_correspondencia:
        raw?.tipo_correspondencia === "exato" || raw?.tipo_correspondencia === "similar"
          ? raw.tipo_correspondencia
          : "nao_encontrado",
      fonte: texto(raw?.fonte, 100),
      titulo: texto(raw?.titulo, 240),
      fonte_url: urlSegura(raw?.fonte_url),
      moeda: moeda(raw?.moeda),
      preco_origem: numero(raw?.preco_origem, 0.0001, 999999999),
      taxa_cambio_brl: taxaCambioParaBrl(raw?.taxa_cambio_brl ?? raw?.taxa_cambio_para_brl),
      fonte_cambio_url: urlSegura(raw?.fonte_cambio_url),
      data_cambio: dataCambio(raw?.data_cambio),
      observacao: texto(raw?.observacao, 500),
    },
    fontes,
  });
  const precoRevisado = numero(raw?.preco_final_brl, 0.0001, 999999999);
  // O valor final e sempre calculado no servidor a partir das fontes validadas.
  // Esta ramificacao preserva somente respostas antigas que ja enviavam o mesmo valor.
  if (calculada.status === "encontrado" && precoRevisado !== null && precoRevisado === calculada.preco_final_brl) {
    return {
      ...calculada,
      preco_final_brl: precoRevisado,
      regra_preco: `${calculada.regra_preco} PREÇO_REVISADO_MANUALMENTE na confirmação humana.`,
      observacao: [calculada.observacao, "Preço final revisado manualmente pela pessoa usuária."].filter(Boolean).join(" "),
    };
  }
  return calculada;
}

export function fontesDeBody(value: unknown): FonteWeb[] {
  const values = Array.isArray(value) ? value : [];
  const fontes = new Map<string, FonteWeb>();
  for (const candidate of values) {
    const fonte = fonteDeRegistro(candidate);
    if (fonte) fontes.set(chaveUrl(fonte.url), fonte);
  }
  return [...fontes.values()].slice(0, 20);
}

export function grupoParaResposta(grupoId: number | null, gruposPorId: Map<number, GrupoRow>) {
  const grupo = grupoId ? gruposPorId.get(grupoId) : null;
  return {
    grupo_id: grupo?.id ?? null,
    grupo_nome: grupo?.nome ?? null,
    grupo_caminho: grupo ? caminhoGrupo(grupo, gruposPorId) : null,
  };
}

export function parseRespostaJson(responseText: string): RecordValue | null {
  try {
    return asRecord(JSON.parse(responseText));
  } catch {
    return null;
  }
}
