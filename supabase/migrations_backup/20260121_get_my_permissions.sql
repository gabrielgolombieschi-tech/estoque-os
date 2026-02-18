begin;

create or replace function public.get_my_permissions(p_tenant_id uuid)
returns table(permission text)
language sql
stable
security definer
set search_path = public, a
as $$
  with me as (
    select u.id as usuario_id
    from a.usuario u
    where u.auth_user_id = auth.uid()
      and u.deleted_at is null
    limit 1
  ),
  tenant_role as (
    select ut.papel
    from a.usuario_tenant ut
    join me on me.usuario_id = ut.usuario_id
    where ut.tenant_id = p_tenant_id
      and ut.ativo = true
      and ut.deleted_at is null
    limit 1
  ),
  base_perms as (
    select rp.permission
    from tenant_role tr
    join public.role_permissions rp
      on rp.role = a.fn_map_papel_tenant_to_role(tr.papel)
  ),
  empresa_papel as (
    select ue.papel
    from a.usuario_empresa ue
    join me on me.usuario_id = ue.usuario_id
    where ue.empresa_id = public.current_empresa_id()
      and ue.ativo = true
      and ue.deleted_at is null
    limit 1
  ),
  empresa_extra as (
    select x.permission
    from empresa_papel ep
    cross join lateral (
      values
        (case when ep.papel = 'ALMOXARIFADO' then 'xml_import.execute' end),
        (case when ep.papel = 'ALMOXARIFADO' then 'nf_entrada.import' end)
    ) as x(permission)
    where x.permission is not null
  )
  select distinct permission
  from (
    select permission from base_perms
    union all
    select permission from empresa_extra
  ) s;
$$;

revoke all on function public.get_my_permissions(uuid) from public;
grant execute on function public.get_my_permissions(uuid) to authenticated;

commit;

