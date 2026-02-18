-- Migration: 20260219_fix_hh_campos_periodos.sql
-- Purpose: Corrigir cálculo de HH lançamentos para 2 períodos (entrada_1/saida_1 + entrada_2/saida_2)
-- Author: AI Assistant
-- Date: 2026-02-19
-- 
-- PROBLEM:
--   Frontend enviava dados em entrada_1/saida_1/entrada_2/saida_2
--   Mas trigger fn_hh_lancamentos_calc() ignorava e calculava apenas com hora_entrada/hora_saida
--   Resultado: Dados salvos em campos legados, novos campos ficavam NULL
--
-- SOLUTION:
--   1. Atualizar função para reconhecer campos novos (entrada_1, saida_1, entrada_2, saida_2)
--   2. Compatibilidade com legado: se novos campos vêm preenchidos, manter eles
--   3. Se apenas legado vem preenchido, preencher novos campos automaticamente
--   4. Cálculo de horas_trabalhadas soma os 2 períodos
--   5. Cálculo de valor_total usa horas totais * valor_hora

BEGIN;

-- Função auxiliar: converter HH:MM para minutos (já deve existir, mas deixamos para segurança)
CREATE OR REPLACE FUNCTION time_to_minutes(time_str VARCHAR)
RETURNS INTEGER AS $$
DECLARE
  parts TEXT[];
  hours INTEGER;
  minutes INTEGER;
BEGIN
  IF time_str IS NULL OR time_str = '' THEN
    RETURN NULL;
  END IF;
  
  parts := string_to_array(time_str, ':');
  IF array_length(parts, 1) < 2 THEN
    RETURN NULL;
  END IF;
  
  hours := (parts[1])::INTEGER;
  minutes := (parts[2])::INTEGER;
  
  RETURN hours * 60 + minutes;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Função auxiliar: converter minutos para HH:MM
CREATE OR REPLACE FUNCTION minutes_to_time(minutes INTEGER)
RETURNS VARCHAR AS $$
DECLARE
  hours INTEGER;
  mins INTEGER;
BEGIN
  IF minutes IS NULL THEN
    RETURN NULL;
  END IF;
  
  hours := minutes / 60;
  mins := minutes % 60;
  
  RETURN LPAD(hours::TEXT, 2, '0') || ':' || LPAD(mins::TEXT, 2, '0');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- FUNÇÃO PRINCIPAL: Cálculo de HH lançamentos
-- Compatibilidade: 
--   - Prioriza campos novos (entrada_1/saida_1/entrada_2/saida_2)
--   - Se chegarem NULL mas hora_entrada/hora_saida existem, sincroniza
--   - Calcula horas_trabalhadas como soma dos 2 períodos
--   - Calcula valor_total = horas_trabalhadas * valor_hora
CREATE OR REPLACE FUNCTION fn_hh_lancamentos_calc()
RETURNS TRIGGER AS $$
DECLARE
  v_entrada1_min INTEGER;
  v_saida1_min INTEGER;
  v_entrada2_min INTEGER;
  v_saida2_min INTEGER;
  v_horas_periodo1_decimal NUMERIC;
  v_horas_periodo2_decimal NUMERIC;
  v_horas_trabalhadas NUMERIC;
  v_valor_hora NUMERIC;
BEGIN
  -- Step 1: Resolver entrada_1 e saida_1
  -- Prioriza novos campos, fallback para legado
  IF NEW.entrada_1 IS NOT NULL AND NEW.entrada_1 != '' THEN
    v_entrada1_min := time_to_minutes(NEW.entrada_1);
  ELSIF NEW.hora_entrada IS NOT NULL AND NEW.hora_entrada != '' THEN
    v_entrada1_min := time_to_minutes(NEW.hora_entrada);
    NEW.entrada_1 := NEW.hora_entrada;  -- Sincroniza novo com legado
  ELSE
    RAISE EXCEPTION 'entrada_1 é obrigatória';
  END IF;

  IF NEW.saida_1 IS NOT NULL AND NEW.saida_1 != '' THEN
    v_saida1_min := time_to_minutes(NEW.saida_1);
  ELSIF NEW.hora_entrada IS NOT NULL AND NEW.hora_entrada != '' THEN
    -- Se saida_1 não tem mas hora_saida tem (para compatibilidade)
    v_saida1_min := time_to_minutes(COALESCE(NEW.hora_saida, NEW.hora_entrada));
    NEW.saida_1 := COALESCE(NEW.hora_saida, NEW.hora_entrada);
  ELSE
    RAISE EXCEPTION 'saida_1 é obrigatória';
  END IF;

  -- Step 2: Resolver entrada_2 e saida_2
  -- Campos novos obrigatórios (regra do negócio: 2 períodos sempre)
  IF NEW.entrada_2 IS NULL OR NEW.entrada_2 = '' THEN
    RAISE EXCEPTION 'entrada_2 é obrigatória';
  END IF;

  IF NEW.saida_2 IS NULL OR NEW.saida_2 = '' THEN
    RAISE EXCEPTION 'saida_2 é obrigatória';
  END IF;

  v_entrada2_min := time_to_minutes(NEW.entrada_2);
  v_saida2_min := time_to_minutes(NEW.saida_2);

  -- Step 3: Validações de horários
  IF v_entrada1_min IS NULL OR v_saida1_min IS NULL OR v_entrada2_min IS NULL OR v_saida2_min IS NULL THEN
    RAISE EXCEPTION 'Horários inválidos. Use formato HH:MM';
  END IF;

  IF v_entrada1_min >= v_saida1_min THEN
    RAISE EXCEPTION 'Entrada 1 (%) deve ser menor que Saída 1 (%)', 
      minutes_to_time(v_entrada1_min), minutes_to_time(v_saida1_min);
  END IF;

  IF v_entrada2_min >= v_saida2_min THEN
    RAISE EXCEPTION 'Entrada 2 (%) deve ser menor que Saída 2 (%)', 
      minutes_to_time(v_entrada2_min), minutes_to_time(v_saida2_min);
  END IF;

  IF v_saida1_min > v_entrada2_min THEN
    RAISE EXCEPTION 'Saída 1 (%) deve ser menor ou igual a Entrada 2 (%) - sem sobreposição', 
      minutes_to_time(v_saida1_min), minutes_to_time(v_entrada2_min);
  END IF;

  -- Step 4: Sincronizar campos legados com novos (para compatibilidade)
  -- Se campos novos foram atualizados, atualiza legado também
  NEW.hora_entrada := COALESCE(NEW.entrada_1, NEW.hora_entrada);
  NEW.hora_saida := COALESCE(NEW.saida_2, NEW.hora_saida);

  -- Step 5: Calcular horas por período (em decimais)
  v_horas_periodo1_decimal := (v_saida1_min - v_entrada1_min)::NUMERIC / 60.0;
  v_horas_periodo2_decimal := (v_saida2_min - v_entrada2_min)::NUMERIC / 60.0;
  
  -- Soma dos 2 períodos
  v_horas_trabalhadas := v_horas_periodo1_decimal + v_horas_periodo2_decimal;
  
  NEW.horas_trabalhadas := v_horas_trabalhadas;

  -- Step 6: Calcular valor_total
  -- Regra: valor_total = horas_trabalhadas * valor_hora
  -- (nota: percentual_aplicado já foi considerado no valor_hora antes de chegar aqui)
  v_valor_hora := COALESCE(NEW.valor_hora, 0);
  
  IF v_valor_hora > 0 THEN
    NEW.valor_total := (v_horas_trabalhadas * v_valor_hora)::NUMERIC;
  ELSE
    NEW.valor_total := 0;
  END IF;

  -- Step 7: Atualizar timestamp
  NEW.atualizado_em := NOW();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Aplicar cálculo antes de qualquer insert/update em hh_lancamentos
DROP TRIGGER IF EXISTS trg_hh_lancamentos_calc ON public.hh_lancamentos;

CREATE TRIGGER trg_hh_lancamentos_calc
  BEFORE INSERT OR UPDATE
  ON public.hh_lancamentos
  FOR EACH ROW
  EXECUTE FUNCTION fn_hh_lancamentos_calc();

-- NOTES:
-- 1. Frontend deve enviar SEMPRE: entrada_1, saida_1, entrada_2, saida_2
-- 2. Também envia hora_entrada e hora_saida para compatibilidade (trigger sincroniza)
-- 3. Cálculo de horas_trabalhadas = (saida_1 - entrada_1) + (saida_2 - entrada_2) em horas decimais
-- 4. Cálculo de valor_total = horas_trabalhadas * valor_hora
-- 5. Se campos novos vêm NULL, trigger tenta usar legado como fallback (compatibilidade)
-- 6. Se legado vem preenchido mas novos NULL, trigger sincroniza automaticamente

COMMIT;
