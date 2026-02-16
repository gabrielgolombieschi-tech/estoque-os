-- Force reset of RLS policies for m.orcamento_item
--
-- Use when you still get:
--   "new row violates row-level security policy for table \"orcamento_item\""
-- after applying other migrations.
--
-- This script drops ALL existing policies on m.orcamento_item and recreates
-- command-specific policies that allow soft delete (UPDATE setting deleted_at).

BEGIN;

ALTER TABLE m.orcamento_item ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'm'
      AND tablename  = 'orcamento_item'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON m.orcamento_item', pol.policyname);
  END LOOP;
END $$;

-- SELECT: only non-deleted rows in current tenant/empresa with comercial access
CREATE POLICY orcamento_item_select
  ON m.orcamento_item
  FOR SELECT
  TO authenticated
  USING (
    tenant_id = public.current_tenant_id()
    AND empresa_id = public.current_empresa_id()
    AND c.has_comercial_access()
    AND deleted_at IS NULL
  );

-- INSERT: require deleted_at IS NULL
CREATE POLICY orcamento_item_insert
  ON m.orcamento_item
  FOR INSERT
  TO authenticated
  WITH CHECK (
    tenant_id = public.current_tenant_id()
    AND empresa_id = public.current_empresa_id()
    AND c.has_comercial_access()
    AND deleted_at IS NULL
  );

-- UPDATE: allow soft delete (do not enforce deleted_at IS NULL in WITH CHECK)
CREATE POLICY orcamento_item_update
  ON m.orcamento_item
  FOR UPDATE
  TO authenticated
  USING (
    tenant_id = public.current_tenant_id()
    AND empresa_id = public.current_empresa_id()
    AND c.has_comercial_access()
    AND deleted_at IS NULL
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
    AND empresa_id = public.current_empresa_id()
    AND c.has_comercial_access()
  );

-- DELETE (hard delete): keep limited to visible (non-deleted) rows
CREATE POLICY orcamento_item_delete
  ON m.orcamento_item
  FOR DELETE
  TO authenticated
  USING (
    tenant_id = public.current_tenant_id()
    AND empresa_id = public.current_empresa_id()
    AND c.has_comercial_access()
    AND deleted_at IS NULL
  );

COMMIT;
