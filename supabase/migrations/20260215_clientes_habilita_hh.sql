-- Adicionar coluna habilita_hh a tabela clientes

do $$
begin
  if to_regclass('public.clientes') is not null then
    alter table public.clientes
      add column if not exists habilita_hh boolean default false not null;

    create index if not exists idx_clientes_habilita_hh on public.clientes(habilita_hh);
  end if;
end$$;
