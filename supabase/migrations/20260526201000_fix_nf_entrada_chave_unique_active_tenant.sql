begin;

alter table public.nf_entrada
  drop constraint if exists nf_entrada_chave_key;

drop index if exists public.nf_entrada_chave_key;

create unique index if not exists nf_entrada_tenant_empresa_chave_active_uidx
  on public.nf_entrada (tenant_id, empresa_id, chave)
  where deleted_at is null
    and chave is not null;

commit;
