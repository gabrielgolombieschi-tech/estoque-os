begin;

alter table f.fin_config
  add column if not exists data_inicio_confiabilidade_ap date;

comment on column f.fin_config.data_inicio_confiabilidade_ap is
  'Primeira data em que o saldo operacional de contas a pagar e considerado confiavel.';

create table if not exists f.titulo_legado_implantacao (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  titulo_id uuid not null,
  corte_date date not null,
  motivo text not null,
  origem_marcacao text not null default 'MANUAL',
  status_titulo_snapshot text not null,
  origem_titulo_snapshot text,
  valor_total_snapshot numeric(15,2) not null default 0,
  valor_aberto_snapshot numeric(15,2) not null default 0,
  parcelas_abertas_snapshot integer not null default 0,
  valor_parcelas_abertas_snapshot numeric(15,2) not null default 0,
  menor_vencimento_snapshot date,
  maior_vencimento_snapshot date,
  marcado_em timestamptz not null default now(),
  marcado_por uuid default a.fn_current_usuario_id(),
  desmarcado_em timestamptz,
  desmarcado_por uuid,
  motivo_desmarcacao text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fk_titulo_legado_implantacao_titulo
    foreign key (titulo_id) references f.titulo(id),
  constraint fk_titulo_legado_implantacao_empresa
    foreign key (empresa_id) references c.empresa(id),
  constraint ck_titulo_legado_implantacao_motivo
    check (length(btrim(motivo)) >= 10),
  constraint ck_titulo_legado_implantacao_origem
    check (origem_marcacao in ('AUTOMATICA_CARGA_INICIAL', 'MANUAL', 'MIGRACAO')),
  constraint ck_titulo_legado_implantacao_desmarcacao
    check (
      (desmarcado_em is null and motivo_desmarcacao is null)
      or
      (desmarcado_em is not null and length(btrim(motivo_desmarcacao)) >= 10)
    )
);

comment on table f.titulo_legado_implantacao is
  'Marcacao auditavel de AP cujo saldo aberto veio da implantacao. Nao cria pagamento, nao cancela o titulo e nao altera resultado ou caixa.';

create unique index if not exists uq_titulo_legado_implantacao_ativo
  on f.titulo_legado_implantacao (tenant_id, empresa_id, titulo_id)
  where desmarcado_em is null;

create index if not exists idx_titulo_legado_implantacao_escopo
  on f.titulo_legado_implantacao (tenant_id, empresa_id, corte_date)
  where desmarcado_em is null;

alter table f.titulo_legado_implantacao enable row level security;

drop policy if exists titulo_legado_implantacao_select
  on f.titulo_legado_implantacao;

create policy titulo_legado_implantacao_select
  on f.titulo_legado_implantacao
  for select
  to authenticated
  using (
    tenant_id = public.current_tenant_id()
    and empresa_id = public.current_empresa_id()
    and f.has_finance_access(tenant_id, empresa_id)
  );

revoke all on table f.titulo_legado_implantacao from public;
revoke all on table f.titulo_legado_implantacao from anon;
grant select on table f.titulo_legado_implantacao to authenticated;
grant select on table f.titulo_legado_implantacao to service_role;

create or replace function f.titulo_eh_legado_implantacao(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_titulo_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'f'
set row_security to 'off'
as $$
  select exists (
    select 1
    from f.titulo_legado_implantacao li
    where li.tenant_id = p_tenant_id
      and li.empresa_id = p_empresa_id
      and li.titulo_id = p_titulo_id
      and li.desmarcado_em is null
  );
$$;

revoke all on function f.titulo_eh_legado_implantacao(uuid, uuid, uuid)
  from public;
revoke all on function f.titulo_eh_legado_implantacao(uuid, uuid, uuid)
  from anon;
revoke all on function f.titulo_eh_legado_implantacao(uuid, uuid, uuid)
  from authenticated;

create or replace function f.resumo_legado_implantacao_ap(
  p_tenant_id uuid,
  p_empresa_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'f'
set row_security to 'off'
as $$
  select jsonb_build_object(
    'tituloQtd', count(*),
    'parcelaQtd', coalesce(sum(li.parcelas_abertas_snapshot), 0),
    'valorAberto', round(coalesce(sum(li.valor_aberto_snapshot), 0), 2),
    'valorParcelasAberto',
      round(coalesce(sum(li.valor_parcelas_abertas_snapshot), 0), 2),
    'corte', max(li.corte_date),
    'marcadoEm', max(li.marcado_em)
  )
  from f.titulo_legado_implantacao li
  where li.tenant_id = p_tenant_id
    and li.empresa_id = p_empresa_id
    and li.desmarcado_em is null;
$$;

revoke all on function f.resumo_legado_implantacao_ap(uuid, uuid)
  from public;
revoke all on function f.resumo_legado_implantacao_ap(uuid, uuid)
  from anon;
revoke all on function f.resumo_legado_implantacao_ap(uuid, uuid)
  from authenticated;

create or replace function f.preview_legado_implantacao_ap(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_corte_date date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_corte date;
  v_result jsonb;
begin
  if p_tenant_id is null or p_empresa_id is null then
    raise exception using
      errcode = '22023',
      message = 'tenant_id e empresa_id sao obrigatorios';
  end if;

  if auth.uid() is null and coalesce(auth.role(), '') <> 'service_role' then
    raise exception using
      errcode = '42501',
      message = 'Usuario nao autenticado';
  end if;

  if auth.uid() is not null then
    if public.current_tenant_id() is distinct from p_tenant_id
       or public.current_empresa_id() is distinct from p_empresa_id
       or not f.has_finance_access(p_tenant_id, p_empresa_id) then
      raise exception using
        errcode = '42501',
        message = 'Sem permissao para o escopo informado';
    end if;
  end if;

  select coalesce(p_corte_date, cfg.data_inicio_confiabilidade_ap)
  into v_corte
  from f.fin_config cfg
  where cfg.tenant_id = p_tenant_id
    and cfg.empresa_id = p_empresa_id
    and cfg.deleted_at is null
  limit 1;

  v_corte := coalesce(v_corte, p_corte_date);
  if v_corte is null then
    raise exception using
      errcode = '22023',
      message = 'Data de corte de AP nao configurada';
  end if;

  with
  titulos_base as (
    select
      t.id,
      t.status,
      t.origem,
      t.descricao,
      t.valor_total,
      t.valor_aberto,
      t.emissao_date,
      t.competencia_date,
      t.created_at,
      count(tp.id) filter (where tp.valor_aberto > 0) as parcelas_abertas,
      coalesce(sum(tp.valor_aberto) filter (where tp.valor_aberto > 0), 0)
        as valor_parcelas_abertas,
      min(tp.vencimento_date) filter (where tp.valor_aberto > 0)
        as menor_vencimento,
      max(tp.vencimento_date) filter (where tp.valor_aberto > 0)
        as maior_vencimento,
      exists (
        select 1
        from f.titulo_parcela tp_pag
        join f.pagamento_item pi
          on pi.tenant_id = p_tenant_id
         and pi.empresa_id = p_empresa_id
         and pi.titulo_parcela_id = tp_pag.id
         and pi.deleted_at is null
        join f.pagamento pag
          on pag.tenant_id = p_tenant_id
         and pag.empresa_id = p_empresa_id
         and pag.id = pi.pagamento_id
         and pag.deleted_at is null
        where tp_pag.tenant_id = p_tenant_id
          and tp_pag.titulo_id = t.id
      ) as tem_pagamento,
      f.titulo_eh_legado_implantacao(
        p_tenant_id,
        p_empresa_id,
        t.id
      ) as ja_marcado
    from f.titulo t
    left join f.titulo_parcela tp
      on tp.tenant_id = p_tenant_id
     and tp.titulo_id = t.id
     and tp.deleted_at is null
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.tipo = 'AP'
      and t.status in ('PENDENTE', 'APROVADO', 'AGENDADO')
      and t.deleted_at is null
      and t.valor_aberto > 0
    group by t.id
  ),
  candidatos as (
    select *
    from titulos_base tb
    where tb.parcelas_abertas > 0
      and tb.maior_vencimento < v_corte
      and not tb.tem_pagamento
      and not tb.ja_marcado
  ),
  por_origem as (
    select jsonb_agg(
      jsonb_build_object(
        'origem', x.origem,
        'tituloQtd', x.titulo_qtd,
        'parcelaQtd', x.parcela_qtd,
        'valorAberto', round(x.valor_aberto, 2)
      )
      order by x.valor_aberto desc, x.origem
    ) as itens
    from (
      select
        coalesce(c.origem, 'NAO_INFORMADA') as origem,
        count(*) as titulo_qtd,
        sum(c.parcelas_abertas) as parcela_qtd,
        sum(c.valor_aberto) as valor_aberto
      from candidatos c
      group by coalesce(c.origem, 'NAO_INFORMADA')
    ) x
  ),
  amostra as (
    select jsonb_agg(
      jsonb_build_object(
        'tituloId', x.id,
        'status', x.status,
        'origem', x.origem,
        'descricao', x.descricao,
        'valorTotal', round(x.valor_total, 2),
        'valorAberto', round(x.valor_aberto, 2),
        'parcelaQtd', x.parcelas_abertas,
        'menorVencimento', x.menor_vencimento,
        'maiorVencimento', x.maior_vencimento,
        'emissao', x.emissao_date,
        'competencia', x.competencia_date
      )
      order by x.valor_aberto desc, x.id
    ) as itens
    from (
      select *
      from candidatos
      order by valor_aberto desc, id
      limit 100
    ) x
  )
  select jsonb_build_object(
    'corte', v_corte,
    'candidatos', jsonb_build_object(
      'tituloQtd', (select count(*) from candidatos),
      'parcelaQtd',
        coalesce((select sum(c.parcelas_abertas) from candidatos c), 0),
      'valorAberto',
        round(coalesce((select sum(c.valor_aberto) from candidatos c), 0), 2),
      'valorParcelasAberto',
        round(coalesce((
          select sum(c.valor_parcelas_abertas)
          from candidatos c
        ), 0), 2)
    ),
    'excluidos', jsonb_build_object(
      'comParcelaNoCorteOuDepois', (
        select count(*)
        from titulos_base tb
        where tb.parcelas_abertas > 0
          and tb.maior_vencimento >= v_corte
      ),
      'comPagamento', (
        select count(*)
        from titulos_base tb
        where tb.parcelas_abertas > 0
          and tb.maior_vencimento < v_corte
          and tb.tem_pagamento
      ),
      'jaMarcados', (
        select count(*)
        from titulos_base tb
        where tb.ja_marcado
      )
    ),
    'porOrigem', coalesce((select po.itens from por_origem po), '[]'::jsonb),
    'amostra', coalesce((select a.itens from amostra a), '[]'::jsonb)
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function f.preview_legado_implantacao_ap(uuid, uuid, date)
  from public;
revoke all on function f.preview_legado_implantacao_ap(uuid, uuid, date)
  from anon;
grant execute on function f.preview_legado_implantacao_ap(uuid, uuid, date)
  to authenticated;
grant execute on function f.preview_legado_implantacao_ap(uuid, uuid, date)
  to service_role;

create or replace function f.marcar_legado_implantacao_ap(
  p_titulo_id uuid,
  p_corte_date date,
  p_motivo text,
  p_origem_marcacao text default 'MANUAL'
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_titulo f.titulo%rowtype;
  v_existente_id uuid;
  v_actor uuid;
  v_parcelas integer;
  v_valor_parcelas numeric(15,2);
  v_menor_vencimento date;
  v_maior_vencimento date;
  v_marker_id uuid;
begin
  if p_titulo_id is null or p_corte_date is null then
    raise exception using
      errcode = '22023',
      message = 'titulo_id e corte_date sao obrigatorios';
  end if;

  if length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception using
      errcode = '22023',
      message = 'Informe um motivo de marcacao com pelo menos 10 caracteres';
  end if;

  if p_origem_marcacao not in ('AUTOMATICA_CARGA_INICIAL', 'MANUAL', 'MIGRACAO') then
    raise exception using
      errcode = '22023',
      message = 'Origem de marcacao invalida';
  end if;

  if auth.uid() is null and coalesce(auth.role(), '') <> 'service_role' then
    raise exception using
      errcode = '42501',
      message = 'Usuario nao autenticado';
  end if;

  select *
  into v_titulo
  from f.titulo t
  where t.id = p_titulo_id
    and t.deleted_at is null
  for update;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if v_titulo.tipo <> 'AP'
     or v_titulo.status not in ('PENDENTE', 'APROVADO', 'AGENDADO') then
    raise exception 'Somente AP ativo e em aberto pode ser marcado como legado';
  end if;

  if auth.uid() is not null then
    if public.current_tenant_id() is distinct from v_titulo.tenant_id
       or public.current_empresa_id() is distinct from v_titulo.empresa_id
       or not f.has_finance_access(
         v_titulo.tenant_id,
         v_titulo.empresa_id
       ) then
      raise exception using
        errcode = '42501',
        message = 'Sem permissao para o escopo do titulo';
    end if;
  end if;

  select li.id
  into v_existente_id
  from f.titulo_legado_implantacao li
  where li.tenant_id = v_titulo.tenant_id
    and li.empresa_id = v_titulo.empresa_id
    and li.titulo_id = v_titulo.id
    and li.desmarcado_em is null
  limit 1;

  if v_existente_id is not null then
    return v_existente_id;
  end if;

  select
    count(*),
    coalesce(sum(tp.valor_aberto), 0),
    min(tp.vencimento_date),
    max(tp.vencimento_date)
  into
    v_parcelas,
    v_valor_parcelas,
    v_menor_vencimento,
    v_maior_vencimento
  from f.titulo_parcela tp
  where tp.tenant_id = v_titulo.tenant_id
    and tp.titulo_id = v_titulo.id
    and tp.deleted_at is null
    and tp.valor_aberto > 0;

  if v_parcelas = 0 or v_titulo.valor_aberto <= 0 then
    raise exception 'Titulo nao possui saldo aberto para marcar';
  end if;

  if v_maior_vencimento >= p_corte_date then
    raise exception
      'Titulo possui parcela aberta no corte ou depois dele (maior vencimento=%)',
      v_maior_vencimento;
  end if;

  if exists (
    select 1
    from f.titulo_parcela tp
    join f.pagamento_item pi
      on pi.tenant_id = v_titulo.tenant_id
     and pi.empresa_id = v_titulo.empresa_id
     and pi.titulo_parcela_id = tp.id
     and pi.deleted_at is null
    join f.pagamento p
      on p.tenant_id = v_titulo.tenant_id
     and p.empresa_id = v_titulo.empresa_id
     and p.id = pi.pagamento_id
     and p.deleted_at is null
    where tp.tenant_id = v_titulo.tenant_id
      and tp.titulo_id = v_titulo.id
  ) then
    raise exception
      'Titulo possui pagamento aplicado e exige conciliacao individual';
  end if;

  v_actor := a.fn_current_usuario_id();

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
    marcado_por,
    metadata
  )
  values (
    v_titulo.tenant_id,
    v_titulo.empresa_id,
    v_titulo.id,
    p_corte_date,
    btrim(p_motivo),
    p_origem_marcacao,
    v_titulo.status,
    v_titulo.origem,
    v_titulo.valor_total,
    v_titulo.valor_aberto,
    v_parcelas,
    v_valor_parcelas,
    v_menor_vencimento,
    v_maior_vencimento,
    v_actor,
    jsonb_build_object(
      'impactaResultado', false,
      'impactaCaixa', false,
      'impactaIndicadoresOperacionais', true
    )
  )
  returning id into v_marker_id;

  insert into f.evento_financeiro (
    tenant_id,
    empresa_id,
    evento,
    ref_table,
    ref_id,
    payload,
    created_by
  )
  values (
    v_titulo.tenant_id,
    v_titulo.empresa_id,
    'TITULO_AP_LEGADO_IMPLANTACAO_MARCADO',
    'f.titulo',
    v_titulo.id,
    jsonb_build_object(
      'marcacaoId', v_marker_id,
      'corte', p_corte_date,
      'motivo', btrim(p_motivo),
      'origemMarcacao', p_origem_marcacao,
      'statusTitulo', v_titulo.status,
      'valorTotal', v_titulo.valor_total,
      'valorAberto', v_titulo.valor_aberto,
      'parcelasAbertas', v_parcelas,
      'valorParcelasAbertas', v_valor_parcelas,
      'menorVencimento', v_menor_vencimento,
      'maiorVencimento', v_maior_vencimento,
      'gerouPagamento', false,
      'alterouResultado', false
    ),
    v_actor
  );

  return v_marker_id;
end;
$$;

revoke all on function f.marcar_legado_implantacao_ap(uuid, date, text, text)
  from public;
revoke all on function f.marcar_legado_implantacao_ap(uuid, date, text, text)
  from anon;
grant execute on function f.marcar_legado_implantacao_ap(uuid, date, text, text)
  to authenticated;
grant execute on function f.marcar_legado_implantacao_ap(uuid, date, text, text)
  to service_role;

create or replace function f.desmarcar_legado_implantacao_ap(
  p_titulo_id uuid,
  p_motivo text
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_titulo f.titulo%rowtype;
  v_marcacao f.titulo_legado_implantacao%rowtype;
  v_actor uuid;
begin
  if length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception using
      errcode = '22023',
      message = 'Informe um motivo de desmarcacao com pelo menos 10 caracteres';
  end if;

  if auth.uid() is null and coalesce(auth.role(), '') <> 'service_role' then
    raise exception using
      errcode = '42501',
      message = 'Usuario nao autenticado';
  end if;

  select *
  into v_titulo
  from f.titulo t
  where t.id = p_titulo_id
    and t.deleted_at is null;

  if not found then
    raise exception 'Titulo nao encontrado (id=%)', p_titulo_id;
  end if;

  if auth.uid() is not null then
    if public.current_tenant_id() is distinct from v_titulo.tenant_id
       or public.current_empresa_id() is distinct from v_titulo.empresa_id
       or not f.has_finance_access(
         v_titulo.tenant_id,
         v_titulo.empresa_id
       ) then
      raise exception using
        errcode = '42501',
        message = 'Sem permissao para o escopo do titulo';
    end if;
  end if;

  select *
  into v_marcacao
  from f.titulo_legado_implantacao li
  where li.tenant_id = v_titulo.tenant_id
    and li.empresa_id = v_titulo.empresa_id
    and li.titulo_id = v_titulo.id
    and li.desmarcado_em is null
  for update;

  if not found then
    raise exception 'Titulo nao possui marcacao ativa de legado';
  end if;

  v_actor := a.fn_current_usuario_id();

  update f.titulo_legado_implantacao
  set
    desmarcado_em = now(),
    desmarcado_por = v_actor,
    motivo_desmarcacao = btrim(p_motivo),
    updated_at = now()
  where id = v_marcacao.id;

  insert into f.evento_financeiro (
    tenant_id,
    empresa_id,
    evento,
    ref_table,
    ref_id,
    payload,
    created_by
  )
  values (
    v_titulo.tenant_id,
    v_titulo.empresa_id,
    'TITULO_AP_LEGADO_IMPLANTACAO_DESMARCADO',
    'f.titulo',
    v_titulo.id,
    jsonb_build_object(
      'marcacaoId', v_marcacao.id,
      'motivo', btrim(p_motivo),
      'gerouPagamento', false,
      'alterouResultado', false
    ),
    v_actor
  );
end;
$$;

revoke all on function f.desmarcar_legado_implantacao_ap(uuid, text)
  from public;
revoke all on function f.desmarcar_legado_implantacao_ap(uuid, text)
  from anon;
grant execute on function f.desmarcar_legado_implantacao_ap(uuid, text)
  to authenticated;
grant execute on function f.desmarcar_legado_implantacao_ap(uuid, text)
  to service_role;

-- O tenant funciona como perimetro do grupo, mas o corte e individual por empresa.
insert into f.fin_config (tenant_id, empresa_id, data_inicio_confiabilidade_ap)
select
  e.tenant_id,
  e.id,
  date '2026-03-01'
from c.empresa e
where e.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
  and e.id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
  and e.deleted_at is null
  and not exists (
    select 1
    from f.fin_config cfg
    where cfg.tenant_id = e.tenant_id
      and cfg.empresa_id = e.id
  );

update f.fin_config cfg
set
  data_inicio_confiabilidade_ap = date '2026-03-01',
  updated_at = now()
where cfg.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
  and cfg.empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
  and cfg.deleted_at is null;

-- Mantem o contrato dos relatorios de aging e faz o detalhe reconciliar com
-- a Saude Financeira. O titulo continua preservado nas tabelas de origem.
create or replace view f.r_ap_aging_detalhe
with (security_invoker = true)
as
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
  current_date - tp.vencimento_date as dias_atraso,
  tp.valor as valor_parcela,
  tp.valor_aberto,
  t.status,
  t.emissao_date,
  t.competencia_date,
  coalesce(
    t.total_parcelas_serie::bigint,
    (
      select count(*)
      from f.titulo_parcela tp2
      where tp2.tenant_id = t.tenant_id
        and tp2.titulo_id = t.id
        and tp2.deleted_at is null
    )
  ) as total_parcelas,
  t.descricao
from f.titulo_parcela tp
join f.titulo t
  on t.tenant_id = tp.tenant_id
 and t.id = tp.titulo_id
left join f.titulo_aprovacao ta
  on ta.tenant_id = t.tenant_id
 and ta.titulo_id = t.id
 and ta.deleted_at is null
left join f.motivo_compra mc
  on mc.tenant_id = t.tenant_id
 and mc.id = coalesce(ta.motivo_compra_id, t.motivo_compra_id)
 and mc.deleted_at is null
left join public.fornecedores forn
  on forn.tenant_id = t.tenant_id
 and forn.empresa_id = t.empresa_id
 and forn.id = t.fornecedor_id
where tp.deleted_at is null
  and t.deleted_at is null
  and t.tipo = 'AP'
  and t.status <> 'CANCELADO'
  and tp.valor_aberto > 0
  and not f.titulo_eh_legado_implantacao(
    t.tenant_id,
    t.empresa_id,
    t.id
  );

create or replace view f.r_ap_aging_resumo
with (security_invoker = true)
as
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
    current_date - tp.vencimento_date as dias_atraso
  from f.titulo_parcela tp
  join f.titulo t
    on t.tenant_id = tp.tenant_id
   and t.id = tp.titulo_id
  left join f.titulo_aprovacao ta
    on ta.tenant_id = t.tenant_id
   and ta.titulo_id = t.id
   and ta.deleted_at is null
  left join f.motivo_compra mc
    on mc.tenant_id = t.tenant_id
   and mc.id = coalesce(ta.motivo_compra_id, t.motivo_compra_id)
   and mc.deleted_at is null
  left join public.fornecedores forn
    on forn.tenant_id = t.tenant_id
   and forn.empresa_id = t.empresa_id
   and forn.id = t.fornecedor_id
  where tp.deleted_at is null
    and t.deleted_at is null
    and t.tipo = 'AP'
    and t.status <> 'CANCELADO'
    and tp.valor_aberto > 0
    and not f.titulo_eh_legado_implantacao(
      t.tenant_id,
      t.empresa_id,
      t.id
    )
)
select
  tenant_id,
  empresa_id,
  fornecedor_id,
  fornecedor_nome,
  motivo_codigo,
  motivo_nome,
  sum(case
    when vencimento_date > current_date then valor_aberto
    else 0
  end)::numeric(15,2) as a_vencer,
  sum(case
    when dias_atraso between 0 and 30 then valor_aberto
    else 0
  end)::numeric(15,2) as vencido_0_30,
  sum(case
    when dias_atraso between 31 and 60 then valor_aberto
    else 0
  end)::numeric(15,2) as vencido_31_60,
  sum(case
    when dias_atraso between 61 and 90 then valor_aberto
    else 0
  end)::numeric(15,2) as vencido_61_90,
  sum(case
    when dias_atraso >= 91 then valor_aberto
    else 0
  end)::numeric(15,2) as vencido_90_mais,
  sum(valor_aberto)::numeric(15,2) as total_aberto
from base
group by
  tenant_id,
  empresa_id,
  fornecedor_id,
  fornecedor_nome,
  motivo_codigo,
  motivo_nome;

grant select on f.r_ap_aging_detalhe to authenticated;
grant select on f.r_ap_aging_resumo to authenticated;

-- A funcao executiva e extensa. Para manter uma migration pequena e
-- rastreavel, partimos da definicao efetivamente instalada e aplicamos quatro
-- insercoes assertivas. A migration aborta se a versao-base nao for a esperada.
do $migration$
declare
  v_definition text;
  v_next text;
begin
  select pg_get_functiondef(
    'f.relatorio_saude_financeira(uuid,uuid,date,date)'::regprocedure
  )
  into v_definition;

  v_next := regexp_replace(
    v_definition,
    $rx$(and t\.status <> 'CANCELADO'[[:space:]]+)(and t\.valor_aberto > 0)$rx$,
    $replacement$\1and not f.titulo_eh_legado_implantacao(
        p_tenant_id,
        p_empresa_id,
        t.id
      )
      \2$replacement$
  );
  if v_next = v_definition then
    raise exception 'Nao foi possivel ajustar titulos_abertos do relatorio';
  end if;
  v_definition := v_next;

  v_next := regexp_replace(
    v_definition,
    $rx$(and t\.status <> 'CANCELADO'[[:space:]]+)(and t\.tipo = 'AP'[[:space:]]+and t\.competencia_date between)$rx$,
    $replacement$\1and not f.titulo_eh_legado_implantacao(
        p_tenant_id,
        p_empresa_id,
        t.id
      )
      \2$replacement$
  );
  if v_next = v_definition then
    raise exception 'Nao foi possivel ajustar ap_periodo do relatorio';
  end if;
  v_definition := v_next;

  v_next := regexp_replace(
    v_definition,
    $rx$(and t\.status <> 'CANCELADO'[[:space:]]+)(and \([[:space:]]+coalesce\(t\.competencia_date)$rx$,
    $replacement$\1and not f.titulo_eh_legado_implantacao(
        p_tenant_id,
        p_empresa_id,
        t.id
      )
      \2$replacement$
  );
  if v_next = v_definition then
    raise exception 'Nao foi possivel ajustar a qualidade do relatorio';
  end if;
  v_definition := v_next;

  v_next := regexp_replace(
    v_definition,
    $rx$(and t\.status <> 'CANCELADO'[[:space:]]+)(and t\.documento_fiscal_id is not null)$rx$,
    $replacement$\1and not f.titulo_eh_legado_implantacao(
        p_tenant_id,
        p_empresa_id,
        t.id
      )
      \2$replacement$
  );
  if v_next = v_definition then
    raise exception 'Nao foi possivel ajustar documentos duplicados do relatorio';
  end if;
  v_definition := v_next;

  v_next := regexp_replace(
    v_definition,
    $rx$([[:space:]]+/\*[[:space:]]+\* Qualidade\.)$rx$,
    $replacement$

  v_compromissos := v_compromissos || jsonb_build_object(
    'legadoExcluido',
    f.resumo_legado_implantacao_ap(p_tenant_id, p_empresa_id)
  );

  /*
   * Qualidade.$replacement$
  );
  if v_next = v_definition then
    raise exception 'Nao foi possivel acrescentar o resumo de legado';
  end if;
  v_definition := v_next;

  execute v_definition;
end;
$migration$;

comment on function f.relatorio_saude_financeira(uuid, uuid, date, date) is
  'Visao gerencial de saude financeira. Resultado e caixa preservam fatos contabilizados; compromissos e qualidade excluem somente AP explicitamente marcado como legado de implantacao.';

grant execute on function f.relatorio_saude_financeira(uuid, uuid, date, date)
  to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
