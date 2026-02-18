-- Fix: Substituir referência de hh_tabela_precos (deletada) por tipos_horas
-- hh_lancamentos.hh_tipo_id ainda é BIGINT, mas usará mapeamento para tipos_horas UUID

-- 1. Criar tabela de mapeamento: tipos_horas UUID → hh_tipos BIGINT
CREATE TABLE IF NOT EXISTS public.hh_tipos_mapping (
  id BIGSERIAL PRIMARY KEY,
  tipo_hora_id UUID NOT NULL UNIQUE REFERENCES public.tipos_horas(id) ON DELETE CASCADE,
  hh_tipo_id BIGINT NOT NULL UNIQUE,
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  ativo BOOLEAN NOT NULL DEFAULT true,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT tipos_horas_mapping_uk UNIQUE (tenant_id, tipo_hora_id)
);

CREATE INDEX IF NOT EXISTS idx_hh_tipos_mapping_tenant ON public.hh_tipos_mapping(tenant_id);
CREATE INDEX IF NOT EXISTS idx_hh_tipos_mapping_tipo_hora ON public.hh_tipos_mapping(tipo_hora_id);

-- 2. Remover constraint FK em hh_lancamentos se existir
ALTER TABLE IF EXISTS public.hh_lancamentos
DROP CONSTRAINT IF EXISTS hh_lancamentos_hh_tipo_id_fkey;

-- 3. Adicionar nova constraint referenciando hh_tipos_mapping (indiretamente tipos_horas)
-- Nota: Isso é uma solução temporária. Ideal seria alterar hh_tipo_id para UUID,
-- mas mantemos BIGINT para compatibilidade com triggers existentes.
ALTER TABLE public.hh_lancamentos
ADD CONSTRAINT hh_lancamentos_hh_tipo_id_fkey 
FOREIGN KEY (hh_tipo_id) REFERENCES public.hh_tipos_mapping(hh_tipo_id) ON DELETE RESTRICT;

-- 4. Criar tipos padrões (um por tenant)
-- Assume que ja existe ao menos um tenant. Executar script separado se necessário.
DO $$
DECLARE
  v_tenant_id UUID;
  v_tipo_hora_id UUID;
  v_next_hh_tipo_id BIGINT;
BEGIN
  -- Obter primeiro tenant
  SELECT id INTO v_tenant_id FROM public.tenants LIMIT 1;
  
  IF v_tenant_id IS NOT NULL THEN
    -- Obter primeiro tipo_horas para este tenant
    SELECT id INTO v_tipo_hora_id 
    FROM public.tipos_horas 
    WHERE tenant_id = v_tenant_id
    AND ativo = true
    ORDER BY codigo ASC 
    LIMIT 1;
    
    IF v_tipo_hora_id IS NOT NULL THEN
      -- Obter próximo hh_tipo_id disponível
      SELECT COALESCE(MAX(hh_tipo_id), 0) + 1 INTO v_next_hh_tipo_id 
      FROM public.hh_tipos_mapping;
      
      -- Inserir mapeamento
      INSERT INTO public.hh_tipos_mapping (tipo_hora_id, hh_tipo_id, tenant_id)
      VALUES (v_tipo_hora_id, v_next_hh_tipo_id, v_tenant_id)
      ON CONFLICT (tenant_id, tipo_hora_id) DO NOTHING;
      
      RAISE NOTICE 'Mapeamento criado: tipos_horas % → hh_tipo_id %', v_tipo_hora_id, v_next_hh_tipo_id;
    END IF;
  END IF;
END $$;

-- 5. Criar função auxiliar para resolver hh_tipo_id a partir de tipos_horas
CREATE OR REPLACE FUNCTION public.get_hh_tipo_id_for_tenant(p_tenant_id UUID)
RETURNS BIGINT AS $$
DECLARE
  v_hh_tipo_id BIGINT;
BEGIN
  -- Busca primeiro mapeamento ativo para o tenant
  SELECT hh_tipo_id INTO v_hh_tipo_id
  FROM public.hh_tipos_mapping
  WHERE tenant_id = p_tenant_id AND ativo = true
  LIMIT 1;
  
  RETURN v_hh_tipo_id;
END;
$$ LANGUAGE plpgsql STABLE;

-- 6. Adicionar comentários
COMMENT ON TABLE public.hh_tipos_mapping IS 'Mapeamento entre tipos_horas (UUID) e hh_lancamentos.hh_tipo_id (BIGINT)';
COMMENT ON FUNCTION public.get_hh_tipo_id_for_tenant(UUID) IS 'Resolve hh_tipo_id padrão para um tenant baseado em tipos_horas';
