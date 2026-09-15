-- =====================================================================================
-- Hora interna corrigida pela própria pessoa.
--
-- Decidido com o Gabriel em 15/09/2026. A hora interna nasce aprovada
-- (20260914140000_horas_internas.sql), e pela regra da hora em OS hora aprovada só a
-- gestão altera: quem lançava errado não conseguia corrigir. Pior, em produção a
-- coordenação (papel GESTOR no tenant), o apontador e o técnico não têm a permissão
-- geral de editar apontamentos, então nem a coordenação corrigia o que lançou.
--
-- Regra da hora interna:
--  - a própria pessoa edita as horas e cancela as suas;
--  - quem lançou para outra pessoa (a coordenação lançando para a equipe) edita e
--    cancela o que lançou — a conta do tablet não conta como "quem lançou";
--  - diretoria e administração, qualquer uma;
--  - coordenação NÃO corrige hora interna que não lançou.
-- Hora em OS não muda.
--
-- Funções geradas a partir das definições de produção de 15/09/2026.
-- =====================================================================================

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. Quem pode alterar ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_usuario_pode_alterar_apontamento(p_tenant_id uuid, p_empresa_id uuid, p_auth_uid uuid, p_apontamento_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'a'
 SET row_security TO 'off'
AS $function$
  select coalesce((
    select case
      when coalesce(apontamento.gerado_por_hh, false) then false
      when lower(coalesce(apontamento.status, '')) = 'fechado' then false
      -- Hora interna nasce aprovada, então a regra de antes e depois da aprovação não
      -- serve. Corrige a própria pessoa; quem lançou para outra pessoa (a coordenação
      -- lançando para a equipe — no tablet quem grava é a conta do aparelho, que não
      -- conta); e diretoria e administração. Coordenação não corrige hora interna que
      -- não lançou. Decidido com o Gabriel em 15/09/2026.
      when apontamento.atividade_id is not null then
        p_auth_uid is not null
        and (
          coalesce(acesso.papel, '') in ('ADMIN', 'DIRETOR')
          or colaborador.user_id = p_auth_uid
          or (apontamento.tablet_sessao_id is null and apontamento.criado_por_user_id = p_auth_uid)
        )
      when coalesce(acesso.papel, '') in ('ADMIN', 'DIRETOR', 'COORDENACAO') then true
      when p_auth_uid is not null
        and ordem.responsavel_aprovacao_id = p_auth_uid then true
      when coalesce(apontamento.status_aprovacao, 'pendente') = 'aprovado' then false
      else colaborador.user_id = p_auth_uid
    end
    from public.apontamentos_horas as apontamento
    join public.colaboradores as colaborador
      on colaborador.id = apontamento.colaborador_id
     and colaborador.tenant_id = apontamento.tenant_id
     and colaborador.empresa_id = apontamento.empresa_id
    left join public.ordens_servico as ordem
      on ordem.id = apontamento.os_id
     and ordem.tenant_id = apontamento.tenant_id
     and ordem.empresa_id = apontamento.empresa_id
    left join lateral (
      select upper(usuario_empresa.papel) as papel
      from a.usuario as usuario
      join a.usuario_empresa as usuario_empresa
        on usuario_empresa.usuario_id = usuario.id
       and usuario_empresa.empresa_id = p_empresa_id
       and usuario_empresa.ativo is true
       and usuario_empresa.deleted_at is null
      where usuario.auth_user_id = p_auth_uid
        and usuario.ativo is true
        and usuario.deleted_at is null
      limit 1
    ) as acesso on true
    where apontamento.id = p_apontamento_id
      and apontamento.tenant_id = p_tenant_id
      and apontamento.empresa_id = p_empresa_id
  ), false);
$function$;

-- 2. Editar pelo aplicativo -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.app_editar_apontamento(p_apontamento_id uuid, p_horas numeric, p_tipo_hora_id uuid, p_descricao text, p_confirmar_avisos boolean, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'a', 'c'
 SET row_security TO 'off'
AS $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_os_id integer;
  v_colaborador_id uuid;
  v_colaborador_user_id uuid;
  v_data date;
  v_gerado_por_hh boolean;
  v_status text;
  v_status_aprovacao text;
  v_horas_antes numeric;
  v_tipo_hora_antes uuid;
  v_descricao_antes text;
  v_tipo_existe boolean;
  v_descricao text := nullif(btrim(p_descricao), '');
  v_motivo text := nullif(btrim(p_motivo), '');
  v_editor_nome text;
  v_hora_de_terceiro boolean;
  v_atividade_id uuid;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar autenticação, tenant e empresa ativos.';
  end if;
  -- Hora interna: quem corrige é decidido só por fn_usuario_pode_alterar_apontamento
  -- (a própria pessoa, quem lançou, diretoria e administração). O apontador e a
  -- coordenação não têm a permissão geral de editar apontamentos, e sem esta separação
  -- ninguém além da diretoria corrigiria a própria hora interna. Hora em OS continua
  -- exigindo a permissão.
  select apontamento.atividade_id
    into v_atividade_id
  from public.apontamentos_horas as apontamento
  where apontamento.id = p_apontamento_id
    and apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id;
  if v_atividade_id is null and not public.can('apontamentos', 'write', v_tenant_id) then
    raise exception 'Seu perfil não possui permissão para editar apontamentos.';
  end if;
  if p_horas is null or p_horas <= 0 or p_horas > 24 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'horas', 'mensagem', 'Informe uma quantidade de horas entre 0 e 24.')));
  end if;
  -- Na hora interna a descrição é opcional, como no lançamento (o tablet nem pede).
  if v_atividade_id is null and (v_descricao is null or char_length(v_descricao) < 10) then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'descricao', 'mensagem', 'Descreva o serviço realizado com pelo menos 10 caracteres.')));
  end if;

  select apontamento.os_id, apontamento.colaborador_id, apontamento.data, apontamento.gerado_por_hh,
         apontamento.status::text, apontamento.status_aprovacao,
         apontamento.horas, apontamento.tipo_hora_id, apontamento.descricao,
         colaborador.user_id
    into v_os_id, v_colaborador_id, v_data, v_gerado_por_hh, v_status, v_status_aprovacao,
         v_horas_antes, v_tipo_hora_antes, v_descricao_antes,
         v_colaborador_user_id
  from public.apontamentos_horas as apontamento
  join public.colaboradores as colaborador
    on colaborador.id = apontamento.colaborador_id
   and colaborador.tenant_id = apontamento.tenant_id
   and colaborador.empresa_id = apontamento.empresa_id
  where apontamento.id = p_apontamento_id
    and apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id;

  if not found then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'apontamento', 'mensagem', 'O apontamento informado não existe ou não pertence à empresa atual.')));
  end if;
  if coalesce(v_gerado_por_hh, false) then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'hh', 'mensagem', 'Este apontamento é um espelho de HH e deve ser alterado no módulo HH.')));
  end if;
  if lower(coalesce(v_status, '')) = 'fechado' then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'status', 'mensagem', 'Este apontamento está fechado e não pode ser alterado.')));
  end if;
  if not public.fn_usuario_pode_alterar_apontamento(v_tenant_id, v_empresa_id, v_auth_uid, p_apontamento_id) then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'permissao',
        'mensagem', case
          when v_atividade_id is not null then 'Hora interna só pode ser alterada pela própria pessoa, por quem a lançou, pela diretoria ou pela administração.'
          when v_status_aprovacao = 'aprovado' then 'Após a aprovação, somente o responsável da OS, Coordenação, Diretor ou Admin pode alterar.'
          else 'Antes da aprovação, somente o próprio colaborador, o responsável da OS, Coordenação, Diretor ou Admin pode alterar.'
        end
      )));
  end if;

  -- A tela de hora interna não escolhe tipo de hora: sem tipo, fica o que a
  -- classificação deu no lançamento.
  if v_atividade_id is not null and p_tipo_hora_id is null then
    p_tipo_hora_id := v_tipo_hora_antes;
  end if;

  v_hora_de_terceiro := v_colaborador_user_id is distinct from v_auth_uid;

  if v_hora_de_terceiro and (v_motivo is null or char_length(v_motivo) < 5) then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'motivo', 'mensagem', 'Para alterar a hora de outro colaborador, informe o motivo com pelo menos 5 caracteres.')));
  end if;
  if v_motivo is not null and char_length(v_motivo) > 500 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'motivo', 'mensagem', 'O motivo da alteração deve ter no máximo 500 caracteres.')));
  end if;

  select exists (
    select 1
    from public.tipos_horas as tipo
    where tipo.id = p_tipo_hora_id
      and tipo.tenant_id = v_tenant_id
      and tipo.ativo
  ) into v_tipo_existe;
  if not v_tipo_existe then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'tipo_hora', 'mensagem', 'O tipo de hora informado não existe ou está inativo.')));
  end if;
  if exists (
    select 1
    from public.apontamentos_horas as apontamento
    where apontamento.id <> p_apontamento_id
      and apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
      and apontamento.os_id = v_os_id
      and apontamento.colaborador_id = v_colaborador_id
      and apontamento.data = v_data
      and apontamento.tipo_hora_id = p_tipo_hora_id
      and not coalesce(apontamento.gerado_por_hh, false)
  ) and p_tipo_hora_id is distinct from v_tipo_hora_antes then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'duplicidade', 'mensagem', 'Já existe outro apontamento para esta OS, colaborador, data e tipo de hora.')));
  end if;

  update public.apontamentos_horas
  set horas = p_horas,
      tipo_hora_id = p_tipo_hora_id,
      descricao = v_descricao
  where id = p_apontamento_id
    and tenant_id = v_tenant_id
    and empresa_id = v_empresa_id;

  select coalesce(
           nullif(btrim(usuario.nome), ''),
           nullif(btrim(usuario.email), ''),
           'Usuário não identificado'
         )
    into v_editor_nome
  from a.usuario as usuario
  where usuario.auth_user_id = v_auth_uid
    and usuario.ativo is true
    and usuario.deleted_at is null
  limit 1;

  insert into public.apontamentos_horas_edicoes (
    apontamento_id, tenant_id, empresa_id, os_id, colaborador_id,
    editado_por_user_id, editado_por_nome, motivo,
    horas_antes, horas_depois,
    tipo_hora_id_antes, tipo_hora_id_depois,
    descricao_antes, descricao_depois,
    status_aprovacao_no_momento
  ) values (
    p_apontamento_id, v_tenant_id, v_empresa_id, v_os_id, v_colaborador_id,
    v_auth_uid, coalesce(v_editor_nome, 'Usuário não identificado'), v_motivo,
    v_horas_antes, p_horas,
    v_tipo_hora_antes, p_tipo_hora_id,
    v_descricao_antes, v_descricao,
    v_status_aprovacao
  );

  if v_hora_de_terceiro and v_colaborador_user_id is not null then
    perform public.app_criar_notificacao(
      v_tenant_id,
      v_empresa_id,
      v_colaborador_user_id,
      'hora_alterada',
      'Hora alterada',
      format(
        '%s alterou a sua hora de %s %s. Motivo: %s',
        coalesce(v_editor_nome, 'Um responsável'),
        to_char(v_data, 'DD/MM/YYYY'),
        -- Hora interna não tem OS: o aviso fala da atividade ("em Comercial").
        coalesce(
          (
            select 'na OS ' || coalesce(nullif(btrim(ordem.numero_os), ''), ordem.os_num::text, ordem.id::text)
            from public.ordens_servico as ordem
            where ordem.id = v_os_id
              and ordem.tenant_id = v_tenant_id
              and ordem.empresa_id = v_empresa_id
          ),
          (
            select 'em ' || atividade.nome
            from public.apontamentos_horas as apontamento
            join public.atividades_internas as atividade
              on atividade.id = apontamento.atividade_id
            where apontamento.id = p_apontamento_id
          ),
          'no lançamento'
        ),
        v_motivo
      ),
      jsonb_build_object(
        'os_id', v_os_id,
        'apontamento_id', p_apontamento_id,
        'url', coalesce('/os/' || v_os_id::text, '/(tabs)/historico')
      ),
      'hora_alterada'
    );
  end if;

  return jsonb_build_object('sucesso', true, 'gravados', 1, 'avisos', '[]'::jsonb, 'erros', '[]'::jsonb);
end;
$function$;

-- 3. Cancelar ---------------------------------------------------------------------------
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
    coalesce(v_apontamento.criado_por_user_id, colaborador.user_id)
    into
      v_numero_os,
      v_cliente_nome,
      v_colaborador_nome,
      v_tipo_hora_nome,
      v_lancado_por_user_id
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

  v_notificacao_id := public.app_criar_notificacao(
    v_tenant_id,
    v_empresa_id,
    v_lancado_por_user_id,
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

-- 4. Editar pelo web --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.web_atualizar_apontamento_horas(p_apontamento_id uuid, p_dados jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
 SET row_security TO 'off'
AS $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_interna boolean;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;
  -- Hora interna: a mesma regra do aplicativo (fn_usuario_pode_alterar_apontamento
  -- decide sozinha); hora em OS continua exigindo a permissão de editar apontamentos.
  select exists (
    select 1 from public.apontamentos_horas as apontamento
    where apontamento.id = p_apontamento_id
      and apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
      and apontamento.atividade_id is not null
  ) into v_interna;
  if not v_interna and not public.can('apontamentos', 'write', v_tenant_id) then
    raise exception 'Seu perfil não possui permissão para editar apontamentos.';
  end if;
  if not public.fn_usuario_pode_editar_apontamento(v_tenant_id, v_empresa_id, v_auth_uid, p_apontamento_id) then
    if v_interna then
      raise exception 'Hora interna só pode ser alterada pela própria pessoa, por quem a lançou, pela diretoria ou pela administração.';
    end if;
    raise exception 'Antes da aprovação, somente o próprio colaborador pode alterar. Após a aprovação, somente Coordenação, Diretor ou Admin.';
  end if;

  update public.apontamentos_horas
  set data = coalesce(nullif(p_dados->>'data', '')::date, data),
      horas = case when p_dados ? 'horas' then nullif(p_dados->>'horas', '')::numeric else horas end,
      tipo_hora_id = case when p_dados ? 'tipo_hora_id' then nullif(p_dados->>'tipo_hora_id', '')::uuid else tipo_hora_id end,
      descricao = case when p_dados ? 'descricao' then nullif(p_dados->>'descricao', '') else descricao end,
      hora_entrada_1 = case when p_dados ? 'hora_entrada_1' then nullif(p_dados->>'hora_entrada_1', '')::time else hora_entrada_1 end,
      hora_saida_1 = case when p_dados ? 'hora_saida_1' then nullif(p_dados->>'hora_saida_1', '')::time else hora_saida_1 end,
      hora_entrada_2 = case when p_dados ? 'hora_entrada_2' then nullif(p_dados->>'hora_entrada_2', '')::time else hora_entrada_2 end,
      hora_saida_2 = case when p_dados ? 'hora_saida_2' then nullif(p_dados->>'hora_saida_2', '')::time else hora_saida_2 end
  where id = p_apontamento_id
    and tenant_id = v_tenant_id
    and empresa_id = v_empresa_id
    and not coalesce(gerado_por_hh, false);

  if not found then
    raise exception 'Apontamento não encontrado, fora da empresa atual ou gerado por HH.';
  end if;
  return jsonb_build_object('sucesso', true);
end;
$function$;

-- 5. Histórico do aplicativo com pode_alterar e descricao_hora --------------------------
-- O retorno ganha duas colunas no fim: DROP + CREATE, com os mesmos grants de antes. O
-- aplicativo já publicado ignora as colunas a mais.
drop function if exists public.app_historico_lancamentos(text, date, date, uuid, integer, integer, text);
CREATE OR REPLACE FUNCTION public.app_historico_lancamentos(p_tipo text DEFAULT 'tudo'::text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_colaborador_id uuid DEFAULT NULL::uuid, p_os_id integer DEFAULT NULL::integer, p_limite integer DEFAULT 40, p_cursor text DEFAULT NULL::text)
 RETURNS TABLE(tipo text, origem_id text, criado_em timestamp with time zone, data_lancamento date, os_id integer, numero_os text, cliente_nome text, descricao text, quantidade numeric, unidade text, status text, nao_cobrado boolean, autor_id uuid, autor_nome text, pode_ver_autoria boolean, aprovado_por_nome text, atividade_nome text, cursor text, pode_alterar boolean, descricao_hora text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'a', 'auth'
 SET row_security TO 'off'
AS $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_colaborador_id uuid;
  v_apontador boolean;
  v_tipo text := lower(coalesce(nullif(btrim(p_tipo), ''), 'tudo'));
  v_de date := coalesce(p_de, current_date - 29);
  v_ate date := coalesce(p_ate, current_date);
  v_limite integer := greatest(1, least(coalesce(p_limite, 40), 100));
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticacao e contexto de empresa sao obrigatorios.';
  end if;

  v_papel := a.fn_current_empresa_papel(v_tenant_id, v_empresa_id);
  if v_papel is null or v_papel = 'PAINEL_TV' then
    raise exception 'Sem permissao para consultar o historico do app.';
  end if;

  if v_tipo not in ('tudo', 'horas', 'materiais') then
    raise exception 'Tipo de historico invalido.';
  end if;
  if v_de > v_ate then
    raise exception 'Periodo de historico invalido.';
  end if;

  select colaborador.id
    into v_colaborador_id
  from public.colaboradores as colaborador
  where colaborador.user_id = v_auth_uid
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true
  limit 1;

  v_apontador := v_papel in ('TECNICO', 'APONTAMENTO_RH', 'APONTADOR');
  if v_apontador and v_colaborador_id is null then
    raise exception 'Seu usuario nao esta vinculado a um colaborador ativo nesta empresa.';
  end if;

  return query
  with lancamentos as (
    select
      'hora'::text as tipo,
      apontamento.id::text as origem_id,
      apontamento.criado_em::timestamptz as criado_em,
      apontamento.data as data_lancamento,
      os.id as os_id,
      coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text)::text as numero_os,
      coalesce(nullif(btrim(os.cliente_nome), ''), nullif(btrim(cliente_cadastro.nome), ''),
               nullif(btrim(apontamento.cliente_nome), ''),
               case when apontamento.atividade_id is null then 'Cliente nao informado' end)::text as cliente_nome,
      -- Hora interna sem descrição fica sem descrição: o título já é a atividade, e
      -- "Apontamento de horas" embaixo de "Treinamento" não diz nada.
      coalesce(nullif(btrim(os.descricao_servico), ''), nullif(btrim(apontamento.orcamento_descricao), ''),
               nullif(btrim(apontamento.descricao), ''),
               case when apontamento.atividade_id is null then 'Apontamento de horas' end)::text as descricao,
      apontamento.horas::numeric as quantidade,
      'h'::text as unidade,
      coalesce(nullif(btrim(apontamento.status_aprovacao), ''), nullif(btrim(apontamento.status), ''), 'pendente')::text as status,
      false as nao_cobrado,
      apontamento.colaborador_id as autor_id,
      colaborador.nome::text as autor_nome,
      case
        when apontamento.aprovado_automaticamente_em is not null and apontamento.aprovado_por is null
          then 'Aprovação automática'
        else coalesce(
          nullif(btrim(perfil.nome), ''),
          nullif(btrim(aprovador.nome), ''),
          nullif(btrim(colaborador_aprovador.nome), '')
        )
      end::text as aprovado_por_nome,
      at.nome::text as atividade_nome,
      apontamento.descricao::text as descricao_hora
    from public.apontamentos_horas as apontamento
    left join public.atividades_internas as at
      on at.id = apontamento.atividade_id
    -- Comercial com cliente do cadastro guarda só cliente_id.
    left join public.clientes as cliente_cadastro
      on cliente_cadastro.id = apontamento.cliente_id
     and cliente_cadastro.tenant_id = v_tenant_id
     and cliente_cadastro.empresa_id = v_empresa_id
    -- Hora interna nao tem OS. O left join deixa a linha viver; o filtro logo
    -- abaixo continua barrando hora de OV, que era o que o inner join fazia.
    left join public.ordens_servico as os
      on os.id = apontamento.os_id
     and os.tenant_id = v_tenant_id
     and os.empresa_id = v_empresa_id
     and coalesce(os.tipo_documento, 'OS') = 'OS'
    join public.colaboradores as colaborador
      on colaborador.id = apontamento.colaborador_id
     and colaborador.tenant_id = v_tenant_id
     and colaborador.empresa_id = v_empresa_id
    left join public.profiles as perfil on perfil.id = apontamento.aprovado_por
    left join a.usuario as aprovador
      on aprovador.auth_user_id = apontamento.aprovado_por
     and aprovador.ativo is true
     and aprovador.deleted_at is null
    left join public.colaboradores as colaborador_aprovador
      on colaborador_aprovador.user_id = apontamento.aprovado_por
     and colaborador_aprovador.tenant_id = v_tenant_id
     and colaborador_aprovador.empresa_id = v_empresa_id
    where apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
      and apontamento.data between v_de and v_ate
      and v_tipo in ('tudo', 'horas')
      and (apontamento.atividade_id is not null or os.id is not null)
      and (p_os_id is null or apontamento.os_id = p_os_id)
      and (
        case when v_apontador then apontamento.colaborador_id = v_colaborador_id
             else p_colaborador_id is null or apontamento.colaborador_id = p_colaborador_id end
      )

    union all

    select
      'material'::text,
      movimentacao.id::text,
      coalesce(movimentacao.created_at, movimentacao.data_movimentacao)::timestamptz,
      movimentacao.data_movimentacao::date,
      os.id,
      coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text)::text,
      coalesce(nullif(btrim(os.cliente_nome), ''), 'Cliente nao informado')::text,
      (coalesce(nullif(btrim(item.nome), ''), nullif(btrim(item.descricao), ''), 'Material')
        || case when nullif(btrim(item.codigo_interno), '') is not null then ' - cod. ' || item.codigo_interno else '' end)::text,
      movimentacao.quantidade::numeric,
      coalesce(nullif(btrim(item.unidade_medida), ''), 'un')::text,
      'baixado'::text,
      coalesce(item_os.nao_cobrado, false),
      autor.id,
      autor.nome::text,
      null::text,
      null::text,
      null::text
    from public.movimentacoes as movimentacao
    join public.ordens_servico as os
      on os.id = movimentacao.origem_os_id
     and os.tenant_id = v_tenant_id
     and os.empresa_id = v_empresa_id
     and coalesce(os.tipo_documento, 'OS') = 'OS'
    join public.itens as item
      on item.id = movimentacao.item_id
     and item.tenant_id = v_tenant_id
     and item.empresa_id = v_empresa_id
    left join lateral (
      select
        colaborador.id,
        colaborador.nome
      from public.colaboradores as colaborador
      where colaborador.tenant_id = v_tenant_id
        and colaborador.empresa_id = v_empresa_id
        and colaborador.ativo is true
        and (
          colaborador.user_id::text = movimentacao.realizado_por
          or lower(coalesce(colaborador.email, '')) = lower(coalesce(movimentacao.realizado_por, ''))
        )
      order by case when colaborador.user_id::text = movimentacao.realizado_por then 0 else 1 end
      limit 1
    ) as autor on true
    left join lateral (
      select public.os_lancamento_nao_cobrado(
        v_tenant_id,
        v_empresa_id,
        item_lancado.os_id,
        item_lancado.criado_em
      ) as nao_cobrado
      from public.os_itens as item_lancado
      where item_lancado.tenant_id = v_tenant_id
        and item_lancado.empresa_id = v_empresa_id
        and item_lancado.os_id = movimentacao.origem_os_id
        and item_lancado.item_id = movimentacao.item_id
        and abs(extract(epoch from (item_lancado.criado_em - movimentacao.data_movimentacao))) <= 600
      order by abs(extract(epoch from (item_lancado.criado_em - movimentacao.data_movimentacao))), item_lancado.id desc
      limit 1
    ) as item_os on true
    where movimentacao.tenant_id = v_tenant_id
      and movimentacao.empresa_id = v_empresa_id
      and movimentacao.tipo = 'saida'
      and movimentacao.motivo like 'Material lançado pelo app na OS %'
      and movimentacao.data_movimentacao::date between v_de and v_ate
      and v_tipo in ('tudo', 'materiais')
      and (p_os_id is null or movimentacao.origem_os_id = p_os_id)
      and (
        case when v_apontador then autor.id = v_colaborador_id
             else p_colaborador_id is null or autor.id = p_colaborador_id end
      )
  ), com_cursor as (
    select
      lancamento.*,
      to_char(lancamento.criado_em at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US')
        || '|' || lancamento.tipo || '|' || lancamento.origem_id as chave_cursor
    from lancamentos as lancamento
  )
  select
    lancamento.tipo,
    lancamento.origem_id,
    lancamento.criado_em,
    lancamento.data_lancamento,
    lancamento.os_id,
    lancamento.numero_os,
    lancamento.cliente_nome,
    lancamento.descricao,
    lancamento.quantidade,
    lancamento.unidade,
    lancamento.status,
    lancamento.nao_cobrado,
    case when v_apontador then null::uuid else lancamento.autor_id end,
    case when v_apontador then null::text else lancamento.autor_nome end,
    not v_apontador,
    case when v_apontador then null::text else lancamento.aprovado_por_nome end,
    lancamento.atividade_nome,
    lancamento.chave_cursor,
    -- Só hora interna: é a linha que o Histórico deixa corrigir. Hora em OS se corrige
    -- na tela da OS, com a permissão de editar apontamentos. Calculado depois do
    -- limite, só para a página que vai para a tela.
    case
      when lancamento.tipo = 'hora' and lancamento.atividade_nome is not null
        then public.fn_usuario_pode_alterar_apontamento(v_tenant_id, v_empresa_id, v_auth_uid, lancamento.origem_id::uuid)
      else false
    end,
    -- A descrição gravada na hora (a coluna descricao mostra o orçamento quando há).
    lancamento.descricao_hora
  from (
    select pagina.*
    from com_cursor as pagina
    where p_cursor is null or pagina.chave_cursor < p_cursor
    order by pagina.chave_cursor desc
    limit v_limite
  ) as lancamento
  order by lancamento.chave_cursor desc;
end;
$function$;
revoke all on function public.app_historico_lancamentos(text, date, date, uuid, integer, integer, text) from public, anon;
grant execute on function public.app_historico_lancamentos(text, date, date, uuid, integer, integer, text) to authenticated, service_role;

do $assertions$
begin
  if pg_get_functiondef('public.fn_usuario_pode_alterar_apontamento(uuid, uuid, uuid, uuid)'::regprocedure)
     not like '%apontamento.criado_por_user_id = p_auth_uid%' then
    raise exception 'fn_usuario_pode_alterar_apontamento ficou sem a regra de quem lançou a hora interna';
  end if;
  if pg_get_function_result('public.app_historico_lancamentos(text, date, date, uuid, integer, integer, text)'::regprocedure)
     not like '%pode_alterar boolean, descricao_hora text%' then
    raise exception 'app_historico_lancamentos ficou sem pode_alterar e descricao_hora';
  end if;
  if not has_function_privilege('authenticated', 'public.app_historico_lancamentos(text, date, date, uuid, integer, integer, text)', 'execute')
     or not has_function_privilege('service_role', 'public.app_historico_lancamentos(text, date, date, uuid, integer, integer, text)', 'execute') then
    raise exception 'app_historico_lancamentos perdeu grants';
  end if;
  if pg_get_functiondef('public.app_editar_apontamento(uuid, numeric, uuid, text, boolean, text)'::regprocedure)
     not like '%v_atividade_id is null and not public.can(%' then
    raise exception 'app_editar_apontamento continua exigindo a permissão geral na hora interna';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
