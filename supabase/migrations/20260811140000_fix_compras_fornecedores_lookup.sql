begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- A listagem direta passava pelas policies historicas de fornecedores para
-- cada linha e podia exceder o timeout. Esta RPC valida uma unica vez o
-- usuario, tenant e empresa e depois executa a consulta no escopo autorizado.
create or replace function public.list_compras_fornecedores(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_search text default null
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
declare
  v_search text := nullif(btrim(coalesce(p_search, '')), '');
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not c.has_compras_access(p_tenant_id, p_empresa_id) then
    raise exception 'compras_fornecedores_access_denied';
  end if;

  return query
  select
    f.id,
    f.nome::text,
    f.ativo
  from public.fornecedores f
  where f.tenant_id = p_tenant_id
    and f.empresa_id = p_empresa_id
    and (v_search is null or f.nome ilike '%' || v_search || '%')
  order by f.nome asc, f.id asc;
end;
$$;

revoke all on function public.list_compras_fornecedores(uuid, uuid, text) from public, anon;
grant execute on function public.list_compras_fornecedores(uuid, uuid, text) to authenticated, service_role;

do $$
begin
  if has_function_privilege(
       'anon',
       'public.list_compras_fornecedores(uuid,uuid,text)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'public.list_compras_fornecedores(uuid,uuid,text)',
       'execute'
     ) then
    raise exception 'list_compras_fornecedores_installation_invalid';
  end if;
end;
$$;

comment on function public.list_compras_fornecedores(uuid, uuid, text) is
  'Lista fornecedores de compras apos validar acesso ativo ao tenant e a empresa informados.';

notify pgrst, 'reload schema';

commit;
