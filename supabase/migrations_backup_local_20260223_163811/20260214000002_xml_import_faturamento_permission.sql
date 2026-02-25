BEGIN;

-- FINANCEIRO: pode importar XML de faturamento (SAÍDA) mas NÃO de entrada/estoque.

WITH roles_norm AS (
  SELECT
    id,
    translate(
      lower(coalesce(name, '')),
      'áàãâäéèêëíìîïóòôõöúùûüç',
      'aaaaaeeeeiiiiooooouuuuc'
    ) AS name_norm
  FROM public.roles
)
DELETE FROM public.role_access_rules rar
USING roles_norm rn
WHERE rar.role_id = rn.id
  AND rn.name_norm LIKE 'financeir%'
  AND rar.resource = 'xml_import'
  AND rar.action = 'execute';

WITH roles_norm AS (
  SELECT
    id,
    translate(
      lower(coalesce(name, '')),
      'áàãâäéèêëíìîïóòôõöúùûüç',
      'aaaaaeeeeiiiiooooouuuuc'
    ) AS name_norm
  FROM public.roles
)
INSERT INTO public.role_access_rules (role_id, resource, action)
SELECT rn.id, 'xml_import_faturamento', 'execute'
FROM roles_norm rn
WHERE rn.name_norm LIKE 'financeir%'
ON CONFLICT DO NOTHING;

COMMIT;
