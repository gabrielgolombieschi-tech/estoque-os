-- A TREECOM COWORKING fornece o endereco fiscal da empresa e um espaco de
-- recebimento com capacidade para um pallet. Trata-se de aluguel operacional
-- ligado ao recebimento/logistica, e nao de servico generico de terceiros.
--
-- Cria uma classificacao recorrente em DESP_ALUGUEL / EST_LOG e corrige as
-- dez mensalidades confirmadas entre marco e dezembro de 2026. Valores,
-- vencimentos, pagamentos, documentos e vinculos permanecem inalterados.

do $corrigir_aluguel_endereco_fiscal_treecom$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_fornecedor_id constant integer := 446;
  v_plano_anterior_id uuid;
  v_plano_aluguel_id uuid;
  v_centro_logistica_id uuid;
  v_motivo_anterior_id uuid;
  v_motivo_aluguel_id uuid;
  v_regra_id uuid;
  v_regra_resultado jsonb;
  v_correcao_resultado jsonb;
  v_titulo_ids uuid[] := array[]::uuid[];
  v_caso record;
  v_titulo f.titulo%rowtype;
  v_motivo_efetivo_codigo text;
  v_rateio_count integer;
begin
  select pc.id
    into strict v_plano_anterior_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_SERV_TERCEIROS'
    and pc.tipo = 'ANALITICA'
    and pc.ativo
    and pc.deleted_at is null;

  select pc.id
    into strict v_plano_aluguel_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_ALUGUEL'
    and pc.tipo = 'ANALITICA'
    and pc.ativo
    and pc.deleted_at is null;

  select cc.id
    into strict v_centro_logistica_id
  from f.centro_custo cc
  where cc.tenant_id = v_tenant_id
    and cc.empresa_id = v_empresa_id
    and cc.codigo = 'EST_LOG'
    and cc.ativo
    and cc.deleted_at is null;

  select mc.id
    into strict v_motivo_anterior_id
  from f.motivo_compra mc
  where mc.tenant_id = v_tenant_id
    and mc.codigo = 'SERV_TERCEIROS'
    and mc.plano_contas_id = v_plano_anterior_id
    and mc.ativo
    and mc.deleted_at is null;

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
    'OPEX_ALUGUEL_ENDERECO_FISCAL',
    'OPEX - ALUGUEL ENDERECO FISCAL E RECEBIMENTO',
    false,
    false,
    true,
    'SERVICO',
    v_plano_aluguel_id,
    true,
    846,
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
  returning id into v_motivo_aluguel_id;

  select rr.id
    into v_regra_id
  from f.regra_rateio rr
  where rr.tenant_id = v_tenant_id
    and rr.empresa_id = v_empresa_id
    and rr.motivo_compra_id = v_motivo_aluguel_id
    and rr.ativo
    and rr.deleted_at is null
  limit 1;

  if v_regra_id is null then
    v_regra_resultado := f.salvar_regra_rateio(
      v_tenant_id,
      v_empresa_id,
      null,
      v_motivo_aluguel_id,
      true,
      jsonb_build_array(jsonb_build_object(
        'plano_contas_id', v_plano_aluguel_id,
        'centro_custo_id', v_centro_logistica_id,
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
      and rr.motivo_compra_id = v_motivo_aluguel_id
      and rr.ativo
      and rr.deleted_at is null
      and rri.plano_contas_id = v_plano_aluguel_id
      and rri.centro_custo_id = v_centro_logistica_id
      and abs(rri.percentual - 100.0000) <= 0.0001
      and not exists (
        select 1
        from f.regra_rateio_item outro
        where outro.tenant_id = rri.tenant_id
          and outro.regra_rateio_id = rri.regra_rateio_id
          and outro.id <> rri.id
          and outro.deleted_at is null
      )
  ) then
    raise exception
      'Regra OPEX_ALUGUEL_ENDERECO_FISCAL -> DESP_ALUGUEL/EST_LOG nao esta configurada.';
  end if;

  if not exists (
    select 1
    from public.fornecedores fornecedor
    where fornecedor.id = v_fornecedor_id
      and fornecedor.tenant_id = v_tenant_id
      and fornecedor.empresa_id = v_empresa_id
      and upper(btrim(fornecedor.nome)) = 'TREECOM COWORKING'
      and regexp_replace(
        coalesce(fornecedor.documento, ''),
        '\D',
        '',
        'g'
      ) = '26941709000185'
      and fornecedor.motivo_compra_padrao_id is null
      and fornecedor.ativo
  ) then
    raise exception
      'O cadastro da TREECOM COWORKING divergiu do contexto validado.';
  end if;

  for v_caso in
    select *
    from (
      values
        (
          '4732507e-3244-4542-94e1-edafd2b3af9e'::uuid,
          '2026-03-01'::date,
          378.00::numeric,
          'PARCELA MENSAL'::text
        ),
        (
          '4c5da718-7cdb-40df-ab0c-c4c273302add'::uuid,
          '2026-04-01'::date,
          423.00::numeric,
          'LOCACAO DE GALPAO'::text
        ),
        (
          'd9fdb2e8-5ce1-40ed-8cca-1533757b3e9a'::uuid,
          '2026-05-01'::date,
          393.00::numeric,
          'LOCACAO ESPAÇO'::text
        ),
        (
          '70654c64-d406-4291-b95a-9a315323c257'::uuid,
          '2026-06-01'::date,
          378.00::numeric,
          'PARCELA MENSAL'::text
        ),
        (
          '22cb6fab-ffac-4eef-ae21-431ece904371'::uuid,
          '2026-07-01'::date,
          395.00::numeric,
          'GALPÃO DE RECEBIMENTO'::text
        ),
        (
          'f6db6034-e383-4f99-af79-21ec287fadfa'::uuid,
          '2026-08-01'::date,
          378.00::numeric,
          'PARCELA MENSAL'::text
        ),
        (
          '5e28f615-21ba-4198-9098-01989164aac2'::uuid,
          '2026-09-01'::date,
          378.00::numeric,
          'PARCELA MENSAL'::text
        ),
        (
          '1b60edbc-16df-4192-8a59-46e054f0157f'::uuid,
          '2026-10-01'::date,
          378.00::numeric,
          'PARCELA MENSAL'::text
        ),
        (
          '7e4ba692-110a-48e2-9b7a-671cbd650c06'::uuid,
          '2026-11-01'::date,
          378.00::numeric,
          'PARCELA MENSAL'::text
        ),
        (
          '27897577-c926-4f9b-a15a-94a2b52d1fe4'::uuid,
          '2026-12-01'::date,
          378.00::numeric,
          'PARCELA MENSAL'::text
        )
    ) as casos(titulo_id, competencia_date, valor_total, descricao)
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
      and upper(btrim(t.descricao)) = v_caso.descricao
      and t.documento_fiscal_id is null
      and not f.titulo_eh_legado_implantacao(
        t.tenant_id,
        t.empresa_id,
        t.id
      )
    for update;

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

    if v_motivo_efetivo_codigo is distinct from 'SERV_TERCEIROS' then
      raise exception
        'Motivo original do titulo % divergiu do caso validado.',
        v_caso.titulo_id;
    end if;

    select count(*)::integer
      into v_rateio_count
    from f.titulo_rateio tr
    where tr.tenant_id = v_tenant_id
      and tr.titulo_id = v_caso.titulo_id
      and tr.plano_contas_id = v_plano_anterior_id
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
      motivo_compra_id = v_motivo_aluguel_id,
      updated_at = now()
    where t.id = v_caso.titulo_id
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id;

    update f.titulo_aprovacao ta
    set
      motivo_compra_id = v_motivo_aluguel_id,
      change_reason =
        'Aluguel de endereco fiscal e espaco de recebimento logistico.',
      updated_at = now()
    where ta.tenant_id = v_tenant_id
      and ta.titulo_id = v_caso.titulo_id
      and ta.deleted_at is null;

    v_titulo_ids := array_append(v_titulo_ids, v_caso.titulo_id);
  end loop;

  update public.fornecedores fornecedor
  set
    motivo_compra_padrao_id = v_motivo_aluguel_id,
    atualizado_em = now()
  where fornecedor.id = v_fornecedor_id
    and fornecedor.tenant_id = v_tenant_id
    and fornecedor.empresa_id = v_empresa_id;

  perform set_config('request.jwt.claim.role', 'service_role', true);

  v_correcao_resultado := f.corrigir_inconsistencias_financeiras(
    v_tenant_id,
    v_empresa_id,
    v_titulo_ids,
    v_plano_aluguel_id,
    v_centro_logistica_id,
    'Endereco fiscal e recebimento: aluguel operacional do centro Estoque e Logistica.',
    false
  );

  if coalesce((v_correcao_resultado ->> 'corrigidos')::integer, 0) <> 10 then
    raise exception
      'Correcao do aluguel da TREECOM retornou quantidade inesperada: %.',
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
      and t.motivo_compra_id = v_motivo_aluguel_id
      and tr.plano_contas_id = v_plano_aluguel_id
      and tr.centro_custo_id = v_centro_logistica_id
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
  ) <> 10 then
    raise exception
      'A classificacao final do aluguel da TREECOM nao passou na validacao.';
  end if;

  if not exists (
    select 1
    from public.fornecedores fornecedor
    where fornecedor.id = v_fornecedor_id
      and fornecedor.tenant_id = v_tenant_id
      and fornecedor.empresa_id = v_empresa_id
      and fornecedor.motivo_compra_padrao_id = v_motivo_aluguel_id
  ) then
    raise exception
      'O motivo padrao da TREECOM nao foi configurado.';
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
    'ALUGUEL_ENDERECO_FISCAL_CLASSIFICADO',
    'f.motivo_compra',
    v_motivo_aluguel_id,
    jsonb_build_object(
      'fornecedorId', v_fornecedor_id,
      'fornecedorNome', 'TREECOM COWORKING',
      'motivoCompraId', v_motivo_aluguel_id,
      'planoContasId', v_plano_aluguel_id,
      'centroCustoId', v_centro_logistica_id,
      'regraRateioId', v_regra_id,
      'titulosCorrigidos', to_jsonb(v_titulo_ids),
      'quantidade', 10,
      'valorTotal', 3857.00,
      'finalidade',
        'Endereco fiscal e espaco para recebimento de encomendas com um pallet.',
      'fornecedorPadraoAlterado', true,
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false,
      'preservouDocumentos', true,
      'preservouOs', true
    )
  );
end;
$corrigir_aluguel_endereco_fiscal_treecom$;
