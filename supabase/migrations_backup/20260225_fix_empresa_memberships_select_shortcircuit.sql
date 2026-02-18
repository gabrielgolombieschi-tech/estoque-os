-- Fix: avoid stack depth recursion in empresa_memberships SELECT by forcing evaluation order
-- We always allow users to read their own membership rows without invoking other functions.

BEGIN;

DROP POLICY IF EXISTS empresa_memberships_select ON public.empresa_memberships;

CREATE POLICY empresa_memberships_select ON public.empresa_memberships
  FOR SELECT
  USING (
    case
      when user_id = auth.uid() then true
      else (
        -- Tenant admins can view all memberships in the tenant
        exists (
          select 1
          from public.tenant_memberships tm
          where tm.user_id = auth.uid()
            and tm.tenant_id = empresa_memberships.tenant_id
            and tm.status in ('active','ativo')
            and tm.role = 'admin'
        )
        or
        -- Non-guest roles can list memberships (used for empresa listing flows)
        exists (
          select 1
          from public.tenant_memberships tm
          where tm.user_id = auth.uid()
            and tm.tenant_id = empresa_memberships.tenant_id
            and tm.status in ('active','ativo')
            and tm.role != 'guest'
        )
      )
    end
  );

COMMIT;

NOTIFY pgrst, 'reload schema';
