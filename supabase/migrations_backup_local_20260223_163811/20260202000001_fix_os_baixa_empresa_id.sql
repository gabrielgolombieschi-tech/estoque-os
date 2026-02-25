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
)
returns public.os_itens
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_item public.itens;
  v_total numeric;
  v_row public.os_itens;
  v_tenant uuid;
  v_realizado_por text;
  v_empresa uuid;
begin
  -- autenticado
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual nao definido';
  end if;

  v_empresa := coalesce(p_empresa_id, public.current_empresa_id());
  if v_empresa is null then
    raise exception 'Empresa atual nao definida. Informe p_empresa_id na chamada da RPC.';
  end if;

  perform public.set_current_empresa(v_empresa);

  -- permissao para gerenciar OS
  if not public.has_permission('os.gerenciar') then
    raise exception 'Sem permissao: os.gerenciar';
  end if;

  -- normaliza "realizado_por"
  v_realizado_por := coalesce(p_realizado_por, auth.uid()::text);

  -- valida OS no tenant atual
  if not exists (
    select 1
    from public.ordens_servico os
    where os.id = p_os_id
      and os.tenant_id = v_tenant
  ) then
    raise exception 'OS invalida ou fora do tenant atual';
  end if;

  -- valida item no tenant atual
  select *
    into v_item
  from public.itens
  where id = p_item_id
    and tenant_id = v_tenant
    and ativo = true;

  if not found then
    raise exception 'Item invalido/inativo ou fora do tenant atual';
  end if;

  -- valida quantidade
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

  -- baixa imediata so se for produto e controla_estoque
  if coalesce(p_baixa_estoque, true)
     and v_item.tipo = 'produto'
     and coalesce(v_item.controla_estoque, false) = true
  then
    -- permissao para movimentar estoque
    if not public.has_permission('estoque.movimentar') then
      raise exception 'Sem permissao: estoque.movimentar';
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

  -- recalcula valor_total da OS (somente no tenant)
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
$function$;

notify pgrst, 'reload schema';
