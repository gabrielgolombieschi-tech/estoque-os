set check_function_bodies = off;

create or replace function m.fn_compra_varredura(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_incluir_os boolean default true,
  p_incluir_estoque boolean default true
)
returns jsonb
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

  if p_incluir_os then
    -- Fonte consolidada: evita duplicidade para mesma OS + item.
    with fonte_os as (
      select
        oi.os_id,
        oi.item_id,
        sum(oi.quantidade)::numeric(15,3) as quantidade
      from public.os_itens oi
      join public.ordens_servico os
        on os.tenant_id = p_tenant_id
       and os.empresa_id = p_empresa_id
       and os.id = oi.os_id
      where oi.tenant_id = p_tenant_id
        and oi.empresa_id = p_empresa_id
        and oi.quantidade > 0
        and coalesce(oi.baixa_estoque, false) = false
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
         and cp.status in ('PENDENTE','EM_PEDIDO')
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
        sum(oi.quantidade)::numeric(15,3) as quantidade
      from public.os_itens oi
      join public.ordens_servico os
        on os.tenant_id = p_tenant_id
       and os.empresa_id = p_empresa_id
       and os.id = oi.os_id
      where oi.tenant_id = p_tenant_id
        and oi.empresa_id = p_empresa_id
        and oi.quantidade > 0
        and coalesce(oi.baixa_estoque, false) = false
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
        'Varredura automatica (OS sem baixa de estoque)'
      from fonte_os f
      join public.itens i
        on i.tenant_id = p_tenant_id
       and i.empresa_id = p_empresa_id
       and i.id = f.item_id
      left join m.compra_pendencia cp
        on cp.tenant_id = p_tenant_id
       and cp.empresa_id = p_empresa_id
       and cp.deleted_at is null
       and cp.status in ('PENDENTE', 'EM_PEDIDO')
       and cp.origem_tipo = 'OS'
       and cp.origem_os_id = f.os_id
       and cp.item_id = f.item_id
      where cp.id is null
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
        coalesce(it.estoque_minimo, 0)::numeric(15,3) as alvo_min,
        coalesce(e.quantidade_atual, 0)::numeric(15,3) as estoque_atual,
        coalesce(ec.qtd_em_compra, 0)::numeric(15,3) as em_compra_qtd,
        greatest(
          0::numeric,
          coalesce(it.estoque_minimo, 0)::numeric(15,3) - (coalesce(e.quantidade_atual, 0)::numeric(15,3) + coalesce(ec.qtd_em_compra, 0)::numeric(15,3))
        )::numeric(15,3) as sugestao_min
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
        and coalesce(it.estoque_minimo, 0) > 0
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
         set quantidade = c.sugestao_min,
             estoque_meta = 'MIN',
             fornecedor_id = coalesce(cp.fornecedor_id, c.fornecedor_id),
             updated_by = a.fn_current_usuario_id()
        from calc c, existentes ex
       where ex.id = cp.id
         and ex.item_id = c.item_id
         and c.sugestao_min > 0
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
        c.sugestao_min,
        'MEDIA',
        'MIN',
        'Varredura automatica (estoque minimo)'
      from calc c
      left join existentes ex on ex.item_id = c.item_id
      where c.sugestao_min > 0
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

grant execute on function m.fn_compra_varredura(uuid, uuid, boolean, boolean) to authenticated, service_role;


