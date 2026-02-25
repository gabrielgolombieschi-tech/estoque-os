-- Diagnostic fix: remove public.can() from apontamentos_horas SELECT policy.
-- If this removes stack depth errors, recursion is coming from public.can()/current_tenant_id()/permission stack.

BEGIN;
DROP POLICY IF EXISTS "apontamentos_horas_select" ON public.apontamentos_horas;
CREATE POLICY "apontamentos_horas_select" ON public.apontamentos_horas
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.empresa_memberships em
      WHERE em.user_id = auth.uid()
        AND em.tenant_id = apontamentos_horas.tenant_id
        AND em.empresa_id = apontamentos_horas.empresa_id
        AND em.status IN ('active','ativo')
    )
  );
COMMIT;
NOTIFY pgrst, 'reload schema';
