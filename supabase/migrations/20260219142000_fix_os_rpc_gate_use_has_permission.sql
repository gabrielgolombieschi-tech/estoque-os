-- Corrige gate das RPCs de OS para usar o modelo atual de permissao (os.write).
-- `public.can('os','write')` pode retornar false no modelo novo para papeis nao-admin.

create or replace function public.add_os_item_baixa_imediata(
  p_os_id integer,
  p_item_id integer,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_desconto_percentual numeric default 0,
  p_desconto_valor numeric default 0,
  p_baixa_estoque boolean default true,
  p_realizado_por text default null,
  p_motivo text default null,
  p_empresa_id uuid default null
) returns public.os_itens
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_item public.itens;
  v_total numeric;
  v_row public.os_itens;
  v_tenant uuid;
  v_realizado_por text;
  v_empresa uuid;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual nao definido';
  end if;

  if not (
    public.can('os_rpcs', 'execute')
    or public.has_permission('os.write')
  ) then
    raise exception 'Sem permissao para executar operacao de OS';
  end if;

  v_empresa := coalesce(p_empresa_id, public.current_empresa_id());
  if v_empresa is null then
    raise exception 'Empresa atual nao definida. Informe p_empresa_id na chamada da RPC.';
  end if;

  perform public.set_current_empresa(v_empresa);

  v_realizado_por := coalesce(p_realizado_por, auth.uid()::text);

  if not exists (
    select 1
    from public.ordens_servico os
    where os.id = p_os_id
      and os.tenant_id = v_tenant
  ) then
    raise exception 'OS invalida ou fora do tenant atual';
  end if;

  select *
    into v_item
  from public.itens
  where id = p_item_id
    and tenant_id = v_tenant
    and ativo = true;

  if not found then
    raise exception 'Item invalido/inativo ou fora do tenant atual';
  end if;

  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Quantidade invalida';
  end if;

  v_total := (p_quantidade * p_valor_unitario) - coalesce(p_desconto_valor, 0);

  insert into public.os_itens (
    tenant_id,
    os_id,
    item_id,
    quantidade,
    valor_unitario,
    valor_total,
    desconto_percentual,
    desconto_valor,
    baixa_estoque,
    criado_em
  )
  values (
    v_tenant,
    p_os_id,
    p_item_id,
    p_quantidade,
    p_valor_unitario,
    v_total,
    coalesce(p_desconto_percentual, 0),
    coalesce(p_desconto_valor, 0),
    coalesce(p_baixa_estoque, true),
    now()
  )
  returning * into v_row;

  if coalesce(p_baixa_estoque, true)
     and v_item.tipo = 'produto'
     and coalesce(v_item.controla_estoque, false) = true
  then
    if not (public.can('estoque', 'write') or public.can('os_rpcs', 'execute')) then
      raise exception 'Sem permissao para movimentar estoque';
    end if;

    insert into public.movimentacoes (
      tenant_id,
      empresa_id,
      item_id,
      tipo,
      quantidade,
      motivo,
      realizado_por,
      data_movimentacao,
      created_at
    )
    values (
      v_tenant,
      v_empresa,
      p_item_id,
      'saida',
      p_quantidade,
      coalesce(p_motivo, 'Baixa imediata via OS ' || p_os_id),
      v_realizado_por,
      now(),
      now()
    );
  end if;

  update public.ordens_servico os
  set valor_total = coalesce((
        select sum(oi.valor_total)
        from public.os_itens oi
        where oi.os_id = p_os_id
          and oi.tenant_id = v_tenant
      ), 0),
      atualizado_em = now()
  where os.id = p_os_id
    and os.tenant_id = v_tenant;

  return v_row;
end;
$$;
create or replace function public.remove_os_item_reverte_estoque(
  p_os_item_id integer,
  p_realizado_por text default null,
  p_motivo text default null,
  p_empresa_id uuid default null
) returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_tenant uuid;
  v_empresa uuid;
  v_realizado_por text;
  v_item public.itens;
  v_row public.os_itens;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual nao definido';
  end if;

  if not (
    public.can('os_rpcs', 'execute')
    or public.has_permission('os.write')
  ) then
    raise exception 'Sem permissao para executar operacao de OS';
  end if;

  v_empresa := coalesce(p_empresa_id, public.current_empresa_id());
  if v_empresa is null then
    raise exception 'Empresa atual nao definida. Informe p_empresa_id na chamada da RPC.';
  end if;

  perform public.set_current_empresa(v_empresa);

  v_realizado_por := coalesce(p_realizado_por, auth.uid()::text);

  select *
    into v_row
  from public.os_itens
  where id = p_os_item_id
    and tenant_id = v_tenant;

  if not found then
    raise exception 'Item da OS nao encontrado';
  end if;

  select *
    into v_item
  from public.itens
  where id = v_row.item_id
    and tenant_id = v_tenant;

  if not found then
    raise exception 'Item invalido ou fora do tenant atual';
  end if;

  delete from public.os_itens
  where id = p_os_item_id
    and tenant_id = v_tenant;

  if coalesce(v_row.baixa_estoque, false)
     and v_item.tipo = 'produto'
     and coalesce(v_item.controla_estoque, false) = true
  then
    if not (public.can('estoque', 'write') or public.can('os_rpcs', 'execute')) then
      raise exception 'Sem permissao para movimentar estoque';
    end if;

    insert into public.movimentacoes (
      tenant_id,
      empresa_id,
      item_id,
      tipo,
      quantidade,
      motivo,
      realizado_por,
      data_movimentacao,
      origem_os_id,
      created_at
    )
    values (
      v_tenant,
      v_empresa,
      v_row.item_id,
      'entrada',
      v_row.quantidade,
      coalesce(p_motivo, 'Estorno baixa OS ' || v_row.os_id),
      v_realizado_por,
      now(),
      v_row.os_id,
      now()
    );
  end if;

  update public.ordens_servico os
  set valor_total = coalesce((
        select sum(oi.valor_total)
        from public.os_itens oi
        where oi.os_id = v_row.os_id
          and oi.tenant_id = v_tenant
      ), 0),
      atualizado_em = now()
  where os.id = v_row.os_id
    and os.tenant_id = v_tenant;
end;
$$;
