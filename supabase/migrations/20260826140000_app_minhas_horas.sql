-- Consulta individual de horas para o app móvel.
-- Não altera apontamentos nem expõe dados de outros colaboradores.

create index if not exists idx_apontamentos_horas_tenant_empresa_colaborador_data
  on public.apontamentos_horas (tenant_id, empresa_id, colaborador_id, data);

create or replace function public.app_minhas_horas_ano(p_ano integer)
returns table (
  mes date,
  total_horas numeric
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_colaborador_id uuid;
  v_ano integer := coalesce(p_ano, extract(year from current_date)::integer);
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  if v_ano not between 2000 and 2100 then
    raise exception 'Ano inválido.';
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
  with meses as (
    select generate_series(
      make_date(v_ano, 1, 1),
      make_date(v_ano, 12, 1),
      interval '1 month'
    )::date as mes
  ),
  totais as (
    select
      date_trunc('month', apontamento.data)::date as mes,
      coalesce(sum(apontamento.horas), 0)::numeric as total_horas
    from public.apontamentos_horas as apontamento
    where apontamento.tenant_id = v_tenant_id
      and apontamento.empresa_id = v_empresa_id
      and apontamento.colaborador_id = v_colaborador_id
      and apontamento.data >= make_date(v_ano, 1, 1)
      and apontamento.data < make_date(v_ano + 1, 1, 1)
    group by date_trunc('month', apontamento.data)::date
  )
  select meses.mes, coalesce(totais.total_horas, 0)::numeric
  from meses
  left join totais on totais.mes = meses.mes
  order by meses.mes;
end;
$$;

create or replace function public.app_minhas_horas_mes(
  p_ano integer,
  p_mes integer
)
returns table (
  data date,
  os_id integer,
  codigo_os text,
  horas numeric,
  tem_rejeitado boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
set row_security = off
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid := public.current_empresa_id();
  v_colaborador_id uuid;
  v_inicio_mes date;
begin
  if v_auth_uid is null
     or v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Autenticação e contexto de empresa são obrigatórios.';
  end if;

  if p_ano is null
     or p_mes is null
     or p_ano not between 2000 and 2100
     or p_mes not between 1 and 12 then
    raise exception 'Período inválido.';
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

  v_inicio_mes := make_date(p_ano, p_mes, 1);

  return query
  select
    apontamento.data,
    os.id,
    coalesce(nullif(os.numero_os, ''), os.os_num::text, os.id::text)::text as codigo_os,
    coalesce(sum(apontamento.horas), 0)::numeric as horas,
    bool_or(apontamento.status_aprovacao = 'rejeitado') as tem_rejeitado
  from public.apontamentos_horas as apontamento
  join public.ordens_servico as os
    on os.id = apontamento.os_id
   and os.tenant_id = apontamento.tenant_id
   and os.empresa_id = apontamento.empresa_id
  where apontamento.tenant_id = v_tenant_id
    and apontamento.empresa_id = v_empresa_id
    and apontamento.colaborador_id = v_colaborador_id
    and apontamento.data >= v_inicio_mes
    and apontamento.data < (v_inicio_mes + interval '1 month')::date
  group by apontamento.data, os.id, os.numero_os, os.os_num
  order by apontamento.data, codigo_os;
end;
$$;

revoke all on function public.app_minhas_horas_ano(integer) from public, anon, authenticated, service_role;
revoke all on function public.app_minhas_horas_mes(integer, integer) from public, anon, authenticated, service_role;

grant execute on function public.app_minhas_horas_ano(integer) to authenticated;
grant execute on function public.app_minhas_horas_mes(integer, integer) to authenticated;
