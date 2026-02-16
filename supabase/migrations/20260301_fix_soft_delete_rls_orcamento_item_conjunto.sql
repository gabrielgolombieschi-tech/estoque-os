-- Allow soft delete (UPDATE setting deleted_at) without breaking the existing "*_all" policies
-- that enforce deleted_at IS NULL in WITH CHECK (which would otherwise block soft delete).
--
-- This migration adds dedicated UPDATE policies that:
-- - only allow updating rows that are currently not deleted (USING ... deleted_at IS NULL)
-- - allow the updated row to have deleted_at set (WITH CHECK without deleted_at constraint)
--
-- IMPORTANT: These policies still enforce tenant/empresa scoping via current_tenant_id/current_empresa_id
-- and require comercial access.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'm'
      AND tablename  = 'orcamento_item'
      AND policyname = 'orcamento_item_soft_delete'
  ) THEN
    CREATE POLICY orcamento_item_soft_delete
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
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'c'
      AND tablename  = 'conjunto'
      AND policyname = 'conjunto_soft_delete'
  ) THEN
    CREATE POLICY conjunto_soft_delete
      ON c.conjunto
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
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'c'
      AND tablename  = 'conjunto_item'
      AND policyname = 'conjunto_item_soft_delete'
  ) THEN
    CREATE POLICY conjunto_item_soft_delete
      ON c.conjunto_item
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
  END IF;
END $$;
