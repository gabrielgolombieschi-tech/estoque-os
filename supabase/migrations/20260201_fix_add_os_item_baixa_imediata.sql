create or replace function public.add_os_item_baixa_imediata(
  p_os_id integer,
  p_item_id integer,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_baixa_estoque boolean,
  p_realizado_por text,
  p_motivo text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_tenant_id uuid;
  v_empresa_id uuid;
  v_quantidade numeric(14,3);
  v_valor_unitario numeric(14,6);
  v_valor_total numeric(14,2);
begin
  v_tenant_id := public.current_tenant_id();
  if v_tenant_id is null then
    raise exception 'tenant_id nao encontrado';
  end if;

  v_empresa_id := public.current_empresa_id();
  if v_empresa_id is null then
    raise exception 'empresa_id nao encontrado';
  end if;

  if p_os_id is null or p_os_id <= 0 then
    raise exception 'os_id invalido';
  end if;

  if p_item_id is null or p_item_id <= 0 then
    raise exception 'item_id invalido';
  end if;

  v_quantidade := coalesce(p_quantidade, 0);
  if v_quantidade <= 0 then
    raise exception 'quantidade invalida';
  end if;

  v_valor_unitario := coalesce(p_valor_unitario, 0);
  v_valor_total := round(v_quantidade * v_valor_unitario, 2);

  if not exists (
    select 1
    from public.ordens_servico os
    where os.id = p_os_id
      and os.tenant_id = v_tenant_id
  ) then
    raise exception 'os_id invalido para este tenant';
  end if;

  with upd as (
    update public.os_itens oi
       set quantidade = oi.quantidade + v_quantidade,
           valor_total = oi.valor_total + v_valor_total,
           valor_unitario = case when v_valor_unitario > 0 then v_valor_unitario else oi.valor_unitario end,
           baixa_estoque = (oi.baixa_estoque or p_baixa_estoque),
           observacoes = coalesce(oi.observacoes, '')
     where oi.tenant_id = v_tenant_id
       and oi.os_id = p_os_id
       and oi.item_id = p_item_id
     returning 1
  )
  insert into public.os_itens (
    os_id,
    item_id,
    quantidade,
    valor_unitario,
    valor_total,
    desconto_percentual,
    desconto_valor,
    baixa_estoque,
    observacoes,
    tenant_id
  )
  select
    p_os_id,
    p_item_id,
    v_quantidade,
    case
      when v_valor_unitario > 0 then v_valor_unitario
      when v_quantidade > 0 and v_valor_total > 0 then (v_valor_total / v_quantidade)
      else 0
    end,
    v_valor_total,
    0,
    0,
    p_baixa_estoque,
    coalesce(p_motivo, 'Adicionado via OS'),
    v_tenant_id
  where not exists (select 1 from upd);

  if coalesce(p_baixa_estoque, false) then
    insert into public.movimentacoes (
      item_id,
      tipo,
      quantidade,
      motivo,
      realizado_por,
      data_movimentacao,
      origem_os_id,
      tenant_id,
      empresa_id
    )
    values (
      p_item_id,
      'saida',
      v_quantidade,
      p_motivo,
      p_realizado_por,
      now(),
      p_os_id,
      v_tenant_id,
      v_empresa_id
    );
  end if;
end;
$$;
notify pgrst, 'reload schema';
