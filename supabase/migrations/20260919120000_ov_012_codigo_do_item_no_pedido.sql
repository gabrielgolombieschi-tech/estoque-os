-- OV-SEG-00012-026: o codigo do item no pedido do cliente entra na nota.
--
-- A Portobello identifica a peca pelo codigo dela, 313852, e pediu o numero na nota. A conferencia
-- da OV nao tem campo de observacao (a da OS tem), e o unico lugar que chega ao infCpl hoje e
-- f.solicitacao_faturamento.observacao — que o montador leva para as informacoes complementares
-- quando o texto nao e o automatico da composicao ("Composicao parcial da OV ...").
--
-- Enquanto o campo nao existe na tela, o texto entra aqui, so nesta solicitacao e so enquanto ela
-- for rascunho. Pedido do Gabriel em 18/09/2026 (item 4 da tarefa da OV-012).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

do $observacao$
declare
  v_sol constant uuid := 'd6a95ef7-6d21-4e33-9727-69c23e95795e';
  v_texto constant text := 'Cod. cliente: 313852';
  v_status text;
begin
  select sf.status into v_status from f.solicitacao_faturamento sf where sf.id = v_sol;
  if v_status is null then
    raise notice 'solicitacao % nao existe neste banco: nada a gravar.', v_sol;
    return;
  end if;
  if v_status <> 'RASCUNHO' then
    raise exception 'solicitacao % esta em %: a observacao so entra em rascunho', v_sol, v_status;
  end if;
  update f.solicitacao_faturamento
     set observacao = v_texto, updated_at = now()
   where id = v_sol;
end;
$observacao$;

do $assertions$
begin
  if exists (select 1 from f.solicitacao_faturamento where id = 'd6a95ef7-6d21-4e33-9727-69c23e95795e')
     and (select observacao from f.solicitacao_faturamento where id = 'd6a95ef7-6d21-4e33-9727-69c23e95795e') <> 'Cod. cliente: 313852' then
    raise exception 'observacao da solicitacao da OV-012 nao ficou com o codigo do cliente';
  end if;
end;
$assertions$;

commit;
