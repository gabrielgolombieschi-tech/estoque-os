-- SMOKE TEST — termina em rollback, nao altera nada.
-- Confere o painel de orcamentos com a data real de fechamento/perda.

begin;

set local role postgres;
select set_config(
  'request.jwt.claims',
  '{"sub":"8eaaa27a-774e-4dcc-b2bb-416cb28bd2aa","role":"authenticated"}',
  true
);
set local role authenticated;

select jsonb_pretty(public.app_orcamento_painel(2026, 8) - 'meses' - 'clientes') as agosto;
select jsonb_pretty(public.app_orcamento_painel(2026, 8) -> 'meses') as por_mes;
select jsonb_pretty(jsonb_path_query_array(public.app_orcamento_painel(2026, 8) -> 'clientes', '$[0 to 3]')) as clientes;

rollback;
