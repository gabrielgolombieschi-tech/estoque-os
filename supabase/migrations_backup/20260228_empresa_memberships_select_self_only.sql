-- Emergency: simplify empresa_memberships SELECT policy to self-only.
-- This avoids touching tenant_memberships/has_permission/current_tenant_id in RLS evaluation,
-- which can cause stack depth recursion chains.

BEGIN;

DROP POLICY IF EXISTS empresa_memberships_select ON public.empresa_memberships;

CREATE POLICY empresa_memberships_select ON public.empresa_memberships
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

COMMIT;

NOTIFY pgrst, 'reload schema';
