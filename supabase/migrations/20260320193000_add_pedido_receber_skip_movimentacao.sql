create or replace function m.fn_pedido_compra_receber(
  p_pedido_id uuid,
  p_recebimento_date date,
  p_documento_ref text,
  p_observacoes text,
  p_itens jsonb,
  p_skip_movimentacao boolean
)
returns uuid
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
declare
  v_pedido m.pedido_compra%rowtype;
  v_recebimento_id uuid;
  v_item jsonb;
  v_item_id uuid;
  v_qtd numeric(15,3);
  v_row m.pedido_compra_item%rowtype;
  v_all_received boolean;
  v_email text;
  v_skip boolean := coalesce(p_skip_movimentacao, false);
begin
  select * into v_pedido from m.pedido_compra p where p.id = p_pedido_id and p.deleted_at is null for update;
  if not found then raise exception 'Pedido nao encontrado'; end if;

  if not (
    public.can('compras','receive', v_pedido.tenant_id)
    or (v_skip and public.can('estoque','write', v_pedido.tenant_id))
  ) then
    raise exception 'Sem permissao para recebimento';
  end if;

  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Itens obrigatorios';
  end if;

  insert into m.pedido_compra_recebimento(tenant_id, empresa_id, pedido_compra_id, recebimento_date, documento_ref, observacoes)
  values (v_pedido.tenant_id, v_pedido.empresa_id, v_pedido.id, coalesce(p_recebimento_date,current_date), p_documento_ref, p_observacoes)
  returning id into v_recebimento_id;

  for v_item in select * from jsonb_array_elements(p_itens) loop
    v_item_id := nullif(v_item->>'pedidoItemId','')::uuid;
    v_qtd := coalesce((v_item->>'quantidade')::numeric,0);
    if v_item_id is null or v_qtd <= 0 then raise exception 'Item invalido no recebimento'; end if;

    select * into v_row from m.pedido_compra_item i where i.id = v_item_id and i.pedido_compra_id = v_pedido.id and i.deleted_at is null for update;
    if not found then raise exception 'Pedido item nao encontrado'; end if;
    if v_row.quantidade_recebida + v_qtd > v_row.quantidade then raise exception 'Quantidade excede saldo'; end if;

    insert into m.pedido_compra_recebimento_item(tenant_id, empresa_id, recebimento_id, pedido_compra_item_id, item_id, quantidade)
    values (v_pedido.tenant_id, v_pedido.empresa_id, v_recebimento_id, v_row.id, v_row.item_id, v_qtd);

    update m.pedido_compra_item
       set quantidade_recebida = quantidade_recebida + v_qtd,
           updated_by = a.fn_current_usuario_id()
     where id = v_row.id;

    if not v_skip and v_row.item_id is not null and exists (
      select 1
      from public.itens it
      where it.tenant_id = v_pedido.tenant_id
        and it.empresa_id = v_pedido.empresa_id
        and it.id = v_row.item_id
        and coalesce(it.controla_estoque, false) = true
    ) then
      v_email := coalesce(current_setting('request.jwt.claim.email', true), 'sistema');
      insert into public.movimentacoes(tenant_id, empresa_id, item_id, tipo, quantidade, motivo, realizado_por, data_movimentacao)
      values (
        v_pedido.tenant_id,
        v_pedido.empresa_id,
        v_row.item_id,
        'entrada',
        v_qtd,
        'RECEBIMENTO ' || v_pedido.codigo,
        v_email,
        coalesce(p_recebimento_date, current_date)::timestamp
      );
    end if;
  end loop;

  select bool_and(i.quantidade_recebida >= i.quantidade)
    into v_all_received
    from m.pedido_compra_item i
   where i.pedido_compra_id = v_pedido.id
     and i.deleted_at is null;

  update m.pedido_compra
     set status = case when coalesce(v_all_received, false) then 'RECEBIDO' else 'PARCIAL_RECEBIDO' end,
         updated_by = a.fn_current_usuario_id()
   where id = v_pedido.id;

  perform m.fn_pedido_compra_log_evento(
    v_pedido.id,
    'RECEBIMENTO',
    v_pedido.status,
    case when coalesce(v_all_received, false) then 'RECEBIDO' else 'PARCIAL_RECEBIDO' end,
    coalesce(
      p_observacoes,
      case when v_skip then 'Conciliacao manual de recebimento sem movimentacao de estoque' else 'Recebimento' end
    )
  );

  update m.compra_pendencia cp
     set status = 'CONCLUIDO',
         concluido_em = now(),
         updated_by = a.fn_current_usuario_id()
   where cp.deleted_at is null
     and cp.status = 'EM_PEDIDO'
     and exists (
       select 1
         from m.pedido_compra_item_origem io
         join m.pedido_compra_item pi
           on pi.id = io.pedido_compra_item_id
        where io.deleted_at is null
          and io.pendencia_id = cp.id
          and pi.pedido_compra_id = v_pedido.id
          and pi.deleted_at is null
          and pi.quantidade_recebida >= pi.quantidade
     );

  return v_recebimento_id;
end;
$$;

create or replace function m.fn_pedido_compra_receber(
  p_pedido_id uuid,
  p_recebimento_date date,
  p_documento_ref text,
  p_observacoes text,
  p_itens jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
begin
  return m.fn_pedido_compra_receber(
    p_pedido_id,
    p_recebimento_date,
    p_documento_ref,
    p_observacoes,
    p_itens,
    false
  );
end;
$$;

grant execute on function m.fn_pedido_compra_receber(uuid, date, text, text, jsonb, boolean) to authenticated, service_role;
grant execute on function m.fn_pedido_compra_receber(uuid, date, text, text, jsonb) to authenticated, service_role;
