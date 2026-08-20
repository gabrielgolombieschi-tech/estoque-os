begin;

-- O cadastro assistido por IA passa a permitir dois ajustes humanos antes da
-- confirmacao: editar o preco unitario sugerido pela pesquisa e informar uma
-- quantidade que, quando maior que zero, tambem gera o estoque inicial do
-- item (antes a quantidade servia apenas de referencia para a cotacao).

alter table public.item_cadastro_agente_sugestoes
  drop constraint if exists item_cadastro_agente_sugestoes_quantidade_positiva_ck;
alter table public.item_cadastro_agente_sugestoes
  add constraint item_cadastro_agente_sugestoes_quantidade_positiva_ck
  check (quantidade_referencia >= 0);

alter table public.item_cadastro_agente_sugestoes
  add column if not exists preco_confirmado numeric(14,4),
  add column if not exists movimentacao_estoque_id integer
    references public.movimentacoes (id) on delete set null;

alter table public.item_cadastro_agente_sugestoes
  drop constraint if exists item_cadastro_agente_sugestoes_preco_confirmado_positivo_ck;
alter table public.item_cadastro_agente_sugestoes
  add constraint item_cadastro_agente_sugestoes_preco_confirmado_positivo_ck
  check (preco_confirmado is null or preco_confirmado > 0);

create index if not exists idx_item_cadastro_agente_sugestoes_movimentacao
  on public.item_cadastro_agente_sugestoes (movimentacao_estoque_id)
  where movimentacao_estoque_id is not null;

comment on column public.item_cadastro_agente_sugestoes.quantidade_referencia is
  'Quantidade informada para a cotacao; quando maior que zero, tambem define o estoque inicial criado na confirmacao.';
comment on column public.item_cadastro_agente_sugestoes.preco_final is
  'Preco final calculado pela pesquisa do agente, antes de eventual ajuste manual na confirmacao.';
comment on column public.item_cadastro_agente_sugestoes.preco_confirmado is
  'Preco unitario efetivamente confirmado pela pessoa usuaria, gravado no cadastro do item e na movimentacao de estoque inicial.';
comment on column public.item_cadastro_agente_sugestoes.movimentacao_estoque_id is
  'Movimentacao de entrada criada para o estoque inicial quando a quantidade informada for maior que zero.';

commit;
