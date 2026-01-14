BEGIN;

-- RPC seguro para listar empresas do usuário (funciona para qualquer role)
-- Usa RLS automática verificando tenant_memberships
CREATE OR REPLACE FUNCTION public.list_user_empresas(p_tenant_id uuid)
RETURNS TABLE (
  id uuid,
  nome text,
  ativo boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    e.id,
    COALESCE(e.nome, e.nome_fantasia, e.razao_social),
    e.ativo
  FROM public.empresas e
  WHERE e.tenant_id = p_tenant_id
    AND e.ativo = true
    AND EXISTS (
      -- User must be an active member of the tenant
      SELECT 1
      FROM public.tenant_memberships tm
      WHERE tm.user_id = auth.uid()
        AND tm.tenant_id = p_tenant_id
        AND tm.status = 'active'
    )
  ORDER BY e.criado_em ASC;
$$;

COMMIT;
