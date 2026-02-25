BEGIN;

-- ============================================================================
-- Migration: Remove FKs problemáticas de colaborador_cliente_funcao
-- Data: 2026-01-15
-- Descrição: Remove todas as FKs que estão causando problemas de validação.
--            As validações serão feitas via código no frontend.
-- ============================================================================

-- Remove todas as possíveis FKs de colaborador
DO $$
BEGIN
  -- FK genérica "fk_colaborador"
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'fk_colaborador' 
    AND conrelid = 'public.colaborador_cliente_funcao'::regclass
  ) THEN
    ALTER TABLE public.colaborador_cliente_funcao
      DROP CONSTRAINT fk_colaborador;
  END IF;
  
  -- FK nomeada "fk_colaborador_cliente_funcao_colaborador"
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'fk_colaborador_cliente_funcao_colaborador' 
    AND conrelid = 'public.colaborador_cliente_funcao'::regclass
  ) THEN
    ALTER TABLE public.colaborador_cliente_funcao
      DROP CONSTRAINT fk_colaborador_cliente_funcao_colaborador;
  END IF;
  
  -- FK de colaborador_id
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'colaborador_cliente_funcao_colaborador_id_fkey' 
    AND conrelid = 'public.colaborador_cliente_funcao'::regclass
  ) THEN
    ALTER TABLE public.colaborador_cliente_funcao
      DROP CONSTRAINT colaborador_cliente_funcao_colaborador_id_fkey;
  END IF;
END $$;

-- Remove FK de cliente se existir
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'fk_cliente' 
    AND conrelid = 'public.colaborador_cliente_funcao'::regclass
  ) THEN
    ALTER TABLE public.colaborador_cliente_funcao
      DROP CONSTRAINT fk_cliente;
  END IF;
  
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'fk_colaborador_cliente_funcao_cliente' 
    AND conrelid = 'public.colaborador_cliente_funcao'::regclass
  ) THEN
    ALTER TABLE public.colaborador_cliente_funcao
      DROP CONSTRAINT fk_colaborador_cliente_funcao_cliente;
  END IF;
END $$;

-- Remove FK de serviço se existir
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'fk_servico' 
    AND conrelid = 'public.colaborador_cliente_funcao'::regclass
  ) THEN
    ALTER TABLE public.colaborador_cliente_funcao
      DROP CONSTRAINT fk_servico;
  END IF;
  
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'fk_colaborador_cliente_funcao_servico' 
    AND conrelid = 'public.colaborador_cliente_funcao'::regclass
  ) THEN
    ALTER TABLE public.colaborador_cliente_funcao
      DROP CONSTRAINT fk_colaborador_cliente_funcao_servico;
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
