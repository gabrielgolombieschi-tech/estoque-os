BEGIN;

-- ============================================================================
-- Migration: Constraints, FKs, Índices e RLS para colaborador_cliente_funcao
-- Data: 2026-01-14
-- Descrição: Adiciona integridade referencial, índices e políticas RLS para
--            vínculos de colaboradores × clientes × funções HH
-- ============================================================================

-- 1) Foreign Keys (se não existirem)
-- ============================================================================

DO $$
BEGIN
  -- FK para clientes
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_colaborador_cliente_funcao_cliente'
  ) THEN
    ALTER TABLE public.colaborador_cliente_funcao
      ADD CONSTRAINT fk_colaborador_cliente_funcao_cliente
      FOREIGN KEY (cliente_id)
      REFERENCES public.clientes(id)
      ON DELETE CASCADE;
  END IF;

  -- FK para colaboradores
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_colaborador_cliente_funcao_colaborador'
  ) THEN
    ALTER TABLE public.colaborador_cliente_funcao
      ADD CONSTRAINT fk_colaborador_cliente_funcao_colaborador
      FOREIGN KEY (colaborador_id)
      REFERENCES public.colaboradores(id)
      ON DELETE CASCADE;
  END IF;

  -- FK para cliente_hh_servicos
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_colaborador_cliente_funcao_servico'
  ) THEN
    ALTER TABLE public.colaborador_cliente_funcao
      ADD CONSTRAINT fk_colaborador_cliente_funcao_servico
      FOREIGN KEY (hh_servico_id)
      REFERENCES public.cliente_hh_servicos(id)
      ON DELETE CASCADE;
  END IF;
END $$;

-- 2) Constraint Unique (evitar duplicação de vínculos)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'unique_colab_cliente_funcao'
  ) THEN
    ALTER TABLE public.colaborador_cliente_funcao
      ADD CONSTRAINT unique_colab_cliente_funcao
      UNIQUE (tenant_id, cliente_id, colaborador_id, hh_servico_id);
  END IF;
END $$;

-- 3) Índices para performance
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_colaborador_cliente_funcao_tenant
  ON public.colaborador_cliente_funcao(tenant_id);

CREATE INDEX IF NOT EXISTS idx_colaborador_cliente_funcao_cliente
  ON public.colaborador_cliente_funcao(tenant_id, cliente_id);

CREATE INDEX IF NOT EXISTS idx_colaborador_cliente_funcao_colaborador
  ON public.colaborador_cliente_funcao(tenant_id, colaborador_id);

CREATE INDEX IF NOT EXISTS idx_colaborador_cliente_funcao_servico
  ON public.colaborador_cliente_funcao(tenant_id, hh_servico_id);

CREATE INDEX IF NOT EXISTS idx_colaborador_cliente_funcao_ativo
  ON public.colaborador_cliente_funcao(ativo)
  WHERE ativo = true;

-- 4) Trigger para atualizar updated_at automaticamente
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_colaborador_cliente_funcao_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.atualizado_em = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_colaborador_cliente_funcao_updated_at
  ON public.colaborador_cliente_funcao;

CREATE TRIGGER trigger_update_colaborador_cliente_funcao_updated_at
  BEFORE UPDATE ON public.colaborador_cliente_funcao
  FOR EACH ROW
  EXECUTE FUNCTION public.update_colaborador_cliente_funcao_updated_at();

-- 5) RLS Policies
-- ============================================================================

-- Habilitar RLS se ainda não estiver
ALTER TABLE public.colaborador_cliente_funcao ENABLE ROW LEVEL SECURITY;

-- Drop policies antigas se existirem
DROP POLICY IF EXISTS colaborador_cliente_funcao_tenant_isolation ON public.colaborador_cliente_funcao;
DROP POLICY IF EXISTS colaborador_cliente_funcao_select ON public.colaborador_cliente_funcao;
DROP POLICY IF EXISTS colaborador_cliente_funcao_insert ON public.colaborador_cliente_funcao;
DROP POLICY IF EXISTS colaborador_cliente_funcao_update ON public.colaborador_cliente_funcao;
DROP POLICY IF EXISTS colaborador_cliente_funcao_delete ON public.colaborador_cliente_funcao;

-- SELECT: qualquer usuário do tenant com permissão HH.read
CREATE POLICY colaborador_cliente_funcao_select
  ON public.colaborador_cliente_funcao
  FOR SELECT
  USING (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
      OR public.can('apontamentos', 'read')
    )
  );

-- INSERT: usuários com permissão HH.write
CREATE POLICY colaborador_cliente_funcao_insert
  ON public.colaborador_cliente_funcao
  FOR INSERT
  WITH CHECK (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
    )
  );

-- UPDATE: usuários com permissão HH.write
CREATE POLICY colaborador_cliente_funcao_update
  ON public.colaborador_cliente_funcao
  FOR UPDATE
  USING (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
    )
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
    )
  );

-- DELETE: usuários com permissão HH.write (admin ou financeiro)
CREATE POLICY colaborador_cliente_funcao_delete
  ON public.colaborador_cliente_funcao
  FOR DELETE
  USING (
    tenant_id = public.current_tenant_id()
    AND (
      public.can('admin', 'manage_users')
      OR public.can('financeiro', 'read')
    )
  );

-- 6) Comentários para documentação
-- ============================================================================

COMMENT ON TABLE public.colaborador_cliente_funcao IS 'Vínculos entre colaboradores e funções/serviços HH por cliente';
COMMENT ON COLUMN public.colaborador_cliente_funcao.tenant_id IS 'Tenant proprietário do vínculo';
COMMENT ON COLUMN public.colaborador_cliente_funcao.cliente_id IS 'Cliente para o qual o colaborador presta serviço';
COMMENT ON COLUMN public.colaborador_cliente_funcao.colaborador_id IS 'Colaborador vinculado';
COMMENT ON COLUMN public.colaborador_cliente_funcao.hh_servico_id IS 'Serviço/especialidade HH atribuída ao colaborador neste cliente';
COMMENT ON COLUMN public.colaborador_cliente_funcao.ativo IS 'Se false, vínculo foi desativado (soft delete)';

COMMIT;

NOTIFY pgrst, 'reload schema';
