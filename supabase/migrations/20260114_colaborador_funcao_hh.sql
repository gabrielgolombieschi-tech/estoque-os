-- Vínculo entre Colaboradores e Serviços HH (Funções)
-- Um colaborador pode ter uma ou mais funções/especialidades

CREATE TABLE IF NOT EXISTS public.colaborador_funcao_hh (
  id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  cliente_id BIGINT NOT NULL REFERENCES public.clientes(id) ON DELETE CASCADE,
  colaborador_id UUID NOT NULL REFERENCES public.colaboradores(id) ON DELETE CASCADE,
  servico_hh_id BIGINT NOT NULL REFERENCES public.cliente_hh_servicos(id) ON DELETE CASCADE,
  ativo BOOLEAN DEFAULT TRUE,
  criado_em TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  atualizado_em TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT colaborador_funcao_hh_unique UNIQUE(tenant_id, cliente_id, colaborador_id, servico_hh_id)
);

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_colaborador_funcao_hh_tenant_id ON public.colaborador_funcao_hh(tenant_id);
CREATE INDEX IF NOT EXISTS idx_colaborador_funcao_hh_cliente_id ON public.colaborador_funcao_hh(cliente_id);
CREATE INDEX IF NOT EXISTS idx_colaborador_funcao_hh_colaborador_id ON public.colaborador_funcao_hh(colaborador_id);
CREATE INDEX IF NOT EXISTS idx_colaborador_funcao_hh_servico_hh_id ON public.colaborador_funcao_hh(servico_hh_id);

-- RLS (Row Level Security)
ALTER TABLE public.colaborador_funcao_hh ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS colaborador_funcao_hh_select ON public.colaborador_funcao_hh;
DROP POLICY IF EXISTS colaborador_funcao_hh_insert ON public.colaborador_funcao_hh;
DROP POLICY IF EXISTS colaborador_funcao_hh_update ON public.colaborador_funcao_hh;
DROP POLICY IF EXISTS colaborador_funcao_hh_delete ON public.colaborador_funcao_hh;

-- Policy: Usuários podem ver vinculações do seu tenant
CREATE POLICY colaborador_funcao_hh_select ON public.colaborador_funcao_hh
  FOR SELECT
  USING (
    tenant_id = public.current_tenant_id()
  );

-- Policy: Usuários podem inserir se tiverem a permissão
CREATE POLICY colaborador_funcao_hh_insert ON public.colaborador_funcao_hh
  FOR INSERT
  WITH CHECK (
    tenant_id = public.current_tenant_id() AND
    public.can('apontamentos', 'write')
  );

-- Policy: Usuários podem atualizar
CREATE POLICY colaborador_funcao_hh_update ON public.colaborador_funcao_hh
  FOR UPDATE
  USING (
    tenant_id = public.current_tenant_id() AND
    public.can('apontamentos', 'write')
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id() AND
    public.can('apontamentos', 'write')
  );

-- Policy: Usuários podem deletar
CREATE POLICY colaborador_funcao_hh_delete ON public.colaborador_funcao_hh
  FOR DELETE
  USING (
    tenant_id = public.current_tenant_id() AND
    public.can('apontamentos', 'write')
  );

-- Trigger para atualizar atualizado_em
DROP TRIGGER IF EXISTS colaborador_funcao_hh_update_timestamp ON public.colaborador_funcao_hh;
CREATE TRIGGER colaborador_funcao_hh_update_timestamp
  BEFORE UPDATE ON public.colaborador_funcao_hh
  FOR EACH ROW
  EXECUTE FUNCTION public.update_timestamp();

COMMENT ON TABLE public.colaborador_funcao_hh IS 'Vínculo entre colaboradores e serviços de HH (funções/especialidades) por cliente';
COMMENT ON COLUMN public.colaborador_funcao_hh.tenant_id IS 'Tenant (organização)';
COMMENT ON COLUMN public.colaborador_funcao_hh.cliente_id IS 'Cliente relacionado';
COMMENT ON COLUMN public.colaborador_funcao_hh.colaborador_id IS 'Colaborador (funcionário)';
COMMENT ON COLUMN public.colaborador_funcao_hh.servico_hh_id IS 'Serviço de HH (função/especialidade) do cliente';
