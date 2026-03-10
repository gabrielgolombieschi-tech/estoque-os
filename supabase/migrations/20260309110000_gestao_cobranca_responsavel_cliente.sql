begin;

alter table if exists f.gestao_cobranca_os
  add column if not exists responsavel_cliente_nome text;

comment on column f.gestao_cobranca_os.responsavel_cliente_nome is
  'Nome do contato do cliente responsável pela cobrança/pagamento da OS.';

commit;
