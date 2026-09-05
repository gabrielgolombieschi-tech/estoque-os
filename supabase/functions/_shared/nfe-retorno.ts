import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  baixarArquivoFocus,
  diagnosticoFocus,
  normalizarFocus,
  validarReferenciaFocusEsperada,
  type FocusAmbiente,
} from "./focus-nfe.ts";

async function armazenar(
  supabase: SupabaseClient,
  tenantId: string,
  empresaId: string,
  referencia: string,
  caminho: string | null,
  extensao: "xml" | "pdf",
  ambiente: FocusAmbiente,
) {
  if (!caminho) return { path: null, raw: null };
  const response = await baixarArquivoFocus(caminho, ambiente);
  const bytes = new Uint8Array(await response.arrayBuffer());
  const path = `${tenantId}/${empresaId}/${referencia}/${extensao === "xml" ? "nfe.xml" : "danfe.pdf"}`;
  const contentType = extensao === "xml" ? "application/xml" : "application/pdf";
  const { error } = await supabase.storage.from("nfe-documentos").upload(path, bytes, { contentType, upsert: true });
  if (error) throw new Error(`Não foi possível guardar ${extensao.toUpperCase()} no Storage: ${error.message}`);
  return {
    path,
    raw: extensao === "xml" ? new TextDecoder().decode(bytes) : null,
  };
}

export async function aplicarRetorno(
  supabase: SupabaseClient,
  payload: unknown,
  emissao: { referencia_externa: string; ambiente: FocusAmbiente; tenant_id: string; empresa_id: string },
  origem: "CALLBACK" | "RECONCILIACAO" | "ENVIO",
  rpcRetorno = "fn_nfe_aplicar_retorno",
) {
  const retorno = normalizarFocus(payload);
  let referencia: string;
  try {
    referencia = validarReferenciaFocusEsperada(retorno.referencia, emissao.referencia_externa);
  } catch (error) {
    const mensagem = error instanceof Error ? error.message : String(error);
    throw new Error(`Retorno da Focus recusado: ${mensagem} (${diagnosticoFocus(payload)}).`);
  }
  // Storage e RPC usam sempre a referencia resolvida pela emissao local. Um
  // campo `ref` injetado/divergente no retorno nunca redireciona artefatos ou
  // estado para outra NF-e.
  let xml = { path: null as string | null, raw: null as string | null };
  let danfe = { path: null as string | null, raw: null as string | null };
  if (retorno.status === "AUTORIZADA") {
    if (!retorno.chaveAcesso) {
      throw new Error(`Retorno autorizado sem chave de acesso reconhecivel (${diagnosticoFocus(payload)}).`);
    }
    [xml, danfe] = await Promise.all([
      armazenar(supabase, emissao.tenant_id, emissao.empresa_id, referencia, retorno.caminhoXml, "xml", emissao.ambiente),
      armazenar(supabase, emissao.tenant_id, emissao.empresa_id, referencia, retorno.caminhoDanfe, "pdf", emissao.ambiente),
    ]);
  }
  const { data, error } = await supabase.schema("f").rpc(rpcRetorno, {
    p_referencia_externa: referencia,
    p_resposta: retorno.bruto,
    p_status: retorno.status,
    p_chave_acesso: retorno.chaveAcesso,
    p_protocolo: retorno.protocolo,
    p_numero: retorno.numero,
    p_serie: retorno.serie,
    p_codigo_status: retorno.codigoStatus,
    p_mensagem: retorno.mensagem,
    p_xml_path: xml.path,
    p_danfe_path: danfe.path,
    p_xml_raw: xml.raw,
    p_origem_retorno: origem,
  });
  if (error) throw new Error(`Não foi possível gravar retorno da Focus: ${error.message}`);
  return { documentoFiscalId: data as string, retorno, xmlPath: xml.path, danfePath: danfe.path };
}
