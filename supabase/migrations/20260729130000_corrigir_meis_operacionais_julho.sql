-- Os pagamentos mensais abaixo sao de prestadores MEI da equipe operacional.
-- O historico de fevereiro a junho ja os classificava como servicos de
-- terceiros, mas os titulos de julho foram lancados como SALARIOS e
-- DESP_GERAL. Como os profissionais atuam em varias OS no mesmo mes, o custo
-- nao deve ser vinculado a uma unica OS.
--
-- Cria um motivo especifico para evitar uma regra generica de
-- SERV_TERCEIROS (que tambem atende servicos administrativos e de estrutura),
-- configura o destino PRODUCAO e corrige somente os 12 titulos confirmados.

do $corrigir_meis_operacionais_julho$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_motivo_salarios_id uuid;
  v_motivo_mei_id uuid;
  v_plano_servicos_id uuid;
  v_centro_producao_id uuid;
  v_regra_id uuid;
  v_regra_resultado jsonb;
  v_correcao_resultado jsonb;
  v_titulo_ids uuid[] := array[]::uuid[];
  v_caso record;
  v_titulo f.titulo%rowtype;
  v_motivo_efetivo_id uuid;
  v_rateio_count integer;
begin
  select mc.id
    into strict v_motivo_salarios_id
  from f.motivo_compra mc
  where mc.tenant_id = v_tenant_id
    and mc.codigo = 'SALARIOS'
    and mc.ativo
    and mc.deleted_at is null;

  select pc.id
    into strict v_plano_servicos_id
  from f.plano_contas pc
  where pc.tenant_id = v_tenant_id
    and pc.codigo = 'DESP_SERV_TERCEIROS'
    and pc.tipo = 'ANALITICA'
    and pc.ativo
    and pc.deleted_at is null;

  select cc.id
    into strict v_centro_producao_id
  from f.centro_custo cc
  where cc.tenant_id = v_tenant_id
    and cc.empresa_id = v_empresa_id
    and cc.codigo = 'PRODUCAO'
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
    'SERV_MEI_OPERACIONAL',
    'SERVICOS MEI - EQUIPE OPERACIONAL',
    false,
    false,
    true,
    'SERVICO',
    v_plano_servicos_id,
    true,
    850,
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
  returning id into v_motivo_mei_id;

  select rr.id
    into v_regra_id
  from f.regra_rateio rr
  where rr.tenant_id = v_tenant_id
    and rr.empresa_id = v_empresa_id
    and rr.motivo_compra_id = v_motivo_mei_id
    and rr.ativo
    and rr.deleted_at is null
  limit 1;

  if v_regra_id is null then
    v_regra_resultado := f.salvar_regra_rateio(
      v_tenant_id,
      v_empresa_id,
      null,
      v_motivo_mei_id,
      true,
      jsonb_build_array(jsonb_build_object(
        'plano_contas_id', v_plano_servicos_id,
        'centro_custo_id', v_centro_producao_id,
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
      and rr.motivo_compra_id = v_motivo_mei_id
      and rr.ativo
      and rr.deleted_at is null
      and rri.plano_contas_id = v_plano_servicos_id
      and rri.centro_custo_id = v_centro_producao_id
      and abs(rri.percentual - 100.0000) <= 0.0001
  ) then
    raise exception
      'Regra SERV_MEI_OPERACIONAL -> PRODUCAO nao esta configurada.';
  end if;

  for v_caso in
    select *
    from (
      values
        (
          '83440bc1-5d36-4e8d-8820-ccd784fa50fe'::uuid,
          354::integer,
          'DOUGLAS LUIZ WIEMES'::text,
          13000.00::numeric
        ),
        (
          'f88ce0f7-bf7d-41eb-a8f5-9bc3a4dcb96b'::uuid,
          353::integer,
          'FRANCISCO DIAS DE SOUZA'::text,
          8963.50::numeric
        ),
        (
          '0ced54da-fc2f-46f2-a1e7-b622f636df5d'::uuid,
          358::integer,
          'ALCINO JOAO VIEIRA'::text,
          7916.67::numeric
        ),
        (
          'e7623fcb-235b-4bee-958c-dc5e3a15605a'::uuid,
          351::integer,
          'PAULO ANDRE DOS SANTOS SOUZA'::text,
          7465.00::numeric
        ),
        (
          '2e3b1d81-c5fe-446c-b0a5-60f9511186b6'::uuid,
          349::integer,
          'NADYJAN VIEIRA DA SILVA'::text,
          7212.92::numeric
        ),
        (
          'e596e73a-2be2-4588-a3a8-f8f0713086e4'::uuid,
          372::integer,
          'ARLINDO LUIZ BERKENBROCK'::text,
          7092.75::numeric
        ),
        (
          'de91d612-a893-4d7a-8c29-93cbf0bf5e8f'::uuid,
          355::integer,
          'RICHARDSON BORTOLO MILIOLI'::text,
          7012.50::numeric
        ),
        (
          '23a6c3f9-f145-42a1-8624-efc58064bb3f'::uuid,
          397::integer,
          'SAMUEL DUTRA DE SOUZA'::text,
          6871.00::numeric
        ),
        (
          '631e8581-68fc-4a6f-93e2-b96b92608652'::uuid,
          350::integer,
          'FAGNER RASCHE'::text,
          6549.10::numeric
        ),
        (
          '31a76c73-d2a7-4d2e-b499-65e2061573c5'::uuid,
          315::integer,
          'MATEUS CAMILO DO NASCIMENTO'::text,
          6000.00::numeric
        ),
        (
          'd5ba6a7f-4675-4790-b295-dfcc8ee38a3e'::uuid,
          356::integer,
          'ANDRIEL AMORIM RUFATO'::text,
          5865.20::numeric
        ),
        (
          '91766ad6-d760-49b7-9296-b032f3d3cff1'::uuid,
          357::integer,
          'SIMPLICIO DA COSTA ALVES'::text,
          4377.47::numeric
        )
    ) as casos(titulo_id, fornecedor_id, fornecedor_nome, valor_total)
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
      and upper(btrim(t.descricao)) = 'SALARIO MEI'
      and coalesce(t.competencia_date, t.emissao_date) = '2026-07-01'::date
    for update;

    if not exists (
      select 1
      from public.fornecedores f
      where f.id = v_caso.fornecedor_id
        and f.tenant_id = v_tenant_id
        and f.empresa_id = v_empresa_id
        and upper(btrim(f.nome)) = v_caso.fornecedor_nome
        and length(regexp_replace(coalesce(f.documento, ''), '\D', '', 'g')) = 14
        and f.ativo
    ) then
      raise exception
        'Fornecedor MEI % divergiu do caso validado.',
        v_caso.fornecedor_nome;
    end if;

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
    where tr.tenant_id = v_tenant_id
      and tr.titulo_id = v_caso.titulo_id
      and tr.deleted_at is null
      and tr.plano_contas_id = (
        select pc.id
        from f.plano_contas pc
        where pc.tenant_id = v_tenant_id
          and pc.codigo = 'DESP_GERAL'
          and pc.ativo
          and pc.deleted_at is null
      )
      and tr.centro_custo_id is null
      and tr.os_id is null
      and abs(tr.percentual - 100.0000) <= 0.0001
      and tr.valor = v_caso.valor_total;

    if v_rateio_count <> 1 then
      raise exception
        'Rateio original do titulo % divergiu do caso validado.',
        v_caso.titulo_id;
    end if;

    update f.titulo t
    set
      motivo_compra_id = v_motivo_mei_id,
      updated_at = now()
    where t.id = v_caso.titulo_id
      and t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id;

    update f.titulo_aprovacao ta
    set
      motivo_compra_id = v_motivo_mei_id,
      change_reason =
        'Prestador MEI operacional: servicos de terceiros para Producao.',
      updated_at = now()
    where ta.tenant_id = v_tenant_id
      and ta.titulo_id = v_caso.titulo_id
      and ta.deleted_at is null;

    update public.fornecedores f
    set
      motivo_compra_padrao_id = v_motivo_mei_id,
      atualizado_em = now()
    where f.id = v_caso.fornecedor_id
      and f.tenant_id = v_tenant_id
      and f.empresa_id = v_empresa_id;

    v_titulo_ids := array_append(v_titulo_ids, v_caso.titulo_id);
  end loop;

  -- A RPC central registra a correcao, marca as inconsistencias resolvidas e
  -- garante que valor, vencimento, pagamentos e vinculos existentes nao mudem.
  perform set_config('request.jwt.claim.role', 'service_role', true);

  v_correcao_resultado := f.corrigir_inconsistencias_financeiras(
    v_tenant_id,
    v_empresa_id,
    v_titulo_ids,
    v_plano_servicos_id,
    v_centro_producao_id,
    'Prestadores MEI operacionais: servicos de terceiros no centro Producao.',
    false
  );

  if coalesce((v_correcao_resultado ->> 'corrigidos')::integer, 0) <> 12 then
    raise exception
      'Correcao dos MEIs retornou quantidade inesperada: %',
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
    'MEI_OPERACIONAL_CLASSIFICACAO_CONFIGURADA',
    'f.motivo_compra',
    v_motivo_mei_id,
    jsonb_build_object(
      'motivoAnteriorId', v_motivo_salarios_id,
      'motivoNovoId', v_motivo_mei_id,
      'planoContasId', v_plano_servicos_id,
      'centroCustoId', v_centro_producao_id,
      'regraRateioId', v_regra_id,
      'titulosCorrigidos', to_jsonb(v_titulo_ids),
      'fornecedoresComPadraoAtualizado', 12,
      'valorTotal', 88326.11,
      'alterouValor', false,
      'alterouVencimento', false,
      'alterouPagamento', false,
      'preservouOs', true
    )
  );
end;
$corrigir_meis_operacionais_julho$;
