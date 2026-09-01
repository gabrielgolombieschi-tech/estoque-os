begin;

-- Fornecedor pertence a uma empresa. Os indices legados abaixo impediam que
-- o mesmo CNPJ fosse cadastrado para duas empresas do mesmo tenant, apesar de
-- todas as consultas e relacionamentos operacionais usarem empresa_id.
drop index if exists public.fornecedores_documento_norm_uniq;
drop index if exists public.fornecedores_tenant_documento_key_uidx;
drop index if exists public.fornecedores_tenant_documento_norm_uidx;
drop index if exists public.fornecedores_tenant_documento_norm_uk;
drop index if exists public.ux_fornecedores_tenant_documento_norm;

-- Mantem a regra correta e explicita no schema: o documento nao pode duplicar
-- dentro da mesma empresa, mas pode existir nas demais empresas do tenant.
create unique index if not exists fornecedores_unique_cnpj
  on public.fornecedores (tenant_id, empresa_id, cnpj_norm)
  where cnpj_norm is not null;

create unique index if not exists fornecedores_unique_docnorm
  on public.fornecedores (tenant_id, empresa_id, documento_norm)
  where documento_norm is not null and documento_norm <> '';

commit;
