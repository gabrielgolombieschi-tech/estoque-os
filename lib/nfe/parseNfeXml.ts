"use client";

import { parseDecimalBR } from "@/lib/decimal";

export type ParsedItem = {
  codigo: string;
  nome: string;
  quantidade: number;
  valorUnit: number;
  valorProd: number;
  total: number;
  vIcms: number;
  vIpi: number;
  vPis: number;
  vCofins: number;
  vSt: number;
  vFrete: number;
  vDesc: number;
  vOutro: number;
  vSeguro: number;
  overrideNome?: string;
  fornecedorId?: number | null;
  ncm?: string | null;
  cfop?: string | null;
  aliquotaIcms?: number | null;
  aliquotaIpi?: number | null;
  aliquotaPis?: number | null;
  aliquotaCofins?: number | null;
};

export type ParsedNfe = {
  chave: string | null;
  numero: string | null;
  serie: string | null;
  emitente: string | null;
  dataEmissao: string | null;
  cnpjEmitente: string | null;
  destinatario: string | null;
  documentoDestinatario: string | null;
  inscricaoEstadualDestinatario: string | null;
  emailDestinatario: string | null;
  endDestCep: string | null;
  endDestLogradouro: string | null;
  endDestNumero: string | null;
  endDestComplemento: string | null;
  endDestBairro: string | null;
  endDestCidade: string | null;
  endDestUf: string | null;
  endDestPais: string | null;
  valorProdutos: number;
  valorFrete: number;
  valorSeguro: number;
  valorDesconto: number;
  valorOutros: number;
  valorTotal: number;
  parcelas?: Array<{ numero: string; vencimento: string; valor: number }>;
};

function toDateOnly(value: string | null | undefined): string | null {
  const v = (value ?? "").trim();
  if (!v) return null;
  if (/^\d{4}-\d{2}-\d{2}/.test(v)) return v.slice(0, 10);
  return null;
}

export function parseNfeXml(raw: string): { nfe: ParsedNfe; itens: ParsedItem[] } {
  const parser = new DOMParser();
  const doc = parser.parseFromString(raw, "application/xml");

  const parseErr = doc.querySelector("parsererror");
  if (parseErr) throw new Error("XML inválido (erro de parse).");

  const num = (v: string | null | undefined) => {
    const n = parseDecimalBR(v ?? "0");
    return Number.isFinite(n) ? n : 0;
  };
  const numOrNull = (v: string | null | undefined) => {
    const n = parseDecimalBR(v ?? "0");
    return Number.isFinite(n) ? n : null;
  };

  const inf = doc.querySelector("infNFe");
  const chaveRaw = inf?.getAttribute("Id") || null;
  const chave = chaveRaw ? chaveRaw.replace(/^NFe/i, "") : null;

  const numero = doc.querySelector("ide > nNF")?.textContent ?? null;
  const serie = doc.querySelector("ide > serie")?.textContent ?? null;
  const emitente = doc.querySelector("emit > xNome")?.textContent ?? null;
  const cnpjEmitente = doc.querySelector("emit > CNPJ")?.textContent ?? null;

  // Destinatário (cliente da NF-e de saída)
  const destinatario = doc.querySelector("dest > xNome")?.textContent ?? null;
  const docDest =
    doc.querySelector("dest > CNPJ")?.textContent ??
    doc.querySelector("dest > CPF")?.textContent ??
    null;
  const ieDest = doc.querySelector("dest > IE")?.textContent ?? null;
  const emailDest = doc.querySelector("dest > email")?.textContent ?? null;

  const enderDest = doc.querySelector("dest > enderDest");
  const endDestCep = enderDest?.querySelector("CEP")?.textContent ?? null;
  const endDestLogradouro = enderDest?.querySelector("xLgr")?.textContent ?? null;
  const endDestNumero = enderDest?.querySelector("nro")?.textContent ?? null;
  const endDestComplemento = enderDest?.querySelector("xCpl")?.textContent ?? null;
  const endDestBairro = enderDest?.querySelector("xBairro")?.textContent ?? null;
  const endDestCidade = enderDest?.querySelector("xMun")?.textContent ?? null;
  const endDestUf = enderDest?.querySelector("UF")?.textContent ?? null;
  const endDestPais =
    enderDest?.querySelector("xPais")?.textContent ?? enderDest?.querySelector("cPais")?.textContent ?? null;
  const dataEmissao = doc.querySelector("ide > dhEmi")?.textContent ?? null;
  const dataEmissaoDate = toDateOnly(dataEmissao);

  const totalNode = doc.querySelector("total > ICMSTot");
  const valorFreteNF = num(totalNode?.querySelector("vFrete")?.textContent);
  const valorProdutosNF = num(totalNode?.querySelector("vProd")?.textContent);
  const valorSeguroNF = num(totalNode?.querySelector("vSeg")?.textContent);
  const valorDescontoNF = num(totalNode?.querySelector("vDesc")?.textContent);
  const valorOutrosNF = num(totalNode?.querySelector("vOutro")?.textContent);
  const valorTotalNF = num(totalNode?.querySelector("vNF")?.textContent);

  const itens: ParsedItem[] = [];
  doc.querySelectorAll("det").forEach((det) => {
    const prod = det.querySelector("prod");
    if (!prod) return;

    const codigo = (prod.querySelector("cProd")?.textContent ?? "").trim().replace(/^0+(?=\\d)/, "");
    const nome = prod.querySelector("xProd")?.textContent ?? "";
    const quantidade = num(prod.querySelector("qCom")?.textContent);
    const valorUnit = num(prod.querySelector("vUnCom")?.textContent);
    const vProd = num(prod.querySelector("vProd")?.textContent);
    const vTotTrib = num(prod.querySelector("vTotTrib")?.textContent);

    const vIPI = num(det.querySelector("IPI > IPITrib > vIPI")?.textContent) || num(det.querySelector("IPI > IPI > vIPI")?.textContent);
    const vICMS = num(det.querySelector("ICMS > * > vICMS")?.textContent);
    const vPIS = num(det.querySelector("PIS > * > vPIS")?.textContent);
    const vCOFINS = num(det.querySelector("COFINS > * > vCOFINS")?.textContent);
    const vST = num(det.querySelector("ICMS > * > vICMSST")?.textContent);

    const vOutro = num(prod.querySelector("vOutro")?.textContent);
    const vFrete = num(prod.querySelector("vFrete")?.textContent);
    const vDesc = num(prod.querySelector("vDesc")?.textContent);
    const vSeguro = num(prod.querySelector("vSeg")?.textContent);

    const totalBase = vProd + vFrete + vOutro + vIPI + vST + vTotTrib - vDesc;
    const total = totalBase > 0 ? totalBase : vProd || quantidade * valorUnit;

    const ncm = prod.querySelector("NCM")?.textContent ?? null;
    const cfop = prod.querySelector("CFOP")?.textContent ?? null;

    const icmsNode = det.querySelector("ICMS");
    let aliquotaIcms: number | null = null;
    icmsNode?.querySelectorAll("*").forEach((node) => {
      if (aliquotaIcms !== null) return;
      const p = numOrNull(node.querySelector("pICMS")?.textContent);
      if (p !== null) aliquotaIcms = p;
    });

    const aliquotaIpi = numOrNull(det.querySelector("IPI > IPITrib > pIPI")?.textContent) ?? numOrNull(det.querySelector("IPI > IPI > pIPI")?.textContent);
    const aliquotaPis = numOrNull(det.querySelector("PIS > * > pPIS")?.textContent);
    const aliquotaCofins = numOrNull(det.querySelector("COFINS > * > pCOFINS")?.textContent);

    if (!codigo) return;

    itens.push({
      codigo,
      nome,
      quantidade,
      valorUnit,
      valorProd: vProd,
      total,
      vIcms: vICMS,
      vIpi: vIPI,
      vPis: vPIS,
      vCofins: vCOFINS,
      vSt: vST,
      vFrete,
      vDesc,
      vOutro,
      vSeguro,
      overrideNome: nome,
      ncm,
      cfop,
      aliquotaIcms,
      aliquotaIpi,
      aliquotaPis,
      aliquotaCofins,
    });
  });

  const parcelasDup: Array<{ numero: string; vencimento: string; valor: number }> = [];

  // XML da NF-e costuma vir com namespace default; em alguns ambientes,
  // querySelectorAll pode não encontrar certos nós. Tenha fallback.
  let dupNodes = Array.from(doc.querySelectorAll("cobr > dup"));
  if (dupNodes.length === 0) {
    const byTag = Array.from(doc.getElementsByTagName("dup"));
    const onlyFromCobr = byTag.filter((el) => el.parentElement?.localName === "cobr");
    dupNodes = onlyFromCobr.length > 0 ? onlyFromCobr : byTag;
  }

  dupNodes.forEach((dup, idx) => {
    const numeroRaw = (dup.querySelector("nDup")?.textContent ?? "").trim();
    const vencRaw = (dup.querySelector("dVenc")?.textContent ?? "").trim();
    const valor = num(dup.querySelector("vDup")?.textContent);
    if (!Number.isFinite(valor) || valor <= 0) return;

    const numero = numeroRaw || String(idx + 1).padStart(3, "0");
    const vencimento = toDateOnly(vencRaw) ?? dataEmissaoDate ?? toDateOnly(new Date().toISOString());
    if (!vencimento) return;
    parcelasDup.push({ numero, vencimento, valor });
  });

  return {
    nfe: {
      chave,
      numero,
      serie,
      emitente,
      dataEmissao,
      cnpjEmitente,
      destinatario,
      documentoDestinatario: docDest,
      inscricaoEstadualDestinatario: ieDest,
      emailDestinatario: emailDest,
      endDestCep,
      endDestLogradouro,
      endDestNumero,
      endDestComplemento,
      endDestBairro,
      endDestCidade,
      endDestUf,
      endDestPais,
      valorProdutos: valorProdutosNF,
      valorFrete: valorFreteNF,
      valorSeguro: valorSeguroNF,
      valorDesconto: valorDescontoNF,
      valorOutros: valorOutrosNF,
      valorTotal: valorTotalNF,
      parcelas: parcelasDup,
    },
    itens,
  };
}

