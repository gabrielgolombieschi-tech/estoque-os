import { dataHoraNfeSaoPaulo } from "./nfe-payload.ts";

/**
 * Payload da NFS-e Padrao Nacional (Focus, POST /v2/nfsen) a partir do
 * contexto congelado na conferencia (f.fn_os_nfse_conferir_homologacao):
 * emitente_snapshot, destinatario_snapshot, operacao_snapshot.servico e a
 * emissao (serie/numero da DPS reservados pelo ERP).
 *
 * Nomes dos campos conferidos em 05/09/2026 na documentacao da Focus
 * (campos.focusnfe.com.br/nfse_nacional/EmissaoDPSXml.html). Nada aqui e
 * deduzido: o que falta no snapshot vira erro nomeando campo e cadastro.
 */

export type ContextoNfse = {
  emissao: Record<string, unknown>;
  documento?: Record<string, unknown>;
  solicitacao: Record<string, unknown>;
  itens: Array<{ documento_item?: Record<string, unknown> | null; solicitacao_item: Record<string, unknown> }>;
};

type JsonObject = Record<string, unknown>;

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
function requiredText(value: unknown, campo: string, cadastro: string) {
  const normalized = text(value);
  if (!normalized) throw new Error(`NFS-e incompleta: ${campo} (${cadastro}).`);
  return normalized;
}
function requiredNumber(value: unknown, campo: string, cadastro: string) {
  const normalized = num(value);
  if (normalized === null) throw new Error(`NFS-e incompleta: ${campo} (${cadastro}).`);
  return normalized;
}
function snapshot(value: unknown, label: string): JsonObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`NFS-e incompleta: snapshot de ${label} nao foi congelado; salve a conferencia.`);
  }
  return value as JsonObject;
}

export const NOME_TOMADOR_HOMOLOGACAO_NFSE = "NFS-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL";

export const CINDOP_PROVISORIO_HOMOLOGACAO: Record<string, string> = { "07.02": "040101", "14.01": "050103" };
export function codigoIndicadorOperacao(servico: Record<string, unknown>) {
  const explicito = text(servico.codigo_indicador_operacao);
  if (explicito && /^[0-9]{6}$/.test(explicito)) return explicito;
  return CINDOP_PROVISORIO_HOMOLOGACAO[String(servico.item_servico ?? "")] ?? "050103";
}

// tpRetPisCofins: 0 nada retido; 3 PIS/COFINS/CSLL retidos.
export function tipoRetencaoPisCofins(retemPcc: boolean) {
  return retemPcc ? 3 : 0;
}

export function montarPayloadNfse(contexto: ContextoNfse, agora = new Date()) {
  const emissao = contexto.emissao ?? {};
  const solicitacao = contexto.solicitacao ?? {};
  const emitente = snapshot(solicitacao.emitente_snapshot, "emitente");
  const tomador = snapshot(solicitacao.destinatario_snapshot, "tomador");
  const operacao = snapshot(solicitacao.operacao_snapshot, "operacao");
  const servico = snapshot(operacao.servico, "servico");
  const ambiente = String(emissao.ambiente ?? "HOMOLOGACAO");

  const serieDps = requiredNumber(emissao.dps_serie, "serie_dps", "c.empresa_fiscal.serie_dps");
  const numeroDps = requiredNumber(emissao.dps_numero, "numero_dps", "reserva da DPS na preparacao");
  if (serieDps < 1 || serieDps > 49999) throw new Error("NFS-e incompleta: serie_dps fora da faixa da API (1 a 49999).");

  const cnpjPrestador = digits(emitente.cnpj);
  if (cnpjPrestador.length !== 14) throw new Error("NFS-e incompleta: cnpj_prestador (empresa).");
  const municipioEmissora = digits(emitente.codigo_municipio_ibge);
  if (municipioEmissora.length !== 7) throw new Error("NFS-e incompleta: codigo_municipio_emissora (endereco fiscal da empresa).");

  const documentoTomador = digits(tomador.documento);
  const tomadorDoc = documentoTomador.length === 14
    ? { cnpj_tomador: documentoTomador }
    : documentoTomador.length === 11
    ? { cpf_tomador: documentoTomador }
    : (() => { throw new Error("NFS-e incompleta: cnpj_tomador (cadastro fiscal do cliente)."); })();
  const municipioTomador = digits(tomador.codigo_ibge_municipio);
  if (municipioTomador.length !== 7) throw new Error("NFS-e incompleta: codigo_municipio_tomador (cadastro fiscal do cliente).");
  const cepTomador = digits(tomador.cep);
  if (cepTomador.length !== 8) throw new Error("NFS-e incompleta: cep_tomador (cadastro fiscal do cliente).");

  const municipioPrestacao = digits(servico.municipio_prestacao_ibge);
  if (municipioPrestacao.length !== 7) throw new Error("NFS-e incompleta: codigo_municipio_prestacao (conferencia).");
  const codigoTribNac = digits(servico.codigo_tributacao_nacional);
  if (codigoTribNac.length !== 6) throw new Error("NFS-e incompleta: codigo_tributacao_nacional_iss (perfil/fixture).");
  const descricao = requiredText(servico.descricao_servico, "descricao_servico", "conferencia");
  if (descricao.length > 1000) throw new Error("NFS-e incompleta: descricao_servico acima de 1000 caracteres.");
  const valorServico = round(requiredNumber(servico.valor_bruto, "valor_servico", "linhas"));
  if (valorServico <= 0) throw new Error("NFS-e incompleta: valor_servico deve ser maior que zero.");
  requiredNumber(servico.aliquota_iss, "aliquota_iss", "fixture");
  const issRetido = servico.iss_retido === true;
  const retemPcc = servico.retem_pcc === true;
  const retemIrrf = servico.retem_irrf === true;
  const retemInss = servico.retem_inss === true;
  const valorIrrf = round(num(servico.valor_irrf) ?? 0);
  const valorPcc = round(num(servico.valor_pcc) ?? 0);
  const valorInss = round(num(servico.valor_inss) ?? 0);
  const cstIbsCbs = requiredText(servico.cst_ibs_cbs, "ibs_cbs_situacao_tributaria", "fixture");
  const cclassTrib = requiredText(servico.cclass_trib, "ibs_cbs_classificacao_tributaria", "fixture");
  const competencia = requiredText(servico.data_competencia, "data_competencia", "conferencia").slice(0, 10);

  const osNumeros = Array.isArray(servico.os_numeros) ? servico.os_numeros.map((n) => String(n)) : [];
  // cIntContrib: padrao [a-zA-Z0-9]{1,20} (rejeicao real do ambiente nacional em 05/09/2026 com "OS 327").
  const codigoInterno = `OS${osNumeros.map((n) => n.replace(/[^a-zA-Z0-9]/g, "")).join("OS")}`.slice(0, 20) || "OS";
  const pedido = (operacao.pedido && typeof operacao.pedido === "object") ? operacao.pedido as JsonObject : {};
  const pedidoCompra = text(pedido.pedido_cliente);
  const pedidoItem = text(pedido.pedido_item);
  const substituicao = (operacao.substituicao && typeof operacao.substituicao === "object") ? operacao.substituicao as JsonObject : null;
  const chaveSubstituida = text(emissao.chave_nfse_substituida) ?? text(substituicao?.chave);

  const inscricaoMunicipalTomador = municipioTomador === "4209102" ? text(tomador.inscricao_municipal) : null;
  const emailTomador = text(tomador.email);
  const nomeTomador = ambiente === "HOMOLOGACAO"
    ? NOME_TOMADOR_HOMOLOGACAO_NFSE
    : requiredText(tomador.nome, "razao_social_tomador", "cadastro fiscal do cliente");

  const payload: JsonObject = {
    data_emissao: dataHoraNfeSaoPaulo(agora),
    serie_dps: serieDps,
    numero_dps: numeroDps,
    data_competencia: competencia,
    emitente_dps: 1,
    codigo_municipio_emissora: Number(municipioEmissora),
    finalidade_emissao: 0,
    consumidor_final: num(operacao.consumidor_final) === 1 ? 1 : 0,
    indicador_destinatario: 0,

    // Prestador = emitente da DPS: o ambiente nacional recusa nome (E0121) e
    // ignora endereco; as NFS-e reais levam so CNPJ, fone, email e regTrib.
    // A razao social continua exigida no cadastro (snapshot) para o DANFSe.
    cnpj_prestador: cnpjPrestador,
    codigo_opcao_simples_nacional: requiredNumber(emitente.codigo_opcao_simples_nacional, "codigo_opcao_simples_nacional", "c.empresa_fiscal"),
    regime_especial_tributacao: requiredNumber(emitente.regime_especial_tributacao, "regime_especial_tributacao", "c.empresa_fiscal"),

    ...tomadorDoc,
    razao_social_tomador: nomeTomador,
    codigo_municipio_tomador: Number(municipioTomador),
    cep_tomador: cepTomador,
    logradouro_tomador: requiredText(tomador.logradouro, "logradouro_tomador", "cadastro fiscal do cliente"),
    numero_tomador: requiredText(tomador.numero_endereco, "numero_tomador", "cadastro fiscal do cliente"),
    bairro_tomador: requiredText(tomador.bairro, "bairro_tomador", "cadastro fiscal do cliente"),

    codigo_municipio_prestacao: municipioPrestacao,
    codigo_tributacao_nacional_iss: codigoTribNac,
    descricao_servico: descricao,
    codigo_interno_contribuinte: codigoInterno,
    valor_servico: valorServico,
    tributacao_iss: num(servico.tributacao_iss) ?? 1,
    // Aliquota de ISS NAO vai: o ambiente nacional a parametriza para municipio
    // ativo e recusa quando informada por nao optante do Simples (E0617,
    // 05/09/2026). A aliquota da fixture serve so a previa/retencao local.
    tipo_retencao_iss: issRetido ? 2 : 1,

    situacao_tributaria_pis_cofins: text(servico.cst_pis_cofins) ?? "01",
    aliquota_pis: num(servico.aliquota_pis) ?? 0,
    aliquota_cofins: num(servico.aliquota_cofins) ?? 0,
    tipo_retencao_pis_cofins: tipoRetencaoPisCofins(retemPcc),

    // Total aproximado de tributos (Lei 12.741): sem ele a Focus manda
    // indTotTrib, que o ambiente nacional recusa para nao optante (E0713,
    // 05/09/2026). Aproximacao: federais = PIS+COFINS proprios, municipais = ISS.
    // As NFS-e reais usam IBPT (ex.: 13,45% federal); ver pergunta ao contador.
    // Com perfil revisado, os percentuais vem da tabela do perfil (13,45% federal
    // e 4,69/3,64/2,11% municipal nas NFS-e reais); sem perfil, a aproximacao.
    valor_total_tributos_federais: num(servico.tributos_aprox_federal_pct) !== null
      ? round(valorServico * (num(servico.tributos_aprox_federal_pct) as number) / 100)
      : round(valorServico * ((num(servico.aliquota_pis) ?? 0) + (num(servico.aliquota_cofins) ?? 0)) / 100),
    valor_total_tributos_estaduais: 0,
    valor_total_tributos_municipais: num(servico.tributos_aprox_municipal_pct) !== null
      ? round(valorServico * (num(servico.tributos_aprox_municipal_pct) as number) / 100)
      : round(num(servico.valor_iss) ?? 0),
    ibs_cbs_situacao_tributaria: cstIbsCbs,
    ibs_cbs_classificacao_tributaria: cclassTrib,
    // cIndOp e obrigatorio quando o grupo IBS/CBS vai (rejeicao real do ambiente
    // nacional em 05/09/2026: "indDest not expected, expected cIndOp"). Valor
    // provisorio de homologacao lido das NFS-e reais de agosto/2026: 040101 na
    // 07.02 (NFS-e 37) e 050103 na 14.01 (NFS-e 32); os demais itens usam o da
    // 14.01 ate o contador confirmar a tabela "codigo indicador de operacao".
    codigo_indicador_operacao: codigoIndicadorOperacao(servico),
  };

  requiredText(emitente.razao_social, "razao_social_prestador", "empresa");
  // IM do prestador NAO vai: o ambiente nacional rejeita (E0120, 05/09/2026)
  // porque Joinville nao registra informacoes complementares no CNC; as NFS-e
  // reais de agosto/2026 tambem saem sem IM no prestador. O valor continua no
  // cadastro (c.empresa_fiscal) para o dia em que o CNC exigir.
  const telefonePrestador = digits(emitente.telefone);
  if (telefonePrestador.length >= 6) payload.telefone_prestador = telefonePrestador;
  const emailPrestador = text(emitente.email);
  if (emailPrestador) payload.email_prestador = emailPrestador;

  const complementoTomador = text(tomador.complemento);
  if (complementoTomador) payload.complemento_tomador = complementoTomador;
  if (inscricaoMunicipalTomador) payload.inscricao_municipal_tomador = inscricaoMunicipalTomador;
  if (emailTomador) payload.email_tomador = emailTomador;
  const telefoneTomador = digits(tomador.telefone);
  if (telefoneTomador.length >= 6) payload.telefone_tomador = telefoneTomador;

  const codigoTribMun = text(servico.codigo_tributacao_municipal);
  if (codigoTribMun) payload.codigo_tributacao_municipal_iss = codigoTribMun;
  const nbs = digits(servico.codigo_nbs);
  if (nbs.length === 9) payload.codigo_nbs = nbs;
  if (pedidoCompra) {
    payload.pedido_compra = pedidoCompra.slice(0, 60);
    if (pedidoItem) payload.itens_pedido_compra = [{ numero_item_compra: pedidoItem.slice(0, 60) }];
  }
  if (retemIrrf && valorIrrf > 0) payload.valor_irrf = valorIrrf;
  if (retemPcc && valorPcc > 0) payload.valor_csll = valorPcc; // soma PIS+COFINS+CSLL retidos (doc Focus)
  if (retemInss && valorInss > 0) payload.valor_cp = valorInss;

  const informacoes = [
    `OS ${osNumeros.join(", ")}`,
    ambiente === "HOMOLOGACAO" ? "EMITIDA EM HOMOLOGACAO - SEM VALOR FISCAL" : null,
  ].filter(Boolean).join(" | ");
  payload.informacoes_complementares = informacoes.slice(0, 2000);

  if (chaveSubstituida) {
    payload.chave_nfse_substituida = chaveSubstituida;
    payload.codigo_justificativa_substituicao = requiredText(emissao.substituicao_codigo ?? substituicao?.codigo, "codigo_justificativa_substituicao", "substituicao");
    payload.motivo_substituicao = requiredText(emissao.substituicao_motivo ?? substituicao?.motivo, "motivo_substituicao", "substituicao");
  }
  return payload;
}

/**
 * Producao so sai igual a homologacao autorizada. Diferencas aceitas: data de
 * emissao, numero da DPS, nome do tomador (homologacao usa o texto da SEFAZ)
 * e informacoes complementares (que carregam o aviso de homologacao).
 */
export function validarPayloadNfseProducaoContraHomologacao(payloadHomologacao: unknown, payloadProducao: unknown) {
  const limpar = (value: unknown, label: string) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`Emissao em producao bloqueada: ${label} nao e um objeto JSON.`);
    const copia = { ...(value as JsonObject) };
    delete copia.data_emissao; delete copia.numero_dps; delete copia.razao_social_tomador; delete copia.informacoes_complementares;
    return JSON.stringify(Object.fromEntries(Object.entries(copia).sort(([a], [b]) => a.localeCompare(b))));
  };
  const hom = limpar(payloadHomologacao, "payload de homologacao");
  const prod = limpar(payloadProducao, "payload de producao");
  if (hom !== prod) {
    const a = JSON.parse(hom) as JsonObject; const b = JSON.parse(prod) as JsonObject;
    const campo = [...new Set([...Object.keys(a), ...Object.keys(b)])].find((k) => JSON.stringify(a[k]) !== JSON.stringify(b[k])) ?? "?";
    throw new Error(`Emissao em producao bloqueada: o payload diverge da homologacao autorizada no campo ${campo}.`);
  }
  if (String((payloadProducao as JsonObject).razao_social_tomador ?? "") === NOME_TOMADOR_HOMOLOGACAO_NFSE) {
    throw new Error("Emissao em producao bloqueada: o tomador real nao foi informado.");
  }
}

export function valorLiquidoNfse(servico: JsonObject) {
  const bruto = num(servico.valor_bruto) ?? 0;
  const iss = servico.iss_retido === true ? (num(servico.valor_iss) ?? 0) : 0;
  return round(bruto - iss - (num(servico.valor_irrf) ?? 0) - (num(servico.valor_pcc) ?? 0) - (num(servico.valor_inss) ?? 0));
}
