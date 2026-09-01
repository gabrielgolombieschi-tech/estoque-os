begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

drop function if exists public.list_compras_fornecedores(uuid, uuid, text);

create function public.list_compras_fornecedores(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_search text default null
)
returns table (
  id integer,
  nome text,
  documento text,
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
  v_search_digits text := regexp_replace(btrim(coalesce(p_search, '')), '[^0-9]', '', 'g');
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id__by_tenant(p_tenant_id) is distinct from p_empresa_id
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not c.has_compras_access(p_tenant_id, p_empresa_id) then
    raise exception 'compras_fornecedores_access_denied';
  end if;

  return query
  select
    f.id,
    f.nome::text,
    f.documento::text,
    f.ativo
  from public.fornecedores f
  where f.tenant_id = p_tenant_id
    and f.empresa_id = p_empresa_id
    and (
      v_search is null
      or f.nome ilike '%' || v_search || '%'
      or f.documento ilike '%' || v_search || '%'
      or (
        length(v_search_digits) >= 3
        and regexp_replace(coalesce(f.documento, ''), '[^0-9]', '', 'g') like '%' || v_search_digits || '%'
      )
    )
  order by f.nome asc, f.id asc;
end;
$$;

revoke all on function public.list_compras_fornecedores(uuid, uuid, text) from public, anon;
grant execute on function public.list_compras_fornecedores(uuid, uuid, text) to authenticated, service_role;

create or replace function public.list_compras_fornecedores_pendentes(
  p_tenant_id uuid,
  p_empresa_id uuid
)
returns table (
  fornecedor_id integer,
  fornecedor_nome text,
  fornecedor_documento text,
  qtd_pendencias_abertas bigint,
  qtd_total_pendente numeric
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
     or not c.has_compras_access(p_tenant_id, p_empresa_id) then
    raise exception 'compras_fornecedores_pendentes_access_denied';
  end if;

  return query
  select
    cp.fornecedor_id,
    coalesce(f.nome, 'SEM FORNECEDOR')::text as fornecedor_nome,
    f.documento::text as fornecedor_documento,
    count(*)::bigint as qtd_pendencias_abertas,
    coalesce(sum(cp.quantidade), 0)::numeric as qtd_total_pendente
  from m.compra_pendencia cp
  left join public.fornecedores f
    on f.tenant_id = cp.tenant_id
   and f.empresa_id = cp.empresa_id
   and f.id = cp.fornecedor_id
  where cp.tenant_id = p_tenant_id
    and cp.empresa_id = p_empresa_id
    and cp.deleted_at is null
    and cp.status = 'PENDENTE'
  group by cp.fornecedor_id, f.nome, f.documento
  order by coalesce(f.nome, 'SEM FORNECEDOR') asc, cp.fornecedor_id asc;
end;
$$;

revoke all on function public.list_compras_fornecedores_pendentes(uuid, uuid) from public, anon;
grant execute on function public.list_compras_fornecedores_pendentes(uuid, uuid) to authenticated, service_role;

comment on function public.list_compras_fornecedores(uuid, uuid, text) is
  'Lista fornecedores por nome ou CPF/CNPJ para criacao de pedidos de compra.';
comment on function public.list_compras_fornecedores_pendentes(uuid, uuid) is
  'Lista fornecedores com pendencias de compra, incluindo CPF/CNPJ, no tenant e empresa ativos.';

notify pgrst, 'reload schema';

commit;
