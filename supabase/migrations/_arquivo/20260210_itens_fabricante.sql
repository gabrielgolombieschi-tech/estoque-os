begin;
do $$
begin
  if to_regclass('public.itens') is not null then
    alter table public.itens
      add column if not exists fabricante text;
  end if;
end$$;
commit;
