-- Adiciona policy de SELECT para os_gestao_itens e recarrega schema cache do PostgREST

alter table public.os_gestao_itens enable row level security;

drop policy if exists os_gestao_itens_perm_select on public.os_gestao_itens;
create policy os_gestao_itens_perm_select
on public.os_gestao_itens
for select
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and (
    public.has_permission('os.view')
    or public.has_permission('os.gerenciar')
  )
);

notify pgrst, 'reload schema';
