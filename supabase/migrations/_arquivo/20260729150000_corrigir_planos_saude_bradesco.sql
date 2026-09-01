-- Os compromissos da BRADESCO SAUDE SA correspondem ao plano de saude de
-- funcionarios e socios. O historico tinha classificacoes divergentes entre
-- despesas gerais, consultoria, servicos de terceiros e custo de OS.
--
-- Cria um motivo especifico, configura o destino recorrente em
-- DESP_BENEFICIOS/PESSOAS, atualiza o padrao do fornecedor e corrige somente
-- os cinco titulos nao legados que possuem inconsistencias abertas.

do $corrigir_planos_saude_bradesco$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_fornecedor_id constant integer := 297;
  v_motivo_saude_id uuid;
  v_plano_beneficios_id uuid;
  v_centro_pessoas_id uuid;
  v_regra_id uuid;
  v_regra_resultado jsonb;
  v_correcao_outros_resultado jsonb;
  v_correcao_classificados_resultado jsonb;
  v_titulo_ids uuid[] := array[]::uuid[];
  v_caso record;
  v_titulo f.titulo%rowtype;
  v_motivo_efetivo_codigo text;
  v_rateio_count integer;
begin
  select pc.id
    into strict v_plano_beneficios_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_BENEFICIOS'
    and pc.tipo = 'ANALITICA'
    and pc.ativo
    and pc.deleted_at is null;

  select cc.id
    into strict v_centro_pessoas_id
  from f.centro_custo cc
  where cc.tenant_id = v_tenant_id
    and cc.empresa_id = v_empresa_id
    and cc.codigo = 'PESSOAS'
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
    'BENEF_PLANO_SAUDE',
    'BENEFICIO - PLANO DE SAUDE',
    false,
    false,
    true,
    'SERVICO',
    v_plano_beneficios_id,
    true,
    840,
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
  returning id into v_motivo_saude_id;

  select rr.id
    into v_regra_id
  from f.regra_rateio rr
  where rr.tenant_id = v_tenant_id
    and rr.empresa_id = v_empresa_id
    and rr.motivo_compra_id = v_motivo_saude_id
    and rr.ativo
    and rr.deleted_at is null
  limit 1;

  if v_regra_id is null then
    v_regra_resultado := f.salvar_regra_rateio(
      v_tenant_id,
      v_empresa_id,
      null,
      v_motivo_saude_id,
      true,
      jsonb_build_array(jsonb_build_object(
        'plano_contas_id', v_plano_beneficios_id,
        'centro_custo_id', v_centro_pessoas_id,
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
      and rr.motivo_compra_id = v_motivo_saude_id
      and rr.ativo
      and rr.deleted_at is null
      and rri.plano_contas_id = v_plano_beneficios_id
      and rri.centro_custo_id = v_centro_pessoas_id
      and abs(rri.percentual - 100.0000) <= 0.0001
  ) then
    raise exception
      'Regra BENEF_PLANO_SAUDE -> DESP_BENEFICIOS/PESSOAS nao esta configurada.';
  end if;

  if not exists (
    select 1
    from public.fornecedores f
    where f.id = v_fornecedor_id
      and f.tenant_id = v_tenant_id
      and f.empresa_id = v_empresa_id
      and upper(btrim(f.nome)) = 'BRADESCO SAUDE SA'
      and regexp_replace(coalesce(f.documento, ''), '\D', '', 'g') =
        '92693118000160'
      and f.ativo
  ) then
    raise exception
      'Fornecedor BRADESCO SAUDE SA divergiu do cadastro validado.';
  end if;

  for v_caso in
    select *
    from (
      values
        (
          'b111c68f-2931-4678-9136-acfc6b9b2bf0'::uuid,
          '2026-02-01'::date,
          'PLANO DE SAUDE'::text,
          7654.38::numeric,
          'OUTROS'::text,
          'DESP_GERAL'::text,
          'EXPLICITO'::text
        ),
        (
          'd535f828-ef27-4858-b6e9-0e2e01714cf6'::uuid,
          '2026-04-01'::date,
          'BRADESCO SAUDE'::text,
          7684.93::numeric,
          'SERV_TERCEIROS'::text,
          'DESP_SERV_TERCEIROS'::text,
          'EXPLICITO'::text
        ),
        (
          'a3034c1c-4041-4624-8e0b-37d5ef6a38d5'::uuid,
          '2026-05-01'::date,
          'PLANO'::text,
          7654.38::numeric,
          'SERV_CONSULTORIA'::text,
          'DESP_CONSULTORIA'::text,
          'EXPLICITO'::text
        ),
        (
          'e31d47e9-ca0c-40de-a0ce-f5defe64097d'::uuid,
          '2026-05-01'::date,
          'PLANO DE SAUDE'::text,
          7654.38::numeric,
          'SERV_TERCEIROS'::text,
          'CUSTO_OS_SERV'::text,
          'EXPLICITO'::text
        ),
        (
          'ef845e18-5c64-45df-812f-8417f08b82de'::uuid,
          '2026-07-01'::date,
          'PLANO DE SAUDE'::text,
          7654.38::numeric,
          'OUTROS'::text,
          'DESP_GERAL'::text,
          'SISTEMA_FALLBACK'::text
        )
    ) as casos(
      titulo_id,
      competencia_date,
      descricao,
      valor_total,
      motivo_codigo,
      plano_codigo,
      origem_rateio
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
      and upper(btrim(t.descricao)) = v_caso.descricao
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
      and tr.origem_rateio = v_caso.origem_rateio
      and tr.deleted_at is null;

    if v_rateio_count <> 1 then
      raise exception
        'Rateio original do titulo % divergiu do caso validado.',
        v_caso.titulo_id;
    end if;

    v_titulo_ids := array_append(v_titulo_ids, v_caso.titulo_id);
  end loop;

  perform set_config('request.jwt.claim.role', 'service_role', true);

  -- Os dois titulos em OUTROS precisam ser corrigidos antes da troca do
  -- motivo. No rateio de fallback, a nova regra passa a representar o destino
  -- efetivo e a Central deixa corretamente de reportar a inconsistência.
  v_correcao_outros_resultado := f.corrigir_inconsistencias_financeiras(
    v_tenant_id,
    v_empresa_id,
    array[
      'b111c68f-2931-4678-9136-acfc6b9b2bf0'::uuid,
      'ef845e18-5c64-45df-812f-8417f08b82de'::uuid
    ],
    v_plano_beneficios_id,
    v_centro_pessoas_id,
    'Planos de saude de funcionarios e socios: Beneficios no centro Pessoas.',
    false
  );

  if coalesce(
    (v_correcao_outros_resultado ->> 'corrigidos')::integer,
    0
  ) <> 2 then
    raise exception
      'Correcao dos planos de saude em OUTROS retornou quantidade inesperada: %',
      v_correcao_outros_resultado;
  end if;

  update f.titulo t
  set
    motivo_compra_id = v_motivo_saude_id,
    updated_at = now()
  where t.id = any(v_titulo_ids)
    and t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id;

  update f.titulo_aprovacao ta
  set
    motivo_compra_id = v_motivo_saude_id,
    change_reason =
      'Plano de saude de funcionarios e socios: beneficio no centro Pessoas.',
    updated_at = now()
  where ta.tenant_id = v_tenant_id
    and ta.titulo_id = any(v_titulo_ids)
    and ta.deleted_at is null;

  -- Os outros tres titulos mantem rateios explicitos divergentes mesmo apos a
  -- troca do motivo e continuam corrigiveis pela Central.
  v_correcao_classificados_resultado :=
    f.corrigir_inconsistencias_financeiras(
      v_tenant_id,
      v_empresa_id,
      array[
        'd535f828-ef27-4858-b6e9-0e2e01714cf6'::uuid,
        'a3034c1c-4041-4624-8e0b-37d5ef6a38d5'::uuid,
        'e31d47e9-ca0c-40de-a0ce-f5defe64097d'::uuid
      ],
      v_plano_beneficios_id,
      v_centro_pessoas_id,
      'Planos de saude de funcionarios e socios: Beneficios no centro Pessoas.',
      false
    );

  if coalesce(
    (v_correcao_classificados_resultado ->> 'corrigidos')::integer,
    0
  ) <> 3 then
    raise exception
      'Correcao dos planos de saude classificados retornou quantidade inesperada: %',
      v_correcao_classificados_resultado;
  end if;

  update public.fornecedores f
  set
    motivo_compra_padrao_id = v_motivo_saude_id,
    atualizado_em = now()
  where f.id = v_fornecedor_id
    and f.tenant_id = v_tenant_id
    and f.empresa_id = v_empresa_id;

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
    'PLANO_SAUDE_CLASSIFICACAO_CONFIGURADA',
    'f.motivo_compra',
    v_motivo_saude_id,
    jsonb_build_object(
      'fornecedorId', v_fornecedor_id,
      'planoContasId', v_plano_beneficios_id,
      'centroCustoId', v_centro_pessoas_id,
      'regraRateioId', v_regra_id,
      'titulosCorrigidos', to_jsonb(v_titulo_ids),
      'valorTotal', 38302.45,
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false,
      'preservouOs', true
    )
  );
end;
$corrigir_planos_saude_bradesco$;
