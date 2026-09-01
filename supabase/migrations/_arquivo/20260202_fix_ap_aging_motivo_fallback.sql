-- Fix: show motivo_compra for AP parcels even when titulo is not yet approved.

do $$
begin
  if to_regclass('f.titulo') is not null
    and to_regclass('f.titulo_parcela') is not null then
    execute $v$
      create or replace view f.r_ap_aging_detalhe as
      select
        t.tenant_id,
        t.empresa_id,
        t.id as titulo_id,
        tp.id as parcela_id,
        tp.numero as parcela_numero,
        t.fornecedor_id,
        coalesce(forn.nome, 'SEM FORNECEDOR') as fornecedor_nome,
        coalesce(mc.codigo, 'NAO_CLASSIFICADO') as motivo_codigo,
        coalesce(mc.nome, 'NAO CLASSIFICADO') as motivo_nome,
        tp.vencimento_date,
        (current_date - tp.vencimento_date) as dias_atraso,
        tp.valor as valor_parcela,
        tp.valor_aberto,
        t.status,
        t.emissao_date,
        t.competencia_date
      from f.titulo_parcela tp
      join f.titulo t on t.id = tp.titulo_id
      left join f.titulo_aprovacao ta
        on ta.tenant_id = t.tenant_id
       and ta.titulo_id = t.id
       and ta.deleted_at is null
      left join f.motivo_compra mc
        on mc.id = coalesce(ta.motivo_compra_id, t.motivo_compra_id)
       and mc.deleted_at is null
      left join public.fornecedores forn on forn.id = t.fornecedor_id
      where tp.deleted_at is null
        and t.deleted_at is null
        and t.tipo = 'AP'
        and tp.valor_aberto > 0
    $v$;

    execute $v$
      create or replace view f.r_ap_aging_resumo as
      with base as (
        select
          t.tenant_id,
          t.empresa_id,
          t.fornecedor_id,
          coalesce(forn.nome, 'SEM FORNECEDOR') as fornecedor_nome,
          coalesce(mc.codigo, 'NAO_CLASSIFICADO') as motivo_codigo,
          coalesce(mc.nome, 'NAO CLASSIFICADO') as motivo_nome,
          tp.vencimento_date,
          tp.valor_aberto,
          (current_date - tp.vencimento_date) as dias_atraso
        from f.titulo_parcela tp
        join f.titulo t on t.id = tp.titulo_id
        left join f.titulo_aprovacao ta
          on ta.tenant_id = t.tenant_id
         and ta.titulo_id = t.id
         and ta.deleted_at is null
        left join f.motivo_compra mc
          on mc.id = coalesce(ta.motivo_compra_id, t.motivo_compra_id)
         and mc.deleted_at is null
        left join public.fornecedores forn on forn.id = t.fornecedor_id
        where tp.deleted_at is null
          and t.deleted_at is null
          and t.tipo = 'AP'
          and tp.valor_aberto > 0
      )
      select
        tenant_id,
        empresa_id,
        fornecedor_id,
        fornecedor_nome,
        motivo_codigo,
        motivo_nome,
        sum(case when vencimento_date > current_date then valor_aberto else 0 end)::numeric(15,2) as a_vencer,
        sum(case when dias_atraso between 0 and 30 then valor_aberto else 0 end)::numeric(15,2) as vencido_0_30,
        sum(case when dias_atraso between 31 and 60 then valor_aberto else 0 end)::numeric(15,2) as vencido_31_60,
        sum(case when dias_atraso between 61 and 90 then valor_aberto else 0 end)::numeric(15,2) as vencido_61_90,
        sum(case when dias_atraso >= 91 then valor_aberto else 0 end)::numeric(15,2) as vencido_90_mais,
        sum(valor_aberto)::numeric(15,2) as total_aberto
      from base
      group by
        tenant_id,
        empresa_id,
        fornecedor_id,
        fornecedor_nome,
        motivo_codigo,
        motivo_nome
    $v$;
  else
    execute $v$
      create or replace view f.r_ap_aging_detalhe as
      select
        null::uuid as tenant_id,
        null::uuid as empresa_id,
        null::uuid as titulo_id,
        null::uuid as parcela_id,
        null::text as parcela_numero,
        null::integer as fornecedor_id,
        null::text as fornecedor_nome,
        null::text as motivo_codigo,
        null::text as motivo_nome,
        null::date as vencimento_date,
        null::integer as dias_atraso,
        null::numeric(15,2) as valor_parcela,
        null::numeric(15,2) as valor_aberto,
        null::text as status,
        null::date as emissao_date,
        null::date as competencia_date
      where false
    $v$;

    execute $v$
      create or replace view f.r_ap_aging_resumo as
      select
        null::uuid as tenant_id,
        null::uuid as empresa_id,
        null::integer as fornecedor_id,
        null::text as fornecedor_nome,
        null::text as motivo_codigo,
        null::text as motivo_nome,
        null::numeric(15,2) as a_vencer,
        null::numeric(15,2) as vencido_0_30,
        null::numeric(15,2) as vencido_31_60,
        null::numeric(15,2) as vencido_61_90,
        null::numeric(15,2) as vencido_90_mais,
        null::numeric(15,2) as total_aberto
      where false
    $v$;
  end if;
end$$;
