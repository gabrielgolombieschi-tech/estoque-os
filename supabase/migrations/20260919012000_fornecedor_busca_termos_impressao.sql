-- A impressao de itens deve aplicar a mesma busca de fornecedor da RPC do
-- cadastro, incluindo termos separados e equivalencia entre virgula e ponto.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

alter table public.fornecedores
  add column if not exists nome_busca_termos text generated always as (
    public.fn_item_busca_normalizar(nome::text)
  ) stored;

comment on column public.fornecedores.nome_busca_termos is
  'Nome gerado para os filtros por termos de fornecedor nas consultas de itens, com a mesma normalizacao das RPCs.';

notify pgrst, 'reload schema';
commit;
