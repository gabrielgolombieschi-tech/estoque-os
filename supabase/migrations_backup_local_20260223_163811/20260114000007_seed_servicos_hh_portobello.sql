-- ============================================================================
-- SEED: Cadastro de Serviços HH para Portobello SA
-- Data: 2026-01-14
-- Descrição: Insere todos os serviços de Hora-Homem para o cliente Portobello SA
-- ============================================================================

-- ⚠️ IMPORTANTE: Ajuste os valores abaixo ANTES de executar:
-- 1. tenant_id: ID do seu tenant (ex: 1, 2, etc)
-- 2. empresa_id: ID da sua empresa (ex: 1, 2, etc)
-- 3. cliente_id: ID do cliente Portobello SA (você pode encontrar em Menu → Cadastros → Clientes)

BEGIN;

-- Busca automaticamente tenant_id, empresa_id e cliente_id para 'Portobello SA'
WITH config AS (
  SELECT 
    t.id as tenant_id,
    e.id as empresa_id,
    c.id as cliente_id,
    now() as criado_em,
    'seed@sistema.com' as criado_por
  FROM public.clientes c
  INNER JOIN public.tenants t ON c.tenant_id = t.id
  CROSS JOIN LATERAL (
    SELECT e2.id
    FROM public.empresas e2
    WHERE e2.tenant_id = t.id
      AND e2.ativo = true
    LIMIT 1
  ) e
  WHERE c.nome ILIKE '%Portobello%'
    AND c.ativo = true
  LIMIT 1
)
INSERT INTO public.cliente_hh_servicos (
  tenant_id,
  empresa_id,
  cliente_id,
  nome,
  descricao,
  preco_base,
  preco_50,
  preco_100,
  ativo,
  criado_em,
  criado_por,
  atualizado_em
)
SELECT
  c.tenant_id,
  c.empresa_id,
  c.cliente_id,
  servico.nome,
  servico.descricao,
  servico.preco_base,
  servico.preco_50,
  servico.preco_100,
  true,
  c.criado_em,
  c.criado_por,
  c.criado_em
FROM config c
CROSS JOIN (
  VALUES
    ('MAO-DE-OBRA ELETRICISTA MONTADOR HH (NIVEL I)', NULL, 53.74, 80.61, 107.48),
    ('MAO-DE-OBRA ELETRICISTA MONTADOR HH (NIVEL II)', NULL, 62.02, 93.03, 124.04),
    ('MAO-DE-OBRA ELETRICISTA MONTADOR HH (NIVEL III)', NULL, 74.42, 111.63, 148.84),
    ('MAO-DE-OBRA ELETRICISTA DE COMANDO HH (NIVEL I)', NULL, 74.42, 111.63, 148.84),
    ('MAO-DE-OBRA ELETRICISTA DE COMANDO HH (NIVEL II)', NULL, 85.44, 128.15, 170.87),
    ('MAO-DE-OBRA ELETRICISTA DE COMANDO HH (NIVEL III)', NULL, 96.47, 144.70, 192.93),
    ('MAO-DE-OBRA ELETRICISTA DE AUTOMACAO HH (NIVEL I)', NULL, 99.22, 148.82, 198.43),
    ('MAO-DE-OBRA ELETRICISTA DE AUTOMACAO HH (NIVEL II)', NULL, 130.92, 196.39, 261.85),
    ('MAO-DE-OBRA ELETRICISTA DE AUTOMACAO HH (NIVEL III)', NULL, 190.18, 285.27, 380.36),
    ('MAO-DE-OBRA TÉCNICA DE MECÂNICA HH (NIVEL II)', NULL, 99.22, 148.82, 198.43)
) AS servico(nome, descricao, preco_base, preco_50, preco_100)
ON CONFLICT DO NOTHING;

COMMIT;
