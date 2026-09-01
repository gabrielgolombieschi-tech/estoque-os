-- O fornecedor GILSOMAR SCABURRI ME emitiu tres NFs nao legadas contendo
-- exclusivamente almoco para funcionarios em servicos de campo.
--
-- A NF 1432 atende simultaneamente as OS 132 e 135 da WEG TINTAS, mas possui
-- uma unica linha sem detalhamento de quantidade ou valor por OS. Por isso,
-- nao e criado um rateio arbitrario entre as OS: o custo fica no centro CAMPO
-- e as duas OS sao registradas na auditoria.
--
-- Cria um motivo especifico, configura DESP_VIAGEM/CAMPO, corrige os tres
-- titulos e alinha a origem das importacoes e o padrao do fornecedor.

do $corrigir_alimentacao_equipe_campo$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_fornecedor_id constant integer := 374;
  v_motivo_alimentacao_id uuid;
  v_plano_viagem_id uuid;
  v_centro_campo_id uuid;
  v_regra_id uuid;
  v_regra_resultado jsonb;
  v_correcao_resultado jsonb;
  v_titulo_ids uuid[] := array[]::uuid[];
  v_caso record;
  v_titulo f.titulo%rowtype;
  v_motivo_efetivo_codigo text;
  v_rateio_count integer;
  v_consumo_count integer;
begin
  select pc.id
    into strict v_plano_viagem_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_VIAGEM'
    and pc.tipo = 'ANALITICA'
    and pc.ativo
    and pc.deleted_at is null;

  select cc.id
    into strict v_centro_campo_id
  from f.centro_custo cc
  where cc.tenant_id = v_tenant_id
    and cc.empresa_id = v_empresa_id
    and cc.codigo = 'CAMPO'
    and cc.ativo
    and cc.deleted_at is null;

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
    'ALIM_EQUIPE_CAMPO',
    'ALIMENTACAO - EQUIPE EM SERVICOS DE CAMPO',
    false,
    false,
    true,
    'SERVICO',
    v_plano_viagem_id,
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
  returning id into v_motivo_alimentacao_id;

  select rr.id
    into v_regra_id
  from f.regra_rateio rr
  where rr.tenant_id = v_tenant_id
    and rr.empresa_id = v_empresa_id
    and rr.motivo_compra_id = v_motivo_alimentacao_id
    and rr.ativo
    and rr.deleted_at is null
  limit 1;

  if v_regra_id is null then
    v_regra_resultado := f.salvar_regra_rateio(
      v_tenant_id,
      v_empresa_id,
      null,
      v_motivo_alimentacao_id,
      true,
      jsonb_build_array(jsonb_build_object(
        'plano_contas_id', v_plano_viagem_id,
        'centro_custo_id', v_centro_campo_id,
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
      and rr.motivo_compra_id = v_motivo_alimentacao_id
      and rr.ativo
      and rr.deleted_at is null
      and rri.plano_contas_id = v_plano_viagem_id
      and rri.centro_custo_id = v_centro_campo_id
      and abs(rri.percentual - 100.0000) <= 0.0001
  ) then
    raise exception
      'Regra ALIM_EQUIPE_CAMPO -> DESP_VIAGEM/CAMPO nao esta configurada.';
  end if;

  if not exists (
    select 1
    from public.fornecedores f
    where f.id = v_fornecedor_id
      and f.tenant_id = v_tenant_id
      and f.empresa_id = v_empresa_id
      and upper(btrim(f.nome)) = 'GILSOMAR SCABURRI ME'
      and regexp_replace(coalesce(f.documento, ''), '\D', '', 'g') =
        '14412138000102'
      and f.ativo
  ) then
    raise exception
      'Fornecedor GILSOMAR SCABURRI ME divergiu do cadastro validado.';
  end if;

  if not exists (
    select 1
    from public.ordens_servico os
    where os.id = 151
      and os.tenant_id = v_tenant_id
      and os.empresa_id = v_empresa_id
      and os.numero_os = '132'
      and upper(btrim(os.cliente_nome)) = 'WEG TINTAS LTDA'
      and os.status <> 'cancelada'
  ) or not exists (
    select 1
    from public.ordens_servico os
    where os.id = 154
      and os.tenant_id = v_tenant_id
      and os.empresa_id = v_empresa_id
      and os.numero_os = '135'
      and upper(btrim(os.cliente_nome)) = 'WEG TINTAS LTDA'
      and os.status <> 'cancelada'
  ) then
    raise exception
      'As OS 132 e 135 da WEG divergem do contexto validado.';
  end if;

  for v_caso in
    select *
    from (
      values
        (
          '5e800fad-e2ca-41fc-92ca-f37968418f03'::uuid,
          '2026-03-01'::date,
          995::bigint,
          '1340'::text,
          '42260314412138000102550010000013401424420054'::text,
          3108::bigint,
          17.000000::numeric,
          35.000000::numeric,
          595.00::numeric,
          'OUTROS'::text,
          'DESP_GERAL'::text
        ),
        (
          '4e4be26b-4359-4663-b705-73e813161c85'::uuid,
          '2026-06-01'::date,
          1651::bigint,
          '1409'::text,
          '42260614412138000102550010000014091396763645'::text,
          4790::bigint,
          80.000000::numeric,
          35.000000::numeric,
          2800.00::numeric,
          'OUTROS'::text,
          'DESP_GERAL'::text
        ),
        (
          '7c9bf15e-e8af-46b4-b6b5-8ce85b410a9b'::uuid,
          '2026-07-01'::date,
          1851::bigint,
          '1432'::text,
          '42260714412138000102550010000014321106045975'::text,
          5244::bigint,
          1.000000::numeric,
          9158.000000::numeric,
          9158.00::numeric,
          'CONSUMO'::text,
          'CONSUMO_GERAL'::text
        )
    ) as casos(
      titulo_id,
      competencia_date,
      nf_entrada_id,
      numero_nf,
      chave_nf,
      nf_item_id,
      quantidade,
      valor_unitario,
      valor_total,
      motivo_codigo,
      plano_codigo
    )
  loop
    select t.*
      into strict v_titulo
    from f.titulo t
    where t.id = v_caso.titulo_id
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
      and t.tipo = 'AP'
      and t.status <> 'CANCELADO'
      and t.deleted_at is null
      and t.fornecedor_id = v_fornecedor_id
      and t.valor_total = v_caso.valor_total
      and coalesce(t.competencia_date, t.emissao_date) =
        v_caso.competencia_date
      and upper(btrim(t.descricao)) =
        'NF-E ' || v_caso.numero_nf || '/1 - GILSOMAR SCABURRI ME'
      and not f.titulo_eh_legado_implantacao(
        t.tenant_id,
        t.empresa_id,
        t.id
      )
    for update;

    if not exists (
      select 1
      from f.documento_fiscal df
      join public.nf_entrada nf
        on nf.id = df.source_nf_entrada_id
       and nf.tenant_id = df.tenant_id
       and nf.empresa_id = df.empresa_id
      where df.id = v_titulo.documento_fiscal_id
        and df.tenant_id = v_tenant_id
        and df.empresa_id = v_empresa_id
        and df.deleted_at is null
        and nf.id = v_caso.nf_entrada_id
        and nf.numero = v_caso.numero_nf
        and nf.serie = '1'
        and nf.chave = v_caso.chave_nf
        and nf.fornecedor_id = v_fornecedor_id
        and nf.valor_total = v_caso.valor_total
        and nf.finalidade_contexto = 'consumo'
        and nf.os_id is null
        and nf.deleted_at is null
    ) then
      raise exception
        'Documento fiscal do titulo % divergiu do caso validado.',
        v_caso.titulo_id;
    end if;

    if not exists (
      select 1
      from public.nf_entrada_itens nfi
      where nfi.id = v_caso.nf_item_id
        and nfi.tenant_id = v_tenant_id
        and nfi.empresa_id = v_empresa_id
        and nfi.nf_entrada_id = v_caso.nf_entrada_id
        and upper(btrim(nfi.descricao)) = 'ALMOCO'
        and nfi.qtd = v_caso.quantidade
        and nfi.v_unit = v_caso.valor_unitario
        and nfi.v_prod = v_caso.valor_total
    ) then
      raise exception
        'Item ALMOCO da NF % divergiu do caso validado.',
        v_caso.numero_nf;
    end if;

    select count(*)::integer
      into v_consumo_count
    from public.consumo_itens ci
    join f.motivo_compra mc
      on mc.id = ci.motivo_compra_id
     and mc.tenant_id = ci.tenant_id
     and mc.codigo = v_caso.motivo_codigo
     and mc.ativo
     and mc.deleted_at is null
    where ci.tenant_id = v_tenant_id
      and ci.empresa_id = v_empresa_id
      and ci.nf_entrada_id = v_caso.nf_entrada_id
      and ci.nf_entrada_item_id = v_caso.nf_item_id
      and upper(btrim(ci.descricao)) = 'ALMOCO'
      and ci.valor_total = v_caso.valor_total
      and ci.deleted_at is null;

    if v_consumo_count <> 1 then
      raise exception
        'Cadastro de consumo da NF % divergiu do caso validado.',
        v_caso.numero_nf;
    end if;

    select mc.codigo
      into strict v_motivo_efetivo_codigo
    from f.motivo_compra mc
    where mc.tenant_id = v_tenant_id
      and mc.id = coalesce(
        (
          select ta.motivo_compra_id
          from f.titulo_aprovacao ta
          where ta.tenant_id = v_tenant_id
            and ta.titulo_id = v_caso.titulo_id
            and ta.deleted_at is null
          order by ta.aprovado_em desc, ta.id desc
          limit 1
        ),
        v_titulo.motivo_compra_id
      )
      and mc.ativo
      and mc.deleted_at is null;

    if v_motivo_efetivo_codigo is distinct from v_caso.motivo_codigo then
      raise exception
        'Motivo original do titulo % divergiu do caso validado.',
        v_caso.titulo_id;
    end if;

    select count(*)::integer
      into v_rateio_count
    from f.titulo_rateio tr
    join f.plano_contas pc
      on pc.id = tr.plano_contas_id
     and pc.tenant_id = tr.tenant_id
     and pc.codigo = v_caso.plano_codigo
     and pc.ativo
     and pc.deleted_at is null
    where tr.tenant_id = v_tenant_id
      and tr.titulo_id = v_caso.titulo_id
      and tr.centro_custo_id is null
      and tr.os_id is null
      and abs(tr.percentual - 100.0000) <= 0.0001
      and tr.valor = v_caso.valor_total
      and tr.origem_rateio = 'EXPLICITO'
      and tr.deleted_at is null;

    if v_rateio_count <> 1 then
      raise exception
        'Rateio original do titulo % divergiu do caso validado.',
        v_caso.titulo_id;
    end if;

    update f.titulo t
    set
      motivo_compra_id = v_motivo_alimentacao_id,
      updated_at = now()
    where t.id = v_caso.titulo_id
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id;

    update f.titulo_aprovacao ta
    set
      motivo_compra_id = v_motivo_alimentacao_id,
      change_reason =
        'Alimentacao de funcionarios em servicos de campo.',
      updated_at = now()
    where ta.tenant_id = v_tenant_id
      and ta.titulo_id = v_caso.titulo_id
      and ta.deleted_at is null;

    update public.nf_entrada nf
    set
      motivo_compra_id = v_motivo_alimentacao_id,
      updated_at = now()
    where nf.id = v_caso.nf_entrada_id
      and nf.tenant_id = v_tenant_id
      and nf.empresa_id = v_empresa_id;

    update public.consumo_itens ci
    set
      motivo_compra_id = v_motivo_alimentacao_id,
      centro_custo = 'CAMPO',
      local_uso = case
        when v_caso.numero_nf = '1432'
          then 'WEG TINTAS - OS 132 E 135'
        else 'SERVICOS EM CAMPO'
      end,
      observacoes = case
        when v_caso.numero_nf = '1432'
          then 'Alimentacao da equipe em servico nas OS 132 e 135.'
        else 'Alimentacao da equipe em servicos de campo.'
      end,
      updated_at = now()
    where ci.tenant_id = v_tenant_id
      and ci.empresa_id = v_empresa_id
      and ci.nf_entrada_id = v_caso.nf_entrada_id
      and ci.nf_entrada_item_id = v_caso.nf_item_id
      and ci.deleted_at is null;

    v_titulo_ids := array_append(v_titulo_ids, v_caso.titulo_id);
  end loop;

  update public.fornecedores f
  set
    motivo_compra_padrao_id = v_motivo_alimentacao_id,
    atualizado_em = now()
  where f.id = v_fornecedor_id
    and f.tenant_id = v_tenant_id
    and f.empresa_id = v_empresa_id;

  perform set_config('request.jwt.claim.role', 'service_role', true);

  v_correcao_resultado := f.corrigir_inconsistencias_financeiras(
    v_tenant_id,
    v_empresa_id,
    v_titulo_ids,
    v_plano_viagem_id,
    v_centro_campo_id,
    'Alimentacao de funcionarios em servicos de campo; NF 1432 atende OS 132 e 135.',
    false
  );

  if coalesce((v_correcao_resultado ->> 'corrigidos')::integer, 0) <> 3 then
    raise exception
      'Correcao da alimentacao de campo retornou quantidade inesperada: %',
      v_correcao_resultado;
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
    'ALIMENTACAO_EQUIPE_CAMPO_CLASSIFICACAO_CONFIGURADA',
    'f.motivo_compra',
    v_motivo_alimentacao_id,
    jsonb_build_object(
      'fornecedorId', v_fornecedor_id,
      'planoContasId', v_plano_viagem_id,
      'centroCustoId', v_centro_campo_id,
      'regraRateioId', v_regra_id,
      'titulosCorrigidos', to_jsonb(v_titulo_ids),
      'valorTotal', 12553.00,
      'nf1432', jsonb_build_object(
        'nfEntradaId', 1851,
        'tituloId', '7c9bf15e-e8af-46b4-b6b5-8ce85b410a9b',
        'osIdsRelacionadas', jsonb_build_array(151, 154),
        'osNumerosRelacionadas', jsonb_build_array('132', '135'),
        'cliente', 'WEG TINTAS LTDA',
        'rateioPorOsCriado', false,
        'motivoSemRateioPorOs',
          'NF possui uma unica linha sem valores separados por OS.'
      ),
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false,
      'preservouOs', true
    )
  );
end;
$corrigir_alimentacao_equipe_campo$;
