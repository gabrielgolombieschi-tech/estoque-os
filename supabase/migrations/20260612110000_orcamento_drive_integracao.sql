begin;

alter table m.orcamento
  add column if not exists drive_folder_id text,
  add column if not exists drive_folder_url text,
  add column if not exists drive_doc_id text,
  add column if not exists drive_doc_url text,
  add column if not exists drive_sync_status text,
  add column if not exists drive_sync_error text,
  add column if not exists drive_sync_requested_at timestamptz,
  add column if not exists drive_synced_at timestamptz;

create index if not exists idx_orcamento__drive_sync_status
  on m.orcamento (tenant_id, empresa_id, drive_sync_status)
  where drive_sync_status is not null;

create index if not exists idx_orcamento__drive_folder_id
  on m.orcamento (tenant_id, empresa_id, drive_folder_id)
  where drive_folder_id is not null and btrim(drive_folder_id) <> '';

commit;
