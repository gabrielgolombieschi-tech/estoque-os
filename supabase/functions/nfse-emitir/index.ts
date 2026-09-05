import { chamarFocus, focusConfigurado, type FocusAmbiente } from "../_shared/focus-nfe.ts";
import { adminClient, json, mensagemErro, responderOptions, userClient } from "../_shared/nfe-http.ts";
import { montarPayloadNfse, validarPayloadNfseProducaoContraHomologacao, type ContextoNfse } from "../_shared/nfse-payload.ts";
import { aplicarRetornoNfse, normalizarFocusNfse } from "../_shared/nfse-retorno.ts";

/**
 * Emissao da NFS-e Padrao Nacional (POST /v2/nfsen?ref=) em HOMOLOGACAO ou,
 * com body.ambiente = "PRODUCAO", em producao. Mesma disciplina da NF-e:
 * documento e emissao ja existem em RASCUNHO (DPS numerada) antes de qualquer
 * chamada externa; claim duravel; consulta preventiva antes de novo POST na
 * mesma referencia; retry apos rejeicao leva numero novo de DPS.
 *
 * Producao: so com homologacao AUTORIZADA da mesma solicitacao, perfil de
 * servico liberado (trigger de producao) e payload igual ao homologado
 * (validarPayloadNfseProducaoContraHomologacao). A chamada fica atras de
 * FOCUS_NFSE_NACIONAL_ENABLED e das credenciais do ambiente.
 */

type Body = { solicitacao_id?: string; ambiente?: FocusAmbiente };

type Emissao = {
  documento_fiscal_id?: string;
  solicitacao_id?: string;
  referencia_externa: string;
  ambiente: FocusAmbiente;
  tenant_id: string;
  empresa_id: string;
  status: string;
  modelo?: string;
  tentativa_count?: number;
  ultima_tentativa_em?: string | null;
  enviado_em?: string | null;
  payload_enviado?: unknown;
  dps_serie?: number;
  dps_numero?: number;
};

type Claim = {
  deve_enviar?: boolean;
  aguardar?: boolean;
  documento_fiscal_id?: string;
  referencia_externa?: string;
  status?: string;
  tentativa_count?: number;
  payload?: unknown;
};

function isUuid(value: unknown) {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

export function nfseNacionalHabilitada() {
  return Deno.env.get("FOCUS_NFSE_NACIONAL_ENABLED") === "true";
}

Deno.serve(async (request) => {
  const options = responderOptions(request);
  if (options) return options;
  if (request.method !== "POST") return json({ erro: "Metodo nao permitido." }, 405);

  let documentoId: string | null = null;
  let claimVencedor = false;
  let respostaPersistida = false;
  const admin = adminClient();
  try {
    const body = await request.json() as Body;
    if (!isUuid(body.solicitacao_id)) return json({ erro: "solicitacao_id e obrigatorio e deve ser um UUID." }, 400);
    const ambiente: FocusAmbiente = body.ambiente === "PRODUCAO" ? "PRODUCAO" : "HOMOLOGACAO";
    if (!focusConfigurado(ambiente)) {
      return json({ erro: `Emissao em ${ambiente.toLowerCase()} desativada ou sem credencial propria.` }, 503);
    }
    const usuario = userClient(request);

    // 1. Documento RASCUNHO + emissao + DPS numerada (idempotente por referencia e ambiente).
    const { data: criada, error: criarError } = await usuario.schema("f").rpc("fn_nfse_preparar_documento_solicitacao", {
      p_solicitacao_id: body.solicitacao_id,
      p_ambiente: ambiente,
    });
    if (criarError) return json({ erro: criarError.message }, criarError.code === "42501" ? 403 : 422);
    const preparada = Array.isArray(criada) ? criada[0] : criada;
    if (!preparada) throw new Error("O RPC nao devolveu a emissao preparada.");
    documentoId = String(preparada.documento_fiscal_id);

    if (!nfseNacionalHabilitada()) {
      return json({
        erro: "NFS-e Nacional ainda nao habilitada na Focus (FOCUS_NFSE_NACIONAL_ENABLED). O rascunho e a DPS ficaram reservados; nada foi enviado.",
        documento_fiscal_id: documentoId, referencia: preparada.referencia_externa, status: "RASCUNHO",
        dps_serie: preparada.dps_serie, dps_numero: preparada.dps_numero, aguardando_habilitacao: true,
      }, 503);
    }

    const carregarContexto = async () => {
      const { data, error } = await admin.schema("f").rpc("fn_nfe_contexto_emissao", { p_documento_fiscal_id: documentoId });
      if (error) throw new Error(`Nao foi possivel montar o contexto da NFS-e: ${error.message}`);
      if (!data) throw new Error("Contexto da emissao nao encontrado.");
      return data as ContextoNfse;
    };
    let contexto = await carregarContexto();
    let emissao = contexto.emissao as Emissao;
    if (emissao.ambiente !== ambiente) throw new Error(`Emissao bloqueada: a referencia pertence a ${emissao.ambiente}.`);
    if (emissao.modelo !== "NFSE") throw new Error("Emissao bloqueada: a solicitacao nao e de NFS-e.");

    if (["AUTORIZADA", "PROCESSANDO", "CANCELADA"].includes(emissao.status)) {
      return json({ documento_fiscal_id: documentoId, referencia: emissao.referencia_externa, status: emissao.status, idempotente: true });
    }
    const claimRecente = emissao.status === "ENVIANDO"
      && typeof emissao.ultima_tentativa_em === "string"
      && Date.parse(emissao.ultima_tentativa_em) >= Date.now() - 2 * 60 * 1000;
    if (claimRecente) {
      return json({ documento_fiscal_id: documentoId, referencia: emissao.referencia_externa, status: "ENVIANDO", aguardar: true, idempotente: true }, 202);
    }

    // 2. Ja houve tentativa? Consulta a Focus antes de qualquer novo POST.
    const houveTentativa = Number(emissao.tentativa_count ?? 0) > 0 || emissao.payload_enviado != null || emissao.enviado_em != null;
    let reconciliacaoConfirmada = false;
    if (houveTentativa) {
      const consulta = await chamarFocus(`/v2/nfsen/${encodeURIComponent(emissao.referencia_externa)}`, {}, ambiente);
      if (consulta.response.ok) {
        const aplicado = await aplicarRetornoNfse(admin, consulta.body, emissao, "RECONCILIACAO");
        if (["AUTORIZADA", "PROCESSANDO"].includes(aplicado.retorno.status)) {
          return json({ documento_fiscal_id: documentoId, referencia: emissao.referencia_externa, status: aplicado.retorno.status, idempotente: true, reconciliado_antes_do_retry: true },
            aplicado.retorno.status === "PROCESSANDO" ? 202 : 200);
        }
        reconciliacaoConfirmada = true;
        contexto = await carregarContexto();
        emissao = contexto.emissao as Emissao;
      } else if (consulta.response.status === 404) {
        reconciliacaoConfirmada = true;
      } else {
        return json({ erro: `Consulta preventiva da Focus falhou (HTTP ${consulta.response.status}).`, documento_fiscal_id: documentoId, referencia: emissao.referencia_externa }, 502);
      }
    }

    // 3. Retry apos rejeicao: DPS nova (a rejeitada fica queimada).
    if (["REJEITADA", "ERRO"].includes(emissao.status)) {
      const { data: renumerada, error: renumerarError } = await admin.schema("f").rpc("fn_nfse_renumerar_dps", { p_documento_fiscal_id: documentoId });
      if (renumerarError) throw new Error(`Nao foi possivel renumerar a DPS: ${renumerarError.message}`);
      if (renumerada?.renumerada) {
        contexto = await carregarContexto();
        emissao = contexto.emissao as Emissao;
      }
    }

    // 4. Payload a partir do snapshot congelado; producao conferida contra a homologacao autorizada.
    let payload: Record<string, unknown>;
    try {
      payload = montarPayloadNfse(contexto);
      if (ambiente === "PRODUCAO") {
        const { data: hom, error: homError } = await admin.schema("f").from("documento_fiscal_emissao")
          .select("payload_enviado,status").eq("solicitacao_id", String(emissao.solicitacao_id)).eq("ambiente", "HOMOLOGACAO").eq("modelo", "NFSE").maybeSingle();
        if (homError || !hom || hom.status !== "AUTORIZADA") throw new Error("Emissao em producao bloqueada: homologacao autorizada da mesma solicitacao nao encontrada.");
        validarPayloadNfseProducaoContraHomologacao(hom.payload_enviado, payload);
      }
    } catch (cause) {
      return json({ erro: mensagemErro(cause), documento_fiscal_id: documentoId, referencia: emissao.referencia_externa }, 422);
    }

    // 5. Claim duravel.
    const { data: claimData, error: claimError } = await admin.schema("f").rpc("fn_nfse_emissao_claimar", {
      p_documento_fiscal_id: documentoId, p_payload: payload, p_reconciliacao_confirmada: reconciliacaoConfirmada,
    });
    if (claimError) return json({ erro: claimError.message, documento_fiscal_id: documentoId }, claimError.code === "42501" ? 403 : claimError.code === "55000" ? 409 : 422);
    const claim = (claimData ?? {}) as Claim;
    if (!isUuid(claim.documento_fiscal_id) || typeof claim.referencia_externa !== "string") throw new Error("O claim nao devolveu uma emissao valida.");
    if (!claim.deve_enviar) {
      return json({ documento_fiscal_id: documentoId, referencia: claim.referencia_externa, status: claim.status, aguardar: Boolean(claim.aguardar), idempotente: true },
        claim.aguardar || claim.status === "ENVIANDO" || claim.status === "PROCESSANDO" ? 202 : 200);
    }
    if (!claim.payload || typeof claim.payload !== "object") throw new Error("O claim nao devolveu o payload congelado.");
    claimVencedor = true;
    payload = claim.payload as Record<string, unknown>;

    // 6. POST na Focus (token do ambiente).
    const chamada = await chamarFocus(`/v2/nfsen?ref=${encodeURIComponent(claim.referencia_externa)}`, { method: "POST", body: JSON.stringify(payload) }, ambiente);
    const normalizado = normalizarFocusNfse(chamada.body);
    if (!chamada.response.ok) {
      const rejeitada = chamada.response.status >= 400 && chamada.response.status < 500;
      const { error: registrarError } = await admin.schema("f").rpc("fn_nfe_registrar_envio", {
        p_documento_fiscal_id: documentoId, p_payload: payload, p_resposta: normalizado.bruto,
        p_status: rejeitada ? "REJEITADA" : "ERRO", p_codigo_status: chamada.response.status,
        p_mensagem: normalizado.mensagem ?? `Focus respondeu HTTP ${chamada.response.status}.`,
      });
      if (registrarError) throw new Error(`A Focus respondeu, mas o ERP nao gravou a resposta: ${registrarError.message}`);
      respostaPersistida = true;
      await admin.schema("f").rpc("fn_nfse_dps_marcar", {
        p_documento_fiscal_id: documentoId, p_resultado: rejeitada ? "REJEITADO" : "ERRO",
        p_mensagem: normalizado.mensagem ?? `Focus respondeu HTTP ${chamada.response.status}.`,
      });
      return json({
        erro: normalizado.mensagem ?? "A Focus recusou a DPS.", codigo: chamada.response.status, documento_fiscal_id: documentoId,
        referencia: claim.referencia_externa, dps_serie: emissao.dps_serie, dps_numero: emissao.dps_numero,
      }, chamada.response.status >= 500 ? 502 : 422);
    }
    const { error: registrarError } = await admin.schema("f").rpc("fn_nfe_registrar_envio", {
      p_documento_fiscal_id: documentoId, p_payload: payload, p_resposta: normalizado.bruto,
      p_status: normalizado.status === "CANCELADA" ? "ERRO" : normalizado.status, p_codigo_status: normalizado.codigoStatus, p_mensagem: normalizado.mensagem,
    });
    if (registrarError) throw new Error(`A Focus recebeu a DPS, mas o ERP nao gravou o envio: ${registrarError.message}`);
    respostaPersistida = true;

    let resultado = normalizado;
    if (normalizado.status !== "PROCESSANDO") {
      resultado = (await aplicarRetornoNfse(admin, chamada.body, { ...emissao, referencia_externa: claim.referencia_externa }, "ENVIO")).retorno;
    }
    return json({
      documento_fiscal_id: documentoId, referencia: claim.referencia_externa, status: resultado.status, mensagem: resultado.mensagem,
      ambiente, dps_serie: emissao.dps_serie, dps_numero: emissao.dps_numero,
    }, normalizado.status === "PROCESSANDO" ? 202 : 200);
  } catch (cause) {
    const mensagem = mensagemErro(cause);
    if (documentoId && claimVencedor && !respostaPersistida) {
      try {
        await admin.schema("f").rpc("fn_nfe_registrar_envio", { p_documento_fiscal_id: documentoId, p_payload: null, p_resposta: null, p_status: "ERRO", p_codigo_status: null, p_mensagem: mensagem });
      } catch { /* preserva a causa original */ }
    }
    return json({ erro: mensagem, documento_fiscal_id: documentoId }, 500);
  }
});
