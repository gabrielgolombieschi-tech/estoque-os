begin;

drop policy if exists apontamentos_horas_perm_select on public.apontamentos_horas;
create policy apontamentos_horas_perm_select on public.apontamentos_horas
  for select
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.has_permission('apontamentos.lancar')
  );

drop policy if exists colaboradores_perm_select on public.colaboradores;
create policy colaboradores_perm_select on public.colaboradores
  for select
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.has_permission('apontamentos.lancar')
  );

drop policy if exists tipos_horas_perm_select on public.tipos_horas;
create policy tipos_horas_perm_select on public.tipos_horas
  for select
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.has_permission('apontamentos.lancar')
  );

drop policy if exists colaborador_taxas_perm_select on public.colaborador_taxas;
create policy colaborador_taxas_perm_select on public.colaborador_taxas
  for select
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and public.has_permission('apontamentos.lancar')
  );

commit;
