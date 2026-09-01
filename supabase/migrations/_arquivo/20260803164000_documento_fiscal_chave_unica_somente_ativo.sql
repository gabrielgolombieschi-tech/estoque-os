begin;

-- Documento fiscal usa soft delete. Uma chave cancelada precisa permanecer no
-- historico, mas nao pode impedir a reimportacao de uma NF de entrada estornada.
alter table f.documento_fiscal
  drop constraint if exists uq_documento_fiscal__tenant_chave;

create unique index if not exists uq_documento_fiscal__tenant_chave_ativo
  on f.documento_fiscal (tenant_id, chave_acesso)
  where deleted_at is null;

commit;

