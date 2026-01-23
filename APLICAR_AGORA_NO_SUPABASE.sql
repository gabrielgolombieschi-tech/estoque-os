-- ================================
-- SOLUÇÃO FINAL: Corrigir trigger validate_hh_lancamento
-- ================================
-- PROBLEMA: Trigger está validando hh_tipo_id (10) ao invés de hh_servico_id (8)
-- ERRO ATUAL: "Serviço HH 10 não está vinculado ao colaborador..."
-- SOLUÇÃO: Usar NEW.hh_servico_id na validação
-- ================================

BEGIN;

-- PASSO 1: Remover trigger existente
DROP TRIGGER IF EXISTS trigger_validate_hh_lancamento ON public.hh_lancamentos;

-- PASSO 2: Remover função antiga
DROP FUNCTION IF EXISTS public.validate_hh_lancamento() CASCADE;

-- PASSO 3: Criar função CORRIGIDA
CREATE OR REPLACE FUNCTION public.validate_hh_lancamento()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cliente_id bigint;
  v_servico_id bigint;
  v_ok_vinculo boolean;
  v_perc integer;
  v_preco numeric;
BEGIN
  -- Percentual aplicado
  v_perc := COALESCE(NEW.percentual_aplicado, 0);

  -- Se não há hh_servico_id, não validar vínculo
  IF NEW.hh_servico_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Obter cliente_id da OS
  SELECT os.cliente_id
    INTO v_cliente_id
  FROM public.ordens_servico os
  WHERE os.id = NEW.os_id
    AND os.tenant_id = NEW.tenant_id
  LIMIT 1;

  IF v_cliente_id IS NULL THEN
    RAISE EXCEPTION 'OS % sem cliente vinculado (cliente_id).', NEW.os_id;
  END IF;

  -- CRÍTICO: Usar hh_servico_id (8), NÃO hh_tipo_id (10)!
  -- hh_tipo_id é apenas para mapeamento de percentual
  -- hh_servico_id é o serviço real que o cliente contratou
  v_servico_id := NEW.hh_servico_id;

  IF v_servico_id IS NULL OR v_servico_id <= 0 THEN
    RAISE EXCEPTION 'Serviço HH inválido no lançamento (hh_servico_id=%).', NEW.hh_servico_id;
  END IF;

  -- Validar se colaborador tem vínculo com esse serviço para esse cliente
  SELECT EXISTS (
    SELECT 1
    FROM public.colaborador_cliente_funcao ccf
    WHERE ccf.tenant_id = NEW.tenant_id
      AND ccf.cliente_id = v_cliente_id
      AND ccf.colaborador_id = NEW.colaborador_id
      AND ccf.hh_servico_id = v_servico_id
      AND COALESCE(ccf.ativo, true) = true
      AND ccf.deleted_at IS NULL
  )
  INTO v_ok_vinculo;

  IF NOT v_ok_vinculo THEN
    RAISE EXCEPTION
      'Serviço HH % não está vinculado ao colaborador % para o cliente % (colaborador_cliente_funcao).',
      v_servico_id, NEW.colaborador_id, v_cliente_id;
  END IF;

  -- Buscar preço correto no cliente_hh_servicos
  SELECT
    CASE
      WHEN v_perc = 0   THEN s.preco_base
      WHEN v_perc = 50  THEN s.preco_50
      WHEN v_perc = 100 THEN s.preco_100
      ELSE NULL
    END
  INTO v_preco
  FROM public.cliente_hh_servicos s
  WHERE s.tenant_id = NEW.tenant_id
    AND s.empresa_id = NEW.empresa_id
    AND s.cliente_id = v_cliente_id
    AND s.id = v_servico_id
    AND s.ativo = true
    AND s.deleted_at IS NULL
  LIMIT 1;

  -- Se encontrou preço, atualizar valor_hora
  IF v_preco IS NOT NULL THEN
    NEW.valor_hora := v_preco;
  END IF;

  RETURN NEW;
END;
$$;

-- PASSO 4: Recriar trigger
CREATE TRIGGER trigger_validate_hh_lancamento
  BEFORE INSERT OR UPDATE OF colaborador_id, hh_servico_id
  ON public.hh_lancamentos
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_hh_lancamento();

COMMIT;
