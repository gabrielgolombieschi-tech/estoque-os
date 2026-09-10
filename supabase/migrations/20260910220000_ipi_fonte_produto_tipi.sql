-- ipi_fonte aceita PRODUTO_TIPI.
--
-- A 20260910210000 fez o IPI da revenda poder vir do cadastro do produto quando a
-- TIPI diz que o NCM e tributado, e marca a origem do dado como 'PRODUTO_TIPI' — mas
-- a check da coluna so conhecia 'PERFIL_OPERACAO' e 'FIXTURE_HOMOLOGACAO'. A emissao
-- da OV-SEG-00007-026 parou exatamente ai, com
-- "new row for relation solicitacao_item violates check constraint
--  solicitacao_item_ipi_fonte_check".
--
-- A coluna existe para dizer de onde veio o numero, e agora ha uma terceira origem
-- legitima: o cadastro fiscal do produto, conferido contra f.tipi_ncm.

alter table f.solicitacao_item
  drop constraint if exists solicitacao_item_ipi_fonte_check;

alter table f.solicitacao_item
  add constraint solicitacao_item_ipi_fonte_check
  check (
    ipi_fonte is null
    or ipi_fonte = any (array['PERFIL_OPERACAO', 'FIXTURE_HOMOLOGACAO', 'PRODUTO_TIPI'])
  );

comment on column f.solicitacao_item.ipi_fonte is
  'De onde vieram CST, cEnq e aliquota do IPI: PERFIL_OPERACAO (perfil traz os tres), PRODUTO_TIPI (cadastro do produto, com o NCM tributado em f.tipi_ncm) ou FIXTURE_HOMOLOGACAO (fixture provisoria por CFOP).';
