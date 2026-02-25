BEGIN;

-- ============================================================================
-- Migration: Fix RLS para cliente_hh_servicos
-- Data: 2026-01-14
-- Descrição: Corrige política RLS para usar current_tenant_id() e 
--            adicionar permissões adequadas para INSERT/UPDATE
-- ============================================================================

-- Drop política antiga
DROP POLICY IF EXISTS cliente_hh_servicos_tenant_empresa_policy ON cliente_hh_servicos;
DROP POLICY IF EXISTS cliente_hh_servicos_select ON cliente_hh_servicos;
DROP POLICY IF EXISTS cliente_hh_servicos_insert ON cliente_hh_servicos;
DROP POLICY IF EXISTS cliente_hh_servicos_update ON cliente_hh_servicos;
DROP POLICY IF EXISTS cliente_hh_servicos_delete ON cliente_hh_servicos;

-- Políticas separadas por operação (mais controle e segurança)

-- SELECT: qualquer usuário do tenant com permissão de leitura
CREATE POLICY cliente_hh_servicos_select
  ON cliente_hh_servicos
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

-- INSERT: usuários com permissão de escrita
CREATE POLICY cliente_hh_servicos_insert
  ON cliente_hh_servicos
  FOR INSERT
  WITH CHECK (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
      OR public.can('apontamentos', 'write')
    )
  );

-- UPDATE: usuários com permissão de escrita
CREATE POLICY cliente_hh_servicos_update
  ON cliente_hh_servicos
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

-- DELETE: apenas admin e financeiro podem deletar
CREATE POLICY cliente_hh_servicos_delete
  ON cliente_hh_servicos
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
