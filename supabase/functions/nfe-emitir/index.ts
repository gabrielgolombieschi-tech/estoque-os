import { aplicarRetorno } from "../_shared/nfe-retorno.ts";
import { chamarFocus, focusConfigurado, normalizarFocus } from "../_shared/focus-nfe.ts";
import { adminClient, json, mensagemErro, responderOptions, userClient } from "../_shared/nfe-http.ts";
import { montarPayloadNfe, type ContextoEmissao } from "../_shared/nfe-payload.ts";

type Body = {
  acao?: "EMITIR" | "ABANDONAR_REJEITADA";
  solicitacao_id?: string;
  justificativa?: string;
};

type EstadoHomologacao = {
  existe?: boolean;
  tenant_id?: string;
  empresa_id?: string;
  solicitacao_id?: string;
  documento_fiscal_id?: string;
  referencia_externa?: string;
  status?: string;
};

type EmissaoHomologacao = {
  documento_fiscal_id?: string;
  solicitacao_id?: string;
  referencia_externa: string;
  ambiente: "HOMOLOGACAO";
  tenant_id: string;
  empresa_id: string;
  status: string;
  tentativa_count?: number;
  ultima_tentativa_em?: string | null;
  enviado_em?: string | null;
  payload_enviado?: unknown;
};

type ClaimHomologacao = {
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

function validarJustificativa(value: unknown) {
  const justificativa = String(value ?? "").trim();
  if (justificativa.length < 15 || justificativa.length > 255) {
    throw new Error("A justificativa deve ter entre 15 e 255 caracteres.");
  }
  return justificativa;
}

async function registrarFalha(admin: ReturnType<typeof adminClient>, documentoId: string, mensagem: string) {
  await admin.schema("f").rpc("fn_nfe_registrar_envio", {
    p_documento_fiscal_id: documentoId,
    p_payload: null,
    p_resposta: null,
    p_status: "ERRO",
    p_codigo_status: null,
    p_mensagem: mensagem,
  });
}

Deno.serve(async (request) => {
  const options = responderOptions(request);
  if (options) return options;
  if (request.method !== "POST") return json({ erro: "Metodo nao permitido." }, 405);

  let documentoId: string | null = null;
  let claimVencedor = false;
  let respostaPersistida = false;
  try {
    const body = await request.json() as Body;
    if (!isUuid(body.solicitacao_id)) {
      return json({ erro: "solicitacao_id e obrigatorio e deve ser um UUID." }, 400);
    }
    const acao = body.acao ?? "EMITIR";
    if (acao !== "EMITIR" && acao !== "ABANDONAR_REJEITADA") {
      return json({ erro: "Acao invalida." }, 400);
    }
    if (!focusConfigurado("HOMOLOGACAO")) {
      return json({ erro: "Emissao de homologacao desativada ou sem credencial propria." }, 503);
    }

    const usuario = userClient(request);
    const admin = adminClient();
    if (acao === "ABANDONAR_REJEITADA") {
      let justificativa: string;
      try {
        justificativa = validarJustificativa(body.justificativa);
      } catch (cause) {
        return json({ erro: mensagemErro(cause) }, 400);
      }
      const { data: estadoData, error: estadoError } = await usuario.schema("f").rpc(
        "fn_nfe_homologacao_estado",
        { p_solicitacao_id: body.solicitacao_id },
      );
      if (estadoError) {
        return json({ erro: estadoError.message }, estadoError.code === "42501" ? 403 : 422);
      }
      const estado = (estadoData ?? {}) as EstadoHomologacao;
      if (
        !estado.existe
        || !isUuid(estado.documento_fiscal_id)
        || typeof estado.referencia_externa !== "string"
        || !isUuid(estado.tenant_id)
        || !isUuid(estado.empresa_id)
      ) {
        return json({ erro: "Nao existe emissao de homologacao ativa para abandonar." }, 404);
      }
      documentoId = estado.documento_fiscal_id;
      const { data: contextoData, error: contextoError } = await admin.schema("f").rpc("fn_nfe_contexto_emissao", {
        p_documento_fiscal_id: documentoId,
      });
      if (contextoError || !contextoData) {
        return json({ erro: contextoError?.message ?? "Contexto da homologacao nao encontrado." }, 422);
      }
      const emissao = (contextoData as ContextoEmissao).emissao as EmissaoHomologacao;
      if (
        emissao.documento_fiscal_id !== documentoId
        || emissao.solicitacao_id !== body.solicitacao_id
        || emissao.tenant_id !== estado.tenant_id
        || emissao.empresa_id !== estado.empresa_id
        || emissao.ambiente !== "HOMOLOGACAO"
      ) {
        return json({ erro: "Escopo da homologacao inconsistente; abandono bloqueado." }, 409);
      }
      const consulta = await chamarFocus(`/v2/nfe/${encodeURIComponent(emissao.referencia_externa)}?completa=1`);
      if (!consulta.response.ok) {
        return json({
          erro: consulta.response.status === 404
            ? "A referencia nao foi encontrada na Focus; 404 nao prova rejeicao e o saldo permanece reservado."
            : `Nao foi possivel comprovar a rejeicao na Focus (HTTP ${consulta.response.status}).`,
          documento_fiscal_id: documentoId,
          referencia: emissao.referencia_externa,
        }, consulta.response.status === 404 ? 409 : 502);
      }
      const comprovacao = normalizarFocus(consulta.body);
      await aplicarRetorno(admin, consulta.body, emissao, "RECONCILIACAO");
      if (comprovacao.status !== "REJEITADA") {
        return json({
          erro: `Abandono bloqueado: a Focus confirmou status ${comprovacao.status}, nao REJEITADA.`,
          documento_fiscal_id: documentoId,
          referencia: emissao.referencia_externa,
          status: comprovacao.status,
        }, 409);
      }
      const { data: abandonoData, error: abandonoError } = await admin.schema("f").rpc(
        "fn_nfe_homologacao_abandonar_rejeitada",
        {
          p_documento_fiscal_id: documentoId,
          p_referencia_externa: emissao.referencia_externa,
          p_status_focus: comprovacao.status,
          p_justificativa: justificativa,
          p_prova_focus: comprovacao.bruto,
          p_codigo_status: comprovacao.codigoStatus,
          p_mensagem: comprovacao.mensagem,
        },
      );
      if (abandonoError) {
        return json({ erro: abandonoError.message, documento_fiscal_id: documentoId },
          abandonoError.code === "42501" ? 403 : abandonoError.code === "55000" ? 409 : 422);
      }
      return json({
        ...(abandonoData as Record<string, unknown>),
        referencia: emissao.referencia_externa,
        rejeicao_comprovada: true,
      });
    }

    const { data: criada, error: criarError } = await usuario.schema("f").rpc(
      "fn_nfe_preparar_documento_solicitacao",
      { p_solicitacao_id: body.solicitacao_id },
    );
    if (criarError) return json({ erro: criarError.message }, criarError.code === "42501" ? 403 : 422);
    const emissaoCriada = Array.isArray(criada) ? criada[0] : criada;
    if (!emissaoCriada) throw new Error("O RPC nao devolveu a emissao preparada.");
    documentoId = String(emissaoCriada.documento_fiscal_id);

    const { data: contextoData, error: contextoError } = await admin.schema("f").rpc("fn_nfe_contexto_emissao", {
      p_documento_fiscal_id: documentoId,
    });
    if (contextoError) throw new Error(`Nao foi possivel montar o contexto fiscal: ${contextoError.message}`);
    if (!contextoData) throw new Error("Contexto da emissao nao encontrado.");
    const contexto = contextoData as ContextoEmissao;
    const emissao = contexto.emissao as EmissaoHomologacao;
    if (emissao.ambiente !== "HOMOLOGACAO") {
      throw new Error("Emissao bloqueada: o endpoint aceita somente HOMOLOGACAO.");
    }

    if (emissao.status === "AUTORIZADA" || emissao.status === "PROCESSANDO" || emissao.status === "CANCELADA") {
      return json({
        documento_fiscal_id: documentoId,
        referencia: emissao.referencia_externa,
        status: emissao.status,
        idempotente: true,
      });
    }

    const claimRecente = emissao.status === "ENVIANDO"
      && typeof emissao.ultima_tentativa_em === "string"
      && Number.isFinite(Date.parse(emissao.ultima_tentativa_em))
      && Date.parse(emissao.ultima_tentativa_em) >= Date.now() - 2 * 60 * 1000;
    if (claimRecente) {
      return json({
        documento_fiscal_id: documentoId,
        referencia: emissao.referencia_externa,
        status: "ENVIANDO",
        aguardar: true,
        idempotente: true,
      }, 202);
    }

    const houveTentativa = Number(emissao.tentativa_count ?? 0) > 0
      || emissao.payload_enviado != null
      || emissao.enviado_em != null;
    let reconciliacaoConfirmada = false;
    if (houveTentativa) {
      let consulta = await chamarFocus(`/v2/nfe/${encodeURIComponent(emissao.referencia_externa)}?completa=1`);
      const completaNormalizada = consulta.response.ok ? normalizarFocus(consulta.body) : null;
      // Algumas contas da Focus retornam a consulta completa sem os artefatos da
      // autorização. A consulta resumida é a fonte alternativa oficial e mantém
      // a mesma referência, portanto não cria nem reenvia a NF-e.
      if (completaNormalizada?.status === "AUTORIZADA" && !completaNormalizada.chaveAcesso) {
        const resumida = await chamarFocus(`/v2/nfe/${encodeURIComponent(emissao.referencia_externa)}`);
        if (resumida.response.ok && normalizarFocus(resumida.body).chaveAcesso) consulta = resumida;
      }
      if (consulta.response.ok) {
        const aplicado = await aplicarRetorno(admin, consulta.body, emissao, "RECONCILIACAO");
        if (["AUTORIZADA", "PROCESSANDO"].includes(aplicado.retorno.status)) {
          return json({
            documento_fiscal_id: documentoId,
            referencia: emissao.referencia_externa,
            status: aplicado.retorno.status,
            idempotente: true,
            reconciliado_antes_do_retry: true,
          }, aplicado.retorno.status === "PROCESSANDO" ? 202 : 200);
        }
        // Rejeicao confirmada nao e beco sem saida: nada foi autorizado e nenhum
        // numero foi consumido na SEFAZ. A referencia velha ja teve desfecho na
        // Focus e nao pode ser reusada, entao a emissao volta a RASCUNHO com uma
        // referencia nova e o payload recusado descartado — e o fluxo segue abaixo
        // montando o payload de novo, agora com o cadastro ja corrigido.
        if (aplicado.retorno.status === "REJEITADA") {
          const { data: recomeco, error: recomecoError } = await admin.schema("f").rpc(
            "fn_nfe_recomecar_rejeitada",
            {
              p_documento_fiscal_id: documentoId,
              p_referencia_externa: emissao.referencia_externa,
              p_status_focus: aplicado.retorno.status,
              p_prova_focus: consulta.body ?? null,
              p_codigo_status: aplicado.retorno.codigoStatus ?? null,
              p_mensagem: aplicado.retorno.mensagem ?? null,
            },
          );
          if (recomecoError) {
            return json({
              erro: `A nota foi rejeitada e o recomeco automatico falhou: ${recomecoError.message}`,
              codigo: aplicado.retorno.codigoStatus,
              documento_fiscal_id: documentoId,
              referencia: emissao.referencia_externa,
              status: aplicado.retorno.status,
            }, recomecoError.code === "42501" ? 403 : 422);
          }
          const referenciaNova = (recomeco as { referencia_externa?: string } | null)?.referencia_externa;
          if (typeof referenciaNova !== "string" || !referenciaNova) {
            throw new Error("O recomeco da emissao rejeitada nao devolveu a referencia nova.");
          }
          emissao.referencia_externa = referenciaNova;
          emissao.status = "RASCUNHO";
          emissao.payload_enviado = null;
          emissao.enviado_em = null;
          emissao.tentativa_count = 0;
          reconciliacaoConfirmada = true;
        } else {
          return json({
            erro: aplicado.retorno.mensagem ?? "A Focus confirmou que a referencia de homologacao nao foi autorizada.",
            codigo: aplicado.retorno.codigoStatus,
            documento_fiscal_id: documentoId,
            referencia: emissao.referencia_externa,
            status: aplicado.retorno.status,
            reconciliado_antes_do_retry: true,
          }, aplicado.retorno.status === "ERRO" ? 502 : 422);
        }
      } else {
        if (consulta.response.status !== 404) {
          return json({
            erro: `Consulta preventiva da Focus falhou (HTTP ${consulta.response.status}).`,
            documento_fiscal_id: documentoId,
            referencia: emissao.referencia_externa,
          }, 502);
        }
        reconciliacaoConfirmada = true;
      }
    }

    let payload: ReturnType<typeof montarPayloadNfe>;
    try {
      const payloadAtual = montarPayloadNfe(contexto);
      if (emissao.payload_enviado && typeof emissao.payload_enviado === "object" && !Array.isArray(emissao.payload_enviado)) {
        payload = emissao.payload_enviado as ReturnType<typeof montarPayloadNfe>;
      } else {
        payload = payloadAtual;
      }
    } catch (cause) {
      const mensagem = mensagemErro(cause);
      return json({ erro: mensagem, documento_fiscal_id: documentoId, referencia: emissao.referencia_externa }, 422);
    }

    const { data: claimData, error: claimError } = await admin.schema("f").rpc(
      "fn_nfe_homologacao_claimar",
      {
        p_documento_fiscal_id: documentoId,
        p_payload: payload,
        p_reconciliacao_confirmada: reconciliacaoConfirmada,
      },
    );
    if (claimError) {
      return json({ erro: claimError.message, documento_fiscal_id: documentoId },
        claimError.code === "42501" ? 403 : claimError.code === "55000" ? 409 : 422);
    }
    const claim = (claimData ?? {}) as ClaimHomologacao;
    if (!isUuid(claim.documento_fiscal_id) || typeof claim.referencia_externa !== "string") {
      throw new Error("O claim de homologacao nao devolveu uma emissao valida.");
    }
    documentoId = claim.documento_fiscal_id;
    if (!claim.deve_enviar) {
      return json({
        documento_fiscal_id: documentoId,
        referencia: claim.referencia_externa,
        status: claim.status,
        aguardar: Boolean(claim.aguardar),
        idempotente: true,
      }, claim.aguardar || claim.status === "ENVIANDO" || claim.status === "PROCESSANDO" ? 202 : 200);
    }
    if (!claim.payload || typeof claim.payload !== "object" || Array.isArray(claim.payload)) {
      throw new Error("O claim de homologacao nao devolveu o payload fiscal congelado.");
    }
    claimVencedor = true;
    payload = claim.payload as ReturnType<typeof montarPayloadNfe>;
    const emissaoClaimada: EmissaoHomologacao = {
      ...emissao,
      documento_fiscal_id: documentoId,
      referencia_externa: claim.referencia_externa,
      status: "ENVIANDO",
      tentativa_count: claim.tentativa_count,
      payload_enviado: payload,
    };

    const chamada = await chamarFocus(
      `/v2/nfe?ref=${encodeURIComponent(claim.referencia_externa)}`,
      { method: "POST", body: JSON.stringify(payload) },
    );
    const normalizado = normalizarFocus(chamada.body);
    if (!chamada.response.ok) {
      const { error: registrarError } = await admin.schema("f").rpc("fn_nfe_registrar_envio", {
        p_documento_fiscal_id: documentoId,
        p_payload: payload,
        p_resposta: normalizado.bruto,
        p_status: chamada.response.status >= 400 && chamada.response.status < 500 ? "REJEITADA" : "ERRO",
        p_codigo_status: normalizado.codigoStatus ?? chamada.response.status,
        p_mensagem: normalizado.mensagem ?? `Focus respondeu HTTP ${chamada.response.status}.`,
      });
      if (registrarError) throw new Error(`A Focus respondeu, mas o ERP nao gravou a resposta: ${registrarError.message}`);
      respostaPersistida = true;
      return json({
        erro: normalizado.mensagem ?? "A Focus recusou a emissao.",
        codigo: normalizado.codigoStatus ?? chamada.response.status,
        documento_fiscal_id: documentoId,
        referencia: claim.referencia_externa,
      }, chamada.response.status >= 500 ? 502 : 422);
    }

    const { error: registrarError } = await admin.schema("f").rpc("fn_nfe_registrar_envio", {
      p_documento_fiscal_id: documentoId,
      p_payload: payload,
      p_resposta: normalizado.bruto,
      p_status: normalizado.status,
      p_codigo_status: normalizado.codigoStatus,
      p_mensagem: normalizado.mensagem,
    });
    if (registrarError) throw new Error(`A Focus recebeu a nota, mas o ERP nao gravou o envio: ${registrarError.message}`);
    respostaPersistida = true;

    let resultado = normalizado;
    if (normalizado.status !== "PROCESSANDO") {
      resultado = (await aplicarRetorno(admin, chamada.body, emissaoClaimada, "ENVIO")).retorno;
    }
    return json({
      documento_fiscal_id: documentoId,
      referencia: claim.referencia_externa,
      status: resultado.status,
      mensagem: resultado.mensagem,
    }, normalizado.status === "PROCESSANDO" ? 202 : 200);
  } catch (cause) {
    const mensagem = mensagemErro(cause);
    if (documentoId && claimVencedor && !respostaPersistida) {
      try {
        await registrarFalha(adminClient(), documentoId, mensagem);
      } catch {
        // Preserva a causa original, que e mais util para a pessoa corrigir.
      }
    }
    return json({ erro: mensagem, documento_fiscal_id: documentoId }, 500);
  }
});
