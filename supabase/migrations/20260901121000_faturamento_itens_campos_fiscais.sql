begin;

alter table public.itens
  add column origem_mercadoria text
    check (origem_mercadoria in ('0', '1', '2', '3', '4', '5', '6', '7', '8')),
  add column cst_icms text,
  add column csosn text,
  add column cst_ipi text,
  add column cst_pis text,
  add column cst_cofins text,
  add column unidade_tributavel text,
  add column c_class_trib text;

commit;
