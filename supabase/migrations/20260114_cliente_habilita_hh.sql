BEGIN;
-- Adicionar flag habilita_hh na tabela clientes
ALTER TABLE clientes 
  ADD COLUMN IF NOT EXISTS habilita_hh BOOLEAN NOT NULL DEFAULT false;
-- Comentário para documentação
COMMENT ON COLUMN clientes.habilita_hh IS 'Indica se o cliente utiliza relatórios de Hora-Homem (HH)';
NOTIFY pgrst, 'reload schema';
COMMIT;
