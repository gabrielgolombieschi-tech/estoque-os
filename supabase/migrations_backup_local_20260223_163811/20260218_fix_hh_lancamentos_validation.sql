-- ============================================================================
-- Migration: CORR ETIVAS DEFINITIVAS PARA HH_LANCAMENTOS
-- Data: 2026-02-18
-- Descrição:
--   1. REMOVE referências a "colaborador_cliente_funcao" (tabela que NÃO existe)
--   2. CRIA validação CORRETA usando "colaborador_funcao_hh" (tabela real)
--   3. GARANTE que HH_LANCAMENTOS NÃO dependa de relatório
--   4. REMOVE empresa_id onde não é necessário na validação
-- ============================================================================

BEGIN;

-- ============================================================================
-- PASSO 1: CORRIGIR FUNÇÃO DE VALIDAÇÃO PARA APONTAMENTOS
-- ============================================================================

-- A função anterior estava procurando em tabela que não existe.
-- AGORA: Usa a tabela correta "colaborador_funcao_hh"

DROP FUNCTION IF EXISTS public.validate_apontamento_colaborador_contrato();

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
  -- 1) Obter tenant_id da linha
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
  --    TABELA CORRETA: colaborador_funcao_hh
  SELECT EXISTS (
    SELECT 1
    FROM public.colaborador_funcao_hh
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

-- Recriar trigger com a função corrigida
DROP TRIGGER IF EXISTS trigger_validate_apontamento_colaborador ON public.apontamentos_horas;

CREATE TRIGGER trigger_validate_apontamento_colaborador
  BEFORE INSERT OR UPDATE OF colaborador_id, os_id
  ON public.apontamentos_horas
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_apontamento_colaborador_contrato();

-- ============================================================================
-- PASSO 2: CRIAR VALIDAÇÃO PARA HH_LANCAMENTOS
-- ============================================================================
--
-- A validação do HH deve ser simples e clara:
-- - Verifica se existe vínculo ativo do colaborador com o serviço HH para o cliente
-- - NÃO consulta relatório (relatório é gerado DEPOIS, não depende disso)
-- - NÃO usa empresa_id (a validação é por cliente, não por empresa)
-- - NÃO consulta tabelas de apontamentos

CREATE OR REPLACE FUNCTION public.validate_hh_lancamento()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id UUID;
  v_cliente_id BIGINT;
  v_servico_ativo BOOLEAN;
  v_vinculo_ativo BOOLEAN;
BEGIN
  -- 1) Obter tenant_id da linha
  v_tenant_id := NEW.tenant_id;
  
  -- 2) Obter cliente_id da OS
  SELECT cliente_id INTO v_cliente_id
  FROM public.ordens_servico
  WHERE id = NEW.os_id
    AND tenant_id = v_tenant_id;
  
  -- Se não encontrou a OS, permitir (RLS vai bloquear se necessário)
  IF v_cliente_id IS NULL THEN
    RETURN NEW;
  END IF;
  
  -- 3) Verificar se o serviço HH existe e está ativo
  SELECT EXISTS (
    SELECT 1
    FROM public.cliente_hh_servicos
    WHERE id = NEW.hh_tipo_id
      AND tenant_id = v_tenant_id
      AND cliente_id = v_cliente_id
      AND ativo = true
  ) INTO v_servico_ativo;
  
  IF NOT v_servico_ativo THEN
    RAISE EXCEPTION 
      'Serviço HH % não existe ou está inativo para o cliente %.',
      NEW.hh_tipo_id, v_cliente_id
      USING ERRCODE = '23503'; -- foreign_key_violation
  END IF;
  
  -- 4) Verificar se existe vínculo ativo do colaborador com este serviço HH para o cliente
  SELECT EXISTS (
    SELECT 1
    FROM public.colaborador_funcao_hh
    WHERE tenant_id = v_tenant_id
      AND cliente_id = v_cliente_id
      AND colaborador_id = NEW.colaborador_id
      AND servico_hh_id = NEW.hh_tipo_id
      AND ativo = true
  ) INTO v_vinculo_ativo;
  
  IF NOT v_vinculo_ativo THEN
    RAISE EXCEPTION 
      'Serviço HH % não está vinculado ao colaborador % para o cliente %.',
      NEW.hh_tipo_id, NEW.colaborador_id, v_cliente_id
      USING ERRCODE = '23503'; -- foreign_key_violation
  END IF;
  
  RETURN NEW;
END;
$$;

-- Criar trigger BEFORE INSERT e UPDATE em hh_lancamentos
DROP TRIGGER IF EXISTS trigger_validate_hh_lancamento ON public.hh_lancamentos;

CREATE TRIGGER trigger_validate_hh_lancamento
  BEFORE INSERT OR UPDATE OF colaborador_id, hh_tipo_id
  ON public.hh_lancamentos
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_hh_lancamento();

-- ============================================================================
-- PASSO 3: SINCRONIZAR DADOS (se houver colaborador_cliente_funcao, copiar para colaborador_funcao_hh)
-- ============================================================================
--
-- Se houver tabela "colaborador_cliente_funcao" por algum motivo,
-- tenta sincronizar dados para colaborador_funcao_hh

DO $$
BEGIN
  -- Verificar se a tabela colaborador_cliente_funcao existe
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'colaborador_cliente_funcao'
  ) THEN
    -- Copiar dados de colaborador_cliente_funcao para colaborador_funcao_hh
    INSERT INTO public.colaborador_funcao_hh (
      tenant_id,
      cliente_id,
      colaborador_id,
      servico_hh_id,
      ativo,
      criado_em,
      atualizado_em
    )
    SELECT
      ccf.tenant_id,
      ccf.cliente_id,
      ccf.colaborador_id,
      ccf.hh_servico_id,
      ccf.ativo,
      NOW(),
      NOW()
    FROM public.colaborador_cliente_funcao ccf
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.colaborador_funcao_hh cfh
      WHERE cfh.tenant_id = ccf.tenant_id
        AND cfh.cliente_id = ccf.cliente_id
        AND cfh.colaborador_id = ccf.colaborador_id
        AND cfh.servico_hh_id = ccf.hh_servico_id
    )
    ON CONFLICT (tenant_id, cliente_id, colaborador_id, servico_hh_id) DO NOTHING;
    
    RAISE NOTICE 'Dados sincronizados de colaborador_cliente_funcao para colaborador_funcao_hh';
  END IF;
END $$;

-- ============================================================================
-- PASSO 4: DOCUMENTAR AS MUDANÇAS
-- ============================================================================

COMMENT ON FUNCTION public.validate_apontamento_colaborador_contrato() IS 
  'Valida que o colaborador do apontamento está vinculado ao contrato do cliente da OS (via colaborador_funcao_hh)';

COMMENT ON FUNCTION public.validate_hh_lancamento() IS 
  'Valida que o serviço HH existe, está ativo, e o colaborador está vinculado a ele para o cliente da OS (via colaborador_funcao_hh). NÃO consulta relatório. NÃO usa empresa_id.';

-- ============================================================================
-- PASSO 5: NOTAS IMPORTANTES
-- ============================================================================

-- ✅ O que foi REMOVIDO:
-- - Referências a "colaborador_cliente_funcao" (tabela que não existe)
-- - Validações que tentavam usar "empresa_id" em validações simples
-- - Qualquer dependência de HH com tabelas de relatório
--
-- ✅ O que foi ADICIONADO:
-- - Validação correta usando "colaborador_funcao_hh" (tabela real)
-- - Verificação de que o serviço HH existe e está ativo
-- - Sincronização automática de dados se houver tabela legada
--
-- ✅ O que PERMANECE IGUAL:
-- - RLS policies em hh_lancamentos (tenant_id + empresa_id)
-- - Trigger para cálculo de horas e valores
-- - View vw_hh_lancamentos intacta
-- - Todos os dados de lançamento já existentes

COMMIT;

NOTIFY pgrst, 'reload schema';
