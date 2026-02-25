-- Emergency fix: colaboradores RLS using membership-only (no public.can() calls)
-- This avoids potential recursion issues and ensures admin/financeiro can create/edit
-- Date: 2026-02-28

begin;

-- Drop all existing policies
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

-- SELECT: allow if user is active member of the row's tenant
create policy "colaboradores_select" on public.colaboradores
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = colaboradores.tenant_id
        and tm.status in ('active', 'ativo')
    )
  );

-- INSERT: allow if user is active member of the tenant being inserted
create policy "colaboradores_insert" on public.colaboradores
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = colaboradores.tenant_id
        and tm.status in ('active', 'ativo')
    )
  );

-- UPDATE: allow if user is active member of the tenant
create policy "colaboradores_update" on public.colaboradores
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = colaboradores.tenant_id
        and tm.status in ('active', 'ativo')
    )
  )
  with check (
    exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = colaboradores.tenant_id
        and tm.status in ('active', 'ativo')
    )
  );

-- DELETE: allow if user is active member of the tenant
create policy "colaboradores_delete" on public.colaboradores
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.tenant_memberships tm
      where tm.user_id = auth.uid()
        and tm.tenant_id = colaboradores.tenant_id
        and tm.status in ('active', 'ativo')
    )
  );

commit;

notify pgrst, 'reload schema';
