alter table f.titulo
  add column if not exists os_id integer references public.ordens_servico(id);

comment on column f.titulo.os_id is
  'OS vinculada opcionalmente a um lançamento manual (AP ou AR) sem documento fiscal.';

create or replace function f.criar_titulo_ar_manual_v1(
  p_cliente_id integer,
  p_descricao text,
  p_emissao_date date,
  p_vencimento_date date,
  p_valor numeric,
  p_os_id integer default null,
  p_change_reason text default null
)
returns table (titulo_id uuid)
language plpgsql
security definer
set search_path to 'f', 'public', 'a', 'c'
set row_security to 'off'
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_usuario_id uuid;
  v_titulo_id uuid;
begin
  if p_cliente_id is null then
    raise exception 'Cliente obrigatório';
  end if;

  if p_descricao is null or length(trim(p_descricao)) = 0 then
    raise exception 'Descrição obrigatória';
  end if;

  if p_emissao_date is null then
    raise exception 'Data de emissão obrigatória';
  end if;

  if p_vencimento_date is null then
    raise exception 'Vencimento obrigatório';
  end if;

  if p_valor is null or p_valor <= 0 then
    raise exception 'Valor deve ser maior que zero';
  end if;

  if auth.uid() is null
     and current_user not in ('postgres', 'service_role') then
    raise exception 'Usuário não autenticado';
  end if;

  v_tenant_id := public.current_tenant_id();
  v_empresa_id := public.current_empresa_id();

  if v_tenant_id is null or v_empresa_id is null then
    raise exception 'Tenant e empresa devem estar selecionados';
  end if;

  if auth.uid() is not null
     and not f.has_finance_access(v_tenant_id, v_empresa_id) then
    raise exception 'Sem permissão financeira';
  end if;

  if not exists (
    select 1
    from public.clientes cliente
    where cliente.id = p_cliente_id
      and cliente.tenant_id = v_tenant_id
      and cliente.empresa_id = v_empresa_id
      and cliente.ativo = true
  ) then
    raise exception 'Cliente inválido para a empresa selecionada';
  end if;

  if p_os_id is not null
     and not exists (
       select 1
       from public.ordens_servico os
       where os.id = p_os_id
         and os.tenant_id = v_tenant_id
         and os.empresa_id = v_empresa_id
     ) then
    raise exception 'OS inválida para a empresa selecionada';
  end if;

  v_usuario_id := a.fn_current_usuario_id();

  insert into f.titulo (
    tenant_id,
    empresa_id,
    tipo,
    status,
    origem,
    cliente_id,
    os_id,
    descricao,
    emissao_date,
    competencia_date,
    valor_total,
    valor_aberto,
    created_at,
    updated_at,
    created_by,
    updated_by,
    deleted_at
  ) values (
    v_tenant_id,
    v_empresa_id,
    'AR',
    'PENDENTE',
    'MANUAL',
    p_cliente_id,
    p_os_id,
    trim(p_descricao),
    p_emissao_date,
    f._month_first(p_emissao_date),
    p_valor,
    p_valor,
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

  return query select v_titulo_id;
end;
$$;

revoke all on function f.criar_titulo_ar_manual_v1(integer, text, date, date, numeric, integer, text)
  from public;
revoke all on function f.criar_titulo_ar_manual_v1(integer, text, date, date, numeric, integer, text)
  from anon;
grant execute on function f.criar_titulo_ar_manual_v1(integer, text, date, date, numeric, integer, text)
  to authenticated, service_role;

comment on function f.criar_titulo_ar_manual_v1(integer, text, date, date, numeric, integer, text) is
  'Cria AR manual (sem documento fiscal), respeitando tenant, empresa ativa e acesso financeiro.';
