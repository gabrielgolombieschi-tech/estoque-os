import fs from "node:fs";
import crypto from "node:crypto";
import { createClient } from "@supabase/supabase-js";

const env = {};
for (const file of [".env.local", ".env"]) {
  if (!fs.existsSync(file)) continue;
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    const match = line.match(/^([^#=]+)=(.*)$/);
    if (!match || env[match[1]]) continue;
    env[match[1]] = match[2].trim().replace(/^['"]|['"]$/g, "");
  }
}

const referencia = process.argv[2];
if (!referencia) throw new Error("Informe a referencia externa da emissao.");
const supabase = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const { data: emissoes, error } = await supabase
  .schema("f")
  .from("documento_fiscal_emissao")
  .select("documento_fiscal_id,solicitacao_id,tenant_id,empresa_id,referencia_externa,ambiente,status,chave_acesso,protocolo,numero,serie,codigo_status,mensagem,tentativa_count,payload_enviado,resposta,xml_path,danfe_path,created_at,updated_at")
  .eq("referencia_externa", referencia)
  .limit(1);
if (error) throw error;
const emissao = emissoes?.[0];
if (!emissao) throw new Error(`Emissao ${referencia} nao encontrada.`);

const resposta = emissao.resposta && typeof emissao.resposta === "object" ? emissao.resposta : {};
const chaveBruta = resposta.chave_nfe ?? resposta.chave ?? resposta.chave_acesso ?? null;

const { data: auditoria, error: auditoriaError } = await supabase.schema("f")
  .rpc("fn_nfe_auditar_documento", { p_documento_fiscal_id: emissao.documento_fiscal_id });
if (auditoriaError) throw new Error(`auditoria: ${auditoriaError.message}`);
const documento = auditoria?.documento ?? null;
const solicitacao = auditoria?.solicitacao ?? null;
const itens = auditoria?.itens ?? [];
const eventos = auditoria?.eventos ?? [];
const titulos = auditoria?.titulos ?? [];
let xmlRaw = "";
let xmlStorageError = null;
if (emissao.xml_path) {
  const { data: xmlStorage, error: downloadError } = await supabase.storage
    .from("nfe-documentos").download(emissao.xml_path);
  if (downloadError) xmlStorageError = downloadError.message;
  else xmlRaw = await xmlStorage.text();
}
let danfeBytes = Buffer.alloc(0);
let danfeStorageError = null;
if (emissao.danfe_path) {
  const { data: danfeStorage, error: downloadError } = await supabase.storage
    .from("nfe-documentos").download(emissao.danfe_path);
  if (downloadError) danfeStorageError = downloadError.message;
  else danfeBytes = Buffer.from(await danfeStorage.arrayBuffer());
}
const origemId = documento?.os_id_import ?? null;
let saldoItens = [];
let saldoValor = [];
let cadastroItens = [];
const itemIds = [...new Set(itens.map((item) => item.item_id).filter((itemId) => itemId != null))];
if (itemIds.length) {
  const { data: cadastroData, error: cadastroError } = await supabase
    .from("itens")
    .select("id,codigo_interno,nome,peso_liquido,peso_bruto")
    .eq("tenant_id", emissao.tenant_id)
    .eq("empresa_id", emissao.empresa_id)
    .in("id", itemIds);
  if (cadastroError) throw new Error(`cadastro_itens: ${cadastroError.message}`);
  cadastroItens = cadastroData ?? [];
}
if (origemId) {
  const [{ data: saldoItensData, error: saldoItensError }, { data: saldoValorData, error: saldoValorError }] = await Promise.all([
    supabase.schema("f").rpc("fn_os_itens_saldo_a_faturar", {
      p_tenant_id: emissao.tenant_id, p_empresa_id: emissao.empresa_id, p_os_id: origemId,
    }),
    supabase.schema("f").rpc("fn_os_saldo_a_faturar", {
      p_tenant_id: emissao.tenant_id, p_empresa_id: emissao.empresa_id, p_os_id: origemId,
    }),
  ]);
  if (saldoItensError) throw new Error(`saldo_itens: ${saldoItensError.message}`);
  if (saldoValorError) throw new Error(`saldo_valor: ${saldoValorError.message}`);
  saldoItens = saldoItensData ?? [];
  saldoValor = saldoValorData ?? [];
}
console.log(JSON.stringify({
  referencia: emissao.referencia_externa,
  ambiente: emissao.ambiente,
  status: emissao.status,
  codigo_status: emissao.codigo_status,
  mensagem: emissao.mensagem,
  tentativa_count: emissao.tentativa_count,
  numero: emissao.numero,
  serie: emissao.serie,
  chave_gravada: emissao.chave_acesso,
  chave_bruta: chaveBruta,
  chave_bruta_tamanho: chaveBruta === null ? null : String(chaveBruta).length,
  protocolo_bruto: resposta.protocolo ?? resposta.protocolo_autorizacao ?? null,
  status_bruto: resposta.status ?? resposta.status_sefaz ?? resposta.situacao ?? null,
  resposta_campos: Object.keys(resposta).sort(),
  payload_tem_cenq: Array.isArray(emissao.payload_enviado?.items)
    ? emissao.payload_enviado.items.every((item) => item.ipi_codigo_enquadramento_legal)
    : false,
  xml_path: emissao.xml_path,
  danfe_path: emissao.danfe_path,
  documento,
  solicitacao,
  itens,
  cadastro_itens: cadastroItens,
  xml: {
    banco: auditoria?.xml ?? null,
    storage_error: xmlStorageError,
    tamanho_bytes_utf8: Buffer.byteLength(xmlRaw, "utf8"),
    hash_storage: xmlRaw ? crypto.createHash("sha256").update(xmlRaw, "utf8").digest("hex") : null,
    hash_confere: Boolean(xmlRaw) && crypto.createHash("sha256").update(xmlRaw, "utf8").digest("hex") === auditoria?.xml?.xml_hash,
    tem_protocolo_autorizacao: /<protNFe[\s>]/.test(xmlRaw),
    tem_gibscbs: /<(?:\w+:)?gIBSCBS[\s>]/.test(xmlRaw),
    tem_cclass_trib: /<(?:\w+:)?cClassTrib>[^<]+<\/(?:\w+:)?cClassTrib>/.test(xmlRaw),
    valores_cclass_trib: [...xmlRaw.matchAll(/<(?:\w+:)?cClassTrib>([^<]+)<\/(?:\w+:)?cClassTrib>/g)]
      .map((match) => match[1]),
    tem_ibs_uf: /<(?:\w+:)?gIBSUF[\s>]/.test(xmlRaw),
    tem_cbs: /<(?:\w+:)?gCBS[\s>]/.test(xmlRaw),
  },
  danfe: {
    storage_error: danfeStorageError,
    tamanho_bytes: danfeBytes.length,
    cabecalho_pdf_valido: danfeBytes.subarray(0, 5).toString("ascii") === "%PDF-",
  },
  eventos,
  titulos,
  impostos: auditoria?.impostos ?? [],
  movimentacoes_da_origem: auditoria?.movimentacoes_da_origem ?? [],
  saldo_por_item: saldoItens,
  saldo_por_valor: saldoValor,
}, null, 2));
