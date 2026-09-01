begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- A busca direta em public.clientes avaliava as policies historicas para cada
-- linha e o frontend ocultava o timeout como "Sem resultados". A RPC valida
-- o acesso uma unica vez e pesquisa apenas dentro do tenant/empresa pedidos.
create or replace function public.search_orcamento_clientes(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_term text,
  p_limit integer default 25
)
returns table (
  id integer,
  nome text
)
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_term text := btrim(coalesce(p_term, ''));
  v_limit integer := greatest(1, least(coalesce(p_limit, 25), 50));
  v_id bigint;
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not c.has_comercial_access(p_tenant_id, p_empresa_id) then
    raise exception 'orcamento_client_search_access_denied';
  end if;

  if v_term = '' then
    return;
  end if;

  if v_term ~ '^[0-9]{1,18}$' then
    v_id := v_term::bigint;
  end if;

  return query
  select
    cli.id,
    cli.nome::text
  from public.clientes cli
  where cli.tenant_id = p_tenant_id
    and cli.empresa_id = p_empresa_id
    and (
      (v_id is not null and cli.id::bigint = v_id)
      or cli.nome ilike '%' || v_term || '%'
    )
  order by cli.nome asc, cli.id asc
  limit v_limit;
end;
$$;

revoke all on function public.search_orcamento_clientes(uuid, uuid, text, integer) from public, anon;
grant execute on function public.search_orcamento_clientes(uuid, uuid, text, integer) to authenticated, service_role;

do $$
begin
  if has_function_privilege(
       'anon',
       'public.search_orcamento_clientes(uuid,uuid,text,integer)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'public.search_orcamento_clientes(uuid,uuid,text,integer)',
       'execute'
     ) then
    raise exception 'search_orcamento_clientes_installation_invalid';
  end if;
end;
$$;

comment on function public.search_orcamento_clientes(uuid, uuid, text, integer) is
  'Busca clientes para orcamentos apos validar acesso comercial ativo ao tenant e a empresa.';

notify pgrst, 'reload schema';

commit;
