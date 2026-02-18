-- Update clientes RLS policies to allow ADMIN/FINANCEIRO/COORDENACAO/COMPRAS
-- ADMIN: full access (read/write/delete)
-- FINANCEIRO/COORDENACAO/COMPRAS: read/write (no delete)
-- Date: 2026-02-28

begin;

do $$
declare r record;
begin
  if to_regclass('public.clientes') is not null then
    for r in (
      select policyname from pg_policies where schemaname = 'public' and tablename = 'clientes'
    ) loop
      execute format('drop policy if exists %I on public.clientes', r.policyname);
    end loop;
  end if;
end$$;

alter table public.clientes enable row level security;

-- SELECT: allow OS read or cad_clientes write
create policy "clientes_select" on public.clientes
  for select
  to authenticated
  using (
    public.can('os', 'read')
    or public.can('cad_clientes', 'write')
    or exists (
      select 1
      from a.usuario_empresa ue
      join public.empresas emp on emp.id = ue.empresa_id
      where ue.usuario_id = a.fn_current_usuario_id()
        and ue.deleted_at is null
        and ue.ativo = true
        and ue.empresa_id = clientes.empresa_id
        and emp.tenant_id = clientes.tenant_id
        and upper(ue.papel) in ('ADMIN', 'FINANCEIRO', 'COORDENACAO', 'COMPRAS')
    )
  );

-- INSERT: allow cad_clientes.write
create policy "clientes_insert" on public.clientes
  for insert
  to authenticated
  with check (
    (
      public.can('cad_clientes', 'write')
      or exists (
        select 1
        from a.usuario_empresa ue
        join public.empresas emp on emp.id = ue.empresa_id
        where ue.usuario_id = a.fn_current_usuario_id()
          and ue.deleted_at is null
          and ue.ativo = true
          and ue.empresa_id = clientes.empresa_id
          and emp.tenant_id = clientes.tenant_id
          and upper(ue.papel) in ('ADMIN', 'FINANCEIRO', 'COORDENACAO', 'COMPRAS')
      )
    )
    and clientes.tenant_id = (
      select e.tenant_id
      from public.empresas e
      where e.id = clientes.empresa_id
      limit 1
    )
  );

-- UPDATE: allow cad_clientes.write
create policy "clientes_update" on public.clientes
  for update
  to authenticated
  using (
    public.can('cad_clientes', 'write')
    or exists (
      select 1
      from a.usuario_empresa ue
      join public.empresas emp on emp.id = ue.empresa_id
      where ue.usuario_id = a.fn_current_usuario_id()
        and ue.deleted_at is null
        and ue.ativo = true
        and ue.empresa_id = clientes.empresa_id
        and emp.tenant_id = clientes.tenant_id
        and upper(ue.papel) in ('ADMIN', 'FINANCEIRO', 'COORDENACAO', 'COMPRAS')
    )
  )
  with check (
    (
      public.can('cad_clientes', 'write')
      or exists (
        select 1
        from a.usuario_empresa ue
        join public.empresas emp on emp.id = ue.empresa_id
        where ue.usuario_id = a.fn_current_usuario_id()
          and ue.deleted_at is null
          and ue.ativo = true
          and ue.empresa_id = clientes.empresa_id
          and emp.tenant_id = clientes.tenant_id
          and upper(ue.papel) in ('ADMIN', 'FINANCEIRO', 'COORDENACAO', 'COMPRAS')
      )
    )
    and clientes.tenant_id = (
      select e.tenant_id
      from public.empresas e
      where e.id = clientes.empresa_id
      limit 1
    )
  );

-- DELETE: only ADMIN can delete (via empresa_memberships.role = 'ADMIN')
create policy "clientes_delete" on public.clientes
  for delete
  to authenticated
  using (
    exists (
      select 1
      from a.usuario_empresa ue
      join public.empresas emp on emp.id = ue.empresa_id
      where ue.usuario_id = a.fn_current_usuario_id()
        and ue.deleted_at is null
        and ue.ativo = true
        and ue.empresa_id = clientes.empresa_id
        and emp.tenant_id = clientes.tenant_id
        and upper(ue.papel) = 'ADMIN'
    )
  );

commit;

notify pgrst, 'reload schema';
