import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { chamarFocus, focusConfigurado, type FocusAmbiente } from "../_shared/focus-nfe.ts";
import { adminClient, corsHeaders, json, mensagemErro, responderOptions, userClient } from "../_shared/nfe-http.ts";
import { baixarArquivoNfse, normalizarFocusNfse } from "../_shared/nfse-retorno.ts";

/**
 * Ciclo de vida da NFS-e Nacional: CANCELAR (DELETE /v2/nfsen/<ref>),
 * EMAIL (POST /v2/nfsen/<ref>/email), REGISTRAR_WEBHOOK (POST /v2/hooks,
 * event "nfsen"). Arquivos (XML/DANFSe) continuam pela acao ARQUIVO do
 * nfe-ciclo, que e generica sobre a emissao.
 */
type Acao = "CANCELAR" | "EMAIL" | "REGISTRAR_WEBHOOK";
type Body = { acao?: Acao; documento_fiscal_id?: string; justificativa?: string; emails?: string[]; ambiente?: FocusAmbiente };

function objeto(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
}
function texto(source: Record<string, unknown>, ...keys: string[]) {
  for (const key of keys) {
    const value = source[key];
    if (value !== null && value !== undefined && String(value).trim()) return String(value).trim();
  }
  return null;
}
function validarTexto(value: unknown, min: number, max: number, label: string) {
  const result = String(value ?? "").trim();
  if (result.length < min || result.length > max) throw new Error(`${label} deve ter entre ${min} e ${max} caracteres.`);
  return result;
}

Deno.serve(async (request) => {
  const options = responderOptions(request);
  if (options) return options;
  if (request.method !== "POST") return json({ error: "Metodo nao permitido." }, 405);
  try {
    const body = await request.json() as Body;
    const acao = String(body.acao ?? "").toUpperCase() as Acao;
    const user = userClient(request);
    const { data: authData, error: authError } = await user.auth.getUser();
    if (authError || !authData.user) return json({ error: "Sessao invalida." }, 401);
    const admin = adminClient();

    if (acao === "REGISTRAR_WEBHOOK") {
      // Ambiente HOMOLOGACAO: o hook e registrado na conta de homologacao da Focus.
      const ambiente: FocusAmbiente = "HOMOLOGACAO";
      if (!focusConfigurado(ambiente)) throw new Error("Credencial de homologacao da Focus ausente.");
      const { data: scope, error: scopeError } = await user.schema("f").rpc("fn_operacao_assert_acesso");
      if (scopeError) throw scopeError;
      const escopo = objeto(Array.isArray(scope) ? scope[0] : scope);
      const empresaId = String(escopo.empresa_id ?? "");
      if (!/^[0-9a-f-]{36}$/i.test(empresaId)) throw new Error("Empresa ativa nao identificada.");
      // Schema c nao e exposto pela API; public.empresas espelha id/cnpj.
      const { data: empresa, error: empresaError } = await admin.from("empresas").select("id,cnpj").eq("id", empresaId).maybeSingle();
      if (empresaError || !empresa) throw new Error(`Empresa nao encontrada (${empresaError?.message ?? empresaId}).`);
      const token = Deno.env.get("FOCUS_NFE_WEBHOOK_TOKEN");
      if (!token) throw new Error("FOCUS_NFE_WEBHOOK_TOKEN ausente; o callback exige token.");
      const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/nfse-callback?token=${encodeURIComponent(token)}`;
      const { response, body: hookBody } = await chamarFocus("/v2/hooks", {
        method: "POST",
        body: JSON.stringify({ cnpj: String(empresa.cnpj ?? "").replace(/\D/g, ""), event: "nfsen", url }),
      }, ambiente);
      const hook = objeto(hookBody);
      if (!response.ok) return json({ error: texto(hook, "mensagem") ?? `Focus respondeu HTTP ${response.status}.`, resposta: hook }, 422);
      const hookId = texto(hook, "id");
      const { error: registrarError } = await admin.schema("f").rpc("fn_nfse_registrar_webhook", { p_empresa_id: empresaId, p_hook_id: hookId });
      if (registrarError) throw registrarError;
      return json({ ok: true, hook_id: hookId, event: "nfsen", url_sem_token: url.split("?")[0] });
    }

    const documentoId = String(body.documento_fiscal_id ?? "").trim();
    if (!/^[0-9a-f-]{36}$/i.test(documentoId)) throw new Error("Documento fiscal invalido.");
    const { data: ctxData, error: ctxError } = await user.schema("f").rpc("fn_nfe_ciclo_contexto", { p_documento_fiscal_id: documentoId });
    if (ctxError) throw ctxError;
    const ctx = objeto(ctxData);
    const emissao = objeto(ctx.emissao);
    if (String(emissao.modelo) !== "NFSE") throw new Error("Este documento nao e uma NFS-e.");
    const ambiente = String(emissao.ambiente) as FocusAmbiente;
    if (!["HOMOLOGACAO", "PRODUCAO"].includes(ambiente)) throw new Error("Ambiente fiscal invalido.");
    if (ambiente === "PRODUCAO") throw new Error("Ciclo de vida da NFS-e em producao ainda nao esta liberado.");
    if (!focusConfigurado(ambiente)) throw new Error(`Ciclo de vida em ${ambiente} desativado ou sem credencial propria.`);
    const referencia = String(emissao.referencia_externa ?? "").trim();
    if (!referencia) throw new Error("Emissao sem referencia externa da Focus.");

    if (acao === "CANCELAR") {
      let justificativa = validarTexto(body.justificativa, 15, 255, "Justificativa");
      const reservar = async (claimReconciliado: string | null) => {
        const { data, error } = await admin.schema("f").rpc("fn_nfse_cancelamento_claim", {
          p_documento_fiscal_id: documentoId, p_justificativa: justificativa, p_reconciliacao_claim_id: claimReconciliado,
        });
        if (error) throw error;
        return objeto(data);
      };
      const finalizar = async (eventoClaimId: string, status: "AUTORIZADA" | "REJEITADA", resposta: Record<string, unknown>) => {
        const { error } = await admin.schema("f").rpc("fn_nfse_cancelamento_finalizar", {
          p_documento_fiscal_id: documentoId, p_evento_claim_id: eventoClaimId, p_status: status,
          p_justificativa: justificativa, p_protocolo: texto(resposta, "protocolo"), p_resposta: resposta,
        });
        if (error) throw error;
      };
      let claim = await reservar(null);
      if (claim.deve_reconciliar === true) {
        const claimPendenteId = String(claim.evento_claim_id ?? "");
        justificativa = validarTexto(claim.justificativa_claim, 15, 255, "Justificativa do claim");
        const consulta = await chamarFocus(`/v2/nfsen/${encodeURIComponent(referencia)}`, {}, ambiente);
        if (!consulta.response.ok) return json({ error: `Nao foi possivel reconciliar o cancelamento pendente (HTTP ${consulta.response.status}).`, status: "ENVIANDO", aguardar: true }, 502);
        const consultaNormalizada = normalizarFocusNfse(consulta.body);
        if (consultaNormalizada.status === "CANCELADA") {
          await finalizar(claimPendenteId, "AUTORIZADA", consultaNormalizada.bruto);
          return json({ ok: true, status: "CANCELADA", resposta: consultaNormalizada.bruto, reconciliado_antes_do_retry: true });
        }
        if (consultaNormalizada.status !== "AUTORIZADA") {
          return json({ error: "A Focus ainda nao confirmou se a NFS-e permanece autorizada; o cancelamento continua pendente.", status: "ENVIANDO", aguardar: true }, 202);
        }
        claim = await reservar(claimPendenteId);
      }
      if (claim.deve_cancelar !== true) return json({ ok: true, status: "ENVIANDO", aguardar: true, documento_fiscal_id: documentoId }, 202);
      const eventoClaimId = String(claim.evento_claim_id ?? "");
      justificativa = validarTexto(claim.justificativa_claim, 15, 255, "Justificativa do claim");
      const { response, body: focusBody } = await chamarFocus(`/v2/nfsen/${encodeURIComponent(referencia)}`, {
        method: "DELETE", body: JSON.stringify({ justificativa }),
      }, ambiente);
      let focus = objeto(focusBody);
      // So o corpo "cancelado" cancela (erro_cancelamento tambem chega com 2xx).
      let status: "AUTORIZADA" | "REJEITADA" = response.ok && (texto(focus, "status") ?? "").toLowerCase() === "cancelado" ? "AUTORIZADA" : "REJEITADA";
      if (status !== "AUTORIZADA") {
        const consulta = await chamarFocus(`/v2/nfsen/${encodeURIComponent(referencia)}`, {}, ambiente);
        if (!consulta.response.ok) return json({ error: `Cancelamento sem resposta conclusiva; reconciliacao pendente (HTTP ${consulta.response.status}).`, status: "ENVIANDO", aguardar: true }, 502);
        const consultaNormalizada = normalizarFocusNfse(consulta.body);
        if (consultaNormalizada.status === "CANCELADA") {
          status = "AUTORIZADA";
          focus = { ...consultaNormalizada.bruto, resposta_delete: focus };
        } else if (consultaNormalizada.status !== "AUTORIZADA") {
          return json({ error: "Cancelamento sem estado conclusivo na Focus; reconciliacao pendente.", status: "ENVIANDO", aguardar: true, resposta: consultaNormalizada.bruto }, 202);
        }
      }
      if (status === "AUTORIZADA") {
        // Guarda o XML do evento de cancelamento quando a Focus o devolve.
        const consulta = await chamarFocus(`/v2/nfsen/${encodeURIComponent(referencia)}`, {}, ambiente);
        const caminho = texto(objeto(consulta.body), "caminho_xml_cancelamento");
        if (caminho) {
          try {
            const arquivo = await baixarArquivoNfse(caminho, ambiente);
            const bytes = new Uint8Array(await arquivo.arrayBuffer());
            const path = `${emissao.tenant_id}/${emissao.empresa_id}/${referencia}/cancelamento.xml`;
            const { error: uploadError } = await admin.storage.from("nfe-documentos").upload(path, bytes, { contentType: "application/xml", upsert: true });
            if (uploadError) throw uploadError;
            focus = { ...focus, xml_cancelamento_path: path };
          } catch (erroArquivo) {
            focus = { ...focus, xml_cancelamento_erro: mensagemErro(erroArquivo) };
          }
        }
      }
      await finalizar(eventoClaimId, status, focus);
      if (status !== "AUTORIZADA") return json({ error: normalizarFocusNfse(focus).mensagem ?? "Cancelamento rejeitado.", resposta: focus }, 422);
      return json({ ok: true, status: "CANCELADA", resposta: focus });
    }

    if (acao === "EMAIL") {
      if (String(emissao.status) !== "AUTORIZADA") throw new Error("Envio exige NFS-e autorizada.");
      const emails = Array.from(new Set((body.emails ?? []).map((e) => String(e).trim().toLowerCase()).filter(Boolean)));
      if (!emails.length || emails.length > 10 || emails.some((e) => !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e))) throw new Error("Informe de 1 a 10 e-mails validos.");
      const { response, body: focusBody } = await chamarFocus(`/v2/nfsen/${encodeURIComponent(referencia)}/email`, {
        method: "POST", body: JSON.stringify({ emails }),
      }, ambiente);
      const focus = objeto(focusBody);
      const { error } = await admin.schema("f").rpc("fn_nfe_evento_registrar", {
        p_documento_fiscal_id: documentoId, p_tipo: "EMAIL", p_status: response.ok ? "ENFILEIRADO" : "ERRO",
        p_resposta: { ...focus, anexos: ["XML", "DANFSE"] }, p_destinatarios: emails,
      });
      if (error) throw error;
      if (!response.ok) return json({ error: texto(focus, "mensagem") ?? "Falha ao enfileirar e-mail.", resposta: focus }, 422);
      return json({ ok: true, destinatarios: emails, resposta: focus });
    }

    return json({ error: "Acao invalida." }, 400);
  } catch (error) {
    return new Response(JSON.stringify({ error: mensagemErro(error) }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
