-- Analice e Reinardo sao funcionarios ativos. Seus salarios mensais foram
-- criados com o motivo SALARIOS, mas esse motivo nao possuia plano de contas
-- e as 24 parcelas da serie ficaram em DESP_GERAL sem centro.
--
-- Cria o plano DESP_SALARIOS, configura o motivo SALARIOS para
-- DESP_SALARIOS/PESSOAS e corrige somente as parcelas salariais confirmadas.
-- O padrao dos fornecedores permanece inalterado porque os funcionarios
-- tambem recebem reembolsos e diarias com outros motivos.

do $corrigir_salarios_funcionarios_ativos$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_plano_salarios_id uuid;
  v_centro_pessoas_id uuid;
  v_motivo_salarios_id uuid;
  v_regra_id uuid;
  v_regra_resultado jsonb;
  v_correcao_resultado jsonb;
  v_titulo_ids uuid[] := array[]::uuid[];
  v_caso record;
  v_titulo f.titulo%rowtype;
  v_motivo_efetivo_id uuid;
  v_rateio_count integer;
begin
  select pc.id
    into v_plano_salarios_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_SALARIOS'
    and pc.deleted_at is null
  limit 1;

  if v_plano_salarios_id is null then
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
      'DESP_SALARIOS',
      'DESPESA - SALARIOS E REMUNERACOES',
      'ANALITICA',
      true,
      now(),
      now()
    )
    returning id into v_plano_salarios_id;
  else
    update f.plano_contas pc
    set
      nome = 'DESPESA - SALARIOS E REMUNERACOES',
      tipo = 'ANALITICA',
      ativo = true,
      updated_at = now(),
      deleted_at = null
    where pc.id = v_plano_salarios_id
      and pc.tenant_id = v_tenant_id;
  end if;

  select cc.id
    into strict v_centro_pessoas_id
  from f.centro_custo cc
  where cc.tenant_id = v_tenant_id
    and cc.empresa_id = v_empresa_id
    and cc.codigo = 'PESSOAS'
    and cc.ativo
    and cc.deleted_at is null;

  select mc.id
    into strict v_motivo_salarios_id
  from f.motivo_compra mc
  where mc.tenant_id = v_tenant_id
    and mc.codigo = 'SALARIOS'
    and mc.ativo
    and mc.deleted_at is null;

  update f.motivo_compra mc
  set
    plano_contas_id = v_plano_salarios_id,
    updated_at = now()
  where mc.id = v_motivo_salarios_id
    and mc.tenant_id = v_tenant_id;

  select rr.id
    into v_regra_id
  from f.regra_rateio rr
  where rr.tenant_id = v_tenant_id
    and rr.empresa_id = v_empresa_id
    and rr.motivo_compra_id = v_motivo_salarios_id
    and rr.ativo
    and rr.deleted_at is null
  limit 1;

  if v_regra_id is null then
    v_regra_resultado := f.salvar_regra_rateio(
      v_tenant_id,
      v_empresa_id,
      null,
      v_motivo_salarios_id,
      true,
      jsonb_build_array(jsonb_build_object(
        'plano_contas_id', v_plano_salarios_id,
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
      and rr.motivo_compra_id = v_motivo_salarios_id
      and rr.ativo
      and rr.deleted_at is null
      and rri.plano_contas_id = v_plano_salarios_id
      and rri.centro_custo_id = v_centro_pessoas_id
      and abs(rri.percentual - 100.0000) <= 0.0001
  ) then
    raise exception
      'Regra SALARIOS -> DESP_SALARIOS/PESSOAS nao esta configurada.';
  end if;

  if not exists (
    select 1
    from public.colaboradores c
    where c.id = 'd8c05145-b203-4041-9ebe-e47d8d9a88ae'::uuid
      and c.tenant_id = v_tenant_id
      and c.empresa_id = v_empresa_id
      and upper(btrim(c.nome)) = 'ANALICE BATISTA MARTINS'
      and upper(btrim(c.cargo)) = 'TEC. SEGURANÇA'
      and c.ativo
  ) then
    raise exception
      'Cadastro ativo da funcionaria Analice divergiu do contexto validado.';
  end if;

  if not exists (
    select 1
    from public.colaboradores c
    where c.id = 'f5174983-2805-46ba-9dfa-712eb6137e38'::uuid
      and c.tenant_id = v_tenant_id
      and c.empresa_id = v_empresa_id
      and upper(btrim(c.nome)) = 'REINARDO ANDRES VANEZCA QUINTERO'
      and upper(btrim(c.cargo)) = 'AUXILIAR ELE'
      and c.ativo
  ) then
    raise exception
      'Cadastro ativo do funcionario Reinardo divergiu do contexto validado.';
  end if;

  if not exists (
    select 1
    from public.fornecedores f
    where f.id = 428
      and f.tenant_id = v_tenant_id
      and f.empresa_id = v_empresa_id
      and upper(btrim(f.nome)) = 'ANALICE BATISTA MARTINS'
      and regexp_replace(coalesce(f.documento, ''), '\D', '', 'g') =
        '03259674900'
      and f.ativo
  ) or not exists (
    select 1
    from public.fornecedores f
    where f.id = 401
      and f.tenant_id = v_tenant_id
      and f.empresa_id = v_empresa_id
      and upper(btrim(f.nome)) = 'REINARDO ANDREZ VANEZCA QUINTERO'
      and regexp_replace(coalesce(f.documento, ''), '\D', '', 'g') =
        '11104866269'
      and f.ativo
  ) then
    raise exception
      'Cadastros financeiros dos funcionarios divergiram do contexto validado.';
  end if;

  for v_caso in
    select *
    from (
      values
        ('ff3a3230-9323-4fa8-be9b-d562e55f495a'::uuid, 428, '2026-03-01'::date, 4054.00::numeric),
        ('dfbf8e53-09e8-4943-bb13-04b15c054f14'::uuid, 428, '2026-04-01'::date, 4054.00::numeric),
        ('58ddbc9a-97bd-4353-ab32-7cd52e893417'::uuid, 428, '2026-05-01'::date, 4054.00::numeric),
        ('dc3cd7c6-9809-412e-aa22-98d8c8a77846'::uuid, 428, '2026-07-01'::date, 4054.00::numeric),
        ('aee0ebad-1a3d-4360-87e0-a863ba742260'::uuid, 428, '2026-08-01'::date, 4054.00::numeric),
        ('824e995c-4696-4139-945f-a2a1a6589422'::uuid, 428, '2026-09-01'::date, 4054.00::numeric),
        ('bcc89571-9b18-4abb-aa64-8a10fba063dd'::uuid, 428, '2026-10-01'::date, 4054.00::numeric),
        ('9b3d9b32-8f66-49c5-b7ac-4cf966ece189'::uuid, 428, '2026-11-01'::date, 4054.00::numeric),
        ('e060ba29-c619-4087-a9e0-67673dd57942'::uuid, 428, '2026-12-01'::date, 4054.00::numeric),
        ('84a563e6-bb57-4ada-9939-0f6f8dbb2b85'::uuid, 428, '2027-01-01'::date, 4054.00::numeric),
        ('0e257983-02e1-400d-8055-9644472ae303'::uuid, 428, '2027-02-01'::date, 4054.00::numeric),
        ('de7d7c89-0713-443c-9833-4f524aa47af5'::uuid, 428, '2027-03-01'::date, 4054.00::numeric),
        ('fad368f4-8ea2-40f5-aebe-4e7d5c6baca2'::uuid, 401, '2026-03-01'::date, 3058.00::numeric),
        ('1cd0cf37-87eb-4d2b-91b3-89467814d5b5'::uuid, 401, '2026-04-01'::date, 3058.00::numeric),
        ('ee0e0659-027f-4141-8016-58b9c6b86b3c'::uuid, 401, '2026-05-01'::date, 3058.00::numeric),
        ('9c2b82e1-1699-47f5-a6dd-211bd9ee5bf5'::uuid, 401, '2026-07-01'::date, 3058.00::numeric),
        ('32ba889b-0ef2-48bb-8d3c-4a3c48f5c623'::uuid, 401, '2026-08-01'::date, 3058.00::numeric),
        ('d62907a1-b279-495a-a59a-bac56051a529'::uuid, 401, '2026-09-01'::date, 3058.00::numeric),
        ('6af710a0-17fc-449f-a949-aadacc7f4e30'::uuid, 401, '2026-10-01'::date, 3058.00::numeric),
        ('891723ad-004a-43dc-add2-34ef89b79583'::uuid, 401, '2026-11-01'::date, 3058.00::numeric),
        ('cd423cb4-b903-404f-beac-c74d942aded5'::uuid, 401, '2026-12-01'::date, 3058.00::numeric),
        ('b2f0cb20-a067-4c5b-8327-cb16a874e2a8'::uuid, 401, '2027-01-01'::date, 3058.00::numeric),
        ('89b0bdf5-25b3-42c1-8c52-f62908d939dc'::uuid, 401, '2027-02-01'::date, 3058.00::numeric),
        ('88de7690-007e-40fc-9490-94141114981b'::uuid, 401, '2027-03-01'::date, 3058.00::numeric)
    ) as casos(titulo_id, fornecedor_id, competencia_date, valor_total)
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
      and t.fornecedor_id = v_caso.fornecedor_id
      and t.valor_total = v_caso.valor_total
      and coalesce(t.competencia_date, t.emissao_date) =
        v_caso.competencia_date
      and upper(btrim(t.descricao)) = 'SALARIO MENSAL'
      and t.documento_fiscal_id is null
      and not f.titulo_eh_legado_implantacao(
        t.tenant_id,
        t.empresa_id,
        t.id
      )
    for update;

    select coalesce(
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
      into v_motivo_efetivo_id;

    if v_motivo_efetivo_id is distinct from v_motivo_salarios_id then
      raise exception
        'Titulo % nao possui mais o motivo SALARIOS.',
        v_caso.titulo_id;
    end if;

    select count(*)::integer
      into v_rateio_count
    from f.titulo_rateio tr
    join f.plano_contas pc
      on pc.id = tr.plano_contas_id
     and pc.tenant_id = tr.tenant_id
     and pc.codigo = 'DESP_GERAL'
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

    v_titulo_ids := array_append(v_titulo_ids, v_caso.titulo_id);
  end loop;

  perform set_config('request.jwt.claim.role', 'service_role', true);

  v_correcao_resultado := f.corrigir_inconsistencias_financeiras(
    v_tenant_id,
    v_empresa_id,
    v_titulo_ids,
    v_plano_salarios_id,
    v_centro_pessoas_id,
    'Salarios mensais de funcionarios ativos: plano de salarios e centro Pessoas.',
    false
  );

  if coalesce((v_correcao_resultado ->> 'corrigidos')::integer, 0) <> 24 then
    raise exception
      'Correcao dos salarios retornou quantidade inesperada: %',
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
    'SALARIOS_FUNCIONARIOS_ATIVOS_CLASSIFICACAO_CONFIGURADA',
    'f.motivo_compra',
    v_motivo_salarios_id,
    jsonb_build_object(
      'planoContasId', v_plano_salarios_id,
      'centroCustoId', v_centro_pessoas_id,
      'regraRateioId', v_regra_id,
      'titulosCorrigidos', to_jsonb(v_titulo_ids),
      'funcionarios', jsonb_build_array(
        jsonb_build_object(
          'fornecedorId', 428,
          'colaboradorId', 'd8c05145-b203-4041-9ebe-e47d8d9a88ae',
          'nome', 'ANALICE BATISTA MARTINS',
          'cargo', 'TEC. SEGURANÇA',
          'parcelasCorrigidas', 12,
          'valorMensal', 4054.00
        ),
        jsonb_build_object(
          'fornecedorId', 401,
          'colaboradorId', 'f5174983-2805-46ba-9dfa-712eb6137e38',
          'nome', 'REINARDO ANDRES VANEZCA QUINTERO',
          'cargo', 'AUXILIAR ELE',
          'parcelasCorrigidas', 12,
          'valorMensal', 3058.00
        )
      ),
      'valorTotal', 85344.00,
      'fornecedorPadraoAlterado', false,
      'motivoFornecedorPreservado',
        'Funcionarios tambem recebem reembolsos e diarias.',
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false,
      'preservouOs', true
    )
  );
end;
$corrigir_salarios_funcionarios_ativos$;
