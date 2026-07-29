-- O PRONAMP e um emprestimo da empresa em fase final de pagamento.
-- As parcelas 47/48 e 48/48 ja possuem o plano DESP_FINANCIAMENTO,
-- mas foram lancadas sem centro de custo e sem regra de rateio.
--
-- Direciona as duas parcelas para ADM_FIN e configura a regra futura.
-- Valores, vencimentos e pagamentos permanecem inalterados.

do $corrigir_pronamp_adm_fin$
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
    and cc.codigo = 'ADM_FIN'
    and cc.ativo
    and cc.deleted_at is null;

  select mc.id
    into strict v_motivo_id
  from f.motivo_compra mc
  where mc.tenant_id = v_tenant_id
    and mc.codigo = 'FINANCIAMENTO_RURAL'
    and mc.nome = 'FINANCIAMENTO RURAL / PRONAMP'
    and mc.plano_contas_id = v_plano_id
    and mc.ativo
    and mc.deleted_at is null;

  if not exists (
    select 1
    from public.fornecedores fornecedor
    where fornecedor.id = 607
      and fornecedor.tenant_id = v_tenant_id
      and fornecedor.empresa_id = v_empresa_id
      and upper(btrim(fornecedor.nome)) = 'PRONAMP'
      and fornecedor.ativo
  ) then
    raise exception
      'O fornecedor PRONAMP divergiu do contexto validado.';
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
  left join lateral (
    select ta.motivo_compra_id
    from f.titulo_aprovacao ta
    where ta.tenant_id = v_tenant_id
      and ta.titulo_id = t.id
      and ta.deleted_at is null
    order by ta.aprovado_em desc, ta.id desc
    limit 1
  ) aprovacao on true
  where t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id
    and t.tipo = 'AP'
    and t.status <> 'CANCELADO'
    and t.deleted_at is null
    and t.fornecedor_id = 607
    and t.valor_total = 7462.09
    and coalesce(aprovacao.motivo_compra_id, t.motivo_compra_id) =
      v_motivo_id
    and not f.titulo_eh_legado_implantacao(
      t.tenant_id,
      t.empresa_id,
      t.id
    );

  if v_quantidade <> 2
     or v_pagos <> 1
     or v_pendentes <> 1
     or v_valor_total <> 14924.18
  then
    raise exception
      'O contrato PRONAMP divergiu: qtd %, pagos %, pendentes %, valor %.',
      v_quantidade,
      v_pagos,
      v_pendentes,
      v_valor_total;
  end if;

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
      and tr.plano_contas_id = v_plano_id
      and tr.centro_custo_id is null
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
  ) <> 2 then
    raise exception
      'Os rateios originais do PRONAMP divergiram do contexto validado.';
  end if;

  perform 1
  from f.titulo t
  where t.id = any(v_titulo_ids)
    and t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id
  order by t.id
  for update;

  select rr.id
    into v_regra_id
  from f.regra_rateio rr
  where rr.tenant_id = v_tenant_id
    and rr.empresa_id = v_empresa_id
    and rr.motivo_compra_id = v_motivo_id
    and rr.ativo
    and rr.deleted_at is null
  limit 1;

  if v_regra_id is null then
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
      'A regra FINANCIAMENTO_RURAL -> DESP_FINANCIAMENTO/ADM_FIN e invalida.';
  end if;

  perform set_config('request.jwt.claim.role', 'service_role', true);

  v_correcao_resultado := f.corrigir_inconsistencias_financeiras(
    v_tenant_id,
    v_empresa_id,
    v_titulo_ids,
    v_plano_id,
    v_centro_id,
    'Parcelas do emprestimo PRONAMP: plano de financiamento e centro Administrativo e Financeiro.',
    false
  );

  if coalesce((v_correcao_resultado ->> 'corrigidos')::integer, 0) <> 2 then
    raise exception
      'Correcao do PRONAMP retornou quantidade inesperada: %.',
      v_correcao_resultado;
  end if;

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
  ) <> 2 then
    raise exception
      'A classificacao final do PRONAMP nao passou na validacao.';
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
    'PRONAMP_CLASSIFICADO_ADM_FIN',
    'f.motivo_compra',
    v_motivo_id,
    jsonb_build_object(
      'fornecedorId', 607,
      'fornecedor', 'PRONAMP',
      'planoContasId', v_plano_id,
      'centroCustoId', v_centro_id,
      'regraRateioId', v_regra_id,
      'titulosCorrigidos', to_jsonb(v_titulo_ids),
      'quantidade', 2,
      'parcelas', jsonb_build_array('47/48', '48/48'),
      'pagos', 1,
      'pendentes', 1,
      'valorParcela', 7462.09,
      'valorTotal', 14924.18,
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false,
      'preservouOs', true
    )
  );
end;
$corrigir_pronamp_adm_fin$;
