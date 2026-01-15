BEGIN;

-- ============================================================================
-- Migration: FORCE FIX RLS para colaboradores
-- Data: 2026-01-15
-- Descrição: Remove TODAS as policies antigas e recria com sintaxe correta
-- ============================================================================

-- 1) DISABLE e ENABLE RLS para forçar refresh
-- ============================================================================

ALTER TABLE public.colaboradores DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.colaboradores ENABLE ROW LEVEL SECURITY;

-- 2) Drop TODAS as policies antigas dinamicamente
-- ============================================================================

DO $$ 
DECLARE 
    r RECORD;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = 'colaboradores' AND schemaname = 'public')
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.colaboradores';
    END LOOP;
END $$;

-- 3) Criar policies corretas
-- ============================================================================

-- SELECT: usuários com permissão apontamentos.read OU os.read
CREATE POLICY colaboradores_select
  ON public.colaboradores
  FOR SELECT
  TO authenticated
  USING (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('apontamentos', 'read')
      OR public.can('os', 'read')
      OR public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
    )
  );

-- INSERT: usuários com permissão admin
CREATE POLICY colaboradores_insert
  ON public.colaboradores
  FOR INSERT
  TO authenticated
  WITH CHECK (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
    )
  );

-- UPDATE: usuários com permissão admin
CREATE POLICY colaboradores_update
  ON public.colaboradores
  FOR UPDATE
  TO authenticated
  USING (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
    )
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
    )
  );

-- DELETE: somente admin
CREATE POLICY colaboradores_delete
  ON public.colaboradores
  FOR DELETE
  TO authenticated
  USING (
    tenant_id = public.current_tenant_id()
    AND public.can('admin', 'manage_users')
  );

COMMIT;

NOTIFY pgrst, 'reload schema';
