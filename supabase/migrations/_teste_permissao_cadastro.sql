-- SMOKE TEST — rollback no final.
-- O agente de cadastro exige can('cad_itens','write'). Confere se o
-- ALMOXARIFADO tem essa permissao antes de eu construir a tela em cima dela.

begin;

set local role postgres;
select set_config(
  'request.jwt.claims',
  '{"sub":"8eaaa27a-774e-4dcc-b2bb-416cb28bd2aa","role":"authenticated"}',
  true
);
set local role authenticated;

select
  public.app_meu_papel_empresa() as papel,
  public.can('cad_itens', 'write') as pode_cadastrar_item,
  public.can('itens', 'write') as pode_itens_write,
  public.can('estoque', 'write') as pode_estoque_write;

rollback;
