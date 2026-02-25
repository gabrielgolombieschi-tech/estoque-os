BEGIN;

-- Fix: public.has_permission() must not reference v.user_id because v_user_permissions view
-- projects only (tenant_id, permission). User filtering happens inside the view via auth.uid().

CREATE OR REPLACE FUNCTION public.has_permission(p_code text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.v_user_permissions v
    WHERE v.tenant_id = public.current_tenant_id()
      AND v.permission = p_code
  );
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
