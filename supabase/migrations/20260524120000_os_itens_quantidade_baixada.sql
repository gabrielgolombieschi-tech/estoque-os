begin;

alter table public.os_itens
  add column if not exists quantidade_baixada numeric(14,3) not null default 0;

update public.os_itens oi
set quantidade_baixada = oi.quantidade
from public.itens i
where coalesce(oi.baixa_estoque, false) = true
  and coalesce(oi.quantidade_baixada, 0) = 0
  and i.tenant_id = oi.tenant_id
  and i.empresa_id = oi.empresa_id
  and i.id = oi.item_id
  and i.tipo = 'produto'
  and coalesce(i.controla_estoque, false) = true;

update public.os_itens
set baixa_estoque = (coalesce(quantidade_baixada, 0) >= quantidade)
where baixa_estoque is distinct from (coalesce(quantidade_baixada, 0) >= quantidade);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'chk_os_itens_quantidade_baixada_nonnegative'
      and conrelid = 'public.os_itens'::regclass
  ) then
    alter table public.os_itens
      add constraint chk_os_itens_quantidade_baixada_nonnegative
      check (quantidade_baixada >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'chk_os_itens_quantidade_baixada_lte_quantidade'
      and conrelid = 'public.os_itens'::regclass
  ) then
    alter table public.os_itens
      add constraint chk_os_itens_quantidade_baixada_lte_quantidade
      check (quantidade_baixada <= quantidade);
  end if;
end $$;

comment on column public.os_itens.quantidade_baixada is
  'Quantidade efetivamente baixada do estoque para o item da OS. Pode ser menor que quantidade quando o saldo disponivel nao cobre 100%.';

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
  v_saldo_atual numeric(14,3) := 0;
  v_quantidade_baixada numeric(14,3) := 0;
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

  if coalesce(p_baixa_estoque, true)
     and v_item.tipo = 'produto'
     and coalesce(v_item.controla_estoque, false) = true
  then
    if not (public.can('estoque', 'write') or public.can('os_rpcs', 'execute')) then
      raise exception 'Sem permissao para movimentar estoque';
    end if;

    select coalesce(e.quantidade_atual, 0)
      into v_saldo_atual
    from public.estoque e
    where e.tenant_id = v_tenant
      and e.empresa_id = v_empresa
      and e.item_id = p_item_id
    for update;

    if not found then
      v_saldo_atual := 0;
    end if;

    v_quantidade_baixada := least(p_quantidade, greatest(coalesce(v_saldo_atual, 0), 0));
  end if;

  v_total := (p_quantidade * coalesce(p_valor_unitario, 0)) - coalesce(p_desconto_valor, 0);

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
    quantidade_baixada,
    criado_em
  )
  values (
    v_tenant,
    v_empresa,
    p_os_id,
    p_item_id,
    p_quantidade,
    coalesce(p_valor_unitario, 0),
    v_total,
    coalesce(p_desconto_percentual, 0),
    coalesce(p_desconto_valor, 0),
    v_quantidade_baixada >= p_quantidade,
    v_quantidade_baixada,
    now()
  )
  returning * into v_row;

  if v_quantidade_baixada > 0 then
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
      v_quantidade_baixada,
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

create or replace function public.add_os_item_baixa_imediata(
  p_os_id integer,
  p_item_id integer,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_desconto_percentual numeric default 0,
  p_desconto_valor numeric default 0,
  p_baixa_estoque boolean default true,
  p_realizado_por text default null,
  p_motivo text default null
)
returns public.os_itens
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.add_os_item_baixa_imediata(
    p_os_id,
    p_item_id,
    p_quantidade,
    p_valor_unitario,
    p_desconto_percentual,
    p_desconto_valor,
    p_baixa_estoque,
    p_realizado_por,
    p_motivo,
    null::uuid
  );
$$;

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
  v_row public.os_itens%rowtype;
  v_os public.ordens_servico%rowtype;
  v_os_label text;
  v_motivo text;
  v_quantidade_estorno numeric(14,3) := 0;
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

  v_quantidade_estorno := least(coalesce(v_row.quantidade_baixada, 0), v_row.quantidade);

  delete from public.os_itens
  where id = p_os_item_id
    and tenant_id = v_tenant
    and empresa_id = v_empresa;

  if v_quantidade_estorno > 0 then
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
      v_quantidade_estorno,
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

create or replace function m.fn_compra_varredura(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_incluir_os boolean default true,
  p_incluir_estoque boolean default true
) returns jsonb
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
declare
  v_os_inseridas int := 0;
  v_os_canceladas int := 0;
  v_estoque_inseridas int := 0;
  v_estoque_atualizadas int := 0;
begin
  if not public.can('compras', 'write', p_tenant_id) then
    raise exception 'Sem permissao para varredura de compras';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('m.fn_compra_varredura'),
    hashtext(coalesce(p_tenant_id::text, '') || ':' || coalesce(p_empresa_id::text, ''))
  );

  if p_incluir_os then
    with fonte_os as (
      select
        oi.os_id,
        oi.item_id,
        sum(greatest(oi.quantidade - coalesce(oi.quantidade_baixada, 0), 0))::numeric(15,3) as quantidade
      from public.os_itens oi
      join public.ordens_servico os
        on os.tenant_id = p_tenant_id
       and os.empresa_id = p_empresa_id
       and os.id = oi.os_id
      where oi.tenant_id = p_tenant_id
        and oi.empresa_id = p_empresa_id
        and oi.quantidade > 0
        and greatest(oi.quantidade - coalesce(oi.quantidade_baixada, 0), 0) > 0
        and os.status in ('aberta', 'em_andamento')
      group by oi.os_id, oi.item_id
    ),
    canceladas as (
      update m.compra_pendencia cp
         set status = 'CANCELADO',
             cancel_reason = 'Cancelado automaticamente: item removido/baixado na OS.',
             updated_by = a.fn_current_usuario_id()
       where cp.tenant_id = p_tenant_id
         and cp.empresa_id = p_empresa_id
         and cp.deleted_at is null
         and cp.origem_tipo = 'OS'
         and cp.status in ('PENDENTE', 'EM_PEDIDO')
         and not exists (
           select 1
           from fonte_os f
           where f.os_id = cp.origem_os_id
             and f.item_id = cp.item_id
         )
      returning cp.id
    )
    select count(*) into v_os_canceladas from canceladas;

    with fonte_os as (
      select
        oi.os_id,
        oi.item_id,
        sum(greatest(oi.quantidade - coalesce(oi.quantidade_baixada, 0), 0))::numeric(15,3) as quantidade
      from public.os_itens oi
      join public.ordens_servico os
        on os.tenant_id = p_tenant_id
       and os.empresa_id = p_empresa_id
       and os.id = oi.os_id
      where oi.tenant_id = p_tenant_id
        and oi.empresa_id = p_empresa_id
        and oi.quantidade > 0
        and greatest(oi.quantidade - coalesce(oi.quantidade_baixada, 0), 0) > 0
        and os.status in ('aberta', 'em_andamento')
      group by oi.os_id, oi.item_id
    ),
    atualizadas as (
      update m.compra_pendencia cp
         set quantidade = f.quantidade,
             updated_by = a.fn_current_usuario_id()
        from fonte_os f
       where cp.tenant_id = p_tenant_id
         and cp.empresa_id = p_empresa_id
         and cp.deleted_at is null
         and cp.origem_tipo = 'OS'
         and cp.status = 'PENDENTE'
         and cp.origem_os_id = f.os_id
         and cp.item_id = f.item_id
      returning cp.id
    ),
    ins as (
      insert into m.compra_pendencia (
        tenant_id,
        empresa_id,
        status,
        fornecedor_id,
        origem_tipo,
        origem_os_id,
        item_id,
        item_nome,
        unidade,
        quantidade,
        prioridade,
        observacoes
      )
      select
        p_tenant_id,
        p_empresa_id,
        'PENDENTE',
        i.fornecedor_id,
        'OS',
        f.os_id,
        f.item_id,
        upper(trim(coalesce(i.nome, i.descricao, 'ITEM'))),
        coalesce(nullif(trim(i.unidade_medida), ''), 'UN'),
        f.quantidade,
        'MEDIA',
        'Varredura automatica (OS com baixa pendente/parcial de estoque)'
      from fonte_os f
      join public.itens i
        on i.tenant_id = p_tenant_id
       and i.empresa_id = p_empresa_id
       and i.id = f.item_id
      left join public.estoque e
        on e.tenant_id = p_tenant_id
       and e.empresa_id = p_empresa_id
       and e.item_id = f.item_id
      left join m.compra_pendencia cp
        on cp.tenant_id = p_tenant_id
       and cp.empresa_id = p_empresa_id
       and cp.deleted_at is null
       and cp.status in ('PENDENTE', 'EM_PEDIDO')
       and cp.origem_tipo = 'OS'
       and cp.origem_os_id = f.os_id
       and cp.item_id = f.item_id
      where cp.id is null
        and coalesce(e.quantidade_atual, 0) < f.quantidade
      returning id
    )
    select count(*) into v_os_inseridas from ins;
  end if;

  if p_incluir_estoque then
    with em_compra as (
      select
        p.tenant_id,
        p.empresa_id,
        i.item_id,
        sum(greatest(i.quantidade - i.quantidade_recebida, 0))::numeric(15,3) as qtd_em_compra
      from m.pedido_compra_item i
      join m.pedido_compra p on p.id = i.pedido_compra_id
      where p.deleted_at is null
        and p.tenant_id = p_tenant_id
        and p.empresa_id = p_empresa_id
        and p.status in ('RASCUNHO','AGUARDANDO_APROVACAO','APROVADO','ENVIADO','PARCIAL_RECEBIDO')
      group by p.tenant_id, p.empresa_id, i.item_id
    ),
    calc as (
      select
        it.id as item_id,
        it.fornecedor_id,
        upper(trim(coalesce(it.nome, it.descricao, 'ITEM'))) as item_nome,
        coalesce(nullif(trim(it.unidade_medida), ''), 'UN') as unidade,
        coalesce(it.estoque_maximo, 0)::numeric(15,3) as alvo_max,
        coalesce(e.quantidade_atual, 0)::numeric(15,3) as estoque_atual,
        coalesce(ec.qtd_em_compra, 0)::numeric(15,3) as em_compra_qtd,
        greatest(
          0::numeric,
          coalesce(it.estoque_maximo, 0)::numeric(15,3) - (coalesce(e.quantidade_atual, 0)::numeric(15,3) + coalesce(ec.qtd_em_compra, 0)::numeric(15,3))
        )::numeric(15,3) as sugestao_max
      from public.itens it
      left join public.estoque e
        on e.tenant_id = p_tenant_id
       and e.empresa_id = p_empresa_id
       and e.item_id = it.id
      left join em_compra ec
        on ec.tenant_id = p_tenant_id
       and ec.empresa_id = p_empresa_id
       and ec.item_id = it.id
      where it.tenant_id = p_tenant_id
        and it.empresa_id = p_empresa_id
        and coalesce(it.controla_estoque, false) = true
        and coalesce(it.estoque_maximo, 0) > 0
    ),
    existentes as (
      select distinct on (cp.item_id)
        cp.id,
        cp.item_id
      from m.compra_pendencia cp
      where cp.tenant_id = p_tenant_id
        and cp.empresa_id = p_empresa_id
        and cp.deleted_at is null
        and cp.origem_tipo = 'ESTOQUE'
        and cp.status in ('PENDENTE', 'EM_PEDIDO')
      order by cp.item_id, cp.created_at desc
    ),
    upd as (
      update m.compra_pendencia cp
         set quantidade = c.sugestao_max,
             estoque_meta = 'MAX',
             fornecedor_id = coalesce(cp.fornecedor_id, c.fornecedor_id),
             updated_by = a.fn_current_usuario_id()
        from calc c, existentes ex
       where ex.id = cp.id
         and ex.item_id = c.item_id
         and c.sugestao_max > 0
      returning cp.id
    ),
    ins as (
      insert into m.compra_pendencia (
        tenant_id,
        empresa_id,
        status,
        fornecedor_id,
        origem_tipo,
        item_id,
        item_nome,
        unidade,
        quantidade,
        prioridade,
        estoque_meta,
        observacoes
      )
      select
        p_tenant_id,
        p_empresa_id,
        'PENDENTE',
        c.fornecedor_id,
        'ESTOQUE',
        c.item_id,
        c.item_nome,
        c.unidade,
        c.sugestao_max,
        'MEDIA',
        'MAX',
        'Varredura automatica (estoque maximo)'
      from calc c
      left join existentes ex on ex.item_id = c.item_id
      where c.sugestao_max > 0
        and ex.id is null
      returning id
    )
    select
      (select count(*) from upd),
      (select count(*) from ins)
      into v_estoque_atualizadas, v_estoque_inseridas;
  end if;

  return jsonb_build_object(
    'os_inseridas', v_os_inseridas,
    'os_canceladas', v_os_canceladas,
    'estoque_inseridas', v_estoque_inseridas,
    'estoque_atualizadas', v_estoque_atualizadas,
    'total_movimentadas', v_os_inseridas + v_os_canceladas + v_estoque_inseridas + v_estoque_atualizadas
  );
end;
$$;

grant execute on function public.add_os_item_baixa_imediata(integer, integer, numeric, numeric, numeric, numeric, boolean, text, text) to anon, authenticated, service_role;
grant execute on function public.add_os_item_baixa_imediata(integer, integer, numeric, numeric, numeric, numeric, boolean, text, text, uuid) to anon, authenticated, service_role;
grant execute on function public.remove_os_item_reverte_estoque(integer, text, text, uuid) to anon, authenticated, service_role;
grant execute on function m.fn_compra_varredura(uuid, uuid, boolean, boolean) to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
