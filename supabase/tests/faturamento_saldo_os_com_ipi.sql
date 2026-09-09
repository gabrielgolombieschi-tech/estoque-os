\set ON_ERROR_STOP on

-- Saldo a faturar conta o IPI (09/09/2026, OS 287 / pedido WEG 4518946561).
-- O orcado da OS e o pedido do cliente, que vem com IPI; entao a nota emitida
-- consome o saldo pelo vNF, e o rascunho reserva mercadoria + IPI previsto.

begin;

insert into public.tenants (id, nome, ativo) values ('19000000-0000-4000-8000-000000000010', 'Tenant saldo IPI', true);
insert into c.tenant (id, codigo, nome, ativo) values ('19000000-0000-4000-8000-000000000010', 'SALDO-IPI', 'Tenant saldo IPI', true);
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo)
values ('19000000-0000-4000-8000-000000000020', '19000000-0000-4000-8000-000000000010', 'IPI-A', 'Empresa saldo IPI', 'Empresa saldo IPI', '19000000000100', true);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo)
values ('19000000-0000-4000-8000-000000000020', '19000000-0000-4000-8000-000000000010', '19000000000100', 'Empresa saldo IPI', 'Empresa saldo IPI', true);

insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social)
values (919001, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'CLIENTE IPI', '19111111000191', 'CLIENTE IPI LTDA');

-- A nota emitida dispara o AR automatico (trg_documento_fiscal__ar_nfe).
insert into f.plano_contas (tenant_id, codigo, nome, natureza, tipo, ativo)
values ('19000000-0000-4000-8000-000000000010', '3.01', 'RECEITA DE VENDAS', 'CREDITO', 'ANALITICA', true);

-- Os tres casos usam o mesmo pedido: 19.411,35 de mercadoria + 9,75% de IPI = 21.303,96.
insert into public.ordens_servico (id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id,
  status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado)
values
  (919001, 'IPI-1', 'CLIENTE IPI', 919001, 'concluida', 919001, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'concluida', 'OS', 'OS-IPI-001', 1, 'OS com NF-e de IPI emitida', 21303.96),
  (919002, 'IPI-2', 'CLIENTE IPI', 919001, 'em_andamento', 919002, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-IPI-002', 1, 'OS com rascunho de IPI', 21303.96),
  (919003, 'IPI-3', 'CLIENTE IPI', 919001, 'em_andamento', 919003, '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-IPI-003', 1, 'OS com rascunho sem IPI', 21303.96);

-- 1) Nota emitida com IPI destacado: vNF 21.303,96 sobre 19.411,35 de mercadoria.
insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza,
  os_id_import, cliente_id, nfe_status, valor_produtos, valor_total)
values ('19000000-0000-4000-8000-000000000031', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020',
  '19000000000000000000000000000000000000000001', '55', '2', '900001', 'SAIDA', 'PRODUTO',
  919001, 919001, 'EMITIDA', 19411.35, 21303.96);

-- 2) Rascunho com IPI tributado (CST 50, 9,75%): reserva mercadoria + imposto.
insert into f.solicitacao_faturamento (id, tenant_id, empresa_id, status, natureza_operacao)
values ('19000000-0000-4000-8000-000000000041', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'RASCUNHO', 'VENDA');
insert into f.solicitacao_item (solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id, ordem, descricao, quantidade, valor_unitario, cst_ipi, aliquota_ipi)
values
  ('19000000-0000-4000-8000-000000000041', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'OS', '919002', 1, 'PAINEL COM DUAS TOMADAS', 6, 2586.85, '50', 9.75),
  ('19000000-0000-4000-8000-000000000041', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'OS', '919002', 2, 'PAINEL COM 6 TOMADAS', 1, 3890.25, '50', 9.75);

-- 3) Mesmo rascunho, porem com IPI nao tributado (CST 51): reserva so a mercadoria.
insert into f.solicitacao_faturamento (id, tenant_id, empresa_id, status, natureza_operacao)
values ('19000000-0000-4000-8000-000000000042', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'RASCUNHO', 'VENDA');
insert into f.solicitacao_item (solicitacao_id, tenant_id, empresa_id, origem_tipo, origem_id, ordem, descricao, quantidade, valor_unitario, cst_ipi, aliquota_ipi)
values
  ('19000000-0000-4000-8000-000000000042', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'OS', '919003', 1, 'PAINEL COM DUAS TOMADAS', 6, 2586.85, '51', null),
  ('19000000-0000-4000-8000-000000000042', '19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 'OS', '919003', 2, 'PAINEL COM 6 TOMADAS', 1, 3890.25, '51', null);

do $saldo$
declare
  v record;
begin
  -- 1) Nota emitida: o faturado e o vNF, entao o pedido zera.
  select * into v from f.fn_os_saldo_a_faturar('19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 919001);
  if v.valor_faturado <> 21303.96 then
    raise exception 'Nota com IPI: faturado deveria ser 21303.96 e veio %.', v.valor_faturado;
  end if;
  if v.saldo <> 0 then
    raise exception 'Nota com IPI: saldo deveria zerar e veio % (era o residual do imposto).', v.saldo;
  end if;

  -- 2) Rascunho com IPI: reserva na mesma moeda do faturado.
  select * into v from f.fn_os_saldo_a_faturar('19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 919002);
  if v.valor_reservado <> 21303.96 then
    raise exception 'Rascunho com IPI: reservado deveria ser 21303.96 e veio %.', v.valor_reservado;
  end if;
  if v.saldo <> 0 then
    raise exception 'Rascunho com IPI: saldo deveria zerar e veio %.', v.saldo;
  end if;

  -- 3) Sem IPI tributado nao ha o que somar: reserva so a mercadoria.
  select * into v from f.fn_os_saldo_a_faturar('19000000-0000-4000-8000-000000000010', '19000000-0000-4000-8000-000000000020', 919003);
  if v.valor_reservado <> 19411.35 then
    raise exception 'Rascunho CST 51: reservado deveria ser 19411.35 e veio %.', v.valor_reservado;
  end if;
  if v.saldo <> 1892.61 then
    raise exception 'Rascunho CST 51: saldo deveria ser 1892.61 e veio %.', v.saldo;
  end if;
end;
$saldo$;

rollback;
