-- Os financiamentos do Banco GM, VW Virtus e VW Polo pertencem a frota.
-- As parcelas foram criadas em DESP_GERAL, DESP_TRIBUTOS ou INVESTIMENTOS
-- e parte delas ficou sem centro de custo.
--
-- Isola as tres series em um motivo especifico, corrige todas as parcelas
-- existentes para DESP_FINANCIAMENTO/FROTA e configura a regra futura.
-- Valores, vencimentos, pagamentos e vinculos permanecem inalterados.

do $corrigir_financiamentos_veiculos_frota$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_plano_id uuid;
  v_centro_id uuid;
  v_motivo_id uuid;
  v_regra_id uuid;
  v_regra_resultado jsonb;
  v_correcao_resultado jsonb;
  v_titulo_ids uuid[];
  v_quantidade integer;
  v_pagos integer;
  v_pendentes integer;
  v_valor_total numeric;
begin
  select pc.id
    into strict v_plano_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_FINANCIAMENTO'
    and pc.nome = 'DESPESA - FINANCIAMENTOS / EMPRÉSTIMOS'
    and pc.tipo = 'ANALITICA'
    and pc.ativo
    and pc.deleted_at is null;

  select cc.id
    into strict v_centro_id
  from f.centro_custo cc
  where cc.tenant_id = v_tenant_id
    and cc.empresa_id = v_empresa_id
    and cc.codigo = 'FROTA'
    and cc.ativo
    and cc.deleted_at is null;

  if not exists (
    select 1
    from public.fornecedores fornecedor
    where fornecedor.id = 440
      and fornecedor.tenant_id = v_tenant_id
      and fornecedor.empresa_id = v_empresa_id
      and upper(btrim(fornecedor.nome)) = 'BANCO GM S.A'
      and fornecedor.ativo
  ) or not exists (
    select 1
    from public.fornecedores fornecedor
    where fornecedor.id = 414
      and fornecedor.tenant_id = v_tenant_id
      and fornecedor.empresa_id = v_empresa_id
      and upper(btrim(fornecedor.nome)) = 'BANCO VOLKSWAGEN S.A.'
      and fornecedor.ativo
  ) then
    raise exception
      'Os fornecedores dos financiamentos divergiram do contexto validado.';
  end if;

  select
    array_agg(t.id order by t.competencia_date, t.id),
    count(*)::integer,
    count(*) filter (where t.status = 'PAGO')::integer,
    count(*) filter (where t.status <> 'PAGO')::integer,
    sum(t.valor_total)
    into
      v_titulo_ids,
      v_quantidade,
      v_pagos,
      v_pendentes,
      v_valor_total
  from f.titulo t
  where t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id
    and t.tipo = 'AP'
    and t.status <> 'CANCELADO'
    and t.deleted_at is null
    and t.documento_fiscal_id is null
    and not f.titulo_eh_legado_implantacao(
      t.tenant_id,
      t.empresa_id,
      t.id
    )
    and (
      (
        t.fornecedor_id = 440
        and upper(btrim(t.descricao)) = 'FINANCIAMENTO'
        and t.valor_total = 2882.37
      )
      or (
        t.fornecedor_id = 414
        and upper(btrim(t.descricao)) like '%VIRTUS 60X'
        and t.valor_total = 2468.72
        and t.total_parcelas_serie = 60
      )
      or (
        t.fornecedor_id = 414
        and upper(btrim(t.descricao)) like '%POLO 60X'
        and t.valor_total = 2275.33
        and t.total_parcelas_serie = 60
      )
    );

  if v_quantidade <> 120
     or v_pagos <> 15
     or v_pendentes <> 105
     or v_valor_total <> 294849.90
  then
    raise exception
      'As series de financiamento divergiram: qtd %, pagos %, pendentes %, valor %.',
      v_quantidade,
      v_pagos,
      v_pendentes,
      v_valor_total;
  end if;

  if (
    select count(*)::integer
    from f.titulo t
    where t.id = any(v_titulo_ids)
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
      and (
        (
          t.fornecedor_id = 440
          and upper(btrim(t.descricao)) = 'FINANCIAMENTO'
          and t.valor_total = 2882.37
        )
        or (
          t.fornecedor_id = 414
          and upper(btrim(t.descricao)) like '%VIRTUS 60X'
          and t.valor_total = 2468.72
          and t.total_parcelas_serie = 60
        )
        or (
          t.fornecedor_id = 414
          and upper(btrim(t.descricao)) like '%POLO 60X'
          and t.valor_total = 2275.33
          and t.total_parcelas_serie = 60
        )
      )
  ) <> 120 then
    raise exception 'A lista de titulos dos financiamentos nao e estavel.';
  end if;

  -- Confirma um unico rateio integral por titulo, sem OS, antes da correcao.
  if (
    select count(*)::integer
    from f.titulo t
    join f.titulo_rateio tr
      on tr.tenant_id = t.tenant_id
     and tr.titulo_id = t.id
     and tr.deleted_at is null
    join f.plano_contas pc
      on pc.tenant_id = tr.tenant_id
     and pc.id = tr.plano_contas_id
     and pc.codigo in ('DESP_GERAL', 'DESP_TRIBUTOS', '4.02')
     and pc.deleted_at is null
    where t.id = any(v_titulo_ids)
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
      and tr.os_id is null
      and abs(tr.percentual - 100.0000) <= 0.0001
      and tr.valor = t.valor_total
      and not exists (
        select 1
        from f.titulo_rateio outro
        where outro.tenant_id = tr.tenant_id
          and outro.titulo_id = tr.titulo_id
          and outro.id <> tr.id
          and outro.deleted_at is null
      )
  ) <> 120 then
    raise exception
      'Os rateios originais dos financiamentos divergiram do contexto validado.';
  end if;

  -- Bloqueia os titulos durante a alteracao do lote.
  perform 1
  from f.titulo t
  where t.id = any(v_titulo_ids)
    and t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id
  order by t.id
  for update;

  insert into f.motivo_compra (
    tenant_id,
    codigo,
    nome,
    requires_text,
    requires_os,
    ativo,
    aplica_em,
    plano_contas_id,
    favorito,
    ordem,
    visivel_import_nfe
  )
  values (
    v_tenant_id,
    'FINANCIAMENTO_VEICULO_FROTA',
    'FINANCIAMENTO DE VEICULO - FROTA',
    false,
    false,
    true,
    'SERVICO',
    v_plano_id,
    true,
    832,
    false
  )
  on conflict (tenant_id, codigo)
  do update set
    nome = excluded.nome,
    requires_text = excluded.requires_text,
    requires_os = excluded.requires_os,
    ativo = excluded.ativo,
    aplica_em = excluded.aplica_em,
    plano_contas_id = excluded.plano_contas_id,
    favorito = excluded.favorito,
    ordem = excluded.ordem,
    visivel_import_nfe = excluded.visivel_import_nfe,
    updated_at = now(),
    deleted_at = null
  returning id into v_motivo_id;

  if exists (
    select 1
    from f.regra_rateio rr
    where rr.tenant_id = v_tenant_id
      and rr.empresa_id = v_empresa_id
      and rr.motivo_compra_id = v_motivo_id
      and rr.ativo
      and rr.deleted_at is null
  ) then
    raise exception
      'Ja existe regra ativa inesperada para FINANCIAMENTO_VEICULO_FROTA.';
  end if;

  -- O motivo e alterado antes da regra existir. Assim, os rateios antigos
  -- permanecem disponiveis para o historico da correcao centralizada.
  update f.titulo t
  set
    motivo_compra_id = v_motivo_id,
    updated_at = now()
  where t.id = any(v_titulo_ids)
    and t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id;

  update f.titulo_aprovacao ta
  set
    motivo_compra_id = v_motivo_id,
    change_reason =
      'Financiamento de veiculo da frota: plano de financiamento e centro Frota.',
    updated_at = now()
  where ta.tenant_id = v_tenant_id
    and ta.titulo_id = any(v_titulo_ids)
    and ta.deleted_at is null;

  perform set_config('request.jwt.claim.role', 'service_role', true);

  v_correcao_resultado := f.corrigir_inconsistencias_financeiras(
    v_tenant_id,
    v_empresa_id,
    v_titulo_ids,
    v_plano_id,
    v_centro_id,
    'Financiamentos de veiculos operacionais da frota: plano de financiamento e centro Frota.',
    false
  );

  if coalesce((v_correcao_resultado ->> 'corrigidos')::integer, 0) <> 120 then
    raise exception
      'Correcao dos financiamentos retornou quantidade inesperada: %.',
      v_correcao_resultado;
  end if;

  -- A regra e criada somente depois da correcao do legado.
  v_regra_resultado := f.salvar_regra_rateio(
    v_tenant_id,
    v_empresa_id,
    null,
    v_motivo_id,
    true,
    jsonb_build_array(jsonb_build_object(
      'plano_contas_id', v_plano_id,
      'centro_custo_id', v_centro_id,
      'percentual', 100.0000
    ))
  );
  v_regra_id := (v_regra_resultado ->> 'id')::uuid;

  if (
    select count(*)::integer
    from f.titulo t
    join f.titulo_rateio tr
      on tr.tenant_id = t.tenant_id
     and tr.titulo_id = t.id
     and tr.deleted_at is null
    where t.id = any(v_titulo_ids)
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
      and t.motivo_compra_id = v_motivo_id
      and tr.plano_contas_id = v_plano_id
      and tr.centro_custo_id = v_centro_id
      and tr.os_id is null
      and abs(tr.percentual - 100.0000) <= 0.0001
      and tr.valor = t.valor_total
      and not exists (
        select 1
        from f.titulo_rateio outro
        where outro.tenant_id = tr.tenant_id
          and outro.titulo_id = tr.titulo_id
          and outro.id <> tr.id
          and outro.deleted_at is null
      )
  ) <> 120 then
    raise exception
      'A classificacao final dos financiamentos nao passou na validacao.';
  end if;

  if not exists (
    select 1
    from f.regra_rateio rr
    join f.regra_rateio_item rri
      on rri.tenant_id = rr.tenant_id
     and rri.regra_rateio_id = rr.id
     and rri.deleted_at is null
    where rr.id = v_regra_id
      and rr.tenant_id = v_tenant_id
      and rr.empresa_id = v_empresa_id
      and rr.motivo_compra_id = v_motivo_id
      and rr.ativo
      and rr.deleted_at is null
      and rri.plano_contas_id = v_plano_id
      and rri.centro_custo_id = v_centro_id
      and abs(rri.percentual - 100.0000) <= 0.0001
  ) then
    raise exception
      'A regra FINANCIAMENTO_VEICULO_FROTA nao passou na validacao.';
  end if;

  insert into f.evento_financeiro (
    tenant_id,
    empresa_id,
    evento,
    ref_table,
    ref_id,
    payload
  )
  values (
    v_tenant_id,
    v_empresa_id,
    'FINANCIAMENTOS_VEICULOS_FROTA_CLASSIFICADOS',
    'f.motivo_compra',
    v_motivo_id,
    jsonb_build_object(
      'planoContasId', v_plano_id,
      'centroCustoId', v_centro_id,
      'regraRateioId', v_regra_id,
      'titulosCorrigidos', to_jsonb(v_titulo_ids),
      'quantidade', 120,
      'pagos', 15,
      'pendentes', 105,
      'valorTotal', 294849.90,
      'series', jsonb_build_array(
        jsonb_build_object(
          'fornecedorId', 440,
          'fornecedor', 'BANCO GM S.A',
          'descricao', 'FINANCIAMENTO',
          'parcelas', 20,
          'valorParcela', 2882.37
        ),
        jsonb_build_object(
          'fornecedorId', 414,
          'fornecedor', 'BANCO VOLKSWAGEN S.A.',
          'descricao', 'FINANCIAMENTO VEICULO - VW VIRTUS 60x',
          'parcelas', 50,
          'valorParcela', 2468.72
        ),
        jsonb_build_object(
          'fornecedorId', 414,
          'fornecedor', 'BANCO VOLKSWAGEN S.A.',
          'descricao', 'FINANCIAMENTO VEICULO - VW POLO 60x',
          'parcelas', 50,
          'valorParcela', 2275.33
        )
      ),
      'fornecedorPadraoAlterado', false,
      'outrosFinanciamentosAlterados', false,
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false,
      'preservouOs', true
    )
  );
end;
$corrigir_financiamentos_veiculos_frota$;
