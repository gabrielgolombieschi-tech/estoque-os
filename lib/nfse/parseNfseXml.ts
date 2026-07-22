export type ParsedNfse = {
  numero: string;
  serie: string;
  prestador_cnpj: string;
  tomador_documento: string;
  data_emissao: string | null;
  codigo_verificacao: string | null;
  municipio_codigo: string | null;
  discriminacao: string | null;
  valores: {
    valor_servicos: string;
    valor_deducoes: string;
    valor_inss: string;
    valor_iss: string;
    valor_iss_retido: string;
    base_calculo: string;
    aliquota: string;
    valor_liquido: string;
    valor_total: string;
    iss_retido: string;
    valor_pis: string;
    valor_cofins: string;
    valor_ir: string;
    valor_csll: string;
  };
  tomador: {
    razao_social: string | null;
    nome_fantasia: string | null;
    email: string | null;
    telefone: string | null;
    contato: {
      email: string | null;
      telefone: string | null;
    };
    endereco: {
      logradouro: string | null;
      numero: string | null;
      complemento: string | null;
      bairro: string | null;
      cidade: string | null;
      municipio: string | null;
      uf: string | null;
      cep: string | null;
    };
  };
};

function digitsOnly(value: string | null | undefined): string {
  return String(value ?? "").replace(/\D/g, "");
}

function normalizeDoc(value: string | null | undefined): string {
  return digitsOnly(value);
}

function parseDecimalLoose(raw: string | null | undefined): number {
  const v = String(raw ?? "").trim();
  if (!v) return NaN;

  const stripped = v.replace(/^R\$\s*/i, "").replace(/\s+/g, "");

  const hasComma = stripped.includes(",");
  const hasDot = stripped.includes(".");

  let normalized = stripped;

  if (hasComma) {
    if (hasDot) {
      // If both exist, assume '.' thousands and ',' decimal when comma is last.
      if (normalized.lastIndexOf(",") > normalized.lastIndexOf(".")) {
        normalized = normalized.replace(/\./g, "").replace(",", ".");
      } else {
        // rare: comma thousands, dot decimal
        normalized = normalized.replace(/,/g, "");
      }
    } else {
      normalized = normalized.replace(",", ".");
    }
  } else if (hasDot) {
    // If multiple dots, treat as thousands separators: keep last dot as decimal.
    const parts = normalized.split(".");
    if (parts.length > 2) {
      const last = parts.pop() ?? "";
      normalized = parts.join("") + "." + last;
    }
  }

  const n = Number(normalized);
  return Number.isFinite(n) ? n : NaN;
}

function formatDecimalForRpc(value: number | null | undefined): string {
  const n = Number(value ?? 0);
  if (!Number.isFinite(n)) return "0";
  // Keep dot decimal; server casts ::numeric
  return n.toFixed(2);
}

function textOf(el: Element | null): string | null {
  if (!el) return null;
  const t = el.textContent;
  const trimmed = typeof t === "string" ? t.trim() : "";
  return trimmed ? trimmed : null;
}

function firstTextByLocalName(root: ParentNode, localNames: string[]): string | null {
  const all = root.querySelectorAll("*");
  const wanted = new Set(localNames.map((n) => n.toLowerCase()));
  for (const el of Array.from(all)) {
    const ln = String(el.localName ?? "").toLowerCase();
    if (!wanted.has(ln)) continue;
    const t = textOf(el);
    if (t) return t;
  }
  return null;
}

function firstAttrByLocalName(root: ParentNode, localName: string, attrName: string): string | null {
  const all = root.querySelectorAll("*");
  for (const el of Array.from(all)) {
    if (String(el.localName ?? "").toLowerCase() !== localName.toLowerCase()) continue;
    const v = el.getAttribute(attrName);
    if (v && v.trim()) return v.trim();
  }
  return null;
}

function firstTextByPath(root: ParentNode, localNamePath: string[]): string | null {
  // Best-effort: walk down by localName sequence.
  let current: ParentNode | null = root;
  for (const part of localNamePath) {
    if (!current) return null;
    const nodeWithQuery = current as unknown as ParentNode & {
      querySelectorAll: (selectors: string) => NodeListOf<Element>;
    };
    const all = nodeWithQuery.querySelectorAll("*");
    let next: Element | null = null;
    for (const el of Array.from(all)) {
      if (String(el.localName ?? "").toLowerCase() === part.toLowerCase()) {
        next = el;
        break;
      }
    }
    if (!next) return null;
    current = next;
  }
  return current && current instanceof Element ? textOf(current) : null;
}

function parseIsoDate(value: string | null | undefined): string | null {
  const v = String(value ?? "").trim();
  if (!v) return null;

  // Common NFSe: 2026-01-29 or 2026-01-29T10:20:30 or with timezone.
  const d = new Date(v);
  if (!Number.isNaN(d.getTime())) {
    const yyyy = d.getFullYear();
    const mm = String(d.getMonth() + 1).padStart(2, "0");
    const dd = String(d.getDate()).padStart(2, "0");
    return `${yyyy}-${mm}-${dd}`;
  }

  // dd/mm/yyyy
  const m = v.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (m) return `${m[3]}-${m[2]}-${m[1]}`;

  return null;
}

function parseIssRetidoFlag(value: string | null | undefined): string {
  const v = String(value ?? "").trim().toLowerCase();
  if (!v) return "0";
  if (["1", "true", "t", "sim", "s", "retido", "yes", "y"].includes(v)) return "1";
  if (["2", "false", "f", "nao", "não", "n", "0"].includes(v)) return "0";
  // ABRASF often uses 1 = SIM, 2 = NAO
  const n = Number(v);
  if (Number.isFinite(n)) return n === 1 ? "1" : "0";
  return "0";
}

// Padrao nacional NFS-e (DPS/infDPS/valores/trib/tribMun/tpRetISSQN):
// 1 = Nao retido; 2 = Retido pelo tomador; 3 = Retido pelo intermediario.
// Note: domain is inverted relative to the ABRASF "IssRetido" flag above.
function parseTpRetIssqnFlag(value: string | null | undefined): string {
  const v = String(value ?? "").trim();
  return v === "2" || v === "3" ? "1" : "0";
}

export function parseNfseXml(xmlText: string): ParsedNfse {
  const parser = new DOMParser();
  const doc = parser.parseFromString(xmlText, "text/xml");

  const parseErrors = doc.getElementsByTagName("parsererror");
  if (parseErrors && parseErrors.length) {
    throw new Error("XML inválido (parsererror). Verifique o arquivo.");
  }

  // Required-ish identifiers
  // "nNFSe" e "emit/toma/DPS/infDPS/..." sao do layout nacional da NFS-e (ADN),
  // usado desde que a emissao passou a ser feita pelo site do governo.
  const numero = firstTextByLocalName(doc, ["Numero", "NumeroNfse", "NumeroNota", "nNFSe"]) ?? "";
  const serie = firstTextByLocalName(doc, ["Serie", "SerieRps", "SeriePrestacao"]) ?? "";

  // Prestador
  const prestadorCnpjRaw =
    firstTextByPath(doc, ["PrestadorServico", "IdentificacaoPrestador", "Cnpj"]) ??
    firstTextByPath(doc, ["Prestador", "Cnpj"]) ??
    firstTextByPath(doc, ["emit", "CNPJ"]) ??
    firstTextByLocalName(doc, ["CnpjPrestador", "Cnpj"]) ??
    "";

  // Tomador
  const tomadorCnpjRaw =
    firstTextByPath(doc, ["TomadorServico", "IdentificacaoTomador", "CpfCnpj", "Cnpj"]) ??
    firstTextByPath(doc, ["Tomador", "IdentificacaoTomador", "CpfCnpj", "Cnpj"]) ??
    firstTextByPath(doc, ["TomadorServico", "IdentificacaoTomador", "Cnpj"]) ??
    firstTextByPath(doc, ["toma", "CNPJ"]) ??
    firstTextByLocalName(doc, ["CnpjTomador"]) ??
    null;

  const tomadorCpfRaw =
    firstTextByPath(doc, ["TomadorServico", "IdentificacaoTomador", "CpfCnpj", "Cpf"]) ??
    firstTextByPath(doc, ["Tomador", "IdentificacaoTomador", "CpfCnpj", "Cpf"]) ??
    firstTextByPath(doc, ["toma", "CPF"]) ??
    firstTextByLocalName(doc, ["CpfTomador"]) ??
    null;

  const tomadorDocumentoRaw = tomadorCnpjRaw ?? tomadorCpfRaw ?? "";

  const dataEmissao =
    parseIsoDate(firstTextByLocalName(doc, ["DataEmissao", "dhEmi"])) ??
    parseIsoDate(firstTextByLocalName(doc, ["Competencia", "dCompet"])) ??
    null;

  // Layout nacional nao tem "CodigoVerificacao"; usa a chave de acesso (Id do infNFSe).
  const codigoVerificacao =
    firstTextByLocalName(doc, ["CodigoVerificacao", "CodigoValidacao"]) ??
    firstAttrByLocalName(doc, "infNFSe", "Id") ??
    null;

  const discriminacao = firstTextByLocalName(doc, ["Discriminacao", "Descricao", "xDescServ"]) ?? null;

  const municipioCodigo =
    firstTextByPath(doc, ["OrgaoGerador", "CodigoMunicipio"]) ??
    firstTextByPath(doc, ["Servico", "CodigoMunicipio"]) ??
    firstTextByLocalName(doc, ["CodigoMunicipio", "cLocPrestacao", "cLocIncid"]) ??
    null;

  // Valores (names vary a lot). Keep best-effort.
  const valorServicosNum = parseDecimalLoose(firstTextByLocalName(doc, ["ValorServicos", "ValorServico", "vServ"]));
  const valorDeducoesNum = parseDecimalLoose(firstTextByLocalName(doc, ["ValorDeducoes", "ValorDeducao"]));
  const valorInssNum = parseDecimalLoose(firstTextByLocalName(doc, ["ValorInss", "ValorINSS"]));

  const valorIssNum = parseDecimalLoose(firstTextByLocalName(doc, ["ValorIss", "ValorISS", "vISSQN"]));
  const valorIssRetidoNum = parseDecimalLoose(firstTextByLocalName(doc, ["ValorIssRetido", "ValorISSRetido"]));
  const baseCalculoNum = parseDecimalLoose(firstTextByLocalName(doc, ["BaseCalculo", "BaseCalculoISS", "vBC"]));
  const aliquotaNum = parseDecimalLoose(firstTextByLocalName(doc, ["Aliquota", "AliquotaISS", "pAliqAplic"]));
  const valorLiquidoNum = parseDecimalLoose(firstTextByLocalName(doc, ["ValorLiquidoNfse", "ValorLiquido", "vLiq"]));

  // tpRetISSQN (layout nacional) tem dominio invertido em relacao a "IssRetido" (ABRASF).
  const tpRetIssqnRaw = firstTextByLocalName(doc, ["tpRetISSQN"]);
  const issRetidoFlag =
    tpRetIssqnRaw != null
      ? parseTpRetIssqnFlag(tpRetIssqnRaw)
      : parseIssRetidoFlag(firstTextByLocalName(doc, ["IssRetido", "ISSRetido"]));

  const valorPisNum = parseDecimalLoose(firstTextByLocalName(doc, ["ValorPis", "ValorPIS"]));
  const valorCofinsNum = parseDecimalLoose(firstTextByLocalName(doc, ["ValorCofins", "ValorCOFINS"]));
  const valorIrNum = parseDecimalLoose(firstTextByLocalName(doc, ["ValorIr", "ValorIR"]));
  const valorCsllNum = parseDecimalLoose(firstTextByLocalName(doc, ["ValorCsll", "ValorCSLL"]));

  const valorTotalNum = Number.isFinite(valorLiquidoNum)
    ? valorLiquidoNum
    : Number.isFinite(valorServicosNum)
      ? valorServicosNum
      : 0;

  const prestador_cnpj = normalizeDoc(prestadorCnpjRaw);
  const tomador_documento = normalizeDoc(tomadorDocumentoRaw);

  const parsed: ParsedNfse = {
    numero: String(numero).trim(),
    serie: String(serie).trim(),
    prestador_cnpj,
    tomador_documento,
    data_emissao: dataEmissao,
    codigo_verificacao: codigoVerificacao,
    municipio_codigo: municipioCodigo,
    discriminacao,
    valores: {
      valor_servicos: formatDecimalForRpc(valorServicosNum),
      valor_deducoes: formatDecimalForRpc(valorDeducoesNum),
      valor_inss: formatDecimalForRpc(valorInssNum),
      valor_iss: formatDecimalForRpc(valorIssNum),
      valor_iss_retido: formatDecimalForRpc(valorIssRetidoNum),
      base_calculo: formatDecimalForRpc(baseCalculoNum),
      aliquota: Number.isFinite(aliquotaNum) ? String(aliquotaNum) : "0",
      valor_liquido: formatDecimalForRpc(valorLiquidoNum),
      valor_total: formatDecimalForRpc(valorTotalNum),
      iss_retido: issRetidoFlag,
      valor_pis: formatDecimalForRpc(valorPisNum),
      valor_cofins: formatDecimalForRpc(valorCofinsNum),
      valor_ir: formatDecimalForRpc(valorIrNum),
      valor_csll: formatDecimalForRpc(valorCsllNum),
    },
    tomador: {
      razao_social:
        firstTextByPath(doc, ["toma", "xNome"]) ??
        firstTextByPath(doc, ["TomadorServico", "RazaoSocial"]) ??
        firstTextByPath(doc, ["Tomador", "RazaoSocial"]) ??
        null,
      nome_fantasia: null,
      email: null,
      telefone: null,
      contato: {
        // No layout nacional o "emit" tambem tem <email>/<fone>, entao a busca
        // generica por qualquer <Email> pegaria o do prestador; preferir "toma".
        email: firstTextByPath(doc, ["toma", "email"]) ?? firstTextByLocalName(doc, ["Email"]) ?? null,
        telefone: firstTextByPath(doc, ["toma", "fone"]) ?? firstTextByLocalName(doc, ["Telefone"]) ?? null,
      },
      endereco: {
        logradouro:
          firstTextByPath(doc, ["toma", "end", "xLgr"]) ??
          firstTextByPath(doc, ["TomadorServico", "Endereco", "Endereco"]) ??
          firstTextByPath(doc, ["TomadorServico", "Endereco", "Logradouro"]) ??
          firstTextByPath(doc, ["Tomador", "Endereco", "Logradouro"]) ??
          null,
        numero:
          firstTextByPath(doc, ["toma", "end", "nro"]) ??
          firstTextByPath(doc, ["TomadorServico", "Endereco", "Numero"]) ??
          firstTextByPath(doc, ["Tomador", "Endereco", "Numero"]) ??
          null,
        complemento:
          firstTextByPath(doc, ["toma", "end", "xCpl"]) ??
          firstTextByPath(doc, ["TomadorServico", "Endereco", "Complemento"]) ??
          firstTextByPath(doc, ["Tomador", "Endereco", "Complemento"]) ??
          null,
        bairro:
          firstTextByPath(doc, ["toma", "end", "xBairro"]) ??
          firstTextByPath(doc, ["TomadorServico", "Endereco", "Bairro"]) ??
          firstTextByPath(doc, ["Tomador", "Endereco", "Bairro"]) ??
          null,
        cidade:
          firstTextByPath(doc, ["toma", "end", "endNac", "cMun"]) ??
          firstTextByPath(doc, ["TomadorServico", "Endereco", "CodigoMunicipio"]) ??
          firstTextByPath(doc, ["Tomador", "Endereco", "CodigoMunicipio"]) ??
          null,
        municipio:
          firstTextByPath(doc, ["TomadorServico", "Endereco", "Municipio"]) ??
          firstTextByPath(doc, ["Tomador", "Endereco", "Municipio"]) ??
          null,
        uf:
          firstTextByPath(doc, ["TomadorServico", "Endereco", "Uf"]) ??
          firstTextByPath(doc, ["Tomador", "Endereco", "Uf"]) ??
          null,
        cep:
          firstTextByPath(doc, ["toma", "end", "endNac", "CEP"]) ??
          firstTextByPath(doc, ["TomadorServico", "Endereco", "Cep"]) ??
          firstTextByPath(doc, ["Tomador", "Endereco", "Cep"]) ??
          null,
      },
    },
  };

  if (!parsed.numero) throw new Error("Número da NFSe não encontrado no XML.");
  if (!parsed.serie) throw new Error("Série da NFSe não encontrada no XML.");
  if (!parsed.prestador_cnpj) throw new Error("CNPJ do prestador não encontrado no XML.");
  if (!parsed.tomador_documento) throw new Error("Documento do tomador (CPF/CNPJ) não encontrado no XML.");

  return parsed;
}
