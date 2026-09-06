/**
 * Destinacao da mercadoria e aliquota interna de ICMS em SC.
 *
 * A aliquota interna nao e caracteristica do produto: e da destinacao que o
 * adquirente da a mercadoria. As bases legais estao em
 * docs/faturamento/regras-icms-sc-contabilidade.md, transcritas do documento da
 * Status Contabilidade e da carta da PORTOBELLO.
 *
 * A PORTOBELLO recusa nota com aliquota divergente, entao a destinacao vem
 * declarada na OC do cliente e a nota precisa dizer qual foi.
 *
 * Atencao ao sujeito: e o que o CLIENTE faz com a mercadoria, nao a natureza da
 * operacao da empresa. A NF-e da OV emite uma unica natureza — venda de
 * mercadoria de terceiros, CFOP 5102. Industrializacao propria sai por OS, e
 * simples remessa, conserto e afins tem lugar proprio. Por isso nao existe aqui
 * uma destinacao "industrializacao": o cliente que industrializa entra em
 * INSUMO, sem repetir um termo que pertence a outro fluxo.
 */

export const DESTINACOES_MERCADORIA = {
  REVENDA: {
    rotulo: "revenda",
    contribuinte: true,
  },
  INSUMO: {
    rotulo: "insumo de produção",
    contribuinte: true,
  },
  MANUTENCAO: {
    rotulo: "manutenção",
    contribuinte: true,
  },
  CONSIGNADO: {
    rotulo: "mercadoria em consignação",
    contribuinte: true,
  },
  USO_CONSUMO: {
    rotulo: "uso e consumo do adquirente",
    contribuinte: false,
  },
  ATIVO_IMOBILIZADO: {
    rotulo: "ativo imobilizado do adquirente",
    contribuinte: false,
  },
} as const;

export type DestinacaoMercadoria = keyof typeof DESTINACOES_MERCADORIA;

/**
 * Base legal da aliquota interna aplicada. Nao e beneficio fiscal — e aliquota,
 * e por isso nao leva cBenef. Vai nas informacoes complementares porque o
 * cliente confere o destaque contra a utilizacao que informou na OC.
 */
const BASE_LEGAL_ALIQUOTA_INTERNA: Array<{ aliquota: number; texto: string }> = [
  {
    aliquota: 12,
    texto: 'Alíquota interna de ICMS de 12% - operação destinada a contribuinte do imposto - '
      + 'Lei 10.297/96, art. 19, III, "n", e Lei 17.878/2019',
  },
  {
    aliquota: 17,
    texto: "Alíquota interna de ICMS de 17% - operação destinada a consumidor final - "
      + "RICMS/SC, art. 26, I",
  },
];

/** Alíquota interna que a destinação exige em SC. */
export function aliquotaInternaEsperada(destinacao: DestinacaoMercadoria) {
  return DESTINACOES_MERCADORIA[destinacao].contribuinte ? 12 : 17;
}

/**
 * A destinacao e a aliquota destacada tem que dizer a mesma coisa. Sem esta
 * guarda a nota podia sair declarando "destinacao: revenda" ao lado de
 * "aliquota de 17% - operacao destinada a consumidor final" — contradicao dentro
 * do proprio campo de informacoes complementares, e o tipo de divergencia que a
 * PORTOBELLO recusa. Vale somente para as duas aliquotas internas conhecidas:
 * operacao interestadual segue a tabela do Senado, e CST de suspensao ou
 * diferimento nao tem aliquota a conferir.
 */
export function conflitoDestinacaoAliquota(
  destinacao: DestinacaoMercadoria,
  aliquotaIcms: number | null,
  interestadual: boolean,
): string | null {
  if (interestadual || aliquotaIcms === null) return null;
  if (aliquotaIcms !== 12 && aliquotaIcms !== 17) return null;
  const esperada = aliquotaInternaEsperada(destinacao);
  if (aliquotaIcms === esperada) return null;
  return `destinação ${rotuloDestinacao(destinacao)} exige alíquota interna de `
    + `${esperada}%, e a nota está com ${aliquotaIcms}%`;
}

export function ehDestinacaoValida(valor: unknown): valor is DestinacaoMercadoria {
  return typeof valor === "string" && valor in DESTINACOES_MERCADORIA;
}

export function rotuloDestinacao(destinacao: DestinacaoMercadoria) {
  return DESTINACOES_MERCADORIA[destinacao].rotulo;
}

/**
 * Frase para as informacoes complementares da nota. Junta a destinacao
 * declarada com a base legal da aliquota efetivamente destacada, quando ela e
 * uma das duas aliquotas internas conhecidas. Em operacao interestadual a
 * aliquota vem da tabela do Senado e nao cabe citar as duas leis de SC, entao
 * so a destinacao e declarada.
 */
export function textoDestinacao(
  destinacao: DestinacaoMercadoria,
  aliquotaIcms: number | null,
  interestadual: boolean,
) {
  const declaracao = `Destinação informada pelo destinatário: ${rotuloDestinacao(destinacao)}`;
  if (interestadual || aliquotaIcms === null) return declaracao;
  const base = BASE_LEGAL_ALIQUOTA_INTERNA.find((regra) => regra.aliquota === aliquotaIcms);
  return base ? `${declaracao}. ${base.texto}` : declaracao;
}

/**
 * NCMs com reducao de base do RICMS/SC-01, Anexo 2, Art. 7o, VII — equipamentos
 * de automacao, informatica e telecomunicacoes. Somente operacoes internas.
 *
 * A alinea "a" do inciso VII faculta aplicar 12% direto sobre a base integral,
 * "desde que o sujeito passivo aponha, no documento fiscal", a observacao de
 * base reduzida. Ou seja: CST 00 com 12% e caminho legal para estes NCMs, mas
 * so com o texto. E, desde 03/02/2025, a SEFAZ rejeita beneficio de ICMS sem
 * cBenef no item e base legal em dados adicionais.
 *
 * NCM 8537.10.20 (controlador programavel) NAO esta na lista: nele o 12% vem da
 * Lei 10.297/96 e nao ha beneficio nenhum a declarar.
 */
export const REDUCAO_AUTOMACAO_SC = {
  cbenef: "SC820006",
  reducaoPercentual: 29.412,
  baseLegal: "RICMS/SC-01, Anexo 2, Art. 7º, VII",
  observacaoDocumento:
    "Base de cálculo reduzida - produtos da indústria de automação, informática e telecomunicações",
  ncms: ["85364900", "85365090", "85444900"] as const,
};

export function temReducaoAutomacaoSc(ncm: string, interestadual: boolean) {
  if (interestadual) return false;
  return (REDUCAO_AUTOMACAO_SC.ncms as readonly string[]).includes(ncm);
}

/** Texto completo para dados adicionais quando o beneficio de automacao e usado. */
export function textoReducaoAutomacaoSc() {
  return `${REDUCAO_AUTOMACAO_SC.observacaoDocumento} - ${REDUCAO_AUTOMACAO_SC.baseLegal}`;
}

/**
 * Maquinas e aparelhos industriais do Convenio ICMS 52/91 (RICMS/SC-01, Anexo 2,
 * Art. 9o): reducao de base para carga efetiva de 8,80%, interna (17% nominal)
 * e interestadual (12% nominal). Contador, 06/09/2026, sobre o NCM 8460.90.90:
 * CST 20, cBenef do convenio, aliquota nominal cheia e base reduzida — nunca
 * 12% direto. O codigo do cBenef nao foi informado e nao e deduzido: o item
 * precisa te-lo cadastrado, senao a nota nao sai.
 */
export const REDUCAO_MAQUINAS_CONVENIO_52_91 = {
  cargaEfetiva: 8.8,
  baseLegal: "Convênio ICMS 52/91 - RICMS/SC-01, Anexo 2, Art. 9º",
  observacaoDocumento: "Base de cálculo reduzida - máquinas e aparelhos industriais",
  ncms: ["84609090"] as const,
};

export function temReducaoMaquinas5291(ncm: string) {
  return (REDUCAO_MAQUINAS_CONVENIO_52_91.ncms as readonly string[]).includes(ncm);
}

export function textoReducaoMaquinas5291() {
  return `${REDUCAO_MAQUINAS_CONVENIO_52_91.observacaoDocumento} - ${REDUCAO_MAQUINAS_CONVENIO_52_91.baseLegal}`;
}
