BEGIN;

-- ============================================================================
-- Migration: Fix tenant_id auto-fill para colaborador_cliente_funcao
-- Data: 2026-01-15
-- Descrição: Adiciona trigger para preencher automaticamente tenant_id no INSERT
--            e remove FK para tenants se existir (tenant_id vem do contexto)
-- ============================================================================

-- 1) Remover FK para tenants se existir (tenant_id vem via contexto, não é FK)
-- ============================================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'fk_tenant' 
    AND conrelid = 'public.colaborador_cliente_funcao'::regclass
  ) THEN
    ALTER TABLE public.colaborador_cliente_funcao
      DROP CONSTRAINT fk_tenant;
  END IF;
  
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'colaborador_cliente_funcao_tenant_id_fkey' 
    AND conrelid = 'public.colaborador_cliente_funcao'::regclass
  ) THEN
    ALTER TABLE public.colaborador_cliente_funcao
      DROP CONSTRAINT colaborador_cliente_funcao_tenant_id_fkey;
  END IF;
END $$;

-- 2) Criar função para preencher tenant_id automaticamente
-- ============================================================================

CREATE OR REPLACE FUNCTION public.set_tenant_id_colaborador_cliente_funcao()
RETURNS TRIGGER AS $$
BEGIN
  -- Se tenant_id não foi fornecido ou é NULL, pega do contexto
  IF NEW.tenant_id IS NULL THEN
    NEW.tenant_id := public.current_tenant_id();
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.set_tenant_id_colaborador_cliente_funcao() IS
  'Trigger function: preenche automaticamente tenant_id no INSERT de colaborador_cliente_funcao';

-- 3) Criar trigger BEFORE INSERT
-- ============================================================================

DROP TRIGGER IF EXISTS trg_set_tenant_id_colaborador_cliente_funcao 
  ON public.colaborador_cliente_funcao;

CREATE TRIGGER trg_set_tenant_id_colaborador_cliente_funcao
  BEFORE INSERT ON public.colaborador_cliente_funcao
  FOR EACH ROW
  EXECUTE FUNCTION public.set_tenant_id_colaborador_cliente_funcao();

COMMIT;

NOTIFY pgrst, 'reload schema';
