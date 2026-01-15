-- Tabela de lançamentos HH (por OS, com entrada/saída)
CREATE TABLE IF NOT EXISTS public.hh_lancamentos (
  id BIGSERIAL PRIMARY KEY,
  tenant_id UUID NOT NULL,
  empresa_id UUID NOT NULL,
  os_id BIGINT NOT NULL REFERENCES public.ordens_servico(id) ON DELETE CASCADE,
  colaborador_id UUID NOT NULL REFERENCES public.colaboradores(id) ON DELETE RESTRICT,
  hh_tipo_id BIGINT NOT NULL REFERENCES public.hh_tabela_precos(id) ON DELETE RESTRICT,
  
  data DATE NOT NULL,
  hora_entrada TIME NOT NULL,
  hora_saida TIME NOT NULL,
  horas_trabalhadas NUMERIC(10,2) NOT NULL DEFAULT 0,
  
  percentual_aplicado INTEGER NOT NULL DEFAULT 0 CHECK (percentual_aplicado IN (0, 50, 100)),
  valor_hora NUMERIC(10,2) NOT NULL DEFAULT 0,
  valor_total NUMERIC(10,2) NOT NULL DEFAULT 0,
  
  observacao TEXT,
  criado_por TEXT,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_hh_lancamentos_tenant ON public.hh_lancamentos(tenant_id);
CREATE INDEX IF NOT EXISTS idx_hh_lancamentos_empresa ON public.hh_lancamentos(empresa_id);
CREATE INDEX IF NOT EXISTS idx_hh_lancamentos_os ON public.hh_lancamentos(os_id);
CREATE INDEX IF NOT EXISTS idx_hh_lancamentos_colaborador ON public.hh_lancamentos(colaborador_id);
CREATE INDEX IF NOT EXISTS idx_hh_lancamentos_data ON public.hh_lancamentos(data);

-- RLS Policies
ALTER TABLE public.hh_lancamentos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS hh_lancamentos_tenant_isolation ON public.hh_lancamentos;
CREATE POLICY hh_lancamentos_tenant_isolation ON public.hh_lancamentos
  USING (tenant_id = current_tenant_id());

DROP POLICY IF EXISTS hh_lancamentos_select ON public.hh_lancamentos;
CREATE POLICY hh_lancamentos_select ON public.hh_lancamentos
  FOR SELECT
  USING (
    tenant_id = current_tenant_id() 
    AND empresa_id = current_empresa_id()
    AND public.can('os', 'read')
  );

DROP POLICY IF EXISTS hh_lancamentos_insert ON public.hh_lancamentos;
CREATE POLICY hh_lancamentos_insert ON public.hh_lancamentos
  FOR INSERT
  WITH CHECK (
    tenant_id = current_tenant_id() 
    AND empresa_id = current_empresa_id()
    AND public.can('os', 'write')
  );

DROP POLICY IF EXISTS hh_lancamentos_update ON public.hh_lancamentos;
CREATE POLICY hh_lancamentos_update ON public.hh_lancamentos
  FOR UPDATE
  USING (
    tenant_id = current_tenant_id() 
    AND empresa_id = current_empresa_id()
    AND public.can('os', 'write')
  );

DROP POLICY IF EXISTS hh_lancamentos_delete ON public.hh_lancamentos;
CREATE POLICY hh_lancamentos_delete ON public.hh_lancamentos
  FOR DELETE
  USING (
    tenant_id = current_tenant_id() 
    AND empresa_id = current_empresa_id()
    AND public.can('os', 'delete')
  );

-- Function para calcular horas e valores automaticamente
CREATE OR REPLACE FUNCTION public.calculate_hh_lancamento()
RETURNS TRIGGER AS $$
DECLARE
  v_preco NUMERIC(10,2);
BEGIN
  -- Calcular horas trabalhadas (hora_saida - hora_entrada)
  NEW.horas_trabalhadas := EXTRACT(EPOCH FROM (NEW.hora_saida - NEW.hora_entrada)) / 3600.0;
  
  -- Se horas negativas (passou meia-noite), adicionar 24h
  IF NEW.horas_trabalhadas < 0 THEN
    NEW.horas_trabalhadas := NEW.horas_trabalhadas + 24;
  END IF;
  
  -- Buscar valor da hora conforme percentual aplicado
  SELECT 
    CASE 
      WHEN NEW.percentual_aplicado = 50 THEN preco_50
      WHEN NEW.percentual_aplicado = 100 THEN preco_100
      ELSE preco_base
    END
  INTO v_preco
  FROM public.hh_tabela_precos
  WHERE id = NEW.hh_tipo_id;
  
  NEW.valor_hora := COALESCE(v_preco, 0);
  NEW.valor_total := NEW.horas_trabalhadas * NEW.valor_hora;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger para calcular valores antes de INSERT/UPDATE
DROP TRIGGER IF EXISTS hh_lancamentos_calculate ON public.hh_lancamentos;
CREATE TRIGGER hh_lancamentos_calculate
  BEFORE INSERT OR UPDATE ON public.hh_lancamentos
  FOR EACH ROW
  EXECUTE FUNCTION public.calculate_hh_lancamento();

-- View para consulta com joins
CREATE OR REPLACE VIEW public.vw_hh_lancamentos AS
SELECT 
  hl.id,
  hl.tenant_id,
  hl.empresa_id,
  hl.os_id,
  os.numero_os,
  hl.colaborador_id,
  c.nome AS colaborador_nome,
  hl.hh_tipo_id,
  ht.descricao AS hh_tipo_descricao,
  ht.nivel AS hh_tipo_nivel,
  ht.categoria AS hh_tipo_categoria,
  hl.data,
  hl.hora_entrada,
  hl.hora_saida,
  hl.horas_trabalhadas,
  hl.percentual_aplicado,
  hl.valor_hora,
  hl.valor_total,
  hl.observacao,
  hl.criado_por,
  hl.criado_em,
  hl.atualizado_em
FROM public.hh_lancamentos hl
LEFT JOIN public.colaboradores c ON c.id = hl.colaborador_id
LEFT JOIN public.hh_tabela_precos ht ON ht.id = hl.hh_tipo_id
LEFT JOIN public.ordens_servico os ON os.id = hl.os_id;

-- Permissões na view
GRANT SELECT ON public.vw_hh_lancamentos TO authenticated;

-- RLS na view (herda das tabelas base)
ALTER VIEW public.vw_hh_lancamentos SET (security_invoker = on);

COMMENT ON TABLE public.hh_lancamentos IS 'Lançamentos de HH por OS (entrada/saída) com tabela negociada';
COMMENT ON VIEW public.vw_hh_lancamentos IS 'View com joins para consulta de lançamentos HH';
