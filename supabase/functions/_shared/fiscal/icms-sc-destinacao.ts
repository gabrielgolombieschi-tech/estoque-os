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

/**
 * `seguePara` e o unico fato que a destinacao declara, e dele saem os DOIS efeitos
 * fiscais — que por isso nao podem divergir:
 *
 *   OPERACAO_SUBSEQUENTE (revenda, insumo, consignacao)
 *     · ICMS 12%  — Lei SC 10.297/96, art. 19, III, "n": mercadoria destinada a
 *                   contribuinte do imposto.
 *     · IPI FORA da base do ICMS — CF art. 155, § 2º, XI: operacao entre
 *                   contribuintes E produto destinado a industrializacao ou
 *                   comercializacao (condicoes cumulativas).
 *
 *   CONSUMO_DO_ADQUIRENTE (manutencao, uso e consumo, ativo imobilizado)
 *     · ICMS 17%  — o § 3º, "a" do mesmo art. 19 afasta a alinea "n" quando a
 *                   mercadoria se destina a uso, consumo ou ativo imobilizado.
 *     · IPI DENTRO da base — falha a segunda condicao do art. 155: manter o
 *                   proprio parque nao e industrializar nem revender.
 *
 * Sao a mesma pergunta ("a mercadoria segue em operacao tributada, ou para no
 * adquirente?") respondida uma vez so. Ate 11/09/2026 estavam em dois campos
 * independentes, e a manutencao saiu com 12% e IPI na base ao mesmo tempo — as
 * duas metades de regras opostas. Foi a NF-e 2/14, com R$ 908,35 de ICMS a menos.
 */
export const DESTINACOES_MERCADORIA = {
  REVENDA: { rotulo: "revenda", seguePara: "OPERACAO_SUBSEQUENTE" },
  INSUMO: { rotulo: "insumo de produção", seguePara: "OPERACAO_SUBSEQUENTE" },
  CONSIGNADO: { rotulo: "mercadoria em consignação", seguePara: "OPERACAO_SUBSEQUENTE" },
  MANUTENCAO: { rotulo: "manutenção", seguePara: "CONSUMO_DO_ADQUIRENTE" },
  USO_CONSUMO: { rotulo: "uso e consumo do adquirente", seguePara: "CONSUMO_DO_ADQUIRENTE" },
  ATIVO_IMOBILIZADO: { rotulo: "ativo imobilizado do adquirente", seguePara: "CONSUMO_DO_ADQUIRENTE" },
} as const;

/** A mercadoria segue em operacao tributada depois desta venda? */
function segueParaOperacaoSubsequente(destinacao: DestinacaoMercadoria) {
  return DESTINACOES_MERCADORIA[destinacao].seguePara === "OPERACAO_SUBSEQUENTE";
}

/**
 * Os dois efeitos juntos. Sao DUAS condicoes cumulativas, nao uma:
 *
 *   1. o destinatario e contribuinte do imposto — a alinea "n" e literalmente
 *      "mercadorias destinadas a contribuinte", e o art. 155, § 2º, XI da CF fala
 *      em operacao "entre contribuintes";
 *   2. a mercadoria segue em operacao tributada (revenda, insumo, consignacao).
 *
 * Faltando qualquer uma, a venda e de consumo final para o ICMS: 17% e o IPI dentro
 * da base. Quem nao e contribuinte nunca alcanca os 12%, seja qual for a destinacao
 * que declare — ele nao tem operacao subsequente para tributar.
 */
export function efeitosDaDestinacao(
  destinacao: DestinacaoMercadoria,
  destinatarioContribuinte: boolean,
) {
  const subsequente = destinatarioContribuinte && segueParaOperacaoSubsequente(destinacao);
  return {
    aliquotaInterna: subsequente ? 12 : 17,
    ipiNaBaseIcms: !subsequente,
    rotulo: DESTINACOES_MERCADORIA[destinacao].rotulo,
  };
}

/** O IPI integra a base do ICMS nesta operacao? */
export function ipiIntegraBaseIcms(
  destinacao: DestinacaoMercadoria,
  destinatarioContribuinte: boolean,
) {
  return efeitosDaDestinacao(destinacao, destinatarioContribuinte).ipiNaBaseIcms;
}

/** indIEDest 1 e contribuinte do ICMS; 2 (isento) e 9 (nao contribuinte) nao sao. */
export function ehDestinatarioContribuinte(indicadorIe: string | null | undefined) {
  return String(indicadorIe ?? "").trim() === "1";
}

export type DestinacaoMercadoria = keyof typeof DESTINACOES_MERCADORIA;

/**
 * Base legal da aliquota interna aplicada. Nao e beneficio fiscal — e aliquota,
 * e por isso nao leva cBenef. Vai nas informacoes complementares porque o
 * cliente confere o destaque contra a utilizacao que informou na OC.
 *
 * Os 12% NAO alcancam mercadoria destinada a uso, consumo ou ativo imobilizado do
 * destinatario: Lei 10.297/96, art. 19, §3º, II, confirmado na Consulta SEF/SC 057/20
 * (contabilidade, 09/09/2026). Por isso USO_CONSUMO e ATIVO_IMOBILIZADO ficam nos 17%
 * em DESTINACOES_MERCADORIA, e os perfis de 12% nao listam essas duas destinacoes —
 * a regra esta nas duas camadas de proposito.
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

/** Alíquota interna que a destinação exige em SC. Sai do mesmo fato que o IPI na base. */
export function aliquotaInternaEsperada(
  destinacao: DestinacaoMercadoria,
  destinatarioContribuinte: boolean,
) {
  return efeitosDaDestinacao(destinacao, destinatarioContribuinte).aliquotaInterna;
}

/**
 * Os dois efeitos da destinacao andam juntos ou a nota esta errada. Guarda contra
 * o par que a NF-e 2/14 produziu — 12% (que so existe porque a mercadoria segue em
 * operacao tributada) com o IPI dentro da base (que so existe porque ela NAO segue).
 *
 * A checagem e sobre a carga efetiva, nao a aliquota nominal: CST 20 a 17% com base
 * reduzida ate 12% e um dos caminhos legitimos dos 12%.
 */
export function conflitoIpiNaBaseComAliquota(
  destinacao: DestinacaoMercadoria,
  cargaEfetivaIcms: number | null,
  ipiEntrouNaBase: boolean,
  interestadual: boolean,
  temIpi: boolean,
  destinatarioContribuinte: boolean,
): string | null {
  // Sem IPI nao ha o que estar dentro ou fora da base: a maquina do Convenio 52/91,
  // por exemplo, sai a 17% com CST 53 e nenhum IPI, e isso nao e contradicao.
  if (!temIpi) return null;
  if (interestadual || cargaEfetivaIcms === null) return null;
  const { ipiNaBaseIcms } = efeitosDaDestinacao(destinacao, destinatarioContribuinte);
  if (cargaEfetivaIcms === 12 && ipiEntrouNaBase) {
    return "os 12% valem porque a mercadoria segue em operação tributada (Lei 10.297/96, "
      + 'art. 19, III, "n"), e nessa mesma condição o IPI fica fora da base do ICMS '
      + "(CF art. 155, § 2º, XI). A nota está com os dois ao mesmo tempo";
  }
  if (cargaEfetivaIcms === 17 && ipiNaBaseIcms && !ipiEntrouNaBase) {
    return `destinação ${rotuloDestinacao(destinacao)} está nos 17% porque a mercadoria `
      + "para no adquirente (art. 19, § 3º, \"a\"), e nessa condição o IPI integra a base "
      + "do ICMS — a nota deixou o IPI de fora";
  }
  return null;
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
  destinatarioContribuinte: boolean,
): string | null {
  if (interestadual || aliquotaIcms === null) return null;
  if (aliquotaIcms !== 12 && aliquotaIcms !== 17) return null;
  const esperada = aliquotaInternaEsperada(destinacao, destinatarioContribuinte);
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
 *
 * `cargaVemDeReducaoDeBase` desliga a citacao da lei da aliquota. Quando os 12%
 * saem de CST 20 a 17% com base reduzida, quem os concedeu foi o beneficio —
 * Anexo 2, Art. 7o, VII ou o Convenio 52/91, ja escritos na nota — e nao a
 * aliquota reduzida da Lei 10.297/96, art. 19, III, "n". Citar as duas seria
 * afirmar dois fundamentos excludentes para o mesmo imposto.
 */
export function textoDestinacao(
  destinacao: DestinacaoMercadoria,
  aliquotaIcms: number | null,
  interestadual: boolean,
  cargaVemDeReducaoDeBase = false,
) {
  const declaracao = `Destinação informada pelo destinatário: ${rotuloDestinacao(destinacao)}`;
  if (interestadual || aliquotaIcms === null || cargaVemDeReducaoDeBase) return declaracao;
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

/**
 * Trava do cBenef do Anexo 2, Art. 7o, VII. Devolve o motivo do bloqueio, ou null.
 *
 * O item usa o beneficio quando o NCM esta na lista, a operacao e interna e ele sai
 * por um dos dois caminhos do inciso: CST 20 (base reduzida, com QUALQUER reducao —
 * a trava nao confere a conta, so a falta do codigo) ou a faculdade da alinea "a",
 * 12% direto sobre a base integral. Nos dois a SEFAZ exige o cBenef desde 03/02/2025.
 *
 * Ate 16/09/2026 so a carga efetiva de 12% disparava a trava: um CST 20 com outra
 * reducao na mesma lista seguia para a Focus sem cBenef. Fica aqui, e nao dentro do
 * builder, para a conferencia da tela chamar a mesma regra antes de a pessoa tentar.
 */
/**
 * Os 12% vieram da ALIQUOTA, e nao do beneficio de automacao?
 *
 * Decisao do Gabriel em 18/09/2026 (OV-SEG-00012-026, CHAVE PIZZATO, NCM 8536.50.90): venda a
 * contribuinte com destinacao que segue em operacao tributada (revenda, insumo, consignacao) e
 * 12% pela Lei 10.297/96, art. 19, III, "n" — aliquota, nao beneficio. A reducao de base do
 * Anexo 2, art. 7º, VII (cBenef SC820006) so tem funcao quando a operacao seria tributada a 17%.
 *
 * Sao quatro condicoes juntas; falta uma, e beneficio (e ai o cBenef e obrigatorio):
 *   1. a destinacao segue em operacao tributada;
 *   2. o destinatario e contribuinte;
 *   3. o perfil NAO aplica reducao de base (CST 00, sem percentual de reducao);
 *   4. a nota nao traz cBenef — quando traz, quem emitiu esta declarando o beneficio (alinea "a",
 *      12% direto sobre a base integral com a observacao no documento), e nada muda.
 */
export function aliquota12PorDestinacaoSc(params: {
  destinacao?: string | null;
  destinatarioContribuinte?: boolean | null;
  situacaoIcms?: string | null;
  reducaoBase?: number | null;
  cbenef?: string | null;
}): boolean {
  const destinacao = String(params.destinacao ?? "");
  if (!ehDestinacaoValida(destinacao)) return false;
  if (!segueParaOperacaoSubsequente(destinacao as DestinacaoMercadoria)) return false;
  if (params.destinatarioContribuinte !== true) return false;
  if (String(params.situacaoIcms ?? "").trim() === "20") return false;
  if ((params.reducaoBase ?? 0) > 0) return false;
  if (String(params.cbenef ?? "").trim()) return false;
  return true;
}

export function faltaCbenefAutomacaoSc(item: {
  codigo: string;
  ncm: string;
  situacaoIcms: string | null;
  cargaEfetivaIcms: number | null;
  cbenef: string | null;
  interestadual: boolean;
  destinacao?: string | null;
  destinatarioContribuinte?: boolean | null;
  reducaoBase?: number | null;
}): string | null {
  const ncm = String(item.ncm ?? "").replace(/\D/g, "");
  if (!temReducaoAutomacaoSc(ncm, item.interestadual)) return null;
  if (String(item.cbenef ?? "").trim()) return null;
  // 12% por aliquota (revenda/insumo/consignacao a contribuinte, sem reducao de base): o cBenef
  // nao entra, porque nao ha beneficio na operacao.
  if (aliquota12PorDestinacaoSc(item)) return null;
  const situacao = String(item.situacaoIcms ?? "").trim();
  const usaBeneficio = situacao === "20" || item.cargaEfetivaIcms === 12;
  if (!usaBeneficio) return null;
  const ncmFormatado = ncm.replace(/^(\d{4})(\d{2})(\d{2})$/, "$1.$2.$3");
  return `item ${item.codigo}, CST ${situacao || "?"} com o benefício de redução de base do `
    + `${REDUCAO_AUTOMACAO_SC.baseLegal} (NCM ${ncmFormatado}) e sem cBenef. O benefício `
    + `exige o cBenef ${REDUCAO_AUTOMACAO_SC.cbenef} — a SEFAZ rejeita benefício de ICMS sem código `
    + "desde 03/02/2025. Corrija o perfil fiscal do item antes de emitir. "
    + "Se a venda é para contribuinte revender, usar como insumo ou receber em consignação, os 12% "
    + "são a alíquota da Lei 10.297/96, art. 19, III, \"n\", e não o benefício: confirme a destinação "
    + "declarada e use perfil sem redução de base";
}

/**
 * Texto completo para dados adicionais quando o beneficio de automacao e usado.
 *
 * Nota que mistura itens com e sem o beneficio diz quais usaram a reducao, pelo
 * numero do item na nota (nItem): "Itens 2, 5: Base de calculo reduzida ...". Quando
 * todos os itens usaram, o texto fica sem a lista. Decisao do Gabriel, 16/09/2026:
 * sem a lista, a observacao dava a entender que a nota inteira tinha base reduzida.
 */
export function textoReducaoAutomacaoSc(itensComBeneficio: number[] = [], totalItens = 0) {
  const texto = `${REDUCAO_AUTOMACAO_SC.observacaoDocumento} - ${REDUCAO_AUTOMACAO_SC.baseLegal}`;
  const itens = [...new Set(itensComBeneficio)].sort((a, b) => a - b);
  if (itens.length === 0 || itens.length >= totalItens) return texto;
  return `${itens.length === 1 ? "Item" : "Itens"} ${itens.join(", ")}: ${texto}`;
}

/**
 * Excecao "ICMS 12% por exigencia do destinatario" (Gabriel, 16/09/2026, pedido da
 * PORTOBELLO). Mercadoria de manutencao, uso e consumo ou ativo imobilizado vai a 17%
 * (art. 19, § 3º), mas o destinatario contribuinte pode exigir os 12% declarando a
 * utilizacao na OC — e ai responde solidariamente pela diferenca (RICMS/SC-01, art. 26,
 * § 6º). Nao e beneficio (sem cBenef) e nao muda o IPI.
 *
 * Com a excecao ativa, cada item SEM o cBenef SC820006 sai CST 00 a 12% sobre a base
 * integral; o item COM SC820006 segue a propria regra (CST 20, base reduzida). O indFinal
 * fica 1 e o IPI continua dentro da base do ICMS, porque a destinacao nao mudou.
 */
export const EXCECAO_ALIQUOTA_12_DESTINATARIO = {
  aliquota: 12,
  cst: "00",
  baseLegal: 'RICMS/SC-01, art. 26, III, "n"',
  destinacoes: ["MANUTENCAO", "USO_CONSUMO", "ATIVO_IMOBILIZADO"] as DestinacaoMercadoria[],
};

export type ExcecaoAliquota12 = { numeroOc: string };

/** Por que a excecao nao cabe nesta nota, ou null quando cabe. */
export function excecaoAliquota12Indisponivel(
  destinacao: DestinacaoMercadoria,
  destinatarioContribuinte: boolean,
  interestadual: boolean,
): string | null {
  if (!destinatarioContribuinte) {
    return "a exceção de ICMS 12% por exigência do destinatário só vale para destinatário contribuinte (indIEDest = 1)";
  }
  if (interestadual) {
    return "a exceção de ICMS 12% por exigência do destinatário só vale em operação interna";
  }
  if (!EXCECAO_ALIQUOTA_12_DESTINATARIO.destinacoes.includes(destinacao)) {
    return `a exceção de ICMS 12% por exigência do destinatário não se aplica à destinação ${rotuloDestinacao(destinacao)}`;
  }
  return null;
}

/**
 * Le a excecao gravada no snapshot da operacao. Ausente e null; presente sem o numero
 * da OC aborta, porque o texto da nota cita a OC e sem ela a exigencia nao tem prova.
 */
export function lerExcecaoAliquota12(valor: unknown): ExcecaoAliquota12 | null {
  if (valor === null || valor === undefined) return null;
  const registro = typeof valor === "object" && !Array.isArray(valor) ? valor as Record<string, unknown> : {};
  const numeroOc = typeof registro.numero_oc === "string" ? registro.numero_oc.trim() : "";
  if (!numeroOc) {
    throw new Error("Emissão bloqueada: a exceção de ICMS 12% por exigência do destinatário exige o número da OC.");
  }
  return { numeroOc };
}

/** O item entra na excecao? So quem nao tem o cBenef do Anexo 2, Art. 7º, VII. */
export function itemNaExcecaoAliquota12(cbenef: string | null | undefined) {
  return String(cbenef ?? "").trim() !== REDUCAO_AUTOMACAO_SC.cbenef;
}

/** Texto das informacoes complementares. Sempre lista os itens (nItem) que usaram a excecao. */
export function textoExcecaoAliquota12(
  itens: number[],
  numeroOc: string,
  destinacao: DestinacaoMercadoria,
) {
  const lista = [...new Set(itens)].sort((a, b) => a - b);
  return `${lista.length === 1 ? "Item" : "Itens"} ${lista.join(", ")}: ICMS à alíquota de 12% `
    + `(${EXCECAO_ALIQUOTA_12_DESTINATARIO.baseLegal}) aplicada por determinação do destinatário, `
    + `conforme OC nº ${numeroOc}, utilização informada: ${rotuloDestinacao(destinacao)}. `
    + "O destinatário responde solidariamente pela diferença de alíquota, nos termos do "
    + "art. 26, § 6º, do RICMS/SC-01.";
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
  cbenef: "SC820028",
  // Inciso I conforme a tabela de cBenef de SC e a orientacao da contabilidade em
  // 09/09/2026: "Saidas internas e interestaduais de maquinas, aparelhos e
  // equipamentos industriais", cBenef SC820028, CST 20, com reducao de base.
  baseLegal: "Convênio ICMS 52/91 - RICMS/SC-01, Anexo 2, Art. 9º, I",
  observacaoDocumento: "Base de cálculo reduzida - máquinas e aparelhos industriais",
  // 8479.81.90 entrou pela NF-e 3805 da ARCELORMITTAL (ERP antigo, 04/09/2026), que
  // saiu com CST 020, aliquota 17% e base reduzida para a carga de 8,80% — os mesmos
  // 48,2353% de reducao. Foi a nota que a contabilidade usou de referencia.
  ncms: ["84609090", "84798190"] as const,
};

export function temReducaoMaquinas5291(ncm: string) {
  return (REDUCAO_MAQUINAS_CONVENIO_52_91.ncms as readonly string[]).includes(ncm);
}

export function textoReducaoMaquinas5291() {
  return `${REDUCAO_MAQUINAS_CONVENIO_52_91.observacaoDocumento} - ${REDUCAO_MAQUINAS_CONVENIO_52_91.baseLegal}`;
}
