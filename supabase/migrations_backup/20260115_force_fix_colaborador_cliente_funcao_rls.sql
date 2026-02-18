BEGIN;

-- ============================================================================
-- Migration: FORCE FIX RLS para colaborador_cliente_funcao
-- Data: 2026-01-15
-- Descrição: Força a recriação completa das políticas RLS para remover
--            qualquer referência antiga a current_setting('app.current_tenant_id')
-- ============================================================================

-- Desabilitar e reabilitar RLS para garantir limpeza
ALTER TABLE public.colaborador_cliente_funcao DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.colaborador_cliente_funcao ENABLE ROW LEVEL SECURITY;

-- Drop TODAS as policies (forçando limpeza completa)
DO $$ 
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = 'colaborador_cliente_funcao' AND schemaname = 'public')
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.colaborador_cliente_funcao';
    END LOOP;
END $$;

-- SELECT: qualquer usuário do tenant com permissão HH.read
CREATE POLICY colaborador_cliente_funcao_select
  ON public.colaborador_cliente_funcao
  FOR SELECT
  USING (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
      OR public.can('apontamentos', 'read')
      OR public.can('apontamentos', 'write')
    )
  );

-- INSERT: usuários com permissão HH.write
CREATE POLICY colaborador_cliente_funcao_insert
  ON public.colaborador_cliente_funcao
  FOR INSERT
  WITH CHECK (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
      OR public.can('apontamentos', 'write')
    )
  );

-- UPDATE: usuários com permissão HH.write
CREATE POLICY colaborador_cliente_funcao_update
  ON public.colaborador_cliente_funcao
  FOR UPDATE
  USING (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
      OR public.can('apontamentos', 'write')
    )
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
      OR public.can('apontamentos', 'write')
    )
  );

-- DELETE: usuários com permissão HH.write (admin ou financeiro)
CREATE POLICY colaborador_cliente_funcao_delete
  ON public.colaborador_cliente_funcao
  FOR DELETE
  USING (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
    )
  );

COMMIT;

NOTIFY pgrst, 'reload schema';
