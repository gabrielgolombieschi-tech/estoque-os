begin;

-- Normalize CNPJ: keep only digits, require 14 digits, else NULL
create or replace function public.normalize_cnpj(p_cnpj text)
returns text
language sql
immutable
as $$
  select case
    when length(nullif(regexp_replace(coalesce(p_cnpj,''), '[^0-9]', '', 'g'), '')) = 14
      then nullif(regexp_replace(coalesce(p_cnpj,''), '[^0-9]', '', 'g'), '')
    else null
  end;
$$;

-- Ensure column exists
alter table public.fornecedores
  add column if not exists cnpj text;

-- Ensure generated normalized column uses normalize_cnpj
alter table public.fornecedores
  drop column if exists cnpj_norm;

alter table public.fornecedores
  add column cnpj_norm text generated always as (public.normalize_cnpj(cnpj)) stored;

-- Best-effort backfill CNPJ from legacy documento_norm when it looks like a CNPJ (14 digits)
update public.fornecedores f
set cnpj = f.documento_norm
where public.normalize_cnpj(f.cnpj) is null
  and length(f.documento_norm) = 14;

-- Normalize stored values (digits-only)
update public.fornecedores f
set cnpj = public.normalize_cnpj(f.cnpj)
where f.cnpj is not null
  and f.cnpj <> public.normalize_cnpj(f.cnpj);

-- Legacy safety: if there are duplicates by (tenant, empresa, cnpj_norm), keep the smallest id and
-- clear CNPJ + deactivate duplicates so the unique index can be created.
with dup_groups as (
  select tenant_id, empresa_id, cnpj_norm, min(id) as keep_id
  from public.fornecedores
  where cnpj_norm is not null
  group by tenant_id, empresa_id, cnpj_norm
  having count(*) > 1
), victims as (
  select f.id
  from public.fornecedores f
  join dup_groups d
    on d.tenant_id = f.tenant_id
   and d.empresa_id = f.empresa_id
   and d.cnpj_norm = f.cnpj_norm
  where f.id <> d.keep_id
)
update public.fornecedores f
set cnpj = null,
    ativo = false,
    atualizado_em = now()
where f.id in (select id from victims);

create unique index if not exists fornecedores_tenant_empresa_cnpj_norm_uidx
  on public.fornecedores (tenant_id, empresa_id, cnpj_norm)
  where cnpj_norm is not null;

commit;
