import { tributacaoProvisoria } from "./tributacao-provisoria.ts";
import {
  conflitoDestinacaoAliquota,
  ehDestinacaoValida,
  REDUCAO_AUTOMACAO_SC,
  temReducaoAutomacaoSc,
  textoDestinacao,
  textoReducaoAutomacaoSc,
  type DestinacaoMercadoria,
} from "./fiscal/icms-sc-destinacao.ts";
import {
  calcularIbsCbsTransicao2026,
  resolverIbsCbsTransicao2026,
  validarCfopIbsCbsTransicao2026,
} from "./fiscal/ibs-cbs-transicao-2026.ts";

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
  if (!["1", "2", "9"].includes(indicadorIe)) {
    throw new Error("Solicitação incompleta: indicador de IE do destinatário deve ser 1, 2 ou 9.");
  }
  if (!Array.isArray(contexto.itens) || contexto.itens.length === 0) {
    throw new Error("Solicitação incompleta: não há itens para emitir.");
  }

  // Destinação declarada pelo destinatário: é ela que decide a alíquota interna
  // de SC, e o cliente confere o destaque contra a utilização que informou na
  // OC. Sem ela a nota sai com alíquota que ninguém confirmou.
  const destinacaoInformada = text(operacao.destinacao_mercadoria);
  if (!destinacaoInformada) {
    throw new Error("Solicitação incompleta: destinação da mercadoria não confirmada.");
  }
  if (!ehDestinacaoValida(destinacaoInformada)) {
    throw new Error(`Solicitação incompleta: destinação da mercadoria ${destinacaoInformada} desconhecida.`);
  }
  const destinacao: DestinacaoMercadoria = destinacaoInformada;

  let valorProdutos = 0;
  let valorDesconto = 0;
  let valorIpi = 0;
  let baseIbsCbsTotal = 0;
  let ibsUfTotal = 0;
  let ibsMunTotal = 0;
  let cbsTotal = 0;
  let usaBeneficioReducaoSc = false;
  // Só cito a base legal da alíquota quando a nota inteira usa uma única
  // alíquota; com itens em alíquotas diferentes, a citação apontaria para a
  // errada em metade das linhas.
  const aliquotasIcms = new Set<number>();
  const items = contexto.itens.map((linha, index) => {
    const item = linha.solicitacao_item;
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
    const fixtureIpi = ambiente === "HOMOLOGACAO"
      ? tributacaoProvisoria.ipiPorCfop[cfop as keyof typeof tributacaoProvisoria.ipiPorCfop]
      : undefined;
    const cstIpi = fixtureIpi?.cst ?? requiredText(item.cst_ipi, `item ${codigo}, CST de IPI do perfil de operação`);
    const enquadramentoIpi = digits(
      fixtureIpi?.cEnq
        ?? requiredText(item.ipi_codigo_enquadramento_legal, `item ${codigo}, cEnq do perfil de operação`),
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
    const ipiValor = aliquotaIpi === null ? 0 : round(base * aliquotaIpi / 100);
    // Consumidor final (indFinal = 1, uso/consumo ou ativo): o IPI integra a base
    // do ICMS (LC 87/96 art. 13 §2 a contrario; RICMS/SC art. 22 §1). NF-e 3766
    // real: 69.232,80 + IPI 6.750,20 = base 75.983,00 x 17% = 12.917,11. Para
    // revenda/industrializacao (indFinal = 0) o IPI fica fora da base.
    const ipiNaBaseIcms = num(operacao.consumidor_final) === 1 ? ipiValor : 0;
    const baseIcms = round((base + ipiNaBaseIcms) * (1 - reducao / 100));
    const icmsValor = aliquotaIcms === null ? null : round(baseIcms * aliquotaIcms / 100);
    const pisValor = aliquotaPis === null ? null : round(base * aliquotaPis / 100);
    const cofinsValor = aliquotaCofins === null ? null : round(base * aliquotaCofins / 100);
    const aliquotaIbsUf = regraIbsCbs.pIBSUF;
    const aliquotaIbsMun = regraIbsCbs.pIBSMun;
    const aliquotaCbs = regraIbsCbs.pCBS;
    const calculoIbsCbs = calcularIbsCbsTransicao2026(base, regraIbsCbs);
    const ibsUfValor = calculoIbsCbs.vIBSUF;
    const ibsMunValor = calculoIbsCbs.vIBSMun;
    const ibsValor = round(ibsUfValor + ibsMunValor);
    const cbsValor = calculoIbsCbs.vCBS;
    valorProdutos = round(valorProdutos + bruto);
    valorDesconto = round(valorDesconto + desconto);
    valorIpi = round(valorIpi + ipiValor);
    baseIbsCbsTotal = round(baseIbsCbsTotal + base);
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
    if (temReducaoAutomacaoSc(ncm, interestadual) && cargaEfetivaIcms === 12) {
      usaBeneficioReducaoSc = true;
      if (!text(item.cbenef)) {
        throw new Error(
          `Solicitação incompleta: item ${codigo}, NCM ${ncm} tem redução de base do Anexo 2, `
          + `Art. 7º, VII e exige o cBenef ${REDUCAO_AUTOMACAO_SC.cbenef} — a SEFAZ rejeita `
          + "benefício de ICMS sem código desde 03/02/2025.",
        );
      }
    }

    return {
      numero_item: index + 1,
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
      ...(aliquotaPis !== null ? { pis_base_calculo: base, pis_aliquota_porcentual: aliquotaPis, pis_valor: pisValor } : {}),
      cofins_situacao_tributaria: cstCofins,
      ...(aliquotaCofins !== null ? { cofins_base_calculo: base, cofins_aliquota_porcentual: aliquotaCofins, cofins_valor: cofinsValor } : {}),
      ibs_cbs_situacao_tributaria: cstIbsCbs,
      ibs_cbs_classificacao_tributaria: cclassTrib,
      ibs_cbs_base_calculo: base,
      ibs_uf_aliquota: aliquotaIbsUf,
      ibs_uf_valor: ibsUfValor,
      ibs_mun_aliquota: aliquotaIbsMun,
      ibs_mun_valor: ibsMunValor,
      ibs_valor_total: ibsValor,
      cbs_aliquota: aliquotaCbs,
      cbs_valor: cbsValor,
      valor_total_item: base,
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
  const aliquotaUnica = aliquotasIcms.size === 1 ? [...aliquotasIcms][0] : null;
  // Quando o benefício de automação está em uso, os 12% vêm do produto (saída
  // interna de equipamentos de automação, Anexo 2, Art. 7º, VII) e não da
  // destinação: nesses NCMs a contabilidade lista 12% direto, sem a alternativa
  // de 17%. Só confiro destinação contra alíquota fora desse caso.
  const conflito = usaBeneficioReducaoSc
    ? null
    : conflitoDestinacaoAliquota(destinacao, aliquotaUnica, interestadual);
  if (conflito) {
    throw new Error(`Solicitação incompleta: ${conflito}. Reveja a destinação ou o perfil fiscal.`);
  }
  // A observacao da solicitacao ficava so no banco e nunca chegava ao infCpl
  // (auditoria da NF-e 2/8). Vai por ultimo, com espacos normalizados, e o
  // conjunto respeita o limite de 5.000 caracteres do campo.
  // O texto automatico da composicao ("Composicao parcial da OV ...") e
  // controle interno e saiu na NF-e 2/1; so observacao escrita por pessoa
  // vai para o cliente.
  const observacaoBruta = text(solicitacao.observacao)?.replace(/\s+/g, " ") ?? null;
  const observacaoSolicitacao = observacaoBruta && !/^Composi[cç][aã]o parcial da (OV|OS)\b/i.test(observacaoBruta)
    ? observacaoBruta
    : null;
  const informacoesComplementares = [
    ...(usaBeneficioReducaoSc ? [textoReducaoAutomacaoSc()] : []),
    textoDestinacao(destinacao, aliquotaUnica, interestadual),
    ...(text(solicitacao.pedido_cliente)
      ? [`Pedido de compra do cliente: ${text(solicitacao.pedido_cliente)}`]
      : []),
    ...(chaveReferenciada ? [`Chave da NF-e referenciada: ${chaveReferenciada}`] : []),
    ...(observacaoSolicitacao ? [observacaoSolicitacao] : []),
  ].join(" | ").slice(0, 5000);

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
  const modalidadeFrete = nomeTransportador ? modalidadeFreteInformada : 9;
  if (nomeTransportador && modalidadeFrete === 9) {
    throw new Error("Solicitação incompleta: transportador informado é incompatível com modalidade 9 (sem transporte).");
  }
  const documentoTransportador = nomeTransportador ? digits(transportador?.documento) : "";
  if (nomeTransportador && documentoTransportador && ![11, 14].includes(documentoTransportador.length)) {
    throw new Error("Solicitação incompleta: CNPJ/CPF do transportador inválido.");
  }

  const volumesInformados = Array.isArray(operacao.volumes) ? operacao.volumes : [];
  if (modalidadeFrete !== 9 && volumesInformados.length === 0) {
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
    consumidor_final: requiredNumber(operacao.consumidor_final, "indicador de consumidor final"),
    presenca_comprador: presencaComprador,
    cnpj_emitente: digits(requiredText(emitente.cnpj, "CNPJ do emitente")),
    nome_emitente: requiredText(emitente.razao_social, "razão social do emitente"),
    nome_fantasia_emitente: text(emitente.nome_fantasia) ?? undefined,
    logradouro_emitente: requiredText(emitente.logradouro, "logradouro do emitente"),
    numero_emitente: requiredText(emitente.numero, "número do emitente"),
    complemento_emitente: text(emitente.complemento) ?? undefined,
    bairro_emitente: requiredText(emitente.bairro, "bairro do emitente"),
    municipio_emitente: requiredText(emitente.cidade, "município do emitente"),
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
    municipio_destinatario: requiredText(destinatario.cidade, "município do destinatário"),
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
    ibs_cbs_is_valor_total: round(ibsUfTotal + ibsMunTotal + cbsTotal),
    formas_pagamento: [{
      forma_pagamento: formaPagamento,
      valor_pagamento: valorTotal,
      indicador_pagamento: indicadorPagamento,
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
      ...(text(transportador?.municipio) ? { municipio_transportador: text(transportador?.municipio)?.slice(0, 60) } : {}),
      ...(text(transportador?.uf) ? { uf_transportador: text(transportador?.uf)?.toUpperCase() } : {}),
    } : {}),
    ...(modalidadeFrete !== 9 && volumes.length > 0 ? { volumes } : {}),
    ...(informacoesComplementares
      ? { informacoes_adicionais_contribuinte: informacoesComplementares }
      : {}),
    items,
  };
}
