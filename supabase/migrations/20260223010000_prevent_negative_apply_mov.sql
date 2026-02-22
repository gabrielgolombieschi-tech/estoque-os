-- Impede novos saldos negativos no fluxo principal de trigger (apply_movimentacao_estoque).

create or replace function public.apply_movimentacao_estoque()
returns trigger
language plpgsql
as $$
declare
  v_delta numeric;
  v_saldo_anterior numeric;
  v_saldo_final numeric;
  v_custo_medio numeric;
  v_custo_entrada numeric;
  v_novo_custo numeric;
begin
  if new.item_id is null then
    return new;
  end if;

  v_saldo_anterior := 0;
  select coalesce(e.quantidade_atual, 0)
    into v_saldo_anterior
  from public.estoque e
  where e.tenant_id = new.tenant_id
    and e.empresa_id = new.empresa_id
    and e.item_id = new.item_id
  limit 1;

  v_delta :=
    case
      when new.tipo = 'entrada' then coalesce(new.quantidade, 0)
      when new.tipo = 'saida' then -coalesce(new.quantidade, 0)
      when new.tipo = 'ajuste' then coalesce(new.quantidade, 0)
      else null
    end;

  if v_delta is null then
    raise exception 'Tipo de movimentacao invalido: %', new.tipo;
  end if;

  v_saldo_final := coalesce(v_saldo_anterior, 0) + coalesce(v_delta, 0);
  if v_saldo_final < 0 then
    raise exception
      'Estoque nao pode ficar negativo (tenant_id=%, empresa_id=%, item_id=%, saldo_final=%)',
      new.tenant_id, new.empresa_id, new.item_id, v_saldo_final;
  end if;

  insert into public.estoque (tenant_id, empresa_id, item_id, quantidade_atual)
  values (new.tenant_id, new.empresa_id, new.item_id, v_delta)
  on conflict (tenant_id, empresa_id, item_id) do update
    set quantidade_atual = coalesce(public.estoque.quantidade_atual, 0) + v_delta;

  if new.tipo = 'entrada' and coalesce(new.quantidade, 0) > 0 then
    select coalesce(i.custo_medio, 0)
      into v_custo_medio
    from public.itens i
    where i.id = new.item_id
      and i.tenant_id = new.tenant_id
    limit 1;

    v_custo_entrada := coalesce(new.custo_unitario_real, new.custo_unitario_bruto, 0);
    v_novo_custo := case
      when (v_saldo_anterior + new.quantidade) > 0
        then ((v_saldo_anterior * v_custo_medio) + (new.quantidade * v_custo_entrada)) / (v_saldo_anterior + new.quantidade)
      else v_custo_entrada
    end;

    update public.itens
       set custo_ultima_compra = v_custo_entrada,
           custo_medio = v_novo_custo
     where id = new.item_id
       and tenant_id = new.tenant_id;
  end if;

  return new;
end;
$$;
