begin;
do $$
begin
  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relkind = 'S'
      and n.nspname = 'public'
      and c.relname = 'fornecedores_id_seq'
  ) then
    create sequence public.fornecedores_id_seq
      as integer
      start with 1
      increment by 1
      no minvalue
      no maxvalue
      cache 1;
  end if;
end$$;
do $$
begin
  if to_regclass('public.fornecedores') is not null then
    alter sequence public.fornecedores_id_seq owned by public.fornecedores.id;

    alter table public.fornecedores
      alter column id set default nextval('public.fornecedores_id_seq'::regclass);

    if not exists (
      select 1
      from pg_constraint
      where conname = 'fornecedores_pkey'
        and conrelid = 'public.fornecedores'::regclass
    ) then
      alter table public.fornecedores
        add constraint fornecedores_pkey primary key (id);
    end if;

    create unique index if not exists fornecedores_tenant_documento_norm_uidx
      on public.fornecedores (tenant_id, documento_norm);
  end if;
end$$;
commit;
