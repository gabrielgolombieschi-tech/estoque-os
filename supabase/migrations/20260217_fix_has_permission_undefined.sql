begin;

do $$
begin
  if to_regclass('public.apontamentos_horas') is not null then
    drop policy if exists apontamentos_horas_perm_select on public.apontamentos_horas;
    drop policy if exists apontamentos_select on public.apontamentos_horas;

    create policy apontamentos_select
    on public.apontamentos_horas
    for select
    to authenticated
    using (
      tenant_id = public.current_tenant_id()
      and public.can('apontamentos','read')
    );
  end if;

  if to_regclass('public.colaboradores') is not null then
    drop policy if exists colaboradores_perm_select on public.colaboradores;
    drop policy if exists colaboradores_select on public.colaboradores;

    create policy colaboradores_select
    on public.colaboradores
    for select
    to authenticated
    using (
      tenant_id = public.current_tenant_id()
      and (
        public.can('apontamentos','read')
        or public.can('os','read')
        or public.can('admin','manage_users')
        or public.can('financeiro','read')
      )
    );
  end if;

  if to_regclass('public.tipos_horas') is not null then
    drop policy if exists tipos_horas_perm_select on public.tipos_horas;
  end if;

  if to_regclass('public.colaborador_taxas') is not null then
    drop policy if exists colaborador_taxas_perm_select on public.colaborador_taxas;
  end if;
end$$;

commit;
notify pgrst, 'reload schema';
