-- Os lancamentos com motivo Crea_SC sao ARTs dos processos de engenharia.
-- Todos estavam em DESP_GERAL sem uma classificacao gerencial especifica.
--
-- Cria o plano DESP_ART_CREA, configura o motivo existente para
-- DESP_ART_CREA/PRODUCAO e corrige as 79 ARTs ja lancadas.
-- Valores, vencimentos, pagamentos e vinculos permanecem inalterados.

do $corrigir_arts_crea_producao$
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
    into v_plano_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_ART_CREA'
    and pc.deleted_at is null
  limit 1;

  if v_plano_id is null then
    insert into f.plano_contas (
      tenant_id,
      codigo,
      nome,
      tipo,
      ativo,
      created_at,
      updated_at
    )
    values (
      v_tenant_id,
      'DESP_ART_CREA',
      'DESPESA - ART / TAXAS TECNICAS',
      'ANALITICA',
      true,
      now(),
      now()
    )
    returning id into v_plano_id;
  else
    update f.plano_contas pc
    set
      nome = 'DESPESA - ART / TAXAS TECNICAS',
      tipo = 'ANALITICA',
      ativo = true,
      updated_at = now(),
      deleted_at = null
    where pc.id = v_plano_id
      and pc.tenant_id = v_tenant_id;
  end if;

  select cc.id
    into strict v_centro_id
  from f.centro_custo cc
  where cc.tenant_id = v_tenant_id
    and cc.empresa_id = v_empresa_id
    and cc.codigo = 'PRODUCAO'
    and cc.ativo
    and cc.deleted_at is null;

  select mc.id
    into strict v_motivo_id
  from f.motivo_compra mc
  where mc.tenant_id = v_tenant_id
    and mc.codigo = 'Crea_SC'
    and mc.nome = 'ART_CREA_SC'
    and mc.ativo
    and mc.deleted_at is null;

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
    and coalesce(aprovacao.motivo_compra_id, t.motivo_compra_id) =
      v_motivo_id
    and not f.titulo_eh_legado_implantacao(
      t.tenant_id,
      t.empresa_id,
      t.id
    );

  if v_quantidade <> 79
     or v_pagos <> 70
     or v_pendentes <> 9
     or v_valor_total <> 14956.42
  then
    raise exception
      'O lote de ARTs divergiu: qtd %, pagos %, pendentes %, valor %.',
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
    join f.plano_contas pc
      on pc.tenant_id = tr.tenant_id
     and pc.id = tr.plano_contas_id
     and pc.codigo = 'DESP_GERAL'
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
  ) <> 79 then
    raise exception
      'Os rateios originais das ARTs divergiram do contexto validado.';
  end if;

  perform 1
  from f.titulo t
  where t.id = any(v_titulo_ids)
    and t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id
  order by t.id
  for update;

  update f.motivo_compra mc
  set
    plano_contas_id = v_plano_id,
    updated_at = now()
  where mc.id = v_motivo_id
    and mc.tenant_id = v_tenant_id;

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
      'A regra ART_CREA_SC -> DESP_ART_CREA/PRODUCAO e invalida.';
  end if;

  perform set_config('request.jwt.claim.role', 'service_role', true);

  v_correcao_resultado := f.corrigir_inconsistencias_financeiras(
    v_tenant_id,
    v_empresa_id,
    v_titulo_ids,
    v_plano_id,
    v_centro_id,
    'ARTs dos processos de engenharia: plano de ART e taxas tecnicas, centro Producao.',
    false
  );

  if coalesce((v_correcao_resultado ->> 'corrigidos')::integer, 0) <> 79 then
    raise exception
      'Correcao das ARTs retornou quantidade inesperada: %.',
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
  ) <> 79 then
    raise exception
      'A classificacao final das ARTs nao passou na validacao.';
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
    'ARTS_CREA_PROCESSOS_CLASSIFICADAS',
    'f.motivo_compra',
    v_motivo_id,
    jsonb_build_object(
      'planoContasId', v_plano_id,
      'centroCustoId', v_centro_id,
      'regraRateioId', v_regra_id,
      'titulosCorrigidos', to_jsonb(v_titulo_ids),
      'quantidade', 79,
      'pagos', 70,
      'pendentes', 9,
      'valorTotal', 14956.42,
      'fornecedores', jsonb_build_array(
        jsonb_build_object(
          'fornecedorId', 303,
          'fornecedor', 'CREA-SC',
          'quantidade', 78
        ),
        jsonb_build_object(
          'fornecedorId', 624,
          'fornecedor', 'NURBURG ENGENHARIA ( RODNEY)',
          'quantidade', 1
        )
      ),
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false,
      'preservouOs', true
    )
  );
end;
$corrigir_arts_crea_producao$;
