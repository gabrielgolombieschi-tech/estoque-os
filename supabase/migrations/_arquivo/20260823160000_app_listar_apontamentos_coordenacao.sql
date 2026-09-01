-- A listagem de apontamentos do app móvel começa pelo perfil COORDENACAO.
-- APONTADOR permanece restrito aos apontamentos do próprio colaborador.

create or replace function public.app_listar_apontamentos(
  p_data_inicio date default null,
  p_data_fim date default null,
  p_os_id integer default null,
  p_colaborador_id uuid default null
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
  v_colaborador_proprio_id uuid;
  v_papel_empresa text;
  v_colaborador_filtro_id uuid;
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
    into v_colaborador_proprio_id
  from public.colaboradores as colaborador
  where colaborador.user_id = v_auth_uid
    and colaborador.tenant_id = v_tenant_id
    and colaborador.empresa_id = v_empresa_id
    and colaborador.ativo is true;

  if v_colaborador_proprio_id is null then
    raise exception 'Seu usuário não está vinculado a um colaborador ativo nesta empresa.';
  end if;

  select usuario_empresa.papel
    into v_papel_empresa
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

  if v_papel_empresa is null then
    raise exception 'Não foi possível identificar o papel deste usuário na empresa atual.';
  end if;

  if upper(v_papel_empresa) = 'APONTADOR' then
    v_colaborador_filtro_id := v_colaborador_proprio_id;
  else
    v_colaborador_filtro_id := p_colaborador_id;
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
    and apontamento.data between v_data_inicio and v_data_fim
    and (p_os_id is null or apontamento.os_id = p_os_id)
    and (v_colaborador_filtro_id is null or apontamento.colaborador_id = v_colaborador_filtro_id)
  order by apontamento.data desc, apontamento.criado_em desc, apontamento.id desc;
end;
$$;

revoke all on function public.app_listar_apontamentos(date, date, integer, uuid) from public, anon, authenticated, service_role;
grant execute on function public.app_listar_apontamentos(date, date, integer, uuid) to authenticated;

drop function public.app_meus_apontamentos(date, date, integer);
