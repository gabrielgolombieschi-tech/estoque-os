begin;

do $$
begin
  if to_regclass('public.fornecedores') is not null then
    alter table public.fornecedores
      add column if not exists gerar_contas_pagar_auto boolean not null default false;

    comment on column public.fornecedores.gerar_contas_pagar_auto is
      'Quando true, importacoes XML do fornecedor geram automaticamente contas a pagar a partir das parcelas do XML.';
  end if;
end$$;

notify pgrst, 'reload schema';
commit;
