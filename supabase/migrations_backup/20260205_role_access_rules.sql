BEGIN;

CREATE TABLE IF NOT EXISTS public.role_access_rules (
  role_id uuid not null,
  resource text not null,
  action text not null,
  created_at timestamptz not null default now(),
  primary key (role_id, resource, action)
);

DO $$
BEGIN
  IF to_regclass('public.roles') IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint
      WHERE conname = 'role_access_rules_role_id_fkey'
    ) THEN
      ALTER TABLE public.role_access_rules
        ADD CONSTRAINT role_access_rules_role_id_fkey
        FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;
    END IF;
  END IF;
END$$;

ALTER TABLE public.role_access_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS role_access_rules_admin ON public.role_access_rules;
CREATE POLICY role_access_rules_admin
ON public.role_access_rules
FOR ALL
TO authenticated
USING (public.has_permission('admin.users.manage'::text))
WITH CHECK (public.has_permission('admin.users.manage'::text));

CREATE OR REPLACE FUNCTION public.can(p_resource text, p_action text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.tenant_memberships tm
    JOIN public.membership_roles mr
      ON mr.membership_id = tm.id
    JOIN public.roles r
      ON r.id = mr.role_id
    JOIN public.role_access_rules ar
      ON ar.role_id = r.id
    WHERE tm.user_id = auth.uid()
      AND tm.tenant_id = public.current_tenant_id()
      AND tm.status IN ('active', 'ativo')
      AND (r.tenant_id IS NULL OR r.tenant_id = tm.tenant_id)
      AND ar.resource = p_resource
      AND ar.action = p_action
  );
$$;

COMMIT;
