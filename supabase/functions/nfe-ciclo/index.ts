import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { chamarFocus, focusConfigurado, normalizarFocus, type FocusAmbiente } from "../_shared/focus-nfe.ts";
import { validarAcaoCicloPorAmbiente } from "../_shared/nfe-ciclo-guard.ts";
import { adminClient, corsHeaders, json, mensagemErro, responderOptions, userClient } from "../_shared/nfe-http.ts";

type Acao =
  | "CANCELAR"
  | "TESTAR_CANCELAMENTO_FORA_PRAZO"
  | "CARTA_CORRECAO"
  | "EMAIL"
  | "INUTILIZAR"
  | "ARQUIVO";
type CicloBody = {
  acao?: Acao;
  documento_fiscal_id?: string;
  justificativa?: string;
  correcao?: string;
  emails?: string[];
  arquivo?: "XML" | "DANFE";
  serie?: number;
  numero_inicial?: number;
  numero_final?: number;
  ambiente?: FocusAmbiente;
};

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

async function contextoDocumento(user: ReturnType<typeof userClient>, documentoId: string) {
  const { data, error } = await user.schema("f").rpc("fn_nfe_ciclo_contexto", { p_documento_fiscal_id: documentoId });
  if (error) throw error;
  const result = objeto(data);
  if (!Object.keys(result).length) throw new Error("Emissao de NF-e nao encontrada.");
  return result;
}

async function registrarEvento(admin: ReturnType<typeof adminClient>, params: Record<string, unknown>) {
  const { error } = await admin.schema("f").rpc("fn_nfe_evento_registrar", params);
  if (error) throw error;
}

Deno.serve(async (request) => {
  const options = responderOptions(request);
  if (options) return options;
  if (request.method !== "POST") return json({ error: "Metodo nao permitido." }, 405);

  try {
    const body = await request.json() as CicloBody;
    const acao = String(body.acao ?? "").toUpperCase() as Acao;
    const user = userClient(request);
    const { data: authData, error: authError } = await user.auth.getUser();
    if (authError || !authData.user) return json({ error: "Sessao invalida." }, 401);
    const admin = adminClient();

    if (acao === "INUTILIZAR") {
      const ambienteSolicitado: FocusAmbiente = body.ambiente === "PRODUCAO" ? "PRODUCAO" : "HOMOLOGACAO";
      validarAcaoCicloPorAmbiente(acao, ambienteSolicitado);
      // O armazenamento/validador atual e deliberadamente HOMOLOGACAO-only.
      // PRODUCAO so pode ser aberta com pipeline e estorno auditados proprios.
      const ambiente: FocusAmbiente = "HOMOLOGACAO";
      if (!focusConfigurado(ambiente)) throw new Error(`Inutilizacao em ${ambiente} desativada ou sem credencial propria.`);
      const justificativa = validarTexto(body.justificativa, 15, 255, "Justificativa");
      const serie = Number(body.serie);
      const numeroInicial = Number(body.numero_inicial);
      const numeroFinal = Number(body.numero_final);
      const { data: validacao, error: validacaoError } = await user.schema("f").rpc("fn_nfe_inutilizacao_validar", {
        p_serie: serie,
        p_numero_inicial: numeroInicial,
        p_numero_final: numeroFinal,
        p_justificativa: justificativa,
      });
      if (validacaoError) throw validacaoError;
      const ctx = objeto(validacao);
      const { response, body: focusBody } = await chamarFocus("/v2/nfe/inutilizacao", {
        method: "POST",
        body: JSON.stringify({
          cnpj: ctx.cnpj,
          serie,
          numero_inicial: numeroInicial,
          numero_final: numeroFinal,
          justificativa,
        }),
      }, ambiente);
      const focus = objeto(focusBody);
      const status = response.ok ? "AUTORIZADA" : "REJEITADA";
      const protocolo = texto(focus, "protocolo", "protocolo_inutilizacao");
      const { error: registrarError } = await admin.schema("f").rpc("fn_nfe_inutilizacao_registrar", {
        p_tenant_id: ctx.tenant_id,
        p_empresa_id: ctx.empresa_id,
        p_serie: serie,
        p_numero_inicial: numeroInicial,
        p_numero_final: numeroFinal,
        p_justificativa: justificativa,
        p_status: status,
        p_protocolo: protocolo,
        p_resposta: focus,
      });
      if (registrarError) throw registrarError;
      if (!response.ok) return json({ error: texto(focus, "mensagem", "mensagem_sefaz") ?? "Inutilizacao rejeitada.", resposta: focus }, 422);
      return json({ ok: true, status, protocolo, resposta: focus });
    }

    const documentoId = String(body.documento_fiscal_id ?? "").trim();
    if (!/^[0-9a-f-]{36}$/i.test(documentoId)) throw new Error("Documento fiscal invalido.");
    const ctx = await contextoDocumento(user, documentoId);
    const emissao = objeto(ctx.emissao);
    const cancelamento = objeto(ctx.cancelamento);
    const ambiente = String(emissao.ambiente) as FocusAmbiente;
    if (!["HOMOLOGACAO", "PRODUCAO"].includes(ambiente)) throw new Error("Ambiente fiscal invalido.");
    validarAcaoCicloPorAmbiente(acao, ambiente);
    const referencia = String(emissao.referencia_externa ?? "").trim();
    if (!referencia) throw new Error("Emissao sem referencia externa da Focus.");

    if (acao === "ARQUIVO") {
      const tipo = body.arquivo === "XML" ? "XML" : "DANFE";
      const path = String(tipo === "XML" ? emissao.xml_path ?? "" : emissao.danfe_path ?? "").trim();
      if (!path) throw new Error(`${tipo} ainda nao foi arquivado no Storage privado.`);
      const { data, error } = await admin.storage.from("nfe-documentos").createSignedUrl(path, 60);
      if (error) throw error;
      await registrarEvento(admin, {
        p_documento_fiscal_id: documentoId, p_tipo: "DOWNLOAD", p_status: "CONCLUIDO",
        p_resposta: { arquivo: tipo, storage_path: path },
      });
      return json({ ok: true, url: data.signedUrl, arquivo: tipo });
    }

    if (!focusConfigurado(ambiente)) throw new Error(`Ciclo de vida em ${ambiente} desativado ou sem credencial propria.`);

    if (acao === "CANCELAR" || acao === "TESTAR_CANCELAMENTO_FORA_PRAZO") {
      const testeForaPrazo = acao === "TESTAR_CANCELAMENTO_FORA_PRAZO";
      let justificativa = validarTexto(body.justificativa, 15, 255, "Justificativa");
      const eventos = Array.isArray(ctx.eventos) ? ctx.eventos.map(objeto) : [];
      const ultimoCancelamento = eventos.find((evento) => evento.tipo === "CANCELAMENTO");
      const cancelamentoEmAndamento = ultimoCancelamento?.status === "ENVIANDO";
      const testeForaPrazoJaExecutado = eventos.some((evento) =>
        objeto(evento.resposta).cenario_homologacao === "CANCELAMENTO_FORA_PRAZO"
      );
      if (testeForaPrazo) {
        if (ambiente !== "HOMOLOGACAO") {
          throw new Error("O teste de cancelamento fora do prazo existe somente em HOMOLOGACAO.");
        }
        if (cancelamento.deve_estornar !== true || cancelamento.pode_cancelar === true) {
          throw new Error("Este cenario so pode ser executado depois do fim da janela de 24 horas.");
        }
        if (testeForaPrazoJaExecutado && !cancelamentoEmAndamento) {
          throw new Error("O cancelamento fora do prazo ja foi testado e registrado nesta NF-e.");
        }
      } else if (cancelamento.pode_cancelar !== true && !cancelamentoEmAndamento) {
        throw new Error("A janela de cancelamento terminou. Use a NF-e de estorno.");
      }
      // PRODUCAO tem claim/finalizacao proprios: alem do estado da emissao,
      // cancelam o documento, a solicitacao e os titulos a receber.
      const rpcClaim = ambiente === "PRODUCAO"
        ? "fn_nfe_cancelamento_producao_claim"
        : "fn_nfe_cancelamento_homologacao_claim";
      const rpcFinalizar = ambiente === "PRODUCAO"
        ? "fn_nfe_cancelamento_producao_finalizar"
        : "fn_nfe_cancelamento_homologacao_finalizar";
      const reservar = async (claimReconciliado: string | null) => {
        const { data, error } = await admin.schema("f").rpc(
          rpcClaim,
          {
            p_documento_fiscal_id: documentoId,
            p_justificativa: justificativa,
            p_reconciliacao_claim_id: claimReconciliado,
          },
        );
        if (error) throw error;
        return objeto(data);
      };
      const finalizar = async (
        eventoClaimId: string,
        status: "AUTORIZADA" | "REJEITADA",
        resposta: Record<string, unknown>,
      ) => {
        // O DELETE autorizado devolve o protocolo do evento em numero_protocolo
        // (conferido na NF-e 2/12: 342260000903334).
        const protocolo = texto(resposta, "protocolo", "protocolo_cancelamento", "numero_protocolo");
        const { error } = await admin.schema("f").rpc(
          rpcFinalizar,
          {
            p_documento_fiscal_id: documentoId,
            p_evento_claim_id: eventoClaimId,
            p_status: status,
            p_justificativa: justificativa,
            p_protocolo: protocolo,
            p_resposta: resposta,
          },
        );
        if (error) throw error;
        return protocolo;
      };

      let claim = await reservar(null);
      if (claim.deve_reconciliar === true) {
        const claimPendenteId = String(claim.evento_claim_id ?? "");
        if (!/^[0-9a-f-]{36}$/i.test(claimPendenteId)) throw new Error("Claim pendente de cancelamento invalido.");
        justificativa = validarTexto(claim.justificativa_claim, 15, 255, "Justificativa do claim");

        // Um DELETE anterior pode ter sido aceito apesar de a resposta ter se
        // perdido. Sempre consulta a referencia antes de qualquer novo DELETE.
        const consulta = await chamarFocus(
          `/v2/nfe/${encodeURIComponent(referencia)}?completa=1`,
          {},
          ambiente,
        );
        if (!consulta.response.ok) {
          return json({
            error: `Nao foi possivel reconciliar o cancelamento pendente (HTTP ${consulta.response.status}).`,
            status: "ENVIANDO",
            aguardar: true,
            documento_fiscal_id: documentoId,
          }, 502);
        }
        const consultaNormalizada = normalizarFocus(consulta.body);
        if (consultaNormalizada.status === "CANCELADA") {
          const protocolo = await finalizar(
            claimPendenteId,
            "AUTORIZADA",
            consultaNormalizada.bruto,
          );
          return json({
            ok: true,
            status: "CANCELADA",
            protocolo,
            resposta: consultaNormalizada.bruto,
            reconciliado_antes_do_retry: true,
          });
        }
        if (consultaNormalizada.status !== "AUTORIZADA") {
          return json({
            error: "A Focus ainda nao confirmou se a NF-e permanece autorizada; o cancelamento continua pendente.",
            status: "ENVIANDO",
            aguardar: true,
            resposta: consultaNormalizada.bruto,
          }, 202);
        }
        claim = await reservar(claimPendenteId);
      }
      if (claim.deve_cancelar !== true) {
        return json({
          ok: true,
          status: "ENVIANDO",
          aguardar: true,
          documento_fiscal_id: documentoId,
        }, 202);
      }
      const eventoClaimId = String(claim.evento_claim_id ?? "");
      if (!/^[0-9a-f-]{36}$/i.test(eventoClaimId)) throw new Error("Claim de cancelamento invalido.");
      justificativa = validarTexto(claim.justificativa_claim, 15, 255, "Justificativa do claim");
      const { response, body: focusBody } = await chamarFocus(`/v2/nfe/${encodeURIComponent(referencia)}`, {
        method: "DELETE", body: JSON.stringify({ justificativa }),
      }, ambiente);
      let focus = objeto(focusBody);
      // O HTTP nao decide: na NF-e 2/1 a Focus devolveu 2xx com
      // status "erro_cancelamento" (cStat 501, prazo excedido) e a nota foi
      // gravada como cancelada. So o corpo "cancelado" autoriza.
      const statusCorpo = (texto(focus, "status") ?? "").toLowerCase();
      let status: "AUTORIZADA" | "REJEITADA" = response.ok && statusCorpo === "cancelado"
        ? "AUTORIZADA"
        : "REJEITADA";

      // Uma resposta 4xx (ou 2xx sem "cancelado") pode significar "ja
      // cancelada" se outro DELETE foi aceito. Confirma por GET antes de
      // gravar rejeicao e manter HOM ativa.
      if (status !== "AUTORIZADA") {
        const consulta = await chamarFocus(
          `/v2/nfe/${encodeURIComponent(referencia)}?completa=1`,
          {},
          ambiente,
        );
        if (!consulta.response.ok) {
          return json({
            error: `Cancelamento sem resposta conclusiva; reconciliacao pendente (HTTP ${consulta.response.status}).`,
            status: "ENVIANDO",
            aguardar: true,
            documento_fiscal_id: documentoId,
          }, 502);
        }
        const consultaNormalizada = normalizarFocus(consulta.body);
        if (consultaNormalizada.status === "CANCELADA") {
          status = "AUTORIZADA";
          focus = consultaNormalizada.bruto;
        } else if (consultaNormalizada.status !== "AUTORIZADA") {
          return json({
            error: "Cancelamento sem estado conclusivo na Focus; reconciliacao pendente.",
            status: "ENVIANDO",
            aguardar: true,
            resposta: consultaNormalizada.bruto,
          }, 202);
        }
      }

      if (testeForaPrazo) {
        focus = {
          ...focus,
          cenario_homologacao: "CANCELAMENTO_FORA_PRAZO",
          executado_apos_limite_em: cancelamento.limite_em ?? null,
        };
      }

      const protocolo = await finalizar(eventoClaimId, status, focus);
      if (status !== "AUTORIZADA") {
        return json({ error: texto(focus, "mensagem", "mensagem_sefaz") ?? "Cancelamento rejeitado.", resposta: focus }, 422);
      }
      return json({ ok: true, status: "CANCELADA", protocolo, resposta: focus });
    }

    if (acao === "CARTA_CORRECAO") {
      const correcao = validarTexto(body.correcao, 15, 1000, "Correcao");
      if (String(emissao.status) !== "AUTORIZADA") throw new Error("Carta de correcao exige NF-e autorizada.");
      const eventos = Array.isArray(ctx.eventos) ? ctx.eventos.map(objeto) : [];
      const sequencia = eventos.filter((evento) => evento.tipo === "CARTA_CORRECAO" && evento.status === "AUTORIZADA").length + 1;
      if (sequencia > 20) throw new Error("Limite de 20 cartas de correcao atingido para esta NF-e.");
      const { response, body: focusBody } = await chamarFocus(`/v2/nfe/${encodeURIComponent(referencia)}/carta_correcao`, {
        method: "POST", body: JSON.stringify({ correcao }),
      }, ambiente);
      const focus = objeto(focusBody);
      const status = response.ok ? "AUTORIZADA" : "REJEITADA";
      const protocolo = texto(focus, "protocolo", "protocolo_carta_correcao");
      await registrarEvento(admin, {
        p_documento_fiscal_id: documentoId, p_tipo: "CARTA_CORRECAO", p_status: status,
        p_justificativa: correcao, p_protocolo: protocolo, p_resposta: focus, p_sequencia: sequencia,
      });
      if (!response.ok) return json({ error: texto(focus, "mensagem", "mensagem_sefaz") ?? "Carta de correcao rejeitada.", resposta: focus }, 422);
      return json({ ok: true, sequencia, protocolo, resposta: focus });
    }

    if (acao === "EMAIL") {
      if (String(emissao.status) !== "AUTORIZADA") throw new Error("Envio exige NF-e autorizada.");
      if (!emissao.xml_path || !emissao.danfe_path) throw new Error("XML e DANFE precisam estar arquivados antes do envio.");
      const emails = Array.from(new Set((body.emails ?? []).map((email) => String(email).trim().toLowerCase()).filter(Boolean)));
      if (!emails.length || emails.length > 10 || emails.some((email) => !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))) {
        throw new Error("Informe de 1 a 10 e-mails validos.");
      }
      const { response, body: focusBody } = await chamarFocus(`/v2/nfe/${encodeURIComponent(referencia)}/email`, {
        method: "POST", body: JSON.stringify({ emails }),
      }, ambiente);
      const focus = objeto(focusBody);
      const status = response.ok ? "ENFILEIRADO" : "ERRO";
      await registrarEvento(admin, {
        p_documento_fiscal_id: documentoId, p_tipo: "EMAIL", p_status: status,
        p_resposta: { ...focus, anexos: ["XML", "DANFE"] }, p_destinatarios: emails,
      });
      if (!response.ok) return json({ error: texto(focus, "mensagem") ?? "Falha ao enfileirar e-mail.", resposta: focus }, 422);
      return json({ ok: true, status, destinatarios: emails, resposta: focus });
    }

    return json({ error: "Acao invalida." }, 400);
  } catch (error) {
    return new Response(JSON.stringify({ error: mensagemErro(error) }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
