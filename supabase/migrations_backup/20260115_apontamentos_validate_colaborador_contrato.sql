BEGIN;

-- ============================================================================
-- Migration: Validação de colaborador vinculado ao contrato do cliente na OS
-- Data: 2026-01-15
-- Descrição: Adiciona trigger para garantir que apenas colaboradores
--            vinculados ao contrato do cliente (via colaborador_cliente_funcao)
--            possam ter apontamentos de horas lançados naquela OS
-- ============================================================================

-- Função de validação (SECURITY DEFINER para ler tabelas relacionadas)
CREATE OR REPLACE FUNCTION public.validate_apontamento_colaborador_contrato()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id UUID;
  v_cliente_id BIGINT;
  v_vinculo_exists BOOLEAN;
BEGIN
  -- 1) Obter tenant_id da linha (assume que apontamentos_horas tem tenant_id)
  v_tenant_id := NEW.tenant_id;
  
  -- 2) Obter cliente_id da OS
  SELECT cliente_id INTO v_cliente_id
  FROM public.ordens_servico
  WHERE id = NEW.os_id
    AND tenant_id = v_tenant_id;
  
  -- Se não encontrou a OS ou ela não tem cliente_id, permite (validação opcional)
  IF v_cliente_id IS NULL THEN
    RETURN NEW;
  END IF;
  
  -- 3) Verificar se existe vínculo ativo do colaborador com este cliente
  SELECT EXISTS (
    SELECT 1
    FROM public.colaborador_cliente_funcao
    WHERE tenant_id = v_tenant_id
      AND cliente_id = v_cliente_id
      AND colaborador_id = NEW.colaborador_id
      AND ativo = true
  ) INTO v_vinculo_exists;
  
  -- 4) Se não existe vínculo, bloquear
  IF NOT v_vinculo_exists THEN
    RAISE EXCEPTION 
      'Colaborador % não está vinculado ao contrato do cliente da OS %. Cadastre o vínculo em Cadastros > Colaboradores × Cliente.',
      NEW.colaborador_id, NEW.os_id
      USING ERRCODE = '23503'; -- foreign_key_violation
  END IF;
  
  RETURN NEW;
END;
$$;

-- Drop trigger se já existir
DROP TRIGGER IF EXISTS trigger_validate_apontamento_colaborador ON public.apontamentos_horas;

-- Criar trigger BEFORE INSERT e UPDATE
CREATE TRIGGER trigger_validate_apontamento_colaborador
  BEFORE INSERT OR UPDATE OF colaborador_id, os_id
  ON public.apontamentos_horas
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_apontamento_colaborador_contrato();

COMMENT ON FUNCTION public.validate_apontamento_colaborador_contrato() IS 
  'Valida que o colaborador do apontamento está vinculado ao contrato do cliente da OS (via colaborador_cliente_funcao)';

COMMIT;

NOTIFY pgrst, 'reload schema';
