-- Simplificar RLS para clientes e ordens_servico (evitar recursion / can())
-- Fix para erro 500 no PostgREST

begin;

-- CLIENTES
alter table public.clientes enable row level security;

-- Remove policies antigas
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='clientes' LOOP
    EXECUTE format('drop policy if exists %I on public.clientes', r.policyname);
  END LOOP;
END $$;

-- Policies simples por tenant+empresa
create policy clientes_select
on public.clientes
for select
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
);

create policy clientes_insert
on public.clientes
for insert
to authenticated
with check (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
);

create policy clientes_update
on public.clientes
for update
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
)
with check (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
);

create policy clientes_delete
on public.clientes
for delete
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
);

-- ORDENS_SERVICO
alter table public.ordens_servico enable row level security;

-- Remove policies antigas
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='ordens_servico' LOOP
    EXECUTE format('drop policy if exists %I on public.ordens_servico', r.policyname);
  END LOOP;
END $$;

create policy ordens_servico_select
on public.ordens_servico
for select
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
);

create policy ordens_servico_insert
on public.ordens_servico
for insert
to authenticated
with check (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
);

create policy ordens_servico_update
on public.ordens_servico
for update
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
)
with check (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
);

create policy ordens_servico_delete
on public.ordens_servico
for delete
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
);

commit;
