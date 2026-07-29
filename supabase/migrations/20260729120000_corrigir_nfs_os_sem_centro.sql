-- Corrige as demais inconsistencias de julho com o mesmo padrao da NF
-- 63964/1: importacao direta e integral para uma OS, mas classificacao
-- financeira herdada como EST_MATERIA_PRIMA e rateio unico sem centro.
--
-- Escopo deliberadamente fechado nas tres NFs confirmadas por:
-- - tenant e empresa;
-- - chave da NF-e;
-- - titulo AP;
-- - OS e numero da OS;
-- - valor do titulo;
-- - item integralmente baixado para a mesma OS.

do $corrigir_nfs_os_sem_centro$
declare
  v_tenant_id constant uuid :=
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid;
  v_empresa_id constant uuid :=
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid;
  v_caso record;
  v_nf public.nf_entrada%rowtype;
  v_motivo_anterior_id uuid;
  v_motivo_os_id uuid;
  v_titulo_id uuid;
  v_rateio_anterior_id uuid;
  v_item_count integer;
  v_resultado jsonb;
begin
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

  for v_caso in
    select *
    from (
      values
        (
          '42260714309992000148550010044417651605574686'::text,
          '4441765'::text,
          '1'::text,
          274::integer,
          1791.93::numeric,
          'b86e29c0-984f-4d3c-8c03-244e3be3cc4a'::uuid
        ),
        (
          '42260707175725001050550010040384561578102278'::text,
          '4038456'::text,
          '1'::text,
          229::integer,
          1425.56::numeric,
          'd86a1613-2c67-40c0-bc03-bdc07070d963'::uuid
        ),
        (
          '42260714309992000148550010044436001927438160'::text,
          '4443600'::text,
          '1'::text,
          281::integer,
          3447.06::numeric,
          'b009ef7f-0eac-4aca-8872-16c8cf586867'::uuid
        )
    ) as casos(
      chave,
      numero,
      serie,
      os_numero,
      valor_total,
      titulo_id
    )
  loop
    select ne.*
      into strict v_nf
    from public.nf_entrada ne
    where ne.tenant_id = v_tenant_id
      and ne.empresa_id = v_empresa_id
      and ne.chave = v_caso.chave
      and ne.numero = v_caso.numero
      and ne.serie = v_caso.serie
      and ne.valor_total = v_caso.valor_total
      and ne.finalidade_contexto = 'materia_prima'
      and ne.motivo_compra_id = v_motivo_anterior_id
    for update;

    if v_nf.os_id is null
       or not exists (
         select 1
         from public.ordens_servico os
         where os.tenant_id = v_tenant_id
           and os.empresa_id = v_empresa_id
           and os.id = v_nf.os_id
           and os.os_num = v_caso.os_numero
       )
    then
      raise exception
        'NF %/% sem o vinculo esperado com a OS %.',
        v_caso.numero,
        v_caso.serie,
        v_caso.os_numero;
    end if;

    select count(*)::integer
      into v_item_count
    from public.nf_entrada_itens nei
    where nei.tenant_id = v_tenant_id
      and nei.empresa_id = v_empresa_id
      and nei.nf_entrada_id = v_nf.id;

    if v_item_count <> 1 then
      raise exception
        'NF %/% deixou de possuir exatamente um item.',
        v_caso.numero,
        v_caso.serie;
    end if;

    if not exists (
      select 1
      from public.nf_entrada_itens nei
      join public.movimentacoes mov
        on mov.tenant_id = nei.tenant_id
       and mov.empresa_id = nei.empresa_id
       and mov.origem_nf_entrada_id = nei.nf_entrada_id
       and mov.origem_os_id = v_nf.os_id
       and mov.item_id = nei.item_id
       and lower(mov.tipo) = 'saida'
       and abs(mov.quantidade - nei.qtd) <= 0.000001
      where nei.tenant_id = v_tenant_id
        and nei.empresa_id = v_empresa_id
        and nei.nf_entrada_id = v_nf.id
    ) then
      raise exception
        'NF %/% nao possui baixa integral do item para a OS %.',
        v_caso.numero,
        v_caso.serie,
        v_caso.os_numero;
    end if;

    if exists (
      select 1
      from public.movimentacoes mov
      where mov.tenant_id = v_tenant_id
        and mov.empresa_id = v_empresa_id
        and mov.origem_nf_entrada_id = v_nf.id
        and mov.origem_os_id is not null
        and mov.origem_os_id <> v_nf.os_id
    ) then
      raise exception
        'NF %/% possui movimentacao para outra OS.',
        v_caso.numero,
        v_caso.serie;
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

    if v_titulo_id <> v_caso.titulo_id
       or not exists (
         select 1
         from f.titulo t
         where t.tenant_id = v_tenant_id
           and t.empresa_id = v_empresa_id
           and t.id = v_titulo_id
           and t.valor_total = v_caso.valor_total
           and t.status <> 'CANCELADO'
       )
    then
      raise exception
        'Titulo da NF %/% divergiu do caso validado.',
        v_caso.numero,
        v_caso.serie;
    end if;

    select tr.id
      into strict v_rateio_anterior_id
    from f.titulo_rateio tr
    where tr.tenant_id = v_tenant_id
      and tr.titulo_id = v_titulo_id
      and tr.plano_contas_id = (
        select mc.plano_contas_id
        from f.motivo_compra mc
        where mc.tenant_id = v_tenant_id
          and mc.id = v_motivo_anterior_id
      )
      and tr.centro_custo_id is null
      and tr.percentual = 100.0000
      and tr.valor = v_caso.valor_total
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
      change_reason = format(
        'NF %s/%s importada integralmente para a OS %s: material direto de OS.',
        v_caso.numero,
        v_caso.serie,
        v_caso.os_numero
      ),
      updated_at = now()
    where ta.tenant_id = v_tenant_id
      and ta.titulo_id = v_titulo_id
      and ta.deleted_at is null;

    if not found then
      raise exception
        'Aprovacao financeira da NF %/% nao encontrada.',
        v_caso.numero,
        v_caso.serie;
    end if;

    update f.titulo t
    set
      motivo_compra_id = v_motivo_os_id,
      updated_at = now()
    where t.tenant_id = v_tenant_id
      and t.empresa_id = v_empresa_id
      and t.id = v_titulo_id;

    -- Preserva o rateio anterior no historico antes de aplicar a regra atual.
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
        'Falha ao aplicar rateio da NF %/%: %',
        v_caso.numero,
        v_caso.serie,
        v_resultado;
    end if;
  end loop;
end;
$corrigir_nfs_os_sem_centro$;
