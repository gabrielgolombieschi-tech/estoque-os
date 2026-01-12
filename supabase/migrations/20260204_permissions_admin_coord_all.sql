begin;

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'tenant_memberships_role_check'
  ) then
    alter table public.tenant_memberships
      drop constraint tenant_memberships_role_check;
  end if;
end$$;

alter table public.tenant_memberships
  add constraint tenant_memberships_role_check
  check (role in ('admin', 'fiscal', 'estoque', 'projetos', 'financeiro', 'coordenacao'));

do $$
begin
  if to_regclass('public.permissions') is not null then
    insert into public.permissions (code, description)
    select 'admin.all', 'Acesso total (admin)'
    where not exists (select 1 from public.permissions p where p.code = 'admin.all');

    insert into public.permissions (code, description)
    select 'coord.all', 'Acesso total (coordenacao)'
    where not exists (select 1 from public.permissions p where p.code = 'coord.all');
  end if;
end$$;

do $$
begin
  if to_regclass('public.role_permissions') is not null
    and exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'role_permissions'
        and column_name = 'role'
    )
  then
    insert into public.role_permissions (role, permission) values
      ('admin', 'admin.all'),
      ('coordenacao', 'coord.all')
    on conflict do nothing;
  end if;
end$$;

commit;
