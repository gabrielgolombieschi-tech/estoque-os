-- 1) Permission seed
insert into public.permissions (code, description)
select 'admin.users.manage', 'Gerenciar usuarios (cadastro, edicao, permissoes e reset de senha)'
where not exists (
  select 1 from public.permissions p where p.code = 'admin.users.manage'
);

-- 2) tenant_memberships policies
alter table public.tenant_memberships enable row level security;

drop policy if exists memberships_select_admin on public.tenant_memberships;
create policy memberships_select_admin
on public.tenant_memberships
for select
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and public.has_permission('admin.users.manage')
);

drop policy if exists memberships_insert_admin on public.tenant_memberships;
create policy memberships_insert_admin
on public.tenant_memberships
for insert
to authenticated
with check (
  tenant_id = public.current_tenant_id()
  and public.has_permission('admin.users.manage')
);

drop policy if exists memberships_update_admin on public.tenant_memberships;
create policy memberships_update_admin
on public.tenant_memberships
for update
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and public.has_permission('admin.users.manage')
)
with check (
  tenant_id = public.current_tenant_id()
  and public.has_permission('admin.users.manage')
);

drop policy if exists memberships_delete_admin on public.tenant_memberships;
create policy memberships_delete_admin
on public.tenant_memberships
for delete
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and public.has_permission('admin.users.manage')
);

-- 3) membership_roles policies
alter table public.membership_roles enable row level security;

drop policy if exists membership_roles_insert_admin on public.membership_roles;
create policy membership_roles_insert_admin
on public.membership_roles
for insert
to authenticated
with check (
  public.has_permission('admin.users.manage')
  and exists (
    select 1
    from public.tenant_memberships tm
    where tm.id = membership_id
      and tm.tenant_id = public.current_tenant_id()
  )
);

drop policy if exists membership_roles_delete_admin on public.membership_roles;
create policy membership_roles_delete_admin
on public.membership_roles
for delete
to authenticated
using (
  public.has_permission('admin.users.manage')
  and exists (
    select 1
    from public.tenant_memberships tm
    where tm.id = membership_id
      and tm.tenant_id = public.current_tenant_id()
  )
);
