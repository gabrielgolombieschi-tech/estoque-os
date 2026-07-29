-- Corrige os titulos de julho que ja possuem a classificacao correta de
-- material direto de OS, mas foram importados antes da regra de centro:
--   motivo: OS_MATERIAL_DIRETO
--   plano:  CUSTO_OS_MAT
--   centro: PRODUCAO
--
-- O escopo fica fechado nos 15 titulos confirmados, com validacao de
-- fornecedor, documento, valor, competencia e rateio unico de 100%.

do $corrigir_custo_os_mat_sem_centro_julho$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_motivo_id uuid;
  v_plano_id uuid;
  v_centro_id uuid;
  v_titulo_ids uuid[] := array[]::uuid[];
  v_caso record;
  v_titulo f.titulo%rowtype;
  v_motivo_efetivo_id uuid;
  v_rateio_count integer;
  v_resultado jsonb;
begin
  select mc.id, mc.plano_contas_id
    into strict v_motivo_id, v_plano_id
  from f.motivo_compra mc
  join f.plano_contas pc
    on pc.id = mc.plano_contas_id
   and pc.tenant_id = mc.tenant_id
   and pc.codigo = 'CUSTO_OS_MAT'
   and pc.tipo = 'ANALITICA'
   and pc.ativo
   and pc.deleted_at is null
  where mc.tenant_id = v_tenant_id
    and mc.codigo = 'OS_MATERIAL_DIRETO'
    and mc.ativo
    and mc.deleted_at is null;

  select cc.id
    into strict v_centro_id
  from f.centro_custo cc
  where cc.tenant_id = v_tenant_id
    and cc.empresa_id = v_empresa_id
    and cc.codigo = 'PRODUCAO'
    and cc.ativo
    and cc.deleted_at is null;

  if not exists (
    select 1
    from f.regra_rateio rr
    join f.regra_rateio_item rri
      on rri.tenant_id = rr.tenant_id
     and rri.regra_rateio_id = rr.id
     and rri.deleted_at is null
    where rr.tenant_id = v_tenant_id
      and rr.empresa_id = v_empresa_id
      and rr.motivo_compra_id = v_motivo_id
      and rr.ativo
      and rr.deleted_at is null
      and rri.plano_contas_id = v_plano_id
      and rri.centro_custo_id = v_centro_id
      and abs(rri.percentual - 100.0000) <= 0.0001
  ) then
    raise exception
      'Regra OS_MATERIAL_DIRETO -> CUSTO_OS_MAT/PRODUCAO nao esta configurada.';
  end if;

  for v_caso in
    select *
    from (
      values
        (
          '6833f734-6e32-42b9-a700-3e4f832f26b6'::uuid,
          3::integer,
          '377371'::text,
          18006.42::numeric
        ),
        (
          'cacbea67-d3ad-4199-b609-9b3b6e38ff0a'::uuid,
          3::integer,
          '371577'::text,
          5905.45::numeric
        ),
        (
          '52b4dff9-6850-4592-95da-d7d2c6fb9d6e'::uuid,
          618::integer,
          '499111'::text,
          5207.61::numeric
        ),
        (
          '96586b9e-c782-41f5-a6a1-88abda93199f'::uuid,
          246::integer,
          '520196'::text,
          5123.36::numeric
        ),
        (
          'a3632944-2d6a-4c73-a5ca-006a178405a4'::uuid,
          14::integer,
          '360350'::text,
          4413.62::numeric
        ),
        (
          'ca70f594-3eda-454a-838b-2334a7a1b610'::uuid,
          260::integer,
          '441'::text,
          1441.80::numeric
        ),
        (
          'c6b512d9-64bd-4f2b-a76e-c3a4a8537535'::uuid,
          131::integer,
          '4431528'::text,
          1373.70::numeric
        ),
        (
          '885c1218-80e4-4dbe-9f6b-e16e3775ea1a'::uuid,
          246::integer,
          '520604'::text,
          735.11::numeric
        ),
        (
          '551ae8b0-6c7a-4b1a-a9c1-9a36e5a5f2bb'::uuid,
          169::integer,
          '99611'::text,
          579.00::numeric
        ),
        (
          'a1eafbc0-a185-4b1e-9187-1c5a9f3e237a'::uuid,
          250::integer,
          '362633'::text,
          538.40::numeric
        ),
        (
          '5e417493-5d42-472e-8b1f-e2954683090c'::uuid,
          618::integer,
          '501275'::text,
          349.03::numeric
        ),
        (
          '34722a8e-5a9f-4a5a-9ff1-e7114e641dd2'::uuid,
          3::integer,
          '371573'::text,
          250.03::numeric
        ),
        (
          '28ee0d4c-55e4-43fd-8fea-ba4cc33a673a'::uuid,
          35::integer,
          '44357'::text,
          206.61::numeric
        ),
        (
          'f862af9b-dddf-45da-8132-0735c7ea2e7d'::uuid,
          348::integer,
          '202828'::text,
          135.72::numeric
        ),
        (
          '2e989d46-a128-4066-bb6c-27a71787b648'::uuid,
          348::integer,
          '202829'::text,
          51.86::numeric
        )
    ) as casos(titulo_id, fornecedor_id, documento, valor_total)
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
      and t.competencia_date = '2026-07-01'::date
      and upper(btrim(t.descricao)) like
        'NF-E ' || v_caso.documento || '/%'
    for update;

    if not exists (
      select 1
      from f.documento_fiscal df
      join public.nf_entrada ne
        on ne.id = df.source_nf_entrada_id
       and ne.tenant_id = df.tenant_id
       and ne.empresa_id = df.empresa_id
      where df.tenant_id = v_tenant_id
        and df.empresa_id = v_empresa_id
        and df.id = v_titulo.documento_fiscal_id
        and df.deleted_at is null
        and ne.numero = v_caso.documento
        and ne.fornecedor_id = v_caso.fornecedor_id
        and ne.valor_total = v_caso.valor_total
        and ne.motivo_compra_id = v_motivo_id
        and ne.finalidade_contexto = 'materia_prima'
    ) then
      raise exception
        'Documento fiscal do titulo % divergiu do caso validado.',
        v_caso.titulo_id;
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

    if v_motivo_efetivo_id is distinct from v_motivo_id then
      raise exception
        'Titulo % nao possui mais o motivo OS_MATERIAL_DIRETO.',
        v_caso.titulo_id;
    end if;

    select count(*)::integer
      into v_rateio_count
    from f.titulo_rateio tr
    where tr.tenant_id = v_tenant_id
      and tr.titulo_id = v_caso.titulo_id
      and tr.plano_contas_id = v_plano_id
      and tr.centro_custo_id is null
      and tr.os_id is null
      and tr.percentual = 100.0000
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

  v_resultado := f.corrigir_inconsistencias_financeiras(
    v_tenant_id,
    v_empresa_id,
    v_titulo_ids,
    v_plano_id,
    v_centro_id,
    'Material direto de OS: plano CUSTO_OS_MAT e centro Producao.',
    false
  );

  if coalesce((v_resultado ->> 'corrigidos')::integer, 0) <> 15 then
    raise exception
      'Correcao de CUSTO_OS_MAT retornou quantidade inesperada: %',
      v_resultado;
  end if;
end;
$corrigir_custo_os_mat_sem_centro_julho$;
