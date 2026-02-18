-- Adicionar coluna habilita_hh à tabela clientes
ALTER TABLE public.clientes
ADD COLUMN IF NOT EXISTS habilita_hh BOOLEAN DEFAULT FALSE NOT NULL;

-- Criar índice para melhor performance em queries
CREATE INDEX IF NOT EXISTS idx_clientes_habilita_hh ON public.clientes(habilita_hh);
