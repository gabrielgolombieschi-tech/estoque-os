-- Fix conflicting/legacy policies that still reference current_tenant_id/current_empresa_id
-- These legacy policies can cause stack depth recursion via current_empresa_id()

-- Ensure RLS enabled
ALTER TABLE public.apontamentos_horas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.colaboradores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tipos_horas ENABLE ROW LEVEL SECURITY;

-- Drop legacy apontamentos_horas policies
DROP POLICY IF EXISTS "apontamentos_select" ON public.apontamentos_horas;
DROP POLICY IF EXISTS "apontamentos_write" ON public.apontamentos_horas;

-- Drop any existing simplified policies (recreate below)
DROP POLICY IF EXISTS "apontamentos_horas_select" ON public.apontamentos_horas;
DROP POLICY IF EXISTS "apontamentos_horas_insert" ON public.apontamentos_horas;
DROP POLICY IF EXISTS "apontamentos_horas_update" ON public.apontamentos_horas;
DROP POLICY IF EXISTS "apontamentos_horas_delete" ON public.apontamentos_horas;

-- Drop legacy colaboradores policies
DROP POLICY IF EXISTS "colaboradores_select" ON public.colaboradores;
DROP POLICY IF EXISTS "colaboradores_insert" ON public.colaboradores;
DROP POLICY IF EXISTS "colaboradores_update" ON public.colaboradores;
DROP POLICY IF EXISTS "colaboradores_delete" ON public.colaboradores;

-- Drop any existing simplified policies (recreate below)
DROP POLICY IF EXISTS "colaboradores_select" ON public.colaboradores;
DROP POLICY IF EXISTS "colaboradores_insert" ON public.colaboradores;
DROP POLICY IF EXISTS "colaboradores_update" ON public.colaboradores;
DROP POLICY IF EXISTS "colaboradores_delete" ON public.colaboradores;

-- Drop legacy tipos_horas policies
DROP POLICY IF EXISTS "tipos_horas_select" ON public.tipos_horas;
DROP POLICY IF EXISTS "tipos_horas_insert" ON public.tipos_horas;
DROP POLICY IF EXISTS "tipos_horas_update" ON public.tipos_horas;
DROP POLICY IF EXISTS "tipos_horas_delete" ON public.tipos_horas;
DROP POLICY IF EXISTS "tipos_horas_perm_select" ON public.tipos_horas;

-- Drop any existing simplified policies (recreate below)
DROP POLICY IF EXISTS "tipos_horas_select" ON public.tipos_horas;
DROP POLICY IF EXISTS "tipos_horas_insert" ON public.tipos_horas;
DROP POLICY IF EXISTS "tipos_horas_update" ON public.tipos_horas;
DROP POLICY IF EXISTS "tipos_horas_delete" ON public.tipos_horas;

-- Recreate simplified policies (permission-only)
CREATE POLICY "apontamentos_horas_select" ON public.apontamentos_horas
  FOR SELECT
  USING (public.can('read', 'apontamentos'));

CREATE POLICY "apontamentos_horas_insert" ON public.apontamentos_horas
  FOR INSERT
  WITH CHECK (public.can('create', 'apontamentos'));

CREATE POLICY "apontamentos_horas_update" ON public.apontamentos_horas
  FOR UPDATE
  USING (public.can('update', 'apontamentos'))
  WITH CHECK (public.can('update', 'apontamentos'));

CREATE POLICY "apontamentos_horas_delete" ON public.apontamentos_horas
  FOR DELETE
  USING (public.can('delete', 'apontamentos'));

CREATE POLICY "colaboradores_select" ON public.colaboradores
  FOR SELECT
  USING (public.can('read', 'colaboradores'));

CREATE POLICY "colaboradores_insert" ON public.colaboradores
  FOR INSERT
  WITH CHECK (public.can('create', 'colaboradores'));

CREATE POLICY "colaboradores_update" ON public.colaboradores
  FOR UPDATE
  USING (public.can('update', 'colaboradores'))
  WITH CHECK (public.can('update', 'colaboradores'));

CREATE POLICY "colaboradores_delete" ON public.colaboradores
  FOR DELETE
  USING (public.can('delete', 'colaboradores'));

CREATE POLICY "tipos_horas_select" ON public.tipos_horas
  FOR SELECT
  USING (public.can('read', 'tipos_horas'));

CREATE POLICY "tipos_horas_insert" ON public.tipos_horas
  FOR INSERT
  WITH CHECK (public.can('create', 'tipos_horas'));

CREATE POLICY "tipos_horas_update" ON public.tipos_horas
  FOR UPDATE
  USING (public.can('update', 'tipos_horas'))
  WITH CHECK (public.can('update', 'tipos_horas'));

CREATE POLICY "tipos_horas_delete" ON public.tipos_horas
  FOR DELETE
  USING (public.can('delete', 'tipos_horas'));