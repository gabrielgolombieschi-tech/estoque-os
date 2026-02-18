BEGIN;

-- ============================================================================
-- Migration: Fix undefined has_permission() function
-- Data: 2026-02-17
-- Descrição: Remove policies that use the undefined has_permission() function
--            and ensure apontamentos_horas uses the correct can() function
-- ============================================================================

-- Drop the broken policies that reference has_permission()
DROP POLICY IF EXISTS apontamentos_horas_perm_select ON public.apontamentos_horas;
DROP POLICY IF EXISTS colaboradores_perm_select ON public.colaboradores;
DROP POLICY IF EXISTS tipos_horas_perm_select ON public.tipos_horas;
DROP POLICY IF EXISTS colaborador_taxas_perm_select ON public.colaborador_taxas;

-- Recreate apontamentos_horas policy with correct can() function
-- (If policy apontamentos_select already exists, this will be a duplicate but we ensure it exists)
DROP POLICY IF EXISTS apontamentos_select ON public.apontamentos_horas;

CREATE POLICY apontamentos_select
ON public.apontamentos_horas
FOR SELECT
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','read')
);

-- Recreate colaboradores policy
DROP POLICY IF EXISTS colaboradores_select ON public.colaboradores;

CREATE POLICY colaboradores_select
ON public.colaboradores
FOR SELECT
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND (
    public.can('apontamentos','read')
    OR public.can('os','read')
    OR public.can('admin','manage_users')
    OR public.can('financeiro','read')
  )
);

COMMIT;

NOTIFY pgrst, 'reload schema';
