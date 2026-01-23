-- Reset colaboradores RLS to allow admin/financeiro insert/update/delete and ensure tenant scoping
-- Date: 2026-02-28

begin;

do $$
declare r record;
begin
  if to_regclass('public.colaboradores') is not null then
    for r in (
      select policyname from pg_policies where schemaname = 'public' and tablename = 'colaboradores'
    ) loop
      execute format('drop policy if exists %I on public.colaboradores', r.policyname);
    end loop;
  end if;
end$$;

alter table public.colaboradores enable row level security;

create policy "colaboradores_select" on public.colaboradores
  for select
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and (
      public.can('colaboradores', 'read')
      or public.can('apontamentos', 'read')
      or public.can('apontamentos', 'create')
      or public.can('apontamentos', 'update')
      or public.can('os', 'read')
      or public.can('financeiro', 'read')
      or public.can('admin', 'manage_users')
    )
  );

create policy "colaboradores_insert" on public.colaboradores
  for insert
  to authenticated
  with check (
    tenant_id = public.current_tenant_id()
    and (
      public.can('colaboradores', 'create')
      or public.can('admin', 'manage_users')
      or public.can('financeiro', 'write')
      or public.can('financeiro', 'config')
    )
  );

create policy "colaboradores_update" on public.colaboradores
  for update
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and (
      public.can('colaboradores', 'update')
      or public.can('admin', 'manage_users')
      or public.can('financeiro', 'write')
      or public.can('financeiro', 'config')
    )
  )
  with check (
    tenant_id = public.current_tenant_id()
    and (
      public.can('colaboradores', 'update')
      or public.can('admin', 'manage_users')
      or public.can('financeiro', 'write')
      or public.can('financeiro', 'config')
    )
  );

create policy "colaboradores_delete" on public.colaboradores
  for delete
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and (
      public.can('colaboradores', 'delete')
      or public.can('admin', 'manage_users')
      or public.can('financeiro', 'write')
      or public.can('financeiro', 'config')
    )
  );

commit;

notify pgrst, 'reload schema';
