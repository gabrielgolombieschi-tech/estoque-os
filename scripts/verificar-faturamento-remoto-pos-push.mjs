import fs from "node:fs";
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

const url = env.NEXT_PUBLIC_SUPABASE_URL;
const serviceKey = env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !serviceKey) throw new Error("Credenciais de leitura remota nao encontradas.");

const supabase = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const openApiResponse = await fetch(`${url}/rest/v1/`, {
  headers: {
    apikey: serviceKey,
    authorization: `Bearer ${serviceKey}`,
    accept: "application/openapi+json",
    "accept-profile": "f",
  },
});
if (!openApiResponse.ok) throw new Error(`OpenAPI do schema f respondeu HTTP ${openApiResponse.status}.`);
const openApi = await openApiResponse.json();
const expectedRpcs = [
  "fn_os_itens_saldo_a_faturar",
  "fn_solicitacao_faturamento_criar_parcial",
  "fn_solicitacao_faturamento_criar_os_livre",
  "fn_faturamento_buscar_itens",
  "fn_faturar_documento",
  "fn_solicitacao_nfe_congelar_cadastro",
  "fn_nfe_preparar_documento_solicitacao",
  "fn_nfe_contexto_emissao",
  "fn_os_saldo_a_faturar",
];
const missingRpcs = expectedRpcs.filter((name) => !openApi.paths?.[`/rpc/${name}`]);
if (missingRpcs.length > 0) throw new Error(`RPCs ausentes no schema remoto: ${missingRpcs.join(", ")}`);

const [{ data: origens, error: origensError }, { data: linhasOrigem, error: linhasOrigemError }] = await Promise.all([
  supabase
    .from("ordens_servico")
    .select("id,tenant_id,empresa_id,tipo_documento,codigo,numero_os")
    .in("tipo_documento", ["OS", "OV"])
    .not("empresa_id", "is", null)
    .order("id", { ascending: false })
    .limit(1000),
  supabase
    .from("os_itens")
    .select("os_id,tenant_id,empresa_id")
    .not("os_id", "is", null)
    .order("id", { ascending: false })
    .limit(5000),
]);
if (origensError) throw origensError;
if (linhasOrigemError) throw linhasOrigemError;

const origemComLinha = new Set((linhasOrigem ?? []).map((row) => `${row.tenant_id}:${row.empresa_id}:${row.os_id}`));
const ov = origens?.find((row) => row.tipo_documento === "OV" && origemComLinha.has(`${row.tenant_id}:${row.empresa_id}:${row.id}`));
const os = origens?.find((row) => row.tipo_documento === "OS");
if (!ov || !os) throw new Error("Nao foi possivel localizar uma OS e uma OV reais para o smoke somente leitura.");

async function saldoValor(origem) {
  const { data, error } = await supabase.schema("f").rpc("fn_os_saldo_a_faturar", {
    p_tenant_id: origem.tenant_id,
    p_empresa_id: origem.empresa_id,
    p_os_id: origem.id,
  });
  if (error) throw new Error(`Saldo por valor da ${origem.tipo_documento} ${origem.id}: ${error.message}`);
  if (!Array.isArray(data) || data.length !== 1 || !("valor_reservado" in data[0])) {
    throw new Error(`Saldo por valor da ${origem.tipo_documento} ${origem.id} nao retornou o contrato novo.`);
  }
  return data[0];
}

const [saldoOs, saldoOv] = await Promise.all([saldoValor(os), saldoValor(ov)]);
const { data: itensOv, error: itensOvError } = await supabase.schema("f").rpc("fn_os_itens_saldo_a_faturar", {
  p_tenant_id: ov.tenant_id,
  p_empresa_id: ov.empresa_id,
  p_os_id: ov.id,
});
if (itensOvError) throw new Error(`Saldo por item da OV ${ov.id}: ${itensOvError.message}`);
if (!Array.isArray(itensOv)) throw new Error("Saldo por item nao retornou uma lista.");
for (const item of itensOv) {
  for (const field of ["quantidade_total", "quantidade_faturada", "saldo"]) {
    if (!Number.isFinite(Number(item[field]))) throw new Error(`Campo ${field} invalido no saldo por item.`);
  }
}

const { error: snapshotColumnsError } = await supabase
  .schema("f")
  .from("solicitacao_faturamento")
  .select("id,emitente_snapshot,destinatario_snapshot,operacao_snapshot,snapshot_cadastro_em")
  .limit(1);
if (snapshotColumnsError) throw new Error(`Colunas de snapshot ausentes: ${snapshotColumnsError.message}`);

console.log(JSON.stringify({
  remoto: true,
  rpcs_confirmadas: expectedRpcs.length,
  os_consultada: os.id,
  ov_consultada: ov.id,
  saldo_os: saldoOs.saldo,
  saldo_ov: saldoOv.saldo,
  linhas_ov_calculadas: itensOv.length,
  snapshots_disponiveis: true,
  escrita_realizada: false,
}, null, 2));
