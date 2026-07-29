-- A casa alugada em Tijucas e usada como apoio para os funcionarios que
-- executam servicos em campo. O plano DESP_ALUGUEL ja esta correto, mas o
-- motivo generico OPEX_ALUGUEL nao identifica o centro responsavel.
--
-- Cria um motivo especifico para este aluguel recorrente, configura o destino
-- CAMPO e corrige as cinco mensalidades confirmadas entre marco e julho.

do $corrigir_aluguel_casa_tijucas$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_fornecedor_id constant integer := 447;
  v_motivo_aluguel_id uuid;
  v_plano_aluguel_id uuid;
  v_centro_campo_id uuid;
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
    into strict v_plano_aluguel_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_ALUGUEL'
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
    'OPEX_ALUGUEL_APOIO_CAMPO',
    'OPEX - ALUGUEL CASA APOIO CAMPO',
    false,
    false,
    true,
    'SERVICO',
    v_plano_aluguel_id,
    true,
    845,
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
      and rr.motivo_compra_id = v_motivo_aluguel_id
      and rr.ativo
      and rr.deleted_at is null
      and rri.plano_contas_id = v_plano_aluguel_id
      and rri.centro_custo_id = v_centro_campo_id
      and abs(rri.percentual - 100.0000) <= 0.0001
  ) then
    raise exception
      'Regra OPEX_ALUGUEL_APOIO_CAMPO -> DESP_ALUGUEL/CAMPO nao esta configurada.';
  end if;

  if not exists (
    select 1
    from public.fornecedores f
    where f.id = v_fornecedor_id
      and f.tenant_id = v_tenant_id
      and f.empresa_id = v_empresa_id
      and upper(btrim(f.nome)) = 'TYUCO IMOVEIS'
      and regexp_replace(coalesce(f.documento, ''), '\D', '', 'g') =
        '05325322000124'
      and f.ativo
  ) then
    raise exception
      'Fornecedor TYUCO IMOVEIS divergiu do cadastro validado.';
  end if;

  for v_caso in
    select *
    from (
      values
        (
          '69d974a5-89cd-42db-80d6-c65989d036fd'::uuid,
          '2026-03-01'::date
        ),
        (
          '7443e195-0bdf-4fc8-b9a3-bbf4c6b86bea'::uuid,
          '2026-04-01'::date
        ),
        (
          'a1d2a82a-435e-46b7-b0d0-2b1d8ee39827'::uuid,
          '2026-05-01'::date
        ),
        (
          'ceeed4b0-ff07-491b-89ce-a5f305120beb'::uuid,
          '2026-06-01'::date
        ),
        (
          'b99f9a9b-3303-4a41-8db4-559a646b2b4b'::uuid,
          '2026-07-01'::date
        )
    ) as casos(titulo_id, competencia_date)
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
      and t.valor_total = 2711.36
      and coalesce(t.competencia_date, t.emissao_date) =
        v_caso.competencia_date
      and upper(btrim(t.descricao)) = 'ALUGUEL CASA TIJUCAS'
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

    if v_motivo_efetivo_codigo is distinct from 'OPEX_ALUGUEL' then
      raise exception
        'Motivo original do titulo % divergiu do caso validado.',
        v_caso.titulo_id;
    end if;

    select count(*)::integer
      into v_rateio_count
    from f.titulo_rateio tr
    where tr.tenant_id = v_tenant_id
      and tr.titulo_id = v_caso.titulo_id
      and tr.plano_contas_id = v_plano_aluguel_id
      and tr.centro_custo_id is null
      and tr.os_id is null
      and abs(tr.percentual - 100.0000) <= 0.0001
      and tr.valor = 2711.36
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
        'Casa em Tijucas usada como apoio para funcionarios em servicos de campo.',
      updated_at = now()
    where ta.tenant_id = v_tenant_id
      and ta.titulo_id = v_caso.titulo_id
      and ta.deleted_at is null;

    v_titulo_ids := array_append(v_titulo_ids, v_caso.titulo_id);
  end loop;

  update public.fornecedores f
  set
    motivo_compra_padrao_id = v_motivo_aluguel_id,
    atualizado_em = now()
  where f.id = v_fornecedor_id
    and f.tenant_id = v_tenant_id
    and f.empresa_id = v_empresa_id;

  perform set_config('request.jwt.claim.role', 'service_role', true);

  v_correcao_resultado := f.corrigir_inconsistencias_financeiras(
    v_tenant_id,
    v_empresa_id,
    v_titulo_ids,
    v_plano_aluguel_id,
    v_centro_campo_id,
    'Casa de apoio em Tijucas: aluguel operacional do centro Servicos em Campo.',
    false
  );

  if coalesce((v_correcao_resultado ->> 'corrigidos')::integer, 0) <> 5 then
    raise exception
      'Correcao do aluguel da casa de Tijucas retornou quantidade inesperada: %',
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
    'ALUGUEL_APOIO_CAMPO_CLASSIFICACAO_CONFIGURADA',
    'f.motivo_compra',
    v_motivo_aluguel_id,
    jsonb_build_object(
      'fornecedorId', v_fornecedor_id,
      'planoContasId', v_plano_aluguel_id,
      'centroCustoId', v_centro_campo_id,
      'regraRateioId', v_regra_id,
      'titulosCorrigidos', to_jsonb(v_titulo_ids),
      'valorTotal', 13556.80,
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false,
      'preservouOs', true
    )
  );
end;
$corrigir_aluguel_casa_tijucas$;
