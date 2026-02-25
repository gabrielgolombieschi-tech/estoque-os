-- Limita tenant_memberships a auto-selecao (sem dependencia de tenant contexto)
alter table public.tenant_memberships enable row level security;

drop policy if exists memberships_select_admin on public.tenant_memberships;
drop policy if exists memberships_insert_admin on public.tenant_memberships;
drop policy if exists memberships_update_admin on public.tenant_memberships;
drop policy if exists memberships_delete_admin on public.tenant_memberships;
drop policy if exists memberships_select_self on public.tenant_memberships;

create policy memberships_select_self
on public.tenant_memberships
for select
to authenticated
using (user_id = auth.uid());
