begin;
do $$
begin
  if to_regclass('public.roles') is not null and to_regclass('public.tenants') is not null then
    insert into public.roles (tenant_id, name)
    select t.id, 'Coordenacao'
    from public.tenants t
    where not exists (
      select 1
      from public.roles r
      where r.tenant_id = t.id
        and r.name = 'Coordenacao'
    );
  end if;
end$$;
do $$
begin
  if to_regclass('public.roles') is not null
    and to_regclass('public.permissions') is not null
    and to_regclass('public.role_permissions') is not null
    and exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'role_permissions'
        and column_name = 'role_id'
    ) then
    insert into public.role_permissions (role_id, permission_id)
    select r.id, p.id
    from public.roles r
    join public.permissions p
      on p.code like 'estoque.%'
    where r.name = 'Coordenacao'
    on conflict do nothing;
  end if;
end$$;
commit;
