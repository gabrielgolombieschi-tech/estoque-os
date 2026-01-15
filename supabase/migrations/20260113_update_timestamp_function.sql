BEGIN;

-- ============================================================================
-- Função: update_timestamp
-- Descrição: Atualiza automaticamente o campo atualizado_em em triggers
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.atualizado_em = NOW();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.update_timestamp() IS 'Trigger function para atualizar campo atualizado_em automaticamente';

COMMIT;
