-- Broaden SELECT permissions for apontamentos-related tables

-- apontamentos_horas: allow any apontamentos permission to read
DROP POLICY IF EXISTS "apontamentos_horas_select" ON public.apontamentos_horas;
CREATE POLICY "apontamentos_horas_select" ON public.apontamentos_horas
  FOR SELECT
  USING (
    public.can('read', 'apontamentos')
    OR public.can('create', 'apontamentos')
    OR public.can('update', 'apontamentos')
    OR public.can('delete', 'apontamentos')
  );

-- colaboradores: allow apontamentos/os/admin/financeiro readers
DROP POLICY IF EXISTS "colaboradores_select" ON public.colaboradores;
CREATE POLICY "colaboradores_select" ON public.colaboradores
  FOR SELECT
  USING (
    public.can('read', 'colaboradores')
    OR public.can('read', 'apontamentos')
    OR public.can('create', 'apontamentos')
    OR public.can('update', 'apontamentos')
    OR public.can('os', 'read')
    OR public.can('financeiro', 'read')
    OR public.can('admin', 'manage_users')
  );

-- tipos_horas: allow apontamentos readers/writers
DROP POLICY IF EXISTS "tipos_horas_select" ON public.tipos_horas;
CREATE POLICY "tipos_horas_select" ON public.tipos_horas
  FOR SELECT
  USING (
    public.can('read', 'tipos_horas')
    OR public.can('read', 'apontamentos')
    OR public.can('create', 'apontamentos')
    OR public.can('update', 'apontamentos')
  );
