BEGIN;

-- Drop old policies that use has_permission (deprecated)
DROP POLICY IF EXISTS apontamentos_horas_perm_select ON public.apontamentos_horas;
DROP POLICY IF EXISTS colaboradores_perm_select ON public.colaboradores;
DROP POLICY IF EXISTS tipos_horas_perm_select ON public.tipos_horas;
DROP POLICY IF EXISTS colaborador_taxas_perm_select ON public.colaborador_taxas;

-- Apontamentos: require apontamentos.read permission
CREATE POLICY apontamentos_horas_select ON public.apontamentos_horas
  FOR SELECT
  TO authenticated
  USING (
    tenant_id = public.current_tenant_id()
    AND public.can('apontamentos', 'read')
  );

CREATE POLICY apontamentos_horas_insert ON public.apontamentos_horas
  FOR INSERT
  TO authenticated
  WITH CHECK (
    tenant_id = public.current_tenant_id()
    AND public.can('apontamentos', 'write')
  );

CREATE POLICY apontamentos_horas_update ON public.apontamentos_horas
  FOR UPDATE
  TO authenticated
  USING (
    tenant_id = public.current_tenant_id()
    AND public.can('apontamentos', 'write')
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
    AND public.can('apontamentos', 'write')
  );

CREATE POLICY apontamentos_horas_delete ON public.apontamentos_horas
  FOR DELETE
  TO authenticated
  USING (
    tenant_id = public.current_tenant_id()
    AND public.can('apontamentos', 'delete')
  );

-- Colaboradores: accessible to users with apontamentos permissions
DROP POLICY IF EXISTS colaboradores_select ON public.colaboradores;
CREATE POLICY colaboradores_select ON public.colaboradores
  FOR SELECT
  TO authenticated
  USING (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('apontamentos', 'read')
      OR public.can('os', 'read')
    )
  );

-- Tipos de horas: accessible to users with apontamentos permissions
DROP POLICY IF EXISTS tipos_horas_select ON public.tipos_horas;
CREATE POLICY tipos_horas_select ON public.tipos_horas
  FOR SELECT
  TO authenticated
  USING (
    tenant_id = public.current_tenant_id()
    AND public.can('apontamentos', 'read')
  );

-- Colaborador taxas: accessible to users with apontamentos permissions  
DROP POLICY IF EXISTS colaborador_taxas_select ON public.colaborador_taxas;
CREATE POLICY colaborador_taxas_select ON public.colaborador_taxas
  FOR SELECT
  TO authenticated
  USING (
    tenant_id = public.current_tenant_id()
    AND public.can('apontamentos', 'read')
  );

COMMIT;
