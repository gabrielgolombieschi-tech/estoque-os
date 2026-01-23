-- ================================
-- SUPABASE: Corrigir fn_hh_lancamentos_calc()
-- ================================
-- PROBLEMA: Função exigia entrada/saída preenchidas, mas HH lança apenas com horas_trabalhadas
-- SOLUÇÃO: Aceitar EITHER (entrada/saída) OR (horas_trabalhadas preenchidas)
-- ================================

BEGIN;

-- Drop função antiga
DROP FUNCTION IF EXISTS public.fn_hh_lancamentos_calc() CASCADE;

-- Recriar com lógica corrigida
CREATE FUNCTION public.fn_hh_lancamentos_calc() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_perc int;
  v_cliente_id bigint;
  v_servico_id bigint;
  v_preco numeric;
  v_ok_vinculo boolean;
BEGIN
  -- 1) percentual sempre pela data (0/50/100)
  v_perc := public.fn_percentual_por_data(NEW.data);
  NEW.percentual_aplicado := v_perc;

  -- 2) Se usou 2 períodos, calcula horas. Se foi preenchido manualmente, aceita horas_trabalhadas direto
  IF NEW.entrada_1 IS NOT NULL OR NEW.saida_1 IS NOT NULL OR NEW.entrada_2 IS NOT NULL OR NEW.saida_2 IS NOT NULL THEN
    -- Modo 2-períodos: todos os 4 campos devem ser preenchidos
    IF NEW.entrada_1 IS NULL OR NEW.saida_1 IS NULL OR NEW.entrada_2 IS NULL OR NEW.saida_2 IS NULL THEN
      RAISE EXCEPTION 'Preencha Entrada 1, Saída 1, Entrada 2 e Saída 2 ou deixe todos em branco.';
    END IF;

    NEW.horas_trabalhadas := public.fn_calc_horas_2_periodos(
      NEW.entrada_1, NEW.saida_1, NEW.entrada_2, NEW.saida_2
    );

    NEW.hora_entrada := NEW.entrada_1;
    NEW.hora_saida   := NEW.saida_2;
  ELSIF NEW.horas_trabalhadas IS NULL THEN
    -- Se nem período nem horas_trabalhadas foram preenchidas, erro
    RAISE EXCEPTION 'Preencha ou (Entrada 1, Saída 1, Entrada 2, Saída 2) ou horas_trabalhadas.';
  END IF;

  -- 3) Descobrir cliente da OS
  SELECT os.cliente_id::bigint
    INTO v_cliente_id
  FROM public.ordens_servico os
  WHERE os.id = NEW.os_id
    AND os.tenant_id = NEW.tenant_id
  LIMIT 1;

  IF v_cliente_id IS NULL THEN
    RAISE EXCEPTION 'OS % sem cliente vinculado (cliente_id).', NEW.os_id;
  END IF;

  -- 4) Serviço escolhido no lançamento:
  --    CRÍTICO: Usar hh_servico_id (ID real do serviço, ex: 8)
  --    NÃO usar hh_tipo_id (é apenas percentual mapping: 10, 11, 13, etc.)
  v_servico_id := NEW.hh_servico_id;

  IF v_servico_id IS NULL OR v_servico_id <= 0 THEN
    RAISE EXCEPTION 'Serviço HH inválido no lançamento (hh_servico_id=%).', NEW.hh_servico_id;
  END IF;

  -- 5) Valida se o colaborador tem vínculo com esse serviço para esse cliente
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

  -- 6) Buscar preço no cliente_hh_servicos pelo serviço selecionado + cliente/empresa/tenant
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

  IF v_preco IS NULL THEN
    RAISE EXCEPTION
      'Preço HH não encontrado para serviço % / cliente % / empresa % / percentual %.',
      v_servico_id, v_cliente_id, NEW.empresa_id, v_perc;
  END IF;

  NEW.valor_hora  := ROUND(v_preco::numeric, 2);
  NEW.valor_total := ROUND(COALESCE(NEW.horas_trabalhadas, 0) * COALESCE(NEW.valor_hora, 0), 2);

  RETURN NEW;
END;
$$;

COMMIT;
