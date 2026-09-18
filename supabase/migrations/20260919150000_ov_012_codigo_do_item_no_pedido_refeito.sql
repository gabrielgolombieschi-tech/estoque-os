-- OV-SEG-00012-026: o codigo do item no pedido do cliente volta para a nota refeita.
--
-- A migration 20260919120000 gravou 'Cod. cliente: 313852' na solicitacao d6a95ef7, que foi
-- cancelada junto com a NF-e 2/34 em 18/09/2026. A nota foi refeita com o IPI por fora e o ICMS
-- pelo beneficio de automacao, em uma solicitacao nova; o texto precisa acompanhar.
--
-- A conferencia da OV continua sem campo de observacao na tela (a da OS tem), e o unico lugar que
-- chega ao infCpl e f.solicitacao_faturamento.observacao — que o montador leva para as informacoes
-- complementares quando o texto nao e o automatico da composicao ("Composicao parcial da OV ...").
--
-- So nesta solicitacao e so enquanto ela for rascunho. Pedido do Gabriel em 18/09/2026.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

do $observacao$
declare
  v_sol constant uuid := '3158a494-9a27-486e-8776-4b49aecd7e77';
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
  if exists (select 1 from f.solicitacao_faturamento where id = '3158a494-9a27-486e-8776-4b49aecd7e77')
     and (select observacao from f.solicitacao_faturamento where id = '3158a494-9a27-486e-8776-4b49aecd7e77') <> 'Cod. cliente: 313852' then
    raise exception 'observacao da solicitacao refeita da OV-012 nao ficou com o codigo do cliente';
  end if;
end;
$assertions$;

commit;
