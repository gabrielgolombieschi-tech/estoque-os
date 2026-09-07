-- Notificacoes de quem so aponta hora (APONTADOR, APONTAMENTO_RH, TECNICO)
-- passam a ser apenas as que falam das horas dele. Decisao de Gabriel em
-- 06/09/2026.
--
-- O que muda:
--
-- 1. Dois tipos novos. 'hora_aprovada' cobre a aprovacao feita por alguem —
--    so existia 'hora_aprovada_automaticamente', da regra de 7 dias, entao o
--    colaborador nao ficava sabendo quando alguem aprovava de fato.
--    'hora_alterada' avisa o dono da hora quando outra pessoa edita o
--    lancamento dele (o cancelamento ja avisava, por 'hora_cancelada').
--
-- 2. fn_notificacao_tipos_do_papel decide o que cada papel pode receber. Para
--    os papeis de apontamento sobram apenas os cinco tipos de hora; os avisos
--    de fluxo de OS e de material somem, inclusive quando a pessoa e a
--    responsavel de alguma OS. Isso vale nos dois lados: app_criar_notificacao
--    recusa o que nao e do papel, e app_listar_preferencias_notificacoes mostra
--    so o que pode chegar — assim toda notificacao que ele recebe tem um botao
--    para desligar em Configuracoes, e nao sobra botao que nao serve para nada.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

-- 1. Tipos novos --------------------------------------------------------------

alter table public.app_notificacoes
  drop constraint chk_app_notificacoes_tipo;

alter table public.app_notificacoes
  add constraint chk_app_notificacoes_tipo check (tipo = any (array[
    'hora_pendente', 'hora_aprovada', 'hora_aprovada_automaticamente',
    'hora_rejeitada', 'hora_cancelada', 'hora_alterada',
    'os_concluida', 'os_faturada', 'os_concluida_garantia',
    'material_lancado', 'os_reaberta'
  ]::text[]));

alter table public.app_notificacoes_preferencias
  drop constraint chk_app_notificacoes_preferencias_tipo;

alter table public.app_notificacoes_preferencias
  add constraint chk_app_notificacoes_preferencias_tipo check (tipo = any (array[
    'hora_pendente', 'hora_aprovada', 'hora_aprovada_automaticamente',
    'hora_rejeitada', 'hora_cancelada', 'hora_alterada',
    'os_concluida', 'os_faturada', 'os_concluida_garantia',
    'material_lancado', 'os_reaberta'
  ]::text[]));

-- 2. O que cada papel pode receber -------------------------------------------

create or replace function public.fn_notificacao_tipos_do_papel(p_papel text)
returns text[]
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select case
    when upper(coalesce(p_papel, '')) in ('APONTADOR', 'APONTAMENTO_RH', 'TECNICO')
      then array[
        'hora_aprovada', 'hora_aprovada_automaticamente',
        'hora_rejeitada', 'hora_cancelada', 'hora_alterada'
      ]::text[]
    else array[
      'hora_pendente', 'hora_aprovada', 'hora_aprovada_automaticamente',
      'hora_rejeitada', 'hora_cancelada', 'hora_alterada',
      'os_concluida', 'os_faturada', 'os_concluida_garantia',
      'material_lancado', 'os_reaberta'
    ]::text[]
  end;
$$;

comment on function public.fn_notificacao_tipos_do_papel(text) is
  'Tipos de notificacao que um papel de empresa pode receber. Quem so aponta hora recebe apenas o que fala das horas dele.';

revoke all on function public.fn_notificacao_tipos_do_papel(text) from public, anon, authenticated, service_role;

-- 3. Criacao da notificacao respeita o papel do destinatario ------------------

create or replace function public.app_criar_notificacao(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_usuario_id uuid,
  p_tipo text,
  p_titulo text,
  p_corpo text,
  p_dados jsonb default '{}'::jsonb,
  p_agrupamento_chave text default null::text
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $function$
declare
  v_id uuid;
  v_quantidade integer;
  v_titulo text;
  v_corpo text;
  v_papel text;
begin
  if p_usuario_id is null
     or p_tenant_id is null
     or p_empresa_id is null
     or p_tipo not in (
       'hora_pendente', 'hora_aprovada', 'hora_aprovada_automaticamente',
       'hora_rejeitada', 'hora_cancelada', 'hora_alterada',
       'os_concluida', 'os_faturada', 'os_concluida_garantia',
       'material_lancado', 'os_reaberta'
     ) then
    return null;
  end if;

  if not exists (
    select 1
    from public.empresa_memberships as membership
    where membership.tenant_id = p_tenant_id
      and membership.empresa_id = p_empresa_id
      and membership.user_id = p_usuario_id
      and membership.status = 'active'
  ) then
    return null;
  end if;

  select upper(usuario_empresa.papel::text)
    into v_papel
  from a.usuario as usuario
  join a.usuario_empresa as usuario_empresa
    on usuario_empresa.usuario_id = usuario.id
   and usuario_empresa.empresa_id = p_empresa_id
   and usuario_empresa.ativo is true
   and usuario_empresa.deleted_at is null
  where usuario.auth_user_id = p_usuario_id
    and usuario.ativo is true
    and usuario.deleted_at is null
  limit 1;

  -- Papel desconhecido cai no conjunto amplo, que e o comportamento antigo.
  if not (p_tipo = any (public.fn_notificacao_tipos_do_papel(v_papel))) then
    return null;
  end if;

  if exists (
    select 1
    from public.app_notificacoes_preferencias as preferencia
    where preferencia.tenant_id = p_tenant_id
      and preferencia.empresa_id = p_empresa_id
      and preferencia.usuario_id = p_usuario_id
      and preferencia.tipo = p_tipo
      and not preferencia.habilitada
  ) then
    return null;
  end if;

  if p_agrupamento_chave is not null then
    update public.app_notificacoes as notificacao
       set quantidade = notificacao.quantidade + 1,
           atualizado_em = now(),
           dados = coalesce(p_dados, '{}'::jsonb) || jsonb_build_object('agrupada', true)
     where notificacao.tenant_id = p_tenant_id
       and notificacao.empresa_id = p_empresa_id
       and notificacao.usuario_id = p_usuario_id
       and notificacao.tipo = p_tipo
       and notificacao.agrupamento_chave = p_agrupamento_chave
       and notificacao.lida_em is null
     returning notificacao.id, notificacao.quantidade
      into v_id, v_quantidade;

    if found then
      v_titulo := case p_tipo
        when 'hora_pendente' then format('%s horas pendentes de aprovação', v_quantidade)
        when 'hora_aprovada' then format('%s horas aprovadas', v_quantidade)
        when 'hora_alterada' then format('%s horas alteradas', v_quantidade)
        when 'hora_cancelada' then format('%s apontamentos cancelados', v_quantidade)
        when 'material_lancado' then format('%s materiais lançados em OS', v_quantidade)
        when 'os_concluida' then format('%s OS concluídas aguardando faturamento', v_quantidade)
        when 'os_faturada' then format('%s OS faturadas', v_quantidade)
        when 'os_concluida_garantia' then format('%s atendimentos de garantia concluídos', v_quantidade)
        when 'os_reaberta' then format('%s OS reabertas', v_quantidade)
        else format('%s novas notificações', v_quantidade)
      end;
      v_corpo := 'Abra a central de notificações para ver os detalhes.';

      update public.app_notificacoes
         set titulo = v_titulo,
             corpo = v_corpo,
             dados = dados || jsonb_build_object(
               'url', '/notificacoes',
               'quantidade', v_quantidade
             )
       where id = v_id;

      update public.app_notificacoes_push_entregas
         set status = 'pendente',
             tentativas = 0,
             erro = null,
             enviado_em = null,
             atualizado_em = now()
       where notificacao_id = v_id;

      return v_id;
    end if;
  end if;

  insert into public.app_notificacoes (
    tenant_id,
    empresa_id,
    usuario_id,
    tipo,
    titulo,
    corpo,
    dados,
    agrupamento_chave
  ) values (
    p_tenant_id,
    p_empresa_id,
    p_usuario_id,
    p_tipo,
    p_titulo,
    p_corpo,
    coalesce(p_dados, '{}'::jsonb),
    p_agrupamento_chave
  )
  returning id into v_id;

  insert into public.app_notificacoes_push_entregas (
    notificacao_id,
    dispositivo_id
  )
  select v_id, dispositivo.id
  from public.app_dispositivos_push as dispositivo
  where dispositivo.tenant_id = p_tenant_id
    and dispositivo.empresa_id = p_empresa_id
    and dispositivo.usuario_id = p_usuario_id
    and dispositivo.ativo;

  return v_id;
end;
$function$;

-- 4. A tela de preferencias mostra so o que pode chegar -----------------------

create or replace function public.app_listar_preferencias_notificacoes()
returns table(tipo text, habilitada boolean)
language sql
security definer
set search_path to 'pg_catalog', 'public', 'a', 'auth'
set row_security to 'off'
as $function$
  with papel as (
    select upper(usuario_empresa.papel::text) as papel
    from a.usuario as usuario
    join a.usuario_empresa as usuario_empresa
      on usuario_empresa.usuario_id = usuario.id
     and usuario_empresa.empresa_id = public.current_empresa_id()
     and usuario_empresa.ativo is true
     and usuario_empresa.deleted_at is null
    where usuario.auth_user_id = auth.uid()
      and usuario.ativo is true
      and usuario.deleted_at is null
    limit 1
  ),
  tipos(tipo) as (
    select unnest(public.fn_notificacao_tipos_do_papel((select papel from papel)))
  )
  select tipos.tipo, coalesce(preferencia.habilitada, true)
  from tipos
  left join public.app_notificacoes_preferencias as preferencia
    on preferencia.tenant_id = public.current_tenant_id()
   and preferencia.empresa_id = public.current_empresa_id()
   and preferencia.usuario_id = auth.uid()
   and preferencia.tipo = tipos.tipo
  where public.app_notificacao_contexto_valido()
  order by tipos.tipo;
$function$;

-- 5. Aprovacao feita por alguem avisa o dono da hora --------------------------

create or replace function public.fn_app_notificar_apontamento_horas()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_responsavel uuid;
  v_destinatario uuid;
  v_dono uuid;
  v_os_numero text;
  v_dados jsonb;
begin
  if coalesce(new.gerado_por_hh, false) then
    return new;
  end if;

  select os.responsavel_aprovacao_id,
         coalesce(nullif(btrim(os.numero_os), ''), os.os_num::text, os.id::text)
    into v_responsavel, v_os_numero
  from public.ordens_servico os
  where os.id = new.os_id
    and os.tenant_id = new.tenant_id
    and os.empresa_id = new.empresa_id;

  -- Dono da hora: o colaborador apontado, que nem sempre e quem lancou.
  select colaborador.user_id
    into v_dono
  from public.colaboradores as colaborador
  where colaborador.id = new.colaborador_id
    and colaborador.tenant_id = new.tenant_id
    and colaborador.empresa_id = new.empresa_id;

  v_dados := jsonb_build_object(
    'os_id', new.os_id,
    'apontamento_id', new.id,
    'url', '/os/' || new.os_id::text
  );

  if tg_op = 'INSERT' and new.status_aprovacao = 'pendente' then
    perform public.app_criar_notificacao(
      new.tenant_id, new.empresa_id, v_responsavel, 'hora_pendente',
      'Hora pendente de aprovação',
      format('Há uma hora lançada na OS %s aguardando sua aprovação.', v_os_numero),
      jsonb_set(v_dados, '{url}', '"/(tabs)/aprovacao"'::jsonb), 'hora_pendente'
    );
  elsif tg_op = 'UPDATE'
    and old.status_aprovacao is distinct from new.status_aprovacao
    and new.status_aprovacao = 'aprovado'
    and new.aprovado_automaticamente_em is not null then
    foreach v_destinatario in array (
      select array_agg(distinct destinatario)
      from unnest(array[v_responsavel, new.criado_por_user_id, v_dono]) as destinatario
      where destinatario is not null
    )
    loop
      perform public.app_criar_notificacao(
        new.tenant_id, new.empresa_id, v_destinatario, 'hora_aprovada_automaticamente',
        'Hora aprovada automaticamente',
        format('A hora lançada na OS %s foi aprovada após 7 dias.', v_os_numero),
        v_dados, null
      );
    end loop;
  elsif tg_op = 'UPDATE'
    and old.status_aprovacao is distinct from new.status_aprovacao
    and new.status_aprovacao = 'aprovado' then
    -- Aprovacao feita por alguem: quem aprovou nao precisa do proprio aviso.
    foreach v_destinatario in array (
      select coalesce(array_agg(distinct destinatario), array[]::uuid[])
      from unnest(array[new.criado_por_user_id, v_dono]) as destinatario
      where destinatario is not null
        and destinatario is distinct from auth.uid()
    )
    loop
      perform public.app_criar_notificacao(
        new.tenant_id, new.empresa_id, v_destinatario, 'hora_aprovada',
        'Hora aprovada',
        format('A hora lançada na OS %s foi aprovada.', v_os_numero),
        v_dados, 'hora_aprovada'
      );
    end loop;
  elsif tg_op = 'UPDATE'
    and old.status_aprovacao is distinct from new.status_aprovacao
    and new.status_aprovacao = 'rejeitado' then
    perform public.app_criar_notificacao(
      new.tenant_id, new.empresa_id, new.criado_por_user_id, 'hora_rejeitada',
      'Hora rejeitada',
      format('A hora lançada na OS %s foi rejeitada. Motivo: %s', v_os_numero, coalesce(new.motivo_devolucao, 'não informado')),
      v_dados, null
    );
  end if;

  return new;
end;
$function$;

-- 6. Editar hora de terceiro avisa o dono da hora ------------------------------

do $patch_editar$
declare
  v_definition text;
  v_needle text := $needle$
  return jsonb_build_object('sucesso', true, 'gravados', 1, 'avisos', '[]'::jsonb, 'erros', '[]'::jsonb);
$needle$;
  v_replacement text := $replacement$
  if v_hora_de_terceiro and v_colaborador_user_id is not null then
    perform public.app_criar_notificacao(
      v_tenant_id,
      v_empresa_id,
      v_colaborador_user_id,
      'hora_alterada',
      'Hora alterada',
      format(
        '%s alterou a sua hora de %s na OS %s. Motivo: %s',
        coalesce(v_editor_nome, 'Um responsável'),
        to_char(v_data, 'DD/MM/YYYY'),
        (
          select coalesce(nullif(btrim(ordem.numero_os), ''), ordem.os_num::text, ordem.id::text)
          from public.ordens_servico as ordem
          where ordem.id = v_os_id
            and ordem.tenant_id = v_tenant_id
            and ordem.empresa_id = v_empresa_id
        ),
        v_motivo
      ),
      jsonb_build_object(
        'os_id', v_os_id,
        'apontamento_id', p_apontamento_id,
        'url', '/os/' || v_os_id::text
      ),
      'hora_alterada'
    );
  end if;

  return jsonb_build_object('sucesso', true, 'gravados', 1, 'avisos', '[]'::jsonb, 'erros', '[]'::jsonb);
$replacement$;
begin
  select pg_get_functiondef('public.app_editar_apontamento(uuid,numeric,uuid,text,boolean,text)'::regprocedure)
    into v_definition;

  if position(v_needle in v_definition) = 0 then
    raise exception 'editar_apontamento_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_editar$;

-- 7. Conferencia ---------------------------------------------------------------

do $assertions$
declare
  v_editar text := pg_get_functiondef('public.app_editar_apontamento(uuid,numeric,uuid,text,boolean,text)'::regprocedure);
begin
  if public.fn_notificacao_tipos_do_papel('APONTADOR') @> array['os_concluida']::text[]
     or not (public.fn_notificacao_tipos_do_papel('APONTADOR') @> array['hora_aprovada', 'hora_alterada', 'hora_cancelada']::text[]) then
    raise exception 'tipos_do_papel_apontador_invalidos';
  end if;

  if not (public.fn_notificacao_tipos_do_papel('COORDENACAO') @> array['os_concluida', 'hora_pendente']::text[]) then
    raise exception 'tipos_do_papel_coordenacao_invalidos';
  end if;

  if position('hora_alterada' in v_editar) = 0 then
    raise exception 'editar_apontamento_sem_notificacao';
  end if;

  if position('hora_aprovada' in pg_get_functiondef('public.fn_app_notificar_apontamento_horas()'::regprocedure)) = 0 then
    raise exception 'trigger_sem_hora_aprovada';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
