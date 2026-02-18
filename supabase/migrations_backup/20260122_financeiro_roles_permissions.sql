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
  check (role in ('admin', 'fiscal', 'estoque', 'projetos', 'financeiro'));

insert into public.role_permissions (role, permission) values
  ('admin', 'financeiro.gerenciar'),
  ('financeiro', 'financeiro.gerenciar')
on conflict do nothing;

commit;
