-- Adiciona policies de SELECT para execucao (os_gestao_itens e ordens_servico)
-- e recarrega schema cache do PostgREST

do $$
begin
  if to_regclass('public.os_gestao_itens') is not null then
    alter table public.os_gestao_itens enable row level security;
    drop policy if exists os_gestao_itens_perm_select_execucao on public.os_gestao_itens;
    create policy os_gestao_itens_perm_select_execucao
    on public.os_gestao_itens
    for select
    to authenticated
    using (
      tenant_id = public.current_tenant_id()
      and (
        public.has_permission('execucao.view')
        or public.has_permission('execucao.edit')
        or public.has_permission('execucao.create')
        or public.has_permission('os.view')
        or public.has_permission('os.edit')
      )
    );
  end if;

  if to_regclass('public.ordens_servico') is not null then
    alter table public.ordens_servico enable row level security;
    drop policy if exists ordens_servico_perm_select_execucao on public.ordens_servico;
    create policy ordens_servico_perm_select_execucao
    on public.ordens_servico
    for select
    to authenticated
    using (
      tenant_id = public.current_tenant_id()
      and (
        public.has_permission('execucao.view')
        or public.has_permission('execucao.edit')
        or public.has_permission('execucao.create')
        or public.has_permission('os.view')
        or public.has_permission('os.edit')
      )
    );
  end if;
end$$;

notify pgrst, 'reload schema';
