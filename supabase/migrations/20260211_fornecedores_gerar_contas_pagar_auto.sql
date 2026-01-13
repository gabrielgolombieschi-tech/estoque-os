begin;

alter table public.fornecedores
  add column if not exists gerar_contas_pagar_auto boolean not null default false;

comment on column public.fornecedores.gerar_contas_pagar_auto is
  'Quando true, importaÃ§Ãµes XML do fornecedor geram automaticamente contas a pagar a partir das parcelas do XML.';

notify pgrst, 'reload schema';

commit;
