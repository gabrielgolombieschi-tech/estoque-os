begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

create index if not exists idx_nf_entrada_empresa_recentes
  on public.nf_entrada (tenant_id, empresa_id, criado_em desc, id desc)
  where deleted_at is null;

create index if not exists idx_nf_entrada_empresa_emissao
  on public.nf_entrada (tenant_id, empresa_id, data_emissao, criado_em desc)
  where deleted_at is null;

create or replace function public.list_imported_nfe(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_start_date date default null,
  p_end_date date default null,
  p_emitente text default null,
  p_numero text default null,
  p_limit integer default 20
)
returns table (
  id bigint,
  chave text,
  numero text,
  serie text,
  emitente_nome text,
  data_emissao timestamp with time zone,
  valor_total numeric,
  criado_em timestamp with time zone,
  finalidade_contexto public.item_finalidade
)
language plpgsql
stable
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_emitente text := nullif(btrim(coalesce(p_emitente, '')), '');
  v_numero text := nullif(btrim(coalesce(p_numero, '')), '');
  v_limit integer := greatest(1, least(coalesce(p_limit, 20), 100));
begin
  if auth.uid() is null
     or p_tenant_id is null
     or p_empresa_id is null
     or public.current_tenant_id() is distinct from p_tenant_id
     or public.current_empresa_id__by_tenant(p_tenant_id) is distinct from p_empresa_id
     or not public.has_active_empresa_access(p_tenant_id, p_empresa_id)
     or not (
       public.can('xml_import', 'execute', p_tenant_id)
       or public.can('xml_import_faturamento', 'execute', p_tenant_id)
       or public.can('estoque', 'read', p_tenant_id)
       or public.can('estoque', 'write', p_tenant_id)
       or public.can('financeiro', 'read', p_tenant_id)
       or public.can('financeiro', 'write', p_tenant_id)
       or public.can('cad_itens', 'write', p_tenant_id)
       or public.can('cad_fornecedores', 'write', p_tenant_id)
     ) then
    raise exception 'imported_nfe_list_access_denied';
  end if;

  if p_start_date is not null
     and p_end_date is not null
     and p_end_date <= p_start_date then
    raise exception 'imported_nfe_list_invalid_period';
  end if;

  return query
  select
    nf.id,
    nf.chave::text,
    nf.numero::text,
    nf.serie::text,
    nf.emitente_nome::text,
    nf.data_emissao,
    nf.valor_total,
    nf.criado_em,
    nf.finalidade_contexto
  from public.nf_entrada nf
  where nf.tenant_id = p_tenant_id
    and nf.empresa_id = p_empresa_id
    and nf.deleted_at is null
    and nf.chave is not null
    and (p_start_date is null or nf.data_emissao >= p_start_date)
    and (p_end_date is null or nf.data_emissao < p_end_date)
    and (v_emitente is null or nf.emitente_nome ilike '%' || v_emitente || '%')
    and (v_numero is null or nf.numero ilike '%' || v_numero || '%')
  order by nf.criado_em desc, nf.id desc
  limit v_limit;
end;
$$;

revoke all on function public.list_imported_nfe(
  uuid, uuid, date, date, text, text, integer
) from public, anon;
grant execute on function public.list_imported_nfe(
  uuid, uuid, date, date, text, text, integer
) to authenticated, service_role;

do $$
begin
  if has_function_privilege(
       'anon',
       'public.list_imported_nfe(uuid,uuid,date,date,text,text,integer)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'public.list_imported_nfe(uuid,uuid,date,date,text,text,integer)',
       'execute'
     ) then
    raise exception 'list_imported_nfe_installation_invalid';
  end if;
end;
$$;

comment on function public.list_imported_nfe(
  uuid, uuid, date, date, text, text, integer
) is 'Lista NF-e importadas da empresa ativa apos validar tenant, empresa e permissao do usuario.';

notify pgrst, 'reload schema';

commit;
