-- Allow apontamentos_horas SELECT for users that are members of the empresa/tenant

DROP POLICY IF EXISTS "apontamentos_horas_select" ON public.apontamentos_horas;

CREATE POLICY "apontamentos_horas_select" ON public.apontamentos_horas
  FOR SELECT
  USING (
    public.can('read', 'apontamentos')
    OR public.can('create', 'apontamentos')
    OR public.can('update', 'apontamentos')
    OR public.can('delete', 'apontamentos')
    OR EXISTS (
      SELECT 1
      FROM public.empresa_memberships em
      WHERE em.user_id = auth.uid()
        AND em.tenant_id = apontamentos_horas.tenant_id
        AND em.empresa_id = apontamentos_horas.empresa_id
        AND em.status IN ('active','ativo')
    )
  );
