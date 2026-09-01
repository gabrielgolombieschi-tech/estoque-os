begin;

-- fiscal_itens.item_id nasceu bigint, mas public.itens.id e integer. As FKs
-- antigas aceitavam tipos numericos compativeis e, por isso, esconderam a
-- divergencia. A coluna passa a usar exatamente o tipo do cadastro real.
alter table public.fiscal_itens
  drop constraint if exists fiscal_itens_item_id_fkey,
  drop constraint if exists fiscal_itens_tenant_item_fk;

alter table public.fiscal_itens
  alter column item_id type integer using item_id::integer,
  add column unidade_tributavel text;

alter table public.fiscal_itens
  add constraint fiscal_itens_item_escopo_fk
    foreign key (tenant_id, empresa_id, item_id)
    references public.itens(tenant_id, empresa_id, id)
    on delete cascade;

comment on column public.fiscal_itens.unidade_tributavel is
  'Unidade tributavel do produto na NF-e. Nao define CFOP, CST/CSOSN ou tributacao da operacao.';

commit;
