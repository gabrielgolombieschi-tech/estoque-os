-- Migration: Corrigir trigger validate_hh_lancamento para usar hh_servico_id ao invés de hh_tipo_id
-- Data: 2026-01-22
-- Problema: Trigger estava validando hh_tipo_id (1/2/3 percentual) contra colaborador_cliente_funcao
--           quando deveria validar hh_servico_id (ID do serviço específico do cliente)

BEGIN;

CREATE OR REPLACE FUNCTION public.validate_hh_lancamento()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_cliente_id bigint;
  v_servico_id bigint;
  v_ok_vinculo boolean;
  v_perc integer;
  v_preco numeric;
BEGIN
  -- 1) Percentual aplicado
  v_perc := COALESCE(NEW.percentual_aplicado, 0);

  -- 2) Se não há hh_servico_id, não validar vínculo (deixar RLS validar)
  IF NEW.hh_servico_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- 3) Obter cliente_id da OS
  SELECT os.cliente_id
    INTO v_cliente_id
  FROM public.ordens_servico os
  WHERE os.id = NEW.os_id
    AND os.tenant_id = NEW.tenant_id
  LIMIT 1;

  IF v_cliente_id IS NULL THEN
    RAISE EXCEPTION 'OS % sem cliente vinculado (cliente_id).', NEW.os_id;
  END IF;

  -- 4) Serviço escolhido no lançamento (usar hh_servico_id, NÃO hh_tipo_id)
  v_servico_id := NEW.hh_servico_id;

  IF v_servico_id IS NULL OR v_servico_id <= 0 THEN
    RAISE EXCEPTION 'Serviço HH inválido no lançamento (hh_servico_id=%).', NEW.hh_servico_id;
  END IF;

  -- 5) Validar se o colaborador tem vínculo com esse serviço para esse cliente
  SELECT EXISTS (
    SELECT 1
    FROM public.colaborador_cliente_funcao ccf
    WHERE ccf.tenant_id = NEW.tenant_id
      AND ccf.cliente_id = v_cliente_id
      AND ccf.colaborador_id = NEW.colaborador_id
      AND ccf.hh_servico_id = v_servico_id
      AND COALESCE(ccf.ativo, true) = true
  )
  INTO v_ok_vinculo;

  IF NOT v_ok_vinculo THEN
    RAISE EXCEPTION
      'Serviço HH % não está vinculado ao colaborador % para o cliente % (colaborador_cliente_funcao).',
      v_servico_id, NEW.colaborador_id, v_cliente_id;
  END IF;

  -- 6) Buscar preço no cliente_hh_servicos pelo serviço selecionado
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
  LIMIT 1;

  -- Se encontrou preço, atualizar valor_hora
  IF v_preco IS NOT NULL THEN
    NEW.valor_hora := v_preco;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.validate_hh_lancamento() IS 
  'Valida vínculo colaborador-serviço usando hh_servico_id (não hh_tipo_id). hh_tipo_id é apenas para percentual.';

COMMIT;

NOTIFY pgrst, 'reload schema';
