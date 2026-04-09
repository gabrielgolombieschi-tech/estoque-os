begin;

create or replace function public.faturamento_empresas_disponiveis()
returns table (
  empresa_id uuid,
  tenant_id uuid,
  nome_fantasia text,
  razao_social text,
  cnpj text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  v_tenant_id := public.current_tenant_id();
  if v_tenant_id is null then
    raise exception 'Tenant atual nao definido';
  end if;

  if to_regclass('public.empresas') is null then
    return;
  end if;

  return query
  select
    e.id as empresa_id,
    e.tenant_id,
    e.nome_fantasia,
    e.razao_social,
    e.cnpj
  from public.empresas e
  where e.tenant_id = v_tenant_id
    and coalesce(e.ativo, true) = true
  order by coalesce(nullif(trim(e.nome_fantasia), ''), nullif(trim(e.razao_social), ''), e.id::text);
end;
$$;

grant execute on function public.faturamento_empresas_disponiveis() to authenticated;
grant execute on function public.faturamento_empresas_disponiveis() to service_role;

notify pgrst, 'reload schema';

commit;
