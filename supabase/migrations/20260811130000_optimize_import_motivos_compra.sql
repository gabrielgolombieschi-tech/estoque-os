begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- O ranking anterior passava por RLS em f.titulo para cada linha. Este indice
-- atende a contagem por empresa/motivo sem varrer os titulos do tenant.
create index if not exists idx_titulo__empresa_motivo_created
  on f.titulo (tenant_id, empresa_id, motivo_compra_id, created_at)
  where deleted_at is null and motivo_compra_id is not null;

create or replace function public.list_motivos_compra_import(
  p_origem text default null
)
returns table (
  id uuid,
  codigo text,
  nome text,
  requires_text boolean,
  requires_os boolean,
  aplica_em text,
  favorito boolean,
  ordem integer,
  qtd_usos_180d bigint,
  ativo boolean,
  deleted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_tenant_id uuid := public.current_tenant_id();
  v_empresa_id uuid;
  v_origem text := upper(trim(coalesce(p_origem, '')));
begin
  if auth.uid() is null or v_tenant_id is null then
    raise exception 'not_authenticated_or_tenant_missing';
  end if;

  v_empresa_id := public.current_empresa_id__by_tenant(v_tenant_id);

  if not public.has_active_empresa_access(v_tenant_id, v_empresa_id)
     or not f.has_motivo_compra_access(v_tenant_id) then
    raise exception 'motivo_compra_access_denied';
  end if;

  if v_origem not in ('', 'XML_PRODUTO') then
    raise exception 'invalid_motivo_compra_origem';
  end if;

  return query
  select
    mc.id,
    mc.codigo,
    mc.nome,
    mc.requires_text,
    mc.requires_os,
    mc.aplica_em,
    mc.favorito,
    mc.ordem,
    coalesce((
      select count(*)
      from f.titulo t
      where t.tenant_id = v_tenant_id
        and t.empresa_id = v_empresa_id
        and t.motivo_compra_id = mc.id
        and t.deleted_at is null
        and t.created_at >= now() - interval '180 days'
    ), 0)::bigint as qtd_usos_180d,
    mc.ativo,
    mc.deleted_at
  from f.motivo_compra mc
  where mc.tenant_id = v_tenant_id
    and mc.deleted_at is null
    and mc.ativo is true
    and mc.visivel_import_nfe is true
    and (v_origem <> 'XML_PRODUTO' or mc.aplica_em in ('PRODUTO','AMBOS'))
  order by mc.favorito desc,
           qtd_usos_180d desc,
           mc.ordem desc,
           mc.nome asc;
end;
$$;

revoke all on function public.list_motivos_compra_import(text) from public, anon;
grant execute on function public.list_motivos_compra_import(text) to authenticated, service_role;

do $$
begin
  if has_function_privilege('anon', 'public.list_motivos_compra_import(text)', 'execute')
     or not has_function_privilege('authenticated', 'public.list_motivos_compra_import(text)', 'execute')
     or not exists (
       select 1
       from pg_indexes
       where schemaname = 'f'
         and tablename = 'titulo'
         and indexname = 'idx_titulo__empresa_motivo_created'
     ) then
    raise exception 'list_motivos_compra_import_installation_invalid';
  end if;
end;
$$;

comment on function public.list_motivos_compra_import(text) is
  'Lista motivos visiveis da empresa atual e calcula uso em 180 dias com autorizacao validada uma unica vez.';

notify pgrst, 'reload schema';

commit;
