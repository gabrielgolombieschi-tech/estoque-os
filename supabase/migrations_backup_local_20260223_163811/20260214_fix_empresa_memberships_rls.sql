BEGIN;

-- Fix RLS policy for empresa_memberships SELECT to allow coordenadores and other non-admin roles
-- to view their own empresa memberships
DROP POLICY IF EXISTS empresa_memberships_select ON public.empresa_memberships;

CREATE POLICY empresa_memberships_select ON public.empresa_memberships
  FOR SELECT
  USING (
    -- Own membership (sempre pode ver)
    user_id = auth.uid()
    OR
    -- Tenant admins podem ver todos as memberships do tenant
    EXISTS (
      SELECT 1
      FROM public.tenant_memberships tm
      WHERE tm.user_id = auth.uid()
        AND tm.tenant_id = empresa_memberships.tenant_id
        AND tm.status = 'active'
        AND tm.role = 'admin'
    )
    OR
    -- Coordenadores e outros roles do tenant podem listar empresas
    EXISTS (
      SELECT 1
      FROM public.tenant_memberships tm
      WHERE tm.user_id = auth.uid()
        AND tm.tenant_id = empresa_memberships.tenant_id
        AND tm.status = 'active'
        AND tm.role != 'guest'
    )
  );

COMMIT;
