import fs from "node:fs";
import readline from "node:readline";
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

const tenantId = process.argv[2];
const empresaId = process.argv[3];
const dumpIndex = process.argv.indexOf("--dump");
const emitenteIndex = process.argv.indexOf("--emitente");
const produtoIndex = process.argv.indexOf("--produto");
const incluirDetalhes = process.argv.includes("--detalhes");
const procurarProdutoEmTodoDump = process.argv.includes("--produto-todos");
const dumpPath = dumpIndex >= 0 ? process.argv[dumpIndex + 1] : null;
const emitenteCnpj = emitenteIndex >= 0 ? String(process.argv[emitenteIndex + 1] ?? "").replace(/\D/g, "") : null;
const produtoFiltro = produtoIndex >= 0 ? String(process.argv[produtoIndex + 1] ?? "").trim() : null;
if (!tenantId || !empresaId) {
  throw new Error("Informe tenant_id e empresa_id para manter a consulta explicitamente escopada.");
}
let linhas = [];
let documentosTotal = 0;
const ocorrenciasProduto = [];

function registrarProduto(xml, documento = {}) {
  if (!produtoFiltro) return;
  const numero = xml.match(/<(?:\w+:)?nNF>(\d+)<\/(?:\w+:)?nNF>/)?.[1] ?? documento.numero ?? null;
  const natOp = xml.match(/<(?:\w+:)?natOp>([^<]+)<\/(?:\w+:)?natOp>/)?.[1] ?? null;
  for (const match of xml.matchAll(/<(?:\w+:)?det\b[^>]*>([\s\S]*?)<\/(?:\w+:)?det>/g)) {
    const itemXml = match[1];
    const campo = (nome) => itemXml.match(new RegExp(`<(?:\\w+:)?${nome}>([^<]*)<\\/(?:\\w+:)?${nome}>`))?.[1] ?? null;
    const codigo = campo("cProd");
    const ncm = campo("NCM");
    if (codigo !== produtoFiltro && ncm !== produtoFiltro) continue;
    ocorrenciasProduto.push({
      numero,
      natureza_operacao: natOp,
      codigo_produto: codigo,
      descricao: campo("xProd"),
      ncm,
      origem: campo("orig"),
      cst_ipi: campo("CST"),
      c_enq_ipi: campo("cEnq"),
    });
  }
}

if (dumpPath) {
  if (!emitenteCnpj || emitenteCnpj.length !== 14) {
    throw new Error("Ao usar --dump, informe tambem --emitente com o CNPJ de 14 digitos da empresa escopada.");
  }
  let lendoXml = false;
  const input = readline.createInterface({ input: fs.createReadStream(dumpPath, { encoding: "utf8" }), crlfDelay: Infinity });
  for await (const line of input) {
    if (!lendoXml) {
      lendoXml = line.startsWith('COPY "f"."documento_fiscal_xml" ');
      continue;
    }
    if (line === "\\.") break;
    const campos = line.split("\t");
    if (campos.length < 5 || campos[1] !== tenantId) continue;
    const xml = campos[4].replace(/\\n/g, "\n").replace(/\\r/g, "\r");
    if (procurarProdutoEmTodoDump) registrarProduto(xml);
    if (!/<(?:\w+:)?dhEmi>2026-08-|<(?:\w+:)?dEmi>2026-08-/.test(xml)) continue;
    const emitente = xml.match(/<(?:\w+:)?emit>[\s\S]*?<(?:\w+:)?CNPJ>(\d{14})<\/(?:\w+:)?CNPJ>/)?.[1];
    if (emitente !== emitenteCnpj) continue;
    if (!procurarProdutoEmTodoDump) registrarProduto(xml);
    const natOp = xml.match(/<(?:\w+:)?natOp>([^<]+)<\/(?:\w+:)?natOp>/)?.[1] ?? null;
    const numero = xml.match(/<(?:\w+:)?nNF>(\d+)<\/(?:\w+:)?nNF>/)?.[1] ?? null;
    linhas.push({ documento_fiscal_id: campos[2], numero, natOp });
  }
  documentosTotal = linhas.length;
} else {
  if (!env.NEXT_PUBLIC_SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error("NEXT_PUBLIC_SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY sao obrigatorias.");
  }
  const supabase = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: documentos, error: documentosError } = await supabase
    .schema("f")
    .from("documento_fiscal")
    .select("id,numero,serie,emissao_date,chave_acesso")
    .eq("tenant_id", tenantId)
    .eq("empresa_id", empresaId)
    .gte("emissao_date", "2026-08-01")
    .lt("emissao_date", "2026-09-01")
    .is("deleted_at", null);
  if (documentosError) throw documentosError;

  const ids = (documentos ?? []).map((documento) => documento.id);
  const xmlResult = ids.length
    ? await supabase
        .schema("f")
        .from("documento_fiscal_xml")
        .select("documento_fiscal_id,xml_raw")
        .eq("tenant_id", tenantId)
        .in("documento_fiscal_id", ids)
    : { data: [], error: null };
  if (xmlResult.error) throw xmlResult.error;

  const porId = new Map((documentos ?? []).map((documento) => [documento.id, documento]));
  linhas = (xmlResult.data ?? []).map((row) => {
    registrarProduto(String(row.xml_raw ?? ""), porId.get(row.documento_fiscal_id));
    const match = String(row.xml_raw ?? "").match(/<(?:\w+:)?natOp>([^<]+)<\/(?:\w+:)?natOp>/);
    return { ...porId.get(row.documento_fiscal_id), natOp: match?.[1] ?? null };
  });
  documentosTotal = documentos?.length ?? 0;
}
const naturezas = Object.entries(
  linhas.reduce((acc, row) => {
    const natureza = row.natOp ?? "<AUSENTE>";
    acc[natureza] = (acc[natureza] ?? 0) + 1;
    return acc;
  }, {}),
)
  .map(([texto, notas]) => ({ texto, notas }))
  .sort((a, b) => a.texto.localeCompare(b.texto));

console.log(JSON.stringify({
  tenant_id: tenantId,
  empresa_id: empresaId,
  documentos: documentosTotal,
  xmls: linhas.length,
  naturezas,
  ...(produtoFiltro ? { produto_filtro: produtoFiltro, ocorrencias_produto: ocorrenciasProduto } : {}),
  ...(incluirDetalhes ? { documentos_xml: linhas.sort((a, b) => Number(a.numero ?? 0) - Number(b.numero ?? 0)) } : {}),
}, null, 2));
