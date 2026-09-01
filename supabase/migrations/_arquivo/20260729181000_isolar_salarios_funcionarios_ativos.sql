-- O motivo legado SALARIOS tambem foi usado em titulos historicos de MEIs e
-- pessoas sem cadastro ativo. Para nao aplicar a regra salarial a esses casos,
-- isola Analice e Reinardo em um motivo especifico de funcionario ativo.
--
-- Os rateios das 24 parcelas ja estao corretos em DESP_SALARIOS/PESSOAS.
-- Esta migration somente ajusta o motivo, move a regra para o novo motivo e
-- devolve o motivo legado ao estado sem plano/regra, evitando efeito colateral.

do $isolar_salarios_funcionarios_ativos$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_titulo_ids uuid[] := array[
    'ff3a3230-9323-4fa8-be9b-d562e55f495a'::uuid,
    'dfbf8e53-09e8-4943-bb13-04b15c054f14'::uuid,
    '58ddbc9a-97bd-4353-ab32-7cd52e893417'::uuid,
    'dc3cd7c6-9809-412e-aa22-98d8c8a77846'::uuid,
    'aee0ebad-1a3d-4360-87e0-a863ba742260'::uuid,
    '824e995c-4696-4139-945f-a2a1a6589422'::uuid,
    'bcc89571-9b18-4abb-aa64-8a10fba063dd'::uuid,
    '9b3d9b32-8f66-49c5-b7ac-4cf966ece189'::uuid,
    'e060ba29-c619-4087-a9e0-67673dd57942'::uuid,
    '84a563e6-bb57-4ada-9939-0f6f8dbb2b85'::uuid,
    '0e257983-02e1-400d-8055-9644472ae303'::uuid,
    'de7d7c89-0713-443c-9833-4f524aa47af5'::uuid,
    'fad368f4-8ea2-40f5-aebe-4e7d5c6baca2'::uuid,
    '1cd0cf37-87eb-4d2b-91b3-89467814d5b5'::uuid,
    'ee0e0659-027f-4141-8016-58b9c6b86b3c'::uuid,
    '9c2b82e1-1699-47f5-a6dd-211bd9ee5bf5'::uuid,
    '32ba889b-0ef2-48bb-8d3c-4a3c48f5c623'::uuid,
    'd62907a1-b279-495a-a59a-bac56051a529'::uuid,
    '6af710a0-17fc-449f-a949-aadacc7f4e30'::uuid,
    '891723ad-004a-43dc-add2-34ef89b79583'::uuid,
    'cd423cb4-b903-404f-beac-c74d942aded5'::uuid,
    'b2f0cb20-a067-4c5b-8327-cb16a874e2a8'::uuid,
    '89b0bdf5-25b3-42c1-8c52-f62908d939dc'::uuid,
    '88de7690-007e-40fc-9490-94141114981b'::uuid
  ];
  v_plano_salarios_id uuid;
  v_centro_pessoas_id uuid;
  v_motivo_legado_id uuid;
  v_motivo_ativo_id uuid;
  v_regra_legada_id uuid;
  v_regra_ativa_id uuid;
  v_regra_resultado jsonb;
  v_count integer;
begin
  select pc.id
    into strict v_plano_salarios_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_SALARIOS'
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

  select mc.id
    into strict v_motivo_legado_id
  from f.motivo_compra mc
  where mc.tenant_id = v_tenant_id
    and mc.codigo = 'SALARIOS'
    and mc.plano_contas_id = v_plano_salarios_id
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
    'SALARIO_FUNCIONARIO_ATIVO',
    'SALARIO - FUNCIONARIO ATIVO',
    false,
    false,
    true,
    'SERVICO',
    v_plano_salarios_id,
    true,
    831,
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
  returning id into v_motivo_ativo_id;

  select rr.id
    into v_regra_ativa_id
  from f.regra_rateio rr
  where rr.tenant_id = v_tenant_id
    and rr.empresa_id = v_empresa_id
    and rr.motivo_compra_id = v_motivo_ativo_id
    and rr.ativo
    and rr.deleted_at is null
  limit 1;

  if v_regra_ativa_id is null then
    v_regra_resultado := f.salvar_regra_rateio(
      v_tenant_id,
      v_empresa_id,
      null,
      v_motivo_ativo_id,
      true,
      jsonb_build_array(jsonb_build_object(
        'plano_contas_id', v_plano_salarios_id,
        'centro_custo_id', v_centro_pessoas_id,
        'percentual', 100.0000
      ))
    );
    v_regra_ativa_id := (v_regra_resultado ->> 'id')::uuid;
  end if;

  if not exists (
    select 1
    from f.regra_rateio rr
    join f.regra_rateio_item rri
      on rri.tenant_id = rr.tenant_id
     and rri.regra_rateio_id = rr.id
     and rri.deleted_at is null
    where rr.id = v_regra_ativa_id
      and rr.tenant_id = v_tenant_id
      and rr.empresa_id = v_empresa_id
      and rr.motivo_compra_id = v_motivo_ativo_id
      and rr.ativo
      and rr.deleted_at is null
      and rri.plano_contas_id = v_plano_salarios_id
      and rri.centro_custo_id = v_centro_pessoas_id
      and abs(rri.percentual - 100.0000) <= 0.0001
  ) then
    raise exception
      'Regra SALARIO_FUNCIONARIO_ATIVO -> DESP_SALARIOS/PESSOAS invalida.';
  end if;

  select count(*)::integer
    into v_count
  from f.titulo t
  where t.id = any(v_titulo_ids)
    and t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id
    and t.tipo = 'AP'
    and t.status <> 'CANCELADO'
    and t.deleted_at is null
    and t.fornecedor_id in (401, 428)
    and upper(btrim(t.descricao)) = 'SALARIO MENSAL'
    and t.motivo_compra_id = v_motivo_legado_id
    and exists (
      select 1
      from f.titulo_rateio tr
      where tr.tenant_id = v_tenant_id
        and tr.titulo_id = t.id
        and tr.plano_contas_id = v_plano_salarios_id
        and tr.centro_custo_id = v_centro_pessoas_id
        and tr.os_id is null
        and abs(tr.percentual - 100.0000) <= 0.0001
        and tr.valor = t.valor_total
        and tr.deleted_at is null
    );

  if v_count <> 24 then
    raise exception
      'Quantidade inesperada de salarios corrigidos para isolar: %.',
      v_count;
  end if;

  update f.titulo t
  set
    motivo_compra_id = v_motivo_ativo_id,
    updated_at = now()
  where t.id = any(v_titulo_ids)
    and t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id;

  update f.titulo_aprovacao ta
  set
    motivo_compra_id = v_motivo_ativo_id,
    change_reason =
      'Salario mensal de funcionario ativo: plano de salarios e centro Pessoas.',
    updated_at = now()
  where ta.tenant_id = v_tenant_id
    and ta.titulo_id = any(v_titulo_ids)
    and ta.deleted_at is null;

  select rr.id
    into strict v_regra_legada_id
  from f.regra_rateio rr
  where rr.tenant_id = v_tenant_id
    and rr.empresa_id = v_empresa_id
    and rr.motivo_compra_id = v_motivo_legado_id
    and rr.ativo
    and rr.deleted_at is null;

  if not exists (
    select 1
    from f.regra_rateio_item rri
    where rri.tenant_id = v_tenant_id
      and rri.regra_rateio_id = v_regra_legada_id
      and rri.plano_contas_id = v_plano_salarios_id
      and rri.centro_custo_id = v_centro_pessoas_id
      and abs(rri.percentual - 100.0000) <= 0.0001
      and rri.deleted_at is null
  ) then
    raise exception
      'Regra legada SALARIOS divergiu antes do isolamento.';
  end if;

  update f.regra_rateio_item rri
  set
    updated_at = now(),
    deleted_at = now()
  where rri.tenant_id = v_tenant_id
    and rri.regra_rateio_id = v_regra_legada_id
    and rri.deleted_at is null;

  update f.regra_rateio rr
  set
    ativo = false,
    updated_at = now(),
    deleted_at = now()
  where rr.id = v_regra_legada_id
    and rr.tenant_id = v_tenant_id
    and rr.empresa_id = v_empresa_id;

  update f.motivo_compra mc
  set
    plano_contas_id = null,
    updated_at = now()
  where mc.id = v_motivo_legado_id
    and mc.tenant_id = v_tenant_id;

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
    'SALARIOS_FUNCIONARIOS_ATIVOS_ISOLADOS',
    'f.motivo_compra',
    v_motivo_ativo_id,
    jsonb_build_object(
      'motivoLegadoId', v_motivo_legado_id,
      'motivoAtivoId', v_motivo_ativo_id,
      'planoContasId', v_plano_salarios_id,
      'centroCustoId', v_centro_pessoas_id,
      'regraLegadaArquivadaId', v_regra_legada_id,
      'regraAtivaId', v_regra_ativa_id,
      'titulosIsolados', to_jsonb(v_titulo_ids),
      'quantidade', 24,
      'motivo',
        'SALARIOS legado tambem aparece em MEIs e pessoas sem cadastro ativo.',
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false
    )
  );
end;
$isolar_salarios_funcionarios_ativos$;
