-- Tabela de preços HH (global, negociada com cliente)
CREATE TABLE IF NOT EXISTS public.hh_tabela_precos (
  id BIGSERIAL PRIMARY KEY,
  descricao TEXT NOT NULL,
  nivel TEXT NOT NULL, -- 'I', 'II', 'III'
  categoria TEXT NOT NULL, -- 'montador', 'comando', 'automacao', 'mecanica'
  preco_base NUMERIC(10,2) NOT NULL DEFAULT 0,
  preco_50 NUMERIC(10,2) NOT NULL DEFAULT 0,
  preco_100 NUMERIC(10,2) NOT NULL DEFAULT 0,
  ativo BOOLEAN NOT NULL DEFAULT true,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_hh_tabela_precos_ativo ON public.hh_tabela_precos(ativo);
CREATE INDEX IF NOT EXISTS idx_hh_tabela_precos_categoria ON public.hh_tabela_precos(categoria);

-- Seed com dados fornecidos
INSERT INTO public.hh_tabela_precos (descricao, nivel, categoria, preco_base, preco_50, preco_100) VALUES
  ('MAO-DE-OBRA ELETRICISTA MONTADOR HH (NIVEL I)', 'I', 'montador', 49.65, 74.47, 99.29),
  ('MAO-DE-OBRA ELETRICISTA MONTADOR HH (NIVEL II)', 'II', 'montador', 57.29, 85.94, 114.59),
  ('MAO-DE-OBRA ELETRICISTA MONTADOR HH (NIVEL III)', 'III', 'montador', 68.75, 103.12, 137.49),
  ('MAO-DE-OBRA ELETRICISTA DE COMANDO HH (NIVEL I)', 'I', 'comando', 68.75, 103.12, 137.49),
  ('MAO-DE-OBRA ELETRICISTA DE COMANDO HH (NIVEL II)', 'II', 'comando', 78.92, 118.39, 157.85),
  ('MAO-DE-OBRA ELETRICISTA DE COMANDO HH (NIVEL III)', 'III', 'comando', 89.11, 133.67, 178.23),
  ('MAO-DE-OBRA ELETRICISTA DE AUTOMACAO HH (NIVEL I)', 'I', 'automacao', 91.66, 137.48, 183.31),
  ('MAO-DE-OBRA ELETRICISTA DE AUTOMACAO HH (NIVEL II)', 'II', 'automacao', 120.95, 181.42, 241.89),
  ('MAO-DE-OBRA ELETRICISTA DE AUTOMACAO HH (NIVEL III)', 'III', 'automacao', 175.69, 263.53, 351.37),
  ('MAO-DE-OBRA TÉCNICA DE MECÂNICA HH (NIVEL II)', 'II', 'mecanica', 91.66, 137.48, 183.31)
ON CONFLICT DO NOTHING;

-- Permissões: qualquer usuário autenticado pode ler
GRANT SELECT ON public.hh_tabela_precos TO authenticated;

COMMENT ON TABLE public.hh_tabela_precos IS 'Tabela de preços de mão-de-obra HH negociada com cliente (global)';
