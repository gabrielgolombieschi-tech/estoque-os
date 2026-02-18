BEGIN;

-- 1) Adicionar flag habilita_servico_hh na tabela empresas
ALTER TABLE empresas 
  ADD COLUMN IF NOT EXISTS habilita_servico_hh BOOLEAN NOT NULL DEFAULT false;

-- 2) Criar tabela cliente_hh_servicos
CREATE TABLE IF NOT EXISTS cliente_hh_servicos (
  id BIGSERIAL PRIMARY KEY,
  tenant_id UUID NOT NULL,
  empresa_id UUID NOT NULL,
  cliente_id BIGINT NOT NULL,
  
  nome TEXT NOT NULL,
  descricao TEXT,
  
  preco_base NUMERIC(15,2) NOT NULL DEFAULT 0,
  preco_50 NUMERIC(15,2) NOT NULL DEFAULT 0,   -- 50% acréscimo
  preco_100 NUMERIC(15,2) NOT NULL DEFAULT 0,  -- 100% acréscimo
  
  ativo BOOLEAN NOT NULL DEFAULT true,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  criado_por TEXT,
  
  -- Cliente deve existir na tabela clientes
  CONSTRAINT fk_cliente_hh_servicos_cliente 
    FOREIGN KEY (cliente_id) 
    REFERENCES clientes(id) 
    ON DELETE CASCADE,
  
  -- Não permitir duplicatas de nome por cliente
  CONSTRAINT uk_cliente_hh_servicos_nome 
    UNIQUE(tenant_id, empresa_id, cliente_id, nome)
);

-- 3) Índices para performance
CREATE INDEX IF NOT EXISTS idx_cliente_hh_servicos_tenant_empresa 
  ON cliente_hh_servicos(tenant_id, empresa_id);

CREATE INDEX IF NOT EXISTS idx_cliente_hh_servicos_cliente 
  ON cliente_hh_servicos(cliente_id);

CREATE INDEX IF NOT EXISTS idx_cliente_hh_servicos_ativo 
  ON cliente_hh_servicos(ativo) WHERE ativo = true;

-- 4) Trigger para atualizar atualizado_em
CREATE OR REPLACE FUNCTION update_cliente_hh_servicos_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.atualizado_em = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cliente_hh_servicos_updated_at ON cliente_hh_servicos;
CREATE TRIGGER trg_cliente_hh_servicos_updated_at
  BEFORE UPDATE ON cliente_hh_servicos
  FOR EACH ROW
  EXECUTE FUNCTION update_cliente_hh_servicos_updated_at();

-- 5) RLS policies
ALTER TABLE cliente_hh_servicos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cliente_hh_servicos_tenant_empresa_policy ON cliente_hh_servicos;
CREATE POLICY cliente_hh_servicos_tenant_empresa_policy 
  ON cliente_hh_servicos 
  FOR ALL
  USING (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
      OR public.can('apontamentos', 'read')
      OR public.can('apontamentos', 'write')
    )
  );

-- 6) Permissões básicas (authenticated users podem ler/escrever via RLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON cliente_hh_servicos TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE cliente_hh_servicos_id_seq TO authenticated;

-- 7) Comentários para documentação
COMMENT ON TABLE cliente_hh_servicos IS 'Serviços de HH (Hora-Homem) específicos por cliente, com preços em 3 níveis: base, 50% e 100%';
COMMENT ON COLUMN cliente_hh_servicos.preco_base IS 'Preço base do serviço (ex: R$ 100,00)';
COMMENT ON COLUMN cliente_hh_servicos.preco_50 IS 'Preço com acréscimo de 50% (ex: R$ 150,00)';
COMMENT ON COLUMN cliente_hh_servicos.preco_100 IS 'Preço com acréscimo de 100% (ex: R$ 200,00)';

NOTIFY pgrst, 'reload schema';

COMMIT;
