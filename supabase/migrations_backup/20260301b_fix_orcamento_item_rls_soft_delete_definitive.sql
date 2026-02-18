-- Definitive fix: replace FOR ALL policy that enforces (deleted_at IS NULL) in WITH CHECK
-- (which blocks soft delete) with command-specific policies.
--
-- Symptoms:
--   PATCH/UPDATE setting deleted_at returns 403 with:
--     "new row violates row-level security policy for table \"orcamento_item\""
--
-- Root cause:
--   Existing policy `orcamento_item_all` has WITH CHECK (... AND deleted_at IS NULL).
--   On UPDATE, WITH CHECK validates the *new* row, so setting deleted_at breaks it.

DO $$
BEGIN
  -- Drop legacy permissive policy (covers ALL commands)
  IF EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'm'
      AND tablename  = 'orcamento_item'
      AND policyname = 'orcamento_item_all'
  ) THEN
    EXECUTE 'DROP POLICY orcamento_item_all ON m.orcamento_item';
  END IF;

  -- Drop earlier attempt policy if present
  IF EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'm'
      AND tablename  = 'orcamento_item'
      AND policyname = 'orcamento_item_soft_delete'
  ) THEN
    EXECUTE 'DROP POLICY orcamento_item_soft_delete ON m.orcamento_item';
  END IF;

  -- SELECT: only non-deleted rows in current tenant/empresa with comercial access
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'm'
      AND tablename  = 'orcamento_item'
      AND policyname = 'orcamento_item_select'
  ) THEN
    EXECUTE $SQL$
      CREATE POLICY orcamento_item_select
        ON m.orcamento_item
        FOR SELECT
        TO authenticated
        USING (
          tenant_id = public.current_tenant_id()
          AND empresa_id = public.current_empresa_id()
          AND c.has_comercial_access()
          AND deleted_at IS NULL
        )
    $SQL$;
  END IF;

  -- INSERT: require deleted_at IS NULL
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'm'
      AND tablename  = 'orcamento_item'
      AND policyname = 'orcamento_item_insert'
  ) THEN
    EXECUTE $SQL$
      CREATE POLICY orcamento_item_insert
        ON m.orcamento_item
        FOR INSERT
        TO authenticated
        WITH CHECK (
          tenant_id = public.current_tenant_id()
          AND empresa_id = public.current_empresa_id()
          AND c.has_comercial_access()
          AND deleted_at IS NULL
        )
    $SQL$;
  END IF;

  -- UPDATE: allow soft delete by NOT enforcing deleted_at IS NULL in WITH CHECK
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'm'
      AND tablename  = 'orcamento_item'
      AND policyname = 'orcamento_item_update'
  ) THEN
    EXECUTE $SQL$
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
        )
    $SQL$;
  END IF;

  -- DELETE (hard delete): keep blocked by requiring row visibility (non-deleted only)
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'm'
      AND tablename  = 'orcamento_item'
      AND policyname = 'orcamento_item_delete'
  ) THEN
    EXECUTE $SQL$
      CREATE POLICY orcamento_item_delete
        ON m.orcamento_item
        FOR DELETE
        TO authenticated
        USING (
          tenant_id = public.current_tenant_id()
          AND empresa_id = public.current_empresa_id()
          AND c.has_comercial_access()
          AND deleted_at IS NULL
        )
    $SQL$;
  END IF;
END $$;
