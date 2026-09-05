\set ON_ERROR_STOP on

begin;

insert into c.tenant (id, codigo, nome)
values ('15100000-0000-4000-8000-000000000001', 'TESTE-PARCIAL', 'Teste faturamento parcial');

insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj)
values (
  '15100000-0000-4000-8000-000000000002',
  '15100000-0000-4000-8000-000000000001',
  'PARCIAL', 'EMPRESA TESTE PARCIAL LTDA', 'PARCIAL', '11111111000191'
);

insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia)
values (
  '15100000-0000-4000-8000-000000000002',
  '15100000-0000-4000-8000-000000000001',
  '11111111000191', 'EMPRESA TESTE PARCIAL LTDA', 'PARCIAL'
)
on conflict (id) do nothing;

insert into public.clientes (id, tenant_id, empresa_id, nome, documento)
values (
  915100,
  '15100000-0000-4000-8000-000000000001',
  '15100000-0000-4000-8000-000000000002',
  'CLIENTE TESTE PARCIAL', '11222333000181'
);

insert into public.itens (
  id, tenant_id, empresa_id, codigo_interno, nome, tipo,
  unidade_medida, finalidade, ativo
)
values
  (
    915100,
    '15100000-0000-4000-8000-000000000001',
    '15100000-0000-4000-8000-000000000002',
    'PARCIAL-1', 'ITEM PARCIAL', 'produto', 'UN', 'revenda', true
  ),
  (
    915101,
    '15100000-0000-4000-8000-000000000001',
    '15100000-0000-4000-8000-000000000002',
    'PARCIAL-LEGADO', 'ITEM SEM FINALIDADE', 'produto', 'UN', 'revenda', true
  );

insert into public.ordens_servico (
  id, numero_os, cliente_nome, cliente_id, status, os_num,
  tenant_id, empresa_id, status_fluxo, tipo_documento, codigo, numero_doc
)
values (
  915100, 'OV-PARCIAL-1', 'CLIENTE TESTE PARCIAL', 915100,
  'em_andamento', 915100,
  '15100000-0000-4000-8000-000000000001',
  '15100000-0000-4000-8000-000000000002',
  'em_andamento', 'OV', 'OV-PARCIAL-001', 1
), (
  915102, 'OV-PARCIAL-2', 'CLIENTE TESTE PARCIAL', 915100,
  'em_andamento', 915102,
  '15100000-0000-4000-8000-000000000001',
  '15100000-0000-4000-8000-000000000002',
  'em_andamento', 'OV', 'OV-PARCIAL-002', 2
);

insert into public.os_itens (
  id, os_id, item_id, quantidade, valor_unitario, valor_total,
  tenant_id, empresa_id, finalidade
)
values
  (
    915100, 915100, 915100, 10, 25, 250,
    '15100000-0000-4000-8000-000000000001',
    '15100000-0000-4000-8000-000000000002', 'venda'
  ),
  (
    915101, 915100, 915101, 3, 10, 30,
    '15100000-0000-4000-8000-000000000001',
    '15100000-0000-4000-8000-000000000002', null
  ),
  (
    915102, 915102, 915100, 10, 25, 240,
    '15100000-0000-4000-8000-000000000001',
    '15100000-0000-4000-8000-000000000002', 'venda'
  );

update public.os_itens
set desconto_valor = 10
where id = 915102;

create temporary table faturamento_parcial_test_ids (
  nome text primary key,
  solicitacao_id uuid not null
) on commit drop;

insert into faturamento_parcial_test_ids (nome, solicitacao_id)
select 'primeira', f.fn_solicitacao_faturamento_criar_parcial(
  '15100000-0000-4000-8000-000000000001',
  '15100000-0000-4000-8000-000000000002',
  915100,
  '[{"os_item_id":915100,"quantidade":5,"valor_unitario":40}]'::jsonb
);

do $test$
declare
  v_saldo numeric;
  v_status text;
begin
  select saldo into v_saldo
  from f.fn_os_itens_saldo_a_faturar(
    '15100000-0000-4000-8000-000000000001',
    '15100000-0000-4000-8000-000000000002',
    915100
  )
  where os_item_id = 915100;
  if v_saldo <> 5 then
    raise exception 'Parcial 5/10 falhou: saldo esperado 5, obtido %.', v_saldo;
  end if;

  select status into v_status
  from f.solicitacao_faturamento
  where id = (select solicitacao_id from faturamento_parcial_test_ids where nome = 'primeira');
  if v_status <> 'RASCUNHO' then
    raise exception 'Composicao deveria ficar RASCUNHO, obtido %.', v_status;
  end if;

  begin
    perform f.fn_solicitacao_faturamento_criar_parcial(
      '15100000-0000-4000-8000-000000000001',
      '15100000-0000-4000-8000-000000000002',
      915100,
      '[{"os_item_id":915100,"quantidade":11,"valor_unitario":40}]'::jsonb
    );
    raise exception 'Quantidade 11 foi aceita para uma linha com saldo 5.';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Linha 915100 da OV OV-PARCIAL-001 excede o saldo.%' then
      raise;
    end if;
  end;
end;
$test$;

update f.solicitacao_faturamento
set status = 'CANCELADA'
where id = (select solicitacao_id from faturamento_parcial_test_ids where nome = 'primeira');

do $test$
declare
  v_saldo numeric;
begin
  select saldo into v_saldo
  from f.fn_os_itens_saldo_a_faturar(
    '15100000-0000-4000-8000-000000000001',
    '15100000-0000-4000-8000-000000000002',
    915100
  )
  where os_item_id = 915100;
  if v_saldo <> 10 then
    raise exception 'Cancelamento nao devolveu saldo: esperado 10, obtido %.', v_saldo;
  end if;
end;
$test$;

insert into faturamento_parcial_test_ids (nome, solicitacao_id)
select 'segunda', f.fn_solicitacao_faturamento_criar_parcial(
  '15100000-0000-4000-8000-000000000001',
  '15100000-0000-4000-8000-000000000002',
  915100,
  '[{"os_item_id":915100,"quantidade":5,"valor_unitario":45}]'::jsonb
);

-- A segunda composicao usa o restante com outro preco digitado. O valor de
-- cada rascunho e independente do custo operacional de R$ 25,00.
insert into faturamento_parcial_test_ids (nome, solicitacao_id)
select 'terceira', f.fn_solicitacao_faturamento_criar_parcial(
  '15100000-0000-4000-8000-000000000001',
  '15100000-0000-4000-8000-000000000002',
  915100,
  '[{"os_item_id":915100,"quantidade":5,"valor_unitario":45}]'::jsonb,
  array[915100]
);

do $test$
declare
  v_saldo numeric;
  v_qtd_terceira numeric;
  v_preco_segunda numeric;
  v_preco_terceira numeric;
  v_legado numeric;
  v_fiscais integer;
begin
  select saldo into v_saldo
  from f.fn_os_itens_saldo_a_faturar(
    '15100000-0000-4000-8000-000000000001',
    '15100000-0000-4000-8000-000000000002',
    915100
  )
  where os_item_id = 915100;
  if v_saldo <> 0 then
    raise exception 'Segunda parcial deveria consumir as 5 restantes; saldo %.', v_saldo;
  end if;

  select quantidade into v_qtd_terceira
  from f.solicitacao_item
  where solicitacao_id = (select solicitacao_id from faturamento_parcial_test_ids where nome = 'terceira');
  if v_qtd_terceira <> 5 then
    raise exception 'Terceira composicao deveria usar saldo 5, obteve %.', v_qtd_terceira;
  end if;

  select valor_unitario into v_preco_segunda
  from f.solicitacao_item
  where solicitacao_id = (select solicitacao_id from faturamento_parcial_test_ids where nome = 'segunda');
  select valor_unitario into v_preco_terceira
  from f.solicitacao_item
  where solicitacao_id = (select solicitacao_id from faturamento_parcial_test_ids where nome = 'terceira');
  if v_preco_segunda <> 45 or v_preco_terceira <> 45 then
    raise exception 'Preco digitado nao foi preservado: segunda %, terceira %.', v_preco_segunda, v_preco_terceira;
  end if;

  select quantidade_total into v_legado
  from f.fn_os_itens_saldo_a_faturar(
    '15100000-0000-4000-8000-000000000001',
    '15100000-0000-4000-8000-000000000002',
    915100
  )
  where os_item_id = 915101;
  if v_legado <> 3 then
    raise exception 'Linha legada sem finalidade nao ficou visivel.';
  end if;

  select count(*) into v_fiscais
  from f.solicitacao_item
  where solicitacao_id in (
    select solicitacao_id
    from faturamento_parcial_test_ids
    where nome in ('segunda', 'terceira')
  )
    and (cfop is not null or cst_icms is not null or csosn is not null
      or cst_ipi is not null or cst_pis is not null or cst_cofins is not null
      or cbenef is not null or cclass_trib is not null);
  if v_fiscais <> 0 then
    raise exception 'A tarefa de quantidade semeou configuracao fiscal.';
  end if;
end;
$test$;

-- O pipeline completo tambem precisa copiar a quantidade parcial e recalcular
-- o desconto proporcional e o total do documento fiscal.
select *
from f.fn_faturar_documento(
  '15100000-0000-4000-8000-000000000001',
  '15100000-0000-4000-8000-000000000002',
  915102,
  array[915102],
  '15100000-0000-4000-8000-000000000102',
  'HOMOLOGACAO',
  'VENDA_MERCADORIA_TERCEIROS',
  '[{"os_item_id":915102,"quantidade":4,"valor_unitario":30}]'::jsonb
);

do $test$
declare
  v_quantidade numeric;
  v_valor_item numeric;
  v_valor_nota numeric;
  v_saldo numeric;
begin
  select quantidade, valor_total
  into v_quantidade, v_valor_item
  from f.documento_fiscal_item
  where documento_fiscal_id = '15100000-0000-4000-8000-000000000102';

  select valor_total into v_valor_nota
  from f.documento_fiscal
  where id = '15100000-0000-4000-8000-000000000102';

  select saldo into v_saldo
  from f.fn_os_itens_saldo_a_faturar(
    '15100000-0000-4000-8000-000000000001',
    '15100000-0000-4000-8000-000000000002',
    915102
  )
  where os_item_id = 915102;

  if v_quantidade <> 4 or v_valor_item <> 116 or v_valor_nota <> 116 or v_saldo <> 6 then
    raise exception 'Pipeline parcial incorreto: qtd %, item %, nota %, saldo %.',
      v_quantidade, v_valor_item, v_valor_nota, v_saldo;
  end if;
end;
$test$;

rollback;
