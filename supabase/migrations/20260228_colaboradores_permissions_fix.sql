-- Fix colaboradores RLS so admin/financeiro can create/update/delete
-- Also correct public.can() argument order to (resource, action)
-- Date: 2026-02-28

begin;
alter table public.colaboradores enable row level security;
drop policy if exists "colaboradores_select" on public.colaboradores;
drop policy if exists "colaboradores_insert" on public.colaboradores;
drop policy if exists "colaboradores_update" on public.colaboradores;
drop policy if exists "colaboradores_delete" on public.colaboradores;
-- SELECT: keep broad read for apontamentos/OS/admin/financeiro
create policy "colaboradores_select" on public.colaboradores
  for select
  to authenticated
  using (
    public.can('colaboradores', 'read')
    or public.can('apontamentos', 'read')
    or public.can('apontamentos', 'create')
    or public.can('apontamentos', 'update')
    or public.can('os', 'read')
    or public.can('financeiro', 'read')
    or public.can('admin', 'manage_users')
  );
-- INSERT: allow explicit permission or admin/financeiro roles
create policy "colaboradores_insert" on public.colaboradores
  for insert
  to authenticated
  with check (
    public.can('colaboradores', 'create')
    or public.can('admin', 'manage_users')
    or public.can('financeiro', 'write')
    or public.can('financeiro', 'config')
  );
-- UPDATE: allow explicit permission or admin/financeiro roles
create policy "colaboradores_update" on public.colaboradores
  for update
  to authenticated
  using (
    public.can('colaboradores', 'update')
    or public.can('admin', 'manage_users')
    or public.can('financeiro', 'write')
    or public.can('financeiro', 'config')
  )
  with check (
    public.can('colaboradores', 'update')
    or public.can('admin', 'manage_users')
    or public.can('financeiro', 'write')
    or public.can('financeiro', 'config')
  );
-- DELETE: allow explicit permission or admin/financeiro roles
create policy "colaboradores_delete" on public.colaboradores
  for delete
  to authenticated
  using (
    public.can('colaboradores', 'delete')
    or public.can('admin', 'manage_users')
    or public.can('financeiro', 'write')
    or public.can('financeiro', 'config')
  );
commit;
