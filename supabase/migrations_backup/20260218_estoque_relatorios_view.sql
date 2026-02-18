-- View auxiliar para Relatórios de Estoque (Tab: Saldo em estoque)
-- Motivo: suportar filtro "Abaixo do mínimo" com paginação server-side.
-- A view é invoker-security (padrão), então RLS das tabelas subjacentes continua valendo.

CREATE OR REPLACE VIEW public.vw_estoque_saldo AS
SELECT
  e.item_id,
  e.quantidade_atual,
  e.localizacao,
  e.tenant_id,
  e.empresa_id,
  i.codigo_interno,
  i.nome AS item_nome,
  i.unidade_medida,
  i.custo_medio,
  i.estoque_minimo,
  i.estoque_ideal,
  i.fornecedor_id,
  i.finalidade,
  i.controla_estoque,
  f.nome AS fornecedor_nome,
  (e.quantidade_atual < COALESCE(i.estoque_minimo, 0)) AS abaixo_minimo,
  (e.quantidade_atual * COALESCE(i.custo_medio, 0)) AS valor_estoque
FROM public.estoque e
JOIN public.itens i ON i.id = e.item_id
LEFT JOIN public.fornecedores f ON f.id = i.fornecedor_id
WHERE COALESCE(i.controla_estoque, false) = true;
