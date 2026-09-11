\set ON_ERROR_STOP on

-- Saldo a faturar conta a NFS-e pelo bruto do servico (11/09/2026, OS 139 / pedido WEG
-- Tintas 4518572701). O liquido da nota tem as retencoes descontadas, e retencao e
-- imposto da Segau, nao desconto no preco: abater o liquido deixava saldo sobrando.
-- E a nota importada precisa aparecer na lista da OS, que so mostrava nota emitida.

begin;

insert into public.tenants (id, nome, ativo) values ('19100000-0000-4000-8000-000000000010', 'Tenant saldo NFS-e', true);
insert into c.tenant (id, codigo, nome, ativo) values ('19100000-0000-4000-8000-000000000010', 'SALDO-NFSE', 'Tenant saldo NFS-e', true);
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo)
values ('19100000-0000-4000-8000-000000000020', '19100000-0000-4000-8000-000000000010', 'NFSE-A', 'Empresa saldo NFS-e', 'Empresa saldo NFS-e', '19100000000100', true);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo)
values ('19100000-0000-4000-8000-000000000020', '19100000-0000-4000-8000-000000000010', '19100000000100', 'Empresa saldo NFS-e', 'Empresa saldo NFS-e', true);

insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social)
values (919101, '19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020', 'CLIENTE NFSE', '19111111000272', 'CLIENTE NFSE LTDA');

-- A nota emitida dispara o AR automatico.
insert into f.plano_contas (tenant_id, codigo, nome, natureza, tipo, ativo)
values ('19100000-0000-4000-8000-000000000010', '3.01', 'RECEITA DE SERVICOS', 'CREDITO', 'ANALITICA', true);

insert into public.ordens_servico (id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id,
  status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado)
values
  (919101, 'NFSE-1', 'CLIENTE NFSE', 919101, 'em_andamento', 919101, '19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020', 'em_andamento', 'OS', 'OS-NFSE-001', 1, 'Metade do pedido faturada', 175000.00),
  (919102, 'NFSE-2', 'CLIENTE NFSE', 919101, 'concluida', 919102, '19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020', 'concluida', 'OS', 'OS-NFSE-002', 1, 'Pedido faturado por inteiro', 10500.00);

-- 1) Metade de um pedido de 175.000,00: 87.500,00 de servico, 81.812,50 liquido.
-- 2) Pedido de 10.500,00 faturado por inteiro, com 1.170,75 de retencoes.
insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza,
  os_id_import, cliente_id, nfse_status, valor_servicos, valor_total)
values
  ('19100000-0000-4000-8000-000000000031', '19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020',
   'NFSE-SALDO-BRUTO-0001', 'NFSE', 'A1', '910001', 'SAIDA', 'SERVICO', 919101, 919101, 'EMITIDA', 87500.00, 81812.50),
  ('19100000-0000-4000-8000-000000000032', '19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020',
   'NFSE-SALDO-BRUTO-0002', 'NFSE', 'A1', '910002', 'SAIDA', 'SERVICO', 919102, 919101, 'EMITIDA', 10500.00, 9329.25);

do $saldo$
declare
  v record;
begin
  -- A regra isolada: NFS-e pelo bruto, NF-e pelo vNF, e bruto ausente cai no total.
  if f.fn_documento_valor_faturado('NFSE', 81812.50, 87500.00, null) <> 87500.00 then
    raise exception 'NFS-e deveria valer o bruto 87500.00.';
  end if;
  if f.fn_documento_valor_faturado('NFSE', 6700.00, 0, null) <> 6700.00 then
    raise exception 'NFS-e sem bruto deveria cair no valor_total.';
  end if;
  if f.fn_documento_valor_faturado('55', 21303.96, 0, 19411.35) <> 21303.96 then
    raise exception 'NF-e deveria valer o vNF 21303.96.';
  end if;
  if f.fn_documento_valor_faturado('55', null, null, 19411.35) <> 19411.35 then
    raise exception 'NF-e sem vNF deveria cair no valor_produtos.';
  end if;

  -- 1) O caso da OS 139: sobram 87.500,00, nao 93.187,50.
  select * into v from f.fn_os_saldo_a_faturar('19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020', 919101);
  if v.valor_faturado <> 87500.00 then
    raise exception 'NFS-e com retencao: faturado deveria ser 87500.00 e veio %.', v.valor_faturado;
  end if;
  if v.saldo <> 87500.00 then
    raise exception 'NFS-e com retencao: saldo deveria ser 87500.00 e veio % (o liquido deixava 93187.50).', v.saldo;
  end if;

  -- 2) Pedido faturado por inteiro zera — antes sobrava a retencao como saldo.
  select * into v from f.fn_os_saldo_a_faturar('19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020', 919102);
  if v.saldo <> 0 then
    raise exception 'Pedido faturado por inteiro: saldo deveria zerar e veio % (era a retencao).', v.saldo;
  end if;
  if not f.fn_os_pronta_para_faturada('19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020', 919102) then
    raise exception 'Pedido faturado por inteiro deveria estar pronto para faturada.';
  end if;

  -- 3) A nota importada, sem emissao pela Focus, aparece em "Notas desta OS".
  select * into v from f.fn_os_notas('19100000-0000-4000-8000-000000000010', '19100000-0000-4000-8000-000000000020', 919101);
  if v.documento_fiscal_id is distinct from '19100000-0000-4000-8000-000000000031'::uuid then
    raise exception 'Nota importada e vinculada deveria aparecer nas notas da OS.';
  end if;
  if v.ambiente <> 'PRODUCAO' or v.emissao_status <> 'IMPORTADA' or v.modelo <> 'NFSE' then
    raise exception 'Nota importada deveria sair como PRODUCAO/IMPORTADA/NFSE e veio %/%/%.', v.ambiente, v.emissao_status, v.modelo;
  end if;
  -- O valor da lista e o mesmo que o saldo abate, para a soma fechar com o "ja faturado".
  if v.valor_total <> 87500.00 then
    raise exception 'Nota importada deveria aparecer pelo bruto 87500.00 e veio %.', v.valor_total;
  end if;
end;
$saldo$;

rollback;
