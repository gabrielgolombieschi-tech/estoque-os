grant usage on schema c to authenticated;
grant select on table c.condicao_pagamento to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'c'
      and tablename = 'condicao_pagamento'
      and policyname = 'condicao_pagamento_compras_select'
  ) then
    create policy "condicao_pagamento_compras_select"
    on c.condicao_pagamento
    for select
    to authenticated
    using (
      ("tenant_id" = public.current_tenant_id())
      and ("empresa_id" = public.current_empresa_id())
      and c.has_compras_access("tenant_id", "empresa_id")
      and ("deleted_at" is null)
    );
  end if;
end $$;
