begin;

-- import_nf_entrada registra este diagnostico quando recebe uma entrada sem
-- XML. A funcao ja existia no baseline, mas a tabela referenciada nao; isso
-- fazia a importacao sem XML abortar antes de criar XML_FALTANDO no ledger.
create table if not exists public.xml_import_errors (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  documento_fiscal_id uuid,
  tipo text not null check (btrim(tipo) <> ''),
  detalhe text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint xml_import_errors_scope_uq
    unique nulls not distinct (tenant_id, documento_fiscal_id, tipo)
);

create index if not exists xml_import_errors_abertos_idx
  on public.xml_import_errors (tenant_id, tipo, created_at desc)
  where resolved_at is null;

alter table public.xml_import_errors enable row level security;

drop policy if exists xml_import_errors_select_tenant on public.xml_import_errors;
create policy xml_import_errors_select_tenant
on public.xml_import_errors
for select
to authenticated
using (tenant_id = public.current_tenant_id());

revoke all on table public.xml_import_errors from public, anon, authenticated;
grant select on table public.xml_import_errors to authenticated;
grant select, insert, update, delete on table public.xml_import_errors to service_role;

comment on table public.xml_import_errors is
  'Diagnosticos tecnicos da importacao XML, isolados por tenant; a escrita ocorre por RPC SECURITY DEFINER.';

notify pgrst, 'reload schema';

commit;
