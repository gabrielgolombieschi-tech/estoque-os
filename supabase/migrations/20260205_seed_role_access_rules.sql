BEGIN;

WITH roles_norm AS (
  SELECT id,
         translate(lower(coalesce(name, '')),
           'áàãâäéèêëíìîïóòôõöúùûüç',
           'aaaaaeeeeiiiiooooouuuuc') AS name_norm
  FROM public.roles
),
rules(role_key, resource, action) AS (
  VALUES
    -- OS
    ('admin', 'os', 'read'),
    ('admin', 'os', 'write'),
    ('admin', 'os', 'delete'),
    ('admin', 'os_itens', 'write'),
    ('admin', 'os_gestao', 'write'),
    ('admin', 'os_rpcs', 'execute'),

    ('coord', 'os', 'read'),
    ('coord', 'os', 'write'),
    ('coord', 'os', 'delete'),
    ('coord', 'os_itens', 'write'),
    ('coord', 'os_gestao', 'write'),
    ('coord', 'os_rpcs', 'execute'),

    ('financeiro', 'os', 'read'),
    ('financeiro', 'os', 'write'),
    ('financeiro', 'os', 'delete'),
    ('financeiro', 'os_itens', 'write'),
    ('financeiro', 'os_gestao', 'write'),
    ('financeiro', 'os_rpcs', 'execute'),

    ('operacional', 'os', 'read'),
    ('operacional', 'os_itens', 'write'),
    ('operacional', 'os_gestao', 'write'),
    ('operacional', 'os_rpcs', 'execute'),

    ('estoque', 'os', 'read'),
    ('estoque', 'os_itens', 'write'),
    ('estoque', 'os_gestao', 'write'),
    ('estoque', 'os_rpcs', 'execute'),

    ('leitura', 'os', 'read'),

    -- Estoque
    ('admin', 'estoque', 'read'),
    ('admin', 'estoque', 'write'),
    ('admin', 'estoque_custos', 'cost_read'),

    ('coord', 'estoque', 'read'),
    ('coord', 'estoque', 'write'),
    ('coord', 'estoque_custos', 'cost_read'),

    ('financeiro', 'estoque', 'read'),
    ('financeiro', 'estoque', 'write'),
    ('financeiro', 'estoque_custos', 'cost_read'),

    ('estoque', 'estoque', 'read'),
    ('estoque', 'estoque', 'write'),

    ('operacional', 'estoque', 'read'),
    ('leitura', 'estoque', 'read'),

    -- Fiscal/XML
    ('admin', 'fiscal_nf', 'read'),
    ('admin', 'fiscal_nf', 'write'),
    ('admin', 'fiscal_nf', 'delete'),
    ('admin', 'fiscal_itens', 'write'),
    ('admin', 'xml_import', 'execute'),

    ('coord', 'fiscal_nf', 'read'),
    ('coord', 'fiscal_nf', 'write'),
    ('coord', 'fiscal_nf', 'delete'),
    ('coord', 'fiscal_itens', 'write'),
    ('coord', 'xml_import', 'execute'),

    ('financeiro', 'fiscal_nf', 'read'),
    ('financeiro', 'fiscal_nf', 'write'),
    ('financeiro', 'fiscal_nf', 'delete'),
    ('financeiro', 'fiscal_itens', 'write'),
    ('financeiro', 'xml_import', 'execute'),

    ('estoque', 'fiscal_nf', 'read'),
    ('estoque', 'fiscal_itens', 'write'),
    ('estoque', 'xml_import', 'execute'),

    ('operacional', 'fiscal_nf', 'read'),

    -- Financeiro
    ('admin', 'financeiro', 'read'),
    ('admin', 'financeiro', 'write'),
    ('admin', 'financeiro', 'delete'),
    ('admin', 'financeiro', 'config'),

    ('financeiro', 'financeiro', 'read'),
    ('financeiro', 'financeiro', 'write'),
    ('financeiro', 'financeiro', 'delete'),
    ('financeiro', 'financeiro', 'config'),

    -- Apontamentos
    ('admin', 'apontamentos', 'read'),
    ('admin', 'apontamentos', 'write'),
    ('admin', 'apontamentos', 'delete'),
    ('admin', 'apontamentos', 'config'),

    ('coord', 'apontamentos', 'read'),
    ('coord', 'apontamentos', 'write'),
    ('coord', 'apontamentos', 'delete'),
    ('coord', 'apontamentos', 'config'),

    ('operacional', 'apontamentos', 'read'),
    ('operacional', 'apontamentos', 'write'),
    ('operacional', 'apontamentos', 'delete'),
    ('operacional', 'apontamentos', 'config'),

    ('financeiro', 'apontamentos', 'read'),
    ('financeiro', 'apontamentos', 'write'),
    ('financeiro', 'apontamentos', 'delete'),
    ('financeiro', 'apontamentos', 'config'),

    ('estoque', 'apontamentos', 'read'),
    ('estoque', 'apontamentos', 'write'),
    ('estoque', 'apontamentos', 'delete'),
    ('estoque', 'apontamentos', 'config'),

    -- Cadastros
    ('admin', 'cad_clientes', 'write'),
    ('admin', 'cad_fornecedores', 'write'),
    ('admin', 'cad_itens', 'write'),

    ('coord', 'cad_clientes', 'write'),
    ('coord', 'cad_fornecedores', 'write'),
    ('coord', 'cad_itens', 'write'),

    ('financeiro', 'cad_clientes', 'write'),
    ('financeiro', 'cad_fornecedores', 'write'),
    ('financeiro', 'cad_itens', 'write'),

    ('estoque', 'cad_clientes', 'write'),
    ('estoque', 'cad_fornecedores', 'write'),
    ('estoque', 'cad_itens', 'write')
)
INSERT INTO public.role_access_rules (role_id, resource, action)
SELECT rn.id, rules.resource, rules.action
FROM roles_norm rn
JOIN rules
  ON (
    (rules.role_key = 'admin' AND rn.name_norm LIKE 'admin%')
    OR (rules.role_key = 'coord' AND (rn.name_norm LIKE 'coord%' OR rn.name_norm LIKE 'coorden%'))
    OR (rules.role_key = 'financeiro' AND rn.name_norm LIKE 'financeir%')
    OR (rules.role_key = 'operacional' AND rn.name_norm LIKE 'operac%')
    OR (rules.role_key = 'estoque' AND rn.name_norm LIKE 'estoque%')
    OR (rules.role_key = 'leitura' AND rn.name_norm LIKE '%leitura%')
  )
ON CONFLICT DO NOTHING;

COMMIT;
