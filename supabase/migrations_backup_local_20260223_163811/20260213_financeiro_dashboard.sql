begin;

-- Drop functions if they exist to allow idempotent migration
-- COMENTADO: Requer tabelas financeiro_movimentos, financeiro_titulos, etc.
-- DROP FUNCTION IF EXISTS public.financeiro_dashboard_resumo(uuid, date, date, text, text, uuid, bigint, text);
-- DROP FUNCTION IF EXISTS public.financeiro_titulos_listar(uuid, date, date, text, text, uuid, bigint, text, integer, integer);

-- Resumo do painel financeiro
-- COMENTADO: Será criado quando a infraestrutura de financeiro estiver pronta
/*
CREATE FUNCTION public.financeiro_dashboard_resumo(
  p_tenant_id uuid,
  p_data_ini date,
  p_data_fim date,
  p_status text,
  p_natureza text,
  p_categoria_id uuid,
  p_fornecedor_id bigint,
  p_q text
) RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
WITH titulos AS (
  -- Prefer view if present
  SELECT t.id, t.tenant_id, t.natureza, t.status, t.descricao, t.documento_ref, t.vencimento,
         t.valor_original, t.total_baixado, t.saldo, t.atrasado, t.categoria_id
  FROM public.vw_financeiro_titulos_com_saldo t
  WHERE t.tenant_id = p_tenant_id
    AND (p_status IS NULL OR p_status = '' OR t.status = p_status::public.financeiro_status_titulo)
    AND (p_natureza IS NULL OR p_natureza = '' OR t.natureza = p_natureza::public.financeiro_natureza_titulo)
    AND (p_categoria_id IS NULL OR t.categoria_id = p_categoria_id)
    AND (
      p_q IS NULL OR p_q = '' OR
      (lower(t.descricao) LIKE ('%' || lower(p_q) || '%') OR lower(coalesce(t.documento_ref, '')) LIKE ('%' || lower(p_q) || '%'))
    )
), movimentos AS (
  SELECT m.id, m.titulo_id, m.tenant_id, m.data_movimento,
         coalesce(m.valor, 0) + coalesce(m.juros, 0) + coalesce(m.multa, 0) - coalesce(m.desconto, 0) AS valor_liquido
  FROM public.financeiro_movimentos m
  WHERE m.tenant_id = p_tenant_id
    AND m.data_movimento BETWEEN p_data_ini AND p_data_fim
), mov_sum AS (
  SELECT t.natureza,
         SUM(CASE WHEN t.natureza = 'RECEBER' THEN m.valor_liquido ELSE 0 END) AS recebimentos_periodo,
         SUM(CASE WHEN t.natureza = 'PAGAR' THEN m.valor_liquido ELSE 0 END) AS pagamentos_periodo
  FROM movimentos m
  JOIN public.financeiro_titulos t ON t.id = m.titulo_id AND t.tenant_id = p_tenant_id
  WHERE (p_status IS NULL OR p_status = '' OR t.status = p_status::public.financeiro_status_titulo)
    AND (p_natureza IS NULL OR p_natureza = '' OR t.natureza = p_natureza::public.financeiro_natureza_titulo)
    AND (p_categoria_id IS NULL OR t.categoria_id = p_categoria_id)
    AND (
      p_q IS NULL OR p_q = '' OR
      (lower(t.descricao) LIKE ('%' || lower(p_q) || '%') OR lower(coalesce(t.documento_ref, '')) LIKE ('%' || lower(p_q) || '%'))
    )
  GROUP BY t.natureza
), atrasados AS (
  SELECT
    SUM(CASE WHEN natureza = 'RECEBER' AND status = 'ABERTO' AND vencimento < current_date THEN saldo ELSE 0 END) AS receber_atrasado,
    SUM(CASE WHEN natureza = 'PAGAR' AND status = 'ABERTO' AND vencimento < current_date THEN saldo ELSE 0 END) AS pagar_atrasado
  FROM titulos
), saldo_hoje AS (
  SELECT
    COALESCE((SELECT SUM(c.saldo_inicial) FROM public.financeiro_contas c WHERE c.tenant_id = p_tenant_id), 0)
    + COALESCE((
      SELECT SUM(
        CASE WHEN t.natureza = 'RECEBER' THEN m.valor_liquido ELSE -m.valor_liquido END
      )
      FROM public.financeiro_movimentos m
      JOIN public.financeiro_titulos t ON t.id = m.titulo_id AND t.tenant_id = p_tenant_id
      WHERE m.tenant_id = p_tenant_id AND m.data_movimento <= current_date
    ), 0) AS valor
), previsao_ate_fim AS (
  SELECT
    COALESCE(SUM(CASE WHEN natureza = 'RECEBER' AND status = 'ABERTO' AND vencimento BETWEEN current_date AND p_data_fim THEN saldo ELSE 0 END), 0) AS receber_previsto,
    COALESCE(SUM(CASE WHEN natureza = 'PAGAR' AND status = 'ABERTO' AND vencimento BETWEEN current_date AND p_data_fim THEN saldo ELSE 0 END), 0) AS pagar_previsto
  FROM titulos
)
SELECT jsonb_build_object(
  'saldoHoje', (SELECT valor FROM saldo_hoje),
  'recebimentosPeriodo', COALESCE((SELECT SUM(recebimentos_periodo) FROM mov_sum), 0),
  'pagamentosPeriodo', COALESCE((SELECT SUM(pagamentos_periodo) FROM mov_sum), 0),
  'receberAtrasado', (SELECT receber_atrasado FROM atrasados),
  'pagarAtrasado', (SELECT pagar_atrasado FROM atrasados),
  'saldoFinal', (SELECT valor FROM saldo_hoje) + (SELECT receber_previsto - pagar_previsto FROM previsao_ate_fim)
);
$$;
*/

-- Listagem de titulos com filtros (paginada)
-- COMENTADO: Requer tabelas financeiro_movimentos, financeiro_titulos, etc.
-- Será criado quando a infraestrutura de financeiro estiver pronta
/*
CREATE FUNCTION public.financeiro_titulos_listar(
  p_tenant_id uuid,
  p_data_ini date,
  p_data_fim date,
  p_status text,
  p_natureza text,
  p_categoria_id uuid,
  p_fornecedor_id bigint,
  p_q text,
  p_limit integer,
  p_offset integer
) RETURNS TABLE (
  id uuid,
  natureza text,
  status text,
  descricao text,
  documento_ref text,
  vencimento date,
  valor_original numeric,
  total_baixado numeric,
  saldo numeric,
  atrasado boolean,
  categoria_id uuid,
  fornecedor_nome text
)
LANGUAGE sql
STABLE
AS $$
WITH base AS (
  SELECT t.id, t.tenant_id, t.natureza, t.status, t.descricao, t.documento_ref, t.vencimento,
         t.valor_original, t.total_baixado, t.saldo, t.atrasado, t.categoria_id,
         COALESCE(f.nome, cl.nome, p.nome) AS fornecedor_nome
  FROM public.vw_financeiro_titulos_com_saldo t
  LEFT JOIN public.fornecedores f ON f.id = t.fornecedor_id AND f.tenant_id = t.tenant_id
  LEFT JOIN public.clientes cl ON cl.id = t.cliente_id AND cl.tenant_id = t.tenant_id
  LEFT JOIN public.pessoas p ON p.id = t.pessoa_id AND p.tenant_id = t.tenant_id
  WHERE t.tenant_id = p_tenant_id
    AND (p_status IS NULL OR p_status = '' OR t.status = p_status::public.financeiro_status_titulo)
    AND (p_natureza IS NULL OR p_natureza = '' OR t.natureza = p_natureza::public.financeiro_natureza_titulo)
    AND (p_categoria_id IS NULL OR t.categoria_id = p_categoria_id)
    AND (p_fornecedor_id IS NULL OR t.fornecedor_id = p_fornecedor_id OR t.cliente_id = p_fornecedor_id OR t.pessoa_id = p_fornecedor_id)
    AND (
      p_q IS NULL OR p_q = '' OR
      (lower(t.descricao) LIKE ('%' || lower(p_q) || '%') OR lower(coalesce(t.documento_ref, '')) LIKE ('%' || lower(p_q) || '%'))
    )
    AND (p_data_ini IS NULL OR t.vencimento >= p_data_ini)
    AND (p_data_fim IS NULL OR t.vencimento <= p_data_fim)
)
SELECT b.id, b.natureza, b.status, b.descricao, b.documento_ref, b.vencimento,
       b.valor_original, b.total_baixado, b.saldo, b.atrasado, b.categoria_id, b.fornecedor_nome
FROM base b
ORDER BY b.vencimento ASC
LIMIT COALESCE(p_limit, 500)
OFFSET COALESCE(p_offset, 0);
$$;
*/

-- Make sure PostgREST is aware of new functions, if applicable
DO $$ BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
EXCEPTION WHEN OTHERS THEN
  -- ignore if pgrst is not present
  NULL;
END $$;

commit;
