/**
 * DIR do Siscomex Remessa (remessa expressa por courier): leitura do XML na tela e conta da
 * NF-e de entrada. O banco (f.fn_importacao_remessa_ler_dir / _criar) le e valida de novo; aqui
 * e so para a tela pre-preencher, calcular e mostrar a previa antes de gravar.
 *
 * Raiz xml1702, namespace http://www.siscomex.gov.br/remessa/v1, um manifesto com uma remessa.
 * Sem DOMParser: o XML e simples (sem atributos relevantes) e o mesmo leitor roda no navegador e
 * nos testes em Node.
 */

export const DIR_NAMESPACE = "http://www.siscomex.gov.br/remessa/v1";

export type DirMercadoria = {
  sequencia: string;
  regimeTributacao: string | null;
  valorUsd: number;
  moeda: string | null;
  unidadeSiscomex: string | null;
  quantidade: number;
  peso: number | null;
  descricao: string;
};

export type DirRemessa = {
  manifesto: { numero: string | null; dataHora: string | null; uaEntrada: string; paisOrigem: string | null };
  courier: { nome: string | null; cnpj: string | null };
  awb: string;
  master: string | null;
  destinacaoComercial: string | null;
  volumes: number | null;
  peso: number | null;
  descricao: string;
  valorUsd: number;
  valorBrl: number;
  freteUsd: number;
  freteBrl: number;
  freteModo: string | null;
  tributavelUsd: number | null;
  tributavelBrl: number;
  multasBrl: number;
  situacao: string;
  cambio: number;
  dir: { numero: string; lote: string | null; dataRegistro: string | null; versao: string | null };
  destinatario: { documento: string; tipoDocumento: string | null; nome: string | null; logradouro: string | null; cep: string | null; uf: string | null };
  remetente: { nome: string | null; logradouro: string | null; complemento: string | null; uf: string | null; paisCodigo: string | null };
  ii: { devido: number | null; pendente: number; recolhido: number | null };
  mercadorias: DirMercadoria[];
};

function escapeTag(tag: string) {
  return tag.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Texto do primeiro <tag>...</tag> dentro de xml: null se ausente; "" quando <tag /> (vazio).
 * O <tag /> conta como encontrado para nao pular para um <tag> aninhado mais adiante
 * (a remessa tem <numero /> e, dentro dela, <dir><numero>).
 */
export function bloco(xml: string, tag: string): string | null {
  const t = escapeTag(tag);
  const re = new RegExp(`<${t}(?:\\s[^>]*?)?(?:/>|>([\\s\\S]*?)</${t}>)`);
  const m = re.exec(xml);
  if (!m) return null;
  return m[1] ?? "";
}

/** Todos os <tag>...</tag> de primeiro nivel (nao aninhados) dentro de xml. */
export function blocos(xml: string, tag: string): string[] {
  const t = escapeTag(tag);
  const re = new RegExp(`<${t}(?:\\s[^>]*?)?(?:/>|>([\\s\\S]*?)</${t}>)`, "g");
  const saida: string[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) saida.push(m[1] ?? "");
  return saida;
}

function decodeEntities(texto: string) {
  return texto
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

function texto(xml: string | null, tag: string): string | null {
  if (xml === null) return null;
  const v = bloco(xml, tag);
  if (v === null) return null;
  const limpo = decodeEntities(v).replace(/\s+/g, " ").trim();
  return limpo === "" ? null : limpo;
}

function numero(xml: string | null, tag: string): number | null {
  const v = texto(xml, tag);
  if (v === null) return null;
  const n = Number(v.replace(",", "."));
  return Number.isFinite(n) ? n : null;
}

function digitos(valor: string | null) {
  return String(valor ?? "").replace(/\D/g, "");
}

export class DirInvalida extends Error {}

/** Le a DIR. Lanca DirInvalida quando o arquivo nao e uma DIR de uma remessa. */
export function lerDirRemessa(xmlBruto: string): DirRemessa {
  const xml = String(xmlBruto ?? "").replace(/^﻿/, "");
  if (!/<xml1702[\s>]/.test(xml)) {
    throw new DirInvalida("O arquivo não é uma DIR do Siscomex Remessa (raiz xml1702).");
  }
  if (!xml.includes(DIR_NAMESPACE)) {
    throw new DirInvalida(`O arquivo não traz o namespace ${DIR_NAMESPACE}.`);
  }
  const manifestos = blocos(xml, "manifesto");
  if (manifestos.length !== 1) {
    throw new DirInvalida(manifestos.length === 0 ? "A DIR não traz manifesto." : `A DIR traz ${manifestos.length} manifestos; envie a DIR de uma remessa só.`);
  }
  const manifesto = manifestos[0];
  const remessas = blocos(bloco(manifesto, "remessas") ?? "", "remessa");
  if (remessas.length !== 1) {
    throw new DirInvalida(remessas.length === 0 ? "A DIR não traz remessa." : `A DIR traz ${remessas.length} remessas; envie a DIR de uma remessa só.`);
  }
  const remessa = remessas[0];
  const dir = bloco(remessa, "dir");
  const destinatario = bloco(remessa, "destinatario");
  const remetente = bloco(remessa, "remetente");
  const ii = bloco(remessa, "ii");
  const mercadorias = blocos(bloco(remessa, "mercadorias") ?? "", "mercadoria").map((m) => ({
    sequencia: texto(m, "sequencia") ?? "",
    regimeTributacao: texto(m, "regimeTributacao"),
    valorUsd: numero(m, "valor") ?? 0,
    moeda: texto(m, "moeda"),
    unidadeSiscomex: texto(m, "unidade"),
    quantidade: numero(m, "quantidade") ?? 0,
    peso: numero(m, "peso"),
    descricao: texto(m, "descricao") ?? "",
  }));
  const awb = texto(remessa, "numero");
  const dirNumero = digitos(texto(dir, "numero"));
  const tributavelBrl = numero(remessa, "valorTributavelReal");
  const cambio = numero(remessa, "txCambioDtRegistro");
  if (!awb) throw new DirInvalida("A DIR não traz o número da remessa (AWB).");
  return {
    manifesto: {
      numero: texto(manifesto, "numero"),
      dataHora: texto(manifesto, "dataHoraManifesto"),
      uaEntrada: digitos(texto(manifesto, "uaEntrada")).padStart(7, "0"),
      paisOrigem: texto(manifesto, "paisOrigem"),
    },
    courier: { nome: texto(manifesto, "nomeEmpresa"), cnpj: digitos(texto(manifesto, "cnpj")) || null },
    awb,
    master: texto(remessa, "master"),
    destinacaoComercial: texto(remessa, "destinacaoComercial"),
    volumes: numero(remessa, "volumes"),
    peso: numero(remessa, "peso"),
    descricao: texto(remessa, "descricao") ?? "",
    valorUsd: numero(remessa, "valorRemessaDolar") ?? 0,
    valorBrl: numero(remessa, "valorRemessaReal") ?? 0,
    freteUsd: numero(remessa, "freteDolar") ?? 0,
    freteBrl: numero(remessa, "freteReal") ?? 0,
    freteModo: texto(remessa, "freteModoPagto"),
    tributavelUsd: numero(remessa, "valorTributavelDolar"),
    tributavelBrl: tributavelBrl ?? 0,
    multasBrl: numero(remessa, "valorMultasReal") ?? 0,
    situacao: texto(remessa, "situacao") ?? "",
    cambio: cambio ?? 0,
    dir: {
      numero: dirNumero,
      lote: texto(dir, "numeroLote"),
      dataRegistro: texto(dir, "dataRegistro"),
      versao: texto(dir, "versaoDIR"),
    },
    destinatario: {
      documento: digitos(texto(destinatario, "documento")),
      tipoDocumento: texto(destinatario, "tipoDocumento"),
      nome: texto(destinatario, "nome"),
      logradouro: texto(bloco(destinatario ?? "", "endereco"), "logradouro"),
      cep: texto(bloco(destinatario ?? "", "endereco"), "cep"),
      uf: texto(bloco(destinatario ?? "", "endereco"), "estado"),
    },
    remetente: {
      nome: texto(remetente, "nome"),
      logradouro: texto(bloco(remetente ?? "", "endereco"), "logradouro"),
      complemento: texto(bloco(remetente ?? "", "endereco"), "complemento"),
      uf: texto(bloco(remetente ?? "", "endereco"), "estado"),
      paisCodigo: texto(bloco(remetente ?? "", "endereco"), "pais"),
    },
    ii: {
      devido: numero(ii, "valorDevido"),
      pendente: numero(ii, "valorPendente") ?? 0,
      recolhido: numero(ii, "valorRecolhido"),
    },
    mercadorias,
  };
}

/** Bloqueios da DIR na tela (o banco repete a conta e e quem decide). */
export function bloqueiosDaDir(dir: DirRemessa, cnpjEmpresa: string): string[] {
  const bloqueios: string[] = [];
  const cnpj = digitos(cnpjEmpresa);
  if (!dir.dir.numero) bloqueios.push("A DIR não traz o número (dir/numero).");
  if (dir.destinatario.documento !== cnpj) {
    bloqueios.push(`O destinatário da DIR (CNPJ ${dir.destinatario.documento || "?"}) não é a empresa emitente (CNPJ ${cnpj || "?"}).`);
  }
  if (dir.situacao !== "25") bloqueios.push(`A remessa está na situação ${dir.situacao || "?"}; só a situação 25 (desembaraçada) pode gerar a nota de entrada.`);
  if (dir.ii.pendente !== 0) bloqueios.push(`Há II pendente de R$ ${formatarBrl(dir.ii.pendente)} na DIR; a nota só sai com o imposto recolhido.`);
  if (dir.mercadorias.length === 0) bloqueios.push("A DIR não traz mercadorias.");
  if (dir.tributavelBrl <= 0) bloqueios.push("A DIR não traz o valor tributável em reais (valor aduaneiro).");
  return bloqueios;
}

export function round2(valor: number) {
  return Math.round((valor + Number.EPSILON) * 100) / 100;
}

export function formatarBrl(valor: number) {
  return valor.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

export type CalculoImportacao = {
  valorAduaneiro: number;
  ii: number;
  aliquotaIcms: number;
  bcIcms: number;
  icms: number;
  outrasDespesas: number;
  valorNota: number;
  gnre: number | null;
  diferencaGnre: number | null;
  gnreConfere: boolean;
};

/**
 * vProd = valor aduaneiro (valor tributavel da DIR); II = o da DIR; BC ICMS = (vProd + II) / (1 - aliquota);
 * ICMS = BC x aliquota; vOutro = ICMS; vNF = vProd + II + vOutro. Diferenca com a GNRE acima de
 * R$ 0,05 bloqueia. Com varios itens o banco calcula o ICMS item a item e o total pode andar centavos.
 */
export function calcularImportacao(entrada: { valorAduaneiro: number; ii: number; aliquotaIcms: number; gnre?: number | null }): CalculoImportacao {
  const valorAduaneiro = round2(entrada.valorAduaneiro);
  const ii = round2(entrada.ii);
  const aliquotaIcms = entrada.aliquotaIcms;
  if (!(aliquotaIcms >= 0 && aliquotaIcms < 100)) throw new Error("Alíquota do ICMS deve estar entre 0 e 100.");
  const bcIcms = round2((valorAduaneiro + ii) / (1 - aliquotaIcms / 100));
  const icms = round2(bcIcms * aliquotaIcms / 100);
  const valorNota = round2(valorAduaneiro + ii + icms);
  const gnre = entrada.gnre === null || entrada.gnre === undefined || !Number.isFinite(entrada.gnre) ? null : round2(entrada.gnre);
  const diferencaGnre = gnre === null ? null : round2(Math.abs(icms - gnre));
  return { valorAduaneiro, ii, aliquotaIcms, bcIcms, icms, outrasDespesas: icms, valorNota, gnre, diferencaGnre, gnreConfere: gnre !== null && diferencaGnre !== null && diferencaGnre <= 0.05 };
}

/** Custo unitario do item para o estoque: vProd + II + despesas do courier; ICMS so nos perfis sem credito. */
export function custoImportacao(entrada: { valorAduaneiro: number; ii: number; icms: number; courier: number; creditoIcms: boolean; quantidade: number }) {
  const total = round2(entrada.valorAduaneiro + entrada.ii + entrada.courier + (entrada.creditoIcms ? 0 : entrada.icms));
  return { total, unitario: entrada.quantidade > 0 ? Math.round((total / entrada.quantidade) * 1e6) / 1e6 : 0 };
}

export const CFOPS_IMPORTACAO: Array<{ cfop: string; natureza: string; rotulo: string; consumidorFinal: 0 | 1; creditoIcms: boolean }> = [
  { cfop: "3101", natureza: "IMPORTACAO_INDUSTRIALIZACAO", rotulo: "3101 · Compra para industrialização (com crédito de ICMS)", consumidorFinal: 0, creditoIcms: true },
  { cfop: "3102", natureza: "IMPORTACAO_COMERCIALIZACAO", rotulo: "3102 · Compra para comercialização / revenda (com crédito de ICMS)", consumidorFinal: 0, creditoIcms: true },
  { cfop: "3556", natureza: "IMPORTACAO_CONSUMO", rotulo: "3556 · Compra de material para uso ou consumo (ICMS no custo)", consumidorFinal: 1, creditoIcms: false },
  { cfop: "3551", natureza: "IMPORTACAO_ATIVO", rotulo: "3551 · Compra de bem para o ativo imobilizado (ICMS no custo)", consumidorFinal: 1, creditoIcms: false },
];

export const VIAS_TRANSPORTE: Array<[number, string]> = [
  [1, "1 · Marítima"], [2, "2 · Fluvial"], [3, "3 · Lacustre"], [4, "4 · Aérea"], [5, "5 · Postal"], [6, "6 · Ferroviária"],
  [7, "7 · Rodoviária"], [8, "8 · Conduto / rede de transmissão"], [9, "9 · Meios próprios"], [10, "10 · Entrada / saída ficta"],
  [11, "11 · Courier"], [12, "12 · Em mãos"], [13, "13 · Por reboque"],
];

/** Unidades da RFB por onde a Segau recebe courier (uaEntrada da DIR -> local e UF do desembaraco). */
export const UNIDADES_RFB: Record<string, { local: string; uf: string }> = {
  "0817700": { local: "AEROPORTO INTERNACIONAL DE VIRACOPOS - CAMPINAS", uf: "SP" },
  "0817600": { local: "AEROPORTO INTERNACIONAL DE SAO PAULO - GUARULHOS", uf: "SP" },
  "0717600": { local: "AEROPORTO INTERNACIONAL DO RIO DE JANEIRO - GALEAO", uf: "RJ" },
};

/** Codigos BACEN de pais mais comuns nas remessas (cPais/xPais da NF-e). */
export const PAISES_BACEN: Array<[string, string]> = [
  ["1600", "CHINA"], ["2496", "ESTADOS UNIDOS"], ["0230", "ALEMANHA"], ["3999", "JAPAO"], ["1902", "COREIA DO SUL"], ["1619", "TAIWAN (FORMOSA)"],
  ["3867", "ITALIA"], ["6289", "REINO UNIDO"], ["2755", "FRANCA"], ["5738", "PAISES BAIXOS (HOLANDA)"], ["3514", "HONG KONG"], ["7412", "SINGAPURA"],
];

/** Pais da DIR (codigo do Siscomex) -> codigo BACEN da NF-e, para pre-preencher o exportador. */
export const PAIS_SISCOMEX_PARA_BACEN: Record<string, string> = {
  "160": "1600", "249": "2496", "023": "0230", "399": "3999", "190": "1902", "161": "1619",
  "386": "3867", "628": "6289", "275": "2755", "573": "5738", "351": "3514", "741": "7412",
};
