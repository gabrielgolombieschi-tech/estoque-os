-- RPCs de leitura para o app móvel.
-- A projeção é intencionalmente sem valores financeiros.

create or replace function public.app_listar_os(
  p_incluir_fechadas boolean default false,
  p_busca text default null
)
returns table (
  id integer,
  numero_os character varying,
  os_num bigint,
  cliente_nome character varying,
  descricao_servico text,
  status character varying,
  usa_relatorio_hh boolean,
  data_abertura timestamp without time zone,
  sou_responsavel boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, c
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_colaborador_id uuid;
  v_busca text := nullif(btrim(p_busca), '');
begin
  if v_auth_uid is null then
    raise exception 'Autenticação obrigatória para consultar ordens de serviço.';
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();

  if v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar um tenant e uma empresa ativos para este usuário.';
  end if;

  select colaborador.id
    into v_colaborador_id
  from public.colaboradores as colaborador
  where colaborador.user_id = v_auth_uid
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true;

  if v_colaborador_id is null then
    raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
  end if;

  return query
  select
    os.id,
    os.numero_os,
    os.os_num,
    os.cliente_nome,
    os.descricao_servico,
    os.status,
    os.usa_relatorio_hh,
    os.data_abertura,
    (os.responsavel_aprovacao_id is not distinct from v_auth_uid) as sou_responsavel
  from public.ordens_servico as os
  where os.tenant_id = v_tenant_id
    and os.empresa_id = v_empresa_id
    and os.status in (
      'em_andamento',
      case when p_incluir_fechadas then 'concluida' else 'em_andamento' end
    )
    and (
      v_busca is null
      or os.numero_os ilike '%' || v_busca || '%'
      or os.os_num::text ilike '%' || v_busca || '%'
      or os.cliente_nome ilike '%' || v_busca || '%'
    )
  order by os.data_abertura desc nulls last, os.id desc;
end;
$$;

create or replace function public.app_listar_colaboradores()
returns table (
  id uuid,
  nome character varying,
  sou_eu boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, c
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_colaborador_id uuid;
begin
  if v_auth_uid is null then
    raise exception 'Autenticação obrigatória para consultar colaboradores.';
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();

  if v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar um tenant e uma empresa ativos para este usuário.';
  end if;

  select colaborador.id
    into v_colaborador_id
  from public.colaboradores as colaborador
  where colaborador.user_id = v_auth_uid
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true;

  if v_colaborador_id is null then
    raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
  end if;

  return query
  select
    colaborador.id,
    colaborador.nome,
    (colaborador.user_id is not distinct from v_auth_uid) as sou_eu
  from public.colaboradores as colaborador
  where colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true
  order by colaborador.nome;
end;
$$;

create or replace function public.app_meus_apontamentos(
  p_data_inicio date default null,
  p_data_fim date default null,
  p_os_id integer default null
)
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
  gerado_por_hh boolean,
  motivo_devolucao text,
  criado_em timestamp with time zone
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, a, c
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_colaborador_id uuid;
  v_data_inicio date := coalesce(p_data_inicio, current_date - 29);
  v_data_fim date := coalesce(p_data_fim, current_date);
begin
  if v_auth_uid is null then
    raise exception 'Autenticação obrigatória para consultar apontamentos.';
  end if;

  if v_data_inicio > v_data_fim then
    raise exception 'A data inicial não pode ser posterior à data final.';
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();

  if v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar um tenant e uma empresa ativos para este usuário.';
  end if;

  select colaborador.id
    into v_colaborador_id
  from public.colaboradores as colaborador
  where colaborador.user_id = v_auth_uid
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true;

  if v_colaborador_id is null then
    raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
  end if;

  return query
  select
    apontamento.id,
    apontamento.os_id,
    os.numero_os,
    os.cliente_nome,
    apontamento.colaborador_id,
    colaborador.nome,
    apontamento.data,
    apontamento.horas,
    apontamento.tipo_hora_id,
    tipo_hora.descricao,
    apontamento.descricao,
    apontamento.status,
    apontamento.gerado_por_hh,
    apontamento.motivo_devolucao,
    apontamento.criado_em
  from public.apontamentos_horas as apontamento
  join public.colaboradores as colaborador
    on colaborador.id = apontamento.colaborador_id
   and colaborador.tenant_id = v_tenant_id
   and colaborador.empresa_id = v_empresa_id
  left join public.ordens_servico as os
    on os.id = apontamento.os_id
   and os.tenant_id = v_tenant_id
   and os.empresa_id = v_empresa_id
  left join public.tipos_horas as tipo_hora
    on tipo_hora.id = apontamento.tipo_hora_id
   and tipo_hora.tenant_id = v_tenant_id
  where apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id
    and apontamento.colaborador_id = v_colaborador_id
    and apontamento.data between v_data_inicio and v_data_fim
    and (p_os_id is null or apontamento.os_id = p_os_id)
  order by apontamento.data desc, apontamento.criado_em desc, apontamento.id desc;
end;
$$;

revoke all on function public.app_listar_os(boolean, text) from public, anon, authenticated, service_role;
revoke all on function public.app_listar_colaboradores() from public, anon, authenticated, service_role;
revoke all on function public.app_meus_apontamentos(date, date, integer) from public, anon, authenticated, service_role;

grant execute on function public.app_listar_os(boolean, text) to authenticated;
grant execute on function public.app_listar_colaboradores() to authenticated;
grant execute on function public.app_meus_apontamentos(date, date, integer) to authenticated;
