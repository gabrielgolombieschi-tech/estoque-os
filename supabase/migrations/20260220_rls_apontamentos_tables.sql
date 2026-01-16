-- RLS policies for apontamentos_horas, colaboradores, and tipos_horas tables
-- Following simplified pattern: check can() permission only, no current_tenant_id() dependency

-- ============================================================================
-- Enable RLS on all three tables (if not already enabled)
-- ============================================================================

ALTER TABLE public.apontamentos_horas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.colaboradores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tipos_horas ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- apontamentos_horas policies
-- ============================================================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "apontamentos_horas_select" ON public.apontamentos_horas;
DROP POLICY IF EXISTS "apontamentos_horas_insert" ON public.apontamentos_horas;
DROP POLICY IF EXISTS "apontamentos_horas_update" ON public.apontamentos_horas;
DROP POLICY IF EXISTS "apontamentos_horas_delete" ON public.apontamentos_horas;

-- SELECT: Allow if user has 'read' permission on apontamentos
CREATE POLICY "apontamentos_horas_select" ON public.apontamentos_horas
  FOR SELECT
  USING (public.can('read', 'apontamentos'));

-- INSERT: Allow if user has 'create' permission on apontamentos
CREATE POLICY "apontamentos_horas_insert" ON public.apontamentos_horas
  FOR INSERT
  WITH CHECK (public.can('create', 'apontamentos'));

-- UPDATE: Allow if user has 'update' permission on apontamentos
CREATE POLICY "apontamentos_horas_update" ON public.apontamentos_horas
  FOR UPDATE
  USING (public.can('update', 'apontamentos'))
  WITH CHECK (public.can('update', 'apontamentos'));

-- DELETE: Allow if user has 'delete' permission on apontamentos
CREATE POLICY "apontamentos_horas_delete" ON public.apontamentos_horas
  FOR DELETE
  USING (public.can('delete', 'apontamentos'));

-- ============================================================================
-- colaboradores policies
-- ============================================================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "colaboradores_select" ON public.colaboradores;
DROP POLICY IF EXISTS "colaboradores_insert" ON public.colaboradores;
DROP POLICY IF EXISTS "colaboradores_update" ON public.colaboradores;
DROP POLICY IF EXISTS "colaboradores_delete" ON public.colaboradores;

-- SELECT: Allow if user has 'read' permission on colaboradores
CREATE POLICY "colaboradores_select" ON public.colaboradores
  FOR SELECT
  USING (public.can('read', 'colaboradores'));

-- INSERT: Allow if user has 'create' permission on colaboradores
CREATE POLICY "colaboradores_insert" ON public.colaboradores
  FOR INSERT
  WITH CHECK (public.can('create', 'colaboradores'));

-- UPDATE: Allow if user has 'update' permission on colaboradores
CREATE POLICY "colaboradores_update" ON public.colaboradores
  FOR UPDATE
  USING (public.can('update', 'colaboradores'))
  WITH CHECK (public.can('update', 'colaboradores'));

-- DELETE: Allow if user has 'delete' permission on colaboradores
CREATE POLICY "colaboradores_delete" ON public.colaboradores
  FOR DELETE
  USING (public.can('delete', 'colaboradores'));

-- ============================================================================
-- tipos_horas policies
-- ============================================================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "tipos_horas_select" ON public.tipos_horas;
DROP POLICY IF EXISTS "tipos_horas_insert" ON public.tipos_horas;
DROP POLICY IF EXISTS "tipos_horas_update" ON public.tipos_horas;
DROP POLICY IF EXISTS "tipos_horas_delete" ON public.tipos_horas;

-- SELECT: Allow if user has 'read' permission on tipos_horas
CREATE POLICY "tipos_horas_select" ON public.tipos_horas
  FOR SELECT
  USING (public.can('read', 'tipos_horas'));

-- INSERT: Allow if user has 'create' permission on tipos_horas
CREATE POLICY "tipos_horas_insert" ON public.tipos_horas
  FOR INSERT
  WITH CHECK (public.can('create', 'tipos_horas'));

-- UPDATE: Allow if user has 'update' permission on tipos_horas
CREATE POLICY "tipos_horas_update" ON public.tipos_horas
  FOR UPDATE
  USING (public.can('update', 'tipos_horas'))
  WITH CHECK (public.can('update', 'tipos_horas'));

-- DELETE: Allow if user has 'delete' permission on tipos_horas
CREATE POLICY "tipos_horas_delete" ON public.tipos_horas
  FOR DELETE
  USING (public.can('delete', 'tipos_horas'));
