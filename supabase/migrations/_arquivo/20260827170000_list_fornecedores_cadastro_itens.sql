-- A consulta direta de fornecedores avalia politicas historicas por linha e
-- pode expirar para perfis operacionais. Esta RPC valida o acesso uma vez e
-- retorna somente fornecedores ativos da empresa atual para o cadastro de item.

create or replace function public.list_fornecedores_cadastro_itens(
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
     or not public.can('cad_itens', 'write') then
    raise exception 'fornecedores_cadastro_itens_access_denied';
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
  order by f.nome asc, f.id asc;
end;
$$;

revoke all on function public.list_fornecedores_cadastro_itens(uuid, uuid) from public, anon;
grant execute on function public.list_fornecedores_cadastro_itens(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
