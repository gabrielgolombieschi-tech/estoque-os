BEGIN;

-- DEPRECATED: RPC complexa desabilitada em favor de geração de PDF cliente-side
-- Esta RPC tentava criar tabelas que não existem (cliente_hh_tabelas, etc)
-- A exportação de PDF agora é feita via gerarRelatorioPDF() no frontend
/*
-- RPC: gera relatorio de HH por OS (snapshot) com regras ERP (lucro real)
-- Retorna o id do relatorio e o total calculado
CREATE OR REPLACE FUNCTION public.gerar_relatorio_hh_os(
  p_os_id integer,
  p_periodo_inicio date,
  p_periodo_fim date
)
RETURNS TABLE (relatorio_id bigint, total numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_cliente_id bigint;
  v_tabela_hh_id bigint;
  v_relatorio_id bigint;
  v_total numeric := 0;
  v_ano int;
  v_missing_apontamento_id text;
  v_missing_valor_apontamento_id text;
BEGIN
  -- 1) Tenant obrigatorio
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Tenant nao definido (current_tenant_id retornou null).';
  END IF;

  IF p_periodo_inicio IS NULL OR p_periodo_fim IS NULL THEN
    RAISE EXCEPTION 'Periodo inicio e fim sao obrigatorios.';
  END IF;

  IF p_periodo_inicio > p_periodo_fim THEN
    RAISE EXCEPTION 'Periodo inicio maior que periodo fim.';
  END IF;

  -- 2) Descobrir cliente da OS
  SELECT os.cliente_id
    INTO v_cliente_id
  FROM public.ordens_servico os
  WHERE os.id = p_os_id
    AND os.tenant_id = v_tenant_id
  LIMIT 1;

  IF v_cliente_id IS NULL THEN
    RAISE EXCEPTION 'OS % nao encontrada ou sem cliente vinculado.', p_os_id;
  END IF;

  -- 3) Descobrir tabela HH ativa do cliente para o ano do periodo
  v_ano := EXTRACT(YEAR FROM p_periodo_inicio)::int;
  SELECT t.id
    INTO v_tabela_hh_id
  FROM public.cliente_hh_tabelas t
  WHERE t.tenant_id = v_tenant_id
    AND t.cliente_id = v_cliente_id
    AND t.ano = v_ano
    AND t.ativo = true
  ORDER BY t.criado_em DESC
  LIMIT 1;

  IF v_tabela_hh_id IS NULL THEN
    RAISE EXCEPTION 'Tabela HH ativa nao encontrada para cliente % no ano %.', v_cliente_id, v_ano;
  END IF;

  -- 4) Nao recalcular se ja existir relatorio fechado para a mesma OS e periodo
  IF EXISTS (
    SELECT 1
    FROM public.os_relatorios_hh r
    WHERE r.tenant_id = v_tenant_id
      AND r.os_id = p_os_id
      AND r.periodo_inicio = p_periodo_inicio
      AND r.periodo_fim = p_periodo_fim
      AND r.status = 'fechado'
  ) THEN
    RAISE EXCEPTION 'Relatorio HH ja fechado para OS % no periodo % a %.', p_os_id, p_periodo_inicio, p_periodo_fim;
  END IF;

  -- 5) Cria cabecalho (status fechado) com total 0 (sera atualizado no fim)
  INSERT INTO public.os_relatorios_hh (
    tenant_id,
    os_id,
    cliente_id,
    tabela_hh_id,
    periodo_inicio,
    periodo_fim,
    data_emissao,
    status,
    total
  ) VALUES (
    v_tenant_id,
    p_os_id,
    v_cliente_id,
    v_tabela_hh_id,
    p_periodo_inicio,
    p_periodo_fim,
    current_date,
    'fechado',
    0
  )
  RETURNING id INTO v_relatorio_id;

  -- 6) Validar especialidade: se nao houver, aborta com erro claro
  WITH base AS (
    SELECT
      ah.id AS apontamento_id,
      ah.colaborador_id,
      ah.data,
      ah.entrada_1,
      ah.saida_1,
      ah.entrada_2,
      ah.saida_2,
      ah.horas_trabalhadas,
      ah.tipo_hora_id,
      ah.fator_aplicado,
      COALESCE(ah.hh_especialidade_id, c.hh_especialidade_id) AS especialidade_id,
      th.codigo AS tipo_hora_codigo,
      th.fator AS tipo_hora_fator
    FROM public.apontamentos_horas ah
    LEFT JOIN public.colaboradores c ON c.id = ah.colaborador_id
    LEFT JOIN public.tipos_horas th ON th.id = ah.tipo_hora_id
    WHERE ah.tenant_id = v_tenant_id
      AND ah.os_id = p_os_id
      AND ah.data BETWEEN p_periodo_inicio AND p_periodo_fim
  )
  SELECT b.apontamento_id
    INTO v_missing_apontamento_id
  FROM base b
  WHERE b.especialidade_id IS NULL
  LIMIT 1;

  IF v_missing_apontamento_id IS NOT NULL THEN
    RAISE EXCEPTION 'Apontamento % sem especialidade (hh_especialidade_id).', v_missing_apontamento_id;
  END IF;

  -- 7) Validar valor_base da tabela HH para cada especialidade
  WITH base AS (
    SELECT
      ah.id AS apontamento_id,
      ah.colaborador_id,
      ah.data,
      ah.entrada_1,
      ah.saida_1,
      ah.entrada_2,
      ah.saida_2,
      ah.horas_trabalhadas,
      ah.tipo_hora_id,
      ah.fator_aplicado,
      COALESCE(ah.hh_especialidade_id, c.hh_especialidade_id) AS especialidade_id,
      th.codigo AS tipo_hora_codigo,
      th.fator AS tipo_hora_fator
    FROM public.apontamentos_horas ah
    LEFT JOIN public.colaboradores c ON c.id = ah.colaborador_id
    LEFT JOIN public.tipos_horas th ON th.id = ah.tipo_hora_id
    WHERE ah.tenant_id = v_tenant_id
      AND ah.os_id = p_os_id
      AND ah.data BETWEEN p_periodo_inicio AND p_periodo_fim
  ), enriched AS (
    SELECT
      b.*,
      ti.valor_base
    FROM base b
    LEFT JOIN public.cliente_hh_tabela_itens ti
      ON ti.tabela_hh_id = v_tabela_hh_id
     AND ti.hh_especialidade_id = b.especialidade_id
  )
  SELECT e.apontamento_id
    INTO v_missing_valor_apontamento_id
  FROM enriched e
  WHERE e.valor_base IS NULL
  LIMIT 1;

  IF v_missing_valor_apontamento_id IS NOT NULL THEN
    RAISE EXCEPTION 'Valor base nao encontrado na tabela HH para o apontamento %.', v_missing_valor_apontamento_id;
  END IF;

  -- 8) Inserir linhas (snapshot) com calculos financeiros
  WITH base AS (
    SELECT
      ah.id AS apontamento_id,
      ah.colaborador_id,
      ah.data,
      ah.entrada_1,
      ah.saida_1,
      ah.entrada_2,
      ah.saida_2,
      ah.horas_trabalhadas,
      ah.tipo_hora_id,
      ah.fator_aplicado,
      COALESCE(ah.hh_especialidade_id, c.hh_especialidade_id) AS especialidade_id,
      th.codigo AS tipo_hora_codigo,
      th.fator AS tipo_hora_fator
    FROM public.apontamentos_horas ah
    LEFT JOIN public.colaboradores c ON c.id = ah.colaborador_id
    LEFT JOIN public.tipos_horas th ON th.id = ah.tipo_hora_id
    WHERE ah.tenant_id = v_tenant_id
      AND ah.os_id = p_os_id
      AND ah.data BETWEEN p_periodo_inicio AND p_periodo_fim
  ), enriched AS (
    SELECT
      b.*,
      he.descricao AS especialidade_descricao,
      ti.valor_base,
      COALESCE(b.fator_aplicado, b.tipo_hora_fator, 1) AS fator_final
    FROM base b
    JOIN public.hh_especialidades he ON he.id = b.especialidade_id
    JOIN public.cliente_hh_tabela_itens ti
      ON ti.tabela_hh_id = v_tabela_hh_id
     AND ti.hh_especialidade_id = b.especialidade_id
  )
  INSERT INTO public.os_relatorios_hh_linhas (
    tenant_id,
    relatorio_id,
    colaborador_id,
    data,
    entrada_1,
    saida_1,
    entrada_2,
    saida_2,
    horas_trabalhadas,
    fator,
    tipo_hora_codigo,
    especialidade_descricao,
    valor_hora_base,
    valor_hora_aplicado,
    total
  )
  SELECT
    v_tenant_id,
    v_relatorio_id,
    e.colaborador_id,
    e.data,
    e.entrada_1,
    e.saida_1,
    e.entrada_2,
    e.saida_2,
    e.horas_trabalhadas,
    e.fator_final,
    e.tipo_hora_codigo,
    e.especialidade_descricao,
    e.valor_base,
    (e.valor_base * e.fator_final) AS valor_hora_aplicado,
    ROUND(e.horas_trabalhadas * (e.valor_base * e.fator_final), 2) AS total
  FROM enriched e;

  -- 9) Atualizar total no cabecalho (arredondamento financeiro)
  SELECT COALESCE(ROUND(SUM(l.total), 2), 0)
    INTO v_total
  FROM public.os_relatorios_hh_linhas l
  WHERE l.relatorio_id = v_relatorio_id;

  UPDATE public.os_relatorios_hh
     SET total = v_total
   WHERE id = v_relatorio_id;

  -- 10) Retorna id e total
  RETURN QUERY SELECT v_relatorio_id, v_total;
END;
$$;
*/

-- Recarrega schema no PostgREST
NOTIFY pgrst, 'reload schema';

COMMIT;
