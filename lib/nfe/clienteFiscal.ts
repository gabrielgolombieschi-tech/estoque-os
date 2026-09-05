export const INDICADOR_IE_OPTIONS = [
  { value: "1", label: "1 — Contribuinte do ICMS" },
  { value: "2", label: "2 — Contribuinte isento de inscrição" },
  { value: "9", label: "9 — Não contribuinte" },
] as const;

export type IndicadorIe = (typeof INDICADOR_IE_OPTIONS)[number]["value"];

export type ClienteFiscal = {
  razao_social?: string | null;
  documento?: string | null;
  inscricao_estadual?: string | null;
  indicador_ie?: string | null;
  cep?: string | null;
  logradouro?: string | null;
  numero_endereco?: string | null;
  complemento?: string | null;
  bairro?: string | null;
  cidade?: string | null;
  uf?: string | null;
  codigo_ibge_municipio?: string | null;
};

export type PendenciaClienteFiscal = {
  campo: keyof ClienteFiscal;
  mensagem: string;
};

export function somenteDigitos(value: unknown): string {
  return String(value ?? "").replace(/\D/g, "");
}

function todosDigitosIguais(value: string): boolean {
  return /^([0-9])\1+$/.test(value);
}

export function cpfValido(value: unknown): boolean {
  const cpf = somenteDigitos(value);
  if (cpf.length !== 11 || todosDigitosIguais(cpf)) return false;

  for (let digito = 9; digito < 11; digito += 1) {
    let soma = 0;
    for (let i = 0; i < digito; i += 1) soma += Number(cpf[i]) * (digito + 1 - i);
    const resto = (soma * 10) % 11;
    const esperado = resto === 10 ? 0 : resto;
    if (esperado !== Number(cpf[digito])) return false;
  }

  return true;
}

export function cnpjValido(value: unknown): boolean {
  const cnpj = somenteDigitos(value);
  if (cnpj.length !== 14 || todosDigitosIguais(cnpj)) return false;

  const calcular = (base: string, pesos: number[]) => {
    const soma = base.split("").reduce((total, atual, index) => total + Number(atual) * pesos[index], 0);
    const resto = soma % 11;
    return resto < 2 ? 0 : 11 - resto;
  };

  const primeiro = calcular(cnpj.slice(0, 12), [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]);
  const segundo = calcular(`${cnpj.slice(0, 12)}${primeiro}`, [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]);
  return cnpj.endsWith(`${primeiro}${segundo}`);
}

export function documentoFiscalValido(value: unknown): boolean {
  const documento = somenteDigitos(value);
  return documento.length === 11 ? cpfValido(documento) : cnpjValido(documento);
}

export function validarClienteFiscal(cliente: ClienteFiscal): PendenciaClienteFiscal[] {
  const pendencias: PendenciaClienteFiscal[] = [];
  const indicador = String(cliente.indicador_ie ?? "").trim();

  if (!String(cliente.razao_social ?? "").trim()) {
    pendencias.push({ campo: "razao_social", mensagem: "Informe a razão social ou o nome completo." });
  }
  if (!documentoFiscalValido(cliente.documento)) {
    pendencias.push({ campo: "documento", mensagem: "Informe um CPF ou CNPJ válido." });
  }
  if (!(["1", "2", "9"] as string[]).includes(indicador)) {
    pendencias.push({ campo: "indicador_ie", mensagem: "Confirme manualmente o indicador de IE." });
  }
  if (indicador === "1" && !String(cliente.inscricao_estadual ?? "").trim()) {
    pendencias.push({ campo: "inscricao_estadual", mensagem: "Contribuinte do ICMS deve ter IE informada." });
  }
  if (somenteDigitos(cliente.cep).length !== 8) {
    pendencias.push({ campo: "cep", mensagem: "Informe o CEP com 8 dígitos." });
  }
  if (!String(cliente.logradouro ?? "").trim()) {
    pendencias.push({ campo: "logradouro", mensagem: "Informe o logradouro." });
  }
  if (!String(cliente.numero_endereco ?? "").trim()) {
    pendencias.push({ campo: "numero_endereco", mensagem: "Informe o número do endereço, inclusive S/N quando aplicável." });
  }
  if (!String(cliente.bairro ?? "").trim()) {
    pendencias.push({ campo: "bairro", mensagem: "Informe o bairro." });
  }
  if (!String(cliente.cidade ?? "").trim()) {
    pendencias.push({ campo: "cidade", mensagem: "Informe o município." });
  }
  if (!/^[A-Z]{2}$/.test(String(cliente.uf ?? "").trim().toUpperCase())) {
    pendencias.push({ campo: "uf", mensagem: "Informe a UF com 2 letras." });
  }
  if (!/^[0-9]{7}$/.test(somenteDigitos(cliente.codigo_ibge_municipio))) {
    pendencias.push({ campo: "codigo_ibge_municipio", mensagem: "Informe o código IBGE do município com 7 dígitos." });
  }

  return pendencias;
}
