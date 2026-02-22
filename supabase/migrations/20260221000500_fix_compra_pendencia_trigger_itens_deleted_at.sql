-- Fix: public.itens does not have deleted_at in this project

create or replace function m.trg_compra_pendencia_biu()
returns trigger
language plpgsql
security definer
set search_path to 'm', 'public'
as $$
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
$$;

