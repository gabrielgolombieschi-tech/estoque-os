BEGIN;

CREATE OR REPLACE FUNCTION public.can_many(p_pairs jsonb)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    jsonb_object_agg(key, val),
    '{}'::jsonb
  )
  FROM (
    SELECT
      CASE
        WHEN elem ? 'key' THEN elem->>'key'
        ELSE (elem->>'resource') || '.' || (elem->>'action')
      END AS key,
      public.can(elem->>'resource', elem->>'action') AS val
    FROM jsonb_array_elements(COALESCE(p_pairs, '[]'::jsonb)) elem
    WHERE jsonb_typeof(elem) = 'object'
  ) s;
$$;

WITH roles_norm AS (
  SELECT id,
         translate(lower(coalesce(name, '')),
           'Â â¦ÃÆââÅ Ëâ°Â¡ÂÅâ¹Â¢â¢âÃ¤âÂ£ââÂâ¡',
           'aaaaaeeeeiiiiooooouuuuc') AS name_norm
  FROM public.roles
),
admin_roles AS (
  SELECT id
  FROM roles_norm
  WHERE name_norm LIKE 'admin%'
)
INSERT INTO public.role_access_rules (role_id, resource, action)
SELECT id, 'admin', 'manage_users'
FROM admin_roles
ON CONFLICT DO NOTHING;

NOTIFY pgrst, 'reload schema';

COMMIT;
