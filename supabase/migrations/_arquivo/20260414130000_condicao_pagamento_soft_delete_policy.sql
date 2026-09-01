create policy "condicao_pagamento_soft_delete"
on "c"."condicao_pagamento"
for update
to "authenticated"
using (
  ("tenant_id" = "public"."current_tenant_id"())
  and ("empresa_id" = "public"."current_empresa_id"())
  and "c"."has_comercial_access"()
  and ("deleted_at" is null)
)
with check (
  ("tenant_id" = "public"."current_tenant_id"())
  and ("empresa_id" = "public"."current_empresa_id"())
  and "c"."has_comercial_access"()
);
