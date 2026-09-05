import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { baixarArquivoFocus, focusBaseUrl, type FocusAmbiente, type FocusStatus } from "./focus-nfe.ts";

/**
 * Normalizacao do retorno da Focus para NFS-e Nacional (GET/POST /v2/nfsen).
 * Status possiveis (doc 05/09/2026): processando_autorizacao, autorizado,
 * negado, erro_autorizacao, cancelado, erro_cancelamento. A chave (50 digitos)
 * nao vem num campo proprio: sai da url (chave=...) ou do caminho do XML
 * (NFS<50 digitos>-nfse.xml).
 */
export type FocusNfseNormalizado = {
  status: FocusStatus;
  referencia: string | null;
  chaveNfse: string | null;
  numero: string | null;
  codigoVerificacao: string | null;
  protocolo: string | null;
  mensagem: string | null;
  codigoStatus: number | null;
  caminhoXml: string | null;
  urlDanfse: string | null;
  caminhoXmlCancelamento: string | null;
  bruto: Record<string, unknown>;
};

function texto(obj: Record<string, unknown>, ...chaves: string[]) {
  for (const chave of chaves) {
    const valor = obj[chave];
    if (valor !== undefined && valor !== null && String(valor).trim() !== "") return String(valor).trim();
  }
  return null;
}

export function chaveNfseDe(...valores: Array<string | null>) {
  for (const valor of valores) {
    if (!valor) continue;
    const m = valor.match(/(?:chave=|NFS)(\d{50})/);
    if (m) return m[1];
    const digitos = valor.replace(/\D/g, "");
    if (digitos.length === 50) return digitos;
  }
  return null;
}

export function normalizarFocusNfse(payload: unknown): FocusNfseNormalizado {
  const bruto = payload && typeof payload === "object" && !Array.isArray(payload)
    ? payload as Record<string, unknown>
    : { mensagem: String(payload ?? "") };
  const statusBruto = (texto(bruto, "status") ?? "").toLowerCase();
  const erros = Array.isArray(bruto.erros) ? bruto.erros as Array<Record<string, unknown>> : [];
  const mensagemErros = erros.map((e) => {
    const codigo = texto(e, "codigo");
    const msg = texto(e, "mensagem") ?? "";
    const correcao = texto(e, "correcao");
    return `${codigo ? `${codigo}: ` : ""}${msg}${correcao ? ` (${correcao})` : ""}`;
  }).filter(Boolean).join(" | ");
  const mensagem = mensagemErros || texto(bruto, "mensagem", "erro", "motivo");
  let status: FocusStatus;
  if (statusBruto.includes("process")) status = "PROCESSANDO";
  else if (statusBruto === "erro_cancelamento") status = "AUTORIZADA";
  else if (statusBruto.includes("erro") || statusBruto.includes("negad")) status = "REJEITADA";
  else if (statusBruto === "cancelado") status = "CANCELADA";
  else if (statusBruto === "autorizado") status = "AUTORIZADA";
  else if (texto(bruto, "codigo") && !statusBruto) status = "REJEITADA";
  else status = "PROCESSANDO";
  const caminhoXml = texto(bruto, "caminho_xml_nota_fiscal", "caminho_xml");
  const urlDanfse = texto(bruto, "url_danfse", "caminho_danfse");
  return {
    status,
    referencia: texto(bruto, "ref", "referencia"),
    chaveNfse: chaveNfseDe(texto(bruto, "chave", "chave_nfse"), texto(bruto, "url"), caminhoXml, urlDanfse),
    numero: texto(bruto, "numero", "numero_nfse"),
    codigoVerificacao: texto(bruto, "codigo_verificacao"),
    protocolo: texto(bruto, "protocolo"),
    mensagem,
    codigoStatus: erros.length > 0 ? 422 : null,
    caminhoXml,
    urlDanfse,
    caminhoXmlCancelamento: texto(bruto, "caminho_xml_cancelamento"),
    bruto,
  };
}

const HOSTS_DANFSE = ["https://focusnfe.s3.sa-east-1.amazonaws.com/", "https://focusnfe.s3.amazonaws.com/"];

// O DANFSe vem como URL absoluta do S3 da Focus; o XML vem como caminho da API.
export async function baixarArquivoNfse(caminho: string, ambiente: FocusAmbiente) {
  if (HOSTS_DANFSE.some((h) => caminho.startsWith(h))) {
    const response = await fetch(caminho, { redirect: "follow" });
    if (!response.ok) throw new Error(`Falha ao baixar DANFSe (HTTP ${response.status}).`);
    return response;
  }
  if (caminho.startsWith("http") && !caminho.startsWith(`${focusBaseUrl(ambiente)}/`)) {
    throw new Error("Download bloqueado: a URL nao pertence a Focus nem ao S3 da Focus.");
  }
  return baixarArquivoFocus(caminho, ambiente);
}

async function armazenar(
  supabase: SupabaseClient,
  tenantId: string,
  empresaId: string,
  referencia: string,
  caminho: string | null,
  extensao: "xml" | "pdf",
  ambiente: FocusAmbiente,
) {
  if (!caminho) return { path: null as string | null, raw: null as string | null };
  const response = await baixarArquivoNfse(caminho, ambiente);
  const bytes = new Uint8Array(await response.arrayBuffer());
  const path = `${tenantId}/${empresaId}/${referencia}/${extensao === "xml" ? "nfse.xml" : "danfse.pdf"}`;
  const contentType = extensao === "xml" ? "application/xml" : "application/pdf";
  const { error } = await supabase.storage.from("nfe-documentos").upload(path, bytes, { contentType, upsert: true });
  if (error) throw new Error(`Nao foi possivel guardar ${extensao.toUpperCase()} da NFS-e no Storage: ${error.message}`);
  return { path, raw: extensao === "xml" ? new TextDecoder().decode(bytes) : null };
}

export async function aplicarRetornoNfse(
  supabase: SupabaseClient,
  payload: unknown,
  emissao: { referencia_externa: string; ambiente: FocusAmbiente; tenant_id: string; empresa_id: string },
  origem: "CALLBACK" | "RECONCILIACAO" | "ENVIO",
) {
  const retorno = normalizarFocusNfse(payload);
  const esperada = emissao.referencia_externa.trim();
  if (retorno.referencia && retorno.referencia !== esperada) {
    throw new Error(`Retorno da Focus recusado: referencia ${retorno.referencia} difere da emissao ${esperada}.`);
  }
  let xml = { path: null as string | null, raw: null as string | null };
  let danfse = { path: null as string | null, raw: null as string | null };
  if (retorno.status === "AUTORIZADA") {
    if (!retorno.chaveNfse) throw new Error("Retorno autorizado sem chave de NFS-e reconhecivel (url/caminho_xml_nota_fiscal).");
    [xml, danfse] = await Promise.all([
      armazenar(supabase, emissao.tenant_id, emissao.empresa_id, esperada, retorno.caminhoXml, "xml", emissao.ambiente),
      armazenar(supabase, emissao.tenant_id, emissao.empresa_id, esperada, retorno.urlDanfse, "pdf", emissao.ambiente),
    ]);
  }
  const { data, error } = await supabase.schema("f").rpc("fn_nfse_aplicar_retorno", {
    p_referencia_externa: esperada,
    p_resposta: retorno.bruto,
    p_status: retorno.status,
    p_chave_nfse: retorno.chaveNfse,
    p_nfse_numero: retorno.numero,
    p_codigo_verificacao: retorno.codigoVerificacao,
    p_protocolo: retorno.protocolo,
    p_codigo_status: retorno.codigoStatus,
    p_mensagem: retorno.mensagem,
    p_xml_path: xml.path,
    p_danfse_path: danfse.path,
    p_xml_raw: xml.raw,
    p_origem_retorno: origem,
  });
  if (error) throw new Error(`Nao foi possivel gravar retorno da NFS-e: ${error.message}`);
  return { documentoFiscalId: data as string, retorno, xmlPath: xml.path, danfsePath: danfse.path };
}
