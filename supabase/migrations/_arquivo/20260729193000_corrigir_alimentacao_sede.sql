-- O RESTAURANTE SABOR CASEIRO fornece almoco na sede para funcionarios e
-- terceiros. Seus 11 pagamentos foram classificados de quatro formas
-- diferentes, inclusive como materia-prima, viagem e materiais gerais.
--
-- Cria uma classificacao especifica para alimentacao na sede, corrige os
-- titulos, as oito NFs e seus 46 itens de consumo, e configura o fornecedor
-- para as proximas importacoes.
-- Valores, vencimentos e pagamentos permanecem inalterados.

do $corrigir_alimentacao_sede$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_fornecedor_id constant integer := 135;
  v_plano_id uuid;
  v_centro_id uuid;
  v_motivo_id uuid;
  v_regra_id uuid;
  v_regra_resultado jsonb;
  v_correcao_resultado jsonb;
  v_titulo_ids uuid[];
  v_nf_ids bigint[];
  v_quantidade integer;
  v_pagos integer;
  v_valor_total numeric;
  v_consumo_itens integer;
begin
  select pc.id
    into v_plano_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_ALIMENTACAO_SEDE'
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
      'DESP_ALIMENTACAO_SEDE',
      'DESPESA - ALIMENTACAO NA SEDE',
      'ANALITICA',
      true,
      now(),
      now()
    )
    returning id into v_plano_id;
  else
    update f.plano_contas pc
    set
      nome = 'DESPESA - ALIMENTACAO NA SEDE',
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
    and cc.codigo = 'PESSOAS'
    and cc.ativo
    and cc.deleted_at is null;

  if not exists (
    select 1
    from public.fornecedores fornecedor
    where fornecedor.id = v_fornecedor_id
      and fornecedor.tenant_id = v_tenant_id
      and fornecedor.empresa_id = v_empresa_id
      and upper(btrim(fornecedor.nome)) =
        'RESTAURANTE SABOR CASEIRO LTDA'
      and regexp_replace(
        coalesce(fornecedor.documento, ''),
        '\D',
        '',
        'g'
      ) = '52090695000143'
      and fornecedor.finalidade_padrao = 'consumo'
      and fornecedor.motivo_compra_padrao_id is null
      and fornecedor.ativo
  ) then
    raise exception
      'O fornecedor RESTAURANTE SABOR CASEIRO divergiu do contexto validado.';
  end if;

  select
    array_agg(t.id order by t.competencia_date, t.id),
    count(*)::integer,
    count(*) filter (where t.status = 'PAGO')::integer,
    sum(t.valor_total)
    into
      v_titulo_ids,
      v_quantidade,
      v_pagos,
      v_valor_total
  from f.titulo t
  where t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id
    and t.tipo = 'AP'
    and t.status <> 'CANCELADO'
    and t.deleted_at is null
    and t.fornecedor_id = v_fornecedor_id
    and not f.titulo_eh_legado_implantacao(
      t.tenant_id,
      t.empresa_id,
      t.id
    );

  if v_quantidade <> 11
     or v_pagos <> 11
     or v_valor_total <> 44810.00
  then
    raise exception
      'O historico de alimentacao divergiu: qtd %, pagos %, valor %.',
      v_quantidade,
      v_pagos,
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
     and pc.codigo in (
       'EST_MAT_PRIMA',
       'DESP_VIAGEM',
       'DESP_GERAL',
       'CONSUMO_GERAL'
     )
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
  ) <> 11 then
    raise exception
      'Os rateios originais da alimentacao divergiram do contexto validado.';
  end if;

  select
    array_agg(distinct nf.id order by nf.id),
    count(distinct nf.id)::integer
    into v_nf_ids, v_quantidade
  from f.titulo t
  join f.documento_fiscal df
    on df.id = t.documento_fiscal_id
   and df.tenant_id = t.tenant_id
   and df.empresa_id = t.empresa_id
   and df.deleted_at is null
  join public.nf_entrada nf
    on nf.id = df.source_nf_entrada_id
   and nf.tenant_id = df.tenant_id
   and nf.empresa_id = df.empresa_id
   and nf.deleted_at is null
  where t.id = any(v_titulo_ids)
    and t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id
    and nf.fornecedor_id = v_fornecedor_id
    and nf.finalidade_contexto = 'consumo'
    and nf.os_id is null;

  if v_quantidade <> 8 then
    raise exception
      'A quantidade de NFs de alimentacao divergiu: %.',
      v_quantidade;
  end if;

  select count(*)::integer
    into v_consumo_itens
  from public.consumo_itens ci
  where ci.tenant_id = v_tenant_id
    and ci.empresa_id = v_empresa_id
    and ci.nf_entrada_id = any(v_nf_ids)
    and ci.centro_custo is null
    and ci.local_uso is null
    and ci.deleted_at is null;

  if v_consumo_itens <> 46 then
    raise exception
      'A quantidade de itens de alimentacao divergiu: %.',
      v_consumo_itens;
  end if;

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
    'ALIMENTACAO_SEDE',
    'ALIMENTACAO - FUNCIONARIOS E TERCEIROS NA SEDE',
    false,
    false,
    true,
    'SERVICO',
    v_plano_id,
    true,
    833,
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
      'Ja existe regra ativa inesperada para ALIMENTACAO_SEDE.';
  end if;

  -- Mantem o legado disponivel para o historico da correcao. A regra do
  -- novo motivo sera criada somente depois que os titulos forem corrigidos.
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
      'Alimentacao de funcionarios e terceiros que trabalham na sede.',
    updated_at = now()
  where ta.tenant_id = v_tenant_id
    and ta.titulo_id = any(v_titulo_ids)
    and ta.deleted_at is null;

  update public.nf_entrada nf
  set
    motivo_compra_id = v_motivo_id,
    updated_at = now()
  where nf.id = any(v_nf_ids)
    and nf.tenant_id = v_tenant_id
    and nf.empresa_id = v_empresa_id
    and nf.fornecedor_id = v_fornecedor_id;

  update public.consumo_itens ci
  set
    motivo_compra_id = v_motivo_id,
    centro_custo = 'PESSOAS',
    local_uso = 'SEDE',
    observacoes =
      'Alimentacao de funcionarios e terceiros que trabalham na sede.',
    updated_at = now()
  where ci.tenant_id = v_tenant_id
    and ci.empresa_id = v_empresa_id
    and ci.nf_entrada_id = any(v_nf_ids)
    and ci.deleted_at is null;

  perform set_config('request.jwt.claim.role', 'service_role', true);

  v_correcao_resultado := f.corrigir_inconsistencias_financeiras(
    v_tenant_id,
    v_empresa_id,
    v_titulo_ids,
    v_plano_id,
    v_centro_id,
    'Alimentacao de funcionarios e terceiros na sede: plano de alimentacao e centro Pessoas.',
    false
  );

  if coalesce((v_correcao_resultado ->> 'corrigidos')::integer, 0) <> 11 then
    raise exception
      'Correcao da alimentacao na sede retornou quantidade inesperada: %.',
      v_correcao_resultado;
  end if;

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

  update public.fornecedores fornecedor
  set
    motivo_compra_padrao_id = v_motivo_id,
    atualizado_em = now()
  where fornecedor.id = v_fornecedor_id
    and fornecedor.tenant_id = v_tenant_id
    and fornecedor.empresa_id = v_empresa_id;

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
  ) <> 11 then
    raise exception
      'A classificacao final da alimentacao nao passou na validacao.';
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
      'A regra ALIMENTACAO_SEDE -> DESP_ALIMENTACAO_SEDE/PESSOAS e invalida.';
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
    'ALIMENTACAO_SEDE_CLASSIFICACAO_CONFIGURADA',
    'f.motivo_compra',
    v_motivo_id,
    jsonb_build_object(
      'fornecedorId', v_fornecedor_id,
      'fornecedor', 'RESTAURANTE SABOR CASEIRO LTDA',
      'planoContasId', v_plano_id,
      'centroCustoId', v_centro_id,
      'regraRateioId', v_regra_id,
      'titulosCorrigidos', to_jsonb(v_titulo_ids),
      'notasCorrigidas', to_jsonb(v_nf_ids),
      'quantidadeTitulos', 11,
      'quantidadeNotas', 8,
      'quantidadeItensConsumo', 46,
      'pagos', 11,
      'valorTotal', 44810.00,
      'publico', 'FUNCIONARIOS E TERCEIROS NA SEDE',
      'fornecedorPadraoAlterado', true,
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false,
      'preservouOs', true
    )
  );
end;
$corrigir_alimentacao_sede$;
