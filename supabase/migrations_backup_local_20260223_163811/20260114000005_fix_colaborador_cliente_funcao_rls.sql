BEGIN;

-- ============================================================================
-- Migration: Fix RLS para colaborador_cliente_funcao
-- Data: 2026-01-14
-- Descrição: Adiciona permissão apontamentos.write às políticas RLS
-- ============================================================================

-- Drop policies antigas
DROP POLICY IF EXISTS colaborador_cliente_funcao_select ON public.colaborador_cliente_funcao;
DROP POLICY IF EXISTS colaborador_cliente_funcao_insert ON public.colaborador_cliente_funcao;
DROP POLICY IF EXISTS colaborador_cliente_funcao_update ON public.colaborador_cliente_funcao;
DROP POLICY IF EXISTS colaborador_cliente_funcao_delete ON public.colaborador_cliente_funcao;

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
