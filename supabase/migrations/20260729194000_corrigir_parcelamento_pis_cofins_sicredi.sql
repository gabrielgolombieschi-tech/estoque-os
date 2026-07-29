-- O parcelamento PIS/COFINS SICREDI foi identificado e renomeado em uma
-- migration anterior, mas seus rateios permaneceram no plano DESP_INTERNET.
--
-- Isola somente esta serie em um motivo especifico, corrige as 51 parcelas
-- cadastradas para DESP_PIS_COFINS/ADM_FIN e configura a regra futura.
-- Os demais tributos da Secretaria da Fazenda permanecem inalterados.

do $corrigir_parcelamento_pis_cofins_sicredi$
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
    and pc.codigo = 'DESP_PIS_COFINS'
    and pc.nome = 'DESPESA - PIS/COFINS'
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

  if not exists (
    select 1
    from public.fornecedores fornecedor
    where fornecedor.id = 298
      and fornecedor.tenant_id = v_tenant_id
      and fornecedor.empresa_id = v_empresa_id
      and upper(btrim(fornecedor.nome)) =
        'SECRETARIA DE ESTADO DA FAZENDA'
      and fornecedor.ativo
  ) then
    raise exception
      'A Secretaria de Estado da Fazenda divergiu do contexto validado.';
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
    and t.fornecedor_id = 298
    and upper(btrim(t.descricao)) =
      'PARCELAMENTO PIS/COFINS - SICREDI 60X'
    and t.total_parcelas_serie = 60
    and t.valor_total = 4112.64
    and not f.titulo_eh_legado_implantacao(
      t.tenant_id,
      t.empresa_id,
      t.id
    );

  if v_quantidade <> 51
     or v_pagos <> 1
     or v_pendentes <> 50
     or v_valor_total <> 209744.64
  then
    raise exception
      'A serie PIS/COFINS SICREDI divergiu: qtd %, pagos %, pendentes %, valor %.',
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
     and pc.codigo = 'DESP_INTERNET'
     and pc.deleted_at is null
    where t.id = any(v_titulo_ids)
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
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
  ) <> 51 then
    raise exception
      'Os rateios em DESP_INTERNET divergiram do contexto validado.';
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
    'PARC_PIS_COFINS_SICREDI',
    'PARCELAMENTO PIS/COFINS - SICREDI',
    false,
    false,
    true,
    'SERVICO',
    v_plano_id,
    true,
    834,
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
      'Ja existe regra ativa inesperada para PARC_PIS_COFINS_SICREDI.';
  end if;

  -- A regra sera criada depois da correcao para preservar o estado anterior
  -- nos snapshots de auditoria da Central de Inconsistencias.
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
      'Parcelamento PIS/COFINS SICREDI: plano tributario e centro Administrativo e Financeiro.',
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
    'Parcelamento PIS/COFINS SICREDI: plano PIS/COFINS e centro Administrativo e Financeiro.',
    false
  );

  if coalesce((v_correcao_resultado ->> 'corrigidos')::integer, 0) <> 51 then
    raise exception
      'Correcao do parcelamento retornou quantidade inesperada: %.',
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
  ) <> 51 then
    raise exception
      'A classificacao final do parcelamento nao passou na validacao.';
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
      'A regra PARC_PIS_COFINS_SICREDI nao passou na validacao.';
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
    'PARCELAMENTO_PIS_COFINS_SICREDI_CLASSIFICADO',
    'f.motivo_compra',
    v_motivo_id,
    jsonb_build_object(
      'fornecedorId', 298,
      'fornecedor', 'SECRETARIA DE ESTADO DA FAZENDA',
      'planoContasId', v_plano_id,
      'centroCustoId', v_centro_id,
      'regraRateioId', v_regra_id,
      'titulosCorrigidos', to_jsonb(v_titulo_ids),
      'quantidade', 51,
      'pagos', 1,
      'pendentes', 50,
      'valorParcela', 4112.64,
      'valorTotal', 209744.64,
      'planoAnterior', 'DESP_INTERNET',
      'motivoGenericoTributosPreservado', true,
      'fornecedorPadraoAlterado', false,
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false,
      'preservouOs', true
    )
  );
end;
$corrigir_parcelamento_pis_cofins_sicredi$;
