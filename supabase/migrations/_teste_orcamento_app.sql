-- SMOKE TEST — termina em rollback, nao cria orcamento de verdade.
-- Confere condicao de pagamento, contatos do cliente, criacao completa e o
-- painel de orcamentos da Home.

begin;

set local role postgres;
select set_config(
  'request.jwt.claims',
  '{"sub":"8eaaa27a-774e-4dcc-b2bb-416cb28bd2aa","role":"authenticated"}',
  true
);
set local role authenticated;

select jsonb_pretty(jsonb_path_query_array(public.app_orcamento_condicoes_pagamento(), '$[0 to 2]')) as condicoes;

select jsonb_pretty(public.app_orcamento_painel(2026, 8) - 'meses' - 'clientes') as painel_agosto;
select jsonb_pretty(public.app_orcamento_painel(2026, 8) -> 'meses') as por_mes;
select jsonb_pretty(jsonb_path_query_array(public.app_orcamento_painel(2026, 8) -> 'clientes', '$[0 to 2]')) as top_clientes;

do $teste$
declare
  v_cliente integer;
  v_condicao uuid;
  v_item integer;
  v_orcamento jsonb;
  v_id uuid;
  v_detalhe jsonb;
begin
  select (public.app_orcamento_clientes('portobello', 1) -> 0 ->> 'id')::integer into v_cliente;
  select (public.app_orcamento_condicoes_pagamento() -> 0 ->> 'id')::uuid into v_condicao;
  select (public.app_orcamento_buscar_itens('disjuntor', null, 1) -> 0 ->> 'item_id')::integer into v_item;

  raise notice 'contatos ja conhecidos do cliente: %',
    jsonb_array_length(public.app_orcamento_contatos_cliente(v_cliente));

  v_orcamento := public.app_orcamento_criar(
    v_cliente, 'TESTE CONDICAO E SOLICITANTE', v_condicao,
    'Fulano de Tal', 'Engenharia', 'FULANO@EXEMPLO.COM.BR', '(47) 99999-0000'
  );
  v_id := (v_orcamento ->> 'id')::uuid;

  perform public.app_orcamento_adicionar_item(v_id, v_item, 2, null);
  v_detalhe := public.app_orcamento_detalhe(v_id) -> 'orcamento';

  raise notice 'codigo % | condicao % | acrescimo %',
    v_detalhe ->> 'codigo', v_detalhe ->> 'condicao_pagamento', v_detalhe ->> 'acrescimo_cond_pag_percent';
  raise notice 'solicitante % | % | % | %',
    v_detalhe ->> 'solicitante_nome', v_detalhe ->> 'solicitante_setor',
    v_detalhe ->> 'solicitante_email', v_detalhe ->> 'solicitante_telefone';
  raise notice 'total %', v_detalhe ->> 'total_liquido';
  raise notice 'contato guardado para a proxima: %',
    jsonb_array_length(public.app_orcamento_contatos_cliente(v_cliente));
end;
$teste$;

-- Recusa criar sem condicao de pagamento.
do $recusa$
begin
  perform public.app_orcamento_criar(1, 'DEVE FALHAR', null, 'Alguem', null, null, null);
  raise exception 'deveria ter recusado sem condicao de pagamento';
exception
  when others then
    if sqlerrm like '%condição de pagamento%' then
      raise notice 'recusou sem condicao, como esperado: %', sqlerrm;
    else
      raise;
    end if;
end;
$recusa$;

rollback;
