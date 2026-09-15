-- =====================================================================================
-- O aviso de hora cancelada vai para a dona da hora e para quem lançou, nunca para
-- quem cancelou.
--
-- Achado na conferência em tela de 15/09/2026, com a correção da hora interna pela
-- própria pessoa (20260915110000). O aviso ia só para quem lançou a hora. Quando a
-- coordenação cancelava o que tinha lançado para alguém da equipe, o aviso "foram
-- canceladas por Carla" ia para a própria Carla, e a dona da hora não recebia nada.
-- Com a própria pessoa e quem lançou cancelando, isso passaria a ser comum. Vale também
-- para a hora em OS. A hora gravada pelo tablet avisa só a dona: quem grava ali é a
-- conta do aparelho.
--
-- Função gerada a partir da definição de produção de 15/09/2026.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

CREATE OR REPLACE FUNCTION public.app_cancelar_apontamento(p_apontamento_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'a', 'auth'
 SET row_security TO 'off'
AS $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_cancelado_por_nome text;
  v_apontamento public.apontamentos_horas%rowtype;
  v_numero_os text;
  v_cliente_nome text;
  v_colaborador_nome text;
  v_tipo_hora_nome text;
  v_lancado_por_user_id uuid;
  v_dono_user_id uuid;
  v_destinatario uuid;
  v_enviada uuid;
  v_eventos_aprovacao jsonb := '[]'::jsonb;
  v_notificacao_id uuid;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_horas_texto text;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  select upper(usuario_empresa.papel::text),
         coalesce(
           nullif(btrim(usuario.nome), ''),
           nullif(btrim(usuario.email), ''),
           'Usuário não identificado'
         )
    into v_papel, v_cancelado_por_nome
  from a.usuario as usuario
  join a.usuario_empresa as usuario_empresa
    on usuario_empresa.usuario_id = usuario.id
   and usuario_empresa.empresa_id = v_empresa_id
   and usuario_empresa.ativo is true
   and usuario_empresa.deleted_at is null
  where usuario.auth_user_id = v_auth_uid
    and usuario.ativo is true
    and usuario.deleted_at is null
  limit 1;

  if v_papel is null then
    raise exception 'Não foi possível identificar o papel deste usuário na empresa atual.';
  end if;

  if v_motivo is null or char_length(v_motivo) < 5 then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'motivo',
        'mensagem', 'Informe o motivo do cancelamento com pelo menos 5 caracteres.'
      ))
    );
  end if;

  if char_length(v_motivo) > 500 then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'motivo',
        'mensagem', 'O motivo do cancelamento deve ter no máximo 500 caracteres.'
      ))
    );
  end if;

  select apontamento.*
    into v_apontamento
  from public.apontamentos_horas as apontamento
  where apontamento.id = p_apontamento_id
    and apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id
  for update;

  if not found then
    if exists (
      select 1
      from public.apontamentos_horas_cancelamentos as cancelamento
      where cancelamento.apontamento_id = p_apontamento_id
        and cancelamento.tenant_id = v_tenant_id
        and cancelamento.empresa_id = v_empresa_id
    ) then
      return jsonb_build_object(
        'sucesso', true,
        'gravados', 0,
        'ja_cancelado', true,
        'avisos', '[]'::jsonb,
        'erros', '[]'::jsonb
      );
    end if;

    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'apontamento',
        'mensagem', 'O apontamento informado não existe ou não pertence à empresa atual.'
      ))
    );
  end if;

  -- A trava de OV é de documento: hora interna não tem documento para conferir, e
  -- com os_id nulo a verificação recusava todo cancelamento.
  if v_apontamento.os_id is not null then
    perform public.assert_documento_operacional_os(v_apontamento.os_id);
  end if;

  if coalesce(v_apontamento.gerado_por_hh, false) then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'hh',
        'mensagem', 'Este apontamento é um espelho de HH e deve ser corrigido no módulo HH.'
      ))
    );
  end if;

  if lower(coalesce(v_apontamento.status, '')) = 'fechado' then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'status',
        'mensagem', 'Este apontamento está fechado e não pode ser cancelado.'
      ))
    );
  end if;

  if exists (
    select 1
    from public.competencias as competencia
    where competencia.tenant_id = v_tenant_id
      and competencia.empresa_id = v_empresa_id
      and competencia.ano = extract(year from v_apontamento.data)::integer
      and competencia.mes = extract(month from v_apontamento.data)::integer
      and competencia.status = 'fechada'
  ) then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'competencia',
        'mensagem', format(
          'A competência %s está fechada e este apontamento não pode ser cancelado.',
          to_char(v_apontamento.data, 'MM/YYYY')
        )
      ))
    );
  end if;

  if not public.fn_usuario_pode_alterar_apontamento(v_tenant_id, v_empresa_id, v_auth_uid, v_apontamento.id) then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'permissao',
        'mensagem', case
          when v_apontamento.atividade_id is not null
            then 'Hora interna só pode ser cancelada pela própria pessoa, por quem a lançou, pela diretoria ou pela administração.'
          when coalesce(v_apontamento.status_aprovacao, 'pendente') = 'aprovado'
            then 'Após a aprovação, somente o responsável da OS, Coordenação, Diretor ou Admin pode cancelar.'
          else 'Antes da aprovação, somente o próprio colaborador, o responsável da OS, Coordenação, Diretor ou Admin pode cancelar.'
        end
      ))
    );
  end if;

  select
    coalesce(nullif(btrim(ordem.numero_os), ''), ordem.os_num::text, ordem.id::text,
             (select at.nome from public.atividades_internas as at where at.id = v_apontamento.atividade_id)),
    coalesce(ordem.cliente_nome, v_apontamento.cliente_nome),
    colaborador.nome,
    tipo_hora.descricao,
    coalesce(v_apontamento.criado_por_user_id, colaborador.user_id),
    colaborador.user_id
    into
      v_numero_os,
      v_cliente_nome,
      v_colaborador_nome,
      v_tipo_hora_nome,
      v_lancado_por_user_id,
      v_dono_user_id
  from public.colaboradores as colaborador
  -- Hora interna nao tem OS: a OS vira opcional e o que amarra e o colaborador.
  left join public.ordens_servico as ordem
    on ordem.id = v_apontamento.os_id
   and ordem.tenant_id = v_tenant_id
   and ordem.empresa_id = v_empresa_id
  left join public.tipos_horas as tipo_hora
    on tipo_hora.id = v_apontamento.tipo_hora_id
   and tipo_hora.tenant_id = v_tenant_id
  where colaborador.id = v_apontamento.colaborador_id
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id;

  if not found then
    raise exception 'Não foi possível localizar o colaborador do apontamento no contexto atual.';
  end if;

  select coalesce(
           jsonb_agg(to_jsonb(evento) order by evento.criado_em),
           '[]'::jsonb
         )
    into v_eventos_aprovacao
  from public.apontamentos_horas_aprovacao_eventos as evento
  where evento.apontamento_id = v_apontamento.id
    and evento.tenant_id = v_tenant_id
    and evento.empresa_id = v_empresa_id;

  insert into public.apontamentos_horas_cancelamentos (
    apontamento_id,
    tenant_id,
    empresa_id,
    os_id,
    numero_os,
    cliente_nome,
    colaborador_id,
    colaborador_nome,
    data,
    horas,
    tipo_hora_id,
    tipo_hora_nome,
    fator_aplicado,
    descricao,
    status_anterior,
    status_aprovacao_anterior,
    pendente_em,
    aprovado_em,
    rejeitado_em,
    motivo_devolucao,
    gerado_por_hh,
    lancado_por_user_id,
    criado_em,
    cancelado_por_user_id,
    cancelado_por_nome,
    cancelamento_motivo,
    dados_apontamento
  ) values (
    v_apontamento.id,
    v_apontamento.tenant_id,
    v_apontamento.empresa_id,
    v_apontamento.os_id,
    v_numero_os,
    v_cliente_nome,
    v_apontamento.colaborador_id,
    v_colaborador_nome,
    v_apontamento.data,
    v_apontamento.horas,
    v_apontamento.tipo_hora_id,
    v_tipo_hora_nome,
    v_apontamento.fator_aplicado,
    v_apontamento.descricao,
    v_apontamento.status,
    v_apontamento.status_aprovacao,
    v_apontamento.pendente_em,
    v_apontamento.aprovado_em,
    v_apontamento.rejeitado_em,
    v_apontamento.motivo_devolucao,
    v_apontamento.gerado_por_hh,
    v_lancado_por_user_id,
    v_apontamento.criado_em,
    v_auth_uid,
    v_cancelado_por_nome,
    v_motivo,
    to_jsonb(v_apontamento) || jsonb_build_object(
      'eventos_aprovacao', v_eventos_aprovacao
    )
  );

  delete from public.apontamentos_horas as apontamento
  where apontamento.id = v_apontamento.id
    and apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id;

  if not found then
    raise exception 'O apontamento mudou durante o cancelamento. Atualize a tela e tente novamente.';
  end if;

  v_horas_texto := replace(v_apontamento.horas::text, '.', ',');

  -- Avisa quem lançou e a dona da hora, e nunca quem está cancelando. Antes o aviso ia só
  -- para quem lançou: a coordenação que cancelava o que lançou para a equipe recebia o
  -- próprio aviso e a pessoa não sabia de nada. No tablet quem grava é a conta do
  -- aparelho, que não é gente: vai só para a dona da hora.
  for v_destinatario in
    select distinct destinatario
    from unnest(array[
      case when v_apontamento.tablet_sessao_id is null then v_lancado_por_user_id end,
      v_dono_user_id
    ]) as destinatario
    where destinatario is not null
      and destinatario is distinct from v_auth_uid
  loop
    v_enviada := public.app_criar_notificacao(
      v_tenant_id,
      v_empresa_id,
      v_destinatario,
      'hora_cancelada',
      'Apontamento cancelado',
      format(
        '%s h de %s %s foram canceladas por %s. Motivo: %s',
        v_horas_texto,
        to_char(v_apontamento.data, 'DD/MM/YYYY'),
        -- Na hora interna v_numero_os é o nome da atividade: "em Treinamento".
        case when v_apontamento.os_id is null then 'em ' || v_numero_os else 'na OS ' || v_numero_os end,
        v_cancelado_por_nome,
        v_motivo
      ),
      jsonb_build_object(
        'url', coalesce('/os/' || v_apontamento.os_id::text, '/(tabs)/historico'),
        'os_id', v_apontamento.os_id,
        'numero_os', v_numero_os,
        'apontamento_id', v_apontamento.id,
        'cancelado_por_user_id', v_auth_uid,
        'cancelado_por_nome', v_cancelado_por_nome,
        'cancelamento_motivo', v_motivo
      ),
      'hora_cancelada:' || v_apontamento.id::text
    );
    v_notificacao_id := coalesce(v_enviada, v_notificacao_id);
  end loop;

  return jsonb_build_object(
    'sucesso', true,
    'gravados', 1,
    'avisos', '[]'::jsonb,
    'erros', '[]'::jsonb,
    'notificacao_enviada', v_notificacao_id is not null,
    'cancelado_por_nome', v_cancelado_por_nome
  );
end;
$function$;

do $assertions$
begin
  if pg_get_functiondef('public.app_cancelar_apontamento(uuid, text)'::regprocedure)
     not like '%destinatario is distinct from v_auth_uid%' then
    raise exception 'app_cancelar_apontamento continua avisando quem cancelou';
  end if;
end;
$assertions$;

commit;
