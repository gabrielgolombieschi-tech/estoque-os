begin;

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
set search_path = public, pg_temp
as $function$
declare
  v_item public.itens%rowtype;
  v_os public.ordens_servico%rowtype;
  v_total numeric;
  v_row public.os_itens%rowtype;
  v_tenant uuid;
  v_realizado_por text;
  v_empresa uuid;
  v_os_label text;
  v_motivo text;
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
    into v_os
  from public.ordens_servico os
  where os.id = p_os_id
    and os.tenant_id = v_tenant
    and os.empresa_id = v_empresa;

  if not found then
    raise exception 'OS invalida ou fora do tenant/empresa atual';
  end if;

  select *
    into v_item
  from public.itens
  where id = p_item_id
    and tenant_id = v_tenant
    and empresa_id = v_empresa
    and ativo = true;

  if not found then
    raise exception 'Item invalido/inativo ou fora do tenant/empresa atual';
  end if;

  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Quantidade invalida';
  end if;

  v_total := (p_quantidade * p_valor_unitario) - coalesce(p_desconto_valor, 0);

  insert into public.os_itens (
    tenant_id,
    empresa_id,
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
    v_empresa,
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

    v_os_label := coalesce(nullif(trim(v_os.numero_os), ''), nullif(v_os.os_num::text, ''), v_os.id::text);
    v_motivo := nullif(trim(coalesce(p_motivo, '')), '');
    if v_motivo is null then
      v_motivo := 'Baixa imediata via OS ' || v_os_label;
    end if;

    v_motivo := trim(regexp_replace(v_motivo, '[[:space:]]*\[OS[[:space:]]+[^\]]+\][[:space:]]*$', '', 'i'));
    if position(upper('OS ' || v_os_label) in upper(v_motivo)) = 0 then
      v_motivo := v_motivo || ' [OS ' || v_os_label || ']';
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
      p_item_id,
      'saida',
      p_quantidade,
      v_motivo,
      v_realizado_por,
      now(),
      p_os_id,
      now()
    );
  end if;

  update public.ordens_servico os
  set valor_total = coalesce((
        select sum(oi.valor_total)
        from public.os_itens oi
        where oi.os_id = p_os_id
          and oi.tenant_id = v_tenant
          and oi.empresa_id = v_empresa
      ), 0),
      atualizado_em = now()
  where os.id = p_os_id
    and os.tenant_id = v_tenant
    and os.empresa_id = v_empresa;

  return v_row;
end;
$function$;

create or replace function public.reclassificar_mov_saida_para_os(
  p_mov_id bigint,
  p_origem_os_id integer,
  p_realizado_por text default null
)
returns table(
  mov_original_id integer,
  mov_ajuste_id integer,
  mov_saida_corrigida_id integer
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_mov public.movimentacoes%rowtype;
  v_os public.ordens_servico%rowtype;
  v_realizado_por text;
  v_motivo_saida text;
  v_os_label text;
  v_mov_ajuste_id integer;
  v_mov_saida_id integer;
begin
  if p_mov_id is null or p_origem_os_id is null then
    raise exception 'Parametros obrigatorios: p_mov_id e p_origem_os_id';
  end if;

  select *
    into v_mov
  from public.movimentacoes
  where id = p_mov_id;

  if not found then
    raise exception 'Movimentacao % nao encontrada', p_mov_id;
  end if;

  if v_mov.tipo <> 'saida' then
    raise exception 'Movimentacao % nao e saida', p_mov_id;
  end if;

  if v_mov.origem_os_id is not null then
    raise exception 'Movimentacao % ja possui origem_os_id', p_mov_id;
  end if;

  select *
    into v_os
  from public.ordens_servico os
  where os.id = p_origem_os_id
    and os.tenant_id = v_mov.tenant_id
    and os.empresa_id = v_mov.empresa_id;

  if not found then
    raise exception 'OS % nao encontrada no mesmo tenant/empresa da movimentacao %', p_origem_os_id, p_mov_id;
  end if;

  select m.id
    into v_mov_ajuste_id
  from public.movimentacoes m
  where m.tenant_id = v_mov.tenant_id
    and m.empresa_id = v_mov.empresa_id
    and m.item_id = v_mov.item_id
    and m.tipo = 'ajuste'
    and m.motivo = ('CORRECAO RASTREIO OS: neutraliza mov #' || v_mov.id::text)
  order by m.id asc
  limit 1;

  if v_mov_ajuste_id is not null then
    select m.id
      into v_mov_saida_id
    from public.movimentacoes m
    where m.tenant_id = v_mov.tenant_id
      and m.empresa_id = v_mov.empresa_id
      and m.item_id = v_mov.item_id
      and m.tipo = 'saida'
      and m.origem_os_id = p_origem_os_id
      and abs(coalesce(m.quantidade, 0) - coalesce(v_mov.quantidade, 0)) < 0.0001
      and abs(extract(epoch from (coalesce(m.data_movimentacao, m.created_at) - coalesce(v_mov.data_movimentacao, v_mov.created_at)))) <= 120
    order by m.id asc
    limit 1;

    if v_mov_saida_id is not null then
      return query
      select v_mov.id::integer, v_mov_ajuste_id, v_mov_saida_id;
      return;
    end if;
  end if;

  v_realizado_por := coalesce(p_realizado_por, auth.uid()::text, 'auditoria_sistema');

  insert into public.movimentacoes (
    tenant_id,
    empresa_id,
    item_id,
    tipo,
    quantidade,
    motivo,
    realizado_por,
    data_movimentacao,
    origem_nf_entrada_id,
    origem_os_id,
    created_at
  )
  values (
    v_mov.tenant_id,
    v_mov.empresa_id,
    v_mov.item_id,
    'ajuste',
    v_mov.quantidade,
    'CORRECAO RASTREIO OS: neutraliza mov #' || v_mov.id::text,
    v_realizado_por,
    coalesce(v_mov.data_movimentacao, now()),
    v_mov.origem_nf_entrada_id,
    null,
    now()
  )
  returning id into v_mov_ajuste_id;

  v_os_label := coalesce(nullif(trim(v_os.numero_os), ''), nullif(v_os.os_num::text, ''), v_os.id::text);
  v_motivo_saida := nullif(trim(coalesce(v_mov.motivo, '')), '');
  if v_motivo_saida is null then
    v_motivo_saida := 'Baixa de estoque via OS ' || v_os_label;
  end if;

  v_motivo_saida := trim(regexp_replace(v_motivo_saida, '[[:space:]]*\[OS[[:space:]]+[^\]]+\][[:space:]]*$', '', 'i'));
  if position(upper('OS ' || v_os_label) in upper(v_motivo_saida)) = 0 then
    v_motivo_saida := v_motivo_saida || ' [OS ' || v_os_label || ']';
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
    origem_nf_entrada_id,
    origem_os_id,
    created_at
  )
  values (
    v_mov.tenant_id,
    v_mov.empresa_id,
    v_mov.item_id,
    'saida',
    v_mov.quantidade,
    v_motivo_saida,
    v_realizado_por,
    coalesce(v_mov.data_movimentacao, now()),
    v_mov.origem_nf_entrada_id,
    p_origem_os_id,
    now()
  )
  returning id into v_mov_saida_id;

  return query
  select v_mov.id::integer, v_mov_ajuste_id, v_mov_saida_id;
end;
$function$;

create or replace function public.remove_os_item_reverte_estoque(
  p_os_item_id integer,
  p_realizado_por text default null,
  p_motivo text default null,
  p_empresa_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant uuid;
  v_empresa uuid;
  v_realizado_por text;
  v_item public.itens%rowtype;
  v_row public.os_itens%rowtype;
  v_os public.ordens_servico%rowtype;
  v_os_label text;
  v_motivo text;
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
    and tenant_id = v_tenant
    and empresa_id = v_empresa;

  if not found then
    raise exception 'Item da OS nao encontrado';
  end if;

  select *
    into v_os
  from public.ordens_servico os
  where os.id = v_row.os_id
    and os.tenant_id = v_tenant
    and os.empresa_id = v_empresa;

  if not found then
    raise exception 'OS do item nao encontrada no tenant/empresa atual';
  end if;

  select *
    into v_item
  from public.itens
  where id = v_row.item_id
    and tenant_id = v_tenant
    and empresa_id = v_empresa;

  if not found then
    raise exception 'Item invalido ou fora do tenant/empresa atual';
  end if;

  delete from public.os_itens
  where id = p_os_item_id
    and tenant_id = v_tenant
    and empresa_id = v_empresa;

  if coalesce(v_row.baixa_estoque, false)
     and v_item.tipo = 'produto'
     and coalesce(v_item.controla_estoque, false) = true
  then
    if not (public.can('estoque', 'write') or public.can('os_rpcs', 'execute')) then
      raise exception 'Sem permissao para movimentar estoque';
    end if;

    v_os_label := coalesce(nullif(trim(v_os.numero_os), ''), nullif(v_os.os_num::text, ''), v_os.id::text);
    v_motivo := nullif(trim(coalesce(p_motivo, '')), '');
    if v_motivo is null then
      v_motivo := 'Estorno baixa OS ' || v_os_label;
    end if;

    v_motivo := trim(regexp_replace(v_motivo, '[[:space:]]*\[OS[[:space:]]+[^\]]+\][[:space:]]*$', '', 'i'));
    if position(upper('OS ' || v_os_label) in upper(v_motivo)) = 0 then
      v_motivo := v_motivo || ' [OS ' || v_os_label || ']';
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
      v_motivo,
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
          and oi.empresa_id = v_empresa
      ), 0),
      atualizado_em = now()
  where os.id = v_row.os_id
    and os.tenant_id = v_tenant
    and os.empresa_id = v_empresa;
end;
$function$;

grant execute on function public.add_os_item_baixa_imediata(integer, integer, numeric, numeric, numeric, numeric, boolean, text, text, uuid) to anon, authenticated, service_role;
grant execute on function public.reclassificar_mov_saida_para_os(bigint, integer, text) to anon, authenticated, service_role;
grant execute on function public.remove_os_item_reverte_estoque(integer, text, text, uuid) to anon, authenticated, service_role;

notify pgrst, 'reload schema';

commit;
