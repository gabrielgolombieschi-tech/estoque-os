-- Emergency fix: remove all RLS policies from public.apontamentos_horas and recreate
-- membership-only policies to eliminate stack depth recursion.
--
-- This avoids calling public.can(), public.has_permission(), current_tenant_id(), etc.

BEGIN;

DO $$
DECLARE r record;
BEGIN
  IF to_regclass('public.apontamentos_horas') IS NOT NULL THEN
    FOR r IN
      SELECT policyname
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = 'apontamentos_horas'
    LOOP
      EXECUTE format('drop policy if exists %I on public.apontamentos_horas', r.policyname);
    END LOOP;
  END IF;
END$$;

ALTER TABLE public.apontamentos_horas ENABLE ROW LEVEL SECURITY;

-- SELECT: allowed when user is an active member of the row's tenant+empresa
CREATE POLICY apontamentos_horas_select
ON public.apontamentos_horas
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.empresa_memberships em
    WHERE em.user_id = auth.uid()
      AND em.tenant_id = tenant_id
      AND em.empresa_id = empresa_id
      AND em.status IN ('active','ativo')
  )
);

-- INSERT: allowed only into tenant+empresa the user belongs to
CREATE POLICY apontamentos_horas_insert
ON public.apontamentos_horas
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.empresa_memberships em
    WHERE em.user_id = auth.uid()
      AND em.tenant_id = tenant_id
      AND em.empresa_id = empresa_id
      AND em.status IN ('active','ativo')
  )
);

-- UPDATE: allowed only within tenant+empresa the user belongs to
CREATE POLICY apontamentos_horas_update
ON public.apontamentos_horas
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.empresa_memberships em
    WHERE em.user_id = auth.uid()
      AND em.tenant_id = tenant_id
      AND em.empresa_id = empresa_id
      AND em.status IN ('active','ativo')
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.empresa_memberships em
    WHERE em.user_id = auth.uid()
      AND em.tenant_id = tenant_id
      AND em.empresa_id = empresa_id
      AND em.status IN ('active','ativo')
  )
);

-- DELETE: allowed only within tenant+empresa the user belongs to
CREATE POLICY apontamentos_horas_delete
ON public.apontamentos_horas
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.empresa_memberships em
    WHERE em.user_id = auth.uid()
      AND em.tenant_id = tenant_id
      AND em.empresa_id = empresa_id
      AND em.status IN ('active','ativo')
  )
);

COMMIT;

NOTIFY pgrst, 'reload schema';
