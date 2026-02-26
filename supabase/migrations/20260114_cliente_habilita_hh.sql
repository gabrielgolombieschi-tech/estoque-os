begin;

do $$
begin
  if to_regclass('public.clientes') is not null then
    alter table public.clientes
      add column if not exists habilita_hh boolean not null default false;

    comment on column public.clientes.habilita_hh is 'Indica se o cliente utiliza relatorios de Hora-Homem (HH)';
  end if;
end$$;

notify pgrst, 'reload schema';
commit;
