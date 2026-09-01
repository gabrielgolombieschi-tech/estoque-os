drop policy if exists codex_hh_tipos_mapping_select on public.hh_tipos_mapping;
create policy codex_hh_tipos_mapping_select
on public.hh_tipos_mapping
for select
to authenticated
using (
  a.fn_is_tenant_member(tenant_id)
);

drop policy if exists codex_hh_tipos_mapping_write on public.hh_tipos_mapping;
create policy codex_hh_tipos_mapping_write
on public.hh_tipos_mapping
for all
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and (
    public.has_capability('apontamentos.config')
    or a.fn_is_tenant_admin(tenant_id)
  )
)
with check (
  tenant_id = public.current_tenant_id()
  and (
    public.has_capability('apontamentos.config')
    or a.fn_is_tenant_admin(tenant_id)
  )
);

notify pgrst, 'reload schema';
