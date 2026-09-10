-- Nota rejeitada volta a ser rascunho, em vez de prender a solicitacao inteira.
--
-- Ate aqui uma rejeicao era um beco sem saida. O retry de f.fn_nfe_homologacao_claimar
-- so reenvia o payload congelado no primeiro claim ("O retry de homologacao diverge do
-- payload congelado"), e o proprio emissor devolve 422 quando a consulta preventiva
-- confirma a rejeicao. Corrigir o cadastro nao adiantava: a unica saida era o abandono,
-- que cancela a solicitacao e devolve o saldo para a OV — obrigando a refazer destino,
-- transportadora, pagamento e conferencia por causa de um digito errado.
--
-- Foi o que aconteceu com a OV-SEG-00007-026 em 10/09/2026: a nota saiu com CST de IPI
-- 53 e IPI de 9,75% destacado ao mesmo tempo, a SEFAZ recusou com a rejeicao 610
-- (somatorio) e o rascunho ficou preso.
--
-- Nota rejeitada nao existe para o Fisco: nada foi autorizado, nenhum numero foi
-- consumido na SEFAZ e nao ha o que regularizar. O certo e corrigir e mandar de novo.
-- O que nao pode e reaproveitar a referencia — para a Focus ela ja teve um desfecho —,
-- entao esta funcao cunha uma nova (sufixo -r2, -r3 ...) e devolve a emissao a
-- RASCUNHO, mantendo a solicitacao, a conferencia e a reserva de saldo de pe.
--
-- Continua exigindo prova: quem chama e o backend fiscal, depois de a Focus confirmar
-- REJEITADA. Fica registrado um evento REENVIO com a referencia velha, o cStat e a
-- mensagem, para a auditoria enxergar a cadeia inteira.

create or replace function f.fn_nfe_recomecar_rejeitada(
  p_documento_fiscal_id uuid,
  p_referencia_externa text,
  p_status_focus text,
  p_prova_focus jsonb default null,
  p_codigo_status integer default null,
  p_mensagem text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_emissao f.documento_fiscal_emissao%rowtype;
  v_base text;
  v_nova text;
  v_tentativa integer;
begin
  if session_user <> 'postgres' and v_role <> 'service_role' then
    raise exception using errcode = '42501',
      message = 'Somente o backend fiscal pode recomecar uma emissao rejeitada.';
  end if;
  if coalesce(p_status_focus, '') <> 'REJEITADA' then
    raise exception using errcode = '55000',
      message = format('Recomeco bloqueado: o provedor respondeu %s, nao REJEITADA.',
                       coalesce(p_status_focus, '(vazio)'));
  end if;

  select dfe.* into v_emissao
  from f.documento_fiscal_emissao dfe
  where dfe.documento_fiscal_id = p_documento_fiscal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Emissao nao encontrada.';
  end if;
  if v_emissao.referencia_externa is distinct from p_referencia_externa then
    raise exception using errcode = '55000',
      message = 'A referencia comprovada nao e a referencia atual da emissao.';
  end if;
  if v_emissao.status not in ('REJEITADA', 'ERRO') then
    raise exception using errcode = '55000',
      message = format('Status %s nao aceita recomeco; so REJEITADA e ERRO.', v_emissao.status);
  end if;
  -- Rejeitada nao tem chave nem protocolo. Se tiver, alguma coisa foi autorizada e
  -- reabrir seria emitir a segunda nota do mesmo fato.
  if v_emissao.chave_acesso is not null or v_emissao.protocolo is not null then
    raise exception using errcode = '55000',
      message = 'A emissao tem chave ou protocolo gravado; recomeco bloqueado.';
  end if;

  -- Referencia nova a cada recomeco: a antiga ja teve desfecho na Focus.
  v_base := regexp_replace(v_emissao.referencia_externa, '-r[0-9]+$', '');
  v_tentativa := 2;
  loop
    v_nova := v_base || '-r' || v_tentativa;
    exit when not exists (
      select 1 from f.documento_fiscal_emissao x
      where x.tenant_id = v_emissao.tenant_id
        and x.empresa_id = v_emissao.empresa_id
        and x.referencia_externa = v_nova
    );
    v_tentativa := v_tentativa + 1;
    if v_tentativa > 99 then
      raise exception using errcode = '55000',
        message = 'Limite de recomecos desta emissao atingido; investigue antes de insistir.';
    end if;
  end loop;

  insert into f.documento_fiscal_evento (
    documento_fiscal_id, tenant_id, empresa_id, tipo, status, resposta,
    referencia_externa, codigo_motivo, justificativa
  ) values (
    v_emissao.documento_fiscal_id,
    v_emissao.tenant_id,
    v_emissao.empresa_id,
    'REENVIO',
    'REJEITADA',
    jsonb_build_object(
      'motivo', 'RECOMECO_APOS_REJEICAO',
      'ambiente', v_emissao.ambiente,
      'referencia_anterior', v_emissao.referencia_externa,
      'referencia_nova', v_nova,
      'tentativas_anteriores', v_emissao.tentativa_count,
      'payload_descartado', v_emissao.payload_enviado,
      'prova_provedor', p_prova_focus
    ),
    v_emissao.referencia_externa,
    nullif(p_codigo_status::text, ''),
    left(coalesce(p_mensagem, 'Rejeicao confirmada pelo provedor; emissao devolvida a rascunho.'), 255)
  );

  update f.documento_fiscal_emissao dfe
  set status = 'RASCUNHO',
      referencia_externa = v_nova,
      payload_enviado = null,
      resposta = null,
      codigo_status = null,
      mensagem = null,
      enviado_em = null,
      tentativa_count = 0,
      ultima_tentativa_em = null,
      callback_recebido_em = null,
      reconciliado_em = now(),
      updated_at = now()
  where dfe.documento_fiscal_id = v_emissao.documento_fiscal_id
  returning dfe.* into v_emissao;

  update f.documento_fiscal df
  set nfe_status = 'RASCUNHO', updated_at = now()
  where df.tenant_id = v_emissao.tenant_id
    and df.empresa_id = v_emissao.empresa_id
    and df.id = v_emissao.documento_fiscal_id
    and df.nfe_status in ('REJEITADA', 'ERRO');

  return jsonb_build_object(
    'documento_fiscal_id', v_emissao.documento_fiscal_id,
    'referencia_anterior', p_referencia_externa,
    'referencia_externa', v_emissao.referencia_externa,
    'status', v_emissao.status
  );
end;
$function$;

revoke all on function f.fn_nfe_recomecar_rejeitada(uuid, text, text, jsonb, integer, text) from public;
grant execute on function f.fn_nfe_recomecar_rejeitada(uuid, text, text, jsonb, integer, text) to service_role;

comment on function f.fn_nfe_recomecar_rejeitada(uuid, text, text, jsonb, integer, text) is
  'Devolve a RASCUNHO uma emissao que o provedor confirmou REJEITADA, com referencia externa nova e payload descartado, para reenviar depois de corrigir o cadastro. Mantem a solicitacao e a reserva de saldo.';
