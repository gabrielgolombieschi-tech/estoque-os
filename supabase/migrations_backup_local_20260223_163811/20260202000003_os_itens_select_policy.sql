-- Adiciona policies de SELECT para listar itens da OS e permitir embed de itens
-- e recarrega schema cache do PostgREST

drop policy if exists os_itens_perm_select on public.os_itens;
create policy os_itens_perm_select
on public.os_itens
for select
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and (
    public.has_permission('os.view')
    or public.has_permission('os.edit')
    or public.has_permission('os.gerenciar')
    or public.has_permission('os.create')
  )
);

drop policy if exists itens_perm_select on public.itens;
create policy itens_perm_select
on public.itens
for select
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and (
    public.has_permission('itens.view')
    or public.has_permission('os.view')
    or public.has_permission('os.edit')
    or public.has_permission('os.gerenciar')
  )
);

notify pgrst, 'reload schema';
