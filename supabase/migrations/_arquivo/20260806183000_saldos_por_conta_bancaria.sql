-- Posicao bancaria por conta, com saldo auditavel e leitura multiempresa.
-- A posicao confirmada funciona como ancora; pagamentos, recebimentos e
-- transferencias posteriores atualizam o saldo calculado.

alter table f.conta_bancaria
  add column if not exists saldo_referencia numeric(15,2),
  add column if not exists saldo_referencia_data date,
  add column if not exists saldo_referencia_em timestamptz,
  add column if not exists saldo_referencia_motivo text;

comment on column f.conta_bancaria.saldo_referencia is
  'Saldo confirmado da conta na data de referencia.';
comment on column f.conta_bancaria.saldo_referencia_data is
  'Data da posicao bancaria confirmada.';
comment on column f.conta_bancaria.saldo_referencia_em is
  'Instante em que a posicao foi confirmada no sistema.';
comment on column f.conta_bancaria.saldo_referencia_motivo is
  'Justificativa informada para a definicao ou ajuste da posicao bancaria.';

create or replace function f.conta_bancaria_ajustar_saldo(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_conta_bancaria_id uuid,
  p_saldo_atual numeric,
  p_data_referencia date,
  p_motivo text
)
returns void
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_conta f.conta_bancaria%rowtype;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Usuario nao autenticado';
  end if;

  if p_tenant_id is null
     or p_tenant_id is distinct from public.current_tenant_id() then
    raise exception 'Tenant invalido para a sessao atual';
  end if;

  if p_empresa_id is null
     or not f.has_finance_access(p_tenant_id, p_empresa_id) then
    raise exception 'Sem acesso financeiro a empresa solicitada';
  end if;

  if p_saldo_atual is null then
    raise exception 'Informe o saldo atual';
  end if;

  if p_data_referencia is null or p_data_referencia > current_date then
    raise exception 'Data da posicao invalida';
  end if;

  if v_motivo is null or length(v_motivo) < 3 then
    raise exception 'Informe um motivo para o ajuste';
  end if;

  select cb.*
    into v_conta
  from f.conta_bancaria cb
  where cb.id = p_conta_bancaria_id
    and cb.tenant_id = p_tenant_id
    and cb.empresa_id = p_empresa_id
    and cb.deleted_at is null
  for update;

  if not found then
    raise exception 'Conta bancaria nao encontrada para a empresa informada';
  end if;

  update f.conta_bancaria cb
  set saldo_referencia = round(p_saldo_atual, 2),
      saldo_referencia_data = p_data_referencia,
      saldo_referencia_em = clock_timestamp(),
      saldo_referencia_motivo = v_motivo,
      updated_at = now()
  where cb.id = v_conta.id
    and cb.tenant_id = p_tenant_id
    and cb.empresa_id = p_empresa_id;

  insert into f.evento_financeiro (
    tenant_id,
    empresa_id,
    evento,
    ref_table,
    ref_id,
    payload
  ) values (
    p_tenant_id,
    p_empresa_id,
    'AJUSTE_SALDO_CONTA',
    'f.conta_bancaria',
    v_conta.id,
    jsonb_build_object(
      'conta_bancaria_id', v_conta.id,
      'conta_codigo', v_conta.codigo,
      'saldo_anterior', v_conta.saldo_referencia,
      'data_anterior', v_conta.saldo_referencia_data,
      'saldo_confirmado', round(p_saldo_atual, 2),
      'data_referencia', p_data_referencia,
      'motivo', v_motivo
    )
  );
end;
$$;

create or replace function f.contas_bancarias_saldos(
  p_tenant_id uuid,
  p_empresa_ids uuid[],
  p_data_inicio date,
  p_data_fim date,
  p_data_referencia date default current_date
)
returns table (
  empresa_id uuid,
  conta_bancaria_id uuid,
  conta_codigo text,
  conta_nome text,
  conta_tipo text,
  configurada boolean,
  saldo_referencia numeric,
  saldo_referencia_data date,
  saldo_referencia_motivo text,
  saldo_inicial_periodo numeric,
  entradas_periodo numeric,
  saidas_periodo numeric,
  transferencias_periodo numeric,
  saldo_atual numeric
)
language plpgsql
stable
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
begin
  if auth.uid() is null then
    raise exception 'Usuario nao autenticado';
  end if;

  if p_tenant_id is null
     or p_tenant_id is distinct from public.current_tenant_id() then
    raise exception 'Tenant invalido para a sessao atual';
  end if;

  if coalesce(cardinality(p_empresa_ids), 0) = 0 then
    raise exception 'Informe ao menos uma empresa';
  end if;

  if p_data_inicio is null
     or p_data_fim is null
     or p_data_referencia is null
     or p_data_inicio > p_data_fim then
    raise exception 'Periodo invalido';
  end if;

  if exists (
    select 1
    from unnest(p_empresa_ids) as requested(empresa_id)
    where not exists (
      select 1
      from c.empresa e
      where e.id = requested.empresa_id
        and e.tenant_id = p_tenant_id
        and e.deleted_at is null
    )
       or not f.has_finance_access(p_tenant_id, requested.empresa_id)
  ) then
    raise exception 'Sem acesso financeiro a uma das empresas solicitadas';
  end if;

  return query
  with contas as (
    select cb.*
    from f.conta_bancaria cb
    where cb.tenant_id = p_tenant_id
      and cb.empresa_id = any(p_empresa_ids)
      and cb.deleted_at is null
  ),
  pagamentos_classificados as (
    select
      p.id,
      p.empresa_id,
      p.conta_bancaria_id,
      p.data_pagamento as data_movimento,
      p.created_at,
      p.valor,
      case
        when bool_or(t.tipo = 'AR') and not bool_or(t.tipo = 'AP') then 'ENTRADA'
        when bool_or(t.tipo = 'AP') and not bool_or(t.tipo = 'AR') then 'SAIDA'
        else null
      end as natureza
    from f.pagamento p
    join f.pagamento_item pi
      on pi.pagamento_id = p.id
     and pi.tenant_id = p.tenant_id
     and pi.empresa_id = p.empresa_id
     and pi.deleted_at is null
    join f.titulo_parcela tp
      on tp.id = pi.titulo_parcela_id
     and tp.tenant_id = p.tenant_id
     and tp.deleted_at is null
    join f.titulo t
      on t.id = tp.titulo_id
     and t.tenant_id = p.tenant_id
     and t.empresa_id = p.empresa_id
     and t.deleted_at is null
    where p.tenant_id = p_tenant_id
      and p.empresa_id = any(p_empresa_ids)
      and p.deleted_at is null
    group by
      p.id,
      p.empresa_id,
      p.conta_bancaria_id,
      p.data_pagamento,
      p.created_at,
      p.valor
  ),
  movimentos as (
    select
      pc.empresa_id,
      pc.conta_bancaria_id,
      pc.data_movimento,
      pc.created_at,
      pc.natureza,
      case when pc.natureza = 'ENTRADA' then pc.valor else -pc.valor end as valor_assinado
    from pagamentos_classificados pc
    where pc.natureza is not null

    union all

    select
      cb.empresa_id,
      el.conta_bancaria_id,
      el.data_movimento,
      el.created_at,
      'TRANSFERENCIA'::text as natureza,
      el.valor as valor_assinado
    from f.extrato_bancario_linha el
    join contas cb
      on cb.id = el.conta_bancaria_id
     and cb.tenant_id = el.tenant_id
    where el.tenant_id = p_tenant_id
      and el.deleted_at is null
      and el.status <> 'IGNORADO'
      and upper(coalesce(el.documento, '')) = 'TRANSFERENCIA'
  )
  select
    cb.empresa_id,
    cb.id as conta_bancaria_id,
    cb.codigo as conta_codigo,
    cb.nome as conta_nome,
    cb.tipo as conta_tipo,
    cb.saldo_referencia is not null
      and cb.saldo_referencia_data is not null
      and cb.saldo_referencia_em is not null as configurada,
    cb.saldo_referencia,
    cb.saldo_referencia_data,
    cb.saldo_referencia_motivo,
    case
      when cb.saldo_referencia is null
        or cb.saldo_referencia_data is null
        or cb.saldo_referencia_em is null then null
      when (p_data_inicio - 1) >= cb.saldo_referencia_data then
        cb.saldo_referencia + coalesce(sum(m.valor_assinado) filter (
          where m.data_movimento <= (p_data_inicio - 1)
            and (
              m.data_movimento > cb.saldo_referencia_data
              or m.created_at > cb.saldo_referencia_em
            )
        ), 0)
      else
        cb.saldo_referencia - coalesce(sum(m.valor_assinado) filter (
          where m.data_movimento > (p_data_inicio - 1)
            and m.data_movimento <= cb.saldo_referencia_data
            and m.created_at <= cb.saldo_referencia_em
        ), 0)
    end::numeric as saldo_inicial_periodo,
    coalesce(sum(m.valor_assinado) filter (
      where m.natureza = 'ENTRADA'
        and m.data_movimento between p_data_inicio and p_data_fim
    ), 0)::numeric as entradas_periodo,
    coalesce(-sum(m.valor_assinado) filter (
      where m.natureza = 'SAIDA'
        and m.data_movimento between p_data_inicio and p_data_fim
    ), 0)::numeric as saidas_periodo,
    coalesce(sum(m.valor_assinado) filter (
      where m.natureza = 'TRANSFERENCIA'
        and m.data_movimento between p_data_inicio and p_data_fim
    ), 0)::numeric as transferencias_periodo,
    case
      when cb.saldo_referencia is null
        or cb.saldo_referencia_data is null
        or cb.saldo_referencia_em is null then null
      when p_data_referencia >= cb.saldo_referencia_data then
        cb.saldo_referencia + coalesce(sum(m.valor_assinado) filter (
          where m.data_movimento <= p_data_referencia
            and (
              m.data_movimento > cb.saldo_referencia_data
              or m.created_at > cb.saldo_referencia_em
            )
        ), 0)
      else
        cb.saldo_referencia - coalesce(sum(m.valor_assinado) filter (
          where m.data_movimento > p_data_referencia
            and m.data_movimento <= cb.saldo_referencia_data
            and m.created_at <= cb.saldo_referencia_em
        ), 0)
    end::numeric as saldo_atual
  from contas cb
  left join movimentos m
    on m.empresa_id = cb.empresa_id
   and m.conta_bancaria_id = cb.id
  group by
    cb.empresa_id,
    cb.id,
    cb.codigo,
    cb.nome,
    cb.tipo,
    cb.saldo_referencia,
    cb.saldo_referencia_data,
    cb.saldo_referencia_em,
    cb.saldo_referencia_motivo
  order by cb.empresa_id, cb.nome, cb.codigo;
end;
$$;

create or replace function f.contas_pagar_receber_listar_v2(
  p_tenant_id uuid,
  p_empresa_ids uuid[],
  p_data_inicio date,
  p_data_fim date
)
returns table (
  empresa_id uuid,
  tipo text,
  nf_numero text,
  titulo_id uuid,
  parcela_id uuid,
  parcela_numero text,
  total_parcelas bigint,
  emissao_date date,
  vencimento_date date,
  pessoa_nome text,
  descricao text,
  motivo_codigo text,
  motivo_nome text,
  aprovado_por_nome text,
  valor numeric,
  valor_aberto numeric,
  titulo_status text,
  formas_aplicadas text[],
  formas_agendadas text[],
  contas_aplicadas text[],
  contas_agendadas text[],
  pagamento_import_json jsonb
)
language plpgsql
stable
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
begin
  if auth.uid() is null then
    raise exception 'Usuario nao autenticado';
  end if;

  if p_tenant_id is null
     or p_tenant_id is distinct from public.current_tenant_id() then
    raise exception 'Tenant invalido para a sessao atual';
  end if;

  if coalesce(cardinality(p_empresa_ids), 0) = 0 then
    raise exception 'Informe ao menos uma empresa';
  end if;

  if p_data_inicio is null or p_data_fim is null or p_data_inicio > p_data_fim then
    raise exception 'Periodo invalido';
  end if;

  if exists (
    select 1
    from unnest(p_empresa_ids) as requested(empresa_id)
    where not exists (
      select 1
      from c.empresa e
      where e.id = requested.empresa_id
        and e.tenant_id = p_tenant_id
        and e.deleted_at is null
    )
       or not f.has_finance_access(p_tenant_id, requested.empresa_id)
  ) then
    raise exception 'Sem acesso financeiro a uma das empresas solicitadas';
  end if;

  return query
  with parcelas as (
    select
      t.empresa_id,
      t.tipo,
      df.numero as nf_numero,
      t.id as titulo_id,
      tp.id as parcela_id,
      tp.numero as parcela_numero,
      count(*) over (partition by t.id) as total_parcelas,
      t.emissao_date,
      tp.vencimento_date,
      case
        when t.tipo = 'AP' then coalesce(forn.nome::text, 'Fornecedor')
        else coalesce(cli.nome::text, cli.razao_social::text, 'Cliente')
      end as pessoa_nome,
      t.descricao,
      mc.codigo as motivo_codigo,
      mc.nome as motivo_nome,
      aprovador.nome as aprovado_por_nome,
      tp.valor,
      tp.valor_aberto,
      t.status as titulo_status,
      df.pagamento_import_json
    from f.titulo_parcela tp
    join f.titulo t
      on t.id = tp.titulo_id
     and t.tenant_id = p_tenant_id
     and t.empresa_id = any(p_empresa_ids)
     and t.deleted_at is null
    left join f.documento_fiscal df
      on df.id = t.documento_fiscal_id
     and df.tenant_id = t.tenant_id
     and df.empresa_id = t.empresa_id
     and df.deleted_at is null
    left join public.fornecedores forn
      on forn.id = t.fornecedor_id
     and forn.tenant_id = t.tenant_id
     and forn.empresa_id = t.empresa_id
    left join public.clientes cli
      on cli.id = t.cliente_id
     and cli.tenant_id = t.tenant_id
     and cli.empresa_id = t.empresa_id
    left join lateral (
      select ta.motivo_compra_id, ta.aprovado_por
      from f.titulo_aprovacao ta
      where ta.tenant_id = t.tenant_id
        and ta.titulo_id = t.id
        and ta.deleted_at is null
      order by ta.aprovado_em desc, ta.created_at desc
      limit 1
    ) aprovacao on true
    left join f.motivo_compra mc
      on mc.id = coalesce(aprovacao.motivo_compra_id, t.motivo_compra_id)
     and mc.tenant_id = t.tenant_id
     and mc.deleted_at is null
    left join a.usuario aprovador
      on aprovador.id = aprovacao.aprovado_por
     and aprovador.deleted_at is null
    where tp.tenant_id = p_tenant_id
      and tp.deleted_at is null
      and tp.vencimento_date between p_data_inicio and p_data_fim
      and t.tipo in ('AP', 'AR')
  )
  select
    base.empresa_id,
    base.tipo,
    base.nf_numero,
    base.titulo_id,
    base.parcela_id,
    base.parcela_numero,
    base.total_parcelas,
    base.emissao_date,
    base.vencimento_date,
    base.pessoa_nome,
    base.descricao,
    base.motivo_codigo,
    base.motivo_nome,
    base.aprovado_por_nome,
    base.valor,
    base.valor_aberto,
    base.titulo_status,
    coalesce(aplicadas.formas, '{}'::text[]) as formas_aplicadas,
    coalesce(agendadas.formas, '{}'::text[]) as formas_agendadas,
    coalesce(aplicadas.contas, '{}'::text[]) as contas_aplicadas,
    coalesce(agendadas.contas, '{}'::text[]) as contas_agendadas,
    base.pagamento_import_json
  from parcelas base
  left join lateral (
    select
      array_agg(distinct p.forma_pagamento order by p.forma_pagamento) as formas,
      array_agg(
        distinct concat_ws(' - ', nullif(cb.codigo, ''), nullif(cb.nome, ''))
        order by concat_ws(' - ', nullif(cb.codigo, ''), nullif(cb.nome, ''))
      ) as contas
    from f.pagamento_item pi
    join f.pagamento p
      on p.id = pi.pagamento_id
     and p.tenant_id = p_tenant_id
     and p.empresa_id = base.empresa_id
     and p.deleted_at is null
    join f.conta_bancaria cb
      on cb.id = p.conta_bancaria_id
     and cb.tenant_id = p.tenant_id
     and cb.empresa_id = p.empresa_id
     and cb.deleted_at is null
    where pi.tenant_id = p_tenant_id
      and pi.empresa_id = base.empresa_id
      and pi.titulo_parcela_id = base.parcela_id
      and pi.deleted_at is null
  ) aplicadas on true
  left join lateral (
    select
      array_agg(distinct ta.forma_pagamento order by ta.forma_pagamento) as formas,
      array_agg(
        distinct concat_ws(' - ', nullif(cb.codigo, ''), nullif(cb.nome, ''))
        order by concat_ws(' - ', nullif(cb.codigo, ''), nullif(cb.nome, ''))
      ) as contas
    from f.titulo_agendamento ta
    join f.conta_bancaria cb
      on cb.id = ta.conta_bancaria_id
     and cb.tenant_id = p_tenant_id
     and cb.empresa_id = base.empresa_id
     and cb.deleted_at is null
    where ta.tenant_id = p_tenant_id
      and ta.titulo_id = base.titulo_id
      and ta.deleted_at is null
  ) agendadas on true
  order by base.vencimento_date, base.tipo, base.pessoa_nome;
end;
$$;

revoke all on function f.conta_bancaria_ajustar_saldo(uuid, uuid, uuid, numeric, date, text) from public;
revoke all on function f.contas_bancarias_saldos(uuid, uuid[], date, date, date) from public;
revoke all on function f.contas_pagar_receber_listar_v2(uuid, uuid[], date, date) from public;

grant execute on function f.conta_bancaria_ajustar_saldo(uuid, uuid, uuid, numeric, date, text) to authenticated, service_role;
grant execute on function f.contas_bancarias_saldos(uuid, uuid[], date, date, date) to authenticated, service_role;
grant execute on function f.contas_pagar_receber_listar_v2(uuid, uuid[], date, date) to authenticated, service_role;

comment on function f.conta_bancaria_ajustar_saldo(uuid, uuid, uuid, numeric, date, text) is
  'Confirma uma posicao bancaria por conta, empresa e tenant, preservando auditoria.';
comment on function f.contas_bancarias_saldos(uuid, uuid[], date, date, date) is
  'Calcula saldo inicial do periodo e saldo atual por conta com pagamentos, recebimentos e transferencias.';
comment on function f.contas_pagar_receber_listar_v2(uuid, uuid[], date, date) is
  'Lista AP/AR multiempresa incluindo as contas bancarias aplicadas e agendadas.';
