begin;

select pg_advisory_xact_lock(
  hashtextextended(
    'SEG|AP|LEGADO_IMPLANTACAO|2026-03-01',
    0
  )
);

create temporary table _legado_ap_alvos (
  titulo_id uuid primary key,
  status text not null,
  origem text,
  valor_total numeric(15,2) not null,
  valor_aberto numeric(15,2) not null,
  parcelas_abertas integer not null,
  valor_parcelas_abertas numeric(15,2) not null,
  menor_vencimento date not null,
  maior_vencimento date not null
) on commit drop;

insert into _legado_ap_alvos (
  titulo_id,
  status,
  origem,
  valor_total,
  valor_aberto,
  parcelas_abertas,
  valor_parcelas_abertas,
  menor_vencimento,
  maior_vencimento
)
select
  t.id,
  t.status,
  t.origem,
  t.valor_total,
  t.valor_aberto,
  count(tp.id)::integer,
  sum(tp.valor_aberto)::numeric(15,2),
  min(tp.vencimento_date),
  max(tp.vencimento_date)
from f.titulo t
join f.titulo_parcela tp
  on tp.tenant_id = t.tenant_id
 and tp.titulo_id = t.id
 and tp.deleted_at is null
 and tp.valor_aberto > 0
where t.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
  and t.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
  and t.tipo = 'AP'
  and t.status in ('PENDENTE', 'APROVADO', 'AGENDADO')
  and t.deleted_at is null
  and t.valor_aberto > 0
  and not f.titulo_eh_legado_implantacao(
    t.tenant_id,
    t.empresa_id,
    t.id
  )
  and not exists (
    select 1
    from f.titulo_parcela tp_futura
    where tp_futura.tenant_id = t.tenant_id
      and tp_futura.titulo_id = t.id
      and tp_futura.deleted_at is null
      and tp_futura.valor_aberto > 0
      and tp_futura.vencimento_date >= date '2026-03-01'
  )
  and not exists (
    select 1
    from f.titulo_parcela tp_pag
    join f.pagamento_item pi
      on pi.tenant_id = t.tenant_id
     and pi.empresa_id = t.empresa_id
     and pi.titulo_parcela_id = tp_pag.id
     and pi.deleted_at is null
    join f.pagamento p
      on p.tenant_id = t.tenant_id
     and p.empresa_id = t.empresa_id
     and p.id = pi.pagamento_id
     and p.deleted_at is null
    where tp_pag.tenant_id = t.tenant_id
      and tp_pag.titulo_id = t.id
  )
group by t.id;

do $validation$
declare
  v_titulos integer;
  v_parcelas integer;
  v_valor_aberto numeric(15,2);
  v_valor_parcelas numeric(15,2);
  v_hash text;
begin
  select
    count(*)::integer,
    coalesce(sum(a.parcelas_abertas), 0)::integer,
    coalesce(sum(a.valor_aberto), 0)::numeric(15,2),
    coalesce(sum(a.valor_parcelas_abertas), 0)::numeric(15,2),
    md5(string_agg(a.titulo_id::text, ',' order by a.titulo_id::text))
  into
    v_titulos,
    v_parcelas,
    v_valor_aberto,
    v_valor_parcelas,
    v_hash
  from _legado_ap_alvos a;

  if v_titulos <> 66
     or v_parcelas <> 66
     or v_valor_aberto <> 181234.37
     or v_valor_parcelas <> 181234.37
     or v_hash <> '0d9dab87f9979321ab4a5ab8d6274f5b' then
    raise exception using
      errcode = 'P0001',
      message = format(
        'Lote de legado divergiu da previa: titulos=%s parcelas=%s valor_aberto=%s valor_parcelas=%s hash=%s',
        v_titulos,
        v_parcelas,
        v_valor_aberto,
        v_valor_parcelas,
        coalesce(v_hash, 'NULL')
      );
  end if;

  if exists (
    select 1
    from _legado_ap_alvos a
    where a.menor_vencimento >= date '2026-03-01'
       or a.maior_vencimento >= date '2026-03-01'
       or a.parcelas_abertas <> 1
  ) then
    raise exception
      'Lote contem titulo com vencimento fora do corte ou mais de uma parcela';
  end if;
end;
$validation$;

-- Bloqueia os registros depois da conferencia e repete os invariantes mais
-- sensiveis para impedir mudanca concorrente entre a previa e a marcacao.
do $locks$
begin
  perform 1
  from f.titulo t
  join _legado_ap_alvos a on a.titulo_id = t.id
  order by t.id
  for update of t;

  perform 1
  from f.titulo_parcela tp
  join _legado_ap_alvos a on a.titulo_id = tp.titulo_id
  where tp.deleted_at is null
  order by tp.id
  for update of tp;
end;
$locks$;

do $concurrency_check$
begin
  if exists (
    select 1
    from _legado_ap_alvos a
    join f.titulo t on t.id = a.titulo_id
    where t.tenant_id is distinct from
        '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
       or t.empresa_id is distinct from
        'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
       or t.tipo <> 'AP'
       or t.status not in ('PENDENTE', 'APROVADO', 'AGENDADO')
       or t.deleted_at is not null
       or t.valor_aberto is distinct from a.valor_aberto
  ) then
    raise exception 'Um ou mais titulos mudaram durante a marcacao';
  end if;

  if exists (
    select 1
    from _legado_ap_alvos a
    join f.titulo_parcela tp on tp.titulo_id = a.titulo_id
    where tp.deleted_at is null
      and tp.valor_aberto > 0
      and tp.vencimento_date >= date '2026-03-01'
  ) then
    raise exception 'Uma parcela futura surgiu durante a marcacao';
  end if;

  if exists (
    select 1
    from _legado_ap_alvos a
    join f.titulo_parcela tp on tp.titulo_id = a.titulo_id
    join f.pagamento_item pi
      on pi.tenant_id = tp.tenant_id
     and pi.titulo_parcela_id = tp.id
     and pi.deleted_at is null
    join f.pagamento p
      on p.id = pi.pagamento_id
     and p.tenant_id = pi.tenant_id
     and p.empresa_id = pi.empresa_id
     and p.deleted_at is null
  ) then
    raise exception 'Um pagamento surgiu durante a marcacao';
  end if;
end;
$concurrency_check$;

with marcados as (
  insert into f.titulo_legado_implantacao (
    tenant_id,
    empresa_id,
    titulo_id,
    corte_date,
    motivo,
    origem_marcacao,
    status_titulo_snapshot,
    origem_titulo_snapshot,
    valor_total_snapshot,
    valor_aberto_snapshot,
    parcelas_abertas_snapshot,
    valor_parcelas_abertas_snapshot,
    menor_vencimento_snapshot,
    maior_vencimento_snapshot,
    metadata
  )
  select
    '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid,
    'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid,
    a.titulo_id,
    date '2026-03-01',
    'Saldo anterior ao inicio de confiabilidade do AP; regularizacao da implantacao sem pagamento, cancelamento ou efeito no resultado.',
    'AUTOMATICA_CARGA_INICIAL',
    a.status,
    a.origem,
    a.valor_total,
    a.valor_aberto,
    a.parcelas_abertas,
    a.valor_parcelas_abertas,
    a.menor_vencimento,
    a.maior_vencimento,
    jsonb_build_object(
      'lote', 'AP_PRE_MARCO_2026_SEG',
      'migration', '20260724103000',
      'impactaResultado', false,
      'impactaCaixa', false,
      'impactaIndicadoresOperacionais', true,
      'criterio',
        'todas_as_parcelas_abertas_antes_do_corte_sem_pagamento_vinculado'
    )
  from _legado_ap_alvos a
  returning *
)
insert into f.evento_financeiro (
  tenant_id,
  empresa_id,
  evento,
  ref_table,
  ref_id,
  payload
)
select
  m.tenant_id,
  m.empresa_id,
  'TITULO_AP_LEGADO_IMPLANTACAO_MARCADO',
  'f.titulo',
  m.titulo_id,
  jsonb_build_object(
    'marcacaoId', m.id,
    'lote', 'AP_PRE_MARCO_2026_SEG',
    'migration', '20260724103000',
    'corte', m.corte_date,
    'motivo', m.motivo,
    'statusTitulo', m.status_titulo_snapshot,
    'valorTotal', m.valor_total_snapshot,
    'valorAberto', m.valor_aberto_snapshot,
    'parcelasAbertas', m.parcelas_abertas_snapshot,
    'valorParcelasAbertas', m.valor_parcelas_abertas_snapshot,
    'menorVencimento', m.menor_vencimento_snapshot,
    'maiorVencimento', m.maior_vencimento_snapshot,
    'gerouPagamento', false,
    'alterouResultado', false
  )
from marcados m;

do $postcondition$
declare
  v_marcados integer;
  v_valor numeric(15,2);
begin
  select
    count(*)::integer,
    coalesce(sum(li.valor_aberto_snapshot), 0)::numeric(15,2)
  into v_marcados, v_valor
  from f.titulo_legado_implantacao li
  where li.tenant_id =
      '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
    and li.empresa_id =
      'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
    and li.desmarcado_em is null
    and li.metadata ->> 'lote' = 'AP_PRE_MARCO_2026_SEG';

  if v_marcados <> 66 or v_valor <> 181234.37 then
    raise exception
      'Pos-condicao do legado falhou: marcados=% valor=%',
      v_marcados,
      v_valor;
  end if;

  if exists (
    select 1
    from f.titulo_legado_implantacao li
    join f.titulo t on t.id = li.titulo_id
    where li.tenant_id =
        '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
      and li.empresa_id =
        'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
      and li.desmarcado_em is null
      and li.metadata ->> 'lote' = 'AP_PRE_MARCO_2026_SEG'
      and (
        t.valor_total is distinct from li.valor_total_snapshot
        or t.valor_aberto is distinct from li.valor_aberto_snapshot
        or t.status is distinct from li.status_titulo_snapshot
      )
  ) then
    raise exception
      'A marcacao alterou indevidamente titulo, saldo ou status';
  end if;
end;
$postcondition$;

select pg_notify('pgrst', 'reload schema');

commit;
