const VALOR_MEDIDA_RE = "\\d+(?:[.,]\\d+)?(?:[-–—/]\\d+(?:[.,]\\d+)?)*";
const UNIDADES_COMPACTAS_SEGURAS_RE = new RegExp(
  [
    `(${VALOR_MEDIDA_RE})`,
    "[\\s\\u00A0]+",
    "(VCA/CC|VAC/DC|VCA|VCC|VAC|VDC|GHZ|MHZ|KHZ|HZ|MVA|KVA|VA|MW|KW|W|HP|CV|KV|MV|KA|[µμ]A|",
    "MM²|MM2|MM³|MM3|MM|CM²|CM2|CM³|CM3|CM|KM|M²|M³|",
    "KG|MG|G|ML|RPM|PPR|GBPS|MBPS|KBPS|BPS|MPA|KPA|PA|BAR|PSI|N·M|NM|",
    "MS|MIN|DI|DO|AI|AO|%|°C|ºC)",
    "(?=$|[\\s,;:.)\\]}/+×x])",
  ].join(""),
  "giu"
);
const AMPERE_COM_ESPACO_RE = new RegExp(`(${VALOR_MEDIDA_RE})[\\s\\u00A0]+(A)(?=$|[\\s,;:.)\\]}/+×x-])`, "giu");
const MILIAMPERE_COM_ESPACO_RE = new RegExp(`(${VALOR_MEDIDA_RE})[\\s\\u00A0]+(MA)(?=$|[\\s,;:.)\\]}/+×x-])`, "giu");
const VOLT_COM_ESPACO_RE = new RegExp(`(${VALOR_MEDIDA_RE})[\\s\\u00A0]+(V)(?=$|[\\s,;:.)\\]}/+×x-])`, "giu");
const METRO_COM_ESPACO_RE = new RegExp(`(${VALOR_MEDIDA_RE})[\\s\\u00A0]+(M)(?=$|[\\s,;:.)\\]}/+×x-])`, "giu");
const LITRO_COM_ESPACO_RE = new RegExp(`(${VALOR_MEDIDA_RE})[\\s\\u00A0]+(L)(?=$|[\\s,;:.)\\]}/+×x-])`, "giu");
const TEMPO_COM_ESPACO_RE = new RegExp(`(${VALOR_MEDIDA_RE})[\\s\\u00A0]+([SH])(?=$|[\\s,;:.)\\]}/+×x-])`, "giu");

/**
 * Aplica a regra aprovada D-027: valores, faixas e razões numéricas ficam
 * colados à unidade técnica. A lista fechada e as exceções de contexto
 * evitam alterar preposições, designações de rosca e referências de produto.
 */
export function normalizarUnidadesNoNome(value: unknown): string {
  let normalized = String(value ?? "").replace(UNIDADES_COMPACTAS_SEGURAS_RE, "$1$2");

  normalized = normalized.replace(AMPERE_COM_ESPACO_RE, (match, numero: string, unidade: string, offset: number, source: string) => {
    const antes = source.slice(Math.max(0, offset - 120), offset).toUpperCase();
    const depois = source.slice(offset + match.length);
    const proximoContato = /^\s+\d+(?:NA|NF)\b/i.test(depois);
    const proximaTensao = /^\s+\d+(?:[.,]\d+)?(?:[-–—/]\d+(?:[.,]\d+)?)*\s*V(?:CA\/CC|AC\/DC|CA|CC|AC|DC)?\b/i.test(depois);
    const proximoNumero = /^\s+\d/.test(depois);
    const contextoEletrico = /(CONTATOR|DISJUNTOR|REL[ÉE]|CORRENTE|SA[ÍI]DA|ENTRADA|AMPER|FONTE|MOTOR|INVERSOR|SOFT-STARTER)/.test(antes);
    if (proximaTensao || (proximoNumero && !proximoContato && !contextoEletrico)) return match;
    return `${numero}${unidade}`;
  });

  normalized = normalized.replace(MILIAMPERE_COM_ESPACO_RE, (match, numero: string, unidade: string, offset: number, source: string) => {
    const antes = source.slice(Math.max(0, offset - 50), offset).toUpperCase();
    const depois = source.slice(offset + match.length);
    if (/\b(?:DIN|ISO|ASTM)\s+\d*\s*$/.test(antes) || /[A-ZÀ-Ý]$/.test(antes) || /^\s+(?:RI|RO|X)\b/i.test(depois)) {
      return match;
    }
    return `${numero}${unidade}`;
  });

  normalized = normalized.replace(VOLT_COM_ESPACO_RE, (match, numero: string, unidade: string, offset: number, source: string) => {
    const antes = source.slice(Math.max(0, offset - 120), offset).toUpperCase();
    const depois = source.slice(offset + match.length);
    const pareceQuantidadeDeVias = Number(numero.replace(",", ".")) <= 12 && /(CABO|CONECTOR).*(M\d+|VIAS?)/.test(antes);
    if (pareceQuantidadeDeVias && !/^\s*(?:AC|DC|CA|CC)(?:\/|\b)/i.test(depois)) return match;
    return `${numero}${unidade}`;
  });

  normalized = normalized.replace(METRO_COM_ESPACO_RE, (match, numero: string, unidade: string, offset: number, source: string) => {
    const antes = source.slice(Math.max(0, offset - 50), offset).toUpperCase();
    const depois = source.slice(offset + match.length);
    const contextoComprimento = /(CABO|COMPRIMENTO|ROLO|MANGUEIRA|BARRA|CORDA)/.test(antes);
    if (/\b(?:DIN|ISO|ASTM)\s+\d*\s*$/.test(antes) || (/^\s+\d/.test(depois) && !contextoComprimento)) return match;
    return `${numero}${unidade}`;
  });

  normalized = normalized.replace(LITRO_COM_ESPACO_RE, (match, numero: string, unidade: string, offset: number, source: string) => {
    const antes = source.slice(Math.max(0, offset - 100), offset).toUpperCase();
    const depois = source.slice(offset + match.length);
    const contextoVolume = /(LITRO|VOLUME|CAPACIDADE|EMBALAGEM|GALÃO|GALAO|BOMBONA|TINTA|THINNER|SOLVENTE|ÓLEO|OLEO)/.test(antes);
    return /^\s*[-/]\s*\d/.test(depois) || !contextoVolume ? match : `${numero}${unidade}`;
  });

  normalized = normalized.replace(TEMPO_COM_ESPACO_RE, (match, numero: string, unidade: string, offset: number, source: string) => {
    const antes = source.slice(Math.max(0, offset - 120), offset).toUpperCase();
    const depois = source.slice(offset + match.length);
    const contextoTemporal = /(TEMP(?:\.|O|ORIZ)|ATRASO|PULSO|DURA[ÇC][ÃA]O|PER[ÍI]ODO|AUTONOMIA)/.test(antes);
    if (!contextoTemporal || /^\s*[/.]/.test(depois)) return match;
    return `${numero}${unidade}`;
  });

  return normalized;
}

const SUFIXO_PEDIDO_RE =
  /\s*(?:[-–—]\s*)?PEDIDO(?:\s+DE\s+COMPRA)?(?:\s*(?:N[º°.]|NÚMERO|NUMERO))?\s*[:#-]?\s*\d{4}\s*\/\s*\d+\s*(?:[-–—])?\s*$/giu;

/**
 * Remove do nome reutilizável identificadores de pedido que pertencem ao
 * documento de compra, preservando a descrição original como evidência fiscal.
 */
export function removerReferenciasTransacionaisDoNome(value: unknown): string {
  return String(value ?? "").replace(SUFIXO_PEDIDO_RE, "").replace(/\s+/g, " ").trim();
}

/** Aplica as normalizações determinísticas aprovadas para o nome do item. */
export function normalizarNomeCadastro(value: unknown): string {
  return normalizarUnidadesNoNome(removerReferenciasTransacionaisDoNome(value));
}
