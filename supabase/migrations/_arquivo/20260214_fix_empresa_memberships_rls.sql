begin;

do $$
begin
  if to_regclass('public.empresa_memberships') is not null then
    drop policy if exists empresa_memberships_select on public.empresa_memberships;

    if to_regclass('public.tenant_memberships') is not null then
      create policy empresa_memberships_select on public.empresa_memberships
        for select
        using (
          user_id = auth.uid()
          or exists (
            select 1
            from public.tenant_memberships tm
            where tm.user_id = auth.uid()
              and tm.tenant_id = empresa_memberships.tenant_id
              and tm.status = 'active'
              and tm.role = 'admin'
          )
          or exists (
            select 1
            from public.tenant_memberships tm
            where tm.user_id = auth.uid()
              and tm.tenant_id = empresa_memberships.tenant_id
              and tm.status = 'active'
              and tm.role != 'guest'
          )
        );
    else
      create policy empresa_memberships_select on public.empresa_memberships
        for select
        using (user_id = auth.uid());
    end if;
  end if;
end$$;

commit;
