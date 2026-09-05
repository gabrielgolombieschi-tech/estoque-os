import { aplicarRetorno } from "../_shared/nfe-retorno.ts";
import { chamarFocus, focusConfigurado, normalizarFocus } from "../_shared/focus-nfe.ts";
import { adminClient, json, mensagemErro, responderOptions, userClient } from "../_shared/nfe-http.ts";
import {
  montarPayloadNfe,
  type ContextoEmissao,
  validarPayloadProducaoContraHomologacao,
} from "../_shared/nfe-payload.ts";

type Body = {
  acao?: "STATUS" | "EMITIR" | "ABANDONAR_REJEITADA";
  solicitacao_id?: string;
  confirmacao_contexto_hash?: string;
  justificativa?: string;
};

type Prontidao = {
  pronta?: boolean;
  motivo?: string;
  perfil_operacao_id?: string;
  perfil_operacao_ids?: string[];
  homologacao_documento_fiscal_id?: string;
  tenant_id?: string;
  empresa_id?: string;
};

type EstadoProducao = {
  existe?: boolean;
  tenant_id?: string;
  empresa_id?: string;
  solicitacao_id?: string;
  documento_fiscal_id?: string;
  status?: string;
  claim_recente?: boolean;
  houve_claim?: boolean;
  homologacao_documento_fiscal_id?: string;
  contexto_hash?: string;
  confirmacao_nome_destinatario?: string;
  confirmacao_tipo_documento_destinatario?: string;
  confirmacao_documento_destinatario?: string;
  confirmacao_valor_total?: number;
};

type EmissaoContexto = {
  documento_fiscal_id?: string;
  solicitacao_id?: string;
  referencia_externa: string;
  ambiente: "HOMOLOGACAO" | "PRODUCAO";
  tenant_id: string;
  empresa_id: string;
  status: string;
  tentativa_count?: number;
  ultima_tentativa_em?: string | null;
  payload_enviado?: unknown;
};

type PreflightProducao = {
  tenant_id?: string;
  empresa_id?: string;
  solicitacao_id?: string;
  homologacao_documento_fiscal_id?: string;
  contexto_hash?: string;
  contexto?: ContextoEmissao;
};

type ClaimProducao = {
  deve_enviar?: boolean;
  aguardar?: boolean;
  documento_fiscal_id?: string;
  referencia_externa?: string;
  status?: string;
  tentativa_count?: number;
  payload?: unknown;
};

function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function mascararDocumentoFiscal(value: unknown) {
  const documento = String(value ?? "").replace(/\D/g, "");
  if (documento.length === 14) return `**.***.***/${documento.slice(8, 12)}-${documento.slice(12)}`;
  if (documento.length === 11) return `***.***.${documento.slice(6, 9)}-${documento.slice(9)}`;
  return null;
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

    const usuario = userClient(request);
    const { data: prontidaoData, error: prontidaoError } = await usuario.schema("f").rpc(
      "fn_nfe_producao_pronta",
      { p_solicitacao_id: body.solicitacao_id },
    );
    if (prontidaoError) {
      return json({ erro: prontidaoError.message }, prontidaoError.code === "42501" ? 403 : 422);
    }
    const prontidao = (prontidaoData ?? {}) as Prontidao;
    const edgeConfigurada = focusConfigurado("PRODUCAO");

    if ((body.acao ?? "STATUS") === "STATUS") {
      let resumoConfirmacao: Record<string, unknown> | null = null;
      let erroPreflight: string | null = null;
      let retomadaExistente = false;
      if (prontidao.pronta) {
        try {
          const { data: preflightData, error: preflightError } = await usuario.schema("f").rpc(
            "fn_nfe_producao_preflight",
            { p_solicitacao_id: body.solicitacao_id },
          );
          if (preflightError) throw new Error(preflightError.message);
          const preflight = (preflightData ?? {}) as PreflightProducao;
          if (
            preflight.solicitacao_id !== body.solicitacao_id
            || preflight.tenant_id !== prontidao.tenant_id
            || preflight.empresa_id !== prontidao.empresa_id
            || preflight.homologacao_documento_fiscal_id !== prontidao.homologacao_documento_fiscal_id
            || typeof preflight.contexto_hash !== "string"
            || !/^[0-9a-f]{64}$/.test(preflight.contexto_hash)
            || !preflight.contexto
          ) {
            throw new Error("O preflight devolveu homologacao, escopo ou hash fiscal inconsistente.");
          }
          const emissaoHomologacao = preflight.contexto.emissao as EmissaoContexto;
          const payloadConfirmacao = montarPayloadNfe({
            ...preflight.contexto,
            emissao: { ...preflight.contexto.emissao, ambiente: "PRODUCAO" },
          });
          validarPayloadProducaoContraHomologacao(emissaoHomologacao.payload_enviado, payloadConfirmacao);
          const cnpj = (payloadConfirmacao as Record<string, unknown>).cnpj_destinatario;
          const cpf = (payloadConfirmacao as Record<string, unknown>).cpf_destinatario;
          resumoConfirmacao = {
            nome_destinatario: payloadConfirmacao.nome_destinatario,
            tipo_documento_destinatario: cnpj ? "CNPJ" : "CPF",
            documento_destinatario_mascarado: mascararDocumentoFiscal(cnpj ?? cpf),
            valor_total: payloadConfirmacao.valor_total,
            contexto_hash: preflight.contexto_hash,
            homologacao_documento_fiscal_id: preflight.homologacao_documento_fiscal_id,
          };
        } catch (cause) {
          erroPreflight = mensagemErro(cause);
        }
      }
      if (!resumoConfirmacao) {
        const { data: estadoData } = await usuario.schema("f").rpc(
          "fn_nfe_producao_estado",
          { p_solicitacao_id: body.solicitacao_id },
        );
        const estado = (estadoData ?? {}) as EstadoProducao;
        if (
          estado.existe
          && estado.houve_claim
          && isUuid(estado.homologacao_documento_fiscal_id)
          && typeof estado.contexto_hash === "string"
          && /^[0-9a-f]{64}$/.test(estado.contexto_hash)
          && typeof estado.confirmacao_nome_destinatario === "string"
        ) {
          retomadaExistente = true;
          erroPreflight = null;
          resumoConfirmacao = {
            nome_destinatario: estado.confirmacao_nome_destinatario,
            tipo_documento_destinatario: estado.confirmacao_tipo_documento_destinatario ?? null,
            documento_destinatario_mascarado: mascararDocumentoFiscal(
              estado.confirmacao_documento_destinatario,
            ),
            valor_total: estado.confirmacao_valor_total ?? null,
            contexto_hash: estado.contexto_hash,
            homologacao_documento_fiscal_id: estado.homologacao_documento_fiscal_id,
            retomada_claim_existente: true,
          };
        }
      }
      const bancoPronto = Boolean(prontidao.pronta) || retomadaExistente;
      return json({
        pronta: bancoPronto && edgeConfigurada && !erroPreflight,
        banco_pronto: bancoPronto,
        edge_configurada: edgeConfigurada,
        preflight_confirmacao_pronto: Boolean(resumoConfirmacao) && !erroPreflight,
        resumo_confirmacao: resumoConfirmacao,
        retomada_existente: retomadaExistente,
        perfil_operacao_id: prontidao.perfil_operacao_id ?? null,
        perfil_operacao_ids: prontidao.perfil_operacao_ids ?? [],
        homologacao_documento_fiscal_id: prontidao.homologacao_documento_fiscal_id ?? null,
        motivo: !bancoPronto
          ? (prontidao.motivo ?? "A solicitacao ainda nao esta pronta para producao.")
          : !edgeConfigurada
          ? "A credencial e a liberacao explicita da Focus em producao ainda nao foram configuradas."
          : erroPreflight
          ? `Preflight de confirmacao bloqueado: ${erroPreflight}`
          : null,
      });
    }

    if (body.acao !== "EMITIR" && body.acao !== "ABANDONAR_REJEITADA") {
      return json({ erro: "Acao invalida." }, 400);
    }
    if (
      body.acao === "EMITIR"
      && (typeof body.confirmacao_contexto_hash !== "string" || !/^[0-9a-f]{64}$/.test(body.confirmacao_contexto_hash))
    ) {
      return json({
        erro: "Confirme novamente destinatario e total: confirmacao_contexto_hash valido e obrigatorio para emitir.",
      }, 409);
    }
    if (!edgeConfigurada) return json({ erro: "Emissao em producao desativada ou sem credencial propria." }, 503);

    const admin = adminClient();
    const { data: estadoData, error: estadoError } = await usuario.schema("f").rpc(
      "fn_nfe_producao_estado",
      { p_solicitacao_id: body.solicitacao_id },
    );
    if (estadoError) {
      return json({ erro: estadoError.message }, estadoError.code === "42501" ? 403 : 422);
    }
    const estado = (estadoData ?? {}) as EstadoProducao;
    let emissaoProducao: EmissaoContexto | null = null;
    let reconciliacaoConfirmada = false;

    if (estado.existe) {
      if (
        !isUuid(estado.documento_fiscal_id)
        || !isUuid(estado.tenant_id)
        || !isUuid(estado.empresa_id)
        || estado.solicitacao_id !== body.solicitacao_id
      ) {
        return json({ erro: "A emissao de producao existente nao possui escopo fiscal valido." }, 422);
      }
      documentoId = estado.documento_fiscal_id;
      const { data: contextoData, error: contextoError } = await admin.schema("f").rpc("fn_nfe_contexto_emissao", {
        p_documento_fiscal_id: documentoId,
      });
      if (contextoError) throw new Error(`Nao foi possivel montar o contexto fiscal: ${contextoError.message}`);
      if (!contextoData) throw new Error("Contexto da emissao de producao nao encontrado.");
      emissaoProducao = (contextoData as ContextoEmissao).emissao as EmissaoContexto;
      if (
        emissaoProducao.documento_fiscal_id !== documentoId
        || emissaoProducao.solicitacao_id !== body.solicitacao_id
        || emissaoProducao.tenant_id !== estado.tenant_id
        || emissaoProducao.empresa_id !== estado.empresa_id
        || emissaoProducao.ambiente !== "PRODUCAO"
      ) {
        throw new Error("Emissao de producao bloqueada: documento, solicitacao ou escopo fiscal inconsistente.");
      }

      if (body.acao === "ABANDONAR_REJEITADA") {
        let justificativa: string;
        try {
          justificativa = validarJustificativa(body.justificativa);
        } catch (cause) {
          return json({ erro: mensagemErro(cause) }, 400);
        }
        const consulta = await chamarFocus(
          `/v2/nfe/${encodeURIComponent(emissaoProducao.referencia_externa)}?completa=1`,
          {},
          "PRODUCAO",
        );
        if (!consulta.response.ok) {
          return json({
            erro: consulta.response.status === 404
              ? "A referencia nao foi encontrada na Focus; 404 nao prova rejeicao e o saldo permanece reservado."
              : `Nao foi possivel comprovar a rejeicao na Focus (HTTP ${consulta.response.status}).`,
            documento_fiscal_id: documentoId,
            referencia: emissaoProducao.referencia_externa,
          }, consulta.response.status === 404 ? 409 : 502);
        }
        const comprovacao = normalizarFocus(consulta.body);
        await aplicarRetorno(
          admin,
          consulta.body,
          emissaoProducao,
          "RECONCILIACAO",
          "fn_nfe_aplicar_retorno_producao",
        );
        if (comprovacao.status !== "REJEITADA") {
          return json({
            erro: `Abandono bloqueado: a Focus confirmou status ${comprovacao.status}, nao REJEITADA.`,
            documento_fiscal_id: documentoId,
            referencia: emissaoProducao.referencia_externa,
            status: comprovacao.status,
          }, 409);
        }
        const { data: abandonoData, error: abandonoError } = await admin.schema("f").rpc(
          "fn_nfe_producao_abandonar_rejeitada",
          {
            p_documento_fiscal_id: documentoId,
            p_referencia_externa: emissaoProducao.referencia_externa,
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
          referencia: emissaoProducao.referencia_externa,
          rejeicao_comprovada: true,
        });
      }

      if (emissaoProducao.status === "AUTORIZADA") {
        return json({
          documento_fiscal_id: documentoId,
          referencia: emissaoProducao.referencia_externa,
          status: emissaoProducao.status,
          idempotente: true,
        });
      }

      // O perdedor de um claim recente nao consulta a Focus: o vencedor pode
      // ainda estar entre o COMMIT do claim e o primeiro POST.
      const claimRecenteNoContexto = emissaoProducao.status === "ENVIANDO"
        && typeof emissaoProducao.ultima_tentativa_em === "string"
        && Number.isFinite(Date.parse(emissaoProducao.ultima_tentativa_em))
        && Date.parse(emissaoProducao.ultima_tentativa_em) >= Date.now() - 2 * 60 * 1000;
      if (claimRecenteNoContexto) {
        return json({
          documento_fiscal_id: documentoId,
          referencia: emissaoProducao.referencia_externa,
          status: "ENVIANDO",
          aguardar: true,
          idempotente: true,
        }, 202);
      }

      // Toda referencia que ja teve claim e nao e recente precisa ser
      // consultada antes de qualquer novo POST. Isso cobre queda apos o aceite.
      if (estado.houve_claim) {
        let consulta = await chamarFocus(
          `/v2/nfe/${encodeURIComponent(emissaoProducao.referencia_externa)}?completa=1`,
          {},
          "PRODUCAO",
        );
        const completaNormalizada = consulta.response.ok ? normalizarFocus(consulta.body) : null;
        if (completaNormalizada?.status === "AUTORIZADA" && !completaNormalizada.chaveAcesso) {
          const resumida = await chamarFocus(
            `/v2/nfe/${encodeURIComponent(emissaoProducao.referencia_externa)}`,
            {},
            "PRODUCAO",
          );
          if (resumida.response.ok && normalizarFocus(resumida.body).chaveAcesso) consulta = resumida;
        }
        if (consulta.response.ok) {
          const aplicado = await aplicarRetorno(
            admin,
            consulta.body,
            emissaoProducao,
            "RECONCILIACAO",
            "fn_nfe_aplicar_retorno_producao",
          );
          if (["AUTORIZADA", "PROCESSANDO"].includes(aplicado.retorno.status)) {
            return json({
              documento_fiscal_id: documentoId,
              referencia: emissaoProducao.referencia_externa,
              status: aplicado.retorno.status,
              idempotente: true,
              reconciliado_antes_do_retry: true,
            }, aplicado.retorno.status === "PROCESSANDO" ? 202 : 200);
          }
          // Uma rejeicao/erro confirmado pela propria referencia e conclusivo
          // para o payload congelado. Nao faz POST automatico por cima dele.
          return json({
            erro: aplicado.retorno.mensagem ?? "A Focus confirmou que a referencia nao foi autorizada.",
            codigo: aplicado.retorno.codigoStatus,
            documento_fiscal_id: documentoId,
            referencia: emissaoProducao.referencia_externa,
            status: aplicado.retorno.status,
            reconciliado_antes_do_retry: true,
          }, aplicado.retorno.status === "ERRO" ? 502 : 422);
        } else if (consulta.response.status !== 404) {
          return json({
            erro: `Consulta preventiva da Focus falhou (HTTP ${consulta.response.status}).`,
            documento_fiscal_id: documentoId,
            referencia: emissaoProducao.referencia_externa,
          }, 502);
        }
        reconciliacaoConfirmada = true;
      }
    } else if (body.acao === "ABANDONAR_REJEITADA") {
      return json({ erro: "Nao existe emissao de producao ativa para abandonar." }, 404);
    } else if (!prontidao.pronta) {
      return json({ erro: prontidao.motivo ?? "Solicitacao bloqueada para producao." }, 422);
    }

    let prontidaoFinal: Prontidao;
    let preflight: PreflightProducao;
    const retomadaComClaimCongelado = reconciliacaoConfirmada
      && estado.houve_claim
      && isUuid(estado.homologacao_documento_fiscal_id)
      && typeof estado.contexto_hash === "string"
      && /^[0-9a-f]{64}$/.test(estado.contexto_hash)
      && Boolean(emissaoProducao?.payload_enviado);

    if (retomadaComClaimCongelado) {
      // Uma liberacao posterior do mesmo perfil nao invalida a referencia ja
      // claimada. O GET=404 autorizou o retry e o SQL ainda revalida HOM,
      // certificado e hash fiscal capturados no primeiro claim.
      const { data: contextoRetomadaData, error: contextoRetomadaError } = await admin.schema("f").rpc(
        "fn_nfe_contexto_emissao",
        { p_documento_fiscal_id: estado.homologacao_documento_fiscal_id },
      );
      if (contextoRetomadaError || !contextoRetomadaData) {
        return json({
          erro: `Nao foi possivel recuperar o contexto congelado do primeiro claim: ${contextoRetomadaError?.message ?? "nao encontrado"}`,
          etapa: "RETOMADA",
          documento_fiscal_id: documentoId,
        }, 422);
      }
      prontidaoFinal = {
        pronta: true,
        tenant_id: estado.tenant_id,
        empresa_id: estado.empresa_id,
        homologacao_documento_fiscal_id: estado.homologacao_documento_fiscal_id,
      };
      preflight = {
        tenant_id: estado.tenant_id,
        empresa_id: estado.empresa_id,
        solicitacao_id: body.solicitacao_id,
        homologacao_documento_fiscal_id: estado.homologacao_documento_fiscal_id,
        contexto_hash: estado.contexto_hash,
        contexto: contextoRetomadaData as ContextoEmissao,
      };
    } else {
      // Primeiro claim revalida todos os gates imediatamente antes do claim.
      const { data: prontidaoFinalData, error: prontidaoFinalError } = await usuario.schema("f").rpc(
        "fn_nfe_producao_pronta",
        { p_solicitacao_id: body.solicitacao_id },
      );
      if (prontidaoFinalError) {
        return json({ erro: prontidaoFinalError.message, documento_fiscal_id: documentoId },
          prontidaoFinalError.code === "42501" ? 403 : 422);
      }
      prontidaoFinal = (prontidaoFinalData ?? {}) as Prontidao;
      if (!prontidaoFinal.pronta) {
        return json({
          erro: prontidaoFinal.motivo ?? "A solicitacao deixou de estar pronta antes do envio.",
          documento_fiscal_id: documentoId,
        }, 422);
      }
      const { data: preflightData, error: preflightError } = await usuario.schema("f").rpc(
        "fn_nfe_producao_preflight",
        { p_solicitacao_id: body.solicitacao_id },
      );
      if (preflightError) {
        return json({
          erro: `Nao foi possivel montar o preflight da homologacao: ${preflightError.message}`,
          etapa: "PREFLIGHT",
          documento_fiscal_id: documentoId,
        }, preflightError.code === "42501" ? 403 : 422);
      }
      preflight = (preflightData ?? {}) as PreflightProducao;
    }

    if (
      !isUuid(prontidaoFinal.homologacao_documento_fiscal_id)
      || !isUuid(prontidaoFinal.tenant_id)
      || !isUuid(prontidaoFinal.empresa_id)
    ) {
      return json({ erro: "A prontidao nao identificou a homologacao e o escopo fiscal." }, 422);
    }
    if (
      estado.existe
      && (estado.tenant_id !== prontidaoFinal.tenant_id || estado.empresa_id !== prontidaoFinal.empresa_id)
    ) {
      return json({ erro: "O escopo fiscal mudou durante a retomada da emissao." }, 409);
    }
    if (!preflight.contexto) {
      return json({ erro: "Contexto da homologacao autorizada nao encontrado.", etapa: "PREFLIGHT" }, 422);
    }
    if (
      preflight.solicitacao_id !== body.solicitacao_id
      || preflight.homologacao_documento_fiscal_id !== prontidaoFinal.homologacao_documento_fiscal_id
      || preflight.tenant_id !== prontidaoFinal.tenant_id
      || preflight.empresa_id !== prontidaoFinal.empresa_id
      || typeof preflight.contexto_hash !== "string"
      || !/^[0-9a-f]{64}$/.test(preflight.contexto_hash)
    ) {
      return json({
        erro: "O preflight devolveu homologacao, escopo ou hash fiscal inconsistente.",
        etapa: "PREFLIGHT",
        documento_fiscal_id: documentoId,
      }, 409);
    }
    if (preflight.contexto_hash !== body.confirmacao_contexto_hash) {
      return json({
        erro: "O contexto fiscal mudou depois da confirmacao de destinatario/total; revise e confirme novamente.",
        etapa: "CONFIRMACAO",
        documento_fiscal_id: documentoId,
      }, 409);
    }
    const contextoHomologacao = preflight.contexto;
    const emissaoHomologacao = contextoHomologacao.emissao as EmissaoContexto;
    if (
      emissaoHomologacao.documento_fiscal_id !== prontidaoFinal.homologacao_documento_fiscal_id
      || emissaoHomologacao.solicitacao_id !== body.solicitacao_id
      || emissaoHomologacao.tenant_id !== prontidaoFinal.tenant_id
      || emissaoHomologacao.empresa_id !== prontidaoFinal.empresa_id
      || emissaoHomologacao.ambiente !== "HOMOLOGACAO"
      || emissaoHomologacao.status !== "AUTORIZADA"
    ) {
      return json({
        erro: "Emissao em producao bloqueada: a homologacao autorizada nao pertence ao mesmo escopo e solicitacao.",
        etapa: "PREFLIGHT",
        documento_fiscal_id: documentoId,
      }, 422);
    }

    let payload: ReturnType<typeof montarPayloadNfe>;
    try {
      const payloadAtual = montarPayloadNfe({
        ...contextoHomologacao,
        emissao: { ...contextoHomologacao.emissao, ambiente: "PRODUCAO" },
      });
      validarPayloadProducaoContraHomologacao(emissaoHomologacao.payload_enviado, payloadAtual);
      if (emissaoProducao?.payload_enviado) {
        validarPayloadProducaoContraHomologacao(
          emissaoHomologacao.payload_enviado,
          emissaoProducao.payload_enviado,
        );
        payload = emissaoProducao.payload_enviado as ReturnType<typeof montarPayloadNfe>;
      } else {
        payload = payloadAtual;
      }
    } catch (cause) {
      return json({
        erro: mensagemErro(cause),
        etapa: "PREFLIGHT",
        documento_fiscal_id: documentoId,
        referencia: emissaoProducao?.referencia_externa,
      }, 422);
    }

    const { data: claimData, error: claimError } = await admin.schema("f").rpc(
      "fn_nfe_producao_preparar_e_claimar",
      {
        p_solicitacao_id: body.solicitacao_id,
        p_payload: payload,
        p_homologacao_documento_id: preflight.homologacao_documento_fiscal_id,
        p_contexto_hash: preflight.contexto_hash,
        p_reconciliacao_confirmada: reconciliacaoConfirmada,
      },
    );
    if (claimError) {
      return json({ erro: claimError.message, documento_fiscal_id: documentoId },
        claimError.code === "42501" ? 403 : claimError.code === "55000" ? 409 : 422);
    }
    const claim = (claimData ?? {}) as ClaimProducao;
    if (!isUuid(claim.documento_fiscal_id) || typeof claim.referencia_externa !== "string") {
      throw new Error("O RPC atomico nao devolveu a emissao de producao reservada.");
    }
    documentoId = claim.documento_fiscal_id;
    if (!claim.deve_enviar) {
      return json({
        documento_fiscal_id: documentoId,
        referencia: claim.referencia_externa,
        status: claim.status,
        aguardar: Boolean(claim.aguardar),
        idempotente: true,
      }, claim.aguardar || claim.status === "PROCESSANDO" || claim.status === "ENVIANDO" ? 202 : 200);
    }
    if (!claim.payload || typeof claim.payload !== "object" || Array.isArray(claim.payload)) {
      throw new Error("O claim de producao nao devolveu o payload fiscal congelado.");
    }
    claimVencedor = true;
    payload = claim.payload as ReturnType<typeof montarPayloadNfe>;

    const emissaoClaimada: EmissaoContexto = {
      documento_fiscal_id: documentoId,
      solicitacao_id: body.solicitacao_id,
      referencia_externa: claim.referencia_externa,
      ambiente: "PRODUCAO",
      tenant_id: prontidaoFinal.tenant_id,
      empresa_id: prontidaoFinal.empresa_id,
      status: "ENVIANDO",
      tentativa_count: claim.tentativa_count,
      payload_enviado: payload,
    };
    const chamada = await chamarFocus(
      `/v2/nfe?ref=${encodeURIComponent(claim.referencia_externa)}`,
      { method: "POST", body: JSON.stringify(payload) },
      "PRODUCAO",
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
      resultado = (await aplicarRetorno(
        admin,
        chamada.body,
        emissaoClaimada,
        "ENVIO",
        "fn_nfe_aplicar_retorno_producao",
      )).retorno;
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
