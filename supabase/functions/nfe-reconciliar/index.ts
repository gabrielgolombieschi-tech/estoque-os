import { aplicarRetorno } from "../_shared/nfe-retorno.ts";
import { chamarFocus, focusConfigurado, normalizarFocus, type FocusAmbiente } from "../_shared/focus-nfe.ts";
import { adminClient, json, mensagemErro, responderOptions } from "../_shared/nfe-http.ts";

type Pendente = { documento_fiscal_id: string; referencia_externa: string; ambiente: FocusAmbiente };

Deno.serve(async (request) => {
  const options = responderOptions(request);
  if (options) return options;
  if (request.method !== "POST") return json({ erro: "Metodo nao permitido." }, 405);
  if (request.headers.get("authorization") !== `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`) {
    return json({ erro: "Reconciliacao nao autorizada." }, 401);
  }

  try {
    const supabase = adminClient();
    const consultas = await Promise.all([
      supabase.schema("f").rpc("fn_nfe_emissoes_pendentes_reconciliacao", { p_limite: 50 }),
      focusConfigurado("PRODUCAO")
        ? supabase.schema("f").rpc("fn_nfe_emissoes_pendentes_reconciliacao_producao", { p_limite: 50 })
        : Promise.resolve({ data: [], error: null }),
    ]);
    if (consultas[0].error) {
      throw new Error(`Nao foi possivel listar emissoes pendentes de homologacao: ${consultas[0].error.message}`);
    }
    if (consultas[1].error) {
      throw new Error(`Nao foi possivel listar emissoes pendentes de producao: ${consultas[1].error.message}`);
    }
    const pendentes = [
      ...((consultas[0].data ?? []) as Pendente[]),
      ...((consultas[1].data ?? []) as Pendente[]),
    ];
    const resultados: Array<Record<string, unknown>> = [];

    for (const pendente of pendentes) {
      try {
        const { data: emissao, error: emissaoError } = await supabase.schema("f")
          .from("documento_fiscal_emissao")
          .select("referencia_externa,ambiente,tenant_id,empresa_id,status")
          .eq("documento_fiscal_id", pendente.documento_fiscal_id)
          .single();
        if (emissaoError) throw emissaoError;
        if (emissao.ambiente !== pendente.ambiente || !["HOMOLOGACAO", "PRODUCAO"].includes(emissao.ambiente)) {
          throw new Error("Reconciliacao recusada: ambiente inconsistente.");
        }
        const ambiente = emissao.ambiente as FocusAmbiente;
        if (!focusConfigurado(ambiente)) {
          throw new Error(`Reconciliacao de ${ambiente} desativada ou sem credencial propria.`);
        }
        const chamada = await chamarFocus(
          `/v2/nfe/${encodeURIComponent(pendente.referencia_externa)}?completa=1`,
          {},
          ambiente,
        );
        if (!chamada.response.ok) {
          const normalizado = normalizarFocus(chamada.body);
          if (chamada.response.status === 404) {
            const rpcRetorno = ambiente === "PRODUCAO"
              ? "fn_nfe_aplicar_retorno_producao"
              : "fn_nfe_aplicar_retorno";
            await supabase.schema("f").rpc(rpcRetorno, {
              p_referencia_externa: pendente.referencia_externa,
              p_resposta: normalizado.bruto,
              p_status: "ERRO",
              p_codigo_status: 404,
              p_mensagem: "A Focus nao encontrou a referencia apos 10 minutos; revisao manual necessaria.",
              p_origem_retorno: "RECONCILIACAO",
            });
          }
          resultados.push({
            referencia: pendente.referencia_externa,
            ambiente,
            status: "ERRO",
            http: chamada.response.status,
          });
          continue;
        }
        const aplicado = await aplicarRetorno(
          supabase,
          chamada.body,
          emissao as Pendente & { tenant_id: string; empresa_id: string },
          "RECONCILIACAO",
          ambiente === "PRODUCAO" ? "fn_nfe_aplicar_retorno_producao" : "fn_nfe_aplicar_retorno",
        );
        resultados.push({ referencia: pendente.referencia_externa, ambiente, status: aplicado.retorno.status });
      } catch (cause) {
        resultados.push({
          referencia: pendente.referencia_externa,
          ambiente: pendente.ambiente,
          status: "ERRO",
          mensagem: mensagemErro(cause),
        });
      }
    }

    return json({ consultadas: pendentes.length, resultados });
  } catch (cause) {
    return json({ erro: mensagemErro(cause) }, 500);
  }
});
