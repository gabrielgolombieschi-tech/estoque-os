create or replace function public.list_fornecedores_materia_prima(
  p_tenant_id uuid,
  p_empresa_id uuid
)
returns table (
  id integer,
  nome text,
  ativo boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id__by_tenant(p_tenant_id) is distinct from p_empresa_id
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not (
       public.can('estoque', 'read')
       or public.can('cad_itens', 'write')
     ) then
    raise exception 'fornecedores_materia_prima_access_denied';
  end if;

  return query
  select
    f.id,
    f.nome::text,
    f.ativo
  from public.fornecedores f
  where f.tenant_id = p_tenant_id
    and f.empresa_id = p_empresa_id
    and f.ativo = true
    and exists (
      select 1
      from public.itens i
      where i.tenant_id = p_tenant_id
        and i.empresa_id = p_empresa_id
        and i.fornecedor_id = f.id
        and i.finalidade = 'materia_prima'
    )
  order by f.nome asc, f.id asc;
end;
$$;

revoke all on function public.list_fornecedores_materia_prima(uuid, uuid) from public, anon;
grant execute on function public.list_fornecedores_materia_prima(uuid, uuid) to authenticated;
grant execute on function public.list_fornecedores_materia_prima(uuid, uuid) to service_role;

notify pgrst, 'reload schema';
