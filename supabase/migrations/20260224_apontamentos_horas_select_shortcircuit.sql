-- Fix: avoid stack depth recursion by short-circuiting membership check before calling public.can()
-- Also fixes public.can() argument order (resource, action).

BEGIN;
DROP POLICY IF EXISTS "apontamentos_horas_select" ON public.apontamentos_horas;
CREATE POLICY "apontamentos_horas_select" ON public.apontamentos_horas
  FOR SELECT
  USING (
    case
      when exists (
        select 1
        from public.empresa_memberships em
        where em.user_id = auth.uid()
          and em.tenant_id = apontamentos_horas.tenant_id
          and em.empresa_id = apontamentos_horas.empresa_id
          and em.status in ('active','ativo')
      ) then true
      else (
        public.can('apontamentos', 'read')
        or public.can('apontamentos', 'create')
        or public.can('apontamentos', 'update')
        or public.can('apontamentos', 'delete')
      )
    end
  );
COMMIT;
NOTIFY pgrst, 'reload schema';
