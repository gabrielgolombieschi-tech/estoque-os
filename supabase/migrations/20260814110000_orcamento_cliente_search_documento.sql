begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

drop function if exists public.search_orcamento_clientes(uuid, uuid, text, integer);

create function public.search_orcamento_clientes(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_term text,
  p_limit integer default 25
)
returns table (
  id integer,
  nome text,
  documento text
)
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_term text := btrim(coalesce(p_term, ''));
  v_term_digits text := regexp_replace(btrim(coalesce(p_term, '')), '[^0-9]', '', 'g');
  v_limit integer := greatest(1, least(coalesce(p_limit, 25), 50));
  v_id bigint;
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id__by_tenant(p_tenant_id) is distinct from p_empresa_id
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
    cli.nome::text,
    cli.documento::text
  from public.clientes cli
  where cli.tenant_id = p_tenant_id
    and cli.empresa_id = p_empresa_id
    and (
      (v_id is not null and cli.id::bigint = v_id)
      or cli.nome ilike '%' || v_term || '%'
      or cli.documento ilike '%' || v_term || '%'
      or (
        length(v_term_digits) >= 3
        and regexp_replace(coalesce(cli.documento, ''), '[^0-9]', '', 'g') like '%' || v_term_digits || '%'
      )
    )
  order by cli.nome asc, cli.id asc
  limit v_limit;
end;
$$;

revoke all on function public.search_orcamento_clientes(uuid, uuid, text, integer) from public, anon;
grant execute on function public.search_orcamento_clientes(uuid, uuid, text, integer) to authenticated, service_role;

comment on function public.search_orcamento_clientes(uuid, uuid, text, integer) is
  'Busca clientes por nome, ID ou CPF/CNPJ para orcamentos, limitada ao tenant e empresa ativos.';

notify pgrst, 'reload schema';

commit;
