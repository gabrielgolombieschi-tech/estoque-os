import { tributacaoProvisoria } from "./tributacao-provisoria.ts";
import {
  ehNaturezaRemessaConserto,
  motivoItemForaDaRemessaConserto,
  REMESSA_CONSERTO,
  textosRemessaConserto,
} from "./fiscal/remessa-conserto.ts";
import {
  ehNaturezaRetornoTerceiros,
  lerOrigemRetornoTerceiros,
  motivoItemForaDoRetornoTerceiros,
  RETORNO_REMESSA_TERCEIROS,
  textoRetornoTerceiros,
} from "./fiscal/retorno-remessa-terceiros.ts";
import {
  conflitoDestinacaoAliquota,
  conflitoIpiNaBaseComAliquota,
  ehDestinatarioContribuinte,
  ehDestinacaoValida,
  excecaoAliquota12Indisponivel,
  EXCECAO_ALIQUOTA_12_DESTINATARIO,
  faltaCbenefAutomacaoSc,
  itemNaExcecaoAliquota12,
  lerExcecaoAliquota12,
  REDUCAO_MAQUINAS_CONVENIO_52_91,
  temReducaoAutomacaoSc,
  ipiIntegraBaseIcms,
  temReducaoMaquinas5291,
  textoDestinacao,
  textoExcecaoAliquota12,
  textoReducaoAutomacaoSc,
  textoReducaoMaquinas5291,
  type DestinacaoMercadoria,
} from "./fiscal/icms-sc-destinacao.ts";
import {
  calcularIbsCbsTransicao2026,
  ibsCbsSemGrupoDeValores,
  resolverIbsCbsTransicao2026,
  validarCfopIbsCbsTransicao2026,
} from "./fiscal/ibs-cbs-transicao-2026.ts";
import {
  dataCivilSaoPaulo,
  type IbptNcm,
  type ItemIbpt,
  textoTributosAproximados as fraseTributosAproximados,
  tributosAproximadosNota,
} from "./fiscal/ibpt.ts";

type LinhaContexto = {
  documento_item?: Record<string, unknown> | null;
  solicitacao_item: Record<string, unknown>;
};

export const NOME_DESTINATARIO_HOMOLOGACAO =
  "NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL";

type JsonObject = Record<string, unknown>;

function jsonObject(value: unknown, label: string): JsonObject {
  let cloned: unknown;
  try {
    cloned = JSON.parse(JSON.stringify(value));
  } catch {
    throw new Error(`Emissao em producao bloqueada: ${label} nao e um JSON valido.`);
  }
  if (!cloned || typeof cloned !== "object" || Array.isArray(cloned)) {
    throw new Error(`Emissao em producao bloqueada: ${label} nao e um objeto JSON.`);
  }
  return cloned as JsonObject;
}

function ordenarJson(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(ordenarJson);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.entries(value as JsonObject)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([key, nested]) => [key, ordenarJson(nested)]),
  );
}

function primeiraDiferenca(a: unknown, b: unknown, caminho = "$"): string | null {
  if (Object.is(a, b)) return null;
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b)) return caminho;
    if (a.length !== b.length) return `${caminho}.length`;
    for (let index = 0; index < a.length; index += 1) {
      const diferenca = primeiraDiferenca(a[index], b[index], `${caminho}[${index}]`);
      if (diferenca) return diferenca;
    }
    return null;
  }
  if (a && b && typeof a === "object" && typeof b === "object") {
    const chavesA = Object.keys(a as JsonObject).sort();
    const chavesB = Object.keys(b as JsonObject).sort();
    if (chavesA.length !== chavesB.length) return caminho;
    for (let index = 0; index < chavesA.length; index += 1) {
      if (chavesA[index] !== chavesB[index]) return caminho;
      const chave = chavesA[index];
      const diferenca = primeiraDiferenca(
        (a as JsonObject)[chave],
        (b as JsonObject)[chave],
        caminho === "$" ? chave : `${caminho}.${chave}`,
      );
      if (diferenca) return diferenca;
    }
    return null;
  }
  return caminho;
}

function normalizarPayloadFiscal(value: unknown, ambiente: "HOMOLOGACAO" | "PRODUCAO") {
  const payload = jsonObject(value, `payload de ${ambiente.toLowerCase()}`);
  const nomeDestinatario = String(payload.nome_destinatario ?? "").trim();
  if (ambiente === "HOMOLOGACAO" && nomeDestinatario !== NOME_DESTINATARIO_HOMOLOGACAO) {
    throw new Error(
      "Emissao em producao bloqueada: a homologacao autorizada nao usou o nome de destinatario exigido pela SEFAZ.",
    );
  }
  if (ambiente === "PRODUCAO" && (!nomeDestinatario || nomeDestinatario === NOME_DESTINATARIO_HOMOLOGACAO)) {
    throw new Error("Emissao em producao bloqueada: o destinatario real nao foi informado no payload de producao.");
  }

  // Sao as unicas diferencas aceitas entre os dois envios. Todo o restante,
  // inclusive itens, impostos, totais e enderecos, permanece congelado.
  delete payload.data_emissao;
  delete payload.data_entrada_saida;
  // As datas das duplicatas derivam da data de emissao (+ dias confirmados);
  // numero e valor continuam congelados.
  if (Array.isArray(payload.duplicatas)) {
    payload.duplicatas = payload.duplicatas.map((d) => {
      const dup = { ...jsonObject(d, "duplicata") };
      delete dup.data_vencimento;
      return dup;
    });
  }
  payload.nome_destinatario = "<NOME_DESTINATARIO_POR_AMBIENTE>";
  delete payload.ambiente;
  delete payload.ambiente_emissao;
  // NFref (retorno de terceiros) so vai na nota real: a SEFAZ de homologacao nao conhece a
  // chave de producao referenciada (rejeicao 267). A chave continua congelada no infCpl.
  delete payload.notas_referenciadas;
  return ordenarJson(payload);
}

export function validarPayloadProducaoContraHomologacao(
  payloadHomologacao: unknown,
  payloadProducao: unknown,
) {
  const homologacao = normalizarPayloadFiscal(payloadHomologacao, "HOMOLOGACAO");
  const producao = normalizarPayloadFiscal(payloadProducao, "PRODUCAO");
  const diferenca = primeiraDiferenca(homologacao, producao);
  if (diferenca) {
    throw new Error(
      `Emissao em producao bloqueada: o payload fiscal diverge da homologacao autorizada no campo ${diferenca}.`,
    );
  }
}

export type ContextoEmissao = {
  emissao: Record<string, unknown>;
  documento?: Record<string, unknown>;
  solicitacao: Record<string, unknown>;
  itens: LinhaContexto[];
  /**
   * Linhas da tabela IBPT (f.ibpt_ncm) dos NCMs da nota, anexadas pela Edge Function
   * (_shared/ibpt-contexto.ts). Ausente = sem tabela: a nota sai sem a frase da
   * Lei 12.741 e sem vTotTrib.
   */
  ibpt?: IbptNcm[] | null;
};

function digits(value: unknown) {
  return String(value ?? "").replace(/\D/g, "");
}

function text(value: unknown) {
  const normalized = String(value ?? "").trim();
  return normalized || null;
}

function num(value: unknown) {
  if (value === null || value === undefined || String(value).trim() === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function round(value: number) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function requiredText(value: unknown, label: string) {
  const normalized = text(value);
  if (!normalized) throw new Error(`Solicitação incompleta: ${label}.`);
  return normalized;
}

function requiredNumber(value: unknown, label: string) {
  const normalized = num(value);
  if (normalized === null) throw new Error(`Solicitação incompleta: ${label}.`);
  return normalized;
}

function snapshot(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`Solicitação incompleta: snapshot de ${label} não foi congelado.`);
  }
  return value as Record<string, unknown>;
}

function documentoDestinatario(destinatario: Record<string, unknown>) {
  const documento = digits(destinatario.documento);
  if (documento.length === 14) return { cnpj_destinatario: documento };
  if (documento.length === 11) return { cpf_destinatario: documento };
  throw new Error(`Solicitação incompleta: destinatário ${destinatario.nome ?? destinatario.id} com CNPJ/CPF inválido.`);
}

function impostoTributado(cst: string, tributados: string[]) {
  return tributados.includes(cst);
}

// Data civil de America/Sao_Paulo somada de N dias (vencimento de duplicata).
export function dataVencimentoSaoPaulo(data: Date, dias: number) {
  if (!(data instanceof Date) || !Number.isFinite(data.getTime())) {
    throw new Error("Data de emissão inválida.");
  }
  const partes = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(data);
  const valor = (tipo: Intl.DateTimeFormatPartTypes) => Number(partes.find((p) => p.type === tipo)?.value ?? "0");
  const base = new Date(Date.UTC(valor("year"), valor("month") - 1, valor("day") + dias));
  return base.toISOString().slice(0, 10);
}

export function dataHoraNfeSaoPaulo(data: Date) {
  if (!(data instanceof Date) || !Number.isFinite(data.getTime())) {
    throw new Error("Data de emissão inválida.");
  }
  const partes = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(data);
  const valor = (tipo: Intl.DateTimeFormatPartTypes) =>
    partes.find((parte) => parte.type === tipo)?.value;
  return `${valor("year")}-${valor("month")}-${valor("day")}T${valor("hour")}:${valor("minute")}:${valor("second")}-03:00`;
}

function naturezaOperacao(valor: unknown) {
  const informada = requiredText(valor, "natureza da operação");
  const mapa = tributacaoProvisoria.naturezasOperacao;
  const codigo = informada in mapa
    ? informada as keyof typeof mapa
    : (Object.entries(mapa).find(([, textoNatureza]) => textoNatureza === informada)?.[0] as keyof typeof mapa | undefined);
  if (!codigo) {
    throw new Error(`Solicitação incompleta: natureza da operação ${informada} não consta na fixture provisória de agosto/2026.`);
  }
  const descricao = mapa[codigo];
  if (descricao.length > 60) {
    throw new Error(`Solicitação incompleta: natOp da natureza ${codigo} excede 60 caracteres.`);
  }
  return { codigo, descricao };
}

function objetoOpcional(value: unknown, label: string) {
  if (value === null || value === undefined) return null;
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`Solicitação incompleta: ${label} deve ser um objeto.`);
  }
  return value as Record<string, unknown>;
}

/**
 * xMun (C10, E10, X10) e o NOME do municipio. So digitos e o codigo IBGE no lugar do nome:
 * a SEFAZ autoriza, porque valida o cMun, mas o DANFE imprime "4218004" como cidade. Foi a
 * NF-e 2/55 (PBG S/A, 16/09/2026), com a cidade do cliente gravada pela importacao de NFS-e.
 * O congelamento ja troca pelo nome da tabela IBGE a partir do cMun; esta e a rede final.
 */
function nomeMunicipio(valor: unknown, label: string) {
  const nome = requiredText(valor, `município ${label}`);
  if (/^[\d\s.-]+$/.test(nome)) {
    throw new Error(
      `Emissão bloqueada: município ${label} está como "${nome}", só com dígitos — é o código IBGE, não o nome (xMun). `
      + "Corrija o município no cadastro.",
    );
  }
  return nome;
}

export function montarPayloadNfe(contexto: ContextoEmissao, agora = new Date()) {
  const emissao = contexto.emissao;
  const solicitacao = contexto.solicitacao;
  const ambiente = String(emissao.ambiente ?? "").toUpperCase();
  if (ambiente !== "HOMOLOGACAO" && ambiente !== "PRODUCAO") {
    throw new Error("Emissão bloqueada: ambiente deve ser HOMOLOGACAO ou PRODUCAO.");
  }

  const emitente = snapshot(solicitacao.emitente_snapshot, "emitente");
  const destinatario = snapshot(solicitacao.destinatario_snapshot, "destinatário");
  const operacao = snapshot(solicitacao.operacao_snapshot, "operação");
  const natureza = naturezaOperacao(operacao.natureza_operacao);
  const regraIbsCbs = resolverIbsCbsTransicao2026(natureza.codigo, agora);
  const ufEmitente = requiredText(emitente.uf, "UF do emitente").toUpperCase();
  const ufDestinatario = requiredText(destinatario.uf, "UF do destinatário").toUpperCase();
  const interestadual = ufEmitente !== ufDestinatario;
  const indicadorIe = requiredText(destinatario.indicador_ie, "indicador de IE do destinatário");
  // Os 12% e o IPI fora da base exigem destinatario contribuinte, nao so a destinacao.
  const destinatarioContribuinte = ehDestinatarioContribuinte(indicadorIe);
  if (!["1", "2", "9"].includes(indicadorIe)) {
    throw new Error("Solicitação incompleta: indicador de IE do destinatário deve ser 1, 2 ou 9.");
  }
  if (!Array.isArray(contexto.itens) || contexto.itens.length === 0) {
    throw new Error("Solicitação incompleta: não há itens para emitir.");
  }

  // Destinação declarada pelo destinatário: é ela que decide a alíquota interna
  // de SC, e o cliente confere o destaque contra a utilização que informou na
  // OC. Sem ela a nota sai com alíquota que ninguém confirmou.
  // A remessa para conserto nao tem destinacao: a mercadoria volta. Tudo que depende da
  // destinacao (aliquota, IPI na base, excecao de 12%, texto) fica de fora dela.
  const remessaConserto = ehNaturezaRemessaConserto(natureza.codigo) ? natureza.codigo : null;
  // Retorno de mercadoria de terceiros (fiscal/retorno-remessa-terceiros.ts): tambem sem
  // destinacao — a mercadoria nem e nossa e volta inteira ao remetente, sem cobranca.
  const retornoTerceiros = ehNaturezaRetornoTerceiros(natureza.codigo) ? natureza.codigo : null;
  const semDestinacao = remessaConserto !== null || retornoTerceiros !== null;
  const origemRetorno = retornoTerceiros ? lerOrigemRetornoTerceiros(operacao.retorno_terceiros) : null;
  const destinacaoInformada = text(operacao.destinacao_mercadoria);
  if (!semDestinacao && !destinacaoInformada) {
    throw new Error("Solicitação incompleta: destinação da mercadoria não confirmada.");
  }
  if (destinacaoInformada && !ehDestinacaoValida(destinacaoInformada)) {
    throw new Error(`Solicitação incompleta: destinação da mercadoria ${destinacaoInformada} desconhecida.`);
  }
  const destinacao: DestinacaoMercadoria | null = semDestinacao ? null : (destinacaoInformada as DestinacaoMercadoria);
  // Excecao "ICMS 12% por exigencia do destinatario" (icms-sc-destinacao.ts). Gravada na
  // conferencia com OC e evidencia; aqui so se confere que ainda cabe nesta nota.
  const excecaoAliquota12 = lerExcecaoAliquota12(operacao.excecao_aliquota_destinatario);
  if (excecaoAliquota12) {
    if (!destinacao) throw new Error("Emissão bloqueada: a exceção de ICMS 12% não se aplica a remessa.");
    const indisponivel = excecaoAliquota12Indisponivel(destinacao, destinatarioContribuinte, interestadual);
    if (indisponivel) throw new Error(`Emissão bloqueada: ${indisponivel}.`);
  }
  // nItem dos itens que sairam a 12% pela excecao: vao listados no texto da nota.
  const itensExcecaoAliquota12: number[] = [];

  let valorProdutos = 0;
  let valorDesconto = 0;
  let valorIpi = 0;
  const itensIbpt: ItemIbpt[] = [];
  let baseIbsCbsTotal = 0;
  let vItemTotal = 0;
  let ibsUfTotal = 0;
  let ibsMunTotal = 0;
  let cbsTotal = 0;
  let usaBeneficioReducaoSc = false;
  // Numero na nota (nItem) de cada item que usou a reducao do Anexo 2, Art. 7º, VII:
  // a observacao lista esses itens quando a nota nao e toda deles.
  const itensBeneficioReducaoSc: number[] = [];
  let usaBeneficioMaquinas5291 = false;
  // Só cito a base legal da alíquota quando a nota inteira usa uma única
  // alíquota; com itens em alíquotas diferentes, a citação apontaria para a
  // errada em metade das linhas.
  const aliquotasIcms = new Set<number>();
  const items = contexto.itens.map((linha, index) => {
    const item = linha.solicitacao_item;
    // nItem do det: o mesmo numero vai em numero_item e na lista de itens da observacao
    // do beneficio, entao "Itens 1, 3: ..." sempre aponta para os det certos. E a
    // posicao na lista COMPLETA dos itens da nota, nunca num array ja filtrado.
    const numeroItem = index + 1;
    const codigo = requiredText(item.codigo_produto, `linha ${index + 1}, código do produto`);
    const descricao = requiredText(item.descricao, `item ${codigo}, descrição`);
    const ncm = digits(item.ncm);
    if (ncm.length !== 8) throw new Error(`Solicitação incompleta: item ${codigo}, NCM deve ter 8 dígitos.`);
    const cfop = digits(item.cfop);
    if (cfop.length !== 4) throw new Error(`Solicitação incompleta: item ${codigo}, CFOP deve ter 4 dígitos.`);
    const origem = requiredNumber(item.origem_mercadoria, `item ${codigo}, origem da mercadoria`);
    if (!Number.isInteger(origem) || origem < 0 || origem > 8) {
      throw new Error(`Solicitação incompleta: item ${codigo}, origem deve estar entre 0 e 8.`);
    }
    const unidade = requiredText(item.unidade, `item ${codigo}, unidade comercial`).toUpperCase();
    const unidadeTributavel = requiredText(item.unidade_tributavel, `item ${codigo}, unidade tributável`).toUpperCase();
    const quantidade = requiredNumber(item.quantidade, `item ${codigo}, quantidade`);
    const valorUnitario = requiredNumber(item.valor_unitario, `item ${codigo}, valor unitário`);
    const desconto = requiredNumber(item.valor_desconto, `item ${codigo}, valor do desconto`);
    if (quantidade <= 0) throw new Error(`Solicitação incompleta: item ${codigo}, quantidade deve ser maior que zero.`);
    if (valorUnitario <= 0) throw new Error(`Solicitação incompleta: item ${codigo}, valor unitário deve ser maior que zero.`);
    if (desconto < 0) throw new Error(`Solicitação incompleta: item ${codigo}, desconto não pode ser negativo.`);

    const cstIcms = text(item.cst_icms);
    const csosn = text(item.csosn);
    if ((cstIcms ? 1 : 0) + (csosn ? 1 : 0) !== 1) {
      throw new Error(`Solicitação incompleta: item ${codigo}, informe CST de ICMS ou CSOSN, nunca ambos.`);
    }
    const situacaoIcms = (cstIcms ?? csosn)!;
    // A fixture de IPI por CFOP e tapa-buraco de homologacao para quando ninguem
    // sabe dizer o CST — preenche o que falta, nunca sobrescreve quem sabe. Se o
    // item traz CST (do perfil de operacao ou do cadastro do produto conferido
    // contra f.tipi_ncm), ele manda.
    //
    // Sobrescrever custou a rejeicao 610 da OV-SEG-00007-026 em 10/09/2026: a
    // chave de seguranca (NCM 85365090) saiu com o IPI de 9,75% do cadastro e o
    // CST 53 da fixture — nao tributada com imposto destacado —, e o somatorio da
    // SEFAZ nao fechou.
    const fixtureIpi = ambiente === "HOMOLOGACAO"
      ? tributacaoProvisoria.ipiPorCfop[cfop as keyof typeof tributacaoProvisoria.ipiPorCfop]
      : undefined;
    const cstIpi = text(item.cst_ipi)
      ?? requiredText(fixtureIpi?.cst, `item ${codigo}, CST de IPI do perfil de operação`);
    const enquadramentoIpi = digits(
      text(item.ipi_codigo_enquadramento_legal)
        ?? requiredText(fixtureIpi?.cEnq, `item ${codigo}, cEnq do perfil de operação`),
    );
    if (enquadramentoIpi.length !== 3) {
      throw new Error(`Solicitação incompleta: item ${codigo}, enquadramento legal do IPI deve ter 3 dígitos.`);
    }
    const cEnqValido = cstIpi === "02" || cstIpi === "52"
      ? /^3\d{2}$/.test(enquadramentoIpi)
      : cstIpi === "04" || cstIpi === "54"
      ? /^0\d{2}$/.test(enquadramentoIpi)
      : cstIpi === "05" || cstIpi === "55"
      ? /^1\d{2}$/.test(enquadramentoIpi)
      : /^(60[1-8]|999)$/.test(enquadramentoIpi);
    if (!cEnqValido) {
      throw new Error(`Solicitação incompleta: item ${codigo}, enquadramento legal do IPI incompatível com o CST ${cstIpi}.`);
    }
    const cstPis = requiredText(item.cst_pis, `item ${codigo}, CST de PIS`);
    const cstCofins = requiredText(item.cst_cofins, `item ${codigo}, CST de COFINS`);
    validarCfopIbsCbsTransicao2026(regraIbsCbs, cfop);
    const cstIbsCbs = regraIbsCbs.cst;
    const cclassTrib = regraIbsCbs.cClassTrib;
    const aliquotaIcms = num(item.aliquota_icms);
    const aliquotaIpi = num(item.aliquota_ipi);
    const aliquotaPis = num(item.aliquota_pis);
    const aliquotaCofins = num(item.aliquota_cofins);
    if (impostoTributado(situacaoIcms, ["00", "10", "20", "70", "90", "101", "201", "900"]) && aliquotaIcms === null) {
      throw new Error(`Solicitação incompleta: item ${codigo}, alíquota de ICMS/CSOSN.`);
    }
    if (impostoTributado(cstIpi, ["50", "99"]) && aliquotaIpi === null) {
      throw new Error(`Solicitação incompleta: item ${codigo}, alíquota de IPI.`);
    }
    // Revenda nao destaca IPI. Quem deve IPI e o industrial e quem a ele se equipara
    // (RIPI, Decreto 7.212/2010, art. 9o) — nao quem apenas revende produto de
    // terceiros. Estar a mercadoria tributada na TIPI diz quanto o FABRICANTE paga,
    // nao que o revendedor deva o imposto; foi essa confusao que pos 9,75% na NF-e
    // 2/50 (soft-starter WEG, NCM 9032.89.11, origem nacional) e ainda somou o IPI
    // a base do ICMS, inflando o ICMS em R$ 56,41.
    //
    // A excecao e a equiparacao: importacao direta ou por conta e ordem (art. 9o, I
    // e IX). Ela e declarada item a item no cadastro fiscal, nunca deduzida do NCM
    // ou da origem — origem 1 e indicio, nao prova, e a importacao por conta e ordem
    // pode aparecer com origem 2.
    //
    // Aborta em vez de zerar calado: IPI indevido numa revenda e erro de cadastro, e
    // corrigi-lo por baixo do pano deixaria f.solicitacao_item guardando CST 50 e a
    // tela de conferencia mostrando um imposto que a nota nao tem.
    const ehRevenda = ["5102", "6102"].includes(cfop);
    const equiparadoIndustrial = item.equiparado_industrial === true;
    // A equiparacao acompanha a origem, e as duas tem de concordar. Origem 1 e
    // importacao direta OU por conta e ordem — nos dois casos o CNPJ da Segau consta
    // como adquirente na DI/DUIMP, entao ela e a importadora e se equipara a
    // industrial (RIPI art. 9o, I e IX). Comprar de distribuidor e o que converte a
    // origem 1 da nota de entrada em origem 2 na saida, e ai nao ha equiparacao.
    //
    // A equiparacao NAO muda o CFOP: quem revende sem industrializar sai em
    // 5102/6102 ainda que destaque IPI (Resposta a Consulta SP 22712/2020). O 5101 e
    // so da fabricacao propria. Por isso a autorizacao do destaque e a flag, nunca
    // o CFOP.
    if (origem === 1 && !equiparadoIndustrial) {
      throw new Error(
        `Emissão bloqueada: item ${codigo}, origem 1 (importação direta ou por conta e ordem) `
        + "sem a marca de equiparado a industrial no cadastro fiscal. Se a Segau importou, "
        + "marque a equiparação; se comprou de distribuidor, a origem na saída é 2.",
      );
    }
    if (origem !== 1 && equiparadoIndustrial) {
      throw new Error(
        `Emissão bloqueada: item ${codigo}, marcado como equiparado a industrial mas com `
        + `origem ${origem}. A equiparação vem de ter importado, e importação é origem 1.`,
      );
    }
    if (ehRevenda && !equiparadoIndustrial && (impostoTributado(cstIpi, ["00", "49", "50", "99"]) || (aliquotaIpi ?? 0) > 0)) {
      throw new Error(
        `Emissão bloqueada: item ${codigo}, revenda em CFOP ${cfop} não destaca IPI. `
        + `O cadastro fiscal traz CST ${cstIpi}${aliquotaIpi ? ` e alíquota de ${aliquotaIpi.toFixed(2).replace(".", ",")}%` : ""}, `
        + "mas só o industrial e quem a ele se equipara devem o imposto (RIPI, art. 9º). "
        + "Use CST 53 sem alíquota, ou marque o item como equiparado a industrial "
        + "(importação direta ou por conta e ordem) no cadastro fiscal.",
      );
    }
    if (impostoTributado(cstPis, ["01", "02"]) && aliquotaPis === null) {
      throw new Error(`Solicitação incompleta: item ${codigo}, alíquota de PIS.`);
    }
    if (impostoTributado(cstCofins, ["01", "02"]) && aliquotaCofins === null) {
      throw new Error(`Solicitação incompleta: item ${codigo}, alíquota de COFINS.`);
    }

    const bruto = round(quantidade * valorUnitario);
    if (desconto > bruto) throw new Error(`Solicitação incompleta: item ${codigo}, desconto maior que o valor bruto.`);
    const base = round(bruto - desconto);
    const reducao = requiredNumber(
      item.reducao_base_icms_percentual,
      `item ${codigo}, redução da base de ICMS (informe zero quando não houver)`,
    );
    if (reducao < 0 || reducao > 100) {
      throw new Error(`Solicitação incompleta: item ${codigo}, redução da base de ICMS inválida.`);
    }
    // Par impossivel: so os CST 50 (saida tributada) e 99 (outras saidas) admitem
    // IPI destacado. Em 51, 52, 53, 54 e 55 a saida nao e tributada, e mandar vIPI
    // junto faz o somatorio da SEFAZ nao fechar (rejeicao 610). Melhor recusar aqui,
    // com o motivo, do que descobrir pelo retorno da nota.
    if (aliquotaIpi !== null && aliquotaIpi > 0 && !impostoTributado(cstIpi, ["50", "99"])) {
      throw new Error(
        `Solicitação incompleta: item ${codigo}, CST de IPI ${cstIpi} não é saída tributada `
        + `mas a alíquota é de ${aliquotaIpi.toFixed(2).replace(".", ",")}%. `
        + `Use o CST 50 para destacar o IPI ou zere a alíquota.`,
      );
    }
    const ipiValor = aliquotaIpi === null ? 0 : round(base * aliquotaIpi / 100);
    // Rede final da trava da TIPI: a conferencia ja recusa NCM tributado saindo sem IPI
    // (f.fn_os_nfe_conferir_homologacao), e aqui a nota nao passa nem que a solicitacao
    // tenha sido montada por outro caminho. A aliquota da TIPI vem no item, resolvida
    // pela conferencia a partir de f.tipi_ncm; sem ela, nada a checar.
    const aliquotaTipi = num(item.ipi_tipi_aliquota);
    if (
      aliquotaTipi !== null && aliquotaTipi > 0 && ipiValor === 0
      && ["5101", "6101"].includes(cfop)
    ) {
      throw new Error(
        `Solicitação incompleta: item ${codigo}, NCM ${ncm} é tributado a `
        + `${aliquotaTipi.toFixed(2).replace(".", ",")}% na TIPI e a nota sairia sem IPI `
        + `(CST ${cstIpi}). Corrija o cadastro fiscal do produto.`,
      );
    }
    // O IPI so fica FORA da base do ICMS quando a operacao e entre contribuintes e o
    // produto se destina a industrializacao ou comercializacao (CF art. 155, §2º, XI,
    // reproduzido na LC 87/96, art. 13, §2º). Sao condicoes cumulativas.
    //
    // A regra sai da destinacao declarada, nao de indFinal. Eram equivalentes ate
    // aparecer a manutencao: o comprador e contribuinte (indFinal 0), mas manter o
    // proprio parque nao e industrializar nem revender, entao o IPI integra a base.
    // Lendo por indFinal a nota saia com ICMS a menos — na OS 319, R$ 1.657,50 a cada
    // R$ 100 mil (contabilidade, 10/09/2026).
    const ipiNaBaseIcms = destinacao && ipiIntegraBaseIcms(destinacao, destinatarioContribuinte) ? ipiValor : 0;
    const baseIcms = round((base + ipiNaBaseIcms) * (1 - reducao / 100));
    const icmsValor = aliquotaIcms === null ? null : round(baseIcms * aliquotaIcms / 100);
    // O ICMS destacado sai da base de PIS/COFINS (STF, RE 574.706/PR, Tema 69, com
    // efeitos desde 15/03/2017; nos embargos de 13/05/2021 ficou definido que o valor
    // a excluir e o ICMS DESTACADO na nota, nao o efetivamente recolhido). Sem isso a
    // base ia como o proprio valor da mercadoria — apontado pela contabilidade em
    // 09/09/2026 sobre as NF-e 2/5 a 2/8. Operacao sem ICMS destacado (isenta, nao
    // tributada, ST) mantem a base cheia, porque nao ha o que excluir.
    //
    // O IPI nao entra nesta conta nem para somar nem para subtrair: ele fica fora da
    // receita bruta por forca da Lei 12.973/2014, art. 12, §4º.
    const basePisCofins = round(Math.max(base - (icmsValor ?? 0), 0));
    const pisValor = aliquotaPis === null ? null : round(basePisCofins * aliquotaPis / 100);
    const cofinsValor = aliquotaCofins === null ? null : round(basePisCofins * aliquotaCofins / 100);
    const aliquotaIbsUf = regraIbsCbs.pIBSUF;
    const aliquotaIbsMun = regraIbsCbs.pIBSMun;
    const aliquotaCbs = regraIbsCbs.pCBS;
    // Base do IBS/CBS. O valor da operacao compreende os tributos incidentes
    // (LC 214/2025, art. 12, §1º) e dele saem: o IPI, pelo art. 12, §2º, II; e o ICMS
    // (CF art. 155, II), o ISS (CF art. 156, III) e o PIS/COFINS (CF art. 195, I "b" e
    // IV), pelo art. 12, §2º, V.
    //
    // REGRA GERAL: so se subtrai o tributo que esta DENTRO da base de partida. Aqui a
    // partida e `base` = vProd - vDesc, que nunca conteve o IPI — ele e somado por fora
    // no vNF. Subtrair o IPI daqui tirava 877,50 que nao estavam la (erro corrigido em
    // 09/09/2026, sobre a NF-e 2/33). Partindo do valor da operacao daria no mesmo:
    // 9.877,50 - 877,50 - 1.679,18 - 120,79 - 556,38 = 9.000,00 - 1.679,18 - 120,79 - 556,38.
    //
    // ISS entra como zero porque nota de produto nao o destaca; o termo fica explicito
    // para o dia em que houver documento misto.
    const issValor = 0;
    const baseIbsCbs = ibsCbsSemGrupoDeValores(regraIbsCbs) ? 0 : round(Math.max(
      base - (icmsValor ?? 0) - issValor - (pisValor ?? 0) - (cofinsValor ?? 0),
      0,
    ));
    const calculoIbsCbs = calcularIbsCbsTransicao2026(baseIbsCbs, regraIbsCbs);
    const ibsUfValor = calculoIbsCbs.vIBSUF;
    const ibsMunValor = calculoIbsCbs.vIBSMun;
    const ibsValor = round(ibsUfValor + ibsMunValor);
    const cbsValor = calculoIbsCbs.vCBS;
    // Remessa para conserto: a conferencia grava CST 50 + SC840007, IPI 55, PIS/COFINS 08.
    // Se chegou outra coisa a nota nao sai — nunca se corrige calado.
    if (remessaConserto) {
      const foraDaRemessa = motivoItemForaDaRemessaConserto({
        codigo,
        cfop,
        situacaoIcms,
        aliquotaIcms,
        cbenef: text(item.cbenef),
        cstIpi,
        aliquotaIpi,
        cstPis,
        cstCofins,
      }, remessaConserto);
      if (foraDaRemessa) throw new Error(`Emissão bloqueada: ${foraDaRemessa}.`);
    }
    // Retorno de terceiros: CST 50 + cBenef do retorno, IPI 55 cEnq 108, PIS/COFINS 08, sem
    // desconto — o item e o espelho da nota de origem e nada e destacado.
    if (retornoTerceiros) {
      const foraDoRetorno = motivoItemForaDoRetornoTerceiros({
        codigo,
        cfop,
        situacaoIcms,
        aliquotaIcms,
        cbenef: text(item.cbenef),
        cstIpi,
        cEnqIpi: enquadramentoIpi,
        aliquotaIpi,
        cstPis,
        cstCofins,
        desconto,
      }, retornoTerceiros);
      if (foraDoRetorno) throw new Error(`Emissão bloqueada: ${foraDoRetorno}.`);
    }
    valorProdutos = round(valorProdutos + bruto);
    valorDesconto = round(valorDesconto + desconto);
    valorIpi = round(valorIpi + ipiValor);
    // Valor do item para o "Valor aproximado dos tributos" (Lei 12.741/2012), mais
    // abaixo. Ate 16/09/2026 a frase somava ICMS + IPI da propria nota, como o emissor
    // antigo; agora e federal + estadual da tabela IBPT, e so com indFinal = 1.
    itensIbpt.push({ codigo, ncm, origem, valor: base });
    baseIbsCbsTotal = round(baseIbsCbsTotal + baseIbsCbs);
    // vNFTot da NT 2025.002-RTC v1.30 (pag. 47): soma dos vItem, e vItem NAO leva
    // vIBSUF, vIBSMun, vIBS, vCBS nem vIS em 2025 e 2026 — era exatamente o que estava
    // aqui antes. Dos componentes da formula, este emissor so produz vProd, vDesc e
    // vIPI; ST, desoneracao, monofasico, II e servico nao existem neste fluxo e por
    // isso nao entram na conta. Validacao da SEFAZ: rejeicao 1094.
    vItemTotal = round(vItemTotal + base + ipiValor);
    ibsUfTotal = round(ibsUfTotal + ibsUfValor);
    ibsMunTotal = round(ibsMunTotal + ibsMunValor);
    cbsTotal = round(cbsTotal + cbsValor);
    // Quem decide se o benefício de automação existe é o NCM, não a alíquota.
    // A lista está em RICMS/SC-01, Anexo 2, Art. 7º, VII (8536.49.00,
    // 8536.50.90 e 8544.49.00) e a alínea "a" faculta aplicar 12% direto sobre
    // a base integral desde que a observação conste no documento — então CST 00
    // com 12% é caminho legal para esses NCMs, mas só com o texto. Já o NCM
    // 8537.10.20 não está na lista: ali o 12% vem da Lei 10.297/96 e declarar
    // "base de cálculo reduzida" seria afirmar benefício que não existe.
    // Carga efetiva, não alíquota nominal: CST 20 a 17% com base reduzida em
    // 29,412% resulta nos mesmos 12% de CST 00 a 12% sobre base integral, e são
    // os dois caminhos que o Anexo 2, Art. 7º, VII autoriza.
    const cargaEfetivaIcms = aliquotaIcms === null
      ? null
      : round(aliquotaIcms * (1 - reducao / 100));
    if (cargaEfetivaIcms !== null) aliquotasIcms.add(cargaEfetivaIcms);
    // Com a excecao ativa, item sem SC820006 sai CST 00 a 12% cheios. A conferencia ja
    // grava assim; aqui a nota nao sai se chegou outra coisa — nunca corrige calado.
    const itemNaExcecao = excecaoAliquota12 !== null && itemNaExcecaoAliquota12(item.cbenef);
    if (itemNaExcecao) {
      if (
        situacaoIcms !== EXCECAO_ALIQUOTA_12_DESTINATARIO.cst
        || aliquotaIcms !== EXCECAO_ALIQUOTA_12_DESTINATARIO.aliquota
        || reducao !== 0
        || text(item.cbenef)
      ) {
        throw new Error(
          `Emissão bloqueada: item ${codigo}, com a exceção de ICMS 12% por exigência do destinatário `
          + `o item sem cBenef SC820006 sai com CST 00 a 12% sobre a base integral, e a conferência `
          + `trouxe CST ${situacaoIcms} a ${aliquotaIcms ?? "?"}%${reducao ? ` com redução de ${reducao}%` : ""}`
          + `${text(item.cbenef) ? ` e cBenef ${text(item.cbenef)}` : ""}. Refaça a conferência.`,
        );
      }
      itensExcecaoAliquota12.push(numeroItem);
    }
    // Os dois efeitos da destinacao tem de andar juntos. Item a item, porque a
    // aliquota e a base sao do item — o conflito de destinacao x aliquota, mais
    // abaixo, olha a nota inteira e nao pegaria um item destoante.
    // Na excecao os 12% vem da exigencia do destinatario, nao de a mercadoria seguir em
    // operacao tributada: o IPI continua na base (manutencao) e isso nao e contradicao.
    const conflitoIpiBase = itemNaExcecao || !destinacao ? null : conflitoIpiNaBaseComAliquota(
      destinacao,
      cargaEfetivaIcms,
      ipiNaBaseIcms > 0,
      interestadual,
      ipiValor > 0,
      destinatarioContribuinte,
    );
    if (conflitoIpiBase) {
      throw new Error(`Emissão bloqueada: item ${codigo}, ${conflitoIpiBase}.`);
    }
    // Trava antes de qualquer envio a Focus: CST 20 (ou os 12% da alinea "a") num NCM
    // do Anexo 2, Art. 7º, VII sem cBenef. A conferencia da tela chama a mesma funcao.
    const faltaCbenef = faltaCbenefAutomacaoSc({
      codigo,
      ncm,
      situacaoIcms,
      cargaEfetivaIcms,
      cbenef: text(item.cbenef),
      interestadual,
    });
    if (faltaCbenef) throw new Error(`Emissão bloqueada: ${faltaCbenef}.`);
    if (temReducaoAutomacaoSc(ncm, interestadual) && cargaEfetivaIcms === 12) {
      usaBeneficioReducaoSc = true;
      itensBeneficioReducaoSc.push(numeroItem);
    }
    // Maquina industrial do Convenio 52/91 (NCM 8460.90.90): CST 20, cBenef do convenio e base
    // reduzida ate a carga efetiva de 8,80% (17% interna ou 12% interestadual, nominais).
    // Sem isso a nota nao sai — nem a 12% direto, nem a 17% cheia (contador, 06/09/2026).
    // No retorno de terceiros a maquina volta ao dono com ICMS suspenso: o convenio e da venda.
    if (!retornoTerceiros && temReducaoMaquinas5291(ncm)) {
      const carga = REDUCAO_MAQUINAS_CONVENIO_52_91.cargaEfetiva;
      if (situacaoIcms !== "20" || cargaEfetivaIcms === null || Math.abs(cargaEfetivaIcms - carga) > 0.01 || !text(item.cbenef)) {
        throw new Error(
          `Solicitação incompleta: item ${codigo}, NCM ${ncm} é máquina do Convênio ICMS 52/91 e exige CST 20, `
          + `cBenef do convênio e redução de base para carga efetiva de ${carga.toFixed(2).replace(".", ",")}% `
          + `(${REDUCAO_MAQUINAS_CONVENIO_52_91.baseLegal}). Nota com CST ${situacaoIcms}, carga ${cargaEfetivaIcms ?? "?"}%`
          + `${text(item.cbenef) ? "" : " e sem cBenef"}.`,
        );
      }
      usaBeneficioMaquinas5291 = true;
    }

    return {
      numero_item: numeroItem,
      codigo_produto: codigo,
      descricao: descricao.slice(0, 120),
      codigo_ncm: ncm,
      ...(digits(item.cest).length === 7 ? { cest: digits(item.cest) } : {}),
      ...(text(item.numero_fci) ? { numero_fci: text(item.numero_fci) } : {}),
      cfop,
      unidade_comercial: unidade,
      quantidade_comercial: quantidade,
      valor_unitario_comercial: valorUnitario,
      valor_bruto: bruto,
      ...(desconto > 0 ? { valor_desconto: desconto } : {}),
      unidade_tributavel: unidadeTributavel,
      quantidade_tributavel: quantidade,
      valor_unitario_tributavel: valorUnitario,
      icms_origem: origem,
      icms_situacao_tributaria: situacaoIcms,
      ...(aliquotaIcms !== null ? {
        icms_modalidade_base_calculo: requiredText(item.icms_modalidade_base_calculo, `item ${codigo}, modalidade da base de ICMS`),
        icms_base_calculo: baseIcms,
        ...(reducao > 0 ? { icms_reducao_base_calculo: reducao } : {}),
        icms_aliquota: aliquotaIcms,
        icms_valor: icmsValor,
      } : {}),
      ...(text(item.cbenef) ? { codigo_beneficio_fiscal: text(item.cbenef) } : {}),
      ipi_situacao_tributaria: cstIpi,
      ipi_codigo_enquadramento_legal: enquadramentoIpi,
      ...(aliquotaIpi !== null ? { ipi_base_calculo: base, ipi_aliquota: aliquotaIpi, ipi_valor: ipiValor } : {}),
      pis_situacao_tributaria: cstPis,
      ...(aliquotaPis !== null ? { pis_base_calculo: basePisCofins, pis_aliquota_porcentual: aliquotaPis, pis_valor: pisValor } : {}),
      cofins_situacao_tributaria: cstCofins,
      ...(aliquotaCofins !== null ? { cofins_base_calculo: basePisCofins, cofins_aliquota_porcentual: aliquotaCofins, cofins_valor: cofinsValor } : {}),
      ibs_cbs_situacao_tributaria: cstIbsCbs,
      ibs_cbs_classificacao_tributaria: cclassTrib,
      // CST 410 (remessa): so CST e cClassTrib. Qualquer aliquota, mesmo zerada, faz a Focus
      // montar o gIBSCBS e a SEFAZ recusa (cStat 1021, homologacao da remessa SICK em
      // 16/09/2026). Os portoes de producao conferem CST e cClassTrib nesse caso.
      ...(ibsCbsSemGrupoDeValores(regraIbsCbs) ? {} : {
        ibs_cbs_base_calculo: baseIbsCbs,
        ibs_uf_aliquota: aliquotaIbsUf,
        ibs_uf_valor: ibsUfValor,
        ibs_mun_aliquota: aliquotaIbsMun,
        ibs_mun_valor: ibsMunValor,
        ibs_valor_total: ibsValor,
        cbs_aliquota: aliquotaCbs,
        cbs_valor: cbsValor,
      }),
      // vItem: a mesma conta do vNFTot, item a item. Sai daqui a soma que a rejeicao
      // 1094 confere contra o total — por isso o IPI entra tambem aqui. Enquanto so o
      // total levava o IPI, a NF-e 2/35 (homologacao, OS 287) saiu com vNFTot 21.303,95
      // contra 19.411,34 de soma dos vItem, os 1.892,61 de IPI de diferenca.
      valor_total_item: round(base + ipiValor),
      ...(text(solicitacao.pedido_cliente) ? { pedido_compra: text(solicitacao.pedido_cliente)?.slice(0, 15) } : {}),
    };
  });

  const valorFrete = requiredNumber(operacao.valor_frete, "valor do frete");
  const valorSeguro = requiredNumber(operacao.valor_seguro, "valor do seguro");
  const outrasDespesas = requiredNumber(operacao.valor_outras_despesas, "outras despesas");
  const valorTotal = round(valorProdutos - valorDesconto + valorFrete + valorSeguro + outrasDespesas + valorIpi);

  const referenciaInformada = text(
    contexto.documento?.nfe_referenciada
      ?? operacao.nfe_referenciada
      ?? solicitacao.nfe_referenciada,
  );
  const chaveReferenciada = referenciaInformada ? digits(referenciaInformada) : null;
  if (referenciaInformada && chaveReferenciada?.length !== 44) {
    throw new Error("Solicitação incompleta: chave da NF-e referenciada deve ter 44 dígitos.");
  }
  // O retorno referencia a nota de origem em NFref (refNFe), nao so no texto.
  if (origemRetorno && origemRetorno.chave !== chaveReferenciada) {
    throw new Error("Solicitação incompleta: a chave referenciada do retorno não é a da NF-e de origem.");
  }
  const aliquotaUnica = aliquotasIcms.size === 1 ? [...aliquotasIcms][0] : null;
  // Quando o benefício de automação está em uso, os 12% vêm do produto (saída
  // interna de equipamentos de automação, Anexo 2, Art. 7º, VII) e não da
  // destinação: nesses NCMs a contabilidade lista 12% direto, sem a alternativa
  // de 17%. Só confiro destinação contra alíquota fora desse caso.
  // Com a excecao ativa a divergencia foi confirmada na tela, com OC e evidencia: nao bloqueia.
  const conflito = usaBeneficioReducaoSc || usaBeneficioMaquinas5291 || excecaoAliquota12 || !destinacao
    ? null
    : conflitoDestinacaoAliquota(destinacao, aliquotaUnica, interestadual, destinatarioContribuinte);
  if (conflito) {
    throw new Error(`Solicitação incompleta: ${conflito}. Reveja a destinação ou o perfil fiscal.`);
  }
  // A observacao da solicitacao ficava so no banco e nunca chegava ao infCpl
  // (auditoria da NF-e 2/8). Vai por ultimo, com espacos normalizados, e o
  // conjunto respeita o limite de 5.000 caracteres do campo.
  // O texto automatico da composicao e controle interno e saiu na NF-e 2/1; so
  // observacao escrita por pessoa vai para o cliente. Sao duas variantes, as duas
  // geradas pelo sistema: "Composicao parcial da OV/OS ..." e "Composicao livre da
  // OS ..." (20260901152000_faturamento_os_linhas_livres.sql). A segunda escapou do
  // filtro e foi parar no infCpl da homologacao 2/36 da OS 287.
  const observacaoBruta = text(solicitacao.observacao)?.replace(/\s+/g, " ") ?? null;
  const observacaoSolicitacao = observacaoBruta && !/^Composi[cç][aã]o (parcial|livre) da (OV|OS)\b/i.test(observacaoBruta)
    ? observacaoBruta
    : null;
  // "Valor aproximado dos tributos" (Lei 12.741/2012), na primeira posicao do infCpl,
  // e o vTotTrib (item e total). Decisao do Gabriel em 16/09/2026:
  //
  //   · so com indFinal = 1. Na venda a contribuinte (indFinal = 0) nao ha frase nem
  //     vTotTrib — a NF-e 2/52 (venda 355) saiu com "265,20" ao lado de indFinal 0;
  //   · o valor e federal + estadual da tabela IBPT por NCM (f.ibpt_ncm, carregada
  //     pela Edge Function em contexto.ibpt), nao o ICMS + IPI da nota, que era a
  //     conta do emissor antigo e daqui ate essa data.
  //
  // Continua so em VENDA (Gabriel, 10/09/2026): remessa, retorno e devolucao nao tem
  // preco cobrado do comprador de que esses tributos sejam parte.
  //
  // Sem linha vigente do IBPT para algum NCM, a nota nao leva a frase nem o campo —
  // nunca uma aliquota inventada. Atencao: nesse caso, com indFinal = 1, a Focus
  // preenche o vTotTrib sozinha pela tabela IBPT dela (doc. do campo
  // valor_total_tributos); foi o que aconteceu nas NF-e 2/11 e 2/12.
  const consumidorFinal = requiredNumber(operacao.consumidor_final, "indicador de consumidor final");
  if (excecaoAliquota12 && consumidorFinal !== 1) {
    throw new Error(
      `Emissão bloqueada: a exceção de ICMS 12% por exigência do destinatário mantém indFinal = 1, e a nota está com ${consumidorFinal}.`,
    );
  }
  const tributosAproximados = tributosAproximadosNota({
    consumidorFinal,
    ehVenda: natureza.codigo.startsWith("VENDA_"),
    uf: ufEmitente,
    data: dataCivilSaoPaulo(agora),
    itens: itensIbpt,
    tabela: contexto.ibpt,
  });
  const textoTributosAproximados = tributosAproximados.aplica
    ? fraseTributosAproximados(tributosAproximados)
    : null;
  const itensComTributos = tributosAproximados.aplica
    ? items.map((item, indice) => ({ ...item, valor_total_tributos: tributosAproximados.itens[indice].total }))
    : items;
  const informacoesComplementares = [
    ...(textoTributosAproximados ? [textoTributosAproximados] : []),
    ...(usaBeneficioReducaoSc ? [textoReducaoAutomacaoSc(itensBeneficioReducaoSc, items.length)] : []),
    ...(usaBeneficioMaquinas5291 ? [textoReducaoMaquinas5291()] : []),
    ...(excecaoAliquota12 && itensExcecaoAliquota12.length > 0
      ? [textoExcecaoAliquota12(itensExcecaoAliquota12, excecaoAliquota12.numeroOc, destinacao)]
      : []),
    // Com a excecao o texto dela ja traz a utilizacao informada: repetir "Destinacao
    // informada pelo destinatario" seria dizer a mesma coisa duas vezes (Gabriel, 16/09/2026,
    // revisao da NF-e 2/55).
    ...(remessaConserto ? textosRemessaConserto() : []),
    // O texto do retorno ja traz numero, serie, data e chave da origem; a linha generica da
    // chave referenciada seria repeticao.
    ...(origemRetorno ? [textoRetornoTerceiros(origemRetorno)] : []),
    ...(itensExcecaoAliquota12.length > 0 || !destinacao
      ? []
      : [textoDestinacao(destinacao, aliquotaUnica, interestadual, usaBeneficioReducaoSc || usaBeneficioMaquinas5291)]),
    ...(text(solicitacao.pedido_cliente)
      ? [`Pedido de compra do cliente: ${text(solicitacao.pedido_cliente)}`]
      : []),
    ...(chaveReferenciada && !origemRetorno ? [`Chave da NF-e referenciada: ${chaveReferenciada}`] : []),
    ...(observacaoSolicitacao ? [observacaoSolicitacao] : []),
  ].join(" | ");
  // Com indFinal = 1 e sem valor_total_tributos nosso, a Focus calcula o vTotTrib e ACRESCENTA
  // "Trib. aprox. R$: ... Fonte: IBPT" ao fim do infCpl, separado so por um espaco — na 2/55
  // saiu "Pedido de compra do cliente: 1311953 Trib. aprox.". O " |" no fim mantem o mesmo
  // separador das demais frases. Os 4.998 caracteres deixam lugar para ele no limite de 5.000.
  const focusAcrescentaTributos = consumidorFinal === 1 && !tributosAproximados.aplica;
  const informacoesComplementaresFinal = focusAcrescentaTributos && informacoesComplementares
    ? `${informacoesComplementares.slice(0, 4998)} |`
    : informacoesComplementares.slice(0, 5000);

  const finalidadeEmissao = requiredNumber(operacao.finalidade_emissao, "finalidade da emissão");
  const presencaComprador = requiredNumber(operacao.presenca_comprador, "presença do comprador");
  // indPres 0 ("nao se aplica") e reservado a NF-e complementar ou de ajuste.
  // A 2/8 saiu com 0 numa venda normal; venda a distancia e 9 (nao presencial,
  // outros) e venda no balcao e 1.
  if (presencaComprador === 0 && finalidadeEmissao !== 2 && finalidadeEmissao !== 3) {
    throw new Error(
      "Solicitação incompleta: presença do comprador 0 (não se aplica) só vale para NF-e complementar ou de ajuste. Em venda normal confirme 1 a 5 ou 9.",
    );
  }

  // Grupo YA (pag/detPag). Enquanto nao era enviado, o provedor preenchia o
  // default dele e a nota autorizada saia com tPag 01 — dinheiro — mesmo numa
  // venda a prazo. Conferido no XML da NF-e 2/8. Uma forma por nota atende a
  // operacao atual; detPag aceita varias.
  const pagamento = objetoOpcional(operacao.pagamento, "pagamento");
  const formaPagamento = text(pagamento?.forma);
  if (!formaPagamento) {
    throw new Error("Solicitação incompleta: forma de pagamento (tPag) não confirmada.");
  }
  if (!/^(0[1-5]|1[0-9]|2[0-4]|9[019])$/.test(formaPagamento)) {
    throw new Error(`Solicitação incompleta: forma de pagamento ${formaPagamento} fora da tabela tPag da NF-e.`);
  }
  const indicadorPagamento = requiredNumber(pagamento?.indicador, "indicador de pagamento (à vista ou a prazo)");
  if (indicadorPagamento !== 0 && indicadorPagamento !== 1) {
    throw new Error("Solicitação incompleta: indicador de pagamento deve ser 0 (à vista) ou 1 (a prazo).");
  }
  const descricaoPagamento = text(pagamento?.descricao)?.slice(0, 60);
  if (formaPagamento === "99" && !descricaoPagamento) {
    throw new Error("Solicitação incompleta: descreva a forma de pagamento quando escolher 99 (outros).");
  }
  // tPag 90 (sem pagamento) e o da remessa: vPag 0 e sem indPag, como nas NF-e de
  // remessa de terceiros. Uma venda nao sai sem pagamento.
  const semPagamento = formaPagamento === REMESSA_CONSERTO.formaPagamento;
  if (semPagamento && !remessaConserto && !retornoTerceiros) {
    throw new Error("Solicitação incompleta: forma de pagamento 90 (sem pagamento) só vale para remessa ou retorno de terceiros.");
  }
  if (remessaConserto && !semPagamento) {
    throw new Error(`Solicitação incompleta: remessa para conserto sai sem pagamento (tPag 90), e a conferência trouxe ${formaPagamento}.`);
  }
  if (retornoTerceiros && (formaPagamento !== RETORNO_REMESSA_TERCEIROS.formaPagamento || indicadorPagamento !== 0)) {
    throw new Error(`Solicitação incompleta: retorno de terceiros sai sem pagamento (tPag 90, à vista), e a conferência trouxe ${formaPagamento}.`);
  }

  // Grupo cobr (fatura + duplicatas) para venda a prazo. As parcelas vem do
  // snapshot como "dias apos a emissao"; a data absoluta nasce aqui, na
  // emissao, e o AR usa a mesma regra. Sem parcelas, a NF-e a prazo saia sem
  // duplicatas (NF-e 2/1), diferente do emissor antigo.
  let cobranca: Record<string, unknown> | null = null;
  if (indicadorPagamento === 1) {
    const parcelasBrutas = Array.isArray(pagamento?.parcelas) ? pagamento.parcelas as unknown[] : [];
    if (parcelasBrutas.length === 0) {
      throw new Error("Solicitação incompleta: venda a prazo exige ao menos uma parcela confirmada na conferência.");
    }
    if (parcelasBrutas.length > 24) {
      throw new Error("Solicitação incompleta: no máximo 24 duplicatas por NF-e.");
    }
    const duplicatas = parcelasBrutas.map((bruta, indice) => {
      const parcela = objetoOpcional(bruta, `parcela ${indice + 1}`) ?? {};
      const dias = requiredNumber(parcela.dias, `parcela ${indice + 1}, dias após a emissão`);
      if (!Number.isInteger(dias) || dias < 0 || dias > 3650) {
        throw new Error(`Solicitação incompleta: parcela ${indice + 1} com dias após a emissão inválidos.`);
      }
      const valorInformado = num(parcela.valor);
      const valor = valorInformado === null
        ? (parcelasBrutas.length === 1 ? valorTotal : null)
        : round(valorInformado);
      if (valor === null || valor <= 0) {
        throw new Error(`Solicitação incompleta: parcela ${indice + 1} sem valor.`);
      }
      return {
        numero: String(indice + 1).padStart(3, "0"),
        data_vencimento: dataVencimentoSaoPaulo(agora, dias),
        valor,
      };
    });
    const somaParcelas = round(duplicatas.reduce((acc, d) => acc + d.valor, 0));
    if (Math.abs(somaParcelas - valorTotal) > 0.009) {
      throw new Error(
        `Solicitação incompleta: as parcelas somam R$ ${somaParcelas.toFixed(2)} e a nota vale R$ ${valorTotal.toFixed(2)}.`,
      );
    }
    cobranca = {
      numero_fatura: (text(pagamento?.fatura_numero) ?? String(emissao.referencia_externa ?? "").replace(/^NFE[HP]-/, "")).slice(0, 60),
      valor_original_fatura: valorTotal,
      valor_desconto_fatura: 0,
      valor_liquido_fatura: valorTotal,
      duplicatas,
    };
  }

  const transportador = objetoOpcional(operacao.transportador, "transportador");
  const nomeTransportador = text(transportador?.nome);
  const modalidadeFreteInformada = requiredNumber(operacao.modalidade_frete, "modalidade do frete");
  // Retorno de terceiros: a modalidade e a escolhida na tela (0, 1, 3, 4 ou 9), sem o grupo
  // transportadora e sem rebaixar para 9 (Gabriel, 16/09/2026). Nas demais naturezas, sem
  // transportador a nota sai como 9.
  const modalidadeFrete = nomeTransportador || retornoTerceiros ? modalidadeFreteInformada : 9;
  if (retornoTerceiros && !(RETORNO_REMESSA_TERCEIROS.modalidadesFrete as readonly number[]).includes(modalidadeFrete)) {
    throw new Error(`Solicitação incompleta: modalidade do frete ${modalidadeFrete} não vale para o retorno de terceiros (0, 1, 3, 4 ou 9).`);
  }
  if (nomeTransportador && modalidadeFrete === 9) {
    throw new Error("Solicitação incompleta: transportador informado é incompatível com modalidade 9 (sem transporte).");
  }
  const documentoTransportador = nomeTransportador ? digits(transportador?.documento) : "";
  if (nomeTransportador && documentoTransportador && ![11, 14].includes(documentoTransportador.length)) {
    throw new Error("Solicitação incompleta: CNPJ/CPF do transportador inválido.");
  }

  const volumesInformados = Array.isArray(operacao.volumes) ? operacao.volumes : [];
  // No retorno de terceiros os volumes vem da nota de origem quando ela os tem; sem eles a
  // nota sai sem o grupo vol, que e opcional.
  if (modalidadeFrete !== 9 && volumesInformados.length === 0 && !retornoTerceiros) {
    throw new Error("Solicitação incompleta: informe ao menos um volume quando houver transporte.");
  }
  const volumes = volumesInformados.map((volumeRaw, index) => {
    const volume = objetoOpcional(volumeRaw, `volume ${index + 1}`)!;
    const quantidade = requiredNumber(volume.quantidade, `volume ${index + 1}, quantidade`);
    const pesoLiquido = requiredNumber(volume.peso_liquido, `volume ${index + 1}, peso líquido`);
    const pesoBruto = requiredNumber(volume.peso_bruto, `volume ${index + 1}, peso bruto`);
    if (!Number.isInteger(quantidade) || quantidade <= 0) {
      throw new Error(`Solicitação incompleta: volume ${index + 1}, quantidade deve ser inteira e maior que zero.`);
    }
    if (pesoLiquido < 0 || pesoBruto < 0 || pesoBruto < pesoLiquido) {
      throw new Error(`Solicitação incompleta: volume ${index + 1}, pesos inválidos; o bruto deve ser maior ou igual ao líquido.`);
    }
    // Espécie, marca e numeração são opcionais no grupo vol (X26) da NF-e, e as
    // notas de produção da SEGAU saem sem eles — conferido na NF 3772/série 1,
    // autorizada sob o protocolo 242260375531137. Exigi-los aqui impedia emitir
    // uma nota que a empresa já emite. Enviados só quando preenchidos, para não
    // mandar string vazia no XML.
    const opcional = (valor: unknown) => {
      const texto = typeof valor === "string" ? valor.trim() : "";
      return texto === "" ? undefined : texto.slice(0, 60);
    };
    return {
      quantidade,
      especie: opcional(volume.especie),
      marca: opcional(volume.marca),
      numero: opcional(volume.numero),
      peso_liquido: pesoLiquido,
      peso_bruto: pesoBruto,
    };
  });
  const dataHora = dataHoraNfeSaoPaulo(agora);

  return {
    natureza_operacao: natureza.descricao,
    // Serie decidida em 05/09/2026: a SEGAU emite pelo ERP na serie 2 em
    // producao; a serie 1 fica com o emissor antigo ate o fim das implantacoes.
    // Sem enviar a serie, a Focus numeraria na serie dela e poderia colidir
    // com o outro sistema. O numero continua sob controle da Focus.
    serie: requiredNumber(emitente.serie_nfe, "série da NF-e do emitente"),
    data_emissao: dataHora,
    data_entrada_saida: dataHora,
    tipo_documento: 1,
    local_destino: interestadual ? 2 : 1,
    finalidade_emissao: finalidadeEmissao,
    consumidor_final: consumidorFinal,
    presenca_comprador: presencaComprador,
    cnpj_emitente: digits(requiredText(emitente.cnpj, "CNPJ do emitente")),
    nome_emitente: requiredText(emitente.razao_social, "razão social do emitente"),
    nome_fantasia_emitente: text(emitente.nome_fantasia) ?? undefined,
    logradouro_emitente: requiredText(emitente.logradouro, "logradouro do emitente"),
    numero_emitente: requiredText(emitente.numero, "número do emitente"),
    complemento_emitente: text(emitente.complemento) ?? undefined,
    bairro_emitente: requiredText(emitente.bairro, "bairro do emitente"),
    municipio_emitente: nomeMunicipio(emitente.cidade, "do emitente"),
    codigo_municipio_emitente: digits(requiredText(emitente.codigo_municipio_ibge, "código IBGE do emitente")),
    uf_emitente: ufEmitente,
    cep_emitente: digits(requiredText(emitente.cep, "CEP do emitente")),
    inscricao_estadual_emitente: requiredText(emitente.inscricao_estadual, "IE do emitente"),
    regime_tributario_emitente: requiredNumber(emitente.crt, "CRT do emitente"),
    nome_destinatario: ambiente === "HOMOLOGACAO"
      ? NOME_DESTINATARIO_HOMOLOGACAO
      : requiredText(destinatario.nome, "nome do destinatário"),
    ...documentoDestinatario(destinatario),
    ...(indicadorIe !== "2" && text(destinatario.inscricao_estadual)
      ? { inscricao_estadual_destinatario: text(destinatario.inscricao_estadual) }
      : {}),
    indicador_inscricao_estadual_destinatario: Number(indicadorIe),
    logradouro_destinatario: requiredText(destinatario.logradouro, "logradouro do destinatário"),
    numero_destinatario: requiredText(destinatario.numero_endereco, "número do destinatário"),
    complemento_destinatario: text(destinatario.complemento) ?? undefined,
    bairro_destinatario: requiredText(destinatario.bairro, "bairro do destinatário"),
    municipio_destinatario: nomeMunicipio(destinatario.cidade, "do destinatário"),
    codigo_municipio_destinatario: digits(requiredText(destinatario.codigo_ibge_municipio, "código IBGE do destinatário")),
    uf_destinatario: ufDestinatario,
    cep_destinatario: digits(requiredText(destinatario.cep, "CEP do destinatário")),
    pais_destinatario: "Brasil",
    telefone_destinatario: digits(destinatario.telefone) || undefined,
    valor_frete: valorFrete,
    valor_seguro: valorSeguro,
    valor_desconto: valorDesconto,
    valor_outras_despesas: outrasDespesas,
    valor_produtos: valorProdutos,
    valor_total: valorTotal,
    ibs_cbs_base_calculo: baseIbsCbsTotal,
    ibs_uf_valor_total: ibsUfTotal,
    ibs_mun_valor_total: ibsMunTotal,
    ibs_valor_total: round(ibsUfTotal + ibsMunTotal),
    cbs_valor_total: cbsTotal,
    ibs_cbs_is_valor_total: vItemTotal,
    ...(tributosAproximados.aplica ? { valor_total_tributos: tributosAproximados.total } : {}),
    formas_pagamento: [{
      forma_pagamento: formaPagamento,
      valor_pagamento: semPagamento ? 0 : valorTotal,
      ...(semPagamento ? {} : { indicador_pagamento: indicadorPagamento }),
      ...(descricaoPagamento ? { descricao_pagamento: descricaoPagamento } : {}),
    }],
    ...(cobranca ?? {}),
    modalidade_frete: modalidadeFrete,
    ...(nomeTransportador ? {
      nome_transportador: nomeTransportador.slice(0, 60),
      ...(documentoTransportador.length === 14 ? { cnpj_transportador: documentoTransportador } : {}),
      ...(documentoTransportador.length === 11 ? { cpf_transportador: documentoTransportador } : {}),
      ...(text(transportador?.inscricao_estadual) ? { inscricao_estadual_transportador: text(transportador?.inscricao_estadual) } : {}),
      ...(text(transportador?.endereco) ? { endereco_transportador: text(transportador?.endereco)?.slice(0, 60) } : {}),
      ...(text(transportador?.municipio) ? { municipio_transportador: nomeMunicipio(transportador?.municipio, "do transportador").slice(0, 60) } : {}),
      ...(text(transportador?.uf) ? { uf_transportador: text(transportador?.uf)?.toUpperCase() } : {}),
    } : {}),
    ...(modalidadeFrete !== 9 && volumes.length > 0 ? { volumes } : {}),
    // NFref da nota de origem (refNFe) e a base legal da suspensao em infAdFisco: so no
    // retorno de terceiros. Devolucao continua citando a chave apenas no infCpl.
    // Em HOMOLOGACAO o NFref fica de fora: a chave da origem e de producao e a SEFAZ de
    // homologacao nao a conhece (rejeicao 267 no retorno da WEG, 16/09/2026). A chave
    // continua no infCpl, e a nota real leva o NFref.
    ...(origemRetorno && ambiente === "PRODUCAO" ? { notas_referenciadas: [{ chave_nfe: origemRetorno.chave }] } : {}),
    ...(retornoTerceiros ? { informacoes_adicionais_fisco: RETORNO_REMESSA_TERCEIROS.textoFisco } : {}),
    ...(informacoesComplementaresFinal
      ? { informacoes_adicionais_contribuinte: informacoesComplementaresFinal }
      : {}),
    items: itensComTributos,
  };
}
