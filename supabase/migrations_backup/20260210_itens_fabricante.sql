begin;

alter table public.itens
  add column if not exists fabricante text;

commit;
