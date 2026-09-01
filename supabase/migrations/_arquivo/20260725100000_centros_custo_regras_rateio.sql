-- Centros de custo e regras automaticas de rateio por empresa.
-- Nao semeia centros/regras e nao reclassifica rateios existentes.

create table if not exists f.regra_rateio (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null,
  motivo_compra_id uuid,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default a.fn_current_usuario_id(),
  updated_by uuid,
  deleted_at timestamptz,
  constraint fk_regra_rateio_empresa
    foreign key (empresa_id) references c.empresa(id),
  constraint fk_regra_rateio_motivo
    foreign key (motivo_compra_id) references f.motivo_compra(id)
);

comment on table f.regra_rateio is
  'Regra automatica por tenant/empresa e motivo. O plano e sempre herdado do motivo; apenas centros e percentuais sao divididos.';

alter table f.regra_rateio
  alter column motivo_compra_id set not null;

create unique index if not exists uq_regra_rateio_motivo_ativo
  on f.regra_rateio (tenant_id, empresa_id, motivo_compra_id)
  where deleted_at is null and ativo and motivo_compra_id is not null;

create index if not exists idx_regra_rateio_escopo
  on f.regra_rateio (tenant_id, empresa_id, ativo)
  where deleted_at is null;

create table if not exists f.regra_rateio_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  regra_rateio_id uuid not null,
  plano_contas_id uuid not null,
  centro_custo_id uuid not null,
  percentual numeric(7,4) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default a.fn_current_usuario_id(),
  updated_by uuid,
  deleted_at timestamptz,
  constraint fk_regra_rateio_item_regra
    foreign key (regra_rateio_id) references f.regra_rateio(id),
  constraint fk_regra_rateio_item_plano
    foreign key (plano_contas_id) references f.plano_contas(id),
  constraint fk_regra_rateio_item_centro
    foreign key (centro_custo_id) references f.centro_custo(id),
  constraint ck_regra_rateio_item_percentual
    check (percentual > 0 and percentual <= 100)
);

create unique index if not exists uq_regra_rateio_item_dimensao
  on f.regra_rateio_item
    (tenant_id, regra_rateio_id, plano_contas_id, centro_custo_id)
  where deleted_at is null;

create index if not exists idx_regra_rateio_item_regra
  on f.regra_rateio_item (tenant_id, regra_rateio_id)
  where deleted_at is null;

alter table f.titulo_rateio
  add column if not exists origem_rateio text not null default 'EXPLICITO',
  add column if not exists regra_rateio_id uuid,
  add column if not exists regra_item_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'f.titulo_rateio'::regclass
      and conname = 'ck_titulo_rateio_origem_rateio'
  ) then
    alter table f.titulo_rateio
      add constraint ck_titulo_rateio_origem_rateio
      check (
        origem_rateio in (
          'EXPLICITO',
          'AUTOMATICO_REGRA',
          'SISTEMA_FALLBACK'
        )
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'f.titulo_rateio'::regclass
      and conname = 'ck_titulo_rateio_regra_origem'
  ) then
    alter table f.titulo_rateio
      add constraint ck_titulo_rateio_regra_origem
      check (
        (
          origem_rateio = 'AUTOMATICO_REGRA'
          and regra_rateio_id is not null
          and regra_item_id is not null
        )
        or
        (
          origem_rateio <> 'AUTOMATICO_REGRA'
          and regra_rateio_id is null
          and regra_item_id is null
        )
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'f.titulo_rateio'::regclass
      and conname = 'fk_titulo_rateio_regra_rateio'
  ) then
    alter table f.titulo_rateio
      add constraint fk_titulo_rateio_regra_rateio
      foreign key (regra_rateio_id) references f.regra_rateio(id);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'f.titulo_rateio'::regclass
      and conname = 'fk_titulo_rateio_regra_item'
  ) then
    alter table f.titulo_rateio
      add constraint fk_titulo_rateio_regra_item
      foreign key (regra_item_id) references f.regra_rateio_item(id);
  end if;
end;
$$;

create unique index if not exists uq_titulo_rateio_regra_item_ativo
  on f.titulo_rateio (tenant_id, titulo_id, regra_item_id)
  where deleted_at is null and origem_rateio = 'AUTOMATICO_REGRA';

create index if not exists idx_titulo_rateio_origem
  on f.titulo_rateio (tenant_id, titulo_id, origem_rateio)
  where deleted_at is null;

create or replace function f.pode_ler_regras_rateio(
  p_tenant_id uuid,
  p_empresa_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
  select
    p_tenant_id = public.current_tenant_id()
    and p_empresa_id = public.current_empresa_id()
    and f.has_finance_access(p_tenant_id, p_empresa_id)
    and (
      public.has_permission('financeiro.read')
      or public.has_permission('financeiro.write')
      or public.has_permission('admin.manage_users')
      or public.has_permission('admin.all')
      or exists (
        select 1
        from a.usuario u
        join a.usuario_tenant ut on ut.usuario_id = u.id
        where u.auth_user_id = auth.uid()
          and u.deleted_at is null
          and ut.tenant_id = p_tenant_id
          and ut.ativo and ut.deleted_at is null
          and ut.papel in ('OWNER', 'ADMIN')
      )
      or exists (
        select 1
        from a.usuario u
        join a.usuario_empresa ue on ue.usuario_id = u.id
        where u.auth_user_id = auth.uid()
          and u.deleted_at is null
          and ue.empresa_id = p_empresa_id
          and ue.ativo and ue.deleted_at is null
          and ue.papel in ('ADMIN', 'FINANCEIRO')
      )
    );
$$;

create or replace function f.pode_escrever_regras_rateio(
  p_tenant_id uuid,
  p_empresa_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
  select
    p_tenant_id = public.current_tenant_id()
    and p_empresa_id = public.current_empresa_id()
    and f.has_finance_access(p_tenant_id, p_empresa_id)
    and (
      public.has_permission('financeiro.write')
      or public.has_permission('admin.manage_users')
      or public.has_permission('admin.all')
      or exists (
        select 1
        from a.usuario u
        join a.usuario_tenant ut on ut.usuario_id = u.id
        where u.auth_user_id = auth.uid()
          and u.deleted_at is null
          and ut.tenant_id = p_tenant_id
          and ut.ativo and ut.deleted_at is null
          and ut.papel in ('OWNER', 'ADMIN')
      )
      or exists (
        select 1
        from a.usuario u
        join a.usuario_empresa ue on ue.usuario_id = u.id
        where u.auth_user_id = auth.uid()
          and u.deleted_at is null
          and ue.empresa_id = p_empresa_id
          and ue.ativo and ue.deleted_at is null
          and ue.papel in ('ADMIN', 'FINANCEIRO')
      )
    );
$$;

revoke all on function f.pode_ler_regras_rateio(uuid, uuid) from public;
revoke all on function f.pode_escrever_regras_rateio(uuid, uuid) from public;
grant execute on function f.pode_ler_regras_rateio(uuid, uuid)
  to authenticated, service_role;
grant execute on function f.pode_escrever_regras_rateio(uuid, uuid)
  to authenticated, service_role;

create or replace function f.trg_regra_rateio_validar()
returns trigger
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_plano_id uuid;
begin
  if new.deleted_at is not null then
    new.updated_at := now();
    if tg_op = 'UPDATE' then
      new.updated_by := a.fn_current_usuario_id();
    end if;
    return new;
  end if;

  if not exists (
    select 1
    from c.empresa e
    where e.id = new.empresa_id
      and e.tenant_id = new.tenant_id
      and e.ativo
      and e.deleted_at is null
  ) then
    raise exception using
      errcode = '23503',
      message = 'Regra de rateio: empresa invalida ou de outro tenant.';
  end if;

  select mc.plano_contas_id
    into v_plano_id
  from f.motivo_compra mc
  join f.plano_contas pc
    on pc.id = mc.plano_contas_id
   and pc.tenant_id = mc.tenant_id
   and pc.tipo = 'ANALITICA'
   and pc.ativo
   and pc.deleted_at is null
  where mc.id = new.motivo_compra_id
    and mc.tenant_id = new.tenant_id
    and mc.ativo
    and mc.deleted_at is null;

  if v_plano_id is null then
    raise exception using
      errcode = '23503',
      message = 'Regra de rateio: motivo sem plano de contas analitico ativo.';
  end if;

  new.updated_at := now();
  if tg_op = 'UPDATE' then
    new.updated_by := a.fn_current_usuario_id();
  end if;
  return new;
end;
$$;

create or replace function f.trg_regra_rateio_item_validar()
returns trigger
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_empresa_id uuid;
  v_plano_motivo uuid;
begin
  if new.deleted_at is not null then
    new.updated_at := now();
    if tg_op = 'UPDATE' then
      new.updated_by := a.fn_current_usuario_id();
    end if;
    return new;
  end if;

  select rr.empresa_id, mc.plano_contas_id
    into v_empresa_id, v_plano_motivo
  from f.regra_rateio rr
  join f.motivo_compra mc
    on mc.id = rr.motivo_compra_id
   and mc.tenant_id = rr.tenant_id
   and mc.ativo
   and mc.deleted_at is null
  where rr.id = new.regra_rateio_id
    and rr.tenant_id = new.tenant_id
    and rr.deleted_at is null;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'Item da regra: regra invalida ou de outro tenant.';
  end if;

  if new.plano_contas_id is distinct from v_plano_motivo
     or not exists (
       select 1
       from f.plano_contas pc
       where pc.id = new.plano_contas_id
         and pc.tenant_id = new.tenant_id
         and pc.tipo = 'ANALITICA'
         and pc.ativo
         and pc.deleted_at is null
     )
  then
    raise exception using
      errcode = '23514',
      message = 'Item da regra: o plano deve ser o plano analitico definido no motivo.';
  end if;

  if not exists (
    select 1
    from f.centro_custo cc
    where cc.id = new.centro_custo_id
      and cc.tenant_id = new.tenant_id
      and cc.empresa_id = v_empresa_id
      and cc.ativo
      and cc.deleted_at is null
  ) then
    raise exception using
      errcode = '23503',
      message = 'Item da regra: centro de custo invalido, inativo ou de outra empresa.';
  end if;

  new.updated_at := now();
  if tg_op = 'UPDATE' then
    new.updated_by := a.fn_current_usuario_id();
  end if;
  return new;
end;
$$;

create or replace function f.validar_total_regra_rateio(
  p_tenant_id uuid,
  p_regra_rateio_id uuid
)
returns void
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_quantidade integer;
  v_total numeric;
begin
  if not exists (
    select 1
    from f.regra_rateio rr
    where rr.id = p_regra_rateio_id
      and rr.tenant_id = p_tenant_id
      and rr.deleted_at is null
  ) then
    return;
  end if;

  select count(*)::integer, coalesce(sum(rri.percentual), 0)
    into v_quantidade, v_total
  from f.regra_rateio_item rri
  where rri.tenant_id = p_tenant_id
    and rri.regra_rateio_id = p_regra_rateio_id
    and rri.deleted_at is null;

  if v_quantidade = 0 then
    raise exception using
      errcode = '23514',
      message = 'Regra de rateio: informe ao menos um destino.';
  end if;

  if abs(v_total - 100.0000) > 0.0001 then
    raise exception using
      errcode = '23514',
      message = format(
        'Regra de rateio: os percentuais devem somar 100%% (soma atual: %s%%).',
        round(v_total, 4)
      );
  end if;
end;
$$;

create or replace function f.trg_validar_total_regra_rateio()
returns trigger
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform f.validar_total_regra_rateio(
      old.tenant_id,
      old.regra_rateio_id
    );
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    perform f.validar_total_regra_rateio(
      new.tenant_id,
      new.regra_rateio_id
    );
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function f.trg_validar_cabecalho_regra_rateio()
returns trigger
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
begin
  if new.deleted_at is null then
    perform f.validar_total_regra_rateio(new.tenant_id, new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_regra_rateio_validar on f.regra_rateio;
create trigger trg_regra_rateio_validar
before insert or update on f.regra_rateio
for each row
execute function f.trg_regra_rateio_validar();

drop trigger if exists trg_regra_rateio_item_validar
  on f.regra_rateio_item;
create trigger trg_regra_rateio_item_validar
before insert or update on f.regra_rateio_item
for each row
execute function f.trg_regra_rateio_item_validar();

drop trigger if exists ct_regra_rateio_item_total
  on f.regra_rateio_item;
create constraint trigger ct_regra_rateio_item_total
after insert or update or delete on f.regra_rateio_item
deferrable initially deferred
for each row
execute function f.trg_validar_total_regra_rateio();

drop trigger if exists ct_regra_rateio_cabecalho_total
  on f.regra_rateio;
create constraint trigger ct_regra_rateio_cabecalho_total
after insert or update on f.regra_rateio
deferrable initially deferred
for each row
execute function f.trg_validar_cabecalho_regra_rateio();

create or replace function f.trg_centro_custo_validar_hierarquia()
returns trigger
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_cursor uuid;
  v_parent_ativo boolean;
  v_visitados uuid[] := array[]::uuid[];
begin
  if new.parent_id is not null then
    if new.parent_id = new.id then
      raise exception using
        errcode = '23514',
        message = 'Centro de custo nao pode ser pai de si mesmo.';
    end if;

    select cc.parent_id, cc.ativo
      into v_cursor, v_parent_ativo
    from f.centro_custo cc
    where cc.id = new.parent_id
      and cc.tenant_id = new.tenant_id
      and cc.empresa_id = new.empresa_id
      and cc.deleted_at is null;

    if not found then
      raise exception using
        errcode = '23503',
        message = 'Centro pai invalido ou de outra empresa.';
    end if;

    if new.ativo and not v_parent_ativo then
      raise exception using
        errcode = '23514',
        message = 'Centro ativo nao pode ficar abaixo de um centro pai inativo.';
    end if;

    v_visitados := array_append(v_visitados, new.parent_id);
    while v_cursor is not null loop
      if v_cursor = new.id then
        raise exception using
          errcode = '23514',
          message = 'A hierarquia de centros de custo nao pode conter ciclos.';
      end if;
      if v_cursor = any(v_visitados) then
        raise exception using
          errcode = '23514',
          message = 'A hierarquia existente de centros de custo possui um ciclo.';
      end if;
      v_visitados := array_append(v_visitados, v_cursor);

      select cc.parent_id
        into v_cursor
      from f.centro_custo cc
      where cc.id = v_cursor
        and cc.tenant_id = new.tenant_id
        and cc.empresa_id = new.empresa_id
        and cc.deleted_at is null;

      if not found then
        raise exception using
          errcode = '23503',
          message = 'A hierarquia referencia centro de outra empresa ou excluido.';
      end if;
    end loop;
  end if;

  if tg_op = 'UPDATE'
     and old.deleted_at is null
     and (
       (old.ativo and not new.ativo)
       or new.deleted_at is not null
     )
  then
    if new.deleted_at is not null
       and exists (
         select 1
         from f.centro_custo filho
         where filho.tenant_id = new.tenant_id
           and filho.empresa_id = new.empresa_id
           and filho.parent_id = new.id
           and filho.deleted_at is null
       )
    then
      raise exception using
        errcode = '23514',
        message = 'Mova ou arquive os centros filhos antes de arquivar o centro principal.';
    end if;

    if not new.ativo
       and exists (
         with recursive descendentes as (
           select filho.id, filho.ativo
           from f.centro_custo filho
           where filho.tenant_id = new.tenant_id
             and filho.empresa_id = new.empresa_id
             and filho.parent_id = new.id
             and filho.deleted_at is null
           union
           select filho.id, filho.ativo
           from f.centro_custo filho
           join descendentes d on d.id = filho.parent_id
           where filho.tenant_id = new.tenant_id
             and filho.empresa_id = new.empresa_id
             and filho.deleted_at is null
         )
         select 1 from descendentes where ativo limit 1
       )
    then
      raise exception using
        errcode = '23514',
        message = 'Desative ou mova os centros subordinados antes de desativar o centro principal.';
    end if;

    if exists (
      select 1
      from f.regra_rateio_item rri
      join f.regra_rateio rr
        on rr.id = rri.regra_rateio_id
       and rr.tenant_id = rri.tenant_id
      where rri.tenant_id = new.tenant_id
        and rri.centro_custo_id = new.id
        and rri.deleted_at is null
        and rr.empresa_id = new.empresa_id
        and rr.ativo
        and rr.deleted_at is null
    ) then
      raise exception using
        errcode = '23514',
        message = 'Arquive ou altere as regras ativas antes de desativar este centro.';
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_centro_custo_validar_hierarquia
  on f.centro_custo;
create trigger trg_centro_custo_validar_hierarquia
before insert or update on f.centro_custo
for each row
execute function f.trg_centro_custo_validar_hierarquia();

alter table f.regra_rateio enable row level security;
alter table f.regra_rateio_item enable row level security;

drop policy if exists regra_rateio_select on f.regra_rateio;
create policy regra_rateio_select
on f.regra_rateio
for select
to authenticated
using (f.pode_ler_regras_rateio(tenant_id, empresa_id));

drop policy if exists regra_rateio_item_select
  on f.regra_rateio_item;
create policy regra_rateio_item_select
on f.regra_rateio_item
for select
to authenticated
using (
  exists (
    select 1
    from f.regra_rateio rr
    where rr.id = regra_rateio_item.regra_rateio_id
      and rr.tenant_id = regra_rateio_item.tenant_id
      and f.pode_ler_regras_rateio(rr.tenant_id, rr.empresa_id)
  )
);

revoke all on table f.regra_rateio from anon, authenticated;
revoke all on table f.regra_rateio_item from anon, authenticated;
grant select on table f.regra_rateio to authenticated;
grant select on table f.regra_rateio_item to authenticated;
grant select on table f.regra_rateio to service_role;
grant select on table f.regra_rateio_item to service_role;

revoke all on function f.trg_regra_rateio_validar() from public;
revoke all on function f.trg_regra_rateio_item_validar() from public;
revoke all on function f.validar_total_regra_rateio(uuid, uuid)
  from public;
revoke all on function f.trg_validar_total_regra_rateio()
  from public;
revoke all on function f.trg_validar_cabecalho_regra_rateio()
  from public;
revoke all on function f.trg_centro_custo_validar_hierarquia()
  from public;

create or replace function f.listar_regras_rateio(
  p_tenant_id uuid,
  p_empresa_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_resultado jsonb;
begin
  if auth.uid() is not null
     and not f.pode_ler_regras_rateio(p_tenant_id, p_empresa_id)
  then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para consultar regras de rateio desta empresa.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', base.id,
        'motivo_compra_id', base.motivo_compra_id,
        'motivo_codigo', base.motivo_codigo,
        'motivo_nome', base.motivo_nome,
        'ativo', base.ativo,
        'updated_at', base.updated_at,
        'itens', base.itens
      )
      order by base.motivo_codigo, base.motivo_nome, base.id
    ),
    '[]'::jsonb
  )
    into v_resultado
  from (
    select
      rr.id,
      rr.motivo_compra_id,
      mc.codigo as motivo_codigo,
      mc.nome as motivo_nome,
      rr.ativo,
      rr.updated_at,
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', rri.id,
            'plano_contas_id', rri.plano_contas_id,
            'plano_codigo', pc.codigo,
            'plano_nome', pc.nome,
            'centro_custo_id', rri.centro_custo_id,
            'centro_codigo', cc.codigo,
            'centro_nome', cc.nome,
            'percentual', rri.percentual
          )
          order by cc.codigo, pc.codigo, rri.id
        )
        from f.regra_rateio_item rri
        join f.plano_contas pc
          on pc.id = rri.plano_contas_id
         and pc.tenant_id = rri.tenant_id
        join f.centro_custo cc
          on cc.id = rri.centro_custo_id
         and cc.tenant_id = rri.tenant_id
         and cc.empresa_id = rr.empresa_id
        where rri.tenant_id = rr.tenant_id
          and rri.regra_rateio_id = rr.id
          and rri.deleted_at is null
      ), '[]'::jsonb) as itens
    from f.regra_rateio rr
    join f.motivo_compra mc
      on mc.id = rr.motivo_compra_id
     and mc.tenant_id = rr.tenant_id
    where rr.tenant_id = p_tenant_id
      and rr.empresa_id = p_empresa_id
      and rr.deleted_at is null
  ) base;

  return v_resultado;
end;
$$;

create or replace function f.salvar_regra_rateio(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_regra_id uuid,
  p_motivo_compra_id uuid,
  p_ativo boolean,
  p_itens jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_regra_id uuid;
  v_plano_motivo uuid;
  v_item jsonb;
  v_centro_id uuid;
  v_plano_id uuid;
  v_percentual numeric(7,4);
  v_total numeric := 0;
  v_quantidade integer;
  v_distintos integer;
begin
  if auth.uid() is not null
     and not f.pode_escrever_regras_rateio(
       p_tenant_id,
       p_empresa_id
     )
  then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para alterar regras de rateio desta empresa.';
  end if;

  if p_motivo_compra_id is null then
    raise exception using
      errcode = '23502',
      message = 'Regra de rateio: motivo de compra e obrigatorio.';
  end if;

  select mc.plano_contas_id
    into v_plano_motivo
  from f.motivo_compra mc
  join f.plano_contas pc
    on pc.id = mc.plano_contas_id
   and pc.tenant_id = mc.tenant_id
   and pc.tipo = 'ANALITICA'
   and pc.ativo
   and pc.deleted_at is null
  where mc.id = p_motivo_compra_id
    and mc.tenant_id = p_tenant_id
    and mc.ativo
    and mc.deleted_at is null;

  if v_plano_motivo is null then
    raise exception using
      errcode = '23503',
      message = 'Regra de rateio: motivo sem plano analitico ativo.';
  end if;

  if p_itens is null
     or jsonb_typeof(p_itens) <> 'array'
     or jsonb_array_length(p_itens) = 0
  then
    raise exception using
      errcode = '23514',
      message = 'Regra de rateio: informe ao menos um destino.';
  end if;

  if jsonb_array_length(p_itens) > 50 then
    raise exception using
      errcode = '54000',
      message = 'Regra de rateio: limite de 50 destinos excedido.';
  end if;

  select
    count(*)::integer,
    count(distinct nullif(item ->> 'centro_custo_id', ''))::integer,
    coalesce(sum((item ->> 'percentual')::numeric), 0)
    into v_quantidade, v_distintos, v_total
  from jsonb_array_elements(p_itens) item;

  if v_quantidade <> v_distintos then
    raise exception using
      errcode = '23505',
      message = 'Regra de rateio: o mesmo centro nao pode aparecer duas vezes.';
  end if;

  if abs(v_total - 100.0000) > 0.0001 then
    raise exception using
      errcode = '23514',
      message = format(
        'Regra de rateio: os percentuais devem somar 100%% (soma atual: %s%%).',
        round(v_total, 4)
      );
  end if;

  if p_regra_id is null then
    insert into f.regra_rateio (
      tenant_id,
      empresa_id,
      motivo_compra_id,
      ativo
    )
    values (
      p_tenant_id,
      p_empresa_id,
      p_motivo_compra_id,
      coalesce(p_ativo, true)
    )
    returning id into v_regra_id;
  else
    select rr.id
      into v_regra_id
    from f.regra_rateio rr
    where rr.id = p_regra_id
      and rr.tenant_id = p_tenant_id
      and rr.empresa_id = p_empresa_id
      and rr.deleted_at is null
    for update;

    if not found then
      raise exception using
        errcode = 'P0002',
        message = 'Regra de rateio nao encontrada nesta empresa.';
    end if;

    update f.regra_rateio rr
    set
      motivo_compra_id = p_motivo_compra_id,
      ativo = coalesce(p_ativo, true),
      updated_at = now(),
      updated_by = a.fn_current_usuario_id()
    where rr.id = v_regra_id
      and rr.tenant_id = p_tenant_id
      and rr.empresa_id = p_empresa_id;

    update f.regra_rateio_item rri
    set
      deleted_at = now(),
      updated_at = now(),
      updated_by = a.fn_current_usuario_id()
    where rri.tenant_id = p_tenant_id
      and rri.regra_rateio_id = v_regra_id
      and rri.deleted_at is null;
  end if;

  for v_item in
    select value from jsonb_array_elements(p_itens)
  loop
    begin
      v_centro_id := nullif(v_item ->> 'centro_custo_id', '')::uuid;
      v_plano_id := nullif(v_item ->> 'plano_contas_id', '')::uuid;
      v_percentual := (v_item ->> 'percentual')::numeric(7,4);
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception using
          errcode = '22023',
          message = 'Regra de rateio: destino com dados invalidos.';
    end;

    if v_plano_id is distinct from v_plano_motivo then
      raise exception using
        errcode = '23514',
        message = 'Regra de rateio: o plano deve ser o plano definido no motivo.';
    end if;

    if v_centro_id is null
       or v_percentual is null
       or v_percentual <= 0
       or v_percentual > 100
    then
      raise exception using
        errcode = '23514',
        message = 'Regra de rateio: centro e percentual valido sao obrigatorios.';
    end if;

    insert into f.regra_rateio_item (
      tenant_id,
      regra_rateio_id,
      plano_contas_id,
      centro_custo_id,
      percentual
    )
    values (
      p_tenant_id,
      v_regra_id,
      v_plano_id,
      v_centro_id,
      v_percentual
    );
  end loop;

  return jsonb_build_object(
    'id', v_regra_id,
    'motivo_compra_id', p_motivo_compra_id,
    'ativo', coalesce(p_ativo, true),
    'destinos', jsonb_array_length(p_itens)
  );
end;
$$;

create or replace function f.arquivar_regra_rateio(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_regra_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_id uuid;
begin
  if auth.uid() is not null
     and not f.pode_escrever_regras_rateio(
       p_tenant_id,
       p_empresa_id
     )
  then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para arquivar regras desta empresa.';
  end if;

  update f.regra_rateio rr
  set
    ativo = false,
    deleted_at = now(),
    updated_at = now(),
    updated_by = a.fn_current_usuario_id()
  where rr.id = p_regra_id
    and rr.tenant_id = p_tenant_id
    and rr.empresa_id = p_empresa_id
    and rr.deleted_at is null
  returning rr.id into v_id;

  if v_id is null then
    raise exception using
      errcode = 'P0002',
      message = 'Regra de rateio nao encontrada nesta empresa.';
  end if;

  return jsonb_build_object('id', v_id, 'arquivada', true);
end;
$$;

revoke all on function f.listar_regras_rateio(uuid, uuid)
  from public;
revoke all on function f.salvar_regra_rateio(
  uuid, uuid, uuid, uuid, boolean, jsonb
) from public;
revoke all on function f.arquivar_regra_rateio(uuid, uuid, uuid)
  from public;
grant execute on function f.listar_regras_rateio(uuid, uuid)
  to authenticated, service_role;
grant execute on function f.salvar_regra_rateio(
  uuid, uuid, uuid, uuid, boolean, jsonb
) to authenticated, service_role;
grant execute on function f.arquivar_regra_rateio(uuid, uuid, uuid)
  to authenticated, service_role;

create or replace function f.aplicar_regra_rateio_titulo(
  p_tenant_id uuid,
  p_titulo_id uuid,
  p_forcar boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_titulo f.titulo%rowtype;
  v_motivo_id uuid;
  v_os_id integer;
  v_requires_os boolean := false;
  v_regra_id uuid;
  v_total_rateios integer := 0;
  v_explicitos integer := 0;
  v_substituiveis integer := 0;
  v_quantidade_itens integer := 0;
  v_total_percentual numeric := 0;
  v_item record;
  v_indice integer := 0;
  v_acumulado numeric(15,2) := 0;
  v_valor_item numeric(15,2);
begin
  select t.*
    into v_titulo
  from f.titulo t
  where t.id = p_titulo_id
    and t.tenant_id = p_tenant_id
  for update;

  if not found
     or v_titulo.deleted_at is not null
     or v_titulo.status = 'CANCELADO'
     or v_titulo.tipo <> 'AP'
  then
    return jsonb_build_object('status', 'TITULO_INELEGIVEL');
  end if;

  select ta.motivo_compra_id, ta.os_id
    into v_motivo_id, v_os_id
  from f.titulo_aprovacao ta
  where ta.tenant_id = p_tenant_id
    and ta.titulo_id = p_titulo_id
    and ta.deleted_at is null
  order by ta.aprovado_em desc, ta.id desc
  limit 1;

  if v_motivo_id is null then
    v_motivo_id := v_titulo.motivo_compra_id;
  end if;

  if v_motivo_id is null then
    return jsonb_build_object('status', 'MOTIVO_AUSENTE');
  end if;

  select mc.requires_os
    into v_requires_os
  from f.motivo_compra mc
  where mc.id = v_motivo_id
    and mc.tenant_id = p_tenant_id
    and mc.ativo
    and mc.deleted_at is null;

  if not found then
    return jsonb_build_object('status', 'MOTIVO_INVALIDO');
  end if;

  if v_requires_os and v_os_id is null then
    return jsonb_build_object(
      'status', 'OS_OBRIGATORIA_AUSENTE',
      'motivo_compra_id', v_motivo_id
    );
  end if;

  if v_os_id is not null
     and not exists (
       select 1
       from public.ordens_servico os
       where os.id = v_os_id
         and os.tenant_id = p_tenant_id
         and os.empresa_id = v_titulo.empresa_id
     )
  then
    return jsonb_build_object('status', 'OS_INVALIDA');
  end if;

  select rr.id
    into v_regra_id
  from f.regra_rateio rr
  where rr.tenant_id = p_tenant_id
    and rr.empresa_id = v_titulo.empresa_id
    and rr.motivo_compra_id = v_motivo_id
    and rr.ativo
    and rr.deleted_at is null
  limit 1;

  if v_regra_id is null then
    return jsonb_build_object(
      'status', 'SEM_REGRA',
      'motivo_compra_id', v_motivo_id
    );
  end if;

  select count(*)::integer, coalesce(sum(rri.percentual), 0)
    into v_quantidade_itens, v_total_percentual
  from f.regra_rateio_item rri
  where rri.tenant_id = p_tenant_id
    and rri.regra_rateio_id = v_regra_id
    and rri.deleted_at is null;

  if v_quantidade_itens = 0
     or abs(v_total_percentual - 100.0000) > 0.0001
     or exists (
       select 1
       from f.regra_rateio_item rri
       join f.regra_rateio rr
         on rr.id = rri.regra_rateio_id
        and rr.tenant_id = rri.tenant_id
       join f.motivo_compra mc
         on mc.id = rr.motivo_compra_id
        and mc.tenant_id = rr.tenant_id
       left join f.plano_contas pc
         on pc.id = rri.plano_contas_id
        and pc.tenant_id = rri.tenant_id
        and pc.tipo = 'ANALITICA'
        and pc.ativo
        and pc.deleted_at is null
       left join f.centro_custo cc
         on cc.id = rri.centro_custo_id
        and cc.tenant_id = rri.tenant_id
        and cc.empresa_id = rr.empresa_id
        and cc.ativo
        and cc.deleted_at is null
       where rri.tenant_id = p_tenant_id
         and rri.regra_rateio_id = v_regra_id
         and rri.deleted_at is null
         and (
           rri.plano_contas_id is distinct from mc.plano_contas_id
           or pc.id is null
           or cc.id is null
         )
     )
  then
    return jsonb_build_object('status', 'REGRA_INCONSISTENTE');
  end if;

  select
    count(*)::integer,
    count(*) filter (
      where tr.origem_rateio = 'EXPLICITO'
    )::integer,
    count(*) filter (
      where tr.origem_rateio in (
        'AUTOMATICO_REGRA',
        'SISTEMA_FALLBACK'
      )
    )::integer
    into v_total_rateios, v_explicitos, v_substituiveis
  from f.titulo_rateio tr
  where tr.tenant_id = p_tenant_id
    and tr.titulo_id = p_titulo_id
    and tr.deleted_at is null;

  if v_explicitos > 0
     or v_total_rateios <> v_explicitos + v_substituiveis
  then
    return jsonb_build_object(
      'status', 'PRESERVADO_EXPLICITO',
      'rateios', v_total_rateios
    );
  end if;

  if v_total_rateios > 0 and not coalesce(p_forcar, false) then
    return jsonb_build_object(
      'status', 'JA_RATEADO_AUTOMATICAMENTE',
      'rateios', v_total_rateios
    );
  end if;

  if v_substituiveis > 0 then
    update f.titulo_rateio tr
    set
      deleted_at = now(),
      updated_at = now(),
      updated_by = a.fn_current_usuario_id()
    where tr.tenant_id = p_tenant_id
      and tr.titulo_id = p_titulo_id
      and tr.deleted_at is null
      and tr.origem_rateio in (
        'AUTOMATICO_REGRA',
        'SISTEMA_FALLBACK'
      );
  end if;

  for v_item in
    select
      rri.id,
      rri.plano_contas_id,
      rri.centro_custo_id,
      rri.percentual,
      row_number() over (
        order by rri.centro_custo_id, rri.id
      ) as numero
    from f.regra_rateio_item rri
    where rri.tenant_id = p_tenant_id
      and rri.regra_rateio_id = v_regra_id
      and rri.deleted_at is null
    order by rri.centro_custo_id, rri.id
  loop
    v_indice := v_indice + 1;
    if v_indice = v_quantidade_itens then
      v_valor_item := round(
        coalesce(v_titulo.valor_total, 0) - v_acumulado,
        2
      );
    else
      v_valor_item := round(
        coalesce(v_titulo.valor_total, 0)
          * v_item.percentual / 100.0,
        2
      );
      v_acumulado := v_acumulado + v_valor_item;
    end if;

    insert into f.titulo_rateio (
      tenant_id,
      titulo_id,
      plano_contas_id,
      centro_custo_id,
      os_id,
      percentual,
      valor,
      origem_rateio,
      regra_rateio_id,
      regra_item_id
    )
    values (
      p_tenant_id,
      p_titulo_id,
      v_item.plano_contas_id,
      v_item.centro_custo_id,
      v_os_id,
      v_item.percentual,
      v_valor_item,
      'AUTOMATICO_REGRA',
      v_regra_id,
      v_item.id
    );
  end loop;

  return jsonb_build_object(
    'status', 'APLICADO',
    'regra_rateio_id', v_regra_id,
    'motivo_compra_id', v_motivo_id,
    'destinos', v_quantidade_itens
  );
end;
$$;

create or replace function f.garantir_rateio_fallback_titulo(
  p_tenant_id uuid,
  p_titulo_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_titulo f.titulo%rowtype;
  v_motivo_id uuid;
  v_os_id integer;
  v_requires_os boolean := false;
  v_plano_id uuid;
  v_fallback_id uuid;
  v_quantidade integer;
begin
  select t.*
    into v_titulo
  from f.titulo t
  where t.id = p_titulo_id
    and t.tenant_id = p_tenant_id
  for update;

  if not found
     or v_titulo.deleted_at is not null
     or v_titulo.status = 'CANCELADO'
     or v_titulo.tipo <> 'AP'
  then
    return jsonb_build_object('status', 'TITULO_INELEGIVEL');
  end if;

  if exists (
    select 1
    from f.titulo_rateio tr
    where tr.tenant_id = p_tenant_id
      and tr.titulo_id = p_titulo_id
      and tr.deleted_at is null
      and tr.origem_rateio <> 'SISTEMA_FALLBACK'
  ) then
    return jsonb_build_object('status', 'RATEIO_PRESERVADO');
  end if;

  select ta.motivo_compra_id, ta.os_id
    into v_motivo_id, v_os_id
  from f.titulo_aprovacao ta
  where ta.tenant_id = p_tenant_id
    and ta.titulo_id = p_titulo_id
    and ta.deleted_at is null
  order by ta.aprovado_em desc, ta.id desc
  limit 1;

  if v_motivo_id is null then
    v_motivo_id := v_titulo.motivo_compra_id;
  end if;

  if v_motivo_id is not null then
    select mc.plano_contas_id, mc.requires_os
      into v_plano_id, v_requires_os
    from f.motivo_compra mc
    where mc.id = v_motivo_id
      and mc.tenant_id = p_tenant_id
      and mc.ativo
      and mc.deleted_at is null;

    if v_plano_id is not null
       and not exists (
         select 1
         from f.plano_contas pc
         where pc.id = v_plano_id
           and pc.tenant_id = p_tenant_id
           and pc.tipo = 'ANALITICA'
           and pc.ativo
           and pc.deleted_at is null
       )
    then
      v_plano_id := null;
    end if;
  end if;

  if v_requires_os and v_os_id is null then
    return jsonb_build_object(
      'status', 'OS_OBRIGATORIA_AUSENTE'
    );
  end if;

  if v_os_id is not null
     and not exists (
       select 1
       from public.ordens_servico os
       where os.id = v_os_id
         and os.tenant_id = p_tenant_id
         and os.empresa_id = v_titulo.empresa_id
     )
  then
    return jsonb_build_object('status', 'OS_INVALIDA');
  end if;

  if v_plano_id is null then
    select pc.id
      into v_plano_id
    from f.plano_contas pc
    where pc.tenant_id = p_tenant_id
      and pc.codigo = 'DESP_GERAL'
      and pc.tipo = 'ANALITICA'
      and pc.ativo
      and pc.deleted_at is null
    limit 1;
  end if;

  if v_plano_id is null then
    return jsonb_build_object('status', 'PLANO_FALLBACK_AUSENTE');
  end if;

  select count(*)::integer
    into v_quantidade
  from f.titulo_rateio tr
  where tr.tenant_id = p_tenant_id
    and tr.titulo_id = p_titulo_id
    and tr.deleted_at is null
    and tr.origem_rateio = 'SISTEMA_FALLBACK';

  if v_quantidade > 1 then
    return jsonb_build_object('status', 'FALLBACK_INCONSISTENTE');
  elsif v_quantidade = 1 then
    select tr.id
      into v_fallback_id
    from f.titulo_rateio tr
    where tr.tenant_id = p_tenant_id
      and tr.titulo_id = p_titulo_id
      and tr.deleted_at is null
      and tr.origem_rateio = 'SISTEMA_FALLBACK'
    limit 1;

    update f.titulo_rateio tr
    set
      plano_contas_id = v_plano_id,
      centro_custo_id = null,
      os_id = v_os_id,
      percentual = 100.0000,
      valor = coalesce(v_titulo.valor_total, 0),
      updated_at = now(),
      updated_by = a.fn_current_usuario_id()
    where tr.id = v_fallback_id
      and tr.tenant_id = p_tenant_id
      and tr.titulo_id = p_titulo_id;
  else
    insert into f.titulo_rateio (
      tenant_id,
      titulo_id,
      plano_contas_id,
      centro_custo_id,
      os_id,
      percentual,
      valor,
      origem_rateio
    )
    values (
      p_tenant_id,
      p_titulo_id,
      v_plano_id,
      null,
      v_os_id,
      100.0000,
      coalesce(v_titulo.valor_total, 0),
      'SISTEMA_FALLBACK'
    );
  end if;

  return jsonb_build_object(
    'status', 'FALLBACK_APLICADO',
    'plano_contas_id', v_plano_id
  );
end;
$$;

create or replace function f.trg_titulo_ap_auto_rateio_por_motivo()
returns trigger
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_resultado jsonb;
begin
  v_resultado := f.aplicar_regra_rateio_titulo(
    new.tenant_id,
    new.id,
    false
  );

  if v_resultado ->> 'status' in (
    'MOTIVO_AUSENTE',
    'MOTIVO_INVALIDO',
    'SEM_REGRA'
  ) then
    perform f.garantir_rateio_fallback_titulo(
      new.tenant_id,
      new.id
    );
  end if;

  return new;
end;
$$;

create or replace function f.trg_titulo_reaplicar_regra_rateio()
returns trigger
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_resultado jsonb;
begin
  if new.tipo <> 'AP'
     or new.deleted_at is not null
     or new.status = 'CANCELADO'
  then
    return new;
  end if;

  v_resultado := f.aplicar_regra_rateio_titulo(
    new.tenant_id,
    new.id,
    true
  );

  if v_resultado ->> 'status' in (
    'MOTIVO_AUSENTE',
    'MOTIVO_INVALIDO',
    'SEM_REGRA'
  ) then
    perform f.garantir_rateio_fallback_titulo(
      new.tenant_id,
      new.id
    );
  end if;
  return new;
end;
$$;

create or replace function f.trg_titulo_aprovacao_validar_escopo()
returns trigger
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_empresa_id uuid;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  select t.empresa_id
    into v_empresa_id
  from f.titulo t
  where t.id = new.titulo_id
    and t.tenant_id = new.tenant_id
    and t.tipo = 'AP'
    and t.deleted_at is null;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'Aprovacao: titulo AP invalido ou de outro tenant.';
  end if;

  if not exists (
    select 1
    from f.motivo_compra mc
    where mc.id = new.motivo_compra_id
      and mc.tenant_id = new.tenant_id
      and mc.ativo
      and mc.deleted_at is null
  ) then
    raise exception using
      errcode = '23503',
      message = 'Aprovacao: motivo invalido ou de outro tenant.';
  end if;

  if new.os_id is not null
     and not exists (
       select 1
       from public.ordens_servico os
       where os.id = new.os_id
         and os.tenant_id = new.tenant_id
         and os.empresa_id = v_empresa_id
     )
  then
    raise exception using
      errcode = '23503',
      message = 'Aprovacao: OS invalida ou de outra empresa.';
  end if;

  if new.os_id is null
     and exists (
       select 1
       from f.motivo_compra mc
       where mc.id = new.motivo_compra_id
         and mc.tenant_id = new.tenant_id
         and mc.requires_os
         and mc.ativo
         and mc.deleted_at is null
     )
  then
    raise exception using
      errcode = '23514',
      message = 'Aprovacao: o motivo selecionado exige uma OS.';
  end if;

  return new;
end;
$$;

create or replace function f.trg_titulo_aprovacao_aplicar_regra()
returns trigger
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_resultado jsonb;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  v_resultado := f.aplicar_regra_rateio_titulo(
    new.tenant_id,
    new.titulo_id,
    true
  );

  if v_resultado ->> 'status' in (
    'MOTIVO_AUSENTE',
    'MOTIVO_INVALIDO',
    'SEM_REGRA'
  ) then
    perform f.garantir_rateio_fallback_titulo(
      new.tenant_id,
      new.titulo_id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists tg_titulo_ap_auto_rateio_por_motivo
  on f.titulo;
create constraint trigger tg_titulo_ap_auto_rateio_por_motivo
after insert on f.titulo
deferrable initially deferred
for each row
execute function f.trg_titulo_ap_auto_rateio_por_motivo();

drop trigger if exists trg_titulo_reaplicar_regra_rateio
  on f.titulo;
create trigger trg_titulo_reaplicar_regra_rateio
after update of valor_total, motivo_compra_id
on f.titulo
for each row
when (
  old.valor_total is distinct from new.valor_total
  or old.motivo_compra_id is distinct from new.motivo_compra_id
)
execute function f.trg_titulo_reaplicar_regra_rateio();

drop trigger if exists trg_titulo_aprovacao_validar_escopo
  on f.titulo_aprovacao;
create trigger trg_titulo_aprovacao_validar_escopo
before insert or update on f.titulo_aprovacao
for each row
execute function f.trg_titulo_aprovacao_validar_escopo();

drop trigger if exists trg_titulo_aprovacao_aplicar_regra
  on f.titulo_aprovacao;
create trigger trg_titulo_aprovacao_aplicar_regra
after insert or update of motivo_compra_id, os_id, deleted_at
on f.titulo_aprovacao
for each row
execute function f.trg_titulo_aprovacao_aplicar_regra();

revoke all on function f.aplicar_regra_rateio_titulo(
  uuid, uuid, boolean
) from public;
revoke all on function f.garantir_rateio_fallback_titulo(
  uuid, uuid
) from public;
revoke all on function f.trg_titulo_ap_auto_rateio_por_motivo()
  from public;
revoke all on function f.trg_titulo_reaplicar_regra_rateio()
  from public;
revoke all on function f.trg_titulo_aprovacao_validar_escopo()
  from public;
revoke all on function f.trg_titulo_aprovacao_aplicar_regra()
  from public;

create or replace function f.aplicar_regras_rateio_pendentes(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_limite integer default 500
)
returns jsonb
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_limite integer := greatest(1, least(coalesce(p_limite, 500), 2000));
  v_total_pendentes integer := 0;
  v_analisados integer := 0;
  v_rateios_criados integer := 0;
  v_centros_preenchidos integer := 0;
  v_ignorados integer := 0;
  v_restantes integer := 0;
  v_titulo record;
  v_rateio record;
  v_item record;
  v_count_rateios integer;
  v_count_itens integer;
  v_resultado jsonb;
  v_erros jsonb := '[]'::jsonb;
begin
  if auth.uid() is not null
     and not f.pode_escrever_regras_rateio(
       p_tenant_id,
       p_empresa_id
     )
  then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para aplicar regras nesta empresa.';
  end if;

  with candidatos as (
    select t.id
    from f.titulo t
    left join lateral (
      select ta.motivo_compra_id, ta.os_id
      from f.titulo_aprovacao ta
      where ta.tenant_id = t.tenant_id
        and ta.titulo_id = t.id
        and ta.deleted_at is null
      order by ta.aprovado_em desc, ta.id desc
      limit 1
    ) aprovacao on true
    join f.motivo_compra mc
      on mc.id = coalesce(
        aprovacao.motivo_compra_id,
        t.motivo_compra_id
      )
     and mc.tenant_id = t.tenant_id
     and mc.ativo
     and mc.deleted_at is null
    join f.regra_rateio rr
      on rr.tenant_id = t.tenant_id
     and rr.empresa_id = t.empresa_id
     and rr.motivo_compra_id = mc.id
     and rr.ativo
     and rr.deleted_at is null
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.tipo = 'AP'
      and t.status <> 'CANCELADO'
      and t.deleted_at is null
      and (not mc.requires_os or aprovacao.os_id is not null)
      and (
        aprovacao.os_id is null
        or exists (
          select 1
          from public.ordens_servico os
          where os.id = aprovacao.os_id
            and os.tenant_id = t.tenant_id
            and os.empresa_id = t.empresa_id
        )
      )
      and (
        not exists (
          select 1
          from f.titulo_rateio tr
          where tr.tenant_id = t.tenant_id
            and tr.titulo_id = t.id
            and tr.deleted_at is null
        )
        or (
          (
            select count(*)
            from f.titulo_rateio tr
            where tr.tenant_id = t.tenant_id
              and tr.titulo_id = t.id
              and tr.deleted_at is null
          ) = 1
          and exists (
            select 1
            from f.titulo_rateio tr
            join f.regra_rateio_item rri
              on rri.tenant_id = rr.tenant_id
             and rri.regra_rateio_id = rr.id
             and rri.plano_contas_id = tr.plano_contas_id
             and rri.deleted_at is null
            where tr.tenant_id = t.tenant_id
              and tr.titulo_id = t.id
              and tr.deleted_at is null
              and tr.centro_custo_id is null
              and abs(coalesce(tr.percentual, 0) - 100) <= 0.0001
              and (
                select count(*)
                from f.regra_rateio_item rri_count
                where rri_count.tenant_id = rr.tenant_id
                  and rri_count.regra_rateio_id = rr.id
                  and rri_count.deleted_at is null
              ) = 1
          )
        )
      )
  )
  select count(*)::integer
    into v_total_pendentes
  from candidatos;

  for v_titulo in
    select
      t.id,
      rr.id as regra_rateio_id,
      mc.id as motivo_compra_id,
      aprovacao.os_id
    from f.titulo t
    left join lateral (
      select ta.motivo_compra_id, ta.os_id
      from f.titulo_aprovacao ta
      where ta.tenant_id = t.tenant_id
        and ta.titulo_id = t.id
        and ta.deleted_at is null
      order by ta.aprovado_em desc, ta.id desc
      limit 1
    ) aprovacao on true
    join f.motivo_compra mc
      on mc.id = coalesce(
        aprovacao.motivo_compra_id,
        t.motivo_compra_id
      )
     and mc.tenant_id = t.tenant_id
     and mc.ativo
     and mc.deleted_at is null
    join f.regra_rateio rr
      on rr.tenant_id = t.tenant_id
     and rr.empresa_id = t.empresa_id
     and rr.motivo_compra_id = mc.id
     and rr.ativo
     and rr.deleted_at is null
    where t.tenant_id = p_tenant_id
      and t.empresa_id = p_empresa_id
      and t.tipo = 'AP'
      and t.status <> 'CANCELADO'
      and t.deleted_at is null
      and (not mc.requires_os or aprovacao.os_id is not null)
      and (
        aprovacao.os_id is null
        or exists (
          select 1
          from public.ordens_servico os
          where os.id = aprovacao.os_id
            and os.tenant_id = t.tenant_id
            and os.empresa_id = t.empresa_id
        )
      )
      and (
        not exists (
          select 1
          from f.titulo_rateio tr
          where tr.tenant_id = t.tenant_id
            and tr.titulo_id = t.id
            and tr.deleted_at is null
        )
        or (
          (
            select count(*)
            from f.titulo_rateio tr
            where tr.tenant_id = t.tenant_id
              and tr.titulo_id = t.id
              and tr.deleted_at is null
          ) = 1
          and exists (
            select 1
            from f.titulo_rateio tr
            join f.regra_rateio_item rri
              on rri.tenant_id = rr.tenant_id
             and rri.regra_rateio_id = rr.id
             and rri.plano_contas_id = tr.plano_contas_id
             and rri.deleted_at is null
            where tr.tenant_id = t.tenant_id
              and tr.titulo_id = t.id
              and tr.deleted_at is null
              and tr.centro_custo_id is null
              and abs(coalesce(tr.percentual, 0) - 100) <= 0.0001
              and (
                select count(*)
                from f.regra_rateio_item rri_count
                where rri_count.tenant_id = rr.tenant_id
                  and rri_count.regra_rateio_id = rr.id
                  and rri_count.deleted_at is null
              ) = 1
          )
        )
      )
    order by t.created_at, t.id
    limit v_limite
  loop
    v_analisados := v_analisados + 1;
    begin
      select count(*)::integer
        into v_count_rateios
      from f.titulo_rateio tr
      where tr.tenant_id = p_tenant_id
        and tr.titulo_id = v_titulo.id
        and tr.deleted_at is null;

      if v_count_rateios = 0 then
        v_resultado := f.aplicar_regra_rateio_titulo(
          p_tenant_id,
          v_titulo.id,
          false
        );
        if v_resultado ->> 'status' = 'APLICADO' then
          v_rateios_criados := v_rateios_criados + 1;
        else
          v_ignorados := v_ignorados + 1;
        end if;
      elsif v_count_rateios = 1 then
        select
          tr.id,
          tr.plano_contas_id,
          tr.centro_custo_id,
          tr.percentual
          into v_rateio
        from f.titulo_rateio tr
        where tr.tenant_id = p_tenant_id
          and tr.titulo_id = v_titulo.id
          and tr.deleted_at is null
        for update;

        select count(*)::integer
          into v_count_itens
        from f.regra_rateio_item rri
        where rri.tenant_id = p_tenant_id
          and rri.regra_rateio_id = v_titulo.regra_rateio_id
          and rri.deleted_at is null;

        if v_count_itens = 1 then
          select
            rri.plano_contas_id,
            rri.centro_custo_id
            into v_item
          from f.regra_rateio_item rri
          where rri.tenant_id = p_tenant_id
            and rri.regra_rateio_id = v_titulo.regra_rateio_id
            and rri.deleted_at is null
          limit 1;
        end if;

        if v_count_itens = 1
           and v_rateio.centro_custo_id is null
           and abs(coalesce(v_rateio.percentual, 0) - 100) <= 0.0001
           and v_rateio.plano_contas_id = v_item.plano_contas_id
        then
          update f.titulo_rateio tr
          set
            centro_custo_id = v_item.centro_custo_id,
            updated_at = now(),
            updated_by = a.fn_current_usuario_id()
          where tr.id = v_rateio.id
            and tr.tenant_id = p_tenant_id
            and tr.titulo_id = v_titulo.id
            and tr.deleted_at is null
            and tr.centro_custo_id is null;

          if found then
            v_centros_preenchidos :=
              v_centros_preenchidos + 1;
          else
            v_ignorados := v_ignorados + 1;
          end if;
        else
          v_ignorados := v_ignorados + 1;
        end if;
      else
        v_ignorados := v_ignorados + 1;
      end if;
    exception
      when others then
        v_ignorados := v_ignorados + 1;
        if jsonb_array_length(v_erros) < 20 then
          v_erros := v_erros || jsonb_build_array(
            jsonb_build_object(
              'titulo_id', v_titulo.id,
              'erro', sqlerrm
            )
          );
        end if;
    end;
  end loop;

  v_restantes := greatest(
    0,
    v_total_pendentes
      - v_rateios_criados
      - v_centros_preenchidos
  );

  return jsonb_build_object(
    'titulos_analisados', v_analisados,
    'rateios_criados', v_rateios_criados,
    'centros_preenchidos', v_centros_preenchidos,
    'ignorados', v_ignorados,
    'limite', v_limite,
    'truncado', v_restantes > 0,
    'pendentes_restantes', v_restantes,
    'erros', v_erros
  );
end;
$$;

revoke all on function f.aplicar_regras_rateio_pendentes(
  uuid, uuid, integer
) from public;
grant execute on function f.aplicar_regras_rateio_pendentes(
  uuid, uuid, integer
) to authenticated, service_role;

comment on function f.aplicar_regras_rateio_pendentes(
  uuid, uuid, integer
) is
  'Aplica regras sem sobrescrever rateio existente; no historico, preenche apenas centro nulo em linha unica de 100% e plano identico.';
