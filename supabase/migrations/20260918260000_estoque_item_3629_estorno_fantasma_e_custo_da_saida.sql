-- Estoque do item 3629 (CLP OMRON CQM1H-CPU61, vendido na OV-SEG-00004-026). Pedido do Gabriel em
-- 18/09/2026 ("Fechar a OV-SEG-00004-026", item 3), conforme a proposta de
-- docs/faturamento/importado-por-nos-e-perfis-origem-1.md:
--
--   02/09  mov. 12633  entrada +1  "Ajuste rapido (inline) (ajuste para 1)"   sem custo   <- fantasma
--   02/09  mov. 12634  saida   -1  "Item lancado na venda OV-SEG-00004-026"    sem custo
--   17/09  mov. 13351  entrada +1  importacao NF-e 2/24 (DIR 260191366846)     995,22
--
-- A unidade que saiu para a Portobello e a importada; o ajuste de 02/09 criou uma unidade que
-- nunca existiu e deixou saldo 1 depois da venda. Aqui:
--   1. estorno do ajuste fantasma: saida -1 datada de hoje (saldo 1 -> 0), sem custo, porque a
--      unidade estornada nunca teve custo;
--   2. custo da saida da OV (mov. 12634): 437,97 bruto e 995,22 real, o custo da importacao.
--      Movimentacoes sao imutaveis (trg_block_mov_update); a trava e desligada so nesta
--      transacao e o audit_log (trg_audit_movimentacoes) registra o antes/depois;
--   3. itens.custo_medio / custo_ultima_compra ja estao em 995,22 (entrada 13351): so conferem.
-- Nenhuma nota fiscal muda. Os blocos pulam quando as linhas nao existem (banco local recriado).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

alter table public.movimentacoes disable trigger trg_block_mov_update;

do $estoque$
declare
  v_item constant integer := 3629;
  v_ajuste public.movimentacoes%rowtype;
  v_saida public.movimentacoes%rowtype;
  v_entrada public.movimentacoes%rowtype;
  v_marca constant text := 'Estorno do ajuste rápido de 02/09/2026 (mov. 12633)';
begin
  select * into v_ajuste from public.movimentacoes where id = 12633 and item_id = v_item;
  if v_ajuste.id is null then
    raise notice 'movimentacao 12633 (ajuste rapido do item 3629) nao existe neste banco: nada a fazer.';
    return;
  end if;
  select * into v_saida from public.movimentacoes where id = 12634 and item_id = v_item and tipo = 'saida' and origem_os_id = 344;
  select * into v_entrada from public.movimentacoes where id = 13351 and item_id = v_item and tipo = 'entrada';
  if v_saida.id is null or v_entrada.id is null then
    raise exception 'item 3629: esperava a saida 12634 (OV 344) e a entrada 13351 (importacao 2/24)';
  end if;
  if v_ajuste.tipo <> 'entrada' or v_ajuste.quantidade <> 1
     or v_ajuste.custo_unitario_real is not null or v_ajuste.motivo not like 'Ajuste rápido%' then
    raise exception 'movimentacao 12633 nao e o ajuste rapido esperado: % % % %', v_ajuste.tipo, v_ajuste.quantidade, v_ajuste.custo_unitario_real, v_ajuste.motivo;
  end if;
  if v_entrada.custo_unitario_real <> 995.22 or v_entrada.custo_unitario_bruto <> 437.97 then
    raise exception 'entrada 13351 com custo diferente do esperado: % / %', v_entrada.custo_unitario_bruto, v_entrada.custo_unitario_real;
  end if;

  -- 1. Estorno do ajuste fantasma (idempotente pela marca no motivo).
  if exists (select 1 from public.movimentacoes where item_id = v_item and motivo like v_marca || '%') then
    raise notice 'estorno do ajuste 12633 ja lancado.';
  else
    insert into public.movimentacoes (
      item_id, tipo, quantidade, motivo, realizado_por, data_movimentacao, tenant_id, empresa_id
    ) values (
      v_item, 'saida', 1,
      v_marca || ': unidade fantasma; a peça vendida na OV-SEG-00004-026 é a da NF-e 2/24 (DIR 260191366846). '
        || 'Pedido do Gabriel; migration 20260918260000.',
      'migration 20260918260000', now()::timestamp without time zone,
      v_ajuste.tenant_id, v_ajuste.empresa_id
    );
  end if;

  -- 2. Custo da saida da OV = custo da importacao.
  if v_saida.custo_unitario_real is distinct from 995.22 or v_saida.custo_unitario_bruto is distinct from 437.97 then
    update public.movimentacoes
       set custo_unitario_bruto = 437.97,
           custo_unitario_real = 995.22
     where id = v_saida.id;
  else
    raise notice 'saida 12634 ja esta com o custo 995,22.';
  end if;
end;
$estoque$;

alter table public.movimentacoes enable trigger trg_block_mov_update;

-- Conferencias: so checam.
do $assertions$
declare
  v_saldo numeric;
  v_custo numeric;
  v_medio numeric;
begin
  if not exists (select 1 from public.movimentacoes where id = 12633 and item_id = 3629) then
    return;
  end if;
  select e.quantidade_atual into v_saldo
  from public.estoque e join public.itens i on i.id = e.item_id and i.tenant_id = e.tenant_id and i.empresa_id = e.empresa_id
  where i.id = 3629;
  if coalesce(v_saldo, 0) <> 0 then
    raise exception 'item 3629 devia ficar com saldo 0 depois do estorno, ficou %', v_saldo;
  end if;
  select custo_unitario_real into v_custo from public.movimentacoes where id = 12634;
  if v_custo is distinct from 995.22 then
    raise exception 'saida 12634 sem o custo 995,22: %', v_custo;
  end if;
  select custo_medio into v_medio from public.itens where id = 3629;
  if v_medio is distinct from 995.22 then
    raise exception 'custo medio do item 3629 devia ser 995,22: %', v_medio;
  end if;
  if not exists (select 1 from public.audit_log where table_name = 'movimentacoes' and row_pk = '12634' and action = 'UPDATE') then
    raise exception 'audit_log da atualizacao de custo da saida 12634 nao gravado';
  end if;
  if (select tgenabled from pg_trigger where tgrelid = 'public.movimentacoes'::regclass and tgname = 'trg_block_mov_update') = 'D' then
    raise exception 'trg_block_mov_update ficou desligado';
  end if;
end;
$assertions$;

commit;
