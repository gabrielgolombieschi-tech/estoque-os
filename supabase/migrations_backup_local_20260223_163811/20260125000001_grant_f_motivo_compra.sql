-- Allow reading f.motivo_compra for authenticated users (subject to RLS).
-- Fixes: "permission denied for schema f" on Estoque import (Classificação/Motivo).

-- Schema/table privileges (required before RLS can even be evaluated).
GRANT USAGE ON SCHEMA f TO authenticated;
GRANT USAGE ON SCHEMA f TO service_role;

GRANT SELECT ON TABLE f.motivo_compra TO authenticated;
GRANT SELECT ON TABLE f.motivo_compra TO service_role;

-- RLS: allow select only for specific empresa roles.
ALTER TABLE f.motivo_compra ENABLE ROW LEVEL SECURITY;

-- Helper: check allowed roles within the tenant without requiring current_empresa_id/current_tenant_id context.
-- SECURITY DEFINER + row_security off so the policy doesn't require direct SELECT privileges on a/c tables.
CREATE OR REPLACE FUNCTION f.has_motivo_compra_access(p_tenant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public','a','c','f'
SET row_security TO 'off'
AS $$
  select exists (
    select 1
    from a.usuario u
    join a.usuario_empresa ue on ue.usuario_id = u.id
    join c.empresa e on e.id = ue.empresa_id
    where u.auth_user_id = auth.uid()
      and u.deleted_at is null
      and ue.ativo is true
      and ue.deleted_at is null
      and e.deleted_at is null
      and e.tenant_id = p_tenant_id
      and upper(trim(coalesce(ue.papel, ''))) in (
        'ADMIN',
        'FINANCEIRO',
        'COORDENACAO',
        'COMPRAS',
        'ALMOXARIFADO',
        'APONTAMENTO_RH'
      )
  );
$$;

GRANT EXECUTE ON FUNCTION f.has_motivo_compra_access(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION f.has_motivo_compra_access(uuid) TO service_role;

DROP POLICY IF EXISTS motivo_compra_select_allowed_roles ON f.motivo_compra;

CREATE POLICY motivo_compra_select_allowed_roles
ON f.motivo_compra
FOR SELECT
TO authenticated
USING (
  deleted_at IS NULL
  AND ativo IS TRUE
  AND f.has_motivo_compra_access(tenant_id)
);
