export type FocusStatus = "PROCESSANDO" | "AUTORIZADA" | "REJEITADA" | "CANCELADA" | "ERRO";
export type FocusAmbiente = "HOMOLOGACAO" | "PRODUCAO";

export type FocusNormalizado = {
  status: FocusStatus;
  referencia: string | null;
  chaveAcesso: string | null;
  protocolo: string | null;
  numero: number | null;
  serie: number | null;
  codigoStatus: number | null;
  mensagem: string | null;
  caminhoXml: string | null;
  caminhoDanfe: string | null;
  bruto: Record<string, unknown>;
};

export function validarReferenciaFocusEsperada(
  referenciaRetornada: string | null,
  referenciaEsperada: string,
) {
  const esperada = referenciaEsperada.trim();
  const retornada = referenciaRetornada?.trim() ?? null;
  if (!esperada) throw new Error("Emissao sem referencia externa esperada.");
  if (retornada && retornada !== esperada) {
    throw new Error(`Referencia retornada ${retornada} difere da emissao esperada ${esperada}.`);
  }
  return esperada;
}

export function diagnosticoFocus(payload: unknown) {
  const bruto = payload && typeof payload === "object" && !Array.isArray(payload)
    ? payload as Record<string, unknown>
    : { valor: payload };
  const objetos = objetosDoRetorno(bruto);
  const campos = [...new Set(objetos.flatMap((objeto) => Object.keys(objeto)))].sort();
  const candidatos = objetos.flatMap((objeto) => Object.entries(objeto))
    .filter(([chave]) => /chave|xml|danfe/i.test(chave))
    .map(([chave, valor]) => {
      const textoValor = typeof valor === "string" || typeof valor === "number" ? String(valor) : "";
      const digitos = textoValor.replace(/\D/g, "");
      return `${chave}:${typeof valor}:${textoValor.length}c/${digitos.length}d`;
    });
  return `campos=${campos.join(",") || "nenhum"}; candidatos=${candidatos.join(",") || "nenhum"}`;
}

function texto(obj: Record<string, unknown>, ...chaves: string[]) {
  for (const chave of chaves) {
    const valor = obj[chave];
    if (valor !== undefined && valor !== null && String(valor).trim() !== "") return String(valor).trim();
  }
  return null;
}

function objetosDoRetorno(payload: Record<string, unknown>) {
  const objetos: Record<string, unknown>[] = [payload];
  const fila: Array<{ valor: unknown; nivel: number }> = Object.values(payload)
    .map((valor) => ({ valor, nivel: 1 }));

  while (fila.length > 0) {
    const atual = fila.shift();
    if (!atual || atual.nivel > 3 || !atual.valor || typeof atual.valor !== "object") continue;
    if (Array.isArray(atual.valor)) {
      for (const valor of atual.valor) fila.push({ valor, nivel: atual.nivel + 1 });
      continue;
    }
    const objeto = atual.valor as Record<string, unknown>;
    objetos.push(objeto);
    for (const valor of Object.values(objeto)) fila.push({ valor, nivel: atual.nivel + 1 });
  }

  return objetos;
}

function textoRecursivo(objetos: Record<string, unknown>[], ...chaves: string[]) {
  for (const objeto of objetos) {
    const valor = texto(objeto, ...chaves);
    if (valor !== null) return valor;
  }
  return null;
}

function numeroRecursivo(objetos: Record<string, unknown>[], ...chaves: string[]) {
  const valor = textoRecursivo(objetos, ...chaves);
  if (valor === null) return null;
  const parsed = Number(valor);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizarChave(valor: string | null) {
  if (!valor) return null;
  const digitos = valor.replace(/\D/g, "");
  if (digitos.length === 44) return digitos;
  const encontrada = valor.match(/(?:NFe)?(\d{44})(?:-nfe)?/i)?.[1];
  return encontrada ?? null;
}

export function normalizarFocus(payload: unknown): FocusNormalizado {
  const bruto = payload && typeof payload === "object" && !Array.isArray(payload)
    ? payload as Record<string, unknown>
    : { mensagem: String(payload ?? "") };
  const objetos = objetosDoRetorno(bruto);
  const statusBruto = (textoRecursivo(objetos, "status", "status_sefaz", "situacao") ?? "").toLowerCase();
  const chave = normalizarChave(textoRecursivo(
    objetos,
    "chave_nfe",
    "chave",
    "chave_acesso",
    "caminho_xml_nota_fiscal",
    "caminho_danfe",
  ));
  const protocolo = textoRecursivo(objetos, "protocolo", "protocolo_autorizacao", "numero_protocolo");
  const codigo = numeroRecursivo(objetos, "status_sefaz", "codigo_status", "cstat", "cStat");
  const mensagem = textoRecursivo(objetos, "mensagem_sefaz", "mensagem", "xmotivo", "xMotivo", "motivo", "erro");

  let status: FocusStatus;
  if (statusBruto.includes("process") || statusBruto.includes("fila") || statusBruto.includes("pend")) status = "PROCESSANDO";
  else if (statusBruto.includes("cancel")) status = "CANCELADA";
  else if (statusBruto.includes("erro") || statusBruto.includes("rejeit") || (codigo !== null && codigo >= 200)) status = "REJEITADA";
  else if (statusBruto.includes("autoriz")) status = "AUTORIZADA";
  else if (chave && protocolo) status = "AUTORIZADA";
  else status = "PROCESSANDO";

  return {
    status,
    referencia: textoRecursivo(objetos, "ref", "referencia"),
    chaveAcesso: chave,
    protocolo,
    numero: numeroRecursivo(objetos, "numero", "numero_nfe"),
    serie: numeroRecursivo(objetos, "serie"),
    codigoStatus: codigo,
    mensagem,
    caminhoXml: textoRecursivo(objetos, "caminho_xml_nota_fiscal", "caminho_xml", "url_xml"),
    caminhoDanfe: textoRecursivo(objetos, "caminho_danfe", "caminho_pdf", "url_danfe"),
    bruto,
  };
}

export function focusBaseUrl(ambiente: FocusAmbiente = "HOMOLOGACAO") {
  return ambiente === "PRODUCAO"
    ? "https://api.focusnfe.com.br"
    : "https://homologacao.focusnfe.com.br";
}

function tokenFocus(ambiente: FocusAmbiente) {
  const nome = ambiente === "PRODUCAO"
    ? "FOCUS_NFE_TOKEN_PRODUCAO"
    : "FOCUS_NFE_TOKEN_HOMOLOGACAO";
  const token = Deno.env.get(nome);
  if (!token) throw new Error(`Secret ${nome} não configurado.`);
  return token;
}

export function focusConfigurado(ambiente: FocusAmbiente) {
  const flag = ambiente === "PRODUCAO"
    ? "FOCUS_NFE_PRODUCAO_ENABLED"
    : "FOCUS_NFE_HOMOLOGACAO_ENABLED";
  const token = ambiente === "PRODUCAO"
    ? "FOCUS_NFE_TOKEN_PRODUCAO"
    : "FOCUS_NFE_TOKEN_HOMOLOGACAO";
  return Deno.env.get(flag) === "true" && Boolean(Deno.env.get(token));
}

export async function chamarFocus(
  path: string,
  init: RequestInit = {},
  ambiente: FocusAmbiente = "HOMOLOGACAO",
) {
  const token = tokenFocus(ambiente);
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  headers.set("Authorization", `Basic ${btoa(`${token}:`)}`);
  if (init.body) headers.set("Content-Type", "application/json");
  const response = await fetch(`${focusBaseUrl(ambiente)}${path}`, { ...init, headers });
  const contentType = response.headers.get("content-type") ?? "";
  const body = contentType.includes("json")
    ? await response.json()
    : { mensagem: await response.text() };
  return { response, body };
}

export async function baixarArquivoFocus(caminho: string, ambiente: FocusAmbiente = "HOMOLOGACAO") {
  const baseUrl = focusBaseUrl(ambiente);
  const url = caminho.startsWith("http") ? caminho : `${baseUrl}${caminho}`;
  if (!url.startsWith(`${baseUrl}/`)) {
    throw new Error(`Download bloqueado: a URL não pertence ao ambiente ${ambiente} da Focus.`);
  }
  const token = tokenFocus(ambiente);
  let response = await fetch(url, {
    redirect: "manual",
    headers: { Authorization: `Basic ${btoa(`${token}:`)}` },
  });
  if (response.status >= 300 && response.status < 400) {
    const location = response.headers.get("location");
    if (!location) throw new Error(`Download Focus redirecionou sem URL (${response.status}).`);
    response = await fetch(location, { redirect: "follow" });
  }
  if (!response.ok) throw new Error(`Falha ao baixar arquivo da Focus (HTTP ${response.status}).`);
  return response;
}
