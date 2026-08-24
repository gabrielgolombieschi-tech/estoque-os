-- Consulta informativa para o aplicativo móvel. Não altera o cálculo automático de HH.

create or replace function public.app_verificar_feriado(p_data date)
returns table(eh_feriado boolean, descricao text)
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
begin
  if v_auth_uid is null then
    raise exception 'Autenticação obrigatória para consultar feriados.';
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();
  if v_tenant_id is null
     or v_empresa_id is null
     or not public.has_active_empresa_access(v_tenant_id, v_empresa_id) then
    raise exception 'Não foi possível identificar um tenant e uma empresa ativos para este usuário.';
  end if;

  if p_data is null then
    return query select false, null::text;
    return;
  end if;

  return query
  select true, feriado.descricao::text
  from public.feriados feriado
  where feriado.data = p_data
  order by feriado.descricao nulls last, feriado.id
  limit 1;

  if not found then
    return query select false, null::text;
  end if;
end;
$$;

revoke all on function public.app_verificar_feriado(date) from public, anon, authenticated, service_role;
grant execute on function public.app_verificar_feriado(date) to authenticated;
