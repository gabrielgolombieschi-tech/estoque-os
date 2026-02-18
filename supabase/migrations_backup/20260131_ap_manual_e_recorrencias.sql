-- AP manual + despesas recorrentes (provis93o mensal)

create schema if not exists f;

-- 1) Tabela de recorr82ncia de AP (ex: energia/1gua/aluguel)
create table if not exists f.ap_recorrencia (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,

  fornecedor_id integer null,
  descricao text not null,

  motivo_compra_id uuid null,

  dia_vencimento integer not null,
  auto_copiar_valor boolean not null default true,
  valor_base numeric(15,2) not null default 0,

  ativo boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default a.fn_current_usuario_id(),
  updated_by uuid,
  deleted_at timestamptz
);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'ck_ap_recorrencia__dia_vencimento'
  ) then
    alter table f.ap_recorrencia
      add constraint ck_ap_recorrencia__dia_vencimento
      check (dia_vencimento between 1 and 31);
  end if;
end$$;

-- 2) Link opcional da recorr82ncia no t1tulo
alter table f.titulo add column if not exists recorrencia_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'uq_titulo__recorrencia_competencia'
  ) then
    alter table f.titulo
      add constraint uq_titulo__recorrencia_competencia
      unique (tenant_id, recorrencia_id, competencia_date);
  end if;
exception
  when duplicate_object then
    null;
end$$;

create index if not exists idx_titulo__recorrencia_id on f.titulo (recorrencia_id);

-- Helpers
create or replace function f._month_first(p_date date)
returns date
language sql
immutable
as $$
  select date_trunc('month', p_date)::date;
$$;

create or replace function f._month_last(p_date date)
returns date
language sql
immutable
as $$
  select (date_trunc('month', p_date) + interval '1 month - 1 day')::date;
$$;

create or replace function f._safe_day_in_month(p_month_first date, p_day integer)
returns date
language sql
immutable
as $$
  select make_date(extract(year from p_month_first)::int, extract(month from p_month_first)::int,
    least(greatest(p_day, 1), extract(day from f._month_last(p_month_first))::int)
  );
$$;

create or replace function f.criar_titulo_ap_manual(
  -- IMPORTANT (Postgres rule): once a parameter has a default, all following must also have defaults.
  -- Keep required parameters first.
  p_descricao text,
  p_vencimento_date date,
  p_valor numeric,
  p_fornecedor_id integer default null,
  p_motivo_compra_id uuid default null,
  p_criar_recorrencia boolean default false,
  p_dia_vencimento integer default null,
  p_auto_copiar_valor boolean default true,
  p_change_reason text default null
)
returns table (titulo_id uuid, recorrencia_id uuid)
language plpgsql
security definer
set search_path to 'f','public','a','c'
set row_security to 'off'
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_usuario_id uuid;

  v_titulo_id uuid;
  v_recorrencia_id uuid;
  v_competencia date;
  v_day integer;
begin
  if p_descricao is null or length(trim(p_descricao)) = 0 then
    raise exception 'p_descricao obrigat3rio';
  end if;
  if p_vencimento_date is null then
    raise exception 'p_vencimento_date obrigat3rio';
  end if;
  if p_valor is null or p_valor <= 0 then
    raise exception 'p_valor deve ser > 0';
  end if;

  -- Auth: app ou SQL Editor
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();
  if v_tenant_id is null then
    raise exception 'Tenant n3o resolvido (current_tenant_id())';
  end if;
  if v_empresa_id is null then
    raise exception 'Empresa n3o resolvida (current_empresa_id())';
  end if;

  if auth.uid() is not null then
    if not f.has_finance_access(v_tenant_id, v_empresa_id) then
      raise exception 'Sem permiss3o financeira';
    end if;
  end if;

  v_usuario_id := a.fn_current_usuario_id();

  v_competencia := f._month_first(p_vencimento_date);

  insert into f.titulo (
    tenant_id,
    empresa_id,
    tipo,
    status,
    fornecedor_id,
    descricao,
    emissao_date,
    competencia_date,
    valor_total,
    valor_aberto,
    motivo_compra_id,
    created_at,
    updated_at,
    created_by,
    updated_by,
    deleted_at
  ) values (
    v_tenant_id,
    v_empresa_id,
    'AP',
    'PENDENTE',
    p_fornecedor_id,
    trim(p_descricao),
    current_date,
    v_competencia,
    p_valor,
    p_valor,
    p_motivo_compra_id,
    now(),
    now(),
    v_usuario_id,
    v_usuario_id,
    null
  ) returning id into v_titulo_id;

  insert into f.titulo_parcela (
    tenant_id,
    titulo_id,
    numero,
    vencimento_date,
    valor,
    valor_aberto,
    created_at,
    updated_at,
    created_by,
    updated_by,
    deleted_at
  ) values (
    v_tenant_id,
    v_titulo_id,
    '1',
    p_vencimento_date,
    p_valor,
    p_valor,
    now(),
    now(),
    v_usuario_id,
    v_usuario_id,
    null
  );

  if p_criar_recorrencia then
    v_day := coalesce(p_dia_vencimento, extract(day from p_vencimento_date)::int);

    insert into f.ap_recorrencia (
      tenant_id,
      empresa_id,
      fornecedor_id,
      descricao,
      motivo_compra_id,
      dia_vencimento,
      auto_copiar_valor,
      valor_base,
      ativo,
      created_at,
      updated_at,
      created_by,
      updated_by,
      deleted_at
    ) values (
      v_tenant_id,
      v_empresa_id,
      p_fornecedor_id,
      trim(p_descricao),
      p_motivo_compra_id,
      v_day,
      coalesce(p_auto_copiar_valor, true),
      p_valor,
      true,
      now(),
      now(),
      v_usuario_id,
      v_usuario_id,
      null
    ) returning id into v_recorrencia_id;

    update f.titulo
      set recorrencia_id = v_recorrencia_id,
          updated_at = now(),
          updated_by = v_usuario_id
    where id = v_titulo_id;
  end if;

  return query select v_titulo_id, v_recorrencia_id;
end;
$$;

-- 4) Provisionar meses futuros para uma recorr82ncia
create or replace function f.provisionar_ap_recorrencia(
  p_recorrencia_id uuid,
  p_meses_a_frente integer default 12,
  p_change_reason text default null
)
returns integer
language plpgsql
security definer
set search_path to 'f','public','a','c'
set row_security to 'off'
as $$
declare
  v_rec f.ap_recorrencia%rowtype;
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_usuario_id uuid;

  v_i integer;
  v_month_first date;
  v_venc date;
  v_valor numeric(15,2);

  v_count integer := 0;
  v_exists uuid;
  v_last_valor numeric(15,2);
begin
  if p_recorrencia_id is null then
    raise exception 'p_recorrencia_id obrigat3rio';
  end if;

  -- Auth: app ou SQL Editor
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_rec
  from f.ap_recorrencia r
  where r.id = p_recorrencia_id
    and r.deleted_at is null
    and r.ativo = true;

  if not found then
    raise exception 'Recorr8ncia n3o encontrada/inativa';
  end if;

  v_tenant_id := v_rec.tenant_id;
  v_empresa_id := v_rec.empresa_id;

  if auth.uid() is not null then
    if not f.has_finance_access(v_tenant_id, v_empresa_id) then
      raise exception 'Sem permiss3o financeira';
    end if;
  end if;

  v_usuario_id := a.fn_current_usuario_id();

  if p_meses_a_frente is null or p_meses_a_frente < 0 then
    p_meses_a_frente := 0;
  end if;

  for v_i in 0..p_meses_a_frente loop
    v_month_first := f._month_first((current_date + (v_i || ' month')::interval)::date);

    -- evita duplicar por competencia
    select t.id into v_exists
    from f.titulo t
    where t.deleted_at is null
      and t.tenant_id = v_tenant_id
      and t.recorrencia_id = v_rec.id
      and t.competencia_date = v_month_first
    limit 1;

    if v_exists is not null then
      continue;
    end if;

    v_venc := f._safe_day_in_month(v_month_first, v_rec.dia_vencimento);

    v_valor := v_rec.valor_base;

    if v_rec.auto_copiar_valor then
      select t.valor_total
        into v_last_valor
      from f.titulo t
      where t.deleted_at is null
        and t.tenant_id = v_tenant_id
        and t.recorrencia_id = v_rec.id
        and t.competencia_date < v_month_first
      order by t.competencia_date desc nulls last
      limit 1;

      if v_last_valor is not null and v_last_valor > 0 then
        v_valor := v_last_valor;
      end if;
    end if;

    insert into f.titulo (
      tenant_id,
      empresa_id,
      tipo,
      status,
      fornecedor_id,
      descricao,
      emissao_date,
      competencia_date,
      valor_total,
      valor_aberto,
      recorrencia_id,
      motivo_compra_id,
      created_at,
      updated_at,
      created_by,
      updated_by,
      deleted_at
    ) values (
      v_tenant_id,
      v_empresa_id,
      'AP',
      'PENDENTE',
      v_rec.fornecedor_id,
      v_rec.descricao,
      current_date,
      v_month_first,
      v_valor,
      v_valor,
      v_rec.id,
      v_rec.motivo_compra_id,
      now(),
      now(),
      v_usuario_id,
      v_usuario_id,
      null
    ) returning id into v_exists;

    insert into f.titulo_parcela (
      tenant_id,
      titulo_id,
      numero,
      vencimento_date,
      valor,
      valor_aberto,
      created_at,
      updated_at,
      created_by,
      updated_by,
      deleted_at
    ) values (
      v_tenant_id,
      v_exists,
      '1',
      v_venc,
      v_valor,
      v_valor,
      now(),
      now(),
      v_usuario_id,
      v_usuario_id,
      null
    );

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- 5) Atualizar valores provisionados dos pr2ximos meses com base em um m6s de refer8ncia
create or replace function f.atualizar_proximos_ap_recorrencia(
  p_recorrencia_id uuid,
  p_referencia_competencia date default null,
  p_change_reason text default null
)
returns integer
language plpgsql
security definer
set search_path to 'f','public','a','c'
set row_security to 'off'
as $$
declare
  v_rec f.ap_recorrencia%rowtype;
  v_ref_comp date;
  v_ref_valor numeric(15,2);
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_usuario_id uuid;

  v_count integer := 0;
begin
  if p_recorrencia_id is null then
    raise exception 'p_recorrencia_id obrigat3rio';
  end if;

  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_rec
  from f.ap_recorrencia r
  where r.id = p_recorrencia_id
    and r.deleted_at is null;

  if not found then
    raise exception 'Recorr8ncia n3o encontrada';
  end if;

  v_tenant_id := v_rec.tenant_id;
  v_empresa_id := v_rec.empresa_id;

  if auth.uid() is not null then
    if not f.has_finance_access(v_tenant_id, v_empresa_id) then
      raise exception 'Sem permiss3o financeira';
    end if;
  end if;

  v_usuario_id := a.fn_current_usuario_id();

  if p_referencia_competencia is not null then
    v_ref_comp := f._month_first(p_referencia_competencia);
  else
    select t.competencia_date
      into v_ref_comp
    from f.titulo t
    where t.deleted_at is null
      and t.tenant_id = v_tenant_id
      and t.recorrencia_id = v_rec.id
    order by t.competencia_date desc nulls last
    limit 1;
  end if;

  if v_ref_comp is null then
    raise exception 'N3o h1 t1tulo de refer8ncia para esta recorr8ncia';
  end if;

  select t.valor_total
    into v_ref_valor
  from f.titulo t
  where t.deleted_at is null
    and t.tenant_id = v_tenant_id
    and t.recorrencia_id = v_rec.id
    and t.competencia_date = v_ref_comp
  order by t.created_at desc
  limit 1;

  if v_ref_valor is null or v_ref_valor <= 0 then
    raise exception 'Valor de refer8ncia inv1lido';
  end if;

  -- Atualiza apenas futuros ainda provisionados (PENDENTE) e sem pagamentos aplicados
  with futuros as (
    select t.id as titulo_id
    from f.titulo t
    where t.deleted_at is null
      and t.tenant_id = v_tenant_id
      and t.recorrencia_id = v_rec.id
      and t.competencia_date > v_ref_comp
      and t.status = 'PENDENTE'
  ), sem_pagamentos as (
    select f.titulo_id
    from futuros f
    where not exists (
      select 1
      from f.titulo_parcela tp
      join f.pagamento_item pi on pi.titulo_parcela_id = tp.id and pi.deleted_at is null
      where tp.titulo_id = f.titulo_id
        and tp.deleted_at is null
    )
  )
  update f.titulo t
     set valor_total = v_ref_valor,
         valor_aberto = v_ref_valor,
         updated_at = now(),
         updated_by = v_usuario_id
   where t.id in (select titulo_id from sem_pagamentos)
  returning 1 into v_count;

  -- Ajusta parcelas (valor + valor_aberto)
  update f.titulo_parcela tp
     set valor = v_ref_valor,
         valor_aberto = v_ref_valor,
         updated_at = now(),
         updated_by = v_usuario_id
   where tp.deleted_at is null
     and tp.titulo_id in (
       select t.id
       from f.titulo t
       where t.deleted_at is null
         and t.tenant_id = v_tenant_id
         and t.recorrencia_id = v_rec.id
         and t.competencia_date > v_ref_comp
         and t.status = 'PENDENTE'
     );

  return coalesce(v_count, 0);
end;
$$;

grant execute on function f.criar_titulo_ap_manual(text, date, numeric, integer, uuid, boolean, integer, boolean, text) to authenticated;
grant execute on function f.provisionar_ap_recorrencia(uuid, integer, text) to authenticated;
grant execute on function f.atualizar_proximos_ap_recorrencia(uuid, date, text) to authenticated;

-- 6) Ajustar valor do ttulo/parcela AP (antes de pagar). 
-- Uso: contas provisionadas (energia/gua) podem variar; ajusta o valor para o real e depois paga.
create or replace function f.ajustar_valor_parcela_ap(
  p_titulo_parcela_id uuid,
  p_novo_valor numeric,
  p_change_reason text default null
)
returns void
language plpgsql
security definer
set search_path to 'f','public','a','c'
set row_security to 'off'
as $$
declare
  v_tp f.titulo_parcela%rowtype;
  v_t f.titulo%rowtype;
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_usuario_id uuid;
  v_delta numeric(15,2);
begin
  if p_titulo_parcela_id is null then
    raise exception 'p_titulo_parcela_id obrigat3rio';
  end if;
  if p_novo_valor is null or p_novo_valor <= 0 then
    raise exception 'p_novo_valor deve ser > 0';
  end if;

  -- Auth: app ou SQL Editor
  if auth.uid() is null then
    if current_user not in ('postgres','service_role') then
      raise exception 'Usuario nao autenticado';
    end if;
  end if;

  select * into v_tp
  from f.titulo_parcela tp
  where tp.id = p_titulo_parcela_id
    and tp.deleted_at is null;

  if not found then
    raise exception 'Parcela n3o encontrada';
  end if;

  select * into v_t
  from f.titulo t
  where t.id = v_tp.titulo_id
    and t.deleted_at is null;

  if not found then
    raise exception 'Titulo n3o encontrado';
  end if;

  if v_t.tipo <> 'AP' then
    raise exception 'Somente AP pode ajustar valor';
  end if;

  if v_t.status <> 'PENDENTE' then
    raise exception 'S3 ajusta valor em t1tulo PENDENTE (status=%)', v_t.status;
  end if;

  -- N3o permite ajustar se j1 h1 pagamentos aplicados
  if exists (
    select 1
    from f.pagamento_item pi
    where pi.titulo_parcela_id = v_tp.id
      and pi.deleted_at is null
  ) then
    raise exception 'N3o  poss1vel ajustar: parcela j1 possui pagamentos aplicados';
  end if;

  v_tenant_id := v_t.tenant_id;
  v_empresa_id := v_t.empresa_id;

  if auth.uid() is not null then
    if not f.has_finance_access(v_tenant_id, v_empresa_id) then
      raise exception 'Sem permiss3o financeira';
    end if;
  end if;

  v_usuario_id := a.fn_current_usuario_id();
  v_delta := p_novo_valor - v_tp.valor;

  -- Ajusta parcela
  update f.titulo_parcela
     set valor = p_novo_valor,
         valor_aberto = p_novo_valor,
         updated_at = now(),
         updated_by = v_usuario_id
   where id = v_tp.id;

  -- Ajusta t1tulo
  update f.titulo
     set valor_total = valor_total + v_delta,
         valor_aberto = valor_aberto + v_delta,
         updated_at = now(),
         updated_by = v_usuario_id
   where id = v_t.id;
end;
$$;

grant execute on function f.ajustar_valor_parcela_ap(uuid, numeric, text) to authenticated;
