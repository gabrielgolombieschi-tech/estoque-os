-- Ajustes pedidos na revisao do app mobile com o perfil APONTADOR:
--
-- 1. Quem altera hora de outra pessoa: responsavel da OS, Coordenacao, Diretor
--    e Admin passam a poder editar e cancelar de qualquer colaborador, em
--    qualquer status. O proprio colaborador continua podendo mexer apenas
--    enquanto a hora nao foi aprovada.
-- 2. Cancelamento substitui a exclusao no app: app_cancelar_apontamento deixa
--    de exigir papel de gestao e passa a usar a mesma regra da edicao, sempre
--    com motivo obrigatorio (a exclusao direta segue desativada).
-- 3. Descricao obrigatoria (minimo 10 caracteres) no lancamento e na edicao de
--    horas pelo app.
-- 4. app_sou_responsavel_os: a tela precisa saber se o usuario e o responsavel
--    da OS para mostrar os botoes de editar/cancelar.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- Todas as funcoes do banco pertencem a postgres. Sem isto, as funcoes novas
-- ficariam com o dono da conexao do CLI e mudariam o efeito do SECURITY DEFINER.
set local role postgres;

-- 1. Regra canonica de alteracao de apontamento -----------------------------

create or replace function public.fn_usuario_pode_alterar_apontamento(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_auth_uid uuid,
  p_apontamento_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'a'
set row_security to 'off'
as $$
  select coalesce((
    select case
      when coalesce(apontamento.gerado_por_hh, false) then false
      when lower(coalesce(apontamento.status, '')) = 'fechado' then false
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
    join public.ordens_servico as ordem
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
$$;

comment on function public.fn_usuario_pode_alterar_apontamento(uuid, uuid, uuid, uuid) is
  'Regra unica de edicao e cancelamento de apontamento: gestao e responsavel da OS alteram de qualquer um; o proprio colaborador so antes da aprovacao.';

-- O nome antigo continua existindo porque web_atualizar_apontamento_horas e
-- app_editar_apontamento ja o chamam. Agora ele apenas delega.
create or replace function public.fn_usuario_pode_editar_apontamento(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_auth_uid uuid,
  p_apontamento_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $$
  select public.fn_usuario_pode_alterar_apontamento(p_tenant_id, p_empresa_id, p_auth_uid, p_apontamento_id);
$$;

-- 2. A tela precisa saber se o usuario e o responsavel da OS ----------------

create or replace function public.app_sou_responsavel_os(p_os_id integer)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  return exists (
    select 1
    from public.ordens_servico as ordem
    where ordem.id = p_os_id
      and ordem.tenant_id = v_tenant_id
      and ordem.empresa_id = v_empresa_id
      and ordem.responsavel_aprovacao_id = v_auth_uid
  );
end;
$function$;

grant execute on function public.app_sou_responsavel_os(integer) to authenticated;

-- 3. Descricao obrigatoria no lancamento de horas do app --------------------

create or replace function public.app_lancar_apontamentos_lote(
  p_os_id integer,
  p_data date,
  p_tipo_hora_id uuid,
  p_lancamentos jsonb,
  p_descricao text default null::text,
  p_confirmar_avisos boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
set row_security to 'off'
as $function$
declare
  v_descricao text := nullif(btrim(p_descricao), '');
begin
  perform public.assert_documento_operacional_os(p_os_id);

  if v_descricao is null or char_length(v_descricao) < 10 then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'descricao',
        'mensagem', 'Descreva o serviço realizado com pelo menos 10 caracteres.'
      ))
    );
  end if;

  return public.app_lancar_apontamentos_lote_unfiltered_ov_20260829(
    p_os_id, p_data, p_tipo_hora_id, p_lancamentos, v_descricao, p_confirmar_avisos
  );
end;
$function$;

-- 4. Descricao obrigatoria tambem na edicao, e mensagem de permissao nova ---

create or replace function public.app_editar_apontamento(
  p_apontamento_id uuid,
  p_horas numeric,
  p_tipo_hora_id uuid,
  p_descricao text default null::text,
  p_confirmar_avisos boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'a', 'c'
set row_security to 'off'
as $function$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_os_id integer;
  v_colaborador_id uuid;
  v_data date;
  v_gerado_por_hh boolean;
  v_status text;
  v_status_aprovacao text;
  v_tipo_existe boolean;
  v_descricao text := nullif(btrim(p_descricao), '');
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar autenticação, tenant e empresa ativos.';
  end if;
  if not public.can('apontamentos', 'write', v_tenant_id) then
    raise exception 'Seu perfil não possui permissão para editar apontamentos.';
  end if;
  if p_horas is null or p_horas <= 0 or p_horas > 24 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'horas', 'mensagem', 'Informe uma quantidade de horas entre 0 e 24.')));
  end if;
  if v_descricao is null or char_length(v_descricao) < 10 then
    return jsonb_build_object('sucesso', false, 'gravados', 0, 'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object('tipo', 'descricao', 'mensagem', 'Descreva o serviço realizado com pelo menos 10 caracteres.')));
  end if;

  select apontamento.os_id, apontamento.colaborador_id, apontamento.data, apontamento.gerado_por_hh,
         apontamento.status::text, apontamento.status_aprovacao
    into v_os_id, v_colaborador_id, v_data, v_gerado_por_hh, v_status, v_status_aprovacao
  from public.apontamentos_horas as apontamento
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
          when v_status_aprovacao = 'aprovado' then 'Após a aprovação, somente o responsável da OS, Coordenação, Diretor ou Admin pode alterar.'
          else 'Antes da aprovação, somente o próprio colaborador, o responsável da OS, Coordenação, Diretor ou Admin pode alterar.'
        end
      )));
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
  ) then
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

  return jsonb_build_object('sucesso', true, 'gravados', 1, 'avisos', '[]'::jsonb, 'erros', '[]'::jsonb);
end;
$function$;

-- 5. Cancelamento: sai a exigencia de papel de gestao, entra a regra unica ---
-- O corpo da funcao e grande e o restante dele continua identico; por isso a
-- troca e feita sobre a definicao ja instalada, como nas migrations anteriores.

do $patch_cancelar$
declare
  v_definition text;
  v_gate_needle text := $needle$
  if v_papel not in ('ADMIN', 'DIRETOR', 'COORDENACAO') then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'permissao',
        'mensagem', 'Somente Coordenação, Diretor ou Admin pode cancelar apontamentos.'
      ))
    );
  end if;

$needle$;
  v_gate_replacement text := $replacement$
$replacement$;
  -- A autoridade so pode ser avaliada depois que o apontamento foi carregado,
  -- e depois das checagens de HH, fechado e competencia, que tem mensagem
  -- propria e mais util que "sem permissao".
  v_check_needle text := $needle$
  select
    coalesce(nullif(btrim(ordem.numero_os), ''), ordem.os_num::text, ordem.id::text),
$needle$;
  v_check_replacement text := $replacement$
  if not public.fn_usuario_pode_alterar_apontamento(v_tenant_id, v_empresa_id, v_auth_uid, v_apontamento.id) then
    return jsonb_build_object(
      'sucesso', false,
      'gravados', 0,
      'avisos', '[]'::jsonb,
      'erros', jsonb_build_array(jsonb_build_object(
        'tipo', 'permissao',
        'mensagem', case
          when coalesce(v_apontamento.status_aprovacao, 'pendente') = 'aprovado'
            then 'Após a aprovação, somente o responsável da OS, Coordenação, Diretor ou Admin pode cancelar.'
          else 'Antes da aprovação, somente o próprio colaborador, o responsável da OS, Coordenação, Diretor ou Admin pode cancelar.'
        end
      ))
    );
  end if;

  select
    coalesce(nullif(btrim(ordem.numero_os), ''), ordem.os_num::text, ordem.id::text),
$replacement$;
begin
  select pg_get_functiondef('public.app_cancelar_apontamento(uuid,text)'::regprocedure)
    into v_definition;

  if position(v_gate_needle in v_definition) = 0 then
    raise exception 'cancelar_apontamento_gate_token_not_found';
  end if;
  if position(v_check_needle in v_definition) = 0 then
    raise exception 'cancelar_apontamento_check_token_not_found';
  end if;

  v_definition := replace(v_definition, v_gate_needle, v_gate_replacement);
  v_definition := replace(v_definition, v_check_needle, v_check_replacement);
  execute v_definition;
end;
$patch_cancelar$;

-- 6. Descancelar acompanha o cancelamento: gestao e responsavel da OS -------

do $patch_restaurar$
declare
  v_definition text;
  v_needle text := $needle$
  if v_papel not in ('ADMIN', 'DIRETOR', 'COORDENACAO') then
    return jsonb_build_object(
      'sucesso', false,
      'erro', jsonb_build_object(
        'tipo', 'sem_permissao',
        'mensagem', 'Apenas coordenação, diretoria ou administração podem descancelar horas.'
      )
    );
  end if;
$needle$;
  v_replacement text := $replacement$
  if v_papel not in ('ADMIN', 'DIRETOR', 'COORDENACAO')
     and not exists (
       select 1
       from public.apontamentos_horas_cancelamentos as cancelamento
       join public.ordens_servico as ordem
         on ordem.id = cancelamento.os_id
        and ordem.tenant_id = cancelamento.tenant_id
        and ordem.empresa_id = cancelamento.empresa_id
       where cancelamento.apontamento_id = p_apontamento_id
         and cancelamento.tenant_id = v_tenant_id
         and cancelamento.empresa_id = v_empresa_id
         and cancelamento.restaurado_em is null
         and ordem.responsavel_aprovacao_id = v_auth_uid
     ) then
    return jsonb_build_object(
      'sucesso', false,
      'erro', jsonb_build_object(
        'tipo', 'sem_permissao',
        'mensagem', 'Apenas o responsável da OS, coordenação, diretoria ou administração podem descancelar horas.'
      )
    );
  end if;
$replacement$;
begin
  select pg_get_functiondef('public.app_restaurar_apontamento(uuid)'::regprocedure)
    into v_definition;

  if position(v_needle in v_definition) = 0 then
    raise exception 'restaurar_apontamento_token_not_found';
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$patch_restaurar$;

-- 7. Conferencia --------------------------------------------------------------

do $assertions$
declare
  v_cancelar text := pg_get_functiondef('public.app_cancelar_apontamento(uuid,text)'::regprocedure);
  v_restaurar text := pg_get_functiondef('public.app_restaurar_apontamento(uuid)'::regprocedure);
begin
  if position('fn_usuario_pode_alterar_apontamento' in v_cancelar) = 0
     or position('Somente Coordenação, Diretor ou Admin pode cancelar apontamentos.' in v_cancelar) > 0 then
    raise exception 'cancelar_apontamento_patch_invalido';
  end if;

  if position('responsavel_aprovacao_id' in v_restaurar) = 0 then
    raise exception 'restaurar_apontamento_patch_invalido';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
