-- Ajusta policies de SELECT para projetos e adiciona funcao de debug de tenant

alter table public.os_gestao_itens enable row level security;
alter table public.ordens_servico enable row level security;

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
    or public.has_permission('projetos.view')
    or public.has_permission('projetos.gerenciar')
  )
);

drop policy if exists ordens_servico_perm_select_projetos on public.ordens_servico;
create policy ordens_servico_perm_select_projetos
on public.ordens_servico
for select
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and (
    public.has_permission('os.view')
    or public.has_permission('os.edit')
    or public.has_permission('os.gerenciar')
    or public.has_permission('projetos.view')
    or public.has_permission('projetos.gerenciar')
  )
);

create or replace function public.debug_tenant()
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'uid', auth.uid(),
    'tenant', public.current_tenant_id(),
    'tenant_setting', current_setting('app.tenant_id', true)
  );
$$;

notify pgrst, 'reload schema';
