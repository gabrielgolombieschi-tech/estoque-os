-- Permite reutilizar codigo_interno de produto quando o fornecedor for diferente.
-- Mantem unicidade por tenant/empresa/fornecedor para itens ativos e preserva
-- uma regra separada para itens ativos sem fornecedor definido.

alter table if exists public.itens
  drop constraint if exists itens_tenant_codigo_interno_uk;

drop index if exists public.uq_itens__tenant_empresa_codigo_interno;
drop index if exists public.uq_itens__tenant_empresa_codigo_interno_sem_zeros__ativos;

create index if not exists idx_itens__tenant_empresa_codigo_interno_lookup
  on public.itens (tenant_id, empresa_id, codigo_interno);

create unique index if not exists uq_itens__tenant_empresa_fornecedor_codigo_interno__ativos
  on public.itens (tenant_id, empresa_id, fornecedor_id, codigo_interno)
  where fornecedor_id is not null
    and coalesce(ativo, true) = true;

create unique index if not exists uq_itens__tenant_empresa_codigo_interno_sem_fornecedor__ativos
  on public.itens (tenant_id, empresa_id, codigo_interno)
  where fornecedor_id is null
    and coalesce(ativo, true) = true;
