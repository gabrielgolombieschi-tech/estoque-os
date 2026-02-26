begin;

do $$
begin
  if to_regclass('public.clientes') is not null then
    with dup_groups as (
      select tenant_id, empresa_id, documento_norm, min(id) as keep_id
      from public.clientes
      where documento_norm is not null
      group by tenant_id, empresa_id, documento_norm
      having count(*) > 1
    ), victims as (
      select c.id
      from public.clientes c
      join dup_groups d
        on d.tenant_id = c.tenant_id
       and d.empresa_id = c.empresa_id
       and d.documento_norm = c.documento_norm
      where c.id <> d.keep_id
    )
    update public.clientes c
    set documento = null,
        ativo = false,
        atualizado_em = now()
    where c.id in (select id from victims);

    drop index if exists public.clientes_tenant_empresa_documento_norm_uidx;

    if not exists (
      select 1
      from pg_constraint
      where conname = 'clientes_tenant_empresa_documento_norm_uk'
        and conrelid = 'public.clientes'::regclass
    ) then
      alter table public.clientes
        add constraint clientes_tenant_empresa_documento_norm_uk
        unique (tenant_id, empresa_id, documento_norm);
    end if;
  end if;
end $$;

commit;
notify pgrst, 'reload schema';
