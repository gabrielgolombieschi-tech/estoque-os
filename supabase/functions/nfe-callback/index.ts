import { aplicarRetorno } from "../_shared/nfe-retorno.ts";
import { normalizarFocus } from "../_shared/focus-nfe.ts";
import { adminClient, json, mensagemErro, responderOptions } from "../_shared/nfe-http.ts";

Deno.serve(async (request) => {
  const options = responderOptions(request);
  if (options) return options;
  if (request.method !== "POST") return json({ erro: "Método não permitido." }, 405);

  try {
    const expected = Deno.env.get("FOCUS_NFE_WEBHOOK_TOKEN");
    const provided = new URL(request.url).searchParams.get("token") ?? request.headers.get("x-focus-webhook-token");
    if (!expected || !provided || provided !== expected) return json({ erro: "Webhook não autorizado." }, 401);

    const payload = await request.json();
    const normalizado = normalizarFocus(payload);
    if (!normalizado.referencia) return json({ erro: "Webhook sem referência da NF-e." }, 400);

    const supabase = adminClient();
    const { data, error } = await supabase.schema("f")
      .from("documento_fiscal_emissao")
      .select("referencia_externa,ambiente,tenant_id,empresa_id,status")
      .eq("referencia_externa", normalizado.referencia)
      .maybeSingle();
    if (error) throw new Error(`Não foi possível localizar a emissão: ${error.message}`);
    if (!data) return json({ erro: `Referência ${normalizado.referencia} não encontrada.` }, 404);
    if (data.ambiente !== "HOMOLOGACAO") {
      return json({ erro: "Callback recusado: este endpoint aceita somente HOMOLOGACAO." }, 403);
    }

    const resultado = await aplicarRetorno(supabase, payload, data, "CALLBACK");
    return json({ recebido: true, documento_fiscal_id: resultado.documentoFiscalId, status: resultado.retorno.status });
  } catch (cause) {
    return json({ erro: mensagemErro(cause) }, 500);
  }
});
