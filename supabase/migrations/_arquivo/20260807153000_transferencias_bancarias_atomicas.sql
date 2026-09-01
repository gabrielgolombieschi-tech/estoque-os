-- Transferencias bancarias com identidade propria e gravacao atomica.
-- Mantem as duas pernas no extrato para preservar saldos e conciliacao existentes.

create table if not exists f.transferencia_bancaria (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  empresa_id uuid not null references c.empresa(id),
  conta_origem_id uuid not null references f.conta_bancaria(id),
  conta_destino_id uuid not null references f.conta_bancaria(id),
  data_movimento date not null,
  valor numeric(15,2) not null,
  descricao text not null,
  status text not null default 'EFETIVADA',
  linha_saida_id uuid references f.extrato_bancario_linha(id),
  linha_entrada_id uuid references f.extrato_bancario_linha(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default a.fn_current_usuario_id(),
  updated_by uuid,
  deleted_at timestamptz,
  constraint ck_transferencia_bancaria_valor check (valor > 0),
  constraint ck_transferencia_bancaria_contas check (conta_origem_id <> conta_destino_id),
  constraint ck_transferencia_bancaria_status check (status in ('EFETIVADA', 'ESTORNADA'))
);

create index if not exists ix_transferencia_bancaria_empresa_data
  on f.transferencia_bancaria (tenant_id, empresa_id, data_movimento desc, created_at desc)
  where deleted_at is null;

create index if not exists ix_transferencia_bancaria_origem
  on f.transferencia_bancaria (tenant_id, empresa_id, conta_origem_id, data_movimento desc)
  where deleted_at is null;

create index if not exists ix_transferencia_bancaria_destino
  on f.transferencia_bancaria (tenant_id, empresa_id, conta_destino_id, data_movimento desc)
  where deleted_at is null;

comment on table f.transferencia_bancaria is
  'Cabecalho auditavel da transferencia entre contas bancarias da mesma empresa.';
comment on column f.transferencia_bancaria.linha_saida_id is
  'Linha negativa criada no extrato manual da conta de origem.';
comment on column f.transferencia_bancaria.linha_entrada_id is
  'Linha positiva criada no extrato manual da conta de destino.';

alter table f.transferencia_bancaria enable row level security;

drop policy if exists transferencia_bancaria_select on f.transferencia_bancaria;
create policy transferencia_bancaria_select
on f.transferencia_bancaria
for select
to authenticated
using (
  tenant_id = public.current_tenant_id()
  and empresa_id = public.current_empresa_id()
  and f.has_finance_access(tenant_id, empresa_id)
);

revoke all on table f.transferencia_bancaria from public, anon, authenticated;
grant select on table f.transferencia_bancaria to authenticated, service_role;

-- Preserva no novo historico os eventos gerados pela tela anterior.
with eventos_validos as (
  select
    e.id,
    e.tenant_id,
    e.empresa_id,
    case
      when coalesce(e.payload->>'origem_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (e.payload->>'origem_id')::uuid
    end as conta_origem_id,
    case
      when coalesce(e.payload->>'destino_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (e.payload->>'destino_id')::uuid
    end as conta_destino_id,
    case
      when coalesce(e.payload->>'data_movimento', '') ~ '^\d{4}-\d{2}-\d{2}$'
        then (e.payload->>'data_movimento')::date
    end as data_movimento,
    case
      when coalesce(e.payload->>'valor', '') ~ '^\d+(\.\d+)?$'
        then (e.payload->>'valor')::numeric(15,2)
    end as valor,
    coalesce(nullif(btrim(e.payload->>'descricao'), ''), 'Transferencia entre contas') as descricao,
    e.created_at,
    e.created_by
  from f.evento_financeiro e
  where e.evento = 'TRANSFERENCIA'
)
insert into f.transferencia_bancaria (
  id,
  tenant_id,
  empresa_id,
  conta_origem_id,
  conta_destino_id,
  data_movimento,
  valor,
  descricao,
  status,
  created_at,
  updated_at,
  created_by
)
select
  ev.id,
  ev.tenant_id,
  ev.empresa_id,
  ev.conta_origem_id,
  ev.conta_destino_id,
  ev.data_movimento,
  ev.valor,
  ev.descricao,
  'EFETIVADA',
  ev.created_at,
  ev.created_at,
  ev.created_by
from eventos_validos ev
join f.conta_bancaria origem
  on origem.id = ev.conta_origem_id
 and origem.tenant_id = ev.tenant_id
 and origem.empresa_id = ev.empresa_id
join f.conta_bancaria destino
  on destino.id = ev.conta_destino_id
 and destino.tenant_id = ev.tenant_id
 and destino.empresa_id = ev.empresa_id
where ev.conta_origem_id is not null
  and ev.conta_destino_id is not null
  and ev.conta_origem_id <> ev.conta_destino_id
  and ev.data_movimento is not null
  and ev.valor > 0
on conflict (id) do nothing;

create or replace function f.registrar_transferencia_bancaria(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_conta_origem_id uuid,
  p_conta_destino_id uuid,
  p_data_movimento date,
  p_valor numeric,
  p_descricao text default null
)
returns table (
  transferencia_id uuid,
  linha_saida_id uuid,
  linha_entrada_id uuid
)
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_transferencia_id uuid := gen_random_uuid();
  v_extrato_origem_id uuid;
  v_extrato_destino_id uuid;
  v_linha_saida_id uuid;
  v_linha_entrada_id uuid;
  v_origem f.conta_bancaria%rowtype;
  v_destino f.conta_bancaria%rowtype;
  v_descricao text := coalesce(nullif(btrim(p_descricao), ''), 'Transferencia entre contas');
  v_referencia text;
begin
  if auth.uid() is null then
    raise exception 'Usuario nao autenticado';
  end if;

  if p_tenant_id is null
     or p_tenant_id is distinct from public.current_tenant_id() then
    raise exception 'Tenant invalido para a sessao atual';
  end if;

  if p_empresa_id is null
     or p_empresa_id is distinct from public.current_empresa_id()
     or not f.has_finance_access(p_tenant_id, p_empresa_id) then
    raise exception 'Sem acesso financeiro a empresa selecionada';
  end if;

  if not (
    public.has_permission('financeiro.write')
    or public.has_permission('admin.manage_users')
    or public.has_permission('admin.all')
  ) then
    raise exception 'Sem permissao para registrar transferencias';
  end if;

  if p_conta_origem_id is null or p_conta_destino_id is null then
    raise exception 'Informe as contas de origem e destino';
  end if;

  if p_conta_origem_id = p_conta_destino_id then
    raise exception 'As contas de origem e destino devem ser diferentes';
  end if;

  if p_data_movimento is null then
    raise exception 'Informe a data da transferencia';
  end if;

  if p_valor is null or round(p_valor, 2) <= 0 then
    raise exception 'O valor da transferencia deve ser maior que zero';
  end if;

  if length(v_descricao) > 500 then
    raise exception 'A descricao deve ter no maximo 500 caracteres';
  end if;

  -- Ordem deterministica evita deadlock em transferencias simultaneas e inversas.
  perform cb.id
  from f.conta_bancaria cb
  where cb.id in (p_conta_origem_id, p_conta_destino_id)
    and cb.tenant_id = p_tenant_id
    and cb.empresa_id = p_empresa_id
    and cb.ativo = true
    and cb.deleted_at is null
  order by cb.id
  for update;

  select cb.*
    into v_origem
  from f.conta_bancaria cb
  where cb.id = p_conta_origem_id
    and cb.tenant_id = p_tenant_id
    and cb.empresa_id = p_empresa_id
    and cb.ativo = true
    and cb.deleted_at is null;

  if not found then
    raise exception 'Conta de origem nao encontrada ou inativa';
  end if;

  select cb.*
    into v_destino
  from f.conta_bancaria cb
  where cb.id = p_conta_destino_id
    and cb.tenant_id = p_tenant_id
    and cb.empresa_id = p_empresa_id
    and cb.ativo = true
    and cb.deleted_at is null;

  if not found then
    raise exception 'Conta de destino nao encontrada ou inativa';
  end if;

  v_referencia := 'TRANSFERENCIA:' || v_transferencia_id::text;

  insert into f.extrato_bancario (
    tenant_id,
    empresa_id,
    conta_bancaria_id,
    fonte,
    referencia,
    periodo_inicio,
    periodo_fim,
    observacoes
  ) values (
    p_tenant_id,
    p_empresa_id,
    p_conta_origem_id,
    'MANUAL',
    v_referencia,
    p_data_movimento,
    p_data_movimento,
    'Saida de transferencia bancaria registrada pelo sistema.'
  ) returning id into v_extrato_origem_id;

  insert into f.extrato_bancario (
    tenant_id,
    empresa_id,
    conta_bancaria_id,
    fonte,
    referencia,
    periodo_inicio,
    periodo_fim,
    observacoes
  ) values (
    p_tenant_id,
    p_empresa_id,
    p_conta_destino_id,
    'MANUAL',
    v_referencia,
    p_data_movimento,
    p_data_movimento,
    'Entrada de transferencia bancaria registrada pelo sistema.'
  ) returning id into v_extrato_destino_id;

  insert into f.extrato_bancario_linha (
    tenant_id,
    extrato_bancario_id,
    conta_bancaria_id,
    data_movimento,
    descricao,
    documento,
    fit_id,
    valor,
    status,
    observacoes
  ) values (
    p_tenant_id,
    v_extrato_origem_id,
    p_conta_origem_id,
    p_data_movimento,
    v_descricao || ' - SAIDA PARA ' || v_destino.codigo || ' ' || v_destino.nome,
    'TRANSFERENCIA',
    v_referencia || ':SAIDA',
    -round(p_valor, 2),
    'PENDENTE',
    'Transferencia ' || v_transferencia_id::text
  ) returning id into v_linha_saida_id;

  insert into f.extrato_bancario_linha (
    tenant_id,
    extrato_bancario_id,
    conta_bancaria_id,
    data_movimento,
    descricao,
    documento,
    fit_id,
    valor,
    status,
    observacoes
  ) values (
    p_tenant_id,
    v_extrato_destino_id,
    p_conta_destino_id,
    p_data_movimento,
    v_descricao || ' - ENTRADA DE ' || v_origem.codigo || ' ' || v_origem.nome,
    'TRANSFERENCIA',
    v_referencia || ':ENTRADA',
    round(p_valor, 2),
    'PENDENTE',
    'Transferencia ' || v_transferencia_id::text
  ) returning id into v_linha_entrada_id;

  insert into f.transferencia_bancaria (
    id,
    tenant_id,
    empresa_id,
    conta_origem_id,
    conta_destino_id,
    data_movimento,
    valor,
    descricao,
    status,
    linha_saida_id,
    linha_entrada_id
  ) values (
    v_transferencia_id,
    p_tenant_id,
    p_empresa_id,
    p_conta_origem_id,
    p_conta_destino_id,
    p_data_movimento,
    round(p_valor, 2),
    v_descricao,
    'EFETIVADA',
    v_linha_saida_id,
    v_linha_entrada_id
  );

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
    'TRANSFERENCIA_BANCARIA_REGISTRADA',
    'f.transferencia_bancaria',
    v_transferencia_id,
    jsonb_build_object(
      'data_movimento', p_data_movimento,
      'valor', round(p_valor, 2),
      'descricao', v_descricao,
      'origem_id', p_conta_origem_id,
      'origem_codigo', v_origem.codigo,
      'origem_nome', v_origem.nome,
      'destino_id', p_conta_destino_id,
      'destino_codigo', v_destino.codigo,
      'destino_nome', v_destino.nome,
      'linha_saida_id', v_linha_saida_id,
      'linha_entrada_id', v_linha_entrada_id
    )
  );

  return query
  select v_transferencia_id, v_linha_saida_id, v_linha_entrada_id;
end;
$$;

create or replace function f.listar_transferencias_bancarias(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_data_inicio date default null,
  p_data_fim date default null,
  p_conta_bancaria_id uuid default null,
  p_limite integer default 500
)
returns table (
  id uuid,
  data_movimento date,
  valor numeric,
  descricao text,
  status text,
  conta_origem_id uuid,
  origem_codigo text,
  origem_nome text,
  origem_banco text,
  conta_destino_id uuid,
  destino_codigo text,
  destino_nome text,
  destino_banco text,
  linha_saida_status text,
  linha_entrada_status text,
  created_at timestamptz
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

  if p_empresa_id is null
     or p_empresa_id is distinct from public.current_empresa_id()
     or not f.has_finance_access(p_tenant_id, p_empresa_id) then
    raise exception 'Sem acesso financeiro a empresa selecionada';
  end if;

  if p_data_inicio is not null
     and p_data_fim is not null
     and p_data_inicio > p_data_fim then
    raise exception 'Periodo invalido';
  end if;

  return query
  select
    tb.id,
    tb.data_movimento,
    tb.valor,
    tb.descricao,
    tb.status,
    tb.conta_origem_id,
    origem.codigo,
    origem.nome,
    origem.banco,
    tb.conta_destino_id,
    destino.codigo,
    destino.nome,
    destino.banco,
    saida.status,
    entrada.status,
    tb.created_at
  from f.transferencia_bancaria tb
  join f.conta_bancaria origem
    on origem.id = tb.conta_origem_id
   and origem.tenant_id = tb.tenant_id
   and origem.empresa_id = tb.empresa_id
  join f.conta_bancaria destino
    on destino.id = tb.conta_destino_id
   and destino.tenant_id = tb.tenant_id
   and destino.empresa_id = tb.empresa_id
  left join f.extrato_bancario_linha saida
    on saida.id = tb.linha_saida_id
   and saida.tenant_id = tb.tenant_id
  left join f.extrato_bancario_linha entrada
    on entrada.id = tb.linha_entrada_id
   and entrada.tenant_id = tb.tenant_id
  where tb.tenant_id = p_tenant_id
    and tb.empresa_id = p_empresa_id
    and tb.deleted_at is null
    and (p_data_inicio is null or tb.data_movimento >= p_data_inicio)
    and (p_data_fim is null or tb.data_movimento <= p_data_fim)
    and (
      p_conta_bancaria_id is null
      or tb.conta_origem_id = p_conta_bancaria_id
      or tb.conta_destino_id = p_conta_bancaria_id
    )
  order by tb.data_movimento desc, tb.created_at desc
  limit least(greatest(coalesce(p_limite, 500), 1), 1000);
end;
$$;

revoke all on function f.registrar_transferencia_bancaria(uuid, uuid, uuid, uuid, date, numeric, text)
  from public, anon;
grant execute on function f.registrar_transferencia_bancaria(uuid, uuid, uuid, uuid, date, numeric, text)
  to authenticated, service_role;

revoke all on function f.listar_transferencias_bancarias(uuid, uuid, date, date, uuid, integer)
  from public, anon;
grant execute on function f.listar_transferencias_bancarias(uuid, uuid, date, date, uuid, integer)
  to authenticated, service_role;

comment on function f.registrar_transferencia_bancaria(uuid, uuid, uuid, uuid, date, numeric, text) is
  'Registra atomicamente a saida, a entrada, o cabecalho e a auditoria da transferencia.';
comment on function f.listar_transferencias_bancarias(uuid, uuid, date, date, uuid, integer) is
  'Lista transferencias bancarias da empresa selecionada com contas e status de conciliacao.';
