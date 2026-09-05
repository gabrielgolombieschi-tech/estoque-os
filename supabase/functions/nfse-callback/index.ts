import { adminClient, json, mensagemErro, responderOptions } from "../_shared/nfe-http.ts";
import { aplicarRetornoNfse, normalizarFocusNfse } from "../_shared/nfse-retorno.ts";

/**
 * Webhook da Focus para NFS-e Nacional (event "nfsen"). Mesmo token da
 * homologacao da NF-e (FOCUS_NFE_WEBHOOK_TOKEN, ?token=). Idempotente: a
 * emissao ja AUTORIZADA ignora repeticoes em f.fn_nfse_aplicar_retorno.
 */
Deno.serve(async (request) => {
  const options = responderOptions(request);
  if (options) return options;
  if (request.method !== "POST") return json({ erro: "Metodo nao permitido." }, 405);
  try {
    const expected = Deno.env.get("FOCUS_NFE_WEBHOOK_TOKEN");
    const provided = new URL(request.url).searchParams.get("token") ?? request.headers.get("x-focus-webhook-token");
    if (!expected || !provided || provided !== expected) return json({ erro: "Webhook nao autorizado." }, 401);

    const payload = await request.json();
    const normalizado = normalizarFocusNfse(payload);
    if (!normalizado.referencia) return json({ erro: "Webhook sem referencia da NFS-e." }, 400);

    const supabase = adminClient();
    const { data, error } = await supabase.schema("f")
      .from("documento_fiscal_emissao")
      .select("referencia_externa,ambiente,tenant_id,empresa_id,status,modelo")
      .eq("referencia_externa", normalizado.referencia)
      .maybeSingle();
    if (error) throw new Error(`Nao foi possivel localizar a emissao: ${error.message}`);
    if (!data) return json({ erro: `Referencia ${normalizado.referencia} nao encontrada.` }, 404);
    if (data.modelo !== "NFSE") return json({ erro: "Callback recusado: a referencia nao e de NFS-e." }, 409);
    if (data.ambiente !== "HOMOLOGACAO") return json({ erro: "Callback recusado: este endpoint aceita somente HOMOLOGACAO." }, 403);

    const resultado = await aplicarRetornoNfse(supabase, payload, data, "CALLBACK");
    return json({ recebido: true, documento_fiscal_id: resultado.documentoFiscalId, status: resultado.retorno.status });
  } catch (cause) {
    return json({ erro: mensagemErro(cause) }, 500);
  }
});
