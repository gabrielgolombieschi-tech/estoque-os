-- A NF 63964/1 da Eletrica Segau foi importada diretamente para a OS 282,
-- mas herdou do fornecedor o motivo EST_MATERIA_PRIMA. O vinculo operacional
-- com a OS foi gravado corretamente; esta migracao realinha somente a
-- classificacao financeira e recria o rateio pela regra OS_MATERIAL_DIRETO.

do $corrigir_nf_63964$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_chave constant text :=
    '42260707421949000104550010000639641492526330';
  v_nf public.nf_entrada%rowtype;
  v_titulo_id uuid;
  v_motivo_anterior_id uuid;
  v_motivo_os_id uuid;
  v_rateio_anterior_id uuid;
  v_resultado jsonb;
begin
  select ne.*
    into strict v_nf
  from public.nf_entrada ne
  where ne.tenant_id = v_tenant_id
    and ne.empresa_id = v_empresa_id
    and ne.chave = v_chave
    and ne.numero = '63964'
    and ne.serie = '1'
  for update;

  if v_nf.os_id is null then
    raise exception
      'NF 63964/1 sem vinculo de OS; correcao financeira cancelada.';
  end if;

  if not exists (
    select 1
    from public.ordens_servico os
    where os.tenant_id = v_tenant_id
      and os.empresa_id = v_empresa_id
      and os.id = v_nf.os_id
      and os.os_num = 282
  ) then
    raise exception
      'A OS vinculada a NF 63964/1 nao corresponde a OS 282.';
  end if;

  select mc.id
    into strict v_motivo_anterior_id
  from f.motivo_compra mc
  where mc.tenant_id = v_tenant_id
    and mc.codigo = 'EST_MATERIA_PRIMA'
    and mc.ativo
    and mc.deleted_at is null;

  select mc.id
    into strict v_motivo_os_id
  from f.motivo_compra mc
  where mc.tenant_id = v_tenant_id
    and mc.codigo = 'OS_MATERIAL_DIRETO'
    and mc.ativo
    and mc.deleted_at is null;

  if not exists (
    select 1
    from f.regra_rateio rr
    join f.regra_rateio_item rri
      on rri.tenant_id = rr.tenant_id
     and rri.regra_rateio_id = rr.id
     and rri.deleted_at is null
    join f.motivo_compra mc
      on mc.tenant_id = rr.tenant_id
     and mc.id = rr.motivo_compra_id
    join f.centro_custo cc
      on cc.tenant_id = rr.tenant_id
     and cc.empresa_id = rr.empresa_id
     and cc.id = rri.centro_custo_id
     and cc.ativo
     and cc.deleted_at is null
    where rr.tenant_id = v_tenant_id
      and rr.empresa_id = v_empresa_id
      and rr.motivo_compra_id = v_motivo_os_id
      and rr.ativo
      and rr.deleted_at is null
      and mc.plano_contas_id = rri.plano_contas_id
      and cc.codigo = 'PRODUCAO'
      and abs(rri.percentual - 100.0000) <= 0.0001
  ) then
    raise exception
      'Regra OS_MATERIAL_DIRETO -> PRODUCAO nao esta configurada.';
  end if;

  select t.id
    into strict v_titulo_id
  from f.documento_fiscal df
  join f.titulo t
    on t.tenant_id = df.tenant_id
   and t.empresa_id = df.empresa_id
   and t.documento_fiscal_id = df.id
   and t.tipo = 'AP'
   and t.deleted_at is null
  where df.tenant_id = v_tenant_id
    and df.empresa_id = v_empresa_id
    and df.source_nf_entrada_id = v_nf.id
    and df.deleted_at is null;

  if not exists (
    select 1
    from f.titulo t
    where t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
      and t.id = v_titulo_id
      and t.valor_total = 19086.12
      and t.status <> 'CANCELADO'
  ) then
    raise exception
      'Titulo da NF 63964/1 divergiu do valor/status esperado.';
  end if;

  select tr.id
    into strict v_rateio_anterior_id
  from f.titulo_rateio tr
  where tr.tenant_id = v_tenant_id
    and tr.titulo_id = v_titulo_id
    and tr.plano_contas_id = (
      select mc.plano_contas_id
      from f.motivo_compra mc
      where mc.id = v_motivo_anterior_id
        and mc.tenant_id = v_tenant_id
    )
    and tr.centro_custo_id is null
    and tr.percentual = 100.0000
    and tr.valor = 19086.12
    and tr.deleted_at is null;

  update public.nf_entrada ne
  set motivo_compra_id = v_motivo_os_id
  where ne.tenant_id = v_tenant_id
    and ne.empresa_id = v_empresa_id
    and ne.id = v_nf.id;

  update f.titulo_aprovacao ta
  set
    motivo_compra_id = v_motivo_os_id,
    os_id = v_nf.os_id,
    change_reason =
      'NF 63964/1 importada diretamente para a OS 282: material direto de OS.',
    updated_at = now()
  where ta.tenant_id = v_tenant_id
    and ta.titulo_id = v_titulo_id
    and ta.deleted_at is null;

  if not found then
    raise exception
      'Aprovacao financeira da NF 63964/1 nao encontrada.';
  end if;

  update f.titulo t
  set
    motivo_compra_id = v_motivo_os_id,
    updated_at = now()
  where t.tenant_id = v_tenant_id
    and t.empresa_id = v_empresa_id
    and t.id = v_titulo_id;

  -- Preserva a linha anterior no historico antes de aplicar a regra vigente.
  update f.titulo_rateio tr
  set
    deleted_at = now(),
    updated_at = now()
  where tr.tenant_id = v_tenant_id
    and tr.titulo_id = v_titulo_id
    and tr.id = v_rateio_anterior_id
    and tr.deleted_at is null;

  v_resultado := f.aplicar_regra_rateio_titulo(
    v_tenant_id,
    v_titulo_id,
    true
  );

  if coalesce(v_resultado ->> 'status', '') <> 'APLICADO' then
    raise exception
      'Falha ao aplicar rateio de material direto da OS: %',
      v_resultado;
  end if;
end;
$corrigir_nf_63964$;
