begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

-- O cancelamento de 20260902224000 apaga a linha e arquiva um snapshot. Isso ja
-- garante que hora cancelada nao gera hora nem custo: ela sai de
-- apontamentos_horas, entao as 32 funcoes que somam a tabela continuam corretas
-- sem precisar de filtro novo. O que faltava era visibilidade e volta atras.
--
-- Aqui o arquivo passa a aparecer na listagem marcado como cancelado, e ganha
-- uma restauracao. O historico continua imutavel: restaurar nao apaga a linha do
-- arquivo, marca restaurado_em. A unicidade de apontamento_id vira parcial para
-- que o mesmo lancamento possa ser cancelado de novo depois de restaurado.

alter table public.apontamentos_horas_cancelamentos
  add column if not exists restaurado_em timestamptz,
  add column if not exists restaurado_por_user_id uuid,
  add column if not exists restaurado_por_nome text;

alter table public.apontamentos_horas_cancelamentos
  drop constraint if exists apontamentos_horas_cancelamentos_apontamento_id_key;

create unique index if not exists uq_apontamentos_horas_cancelamentos_ativo
  on public.apontamentos_horas_cancelamentos (apontamento_id)
  where restaurado_em is null;

comment on column public.apontamentos_horas_cancelamentos.restaurado_em is
  'Quando preenchido, este cancelamento foi desfeito e o apontamento voltou para apontamentos_horas.';

-- Restauracao. Mesmo gate de papel do cancelamento.
create or replace function public.app_restaurar_apontamento(p_apontamento_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, a, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_papel text;
  v_restaurado_por_nome text;
  v_arquivo public.apontamentos_horas_cancelamentos%rowtype;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  select upper(usuario_empresa.papel::text), coalesce(nullif(btrim(usuario.nome), ''), 'Usuário')
    into v_papel, v_restaurado_por_nome
  from a.usuario as usuario
  join a.usuario_empresa as usuario_empresa on usuario_empresa.usuario_id = usuario.id
  where usuario.auth_user_id = v_auth_uid
    and usuario.ativo and usuario.deleted_at is null
    and usuario_empresa.empresa_id = v_empresa_id
    and usuario_empresa.ativo and usuario_empresa.deleted_at is null
  limit 1;

  if v_papel is null then
    raise exception 'Não foi possível identificar o papel deste usuário na empresa atual.';
  end if;
  if v_papel not in ('ADMIN', 'DIRETOR', 'COORDENACAO') then
    return jsonb_build_object(
      'sucesso', false,
      'erro', jsonb_build_object(
        'tipo', 'sem_permissao',
        'mensagem', 'Apenas coordenação, diretoria ou administração podem descancelar horas.'
      )
    );
  end if;

  select * into v_arquivo
  from public.apontamentos_horas_cancelamentos as cancelamento
  where cancelamento.apontamento_id = p_apontamento_id
    and cancelamento.tenant_id = v_tenant_id
    and cancelamento.empresa_id = v_empresa_id
    and cancelamento.restaurado_em is null
  for update;

  if not found then
    return jsonb_build_object(
      'sucesso', false,
      'erro', jsonb_build_object(
        'tipo', 'nao_encontrado',
        'mensagem', 'Este apontamento não está cancelado.'
      )
    );
  end if;

  if exists (
    select 1 from public.apontamentos_horas as apontamento
    where apontamento.id = p_apontamento_id
  ) then
    return jsonb_build_object(
      'sucesso', false,
      'erro', jsonb_build_object(
        'tipo', 'ja_existe',
        'mensagem', 'O lançamento já está ativo. Atualize a tela.'
      )
    );
  end if;

  -- dados_apontamento e o to_jsonb da linha original; jsonb_populate_record
  -- ignora a chave extra eventos_aprovacao e devolve o lancamento inteiro.
  insert into public.apontamentos_horas
  select (jsonb_populate_record(null::public.apontamentos_horas, v_arquivo.dados_apontamento)).*;

  update public.apontamentos_horas_cancelamentos
     set restaurado_em = now(),
         restaurado_por_user_id = v_auth_uid,
         restaurado_por_nome = v_restaurado_por_nome
   where id = v_arquivo.id;

  return jsonb_build_object(
    'sucesso', true,
    'apontamento_id', p_apontamento_id,
    'horas', v_arquivo.horas
  );
end;
$$;

revoke all on function public.app_restaurar_apontamento(uuid) from public, anon;
grant execute on function public.app_restaurar_apontamento(uuid) to authenticated, service_role;

comment on function public.app_restaurar_apontamento(uuid) is
  'Desfaz um cancelamento de apontamento, recriando o lançamento a partir do snapshot e marcando o arquivo como restaurado.';

-- Listagem: ativos + cancelados ainda nao restaurados, com quem aprovou/cancelou.
drop function if exists public.app_listar_apontamentos_os_fluxo(integer);
drop function if exists public.app_listar_apontamentos_os_fluxo_unfiltered_ov_20260829(integer);

create function public.app_listar_apontamentos_os_fluxo_unfiltered_ov_20260829(p_os_id integer)
returns table (
  id uuid,
  os_id integer,
  numero_os character varying,
  cliente_nome character varying,
  colaborador_id uuid,
  nome_colaborador character varying,
  data date,
  horas numeric,
  tipo_hora_id uuid,
  nome_tipo_hora character varying,
  descricao text,
  status character varying,
  status_aprovacao text,
  pendente_em timestamptz,
  aprovado_em timestamptz,
  rejeitado_em timestamptz,
  gerado_por_hh boolean,
  motivo_devolucao text,
  criado_em timestamptz,
  aprovado_por_nome text,
  cancelado boolean,
  cancelado_por_nome text,
  cancelamento_motivo text,
  cancelado_em timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, c, auth
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_colaborador_id uuid;
  v_papel text;
begin
  if v_auth_uid is null or v_tenant_id is null or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  select ue.papel into v_papel
  from a.usuario u
  join a.usuario_empresa ue on ue.usuario_id = u.id
  where u.auth_user_id = v_auth_uid and u.ativo and u.deleted_at is null
    and ue.empresa_id = v_empresa_id and ue.ativo and ue.deleted_at is null
  limit 1;
  if v_papel is null then
    raise exception 'Não foi possível identificar o papel deste usuário na empresa.';
  end if;

  if upper(v_papel) = 'APONTAMENTO_RH' then
    select c.id into v_colaborador_id
    from public.colaboradores c
    where c.user_id = v_auth_uid and c.tenant_id = v_tenant_id and c.empresa_id = v_empresa_id and c.ativo;
    if v_colaborador_id is null then
      raise exception 'Seu usuário de apontamento não está vinculado a um colaborador ativo nesta empresa.';
    end if;
  end if;

  return query
  select ah.id, ah.os_id, os.numero_os, os.cliente_nome, ah.colaborador_id, c.nome,
         ah.data, ah.horas, ah.tipo_hora_id, th.descricao, ah.descricao, ah.status,
         ah.status_aprovacao, ah.pendente_em, ah.aprovado_em, ah.rejeitado_em,
         ah.gerado_por_hh, ah.motivo_devolucao, ah.criado_em,
         case
           when ah.aprovado_automaticamente_em is not null and ah.aprovado_por is null
             then 'Aprovação automática'
           else coalesce(
             nullif(btrim(perfil.nome), ''),
             nullif(btrim(aprovador.nome), ''),
             nullif(btrim(colaborador_aprovador.nome), '')
           )
         end::text as aprovado_por_nome,
         false as cancelado,
         null::text as cancelado_por_nome,
         null::text as cancelamento_motivo,
         null::timestamptz as cancelado_em
  from public.apontamentos_horas ah
  join public.ordens_servico os on os.id = ah.os_id and os.tenant_id = ah.tenant_id and os.empresa_id = ah.empresa_id
  join public.colaboradores c on c.id = ah.colaborador_id and c.tenant_id = v_tenant_id and c.empresa_id = v_empresa_id
  left join public.tipos_horas th on th.id = ah.tipo_hora_id and th.tenant_id = v_tenant_id
  left join public.profiles perfil on perfil.id = ah.aprovado_por
  left join a.usuario aprovador
    on aprovador.auth_user_id = ah.aprovado_por
   and aprovador.ativo is true and aprovador.deleted_at is null
  left join public.colaboradores colaborador_aprovador
    on colaborador_aprovador.user_id = ah.aprovado_por
   and colaborador_aprovador.tenant_id = v_tenant_id
   and colaborador_aprovador.empresa_id = v_empresa_id
  where ah.os_id = p_os_id
    and ah.tenant_id = v_tenant_id and ah.empresa_id = v_empresa_id
    and (upper(v_papel) <> 'APONTAMENTO_RH' or ah.colaborador_id = v_colaborador_id)

  union all

  select cancelado.apontamento_id, cancelado.os_id,
         cancelado.numero_os::character varying, cancelado.cliente_nome::character varying,
         cancelado.colaborador_id, cancelado.colaborador_nome::character varying,
         cancelado.data, cancelado.horas, cancelado.tipo_hora_id,
         cancelado.tipo_hora_nome::character varying, cancelado.descricao,
         cancelado.status_anterior, cancelado.status_aprovacao_anterior,
         cancelado.pendente_em, cancelado.aprovado_em, cancelado.rejeitado_em,
         cancelado.gerado_por_hh, cancelado.motivo_devolucao, cancelado.criado_em,
         null::text as aprovado_por_nome,
         true as cancelado,
         cancelado.cancelado_por_nome,
         cancelado.cancelamento_motivo,
         cancelado.cancelado_em
  from public.apontamentos_horas_cancelamentos cancelado
  where cancelado.os_id = p_os_id
    and cancelado.tenant_id = v_tenant_id and cancelado.empresa_id = v_empresa_id
    and cancelado.restaurado_em is null
    and (upper(v_papel) <> 'APONTAMENTO_RH' or cancelado.colaborador_id = v_colaborador_id)

  order by data desc, criado_em desc, id desc;
end;
$$;

create function public.app_listar_apontamentos_os_fluxo(p_os_id integer)
returns table (
  id uuid,
  os_id integer,
  numero_os character varying,
  cliente_nome character varying,
  colaborador_id uuid,
  nome_colaborador character varying,
  data date,
  horas numeric,
  tipo_hora_id uuid,
  nome_tipo_hora character varying,
  descricao text,
  status character varying,
  status_aprovacao text,
  pendente_em timestamptz,
  aprovado_em timestamptz,
  rejeitado_em timestamptz,
  gerado_por_hh boolean,
  motivo_devolucao text,
  criado_em timestamptz,
  aprovado_por_nome text,
  cancelado boolean,
  cancelado_por_nome text,
  cancelamento_motivo text,
  cancelado_em timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
set row_security = off
as $$
begin
  perform public.assert_documento_operacional_os(p_os_id);
  return query
  select * from public.app_listar_apontamentos_os_fluxo_unfiltered_ov_20260829(p_os_id);
end;
$$;

revoke all on function public.app_listar_apontamentos_os_fluxo(integer) from public, anon;
revoke all on function public.app_listar_apontamentos_os_fluxo_unfiltered_ov_20260829(integer) from public, anon;
grant execute on function public.app_listar_apontamentos_os_fluxo(integer) to authenticated, service_role;
grant execute on function public.app_listar_apontamentos_os_fluxo_unfiltered_ov_20260829(integer) to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
