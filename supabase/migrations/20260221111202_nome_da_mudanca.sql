set check_function_bodies = off;

CREATE OR REPLACE FUNCTION m.fn_compra_varredura(p_tenant_id uuid, p_empresa_id uuid, p_incluir_os boolean DEFAULT true, p_incluir_estoque boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'm', 'public'
AS $function$
declare
  v_os_inseridas int := 0;
  v_estoque_inseridas int := 0;
  v_estoque_atualizadas int := 0;
begin
  if not public.can('compras', 'write', p_tenant_id) then
    raise exception 'Sem permissao para varredura de compras';
  end if;

  if p_incluir_os then
    with ins as (
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
        oi.os_id,
        oi.item_id,
        upper(trim(coalesce(i.nome, i.descricao, 'ITEM'))),
        coalesce(nullif(trim(i.unidade_medida), ''), 'UN'),
        oi.quantidade::numeric(15,3),
        'MEDIA',
        'Varredura automatica (OS sem baixa de estoque)'
      from public.os_itens oi
      join public.ordens_servico os
        on os.tenant_id = p_tenant_id
       and os.empresa_id = p_empresa_id
       and os.id = oi.os_id
      join public.itens i
        on i.tenant_id = p_tenant_id
       and i.empresa_id = p_empresa_id
       and i.id = oi.item_id
       and i.deleted_at is null
      left join m.compra_pendencia cp
        on cp.tenant_id = p_tenant_id
       and cp.empresa_id = p_empresa_id
       and cp.deleted_at is null
       and cp.status in ('PENDENTE', 'EM_PEDIDO')
       and cp.origem_tipo = 'OS'
       and cp.origem_os_id = oi.os_id
       and cp.item_id = oi.item_id
      where oi.tenant_id = p_tenant_id
        and oi.empresa_id = p_empresa_id
        and oi.quantidade > 0
        and coalesce(oi.baixa_estoque, false) = false
        and os.status in ('aberta', 'em_andamento')
        and cp.id is null
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
        and i.deleted_at is null
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
        and it.deleted_at is null
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
        from calc c
        join existentes ex on ex.id = cp.id and ex.item_id = c.item_id
       where c.sugestao_min > 0
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
    'estoque_inseridas', v_estoque_inseridas,
    'estoque_atualizadas', v_estoque_atualizadas,
    'total_movimentadas', v_os_inseridas + v_estoque_inseridas + v_estoque_atualizadas
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION m.trg_compra_pendencia_biu()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'm', 'public'
AS $function$
declare
  v_item public.itens%rowtype;
  v_estoque_atual numeric(15,3) := 0;
  v_em_compra numeric(15,3) := 0;
  v_alvo numeric(15,3) := 0;
begin
  if new.item_id is null and new.item_nome is not null then
    new.item_nome := upper(trim(new.item_nome));
  end if;

  if new.origem_tipo = 'OS' and new.origem_os_id is null then
    raise exception 'origem_os_id obrigatorio quando origem_tipo=OS';
  end if;

  if new.origem_tipo = 'ESTOQUE' then
    if new.item_id is null then
      raise exception 'item_id obrigatorio quando origem_tipo=ESTOQUE';
    end if;
    if new.estoque_meta is null then
      raise exception 'estoque_meta obrigatorio quando origem_tipo=ESTOQUE';
    end if;

    select * into v_item
    from public.itens i
    where i.tenant_id = new.tenant_id
      and i.empresa_id = new.empresa_id
      and i.id = new.item_id
      and i.deleted_at is null
    limit 1;

    if not found then
      raise exception 'Item % nao encontrado para pendencia de estoque', new.item_id;
    end if;

    if new.item_nome is null or btrim(new.item_nome) = '' then
      new.item_nome := upper(trim(coalesce(v_item.nome, v_item.descricao, 'ITEM')));
    end if;
    if new.unidade is null or btrim(new.unidade) = '' then
      new.unidade := coalesce(nullif(trim(v_item.unidade_medida), ''), 'UN');
    end if;

    select coalesce(e.quantidade_atual, 0)::numeric(15,3)
      into v_estoque_atual
    from public.estoque e
    where e.tenant_id = new.tenant_id
      and e.empresa_id = new.empresa_id
      and e.item_id = new.item_id;

    select coalesce(sum(greatest(i.quantidade - i.quantidade_recebida, 0)), 0)::numeric(15,3)
      into v_em_compra
    from m.pedido_compra_item i
    join m.pedido_compra p on p.id = i.pedido_compra_id
    where p.deleted_at is null
      and i.deleted_at is null
      and p.tenant_id = new.tenant_id
      and p.empresa_id = new.empresa_id
      and i.item_id = new.item_id
      and p.status in ('RASCUNHO','AGUARDANDO_APROVACAO','APROVADO','ENVIADO','PARCIAL_RECEBIDO');

    v_alvo := case upper(trim(new.estoque_meta))
      when 'MIN' then coalesce(v_item.estoque_minimo, 0)
      when 'IDEAL' then coalesce(v_item.estoque_ideal, 0)
      when 'MAX' then coalesce(v_item.estoque_maximo, 0)
      else 0
    end;

    new.estoque_atual_qtd := v_estoque_atual;
    new.estoque_em_compra_qtd := v_em_compra;
    new.estoque_alvo_qtd := v_alvo;
    new.estoque_sugestao_qtd := greatest(0, v_alvo - (v_estoque_atual + v_em_compra));
  else
    new.estoque_atual_qtd := null;
    new.estoque_em_compra_qtd := null;
    new.estoque_alvo_qtd := null;
    new.estoque_sugestao_qtd := null;
  end if;

  return new;
end;
$function$
;


