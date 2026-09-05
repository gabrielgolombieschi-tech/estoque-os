import { aplicarRetorno } from "../_shared/nfe-retorno.ts";
import { normalizarFocus } from "../_shared/focus-nfe.ts";
import { adminClient, json, mensagemErro, responderOptions } from "../_shared/nfe-http.ts";

Deno.serve(async (request) => {
  const options = responderOptions(request);
  if (options) return options;
  if (request.method !== "POST") return json({ erro: "Metodo nao permitido." }, 405);

  try {
    const expected = Deno.env.get("FOCUS_NFE_WEBHOOK_TOKEN_PRODUCAO");
    const provided = new URL(request.url).searchParams.get("token") ?? request.headers.get("x-focus-webhook-token");
    if (!expected || !provided || provided !== expected) return json({ erro: "Webhook nao autorizado." }, 401);

    const payload = await request.json();
    const normalizado = normalizarFocus(payload);
    if (!normalizado.referencia) return json({ erro: "Webhook sem referencia da NF-e." }, 400);

    const supabase = adminClient();
    const { data, error } = await supabase.schema("f")
      .from("documento_fiscal_emissao")
      .select("referencia_externa,ambiente,tenant_id,empresa_id,status")
      .eq("referencia_externa", normalizado.referencia)
      .maybeSingle();
    if (error) throw new Error(`Nao foi possivel localizar a emissao: ${error.message}`);
    if (!data) return json({ erro: `Referencia ${normalizado.referencia} nao encontrada.` }, 404);
    if (data.ambiente !== "PRODUCAO") {
      return json({ erro: "Callback recusado: este endpoint aceita somente PRODUCAO." }, 403);
    }

    const resultado = await aplicarRetorno(
      supabase,
      payload,
      { ...data, ambiente: "PRODUCAO" },
      "CALLBACK",
      "fn_nfe_aplicar_retorno_producao",
    );
    return json({ recebido: true, documento_fiscal_id: resultado.documentoFiscalId, status: resultado.retorno.status });
  } catch (cause) {
    return json({ erro: mensagemErro(cause) }, 500);
  }
});
