-- SMOKE TEST — termina em rollback, nao altera nada.
-- Roda o painel de estoque como a conta de teste, que agora e ALMOXARIFADO.

begin;

set local role postgres;
select set_config(
  'request.jwt.claims',
  '{"sub":"8eaaa27a-774e-4dcc-b2bb-416cb28bd2aa","role":"authenticated"}',
  true
);
set local role authenticated;

select jsonb_pretty(public.app_estoque_painel(2026, 8) - 'cadastros' - 'repor' - 'giro') as resumo;
select jsonb_pretty(public.app_estoque_painel(2026, 8) -> 'cadastros') as cadastros;
select jsonb_pretty(jsonb_path_query_array(public.app_estoque_painel(2026, 8) -> 'repor', '$[0 to 2]')) as repor;
select jsonb_pretty(jsonb_path_query_array(public.app_estoque_painel(2026, 8) -> 'giro', '$[0 to 2]')) as giro;

rollback;
